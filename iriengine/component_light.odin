package iri

import "core:math/linalg"
import iria "iriasset"

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
	if comp == nil {
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
	if comp == nil {
		return;
	}

	comp.color = [3]f32{1.0, 1.0, 1.0};
	comp.strength = 1000.0;
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


comp_light_init_from_light_asset_uuid :: proc(comp : ^LightComponent, asset_uuid : AssetUUID, apply_transforms_to_entity : bool = true){
	asset_manager := engine.asset_manager;
	asset , asset_ok := asset_io_load_light_asset(asset_manager, asset_uuid);
	if !asset_ok {
		return;
	}

	comp_light_init_from_light_asset(comp, asset, apply_transforms_to_entity);
}

comp_light_init_from_light_asset :: proc(comp : ^LightComponent, asset : iria.LightAsset, apply_transforms_to_entity : bool = true){


	comp.color    = asset.color;
	comp.strength = asset.strength;

	if asset.type == .DIRECTIONAL {
		dir_variant := DirectionalLightVariant{};
		dir_variant.shadowmap_cascade_resolutions[0] = asset.shadowmap_res_0;
		dir_variant.shadowmap_cascade_resolutions[1] = asset.shadowmap_res_1;
		dir_variant.shadowmap_cascade_resolutions[2] = asset.shadowmap_res_2;

		comp.variant = dir_variant;
	
	} else if asset.type == .POINT {

		point_variant := PointLightVariant{};
		point_variant.shadowmap_resolution = asset.shadowmap_res_0;
		point_variant.draw_cone = iria.LightAssetFlag.DebugDrawFrustum in asset.flags;
		
		comp.variant = point_variant;

	} else if asset.type == .SPOT {

		spot_variant := SpotLightVariant{};
		spot_variant.shadowmap_resolution = asset.shadowmap_res_0;
		spot_variant.inner_cone_angle_deg = linalg.to_degrees(min(asset.spot_inner_cone_angle_radians, asset.spot_outer_cone_angle_radians));
		spot_variant.outer_cone_angle_deg = linalg.to_degrees(asset.spot_outer_cone_angle_radians);
		spot_variant.draw_cone = iria.LightAssetFlag.DebugDrawFrustum in asset.flags;
		comp.variant = spot_variant;
	}

	if apply_transforms_to_entity {
		transform_comp := ecs_get_transform(comp.parent_ecs, comp.entity);
		transform_comp.transform = asset.transform;
	}

	comp_light_push_changes(comp);
}


// Create light asset structure from current component values.
comp_light_create_light_asset :: proc(comp : ^LightComponent) -> iria.LightAsset {

	asset := iria.LightAsset {
		color = comp.color,
		strength = comp.strength,
	}

	asset.flags = iria.LightAssetFlags{};
	if comp.cast_shadows {
		asset.flags += iria.LightAssetFlags{.CastShadows};
	}

	switch &v in comp.variant {
		case DirectionalLightVariant: 	{
			asset.type = LightType.DIRECTIONAL;
			asset.shadowmap_res_0 = v.shadowmap_cascade_resolutions[0];
			asset.shadowmap_res_1 = v.shadowmap_cascade_resolutions[1];
			asset.shadowmap_res_2 = v.shadowmap_cascade_resolutions[2];
		}
		case PointLightVariant: {
			asset.type = LightType.POINT;
			asset.shadowmap_res_0 = v.shadowmap_resolution;
			if v.draw_cone {
				asset.flags += iria.LightAssetFlags{.DebugDrawFrustum};
			}
		}
		case SpotLightVariant: {
			asset.type = LightType.SPOT;
			
			asset.spot_inner_cone_angle_radians = linalg.to_radians(v.inner_cone_angle_deg);
			asset.spot_outer_cone_angle_radians = linalg.to_radians(v.outer_cone_angle_deg);
			asset.shadowmap_res_0 = v.shadowmap_resolution;
			if v.draw_cone {
				asset.flags += iria.LightAssetFlags{.DebugDrawFrustum};
			}
		}
	}

	transform_comp := ecs_get_transform(comp.parent_ecs, comp.entity);
	asset.transform = transform_comp.transform;

	return asset;
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
	gpu_light.is_disabled = entity_is_enabled(comp.entity) ? 0 : 1;

	if !comp.cast_shadows {
		gpu_light.shadowmap_index = -1;
	}

	if light_type_enum == .SPOT {

		spot_variant, ok := &comp.variant.(SpotLightVariant);;
		engine_assert(ok);

		inner_cone_angle_rad : f32 = linalg.to_radians(spot_variant.inner_cone_angle_deg);
		outer_cone_angle_rad : f32 = linalg.to_radians(spot_variant.outer_cone_angle_deg);

		inner_cone_angle_rad = min(inner_cone_angle_rad, outer_cone_angle_rad);

		gpu_light.spot_angle_scale  = 1.0 / max(0.001, linalg.cos(inner_cone_angle_rad) - linalg.cos(outer_cone_angle_rad));
		gpu_light.spot_angle_offset = - linalg.cos(outer_cone_angle_rad) * gpu_light.spot_angle_scale;

	} else if light_type_enum == .DIRECTIONAL{
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
		inner_cone_angle_deg = 30.0,
		outer_cone_angle_deg = 40.0,
	}
}