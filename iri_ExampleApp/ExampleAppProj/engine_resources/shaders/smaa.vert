#version 450 core


// Output Vertex Data
layout (location = 0) out vertex_data {
	vec2 uv;
	vec2 pixcoord;
	vec4 offsets[3];
} vert_data;


//Static Screen Quad Vertex buffer
const float vertex_buffer[12] = {
	// pos.xy, pos.xy, pos.xy ... 
    // triangle 1
    -1.0f, -1.0f,
     1.0f,  1.0f,
    -1.0f,  1.0f,
    // triangle 2
    -1.0f, -1.0f,
     1.0f, -1.0f,
     1.0f,  1.0f
 };

// Uniform buffer
layout(set=1, binding=0) uniform edge_detection_ubo {
	vec4 _input_dimentions;  // zw = input_texture_dimentions,  xy = 1.0 / input_texture_dimentions
};

#define SMAA_GLSL_4
#define SMAA_INCLUDE_VS 1
#define SMAA_INCLUDE_PS 0
#define SMAA_RT_METRICS _input_dimentions
#include "../shader_lib/vendor/smaa/SMAA.hlsl"

void main() {

	// The vertex of the screenquad we are currently processing.
	// a screenquad has 6 vertecies.
	const uint vertex = gl_VertexIndex % 6;

    // for a quad we do a trick here and just grab the vertex data inside the shader directly
   	const vec2 vert_pos = vec2(vertex_buffer[vertex * 2], vertex_buffer[vertex * 2 + 1]);
   

	// Flip y axis and Map from -1..1 to 0..1 range 
	// equivalent to: vert_pos.xy * vec2(1.0f, -1.0f) / 2.0f + 0.5f
	vert_data.uv = vert_pos.xy * vec2(0.5f, -0.5f) + 0.5f; 

	// Assign Vertex Data
	gl_Position = vec4(vert_pos.xy, 0.0f , 1.0f);

	#ifdef SMAA_PASS_EDGE_DETECTION
		SMAAEdgeDetectionVS(vert_data.uv, vert_data.offsets);
	#endif

	#ifdef SMAA_PASS_BLEND_WEIGHT
		SMAABlendingWeightCalculationVS(vert_data.uv,vert_data.pixcoord,vert_data.offsets);
	#endif

	#ifdef SMAA_PASS_NEIGHBORHOOD_BLEND
		SMAANeighborhoodBlendingVS(vert_data.uv, vert_data.offsets[0]);
	#endif
}