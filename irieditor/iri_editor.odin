package iriedit

import "core:log"

import "base:runtime"
import "core:mem"
import "core:strings"
import "core:os"
import "core:fmt"

import iri "../iriengine"
import iria "../iriengine/iriasset"

import im "odinary:dear_imguy"
import "odinary:platformly"

// README
// ===========================================================================
// @Note on using the editor..
// The Iri editor is efectivly just using normal engine features and implementing them
// into a gui interface using imgui drawing. It is not required and has to be explicitly initialized
// by the user application using init()/deinit(), it should be initialized after the engine and deinitialized
//  before the engine's deinit.

// use toggle_ui() to toggle on/off UI rendering

// the editor is build in a modular way and implements various ui interfaces as dear_imgui draw commands
// that means even without initializing the editor some draw procedures can still be used anyway.
// some procedure need to track state from the editor so it may still be adviasable to initialize the editor even when
// implementing your own editor ui on top of these procedures.
// ===========================================================================

IriEditor :: struct {

	// seperate temp arena allocator
	tmp_arena : mem.Dynamic_Arena,
	tmp_allocator : runtime.Allocator,
	// store context to used in some c callbacks.
	default_context : runtime.Context, 

	draw_ui : bool,

	enabled_windows : EditorWindowsFlags,
	
	// constant (128 byte) buffer for input text edits.
	universe_rename_buf 		: [^]u8, 
	universe_rename_buf_len 	: u32,

	_selected_entity : iri.Entity,
	// constant (128 byte) buffer for input text edits of project dir path.
	selected_entity_rename_buf 		: [^]u8, 
	selected_entity_rename_buf_len 	: u32,


	// == PROJECT BROWSER ===
	browser_update_interval_event : iri.IntervalEventID,
	show_file_type_flags : FileInfoTypeFlags,
	show_asset_type_flags : iri.AssetTypeFlags,

	curr_proj_dir     : string, 	// current directory of project to display in browser

	curr_proj_dir_buf : [^]u8, 		// buffer for input text edits of project dir path.
	curr_proj_dir_buf_len : u32,	

	// buffer for renaming files.
	file_rename_buf : [^]u8,
	file_rename_buf_len : u32,

	curr_proj_dir_file_infos : [dynamic]FileInfo,
	curr_import_path : string,

	// import 
	curr_mesh_import_flags : iri.AssetImportFlags,
}

@(private="package")
editor : ^IriEditor;

init :: proc() {

	if editor != nil {
		return;
	}

	editor = new(IriEditor, context.allocator);

	{
		block_size := 4 * mem.Megabyte; 
		mem.dynamic_arena_init(&editor.tmp_arena, context.allocator, context.allocator, block_size ,mem.DYNAMIC_ARENA_OUT_OF_BAND_SIZE_DEFAULT, mem.DEFAULT_ALIGNMENT);
		editor.tmp_allocator = mem.dynamic_arena_allocator(&editor.tmp_arena);
	}


	editor.default_context = context;

	editor.draw_ui = false;
	editor.enabled_windows = EditorWindowsFlags{.Settings,.UniverseViewer, .ProjectBrowser, .Properties}


	iri.debug_gui_set_enable(true);
	iri.debug_gui_set_editor_callback_procedure(draw_imgui_callback);

	editor._selected_entity = iri.Entity{id = -1}
	editor.selected_entity_rename_buf_len = 128;
	editor.selected_entity_rename_buf = make_multi_pointer([^]u8, 128, context.allocator);
	
	editor.universe_rename_buf_len = 128;
	editor.universe_rename_buf = make_multi_pointer([^]u8, 128, context.allocator);

	// Project browser
	editor.browser_update_interval_event = iri.schedule_interval_event(proj_browser_update_interval_callback, delay_sec = 3.0, interval_exec_duration_sec = -1, interval_wait_duration_sec = 2.5, num_intervals = -1, use_true_time  = true);

	editor.show_file_type_flags  = FileInfoTypeFlags{.Directory, .RegularFile, .AssetFile}
	editor.show_asset_type_flags = iri.ASSET_TYPE_FLAGS_ALL;
	
	editor.curr_proj_dir_buf = make_multi_pointer([^]u8, 512, context.allocator);
	editor.curr_proj_dir_buf_len = 512;


	editor.file_rename_buf_len = 128;
	editor.file_rename_buf = make_multi_pointer([^]u8, 128, context.allocator);


	proj_browser_switch_curr_proj_dir(iri.get_project_content_path());


	// import options
	editor.curr_mesh_import_flags = iri.AssetImportFlags{.LogErrors, .OverwriteExisting};


}

