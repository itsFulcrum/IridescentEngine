package iriedit

import "core:log"
import "core:os"
import "core:strings"
import "core:fmt"
import "base:runtime"
import "core:c"

import iri "../iriengine"
import iria "../iriengine/iriasset"
import im "odinary:dear_imguy"

import "odinary:platformly"
import "core:sort"

import sdl "vendor:sdl3"

DIRECTORY_COL 		:: im.Vec4{0.28, 0.25, 0.25, 1.00}
REG_FILE_COL 		:: im.Vec4{0.18, 0.21, 0.25, 1.00}
UNIVERSE_ASSET_COL 	:: im.Vec4{ 0.3, 0.27, 0.17, 1.00}
MESH_ASSET_COL 		:: im.Vec4{0.19, 0.25, 0.22, 1.00}
MATERIAL_ASSET_COL 	:: im.Vec4{0.22, 0.21, 0.18, 1.00}
LIGHT_ASSET_COL 	:: im.Vec4{0.14, 0.22, 0.25, 1.00}
GRAYED_TEXT_COL 	:: im.Vec4{0.2, 0.2, 0.2, 1.00}


// @Note: requires editor to be initialized!
draw_project_browser :: proc(){
	
	if !editor_is_initialized() {
		return
	}

	@static list_view : bool = true;
	@static btn_size_ctrl : f32 = 80;
	dir_path : string = editor.curr_proj_dir;


	menu_bar: {
	 	if im.BeginMenuBar() {

	 		im.Spacing()
	 		if im.BeginMenu("View Options"){
	 			defer im.EndMenu();

	 			im.Checkbox("List View", &list_view)
	 			im.Separator();

	 			enum_flags_checkbox("Directories"    , FileInfoType.Directory, &editor.show_file_type_flags);
	 			enum_flags_checkbox("Regular Files"  , FileInfoType.RegularFile, &editor.show_file_type_flags);
	 			enum_flags_checkbox("Iri Asset Files", FileInfoType.AssetFile, &editor.show_file_type_flags);
	 			
	 			im.Spacing();
	 			disabled_assets := .AssetFile not_in editor.show_file_type_flags;
	 			im.BeginDisabled(disabled_assets);
	 			
	 			enum_flags_checkbox("Universe Assets", iri.AssetType.Universe, &editor.show_asset_type_flags);
	 			enum_flags_checkbox("MeshData Assets"    , iri.AssetType.Mesh    , &editor.show_asset_type_flags);
	 			enum_flags_checkbox("Material Assets", iri.AssetType.Material, &editor.show_asset_type_flags);
	 			enum_flags_checkbox("Lights   Assets"   , iri.AssetType.Light   , &editor.show_asset_type_flags);

	 			im.EndDisabled()
	 		}	

	 		//menu_avail := im.GetContentRegionAvail();
	 		im.SetCursorPosX( im.GetCursorPosX() + max(0.0, im.GetContentRegionAvail().x - 232) );

 			im.Text("Icon Size:")
 			im.SetNextItemWidth(155);
			im.SliderFloat("##IconSize", &btn_size_ctrl, 25, 250);
	 		
	 		im.Spacing()
	 		im.Spacing()
		}
		im.EndMenuBar();
	}

	im.SameLine();
	buf_cstr_alias := cstring(editor.curr_proj_dir_buf);
	if im.InputText("##PathInput", buf_cstr_alias , cast(uint)editor.curr_proj_dir_buf_len, im.InputTextFlags{.ElideLeft,.EnterReturnsTrue}) {
		
		// test if the path would exist.

		str : string = strings.clone_from_cstring(buf_cstr_alias, context.temp_allocator);

		joined , e1 := os.join_path({iri.get_project_path(), str}, context.temp_allocator);
		cleaned , e2 := os.clean_path(joined, context.temp_allocator);
		
		if os.is_directory(cleaned){
			proj_browser_switch_curr_proj_dir(cleaned);
		}

	}
	im.SameLine();
	if im.Button("Refresh") {
		proj_browser_reload_curr_proj_dir_file_infos();
	}

	im.Separator()

	btn_size := im.Vec2{btn_size_ctrl, btn_size_ctrl};

	if list_view {
		btn_size = im.Vec2{32, 24}
	}



	if im.Button("...##ParentFolder", btn_size) {
		
		base, _ := os.split_path(editor.curr_proj_dir);
		proj_browser_switch_curr_proj_dir(base);
	}
	drop_parent: if drop_file_info := file_info_drag_drop_target({.Directory,.AssetFile, .RegularFile}, iri.ASSET_TYPE_FLAGS_ALL); drop_file_info != nil {

		base , filename := os.split_path(drop_file_info.fullpath);
		base_base , _ := os.split_path(base);

		old_path : string = drop_file_info.fullpath;
		new_path : string = os.join_path({base_base, filename}, context.temp_allocator) or_break drop_parent;
		iri.project_rename_named_file(old_path, new_path);
		proj_browser_reload_curr_proj_dir_file_infos();
	}

	im.SetItemTooltip("Parent Folder")

	if !list_view {
		im.SameLine();
	}

	avail := im.GetContentRegionAvail();
	row_space_occupied : f32 = 0.0;

	// DISPALY ALL FILES/DIRECTORIES
	files_loop: for &info, index in editor.curr_proj_dir_file_infos {

		if info.file_type not_in editor.show_file_type_flags {
			continue files_loop;
		}

		if info.file_type == .AssetFile && info.asset_type not_in editor.show_asset_type_flags {
			continue;
		}

		// filename can be directory name too.
		_ , filename := os.split_path(info.fullpath);
		//filename_cstr : cstring = strings.clone_to_cstring(filename, context.temp_allocator);
		file_btn_label : cstring = list_view ? fmt_cstr("##{}", filename, allocator = context.temp_allocator) : fmt_cstr("{}", filename, allocator = context.temp_allocator)



		switch info.file_type {

			case .Directory: {

				im.PushStyleColorImVec4(im.Col.Button, DIRECTORY_COL);

				if im.Button(file_btn_label, btn_size) {
					proj_browser_switch_curr_proj_dir(info.fullpath);
				}

				im.PopStyleColor();
				
				// DRAG DROP TARGET: move files inside this directory.
				drop: if drop_file_info := file_info_drag_drop_target({.Directory,.AssetFile, .RegularFile}, iri.ASSET_TYPE_FLAGS_ALL); drop_file_info != nil {
					if drop_file_info != &info {

						_ , filename := os.split_path(drop_file_info.fullpath);
						old_path : string = drop_file_info.fullpath;
						new_path : string = os.join_path({info.fullpath, filename}, context.temp_allocator) or_break drop;
						iri.project_rename_named_file(old_path, new_path);
						proj_browser_reload_curr_proj_dir_file_infos();
					}
				}
			}
			case .RegularFile: {

				im.PushStyleColorImVec4(im.Col.Button, REG_FILE_COL);
				im.Button(file_btn_label, btn_size);
				im.PopStyleColor();

			}
			case .AssetFile: {
				
				switch info.asset_type {
					case .None 	: im.PushStyleColorImVec4(im.Col.Button, REG_FILE_COL);
					case .Mesh 		: im.PushStyleColorImVec4(im.Col.Button, MESH_ASSET_COL);
					case .Material 	: im.PushStyleColorImVec4(im.Col.Button, MATERIAL_ASSET_COL);
					case .Universe 	: im.PushStyleColorImVec4(im.Col.Button, UNIVERSE_ASSET_COL);
					case .Light     : im.PushStyleColorImVec4(im.Col.Button, LIGHT_ASSET_COL);
					case .SceneCollection	: im.PushStyleColorImVec4(im.Col.Button, LIGHT_ASSET_COL); // TODO: color
				}

				defer im.PopStyleColor();

				if im.Button(file_btn_label, btn_size) {

					#partial switch info.asset_type {
						case .Universe 	: {

							iri.multiverse_jump(info.asset_uuid, iri.UniverseUpdateCallbacks{}, store_active_universe = true);
						}
					}
				}
				
			}
		}

		// DRAG DROP SOURCE
		if im.BeginDragDropSource() {
			im.SetDragDropPayload("FileInfoDragDrop", cast(rawptr)&info, size_of(info));
			im.EndDragDropSource();
		}

		// == RIGHT CLICK MENU for file buttons.
		popup_label : cstring = fmt_cstr("FileRCMenu##{}", index);
		if im.BeginPopupContextItem(popup_label) {
			defer im.EndPopup();


			im.Text("- %s -", filename);
			im.Separator();


			if im.MenuItem("Rename") {
				proj_browser_popup_rename_file_entry(&info)
			}
			
			if im.MenuItem("Delete") {
				proj_browser_delete_named_file(&info);
			}

			if im.MenuItem("Copy Path") {
				rel_path, rel_path_ok := iri.project_get_relative_path(info.fullpath, context.temp_allocator);
				if rel_path_ok {
					rel_path_cstr := strings.clone_to_cstring(rel_path, context.temp_allocator);
					im.SetClipboardText(rel_path_cstr);
				}
			}
			
			// if info.file_type == .AssetFile {

			// 	if im.MenuItem("Copy AssetUUID") {

			// 	}
			// }
		}

		if !list_view {
			// Handle arrangment, if we can put next item on the same line or begin a new line.
			item_size := im.GetItemRectSize();
			row_space_occupied += item_size.x;

			if row_space_occupied + item_size.x < avail.x {
				im.SameLine();
			} else {
				row_space_occupied = 0.0;
			}

		} else {
			im.SameLine();
			im.Text("%s", filename)

			txt : cstring;
			
			if info.file_type == .Directory {
				txt = "Folder --";
			} else if info.file_type == .AssetFile {
				txt = fmt_cstr("{} --", info.asset_type);
			} else if info.file_type == .RegularFile {
				txt = "File --";
			}
			
			txt_size := im.CalcTextSize(txt);

			im.SameLine();
			im.SetCursorPosX( im.GetCursorPosX() + max(0.0, im.GetContentRegionAvail().x - txt_size.x) );

			im.TextDisabled(txt);
		}
	}

	
	is_any_hovered : bool = im.IsAnyItemHovered();

	if !is_any_hovered  || im.IsPopupOpen("RightClickMenu") {

		pop_flags : im.PopupFlags = im.PopupFlags(1);
		// right click menu
		if im.BeginPopupContextWindow("RightClickMenu", pop_flags) {

			if im.BeginMenu("Import") {
				
				if im.MenuItem("Import GLTF"){
					proj_browser_popup_modal_import_gltf(open_modal = true)
				}
				
				im.EndMenu()
			}

			if im.BeginMenu("Create") {
				defer im.EndMenu()
				
				if im.MenuItem("New Folder"){
				
					folder_path , name_ok := get_unique_filename_in_directory(editor.curr_proj_dir, "Folder", return_name_only = false);
					if name_ok {
						make_dir_err := os.make_directory(folder_path);
						proj_browser_reload_curr_proj_dir_file_infos();
					}
				}

				if im.MenuItem("Material"){
					
				}

				if im.MenuItem("Universe"){

					uni_name , uni_name_ok := get_unique_filename_in_directory(editor.curr_proj_dir, "Universe.iria", return_name_only = true)
					
					if uni_name_ok {

						name_stem := os.short_stem(uni_name);
						new_uni, new_uni_ok := iri.asset_io_create_new_universe_asset(editor.curr_proj_dir, name_stem)

						// maybe we should switch to it directly ??
						if new_uni_ok {
							iri.universe_deinit(new_uni);
							free(new_uni);
						}
						
						proj_browser_reload_curr_proj_dir_file_infos();
					}
				}
			}

			if im.Selectable("Open Folder...") {
				platformly.open_system_folder_at_path(editor.curr_proj_dir);
			}

			im.EndPopup();
		}
	}

	// MODALS & Popups
	proj_browser_popup_rename_file_entry();
	proj_browser_popup_modal_import_gltf();
	proj_browser_popup_modal_ask_delete_really();
}

