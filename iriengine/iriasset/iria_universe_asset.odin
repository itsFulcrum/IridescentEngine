package iria

import "core:log"
import "core:os"
import "core:mem"
import "core:strings"

import geo "odinary:geometry"
import reader "odinary:readbinary"
import iricom "../iricommon"


// Version 3 universe file
/*
	Common Header - AssetFileCommonHeader, 32 bytes
	Asset Alias   - AssetFileString128, 128 bytes

	AssetUniverseHeader_v3
	Universe Name - AssetFileString64, 64 bytes.

	@Variaous Buffers
	Always starts with a BufferInfo (AssetUniverseBufferInfo_v3)
	followed by the buffer itself.
	based on 'AssetUniverseBufferInfo_v3.type' the buffer contents should be read differently.

	Special Cases for buffer types: 
	
		BufferType - EntityNames
		Each entity name first stores a u32 indicating the number of bytes of the string name (can be utf8).
		followed by this many number of bytes that make up the string.
		Number of total strings is equal to number of entities.

		BufferType - DrawableGroup
		Each Drawable Group first stores a small Header structure (AssetDrawGroup) which contains the AssetID of the Model asset
		Number of primitives to indicate how many sub meshes a model has.
		then following this Header there come 3 arrays all with num_primitives elements.
		flags   	   : []iricom.DrawInstanceFlags, // flags per primitve.
		transforms     : []geo.Transform, // transform overwrites per primitve
		material_asset : []AssetID, // Material asset overwrites per primitve

		BufferType - EndOfFile
		After this there is no more data in the file..
*/

AssetDrawGroupHeader :: struct #packed {
	asset_id : AssetID, // Mesh or Model asset.
	asset_drawable_type : iricom.DrawGroupAssetType,
	num_primitives : u32, // For Mesh Assets this is just always 1.
	_ : u32,
	_ : u32,
} 

AssetDrawGroup :: struct {
	asset_id 			: AssetID, // Mesh or Model asset.
	asset_drawable_type : iricom.DrawGroupAssetType,
	num_primitives 		: u32, // For Mesh Assets this is just always 1.
	flags   	   		: []iricom.DrawInstanceFlags,
	transforms     		: []geo.Transform,
	material_asset_ids 	: []AssetID,
}

AssetUniverseSettings :: struct #packed {	
	shadow_cascade_near_far_scale 	: f32,
	shadow_cascade_side_scale 		: f32,
	shadow_cascade_split_1 			: f32,
	shadow_cascade_split_2 			: f32,
	shadow_cascade_split_3 			: f32,


	cull_shadow_draws 			: b8,
    do_frustum_culling 			: b8,
    _ : b8,
    _ : b8,
    _ : [16]u32, // reserved.
}


AssetUniverse :: struct {
	asset_id : AssetID,
	name       : string,
	tag 	   : u32,
	asset_alias : string, // Version 3..

	settings : AssetUniverseSettings,

	active_camera_entity : int, // index into entity slices below, or -1 if not set.
	active_skybox_entity : int, // index into entity slices below, or -1 if not set.

	
	num_entities : u32,
	// These MUST all have length of num_entities!
	entity_names : []string, 			// @Note: individual strings are not freed by 'free_universe_asset()', expected to be allocated with arena or manually freed by caller.
	entity_infos : []AssetEntityInfo,
	entity_trans : []geo.Transform,
	entity_comp_indexes : []AssetComponentIndexes,


	camera_comp_data   : []AssetCameraComponentData,
	skybox_comp_data   : []AssetSkyboxComponentData,
	light_comp_data    : []AssetLightComponentData,
	meshren_comp_data  : []AssetMeshRendererComponentData,
	collider_comp_data : []AssetColliderComponentData,

	// This array is ORDERED by mesh renderer component. 
	// such that MeshRendererCompData gives an offset where to start reading Draw Groups form
	// this array, and a number of how many Draw Groups to read consecutavly.

	drawable_groups : []AssetDrawGroup,
}



ASSET_UNIVERSE_FILE_CURRENT_VERSION : u32 : 3


AssetUniverseHeader_v3 :: struct #packed {
	active_camera_entity : i64, // index into constant entity buffers, or -1 if not set.
	active_skybox_entity : i64, // index into constant entity buffers, or -1 if not set.
	num_entities 		 : u32, // technically not nessesary.
	tag : u32, // Universe Tag value. // can maybe depricate ??
	_ : [8]u32, // reserved
}

