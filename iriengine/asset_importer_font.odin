package iri

import "core:log"
import "core:os"
import "core:mem"
import "core:math"
import "core:strings"

import iria "iriasset"
import iricom "iricommon"

import "vendor:stb/truetype"
import "vendor:stb/rect_pack"

FontGlyphRangeFlags :: bit_set[FontGlyphRange]
FontGlyphRange :: enum u32 {
	Ascii,           // Codepoint-Decimals:  32..<=127
	AsciiExtention,  // Codepoint-Decimals: 128..<=255
	LatinExtentionA, // Codepoint-Decimals: 256..<=383
	LatinExtentionB, // Codepoint-Decimals: 384..<=591
}

FontAtlasCreateInfo :: struct {

	asset_alias : string , // optionally already specify the alias

	import_flags : AssetImportFlags,
	font_size      : f32, // height of tallest glyph in pixels

	use_nearest_neighboor_filtering : bool,
	oversampling_x : u32,
	oversampling_y : u32,
	glyph_range_flags : FontGlyphRangeFlags,

	custom_range_min_decimal : u32,
	custom_range_max_decimal : u32,
	custom_codepoints : string,
}

FontAtlasRawData :: struct {
	info : iricom.FontAtlasInfo,
	pixels : [^]u8,

	// rune_codepoints and rune info have the same length rand correspond to each other by array index.
	rune_codepoints : []rune,
	rune_info : []iricom.FontAtlasRuneInfo,
}

asset_importer_import_font_to_project :: proc(load_path : string, store_directory_path : string, create_info : FontAtlasCreateInfo) -> (ok : bool) {

	import_flags := create_info.import_flags;

	log_errors : bool = .LogErrors in import_flags;
	can_overwrite_existing : bool = .OverwriteExisting in import_flags;
	write_flags : iria.AssetWriteFlags = importer_iria_write_flags_from_asset_import_flags(import_flags);

	//
	// - Validate load filepath and Write filepath.
	// 

	if !os.exists(load_path) {
		if log_errors do log.errorf("AssetImporter-Font: Filepath does not exist: {}", load_path);
		return false;
	}

	store_dir_path_abs := clean_path_absolute(store_directory_path) or_return;
	if !os.is_directory(store_dir_path_abs){

		make_err := os.make_directory_all(store_dir_path_abs);
		if make_err != os.ERROR_NONE {
			log.errorf("AssetImporter-Font: Failed to create directory to write assets to {}", store_dir_path_abs);
			return false;
		}
	}


	_ , load_file_name  := os.split_path(load_path);
	load_file_name_only := os.short_stem(load_file_name);

	store_filename , osErr := os.join_filename(load_file_name_only, iria.FILE_EXTENTION_NAME, context.temp_allocator);
	engine_assert(osErr == os.ERROR_NONE);

	full_store_filepath, alloc_err := os.join_path({store_directory_path, store_filename}, context.temp_allocator);
	engine_assert(alloc_err == nil);

	store_path_exists_already := os.exists(full_store_filepath);
	
	if store_path_exists_already && !can_overwrite_existing {
		if log_errors do log.errorf("AssetImporter-Font: Filepath Validation Failed - 'OverwriteExisting' is false but file already exists at", full_store_filepath);
		return false;
	}

	//
	// - Load .ttf and render 
	// 

	font_atlas_data, import_ok := asset_importer_font_atlas_load_ttf_and_render_atlas(load_path, create_info, log_errors);
	if !import_ok {
		return false;
	}
	

	asset_font : ^iria.AssetFontAtlas = new(iria.AssetFontAtlas, context.temp_allocator);

	defer {
		iria.asset_font_atlas_free_contents(asset_font);
	}


	asset_id : AssetID;
	if store_path_exists_already && can_overwrite_existing {
		// check if asset exits at this path and get its, id
		existing_asset_id, _, is_valid_asset := iria.read_asset_header_info_from_path(full_store_filepath, .FontAtlas , log_errors);

		if is_valid_asset {
			asset_id = existing_asset_id;
		} else {
			// corrputed file ?? Since we were told to overwrite we will do that with a new AssetID

			asset_id = iria.generate_new_asset_id()
		}

	} else {
		asset_id = iria.generate_new_asset_id()
	}

	if len(create_info.asset_alias) > 0 {
		asset_font.asset_alias = strings.clone(create_info.asset_alias, context.allocator);
	}

	asset_font.asset_id = asset_id;

	asset_font.num_rune_codepoints = cast(u32)len(font_atlas_data.rune_codepoints);

	asset_font.rune_codepoints = font_atlas_data.rune_codepoints;
	asset_font.rune_info       = font_atlas_data.rune_info;
	asset_font.info 		   = font_atlas_data.info;
	asset_font.atlas_pixels    = font_atlas_data.pixels;

	asset_font.use_nearest_neighbour_filtering = create_info.use_nearest_neighboor_filtering;


	iria.asset_font_atlas_write_to_file(full_store_filepath, asset_font, write_flags) or_return;

	asset_manager := engine.asset_manager;
	is_registered := asset_manager_register_asset_file_by_path(asset_manager, full_store_filepath);

	return true;
}


