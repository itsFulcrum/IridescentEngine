package iri

import "core:log"
import "core:c"
import "core:mem"
import "core:math"
import "core:container/bit_array"
import sdl "vendor:sdl3"

import "core:math/rand"

// TODO:
// - make process user inputs into two seperate things (process mouse inputs, process keyboard inputs) we can get this seperatly from DearImgui



InputSystem :: struct {

	process_user_inputs: bool,
	
	sdl_events_callbacks: [dynamic]SDLEvent_CallbackEntry,

	// -- KEYBOARD --
	keyboard_state_now  : bit_array.Bit_Array, // 512 bits, 64 bytes.
	keyboard_state_last : bit_array.Bit_Array, // 512 bits, 64 bytes.
	keymods : KeymodFlags, // currently pressed keymods
	keyboard_callbacks  : 	[dynamic]Keyboard_CallbackEntry,

	// -- MOUSE --
	cursor_state : MouseCursorState,
	relative_mouse_pos_last : [2]f32, // relative to the focused window.
	relative_mouse_pos : [2]f32, 	  // relative to the focused window.
	global_mouse_pos : [2]f32, 		  // global to the entire screen
	
	mouse_delta : [2]f32,
	mouse_delta_last : [2]f32,

	mouse_wheel_now  : [2]f32,
	mouse_wheel_last : [2]f32,

	mouse_btn_state_flags_last  : sdl.MouseButtonFlags,
	mouse_btn_state_flags 		: sdl.MouseButtonFlags,
	mouse_btn_curr_press_events : [MouseButton]PressEventFlags,

	mouse_button_callbacks: [dynamic]MouseButton_CallbackEntry,
	mouse_wheel_callbacks: 	[dynamic]MouseWheel_CallbackEntry,
	mouse_motion_callbacks: [dynamic]MouseMotion_CallbackEntry,

	// -- GAMEPAD
	gp_added_callback: 		GamepadDeviceEvent_CallbackSignature,
	gp_removed_callback: 	GamepadDeviceEvent_CallbackSignature,
	gp_remapped_callback: 	GamepadDeviceEvent_CallbackSignature,

	gp_button_callbacks: [dynamic]GamepadButton_CallbackEntry,
	gp_analog_callbacks: [dynamic]GamepadAnalog_CallbackEntry,

	gp_connected : [MAX_GAMEPADS]bool,
	gp_ids       : [MAX_GAMEPADS]sdl.JoystickID,
	gp_states    : [MAX_GAMEPADS]GamepadState,
}



@(private="package")
input_system_init :: proc(input_sys : ^InputSystem) {

	input_sys.process_user_inputs = true;
	
	keyboard_state : [^]bool = sdl.GetKeyboardState(nil);

	// Initialize Keyboard State.
	bit_array.init(&input_sys.keyboard_state_now,512, 0, context.allocator);
	bit_array.init(&input_sys.keyboard_state_last,512, 0, context.allocator);

	for scancode in sdl.Scancode {		
		if keyboard_state[cast(u32)scancode] {
			bit_array.set(&input_sys.keyboard_state_now , cast(uint)scancode, false);
			bit_array.set(&input_sys.keyboard_state_last, cast(uint)scancode, false);
		}
	}

	// TODO: should check in with sdl before just assuming the mouse state.
	input_sys.cursor_state = MouseCursorState.Normal;

}

@(private="package")
input_system_deinit :: proc(input_sys : ^InputSystem){

	bit_array.destroy(&input_sys.keyboard_state_now);
	bit_array.destroy(&input_sys.keyboard_state_last);

	delete(input_sys.sdl_events_callbacks);
	delete(input_sys.mouse_button_callbacks);
	delete(input_sys.mouse_wheel_callbacks);
	delete(input_sys.mouse_motion_callbacks);
	delete(input_sys.keyboard_callbacks);
	delete(input_sys.gp_analog_callbacks);
	delete(input_sys.gp_button_callbacks);
}

