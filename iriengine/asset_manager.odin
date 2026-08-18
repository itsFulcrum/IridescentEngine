package iri

import "core:log"
import "base:runtime"
import "core:mem"
import "core:os"
import "core:strings"
import "core:encoding/uuid"

import iria "iriasset"
import reader "odinary:readbinary"

AssetID 		:: iria.AssetID
AssetID_NONE 	:: iria.AssetID_NONE

AssetType 		:: iria.AssetType
AssetTypeFlags 	:: iria.AssetTypeFlags
ASSET_TYPE_FLAGS_ALL :: iria.ASSET_TYPE_FLAGS_ALL


AssetEntry :: struct {
	path  : string, // path to asset file, relative to project folder
	alias : string,
	type : iria.AssetType,
}

AssetHandleModel :: struct {
	mesh_ids : []MeshID,
	material_asset_ids : []AssetID,
}

AssetHandleMaterial :: struct {
	mat_id   : MaterialID,
}

@(private="package")
AssetLoadHandleModel :: struct {
	runtime_handle : AssetHandleModel,
	ref_count : u32,
}

@(private="package")
AssetLoadHandleMaterial :: struct {
	runtime_handle : AssetHandleMaterial,
	ref_count : u32,
}

@(private="package")
AssetLoadHandleFontAtlas :: struct {
	runtime_handle : FontID,
	ref_count : u32,
}

AssetManager :: struct {

	// allocator exclusivly for allocating string paths
	path_arena : mem.Dynamic_Arena,
	path_allocator : runtime.Allocator,

	alias_arena : mem.Dynamic_Arena,
	alias_allocator : runtime.Allocator,


	asset_entries : map[AssetID]AssetEntry,
	asset_aliases : map[string]AssetID,

	model_handles    : map[AssetID]AssetLoadHandleModel,
	material_handles : map[AssetID]AssetLoadHandleMaterial,
	font_handles     : map[AssetID]AssetLoadHandleFontAtlas,
}

@(private="package")
asset_manager_init :: proc(asset_manager : ^AssetManager) {

	engine_assert(asset_manager != nil);

	{
		block_size := 4 * mem.Megabyte; 
		// Path Allocator
		mem.dynamic_arena_init(&asset_manager.path_arena, context.allocator, context.allocator, block_size ,mem.DYNAMIC_ARENA_OUT_OF_BAND_SIZE_DEFAULT, mem.DEFAULT_ALIGNMENT);
		asset_manager.path_allocator = mem.dynamic_arena_allocator(&asset_manager.path_arena);
		
		// String Allocator
		mem.dynamic_arena_init(&asset_manager.alias_arena, context.allocator, context.allocator, block_size ,mem.DYNAMIC_ARENA_OUT_OF_BAND_SIZE_DEFAULT, mem.DEFAULT_ALIGNMENT);
		asset_manager.alias_allocator = mem.dynamic_arena_allocator(&asset_manager.alias_arena);
	}

	asset_manager.asset_entries = make_map(map[AssetID]AssetEntry, context.allocator);
}

@(private="package")
asset_manager_deinit :: proc(asset_manager :  ^AssetManager) {

	engine_assert(asset_manager != nil);

	delete_map(asset_manager.asset_entries);
	delete_map(asset_manager.asset_aliases);

	delete_map(asset_manager.model_handles);
	delete_map(asset_manager.material_handles);
	delete_map(asset_manager.font_handles);

	free_all(asset_manager.path_allocator);
	mem.dynamic_arena_destroy(&asset_manager.path_arena);
	free_all(asset_manager.alias_allocator);
	mem.dynamic_arena_destroy(&asset_manager.alias_arena);
}

// Used by the editor to display asset entries.
asset_manager_get_entries_map_read_only :: proc() -> ^map[iria.AssetID]AssetEntry {
	return &engine.asset_manager.asset_entries;
}

// Rescan all assets in the project folder.
asset_manager_rescan_entire_project :: proc() {
	IRI_PROFILE_PROCEDURE()

	engine_assert(engine != nil);

	asset_manager := engine.asset_manager;

	engine_assert(asset_manager != nil);
	engine_assert(len(engine.project_content_path) > 0);

	
	free_all(asset_manager.path_allocator);
	free_all(asset_manager.alias_allocator);
	clear(&asset_manager.asset_entries);

	asset_manager_scan_project_directory_recursiv(asset_manager, get_project_path());
}

// @Note expects directory_path to be an absolute path to a sub directory of the project.
@(private="package")
asset_manager_scan_project_directory_recursiv :: proc(asset_manager :  ^AssetManager, directory_path : string){

	IRI_PROFILE_PROCEDURE()


	if !os.is_directory(directory_path) {
		return;
	}

	dir_f, open_err := os.open(directory_path);
	if open_err != os.ERROR_NONE {
		log.warnf("Failed to open directory for scanning contents: path: {}, error code {}", directory_path, open_err);
		return;
	}

	defer os.close(dir_f);

	dir_iterator := os.read_directory_iterator_create(dir_f);
	defer os.read_directory_iterator_destroy(&dir_iterator);


	for info in os.read_directory_iterator(&dir_iterator) {

		if path, error := os.read_directory_iterator_error(&dir_iterator); error != os.ERROR_NONE {
			log.warnf("Failed to read file/directory {}, error: {}", path, error);
			continue;
		}

		if info.type == os.File_Type.Directory{

			asset_manager_scan_project_directory_recursiv(asset_manager, info.fullpath);

		} else if info.type == os.File_Type.Regular {

			asset_manager_register_asset_file_by_path(asset_manager, info.fullpath) or_continue;
		}
	}
}

