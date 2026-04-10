#version 450 core

layout(set=3, binding=0) uniform color_ubo {
	vec4 color;
} _mat;


layout (location=0) out vec4 frag_color;

void main() {
	frag_color = vec4(_mat.color.rgb, 1.0f);
}