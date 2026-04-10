package iri

import "core:log"
import "core:os"
import "core:strings"
import iria "iriasset"

import "odinary:platformly"



get_project_path :: proc() -> string {
	return engine.project_path;
}

get_project_content_path :: proc() -> string {
	return engine.project_content_path;
}

get_resources_path :: proc() -> string {
	return engine.engine_resources_path;
}

// Validate that engine resources path is likely correct
// but does not gurantee that all files are present and not corrupted.
@(require_results)
@(private="package")
project_validate_engine_resources_path :: proc(engine_resources_path : string) -> bool {
	
	if !os.is_directory(engine_resources_path) {
		return false;
	}

	shaders_path    , alloc_err1 := os.join_path({engine_resources_path, "shaders"}, context.temp_allocator);
	shader_lib_path , alloc_err2 := os.join_path({engine_resources_path, "shader_lib"}, context.temp_allocator);
	rendering_path  , alloc_err3 := os.join_path({engine_resources_path, "rendering"}, context.temp_allocator);

	if !os.is_directory(shaders_path) {
		return false;
	}

	if !os.is_directory(shader_lib_path) {
		return false;
	}

	if !os.is_directory(rendering_path) {
		return false;
	}

	return true;
}


@(require_results)
@(private="package")
project_validate_or_create_project_folder :: proc(init_info : EngineInitInfo) -> (ok : bool) {
	
	if !os.is_directory(init_info.project_path) {

		if !init_info.initialize_empty_project {
			log.errorf("Project path in EngineInitInfo is not a valid directory, Path: {}", init_info.project_path);
			return false;
		}
		
		make_dir_err := os.make_directory_all(init_info.project_path);
		if make_dir_err != os.ERROR_NONE {
			
			log.errorf("Failed to create directory for new project at path: {}", init_info.project_path);
			return false;
		}
	}

	// Now validate that the engine resources path within exists which is the minimum of what a project needs.
	project_engine_resources_path, alloc_err := os.join_path({init_info.project_path, "engine_resources"}, context.temp_allocator);
	project_engine_resources_path, alloc_err = os.clean_path(project_engine_resources_path, context.temp_allocator);

	project_engine_res_path_ok := project_validate_engine_resources_path(project_engine_resources_path);

	// if the 'engine_resources' subfolder of the provided project directory is not valid (not existing or incomplete)
	// then check if user wants to create a new project in which case we need the path 
	// to the original 'engine_resources' folder of the engine odin project to copy it to the user project folder.
	// we must return false and exit the application if we cannot find this original path. (in case of a binary realse where IriEngine source code is not present.)
	if !project_engine_res_path_ok {

		if init_info.initialize_empty_project {

			this_file_dir := #directory; // get the directory of this file.

			original_res_path, alloc_err1 := os.join_path({this_file_dir, "../engine_resources"}, context.temp_allocator);
			original_res_path, alloc_err1 = os.clean_path(original_res_path, context.temp_allocator);

			original_engine_res_path_ok := project_validate_engine_resources_path(original_res_path);

			if !original_engine_res_path_ok {
				log.errorf("Unable to initialze new project at: {} because we could not find the original 'engine_resources' sub folder that ships with this IriEngine. This will happen on binary releases when the project folder is corrupted. For project creation the engine needs to copy the origianl 'engine_resources' folder (provided with the engine) to the new user project folder.", init_info.project_path);
				return false;
			}

			// make sure delete the existing folder first if it was only invalid because some stuff inside was missing
			// then we copy a fresh copy to the project. 
			
			if os.exists(project_engine_resources_path) {
				remove_err := os.remove_all(project_engine_resources_path);
				if remove_err != os.ERROR_NONE {
					log.errorf("Faild to remove 'engine_resources' subfolder of within project folder while trying to make a fresh copy from original engine_resources folder from the Iri Engine, Error code: {}", remove_err);
					return false;
				}
			}
			

			// for some reason we need absolute paths to copy a directory.
			abs_original_path, e1 := os.get_absolute_path(original_res_path, context.temp_allocator);
			abs_project_path,  e2 := os.get_absolute_path(project_engine_resources_path, context.temp_allocator);

			assert(e1 == os.ERROR_NONE)
			assert(e2 == os.ERROR_NONE)

			copy_dir_err := os.copy_directory_all(abs_project_path, abs_original_path);
			if copy_dir_err != os.ERROR_NONE {
				log.errorf("Faild to copy original 'engine_resources' folder: {} to user project folder: {}, Error code: {}", original_res_path,project_engine_resources_path,copy_dir_err);
				return false;
			}

		} else {
			err_str : string = ("The 'engine_resources' subfolder is missing or incomplete in the provided project folder at: {}\n If you want to initialize a new project, make sure engine_resources_path in EngineInitInfo is set to the 'engine_resources' folder provided with this engine (so it can be copied to the project) and set 'initialize_empty_project' in EngineInitInfo to true. This is only needed once for Project creation.");
			log.errorf(err_str, project_engine_resources_path);
			return false;
		}
	}

	// Create content folder if it doesn't exist yet.

	if init_info.initialize_empty_project {
	
		content_folder_path, alloc_err2 := os.join_path({init_info.project_path, "content"}, context.temp_allocator);
		
		if !os.exists(content_folder_path) {
			make_dir_err := os.make_directory(content_folder_path);

			if make_dir_err != os.ERROR_NONE {
				log.warnf("Failed to create content directory in project at: {}, error code: {}", content_folder_path, make_dir_err);
			}
		}
	}

	return true;
}