// Recursivly walk all files in a directory and unregister all asset files.
@(private="package")
asset_manager_unscan_project_directory_recursiv :: proc(asset_manager :  ^AssetManager, directory_path : string){

	if !os.is_directory(directory_path) {
		return;
	}

	dir_f, open_err := os.open(directory_path);
	if open_err != os.ERROR_NONE {
		log.warnf("Failed to open directory for scanning contents: path: {}, error code {}", directory_path, open_err);
		return;
	}
	defer os.close(dir_f);


	dir_iterator := os.read_directory_iterator_create(dir_f);
	defer os.read_directory_iterator_destroy(&dir_iterator);


	for info in os.read_directory_iterator(&dir_iterator) {

		if path, error := os.read_directory_iterator_error(&dir_iterator); error != os.ERROR_NONE {
			log.warnf("Failed to read file/directory {}, error: {}", path, error);
			continue;
		}

		if info.type == os.File_Type.Directory{

			asset_manager_unscan_project_directory_recursiv(asset_manager, info.fullpath);
		} else if info.type == os.File_Type.Regular {
			
			asset_id, _ := iria.read_asset_header_info_from_path(info.fullpath, expected_asset_type = .None, log_errors = false) or_continue;
			asset_manager_unregister_asset(asset_manager, asset_id);
		}
	}
}

// @Note: this procedure will overwrite entries if an asset id is encountered again.
// asset id should be unique and if it occures twice than the file is a dublicate file.
// we could choose to not register the second occurence of a id but it doens't solve the problem that we dont
// know how to differantiate them anyway. It is more usefull if we have the ability to overwrite asset id entries
// for example if we move files from one folder to another we need to update the filepaths
// and thats easier if we just rescan the parent directorie if we dont want to perform a full rescan of the entire project.
@(private="package")
asset_manager_register_asset_file_by_path :: proc(asset_manager :  ^AssetManager, full_file_path : string) -> (is_registered : bool) {

	IRI_PROFILE_PROCEDURE()

	iria.has_valid_extention(full_file_path) or_return;
	
	// anything outside project path we will not register.
	// also this proc returns us a cleaned absolute path!
	abs_path := project_contains_path(full_file_path) or_return;

	
	// @Note expects proj_path to be an absolute and normalized path (clean_path() was called on it)
	proj_path := get_project_path();

	rel_path , rel_path_err := os.get_relative_path(proj_path, abs_path, context.temp_allocator);
	if rel_path_err != os.ERROR_NONE {
		return false;
	}
	
	file , open_err := os.open(abs_path);
	if open_err != os.ERROR_NONE {
		return;
	}

	b_reader := reader.create_file_reader(file);
	defer os.close(b_reader.file);

	hdr : iria.AssetFileCommonHeader = reader.consume_copy_type(&b_reader, iria.AssetFileCommonHeader) or_return;
	iria.is_valid_header(&hdr) or_return;

	asset_alias : iria.AssetAlias = reader.consume_copy_type(&b_reader, iria.AssetAlias) or_return;
	alias_str, has_alias := iria.string_clone_from_asset_alias(&asset_alias, asset_manager.alias_allocator);

	asset_id 	:= hdr.asset_id;
	asset_type 	:= hdr.asset_type;

	// @Note, we are intentionally overwriting entries if they already exist.
	// see comment above this procedure!

	new_entry := AssetEntry {
		path  = strings.clone(rel_path, asset_manager.path_allocator),
		alias = has_alias ? alias_str : "",
		type  = asset_type,
	}


	asset_manager.asset_entries[asset_id] = new_entry;

	if has_alias {

		if _, alias_exists_already := asset_manager.asset_aliases[alias_str]; alias_exists_already {
			log.warnf("AssetManager: An Asset file of type {} has the same alias as another. Aliases will be overwritten with new asset file - alias: {} - Path: ", asset_type, alias_str, rel_path);
		}
		asset_manager.asset_aliases[alias_str] = asset_id;
	}

	return true;
}


@(private="package")
asset_manager_unregister_asset :: proc(asset_manager :  ^AssetManager, asset_id : AssetID) {
	
	if entry , exists := asset_manager.asset_entries[asset_id]; exists {

 		if len(entry.alias) > 0 {
 			delete_key(&asset_manager.asset_aliases, entry.alias);
 		}

		delete_key(&asset_manager.asset_entries, asset_id);
	}

	// Search. we could maybe also load the file and try read the alias from it but meh.
	// for key, value_asset_id in asset_manager.asset_aliases {
		
	// 	if value_asset_id == asset_id {
	// 		delete_key(&asset_manager.asset_aliases, key);
	// 		break;
	// 	} 
	// }
}

