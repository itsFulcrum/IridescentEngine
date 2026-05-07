package iria

import "core:log"
import "core:os"
import "core:mem"
import "core:strings"

import geo "odinary:geometry"
import reader "odinary:readbinary"
import iricom "../iricommon"

EntityInfoPacked :: struct {
	flags 		: iricom.EntityFlags,
	comp_set 	: iricom.ComponentSet,
	tag 		: u32,
}

CompIndexes :: struct {
	camera_index   : i32,
	skybox_index   : i32,
	light_index    : i32,
	meshren_index  : i32,
	collider_index : i32,
	_ : [3]i32, // reserved.
}

MeshRendererCompData :: struct {
	num_drawable_assets : u32, // number of DrawableAssets that belong to this component.
	array_offset : u32, // offset into drawable_assets array of universe asset.
}

ColliderCompData :: struct #packed {
	type  : u32, // Collider type enum
	flags : u32, // ColliderFlags enum bitset of collider component
	offset : [3]f32,
	extent : [3]f32,
	orientation : quaternion128,
}

DrawableAsset :: struct {
	draw_instance_asset : DrawInstanceAsset,
	transform : geo.Transform,
}

UniverseAssetSettings :: struct #packed {	
	shadow_cascade_near_far_scale 	: f32,
	shadow_cascade_side_scale 		: f32,
	shadow_cascade_split_1 			: f32,
	shadow_cascade_split_2 			: f32,
	shadow_cascade_split_3 			: f32,

	// TODO: these bools should have an explicit size!! b8
	cull_shadow_draws 			: b8,
    do_frustum_culling 			: b8,
    _ : b8,
    _ : b8,
    _ : [16]u32, // reserved.
}

UniverseAsset :: struct {
	asset_uuid : AssetUUID,
	name       : string,
	tag 	   : u32,

	settings : UniverseAssetSettings,

	active_camera_entity : int, // index into entity slices below, or -1 if not set.
	active_skybox_entity : int, // index into entity slices below, or -1 if not set.

	
	num_entities : u32,
	// These MUST all have length of num_entities!
	entity_names : []string, 			// @Note: individual strings are not freed by 'free_universe_asset()', expected to be allocated with arena or manually freed by caller.
	entity_infos : []EntityInfoPacked,
	entity_trans : []geo.Transform,
	entity_comp_indexes : []CompIndexes,


	camera_comp_data  : []iricom.CameraCompData,
	skybox_comp_data  : []iricom.SkyboxCompData,
	light_comp_data   : []LightAsset,
	meshren_comp_data : []MeshRendererCompData,
	collider_comp_data : []ColliderCompData,

	// This array is ORDERED by mesh renderer component. 
	// such that MeshRendererCompData gives an offset where to start reading drawable asset form
	// this array, and a number of how many drawable assets to read consecutavly.
	drawable_assets_array : []DrawableAsset,
}



UNIVERSE_ASSET_CURRENT_VERSION : u32 : 2

// =============== File IO ============================
// Universe Asset file first write the Common Header which is followed by the 'UniverseAssetFirstHeader_v2' header. This 
// contains the universe tag and number of bytes of the universe name string. The Name string comes imideatly after the 'UniverseAssetFirstHeader_v2' header.
// After the name comes the Second 'UniverseAssetSecondHeader_v2' header that can hold some extra information.
// After that header ther is always a 12 byte 'UniAssetBufferInfo' structure containing info on the following buffer contents.



UniverseAssetFirstHeader_v2 :: struct #packed { // 8 byte structure
	tag 				: u32, // universe tag value.
	name_str_num_bytes 	: u32, // length of universe name string in bytes.
}

UniverseAssetSecondHeader_v2 :: struct #packed { // 56 byte structure
	active_camera_entity : i64, // index into constant entity buffers, or -1 if not set.
	active_skybox_entity : i64, // index into constant entity buffers, or -1 if not set.
	num_entities 		 : u32, // technically not nessesary.
	_ : [8]u32, // reserved
}

