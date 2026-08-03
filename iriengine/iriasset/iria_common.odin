package iria

import "core:log"
import "core:os"
import "core:strings"
import "core:mem"
import "core:encoding/uuid"
import reader "odinary:readbinary"


MAGIC :: [4]byte{'I','R','I','A'}
FILE_EXTENTION 		: string : ".iria"
FILE_EXTENTION_NAME : string :  "iria"

AssetID 		:: uuid.Identifier
AssetID_NONE 	:: AssetID{}

ASSET_TYPE_FLAGS_ALL :: AssetTypeFlags{.Material, .Universe, .Light, .Model} 
AssetTypeFlags :: distinct bit_set[AssetType]
AssetType :: enum u32 {
// @NOTE!!! Do not reorder or remove from the middle.
	None 		= 0,
	_Unused_1	= 1,
	Material 	= 2,
	Universe 	= 3,
	Light 		= 4,
	_Unused_2	= 5,
	Model	    = 6,
}

AssetWriteFlags :: distinct bit_set[AssetWriteFlag]
AssetWriteFlag :: enum {
	LogErrors = 0,
	OverwriteExisting
}

// Every Asset File has this Common Header Frist
AssetFileCommonHeader :: struct #packed { // 32 bytes
	magic 				: [4]byte,		//  4 bytes, magic
	asset_type 			: AssetType,	//  4 bytes, asset type enum u32
	asset_type_version	: u32,			//  4 bytes, version of the asset type
	_ 					: [4]byte,		//  4 bytes, reserved
	asset_id 			: AssetID,		// 16 bytes, UUID
}

// A string with a constant buffer and maximum size of 31 bytes.
AssetFileString32 :: struct #packed {
	bytes : [31]u8,
	len   : u8, 
}

// A string with a constant buffer and maximum size of 63 bytes.
AssetFileString64 :: struct #packed {
	bytes : [63]u8,
	len   : u8, 
}

// A string with a constant buffer and maximum size of 127 bytes.
AssetFileString128 :: struct #packed {
	bytes : [127]u8,
	len   : u8, 
}

// Every Asset File stores an alias (string) of 128 bytes after the Common Header.
AssetAlias :: AssetFileString128


generate_new_asset_id :: proc () -> AssetID {
	return uuid.generate_v7_basic();
}

asset_id_from_uuid_string :: proc(uuid_string : string) -> (asset_id : AssetID, ok : bool){
	id , read_err := uuid.read(uuid_string);
	if read_err != nil {
		return AssetID_NONE, false;	
	}

	return id, true;
}

asset_id_to_string :: proc(asset_id : AssetID, allocator := context.temp_allocator) -> string {
	str, _ := uuid.to_string_allocated(asset_id, allocator);
	return str;
}

get_current_version_for_type :: proc(asset_type : AssetType) -> u32 {
	
	switch asset_type {
		case .None: 	 return 0;
		case ._Unused_1: return 0;
		case .Material:	 return ASSET_MATERIAL_FILE_CURRENT_VERSION;
		case .Universe:	 return ASSET_UNIVERSE_FILE_CURRENT_VERSION;
		case .Light:	 return ASSET_LIGHT_FILE_CURRENT_VERSION;
		case ._Unused_2: return 0;
		case .Model:	 return ASSET_MODEL_FILE_CURRENT_VERSION;
	}

	return 0;
}

// Optionally specify custom version otherwise use most current for type.
create_common_header :: proc(type : AssetType, asset_id : AssetID, asset_version : u32 = 0) -> AssetFileCommonHeader {
	
	assert(type != .None);
	assert(type != ._Unused_1);
	assert(type != ._Unused_2);

	return AssetFileCommonHeader {
		magic = MAGIC,
		asset_type = type,
		asset_type_version = asset_version > 0 ? asset_version : get_current_version_for_type(type),
		asset_id = asset_id,
	}
}

has_valid_extention :: proc(filepath : string) -> bool {
	return os.ext(filepath) == FILE_EXTENTION;
}

