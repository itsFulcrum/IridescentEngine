package iriedit

import "core:c"

import iri "../iriengine"
import im "odinary:dear_imguy"


draw_window_universe_viewer :: proc() {

	window_enabled : bool = .UniverseViewer in editor.enabled_windows

	if !window_enabled {
		return;
	}

	defer {
		im.End();

		if !window_enabled {
			disable_window(.UniverseViewer);
		}
	}

	window_draw: if im.Begin("Universe Viewer", &window_enabled) {

		universe := iri.get_active_universe();

		if universe == nil {
			im.Text("No universe there is!")
			break window_draw;
		}

		tab_bar_flags := im.TabBarFlags{.NoCloseWithMiddleMouseButton};

		if im.BeginTabBar("Scene View") {

			item_flags := im.TabItemFlags{.NoAssumedClosure};
			is_open : bool = true;
			if im.BeginTabItem("Scene View", &is_open, item_flags) {

				draw_entity_list(universe);
				//draw_entity_component_table(universe);

				im.EndTabItem();
			}

			if im.BeginTabItem("Settings", &is_open, item_flags) {

				draw_universe_settings(universe);

				im.EndTabItem();
			}


			im.EndTabBar();
		}
	}
}