#version 450 core

// Vertex Attribute Data
layout (location=0) in vec3 a_pos;

#ifdef VERT_LAYOUT_MINIMAL
layout (location=1) in vec4 a_normal_tangent; // oct encoded.
layout (location=2) in vec2 a_texcoord_0;
#endif 

#ifdef VERT_LAYOUT_STANDARD
layout (location=1) in vec4 a_normal_tangent; // oct encoded.
layout (location=2) in vec4 a_color_0;
layout (location=3) in vec2 a_texcoord_0;
#endif 

#ifdef VERT_LAYOUT_EXTENDED
layout (location=1) in vec4 a_normal_tangent; // oct encoded.
layout (location=2) in vec4 a_color_0;
layout (location=3) in vec4 a_color_1;
layout (location=4) in vec2 a_texcoord_0;
layout (location=5) in vec2 a_texcoord_1;
#endif

#include "../shader_lib/mathy.glsl"

// Uniform Data
// in SDL GPU uniform buffers in vertex shader must be bound to 'set=1' in fragment shader it is 'set=3'
// https://wiki.libsdl.org/SDL3/SDL_CreateGPUShader

#include "../shader_lib/resources/resource_matrix_buffer.glsl"

layout(set=1,binding=0) uniform global_vertex_ubo {
	mat4 view_mat;
	mat4 proj_mat;
	mat4 view_proj_mat;
} _global_vertex;

layout(set=1,binding=1) uniform draw_instance_vertex_ubo {
	uint drawable_index;
	uint padding1;
	uint padding2;
	uint padding3;
} _draw_inst;

// Output Vertex Data
layout (location = 0) out vertex_data {	
	vec3 position_ws;
	vec3 normal_ws;
	vec4 color_0;
	vec4 color_1;
	vec2 uv_0;
	vec2 uv_1;
	mat3 tangent_to_world_mat;
	mat3 tbn_mat;
} vert_data;

void main() {

	mat4 world_mat = _matrix_buffer.data[_draw_inst.drawable_index];

	vec4 position_ws = world_mat * vec4(a_pos.xyz, 1.0f);

	vec4 position_cs = _global_vertex.view_proj_mat * vec4(position_ws.xyz, 1.0f);

	gl_Position = position_cs;
	
	mat3 normal_mat = adjoint(mat3(world_mat));

	vec3 a_normal  = oct_decode(a_normal_tangent.xy);
	vec3 a_tangent = oct_decode(a_normal_tangent.zw);

	vec3 bitangent_os = cross(a_normal, a_tangent);

	vec3 tangent_ws   = normalize(vec3(normal_mat * a_tangent   ));
  	vec3 bitangent_ws = normalize(vec3(normal_mat * bitangent_os));
	vec3 normal_ws    = normalize(vec3(normal_mat * a_normal    ));
	

  	vert_data.tbn_mat = mat3(tangent_ws, bitangent_ws, normal_ws);
	vert_data.tangent_to_world_mat = adjoint(vert_data.tbn_mat);

	vert_data.position_ws = position_ws.xyz;
	vert_data.normal_ws = normal_ws;

	// TODO: pass viewspace pos seperatily or do shadowmap cascade sampling different..
	vert_data.color_0 = _global_vertex.view_mat  * vec4(position_ws.xyz, 1.0f);
	//vert_data.color_0 = a_color_0 ;
	vert_data.uv_0 = a_texcoord_0;
	
	#ifdef VERT_LAYOUT_STANDARD
		vert_data.uv_1    = vec2(0.0f);
		vert_data.color_0 = a_color_0;
		vert_data.color_1 = vec4(1.0f);
	#endif

	#ifdef VERT_LAYOUT_EXTENDED
		vert_data.uv_1    = a_texcoord_1;
		vert_data.color_0 = a_color_0;
		vert_data.color_1 = a_color_1;
	#endif
}