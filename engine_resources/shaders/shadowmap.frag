#version 450 core

layout (location=0) out vec4 frag_color;

void main() {

	frag_color = vec4(gl_FragCoord.z, 0.0f, 0.0f, 0.0f);
}