// Should be called each frame with no parameter
// and can be called with paramter true to open it next time its called normally
// because modals and popups have to be opened in the same scope.
proj_browser_popup_modal_import_gltf :: proc(open_modal : bool = false) {

	@static do_open : bool = false;
	@static is_open : bool = false;
	
	if open_modal {

		if !is_open {
			do_open = true;
		}

		return;
	}

	if do_open {

		im.OpenPopup("Import Mesh gltf");
		is_open = true;
		do_open = false;
	}

	flags := im.WindowFlags{.AlwaysAutoResize}

	if im.BeginPopupModal("Import Mesh gltf", nil, flags) {

		// import options
		include_set := iri.AssetImportFlags{.LogErrors, .OverwriteExisting, .MeshImportMaterials, .MeshImportLights, .MeshCombineMeshes,
											.MeshForceVertexLayout, .MeshForceVertexLayoutMinimal, .MeshForceVertexLayoutStandard, .MeshForceVertexLayoutExtended,
											.MeshCreateCollection}
		draw_asset_import_flags_settings(&editor.curr_mesh_import_flags, include_set);

		if im.Button("Open File...") {
			window := iri.get_window_context();
			default_dir : cstring = strings.clone_to_cstring(iri.get_project_path(), context.temp_allocator);
			sdl.ShowOpenFileDialog(callback = proj_browser_set_current_import_path_from_file_dialog_callback, userdata = nil, window = window.handle, filters = nil, nfilters = 0, default_location = default_dir, allow_many = false)
		}

		im.SameLine();

		if len(editor.curr_import_path) > 0 {
			im.Text("Path: %s", editor.curr_import_path);
		} else {
			im.Text("Path: ---");
		}

		im.Spacing();

		import_btn: if im.Button("Import"){
			
			if len(editor.curr_import_path) <= 0 {
				log.warnf("No import path set.")
				break import_btn;
			}

			import_ok := iri.asset_importer_import_gltf_to_project(editor.curr_import_path, editor.curr_proj_dir, editor.curr_mesh_import_flags);
			

			proj_browser_reload_curr_proj_dir_file_infos();

			// TODO: make a string error directly in this modal.			
			if import_ok {
				is_open = false;
				do_open = false;
				im.CloseCurrentPopup();
			}
		}

		im.SameLine();

		if im.Button("Cancel"){
			
			is_open = false;
			do_open = false;
			im.CloseCurrentPopup();
		}

		im.EndPopup();
	}
}

