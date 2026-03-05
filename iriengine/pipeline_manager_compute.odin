package iri

import "core:strings"
import "core:log"
import sdl "vendor:sdl3"


ComputePipelineShader :: enum {
    BRDF_LUT_GEN,
    MIN_MAX_DEPTH_HIERARCHY,
    GTAO,
    UPSCALE_AO,
    EQUIRECTANGULAR_TO_CUBEMAP,
    SHADOWMAP_BLUR_TWO_PASS,
}

ComputePipeManager :: struct {

    shader_ids : [ComputePipelineShader]ShaderID,
	compute_pipelines: [ComputePipelineShader]^sdl.GPUComputePipeline,
}

@(private="package")
get_compute_pipeline :: proc(compute_pipeline_shader : ComputePipelineShader) -> (compute_pipeline: ^sdl.GPUComputePipeline, threadcount : [3]u32) {
	return compute_pipe_manager_get_pipeline(engine.compute_pipe_manager, engine.shader_manager, compute_pipeline_shader);
}

@(private="package")
compute_pipe_manager_init :: proc(manager : ^ComputePipeManager, gpu_device : ^sdl.GPUDevice, shader_manager : ^ShaderManager){

    shaders_path :string = strings.join({get_resources_path(), "shaders"}, "/", context.temp_allocator);

    // @Note: im doing a for loop and switch here just because i want to get compiler messages when 
    // i add new compute shader enum so i remember to add it here.
    for compute_shader in ComputePipelineShader {

        id : ShaderID = -1;

        switch compute_shader {
            case .BRDF_LUT_GEN:                 id = shader_manager_register_shader_source(shader_manager, strings.join({shaders_path, "brdf_lut_gen.comp"              }, "/", context.temp_allocator) , .COMPUTE, enable_hot_reloading = false);
            case .MIN_MAX_DEPTH_HIERARCHY:      id = shader_manager_register_shader_source(shader_manager, strings.join({shaders_path, "min_max_depth.comp"             }, "/", context.temp_allocator) , .COMPUTE, enable_hot_reloading = true);
            //case .GTAO:                         id = shader_manager_register_shader_source(shader_manager, strings.join({shaders_path, "gtao.comp"                      }, "/", context.temp_allocator) , .COMPUTE, enable_hot_reloading = true);
            case .GTAO:                         id = shader_manager_register_shader_source(shader_manager, strings.join({shaders_path, "gtao2.comp"                      }, "/", context.temp_allocator) , .COMPUTE, enable_hot_reloading = true);
            case .UPSCALE_AO:                   id = shader_manager_register_shader_source(shader_manager, strings.join({shaders_path, "upscale_ao.comp"                }, "/", context.temp_allocator) , .COMPUTE, enable_hot_reloading = true);
            case .EQUIRECTANGULAR_TO_CUBEMAP:   id = shader_manager_register_shader_source(shader_manager, strings.join({shaders_path, "equirectangular_to_cubemap.comp"}, "/", context.temp_allocator) , .COMPUTE, enable_hot_reloading = false);
            case .SHADOWMAP_BLUR_TWO_PASS:      id = shader_manager_register_shader_source(shader_manager, strings.join({shaders_path, "shadowmap_blur.comp"            }, "/", context.temp_allocator) , .COMPUTE, enable_hot_reloading = false);
            case:
        }

        engine_assert(id >= 0);

        manager.shader_ids[compute_shader] = id;
    }

    for compute_pipe in ComputePipelineShader {
        compute_pipe_manager_rebuild_pipeline(manager, shader_manager, gpu_device, compute_pipe);
    }
}

@(private="package")
compute_pipe_manager_deinit :: proc(manager : ^ComputePipeManager, gpu_device : ^sdl.GPUDevice){

	for comp_pipe in ComputePipelineShader {

        if manager.compute_pipelines[comp_pipe] != nil {
            sdl.ReleaseGPUComputePipeline(gpu_device, manager.compute_pipelines[comp_pipe]);
        }
    }
}

