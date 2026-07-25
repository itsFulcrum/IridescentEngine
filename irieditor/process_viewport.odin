package iriedit

import "core:log"

import iri "../iriengine"

import im "odinary:dear_imguy"

process_viewport :: proc() {
	

	curr_universe := iri.get_active_universe();
	if  curr_universe == nil{
		return;
	}

	is_viewport_hovered : bool = !iri.debug_gui_want_capture_input();

	if !is_viewport_hovered{
		return;
	}

	if iri.input_mouse_button(.LEFT, {.WasPressed}).triggered {

		mouse_pos := iri.input_relative_mouse_position();
		//log.debugf("MousePresssed. mouse_pos {}", mouse_pos);

		did_hit, hit_info := iri.raycast_universe_from_camera(curr_universe, mouse_pos);

		if did_hit {
			select_entity(curr_universe, hit_info.entity)
			editor.selected_drawable_index = cast(i32)hit_info.drawable_index;
		}
	}

}
