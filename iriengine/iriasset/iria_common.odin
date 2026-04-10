package iria

import "core:log"
import "core:os"
import "core:strings"
import "core:mem"
import "core:encoding/uuid"
import reader "binary_reader"

MAGIC :: [4]byte{'I','R','I','A'}
FILE_EXTENTION 		: string : ".iria"
FILE_EXTENTION_NAME : string : "iria"

AssetUUID :: uuid.Identifier
AssetUUID_INVALID :: AssetUUID{}

ASSET_TYPE_FLAGS_ALL :: AssetTypeFlags{.None, .Mesh, .Material, .Universe, .Light, .SceneCollection} 
AssetTypeFlags :: distinct bit_set[AssetType]
AssetType :: enum u32 {
	None 		= 0,
	Mesh 		= 1,
	Material 	= 2,
	Universe 	= 3,
	Light 		= 4,
	SceneCollection	= 5,
}

IriAssetCommonHeader :: struct #packed {
	// 32 bytes total
	magic : [4]byte,			//  4 bytes, magic
	asset_type : AssetType, 	//  4 bytes, asset type enum u32
	asset_type_version : u32,	//  4 bytes, version of the asset type
	_ : [4]byte, 				//  4 bytes, reserved
	asset_uuid : AssetUUID, 	// 16 bytes, UUID
}

WriteFlags :: distinct bit_set[WriteFlag]
WriteFlag :: enum {
	LogErrors = 0,
	OverwriteExisting
}

get_most_current_version_for_type :: proc(asset_type : AssetType) -> u32 {
	
	switch asset_type {
		case .None: 	return 0;
		case .Mesh: 	return MESH_ASSET_CURRENT_VERSION;
		case .Material:	return MATERIAL_ASSET_CURRENT_VERSION;
		case .Universe:	return UNIVERSE_ASSET_CURRENT_VERSION;
		case .Light:	return LIGHT_ASSET_CURRENT_VERSION;
		case .SceneCollection:	return SCENE_COLLECTION_ASSET_CURRENT_VERSION;
	}

	return 0;
}

// can specify custom version otherwise use most current for type.
create_common_header :: proc(type : AssetType, id : AssetUUID, asset_version : u32 = 0) -> IriAssetCommonHeader {
	
	assert(type != .None);

	return IriAssetCommonHeader{
		magic = MAGIC,
		asset_type = type,
		asset_type_version = asset_version > 0 ? asset_version : get_most_current_version_for_type(type),
		asset_uuid = id,
	}
}


// Validate that we can write to this filepath.
validate_write_filepath :: proc(filepath : string, log_errors : bool = true) -> (file_exists : bool, ok : bool) {
	
	file_ext : string = os.ext(filepath);

	if file_ext != FILE_EXTENTION {
		if log_errors do log.errorf("IriAsset: Filepath does not have the correct file extention '{}' path: {}", FILE_EXTENTION, filepath);
		return false, false;
	}

	path_dir, path_filename := os.split_path(filepath);

	if !os.is_directory(path_dir) {
		return false, false;
	}

	return os.exists(filepath), true;
}

// if 'expected_asset_type' is not set to 'None' procedure will return false (!ok) if expected type does not match actual asset type
get_asset_info_from_path :: proc(filepath : string, expected_asset_type : AssetType = .None) -> (type : AssetType, asset_uuid : AssetUUID, ok : bool) {

	file , open_err := os.open(filepath);
	if open_err != os.ERROR_NONE {
		return;
	}
	defer os.close(file);

	file_size, err := os.file_size(file);
	if err != os.ERROR_NONE{
		return;
	}

	if file_size < cast(i64)size_of(IriAssetCommonHeader) {
		return;
	}

	hdr : IriAssetCommonHeader;
	read_bytes , read_err := os.read_ptr(file, &hdr, size_of(IriAssetCommonHeader));
	if read_err != os.ERROR_NONE {
		return;
	}
	
	if expected_asset_type != .None && hdr.asset_type != expected_asset_type {
		return;
	}

	ok = hdr.magic == MAGIC && hdr.asset_type != .None && hdr.asset_uuid != AssetUUID{};

	return hdr.asset_type, hdr.asset_uuid, ok;
}

is_valid_extention :: proc(filepath : string) -> bool {
	return os.ext(filepath) == FILE_EXTENTION;
}

is_valid_header :: proc(hdr : ^IriAssetCommonHeader) -> bool {
	if hdr == nil {
		return false;
	}

	return hdr.magic == MAGIC && hdr.asset_type != .None && hdr.asset_uuid != AssetUUID{};
}

is_valid_asset_file :: proc(filepath : string) -> (asset_uuid : AssetUUID, asset_type : AssetType, is_asset_file : bool){

	is_valid_extention(filepath) or_return;

	file , open_err := os.open(filepath);
	if open_err != os.ERROR_NONE {
		return;
	}

	defer os.close(file);

	file_size, err := os.file_size(file);
	if err != os.ERROR_NONE{
		return;
	}

	if file_size < cast(i64)size_of(IriAssetCommonHeader) {
		return;
	}

	hdr : IriAssetCommonHeader;
	read_bytes , read_err := os.read_ptr(file, &hdr, size_of(IriAssetCommonHeader));
	if read_err != os.ERROR_NONE {
		return;
	}
	
	is_asset_file = is_valid_header(&hdr);

	return hdr.asset_uuid, hdr.asset_type, is_asset_file;
}


get_asset_type_and_version :: proc(data : []byte) -> (type : AssetType, version : u32) {

	if len(data) < size_of(IriAssetCommonHeader) {
		return AssetType.None, 0;
	}

	hdr : ^IriAssetCommonHeader = cast(^IriAssetCommonHeader)&data[0];

	return hdr.asset_type, hdr.asset_type_version; 
}




// This is used during writing procedures to check all the os errors and log it.
// it is useful since we will want to do this so often and we can use or_return after it.
@(private="package")
is_no_write_error :: proc(err : os.Error, filepath : string, log_errors : bool) -> (ok : bool) {
	
	if err != os.ERROR_NONE {
		if log_errors do log.errorf("IriAsset: Failed to write into file: Error Code: {}, filepath: {}", err, filepath);
		return false;
	}

	return true;
}

// We want to delete a file if something failed during writing so we dont end up with a corrupted file.
@(private="package")
try_delete_file :: proc(filepath : string, log_errors : bool) -> (ok : bool) {

	if os.exists(filepath) {
		remove_err := os.remove(filepath);
		if remove_err != os.ERROR_NONE {
			// not sure what to do now except log the error.
			// if removing also faild we cant do much more ig.
			if log_errors do log.errorf("IriAsset: Failed to remove file after aborted and incomplete file writing. {}, error code: {}", filepath, remove_err);
			return false;
		}
	}

	return true;
}
