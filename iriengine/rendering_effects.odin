package iri
import "core:log"
import "core:mem"
import "core:strings"
import "core:os"
import "core:math"
import sdl "vendor:sdl3"
import "odinary:picy"


RENDERING_EFFECT_FLAGS_ALL :: RenderingEffectFlags{.GTAO, .SMAA, .RACA}
RENDERING_EFFECT_FLAGS_DEFAULT :: RenderingEffectFlags{.GTAO, .SMAA, .RACA}
RenderingEffectFlags :: distinct bit_set[RenderingEffectFlag]
RenderingEffectFlag :: enum u32 {
	GTAO, // Ground Truth Ambient Occlusion
	SMAA, // Subpixel Morphological Anti Aliasing
	RACA, // Radiance Cascades
}


RenderEffectsData :: struct {
	gtao : ^RenEffectGTAO,
	smaa : ^RenEffectSMAA,
	raca : ^RenEffectRACA,
}


render_effects_reinit :: proc(gpu_device: ^sdl.GPUDevice, effects : ^RenderEffectsData, effect_flags : RenderingEffectFlags, frame_size: [2]u32) {

	if .GTAO in effect_flags {

		if effects.gtao == nil {
			effects.gtao = new(RenEffectGTAO);
			effects.gtao.settings = ren_effect_GTAO_create_default_settings();
		}

		if !engine.in_init_phase {
			ren_effect_GTAO_reinit(gpu_device, effects.gtao, frame_size);
		}
	}

	if .SMAA in effect_flags {

		if effects.smaa == nil {
			effects.smaa = new(RenEffectSMAA);
			effects.smaa.settings = ren_effect_SMAA_create_default_settings();
		}

		if !engine.in_init_phase {
			ren_effect_SMAA_reinit(gpu_device, effects.smaa, frame_size);
		}
	}

	if .RACA in effect_flags {

		if effects.raca == nil {
			effects.raca = new(RenEffectRACA);
			effects.raca.settings = ren_effect_RACA_create_default_settings();
		}

		if !engine.in_init_phase {
			ren_effect_RACA_reinit(gpu_device, effects.raca, frame_size);
		}
	}
}

render_effects_deinit_and_destroy :: proc(render_context : ^RenderContext, gpu_device: ^sdl.GPUDevice, effect_flags : RenderingEffectFlags = RENDERING_EFFECT_FLAGS_ALL){

	engine_assert(render_context != nil);

	effects := &render_context.effects;

	if effects.gtao != nil && .GTAO in effect_flags {
		ren_effect_GTAO_deinit(gpu_device, effects.gtao);
		free(effects.gtao);
		effects.gtao = nil;
	}

	if effects.smaa != nil && .SMAA in effect_flags{
		ren_effect_SMAA_deinit(gpu_device, effects.smaa);
		free(effects.smaa);
		effects.smaa = nil;
	}

	if effects.raca != nil && .RACA in effect_flags {
		ren_effect_RACA_deinit(gpu_device, effects.raca);
		free(effects.raca);
		effects.raca = nil;
	}

	render_context.config.ren_effect_flags -= effect_flags;
}


// ==============================================================
// GTAO 
// ==============================================================

RenEffectGTAO :: struct {
	target_tex : ^sdl.GPUTexture,
	settings : RenEffectGTAOSettings
}

RenEffectGTAOSettings :: struct {
	temporary_disabled : bool,
	full_res : bool,

	strength : f32,
    sample_count : u32,
    slice_count  : u32,
    sample_radius : f32,
    hit_thickness : f32,
}

ren_effect_GTAO_create_default_settings :: proc() -> RenEffectGTAOSettings {

	return RenEffectGTAOSettings{
		temporary_disabled = false,
		full_res 		= true,
		strength        = 2.5,
        sample_count    = 8,
        slice_count     = 8,
        sample_radius   = 1.0,
        hit_thickness   = 0.15,
	};
}

ren_effect_GTAO_reinit :: proc(gpu_device: ^sdl.GPUDevice, gtao : ^RenEffectGTAO, frame_size: [2]u32){

	engine_assert(gtao != nil)

	if gtao.target_tex != nil {
        sdl.ReleaseGPUTexture(gpu_device, gtao.target_tex);
        gtao.target_tex = nil;
    }

    ao_tex_format := sdl.GPUTextureFormat.R8_UNORM;
	gtao.target_tex = texture_create_2D(gpu_device, frame_size, ao_tex_format, true, {.SAMPLER, .COMPUTE_STORAGE_READ, .COMPUTE_STORAGE_WRITE, .COMPUTE_STORAGE_SIMULTANEOUS_READ_WRITE});

}

