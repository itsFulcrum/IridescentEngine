package iri
import "core:log"
import "core:mem"
import "core:strings"
import "core:os"
import sdl "vendor:sdl3"
import "odinary:picy"


RENDERING_EFFECT_FLAGS_ALL :: RenderingEffectFlags{.GTAO, .SMAA}
RENDERING_EFFECT_FLAGS_DEFAULT :: RenderingEffectFlags{.GTAO, .SMAA}
RenderingEffectFlags :: distinct bit_set[RenderingEffectFlag]
RenderingEffectFlag :: enum u32 {
	GTAO,
	SMAA
}


RenderEffectsData :: struct {
	gtao : ^RenEffectGTAO,
	smaa : ^RenEffectSMAA,
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
			effects.smaa.settings = ren_effect_SMAA_create_default_settings()
		}

		if !engine.in_init_phase {
			ren_effect_SMAA_reinit(gpu_device, effects.smaa, frame_size);
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
	full_res : bool, // Not implmented yet

	strength : f32,
    sample_count : u32,
    slice_count  : u32,
    sample_radius : f32,
    hit_thickness : f32,
}

ren_effect_GTAO_create_default_settings :: proc() -> RenEffectGTAOSettings {

	return RenEffectGTAOSettings{
		temporary_disabled = false,
		full_res 		= false,
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

