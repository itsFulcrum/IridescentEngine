package iria

import "core:log"

import "core:os"
import "core:mem"
import "core:strings"

import geo "odinary:geometry"
import reader "odinary:readbinary"
import iricom "../iricommon"

// Typedefs
VertexDataLayout :: iricom.VertexDataLayout

VertexDataMinimal :: iricom.VertexDataMinimal
VertexDataStandard :: iricom.VertexDataStandard
VertexDataExtended :: iricom.VertexDataExtended

MeshData :: iricom.MeshData

// FILE IO

MESH_ASSET_CURRENT_VERSION : u32 : 1

MeshAssetHeader_v1 :: struct #packed {
	has_name : b32,
	vertex_data_layout : VertexDataLayout,

	num_vertecies : u32,
	num_indecies  : u32,
	
	aabb_min : [3]f32,
	aabb_max : [3]f32,

	transform_position       : [3]f32,
	transform_scale          : [3]f32,
	transform_orientation    : quaternion128,
}

MeshAssetBufferType :: enum u16 {
	NameStr = 0,
	Indecies_u16,
	Indecies_u32,
	Positions_3f32,
	VertexData,
}

MeshAssetBufferInfo :: struct #packed {
	type : MeshAssetBufferType,
	byte_size : u64,
}

asset_mesh_read_from_path :: proc(filepath : string) -> (mesh_data : ^MeshData, ok : bool) {

	file, open_err := os.open(filepath);
	if open_err != os.ERROR_NONE {
		return;
	}
	defer os.close(file);

	b_reader := reader.create_file_reader(file);
	return asset_mesh_read(&b_reader);
}

asset_mesh_read_from_memory :: proc(data : []byte) -> (mesh_data : ^MeshData, ok : bool) {
	b_reader := reader.create_memory_reader(data);
	return asset_mesh_read(&b_reader);
}

@(private="file")
asset_mesh_read :: proc(b_reader : ^$T) -> (mesh_data : ^MeshData, ok : bool) where T == reader.FileBinaryReader || T == reader.MemBinaryReader {
	common_hdr := reader.consume_copy_type(b_reader, IriAssetCommonHeader) or_return;

	if common_hdr.asset_type != AssetType.Mesh {
		return nil, false;
	}

	switch common_hdr.asset_type_version {
		case 1: return asset_mesh_read_v1(b_reader, common_hdr);
	}

	// invalid or depricated version
	return nil, false;
}