@(private="package")
input_system_update :: proc(input_sys : ^InputSystem, window : ^WindowContext){

	IRI_PROFILE_PROCEDURE()
	
	event : sdl.Event;

	input_sys.mouse_wheel_last = input_sys.mouse_wheel_now;
	input_sys.mouse_wheel_now  = [2]f32{0.0, 0.0}; // reset 
	input_sys.mouse_delta_last = input_sys.mouse_delta;
	input_sys.relative_mouse_pos_last = input_sys.relative_mouse_pos;

	if input_sys.cursor_state == .HiddenAndLocked {
		size : [2]i32 = window_context_get_size_pixels(window);
		center := [2]f32{cast(f32)size.x,cast(f32)size.y} / 2.0;
		sdl.WarpMouseInWindow(window.handle, center.x, center.y);
	}

	for i in 0..<len(input_sys.keyboard_state_now.bits){
		input_sys.keyboard_state_last.bits[i] = input_sys.keyboard_state_now.bits[i];
	}

	for i in 0..<MAX_GAMEPADS {
		if !input_sys.gp_connected[i] do continue;
		gp := &input_sys.gp_states[i];

		gp.trigger_R_last = gp.trigger_R;
		gp.trigger_L_last = gp.trigger_L;

		gp.stick_L_last = gp.stick_L; 
		gp.stick_R_last = gp.stick_R; 
		gp.pressed_btns_last = gp.pressed_btns_now;
	}

	for sdl.PollEvent(&event) {

		input_system_broadcast_sdl_event_callbacks(input_sys, &event);

		
		#partial switch event.type {

			case sdl.EventType.QUIT:			

			// Keyboard
			case sdl.EventType.KEY_DOWN: {

				key_code : Key = cast(Key)event.key.key; // we can do this cast bc the enum values match SDL keycodes

				// update keyboard state 
				scancode : sdl.Scancode = sdl.GetScancodeFromKey(cast(sdl.Keycode)key_code, nil);			
				bit_array.set(&input_sys.keyboard_state_now , cast(uint)scancode, true);

				is_repeat := event.key.repeat;
				mods: KeymodFlags = transmute(KeymodFlags)event.key.mod;
				input_system_broadcast_keyboard_callbacks(input_sys, key_code, is_repeat ? .IsPressed : .WasPressed, true, is_repeat, mods);	
			}			
			case sdl.EventType.KEY_UP:{

				key_code : Key = cast(Key)event.key.key; // we can do this cast bc the enum values match SDL keycodes
				
				scancode : sdl.Scancode = sdl.GetScancodeFromKey(cast(sdl.Keycode)key_code, nil);
				bit_array.set(&input_sys.keyboard_state_now , cast(uint)scancode, false);
				
				// note the empty keymods here bc release atm always goes through regardless of keymods
				input_system_broadcast_keyboard_callbacks(input_sys, key_code, .WasReleased, false, false, {}); 
			}
			// Mouse Motion
			case sdl.EventType.MOUSE_MOTION: 
				
				new_rel_pos : [2]f32 = [2]f32{event.motion.x, event.motion.y};

				if input_sys.cursor_state == .HiddenAndLocked {
					//log.debugf("MOUSE: motion: {}, rel: {}", [2]f32{event.motion.x, event.motion.y}, [2]f32{event.motion.xrel, event.motion.yrel});
					
					//input_sys.mouse_delta = new_rel_pos - input_sys.relative_mouse_pos;
					input_sys.relative_mouse_pos = new_rel_pos
				}

				input_system_broadcast_mouse_motion_callbacks(input_sys, new_rel_pos, [2]f32{event.motion.xrel, event.motion.yrel});

			// Mouse Buttons
			case sdl.EventType.MOUSE_BUTTON_DOWN:				
				if event.button.button == 0 || event.button.button > 5 do continue;			
				input_system_broadcast_mouse_button_callbacks(input_sys, cast(MouseButton)event.button.button, PressEvent.WasPressed, is_double_click = event.button.clicks == 2, mouse_pos = [2]f32{event.button.x, event.button.y});
			
			case sdl.EventType.MOUSE_BUTTON_UP:
				if event.button.button == 0 || event.button.button > 5 do continue;
				input_system_broadcast_mouse_button_callbacks(input_sys, cast(MouseButton)event.button.button, PressEvent.WasReleased, is_double_click = false, mouse_pos = [2]f32{event.button.x, event.button.y});

			// Mouse Wheel
			case sdl.EventType.MOUSE_WHEEL: {
				mouse_pos := [2]f32{event.wheel.mouse_x, event.wheel.mouse_y};
				input_sys.mouse_wheel_now  =[2]f32{event.wheel.x, event.wheel.y};
				input_system_broadcast_mouse_wheel_callbacks(input_sys, mouse_pos, input_sys.mouse_wheel_now, event.wheel.direction == sdl.MouseWheelDirection.FLIPPED);
			}

			// GAMEPAD
			case sdl.EventType.GAMEPAD_ADDED:	input_system_handle_gamepad_added(input_sys  , event.gdevice.which); // also calls user callback
			case sdl.EventType.GAMEPAD_REMOVED: input_system_handle_gamepad_removed(input_sys, event.gdevice.which); // also calls user callback
			case sdl.EventType.GAMEPAD_REMAPPED:
				if input_sys.gp_remapped_callback != nil {
					arr_idx, _ := input_system_get_gamepad_state_for_device_id(input_sys, event.gaxis.which);
					if arr_idx >= 0 && arr_idx < 4 {
						gamepad : GamepadDevice = cast(GamepadDevice)arr_idx;
						input_sys.gp_remapped_callback(gamepad);
					}
				}
			
			case sdl.EventType.GAMEPAD_BUTTON_DOWN:	
				input_system_broadcast_gamepad_button_callbacks(input_sys, event.gbutton.which, cast(GamepadButton)event.gbutton.button, PressEvent.WasPressed, event.gbutton.down)
			case sdl.EventType.GAMEPAD_BUTTON_UP:   
				input_system_broadcast_gamepad_button_callbacks(input_sys, event.gbutton.which, cast(GamepadButton)event.gbutton.button, PressEvent.WasReleased, event.gbutton.down)
				
			case sdl.EventType.GAMEPAD_AXIS_MOTION:
				// @Note actuall min is -32768 but its awkward to deal with wrapping behavior so we clamp it.
				_MAX ::  32767
				_MIN :: -32767

				axis_type := cast(sdl.GamepadAxis)event.gaxis.axis
				val: i16 = clamp(event.gaxis.value, _MIN, _MAX);
				arr_idx, gp := input_system_get_gamepad_state_for_device_id(input_sys, event.gaxis.which);
				//log.debugf("val: {} ",val)
				if gp != nil {
					switch axis_type {
						case .INVALID:
						case .RIGHT_TRIGGER:
							gp.trigger_R =  val;
							gp.event_happend_set += {.RIGHT_TRIGGER};
						case .LEFT_TRIGGER:
							gp.trigger_L = val;
							gp.event_happend_set += {.LEFT_TRIGGER};
						case .LEFTX:
							gp.stick_L.x = val;
							gp.event_happend_set += {.LEFT_STICK};				
						case .LEFTY:
							gp.stick_L.y = val;
							gp.event_happend_set += {.LEFT_STICK};
						case .RIGHTX:
							gp.stick_R.x = val;
							gp.event_happend_set += {.RIGHT_STICK};
						case .RIGHTY:
							gp.stick_R.y = val;
							gp.event_happend_set += {.RIGHT_STICK};
					}
				}

			case:
		} // switch end
	} // poll events end


	// Update Mouse Stuff
	{

		global_mouse_state := sdl.GetGlobalMouseState(&input_sys.global_mouse_pos.x, &input_sys.global_mouse_pos.y);
		
		new_relative_mouse_pos : [2]f32;
		input_sys.mouse_btn_state_flags_last = input_sys.mouse_btn_state_flags;
		input_sys.mouse_btn_state_flags = sdl.GetMouseState(&new_relative_mouse_pos.x, &new_relative_mouse_pos.y);
		
		if input_sys.cursor_state != .HiddenAndLocked {
			// if locked we update relative_mouse_pos in mouse_motion event.
			input_sys.relative_mouse_pos = new_relative_mouse_pos;
		}
		
		input_sys.mouse_delta = input_sys.relative_mouse_pos - input_sys.relative_mouse_pos_last;


		// We just maintain current press events for each mouse button.
		for mouse_button in MouseButton {
			
			press_events : PressEventFlags;

			sdl_mouse_btn := #force_inline mouse_button_to_sdl_mouse_button_flag(mouse_button);
			is_down_now   : bool = sdl_mouse_btn in input_sys.mouse_btn_state_flags;
			was_down_last : bool = sdl_mouse_btn in input_sys.mouse_btn_state_flags_last;

			press_events += is_down_now ? {.IsPressed} : {.IsReleased};
			
			if is_down_now && !was_down_last {
				press_events += {.WasPressed};
			} else if !is_down_now && was_down_last {
				press_events += {.WasReleased};
			}

			input_sys.mouse_btn_curr_press_events[mouse_button] = press_events;
		}
	}
	
	// get current keymods
	input_sys.keymods = transmute(KeymodFlags)sdl.GetModState();


	// Continuous press registers for mouse and keyboard are handled seperatly each frame.
	input_system_broadcast_keyboard_callbacks_continuous_presses(input_sys);
	input_system_broadcast_mouse_button_callbacks_continuous_presses(input_sys, input_sys.relative_mouse_pos);


	true_delta_time := clock_get_true_delta_time();
	input_system_evaluate_gamepad_states_and_broadcast_analog_callbacks(input_sys,true_delta_time);


	input_system_broadcast_gamepad_button_callbacks_continuous_presses(input_sys);
}