// @NOTE: IMPORTANT; when adding new field append them to the end DONT REORDER - breaks reading sind type is stored as uint in the files!
UniAssetBufferType :: enum u32 {
	UniverseSettings = 0,

	// it is required that each of the entitiy buffers has the same number of array elements.
	EntityInfos, 			// array of 'EntityInfoPacked' structures
	EntityTransforms,		// array of 'Transform' structures
	EntityComponentIndexes, // array of 'CompIndexes' structures
	EntityNames, 			// array of entity name strings, each string has a 4 bytes u32 in front indicating the byte size of the following string.

	CameraCompData, 	// array of 'CameraCompData' structures
	LightCompData, 		// array of 'SkyboxCompData' structures
	SkyboxCompData, 	// array of 'LightAsset' structures
	MeshrenCompData, 	// array of 'MeshRendererCompData' structures
	DrawablesArray, 	// array of 'DrawableAsset' structures
	ColliderCompData,   // array of 'ColliderCompData' structures

}

UniAssetBufferInfo :: struct #packed { // 12 bytes structure.
	type : UniAssetBufferType,
	numbr : u32, // number of entries/components/strings in the following buffer.
	bytes : u32, // byte size of following buffer contents.
}

free_universe_asset :: proc(uni : ^UniverseAsset){
	if uni == nil {
		return;
	}

	if len(uni.name) > 0{
		delete_string(uni.name);
	}

	if uni.entity_names != nil {
		// @Note: we dont free individuals strings as we expect them to be allocated in an arena or scratch buffer.
		delete_slice(uni.entity_names);
	}

	if uni.entity_infos != nil {
		delete_slice(uni.entity_infos);
	}

	if uni.entity_trans != nil {
		delete_slice(uni.entity_trans);
	}

	if uni.entity_comp_indexes != nil {
		delete_slice(uni.entity_comp_indexes);
	}

	if uni.camera_comp_data != nil {
		delete_slice(uni.camera_comp_data);
	}

	if uni.skybox_comp_data != nil {
		delete_slice(uni.skybox_comp_data);
	}

	if uni.light_comp_data != nil {
		delete_slice(uni.light_comp_data);
	}

	if uni.collider_comp_data != nil {
		delete_slice(uni.collider_comp_data);
	}

	if uni.meshren_comp_data != nil {
		delete_slice(uni.meshren_comp_data);
	}

	if uni.drawable_assets_array != nil {
		delete_slice(uni.drawable_assets_array);
	}

	free(uni);
}


asset_universe_read_from_path :: proc(filepath : string) -> (universe_asset : ^UniverseAsset, ok : bool) {

	file, open_err := os.open(filepath);
	if open_err != os.ERROR_NONE {
		return;
	}
	defer os.close(file);

	b_reader := reader.create_file_reader(file);
	return asset_universe_read(&b_reader);
}

asset_universe_read_from_memory :: proc(data : []byte) -> (universe_asset : ^UniverseAsset, ok : bool) {
	b_reader := reader.create_memory_reader(data);
	return asset_universe_read(&b_reader);
}

@(private="file")
asset_universe_read :: proc(b_reader : ^$T) -> (uni_asset : ^UniverseAsset, ok : bool) where T == reader.FileBinaryReader || T == reader.MemBinaryReader {
	
	common_hdr := reader.consume_copy_type(b_reader, IriAssetCommonHeader) or_return;

	if common_hdr.asset_type != AssetType.Universe {
		return nil, false;
	}

	switch common_hdr.asset_type_version {
		//case 1: return asset_universe_read_v1(b_reader, common_hdr);
		case 2: return asset_universe_read_v2(b_reader, common_hdr);
	}

	// invalid or depricated version
	return nil, false;
}


asset_universe_read_tag_and_name :: proc(b_reader : ^$T, allocator := context.allocator) -> (uni_tag : u32, uni_name : string, ok : bool) where T == reader.FileBinaryReader || T == reader.MemBinaryReader {
	
	reader.seek(b_reader, size_of(IriAssetCommonHeader));

	first_hdr : UniverseAssetFirstHeader_v2 = reader.consume_copy_type(b_reader, UniverseAssetFirstHeader_v2) or_return;

	// Read name string
	name : string;
	if first_hdr.name_str_num_bytes > 0 {
		name = reader.consume_make_string(b_reader, cast(int)first_hdr.name_str_num_bytes, allocator) or_return;
	} else {
		name = strings.clone("UnnamedUniverse", allocator);
	}

	return first_hdr.tag, name, true;
}

