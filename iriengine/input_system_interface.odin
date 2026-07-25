package iri

import "core:log"
import "core:container/bit_array"
import sdl "vendor:sdl3"

// ========================================================
// ---- General Interface --------------------------
// ========================================================


MouseCursorState :: enum {
	Normal, 			// Normal Visibile Mouse Cursor.
	Hidden, 		 	// Cursor is Hidden and its position is clamped to the window.
	HiddenAndLocked, 	// Hiden and its position is locked to the center of the window. -> This Still Maintains Mouse Delta
}

input_get_mouse_cursor_state :: proc() -> MouseCursorState {
	return engine.input_system.cursor_state;
}

input_set_mouse_cursor_state :: proc(state : MouseCursorState) -> bool {
	
	input_sys := engine.input_system;

	if input_sys.cursor_state == state {
		return true;
	}

	window_handle := get_window_context().handle;
	window_size   := get_window_size();

	prev_state := input_sys.cursor_state;

	switch state {
		case .Normal: {
			ok := sdl.SetWindowRelativeMouseMode(window_handle, false);
			if !ok {
				log.warnf("InputSystem: Faild to set Mouse Cursor State to {}. - {}",state, sdl.GetError());
				return false;
			}
			
		}
		case .Hidden: {

			if prev_state == .Normal {
				ok := sdl.SetWindowRelativeMouseMode(window_handle, true);
				if !ok {
					log.warnf("InputSystem: Faild to set Mouse Cursor State to {}. - {}",state, sdl.GetError());
					return false;
				}
			}			
		}
		case .HiddenAndLocked: {
			if prev_state == .Normal {
				ok := sdl.SetWindowRelativeMouseMode(window_handle, true);
				if !ok {
					log.warnf("InputSystem: Faild to set Mouse Cursor State to {}. - {}",state, sdl.GetError());
					return false;
				}
			}
			
		}
	}

	input_sys.cursor_state = state;
	return true;
}


// ========================================================
// ---- Input Action Interface ----------------------------
// ========================================================

// -> Refer to input_system_action_interface.odin & input_system_action_types.odin


// ========================================================
// ---- Immediate Poll Interface --------------------------
// ========================================================

input_create_default_context :: proc() -> InputContext {
	return InputContext {
		gamepad_device = GamepadDevice.Any,
	}
}


input_keyboard :: proc(key : Key, press_events : PressEventFlags, condition : InputCondition = nil, ctx : ^InputContext = nil) -> PressResult {

	input_sys : ^InputSystem = engine.input_system;

	if !input_sys.process_user_inputs {
		return PressResult{};
	}

	if condition != nil {
		is_satisfied := input_is_condition_satisfied(condition, ctx);
		if !is_satisfied {
			return PressResult{};
		}
	}

	scancode : sdl.Scancode = sdl.GetScancodeFromKey(cast(sdl.Keycode)key, nil);
	is_down_now, _   := bit_array.get(&input_sys.keyboard_state_now, cast(uint)scancode);
	was_down_last, _ := bit_array.get(&input_sys.keyboard_state_last, cast(uint)scancode);


	key_press_flags : PressEventFlags = {};

	if is_down_now {
		key_press_flags += {.IsPressed}; 
	} else {
		key_press_flags += {.IsReleased};
	}

	if is_down_now && !was_down_last {
	 	key_press_flags += {.WasPressed};
	}

	if !is_down_now && was_down_last {
	 	key_press_flags += {.WasReleased};
	}

	// @Note: if there is any intersection between the two sets we return true.
	res : PressResult;
	res.triggered = (key_press_flags & press_events) != PressEventFlags{};
	res.is_down   = is_down_now;

	return res;
}

