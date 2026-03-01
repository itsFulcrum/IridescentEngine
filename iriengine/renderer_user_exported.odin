package iri

import sdl "vendor:sdl3"

get_render_config :: proc() -> RenderConfig {
    return engine.render_context.config;
}

set_render_config :: proc(config : RenderConfig){

    gpu_device := get_gpu_device();
	renderer_set_render_config(engine.render_context, gpu_device, config);
}

get_render_debug_config :: proc() -> ^RenderDebugConfig {
	return &engine.render_context.debug_config;
}

set_render_resolution :: proc(render_resolution: RenderResolution){
    gpu_device := get_gpu_device();
	renderer_set_render_resolution(engine.render_context, gpu_device, render_resolution);
}

set_render_target_format :: proc(format: RenderTargetFormat){
    gpu_device := get_gpu_device();
	renderer_set_render_target_format(engine.render_context, gpu_device, format);
}

set_depth_stencil_target_format :: proc(format: DepthStencilFormat){
    gpu_device := get_gpu_device();
	renderer_set_depth_stencil_target_format(engine.render_context, gpu_device, format);
}

enable_render_effects :: proc(effects : RenderingEffectFlags){

    gpu_device := get_gpu_device();
	renderer_enable_render_effects(engine.render_context, gpu_device, effects);
}

disable_render_effects :: proc(effects : RenderingEffectFlags) {

    gpu_device := get_gpu_device();
	renderer_disable_render_effects(engine.render_context, gpu_device, effects)
}

get_ren_effect_GTAO_settings :: proc() -> RenEffectGTAOSettings{
	return renderer_get_ren_effect_GTAO_settings(engine.render_context);
}

set_ren_effect_GTAO_settings :: proc(settings : RenEffectGTAOSettings){
	gpu_device := get_gpu_device();
	renderer_set_ren_effect_GTAO_settings(engine.render_context,gpu_device, settings);
}

get_ren_effect_SMAA_settings :: proc() -> RenEffectSMAASettings{
	return renderer_get_ren_effect_SMAA_settings(engine.render_context);
}

set_ren_effect_SMAA_settings :: proc(settings : RenEffectSMAASettings){
	gpu_device := get_gpu_device();
	renderer_set_ren_effect_SMAA_settings(engine.render_context, gpu_device, settings);
}