proj_browser_popup_rename_file_entry :: proc(file_info : ^FileInfo = nil) {

	if !editor_is_initialized(){
		return;
	}

	@static do_open : bool = false;
	@static is_open : bool = false;
	@static file_info_uintptr : uintptr = 0;

	if file_info != nil {

		if !is_open {
			do_open = true;
			file_info_uintptr = cast(uintptr)file_info;
			
			_ , filename := os.split_path(file_info.fullpath);
			stem := os.short_stem(filename);
			copy_string_to_buffer_null_terminate(editor.file_rename_buf, cast(int)editor.file_rename_buf_len, stem);
		}

		return;
	}

	if do_open {

		im.OpenPopup("RenameFileEntry");
		//is_open = true;
		do_open = false;
	}

	flags := im.WindowFlags{.AlwaysAutoResize}

	if im.BeginPopup("RenameFileEntry", flags) {
		defer im.EndPopup();

		file_info_ptr : ^FileInfo = cast(^FileInfo)file_info_uintptr;

		original_base , original_filename := os.split_path(file_info_ptr.fullpath);

		buf_cstr_alias := cstring(editor.file_rename_buf);
		//copy_str := strings.clone_from_cstring(buf_cstr_alias, context.temp_allocator);
		im.Text("Rename: %s", original_filename)


		input_flags := im.InputTextFlags{.ElideLeft, .EnterReturnsTrue, .AutoSelectAll, .CharsNoBlank};
		if im.InputText("##FileRename", buf_cstr_alias, cast(uint)editor.file_rename_buf_len, input_flags) {
			
			orig_ext := os.ext(original_filename);
			orig_has_ext : bool = orig_ext != "";

			renamed_str := strings.clone_from_cstring(buf_cstr_alias, context.temp_allocator);
			
			// we apply short stem because users may do werid stuff like append custom file extention
			// that dont match the original or add '/' path seperators etc.
			renamed_stem := os.short_stem(renamed_str);

			if orig_has_ext {
				renamed_stem = fmt.aprintf("{}{}", renamed_stem, orig_ext, allocator = context.temp_allocator);
			}

			// same name
			if renamed_stem == original_filename {
				im.CloseCurrentPopup();
				return;
			}

			name_unique, name_ok := get_unique_filename_in_directory(original_base, renamed_stem, return_name_only = true);
			if !name_ok {
				return;
			}

			from_path := file_info_ptr.fullpath;
			to_path , err := os.join_path({original_base, name_unique}, context.temp_allocator); 

			if err == nil {

				//log.debugf("Renameing: From: {}  To: {}", from_path , to_path)

				iri.project_rename_named_file(from_path, to_path);
				proj_browser_reload_curr_proj_dir_file_infos();
				im.CloseCurrentPopup();
				return;
			}

		}

	} else {
		is_open = false;
		do_open = false;
		file_info_uintptr = 0;
	}
}