asset_importer_font_atlas_create_rune_codepoints_list :: proc(create_info : FontAtlasCreateInfo, allocator := context.allocator) -> [dynamic]rune {

	// just using this map as a datastructure to not add dublicates.
	rune_table     : map[rune]u8 = make_map_cap(map[rune]u8, 256, context.allocator);
	defer delete_map(rune_table);
	
	include_flags := create_info.glyph_range_flags;

	rune_codepoints : [dynamic]rune = make_dynamic_array_len_cap([dynamic]rune, 0 , 256, allocator);

	append_codepoint_range :: proc(range_min : i32, range_max : i32, rune_table : ^map[rune]u8, rune_codepoints : ^[dynamic]rune) {
		for i in range_min..=range_max {
			codepoint : rune = cast(rune)i;
			if codepoint not_in rune_table {
				//log.debugf("Add: Dec: {}, Char '{}'", i, codepoint);
				rune_table[codepoint] = 1;
				append(rune_codepoints, codepoint);
			}
		}
	}

	// Ascii 
	if .Ascii in include_flags {
		//log.warnf("Adding ASCII")
		append_codepoint_range(32, 127, &rune_table, &rune_codepoints)
	}

	if .AsciiExtention in include_flags {			
		//log.warnf("Adding ASCII Extended")
		append_codepoint_range(128, 254, &rune_table, &rune_codepoints)
	}

	if .LatinExtentionA in include_flags {
		//log.warnf("Adding Latin Extended A")
		append_codepoint_range(255, 383, &rune_table, &rune_codepoints)
	}

	if .LatinExtentionB in include_flags {
		//log.warnf("Adding Latin Extended B")
		append_codepoint_range(384, 591, &rune_table, &rune_codepoints)
	}

	if create_info.custom_range_min_decimal > 0 && create_info.custom_range_max_decimal > 0{
		if create_info.custom_range_max_decimal >= create_info.custom_range_min_decimal {
			append_codepoint_range(cast(i32)create_info.custom_range_min_decimal, cast(i32)create_info.custom_range_max_decimal, &rune_table, &rune_codepoints)
		}
	}

	// Add Custom Codepoints.
	if len(create_info.custom_codepoints) > 0 {


		for codepoint, _ in create_info.custom_codepoints {
			if cast(i32)codepoint == 0 {
				break; // Null termination of string/cstring. We need this aprrantly if string was created from a null_terminated buffer.
			}
			if codepoint not_in rune_table {
				rune_table[codepoint] = 1;
				append(&rune_codepoints, codepoint);					
			}
		}
	}

	return rune_codepoints;
}


