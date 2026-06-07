package iri

import sdl "vendor:sdl3"



input_mouse_button_to_sdl_mouse_button_flag :: proc(mouse_button : MouseButton) -> sdl.MouseButtonFlag {
	
	// SDL MouseButtonFlag Definition is this:
	// MouseButtonFlag :: enum Uint32 {
	// 	LEFT   = 1 - 1,
	// 	MIDDLE = 2 - 1,
	// 	RIGHT  = 3 - 1,
	// 	X1     = 4 - 1,
	// 	X2     = 5 - 1,
	// }

	return cast(sdl.MouseButtonFlag)cast(u32)mouse_button;
}