// call each frame with no arguments. 
// To Open the popup, call once with true and ^FileInfo. Requires that file_info ptr remains stable until popup is closed by user
@(private="package")
proj_browser_popup_modal_ask_delete_really :: proc(open_modal : bool = false, file_info : ^FileInfo = nil){

	if !editor_is_initialized() {
		return
	}

	@static do_open : bool = false;
	@static is_open : bool = false;
	@static file_info_uintptr : uintptr = 0; // not allowed to store static pointers so we do hacky here.

	if open_modal {

		if !is_open {
			
			if file_info != nil {
				do_open = true;
				file_info_uintptr = cast(uintptr)file_info;
			}
		}
		return;
	}

	if do_open {

		im.OpenPopup("Delete Files ?");
		is_open = true;
		do_open = false;
	}

	flags := im.WindowFlags{.AlwaysAutoResize}

	if im.BeginPopupModal("Delete Files ?", nil, flags) {

		info_ptr : ^FileInfo = cast(^FileInfo)file_info_uintptr;

		proj_path := iri.get_project_path();
		rel_path , err := os.get_relative_path(proj_path, info_ptr.fullpath, context.temp_allocator); 

		im.Text("Are you sure you want to delete: \n %s", rel_path);
		im.Text("All contents will be lost")

		if im.Button("Delete") {	
						
			iri.project_delete_named_file(info_ptr.fullpath);

			proj_browser_reload_curr_proj_dir_file_infos();

			is_open = false;
			do_open = false;
			file_info_uintptr = 0;
			im.CloseCurrentPopup();
		}

		im.SameLine();

		if im.Button("Cancel"){
			
			is_open = false;
			do_open = false;
			file_info_uintptr = 0;
			im.CloseCurrentPopup();
		}

		im.EndPopup();
	}
}

