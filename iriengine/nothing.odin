package iri


// import sdl "vendor:sdl3"


// example :: proc(){

// 	// During Init phase

// 	composit_tex : ^sdl.GPUTexture;
// 	create_info : sdl.GPUTextureCreateInfo = {
//         type = sdl.GPUTextureType.D2, 
//         format = sdl.GPUTextureFormat.R8G8B8A8_UNORM,
//         usage = {.SAMPLER, .COMPUTE_STORAGE_WRITE}
//         width  = texture_size.x,
//         height = texture_size.y,
//         layer_count_or_depth = 1,
//         num_levels = 1,
//         sample_count = sdl.GPUSampleCount._0,
//     }

//     composit_tex : ^sdl.GPUTexture = sdl.CreateGPUTexture(gpu_device, create_info);




//     // During Draw


//     num_storage_tex_readwrite_bindings : u32 = 1;
//     readwrite_tex_bindings := sdl.GPUStorageTextureReadWriteBinding{
//         texture = composit_tex, 
//         mip_level = 0,   
//         layer = 0,      
//         cycle = false,
//     }


// 	compute_pass := sdl.BeginGPUComputePass(cmd_buf, &readwrite_tex_bindings, num_storage_tex_readwrite_bindings, nil, 0);
    
//     assert(compute_pass != nil);
//     // get the pipeline previously created pipeline from my pipeline manager
//     comp_pipeline, thread_count := pipe_manager_get_compute_pipeline(.COMPOSIT);
//     assert(comp_pipeline != nil);

//     sdl.BindGPUComputePipeline(compute_pass, comp_pipeline);



//     sdl.BindGPUComputeStorageTextures(compute_pass, 0, &composit_tex ,num_bindings = 1);


//     sdl.DispatchGPUCompute(compute_pass, work_groups.x, work_groups.y, work_groups.z);

//     sdl.EndGPUComputePass(compute_pass);


//     // After Compute is done, i blit the composit texture to the swapchain..


//         blit_info : sdl.GPUBlitInfo = {
//         source = sdl.GPUBlitRegion {
//             texture = composit_tex,
//             mip_level = 0,
//             layer_or_depth_plane = 0,   
//             x = 0,               
//             y = 0,                    
//             w = swapchain_tex_size.x,     
//             h = swapchain_tex_size.y,           
//         },
//         destination = sdl.GPUBlitRegion {
//             texture = swapchain_texture,
//             mip_level = 0,
//             layer_or_depth_plane = 0,     
//             x = 0,                          
//             y = 0,                         
//             w = swapchain_tex_size.x,      
//             h = swapchain_tex_size.y,     
//         },
//         load_op = sdl.GPULoadOp.DONT_CARE, 
//         filter = sdl.GPUFilter.NEAREST,
//         cycle = true,                   
//     };

//     sdl.BlitGPUTexture(cmd_buf, blit_info);

//     submit_ok := sdl.SubmitGPUCommandBuffer(cmd_buf);
//     engine_assert(submit_ok);

// }