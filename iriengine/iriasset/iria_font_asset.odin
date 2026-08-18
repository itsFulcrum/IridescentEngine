package iria


import "core:os"
import "core:log"

import iricom "../iricommon"
import reader "odinary:readbinary"

AssetFontAtlas :: struct {

	asset_id : AssetID,
	asset_alias : string, // can be nothing.
	
	num_rune_codepoints : u32,
	// For each codepoint there is a rune_info.
	rune_codepoints : []rune,
	rune_info       : []iricom.FontAtlasRuneInfo,

	use_nearest_neighbour_filtering : bool,

	info : iricom.FontAtlasInfo,
	// pixel format is uncompress u8 single channel. (R8_UNORM)
	atlas_pixels : [^]u8,
}

asset_font_atlas_free_contents :: proc(font : ^AssetFontAtlas){

	if font == nil do return;

	if len(font.asset_alias) > 0 {
		delete_string(font.asset_alias);
	}

	if font.rune_codepoints != nil {
		delete_slice(font.rune_codepoints);
	}
	
	if font.rune_info != nil {
		delete_slice(font.rune_info);
	}
	
	if font.atlas_pixels != nil {
		free(font.atlas_pixels);
	}
}

asset_font_atlas_free :: proc(font : ^AssetFontAtlas){

	if font == nil do return;

	asset_font_atlas_free_contents(font);
	free(font);
}



ASSET_FONT_ATLAS_FILE_CURRENT_VERSION : u32 : 1

// @ Font Atlas Asset version 1 File Layout
/*

-- CommonHeader  - Type: AssetFileCommonHeader 	| Size: size_of(AssetFileCommonHeader) (32 bytes)
-- AssetAliasStr - Type: AssetFileString128  	| Size: size_of(AssetFileString128) (128 bytes) - can be just zero memory (no alias).

AssetFontAtlasHeader_v1 contains info on number of codepoints stored aswell as width/height of the texture. 
 -> FontHeader.num_codepoints, FontHeader.info.atlas_width, FontHeader.info.atlas_height.
-- FontHeader    - Type: AssetFontAtlasHeader_v1| Size: size_of(AssetFontAtlasHeader_v1)

Contigous Array of runes/codepoints/i32 that is 'num_codepoints' long.
-- Codepoints/Runes - Type: []rune | Size: num_codepoints * size_of(rune)

Contigous Array of rune_info structures (iricom.FontAtlasRuneInfo) that is 'num_codepoints' long.
-- rune_info - Type: []iricom.FontAtlasRuneInfo | Size: num_codepoints * size_of(iricom.FontAtlasRuneInfo)

Raw uncrompressed pixel data of the atlas texture.
The pixel format is single (alpha) channel u8 - R8_UNORM
-- pixels - Type: [^]u8 | Size: FontHeader.info.atlas_width * FontHeader.info.atlas_height

*/

AssetFontAtlasHeader_v1 :: struct #packed {

	num_rune_codepoints : u32,

	use_nearest_neighbour_filtering : b8,
	_ : b8, 
	_ : b8, 
	_ : b8, 

	info : iricom.FontAtlasInfo,

	_ : [8]u32, // reserved
}


asset_font_atlas_read_from_path :: proc(filepath : string) -> (asset_font : ^AssetFontAtlas, ok : bool)  {
		
	file, open_err := os.open(filepath);
	if open_err != os.ERROR_NONE {
		return;
	}
	defer os.close(file);

	b_reader := reader.create_file_reader(file);
	return asset_font_atlas_read(&b_reader);
}

asset_font_atlas_read_from_memory :: proc(data : []byte) -> (asset_font : ^AssetFontAtlas, ok : bool) {
	b_reader := reader.create_memory_reader(data);
	return asset_font_atlas_read(&b_reader);
}


@(private="file")
asset_font_atlas_read :: proc(b_reader : ^$T) -> (asset_font : ^AssetFontAtlas, ok : bool) where T == reader.FileBinaryReader || T == reader.MemBinaryReader {

	common_hdr := reader.consume_copy_type(b_reader, AssetFileCommonHeader) or_return;

	if common_hdr.asset_type != AssetType.FontAtlas {
		return nil, false;
	}

	switch common_hdr.asset_type_version {
		case 1: return asset_font_atlas_read_v1(b_reader, common_hdr);
	}

	// invalid or depricated version
	return nil, false;
}