@(private="package")
asset_manager_asset_exists :: proc(asset_manager :  ^AssetManager, asset_id : AssetID) -> bool {
	return asset_id in asset_manager.asset_entries;
}

// Read Only!
asset_manager_get_entry :: proc(asset_manager :  ^AssetManager, asset_id : iria.AssetID) -> (entry : AssetEntry, exists : bool) {
	return asset_manager.asset_entries[asset_id];
}

// Get the absolute filepath to a registered asset.
@(private="package")
asset_manager_get_absolute_filepath :: proc (asset_manager :  ^AssetManager, asset_id : iria.AssetID, expected_type : iria.AssetType = .None, allocator := context.temp_allocator) -> (path : string, entry_exists : bool){
	
	entry , exists := asset_manager.asset_entries[asset_id];
	if !exists {
		return;
	}

	if expected_type != .None  && entry.type != expected_type {
		return;	
	}

	joind , alloc_err := os.join_path({get_project_path(),entry.path}, context.temp_allocator)
	
	cleaned, alloc_err1 := os.clean_path(joind, allocator);

	return cleaned, true;
}


// TODO: replace this with something like - does_asset_exist_at_path

// Checks the filepath to see if there is an asset file, if yes and the type matches the expected type we 
// return the asset id stored in that file because we likely want to overwrite it with a new version of the asset.
// if the path does not exist yet we generate a new id.
// full_store_filepath must be a full absolute filepath to an .iria asset file.
// If this procedure returns false we should not continue writing any files to this path because something probably went wrong.
@(private="package")
asset_manager_get_or_generate_asset_id :: proc(full_store_filepath : string, expected_asset_type : iria.AssetType, log_errors : bool) -> (asset_id : AssetID, ok : bool) {

	if os.exists(full_store_filepath) {

		_asset_id, _ := iria.read_asset_header_info_from_path(full_store_filepath, expected_asset_type, log_errors) or_return;

		// More validation ??
		// existing_entry, entry_exists := asset_manager_get_entry(asset_manager,asset_id);
		// engine_assert(entry_exists);
		// engine_assert(existing_entry.type == asset_type);

		return _asset_id, true;
	}

	return iria.generate_new_asset_id(), true;
}


@(private="package")
asset_manager_set_asset_alias :: proc(asset_manager : ^AssetManager, asset_id : iria.AssetID, alias : string) {

	if entry, exists := asset_manager.asset_entries[asset_id]; exists {
		
		// Crude way to truncate the string to fit 127 characters.
		alias_128 , _ := iria.string_to_asset_alias(alias);
		alias_trunc_str, str_has_data := iria.string_clone_from_asset_alias(&alias_128, context.temp_allocator);

 		alias_clone := str_has_data ? strings.clone(alias_trunc_str, asset_manager.alias_allocator) : ""
	
		// Delete old alias.
 		if len(entry.alias) > 0 {
 			delete_key(&asset_manager.asset_aliases, entry.alias);
 		}
		
		// write new alias if its not 0.
		if str_has_data {
			asset_manager.asset_aliases[alias_clone] = asset_id;
		}

 		// Update entry
 		entry.alias = alias_clone;
		asset_manager.asset_entries[asset_id] = entry; 

		abs_path, abs_path_ok := asset_manager_get_absolute_filepath(asset_manager, asset_id)
		if abs_path_ok {
			write_ok := iria.write_asset_alias_to_asset_file(abs_path, alias_128 ,log_errors = true)
			if !write_ok {
				log.errorf("AssetManager: Failed to write asset alias to path: {}", abs_path)
			}
		}
	}
}

// Get the asset id from a unique alias associated with this file. Optionally provide the expected file type to make this procedure fail if alias exists but the asset file type does not match.
@(private="package")
asset_manager_get_asset_id_from_alias :: proc(asset_manager : ^AssetManager, asset_alias : string, expected_type : iria.AssetType = iria.AssetType.None) -> (asset_id : AssetID, exists : bool) {

	id, alias_exists := asset_manager.asset_aliases[asset_alias]

	if !alias_exists {
		return AssetID_NONE, false;
	}

	if expected_type != iria.AssetType.None {

		entry, entry_exists := asset_manager.asset_entries[id];

		engine_assert(entry_exists); // Its registered with the aliases. Fix elsewhere if this fails.

		if entry.type != expected_type {
			return AssetID_NONE, false;
		}
	}

	return id, true;
}

// Get the asset id from a path relative to the project folder. Returns false if path is not a valid asset file.
@(private="package")
asset_manager_get_asset_id_from_path :: proc(asset_manager : ^AssetManager, rel_asset_path : string) -> (asset_id : AssetID, exists : bool){

	abs_path := project_get_absolute_path(rel_asset_path, context.temp_allocator) or_return;

	project_contains_path(abs_path) or_return;

	_asset_id, _ := iria.read_asset_header_info_from_path(abs_path) or_return;

	if !asset_manager_asset_exists(asset_manager, _asset_id){
		return AssetID_NONE, false
	}

	return _asset_id, true;
}
