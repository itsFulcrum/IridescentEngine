package iri

import sdl "vendor:sdl3"
import iricom "iricommon"


FontAtlas :: struct {
	
	font_is_loaded     : bool,
	font_id_generation : u8,

    altas_tex : Texture2D,
    
    rune_render_lookup  : map[rune]iricom.FontAtlasRuneInfo,
    // stores only x_advance since thats the only thing we need to measureing atm. // may need to include kerning info here..
    rune_measure_lookup : map[rune]f32, 

    info : iricom.FontAtlasInfo,
}

font_atlas_clear_contents :: proc(gpu_device : ^sdl.GPUDevice, font_atlas : ^FontAtlas){

	font_atlas.font_id_generation = 0;
	font_atlas.font_is_loaded = false;

	texture_2D_destroy(gpu_device, &font_atlas.altas_tex, true);

	clear_map(&font_atlas.rune_render_lookup)
	clear_map(&font_atlas.rune_measure_lookup)

	font_atlas.info = iricom.FontAtlasInfo{};
}

font_atlas_free_contents :: proc(gpu_device : ^sdl.GPUDevice, font_atlas : ^FontAtlas){

	font_atlas_clear_contents(gpu_device, font_atlas);

	delete_map(font_atlas.rune_render_lookup)
	delete_map(font_atlas.rune_measure_lookup)
}