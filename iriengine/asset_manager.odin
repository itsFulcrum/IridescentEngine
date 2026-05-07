package iri

import "core:log"
import "base:runtime"
import "core:mem"
import "core:os"
import "core:strings"
import "core:encoding/uuid"

import iria "iriasset"
import reader "odinary:readbinary"

AssetUUID 			:: iria.AssetUUID
AssetUUID_INVALID 	:: iria.AssetUUID_INVALID

AssetType 		:: iria.AssetType
AssetTypeFlags 	:: iria.AssetTypeFlags
ASSET_TYPE_FLAGS_ALL :: iria.ASSET_TYPE_FLAGS_ALL

MaterialAsset 	:: iria.MaterialAsset

UniverseAssetInfo :: struct {
	uni_tag  : u32,
	uni_name : string,
	asset_uuid : AssetUUID,
}

AssetEntry :: struct {
	path : string, // path to asset file, relative to content directory in project folder
	type : iria.AssetType,
}

AssetManager :: struct {

	// allocator exclusivly for allocating string paths so they are all close in memory
	path_arena : mem.Dynamic_Arena,
	path_allocator : runtime.Allocator,

	// Store paths to assets, path are relative to content directory in project folder
	entries : map[iria.AssetUUID]AssetEntry,

	universe_infos : [dynamic]UniverseAssetInfo,
}

@(private="package")
asset_manager_generate_asset_uuid :: proc () -> iria.AssetUUID {
	return uuid.generate_v7_basic();
}

@(private="package")
asset_manager_init :: proc(manager : ^AssetManager) {

	engine_assert(manager != nil);

	{
		block_size := 8 * mem.Megabyte; 
		mem.dynamic_arena_init(&manager.path_arena, context.allocator, context.allocator, block_size ,mem.DYNAMIC_ARENA_OUT_OF_BAND_SIZE_DEFAULT, mem.DEFAULT_ALIGNMENT);
		manager.path_allocator = mem.dynamic_arena_allocator(&manager.path_arena);
	}

	manager.entries = make_map(map[iria.AssetUUID]AssetEntry, context.allocator);
}

@(private="package")
asset_manager_deinit :: proc(manager :  ^AssetManager) {
	engine_assert(manager != nil);

	free_all(manager.path_allocator);
	mem.dynamic_arena_destroy(&manager.path_arena);

	delete_map(manager.entries);

	for &info in manager.universe_infos {
		delete(info.uni_name);
	}
	delete(manager.universe_infos);

}

// Used by the editor to display asset entries.
asset_manager_get_entries_map_read_only :: proc() -> ^map[iria.AssetUUID]AssetEntry {
	return &engine.asset_manager.entries;
}

asset_manager_rescan_entire_project :: proc() {
	
	engine_assert(engine != nil);
	engine_assert(engine.asset_manager != nil);
	engine_assert(len(engine.project_content_path) > 0);

	manager := engine.asset_manager;
	free_all(manager.path_allocator);
	clear(&manager.entries);

	asset_manager_scan_project_directory_recursiv(manager, get_project_path());
}

// @Note expects directory_path to be an absolute path to a sub directory of the project.
@(private="package")
asset_manager_scan_project_directory_recursiv :: proc(manager :  ^AssetManager, directory_path : string){

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

			asset_manager_scan_project_directory_recursiv(manager, info.fullpath);

		} else if info.type == os.File_Type.Regular {

			asset_manager_register_asset_file_by_path(manager, info.fullpath) or_continue;
		}
	}
}

// @Note: recursivly walk all files in a directory and remove all asset files form entires map.
@(private="package")
asset_manager_unscan_project_directory_recursiv :: proc(manager :  ^AssetManager, directory_path : string){

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

			asset_manager_unscan_project_directory_recursiv(manager, info.fullpath);
		} else if info.type == os.File_Type.Regular {
			
			asset_uuid, asset_type := iria.is_valid_asset_file(info.fullpath) or_continue;
			asset_manager_unregister_entry(manager, asset_uuid, asset_type);
		}
	}
}

// @Note: this procedure will overwrite entries if an asset uuid is encountered again.
// asset uuid should be unique and if it occures twice than the file is a dublicate file.
// we could choose to not register the second occurence of a uuid but it doens't solve the problem that we dont
// know how to differantiate them anyway. It is more usefull if we have the ability to overwrite asset uuid entries
// for example if we move files from one folder to another we need to update the filepaths
// and thats easier if we just rescan the parent directorie if we dont want to perform a full rescan of the entire project. 
@(private="package")
asset_manager_register_asset_file_by_path :: proc(manager :  ^AssetManager, full_file_path : string) -> (is_registered : bool) {

	iria.is_valid_extention(full_file_path) or_return;
	
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

	hdr : iria.IriAssetCommonHeader = reader.consume_copy_type(&b_reader, iria.IriAssetCommonHeader) or_return;
	
	iria.is_valid_header(&hdr) or_return;

	asset_uuid := hdr.asset_uuid;
	asset_type := hdr.asset_type; 

	// @Note, we are intentionally overwriting entries if they already exist.
	// see comment above this procedure!

	new_entry := AssetEntry {
		path = strings.clone(rel_path, manager.path_allocator),
		type = asset_type,
	}

	manager.entries[asset_uuid] = new_entry;

	if asset_type == .Universe {
		
		// if asset is of type universe, we gather extra information that we store seperatly

		uni_tag, uni_name, uni_read_ok := iria.asset_universe_read_tag_and_name(&b_reader, context.allocator);
		engine_assert(uni_read_ok); // we already validated this file above

		new_uni_info := UniverseAssetInfo{
			uni_name   = uni_name,
			uni_tag    = uni_tag,
			asset_uuid = asset_uuid,
		}

		already_registered_index : int = -1;
		for &uni_info, index in manager.universe_infos {

			if uni_info.asset_uuid == asset_uuid {
				already_registered_index = index;
				break;
			}
		}

		if already_registered_index == -1 {
			append(&manager.universe_infos, new_uni_info);
		} else {
			info := &manager.universe_infos[already_registered_index];
			delete(info.uni_name);
			manager.universe_infos[already_registered_index] = new_uni_info;
		}
	}

	return true;
}

