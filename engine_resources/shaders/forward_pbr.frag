#version 450 core

#include "../shader_lib/materials.glsl"
#include "../shader_lib/light.glsl"
#include "../shader_lib/lighting.glsl"
#include "../shader_lib/skybox.glsl"
#include "../shader_lib/color.glsl"
#include "../shader_lib/mathy.glsl"
#include "../shader_lib/noise.glsl"

// Vertex Input Data
layout (location = 0) in vertex_data {
	vec3 position_ws;
	vec3 normal_ws;
	vec4 color_0;
	vec4 color_1;
	vec2 uv_0;
	vec2 uv_1;
	mat3 tangent_to_world_mat;
	mat3 tbn_mat;
} vert_data;

// ========= Storage Buffers

// in SDL GPU storage buffers in vertex shader must be bound to 'set=0' in fragment shader it is 'set=2'
// https://wiki.libsdl.org/SDL3/SDL_CreateGPUShader

layout (set=2, binding=0) uniform sampler2D _brdf_lut;
layout (set=2, binding=1) uniform sampler2D _ao_tex;
layout (set=2, binding=2) uniform samplerCube _skybox_cubemap;
layout (set=2, binding=3) uniform sampler2DArray _main_light_shadowmap;


#define RES_GLOBAL_FRAG_BUFFER_SET 2
#define RES_GLOBAL_FRAG_BUFFER_BIND 4
#include "../shader_lib/resources/resource_global_fragment_buffer.glsl"


layout (std140, set=2, binding=5) readonly buffer skybox_buffer {
    SkyboxData data; // defined in skybox.glsl
} _skybox;

layout (std140, set=2, binding=6) readonly buffer pbr_material_buffer {
    PbrMaterial _pbr_materials[];
};

layout (std140, set=2, binding=7) readonly buffer lights_buffer {
    uint num_lights;
    uint directional_lights_end; 
    uint point_lights_end;
    uint padding3;
    LightData lights[];
} _lights_buffer;

layout (std140, set=2, binding=8) readonly buffer shadowmap_buffer {
    uint array_len;
    uint padding1; 
    uint padding2;
    uint padding3;
    ShadowmapInfo infos[];
} _shadowmap_buffer;


// ========= Uniform Buffers

layout(set=3, binding=0) uniform mat_ubo {
	uint mat_index;
} _mat_ubo;


