package iria

import "core:log"
import "core:os"

import "base:intrinsics"

import reader "binary_reader"
import iricom "../iricommon"

LIGHT_ASSET_CURRENT_VERSION : u32 : 1

LightAssetFlags :: distinct bit_set[LightAssetFlag; u8]
LightAssetFlag :: enum u8 {
	CastShadows = 0,
	DebugDrawFrustum, // Shadowmap frustums.
}

LightAsset :: struct {
	color 			: [3]f32,
	strength 		: f32,

	flags 			: LightAssetFlags,  // u8
	type 			: iricom.LightType, // u8

	// spot lights only
	spot_inner_cone_angle_radians : f32,
	spot_outer_cone_angle_radians : f32,

	// @Note: for point and spot lights, only shadomap_res_0 is considered
	// for directional lights, 0,1,2 correspond to the 3 cascades.
	shadowmap_res_0 : iricom.ShadowmapResolution,
	shadowmap_res_1 : iricom.ShadowmapResolution,
	shadowmap_res_2 : iricom.ShadowmapResolution,

	transform : iricom.Transform,
}

LightAssetHeader_v1 :: struct #packed {
	asset : LightAsset,
}

asset_light_read_from_path :: proc(filepath : string) -> (light_asset : LightAsset, ok : bool)  {
		
	file, open_err := os.open(filepath);
	if open_err != os.ERROR_NONE {
		return;
	}
	defer os.close(file);

	b_reader := reader.create_file_reader(file);
	return asset_light_read(&b_reader);
}

asset_light_read_from_memory :: proc(data : []byte) -> (light_asset : LightAsset, ok : bool) {
	b_reader := reader.create_memory_reader(data);
	return asset_light_read(&b_reader);
}

@(private="file")
asset_light_read :: proc(b_reader : ^$T) -> (light_asset : LightAsset, ok : bool) where T == reader.FileBinaryReader || T == reader.MemBinaryReader {

	common_hdr := reader.consume_copy_type(b_reader, IriAssetCommonHeader) or_return;

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
asset_light_read_v1 :: proc(b_reader : ^$T, common_hdr : IriAssetCommonHeader) -> (light_asset : LightAsset, ok : bool) where T == reader.FileBinaryReader || T == reader.MemBinaryReader {

	light_hdr := reader.consume_copy_type(b_reader, LightAssetHeader_v1) or_return;

	return light_hdr.asset, true,
}



asset_light_write_to_file :: proc(filepath : string, light_asset : ^LightAsset, asset_uuid : AssetUUID, write_flags : WriteFlags) -> (ok : bool){

	log_errors : bool = .LogErrors in write_flags;

	assert(light_asset != nil);
	assert(asset_uuid != AssetUUID_INVALID)

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

	defer {
		os.close(file);
		
		if !ok {
			try_delete_file(filepath, log_errors);
		}
	}

	// Common Header
	{
		hdr : IriAssetCommonHeader = create_common_header(AssetType.Light, asset_uuid);

		written_bytes , write_err := os.write_ptr(file, &hdr, size_of(IriAssetCommonHeader));
		is_no_write_error(write_err, filepath, log_errors) or_return;
	}
	
	// Light Header
	light_hdr : LightAssetHeader_v1;	
	{

		light_hdr.asset = light_asset^;

		written_bytes , write_err := os.write_ptr(file, &light_hdr, size_of(LightAssetHeader_v1));
		is_no_write_error(write_err, filepath, log_errors) or_return;
	}

	
	return true;
}