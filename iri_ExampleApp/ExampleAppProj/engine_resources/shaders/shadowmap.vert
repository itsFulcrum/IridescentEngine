#version 450 core

// Vertex Attribute Data
layout (location=0) in vec3 a_pos;

#define RES_MATRIX_BUFFER_SET 0
#define RES_MATRIX_BUFFER_BIND 0
#include "../shader_lib/resources/resource_matrix_buffer.glsl"

#define RES_SHADOWINFO_BUFFER_SET 0
#define RES_SHADOWINFO_BUFFER_BIND 1
#include "../shader_lib/resources/resource_shadowmap_info_buffer.glsl"

layout(set=1, binding=0) uniform draw_instance_vertex_ubo {
	uint drawable_index;
	uint shadowmap_info_index;
	uint padding2;
	uint padding3;
} _draw_inst;

void main() {

	gl_Position = _shadowmap_buffer.infos[_draw_inst.shadowmap_info_index].view_proj *  vec4(_matrix_buffer.data[_draw_inst.drawable_index] * vec4(a_pos.xyz, 1.0f));
}