// File dialog callback
@(private="package")
proj_browser_set_current_import_path_from_file_dialog_callback :: proc "c" (userdata: rawptr, filelist: [^]cstring, filter: c.int) {

	if editor == nil {
		return
	}

	context = editor.default_context;

	if filelist == nil {
		return;
	}

	path : cstring = filelist[0];

	if len(path) == 0 {
		return;
	}

	if len(editor.curr_import_path) == 0 {
		delete_string(editor.curr_import_path);
	}

	editor.curr_import_path = strings.clone_from_cstring(path, context.allocator);
}


// @Note: import flags will be modified obviously by user interaction
// specifiy through include set which options to show as we may use this procedure to implement them
// all but only show those relevant to the specific asset type.
@(private="package")
draw_asset_import_flags_settings :: proc(import_flags : ^iri.AssetImportFlags, include_set : iri.AssetImportFlags) {

	// TODO: tooltips..

	update_flag :: proc(import_flags : ^iri.AssetImportFlags, flag : iri.AssetImportFlag, enabled : bool) {

		if enabled {
			import_flags^ += iri.AssetImportFlags{flag};
		} else {
			import_flags^ -= iri.AssetImportFlags{flag};
		}
	}

	flag_checkbox :: proc(label : cstring, flag : iri.AssetImportFlag,  import_flags : ^iri.AssetImportFlags, include_set : iri.AssetImportFlags) -> bool {

		if flag not_in include_set {
			return false;
		}

		is_enabled : bool = flag in import_flags;
		if im.Checkbox(label, &is_enabled) {
			update_flag(import_flags, flag,  is_enabled);
			return true;
		}

		return false;
	}
	
	flag_checkbox("Log Errors" 				, .LogErrors, import_flags, include_set);
	flag_checkbox("Overwrite Existing Files", .OverwriteExisting, import_flags, include_set);
	flag_checkbox("Import Materials"		, .MeshImportMaterials, import_flags, include_set);
	flag_checkbox("Import Lights"			, .MeshImportLights, import_flags, include_set);
	flag_checkbox("Combine Meshes"			, .MeshCombineMeshes, import_flags, include_set);
	flag_checkbox("Force Vertex Layout"		, .MeshForceVertexLayout, import_flags, include_set);
	flag_checkbox("Create Collection"		, .MeshCreateCollection, import_flags, include_set);

	if .MeshForceVertexLayout in include_set {

		if .MeshForceVertexLayout in import_flags {
			im.Text("Force Layout: ")
			im.SameLine();
			if flag_checkbox("Minimal", .MeshForceVertexLayoutMinimal, import_flags, include_set) {
				is_enabled : bool = .MeshForceVertexLayoutMinimal in import_flags;
				if is_enabled {
					update_flag(import_flags, .MeshForceVertexLayoutStandard,  false);
					update_flag(import_flags, .MeshForceVertexLayoutExtended,  false);
				}else{
					update_flag(import_flags, .MeshForceVertexLayoutMinimal ,  true);					
				}
			}
			im.SameLine();
			if flag_checkbox("Standard", .MeshForceVertexLayoutStandard, import_flags, include_set) {
				is_enabled : bool = .MeshForceVertexLayoutStandard in import_flags;
				if is_enabled {
					update_flag(import_flags, .MeshForceVertexLayoutMinimal ,  false);
					update_flag(import_flags, .MeshForceVertexLayoutExtended,  false);
				} else{
					update_flag(import_flags, .MeshForceVertexLayoutStandard ,  true);
				}
			}
			im.SameLine();
			if flag_checkbox("Extended", .MeshForceVertexLayoutExtended, import_flags, include_set) {
				is_enabled : bool = .MeshForceVertexLayoutExtended in import_flags;
				if is_enabled {
					update_flag(import_flags, .MeshForceVertexLayoutMinimal ,  false);
					update_flag(import_flags, .MeshForceVertexLayoutStandard,  false);
				} else{
					update_flag(import_flags, .MeshForceVertexLayoutExtended ,  true);
				}
			}

		}
	}


	// 	MeshForceVertexLayout,			// enables forcing a vertex layout. specified by setting one of the 3 following flags.
	// MeshForceVertexLayoutMinimal,
	// MeshForceVertexLayoutStandard, // ignored if force minimal is set.
	// MeshForceVertexLayoutExtended, // ignored if force standard or force minimal is set


	//
}



