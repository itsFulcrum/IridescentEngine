package iriedit

import "core:c"
import "core:log"

import iri "../iriengine"
import iria "../iriengine/iriasset"
import im "odinary:dear_imguy"



draw_window_properties :: proc() {

	window_enabled : bool = .Properties in editor.enabled_windows

	if !window_enabled {
		return;
	}

	defer {
		im.End();

		if !window_enabled {
			disable_window(.Properties);
		}
	}

	flags := im.WindowFlags{}
	window_draw: if im.Begin("Properties", &window_enabled, flags) {


		active_universe := iri.get_active_universe();

		if active_universe == nil {
			im.Text("No Universe Loaded")
			break window_draw;
		}


		im.Spacing();

		draw_entity_viewer(active_universe, editor._selected_entity);

	}
}