AssetUniverseBufferType_v3 :: enum u32 {
	EndOfFile 	         = 0,

	UniverseSettings 	 = 1,
	_Reserved_1 		 = 2,
	_Reserved_2 		 = 3,
	_Reserved_3 		 = 4,
	_Reserved_4 		 = 5,
	
	DrawableGroup 		 = 6, 	// array of 'DrawableAsset' structures

	// it is required that each of the entitiy buffers has the same number of array elements.
	EntityInfos 		   = 7, 			// array of 'EntityInfoPacked' structures
	EntityTransforms 	   = 8,		// array of 'Transform' structures
	EntityComponentIndexes = 9, // array of 'CompIndexes' structures
	EntityNames 		   = 10, 			// array of entity name strings, each string has a 4 bytes u32 in front indicating the byte size of the following string.

	_Entity_Reserved_1 = 11,
	_Entity_Reserved_2 = 12,
	_Entity_Reserved_3 = 13,
	_Entity_Reserved_4 = 14,
	
	CameraCompData, 	// array of 'CameraCompData' structures
	LightCompData, 		// array of 'SkyboxCompData' structures
	SkyboxCompData, 	// array of 'LightAsset' structures
	MeshrenCompData, 	// array of 'MeshRendererCompData' structures
	ColliderCompData,   // array of 'ColliderCompData' structures
	_CompReserved_1,
	_CompReserved_2,
	_CompReserved_3,
	_CompReserved_4,
	_CompReserved_5,
	_CompReserved_6,
	_CompReserved_7,
	_CompReserved_8,
	_CompReserved_9,
	_CompReserved_10,
	_CompReserved_11,
	_CompReserved_12,
	_CompReserved_13,
	_CompReserved_14,
	_CompReserved_15,
	_CompReserved_16,

}

AssetUniverseBufferInfo_v3 :: struct #packed { // 12 bytes structure.
	type : AssetUniverseBufferType_v3,
	numbr : u32, // number of entries/components/strings in the following buffer.
	bytes : u32, // byte size of following buffer contents.
}


