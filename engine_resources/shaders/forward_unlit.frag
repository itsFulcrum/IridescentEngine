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


#define RES_GLOBAL_FRAG_BUFFER_SET 2
#define RES_GLOBAL_FRAG_BUFFER_BIND 0
#include "../shader_lib/resources/resource_global_fragment_buffer.glsl"

#define RES_UNLIT_BUF_SET 2
#define RES_UNLIT_BUF_BIND 1
#include "../shader_lib/resources/resource_unlit_material_buffer.glsl"


layout(set=3, binding=0) uniform mat_ubo {
	uint mat_index;
} _mat_ubo;


layout (location=0) out vec4 frag_color;

void main() {

	frag_color = vec4(0.0f,0.0f,0.0f,1.0f);
	
	UnlitMaterial mat = _unlit_materials[_mat_ubo.mat_index];

	frag_color.rgb = mat.albedo_color.rgb;
}