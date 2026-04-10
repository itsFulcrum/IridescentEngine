#version 450 core

struct UIData{
	vec4 color;
	vec4 vert_offset_scale;
	vec4 uv_offset_scale;
	float use_atlas; // 0 if not using atlas 1 if using atlas.
	float padding1;
	float padding2;
	float padding3;
};


// in SDL GPU storage buffers in vertex shader must be bound to 'set=0' in fragment shader it is 'set=2'
// https://wiki.libsdl.org/SDL3/SDL_CreateGPUShader
layout (std140, set=0, binding=0) readonly buffer _ui_data_buffer {
    UIData _ui_data[];
};


// Output Vertex Data
layout (location = 0) out vertex_data {
	vec4 color;
	vec2 uv;
	float use_atlas; // a value 0..1 to lerp how much atlas opacity to apply.
} vert_data;


//Static Screen Quad Vertex buffer
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

 // const float vertex_buffer[12] = {
// 	// pos.xy, pos.xy, pos.xy ... 
 //    // triangle 1
 //    -1.0, -1.0,
 //    -1.0,  1.0,
 //     1.0,  1.0,
 //    // triangle 2
 //    -1.0, -1.0,
 //     1.0,  1.0,
 //     1.0, -1.0
 // };

void main() {


	// We Know we issure 6 vertecies per quad instance so integer devision by 6 can give us the instance id.
	const uint instance_id = gl_VertexIndex / 6;
	
	// the vertex of the screenquad we are currently processing.
	// a screenquad has 6 vertecies.
	const uint vertex = gl_VertexIndex % 6;

	UIData ui_instance_data = _ui_data[instance_id];

	const vec2 vert_offset 	= ui_instance_data.vert_offset_scale.xy;
	const vec2 vert_scale  	= ui_instance_data.vert_offset_scale.zw;

    // for a quad we do a trick here and just grab the vertex data inside the sahder directly
   	const vec2 vert_pos_os = vec2(vertex_buffer[vertex * 2], vertex_buffer[vertex * 2 + 1]);
   

	// Map from -1..1 to 0..1 range
	vec2 pos = vert_pos_os.xy / 2 + 0.5f;

	// Flip Horizontal because our transformations assumed fliped y
	pos.y = 1.0f - pos.y; 

	// transform to correct screen pos
	pos *= vert_scale;
	pos += vert_offset;

	// map back to -1..1 NDC
	pos = pos * 2 - 1;
	// Flip back horizontal
	pos.y *= -1;


	// Compute UV Coords in the atlas texture
	const vec2 uv_offset 	= ui_instance_data.uv_offset_scale.xy;
	const vec2 uv_scale 	= ui_instance_data.uv_offset_scale.zw;
	
	// Since a screenquad is defined in -1..1 space we can just map it to 0..1 space to get uv coords
   	vec2 uv = vert_pos_os * 0.5f + 0.5f; 

   	// Flip horrizontal because the atlas texture is upside down.
   	uv.y = 1.0f - uv.y;

   	// transform to the pos in the atlas
	uv *= uv_scale;
	uv += uv_offset;

	// Assign Vertex Data
	gl_Position = vec4(pos.xy, 0 , 1.0f);

	vert_data.color = ui_instance_data.color;
	vert_data.uv = uv;
	vert_data.use_atlas = ui_instance_data.use_atlas;
}