deinit :: proc() {

	if editor == nil {
		return;
	}

	iri.unschedule_interval_event(&editor.browser_update_interval_event);

	proj_browser_clear_curr_proj_dir_file_infos();
	delete(editor.curr_proj_dir_file_infos);

	if len(editor.curr_proj_dir) > 0 {
		delete_string(editor.curr_proj_dir);
	}

	if len(editor.curr_import_path) > 0 {
		delete_string(editor.curr_import_path);
	}

	if editor.curr_proj_dir_buf != nil {
		free(editor.curr_proj_dir_buf);
		editor.curr_proj_dir_buf = nil;
	}

	if editor.selected_entity_rename_buf != nil {
		free(editor.selected_entity_rename_buf);
		editor.selected_entity_rename_buf = nil;
	}

	if editor.universe_rename_buf != nil {
		free(editor.universe_rename_buf);
		editor.universe_rename_buf = nil;
	}

	if editor.file_rename_buf != nil {
		free(editor.file_rename_buf);
		editor.file_rename_buf = nil;
	}

	free_all(editor.tmp_allocator);
	mem.dynamic_arena_destroy(&editor.tmp_arena);

	iri.debug_gui_set_editor_callback_procedure(nil);	

	free(editor);
	editor = nil; // keep this so we can init/deinit any time as often as we want to.
}

editor_is_initialized :: proc() -> bool{
	return editor != nil;
}

toggle_ui :: proc(){
	editor.draw_ui = !editor.draw_ui;
}

enable_window :: proc(window : EditorWindow){
	editor.enabled_windows += EditorWindowsFlags{window};
}

disable_window :: proc(window : EditorWindow){
	editor.enabled_windows -= EditorWindowsFlags{window};
}


@(private="file")
draw_imgui_callback :: proc() {


	if editor == nil {
		return;
	}

	if !editor.draw_ui {
		return;
	}

	free_all(editor.tmp_allocator);

	// overwrite the tmp allocator for our purposes
	context.temp_allocator = editor.tmp_allocator;

	im.DockSpaceOverViewport(flags = im.DockNodeFlags{.PassthruCentralNode},window_class = nil);
	//im.DockSpaceOverViewport(dockspace_id: ID = {}, viewport: ^Viewport = nil, flags: DockNodeFlags = {}, window_class: ^WindowClass = nil)

	draw_window_settings();
	draw_window_universe_viewer();
	draw_window_project_browser();
	draw_window_properties();
	draw_main_menu_bar();
}

@(private="package")
select_entity :: proc(universe : ^iri.Universe, entity : iri.Entity) {

	if !editor_is_initialized(){
		return;
	}

	editor._selected_entity = entity;

	ent_name , ecs_err := iri.entity_get_name(entity, universe);
	
	if ecs_err == iri.EcsError.None {
		// copy name to buffer
		copy_string_to_buffer_null_terminate(editor.selected_entity_rename_buf ,cast(int)editor.selected_entity_rename_buf_len, ent_name)
	}
}

