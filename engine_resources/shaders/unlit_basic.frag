#version 450 core


// Vertex Input Data
layout (location = 0) in vertex_data {
	vec3 position_os;
	float padding1;
	vec3 position_ws;
	float padding2;
} vert_data;

layout(set=3, binding=0) uniform mat_ubo {
	vec4 color;
} _mat_ubo;


layout (location=0) out vec4 frag_color;

void main() {

	frag_color = _mat_ubo.color;
}