@(private="package")
input_system_enable_user_inputs :: proc(input_sys : ^InputSystem){
	if input_sys.process_user_inputs {
		return;
	}

	input_sys.process_user_inputs = true;

	// TODO ?
}

@(private="package")
input_system_disable_user_inputs :: proc(input_sys : ^InputSystem){
	if !input_sys.process_user_inputs {
		return;
	}

	input_sys.process_user_inputs = false;

	// TODO ?
}

// ============================================================================================================================
// SDL Event Callbacks

@(private="package")
input_system_register_sdl_event_callback :: proc(input_sys : ^InputSystem, callback_proc: SDLEvent_CallbackSignature) -> InputID {
	
	if callback_proc == nil {
		return InputID_INVALID;
	}

	free_array_index : i32 = -1;
	for i in 0..<len(input_sys.sdl_events_callbacks) {

		if input_sys.sdl_events_callbacks[i].id == InputID_INVALID {
			// We found an unused spot
			free_array_index = cast(i32)i;
			break;
		}
	}
	
	entry : SDLEvent_CallbackEntry = {
		id = {-1, rand.int31()},
		callback = callback_proc,
	}

	if free_array_index == -1 {
		entry.id.x = cast(i32)len(input_sys.sdl_events_callbacks);
		append(&input_sys.sdl_events_callbacks, entry);
	} else {
		entry.id.x = free_array_index;
		input_sys.sdl_events_callbacks[free_array_index] = entry;
	}

	return entry.id;
}

@(private="package")
input_system_unregister_sdl_event_callback :: proc(input_sys : ^InputSystem, input_id : ^InputID) -> (ok : bool) {

	id : InputID = input_id^;

	if id.x < 0 || id.x >= cast(i32)len(input_sys.sdl_events_callbacks){
		return false; // invalid id
	}

	entry := &input_sys.sdl_events_callbacks[id.x];

	if entry.id.y != id.y {
		return false; // invalid id
	}

	entry.id = InputID_INVALID;
	entry.callback = nil;
	input_id^ = InputID_INVALID; // invalidate the user id

	return true;
}

@(private="file")
input_system_broadcast_sdl_event_callbacks :: proc(input_sys : ^InputSystem, sdl_event: ^sdl.Event) {

	// For sdl event we ingore if process_user_inputs is false

	for i in 0..<len(input_sys.sdl_events_callbacks) {

		if input_sys.sdl_events_callbacks[i].id.x >= 0 && input_sys.sdl_events_callbacks[i].callback != nil {
			input_sys.sdl_events_callbacks[i].callback(sdl_event);
		}
	}
}


// ============================================================================================================================
// MOUSE BUTTON

