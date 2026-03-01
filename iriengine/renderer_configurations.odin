package iri

import "core:log"

import sdl "vendor:sdl3"

renderer_render_config_create_default :: proc() -> RenderConfig{

    return RenderConfig{
        ren_effect_flags = RENDERING_EFFECT_FLAGS_DEFAULT,
        geo_depth_stencil_format = DepthStencilFormat.D24_UNORM_S8_UINT,
        geo_color_target_format  = RenderTargetFormat.RGBA16_FLOAT,
        //post_correct_color_target_format = RenderTargetFormat.RGBA8_SRGB,
        render_resolution = RenderResolution.Native,
    }
}

@(private="package")
renderer_set_render_config :: proc(ren_ctx : ^RenderContext, gpu_device : ^sdl.GPUDevice, config: RenderConfig) {

    pipe_manager := engine.pipeline_manager;

    wait_ok := sdl.WaitForGPUIdle(gpu_device);
    if !wait_ok {
        log.errorf("Wait For GPU Idle failed: {}", sdl.GetError());
    }

    ren_ctx.config = config;

    ren_ctx.render_pass_infos[.Main].depth_target_format  = config.geo_depth_stencil_format;
    ren_ctx.render_pass_infos[.Main].color_target_format  = config.geo_color_target_format;
    //ren_ctx.render_pass_infos[.Main].msaa                 = config.geo_msaa;

    //ren_ctx.render_pass_infos[.PostColorCorrect].color_target_format = config.post_correct_color_target_format;
    ren_ctx.render_pass_infos[.DEPTH_PREPASS].depth_target_format = config.geo_depth_stencil_format;
    // @Note: - fulcrum
    // if we are not yet running we will anyway 
    // rebuild the pipelines and create render targets just before we enter the main loop
    if engine.in_init_phase {
        return;
    }

    // rebuild pipelines        
    renderer_recreate_all_render_targets(ren_ctx, gpu_device);
    pipe_manager_rebuild_all_pipelines_for_render_pass_types(pipe_manager, gpu_device, {.Main, .PostColorCorrect, .DEPTH_PREPASS});
}

@(private="package")
renderer_set_render_resolution :: proc(ren_ctx : ^RenderContext, gpu_device : ^sdl.GPUDevice, render_resolution: RenderResolution){

    if render_resolution == ren_ctx.config.render_resolution {
        return;
    }

    ren_ctx.config.render_resolution = render_resolution;
    ren_ctx.current_frame_size = renderer_calculate_frame_size_from_swapchain_size(ren_ctx.current_swapchain_size, ren_ctx.config.render_resolution);
    
    if engine.in_init_phase {
        return;
    }

    renderer_recreate_all_render_targets(ren_ctx, gpu_device);
}

@(private="package")
renderer_set_render_target_format :: proc(ren_ctx : ^RenderContext,gpu_device : ^sdl.GPUDevice, format: RenderTargetFormat){

    if format == ren_ctx.config.geo_color_target_format {
        return;
    }

    ren_ctx.config.geo_color_target_format = format;
    ren_ctx.render_pass_infos[.Main].color_target_format = format;

    if engine.in_init_phase {
        return;
    }

    if ren_ctx.geo_color_target_tex != nil {
        sdl.ReleaseGPUTexture(gpu_device, ren_ctx.geo_color_target_tex);
        ren_ctx.geo_color_target_tex = nil; 
    }

    ren_ctx.geo_color_target_tex = renderer_create_render_target_texture(gpu_device, ren_ctx.current_frame_size, ren_ctx.config.geo_color_target_format, MSAA.OFF, {.COLOR_TARGET, .SAMPLER});

    pipe_manager := engine.pipeline_manager;
    pipe_manager_rebuild_all_pipelines_for_render_pass_types(pipe_manager, gpu_device, {.Main});
}