input_keyboard_axis_WASD :: proc() -> [2]f32 {

	if !engine.input_system.process_user_inputs {
		return [2]f32{0.0,0.0};
	}

	axis : [2]f32;

	if input_keyboard(.W, {.IsPressed}).triggered {
		axis.y += 1.0;
	}
	if input_keyboard(.S, {.IsPressed}).triggered {
		axis.y -= 1.0;
	}
	if input_keyboard(.A, {.IsPressed}).triggered {
		axis.x -= 1.0;
	}
	if input_keyboard(.D, {.IsPressed}).triggered {
		axis.x += 1.0;
	}

	return axis;
}

input_keyboard_axis_ARROWS :: proc() -> [2]f32 {
	
	if !engine.input_system.process_user_inputs {
		return [2]f32{0.0,0.0};
	}

	axis : [2]f32;

	if input_keyboard(.UP, {.IsPressed}).triggered {
		axis.y += 1.0;
	}
	if input_keyboard(.DOWN, {.IsPressed}).triggered {
		axis.y -= 1.0;
	}
	if input_keyboard(.LEFT, {.IsPressed}).triggered {
		axis.x -= 1.0;
	}
	if input_keyboard(.RIGHT, {.IsPressed}).triggered {
		axis.x += 1.0;
	}

	return axis;
}


input_mouse_button :: proc(btn : MouseButton, press_events : PressEventFlags, condition : InputCondition = nil, ctx : ^InputContext = nil) -> PressResult {
	
	input_sys : ^InputSystem = engine.input_system;

	if !input_sys.process_user_inputs {
		return PressResult{};
	}

	if condition != nil {
		if !input_is_condition_satisfied(condition, ctx) {
			return PressResult{};
		}
	}

	return PressResult {
		triggered = input_sys.mouse_btn_curr_press_events[btn] & press_events != PressEventFlags{},
		is_down  = .IsPressed in input_sys.mouse_btn_curr_press_events[btn],
	}
}

// Get the OS Mouse Cursor position in pixels on monitor setup.
input_global_mouse_position :: proc() -> [2]f32 {
	return engine.input_system.global_mouse_pos;
}

// Get mouse position in pixels relative to the window.
input_relative_mouse_position :: proc() -> [2]f32 {
	if !engine.input_system.process_user_inputs {
		return [2]f32{0.0,0.0};
	}

	return engine.input_system.relative_mouse_pos;
}

input_mouse_delta :: proc() -> [2]f32 {
	if !engine.input_system.process_user_inputs {
		return [2]f32{0.0,0.0};
	}

	return engine.input_system.mouse_delta;
}

input_mouse_wheel :: proc(condition : InputCondition = nil, ctx : ^InputContext = nil) -> [2]f32 {
	if !engine.input_system.process_user_inputs {
		return [2]f32{0.0,0.0};
	}

	if !input_is_condition_satisfied(condition, ctx) {
		return [2]f32{0.0,0.0};
	}

	return engine.input_system.mouse_wheel_now;
}

input_mouse_in_motion :: proc() -> bool {
	return engine.input_system.mouse_delta != [2]f32{0.0, 0.0};
}

input_gamepad_button :: proc(btn : GamepadButton, press_events : PressEventFlags, condition : InputCondition = nil, ctx : ^InputContext = nil) -> PressResult {

	input_sys := engine.input_system;
	
	if !input_sys.process_user_inputs {
		return PressResult{};
	}

	gp_device : GamepadDevice = ctx == nil ? GamepadDevice.Any : ctx.gamepad_device;

	for idx in 0..<MAX_GAMEPADS {
		
		curr_device : GamepadDevice = cast(GamepadDevice)idx;

		// if not 'Any' skip all except the one we want to check for.		
		if gp_device != GamepadDevice.Any && curr_device != gp_device {
			continue;
		}

		if !input_sys.gp_connected[idx] {
			continue;
		}

		if condition != nil {
			if !input_is_condition_satisfied_explicit_gamepad(condition, curr_device, ctx) {
				return PressResult{}
			}
		}

		state := &input_sys.gp_states[idx];

		is_down_now   : bool = btn in state.pressed_btns_now;
		was_down_last : bool = btn in state.pressed_btns_last;

		event_flags : PressEventFlags = {};
		event_flags += is_down_now ? {.IsPressed} : {.IsReleased};

		if is_down_now && !was_down_last {
		 	event_flags += {.WasPressed};
		}

		if !is_down_now && was_down_last {
		 	event_flags += {.WasReleased};
		}

		return PressResult {
			// @Note: if there is any intersection between the two sets we return true.
			triggered = (event_flags & press_events) != PressEventFlags{},
			is_down = is_down_now,
		}
	}

	return PressResult{};
}

