package iricom


DRAW_INSTANCE_FLAGS_DEFAULT :: DrawInstanceFlags{.IsVisible, .CastShadows}
DRAW_INSTANCE_FLAGS_INTERNAL :: DrawInstanceFlags{._Internal_NoValidMesh, ._Internal_ReuploadMatrixGPU}
DrawInstanceFlags :: distinct bit_set[DrawInstanceFlag]
DrawInstanceFlag :: enum u32 {
	IsStatic = 0,
	IsVisible,
	CastShadows,
	// Internal Usage only..
	_Internal_NoValidMesh,
	_Internal_ReuploadMatrixGPU, // notfy the matrix buffer update that this drawable must recompute/reupload the transform matrix.
}

DrawInstance :: struct {
	flags   	: DrawInstanceFlags,
	mesh_id 	: MeshID,
	mat_id  	: MaterialID,
	transform   : Transform,
}