@(private="package")
input_system_register_mouse_button_callback :: proc(input_sys : ^InputSystem, callback_proc: MouseButton_CallbackSignature, mouse_button : MouseButton, press_event_flags: PressEventFlags = {.IsPressed}) -> InputID {

	if callback_proc == nil {
		return InputID_INVALID;
	}

	free_array_index : i32 = -1;
	for i in 0..<len(input_sys.mouse_button_callbacks){

		if input_sys.mouse_button_callbacks[i].id == InputID_INVALID {
			// We found an unused spot
			free_array_index = cast(i32)i;
			break;
		}
	}
	
	entry : MouseButton_CallbackEntry = {
		id 			 = {-1, rand.int31()},
		callback     = callback_proc,
		mouse_button = mouse_button,
		press_flags  = press_event_flags,
	}

	if free_array_index == -1 {
		entry.id.x = cast(i32)len(input_sys.mouse_button_callbacks);
		append(&input_sys.mouse_button_callbacks, entry);
	} else {
		entry.id.x = free_array_index;
		input_sys.mouse_button_callbacks[free_array_index] = entry;
	}

	return entry.id;
}

@(private="package")
input_system_unregister_mouse_button_callback :: proc(input_sys : ^InputSystem, input_id : ^InputID) -> (ok : bool) {

	id : InputID = input_id^;

	if id.x < 0 || id.x >= cast(i32)len(input_sys.mouse_button_callbacks){
		return false; // invalid id
	}

	entry := &input_sys.mouse_button_callbacks[id.x];

	if entry.id.y != id.y {
		return false; // invalid id
	}

	entry.id = InputID_INVALID;
	entry.callback = nil;
	input_id^ = InputID_INVALID; // invalidate the user id

	return true;
}

@(private="file")
input_system_broadcast_mouse_button_callbacks :: proc(input_sys : ^InputSystem, mouse_button: MouseButton, press_event: PressEvent, is_double_click : bool, mouse_pos : [2]f32) {
	
	// @Note: the only reason we maintain this atm is because it offers to know if it was a double click.

	if !input_sys.process_user_inputs {
			return;
	}

	for &entry in input_sys.mouse_button_callbacks {

		if entry.id.x < 0 || entry.callback == nil {
			continue;
		}
		
		if mouse_button != entry.mouse_button || press_event not_in entry.press_flags {
			continue;
		}

		is_down : bool = press_event == PressEvent.WasPressed;
		entry.callback(mouse_pos, is_down, is_double_click);
	}
}


@(private="file")
input_system_broadcast_mouse_button_callbacks_continuous_presses :: proc(input_sys : ^InputSystem, mouse_pos : [2]f32){

	if !input_sys.process_user_inputs {
		return;
	}

	for &entry in input_sys.mouse_button_callbacks {
		// Check if entry is used
		if entry.id.x < 0 || entry.callback == nil {
			continue;
		}

		// only care about entries with continuous presses
		if PressEvent.IsPressed in entry.press_flags || PressEvent.IsReleased in entry.press_flags {

			sdl_mouse_btn := #force_inline mouse_button_to_sdl_mouse_button_flag(entry.mouse_button);
			is_down : bool = sdl_mouse_btn in input_sys.mouse_btn_state_flags;
			if PressEvent.IsPressed in entry.press_flags && is_down {
				entry.callback(mouse_pos, is_down, is_double_click = false);
			}
			if PressEvent.IsReleased in entry.press_flags && !is_down {
				entry.callback(mouse_pos, is_down, is_double_click = false);
			}
		}
	}
}

// ============================================================================================================================
// MOUSE WHEEL
@(private="package")
input_system_register_mouse_wheel_callback :: proc(input_sys : ^InputSystem, callback_proc: MouseWheel_CallbackSignature) -> InputID {

	if callback_proc == nil {
		return InputID_INVALID;
	}

	free_array_index : i32 = -1;
	for i in 0..<len(input_sys.mouse_wheel_callbacks){

		if input_sys.mouse_wheel_callbacks[i].id == InputID_INVALID {
			// We found an unused spot
			free_array_index = cast(i32)i;
			break;
		}
	}
	
	entry : MouseWheel_CallbackEntry = {
		id 			 = {-1, rand.int31()},
		callback     = callback_proc,
	}

	if free_array_index == -1 {
		entry.id.x = cast(i32)len(input_sys.mouse_wheel_callbacks);
		append(&input_sys.mouse_wheel_callbacks, entry);
	} else {
		entry.id.x = free_array_index;
		input_sys.mouse_wheel_callbacks[free_array_index] = entry;
	}

	return entry.id;
}

@(private="package")
input_system_unregister_mouse_wheel_callback :: proc(input_sys : ^InputSystem, input_id : ^InputID) -> (ok : bool) {

	id : InputID = input_id^;

	if id.x < 0 || id.x >= cast(i32)len(input_sys.mouse_wheel_callbacks){
		return false; // invalid id
	}

	entry := &input_sys.mouse_wheel_callbacks[id.x];

	if entry.id.y != id.y {
		return false; // invalid id
	}

	entry.id = InputID_INVALID;
	entry.callback = nil;
	input_id^ = InputID_INVALID; // invalidate the user id

	return true;
}

@(private="file")
input_system_broadcast_mouse_wheel_callbacks :: proc(input_sys : ^InputSystem, mouse_pos : [2]f32, mouse_scroll : [2]f32, is_flipped_direction : bool){

	if !input_sys.process_user_inputs {
		return;
	}

	for &entry in input_sys.mouse_wheel_callbacks {
		// Check if entry is used
		if entry.id.x >= 0 && entry.callback != nil {
			entry.callback(mouse_pos, mouse_scroll, is_flipped_direction);
		}
	}
}


// ============================================================================================================================
// MOUSE MOTION

