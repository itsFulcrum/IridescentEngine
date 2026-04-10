#version 450 core


// Vertex Input Data
layout (location = 0) in vertex_data {
	vec2 uv;
	vec2 pixcoord;
    vec4 offsets[3];
} vert_data;


layout(set=2, binding=0) uniform sampler2D _edges_target_tex; // render target of previous edge detection pass
layout(set=2, binding=1) uniform sampler2D _area_tex;
layout(set=2, binding=2) uniform sampler2D _search_tex;


// Uniform buffer
layout(set=3, binding=0) uniform edge_detection_ubo {
	vec4 _input_dimentions; // zw = input_texture_dimentions,  xy = 1.0 / input_texture_dimentions
};


#define SMAA_GLSL_4
#define SMAA_PRESET_HIGH
#define SMAA_INCLUDE_VS 0
#define SMAA_INCLUDE_PS 1
#define SMAA_RT_METRICS _input_dimentions
#include "../shader_lib/vendor/smaa/SMAA.hlsl"

layout (location=0) out vec4 frag_color;

void main() {

	vec4 subsampleIndices = vec4(0.0f); // not sure exactly what to pass here if no MSAA multisampling

	frag_color =  SMAABlendingWeightCalculationPS(vert_data.uv, vert_data.pixcoord, vert_data.offsets, _edges_target_tex, _area_tex, _search_tex, subsampleIndices);
}