@(private="file")
asset_mesh_read_v1 :: proc(b_reader : ^$T, common_hdr : IriAssetCommonHeader) -> (mesh_data : ^MeshData, ok : bool) {

	mesh_data = new(MeshData);

	defer if !ok {
		iricom.free_mesh_data(mesh_data);
		mesh_data = nil;
	}
	
	mesh_data.asset_uuid = common_hdr.asset_uuid;

	mesh_hdr : ^MeshAssetHeader_v1 = reader.consume_make_type(b_reader, MeshAssetHeader_v1, context.temp_allocator) or_return;

	{
		if !mesh_hdr.has_name {
			mesh_data.name = strings.clone(string("Unnamed"), context.allocator);
		}

		mesh_data.vertex_data_layout 	= mesh_hdr.vertex_data_layout;
		mesh_data.num_vertecies 		= mesh_hdr.num_vertecies;
		mesh_data.num_indecies 			= mesh_hdr.num_indecies;

		mesh_data.aabb_min 				= mesh_hdr.aabb_min;
		mesh_data.aabb_max 				= mesh_hdr.aabb_max;

		mesh_data.transform.position 	= mesh_hdr.transform_position;
		mesh_data.transform.scale 		= mesh_hdr.transform_scale;
		mesh_data.transform.orientation = mesh_hdr.transform_orientation;
	}

	for reader.remaining_bytes(b_reader) > 0 {

		buf_info : MeshAssetBufferInfo = reader.consume_copy_type(b_reader, MeshAssetBufferInfo) or_return;
		buf_size : int = cast(int)buf_info.byte_size;

		switch buf_info.type {
			case .NameStr: {
				mesh_data.name = reader.consume_make_string(b_reader, buf_size, context.allocator) or_return;
			}
			case .Indecies_u16: {
				unimplemented();
			}
			case .Indecies_u32: {
				
				expected_byte_size : int = cast(int)mesh_data.num_indecies * size_of(u32);
				assert(expected_byte_size == buf_size);

				mesh_data.indecies = make_multi_pointer([^]u32, cast(int)mesh_data.num_indecies, context.allocator);
				reader.consume_mem_copy(b_reader, &mesh_data.indecies[0], expected_byte_size) or_return;			
			}
			case .Positions_3f32: {
				
				expected_byte_size : int = cast(int)mesh_data.num_vertecies * size_of([3]f32);
				assert(expected_byte_size == buf_size);

				mesh_data.positions = make_multi_pointer([^]byte, expected_byte_size, context.allocator);
				reader.consume_mem_copy(b_reader, &mesh_data.positions[0], expected_byte_size) or_return;
			}
			case .VertexData: {
				expected_byte_size : int = cast(int)mesh_data.num_vertecies * iricom.get_vertex_layout_byte_size(mesh_data.vertex_data_layout);
				assert(expected_byte_size == buf_size);
				
				mesh_data.vertex_data = make_multi_pointer([^]byte, expected_byte_size, context.allocator);
				reader.consume_mem_copy(b_reader, &mesh_data.vertex_data[0], expected_byte_size) or_return;
			}
		}
	}

	// Validate that we have everything

	assert(mesh_data.indecies != nil);
	assert(mesh_data.positions != nil);
	assert(mesh_data.vertex_data != nil);

	assert(mesh_data.num_indecies > 0);
	assert(mesh_data.num_vertecies > 0);

	return mesh_data, true,
}