@(private="file")
asset_universe_read_v2 :: proc(b_reader : ^$T, common_hdr : IriAssetCommonHeader) -> (uni_asset : ^UniverseAsset, ok : bool) {

	uni_asset = new(UniverseAsset);

	defer if !ok {
		log.errorf("Failed to read universe asset")
		free_universe_asset(uni_asset);
		uni_asset = nil;
	
	}

	uni_asset.asset_uuid = common_hdr.asset_uuid;

	// first header 

	first_hdr : UniverseAssetFirstHeader_v2 = reader.consume_copy_type(b_reader, UniverseAssetFirstHeader_v2) or_return;
	uni_asset.tag = first_hdr.tag;

	// Read name string
	if first_hdr.name_str_num_bytes > 0 {
		uni_asset.name = reader.consume_make_string(b_reader, cast(int)first_hdr.name_str_num_bytes, context.allocator) or_return;
	} else {
		uni_asset.name = strings.clone("UnnamedUniverse", context.allocator);
	}

	uni_hdr : ^UniverseAssetSecondHeader_v2 = reader.consume_make_type(b_reader, UniverseAssetSecondHeader_v2, context.temp_allocator) or_return;
	{
		uni_asset.active_camera_entity = cast(int)uni_hdr.active_camera_entity;
		uni_asset.active_skybox_entity = cast(int)uni_hdr.active_skybox_entity;
		uni_asset.num_entities 	= uni_hdr.num_entities;
	}

	for reader.remaining_bytes(b_reader) > 0 {
		buf_info := reader.consume_copy_type(b_reader, UniAssetBufferInfo) or_return;
		
		if buf_info.bytes <= 0 || buf_info.numbr <= 0 {
			continue;
		}

		byte_size : int = cast(int)buf_info.bytes;
		numbr : int = cast(int)buf_info.numbr;

		switch buf_info.type {
			case .UniverseSettings:	reader.consume_mem_copy(b_reader, &uni_asset.settings, byte_size) or_return;
			case .EntityInfos: 		uni_asset.entity_infos = reader.consume_make_slice(b_reader, []EntityInfoPacked, numbr, context.allocator) or_return;
			case .EntityTransforms: uni_asset.entity_trans = reader.consume_make_slice(b_reader, []geo.Transform, numbr, context.allocator) or_return;
			case .EntityComponentIndexes: uni_asset.entity_comp_indexes = reader.consume_make_slice(b_reader, []CompIndexes, numbr, context.allocator) or_return;
			case .EntityNames: 	{
				num_ents : int = numbr;
				uni_asset.entity_names = make_slice([]string, num_ents, context.allocator);

				for i in 0..<num_ents {
					name_byte_size : u32 = reader.consume_copy_type(b_reader, u32) or_return;

					if name_byte_size > 0 {
						uni_asset.entity_names[i] = reader.consume_make_string(b_reader, cast(int)name_byte_size, context.temp_allocator) or_return;
					}
				}
			}
			case .CameraCompData:  uni_asset.camera_comp_data 		= reader.consume_make_slice(b_reader, []iricom.CameraCompData, numbr, context.allocator) or_return;
			case .LightCompData:   uni_asset.light_comp_data  		= reader.consume_make_slice(b_reader, []LightAsset           , numbr, context.allocator) or_return;
			case .SkyboxCompData:  uni_asset.skybox_comp_data 		= reader.consume_make_slice(b_reader, []iricom.SkyboxCompData, numbr, context.allocator) or_return;
			case .ColliderCompData: uni_asset.collider_comp_data 	= reader.consume_make_slice(b_reader, []ColliderCompData 	 , numbr, context.allocator) or_return;
			case .MeshrenCompData: uni_asset.meshren_comp_data 		= reader.consume_make_slice(b_reader, []MeshRendererCompData , numbr, context.allocator) or_return;
			case .DrawablesArray:  uni_asset.drawable_assets_array 	= reader.consume_make_slice(b_reader, []DrawableAsset        , numbr, context.allocator) or_return;
		}
	}

	num_ents : int = len(uni_asset.entity_infos);
	assert(num_ents == len(uni_asset.entity_trans));
	assert(num_ents == len(uni_asset.entity_names));
	assert(num_ents == len(uni_asset.entity_comp_indexes));

	return uni_asset, true;
}