@(private="package")
input_system_register_mouse_motion_callback :: proc(input_sys : ^InputSystem, callback_proc: MouseMotion_CallbackSignature) -> InputID {

	if callback_proc == nil {
		return InputID_INVALID;
	}

	free_array_index : i32 = -1;
	for i in 0..<len(input_sys.mouse_motion_callbacks){

		if input_sys.mouse_motion_callbacks[i].id == InputID_INVALID {
			// We found an unused spot
			free_array_index = cast(i32)i;
			break;
		}
	}
	
	entry : MouseMotion_CallbackEntry = {
		id 			 = {-1, rand.int31()},
		callback     = callback_proc,
	}

	if free_array_index == -1 {
		entry.id.x = cast(i32)len(input_sys.mouse_motion_callbacks);
		append(&input_sys.mouse_motion_callbacks, entry);
	} else {
		entry.id.x = free_array_index;
		input_sys.mouse_motion_callbacks[free_array_index] = entry;
	}

	return entry.id;
}

@(private="package")
input_system_unregister_mouse_motion_callback :: proc(input_sys : ^InputSystem, input_id : ^InputID) -> (ok : bool) {

	id : InputID = input_id^;

	if id.x < 0 || id.x >= cast(i32)len(input_sys.mouse_motion_callbacks){
		return false; // invalid id
	}

	entry := &input_sys.mouse_motion_callbacks[id.x];

	if entry.id.y != id.y {
		return false; // invalid id
	}

	entry.id = InputID_INVALID;
	entry.callback = nil;
	input_id^ = InputID_INVALID; // invalidate the user id

	return true;
}

@(private="file")
input_system_broadcast_mouse_motion_callbacks :: proc(input_sys : ^InputSystem, mouse_pos : [2]f32, mouse_delta : [2]f32){

	if !input_sys.process_user_inputs {
		return;
	}

	for &entry in input_sys.mouse_motion_callbacks {

		// Check if entry is used
		if entry.id.x >= 0 && entry.callback != nil {
			entry.callback(mouse_pos, mouse_delta);
		}
	}
}

// ============================================================================================================================
// KEYBOARD

@(private="package")
input_system_register_keyboard_callback :: proc(input_sys : ^InputSystem, callback_proc: Keyboard_CallbackSignature, key_code: Key, press_event_flags : PressEventFlags, key_mods_flags: KeymodFlags = {}) -> InputID {


	if callback_proc == nil {
		return InputID_INVALID;
	}

	free_array_index : i32 = -1;
	for i in 0..<len(input_sys.keyboard_callbacks){

		if input_sys.keyboard_callbacks[i].id == InputID_INVALID {
			// We found an unused spot
			free_array_index = cast(i32)i;
			break;
		}
	}	

	entry : Keyboard_CallbackEntry = {
		id 			= {-1, rand.int31()},
		callback 	= callback_proc,
		key_code 	= key_code,
		press_flags = press_event_flags,
		key_mods 	= key_mods_flags,
	}

	if free_array_index == -1 {
		entry.id.x = cast(i32)len(input_sys.keyboard_callbacks);
		append(&input_sys.keyboard_callbacks, entry);
	} else {
		entry.id.x = free_array_index;
		input_sys.keyboard_callbacks[free_array_index] = entry;
	}

	return entry.id;
}

@(private="package")
input_system_unregister_keyboard_callback :: proc(input_sys : ^InputSystem, input_id : ^InputID) -> (ok : bool) {

	id : InputID = input_id^;

	if id.x < 0 || id.x >= cast(i32)len(input_sys.keyboard_callbacks){
		return false; // invalid id
	}

	entry := &input_sys.keyboard_callbacks[id.x];

	if entry.id.y != id.y {
		return false; // invalid id
	}

	entry.id = InputID_INVALID;
	entry.callback = nil;
	input_id^ = InputID_INVALID; // invalidate the user id

	return true;
}

@(private="file")
input_system_broadcast_keyboard_callbacks :: proc(input_sys : ^InputSystem, key_code : Key, press_event : PressEvent, is_pressed: bool, is_repeat : bool, key_mods: KeymodFlags){


	if !input_sys.process_user_inputs {
		return;
	}


	for &entry in input_sys.keyboard_callbacks {

		// Check if entry is used
		if entry.id.x < 0 || entry.callback == nil {
			continue;
		}

		if entry.key_code != key_code || press_event not_in entry.press_flags {
			continue;
		}

		if entry.key_mods <= key_mods { // A <= B - subset relation (A is a subset of B or equal to B)
			entry.callback(is_pressed, is_repeat);
		}
	}
}

// TODO: keymods
// Here we process only registered entry with the KeyAction.PRESS_CONTINUOUS
@(private="file")
input_system_broadcast_keyboard_callbacks_continuous_presses :: proc(input_sys: ^InputSystem) {
	
	if !input_sys.process_user_inputs {
		return;
	}

	for &entry in input_sys.keyboard_callbacks {

		// Check if entry is used
		if entry.id.x < 0 || entry.callback == nil {
			continue;
		}

		if .IsPressed in entry.press_flags || .IsReleased in entry.press_flags {

			keymods_pressed : bool = entry.key_mods <= input_sys.keymods; // subset relation.
			if !keymods_pressed {
				continue;
			}

			scancode : sdl.Scancode = sdl.GetScancodeFromKey(cast(sdl.Keycode)entry.key_code, nil);
			is_down, ok := bit_array.get(&input_sys.keyboard_state_now, cast(uint)scancode);


			if .IsPressed in entry.press_flags && is_down {
				entry.callback(is_down, is_repeat = false);
			}

			if .IsReleased in entry.press_flags && !is_down {
				entry.callback(is_down, is_repeat = false);
			}
		}		
	}
}