asset_mesh_write_to_file :: proc(filepath : string, mesh_data : ^MeshData, write_flags : WriteFlags) -> (ok : bool){

	log_errors : bool = .LogErrors in write_flags;

	if mesh_data == nil {
		return false;
	}

	assert(mesh_data.indecies != nil);
	assert(mesh_data.positions != nil);
	assert(mesh_data.vertex_data != nil);
	
	assert(mesh_data.num_vertecies > 0);
	assert(mesh_data.num_indecies  > 0);
	assert(mesh_data.asset_uuid != AssetUUID_INVALID)

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

	// @Note:
	// we setup this defer block here and initialize successful to false
	// if we encounter any error we return imidiatly from this procedure and this cleanup code will run
	// if everything works out as expected, we set succesfull to true at the very end and wont run any cleanup

	successful : bool = false;

	defer {

		os.close(file);
		
		if !successful {

			// it should exist now.
			if os.exists(filepath) {
				remove_err := os.remove(filepath);
				// not sure what to do now except log the error.
				// if removing also faild we cant do much more ig.
				if remove_err != os.ERROR_NONE {
					if log_errors do log.errorf("IriAsset: Failed to remove file after aborted and incomplete file writing. {}, error code: {}", filepath, remove_err);
				}
			}
		}
	}

	is_no_write_error :: proc(err : os.Error, filepath : string, log_error : bool) -> bool {
		
		if err != os.ERROR_NONE {
			if log_error do log.errorf("IriAsset: Failed to write into file: Error Code: {}, filepath: {}", err, filepath);
			return false;
		}

		return true;
	}

	// Common Header
	{
		hdr : IriAssetCommonHeader = create_common_header(AssetType.Mesh, mesh_data.asset_uuid);

		written_bytes , write_err := os.write_ptr(file, &hdr, size_of(IriAssetCommonHeader));
		is_no_write_error(write_err, filepath, log_errors) or_return;
				
	}
	
	// Mesh Header
	mesh_hdr : MeshAssetHeader_v1;	
	{
		has_name : bool = len(mesh_data.name) > 0 ? true : false;
		
		mesh_hdr.has_name = cast(b32)has_name;
		mesh_hdr.vertex_data_layout = mesh_data.vertex_data_layout;

		mesh_hdr.num_vertecies 			= mesh_data.num_vertecies;
		mesh_hdr.num_indecies  			= mesh_data.num_indecies;
		mesh_hdr.aabb_min 				= mesh_data.aabb_min;
		mesh_hdr.aabb_max 				= mesh_data.aabb_max;
		mesh_hdr.transform_position     = mesh_data.transform.position;
		mesh_hdr.transform_scale 		= mesh_data.transform.scale;
		mesh_hdr.transform_orientation  = mesh_data.transform.orientation;

		written_bytes , write_err := os.write_ptr(file, &mesh_hdr, size_of(MeshAssetHeader_v1));
		is_no_write_error(write_err, filepath, log_errors) or_return;
	}

	// Name String -- Optional
	{
		if mesh_hdr.has_name {

			buf_info := MeshAssetBufferInfo{
				type = MeshAssetBufferType.NameStr,
				byte_size = cast(u64)len(mesh_data.name),
			}
			written_bytes , write_err := os.write_ptr(file, &buf_info, size_of(MeshAssetBufferInfo));
			is_no_write_error(write_err, filepath, log_errors) or_return;
			
			written_bytes1 , write_err1 := os.write_string(file, mesh_data.name);
			is_no_write_error(write_err1, filepath, log_errors) or_return;

			assert(written_bytes1 == len(mesh_data.name));
		}
	}

	// Indecies 
	{
		// @Note: we currently only support u32 indecies but we may want to compress it to u16 for file storage if possible
		indecie_elem_size   : int = size_of(u32);
		indecies_buf_size   : int = cast(int)mesh_data.num_indecies * indecie_elem_size; 
		
		buf_info := MeshAssetBufferInfo{
			type = MeshAssetBufferType.Indecies_u32,
			byte_size = cast(u64)indecies_buf_size,
		}
		info_written_bytes , info_write_err := os.write_ptr(file, &buf_info, size_of(MeshAssetBufferInfo));
		is_no_write_error(info_write_err, filepath, log_errors) or_return;

		buf_written_bytes , buf_write_err := os.write_ptr(file, &mesh_data.indecies[0], indecies_buf_size);
		is_no_write_error(buf_write_err, filepath, log_errors) or_return;
	}

	// Positions 
	{
		position_elem_size  : int = size_of([3]f32);
		position_buf_size  : int = cast(int)mesh_data.num_vertecies * position_elem_size;
		
		buf_info := MeshAssetBufferInfo{
			type = MeshAssetBufferType.Positions_3f32,
			byte_size = cast(u64)position_buf_size,
		}
		info_written_bytes , info_write_err := os.write_ptr(file, &buf_info, size_of(MeshAssetBufferInfo));
		is_no_write_error(info_write_err, filepath, log_errors) or_return;

		buf_written_bytes , buf_write_err := os.write_ptr(file, &mesh_data.positions[0], position_buf_size);
		is_no_write_error(buf_write_err, filepath, log_errors) or_return;
	}

	// Vertex Data Interleaved buffer
	{
		vert_data_elem_size : int = iricom.get_vertex_layout_byte_size(mesh_data.vertex_data_layout);
		vert_data_buf_size : int = cast(int)mesh_data.num_vertecies * vert_data_elem_size; 

		buf_info := MeshAssetBufferInfo{
			type = MeshAssetBufferType.VertexData,
			byte_size = cast(u64)vert_data_buf_size,
		}
		info_written_bytes , info_write_err := os.write_ptr(file, &buf_info, size_of(MeshAssetBufferInfo));
		is_no_write_error(info_write_err, filepath, log_errors) or_return;

		buf_written_bytes , buf_write_err := os.write_ptr(file, &mesh_data.vertex_data[0], vert_data_buf_size);
		is_no_write_error(buf_write_err, filepath, log_errors) or_return;
	}

	// we need to set this to true here so we dont run any cleanup from the defer block above.
	successful = true;
	return true;
}