asset_importer_font_atlas_load_ttf_and_render_atlas :: proc(full_filepath : string, create_info : FontAtlasCreateInfo, log_errors : bool = true) -> (font_data : FontAtlasRawData, ok : bool) {

	GLYPH_PADDING :: 3


	//
	//	- Read Font File.
	//

	file_data , read_err := os.read_entire_file_from_path(full_filepath, context.allocator);
	if read_err != nil {
		if log_errors do log.errorf("AssetImporter-Font: Failed to read file at path: {} - msg: {}", full_filepath, read_err)
		return font_data, false;
	}
	defer delete_slice(file_data);


	// 
	// - Produce a List of all Codepoint we want to Render into the Atlas Texture. 
	//

	rune_codepoints : [dynamic]rune = asset_importer_font_atlas_create_rune_codepoints_list(create_info, context.allocator);

	num_runes : int = len(rune_codepoints);
	if num_runes <= 0 {
		if log_errors do log.errorf("AssetImporter-Font: No Codepoints/GlyphRanges where specified for importing truetype font: {}. - It doesn't make sense to build an atlas with nothing in it..", full_filepath);
		return font_data, false;
	}


	font_info : ^truetype.fontinfo = new(truetype.fontinfo, context.temp_allocator);
	init_ok := truetype.InitFont(font_info, &file_data[0], 0);
	if !init_ok {
		if log_errors do log.errorf("AssetImporter-Font: stb_truetype faild to read/initialize font data: {}", full_filepath);
		return font_data, false;
	}


	font_size : f32 = create_info.font_size;

	ascent   : i32
	descent  : i32
	line_gap : i32
	truetype.GetFontVMetrics(font_info, &ascent, &descent, &line_gap);
	scale_factor : f32 = truetype.ScaleForPixelHeight(font_info, font_size);


	//
	//	- Compute Temp Buffer Size Estimate.
	//

	// Oversampling grows the glyph pixel size so when we want to calculate buffer size for the texture
	// we have to take that into account.
	// Allow a maximun oversampling of 16 to avoid huge ass textures.
    oversampling_x : u32 = create_info.oversampling_x <= 0 ? 1 : min(create_info.oversampling_x, 16);
    oversampling_y : u32 = create_info.oversampling_y <= 0 ? 1 : min(create_info.oversampling_y, 16);

	atlas_temp_buffer_width  : u32 = 512; 
	atlas_temp_buffer_height : u32 = 512;

    // Compute Conservative Estimate of buffer size we need to render glyphs into.
    {
    	// @Note: 
    	// We don't include glyph padding in this calculations but since we are quite conservative here it should be fine.
    	font_size_u32    : u32 = cast(u32)font_size;
    	glpyh_height     : u32 = font_size_u32 * oversampling_y // This Should roughly hold.
    	glpyh_width      : u32 = font_size_u32 * oversampling_x // Very vonservative estimate since Glyphs can have drasticly different widths.
    	glyph_num_pixels : u32 = glpyh_width * glpyh_height;
    
    	// Conservative Estimate.
    	max_num_pixels : u32 = cast(u32)num_runes * glyph_num_pixels; 

    	dim : u32 = cast(u32)math.ceil(math.sqrt_f32(cast(f32)max_num_pixels))
    	if dim % 2 == 1  do dim +=1 // Avoid uneven numbers.
    	atlas_temp_buffer_width  = dim;
    	atlas_temp_buffer_height = dim;
    }

	// @Note: This a conservative Estimate of the texture dimentions we may need but likely much bigger.
	// After stb_truetype is finished packing we will trim this down.
	atlas_temp_buffer_num_pixels : u32 = atlas_temp_buffer_width * atlas_temp_buffer_height;

	atlas_temp_buffer_pixels : [^]u8 = make_multi_pointer([^]u8, cast(int)atlas_temp_buffer_num_pixels, context.allocator);
	defer free(atlas_temp_buffer_pixels);


	char_data := make_multi_pointer([^]truetype.packedchar, num_runes, context.allocator);
	defer free(char_data);

	pack_ranges : [1]truetype.pack_range;
	pack_ranges[0].font_size = font_size;
	pack_ranges[0].array_of_unicode_codepoints = &rune_codepoints[0]
	pack_ranges[0].num_chars = cast(i32)num_runes
	pack_ranges[0].chardata_for_range = char_data

	// 
	// - Stb Render Glyphs to Temp Buffer.
	//

	pack_context : truetype.pack_context;

	res := truetype.PackBegin(&pack_context, atlas_temp_buffer_pixels, cast(i32)atlas_temp_buffer_width, cast(i32)atlas_temp_buffer_height, stride_in_bytes = 0, padding = GLYPH_PADDING, alloc_context = nil);
	engine_assert(res == 1); // TODO: error handling

	truetype.PackSetOversampling(&pack_context, oversampling_x, oversampling_y);

	res = truetype.PackFontRanges(&pack_context, fontdata = &file_data[0], font_index = 0, ranges = &pack_ranges[0], num_ranges = 1);
	engine_assert(res == 1); // TODO: error handling


	truetype.PackEnd(&pack_context);


	// 
	// - Slice/Trim Temp Buffer
	// 

	// @Note: Here we attempt to trim down the conservative buffer to only what we need.
	// stb_truetype packs glyphs from left->right and top->bottom.
	// So we iterate all pixels from the top and stop when we find multiple rows that don't contain any non-zero pixel.

	trim_height : u32 = atlas_temp_buffer_height;
	max_num_rows_without_pixel_data : u32 = GLYPH_PADDING + 4; // + 4 just to be safe.
	curr_num_rows_without_pixel_data : u32 = 0;

	row_loop: for y in 0..<atlas_temp_buffer_height {

		collum_loop: for x in 0..<atlas_temp_buffer_width {

			pixel_index : u32 = y * atlas_temp_buffer_width + x;
			if atlas_temp_buffer_pixels[pixel_index] > 0 {
				curr_num_rows_without_pixel_data = 0;
				break collum_loop;
			}
		}

		if curr_num_rows_without_pixel_data >= max_num_rows_without_pixel_data {
			trim_height = y;
			break row_loop;
		}
		
		curr_num_rows_without_pixel_data += 1;
	}

	if trim_height % 2 == 1 do trim_height +=1; // Avoid Uneven Number.
	// Even if we didn't trim anything trim_height should be same as previous height an even number and line above this should not have added +1;
	engine_assert(trim_height <= atlas_temp_buffer_height);

	final_atlas_width  : u32 = atlas_temp_buffer_width;
	final_atlas_height : u32 = trim_height;
	final_num_pixels : u32 = final_atlas_width * final_atlas_height;

	final_pixel_buf : [^]u8 = make_multi_pointer([^]u8, cast(int)final_num_pixels, context.allocator);
	mem.copy(final_pixel_buf, atlas_temp_buffer_pixels, cast(int)final_num_pixels);

	
	// 
	// - Convert packedchar data into runtime ready format.
	//

	// @Note: Even if not all glyphs where part of the font, 
	// stb_truetype will add valid rectangle/packedchar data that points to an empty or invalid glyph symbol in the atlas.
	// So we will include them aswell so that we can render them.
	// It would be nice to somehow store this Invlid/Glyph specifically somewhere so that we can use that whenever we need to draw a codepoint that is not in this table.
	
	rune_info : []iricom.FontAtlasRuneInfo = make_slice([]iricom.FontAtlasRuneInfo, num_runes, context.allocator);

	inv_atlas_size : [2]f32 = 1.0 / [2]f32{cast(f32)final_atlas_width, cast(f32)final_atlas_height};

	for codepoint, index in rune_codepoints {
		
		pchar := char_data[index]		
		// in pixels
        char_extent_x : f32 = f32(pchar.x1 - pchar.x0)
        char_extent_y : f32 = f32(pchar.y1 - pchar.y0)		

		rune_info[index] = iricom.FontAtlasRuneInfo {
			x_advance_px = pchar.xadvance,
			offset_px    = [2]f32{pchar.xoff, pchar.yoff},
			size_px      = [2]f32{pchar.xoff2 - pchar.xoff, pchar.yoff2 - pchar.yoff},
            uv_scale  = [2]f32{char_extent_x, char_extent_y} * inv_atlas_size,
            uv_offset = [2]f32{f32(pchar.x0), f32(pchar.y0)} * inv_atlas_size,
		}
	}

	engine_assert(len(rune_info) == len(rune_codepoints));


	//
	// - Prepare Output Data
	// 

	font_data = FontAtlasRawData {	
		info = iricom.FontAtlasInfo {
			font_size_px = font_size,
			scale_factor = scale_factor,
			ascent_px    = f32(ascent)   * scale_factor,
	    	descent_px   = f32(descent)  * scale_factor,
	    	line_gap_px  = f32(line_gap) * scale_factor,

	    	atlas_width  = final_atlas_width,
			atlas_height = final_atlas_height,
		},
		pixels = final_pixel_buf,
		rune_info = rune_info,
		rune_codepoints = rune_codepoints[:],
	}


	return font_data, true;
}