// ============================================================================================================================
// GAMEPAD

// GAMEPAD ANALOG
@(private="file")
input_system_handle_gamepad_added :: proc(input_sys : ^InputSystem, joystick_id : sdl.JoystickID) {

	//log.debugf("gamepad added");

	//device_id: u32 = cast(u32)joystick_id;
	
	// Find a free spot to allocate a new GamepadState structure to track
	// Note that we only support up to 4 atm.
	array_index: i32 = -1;

	for i in 0..<4 {
		
		if input_sys.gp_connected[i] == false {

			array_index = cast(i32)i;
			break;
		}
	}

	if array_index == -1 {
		// 4 gamepads are already connected.
		log.warnf("InputSystem: Registered more than 4 gampad devices connected - the Engine only supports up to 4 gamepads.");
		return;
	}

	gamepad : GamepadDevice = cast(GamepadDevice)array_index;
	engine_assert(gamepad != GamepadDevice.Any);
	
	input_sys.gp_connected[array_index] = true;
	input_sys.gp_ids[array_index] = joystick_id;
	input_sys.gp_states[array_index] = GamepadState{};

	// call user proc
	if input_sys.gp_added_callback != nil {
		input_sys.gp_added_callback(gamepad);
	}
}

@(private="file")
input_system_handle_gamepad_removed :: proc(input_sys : ^InputSystem, joystick_id : sdl.JoystickID){

	//device_id: u32 = cast(u32)joystick_id;

	array_index: i32 = -1;
	for i in 0..<4 {
		
		if input_sys.gp_ids[i] == joystick_id {
			array_index = cast(i32)i;
			break;
		}
	}

	if array_index == -1 {
		log.warnf("InputSystem: Noticed Gamepad removed that was not registered. Were more than 4 gamepads connected ?");
		return;
	} 

	gamepad : GamepadDevice = cast(GamepadDevice)array_index;
	engine_assert(gamepad != GamepadDevice.Any);

	input_sys.gp_ids[array_index] = 0;
	input_sys.gp_connected[array_index] = false;
	input_sys.gp_states = GamepadState{};

	// call user proc
	if input_sys.gp_removed_callback != nil {
		input_sys.gp_removed_callback(gamepad);
	}
}

// Returns nil if the joystick_id is not registered.
@(private="file")
input_system_get_gamepad_state_for_device_id :: proc(input_sys : ^InputSystem, joystick_id : sdl.JoystickID) -> (array_index : int ,state : ^GamepadState) {

	for i in 0..<4{
		if input_sys.gp_ids[i] == joystick_id {
			return i, &input_sys.gp_states[i];
		}
	}

	return -1, nil;
}

