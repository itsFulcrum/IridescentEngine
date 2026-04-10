package iriedit

import iri "../iriengine"
import im "odinary:dear_imguy"


draw_window_settings :: proc() {

	window_enabled : bool = .Settings in editor.enabled_windows

	if !window_enabled {
		return;
	}

	defer {
		im.End();

		if !window_enabled {
			disable_window(.Settings);
		}
	}

	if im.Begin("Settings", &window_enabled) {

		if im.TreeNode("Info") {
			draw_base_info();	
			im.TreePop();
		}

		if im.TreeNode("Performance Counters") {

			draw_performance_counters();
			
			im.TreePop();
		}

		if im.TreeNode("Render Settings") {

			draw_render_settings();

			im.TreePop();
		}

		if im.TreeNode("Assets View") {
			
			draw_assets_view();

			im.TreePop();
		}
	}
}