#version 450 core


struct RectVertDrawData {
	vec2 position;  // pixel xy. // could also pack into 2 x u16
	float norm_z_depth;  // normalized z-index to range 0..1
	uint size_2u16; // width, height
	vec2 uv_offset;
	vec2 uv_scale;
};


#define RES_UI_VERT_BUFFER_SET  0
#define RES_UI_VERT_BUFFER_BIND 0

layout (std140, set=RES_UI_VERT_BUFFER_SET, binding=RES_UI_VERT_BUFFER_BIND) readonly buffer rect_vert_draw_data_buf {
    RectVertDrawData _rect_vert_data[];
};


layout(set=1, binding=0 ) uniform ui_global_vert_ubo {
	vec2 frame_size; 
	vec2 layout_dimentions; // width, height of the layout.
} global_ubo;


// Output Vertex Data
layout (location = 0) out vertex_data {
	vec2 uv;
	vec2 coord; // in pixel space.
	uint instance_id;
	float padding; // z index frag depth ? and instance draw everything ??
} vert_data;


//Static/GroupSharedMem - Screen Quad Vertex buffer
const float vertex_buffer[12] = {
	// pos.xy, pos.xy, pos.xy ... 
    // triangle 1
    -1.0, -1.0,
     1.0,  1.0,
    -1.0,  1.0,
    // triangle 2
    -1.0, -1.0,
     1.0, -1.0,
     1.0,  1.0
};

// Unpack 2u16 packed in one u32 and cast to float but dont normalize.
vec2 unpack_2u16_to_2f32(const uint bits){
	// if we think of it as a vector: [lsb,msb]
	// const float msb = float(bits&0xFFFFu);
	// const float lsb = float(bits>>16u);
	return vec2(float(bits&0xFFFFu), float(bits>>16u));
}

void main() {

	//RectVertDrawData rect_draw_data = _rect_vert_data[gl_InstanceIndex];

	vec2 size = unpack_2u16_to_2f32(_rect_vert_data[gl_InstanceIndex].size_2u16);
	const uint vertex_index = gl_VertexIndex % 6;

    // for a quad we do a trick here and just grab the vertex data inside the sahder directly
   	vec2 vertex = vec2(vertex_buffer[vertex_index * 2], vertex_buffer[vertex_index * 2 + 1]);   

	// Map from -1..1 to 0..1 range
	vertex = vertex * 0.5f + 0.5f;

	// to local pixel coordinates.
	vec2 local = vertex * size;
	// screen pixel coordinates.
	vec2 world = local + _rect_vert_data[gl_InstanceIndex].position;

	vec2 ndc = world.xy / vec2(global_ubo.frame_size.x, global_ubo.frame_size.y);
	ndc = ndc * 2.0 -1.0; // to range -1..1;
	ndc.y *= -1.0;

	// // Since a screenquad is defined in -1..1 space we can just map it to 0..1 space to get uv coords
   	vec2 norm_uv = vertex;
   	//norm_uv.y = 1.0 - norm_uv.y;
   	norm_uv *= _rect_vert_data[gl_InstanceIndex].uv_scale;
   	norm_uv += _rect_vert_data[gl_InstanceIndex].uv_offset;

	// Assign Vertex Data
	gl_Position = vec4(ndc, _rect_vert_data[gl_InstanceIndex].norm_z_depth , 1.0f);

	vert_data.uv          = norm_uv;
	vert_data.coord       = local;
	vert_data.instance_id = gl_InstanceIndex;
}