ren_effect_GTAO_deinit :: proc(gpu_device: ^sdl.GPUDevice, gtao : ^RenEffectGTAO){

	engine_assert(gtao != nil)

	if gtao.target_tex != nil {
        sdl.ReleaseGPUTexture(gpu_device, gtao.target_tex);
        gtao.target_tex = nil;
    }
}


// ==============================================================
// SMAA
// ==============================================================

RenEffectSMAA :: struct {
	edges_target : ^sdl.GPUTexture,
    blend_target : ^sdl.GPUTexture,
    area_tex   : ^sdl.GPUTexture,
    search_tex : ^sdl.GPUTexture,

    settings : RenEffectSMAASettings,
}

RenEffectSMAASettings :: struct {
	temporary_disabled : bool,
	tmp : f32,
}

ren_effect_SMAA_create_default_settings :: proc() -> RenEffectSMAASettings {

	return RenEffectSMAASettings{
		temporary_disabled = false,
		tmp = 1,
	};
}

ren_effect_SMAA_reinit :: proc(gpu_device: ^sdl.GPUDevice, smaa : ^RenEffectSMAA, frame_size: [2]u32) {
	engine_assert(smaa != nil)

	if smaa.edges_target != nil {
        sdl.ReleaseGPUTexture(gpu_device, smaa.edges_target);
        smaa.edges_target = nil;
    }

    if smaa.blend_target != nil {
        sdl.ReleaseGPUTexture(gpu_device, smaa.blend_target);
        smaa.blend_target = nil;
    }

   	smaa.edges_target = texture_create_2D(gpu_device, frame_size, sdl.GPUTextureFormat.R8G8B8A8_UNORM, false, {.COLOR_TARGET, .SAMPLER});
   	smaa.blend_target = texture_create_2D(gpu_device, frame_size, sdl.GPUTextureFormat.R8G8B8A8_UNORM, false, {.COLOR_TARGET, .SAMPLER});

   	if smaa.search_tex == nil {

   		SEARCH_TEX_WIDTH :: 64
		SEARCH_TEX_HEIGHT :: 16
		SEARCH_TEX_NUM_BYTES :: SEARCH_TEX_HEIGHT * SEARCH_TEX_WIDTH * 1

   		search_tex_path : string = strings.join({get_resources_path(), "rendering/smaa/smaa_search_tex_64x16px_R8_UNORM.rawbytes"}, "/", context.temp_allocator);

   		search_tex_bytes , err := os.read_entire_file_from_path(search_tex_path, context.allocator)
   		defer if search_tex_bytes != nil {
   			delete(search_tex_bytes);
   		}

   		if err != nil {
   			log.debugf("Renderer: Faild to load SMAA Search texture from resources path, cannot activate SMAA render effect feature. path: {}, error: {}", search_tex_path, err);
   			render_effects_deinit_and_destroy(engine.render_context, gpu_device, {.SMAA});
   			return;
   		}

   		pic_info := picy.PicInfo{
   			format = picy.PicFormat.R8_UNORM,
   			width  = SEARCH_TEX_WIDTH,
   			height = SEARCH_TEX_HEIGHT,
   			num_bytes = SEARCH_TEX_NUM_BYTES,
   			pixels = cast([^]byte)raw_data(search_tex_bytes)
   		}


   		smaa.search_tex = texture_create_2D(gpu_device, [2]u32{SEARCH_TEX_WIDTH, SEARCH_TEX_HEIGHT}, sdl.GPUTextureFormat.R8_UNORM, false, {.SAMPLER});

   		upload_ok := texture_upload_pic_info_to_gpu_texture_2D(gpu_device, smaa.search_tex, &pic_info);

   		if !upload_ok {
   			log.debugf("Renderer: Faild to upload SMAA Search texture to gpu, cannot activate SMAA render effect feature.");
   			render_effects_deinit_and_destroy(engine.render_context, gpu_device, {.SMAA});
   			return;
   		}
   	}

   	if smaa.area_tex == nil {

   		AREA_TEX_WIDTH :: 160
		AREA_TEX_HEIGHT :: 560
		AREA_TEX_NUM_BYTES :: AREA_TEX_HEIGHT * AREA_TEX_WIDTH * 2

		area_tex_path : string = strings.join({get_resources_path(), "rendering/smaa/smaa_area_tex_160x560px_R8G8_UNORM.rawbytes"}, "/", context.temp_allocator);

   		area_tex_bytes , err := os.read_entire_file_from_path(area_tex_path, context.allocator)
   		defer if area_tex_bytes != nil {
   			delete(area_tex_bytes);
   		}

   		if err != nil {
   			log.debugf("Renderer: Faild to load SMAA Area texture from resources path, cannot activate SMAA render effect feature. path: {}, error: {}", area_tex_path, err);
   			render_effects_deinit_and_destroy(engine.render_context, gpu_device, {.SMAA});
   			return;
   		}

   		pic_info := picy.PicInfo{
   			format = picy.PicFormat.RG8_UNORM,
   			width  = AREA_TEX_WIDTH,
   			height = AREA_TEX_HEIGHT,
   			num_bytes = AREA_TEX_NUM_BYTES,
   			pixels = cast([^]byte)raw_data(area_tex_bytes),
   		}
   		
   		smaa.area_tex = texture_create_2D(gpu_device, [2]u32{AREA_TEX_WIDTH, AREA_TEX_HEIGHT}, sdl.GPUTextureFormat.R8G8_UNORM, false, {.SAMPLER});

   		upload_ok := texture_upload_pic_info_to_gpu_texture_2D(gpu_device, smaa.area_tex, &pic_info);

   		if !upload_ok {
   			log.debugf("Renderer: Faild to upload SMAA Area texture to gpu, cannot activate SMAA render effect feature.");
   			render_effects_deinit_and_destroy(engine.render_context, gpu_device, {.SMAA});
   			return;
   		}
   	}

}

