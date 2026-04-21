#version 450 core

#include 		"../shader_lib/mathy.glsl"
#include 		"../shader_lib/color.glsl"
#include 		"../shader_lib/skybox.glsl"

#include "../shader_lib/noise.glsl"
#include "../shader_lib/noise/noise_voronoi.glsl"
#include "../shader_lib/noise/noise_perlin.glsl"

// Vertex Input Data
layout (location = 0) in vertex_data {
	vec3 position_os;
} vert_data;


layout (set=2, binding=0) uniform samplerCube _skybox_cubemap;

#define RES_GLOBAL_FRAG_BUFFER_SET 2
#define RES_GLOBAL_FRAG_BUFFER_BIND 1
#include "../shader_lib/resources/resource_global_fragment_buffer.glsl"


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


vec3 skybox_sample_procedual_universe(vec3 dir, vec3 zenith, vec3 horizon, vec3 nadir){

	zenith  = pow(zenith, vec3(2.2f)); // srgb to linear
	horizon = pow(horizon,vec3(2.2f)); // srgb to linear
	nadir   = pow(nadir,  vec3(2.2f)); // srgb to linear

	vec3 color = vec3(0);
	float up_dot = dot(dir.xyz, vec3(0,1,0));

	float dot_abs = abs(up_dot);

	int octaves = 8;
	float perlin = noise_perlin_3D(dir * 10, octaves, 0.5, 2.0 , 2);

	perlin = (perlin + 1) / 2;
	



	float vertical = dir.y * 0.5 + 0.5; // from -1..1 to 0..1; 
	
	float lerp = clamp( pow(  abs(up_dot), 0.7 )  , 0,1) - (perlin * 0.2) * perlin;
	vec3 col = mix(nadir, zenith, vertical);
	col = mix(col, horizon, 1-lerp);
	color =  col;


	float t = _global.time_sec;

	float tslow = _global.time_sec * 0.15;
	float sin_time = sin(_global.time_sec);

	vec3 rot_dir = rotate_mat3_Y(tslow) * dir;


	float rot_noise = noise_dot_3D(rot_dir * 20);
	
	//return vec3(rot_noise);

	//float dot_noise1 = noise_dot_3D((dir - vec3(12.233, 23.398, 7.34)) * 25.3);
	float vor_noise = noise_voronoi_3D(dir * 60).x;



	//dot_noise *= st;

	float inv_voronoi = 1.02 - vor_noise;

	float v = clamp((inv_voronoi * inv_voronoi - 0.77) * 2.0, 0.0,1.0);

	float stars_emission = 100;
	float stars = pow(v, 4) * stars_emission * (1-perlin ) * rot_noise;// + dot_noise;





	float noiset = (perlin + 0.8) - (rot_noise * 0.8);
	noiset = max(0.0,noiset);

	vec3 sun_col = vec3(1.0,0.6,0.0);
	sun_col = mix(sun_col, vec3(1.0,0.5,0.0), noiset);




	float sun_theta = 0.5;
	float sun_phi = 0.5;

	vec3 sun_dir = spherical_to_cartesian(sun_theta, sun_phi);

	float sun_dot = dot(sun_dir, dir);

	sun_dot = max(0.0, inverse_lerp(0.95, 1.0, sun_dot));

	float sun_dot1 = pow(sun_dot, 8);
	vec3 dnoise_in = vec3(1.0) * sun_dot * inverse_lerp(-1, 1, sin(tslow)) * 10 - perlin;
	float sun_noise = noise_dot_3D( dnoise_in) * 2;
	float shine_sub_lerp = pow(sun_noise, 1 );
	float shine_sub = mix(0.0,0.02, shine_sub_lerp) ;

	float sun_main_strength = mix(1, 2, noiset);
	vec3 sun_main = sun_col * saturate(sun_dot1 - 0.2 - shine_sub) * sun_main_strength ; 
		


	//return vec3(shine_sub_lerp);
		

	vec3 sun_shine = sun_col * saturate(sun_dot1 - shine_sub) * 0.04;



	float sun_strength = 100.0f;

	vec3 sun = (sun_main + sun_shine) * sun_strength;

	color += sun;

	color += vec3(stars);


	return color;
}

void main() {

	frag_color = vec4(0.0f,0.0f,0.0f,1.0f);

	float r_radian = radians(skybox.data.rotation);
	mat3 rot_mat = rotate_mat3_Y(r_radian);
	vec3 sample_dir = rot_mat * normalize(vert_data.position_os);


	vec3 sky_procedual_col = skybox_sample_procedual_universe(sample_dir, skybox.data.color_zenith, skybox.data.color_horizon, skybox.data.color_nadir);
	vec3 sky_cubemap_col   = textureLod(_skybox_cubemap, sample_dir,0.0f).rgb;

	vec3 sky_col = mix(sky_procedual_col, sky_cubemap_col, skybox.data.use_cubemap);
	sky_col = sky_col * _global.camera_exposure * pow(2, skybox.data.exposure);

	frag_color.rgb = sky_col.rgb;
}