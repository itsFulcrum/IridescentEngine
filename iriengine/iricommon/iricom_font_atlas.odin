package iricom


// Mesurements come from stb_truetype.packedchar, in the comment namespace 'tt' refers to 'stb_truetype'

FontAtlasRuneInfo :: struct {
	x_advance_px : f32,    // stb_truetype.packedchar.x_advance
	offset_px    : [2]f32, // tt.packedchar.xoff && tt.packedchar.yoff
	size_px      : [2]f32, // {tt.packedchar.xoff2 - tt.packedchar.xoff, tt.packedchar.yoff2 - tt.packedchar.yoff}

	// @Note: given a rectangle where top-left corner has uvs (0,0) and bottom right has (1,1). 
	// Can use this to calculate its uv in the atlas texture -> atlas_uv = rect_uv * uv_scale + uv_offset.
	uv_offset : [2]f32,
	uv_scale  : [2]f32,
}


FontAtlasInfo :: struct {

	font_size_px : f32, // font_size in pixels this was created with.
    scale_factor : f32, // stb_truetype.ScaleForPixelHeight(font_info, pixel_height); (This is computed as: pixel_height / (ascent - descent) )

    // Comment from stb_truetype: GetFontVMetrics()
    // ascent is the coordinate above the baseline the font extends; 
    // descent is the coordinate below the baseline the font extends (i.e. it is typically negative) 
    // lineGap is the spacing between one row's descent and the next row's ascent... 
    // so you should advance the vertical position by "ascent - descent + lineGap" these are expressed in unscaled coordinates, 
    // so you must multiply by the scale factor for a given size
    ascent_px    : f32, // these are already multiplied by 'scale_factor'
    descent_px   : f32,
    line_gap_px  : f32,

	atlas_width  : u32,
	atlas_height : u32,
}

