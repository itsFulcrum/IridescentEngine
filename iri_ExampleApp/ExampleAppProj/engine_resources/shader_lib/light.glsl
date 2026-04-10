

struct LightData {
  vec3 position;
  uint type; 				        // 0 = directional, 1 = point, 2 = spot
  vec3 direction;			
  int shadowmap_index;      // -1 if no shadowmap
  vec3 radiance;  			    // light color multiplied by instensity // candela for punctual light lux for directional light
  
  float spot_light_angle_scale;  // Calculated as: 1.0f / max(0.001f, cos(inner_cone_angle_radians) - cos(outer_cone_angle_radians));
  float spot_light_angle_offset; // Calculated as: -cos(outer_cone_angle_radians) * spot_light_angle_scale;
  float padding1;
  float padding2; 
  float padding3; 
};


struct ShadowmapInfo {
  mat4  view_proj;
  int  array_layer; // -1 == unused 
  uint  mip_level;
  uint  resolution;
  float texels_per_world_unit; // resolution / frustum_extents
};


float light_get_point_light_attenuation(vec3 fragment_position, vec3 light_position) {
  float distance = max(length(light_position - fragment_position), 0.001f); // avoid divide by 0
  return 1.0f / (distance * distance); // inverse square law
}


float light_get_spot_light_angular_attenuation(vec3 spot_light_direction, vec3 to_light_vector, float light_angle_scale, float light_angle_offset) {
  // @Note: 
  // Paramters 'light_angle_scale' and 'light_angle_offset' can be calculated on the cpu
  // inner and outter cone angles in radians.
  // float light_angle_scale = 1.0f / max(0.001f, cos(inner_cone_angle_radians) - cos(outer_cone_angle_radians));
  // float light_angle_offset = -cos(outer_cone_angle_radians) * light_angle_scale;

  // Angular attenuation
  float LdotL = dot(spot_light_direction, to_light_vector);
  float angular_attenuation = clamp(LdotL * light_angle_scale + light_angle_offset, 0.0f, 1.0f);

  return angular_attenuation * angular_attenuation;
}