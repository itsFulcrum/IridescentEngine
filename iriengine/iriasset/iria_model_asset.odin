package iria
	
import "core:log"

import "core:os"
import "core:mem"
import "core:fmt"
import "core:strings"

import iricom "../iricommon"
import geo "odinary:geometry"
import reader "odinary:readbinary"

// @ Model Asset File Layout
/*

@Note: First we store a bunch of header information.

-- CommonHeader  - Type: IriAssetCommonHeader | Size: size_of(IriAssetCommonHeader) (32 bytes)
-- AssetAliasStr - Type: IriAssetString128 	  | Size: size_of(IriAssetString128) (128 bytes) - can be just zero memory (no alias).
-- ModelHeader   - Type: ModelAssetHeader_v1  | Size: size_of(ModelAssetHeader_v1) (100 bytes)
-- ModelNameStr  - Type: IriAssetString64     | Size: size_of(IriAssetString64) (64 bytes) - can be just zero memory (no name).


Contigous Array Of material AssetUUIDs. Each submesh refers to one but it can be an InvalidUUID so no material assigned.
-- Material IDs  - Type: [ModelHeader.num_meshes]AssetUUID | Size: size_of(AssetUUID) * ModelHeader.num_meshes

Contigous Array of u64. Each submesh stores its absolute file offset here. Can use this for streaming.
-- Submesh File Offsets - [ModelHeader.num_meshes]u64 	|  Size: size_of(u64) * ModelHeader.num_meshes 

@Note: 	Now we come to the actual Mesh data. The Model file can store many sub-meshes but no hierarchy is supported.
		So we store each submesh one ofter the other. File Offsets can be used to jump to a specific submesh directly
		the file Offset are absolute to the beginning of the file.

Foreach Mesh {

-- MeshHeader          - Type: MeshAssetHeader       | Size: size_of(MeshAssetHeader);
-- MeshName            - Type: IriAssetString64  | Size: size_of(IriAssetString64);
-- Indecies Buffer     - Type: [^]u32  			 | Size: MeshHeader.num_indecies  * size_of(u32)
-- Positions Buffer    - Type: [^]byte 			 | Size: MeshHeader.num_vertecies * size_of([4]f32) | @ xyzw per position, 4 floats.

// @Note: Vertex Data can be packed in 3 different formats based on MeshHeader.vertex_data_layout. The byte size for each Vertex can therefore vary.
-- Vertex Data buffer  - Type: [^]byte 			 | Size: MeshHeader.num_vertecies * iricom.get_vertex_layout_byte_size(MeshHeader.vertex_data_layout);
-- Bvh Indecies Buffer - Type: [^]u32 			 | Size: MeshHeader.num_indecies  * size_of(u32)
-- Bvh nodes Buffer    - Type: [^]geo.BvhNode    | Size: MeshHeader.num_bvh_nodes * size_of(geo.BvhNode)
}

*/



MODEL_ASSET_CURRENT_VERSION : u32 : 1

ModelAssetHeader_v1 :: struct #packed {

	num_meshes     : u32, 
	offsets_byte_size : u64, // = num_submeshes * sizeof(u64). Usefull if we dont care about offsets and just want to jump to where the first mesh is.

	aabb_min : [3]f32,
	aabb_max : [3]f32,

	// Needed ?
	transform_position       : [3]f32,
	transform_scale          : [3]f32,
	transform_orientation    : quaternion128,

	_ : [6]u32, // reserved
}


MeshAssetHeader :: struct #packed {

	vertex_data_layout : VertexDataLayout,

	num_indecies  : u32,
	num_vertecies : u32,
	num_bvh_nodes : u32,
	
	aabb_min : [3]f32,
	aabb_max : [3]f32,

	transform_position       : [3]f32,
	transform_scale          : [3]f32,
	transform_orientation    : quaternion128,

	_ : [6]u32, // reserved
}

asset_model_read_from_path :: proc(filepath : string) -> (model : ^iricom.ModelAsset, ok : bool) {

	file, open_err := os.open(filepath);
	if open_err != os.ERROR_NONE {
		return;
	}
	defer os.close(file);

	f_reader := reader.create_file_reader(file);
	return asset_model_read(&f_reader);
}

asset_model_read_from_memory :: proc(data : []byte) -> (model : ^iricom.ModelAsset, ok : bool) {
	m_reader := reader.create_memory_reader(data);
	return asset_model_read(&m_reader);
}


