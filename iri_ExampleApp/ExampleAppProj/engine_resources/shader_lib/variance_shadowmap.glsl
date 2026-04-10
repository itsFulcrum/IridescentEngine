// referance for variance shadowmap sampling. 
// not in use atm..

float linstep(float low, float high, float value) {
	
	return clamp((value-low)/(high - low), 0.0f, 1.0f);

}


float sample_variance_shadow_map(sampler2D _shadowmap, vec3 frag_pos_ws, mat4 vp_mat){

	vec4 proj_coords = vp_mat * vec4(frag_pos_ws, 1.0f);
	proj_coords.xyz /= proj_coords.w;

	// uvs to sample depth texture
    vec2 shadow_uv = proj_coords.xy * 0.5f + 0.5f;
    shadow_uv.y = 1 - shadow_uv.y;

    float compare = proj_coords.z; // current depth of pixel.

    float array_layer = 0.0f; // need to calculate this 
    float mip_level = 0.0f; // hardcoded atm


    // THIS WIL PROB CRASH
    vec3 moments = vec3(0.0f); //textureLod(_shadowmap, vec3(shadow_uv, array_layer), mip_level).rgb;

    float d = compare - moments.x;
    float p = step(compare, moments.x);
    

    float variance = max(moments.y - moments.x * moments.x, 0.00001f);

    // hack multiplyer to remove a bit of light bleed
    float p2 = smoothstep(moments.y, variance, d );


    float p_max = variance / (variance + d*d); // Chebyshevs inequality ..

    float lin = 0.8; // if one wants hard shadows, turn this up, it'll also reduce light bleeding.
    
    p_max = linstep( lin, 1.0f, p_max);

    
    float shadow = min(max(p, p_max), 1.0f) * p2;
    
    vec2 uv_clamp = clamp(shadow_uv.xy, 0.0f, 1.0f);
    

    float bounds_hardness = 64.0f;
    float bounds_z = min( (1.0f - clamp(compare, 0.0f, 1.0f)) * bounds_hardness , 1.0f);
    float bounds_xy = min(uv_clamp.y * (1-uv_clamp.y) * bounds_hardness , 1.0f) * min(uv_clamp.x * (1-uv_clamp.x) * bounds_hardness, 1.0f) * bounds_z;
   	float bounds = max(0.0f, sign(bounds_xy));

	return mix(1.0f,shadow, bounds);
}