#version 450 core


layout (location=0) out vec4 frag_color;

void main() {

	frag_color = vec4(gl_FragCoord.z, 0.0f, 0.0f, 0.0f);

	// Variance Shadow maps would be this..
	
	// float depth = gl_FragCoord.z;
	
	// // Fixes a little bit acne when having very shallow angles light direction angles.
	// vec2 dxy = vec2(dFdx(depth), dFdy(depth));
	// float moment_2 = depth * depth  + 0.25f * dot(dxy, dxy);
	
	// frag_color = vec4(depth, moment_2, 0.0f);
}