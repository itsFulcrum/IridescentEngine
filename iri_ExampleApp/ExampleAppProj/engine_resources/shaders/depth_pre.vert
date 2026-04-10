#version 450 core

// Vertex Attribute Data
layout (location=0) in vec3 a_pos;

// in SDL GPU uniform buffers in vertex shader must be bound to 'set=1' in fragment shader it is 'set=3'
// https://wiki.libsdl.org/SDL3/SDL_CreateGPUShader

// For vertex shaders:
// set 0: Sampled textures, followed by storage textures, followed by storage buffers
// set 1: Uniform buffers

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

void main() {

	//vec4 position_ws = _mesh_ubo.model_mat * vec4(a_pos.xyz, 1.0f);

	vec4 position_ws = _matrix_buffer.data[_draw_inst.drawable_index] * vec4(a_pos.xyz, 1.0f);


	vec4 position_cs = _global_vertex.view_proj_mat * vec4(position_ws.xyz, 1.0f);

	gl_Position = position_cs;
}