float sample_shadow_map(sampler2DArray _shadowmap, ShadowmapInfo info, float do_perspective_0_or_1, vec3 frag_pos_ws, vec3 normal_ws, float NdotL, float screen_noise) {

	
	// @Note: we can't use texel_size which is in pixel size unit as world space modifier for normal bias. 
	// We need info.texels_per_world unit for that which indicates how many texels there are for a world unit of 1.0
	// so 1/info.texels_per_world gives us how much we can offset the position along the normal to go one texel unit in world space
	// However this only works directly for directional light shadomaps which have an orthographics proj matrix so this value doesn't scale with distance to light source.
	// For point and spot lights this value represents the world space texel number at the far end of the frustum (far clip plane) so idealy we 
	// would need to scale it by the distance to fragment position. the problem is we dont have that before the transform the position to 
	// light space unless convert the position to light space twice which i would like to avoid.
	// so instead we will offset along the normal by a small constant just to get some extra acne avoidance but it will never work in all cases.  


    float inv_texels_per_unit = 1.0f/info.texels_per_world_unit;
    float normal_bias_scale = mix(inv_texels_per_unit + 0.002f, 0.02f, do_perspective_0_or_1);
    
    float inv_NdotL = 1.0f - NdotL;

    float normal_bias = mix(0.1, 1.0, inv_NdotL) * normal_bias_scale;
    normal_bias = 0.05f;

	vec3 pos = frag_pos_ws + normal_ws * normal_bias;
	
	vec4 proj_coords = info.view_proj * vec4(pos, 1.0f);
	proj_coords.xyz = mix(proj_coords.xyz, proj_coords.xyz / proj_coords.w, do_perspective_0_or_1);

	// uvs to sample depth texture
    vec2 shadow_uv = proj_coords.xy * 0.5f + 0.5f;
    shadow_uv.y = 1 - shadow_uv.y;


    // Depth bias
    float texel_size = (1.0f/float(info.resolution));
    float depth_bias = (texel_size + 0.0025f) * max(0.75f, NdotL);
    depth_bias = mix(depth_bias, depth_bias / proj_coords.w, do_perspective_0_or_1);

    float compare = proj_coords.z - depth_bias; // current depth of pixel.


	float noise = (screen_noise * 2.0f - 1.0f) * 1.25f;
	noise = noise;

    int kernel_size = 1;
    float num_samples = float(kernel_size * 2 + 1) * float(kernel_size * 2 + 1);

    float shadow = 0.0f;
    for (int x = -kernel_size; x <= kernel_size; x++){
    	for (int y = -kernel_size; y <= kernel_size; y++){
    		
    		vec2 uv_offset = vec2(float(x)+ noise, float(y)+ noise) * texel_size;

    		float light_depth = textureLod(_shadowmap, vec3(shadow_uv + uv_offset, float(info.array_layer)), float(info.mip_level)).r;
    		shadow += step(compare, light_depth);
    	}
    }

    shadow /= num_samples;
	

	vec2 uv_clamp = clamp(shadow_uv, 0.0f, 1.0f);	
    float bounds_hardness = 128.0f;
    float bounds_z = min( (1.0f - clamp(compare, 0.0f, 1.0f)) * bounds_hardness , 1.0f);
    float bounds_xy = min(uv_clamp.y * (1-uv_clamp.y) * bounds_hardness , 1.0f) * min(uv_clamp.x * (1-uv_clamp.x) * bounds_hardness, 1.0f) * bounds_z;
   	float bounds = max(0.0f, sign(bounds_xy));

   	// We dont really want bounds for spot and point lights
   	// as they natrually are bounded through their attenuation.
   	bounds = mix(bounds,1.0f, do_perspective_0_or_1); 
	//return mix(1.0f,shadow, 1);
	return mix(1.0f,shadow, bounds);
}

// Not used right now..
void attenuate_roughness_to_reduce_specular_aliasing(float roughness,float NdotV_unclammped, vec3 normal, vec3 view_dir,out float atten_rougness, out float env_brdf_roughness){
	
	vec3 ddxN = dFdx(normal);
	vec3 ddyN = dFdy(normal);

	float curv = max(dot(ddxN,ddxN), dot(ddyN,ddyN));

	// @Note: Here we do some wishy washy fiddley to reduce specular alaiasing from environment lighting
	// essentially we try to find edges and create a mask where this specualar aliasing occurs
	// and mess with the roughness at those pixels.
	// It works like this but I do wonder if there is an actually good way to do this.

	vec3 tan  = cross(view_dir, normal);
	vec3 norm = cross(normal, tan);
	float NdotV0 = dot(norm, view_dir);	
	float NdotV1 = NdotV_unclammped;

	float ff = smoothstep(0.0f, 0.1f,clamp(-1.0f * NdotV1, 0.0f, 1.0f));
 	float nn = smoothstep(0.5f, 1.0f, 1.0f - clamp(NdotV1,0.0f,1.0f));

	float a = max(dFdx(NdotV0),dFdy(NdotV0));
	float b = max(dFdx(NdotV1),dFdy(NdotV1));
	float c = clamp(max(a, b), 0.0f, 1.0f);
	
	float ee = min(nn, c * 10.0f);
	float gg = smoothstep(0.4f, 1.0f, ee) * 8.0f;
 	gg = max(gg, ff); 	

 	float hh = smoothstep(0.8f, 0.95f,ee);
    env_brdf_roughness = min(0.95f, mix(roughness, 0.1f ,hh));

 	float ll = clamp(gg, 0.0f, 1.0f);
	atten_rougness = mix(roughness, 1.0f, ll);
}


// ========= Output

layout (location=0) out vec4 frag_color;

