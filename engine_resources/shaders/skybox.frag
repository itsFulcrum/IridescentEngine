#version 450 core

#include 		"../shader_lib/mathy.glsl"
#include 		"../shader_lib/color.glsl"
#include 		"../shader_lib/skybox.glsl"

// Vertex Input Data
layout (location = 0) in vertex_data {
	vec3 position_os;
} vert_data;


layout (set=2, binding=0) uniform samplerCube _skybox_cubemap;

layout (std140, set=2, binding = 1) readonly buffer global_fragment {
    vec3 camera_pos_ws;
	float time_sec;

	vec3 camera_dir_ws;
	float near_plane;
	
	uvec2 frame_size;
	float far_plane;
	float cascade_frust_split_1;
	
	float cascade_frust_split_2;
	float cascade_frust_split_3;
	float camera_exposure;

	float padding7;
} _global;



layout (std140, set=2, binding = 2) readonly buffer skybox_buffer {
    SkyboxData data; // defined in skybox.glsl
} skybox;

layout (location=0) out vec4 frag_color;


vec4 sample_octahedral_map_interpolated(sampler2D tex, vec3 direction, uint oct_texel_size) {

    vec2 encode = oct_encode(direction);// * float(sqrt_num_probe_samples) - 0.5f;
    vec2 oct_texel_f = encode * float(oct_texel_size) - 0.5f; // map to range of subdivided octahedral texels

    //NOTE: for some reason this floor here is important and we cant just cast to integer
    // I belive because oct_texel_f may be negative with the -0.5 and cause oct_wrapping error or something
    vec2 f = floor(oct_texel_f); 
    ivec2 corner = ivec2(f);
    vec2 fraction = oct_texel_f - f;

    vec4 oct_weights;
    oct_weights.x = (1 - fraction.x) * (1 - fraction.y);
    oct_weights.y = (    fraction.x) * (1 - fraction.y);
    oct_weights.z = (1 - fraction.x) * (    fraction.y);
    oct_weights.w = (    fraction.x) * (    fraction.y);

    ivec2 texel_size = ivec2(oct_texel_size,oct_texel_size);

    ivec2 oct_texel_0 = oct_wrap_texel_coordinates(corner + ivec2(0,0), texel_size);
    ivec2 oct_texel_1 = oct_wrap_texel_coordinates(corner + ivec2(1,0), texel_size);
    ivec2 oct_texel_2 = oct_wrap_texel_coordinates(corner + ivec2(0,1), texel_size);
    ivec2 oct_texel_3 = oct_wrap_texel_coordinates(corner + ivec2(1,1), texel_size);
    
    vec4 col = vec4(0);
    col += texelFetch(tex, ivec2(oct_texel_0), 0) * oct_weights.x;
    col += texelFetch(tex, ivec2(oct_texel_1), 0) * oct_weights.y;
    col += texelFetch(tex, ivec2(oct_texel_2), 0) * oct_weights.z;
    col += texelFetch(tex, ivec2(oct_texel_3), 0) * oct_weights.w;

    return col;
}

void main() {

	frag_color = vec4(0.0f,0.0f,0.0f,1.0f);


	float r_radian = radians(skybox.data.rotation);
	mat3 rot_mat = rotate_mat3_Y(r_radian);
	vec3 sample_dir = rot_mat * normalize(vert_data.position_os);


	vec3 sky_procedual_col = skybox_sample_procedual(sample_dir, skybox.data.color_zenith, skybox.data.color_horizon, skybox.data.color_nadir);
	vec3 sky_cubemap_col   = textureLod(_skybox_cubemap, sample_dir,0.0f).rgb;

	vec3 sky_col = mix(sky_procedual_col, sky_cubemap_col, skybox.data.use_cubemap);
	sky_col = sky_col * _global.camera_exposure * pow(2, skybox.data.exposure);

	frag_color.rgb = sky_col.rgb;
}