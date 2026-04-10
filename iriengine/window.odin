package iri

import "core:c"
import "core:log"
import "core:strings"
import sdl "vendor:sdl3"


@(private="package")
window_create_context :: proc(window_title : string, window_size: [2]u32, start_fullscreen: bool = false, enable_validation_layers: bool = false) -> (window_context: WindowContext, ok: bool) {

    ctx : WindowContext;
    ctx.handle = nil;
    ctx.gpu_device = nil;
    ctx.swapchain_settings.color_space  = SwapchainColorSpace.Srgb;
    ctx.swapchain_settings.present_mode = SwapchainPresentMode.VSync;
    ctx.in_fullscreen_mode = start_fullscreen;

	//window_flags := sdl.WindowFlags{.VULKAN,.HIGH_PIXEL_DENSITY};
    //window_flags := sdl.WindowFlags{.VULKAN, .RESIZABLE};
    window_flags := sdl.WindowFlags{.OPENGL, .RESIZABLE};
    if start_fullscreen {
        window_flags |= {.FULLSCREEN};
    }

    title_cstring := strings.clone_to_cstring(window_title, context.temp_allocator);
    window_size_i32 : [2]i32;
    // use defaults if window size is nonsense
    window_size_i32.x = window_size.x > 0 ? cast(i32)window_size.x : 900;
    window_size_i32.y = window_size.y > 0 ? cast(i32)window_size.y : 720;

	handle := sdl.CreateWindow(title_cstring, window_size_i32.x, window_size_i32.y, window_flags);
    
    if handle == nil {
        log.errorf("Failed to Create Window: {}", sdl.GetError());
        return ctx, false;
    }

    gpu_device := sdl.CreateGPUDevice({.SPIRV}, enable_validation_layers, nil);

    if gpu_device == nil {
        log.errorf("Failed to Create a GPU Device: {}", sdl.GetError());
        return ctx, false;
    }

    claim_device_ok := sdl.ClaimWindowForGPUDevice(gpu_device, handle);
    if !claim_device_ok {
        log.errorf("Failed to Create to Claim Window For GPU Device: {}", sdl.GetError());
        return ctx, false;
    }

    frames_in_flight_ok := sdl.SetGPUAllowedFramesInFlight(gpu_device,2);
    engine_assert(frames_in_flight_ok);

    ctx.handle = handle;
    ctx.gpu_device = gpu_device;
    ctx.in_fullscreen_mode = start_fullscreen;

    // Submit a clear on the swapchain.
    for i in 0..<1{
        wait_ok := sdl.WaitForGPUIdle(ctx.gpu_device);
        engine_assert(wait_ok);
        
        cmd_buf := sdl.AcquireGPUCommandBuffer(ctx.gpu_device);

        swapchain_texture : ^sdl.GPUTexture;
        swapchain_tex_size : [2]u32;
        swapchain_ok := sdl.WaitAndAcquireGPUSwapchainTexture(cmd_buf, ctx.handle, &swapchain_texture, &swapchain_tex_size.x, &swapchain_tex_size.y);
        
        // just wait and dont do any rendering, its likely that the window was just minimized
        if !swapchain_ok || swapchain_texture == nil {
            log.errorf("failed to aquire swapchain texture: {}", sdl.GetError());
            engine_assert(false);
            submited_ok := sdl.SubmitGPUCommandBuffer(cmd_buf);
            
            continue;
        }

        swapchain_target := sdl.GPUColorTargetInfo {
                texture = swapchain_texture,
                clear_color = sdl.FColor{0.2,0,0.2,1},
                load_op  = sdl.GPULoadOp.CLEAR,
                store_op = sdl.GPUStoreOp.STORE,
                cycle = true,
        }

        swapchain_blit_pass := sdl.BeginGPURenderPass(cmd_buf, &swapchain_target,1, nil);
        sdl.EndGPURenderPass(swapchain_blit_pass);

        submit_ok := sdl.SubmitGPUCommandBuffer(cmd_buf);
        engine_assert(submit_ok);
    
        wait_ok = sdl.WaitForGPUIdle(ctx.gpu_device);
        engine_assert(wait_ok);
    }

    return ctx, true;
}