asset_universe_free :: proc(uni : ^AssetUniverse){
	if uni == nil {
		return;
	}

	if len(uni.name) > 0{
		delete_string(uni.name);
	}

	if len(uni.asset_alias) > 0 {
		delete_string(uni.asset_alias);
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

	if uni.drawable_groups != nil {

		for &group in uni.drawable_groups {

			if group.flags != nil {
				delete_slice(group.flags);
			}

			if group.transforms != nil {
				delete_slice(group.transforms);
			}

			if group.material_asset_ids != nil {
				delete_slice(group.material_asset_ids);
			}
		}



		delete_slice(uni.drawable_groups);
	}

	free(uni);
}


asset_universe_read_from_path :: proc(filepath : string) -> (universe_asset : ^AssetUniverse, ok : bool) {

	file, open_err := os.open(filepath);
	if open_err != os.ERROR_NONE {
		return;
	}
	defer os.close(file);

	b_reader := reader.create_file_reader(file);
	return asset_universe_read(&b_reader);
}

asset_universe_read_from_memory :: proc(data : []byte) -> (universe_asset : ^AssetUniverse, ok : bool) {
	b_reader := reader.create_memory_reader(data);
	return asset_universe_read(&b_reader);
}

@(private="file")
asset_universe_read :: proc(b_reader : ^$T) -> (uni_asset : ^AssetUniverse, ok : bool) where T == reader.FileBinaryReader || T == reader.MemBinaryReader {
	
	common_hdr := reader.consume_copy_type(b_reader, AssetFileCommonHeader) or_return;

	if common_hdr.asset_type != AssetType.Universe {
		return nil, false;
	}

	switch common_hdr.asset_type_version {
		case 3: return asset_universe_read_v3(b_reader, common_hdr);
	}

	// invalid or depricated version
	return nil, false;
}

asset_universe_write_to_file :: proc(filepath : string, uni_asset : ^AssetUniverse, write_flags : AssetWriteFlags) -> (ok : bool){
	return asset_universe_write_v3_to_file(filepath, uni_asset, write_flags);
}

@(private="file")
asset_universe_read_v3 :: proc(b_reader : ^$T, common_hdr : AssetFileCommonHeader) -> (uni_asset : ^AssetUniverse, ok : bool) {

	uni_asset = new(AssetUniverse);

	defer if !ok {
		log.errorf("Failed to read universe asset")
		asset_universe_free(uni_asset);
		uni_asset = nil;	
	}

	uni_asset.asset_id = common_hdr.asset_id;


	// Read Alias string
	uni_alias128 : AssetFileString128 = reader.consume_copy_type(b_reader, AssetFileString128) or_return;
	uni_alias_str, uni_has_alias := string_clone_from_asset_string128(&uni_alias128, context.allocator);
	if uni_has_alias {
		uni_asset.asset_alias = uni_alias_str;
	}



	// Universe Header
	uni_hdr : AssetUniverseHeader_v3 = reader.consume_copy_type(b_reader, AssetUniverseHeader_v3) or_return;
	{

		uni_asset.active_camera_entity = cast(int)uni_hdr.active_camera_entity;
		uni_asset.active_skybox_entity = cast(int)uni_hdr.active_skybox_entity;
		uni_asset.num_entities 	= uni_hdr.num_entities;

		uni_asset.tag = uni_hdr.tag;
	}

	// Universe Name string
	{
		uni_name_string64 : AssetFileString64 = reader.consume_copy_type(b_reader, AssetFileString64) or_return;

		uni_name_str, uni_has_name := string_clone_from_asset_string64(&uni_name_string64, context.allocator);
		if uni_has_name {
			uni_asset.name = uni_name_str;
		} else {
			uni_asset.name = strings.clone("UnnamedUniverse", context.allocator);
		}

	}

	buffer_loop: for reader.remaining_bytes(b_reader) > 0 {
		buf_info := reader.consume_copy_type(b_reader, AssetUniverseBufferInfo_v3) or_return;
		
		if buf_info.bytes <= 0 || buf_info.numbr <= 0 {
			continue;
		}

		byte_size : int = cast(int)buf_info.bytes;
		numbr : int = cast(int)buf_info.numbr;

		#partial switch buf_info.type {
			case .EndOfFile: break buffer_loop;

			case .UniverseSettings:	reader.consume_mem_copy(b_reader, &uni_asset.settings, byte_size) or_return;
		
			case .EntityInfos: 		uni_asset.entity_infos = reader.consume_make_slice(b_reader, []AssetEntityInfo, numbr, context.allocator) or_return;
			case .EntityTransforms: uni_asset.entity_trans = reader.consume_make_slice(b_reader, []geo.Transform, numbr, context.allocator) or_return;
			case .EntityComponentIndexes: uni_asset.entity_comp_indexes = reader.consume_make_slice(b_reader, []AssetComponentIndexes, numbr, context.allocator) or_return;
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
			case .CameraCompData:  uni_asset.camera_comp_data 		= reader.consume_make_slice(b_reader, []AssetCameraComponentData       , numbr, context.allocator) or_return;
			case .LightCompData:   uni_asset.light_comp_data  		= reader.consume_make_slice(b_reader, []AssetLightComponentData        , numbr, context.allocator) or_return;
			case .SkyboxCompData:  uni_asset.skybox_comp_data 		= reader.consume_make_slice(b_reader, []AssetSkyboxComponentData       , numbr, context.allocator) or_return;
			case .ColliderCompData: uni_asset.collider_comp_data 	= reader.consume_make_slice(b_reader, []AssetColliderComponentData 	   , numbr, context.allocator) or_return;
			case .MeshrenCompData: uni_asset.meshren_comp_data 		= reader.consume_make_slice(b_reader, []AssetMeshRendererComponentData , numbr, context.allocator) or_return;
			case .DrawableGroup: {

				uni_asset.drawable_groups = make_slice([]AssetDrawGroup, numbr, context.allocator);

				for g in 0..<numbr {
					group_hdr : AssetDrawGroupHeader = reader.consume_copy_type(b_reader, AssetDrawGroupHeader) or_return;

					group := &uni_asset.drawable_groups[g];

					group.asset_id = group_hdr.asset_id;
					group.asset_drawable_type = group_hdr.asset_drawable_type;
					group.num_primitives = group_hdr.num_primitives;

					num_primitives : int = cast(int)group_hdr.num_primitives;

					group.flags 		 = reader.consume_make_slice(b_reader, []iricom.DrawInstanceFlags , num_primitives, context.allocator) or_return;
					group.transforms 	 = reader.consume_make_slice(b_reader, []geo.Transform , num_primitives, context.allocator) or_return;
					group.material_asset_ids = reader.consume_make_slice(b_reader, []AssetID , num_primitives, context.allocator) or_return;
				}				
			}
		} 
	}

	num_ents : int = len(uni_asset.entity_infos);
	assert(num_ents == len(uni_asset.entity_trans));
	assert(num_ents == len(uni_asset.entity_names));
	assert(num_ents == len(uni_asset.entity_comp_indexes));

	return uni_asset, true;
}

