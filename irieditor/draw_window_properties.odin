package iriedit

import "core:c"
import "core:log"

import iri "../iriengine"
import iria "../iriengine/iriasset"
import im "odinary:dear_imguy"


PorpertiePanelTabs :: bit_set[PropertiePanelTab]
PropertiePanelTab :: enum {
	EntityView,
	AssetsView,
	MaterialEditor,
}


PROPERTIES_ALIAS_EDIT_BUFFER_SIZE :: 128 // 128 because the buffer includes null terminator but the actual alias string in the file will truncate it to 127 bytes and store lenght instead.
PropertiesPanel :: struct {
	// active_tab : PropertiePanelTab,
	// open_active_tab_next : bool,

	tab_item_base_flags : [PropertiePanelTab]im.TabItemFlags,
	tab_item_flags : [PropertiePanelTab]im.TabItemFlags,



	active_asset_type : iria.AssetType,
	active_asset_id   : iria.AssetID,
	//active_asset_alias_str : string,

	alias_edit_buffer : [PROPERTIES_ALIAS_EDIT_BUFFER_SIZE]u8,
	//_ : u8, // padding
	//alias_edit_buffer_size : u32,

}

init_properties_panel :: proc(properties : ^PropertiesPanel) {

	// for tab in PropertiePanelTab {
	// 	properties.tab_item_flags[tab]      = im.TabItemFlags{.UnsavedDocument};
	// 	properties.tab_item_base_flags[tab] = im.TabItemFlags{.UnsavedDocument};
	// }

}


properties_panel_set_active_asset :: proc(editor : ^IriEditor, asset_id : iria.AssetID ) {

	if asset_id == iria.AssetID_NONE {
		return;
	}

	entry, exists := iri.asset_get_entry(asset_id)

	props := &editor.properties_panel_state;
	
	if !exists {
		props.active_asset_id   = iria.AssetID_NONE
		props.active_asset_type = iria.AssetType.None
		props.alias_edit_buffer = [PROPERTIES_ALIAS_EDIT_BUFFER_SIZE]u8{};
		return;
	}


	props.active_asset_id   = asset_id;
	props.active_asset_type = entry.type;

	// clear alias buffer
	props.alias_edit_buffer = [PROPERTIES_ALIAS_EDIT_BUFFER_SIZE]u8{};


	alias := entry.alias;
	if len(alias) > 0 {
		copy_string_to_buffer_null_terminate(&props.alias_edit_buffer[0], PROPERTIES_ALIAS_EDIT_BUFFER_SIZE, alias)
	}

	properties_panel_select_tab(editor, .AssetsView);	
}

properties_panel_select_tab :: proc(editor : ^IriEditor, tab : PropertiePanelTab){

	editor.properties_panel_state.tab_item_flags[tab] += im.TabItemFlags{.SetSelected};
}


draw_window_properties :: proc(editor : ^IriEditor,) {

	window_enabled : bool = .Properties in editor.enabled_windows

	if !window_enabled {
		return;
	}


	defer if !window_enabled {
		disable_window(.Properties);
	}
	defer im.End();

	flags := im.WindowFlags{}
	window_draw: if im.Begin("Properties", &window_enabled, flags) {

		active_universe := iri.get_active_universe();

		props := &editor.properties_panel_state;

		// Reset Tabs flags.
		defer {
			for tab in PropertiePanelTab {
				props.tab_item_flags[tab] = props.tab_item_base_flags[tab];
			}
		}



		bar_flags := im.TabBarFlags{.AutoSelectNewTabs}
		if im.BeginTabBar("PropertiesTabPanel") {
			defer im.EndTabBar();


			entity_viewer: if im.BeginTabItem("Entity", nil, props.tab_item_flags[.EntityView]) {
				defer im.EndTabItem();

				if active_universe == nil {
					im.Text("No Universe Loaded")
					break entity_viewer;
				}
				
				draw_entity_viewer(active_universe, editor._selected_entity);
			}

			if im.BeginTabItem("Assets", nil, props.tab_item_flags[.AssetsView]) {
				defer im.EndTabItem();

				draw_properties_tab_asset_files(editor)

			}

			if im.BeginTabItem("Materials", nil, props.tab_item_flags[.MaterialEditor]) {
				defer im.EndTabItem();

				im.Text("Not implmented yet, ")

			}
		}

		im.Spacing();


	}
}