@(private="package")
proj_browser_switch_curr_proj_dir :: proc(full_path : string){
	
	if !editor_is_initialized() {
		return
	}

	if !os.is_absolute_path(full_path){
		return;
	}

	path_clean, alloc_error := os.clean_path(full_path,context.temp_allocator);

	if !os.exists(path_clean) || !os.is_directory(path_clean){
		return;
	}

	proj_path := iri.get_project_path();

	if !strings.contains(path_clean, proj_path) {
		return;
	}

	if len(editor.curr_proj_dir) > 0 {
		delete_string(editor.curr_proj_dir);
	}

	editor.curr_proj_dir = strings.clone(path_clean, context.allocator);

	rel_dir, rel_err := os.get_relative_path(iri.get_project_path(), editor.curr_proj_dir, context.temp_allocator);

	buf_size : int = cast(int)editor.curr_proj_dir_buf_len // hardcoded atm
	// copy to buffer
	for i in 0..<len(rel_dir) {
		// bounds check
		if i >= buf_size {
			break;
		}
		editor.curr_proj_dir_buf[i] = rel_dir[i];
	}
	last : int = min(len(rel_dir), buf_size-1);
	editor.curr_proj_dir_buf[last] = 0x00; // null termination for cstring..

	proj_browser_reload_curr_proj_dir_file_infos();
}

