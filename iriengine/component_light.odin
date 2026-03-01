package iri

import "core:math/linalg"


LightComponent :: struct{
	using common : ComponentCommon,
	
	// TODO: would be cool
	// temperature : f32,
	// use_temperature : bool,

	color: [3]f32,
	strength : f32,
	cast_shadows : bool,
	
	variant : union {
		DirectionalLightVariant,
		PointLightVariant,
		SpotLightVariant,
	},

	_is_dirty : bool,
}


@(private="package")
comp_light_init :: proc (comp: ^LightComponent){
	if(comp == nil){
		return;
	}

	#force_inline comp_light_set_defaults(comp);
}

@(private="package")
comp_light_deinit :: proc(comp: ^LightComponent){
	// if(comp == nil){
	// 	return;
	// }
}

comp_light_set_defaults :: proc(comp : ^LightComponent){
	if(comp == nil){
		return;
	}

	comp.color = [3]f32{1.0, 1.0, 1.0};
	comp.strength = 1.0;
	comp.cast_shadows = true;
	comp.variant = DirectionalLightVariant_get_default();
	comp_light_push_changes(comp);
}

// =====================================================================
// Component procedures
// =====================================================================

comp_light_get_type :: proc (comp : ^LightComponent) -> LightType{

	switch &m in comp.variant {
		case DirectionalLightVariant: 	return LightType.DIRECTIONAL;
		case PointLightVariant: 		return LightType.POINT;
		case SpotLightVariant: 			return LightType.SPOT;
	}

	panic("Invalid Codepath, LightsComponents must have a variant")
}

comp_light_set_type :: proc(comp : ^LightComponent, type : LightType){

	curr_type := comp_light_get_type(comp);

	if curr_type == type {
		return;
	}

	switch type {
		case .DIRECTIONAL: 	comp.variant = DirectionalLightVariant_get_default();
		case .POINT: 		comp.variant = PointLightVariant_get_default();
		case .SPOT: 		comp.variant = SpotLightVariant_get_default();
	}


	engine_assert(comp.variant != nil);
}

comp_light_push_changes :: proc(comp : ^LightComponent){

	comp._is_dirty = true;
	comp.common.parent_ecs.any_light_is_dirty = true;
}


comp_light_set_values_from_asset_light :: proc(comp : ^LightComponent, asset_light : AssetLight) {

	comp.color = asset_light.color;
	comp.strength = asset_light.strength;

	if asset_light.type == .DIRECTIONAL {
		comp.variant = DirectionalLightVariant_get_default();
	} else if asset_light.type == .POINT {
		comp.variant = PointLightVariant_get_default();
	} else if asset_light.type == .SPOT {

		spot_default := SpotLightVariant_get_default();
		spot_default.inner_cone_angle_deg = min(asset_light.spot_angle_inner_deg, asset_light.spot_angle_outer_deg);
		spot_default.outer_cone_angle_deg = asset_light.spot_angle_outer_deg;
		comp.variant = spot_default;
	}
}

@(private="package")
comp_light_create_LightDataGPU :: proc(comp : ^LightComponent) -> LightDataGPU {
 	transform_comp := ecs_get_transform(comp.parent_ecs, comp.entity);

 	gpu_light : LightDataGPU;

 	light_type_enum : LightType = comp_light_get_type(comp);

	gpu_light.position = transform_comp.position;
	gpu_light.direction = -get_forward(transform_comp);
	gpu_light.type = cast(u32)light_type_enum;
	gpu_light.radiance = comp.color * comp.strength;

	if !comp.cast_shadows {
		gpu_light.shadowmap_index = -1;
	}

	if(light_type_enum == .SPOT) {

		spot_variant, ok := &comp.variant.(SpotLightVariant);;
		engine_assert(ok);

		inner_cone_angle_rad : f32 = linalg.to_radians(spot_variant.inner_cone_angle_deg);
		outer_cone_angle_rad : f32 = linalg.to_radians(spot_variant.outer_cone_angle_deg);

		inner_cone_angle_rad = min(inner_cone_angle_rad, outer_cone_angle_rad);

		gpu_light.spot_angle_scale  = 1.0 / max(0.001, linalg.cos(inner_cone_angle_rad) - linalg.cos(outer_cone_angle_rad));
		gpu_light.spot_angle_offset = - linalg.cos(outer_cone_angle_rad) * gpu_light.spot_angle_scale;

	} else if(light_type_enum == .DIRECTIONAL){
		// as we dont need position for dir lights store up vectore to compute proper 
		// view_proj for cascaded shadowmaps
		//gpu_light.position = get_up(transform_comp); 
	}


	return gpu_light;
}


// Light Variants



DirectionalLightVariant :: struct {
	shadowmap_cascade_resolutions : [3]ShadowmapResolution,
}

PointLightVariant :: struct{
	shadowmap_resolution : ShadowmapResolution,
	draw_cone : bool,
	draw_cone_index : i32,
}

SpotLightVariant :: struct {
	shadowmap_resolution : ShadowmapResolution,
	inner_cone_angle_deg : f32,
	outer_cone_angle_deg : f32,
	draw_cone : bool,
}

PointLightVariant_get_default :: proc() -> PointLightVariant{
	return PointLightVariant {
		shadowmap_resolution = ._2048,
		draw_cone_index = -1,
	}
}

DirectionalLightVariant_get_default :: proc() -> DirectionalLightVariant{
	return DirectionalLightVariant {
		shadowmap_cascade_resolutions = {ShadowmapResolution._2048,ShadowmapResolution._2048,ShadowmapResolution._4096}
	}
}
SpotLightVariant_get_default :: proc() -> SpotLightVariant{
	return SpotLightVariant {
		shadowmap_resolution = ._2048,
		inner_cone_angle_deg = 0.5,
		outer_cone_angle_deg = 90.0,
	}
}