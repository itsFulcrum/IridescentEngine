package iricom

import geo "odinary:geometry"
import "core:encoding/uuid"

MeshID :: distinct i32

VERTEX_LAYOUTS_ALL :: VertexDataLayoutFlags{.Minimal,.Standard,.Extended}
VertexDataLayoutFlags :: distinct bit_set[VertexDataLayout]
VertexDataLayout :: enum u32 {
	Minimal = 0,
	Standard,
	Extended,
}

VertexDataMinimal :: struct { // 24 bytes
	qtangent    : [4]f32, // quaternion (qTangent) encoding tangent space normal,tangent, bitangent
	texcoord_0 	: [2]f32,
}

VertexDataStandard :: struct { // 40 bytes
	qtangent    : [4]f32, // quaternion (qTangent) encoding tangent space normal,tangent, bitangent
	texcoord_0 	: [2]f32,
	// @note we should probaly have texcoord_1 here to fill the 16 byte gap..
	color_0 	: [4]f32,
}

VertexDataExtended :: struct { // 64 bytes
	qtangent    : [4]f32, // quaternion (qTangent) encoding tangent space normal,tangent, bitangent
	texcoord_0 	: [2]f32,
	texcoord_1 	: [2]f32,
	color_0 	: [4]f32,
	color_1 	: [4]f32,
}


MeshData :: struct {
	asset_uuid : uuid.Identifier,

	name : string,

	num_vertecies : u32,
	vertex_data_layout : VertexDataLayout,

	positions	 : [^]byte,	// position xyzw (16 bytes)
	vertex_data  : [^]byte, // interleaved according to vertex_data_layout

	num_indecies : u32,
	indecies: 	[^]u32,
	//shadow_indecies : [^]u32, // not used atm.

	aabb_min : [3]f32,
	aabb_max : [3]f32,

	bvh_num_nodes : u32,
	bvh_indecies  : [^]u32, // num bvh indecies is same as num indecies
	bvh_nodes     : [^]geo.BvhNode,

	// transform data
	transform : geo.Transform,
}

free_mesh_data :: proc(mesh_data : ^MeshData) {
	
	if mesh_data == nil {
		return;
	}

	if mesh_data.positions != nil {
		free(mesh_data.positions);
		mesh_data.positions = nil;
	}
	if mesh_data.indecies != nil {
		free(mesh_data.indecies);
		mesh_data.indecies = nil;
	}

	// if mesh_data.shadow_indecies != nil {
	// 	free(mesh_data.shadow_indecies);
	// 	mesh_data.shadow_indecies = nil;
	// }

	if mesh_data.vertex_data != nil {
		free(mesh_data.vertex_data);
		mesh_data.vertex_data = nil;
	}

	if len(mesh_data.name) > 0 {
		delete(mesh_data.name);
	}

	if mesh_data.bvh_indecies != nil {
		free(mesh_data.bvh_indecies);
	}

	if mesh_data.bvh_nodes != nil {
		free(mesh_data.bvh_nodes)
	}

	free(mesh_data);
}


get_vertex_layout_byte_size :: proc(layout : VertexDataLayout) -> int {
	
	switch layout {
		case .Minimal:  return size_of(VertexDataMinimal)
		case .Standard: return size_of(VertexDataStandard)
		case .Extended: return size_of(VertexDataExtended)
	}

	return 0;
}