input_gamepad_analog :: proc(analog_type : GamepadAnalog, condition : InputCondition = nil, ctx : ^InputContext = nil) -> [2]f32 {

	input_sys := engine.input_system;
	
	if !input_sys.process_user_inputs {
		return [2]f32{0.0,0.0};
	}

	gp_device : GamepadDevice = ctx == nil ? GamepadDevice.Any : ctx.gamepad_device;

	for idx in 0..<MAX_GAMEPADS {
		
		curr_device : GamepadDevice = cast(GamepadDevice)idx;

		// if not 'Any' skip all except the one we want to check for.		
		if gp_device != GamepadDevice.Any && curr_device != gp_device {
			continue;
		}

		if !input_sys.gp_connected[idx] {
			continue;
		}

		if condition != nil {
			if !input_is_condition_satisfied_explicit_gamepad(condition, curr_device, ctx) {
				continue
			}
		}

		state := &input_sys.gp_states[idx];

		val : [2]f32;

		switch analog_type {
			case GamepadAnalog.RIGHT_TRIGGER: val.x = state.trigger_R_normalized_01;
			case GamepadAnalog.LEFT_TRIGGER:  val.x = state.trigger_L_normalized_01;
			case GamepadAnalog.RIGHT_STICK:   val = state.stick_R_normalized;
			case GamepadAnalog.LEFT_STICK:    val = state.stick_L_normalized;
		}

		if abs(val.x) > 0.0 || abs(val.y) > 0.0 {
			return val;
		}
	}

	return [2]f32{0.0,0.0};
}

input_gamepad_analog_as_button :: proc(analog_type : GamepadAnalog, press_events : PressEventFlags, axis_to_value_op : AxisToValueOp = AxisToValueOp.Length, press_threshold : f32 = 0.1, condition : InputCondition = nil, ctx : ^InputContext = nil) -> PressResult {

	input_sys := engine.input_system;
	
	if !input_sys.process_user_inputs {
		return PressResult{};
	}

	//_idx := cast(int)gamepad_device;


	I16_MAX :: 32767.0;

	// we do this in i16 space because we only store i16 raw values in both current and last state for gamepad analogs.
	//press_threshold_i16 : i16 = cast(i16)(press_threshold * 32767.0);

	gp_device : GamepadDevice = ctx == nil ? GamepadDevice.Any : ctx.gamepad_device;

	for idx in 0..<MAX_GAMEPADS {
		
		curr_device : GamepadDevice = cast(GamepadDevice)idx;

		// if not 'Any' skip all except the one we want to check for.		
		if gp_device != GamepadDevice.Any && curr_device != gp_device {
			continue;
		}

		if !input_sys.gp_connected[idx] {
			continue;
		}

		if condition != nil {
			if !input_is_condition_satisfied_explicit_gamepad(condition, curr_device, ctx) {
				continue
			}
		}

		state := &input_sys.gp_states[idx];

		pressed_now  : bool = false;
		pressed_last : bool = false;

		switch analog_type {
			case GamepadAnalog.RIGHT_TRIGGER: {
				pressed_now  = f32(f32(state.trigger_R     ) / I16_MAX) > press_threshold;
				pressed_last = f32(f32(state.trigger_R_last) / I16_MAX) > press_threshold;
			}
			case GamepadAnalog.LEFT_TRIGGER:{
				pressed_now  = f32(f32(state.trigger_L     ) / I16_MAX) > press_threshold;
				pressed_last = f32(f32(state.trigger_L_last) / I16_MAX) > press_threshold;
			}
			case GamepadAnalog.RIGHT_STICK: {

				stick_r_now_axis  : [2]f32 = [2]f32{f32(state.stick_R.x     ), f32(state.stick_R.y     )} / I16_MAX;
				stick_r_last_axis : [2]f32 = [2]f32{f32(state.stick_R_last.x), f32(state.stick_R_last.y)} / I16_MAX;
								
				pressed_now   = abs(input_apply_axis_to_value_op(stick_r_now_axis , axis_to_value_op).x) > press_threshold;
				pressed_last  = abs(input_apply_axis_to_value_op(stick_r_last_axis, axis_to_value_op).x) > press_threshold;
					
			}
			case GamepadAnalog.LEFT_STICK: {

				stick_l_now_axis  : [2]f32 = [2]f32{f32(state.stick_L.x     ), f32(state.stick_L.y     )} / I16_MAX;
				stick_l_last_axis : [2]f32 = [2]f32{f32(state.stick_L_last.x), f32(state.stick_L_last.y)} / I16_MAX;
				
				pressed_now   = abs(input_apply_axis_to_value_op(stick_l_now_axis , axis_to_value_op).x) > press_threshold;
				pressed_last  = abs(input_apply_axis_to_value_op(stick_l_last_axis, axis_to_value_op).x) > press_threshold;			
			}
		}

		analog_press_flags : PressEventFlags;
		analog_press_flags += pressed_now ? {.IsPressed} : {.IsReleased};

		if pressed_now && !pressed_last {
			analog_press_flags += {.WasPressed};
		}
		if !pressed_now && pressed_last {
			analog_press_flags += {.WasReleased};
		}

		triggered : bool = (analog_press_flags & press_events) != PressEventFlags{};
		if triggered {
			return PressResult {
				triggered = true,
				is_down  = pressed_now,
			}
		}		
	}

	return PressResult{};
}

