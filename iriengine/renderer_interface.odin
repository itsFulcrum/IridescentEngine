package iri

import sdl "vendor:sdl3"

/*
	The Renderer Interface generally works on a get/set bases where you can get the 
	current configuration state using a get call which will return a copy of the
	configuration which you can modify and then apply using a set call.
	The interface works this way because we often have to do a bunch 
	of work behind the scenes to manage resources, reallocate buffers,
	recreate render targets even rebuild shader variants and pipline states in some cases.
	So it would be unergonomical to return a mutable pointer to the configuration state.
*/



get_render_config :: proc() -> RenderConfig {
    return engine.render_context.config;
}

set_render_config :: proc(config : RenderConfig){

    gpu_device := get_gpu_device();
	renderer_set_render_config(engine.render_context, gpu_device, config);
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

get_ren_effect_RACA_settings :: proc() -> RenEffectRACASettings{
	return renderer_get_ren_effect_RACA_settings(engine.render_context);
}

set_ren_effect_RACA_settings :: proc(settings : RenEffectRACASettings){
	gpu_device := get_gpu_device();
	renderer_set_ren_effect_RACA_settings(engine.render_context, gpu_device, settings);
}