// Check if a path is a part of the project current directory
// if path is relative, it will be asumed to be relative to the executable.
// On succes returns the a cleaned version of absolute filepath
// allocated using context.temp_allocator.
project_contains_path :: proc(path : string) -> (cleaned_absolute_path : string, contains : bool) {
	engine_assert(engine != nil);

	abs_path , os_err1 := os.get_absolute_path(path, context.temp_allocator);
	abs_path , os_err1  = os.clean_path(abs_path, context.temp_allocator);

	if !os.exists(abs_path) {
		return "", false;
	}

	proj_path := get_project_path();

	if !strings.has_prefix(abs_path, proj_path) {
		return "", false;
	}

	return abs_path, true;
}

// Check if a path is a subpath of the current project directory
// Does not check if path actually exists..
// if path is relative, it will be asumed to be relative to the executable.
// On succes returns the a cleaned version of absolute filepath
// allocated using context.temp_allocator.
project_contents_contains_path :: proc(path : string) -> (cleaned_absolute_path : string, contains : bool) {
	
	engine_assert(engine != nil);

	abs_path , os_err1 := os.get_absolute_path(path, context.temp_allocator);
	abs_path , os_err1  = os.clean_path(abs_path, context.temp_allocator);

	contents_path := get_project_content_path();

	if !strings.has_prefix(abs_path, contents_path) {
		return "", false;
	}

	return abs_path, true;
}