ren_effect_SMAA_deinit :: proc(gpu_device: ^sdl.GPUDevice, smaa : ^RenEffectSMAA){

	engine_assert(smaa != nil)

	if smaa.edges_target != nil {
        sdl.ReleaseGPUTexture(gpu_device, smaa.edges_target);
        smaa.edges_target = nil;
    }

    if smaa.blend_target != nil {
        sdl.ReleaseGPUTexture(gpu_device, smaa.blend_target);
        smaa.blend_target = nil;
    }

    if smaa.area_tex != nil {
        sdl.ReleaseGPUTexture(gpu_device, smaa.area_tex);
        smaa.area_tex = nil;
    }

    if smaa.search_tex != nil {
        sdl.ReleaseGPUTexture(gpu_device, smaa.search_tex);
        smaa.search_tex = nil;
    }
}



// ==============================================================
// RACA - Radiance Cascades
// ==============================================================

RenEffectRACA :: struct {
	ao_tex_0 : ^sdl.GPUTexture,
	ao_tex_1 : ^sdl.GPUTexture,

	cascade_array_tex : ^sdl.GPUTexture,
	settings : RenEffectRACASettings
}

RenEffectRACASettings :: struct {
	temporary_disabled : bool,
	num_cascades : u32,
	base_ray_length  : f32,
	base_probe_size  : u32, // how many pixel c0 probes have in one axis. e.g  4 means 4x4px = 16 pxiels aka samples. 
	pixels_per_probe : u32, // how many screen pixels c0 probes occupy.
	depth_bias : f32,
}

ren_effect_RACA_create_default_settings :: proc() -> RenEffectRACASettings {

	return RenEffectRACASettings{
		temporary_disabled = false,
		num_cascades 	 = 5,
		base_ray_length  = 0.1,
		base_probe_size  = 4,
		pixels_per_probe = 4,
		depth_bias = 0.0001,
	};
}

ren_effect_RACA_require_reinit :: proc(curr_settings, new_settings : RenEffectRACASettings) -> bool{
	do_reinit : bool = false;

    do_reinit |= (curr_settings.num_cascades != new_settings.num_cascades);
    do_reinit |= (curr_settings.base_probe_size != new_settings.base_probe_size);
    do_reinit |= (curr_settings.pixels_per_probe != new_settings.pixels_per_probe);

    return do_reinit;
}