@(private="file")
proj_browser_update_interval_callback :: proc(event_id : iri.IntervalEventID, interval_elapsed_time : f32, interval_progression_normalized_01 : f32, curr_interval : u32, user_data : rawptr){

	if .ProjectBrowser in editor.enabled_windows {
		proj_browser_reload_curr_proj_dir_file_infos()
	}
}

// Get a unique filename respective to the contents of a directory 'dir'. A number suffix '_N' is applied to the filename
// if neccesary, where 'N' is a number . Works on directory names too and keeps file extentions of filenames (e.g .glsl.spv) in takt.
// returns empty string and false if directory 'dir' does not exist or no unique name could be found. 
// 'return_name_only' can be used to either return the full path of 'dir/unique_name' or just the unique_name itself.
// 'max_search_iterations' defines how many suffixes we will test maximally so we dont end up searching forever
get_unique_filename_in_directory :: proc(dir : string, name : string, return_name_only : bool = false, max_search_iterations : u32 = 10_000) -> (unique_name : string, ok : bool){

	if !os.is_directory(dir) {
		return "", false;
	}

	path , alloc_error := os.join_path({dir, name}, context.temp_allocator);

	if !os.exists(path) {

		if return_name_only {
			return name, true;
		} else {
			return path, true;
		}
	}

	name_long_ext      := os.long_ext(name);
	has_extention : bool = name_long_ext != "";
	
	if has_extention {
		
		name_stem := os.short_stem(name);

		for nbr_suffix in 1..<max_search_iterations{
			
			filename_with_suffix : string = fmt.aprintf("{}_{}{}", name_stem, nbr_suffix, name_long_ext, allocator = context.temp_allocator);
			filename_path , alloc_error := os.join_path({dir, filename_with_suffix}, context.temp_allocator);
			if !os.exists(filename_path) {
				if return_name_only {
					return filename_with_suffix, true;
				} else {
					return filename_path, true;
				}
			}
		}
	} else {

		for nbr_suffix in 1..<max_search_iterations{
			filename_with_suffix : string = fmt.aprintf("{}_{}", name, nbr_suffix, allocator = context.temp_allocator);
			filename_path , alloc_error := os.join_path({dir, filename_with_suffix}, context.temp_allocator);
			if !os.exists(filename_path) {
				
				if return_name_only {
					return filename_with_suffix, true;
				} else {
					return filename_path, true;
				}
			}
		}
	}

	log.warnf("Editor: Cound't find unique name for folder using {} suffix tests.", max_search_iterations);

	return "", false;
}


// accept dear-ImGui DragDrop of files (file_info) drag sources. 
// Specify with flags what kind of file types to accept for a DragDrop target.
// This will return a file info only when the payload was accepted accoring to the specified flags and 
// wil return nil in all other cases. The returned ^FileInfo ptr is read only!
file_info_drag_drop_target :: proc(file_type_flags : FileInfoTypeFlags, asset_type_flags : iri.AssetTypeFlags) -> ^FileInfo {

	if im.BeginDragDropTarget() {
		defer im.EndDragDropTarget();

		peek_payload: {

			payload : ^im.Payload = im.GetDragDropPayload();
			if payload == nil {
				return nil;
			}
			if !im.Payload_IsDataType(payload, "FileInfoDragDrop") {
				return nil;
			}

			file_info : ^FileInfo = cast(^FileInfo)payload.Data;
			if file_info == nil {
				return nil;
			}

			if file_info.file_type not_in file_type_flags {
				return nil;
			}

			if file_info.file_type == .AssetFile && file_info.asset_type not_in asset_type_flags {
				return nil;
			}
		}

		accept_payload: {

			drag_drop_flags := im.DragDropFlags{};
			payload : ^im.Payload = im.AcceptDragDropPayload("FileInfoDragDrop", drag_drop_flags);
			if payload == nil {
				return nil;
			}

			file_info : ^FileInfo = cast(^FileInfo)payload.Data;

			return file_info;

		} // accept_payload scope end
		
	}

	return nil;
}