// Rename a named file. Works on directories but expects old_path and new_path are of same named file type. aka: Cannot rename a directory to a file!
project_rename_named_file :: proc(old_path : string, new_path : string){

	_old_path, contains_old := project_contents_contains_path(old_path);
	if !contains_old {
		log.warnf("Renaming files outside the 'content' folder is not allowed, {}", old_path);
		return; // we dont allow deleting stuff outside of contents folder.
	}

	_new_path, contains_new := project_contents_contains_path(new_path);
	if !contains_new {
		log.warnf("Renaming files to something outside the 'content' folder is not allowed, {}", new_path);
		return; // we dont allow deleting stuff outside of contents folder.
	}

	old_is_dir  := os.is_directory(_old_path);
	old_is_file := os.is_file(_old_path);

	if !old_is_dir && !old_is_file {
		return;
	}

	// dont allow overwriting.
	if os.exists(_new_path) {
		log.warnf("Cannot move file/directory because new path already exists {}", _new_path)
		return;
	}

	is_file_scope: if old_is_file {

		asset_uuid, asset_type, is_asset_file := iria.is_valid_asset_file(_old_path);

		rename_err := os.rename(_old_path, _new_path);
		if rename_err != os.ERROR_NONE {
			log.warnf("Failed to rename file,{}, old path: {}, new path: {}", rename_err, _old_path, _new_path);
			return;
		}

		if is_asset_file {
			// This will overwrite the current entry of the asset_id..
			asset_manager := engine.asset_manager;
			asset_manager_register_asset_file_by_path(asset_manager, _new_path);
		}

		return;
	}

	rename_err := os.rename(_old_path, _new_path);
	if rename_err != os.ERROR_NONE {
		log.warnf("Failed to rename file,{}, old path: {}, new path: {}", rename_err, _old_path, _new_path);
		return;
	}
	
	// rescan the new direcotry, which will update all asset files inside it with the new paths.
	asset_manager := engine.asset_manager;
	asset_manager_scan_project_directory_recursiv(asset_manager, _new_path);
}

// == IMPORTANT ==: This will delete files, AND directories INCLUDING all folder Contents.
// This procedure handles updating the asset managers entries to asset files. aka removing them form the hashmap
// but it does not fix missing references. If one asset referances another asset by uuid and we delete this 
// asset file, it will be a missing referance.
project_delete_named_file :: proc(path : string) {

	abs_path , contains := project_contents_contains_path(path);
	if !contains {
		log.warnf("Deleting files outside the 'content' folder is not allowed, {}", path);
		return; // we dont allow deleting stuff outside of contents folder.
	}

	is_dir  := os.is_directory(abs_path);
	is_file := os.is_file(abs_path);

	if !is_dir && !is_file {
		return;
	}


	is_file_scope: if is_file {

		asset_uuid, asset_type, is_asset_file := iria.is_valid_asset_file(abs_path);

		rem_err := os.remove(abs_path);
		if rem_err != os.ERROR_NONE {
			// unlikely that this error happens, probably only if file is opened/locked elsewhere..
			log.warnf("Failed to delete file: {}, {}", rem_err, abs_path);
			return;
		}

		if is_asset_file {
			
			asset_manager := engine.asset_manager;
			asset_manager_unregister_entry(asset_manager, asset_uuid, asset_type);

		}
		return;
	}


	// Named file is a directory.
	// First check if the directory is empty..
	is_empty := platformly.is_empty_directory_by_path(abs_path);

	if is_empty {
		rem_err := os.remove(abs_path);
		if rem_err != os.ERROR_NONE {
			log.warnf("Failed to delete empty directory: {} , {}", rem_err, abs_path);
		}

		return;
	}

	asset_manager := engine.asset_manager;
	asset_manager_unscan_project_directory_recursiv(asset_manager, abs_path);

	rem_err := os.remove_all(abs_path);
	if rem_err != os.ERROR_NONE {
		log.warnf("Failed to delete directory: {} , {}", rem_err, abs_path);
	}
}

// given an absolute path, get the relative path from the project directory
// returns false if abs_path is invalid
project_get_relative_path :: proc(abs_path : string, allocator := context.allocator) -> (string, bool) {

	if !os.is_absolute_path(abs_path) {
		return "", false;
	}

	// @Note expects proj_path to be an absolute and normalized path (clean_path() was called on it)
	proj_path := get_project_path();

	rel_path , rel_path_err := os.get_relative_path(proj_path, abs_path, allocator);
	if rel_path_err != os.ERROR_NONE {
		return "", false;
	}

	return rel_path, true;

}

// Given a relative path (from the project directory) get the absolute path. 
// Returns false on erros
project_get_absolute_path :: proc(rel_path : string, allocator := context.allocator) -> (string, bool) {

	if os.is_absolute_path(rel_path){
		return "", false;
	}

	abs_path, err := os.join_path({get_project_path(), rel_path}, allocator);
	if err != nil {
		return "", false;
	}

	return abs_path, true;
}