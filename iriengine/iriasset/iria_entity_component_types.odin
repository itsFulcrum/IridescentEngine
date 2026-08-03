package iria

import iricom "../iricommon"

AssetEntityInfo :: struct {
	flags 		: iricom.EntityFlags,
	comp_set 	: iricom.ComponentSet,
	tag 		: u32,
}

AssetComponentIndexes :: struct {
	camera_index   : i32,
	skybox_index   : i32,
	light_index    : i32,
	meshren_index  : i32,
	collider_index : i32,
	_ : [3]i32, // reserved.
}


// == Components ==

// Flat constant size data blobs of components
// to make serialisation between file data and comp data
// easier. These Must Not hold any variable sized data or pointers
// of any kind. Flat Constant sized data only.


AssetMeshRendererComponentData :: struct {
	num_draw_groups : u32, // number of draw_groups that belong to this component.
	array_offset : u32,    // offset into 'drawable_groups' array of AssetUniverse.
}

AssetColliderComponentData :: struct #packed {
	type  : u32, // Collider type enum
	flags : u32, // ColliderFlags enum bitset of collider component
	offset : [3]f32,
	extent : [3]f32,
	orientation : quaternion128,
}


AssetLightFlags :: distinct bit_set[AssetLightFlag; u8]
AssetLightFlag :: enum u8 {
	CastShadows = 0,
	DebugDrawFrustum, // Shadowmap frustums.
}

AssetLightComponentData :: struct {
	color 			: [3]f32,
	strength 		: f32,

	flags 			: AssetLightFlags,  // u8
	type 			: iricom.LightType, // u8

	// spot lights only
	spot_inner_cone_angle_radians : f32,
	spot_outer_cone_angle_radians : f32,

	// @Note: for point and spot lights, only shadomap_res_0 is considered
	// for directional lights, 0,1,2 correspond to the 3 cascades.
	shadowmap_res_0 : iricom.ShadowmapResolution,
	shadowmap_res_1 : iricom.ShadowmapResolution,
	shadowmap_res_2 : iricom.ShadowmapResolution,
}


AssetCameraComponentData :: struct {
	fov_deg  		: f32,
	near_clip		: f32,
	far_clip 		: f32,
	exposure_correction : f32,
	// physical camera
	// TODO: maybe implment focal lenght and sensor size ?
	iso 			: f32,
	shutter_speed 	: f32,
	aperture 		: f32,
}

AssetSkyboxComponentData :: struct {
	color_zenith 	: [3]f32,
	color_horizon 	: [3]f32,
	color_nadir 	: [3]f32,
	exposure : f32,	
	rotation : f32,
}