package iri

window_get_size_pixels :: proc() -> [2]i32 {
    return window_context_get_size_pixels(get_window_context());
}

window_set_swapchain_settings :: proc(target_settings : SwapchainSettings) -> bool{
    window := get_window_context();
    
    success := window_context_set_swapchain_settings(window, target_settings);
    pipe_manager_rebuild_all_pipelines_for_render_pass_types(engine.pipeline_manager, window.gpu_device, {.SWAPCHAIN_COMPOSIT});
    return success;
}

window_set_present_mode :: proc(target_present_mode: SwapchainPresentMode) -> bool {
    return window_context_set_present_mode(get_window_context(), target_present_mode);
}

window_set_color_space :: proc(target_color_space: SwapchainColorSpace) -> bool {

    window := get_window_context();
    success := window_context_set_color_space(window, target_color_space);
    pipe_manager_rebuild_all_pipelines_for_render_pass_types(engine.pipeline_manager, window.gpu_device, {.SWAPCHAIN_COMPOSIT})

    return success;
}


window_set_fullscreen :: proc(fullscreen : bool) -> bool {
    return window_context_set_fullscreen(get_window_context(), fullscreen);
}

window_is_fullscreen :: proc() -> bool {
	return get_window_context().in_fullscreen_mode;
}