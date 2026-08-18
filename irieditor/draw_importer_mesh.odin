package iriedit

import "core:log"
import "core:strings"

import im "odinary:dear_imguy"
import iri "../iriengine"

import sdl "vendor:sdl3"

// Should be called each frame with no parameter
// and can be called with paramter true to open it next time its called normally
// because modals and popups have to be opened in the same scope.
editor_proj_browser_popup_modal_import_mesh_gltf :: proc(open_modal : bool = false) {

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


		importer_settings := & editor.importer_settings;

		// import options
		include_set := iri.AssetMeshImportFlags{.LogErrors, .OverwriteExisting, .MeshImportMaterials, .MeshImportLights, .MeshJoinAllMeshes, .MeshSeparateFiles,
											.MeshForceVertexLayout, .MeshForceVertexLayoutMinimal, .MeshForceVertexLayoutStandard, .MeshForceVertexLayoutExtended}
		
		draw_mesh_import_settings(&importer_settings.curr_mesh_import_flags, include_set);

		if im.Button("Open File...") {
			window := iri.get_window_context();
			directory : cstring = editor_proj_browser_get_current_import_directory_path();
			sdl.ShowOpenFileDialog(callback = proj_browser_set_current_import_path_from_file_dialog_callback, userdata = nil, window = window.handle, filters = nil, nfilters = 0, default_location = directory, allow_many = false)
		}

		im.SameLine();

		if len(importer_settings.curr_import_path) > 0 {
			im.Text("Path: %s", importer_settings.curr_import_path);
		} else {
			im.Text("Path: ---");
		}

		im.Spacing();

		import_btn: if im.Button("Import"){
			
			if len(importer_settings.curr_import_path) <= 0 {
				log.warnf("No import path set.")
				break import_btn;
			}

			import_ok := iri.asset_importer_import_gltf_to_project(importer_settings.curr_import_path, editor.curr_proj_dir, importer_settings.curr_mesh_import_flags);
			

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

// @Note: import flags will be modified obviously by user interaction
// specifiy through include set which options to show as we may use this procedure to implement them
// all but only show those relevant to the specific asset type.
@(private="package")
draw_mesh_import_settings :: proc(import_flags : ^iri.AssetMeshImportFlags, include_set : iri.AssetMeshImportFlags) {

	// TODO: tooltips..

	update_flag :: proc(import_flags : ^iri.AssetMeshImportFlags, flag : iri.AssetMeshImportFlag, enabled : bool) {

		if enabled {
			import_flags^ += iri.AssetMeshImportFlags{flag};
		} else {
			import_flags^ -= iri.AssetMeshImportFlags{flag};
		}
	}

	flag_checkbox :: proc(label : cstring, flag : iri.AssetMeshImportFlag,  import_flags : ^iri.AssetMeshImportFlags, include_set : iri.AssetMeshImportFlags) -> bool {

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

	im.Spacing();

	flag_checkbox("Import Materials"		, .MeshImportMaterials, import_flags, include_set);
	flag_checkbox("Import Lights"			, .MeshImportLights, import_flags, include_set);
	
	flag_checkbox("Join Meshes"			, .MeshJoinAllMeshes, import_flags, include_set);
	
	//flag_checkbox("Join Same Material"			, .MeshJoinSameMaterial, import_flags, include_set);
	//im.SetItemTooltip("Not yet implemented");
	
	flag_checkbox("Separate Files"			, .MeshSeparateFiles, import_flags, include_set);
	//im.SetItemTooltip("Non Separate files are not yet implemented");

	//flag_checkbox("Create Collection"		, .MeshCreateCollection, import_flags, include_set);
	flag_checkbox("Force Vertex Layout"		, .MeshForceVertexLayout, import_flags, include_set);
	im.SetItemTooltip("Specify a specific Vertex Layout, otherwise Auto Choose per Mesh");



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
			im.SetItemTooltip("qtangent.xyzw + uv0.xy")
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
			im.SetItemTooltip("qtangent.xyzw + uv0.xy + color0.rgba")
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
			im.SetItemTooltip("qtangent.xyzw + uv0.xy + uv1.xy + color0.rgba + color1.rgba")

		}
	}
}