@(private="file")
input_system_evaluate_gamepad_states_and_broadcast_analog_callbacks :: proc(input_sys : ^InputSystem, true_delta_seconds: f64){

	// @Note - Fuclrum
	// Constants for normalizing analog/axis gamepad inputs.
	// Analog gamepad inputs are received by SDL in the Range -32768..32767 as an int16
	_MAX ::  32767.0
	_MIN :: -32767.0
	_RANGE :: _MAX - _MIN
	_INV_RANGE2 :: 1.0 / _RANGE * 2.0
	_INV_MAX :: 1.0 / _MAX


	// @Note - Fulcrum
	// We receive gampad axis/analog events only if there was a change.
	// However we want to send out callbacks every frame if the axis is not in idle (currently being pushed).
	// It can be tricky though to determine when its not being pressed anymore because the last events we receive,
	// may likely not be perfect zero values, especially for the gamepad sticks.
	// To mitigate this we perform a gernal idle threshold (_IDLE_THRESHOLD) check for each event.
	// Under this value we just dont consider it any input.
	// For Triggers a rather small value seems to be sufficiant. For me, they mostly even report a zero as the last event.
	// For gamepad sticks we aditionally reevalute if its Idle when no events happend for some time.
	// This is because stick axis inputs can be much less precise and it might happen that the last event we receive 
	// is still with a fairly large value (I observed as much as 2000 - 3000).
	// As I don't gernerally want to ignore stick inputs below such a large value and it's not even clear how large they may
	// be with for example not perfecly functioning sensors. I resort to using a time based fallback system.
	// So if no events are happening for extended time we check if its below a fairly large value,
	// and only then consider it idle and reset it to 0.
	

	_IDLE_THRESHOLD :: 327 // normalized about 0.01
	_IDLE_THRESHOLD_STICK :: 3500 // normalized about 0.1

	_STICK_EVALUTATE_RESET_TIME :: 0.75 // in seconds

	for i in 0..<4 {
		
		if input_sys.gp_connected[i] == false {
			continue;
		}
		
		gamepad : GamepadDevice = cast(GamepadDevice)i;

		gp := &input_sys.gp_states[i];


		// For each event that happend do a general Idle Threshold check
		for changed_analog_type in gp.event_happend_set {
			switch changed_analog_type {
				
				case .RIGHT_TRIGGER:					
					if gp.trigger_R < _IDLE_THRESHOLD {
						gp.trigger_R = 0;
						gp.trigger_R_normalized_01 = 0.0;
					}

				case .LEFT_TRIGGER:
					if gp.trigger_L < _IDLE_THRESHOLD {
						gp.trigger_L = 0;
						gp.trigger_L_normalized_01 = 0.0;
					}
				
				case .RIGHT_STICK:	

					gp.stick_R_sec_since_event = 0.0
					
					if abs(gp.stick_R.x) < _IDLE_THRESHOLD {
						gp.stick_R.x = 0;
						gp.stick_R_normalized.x = 0.0;
					}
					if abs(gp.stick_R.y) < _IDLE_THRESHOLD {
						gp.stick_R.y = 0;
						gp.stick_R_normalized.y = 0.0;
					}

				case .LEFT_STICK:
					gp.stick_L_sec_since_event = 0.0
					if abs(gp.stick_L.x) < _IDLE_THRESHOLD && abs(gp.stick_L.y) < _IDLE_THRESHOLD {
						gp.stick_L.x = 0;
						gp.stick_L_normalized.x = 0.0;
					}
					if abs(gp.stick_L.y) < _IDLE_THRESHOLD {
						gp.stick_L.y = 0;
						gp.stick_L_normalized.y = 0.0;
					}
			}
		}

		gp.event_happend_set = {}; // reset events happend 


		type: for analog_type in GamepadAnalog {

			value: [2]f32;
			delta: [2]f32;
	
			switch analog_type {
				
				case .RIGHT_TRIGGER:

					if gp.trigger_R == 0 && gp.trigger_R_last == 0 {
						continue type;
					}

					delta_i: i16 = gp.trigger_R - gp.trigger_R_last;
					//gp.trigger_R_last = gp.trigger_R;
					// Trigger input is given by SDL in range 0..32767
					// map to range 0..1
					delta.x = _INV_MAX * f32(delta_i);
					value.x = _INV_MAX * f32(gp.trigger_R);
					gp.trigger_R_normalized_01 = clamp(value.x, 0.0, 1.0);

				case .LEFT_TRIGGER:
					
					if gp.trigger_L == 0 && gp.trigger_L_last == 0 {
						continue type;
					}

					delta_i : i16 = gp.trigger_L - gp.trigger_L_last;
					// Trigger input is given by SDL in range 0..32767
					// map to range 0..1
					delta.x = _INV_MAX * f32(delta_i);
					value.x = _INV_MAX * f32(gp.trigger_L);
					gp.trigger_L_normalized_01 = clamp(value.x, 0.0, 1.0);

				case .RIGHT_STICK: {				

					if gp.stick_R == {0,0} && gp.stick_R_last == {0,0} {
						continue type;
					}

					delta_i : [2]i16 = gp.stick_R - gp.stick_R_last;
					//gp.stick_R_last  = gp.stick_R;
					// Stick input is given by SDL in range -32768..32767
					// map to range -1..1
					delta = ([2]f32{f32(delta_i.x), f32(delta_i.y)} - _MIN) * _INV_RANGE2 -1.0;
					value = ([2]f32{f32(gp.stick_R.x), f32(gp.stick_R.y)} - _MIN) * _INV_RANGE2 -1.0;
					
					// If no events happend for some time, evaluate if stick is in Idle to reset it.
					// We do this before filling out 'value' and 'delta' so callbacks always receive 0 as last value
					gp.stick_R_sec_since_event += cast(f32)true_delta_seconds;
					if gp.stick_R_sec_since_event >= _STICK_EVALUTATE_RESET_TIME {

						if abs(gp.stick_R.x) < _IDLE_THRESHOLD_STICK {
							gp.stick_R.x = 0;
							delta.x = 0.0;
							value.x = 0.0;
						}

						if abs(gp.stick_R.y) < _IDLE_THRESHOLD_STICK {
							gp.stick_R.y = 0;
							delta.y = 0.0;
							value.y = 0.0;
						}

						gp.stick_R_sec_since_event = 0.0;
					}

					gp.stick_R_normalized = value;

				}
				case .LEFT_STICK:{


					if gp.stick_L == {0,0} && gp.stick_L_last == {0,0} {
						continue type;
					}

					delta_i : [2]i16 = gp.stick_L - gp.stick_L_last;
					//gp.stick_L_last  = gp.stick_L;

					// Stick input is given by SDL in range -32768..32767
					// map to range -1..1
					delta = ([2]f32{f32(delta_i.x), f32(delta_i.y)} - _MIN) * _INV_RANGE2 - 1.0; 
					value = ([2]f32{f32(gp.stick_L.x), f32(gp.stick_L.y)} - _MIN) * _INV_RANGE2 - 1.0;
					
					// If no events happend for some time, evaluate if stick is in Idle to reset it.
					// We do this before filling out 'value' and 'delta' so callbacks always receive 0 as last value
					gp.stick_L_sec_since_event += cast(f32)true_delta_seconds;
					if gp.stick_L_sec_since_event >= _STICK_EVALUTATE_RESET_TIME {

						if abs(gp.stick_L.x) < _IDLE_THRESHOLD_STICK && abs(gp.stick_L.y) < _IDLE_THRESHOLD_STICK {
							gp.stick_L.x = 0;
							//gp.stick_L_last.x = 0;
							delta.x = 0.0;
							value.x = 0.0;
						}

						if abs(gp.stick_L.y) < _IDLE_THRESHOLD_STICK {
							gp.stick_L.y = 0;
							//gp.stick_L_last.y = 0;
							delta.y = 0.0;
							value.y = 0.0;
						}

						gp.stick_L_sec_since_event = 0.0;
					}

					gp.stick_L_normalized = value;					
				}
			}

			if input_sys.process_user_inputs {


				for &entry in input_sys.gp_analog_callbacks {

					if entry.id.x < 0 || entry.callback == nil {
						continue;
					}
				
					if entry.analog_type == analog_type {

						entry.callback(gamepad, value, delta);
					}
				}
			}

		} // analog type
	
	} // gamepad
}