ren_effect_RACA_reinit :: proc(gpu_device: ^sdl.GPUDevice, raca : ^RenEffectRACA, frame_size: [2]u32) {

	engine_assert(raca != nil)
	//log.warnf("RACA reinit")
	ren_effect_RACA_deinit(gpu_device, raca);

    ao_tex_format := sdl.GPUTextureFormat.R32G32B32A32_FLOAT;


	// TODO: account for unevenes and possibly add 1 more probe.
	base_probe_count : [2]u32 = ren_effect_RACA_get_base_probe_counts(raca.settings.pixels_per_probe, frame_size);
	resolution  : [2]u32 = base_probe_count * raca.settings.base_probe_size;
	
	cascades_format := sdl.GPUTextureFormat.R8G8_UNORM;
	array_count := raca.settings.num_cascades;

	raca.ao_tex_1 = texture_create_2D(gpu_device, resolution, ao_tex_format, false, {.SAMPLER, .COMPUTE_STORAGE_READ, .COMPUTE_STORAGE_WRITE, .COMPUTE_STORAGE_SIMULTANEOUS_READ_WRITE});
	raca.ao_tex_0 = texture_create_2D(gpu_device, resolution, ao_tex_format, false, {.SAMPLER, .COMPUTE_STORAGE_READ, .COMPUTE_STORAGE_WRITE, .COMPUTE_STORAGE_SIMULTANEOUS_READ_WRITE});


	LOG_CASCADES_INFO :: false
	when LOG_CASCADES_INFO {
		log.warnf("Cascade Texture: base_counts {}x{} | TexResolution: {}x{}", base_probe_count.x, base_probe_count.y, resolution.x, resolution.y);

		for c in 0..<raca.settings.num_cascades {
			
			cascade_index : u32 = cast(u32)c;
			probe_counts    : [2]u32 = ren_effect_RACA_get_probe_counts_for_cascade(cascade_index, base_probe_count);
	        probe_size      : u32    = ren_effect_RACA_get_probe_size_for_cascade(cascade_index, raca.settings.base_probe_size);
	         //cascade_interval_range  : [2]f32 = ren_effect_RACA_get_interval_range(cascade_index, raca.settings.base_ray_length);

	        log.warnf("Cadcade: {}, probe_count {}x{} 	| probe_size = {}x{} = {}", cascade_index, probe_counts.x, probe_counts.y, probe_size, probe_size, probe_size*probe_size)
		}
	}

	cascade_array_create_info : sdl.GPUTextureCreateInfo = {
    	type = sdl.GPUTextureType.D2_ARRAY, 
    	format = cascades_format,
    	usage  = sdl.GPUTextureUsageFlags{.COMPUTE_STORAGE_WRITE, .SAMPLER},
    	width  = resolution.x,
    	height = resolution.y,
    	layer_count_or_depth = array_count,
    	num_levels   = 1, // no mip levels
    	sample_count = sdl.GPUSampleCount._1,
	}

	raca.cascade_array_tex = sdl.CreateGPUTexture(gpu_device, cascade_array_create_info);
}

ren_effect_RACA_deinit :: proc(gpu_device: ^sdl.GPUDevice, raca : ^RenEffectRACA){

	engine_assert(raca != nil)

	if raca.ao_tex_0 != nil {
        sdl.ReleaseGPUTexture(gpu_device, raca.ao_tex_0);
        raca.ao_tex_0 = nil;
    }

    if raca.ao_tex_1 != nil {
        sdl.ReleaseGPUTexture(gpu_device, raca.ao_tex_1);
        raca.ao_tex_1 = nil;
    }

    if raca.cascade_array_tex != nil {
        sdl.ReleaseGPUTexture(gpu_device, raca.cascade_array_tex);
        raca.cascade_array_tex = nil;
    }
}


ren_effect_RACA_get_base_probe_counts :: proc "contextless" (pixels_per_probe : u32, frame_size : [2]u32) -> [2]u32{
	
	base_counts : [2]u32 = frame_size / pixels_per_probe;
	
	if( frame_size.x % pixels_per_probe > 0) {base_counts.x += 1;}
	if( frame_size.y % pixels_per_probe > 0) {base_counts.y += 1;}

	return base_counts;
}

ren_effect_RACA_get_probe_counts_for_cascade :: proc "contextless" (cascade_index : u32, base_counts : [2]u32) -> [2]u32 {
	
	//base_counts : [2]u32 = frame_size / pixels_per_probe;	
	return base_counts / (u32(1) << cascade_index); // bit shift equivalent to: cast(u32)mathy.pow_i32(2 , cast(i32)cascade);
}

ren_effect_RACA_get_interval_range :: proc "contextless" (cascade_index : u32, base_length: f32) -> [2]f32 {

	intervall_scale_0 : f32 = cascade_index == 0 ? 0.0 : math.pow(4.0, f32(cascade_index));
	intervall_scale_1 : f32 = math.pow(4.0, f32(cascade_index + 1));

	start : f32 = base_length * intervall_scale_0;
	end   : f32 = base_length * intervall_scale_1;

	return [2]f32{start, end};
}

ren_effect_RACA_get_probe_size_for_cascade :: proc "contextless" (cascade_index : u32, base_probe_size: u32) -> u32 {

	return base_probe_size * (1 << cascade_index) // base_probe_size * 2^cascade_index
}