
struct SkyboxData {
	vec3  sun_direction;
    float sun_strength;
    vec3  sun_color;
    float use_cubemap;

    vec3  color_zenith;
	float exposure;
	vec3  color_horizon;
	float rotation;
	vec3  color_nadir;
	uint  max_cubemap_mip;
};

uint direction_to_cubemap_face_index(const vec3 dir){
	vec3 absdir = abs(dir);
	uint face_index = 0;

	// Faces indexes map in this order to cube directions
	// +x, -x, +y, -y, +z, -z

	// UV stuff here is for future referance and NOT tested yet
	// (prob need to switch some signs around)
	//float ma = 0.0f;
	//vec2 uv = vec2(0.0f);

	if(absdir.z >= absdir.x && absdir.z >= absdir.y){
		face_index = dir.z < 0.0f ? 5 : 4; 	// z axis

		//ma = 0.5f / absdir.z;
		//uv = vec2(dir.z < 0.0 ? -dir.x : dir.x,  -dir.y);
	} else if (absdir.y >= absdir.x){
		face_index = dir.y < 0.0 ? 3 : 2; 	// y axis
		
		//ma = 0.5f / absdir.y;
		//uv = vec2(dir.x, dir.y < 0.0 ? -dir.z : dir.z);
	} else {
		face_index = dir.x < 0.0f ? 1 : 0; 	// x axis
		
		//ma = 0.5f / absdir.x;
		//uv = vec2(dir.x < 0.0 ? dir.z : -dir.z, -dir.y);
	}

	//uv = uv * ma + 0.5f;

	return face_index;
}

vec3 get_diffuse_dominant_dir( vec3 normal, vec3 view_direction, float NdotV, float roughness) {
	float a = 1.02341f * roughness - 1.51174f;
	float b = -0.511705f * roughness + 0.755868f;
	float lerpFactor = clamp(( NdotV * a + b) * roughness, 0.0f, 1.0f);
	// The result is not normalized as we fetch in a cubemap
	return mix(normal , view_direction , lerpFactor);
}

vec3 get_specular_dominant_dir(vec3 normal, vec3 reflected, float NdotV, float roughness ) {

	// "We have a better approximation of the off specular peak
	// but due to the other approximations we found this one performs better.
	// N is the normal direction
	// R is the mirror vector
	// This approximation works fine for G smith correlated and uncorrelated"
	// Source: https://seblagarde.wordpress.com/wp-content/uploads/2015/07/course_notes_moving_frostbite_to_pbr_v32.pdf

	//#define DO_ACCURATE
	//#define GSMITH_CORRELATED

	// #ifdef DO_ACCURATE
	// // This is an accurate fitting of the specular peak ,
	// // but due to other approximation in our decomposition it doesn ’t perform well
	// #ifdef GSMITH_CORRELATED
	// 	float lerpFactor = pow(1.0f - NdotV , 10.8649f) * (1.0f - 0.298475f * log (39.4115f - 39.0029f * roughness)) + 0.298475f * log (39.4115f - 39.0029f * roughness ) ;
	// #else
	//  	float lerpFactor = 0.298475f * NdotV * log(39.4115f - 39.0029f * roughness) + (0.385503f -	0.385503f * NdotV ) * log (13.1567f - 12.2848f * roughness );
	// #endif
	// #endif

	float smoothness = 1.0f - roughness;
	float lerpFactor = smoothness * (sqrt(smoothness) + roughness);
	// The result is not normalized as we fetch in a cubemap
	return mix(normal, reflected , lerpFactor );
}


vec3 skybox_sample_indirect_diffuse(samplerCube prefilter_cubemap, vec3 surface_normal, uint max_cubemap_mip) {
	// @Note:  
	// I ommit creation of a seperate 'irradiance convolution map' and instead just use
	// the last mip level of the 'prefiliter convolution map' verison because at roughness 1.0 this 
	// also effectivly converges to the irradiance convolution used for diffuse lighting.
	return textureLod(prefilter_cubemap, surface_normal, float(max_cubemap_mip)).rgb;
}

vec3 skybox_sample_indirect_specular(samplerCube prefilter_cubemap, vec3 dir, float roughness, uint max_cubemap_mip){
    return textureLod(prefilter_cubemap, dir,  roughness * float(max_cubemap_mip)).rgb;
}

vec3 skybox_sample_procedual(vec3 dir, vec3 zenith, vec3 horizon, vec3 nadir){


	zenith  = pow(zenith, vec3(2.2f)); // srgb to linear
	horizon = pow(horizon,vec3(2.2f)); // srgb to linear
	nadir   = pow(nadir,  vec3(2.2f)); // srgb to linear


	vec3 color = vec3(0);

	float dot = dot(dir.xyz, vec3(0,1,0));

	float lerp = clamp( pow(  abs(dot), 0.7 )  , 0,1);
	if( dot >= 0) {
		color =  mix(horizon, zenith, lerp );
	} else {
		color = mix(horizon, nadir, lerp );
	}

	return color;
}