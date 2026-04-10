package iriedit

import "core:c"

import iri "../iriengine"
import im "odinary:dear_imguy"


draw_window_project_browser :: proc() {

	window_enabled : bool = .ProjectBrowser in editor.enabled_windows

	if !window_enabled {
		return;
	}

	defer {
		im.End();

		if !window_enabled {
			disable_window(.ProjectBrowser);
		}
	}

	flags := im.WindowFlags{.MenuBar}
	window_draw: if im.Begin("Project Browser", &window_enabled, flags) {

		draw_project_browser();
	}
}