void main() {

	frag_color = vec4(0.0f,0.0f,0.0f,1.0f);

	vec2 screen_uv = (vec2(gl_FragCoord.xy) ) / vec2(_global.frame_size);
	screen_uv.y = 1.0f - screen_uv.y;

	float screen_noise = randf(int(gl_FragCoord.x), int(gl_FragCoord.y));

	//vec3 ndc = vec3(screen_uv.xy * 2.0f - 1.0f, gl_FragCoord.z);
	
	float scene_ao = 1.0f;

	#ifndef USE_ALPHA_BLEND
		vec4 ao_tex_sample = texture(_ao_tex, screen_uv);
		scene_ao = srgb_to_linear_float_gamma_2_2(ao_tex_sample.r);
	#endif


	//frag_color.rgb = vec3(scene_ao);
	//return;

	//frag_color.rgb = vert_data.normal_ws.xyz;
	//return;

	// frag_color.rgb = vec3(scene_ao);
	// return;

	PbrMaterial mat = _pbr_materials[_mat_ubo.mat_index];

	SurfaceData surf_data;
	//surf_data.albedo = srgb_to_linear_gamma_2_2(mat.albedo.rgb);
	surf_data.albedo = mat.albedo.rgb;
	//surf_data.albedo = vec3(0.5f);
	surf_data.normal = normalize(vert_data.normal_ws.xyz);
  	surf_data.emissive = srgb_to_linear_gamma_2_2(mat.emissive.rgb);
  	surf_data.emission_strength = mat.emissive.w;
  	surf_data.roughness = mat.roughness;
  	//surf_data.roughness = 1.0f;
  	surf_data.metallic = mat.metallic;
  	surf_data.ambient_occlusion = scene_ao;
  	surf_data.alpha = mat.alpha_value;

  	LightingData lighting_data;
  	lighting_data.frag_position = vert_data.position_ws.xyz;
  	lighting_data.view_direction = normalize(_global.camera_pos_ws - vert_data.position_ws.xyz);

  	vec3 F0 = mix(vec3(DIALECTRIC_F0), surf_data.albedo, surf_data.metallic);

	
	//surf_data.roughness = 0.3f;

	float CURV_MOD = 25.0f;
	float CURV_MOD2 = 10.0f;
	vec3 ddxN = dFdx(surf_data.normal);
	vec3 ddyN = dFdy(surf_data.normal);

	float curv2 = max(dot(ddxN,ddxN), dot(ddyN,ddyN));
	float alias_mask = saturate(-0.0909 - -0.0909 * log2( CURV_MOD * curv2));
	float alias_mask_fine = saturate(-0.0909 - -0.0909 * log2( CURV_MOD2 * curv2));

	//alias_mask = 0.0;
	//alias_mask_fine = 0.0;

  	vec3 atten_norm = normalize(mix(surf_data.normal, lighting_data.view_direction, saturate(alias_mask * 10)  ));

  	float NdotV = max(dot(surf_data.normal, lighting_data.view_direction),0.00f);
  	float NdotV_atten = max(dot(atten_norm, lighting_data.view_direction),0.00f);
  	float NdotV_ = dot(surf_data.normal, lighting_data.view_direction);

  	//surf_data.roughness = mix(surf_data.roughness, 1.0f, saturate(alias_mask * 10));

  	float prefilter_roughness = surf_data.roughness;
	float env_brdf_roughness  = min(0.95f, mix(surf_data.roughness, 0.1f ,saturate(alias_mask * 2)));;

	// @Note - not very good.
	//attenuate_roughness_to_reduce_specular_aliasing(surf_data.roughness, NdotV_, surf_data.normal, lighting_data.view_direction, prefilter_roughness, env_brdf_roughness);
  
  	////// DIRECT RADIANCE ========================================================================================== ////
  	//// ============================================================================================================ ////

  	vec3 direct_radiance = vec3(0.0f); 

  	vec3 debug_color = vec3(0.0f);

  	// TODO: do this on the cpu!
  	// TODO: try doing it with gl_fragcoord.z and linearize_depth()
  	float z_linear = -vert_data.color_0.z; // view space pos
  	float split_1  = lerp(_global.near_plane, _global.far_plane, _global.cascade_frust_split_1);
  	float split_2  = lerp(_global.near_plane, _global.far_plane, _global.cascade_frust_split_2);
  	float split_3  = lerp(_global.near_plane, _global.far_plane, _global.cascade_frust_split_3);

	int cascade_index = -1;
	if(z_linear <= split_3){
		cascade_index = 2; // cascade 3
	}
	if(z_linear <= split_2){
		cascade_index = 1; // cascade 2
	}
	if(z_linear <= split_1){
		cascade_index = 0; // cascade 1
	}
	
	// DIRECTIONAL LIGHTS
 	for (int i = 0; i < _lights_buffer.directional_lights_end; i++){

 		LightData light = _lights_buffer.lights[i];

 		float shadow = 1.0f;
 		if(light.shadowmap_index >= 0 && cascade_index != -1){
			// casts shadow
			ShadowmapInfo shadow_info = _shadowmap_buffer.infos[light.shadowmap_index + cascade_index];

			float NdotL  = max(dot(vert_data.normal_ws.xyz, light.direction), 0.0f);

			shadow = sample_shadow_map(_main_light_shadowmap, shadow_info, 0.0f, vert_data.position_ws.xyz, vert_data.normal_ws.xyz, NdotL, screen_noise);
 		}

 		vec3 to_light_vec = light.direction;
 		vec3 attenuated_radiance = light.radiance;

 		vec3 light_radiance = DiffuseSpecularBRDF(lighting_data.frag_position, lighting_data.view_direction, NdotV, F0, attenuated_radiance, to_light_vec, surf_data, alias_mask_fine);

 		light_radiance *= shadow; 		
 		direct_radiance += light_radiance;

 		debug_color += shadow;
	}

	// POINT LIGHTS
	#if 0
	for (uint i = _lights_buffer.directional_lights_end; i < _lights_buffer.point_lights_end; i++){
 		
 		LightData light = _lights_buffer.lights[i];
    	vec3 to_light_vec = light.position.xyz - lighting_data.frag_position;
    	float light_distance = length(to_light_vec);
    	to_light_vec /= light_distance; // normalize
    	float NdotL  = max(dot(vert_data.normal_ws.xyz, to_light_vec), 0.0f);

    	float shadow = 1.0f;

    	if(light.shadowmap_index >= 0) {
    		uint face_index = direction_to_cubemap_face_index(-to_light_vec);
    		shadow = sample_shadow_map(_main_light_shadowmap, _shadowmap_buffer.infos[light.shadowmap_index + face_index], 1.0f,  vert_data.position_ws.xyz, vert_data.normal_ws.xyz, NdotL, screen_noise);
    	}


    	float attenuation = 1.0f / (light_distance * light_distance);
    	vec3 attenuated_radiance = _lights_buffer.lights[i].radiance.rgb * attenuation;

    	vec3 light_radiance = DiffuseSpecularBRDF(lighting_data.frag_position, lighting_data.view_direction, NdotV, F0, attenuated_radiance, to_light_vec, surf_data, alias_mask_fine);
 		light_radiance *= shadow;

 		direct_radiance += light_radiance;

 		debug_color += shadow;
	}
	#endif

	// SPOT LIGHTS
	#if 1
	for (uint i = _lights_buffer.point_lights_end; i < _lights_buffer.num_lights; i++){
 		
    	float shadow = 1.0f;

    	LightData light = _lights_buffer.lights[i];

 		vec3 to_light_vec = light.position.xyz - lighting_data.frag_position;
    	float light_distance = length(to_light_vec);
    	to_light_vec /= light_distance; // normalize

 		float inv_square_law = 1.0f / (light_distance * light_distance);

  		float light_attenuation = inv_square_law * light_get_spot_light_angular_attenuation( light.direction, to_light_vec , light.spot_light_angle_scale, light.spot_light_angle_offset);
  		vec3 attenuated_radiance = light.radiance * light_attenuation;

 		if(light.shadowmap_index >= 0){
			// casts shadow
			ShadowmapInfo shadow_info = _shadowmap_buffer.infos[light.shadowmap_index];
			float NdotL  = max(dot(vert_data.normal_ws.xyz, to_light_vec), 0.0f);
			shadow = sample_shadow_map(_main_light_shadowmap, shadow_info, 1.0f,  vert_data.position_ws.xyz, vert_data.normal_ws.xyz, NdotL, screen_noise);
 		}

 		vec3 light_radiance =  DiffuseSpecularBRDF(lighting_data.frag_position, lighting_data.view_direction, NdotV, F0, attenuated_radiance, to_light_vec, surf_data, alias_mask_fine);
 		
 		light_radiance *= shadow; 		
 		direct_radiance += light_radiance;
 		debug_color += shadow;
	}
	#endif

	//frag_color.rgb = debug_color.rgb * 1.0f;
	//return;
	////// EMISSIVE RADIANCE ======================================================================================== ////
  	//// ============================================================================================================ ////

	vec3 emissive_radiance = surf_data.emissive * surf_data.emission_strength;


	////// INDIRECT RADIANCE ======================================================================================== ////
  	//// ============================================================================================================ ////

    // we rotate normal and reflection vector by this matrix to simulate rotation of the skybox
	mat3 sky_rot_mat = rotate_mat3_Y(radians(_skybox.data.rotation)); // TODO: We could actually calculate this on the cpu 

    
    // ========== INDIRECT DIFFUSE
    // ================================
    
  	vec3 dominant_diffuse_dir = sky_rot_mat * get_diffuse_dominant_dir(surf_data.normal, -lighting_data.view_direction, NdotV, surf_data.roughness);
    
    vec3 sky_indirect_diffuse_cubemap   = skybox_sample_indirect_diffuse(_skybox_cubemap, dominant_diffuse_dir, _skybox.data.max_cubemap_mip);
    vec3 sky_indirect_diffuse_procedual = skybox_sample_procedual(dominant_diffuse_dir, _skybox.data.color_zenith, _skybox.data.color_horizon, _skybox.data.color_nadir);
    vec3 sky_indirect_diffuse = apply_exposure(mix(sky_indirect_diffuse_procedual, sky_indirect_diffuse_cubemap, _skybox.data.use_cubemap), _skybox.data.exposure);
    
    // ========== INDIRECT SPECULAR
    // ================================
    
	vec3 reflected = reflect(-lighting_data.view_direction, surf_data.normal);
	vec3 dominant_spec_dir = sky_rot_mat * get_specular_dominant_dir(surf_data.normal, reflected, NdotV, surf_data.roughness);

    vec3 sky_indirect_specular_cube      = skybox_sample_indirect_specular(_skybox_cubemap, dominant_spec_dir, prefilter_roughness, _skybox.data.max_cubemap_mip);
    vec3 sky_indirect_specular_procedual = skybox_sample_procedual(dominant_spec_dir, _skybox.data.color_zenith, _skybox.data.color_horizon, _skybox.data.color_nadir);
    vec3 sky_indirect_specular = apply_exposure(mix(sky_indirect_specular_procedual, sky_indirect_specular_cube, _skybox.data.use_cubemap), _skybox.data.exposure);


    float diffuse_occlusion = scene_ao;
	float specular_occlusion = saturate(pow(NdotV + scene_ao, exp2(-16.0f * surf_data.roughness -1.0f)) - 1.0f + scene_ao);

	vec3 F = FresnelSchlickRoughness(NdotV_atten, F0, prefilter_roughness);
    vec3 kS = F;
    vec3 kD = (1.0 -kS) * (1.0 - surf_data.metallic);
    
    // @Note: We clamp NdotV here to reduce some specualar aliasing
	vec2 envBRDF  = texture(_brdf_lut, vec2(NdotV_atten, env_brdf_roughness)).rg;


    vec3 indirect_specular = sky_indirect_specular * (F * envBRDF.x + envBRDF.y) * specular_occlusion;
    vec3 indirect_diffuse = sky_indirect_diffuse * surf_data.albedo * diffuse_occlusion;

	vec3 indirect_radiance = vec3(0.0f);
	indirect_radiance = (kD * indirect_diffuse + indirect_specular) ;

    ////// COMBINED OUTGOING RADIANCE ===============================================================================
  	//// ============================================================================================================

	vec3 outgoing_radiance = (indirect_radiance + direct_radiance + emissive_radiance);

	//outgoing_radiance = direct_radiance;
	//outgoing_radiance = indirect_specular;
	//outgoing_radiance = vec3(specular_occlusion* 10);

	frag_color.rgb = outgoing_radiance * _global.camera_exposure;
	
	#ifdef USE_ALPHA_TEST
		//frag_color.rgb = vec3(1.0, 0.0, 1.0);
	#endif


	frag_color.a = 1.0f;

	#ifdef USE_ALPHA_BLEND
	frag_color.a = surf_data.alpha;
	#endif

}