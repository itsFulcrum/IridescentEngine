package iria

import "core:log"
import "core:os"

import geo "odinary:geometry"
import reader "odinary:readbinary"
import iricom "../iricommon"

ASSET_LIGHT_FILE_CURRENT_VERSION : u32 : 1

AssetLight :: struct {

	asset_alias : string,
	comp_data : AssetLightComponentData,
	transform : geo.Transform,
}

AssetLightHeader_v1 :: struct #packed {
	
	comp_data : AssetLightComponentData,
	transform : geo.Transform,
}

asset_light_read_from_path :: proc(filepath : string) -> (light_asset : AssetLight, ok : bool)  {
		
	file, open_err := os.open(filepath);
	if open_err != os.ERROR_NONE {
		return;
	}
	defer os.close(file);

	b_reader := reader.create_file_reader(file);
	return asset_light_read(&b_reader);
}

asset_light_read_from_memory :: proc(data : []byte) -> (light_asset : AssetLight, ok : bool) {
	b_reader := reader.create_memory_reader(data);
	return asset_light_read(&b_reader);
}

@(private="file")
asset_light_read :: proc(b_reader : ^$T) -> (light_asset : AssetLight, ok : bool) where T == reader.FileBinaryReader || T == reader.MemBinaryReader {

	common_hdr := reader.consume_copy_type(b_reader, AssetFileCommonHeader) or_return;

	if common_hdr.asset_type != AssetType.Light {
		return light_asset, false;
	}

	switch common_hdr.asset_type_version {
		case 1: return asset_light_read_v1(b_reader, common_hdr);
	}

	// invalid or depricated version
	return light_asset, false;
}


@(private="file")
asset_light_read_v1 :: proc(b_reader : ^$T, common_hdr : AssetFileCommonHeader) -> (light_asset : AssetLight, ok : bool) where T == reader.FileBinaryReader || T == reader.MemBinaryReader {


	alias_str_128 := reader.consume_copy_type(b_reader, AssetFileString128) or_return;

	alias_str, has_alias := string_clone_from_asset_string128(&alias_str_128,context.allocator);
	
	if has_alias {
		light_asset.asset_alias = alias_str;
	}

	light_hdr := reader.consume_copy_type(b_reader, AssetLightHeader_v1) or_return;

	light_asset.comp_data = light_hdr.comp_data;
	light_asset.transform = light_hdr.transform;

	return light_asset, true,
}



asset_light_write_to_file :: proc(filepath : string, light_asset : ^AssetLight, asset_id : AssetID, write_flags : AssetWriteFlags) -> (ok : bool){

	log_errors : bool = .LogErrors in write_flags;
	can_overwrite_existing: bool = .OverwriteExisting in write_flags;

	assert(light_asset != nil);
	assert(asset_id != AssetID_NONE)

	file_exists_already := is_valid_write_filepath(filepath,can_overwrite_existing, log_errors) or_return;

	file, open_err := os.open(filepath, flags = os.File_Flags{.Write, .Create, .Trunc});

	if open_err != os.ERROR_NONE {
		if log_errors do log.errorf("IriAsset: Failed to open file for writing with error code: {}, path: {}", filepath);
		return false;
	}

	defer if !ok {
		try_delete_file(filepath, log_errors);
	}
	defer os.close(file);


	write_common_header_and_alias_to_file(file, filepath, AssetType.Light, asset_id, light_asset.asset_alias, log_errors) or_return;

	// Light Header
	light_hdr : AssetLightHeader_v1; 
	{

		light_hdr.transform = light_asset.transform;
		light_hdr.comp_data = light_asset.comp_data;

		written_bytes , write_err := os.write_ptr(file, &light_hdr, size_of(AssetLightHeader_v1));
		check_write_error(write_err, filepath, log_errors) or_return;
	}
	
	return true;
}