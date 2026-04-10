#ifndef PBR_LIGHTING_GLSL
#define PBR_LIGHTING_GLSL

// depends on to compile
#include "pbr_lighting_terms.glsl"

#define LI_PI 3.14159265359f
#define LI_ONE_OVER_PI 0.31830988618379067154f
#define DIALECTRIC_F0 0.04f

const float MAX_REFLECTION_LOD = 8.0;

struct SurfaceData {
  vec3 albedo;
  vec3 normal;
  vec3  emissive;
  float emission_strength;
  float roughness;
  float metallic;
  float ambient_occlusion;
  float alpha;
};

struct LightingData {
  vec3 frag_position;
  vec3 view_direction;
};


float randff(int x, int y) {
    // https://blog.demofox.org/2022/01/01/interleaved-gradient-noise-a-different-kind-of-low-discrepancy-sequence/
    return mod(52.9829189f * mod(0.06711056f * float(x) + 0.00583715f * float(y), 1.0f), 1.0f);
}

// A Modified CookTorranceSpecularBRDF, it needs to run per lightsource to calculate the combined radiance (energy) emitted by a given point/fragment
// 'attenuated_light_radiance' is lights radiance * attenuation.
// for point lights attenuation might be inverse square law (1.0 / light_distance * light_distance)
// for directinal lights attenuation would be 1.0 exactly and the 'to_light_vector' would equal the directional lights
vec3 DiffuseSpecularBRDF(vec3 frag_position, vec3 view_direction, float NdotV, vec3 F0, vec3 attenuated_light_radiance, vec3 to_light_vector, SurfaceData sd, float alias_mask) {

    vec3 incomming_radiance = attenuated_light_radiance;

    NdotV = clamp(NdotV, 0.0, 1.0f);

    vec3  half_vec = normalize(view_direction + to_light_vector);
    float NdotL = max(0.0f, dot(sd.normal, to_light_vector));
    float NdotH = max(0.0f, dot(sd.normal, half_vec));
    float HdotV = max(0.0f, dot(half_vec , view_direction));
    float LdotH = max(0.0f, dot(half_vec , to_light_vector));


    float normal_distribution_ggx = NormalDistributionGGX(NdotH, sd.roughness, alias_mask);

    float geometry = GeometrySmith(NdotV, NdotL, sd.roughness);
    
    // @Note: not sure which is better 
    // vec3 fresnel = FresnelSchlick(HdotV ,F0); // sometimes denoted as 'kS'
    vec3 fresnel = FresnelSchlickRoughness(HdotV ,F0, sd.roughness); // sometimes denoted as 'kS'

    vec3 numerator = normal_distribution_ggx * geometry * fresnel;
    float denominator = 1.0f * NdotV * NdotL + 0.0001f;
    vec3 specular = numerator / denominator;

    vec3 diffuse_reflection = vec3(1.0f - fresnel) * (1.0f - sd.metallic);     // sometimes denoted as kD

    float oren_nayer = OrenNayarDiffuse(to_light_vector, view_direction, sd.normal, sd.roughness);
    //float burley = BurleyDiffuse(LdotH, NdotL, NdotV, sd.roughness);

    //vec3 outgoing_radiance = (diffuse_reflection * sd.albedo * LI_ONE_OVER_PI + specular) * incomming_radiance * NdotL;
    vec3 outgoing_radiance = (diffuse_reflection* sd.albedo * LI_ONE_OVER_PI + specular)  * incomming_radiance * oren_nayer * sd.ambient_occlusion;
    
    //outgoing_radiance = specular * incomming_radiance;
    //outgoing_radiance = specular * incomming_radiance;

    return outgoing_radiance;
}

// A refrence pseudo code implementation of basic pbr lighting with direct light sources and image base skybox lighting
// DOES NOT COMPILE
// vec4 lightingPBR_Example(SurfaceData sd, LightingData ld,samplerCube irradianceMap,samplerCube prefilterMap, sampler2D brdfLUT) {

//   // STEP 1: Get surface data
//   SurfaceData sd;
//   sd.albedo = vec3(1.0f);
//   sd.roughness = 0.5f;
//   sd.metallic = 0.0f;
//   sd.normal = vec3(0.0, 1.0f, 0.0f); // sample normal map
//   sd.emission_strength = 0.0f;
//   sd.ambient_occlusion = 1.0f;