asset_universe_write_to_file :: proc(filepath : string, uni_asset : ^UniverseAsset, write_flags : WriteFlags) -> (ok : bool) {

	log_errors : bool = .LogErrors in write_flags;

	if uni_asset == nil {
		return false;
	}
	
	assert(uni_asset.asset_uuid != AssetUUID_INVALID)

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

	// Cleanup 
	defer os.close(file);
	defer if !ok {
		// if something goes wrong during writing the file, we will atempt to delete the file imidiatly.
		try_delete_file(filepath, log_errors);		
	}

	// Common Header
	{
		hdr : IriAssetCommonHeader = create_common_header(AssetType.Universe, uni_asset.asset_uuid);
		written_bytes , write_err := os.write_ptr(file, &hdr, size_of(IriAssetCommonHeader));
		is_no_write_error(write_err, filepath, log_errors) or_return;
	}

	// First Asset Header 
	{
		first_hdr := UniverseAssetFirstHeader_v2{
			tag = uni_asset.tag,
			name_str_num_bytes = cast(u32)len(uni_asset.name),

		}

		written_bytes , write_err := os.write_ptr(file, &first_hdr, size_of(UniverseAssetFirstHeader_v2));
		is_no_write_error(write_err, filepath, log_errors) or_return;
	}

	// Name string directly after small header.
	if len(uni_asset.name) > 0 {
		written_bytes, write_err := os.write_string(file, uni_asset.name);
		is_no_write_error(write_err, filepath, log_errors) or_return;	
	}

	// Second Asset Header
	uni_hdr : UniverseAssetSecondHeader_v2;
	{
		uni_hdr.num_entities 		 = uni_asset.num_entities;
		uni_hdr.active_camera_entity = cast(i64)uni_asset.active_camera_entity;
		uni_hdr.active_skybox_entity = cast(i64)uni_asset.active_skybox_entity;

		written_bytes , write_err := os.write_ptr(file, &uni_hdr, size_of(UniverseAssetSecondHeader_v2));
		is_no_write_error(write_err, filepath, log_errors) or_return;
	}

	// Universe Settings
	{
		buf_info := UniAssetBufferInfo{
			type  = UniAssetBufferType.UniverseSettings,
			numbr = 1,
			bytes = cast(u32)size_of(uni_asset.settings),
		}
		buf_info_written_bytes , buf_info_write_err := os.write_ptr(file, &buf_info, size_of(buf_info));
		is_no_write_error(buf_info_write_err, filepath, log_errors) or_return;

		written_bytes , write_err := os.write_ptr(file, &uni_asset.settings, size_of(uni_asset.settings));
		is_no_write_error(write_err, filepath, log_errors) or_return;
	}

	num_ents : int = cast(int)uni_asset.num_entities;

	assert(num_ents == len(uni_asset.entity_infos))
	assert(num_ents == len(uni_asset.entity_trans))
	assert(num_ents == len(uni_asset.entity_names))
	assert(num_ents == len(uni_asset.entity_comp_indexes))

	// Packed infos
	{
		byte_size : int = num_ents * size_of(EntityInfoPacked);
		
		if byte_size > 0 {
			
			buf_info := UniAssetBufferInfo{
				type  = UniAssetBufferType.EntityInfos,
				numbr = cast(u32)num_ents,
				bytes = cast(u32)byte_size,
			}
			buf_info_written_bytes , buf_info_write_err := os.write_ptr(file, &buf_info, size_of(buf_info));
			is_no_write_error(buf_info_write_err, filepath, log_errors) or_return;

			written_bytes, write_err := os.write_ptr(file,&uni_asset.entity_infos[0], byte_size);
			is_no_write_error(write_err, filepath, log_errors) or_return;	
			assert(byte_size == written_bytes);
		}
	}

	// transforms
	{
		byte_size : int = num_ents * size_of(geo.Transform);
		
		if byte_size > 0 {
			
			buf_info := UniAssetBufferInfo{
				type  = UniAssetBufferType.EntityTransforms,
				numbr = cast(u32)num_ents,
				bytes = cast(u32)byte_size,
			}
			buf_info_written_bytes , buf_info_write_err := os.write_ptr(file, &buf_info, size_of(buf_info));
			is_no_write_error(buf_info_write_err, filepath, log_errors) or_return;

		
			written_bytes, write_err := os.write_ptr(file,&uni_asset.entity_trans[0], byte_size);
			is_no_write_error(write_err, filepath, log_errors) or_return;
			assert(byte_size == written_bytes);
		}
	}

	// Component  indexes
	{
		byte_size : int = num_ents * size_of(CompIndexes);
		
		if byte_size > 0 {
			
			buf_info := UniAssetBufferInfo{
				type  = UniAssetBufferType.EntityComponentIndexes,
				numbr = cast(u32)num_ents,
				bytes = cast(u32)byte_size,
			}
			buf_info_written_bytes , buf_info_write_err := os.write_ptr(file, &buf_info, size_of(buf_info));
			is_no_write_error(buf_info_write_err, filepath, log_errors) or_return;
		
			written_bytes, write_err := os.write_ptr(file, &uni_asset.entity_comp_indexes[0], byte_size);
			is_no_write_error(write_err, filepath, log_errors) or_return;
			assert(byte_size == written_bytes);
		}
	}

	// Entity Names 
	{
		// For each name string we write the byte size first and then the string after. even if string is empty we write 
		// a byte size of 0
		byte_size : int = 0;

		for i in 0..<num_ents {
			byte_size += size_of(u32);
			byte_size += len(uni_asset.entity_names[i]);
		}

		if byte_size > 0 {
			
			buf_info := UniAssetBufferInfo{
				type  = UniAssetBufferType.EntityNames,
				numbr = cast(u32)num_ents,
				bytes = cast(u32)byte_size,
			}
			buf_info_written_bytes , buf_info_write_err := os.write_ptr(file, &buf_info, size_of(buf_info));
			is_no_write_error(buf_info_write_err, filepath, log_errors) or_return;

			for i in 0..<num_ents {
				name_str := uni_asset.entity_names[i];
				name_len : u32 = cast(u32)len(name_str);

				len_written_bytes, len_write_err := os.write_ptr(file, &name_len, size_of(u32));
				is_no_write_error(len_write_err, filepath, log_errors) or_return;

				if name_len > 0 {
					str_written_bytes, str_write_err := os.write_string(file, name_str);
					is_no_write_error(str_write_err, filepath, log_errors) or_return;	
				}
			}
		}
	}


	// Component Data Camera
	{
		byte_size : int = len(uni_asset.camera_comp_data) * size_of(iricom.CameraCompData);
		
		if byte_size > 0 {

			buf_info := UniAssetBufferInfo{
				type  = UniAssetBufferType.CameraCompData,
				numbr = cast(u32)len(uni_asset.camera_comp_data),
				bytes = cast(u32)byte_size,
			}
			buf_info_written_bytes , buf_info_write_err := os.write_ptr(file, &buf_info, size_of(buf_info));
			is_no_write_error(buf_info_write_err, filepath, log_errors) or_return;

		
			written_bytes, write_err := os.write_ptr(file, &uni_asset.camera_comp_data[0], byte_size);
			is_no_write_error(write_err, filepath, log_errors) or_return;
			assert(byte_size == written_bytes);
		}
	}

	// Component Data Skybox
	{
		byte_size : int = len(uni_asset.skybox_comp_data) * size_of(iricom.SkyboxCompData);
		
		if byte_size > 0 {

			buf_info := UniAssetBufferInfo{
				type  = UniAssetBufferType.SkyboxCompData,
				numbr = cast(u32)len(uni_asset.skybox_comp_data),
				bytes = cast(u32)byte_size,
			}
			buf_info_written_bytes , buf_info_write_err := os.write_ptr(file, &buf_info, size_of(buf_info));
			is_no_write_error(buf_info_write_err, filepath, log_errors) or_return;

			written_bytes, write_err := os.write_ptr(file, &uni_asset.skybox_comp_data[0], byte_size);
			is_no_write_error(write_err, filepath, log_errors) or_return;
			assert(byte_size == written_bytes);
		}
	}

	// Component Data Lights
	{
		byte_size : int = len(uni_asset.light_comp_data) * size_of(LightAsset);
		
		if byte_size > 0 {

			buf_info := UniAssetBufferInfo{
				type  = UniAssetBufferType.LightCompData,
				numbr = cast(u32)len(uni_asset.light_comp_data),
				bytes = cast(u32)byte_size,
			}
			buf_info_written_bytes , buf_info_write_err := os.write_ptr(file, &buf_info, size_of(buf_info));
			is_no_write_error(buf_info_write_err, filepath, log_errors) or_return;

			written_bytes, write_err := os.write_ptr(file, &uni_asset.light_comp_data[0], byte_size);
			is_no_write_error(write_err, filepath, log_errors) or_return;
			assert(byte_size == written_bytes);
		}
	}

	// Component Data Colliders
	{
		byte_size : int = len(uni_asset.collider_comp_data) * size_of(ColliderCompData);
		
		if byte_size > 0 {

			buf_info := UniAssetBufferInfo{
				type  = UniAssetBufferType.ColliderCompData,
				numbr = cast(u32)len(uni_asset.collider_comp_data),
				bytes = cast(u32)byte_size,
			}
			buf_info_written_bytes , buf_info_write_err := os.write_ptr(file, &buf_info, size_of(buf_info));
			is_no_write_error(buf_info_write_err, filepath, log_errors) or_return;

			written_bytes, write_err := os.write_ptr(file, &uni_asset.collider_comp_data[0], byte_size);
			is_no_write_error(write_err, filepath, log_errors) or_return;
			assert(byte_size == written_bytes);
		}
	}


	// Component Data MeshRenderer
	{
		byte_size : int = len(uni_asset.meshren_comp_data) * size_of(MeshRendererCompData);
		
		if byte_size > 0 {

			buf_info := UniAssetBufferInfo{
				type  = UniAssetBufferType.MeshrenCompData,
				numbr = cast(u32)len(uni_asset.meshren_comp_data),
				bytes = cast(u32)byte_size,
			}
			buf_info_written_bytes , buf_info_write_err := os.write_ptr(file, &buf_info, size_of(buf_info));
			is_no_write_error(buf_info_write_err, filepath, log_errors) or_return;


			written_bytes, write_err := os.write_ptr(file, &uni_asset.meshren_comp_data[0], byte_size);
			is_no_write_error(write_err, filepath, log_errors) or_return;
			assert(byte_size == written_bytes);
		}
	}

	// Drawables array.
	{
		byte_size : int = len(uni_asset.drawable_assets_array) * size_of(DrawableAsset);
		
		if byte_size > 0 {

			buf_info := UniAssetBufferInfo{
				type  = UniAssetBufferType.DrawablesArray,
				numbr = cast(u32)len(uni_asset.drawable_assets_array),
				bytes = cast(u32)byte_size,
			}
			buf_info_written_bytes , buf_info_write_err := os.write_ptr(file, &buf_info, size_of(buf_info));
			is_no_write_error(buf_info_write_err, filepath, log_errors) or_return;

			written_bytes, write_err := os.write_ptr(file, &uni_asset.drawable_assets_array[0], byte_size);
			is_no_write_error(write_err, filepath, log_errors) or_return;
			assert(byte_size == written_bytes);
		}
	}

	return true;
}