@(private="package")
window_destroy_context :: proc(window: ^WindowContext) {

    if window.gpu_device != nil {
        sdl.ReleaseWindowFromGPUDevice(window.gpu_device, window.handle);
        window.gpu_device = nil;
    }

	if window.handle != nil {
		sdl.DestroyWindow(window.handle);
        window.handle = nil;
	}
}

@(private="package")
window_context_get_size_pixels :: proc(window: ^WindowContext) -> [2]i32 {
    
    window_size : [2]c.int;
    sdl.GetWindowSizeInPixels(window.handle, &window_size.x, &window_size.y);
    return [2]i32{window_size.x, window_size.y};
}

@(private="package")
window_context_set_swapchain_settings :: proc(window: ^WindowContext, target_settings : SwapchainSettings) -> bool{

    success: bool = true;

    target_composition: sdl.GPUSwapchainComposition = get_sdl_GPUSwapchainComposition_from_SwapchainColorSpace(target_settings.color_space);

    if(target_settings.color_space == SwapchainColorSpace.Hdr10_st2084 || target_settings.color_space == SwapchainColorSpace.Hdr_Linear_Extended){

        log.warnf("Swapchain Color Space '{}' is currently not supported by the engine", target_settings.color_space);
        target_composition = get_sdl_GPUSwapchainComposition_from_SwapchainColorSpace(window.swapchain_settings.color_space);
        success = false;
    }
    else if(!sdl.WindowSupportsGPUSwapchainComposition(window.gpu_device, window.handle, target_composition)){

        log.warnf("Swapchain Color Space '{}' is not supported by this device", target_settings.color_space);

        target_composition = get_sdl_GPUSwapchainComposition_from_SwapchainColorSpace(window.swapchain_settings.color_space);
        success = false;
    }


    target_present_mode : sdl.GPUPresentMode = get_sdl_GPUPresentMode_from_SwapchainPresentMode(target_settings.present_mode);

    // SDL doc states that VSYNC will always be supported
    // https://wiki.libsdl.org/SDL3/SDL_GPUPresentMode
    if(!sdl.WindowSupportsGPUPresentMode(window.gpu_device, window.handle, target_present_mode)){
        log.warnf("Swapchain present mode '{}' is not supported by this device", target_settings.present_mode);
        
        target_present_mode = get_sdl_GPUPresentMode_from_SwapchainPresentMode(window.swapchain_settings.present_mode);
        success = false;
    }

    window.swapchain_settings.color_space = get_SwapchainColorSpace_from_sdl_GPUSwapchainComposition(target_composition);
    window.swapchain_settings.present_mode = get_SwapchainPresentMode_from_sdl_GPUPresentMode(target_present_mode);

    ok: bool = sdl.SetGPUSwapchainParameters(window.gpu_device,window.handle, target_composition, target_present_mode);
    engine_assert(ok); // This Should be ok since we just check if the settings are supported

    return success;
}

@(private="package")
window_context_set_present_mode:: proc(window: ^WindowContext, target_mode: SwapchainPresentMode) -> bool {

    target_settings := SwapchainSettings {
        color_space = window.swapchain_settings.color_space,
        present_mode = target_mode,
    }

    return window_context_set_swapchain_settings(window, target_settings);
}

@(private="package")
window_context_set_color_space :: proc(window: ^WindowContext, target_color_space: SwapchainColorSpace) -> bool {

    target_settings := SwapchainSettings {
        color_space = target_color_space,
        present_mode = window.swapchain_settings.present_mode,
    }
    return window_context_set_swapchain_settings(window, target_settings);
}

@(private="package")
window_context_set_fullscreen :: proc(window: ^WindowContext, fullscreen : bool) -> bool {

    success := sdl.SetWindowFullscreen(window.handle, fullscreen);

    if(success){
        window.in_fullscreen_mode = fullscreen;
        return true;
    }

    return false;
}