//   ////// PRECOMPUDED TERMS ======================================================================================== ////
//   //// ============================================================================================================ ////
//     // precompude some terms here already for performace as they are used frequently throughout

//       vec3 F0 = mix(vec3(DIALECTRIC_F0),sd.albedo,sd.metallic);
//       float NdotV = max(dot(sd.normal, -ld.viewDirection), 0.0);

//   //// DIRECT LIGHTING ============================================================================================ ////
//   //// ============================================================================================================ ////

//     vec3 directRadiance = vec3(0.0f); // commonly denoted as Lo

//     const int num_of_lights = 1;
//     for (int i = 0; i < num_of_lights; i++){

//       LightData light; // get light from some kind of light buffer
//       light.position = vec3(0.0f,1.0f,0.0f);
//       light.direction = vec3(0.0f,-1.0f,0.0f);
//       light.type = 0; // type 0 would be directional light in my case.
//       light.radiance = vec3(1.0f,1.0f,1.0f);
//       light.spot_light_angle_scale  = 0.0f; // 1.0f / max(0.001f, cos(inner_cone_angle_radians) - cos(outer_cone_angle_radians));
//       light.spot_light_angle_offset = 0.0f; // -cos(outer_cone_angle_radians) * spot_light_angle_scale;

//       float shadow = 1.0f; // Calculate shadow for this light ..

//       emited_radiance = DiffuseSpecularBRDF(ld.fragmentPosition, -ld.viewDirection,NdotV,F0, light, sd);
//       directRadiance += (emited_radiance * shadow);
//     }


//   ////// INDIRECT LIGHTING ======================================================================================== ////
//   //// ============================================================================================================ ////
//     vec3 F = FresnelSchlickRoughness(NdotV,F0,sd.roughness);
//     vec3 kS = F;
//     vec3 kD = 1.0 -kS;
//     kD *= 1.0 - sd.metallic;

//     vec3 R = reflect(ld.viewDirection,sd.normal);


//     // INDIRECT DIFFUSE
//     vec3 rotatedNormal =  rotate_around_axis_radians(sd.normal, vec3(0.0f,1.0f,0.0f), ld.skyboxRotation);
//     vec3 irradiance = texture(irradianceMap, rotatedNormal).rgb;
//     irradiance.rgb = lerp(ld.skyboxColor.rgb,irradiance.rgb,ld.skyboxColor.w); // skyboxColor.w indicates if skybox samplers are bound or not


//     irradiance = apply_exposure(irradiance, ld.skyboxExposure).rgb;
//     vec3 diffuse = irradiance * sd.albedo;

//     // INDIRECT SPECULAR
//     vec3 reflectVec = reflect(ld.viewDirection, sd.normal);
//     vec3 rotatedReflect = rotate_around_axis_radians(reflectVec, vec3(0.0f,1.0f,0.0f), ld.skyboxRotation);

//     vec3 prefilteredColor = textureLod(prefilterMap, rotatedReflect,  sd.roughness * MAX_REFLECTION_LOD).rgb;
//     prefilteredColor.rgb = lerp(ld.skyboxColor.rgb,prefilteredColor.rgb,ld.skyboxColor.w); // same here if skyboxes are not bound just use its color;


//     prefilteredColor = apply_exposure(prefilteredColor, ld.skyboxExposure).rgb;
//     vec2 envBRDF  = texture(brdfLUT, vec2(NdotV, sd.roughness)).rg;
//     vec3 specular = prefilteredColor * (F * envBRDF.x + envBRDF.y);

//     vec3 indirectRadiance = (kD * diffuse + specular) * sd.ambient_occlusion;


//   ////// Emissive RADIANCE ======================================================================================== ////
//   //// ============================================================================================================ ////

//     vec3 emissionRadiance = sd.albedo * sd.emission_strength; // no support for different emission color then albedo

//   ////// COMBINED RADIANCE ======================================================================================== ////
//   //// ============================================================================================================ ////

//     vec3 pbrShadedColor = directRadiance + indirectRadiance + emissionRadiance;
//     //pbrShadedColor = specular;

//   ////// OUTPUT =================================================================================================== ////
//   //// ============================================================================================================ ////

//     return vec4(pbrShadedColor,sd.alpha);
// }

#endif