@(private="package")
asset_manager_unregister_entry :: proc(manager :  ^AssetManager, asset_uuid : iria.AssetUUID, asset_type : AssetType) {
	
	entry, exists := manager.entries[asset_uuid];

	if exists {

		if entry.type == .Universe {
			for &uni_info, index in manager.universe_infos{
				if uni_info.asset_uuid == asset_uuid {
					delete(uni_info.uni_name)
					unordered_remove(&manager.universe_infos, index);
					break;
				}
			}
		}

		delete_key(&manager.entries, asset_uuid);
	}
}


@(private="package")
asset_manager_asset_exists :: proc(manager :  ^AssetManager, id : iria.AssetUUID) -> bool {
	return id in manager.entries;
}

@(private="package")
asset_manager_get_entry :: proc(manager :  ^AssetManager, asset_uuid : iria.AssetUUID) -> (entry : AssetEntry, exists : bool) {
	return manager.entries[asset_uuid]; // @Note this map odin syntax actually returns both entry and exists.
}

@(private="package")
asset_manager_get_absolute_filepath :: proc (manager :  ^AssetManager, asset_uuid : iria.AssetUUID, expected_type : iria.AssetType = .None, allocator := context.temp_allocator) -> (path : string, entry_exists : bool){
	
	entry , exists := manager.entries[asset_uuid];
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


@(private="package")
asset_manager_update_universe_name :: proc(manager :  ^AssetManager, asset_uuid : iria.AssetUUID, new_name : string){

	for &uni_info in manager.universe_infos {
		if uni_info.asset_uuid == asset_uuid {
			delete(uni_info.uni_name);
			uni_info.uni_name = strings.clone(new_name, context.allocator);
			break;
		}
	}
}

// @Note:
// Checks the filepath to see if there is an asset file, if yes and the type matches the expected type we 
// return the assed id stored in that file because we likely want to overwrite it with a new version of the asset.
// if the path does not exist yet we generate a new uuid.
// full_store_filepath must be a full absolute filepath to an .iria asset file.
// If this procedure returns false we should not continue writing any files to this path because something probably went wrong.
@(private="package")
asset_manager_get_or_generate_asset_uuid :: proc(full_store_filepath : string, expected_asset_type : iria.AssetType, log_errors : bool) -> (id : iria.AssetUUID, ok : bool) {

	if os.exists(full_store_filepath) {

		asset_type, asset_uuid, asset_file_ok := iria.get_asset_info_from_path(full_store_filepath, expected_asset_type);

		if !asset_file_ok {
			if log_errors do log.warnf("Faild to export asset file to {}. Overwriting existing asset files that are invalid or of different asset type is not allowed. existing file asset type: {}, expected asset type {}", full_store_filepath, asset_type, expected_asset_type);
			return id, false;
		}

		// More validation ??
		// existing_entry, entry_exists := asset_manager_get_entry(asset_manager,asset_uuid);
		// engine_assert(entry_exists);
		// engine_assert(existing_entry.type == asset_type);

		return asset_uuid, true;
	}

	return asset_manager_generate_asset_uuid(), true;
}


asset_manager_get_asset_uuid_from_path :: proc(rel_asset_path : string) -> (asset_uuid : AssetUUID, exists : bool){
	manager := engine.asset_manager;
	
	abs_path := project_get_absolute_path(rel_asset_path, context.temp_allocator) or_return;

	project_contains_path(abs_path) or_return;

	uuid , type := iria.is_valid_asset_file(abs_path) or_return;

	if !asset_manager_asset_exists(manager, uuid){
		return AssetUUID_INVALID, false
	}

	return uuid, true;
}

// TODO: this should not live here.
// make a path absolute and run clean on it.
clean_path_absolute :: proc(path : string) -> (clean_path : string, ok : bool) {
	
	clean_path = path;

	if !os.is_absolute_path(path) {
		osErr : os.Error;
		clean_path, osErr = os.get_absolute_path(path, context.temp_allocator);
		if osErr != os.ERROR_NONE {
			return "",false;
		}
	}
	alloc_err : runtime.Allocator_Error;
	clean_path , alloc_err = os.clean_path(clean_path, context.temp_allocator);
	if alloc_err != nil {
		return "",false;
	}

	return clean_path, true;
}