@(private="package")
compute_pipe_manager_on_shader_source_changed :: proc(manager : ^ComputePipeManager, shader_manager : ^ShaderManager,gpu_device : ^sdl.GPUDevice, shader_id : ShaderID){
    
    // find the pipeline that matches the shader_id
    for comp_pipe in ComputePipelineShader {

        id := manager.shader_ids[comp_pipe]

        if id == shader_id {

            compute_pipe_manager_rebuild_pipeline(manager, shader_manager, gpu_device, comp_pipe);
            break;
        }
    }
}

@(private="file")
compute_pipe_manager_get_pipeline :: proc(manager : ^ComputePipeManager, shader_manager : ^ShaderManager, compute_pipeline_shader : ComputePipelineShader) -> (compute_pipeline: ^sdl.GPUComputePipeline, threadcount : [3]u32) {
    
    shader_id := manager.shader_ids[compute_pipeline_shader];
    engine_assert(shader_id > -1)

    compile_info := shader_manager_get_compile_info_ptr(shader_manager, shader_id);
    engine_assert(compile_info != nil)

    return manager.compute_pipelines[compute_pipeline_shader], compile_info.compute_threadcount;
}

@(private="file")
compute_pipe_manager_rebuild_pipeline :: proc(manager : ^ComputePipeManager, shader_manager : ^ShaderManager, gpu_device: ^sdl.GPUDevice, compute_pipeline : ComputePipelineShader){

    shader_id := manager.shader_ids[compute_pipeline];
    spirv_or_err_str, compile_info, load_ok := shader_manager_load_or_compile_spirv_variant(shader_manager, shader_id, ShaderVariant{})

    defer if load_ok {
        // spriv_code is an error strings are allocated in temp_allocator. so we dont free them
        delete(spirv_or_err_str);
    }

    if !load_ok {
        log.errorf("Failed to Build Compute Pipline: {}", compute_pipeline);
        log.errorf("{}", transmute(string)(spirv_or_err_str)); 
        return;    
    }

    comp_pipeline := compute_pipe_manager_create_pipeline(gpu_device, spirv_or_err_str, compile_info);
    if comp_pipeline == nil {
        log.errorf("Failed to Build Compute Pipline: {}, msg {}", compute_pipeline, sdl.GetError());
    }

    engine_assert(comp_pipeline != nil);

    if manager.compute_pipelines[compute_pipeline] != nil {
        sdl.ReleaseGPUComputePipeline(gpu_device, manager.compute_pipelines[compute_pipeline]);
    }

    log.debugf("Build Compute Pipline: {}", compute_pipeline);

    manager.compute_pipelines[compute_pipeline] = comp_pipeline;
}


@(private="file")
compute_pipe_manager_create_pipeline :: proc(gpu_device: ^sdl.GPUDevice, spirv_code: []byte, compile_info: ShaderCompileInfo2) -> ^sdl.GPUComputePipeline {
    
    create_info :=  sdl.GPUComputePipelineCreateInfo{

        code_size   = len(spirv_code),
        code        = raw_data(spirv_code),
        entrypoint  = "main",          
        format      = {sdl.GPUShaderFormat.SPIRV},
        
        num_samplers                    = cast(u32)compile_info.num_samplers,
        num_readonly_storage_textures   = cast(u32)compile_info.num_readonly_storage_textures,
        num_readonly_storage_buffers    = cast(u32)compile_info.num_readonly_storage_buffers,
        num_readwrite_storage_textures  = cast(u32)compile_info.num_writeable_storage_textures,
        num_readwrite_storage_buffers   = cast(u32)compile_info.num_writeable_storage_buffers,
        num_uniform_buffers             = cast(u32)compile_info.num_uniform_buffers,
        threadcount_x                   = cast(u32)compile_info.compute_threadcount.x,
        threadcount_y                   = cast(u32)compile_info.compute_threadcount.y,
        threadcount_z                   = cast(u32)compile_info.compute_threadcount.z,

    };

    return sdl.CreateGPUComputePipeline(gpu_device, create_info);
}