input_is_condition_satisfied :: proc(condition : InputCondition, ctx : ^InputContext = nil) -> bool {

	input_sys := engine.input_system;

	if condition == nil {
		return true; // no condition
	}

	switch variant in condition {
		case KeymodFlags:  		 return variant <= input_sys.keymods;
		case MouseButtonFlags:   {

			for mouse_btn in variant{
				if .IsPressed not_in input_sys.mouse_btn_curr_press_events[mouse_btn]{
					return false;
				}
			}
			return true;
		}
		case GamepadButtonFlags: {

			gp_device : GamepadDevice = ctx == nil ? GamepadDevice.Any : ctx.gamepad_device;

			if gp_device != GamepadDevice.Any {

				idx : int = cast(int)gp_device;
				if !input_sys.gp_connected[idx] {
					return false; // gamepad not connected.
				}
				return variant <= input_sys.gp_states[idx].pressed_btns_now;
			}

			for idx in 0..<MAX_GAMEPADS{
				if !input_sys.gp_connected[idx] {
					continue;
				}
				if variant <= input_sys.gp_states[idx].pressed_btns_now {
					return true;
				}
			}

			return false; // no connected gamepad satisfies the condition.
		}
	}

	return false; // invalid codepath
}

// Mostly for internal usage
input_is_condition_satisfied_explicit_gamepad :: proc(condition : InputCondition, gp_device : GamepadDevice, ctx : ^InputContext = nil) -> bool {

	input_sys := engine.input_system;

	if condition == nil {
		return true; // no condition
	}

	engine_assert(gp_device != GamepadDevice.Any); // Explicit!

	switch variant in condition {
		case KeymodFlags:  		 return variant <= input_sys.keymods;
		case MouseButtonFlags: {

			for mouse_btn in variant{
				if .IsPressed not_in input_sys.mouse_btn_curr_press_events[mouse_btn]{
					return false;
				}
			}
			return true; 
		}
		case GamepadButtonFlags: {

			idx : int = cast(int)gp_device;
			if !input_sys.gp_connected[idx] {
				return false; // gamepad not connected.
			}
			return variant <= input_sys.gp_states[idx].pressed_btns_now;
		}
	}

	return false; // invalid codepath
}


