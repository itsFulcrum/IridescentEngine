#version 450 core
// Vertex Input Data
layout (location = 0) in vertex_data {
	vec2 uv;
	vec2 rect_coord;
	flat uint instance_id;
	float padding;
} vert_data;

// Font atlas in case of rendering Text, Image in case of rendering images. But Images are not implemented yet.
layout(set=2, binding=0) uniform sampler2D _tex;


struct RectFragDrawData {
 	vec2 rect_size; // We could bitback this too if we need and extra value but for now we dont.
 	uint mode;      // Mode 0 = NonTexturedRect, Mode 1 = Text, Mode 2 = Textured Rect (unimplemented)
 	uint color_4u8; // bitpacked color 4xu8.

 	uint corner_radius_top; 		// bit-packed: 2 x u16 - msb TopLeft, lsb - TopRight.
 	uint corner_radius_bot; 		// bit-packed: 2 x u16 - msb BotLeft, lsb - BotRight.
 	uint border_width_left_right; 	// bit-packed: 2 x u16 - msb Left, lsb - Right.
 	uint border_width_top_bot;		// bit-packed: 2 x u16 - msb Top , lsb - Bot.
};

#define RES_UI_FRAG_BUFFER_SET  2
#define RES_UI_FRAG_BUFFER_BIND 1

layout (std140, set=RES_UI_FRAG_BUFFER_SET, binding=RES_UI_FRAG_BUFFER_BIND) readonly buffer rect_frag_draw_data_buf {
    RectFragDrawData _rect_frag_data[];
};

// Fragment output color
layout (location=0) out vec4 color;


float sdf_rect(vec2 point, const vec4 rect, vec4 r) {
	// rect.xy = top-left corner, rect.zw = bot-right-corner
	// r.x = roundedness top-left
	// r.y = roundedness top-right
	// r.z = roundedness bot-left
	// r.w = roundedness bot-right
    
    const vec2 bounds_half = rect.zw * 0.5;
	    
    point = point - rect.xy - bounds_half;
    
    // decide which corner radius we should use right now.
    r.xy = (point.x>0.0f) ? r.yw : r.xz;
    r.x  = (point.y>0.0f) ? r.y  : r.x;

    vec2 q = abs(point) - bounds_half + vec2(r.x);
    
    float res = min(max(q.x,q.y), 0.0) + length(max(q.xy, vec2(0.0))) - r.x;
    return 1.0 - max(0.0, min(1.0, res));
}

// Unpack 2u16 packed in one u32 and cast to float but dont normalize.
vec2 unpack_2u16_to_2f32(const uint bits){
	// const float msb = float(bits&0xFFFFu);
	// const float lsb = float(bits>>16u);
	return vec2(float(bits&0xFFFFu), float(bits>>16u));
}

void main() {

	
	//RectFragDrawData frag_data = _rect_frag_data[vert_data.instance_id];l

	color = unpackUnorm4x8(_rect_frag_data[vert_data.instance_id].color_4u8);

	uint mode = _rect_frag_data[vert_data.instance_id].mode;

	if (mode == 1) {
		// Text Mode
		vec4 atlas = textureLod(_tex, vert_data.uv, 0);
		//color.a *= textureLod(_tex, vert_data.uv, 0).r;

		// - Not sure yet if i want to use mipmapping ?
		//vec4 atlas = texture(_tex, vert_data.uv);
		color.a *= smoothstep(0.1, 0.7, atlas.r);

	} else {

 		//unpack 2xu16 from u32 and cast to floating point. We _Dont_ wan to normalize.
 		vec2 top = unpack_2u16_to_2f32(_rect_frag_data[vert_data.instance_id].corner_radius_top);
 		vec2 bot = unpack_2u16_to_2f32(_rect_frag_data[vert_data.instance_id].corner_radius_bot);
 		vec4 corner_radius = vec4(top, bot);

		// Rectangle
		color.a *= sdf_rect(vert_data.rect_coord, vec4(0,0, _rect_frag_data[vert_data.instance_id].rect_size.xy), corner_radius);
		

		// Bordered Rectangle.
		// if we are drawing a border rectangle.
		// produce a mask for the inner rectangle aswell.		
		if (_rect_frag_data[vert_data.instance_id].border_width_left_right + _rect_frag_data[vert_data.instance_id].border_width_top_bot > 0) {

			//unpack 2xu16 from u32 and cast to floating point. We _Dont_ wan to normalize.
	 		vec2 left_right = unpack_2u16_to_2f32(_rect_frag_data[vert_data.instance_id].border_width_left_right);
	 		vec2 top_bottom = unpack_2u16_to_2f32(_rect_frag_data[vert_data.instance_id].border_width_top_bot);
	 		vec4 border_widths = vec4(left_right, top_bottom);

			vec4 inner_rect = vec4(border_widths.xz, _rect_frag_data[vert_data.instance_id].rect_size.xy - border_widths.yw - border_widths.xz);
			color.a *= 1.0 - sdf_rect(vert_data.rect_coord,  inner_rect, corner_radius);
		}
	}
	
	// cheap linear to srgb
	color.rgb = pow(color.rgb, vec3(2.2f));
}