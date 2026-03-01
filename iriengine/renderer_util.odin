package iri

import sdl "vendor:sdl3"
import "core:c"

import "core:log"
import "core:mem"
import "core:math"
import "core:math/rand"
import "core:math/linalg"
import "odinary:mathy"


@(private="package")
renderer_create_depth_stencil_texture :: proc(gpu_device : ^sdl.GPUDevice, frame_size : [2]u32, format : DepthStencilFormat = DepthStencilFormat.D24_UNORM_S8_UINT, msaa: MSAA = MSAA.OFF, usage_flags : sdl.GPUTextureUsageFlags = {.DEPTH_STENCIL_TARGET}) -> ^sdl.GPUTexture{


    create_info : sdl.GPUTextureCreateInfo = {
        type = sdl.GPUTextureType.D2, 
        format = get_sdl_GPUTextureFormat_from_DepthStencilFormat(format),
        usage = usage_flags,
        width  = frame_size.x,
        height = frame_size.y,
        layer_count_or_depth = 1,
        num_levels = 1,
        sample_count = get_sdl_GPUSampleCount_from_MSAA(msaa),
    }

    return sdl.CreateGPUTexture(gpu_device, create_info);
}

@(private="package")
renderer_create_render_target_texture :: proc(gpu_device : ^sdl.GPUDevice, frame_size : [2]u32, format : RenderTargetFormat = RenderTargetFormat.RGBA16_FLOAT, msaa: MSAA = MSAA.OFF, usage_flags : sdl.GPUTextureUsageFlags = {.COLOR_TARGET}) -> ^sdl.GPUTexture{

	// TODO: we may have to quary support for certain format idk

    create_info : sdl.GPUTextureCreateInfo = {
        type = sdl.GPUTextureType.D2, 
        format = get_sdl_GPUTextureFormat_from_RenderTargetFormat(format),
        usage = usage_flags, // sdl.GPUTextureUsageFlag.COMPUTE_STORAGE_SIMULTANEOUS_READ_WRITE
        width  = frame_size.x,
        height = frame_size.y,
        layer_count_or_depth = 1,
        num_levels = 1,
        sample_count = get_sdl_GPUSampleCount_from_MSAA(msaa),
    }

    return sdl.CreateGPUTexture(gpu_device, create_info)
}



@(private="package")
renderer_calculate_frame_size_from_swapchain_size :: proc(swapchain_size : [2]u32, resolution : RenderResolution) -> [2]u32 {

    switch (resolution){
        case RenderResolution.Native:       return swapchain_size;
        case RenderResolution.Half:         return swapchain_size / 2;
        case RenderResolution.Quarter:      return swapchain_size / 4;
        case RenderResolution.Double:       return swapchain_size * 2;
        case RenderResolution.Quadruple:    return swapchain_size * 4;
    }

    panic("Invalid Codepath")
}

@(private="package")
// invocations is total amount of invocations we want. thread_count is local (per work group, invocations);
calc_work_groups_from_thread_counts_and_invocations :: proc(thread_counts : [3]u32, invocations : [3]u32) -> [3]u32 {

    work_groups : [3]u32 = invocations / thread_counts;

    modulo : [3]u32 = invocations % thread_counts;

    work_groups.x = modulo.x > 0 ? work_groups.x+1 : work_groups.x;
    work_groups.y = modulo.y > 0 ? work_groups.y+1 : work_groups.y;
    work_groups.z = modulo.z > 0 ? work_groups.z+1 : work_groups.z;

    return work_groups;
}





make_ssao_sample_kernel :: proc(num_samples : u32) -> [][4]f32 {

    actual : u32 = num_samples * 2;

    kernel : [][4]f32 = make_slice([][4]f32, num_samples, context.allocator);

    // This produces evenly distributed directions in the unit hemisphere
    // using fibonacci spiral. The hemisphere is oriented in tangent space
    // so the normal from the hemisphere is in the positive z direction.

    DO_FULL_SPHERE :: false;
    // if we do 2*dist we would get samples in the whole sphere.
    distance_range : f64 = DO_FULL_SPHERE ? 2.0 : 1.0;

    golden_ratio :: 1.618033988749894; // (1 + math.sqrt_f64(5.0)) / 2;
    golden_angle :: (1.0 - 1.0 / golden_ratio) * math.PI * 2.0;

    for i in 0..<num_samples {

        dist : f64 = cast(f64)i / cast(f64)num_samples;
        incline := math.acos_f64(1-distance_range*dist);

        azimuth := golden_angle * cast(f64)i;
        
        dir : [3]f32 = mathy.spherical_to_cartesian(cast(f32)incline, cast(f32)azimuth);

        dir = linalg.normalize(dir);

        kernel[i] = [4]f32{dir.x,dir.y,dir.z, 1.0};
    }

    // randomize all lenghts a bit
    for i in 0..<num_samples {
        random_f : f32 = rand.float32_range(0.7, 1.0);
        kernel[i] *= random_f;
    }

    // scale directions randomly but such that more are closer to origin.

    iterations : u32 = num_samples;
    for i in 0..<iterations{
        
        // pic a random sample to modify
        random : u32 = rand.uint32()
        index : u32 = random % num_samples;

        // scale by an exponential function so more samples are scaled with a lower value
        scale : f32 = f32(i) / f32(iterations) ; 
        scale   = math.lerp(f32(0.1), f32(1.0), scale * scale);
        
        kernel[index] *= scale;
    }

    // populate last index with a random value
    // not sure if we'll need this yet.
    for i in 0..<num_samples {
        random_f : f32 = rand.float32_range(0.01, 1.0);
        kernel[i].w *= random_f;
    }

    return kernel;

}