@(private="file")
asset_model_read :: proc(b_reader : ^$T) -> (model : ^iricom.ModelAsset, ok : bool) where T == reader.FileBinaryReader || T == reader.MemBinaryReader {
	
	common_hdr := reader.consume_copy_type(b_reader, IriAssetCommonHeader) or_return;

	if common_hdr.asset_type != AssetType.Model {
		return nil, false;
	}

	switch common_hdr.asset_type_version {
		case 1: return asset_model_read_v1(b_reader, common_hdr);
	}

	// invalid or depricated version
	return nil, false;
}

@(private="file")
asset_model_read_v1 :: proc(b_reader : ^$T, common_hdr : IriAssetCommonHeader) -> (model : ^iricom.ModelAsset, ok : bool) {

	model = new(iricom.ModelAsset);

	defer if !ok {
		iricom.free_model_asset(model);
		model = nil;
	}
	
	model.asset_id = common_hdr.asset_uuid;

	// Read Alias string
	model_alias128 : IriAssetString128 = reader.consume_copy_type(b_reader, IriAssetString128) or_return;
	model_alias_str, model_has_alias := string_clone_from_asset_string128(&model_alias128, context.allocator);
	if model_has_alias {
		model.asset_alias = model_alias_str;
	}

	// Model Header
	model_hdr : ^ModelAssetHeader_v1 = reader.consume_make_type(b_reader, ModelAssetHeader_v1, context.temp_allocator) or_return;
	{
		model.aabb = geo.aabb_from_min_max_vec3(model_hdr.aabb_min, model_hdr.aabb_max);
		model.transform.position 	= model_hdr.transform_position;
		model.transform.scale 		= model_hdr.transform_scale;
		model.transform.orientation = model_hdr.transform_orientation;
	}

	// Model Name
	{
		model_name64 : IriAssetString64 = reader.consume_copy_type(b_reader, IriAssetString64) or_return;
		model_name_str, model_has_name := string_clone_from_asset_string64(&model_name64, context.allocator);
		if model_has_name {
			model.name = model_name_str;
		} else {
			model.name = strings.clone("UnnamedModel", context.allocator);
		}
	}


	// Materials
	num_meshes : int = cast(int)model_hdr.num_meshes;
	model.material_ids = reader.consume_make_slice(b_reader, []AssetUUID, num_meshes, context.allocator) or_return;

	// We dont care about offset here.
	offsets_byte_size : int = cast(int)model_hdr.offsets_byte_size;
	reader.advance(b_reader, offsets_byte_size);


	meshes : [dynamic]^MeshData

	for i in 0..<num_meshes {
		
		mesh_data : ^MeshData = new(MeshData);
		defer {
			append(&meshes, mesh_data);
		} 

		// -- MeshHeader          - Type: MeshAssetHeader       | Size: size_of(MeshAssetHeader);
		mesh_hdr : MeshAssetHeader = reader.consume_copy_type(b_reader, MeshAssetHeader) or_return;
		{
			mesh_data.num_vertecies 		= mesh_hdr.num_vertecies;
			mesh_data.vertex_data_layout 	= mesh_hdr.vertex_data_layout;
			mesh_data.num_indecies 			= mesh_hdr.num_indecies;
			mesh_data.aabb_min 				= mesh_hdr.aabb_min;
			mesh_data.aabb_max 				= mesh_hdr.aabb_max;
			mesh_data.bvh_num_nodes 		= mesh_hdr.num_bvh_nodes;
			mesh_data.transform.position 	= mesh_hdr.transform_position;
			mesh_data.transform.scale 		= mesh_hdr.transform_scale;
			mesh_data.transform.orientation = mesh_hdr.transform_orientation;
		}

		// -- MeshName            - Type: IriAssetString64   | Size: size_of(IriAssetString64);
		{
			mesh_name_64 : IriAssetString64 = reader.consume_copy_type(b_reader, IriAssetString64) or_return;
			mesh_name_str, mesh_has_name := string_clone_from_asset_string64(&mesh_name_64, context.allocator);
			if mesh_has_name {
				mesh_data.name = mesh_name_str;
			} else {

				new_mesh_name := fmt.aprintf("{}_{}", model.name,i, context.allocator);

				mesh_data.name = new_mesh_name;
			}
		}

		// -- Indecies Buffer     - Type: [^]u32  			 | Size: MeshHeader.num_indecies  * size_of(u32)
		{
			indecies_buf_size : int = cast(int)mesh_data.num_indecies * size_of(u32);

			mesh_data.indecies = make_multi_pointer([^]u32, cast(int)mesh_data.num_indecies, context.allocator);
			reader.consume_mem_copy(b_reader, &mesh_data.indecies[0], indecies_buf_size) or_return;
		}

		// -- Positions Buffer    - Type: [^]byte 			 | Size: MeshHeader.num_vertecies * size_of([4]f32) | @ xyzw per position, 4 floats.
		{		
			positions_byte_size : int = cast(int)mesh_data.num_vertecies * size_of([4]f32);

			mesh_data.positions = make_multi_pointer([^]byte, positions_byte_size, context.allocator);
			reader.consume_mem_copy(b_reader, &mesh_data.positions[0], positions_byte_size) or_return;
		}

		// // @Note: Vertex Data can be packed in 3 different formats based on MeshHeader.vertex_data_layout. The byte size for each Vertex can therefore vary.
		// -- Vertex Data buffer  - Type: [^]byte 			 | Size: MeshHeader.num_vertecies * iricom.get_vertex_layout_byte_size(MeshHeader.vertex_data_layout);
		{
			vert_data_byte_size : int = cast(int)mesh_data.num_vertecies * iricom.get_vertex_layout_byte_size(mesh_data.vertex_data_layout);
						
			mesh_data.vertex_data = make_multi_pointer([^]byte, vert_data_byte_size, context.allocator);
			reader.consume_mem_copy(b_reader, &mesh_data.vertex_data[0], vert_data_byte_size) or_return;
		}

		// -- Bvh Indecies Buffer - Type: [^]u32 			 | Size: MeshHeader.num_indecies  * size_of(u32)
		{
			bvh_indecies_byte_size : int = cast(int)mesh_data.num_indecies * size_of(u32);
			
			mesh_data.bvh_indecies =  make_multi_pointer([^]u32, cast(int)mesh_data.num_indecies, context.allocator);
			reader.consume_mem_copy(b_reader, &mesh_data.bvh_indecies[0], bvh_indecies_byte_size) or_return;
		}
		
		// -- Bvh nodes Buffer    - Type: [^]geo.BvhNode     | Size: MeshHeader.num_bvh_nodes * size_of(geo.BvhNode)		
		{
			bvh_node_byte_size : int = cast(int)mesh_data.bvh_num_nodes * size_of(geo.BvhNode);

			mesh_data.bvh_nodes = make_multi_pointer([^]geo.BvhNode, cast(int)mesh_data.bvh_num_nodes, context.allocator);
			reader.consume_mem_copy(b_reader, &mesh_data.bvh_nodes[0], bvh_node_byte_size) or_return;
		}

	} // End Meshes loop


	assert(len(meshes) == num_meshes);
	assert(len(meshes) == len(model.material_ids));

	model.meshes = meshes[:];


	return model, true,
}

