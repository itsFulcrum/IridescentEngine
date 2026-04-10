package iricom


DRAW_INSTANCE_FLAGS_DEFAULT :: DrawInstanceFlags{.IsVisible, .CastShadows}
DRAW_INSTANCE_FLAGS_INTERNAL :: DrawInstanceFlags{._Internal_NoValidMesh, ._Internal_ForceUpdate, ._Internal_DisabledEntity}
DrawInstanceFlags :: distinct bit_set[DrawInstanceFlag]
DrawInstanceFlag :: enum u32 {
	IsStatic = 0,
	IsVisible,
	CastShadows,
	// Internal Usage only..
	_Internal_ForceUpdate,
	_Internal_NoValidMesh,
	_Internal_DisabledEntity,
}

DrawInstance :: struct {
	flags   	: DrawInstanceFlags,
	mesh_id 	: MeshID,
	mat_id  	: MaterialID,
	transform   : Transform,
}