// ========================================================
// ---- Callback Interface --------------------------------
// ========================================================

// @Note: you can use this to get 'raw' SDL input events and handle stuff yourself at your own risk.
input_register_sdl_event_callback :: proc(callback_proc: SDLEvent_CallbackSignature) -> InputID {
	return input_system_register_sdl_event_callback(engine.input_system, callback_proc);
}

input_unregister_sdl_event_callback :: proc(input_id : ^InputID) -> (ok : bool) {
	return input_system_unregister_sdl_event_callback(engine.input_system, input_id);
}

// --- Keyboard ---
input_register_keyboard_callback :: proc(callback_proc: Keyboard_CallbackSignature, key_code: Key, press_event_flags : PressEventFlags, key_mods: KeymodFlags = {}) -> InputID {
	return input_system_register_keyboard_callback(engine.input_system, callback_proc, key_code, press_event_flags, key_mods);
}

input_unregister_keyboard_callback :: proc(input_id : ^InputID) -> (ok : bool) {
	return input_system_unregister_keyboard_callback(engine.input_system, input_id);
}

// --- Mouse ---

input_register_mouse_button_callback :: proc(callback_proc: MouseButton_CallbackSignature, mouse_button : MouseButton, press_event_flags: PressEventFlags = {.IsPressed}) -> InputID {
	return input_system_register_mouse_button_callback(engine.input_system, callback_proc, mouse_button, press_event_flags);
}

input_unregister_mouse_button_callback :: proc(input_id : ^InputID) -> (ok : bool) {
	return input_system_unregister_mouse_button_callback(engine.input_system, input_id);
}

input_register_mouse_wheel_callback :: proc(callback_proc: MouseWheel_CallbackSignature) -> InputID {
	return input_system_register_mouse_wheel_callback(engine.input_system, callback_proc);
}

input_unregister_mouse_wheel_callback :: proc(input_id : ^InputID) -> (ok : bool) {
	return input_system_unregister_mouse_wheel_callback(engine.input_system, input_id);
}

input_register_mouse_motion_callback :: proc(callback_proc: MouseMotion_CallbackSignature) -> InputID {
	return input_system_register_mouse_motion_callback(engine.input_system, callback_proc);
}

input_unregister_mouse_motion_callback :: proc(input_id : ^InputID) -> (ok : bool) {
	return input_system_unregister_mouse_motion_callback(engine.input_system, input_id);
}

// --- Gamepad ---

input_set_gamepad_added_callback :: proc(callback_proc : GamepadDeviceEvent_CallbackSignature){
	engine.input_system.gp_added_callback = callback_proc;
}

input_set_gamepad_removed_callback :: proc(callback_proc : GamepadDeviceEvent_CallbackSignature){
	engine.input_system.gp_removed_callback = callback_proc;
}

input_set_gamepad_remapped_callback :: proc(callback_proc : GamepadDeviceEvent_CallbackSignature){
	engine.input_system.gp_remapped_callback = callback_proc;
}


input_register_gamepad_button_callback :: proc(callback_proc: GamepadButton_CallbackSignature, button: GamepadButton, press_event_flags: PressEventFlags = {.IsPressed}) -> InputID {
	return input_system_register_gamepad_button_callback(engine.input_system,callback_proc, button, press_event_flags);
}

input_unregister_gamepad_button_callback :: proc(input_id : ^InputID) -> (ok : bool) {
	return input_system_unregister_gamepad_button_callback(engine.input_system, input_id);
}


input_register_gamepad_analog_callback :: proc(callback_proc: GamepadAnalog_CallbackSignature, analog_type: GamepadAnalog) -> InputID {
	return input_system_register_gamepad_analog_callback(engine.input_system, callback_proc, analog_type);
}

input_unregister_gamepad_analog_callback :: proc(input_id : ^InputID) -> (ok : bool) {
	return input_system_unregister_gamepad_analog_callback(engine.input_system, input_id)
}