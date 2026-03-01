#version 450 core

#include "../shader_lib/color.glsl"
#include "../shader_lib/tonemap.glsl"

// Vertex Input Data
layout (location = 0) in vertex_data {
	vec2 uv;
} vert_data;

layout(set=2, binding=0) uniform sampler2D _render_tex;

// Uniform buffer
layout(set=3, binding=0) uniform post_settings_ubo {
	float exposure;
	uint tone_map_mode;
	bool convert_to_srgb;
	bool padding1;
	bool padding2;
	bool padding3;
} _post_settings;

// Fragment output color
layout (location=0) out vec4 frag_color;

void main() {

	vec3 color = texture(_render_tex, vert_data.uv).rgb;

	color.rgb = apply_exposure(color.rgb, _post_settings.exposure);
	//color.rgb = apply_exposure(color.rgb, 0.0);

	color.rgb = tonemap_agx(color.rgb);
	//color.rgb = tonemap_aces(color.rgb);
	//color.rgb = tonemap_reinhard(color.rgb);
	//color.rgb = tonemap_filmic(color.rgb);
	//color.rgb = tonemap_clamp(color.rgb);

	// @Note: do not convert to srgb here, we are rendering to a R8G8B8A8_UNORM_SRGB rendertarget
	// so the gpu will do this convertion for us!
	frag_color = vec4(color.rgb,1.0f);
}