@(private="file")
asset_universe_write_v3_to_file :: proc(filepath : string, uni_asset : ^AssetUniverse, write_flags : AssetWriteFlags) -> (ok : bool) {

	log_errors : bool = .LogErrors in write_flags;
	can_overwrite_existing : bool = .OverwriteExisting in write_flags;

	if uni_asset == nil {
		return false;
	}
	
	assert(uni_asset.asset_id != AssetID_NONE)


	file_exists_already := is_valid_write_filepath(filepath, can_overwrite_existing, log_errors) or_return;


	file, open_err := os.open(filepath, flags = os.File_Flags{.Write, .Create, .Trunc});

	if open_err != os.ERROR_NONE {
		if log_errors do log.errorf("IriAsset: Failed to open file for writing with error code: {}, path: {}", filepath);
		return false;
	}

	// Cleanup 
	defer if !ok {
		// if something goes wrong during writing the file, we will atempt to delete the file imidiatly.
		try_delete_file(filepath, log_errors);		
	}
	defer os.close(file);


	write_common_header_and_alias_to_file(file, filepath, AssetType.Universe, uni_asset.asset_id, uni_asset.asset_alias, log_errors) or_return;


	// Header v3
	{
		uni_hdr : AssetUniverseHeader_v3;

		uni_hdr.num_entities 		 = uni_asset.num_entities;
		uni_hdr.active_camera_entity = cast(i64)uni_asset.active_camera_entity;
		uni_hdr.active_skybox_entity = cast(i64)uni_asset.active_skybox_entity;

		uni_hdr.tag = uni_asset.tag;


		written_bytes, write_err := os.write_ptr(file, &uni_hdr, size_of(AssetUniverseHeader_v3));
		check_write_error(write_err, filepath, log_errors) or_return;
	}

	// Universe String Name 
	{
		uni_name_64, has_name := string_to_asset_string64(uni_asset.name); 
		written_bytes, write_err := os.write_ptr(file, &uni_name_64, size_of(AssetFileString64));
		check_write_error(write_err, filepath, log_errors) or_return;
	}


	// Start Writing Buffers


	// Universe Settings
	{
		buf_info := AssetUniverseBufferInfo_v3{
			type  = AssetUniverseBufferType_v3.UniverseSettings,
			numbr = 1,
			bytes = cast(u32)size_of(uni_asset.settings),
		}
		buf_info_written_bytes, buf_info_write_err := os.write_ptr(file, &buf_info, size_of(buf_info));
		check_write_error(buf_info_write_err, filepath, log_errors) or_return;

		written_bytes, write_err := os.write_ptr(file, &uni_asset.settings, size_of(uni_asset.settings));
		check_write_error(write_err, filepath, log_errors) or_return;
	}

	num_ents : int = cast(int)uni_asset.num_entities;

	assert(num_ents == len(uni_asset.entity_infos))
	assert(num_ents == len(uni_asset.entity_trans))
	assert(num_ents == len(uni_asset.entity_names))
	assert(num_ents == len(uni_asset.entity_comp_indexes))

	// Asset Entity Info
	{
		byte_size : int = num_ents * size_of(AssetEntityInfo);
		
		if byte_size > 0 {
			
			buf_info := AssetUniverseBufferInfo_v3 {
				type  = AssetUniverseBufferType_v3.EntityInfos,
				numbr = cast(u32)num_ents,
				bytes = cast(u32)byte_size,
			}
			buf_info_written_bytes , buf_info_write_err := os.write_ptr(file, &buf_info, size_of(buf_info));
			check_write_error(buf_info_write_err, filepath, log_errors) or_return;

			written_bytes, write_err := os.write_ptr(file,&uni_asset.entity_infos[0], byte_size);
			check_write_error(write_err, filepath, log_errors) or_return;	
			assert(byte_size == written_bytes);
		}
	}

	// transforms
	{
		byte_size : int = num_ents * size_of(geo.Transform);
		
		if byte_size > 0 {
			
			buf_info := AssetUniverseBufferInfo_v3{
				type  = .EntityTransforms,
				numbr = cast(u32)num_ents,
				bytes = cast(u32)byte_size,
			}
			buf_info_written_bytes , buf_info_write_err := os.write_ptr(file, &buf_info, size_of(buf_info));
			check_write_error(buf_info_write_err, filepath, log_errors) or_return;

		
			written_bytes, write_err := os.write_ptr(file,&uni_asset.entity_trans[0], byte_size);
			check_write_error(write_err, filepath, log_errors) or_return;
			assert(byte_size == written_bytes);
		}
	}

	// Component  indexes
	{
		byte_size : int = num_ents * size_of(AssetComponentIndexes);
		
		if byte_size > 0 {
			
			buf_info := AssetUniverseBufferInfo_v3{
				type  = .EntityComponentIndexes,
				numbr = cast(u32)num_ents,
				bytes = cast(u32)byte_size,
			}
			buf_info_written_bytes , buf_info_write_err := os.write_ptr(file, &buf_info, size_of(buf_info));
			check_write_error(buf_info_write_err, filepath, log_errors) or_return;
		
			written_bytes, write_err := os.write_ptr(file, &uni_asset.entity_comp_indexes[0], byte_size);
			check_write_error(write_err, filepath, log_errors) or_return;
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
			
			buf_info := AssetUniverseBufferInfo_v3{
				type  = .EntityNames,
				numbr = cast(u32)num_ents,
				bytes = cast(u32)byte_size,
			}
			buf_info_written_bytes , buf_info_write_err := os.write_ptr(file, &buf_info, size_of(buf_info));
			check_write_error(buf_info_write_err, filepath, log_errors) or_return;

			for i in 0..<num_ents {
				name_str := uni_asset.entity_names[i];
				name_len : u32 = cast(u32)len(name_str);

				len_written_bytes, len_write_err := os.write_ptr(file, &name_len, size_of(u32));
				check_write_error(len_write_err, filepath, log_errors) or_return;

				if name_len > 0 {
					str_written_bytes, str_write_err := os.write_string(file, name_str);
					check_write_error(str_write_err, filepath, log_errors) or_return;	
				}
			}
		}
	}


	// Component Data Camera
	{
		byte_size : int = len(uni_asset.camera_comp_data) * size_of(AssetCameraComponentData);
		
		if byte_size > 0 {

			buf_info := AssetUniverseBufferInfo_v3{
				type  = .CameraCompData,
				numbr = cast(u32)len(uni_asset.camera_comp_data),
				bytes = cast(u32)byte_size,
			}
			buf_info_written_bytes , buf_info_write_err := os.write_ptr(file, &buf_info, size_of(buf_info));
			check_write_error(buf_info_write_err, filepath, log_errors) or_return;

		
			written_bytes, write_err := os.write_ptr(file, &uni_asset.camera_comp_data[0], byte_size);
			check_write_error(write_err, filepath, log_errors) or_return;
			assert(byte_size == written_bytes);
		}
	}

	// Component Data Skybox
	{
		byte_size : int = len(uni_asset.skybox_comp_data) * size_of(AssetSkyboxComponentData);
		
		if byte_size > 0 {

			buf_info := AssetUniverseBufferInfo_v3{
				type  = .SkyboxCompData,
				numbr = cast(u32)len(uni_asset.skybox_comp_data),
				bytes = cast(u32)byte_size,
			}
			buf_info_written_bytes , buf_info_write_err := os.write_ptr(file, &buf_info, size_of(buf_info));
			check_write_error(buf_info_write_err, filepath, log_errors) or_return;

			written_bytes, write_err := os.write_ptr(file, &uni_asset.skybox_comp_data[0], byte_size);
			check_write_error(write_err, filepath, log_errors) or_return;
			assert(byte_size == written_bytes);
		}
	}

	// Component Data Lights
	{
		byte_size : int = len(uni_asset.light_comp_data) * size_of(AssetLightComponentData);
		
		if byte_size > 0 {

			buf_info := AssetUniverseBufferInfo_v3{
				type  = .LightCompData,
				numbr = cast(u32)len(uni_asset.light_comp_data),
				bytes = cast(u32)byte_size,
			}
			buf_info_written_bytes , buf_info_write_err := os.write_ptr(file, &buf_info, size_of(buf_info));
			check_write_error(buf_info_write_err, filepath, log_errors) or_return;

			written_bytes, write_err := os.write_ptr(file, &uni_asset.light_comp_data[0], byte_size);
			check_write_error(write_err, filepath, log_errors) or_return;
			assert(byte_size == written_bytes);
		}
	}

	// Component Data Colliders
	{
		byte_size : int = len(uni_asset.collider_comp_data) * size_of(AssetColliderComponentData);
		
		if byte_size > 0 {

			buf_info := AssetUniverseBufferInfo_v3{
				type  = .ColliderCompData,
				numbr = cast(u32)len(uni_asset.collider_comp_data),
				bytes = cast(u32)byte_size,
			}
			buf_info_written_bytes , buf_info_write_err := os.write_ptr(file, &buf_info, size_of(buf_info));
			check_write_error(buf_info_write_err, filepath, log_errors) or_return;

			written_bytes, write_err := os.write_ptr(file, &uni_asset.collider_comp_data[0], byte_size);
			check_write_error(write_err, filepath, log_errors) or_return;
			assert(byte_size == written_bytes);
		}
	}


	// Component Data MeshRenderer
	{
		byte_size : int = len(uni_asset.meshren_comp_data) * size_of(AssetMeshRendererComponentData);
		
		if byte_size > 0 {

			buf_info := AssetUniverseBufferInfo_v3{
				type  = .MeshrenCompData,
				numbr = cast(u32)len(uni_asset.meshren_comp_data),
				bytes = cast(u32)byte_size,
			}
			buf_info_written_bytes , buf_info_write_err := os.write_ptr(file, &buf_info, size_of(buf_info));
			check_write_error(buf_info_write_err, filepath, log_errors) or_return;


			written_bytes, write_err := os.write_ptr(file, &uni_asset.meshren_comp_data[0], byte_size);
			check_write_error(write_err, filepath, log_errors) or_return;
			assert(byte_size == written_bytes);
		}
	}


	// Drawable Group
	{
		byte_size : int = 0; // len(uni_asset.drawable_assets_array) * size_of(DrawableAsset);

		num_groups : int = len(uni_asset.drawable_groups);

		// Precompute byte size for this buffer.
		for &group in uni_asset.drawable_groups {
			
			num_primitives : int = cast(int)group.num_primitives;
			assert(num_primitives == len(group.flags));
			assert(num_primitives == len(group.transforms));
			assert(num_primitives == len(group.material_asset_ids));

			byte_size += size_of(AssetDrawGroupHeader);

			// flags array.
			byte_size += num_primitives * size_of(iricom.DrawInstanceFlags);
				
			// transforms array.
			byte_size += num_primitives * size_of(geo.Transform);
			
			// Material IDs array.
			byte_size += num_primitives * size_of(AssetID);

		}

		if byte_size > 0 {


			buf_info := AssetUniverseBufferInfo_v3{
				type  = AssetUniverseBufferType_v3.DrawableGroup,
				numbr = cast(u32)num_groups,
				bytes = cast(u32)byte_size,
			}


			buf_info_written_bytes , buf_info_write_err := os.write_ptr(file, &buf_info, size_of(buf_info));
			check_write_error(buf_info_write_err, filepath, log_errors) or_return;

			group_loop: for g in 0..<num_groups{
				group := &uni_asset.drawable_groups[g];

				num_primitives : int = cast(int)group.num_primitives;

				group_header := AssetDrawGroupHeader{
					asset_id = group.asset_id,
					asset_drawable_type = group.asset_drawable_type,
					num_primitives = group.num_primitives,
				}

				grp_hdr_written_bytes , grp_hdr_write_err := os.write_ptr(file, &group_header, size_of(group_header));
				check_write_error(grp_hdr_write_err, filepath, log_errors) or_return;

				if num_primitives <= 0 {
					continue group_loop;
				}
				
				// flags array.
				flags_array_size : int = num_primitives * size_of(iricom.DrawInstanceFlags);
				flags_written_bytes, flags_write_err := os.write_ptr(file, &group.flags[0], flags_array_size);
				check_write_error(flags_write_err, filepath, log_errors) or_return;
				
				// transforms array.
				trans_array_size : int = num_primitives * size_of(geo.Transform);
				trans_written_bytes, trans_write_err := os.write_ptr(file, &group.transforms[0], trans_array_size);
				check_write_error(trans_write_err, filepath, log_errors) or_return;


				// Material IDs array.
				mat_array_size : int = num_primitives * size_of(AssetID);
				mat_written_bytes, mat_write_err := os.write_ptr(file, &group.material_asset_ids[0], mat_array_size);
				check_write_error(mat_write_err, filepath, log_errors) or_return;
				
			}

		}
	}


	// End Of File
	{
		buf_info := AssetUniverseBufferInfo_v3 {
			type  = AssetUniverseBufferType_v3.EndOfFile,
		}

		buf_info_written_bytes , buf_info_write_err := os.write_ptr(file, &buf_info, size_of(buf_info));
		check_write_error(buf_info_write_err, filepath, log_errors) or_return;
	}

	return true;
}