@(private="package")
renderer_set_depth_stencil_target_format :: proc(ren_ctx : ^RenderContext, gpu_device : ^sdl.GPUDevice, format: DepthStencilFormat){
    
    if format == ren_ctx.config.geo_depth_stencil_format {
        return;
    }

    ren_ctx.config.geo_depth_stencil_format = format;
    ren_ctx.render_pass_infos[.Main].depth_target_format = format;
    ren_ctx.render_pass_infos[.DEPTH_PREPASS].depth_target_format = format;

    if engine.in_init_phase {
        return;
    }

    if ren_ctx.geo_depth_stencil_target_tex != nil {
        sdl.ReleaseGPUTexture(gpu_device, ren_ctx.geo_depth_stencil_target_tex);
    }
    ren_ctx.geo_depth_stencil_target_tex = renderer_create_depth_stencil_texture(gpu_device, ren_ctx.current_frame_size, ren_ctx.config.geo_depth_stencil_format, MSAA.OFF, {.DEPTH_STENCIL_TARGET, .SAMPLER});

    pipe_manager := engine.pipeline_manager;
    pipe_manager_rebuild_all_pipelines_for_render_pass_types(pipe_manager, gpu_device, {.Main, .DEPTH_PREPASS});
}

@(private="package")
renderer_enable_render_effects :: proc(ren_ctx : ^RenderContext, gpu_device : ^sdl.GPUDevice, effects : RenderingEffectFlags){

    ren_ctx.config.ren_effect_flags += effects; // this has to happen before not after because some effects may fail to initialize in which case they will be removed from these flags.
    render_effects_reinit(gpu_device, &ren_ctx.effects, effects, ren_ctx.current_frame_size);
}

@(private="package")
renderer_disable_render_effects :: proc(ren_ctx : ^RenderContext, gpu_device : ^sdl.GPUDevice, effects : RenderingEffectFlags) {

    render_effects_deinit_and_destroy(ren_ctx, gpu_device, effects)
}

@(private="package")
renderer_get_ren_effect_GTAO_settings :: proc(ren_ctx : ^RenderContext) -> RenEffectGTAOSettings {

    if .GTAO in ren_ctx.config.ren_effect_flags{
        engine_assert(ren_ctx.effects.gtao != nil);

        return ren_ctx.effects.gtao.settings;
    }

    log.warnf("Renderer: Render Effect GTAO is not enabled, return empty SettingsStruct.")

    return RenEffectGTAOSettings{};
}

@(private="package")
renderer_set_ren_effect_GTAO_settings :: proc(ren_ctx : ^RenderContext, gpu_device : ^sdl.GPUDevice, settings : RenEffectGTAOSettings) {

    if .GTAO in ren_ctx.config.ren_effect_flags{
        engine_assert(ren_ctx.effects.gtao != nil);

        ren_ctx.effects.gtao.settings = settings;
        render_effects_reinit(gpu_device, &ren_ctx.effects, {.GTAO} ,ren_ctx.current_frame_size)
        return;
    }

    log.warnf("Renderer: Render Effect GTAO is not enabled, Cannot Enable before applying settings")
}


@(private="package")
renderer_get_ren_effect_SMAA_settings :: proc(ren_ctx : ^RenderContext) -> RenEffectSMAASettings {

    if .SMAA in ren_ctx.config.ren_effect_flags{
        engine_assert(ren_ctx.effects.smaa != nil);

        return ren_ctx.effects.smaa.settings;
    }

    log.warnf("Renderer: Render Effect SMAA is not enabled, return empty SettingsStruct.")

    return RenEffectSMAASettings{};
}

@(private="package")
renderer_set_ren_effect_SMAA_settings :: proc(ren_ctx : ^RenderContext, gpu_device : ^sdl.GPUDevice, settings : RenEffectSMAASettings) {

    if .SMAA in ren_ctx.config.ren_effect_flags{
        engine_assert(ren_ctx.effects.smaa != nil);

        ren_ctx.effects.smaa.settings = settings;
        render_effects_reinit(gpu_device, &ren_ctx.effects, {.SMAA} ,ren_ctx.current_frame_size);
        return;
    }

    log.warnf("Renderer: Render Effect SMAA is not enabled, Cannot Enable before applying settings")
}