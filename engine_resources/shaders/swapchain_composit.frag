#version 450 core

#include "../shader_lib/color.glsl"


// Vertex Input Data
layout (location = 0) in vertex_data {
	vec2 uv;
} vert_data;


layout(set=2, binding=0) uniform sampler2D _scene_input_color_target;
layout(set=2, binding=1) uniform sampler2D _debug_ui_tex;


// Uniform buffer
layout(set=3, binding=0) uniform swap_composit_ubo {
	uint _convert_to_srgb;
    uint _convert_scene_to_linear_on_load;
    uint _padding1;
    uint _padding2;
};

layout (location=0) out vec4 frag_color;

void main() {


	vec4 scene = texture(_scene_input_color_target, vert_data.uv);

    // @Note: If scene texture is a _SRGB texture we dont need to convert to linear on load 
    // if we are using SMAA pass the input is a _UNORM and already contaion SRGB so we convert to linear 
    // on load first and than decide again for the swapchain texture if we need to do manual convertion back to srgb space.
    
    if (_convert_scene_to_linear_on_load == 1) {
        scene.rgb = srgb_to_linear(scene.rgb);
    }

    vec4 ui = texture(_debug_ui_tex, vert_data.uv);

    vec3 color = mix(scene.rgb, ui.rgb, ui.a);

    // if the swapchain texture format is just _UNORM we have to explicitly convert to srgb manually
    // if swapchain format is _SRGB the GPU will do this convertion for us.
    if(_convert_to_srgb == 1){
    	color.rgb = linear_to_srgb(color.rgb);
    }

	frag_color = vec4(color.rgb,1.0f);
}