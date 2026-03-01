#version 450 core

// Vertex Input Data
layout (location = 0) in vertex_data {
	vec4 color;
	vec2 uv;
	float use_atlas; // value 0..1 - 1 if rectangle should use atlas texture alpha , 0 otherwise
} vert_data;


layout(set=2, binding=0) uniform sampler2D _atlas_tex;

// Fragment output color
layout (location=0) out vec4 frag_color;

void main() {

	frag_color = vec4(0.0f,0.0f,0.0f,1.0f);
	
	frag_color.rgb = vert_data.color.rgb;


	float atlas_alpha = texture(_atlas_tex, vert_data.uv).a;


	float alpha = mix( 1.0f, atlas_alpha, vert_data.use_atlas);

	frag_color.a = alpha;
}