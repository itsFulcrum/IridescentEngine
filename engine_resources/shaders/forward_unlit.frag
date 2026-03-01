#version 450 core

#include "../shader_lib/materials.glsl"

// Vertex Input Data
layout (location = 0) in vertex_data {
	vec3 position_ws;
	vec3 normal_ws;
	vec4 color_0;
	vec4 color_1;
	vec2 uv_0;
	vec2 uv_1;
	mat3 tangent_to_world_mat;
	mat3 tbn_mat;
} vert_data;

layout (std140, set=2, binding=0) readonly buffer global_fragment {
    vec3 camera_pos_ws;
	float time_sec;
	vec3 camera_dir_ws;
	float padding1;
	uvec2 frame_size;
	float padding2;
	float padding3;
	mat4  inv_view_proj_mat;
	mat4  main_light_view_proj_mat;
} _global;

layout (std140, set=2, binding=1) readonly buffer unlit_material_buffer {
    UnlitMaterial _unlit_materials[];
};

layout(set=3, binding=0) uniform mat_ubo {
	uint mat_index;
} _mat_ubo;


layout (location=0) out vec4 frag_color;

void main() {

	frag_color = vec4(0.0f,0.0f,0.0f,1.0f);
	
	UnlitMaterial mat = _unlit_materials[_mat_ubo.mat_index];

	frag_color.rgb = vert_data.color_0.rgb;
}