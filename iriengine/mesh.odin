package iri


VertexDataLayout :: enum {
	Minimal = 0,
	Standard,
	Extended,
}

VertexDataMinimal :: struct {
	normal_tangent 	: [4]f32, // Octahedral Encoded, Normal.xy , Tangent.zw
	texcoord_0 	    : [2]f32,
}

VertexDataStandard :: struct {
	normal_tangent 	: [4]f32, // Octahedral Encoded
	color_0 	    : [4]f32,
	texcoord_0 	    : [2]f32,
}

VertexDataExtended :: struct {
	normal_tangent 	: [4]f32, // Octahedral Encoded
	color_0 		: [4]f32,
	color_1 		: [4]f32,
	texcoord_0 		: [2]f32,
	texcoord_1 		: [2]f32,
}


MeshData :: struct {
	name : string,

	vertex_data_layout : VertexDataLayout,
	num_vertecies : u32,
	positions	: [^][3]f32,
	normals  	: [^][3]f32,
	tangents 	: [^][3]f32,
	colors_0 	: [^][4]f32,
	colors_1 	: [^][4]f32,
	texcoords_0 : [^][2]f32,
	texcoords_1 : [^][2]f32,

	aabb_min : [3]f32,
	aabb_max : [3]f32,

	num_indecies : u32,
	indecies: 	[^]u32,

	// transform data
	transform: Transform,
}

// free internal memory of a mesh data struct
// this does not free the struct itself but only any data contain within it
mesh_data_destroy :: proc(mesh_data : ^MeshData){

	if mesh_data == nil {
		return;
	}

	delete(mesh_data.name);

	if mesh_data.positions != nil {
		free(mesh_data.positions);
	}

	if mesh_data.normals != nil {
		free(mesh_data.normals);
	}

	if mesh_data.tangents != nil {
		free(mesh_data.tangents);
	}

	if mesh_data.colors_0 != nil {
		free(mesh_data.colors_0);
	}
	
	if mesh_data.colors_1 != nil{
		free(mesh_data.colors_1);
	}
	
	if mesh_data.texcoords_0 != nil {
		free(mesh_data.texcoords_0);
	}

	if mesh_data.texcoords_1 != nil {
		free(mesh_data.texcoords_1);
	}

	if mesh_data.indecies != nil {
		free(mesh_data.indecies);
	}
}