asset_model_write_to_file :: proc(filepath : string, model : ^iricom.ModelAsset, write_flags : WriteFlags) -> (ok : bool) {

	log_errors : bool = .LogErrors in write_flags;

	if model == nil {
		return false;
	}

	assert(model.asset_id != AssetUUID_INVALID);		
	assert(len(model.meshes) > 0);
	assert(len(model.meshes) == len(model.material_ids));

	file_exists_already := validate_write_filepath(filepath, log_errors) or_return;

	if file_exists_already && .OverwriteExisting not_in write_flags {
		if log_errors do log.errorf("IriAsset: Failed to write asset file, 'OverwriteExisting' flag is not set and file already exists. Path: {}", filepath);
		return false;
	}

	file, open_err := os.open(filepath, flags = os.File_Flags{.Write, .Create, .Trunc});

	if open_err != os.ERROR_NONE {
		if log_errors do log.errorf("IriAsset: Failed to open file for writing with error code: {}, path: {}", filepath);
		return false;
	}


	defer if !ok {
		_ = try_delete_file(filepath, log_errors);
	}
	defer os.close(file);


	// Common Header
	{
		asset_flags : IriAssetFlags = ASSET_FLAGS_NONE;

		if len(model.asset_alias) > 0 {
			asset_flags += IriAssetFlags{.HasAlias};
		}

		hdr : IriAssetCommonHeader = create_common_header(AssetType.Model, model.asset_id, MODEL_ASSET_CURRENT_VERSION, asset_flags);

		written_bytes , write_err := os.write_ptr(file, &hdr, size_of(IriAssetCommonHeader));
		is_no_write_error(write_err, filepath, log_errors) or_return;		

		alias, has_alias := string_to_asset_string128(model.asset_alias); 

		alias_written_bytes, alias_write_err := os.write_ptr(file, &alias, size_of(IriAssetString128));
		is_no_write_error(alias_write_err, filepath, log_errors) or_return;
	}


	num_possible_submeshes : int = len(model.meshes);
	submesh_is_valid : []bool = make_slice([]bool, len(model.meshes), context.temp_allocator)
	num_valid_submeshes : int = 0;

	// =============================
	// ====== Validate Submeshes ===
	// =============================

	for i in 0..<len(model.meshes) {
		
		if model.meshes[i] == nil {
			continue;
		}

		if model.meshes[i].indecies    == nil {
			continue;
		}
		if model.meshes[i].positions   == nil {
			continue;
		}
		if model.meshes[i].vertex_data == nil {
			continue;
		}
	
		if model.meshes[i].num_vertecies <= 0  {
			continue;
		}
		if model.meshes[i].num_indecies  <= 0  {
			continue;
		}

		// Bvh
		if model.meshes[i].bvh_num_nodes  <= 0  {
			continue;
		}
		if model.meshes[i].bvh_indecies   == nil {
			continue;
		}
		if model.meshes[i].bvh_nodes == nil {
			continue;
		}


		num_valid_submeshes += 1;
		submesh_is_valid[i] = true;
	}

	if num_valid_submeshes <= 0 {

		if log_errors do log.errorf("IriAsset: Failed to write ModelAsset file because no valid submeshes exist. Path: {}", filepath);
		return false;
	}

	// Model Header
	{
		model_hdr : ModelAssetHeader_v1;	
		
		model_hdr.num_meshes     = cast(u32)num_valid_submeshes;
		model_hdr.offsets_byte_size = cast(u64)model_hdr.num_meshes * size_of(u64);

		model_hdr.aabb_min 				 = model.aabb.min.xyz;
		model_hdr.aabb_max 				 = model.aabb.max.xyz;
		model_hdr.transform_position     = model.transform.position;
		model_hdr.transform_scale 		 = model.transform.scale;
		model_hdr.transform_orientation  = model.transform.orientation;
		
		written_bytes , write_err := os.write_ptr(file, &model_hdr, size_of(ModelAssetHeader_v1));
		is_no_write_error(write_err, filepath, log_errors) or_return;
	}

	model_name, model_has_name := string_to_asset_string64(model.name);
	{
		written_bytes , write_err := os.write_ptr(file, &model_name, size_of(IriAssetString64));
		is_no_write_error(write_err, filepath, log_errors) or_return;
	}


	// =====

	current_file_byte_offset : u64 = size_of(IriAssetCommonHeader) + size_of(IriAssetString128) + size_of(ModelAssetHeader_v1) + size_of(IriAssetString64);

	expected_material_ids_byte_size : u64 = cast(u64)(size_of(AssetUUID) * num_valid_submeshes);
	actual_material_ids_byte_size : u64 = 0;

	// Write Material IDs
	// @Speed. If all submeshes are valid we can just write the entire slice at once.
	for i in 0..<num_possible_submeshes {
		if !submesh_is_valid[i]{
			continue;
		}
		written_bytes , write_err := os.write_ptr(file, &model.material_ids[i], size_of(AssetUUID));
		is_no_write_error(write_err, filepath, log_errors) or_return;

		actual_material_ids_byte_size += cast(u64)written_bytes;
	}

	assert(expected_material_ids_byte_size == actual_material_ids_byte_size);
	
	current_file_byte_offset += expected_material_ids_byte_size;


	// ====== Submeshes File Offsets ======

	submeshes_file_offsets_begin_byte : u64 = current_file_byte_offset;
	submeshes_file_offsets_byte_size  : int = size_of(u64) * num_valid_submeshes;

	// Allocate space to store all offsets.
	// @Note For now we first write the zero initialized array and come back later to overwrite it once we actually know the offsets.
	submesh_file_offsets : []u64 = make_slice([]u64, num_valid_submeshes, context.temp_allocator);
	{
		written_bytes , write_err := os.write_ptr(file, &submesh_file_offsets[0], submeshes_file_offsets_byte_size);
		is_no_write_error(write_err, filepath, log_errors) or_return;
	}


	current_file_byte_offset += cast(u64)(num_valid_submeshes * size_of(u64));

	// =============================
	// ====== Write Submeshes ======
	// =============================

	valid_submesh_file_offset : u64 = current_file_byte_offset;
	valid_submesh_index : int = 0;

	for i in 0..<num_possible_submeshes {
		if !submesh_is_valid[i]{
			continue;
		}

		submesh_byte_size : u64 = 0;

		mesh_data := model.meshes[i];


		// -- SubMesh Info --
		{
			info_buf_size : int = size_of(MeshAssetHeader);

			submesh_info := MeshAssetHeader {
				vertex_data_layout = mesh_data.vertex_data_layout,
				
				num_indecies  = mesh_data.num_indecies,
				num_vertecies = mesh_data.num_vertecies,
				num_bvh_nodes = mesh_data.bvh_num_nodes,
				
				aabb_min = mesh_data.aabb_min,
				aabb_max = mesh_data.aabb_max,

				transform_position    = mesh_data.transform.position,
				transform_scale       = mesh_data.transform.scale,
				transform_orientation = mesh_data.transform.orientation,
			}

			buf_written_bytes , buf_write_err := os.write_ptr(file, &submesh_info, info_buf_size);
			is_no_write_error(buf_write_err, filepath, log_errors) or_return;

			submesh_byte_size += cast(u64)info_buf_size;
		}

		// -- Mesh Name --
		{
			name_buf_size : int = size_of(IriAssetString64);
			mesh_name_64, has_name := string_to_asset_string64(mesh_data.name);

			buf_written_bytes , buf_write_err := os.write_ptr(file, &mesh_name_64, name_buf_size);
			is_no_write_error(buf_write_err, filepath, log_errors) or_return;
			submesh_byte_size += cast(u64)name_buf_size;
		}

		// -- Indecies -- 
		// @Note: we currently only support u32 indecies but we may want to compress it to u16 for file storage if possible
		{

			indecie_elem_size   : int = size_of(u32);
			indecies_buf_size   : int = cast(int)mesh_data.num_indecies * indecie_elem_size; 
			
			buf_written_bytes , buf_write_err := os.write_ptr(file, &mesh_data.indecies[0], indecies_buf_size);
			is_no_write_error(buf_write_err, filepath, log_errors) or_return;
			
			submesh_byte_size += cast(u64)indecies_buf_size;		
		}

		// -- Positions -- 
		{
			position_elem_size  : int = size_of([4]f32);
			position_buf_size   : int = cast(int)mesh_data.num_vertecies * position_elem_size;
			
			buf_written_bytes , buf_write_err := os.write_ptr(file, &mesh_data.positions[0], position_buf_size);
			is_no_write_error(buf_write_err, filepath, log_errors) or_return;

			submesh_byte_size += cast(u64)position_buf_size;
		}

		// -- Interleaved Layout Vertex Data --
		{
			vert_data_elem_size : int = iricom.get_vertex_layout_byte_size(mesh_data.vertex_data_layout);
			vert_data_buf_size  : int = cast(int)mesh_data.num_vertecies * vert_data_elem_size; 

			buf_written_bytes , buf_write_err := os.write_ptr(file, &mesh_data.vertex_data[0], vert_data_buf_size);
			is_no_write_error(buf_write_err, filepath, log_errors) or_return;

			submesh_byte_size += cast(u64)vert_data_buf_size;
		}

		// -- Bvh Indecies data --
		{
			bvh_indecie_elem_size   : int = size_of(u32);
			bvh_indecies_buf_size   : int = cast(int)mesh_data.num_indecies * bvh_indecie_elem_size; 
			

			buf_written_bytes , buf_write_err := os.write_ptr(file, &mesh_data.bvh_indecies[0], bvh_indecies_buf_size);
			is_no_write_error(buf_write_err, filepath, log_errors) or_return;

			submesh_byte_size += cast(u64)bvh_indecies_buf_size;
		}

		// -- Bvh nodes --
		{
			bvh_node_elem_size   : int = size_of(geo.BvhNode);
			bvh_node_buf_size   : int = cast(int)mesh_data.bvh_num_nodes * bvh_node_elem_size; 
			
			buf_written_bytes , buf_write_err := os.write_ptr(file, &mesh_data.bvh_nodes[0], bvh_node_buf_size);
			is_no_write_error(buf_write_err, filepath, log_errors) or_return;

			submesh_byte_size += cast(u64)bvh_node_buf_size;		
		}

		// store the current file offset for this submesh.
		submesh_file_offsets[valid_submesh_index] = current_file_byte_offset;
		current_file_byte_offset += submesh_byte_size;

		valid_submesh_index += 1;
	} // End Submeshes loop.


	// TODO: does write_at() truncate everything after it ??.

	// Write Submesh File Offsets
	{
		// Write Submesh Offsets.

		// @Speed. is there a way to cast this ?
		file_offsets_bytes : []byte = make_slice([]byte, submeshes_file_offsets_byte_size, context.temp_allocator);
		mem.copy(&file_offsets_bytes[0], &submesh_file_offsets[0], submeshes_file_offsets_byte_size);

		written_bytes , write_err := os.write_at(file, file_offsets_bytes, cast(i64)submeshes_file_offsets_begin_byte);
		is_no_write_error(write_err, filepath, log_errors) or_return;
	}

	return true;
}