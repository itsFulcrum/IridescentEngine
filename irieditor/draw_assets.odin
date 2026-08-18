package iriedit

import "core:strings"
import "core:log"
import "core:os"

import iri "../iriengine"
import iria "../iriengine/iriasset"
import im "odinary:dear_imguy"



draw_assets_view :: proc(){


	asset_entries := iri.asset_manager_get_entries_map_read_only();

	if im.Button("Rescan Project") {
		iri.asset_manager_rescan_entire_project();	
	}

	NUM_COLLUMS :: 4


	@static asset_type_filter : iria.AssetTypeFlags = iria.ASSET_TYPE_FLAGS_ALL;

	im.Text("Asset Filter:")
	im.SameLine();
	enum_flags_checkbox("Universe##FilterFlag", iria.AssetType.Universe, &asset_type_filter);
	im.SameLine();
	enum_flags_checkbox("Material##FilterFlag", iria.AssetType.Material, &asset_type_filter);
	im.SameLine();
	enum_flags_checkbox("Model##FilterFlag", iria.AssetType.Model, &asset_type_filter);
	im.SameLine();
	enum_flags_checkbox("Light##FilterFlag", iria.AssetType.Light, &asset_type_filter);
	im.SameLine();
	enum_flags_checkbox("FontAtlas##FilterFlag", iria.AssetType.FontAtlas, &asset_type_filter);

	table_flags := im.TableFlags_Resizable |  im.TableFlags_Borders;

	if im.BeginTable("Entity", NUM_COLLUMS, table_flags) {

		defer im.EndTable();

		im.TableHeadersRow();

		im.TableSetColumnIndex(0);
		im.Text("Type");

		im.TableSetColumnIndex(1);
		im.Text("File");
		im.TableSetColumnIndex(2);
		im.Text("Path");
		im.TableSetColumnIndex(3);
		im.Text("AssetID");

		row_counter : u64 = 0;
		for asset_id, &entry in asset_entries {

			row_counter += 1;

			if entry.type not_in asset_type_filter {
				continue;
			}

			im.TableNextRow();


			// Type
			im.TableSetColumnIndex(0);
			if im.Selectable(fmt_cstr("{}##{}", entry.type, row_counter)) {

				if editor_is_initialized() {
					properties_panel_set_active_asset(editor, asset_id);
				}
			}

			_ , filename := os.split_path(entry.path);

			// Filename
			im.TableSetColumnIndex(1);
			filename_cstr := strings.clone_to_cstring(filename, context.temp_allocator);
			im.Text("%s", filename_cstr);


			// Path
			im.TableSetColumnIndex(2);
			path_cstr := strings.clone_to_cstring(entry.path ,context.temp_allocator)
			im.Text("%s", path_cstr);

			// AssetID
			im.TableSetColumnIndex(3);
			//im.Text("%i", cast(i32)index);
			str := iria.asset_id_to_string(asset_id, context.temp_allocator);
			im.Text("%s", str);
		}

	}
}



draw_properties_asset_file_editor :: proc(editor : ^IriEditor) {
	

	props := &editor.properties_panel_state;

	im.Spacing();
	im.Spacing();

	if props.active_asset_type == iria.AssetType.None {
		im.Text("Not Asset Selected");
		return;
	}

	entry, entry_exists := iri.asset_get_entry(props.active_asset_id);

	if !entry_exists {
		return;
	}

	_, filename := os.split_path(entry.path)

	name_and_type_cstr := fmt_cstr("File Name: {} 	Type: {}", filename , props.active_asset_type);
	im.Text(name_and_type_cstr);

	im.Spacing();

	im.Text("Path: %s", entry.path);


	asset_id_str := iria.asset_id_to_string(props.active_asset_id, context.temp_allocator);
	im.Text("Asset ID: %s", asset_id_str);


	im.Spacing();
	im.Spacing();

	im.Text("Current Alias: %s", entry.alias);

	im.Text("Alias: ");
	im.SameLine();

	edit_buf_cstr_cast := cstring(&props.alias_edit_buffer[0]);

	if im.InputText("##AliasInputText", edit_buf_cstr_cast, PROPERTIES_ALIAS_EDIT_BUFFER_SIZE, im.InputTextFlags{.EnterReturnsTrue}) {
		

		alias_str : string = strings.clone_from_cstring(edit_buf_cstr_cast, context.temp_allocator);

		iri.asset_set_alias(props.active_asset_id, alias_str);
		//log.debugf("New Alias is: {}", alias_str);
		// 	joined , e1 := os.join_path({iri.get_project_path(), str}, context.temp_allocator);
		// 	cleaned , e2 := os.clean_path(joined, context.temp_allocator);
			
		// 	if os.is_directory(cleaned){
		// 		proj_browser_switch_curr_proj_dir(cleaned);
		// 	}

	}
	im.SameLine();
	curr_len := cast(u32)len(edit_buf_cstr_cast);
	im.Text("%u/%u",curr_len,PROPERTIES_ALIAS_EDIT_BUFFER_SIZE -1)

}


draw_properties_tab_asset_files :: proc(editor : ^IriEditor){


	draw_properties_asset_file_editor(editor);

	im.Spacing()
	im.Separator();
	im.Spacing()
	im.Spacing()
	im.Spacing()


	draw_assets_view()
}