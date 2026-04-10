#version 450 core
// Vertex Attribute Data
layout (location=0) in vec3 a_pos;
// layout (location=1) in vec3 a_normal;
// layout (location=2) in vec3 a_tangent;
// layout (location=3) in vec4 a_color_0;
// layout (location=4) in vec4 a_color_1;
// layout (location=5) in vec2 a_texcoord_0;
// layout (location=6) in vec2 a_texcoord_1;


// Uniform Data
// in SDL GPU uniform buffers in vertex shader must be bound to 'set=1' in fragment shader it is 'set=3'
// https://wiki.libsdl.org/SDL3/SDL_CreateGPUShader
layout(set=1,binding=0) uniform global_vertex_ubo {
	mat4 view_mat;
	mat4 proj_mat;
	mat4 view_proj_mat;
} global_ubo;

// layout(set=1,binding=1) uniform mesh_vertex_ubo {
// 	mat4 model_mat;
// } mesh_ubo;


// Output Vertex Data
layout (location = 0) out vertex_data {
	
	vec3 position_os;
} vert_data;

void main() {

	vec4 pos_cs = global_ubo.proj_mat * mat4(mat3(global_ubo.view_mat)) * vec4(a_pos.xyz, 1.0f);

	gl_Position = pos_cs.xyww;
	
	vert_data.position_os = a_pos.xyz;
}