@(private="file")
asset_font_atlas_read_v1 :: proc(b_reader : ^$T, common_hdr : AssetFileCommonHeader) -> (asset_font : ^AssetFontAtlas, ok : bool) where T == reader.FileBinaryReader || T == reader.MemBinaryReader {


	asset_font = new(AssetFontAtlas);

	defer if !ok {
		asset_font_atlas_free(asset_font);
		asset_font = nil;
	}

	asset_font.asset_id = common_hdr.asset_id;

	alias_str_128 := reader.consume_copy_type(b_reader, AssetFileString128) or_return;
	alias_str, has_alias := string_clone_from_asset_string128(&alias_str_128,context.allocator);

	if has_alias {
		asset_font.asset_alias = alias_str;
	}


	// Asset Header
	asset_hdr : AssetFontAtlasHeader_v1 = reader.consume_copy_type(b_reader, AssetFontAtlasHeader_v1) or_return;
	{
		asset_font.info = asset_hdr.info;
		asset_font.use_nearest_neighbour_filtering = cast(bool)asset_hdr.use_nearest_neighbour_filtering;
		asset_font.num_rune_codepoints = asset_hdr.num_rune_codepoints;
	}


	num_codepoints : int = cast(int)asset_font.num_rune_codepoints;

	assert(num_codepoints != 0);


	// Read Rune Codepoints Array
	{
		asset_font.rune_codepoints = reader.consume_make_slice(b_reader, []rune, num_codepoints, context.allocator) or_return;
	}

	// Read Rune info Array
	{
		asset_font.rune_info = reader.consume_make_slice(b_reader, []iricom.FontAtlasRuneInfo, num_codepoints, context.allocator) or_return;
	}

	// Read Font Atlas Pixels
	{
		width  : int = cast(int)asset_font.info.atlas_width;
		height : int = cast(int)asset_font.info.atlas_height;

		num_pixels : int = width * height;
		assert(num_pixels >= 0);

		num_bytes : int = num_pixels * size_of(u8);

		asset_font.atlas_pixels = make_multi_pointer([^]u8, num_bytes, context.allocator);

		reader.consume_mem_copy(b_reader, &asset_font.atlas_pixels[0], num_bytes) or_return;
	}


	return asset_font, true,
}



asset_font_atlas_write_to_file :: proc(filepath : string, asset_font : ^AssetFontAtlas, write_flags : AssetWriteFlags) -> (ok : bool){

	log_errors : bool = .LogErrors in write_flags;
	can_overwrite_existing: bool = .OverwriteExisting in write_flags;

	assert(asset_font != nil);
	assert(asset_font.asset_id != AssetID_NONE)
	assert(asset_font.atlas_pixels != nil);
	assert(asset_font.num_rune_codepoints > 0)
	assert(len(asset_font.rune_codepoints) == len(asset_font.rune_info));

	file_exists_already := is_valid_write_filepath(filepath,can_overwrite_existing, log_errors) or_return;

	file, open_err := os.open(filepath, flags = os.File_Flags{.Write, .Create, .Trunc});

	if open_err != os.ERROR_NONE {
		if log_errors do log.errorf("IriAsset: Failed to open file for writing with error code: {}, path: {}", filepath);
		return false;
	}

	defer if !ok {
		try_delete_file(filepath, log_errors);
	}
	defer os.close(file);


	write_common_header_and_alias_to_file(file, filepath, AssetType.FontAtlas, asset_font.asset_id, asset_font.asset_alias, log_errors) or_return;

	// Font Atlas Header
	font_hdr : AssetFontAtlasHeader_v1; 
	{
		font_hdr.info = asset_font.info;
		font_hdr.num_rune_codepoints = asset_font.num_rune_codepoints;
		font_hdr.use_nearest_neighbour_filtering = cast(b8)asset_font.use_nearest_neighbour_filtering

		written_bytes , write_err := os.write_ptr(file, &font_hdr, size_of(font_hdr));
		check_write_error(write_err, filepath, log_errors) or_return;
	}

	num_codepoints : int = cast(int)asset_font.num_rune_codepoints;

	// rune codepoints array
	{
		byte_size : int = num_codepoints * size_of(rune);

		buf_written_bytes , buf_write_err := os.write_ptr(file, &asset_font.rune_codepoints[0], byte_size);
		check_write_error(buf_write_err, filepath, log_errors) or_return;
	}

	// rune info array
	{
		byte_size : int = num_codepoints * size_of(iricom.FontAtlasRuneInfo);

		buf_written_bytes , buf_write_err := os.write_ptr(file, &asset_font.rune_info[0], byte_size);
		check_write_error(buf_write_err, filepath, log_errors) or_return;
	}

	// Atlas Pixel data
	{
		num_pixels : int = cast(int)asset_font.info.atlas_width * cast(int)asset_font.info.atlas_height;
		byte_size  : int = num_pixels * size_of(u8);

		buf_written_bytes , buf_write_err := os.write_ptr(file, &asset_font.atlas_pixels[0], byte_size);
		check_write_error(buf_write_err, filepath, log_errors) or_return;
	}
	
	return true;
}