is_valid_header :: proc(hdr : ^AssetFileCommonHeader, expected_asset_type : AssetType = AssetType.None) -> bool {
	if hdr == nil {
		return false;
	}

	if expected_asset_type != .None && hdr.asset_type != expected_asset_type {
		return false;
	}

	return hdr.magic == MAGIC && hdr.asset_type != .None && hdr.asset_id != AssetID_NONE;
}

// Validate that we can write to this filepath. returns false when file exists but 'can_overwrite_existing' is set to false
// Also returns wheather a file already exists at that location.
@(require_results)
is_valid_write_filepath :: proc(filepath : string, can_overwrite_existing : bool, log_errors : bool = true) -> (file_exists : bool, ok : bool) {
	
	// file_ext : string = os.ext(filepath);

	if !has_valid_extention(filepath) {
		if log_errors do log.errorf("IriAsset: Write validation Failed - Filepath does not have the correct file extention '{}' path: {}", FILE_EXTENTION, filepath);
		return false, false;
	}

	
	path_dir, path_filename := os.split_path(filepath);

	if !os.is_directory(path_dir) {
		return false, false;
	}

	file_exists = os.exists(filepath);

	if file_exists && !can_overwrite_existing {
		if log_errors do log.warnf("IriAsset: Write validation Failed - A File already exists at {}", filepath);
		return file_exists, false;
	}


	return file_exists, true;
}

@(require_results)
is_valid_read_filepath :: proc(filepath : string, log_errors : bool = true) -> (file_exists : bool) {
	
	if !has_valid_extention(filepath) {
		if log_errors do log.errorf("IriAsset: Filepath does not have the correct file extention '{}' path: {}", FILE_EXTENTION, filepath);
		return false;
	}

	return os.exists(filepath);
}

read_asset_header_info_from_path :: proc(filepath : string, expected_asset_type : AssetType = .None, log_errors : bool = true) -> (asset_id : AssetID, type : AssetType, is_valid_asset_file : bool) {
	
	is_valid_read_filepath(filepath, log_errors = true) or_return;
	
	file , open_err := os.open(filepath);
	if open_err != nil {
		if log_errors do log.errorf("IriAsset: Failed to Open File. Error: {} - Path: {}", open_err, filepath);
		return;
	}
	defer os.close(file);

	file_size, size_err := os.file_size(file);
	if size_err != nil{
		if log_errors do log.errorf("IriAsset: Failed to read file size, Corrupted file ? - Path: {}", filepath);
		return;
	}

	if file_size < cast(i64)size_of(AssetFileCommonHeader) {
		if log_errors do log.errorf("IriAsset: File size is {} bytes which is smaller than the Header, Corrupted file ? - Path: {}", file_size, filepath);
		return;
	}

	hdr : AssetFileCommonHeader;
	read_bytes , read_err := os.read_ptr(file, &hdr, size_of(AssetFileCommonHeader));
	if read_err != nil {
		if log_errors do log.errorf("IriAsset: Reading Header Failed: Error: {} - Path: {}", read_err, filepath)
		return;
	}
	
	ok := is_valid_header(&hdr, expected_asset_type);
	if !ok {
		return AssetID_NONE, .None, false;
	}

	return  hdr.asset_id, hdr.asset_type, ok;
}


// This is used during writing procedures to check all the os errors and log it.
// it is useful since we will want to do this so often and we can use or_return after it.
@(private="package")
check_write_error :: proc(err : os.Error, filepath : string, log_errors : bool) -> (ok : bool) {
	
	if err != os.ERROR_NONE {
		if log_errors do log.errorf("IriAsset: Failed to write into file: Error Code: {}, filepath: {}", err, filepath);
		return false;
	}

	return true;
}


