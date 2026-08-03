package iricom

// =========================================================================================================
// @Note: Any engine package can import 'iricom' but 'iricom' itself can _Not_ import other Engine packages! 
// =========================================================================================================

import geo "odinary:geometry"

DRAW_INSTANCE_FLAGS_DEFAULT :: DrawInstanceFlags{.IsVisible, .CastShadows,.IsRaycastVisible}
DRAW_INSTANCE_FLAGS_INTERNAL :: DrawInstanceFlags{._Internal_NoValidMesh, ._Internal_ReuploadMatrixGPU}
DrawInstanceFlags :: distinct bit_set[DrawInstanceFlag]
DrawInstanceFlag :: enum u32 {
	IsStatic = 0,
	IsVisible,
	CastShadows,
	IsRaycastVisible,
	// Internal Usage only..
	_Internal_NoValidMesh,
	_Internal_ReuploadMatrixGPU, // notfy the matrix buffer update that this drawable must recompute/reupload the transform matrix.
}

DrawInstance :: struct {
	flags   	: DrawInstanceFlags,
	mesh_id 	: MeshID,
	mat_id  	: MaterialID,
	transform   : geo.Transform,
}

// Better name for this ? we try to keep track of which draw instance maps to which material asset if any.
DrawableIndexReference :: struct {
	drawable_index : int,
	material_asset_id : AssetUUID,
}

DrawGroupAssetType :: enum u32 {
	Model = 0,
	//Mesh   = 1,
}

DrawGroup :: struct {

	asset_id   : AssetUUID,
	asset_drawable_type : DrawGroupAssetType,
	// #soa Array ? 
	drawable_index_refs   : [dynamic]DrawableIndexReference,
}


// @Note: Struct replicated on GPU
// Similar to MeshGlobalBufferInfo but less info and we use this one to upload to gpu.
DrawableGlobalBufferInfo :: struct #align(16) {
	bl_bvh_root_offset      : u32, // offset into global bl bvh buffer
	global_indecies_offset  : u32, // offset into global index buffer
	global_vertecies_offset : u32, // offset into global vertex buffer
	_ : u32, // Padding. Maybe material ID ? but then we need material type too. or we say only pbr materials are supported for gpu raytracing.
}

Drawable :: struct {
	entity : Entity,
	draw_instance  : DrawInstance,
	world_aabb : geo.AABB, // world space aabb
	world_oobb : geo.OBB,  // world space obb
	world_mat  : matrix[4,4]f32, // Local to World
	inv_world_mat  : matrix[4,4]f32, // World to Local
	global_buf_info : DrawableGlobalBufferInfo,
	prev_physics_world_transform : geo.Transform, // World Transform of the previous physics state!
}