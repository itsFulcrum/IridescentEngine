#version 450 core

#include "../shader_lib/color.glsl"

// Vertex Input Data
layout (location = 0) in vertex_data {
	vec2 uv;
	vec2 pixcoord;
    vec4 offsets[3];
} vert_data;


// main render color target wich should be a _UNORM_SRGB color target from post process stage.
// so gpu wil convert to linear on load but for this stage of SMAA we want to read in srgb space
// so below we overwrite the sampling function and convert to sRGB manually
layout(set=2, binding=0) uniform sampler2D _input_color_target_tex; 
layout(set=2, binding=1) uniform sampler2D _blend_target_tex; // render target of previous blend weight pass

// Uniform buffer
layout(set=3, binding=0) uniform edge_detection_ubo {
	vec4 _input_dimentions; // zw = input_texture_dimentions,  xy = 1.0 / input_texture_dimentions
};


vec4 sample_input_texture_srgb(sampler2D tex, vec2 texcoord){
	vec4 col = textureLod(tex, texcoord, 0.0f);

	return vec4(linear_to_srgb(col.rgb), col.a);	
}


#define SMAASampleLevelZero_ColorTex(tex, coord) sample_input_texture_srgb(tex, coord);

#define SMAA_GLSL_4
#define SMAA_PRESET_HIGH
#define SMAA_INCLUDE_VS 0
#define SMAA_INCLUDE_PS 1
#define SMAA_RT_METRICS _input_dimentions
#include "../shader_lib/vendor/smaa/SMAA.hlsl"

layout (location=0) out vec4 frag_color;

void main() {

	frag_color = SMAANeighborhoodBlendingPS(vert_data.uv, vert_data.offsets[0],  _input_color_target_tex, _blend_target_tex );
}