@(private="package")
input_system_register_gamepad_analog_callback :: proc(input_sys : ^InputSystem, callback_proc: GamepadAnalog_CallbackSignature, analog_type: GamepadAnalog) -> InputID {

	if callback_proc == nil {
		return InputID_INVALID;
	}

	free_array_index : i32 = -1;
	for i in 0..<len(input_sys.gp_analog_callbacks){

		if input_sys.gp_analog_callbacks[i].id == InputID_INVALID {
			// We found an unused spot
			free_array_index = cast(i32)i;
			break;
		}
	}
	
	entry : GamepadAnalog_CallbackEntry = {
		id 			= {-1, rand.int31()},
		callback 	= callback_proc,
		analog_type = analog_type,
	}

	if free_array_index == -1 {
		entry.id.x = cast(i32)len(input_sys.gp_analog_callbacks);
		append(&input_sys.gp_analog_callbacks, entry);
	} else {
		entry.id.x = free_array_index;
		input_sys.gp_analog_callbacks[free_array_index] = entry;
	}

	return entry.id;
}

@(private="package")
input_system_unregister_gamepad_analog_callback :: proc(input_sys : ^InputSystem, input_id : ^InputID) -> (ok : bool) {

	id : InputID = input_id^;

	if id.x < 0 || id.x >= cast(i32)len(input_sys.gp_analog_callbacks){
		return false; // invalid id
	}

	entry := &input_sys.gp_analog_callbacks[id.x];

	if entry.id.y != id.y {
		return false; // invalid id
	}

	entry.id = InputID_INVALID;
	entry.callback = nil;
	input_id^ = InputID_INVALID; // invalidate the user id

	return true;
}

// Gamepad Button
@(private="package")
input_system_register_gamepad_button_callback :: proc(input_sys : ^InputSystem, callback_proc: GamepadButton_CallbackSignature, button: GamepadButton, press_event_flags: PressEventFlags = {.IsPressed}) -> InputID {
	
	if callback_proc == nil {
		return InputID_INVALID;
	}

	free_array_index : i32 = -1;
	for i in 0..<len(input_sys.gp_button_callbacks){

		if input_sys.gp_button_callbacks[i].id == InputID_INVALID {
			// We found an unused spot
			free_array_index = cast(i32)i;
			break;
		}
	}
	
	entry : GamepadButton_CallbackEntry = {
		id 			= {-1, rand.int31()},
		callback 	= callback_proc,
		btn 		= button,
		press_flags = press_event_flags,
	}

	if free_array_index == -1 {
		entry.id.x = cast(i32)len(input_sys.gp_button_callbacks);
		append(&input_sys.gp_button_callbacks, entry);
	} else {
		entry.id.x = free_array_index;
		input_sys.gp_button_callbacks[free_array_index] = entry;
	}

	return entry.id;
}

@(private="package")
input_system_unregister_gamepad_button_callback :: proc(input_sys : ^InputSystem, input_id : ^InputID) -> (ok : bool) {

	id : InputID = input_id^;

	if id.x < 0 || id.x >= cast(i32)len(input_sys.gp_button_callbacks){
		return false; // invalid id
	}

	entry := &input_sys.gp_button_callbacks[id.x];

	if entry.id.y != id.y {
		return false; // invalid id
	}

	entry.id = InputID_INVALID;
	entry.callback = nil;
	input_id^ = InputID_INVALID; // invalidate the user id

	return true;
}

@(private="file")
input_system_broadcast_gamepad_button_callbacks :: proc(input_sys : ^InputSystem, device_id: sdl.JoystickID, button: GamepadButton, press_event: PressEvent, is_press : bool){

	// first we want to update the pressed buttons for the gamepad

	idx, gp_state := input_system_get_gamepad_state_for_device_id(input_sys, device_id);
	gamepad : GamepadDevice = cast(GamepadDevice)idx;

	if gp_state == nil {
		return;
	}

	#partial switch press_event {
		case .WasPressed:	gp_state.pressed_btns_now += {button};
		case .WasReleased:	gp_state.pressed_btns_now -= {button};
	}

	if !input_sys.process_user_inputs {
		return;
	}

	for &entry in input_sys.gp_button_callbacks {

		if entry.id.x < 0 || entry.callback == nil {
			continue;
		}

		if button != entry.btn || press_event not_in entry.press_flags {
			continue;
		}

		entry.callback(gamepad, is_press);
	}
}

@(private="file")
input_system_broadcast_gamepad_button_callbacks_continuous_presses :: proc(input_sys : ^InputSystem) {

	if !input_sys.process_user_inputs {
		return;
	}

	gamepads: for idx in 0..<MAX_GAMEPADS {

		if !input_sys.gp_connected[idx] {
			continue;
		}

		gamepad : GamepadDevice = cast(GamepadDevice)idx;
		gp := &input_sys.gp_states[idx];

		callbacks: for &entry in input_sys.gp_button_callbacks {
			
			// Check if entry is used
			if entry.id.x < 0 || entry.callback == nil {
				continue callbacks;
			}

			if .IsPressed in entry.press_flags || .IsReleased in entry.press_flags {
				
				is_down : bool = entry.btn in gp.pressed_btns_now;

				if .IsPressed in entry.press_flags && is_down {
					entry.callback(gamepad, is_down);
				}

				if .IsReleased in entry.press_flags && !is_down {
					entry.callback(gamepad, is_down);
				}
			}
		}
	}

}

