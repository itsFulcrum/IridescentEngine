package iricom

import "core:math/rand"

Entity :: struct {
	id : i32,
	identifier : i32,
}

EntityInvalid :: Entity{id = -1, identifier = -1}

ENTITY_FLAGS_INTERNAL :: EntityFlags{._Internal_IsEnabled, ._Internal_Exists, ._Internal_PendingDestroy}
EntityFlags :: bit_set[EntityFlag; u32]
EntityFlag :: enum u32 {
	_Internal_IsEnabled = 0,
	NonPersistant = 1, // Entities with this flag are not stored to file.
	_Internal_Exists = 16,
	_Internal_PendingDestroy = 17,
}

EntityInfo :: struct {
	name : string,
	identifier : i32,
	flags : EntityFlags,
	component_set: ComponentSet,
	tag : u32,
	user_data : uintptr,
}

ComponentSet :: bit_set[ComponentType; u32]
ComponentType :: enum u32 {
	Transform 	 = 0,
	Camera 		 ,
	Light 		 ,
	Skybox		 ,
	MeshRenderer ,
	Collider 	 ,
}


// Flat constant size data blobs of components
// to make serialisation between file data and comp data
// easier. These Must Not hold any variable sized data or pointers
// of any kind. Flat Constant sized data only.
CameraCompData :: struct {
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


SkyboxCompData :: struct {
	color_zenith 	: [3]f32,
	color_horizon 	: [3]f32,
	color_nadir 	: [3]f32,
	exposure : f32,	
	rotation : f32,
}