@(private="package")
proj_browser_reload_curr_proj_dir_file_infos :: proc(){

	if !editor_is_initialized() {
		return
	}

	proj_browser_clear_curr_proj_dir_file_infos();
	
	if len(editor.curr_proj_dir) <= 0 {
		return;
	}

	if !os.exists(editor.curr_proj_dir) || !os.is_directory(editor.curr_proj_dir){
		return;
	}

	dir_f, open_err := os.open(editor.curr_proj_dir);
	if open_err != os.ERROR_NONE {
		return;
	}
	defer os.close(dir_f);


	file_infos , os_err := os.read_directory(dir_f, 0, context.temp_allocator);
	if os_err != os.ERROR_NONE {
		return;
	}	

	for &file, index in file_infos {

		info : FileInfo;

		#partial switch file.type {
			case .Directory: info.file_type = FileInfoType.Directory;
			case .Regular: {

				ext := os.ext(file.fullpath);

				if ext == iria.FILE_EXTENTION {
					info.file_type = FileInfoType.AssetFile;

					type, uuid, ok := iria.get_asset_info_from_path(file.fullpath);

					info.asset_uuid = uuid;
					info.asset_type = type;
				} else {
					info.file_type = FileInfoType.RegularFile;
				}
			}
			case: continue;
		}

		
		info.fullpath , _ = strings.clone(file.fullpath, context.allocator);

		append(&editor.curr_proj_dir_file_infos, info);
	}

	// Sort entries by directory and lexiographically.

	file_compare_proc :: proc (a : FileInfo, b : FileInfo) -> int {

		a_is_dir := a.file_type == .Directory;
		b_is_dir := b.file_type == .Directory;

		if a_is_dir && !b_is_dir {
			return -1;
		} else if !a_is_dir && b_is_dir {
			return +1;
		}
		// @speed: could cache this..
		_, a_filename := os.split_path(a.fullpath);
		_, b_filename := os.split_path(b.fullpath);
		return sort.compare_strings(a_filename, b_filename);
	}


	sort.quick_sort_proc(editor.curr_proj_dir_file_infos[:], file_compare_proc);
}


@(private="package")
proj_browser_clear_curr_proj_dir_file_infos :: proc(){

	for &info in editor.curr_proj_dir_file_infos {

		if len(info.fullpath) > 0 {
			delete_string(info.fullpath);
		}
	}
	clear(&editor.curr_proj_dir_file_infos);
}

@(private="package")
proj_browser_delete_named_file :: proc(file_info : ^FileInfo) {

	if !os.exists(file_info.fullpath) {
		return;
	}

	defer {
		proj_browser_reload_curr_proj_dir_file_infos();
	}


	switch file_info.file_type {
		case .Directory: {

			if platformly.is_empty_directory_by_path(file_info.fullpath) {
				iri.project_delete_named_file(file_info.fullpath);
			} else {
				proj_browser_popup_modal_ask_delete_really(true, file_info);
			}
		}
		case .RegularFile: {
			iri.project_delete_named_file(file_info.fullpath);
		}
		case .AssetFile: {

			if file_info.asset_type == .Universe {
				proj_browser_popup_modal_ask_delete_really(true, file_info);

			} else {
				iri.project_delete_named_file(file_info.fullpath);
			}

		}
	}
}