renderer_upload_ssao_sample_kernel_to_gpu_buffer :: proc(gpu_device : ^sdl.GPUDevice, kernel : [][4]f32) -> ^sdl.GPUBuffer {


    kernel_size : u32 = cast(u32)len(kernel);

    if(kernel_size == 0){
        return nil;
    }

    kernel_byte_size : u32 = kernel_size * cast(u32)size_of([4]f32);

    // @Note - the buffer has a header of 4 u32 so the gpu buffer is slightly bigger 

    buffer_header_byte_size : u32 = size_of([4]u32);

    gpu_buffer_size : u32 = buffer_header_byte_size + kernel_byte_size;


    buffer_header : [4]u32;
    buffer_header[0] = kernel_size;
    // the rest is padding atm


    gpu_buf_ci : sdl.GPUBufferCreateInfo = {
        usage = {sdl.GPUBufferUsageFlag.COMPUTE_STORAGE_READ},
        size  =  gpu_buffer_size,
    };
    gpu_buffer : ^sdl.GPUBuffer = sdl.CreateGPUBuffer(gpu_device, gpu_buf_ci);


    if(gpu_buffer == nil){
        log.errorf("Faild to create gpu buffer.");
        return nil;
    }

    transfer_buf_ci : sdl.GPUTransferBufferCreateInfo = {
        usage = sdl.GPUTransferBufferUsage.UPLOAD,
        size  = gpu_buf_ci.size,
    }
    transfer_buf := sdl.CreateGPUTransferBuffer(gpu_device, transfer_buf_ci);
    if(transfer_buf == nil){
        log.errorf("Faild to create transfer buffer.");
        
        if(gpu_buffer != nil){
            sdl.ReleaseGPUBuffer(gpu_device, gpu_buffer);
        }

        return nil;
    }
    defer sdl.ReleaseGPUTransferBuffer(gpu_device, transfer_buf);

    transfer_buf_data_ptr : rawptr = sdl.MapGPUTransferBuffer(gpu_device, transfer_buf, false);
        
    byte_ptr: [^]byte = cast([^]byte)transfer_buf_data_ptr;

    // copy the header.
    mem.copy_non_overlapping(&byte_ptr[0], &buffer_header, size_of(buffer_header));
    // copy the kernel directly after the header.
    mem.copy_non_overlapping(&byte_ptr[size_of(buffer_header)], &kernel[0], cast(int)kernel_byte_size);

    sdl.UnmapGPUTransferBuffer(gpu_device, transfer_buf);


    transfer_buf_location := sdl.GPUTransferBufferLocation{
        transfer_buffer = transfer_buf,
        offset = 0,
    }

    transfer_buf_region := sdl.GPUBufferRegion{
        buffer = gpu_buffer,
        offset = 0,
        size = gpu_buffer_size,
    }


    cmd_buf := sdl.AcquireGPUCommandBuffer(gpu_device);
    engine_assert(cmd_buf != nil);

    copy_pass :  ^sdl.GPUCopyPass = sdl.BeginGPUCopyPass(cmd_buf);

    sdl.UploadToGPUBuffer(copy_pass, transfer_buf_location, transfer_buf_region, false);


    sdl.EndGPUCopyPass(copy_pass);

    submit_ok := sdl.SubmitGPUCommandBuffer(cmd_buf);
    engine_assert(submit_ok);


    return gpu_buffer;
}




@(private="package")
renderer_setup_render_brdf_lut :: proc(cmd_buf : ^sdl.GPUCommandBuffer, lut_tex : ^Texture2D){

     // ubo layout in shader
    BRDF_LUT_GEN_UBO :: struct {
            _texture_size  : [2]u32,
            _padding1       : u32,
            _padding2       : u32,
    }

    ubo : BRDF_LUT_GEN_UBO = {
        _texture_size = lut_tex.size,
    };


    rw_binding : sdl.GPUStorageTextureReadWriteBinding = {
        texture = lut_tex.binding.texture, 
        mip_level = 0,
        layer = 0,
        cycle = false,
    }

    brdf_lut_get_pipeline , thread_count := get_compute_pipeline(.BRDF_LUT_GEN);


    compute_pass := sdl.BeginGPUComputePass(cmd_buf, &rw_binding, 1, nil, 0);

    sdl.BindGPUComputePipeline(compute_pass, brdf_lut_get_pipeline);
            
    sdl.PushGPUComputeUniformData(cmd_buf,0, &ubo, size_of(ubo));

    work_groups : [3]u32 = calc_work_groups_from_thread_counts_and_invocations(thread_count, [3]u32{ubo._texture_size.x, ubo._texture_size.y, 1});

    sdl.DispatchGPUCompute(compute_pass, work_groups.x, work_groups.y , 1);

    sdl.EndGPUComputePass(compute_pass);
}


// Kinda hacky solution. works only if texture has COLOR_TARGET bit set
// as we just exploit the clear op for color targets in render passes.
@(private="package")
renderer_clear_texture :: proc(cmd_buf : ^sdl.GPUCommandBuffer, texture : ^sdl.GPUTexture, clear_color : [4]f32 , generate_mips : bool = true) {

    color_target := sdl.GPUColorTargetInfo {
        texture  = texture,
        load_op  = .CLEAR,
        store_op = .STORE,
        clear_color = sdl.FColor{clear_color.r, clear_color.g,clear_color.b,clear_color.a},
        cycle = false,
    }

    clear_pass := sdl.BeginGPURenderPass(cmd_buf, &color_target, 1, nil);
    sdl.EndGPURenderPass(clear_pass);
    
    if(generate_mips){
        sdl.GenerateMipmapsForGPUTexture(cmd_buf, texture);
    }

}