@(require_results)
@(private="package")
write_common_header_and_alias_to_file :: proc(file : ^os.File, filepath : string, asset_type : AssetType, asset_id : AssetID, asset_alias_string : string, log_errors : bool) -> (ok : bool) {

	if file == nil {
		return false;
	}

	{
		hdr : AssetFileCommonHeader = create_common_header(asset_type, asset_id);
		written_bytes , write_err := os.write_ptr(file, &hdr, size_of(AssetFileCommonHeader));
		check_write_error(write_err, filepath, log_errors) or_return;	
	}
	// Alias String
	{
		alias_str128, has_alias := string_to_asset_string128(asset_alias_string); 

		alias_written_bytes, alias_write_err := os.write_ptr(file, &alias_str128, size_of(AssetFileString128));
		check_write_error(alias_write_err, filepath, log_errors) or_return;
	}

	return true;
}

write_asset_alias_to_asset_file :: proc(filepath : string, asset_alias : AssetAlias, log_errors : bool = true) -> (ok : bool){

	file_exists := is_valid_write_filepath(filepath, true, log_errors) or_return;

	if !file_exists {
		if log_errors do log.errorf("IriAsset: Cannot write alias to non existing file. Path: {}", filepath);
		return false;
	}


	file , open_err := os.open(filepath, os.File_Flags{.Write});
	if open_err != nil {
		if log_errors do log.errorf("IriAsset: Failed to Open File. Error: {} - Path: {}", open_err, filepath);
		return false;
	}
	defer os.close(file);

	offset : int = size_of(AssetFileCommonHeader);
	os.seek(file, cast(i64)offset, .Start);

	copy := asset_alias;
	size := size_of(AssetAlias);

	written_bytes, write_err := os.write_ptr(file, &copy, size);
	check_write_error(write_err, filepath, log_errors) or_return;

	return true;
}


// We may want to delete a file if something failed during writing so we dont end up with a corrupted file.
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


string_to_asset_alias 		  :: string_to_asset_string128
string_clone_from_asset_alias :: string_clone_from_asset_string128

string_to_asset_string32 :: proc(str : string) -> (asset_string : AssetFileString32, has_data : bool) {

	if len(str) <= 0{
		return;
	}

	length : int = min(len(str), 63); // we need 1 extra byte to store len
	asset_string.len = cast(u8)length;

	for i in 0..<length{
		asset_string.bytes[i] = str[i];
	}

	return asset_string, true;
}

string_to_asset_string64 :: proc(str : string) -> (asset_string : AssetFileString64, has_data : bool) {

	if len(str) <= 0{
		return;
	}

	length : int = min(len(str), 63); // we need 1 extra byte to store len
	asset_string.len = cast(u8)length;

	for i in 0..<length{
		asset_string.bytes[i] = str[i];
	}

	return asset_string, true;
}

string_to_asset_string128 :: proc(str : string) -> (asset_string : AssetFileString128, has_data : bool) {

	if len(str) <= 0{
		return;
	}

	length : int = min(len(str), 127); // we need 1 extra byte to store len
	asset_string.len = cast(u8)length;

	for i in 0..<length{
		asset_string.bytes[i] = str[i];
	}

	return asset_string, true;
}

string_clone_from_asset_string32 :: proc(asset_string : ^AssetFileString32, allocator := context.allocator) -> (str : string, has_data : bool){

	if asset_string.len == 0 {
		return;
	}

	as_str : string = transmute(string)asset_string.bytes[0:asset_string.len];
	out_str, alloc_err := strings.clone(as_str, allocator)

	if alloc_err != nil {
		return;
	}

	return out_str, true;
}

string_clone_from_asset_string64 :: proc(asset_string : ^AssetFileString64, allocator := context.allocator) -> (str : string, has_data : bool){

	if asset_string.len == 0 {
		return;
	}

	as_str : string = transmute(string)asset_string.bytes[0:asset_string.len];
	out_str, alloc_err := strings.clone(as_str, allocator)

	if alloc_err != nil {
		return;
	}

	return out_str, true;
}

string_clone_from_asset_string128 :: proc(asset_string : ^AssetFileString128, allocator := context.allocator) -> (str : string, has_data : bool){

	if asset_string.len == 0 {
		return;
	}

	as_str : string = transmute(string)asset_string.bytes[0:asset_string.len];
	out_str, alloc_err := strings.clone(as_str, allocator)

	if alloc_err != nil {
		return;
	}

	return out_str, true;
}

