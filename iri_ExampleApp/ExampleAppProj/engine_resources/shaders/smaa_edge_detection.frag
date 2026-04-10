#version 450 core

#include "../shader_lib/color.glsl"

// Vertex Input Data
layout (location = 0) in vertex_data {
    vec2 uv;
    vec2 pixcoord;
    vec4 offsets[3];
} vert_data;


layout(set=2, binding=0) uniform sampler2D _input_tex;


// Uniform buffer
layout(set=3, binding=0) uniform edge_detection_ubo {
	vec4 _input_dimentions; // zw = input_texture_dimentions,  xy = 1.0 / input_texture_dimentions
};

//#define SMAA_THRESHOLD 0.01
//#define SMAA_MAX_SEARCH_STEPS 16
//#define SMAA_MAX_SEARCH_STEPS_DIAG 8
//#define SMAA_CORNER_ROUNDING 25

vec4 sample_input_texture_srgb(sampler2D tex, vec2 texcoord){
    vec4 col = textureLod(tex, texcoord, 0.0f);

    //return vec4(linear_to_srgb(col.rgb), col.a);
    return vec4(col.rgb, col.a);
}

#define SMAASamplePoint(tex, coord) sample_input_texture_srgb(tex, coord)

#define SMAA_GLSL_4
#define SMAA_PRESET_ULTRA
#define SMAA_INCLUDE_VS 0
#define SMAA_INCLUDE_PS 1
#define SMAA_RT_METRICS _input_dimentions
#include "../shader_lib/vendor/smaa/SMAA.hlsl"

layout (location=0) out vec4 frag_color;

void main() {

    frag_color = vec4(0.0f);

    frag_color.rg = SMAALumaEdgeDetectionPS(vert_data.uv, vert_data.offsets, _input_tex);
    //frag_color.rg = SMAAColorEdgeDetectionPS(vert_data.uv, vert_data.offsets, _input_tex);
}