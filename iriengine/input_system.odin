package iri

import "core:log"
import "core:c"
import "core:math"
import sdl "vendor:sdl3"

// TODO:
// - make process user inputs into two seperate things (process mouse inputs, process keyboard inputs) we can get this seperatly from DearImgui

// Window Events
// Mouse Cursor Operations (hide show.. )


SDLEvent_CallbackSignature :: #type proc(sdl_event: ^sdl.Event);
SDLEvent_CallbackEntry :: struct {
	id : i32,
	callback: SDLEvent_CallbackSignature,
}

MouseButton_CallbackSignature :: #type proc(mouse_pos: [2]f32, is_pressed: bool,is_double_click : bool);
MouseButton_CallbackEntry :: struct {
	id : i32,
	callback : MouseButton_CallbackSignature,
	mouse_button : MouseButton,
	mouse_button_actions : MouseButtonActionSet,
}

MouseWheel_CallbackSignature :: #type proc(mouse_pos: [2]f32, mouse_scroll: [2]f32, is_flipped_direction : bool);
MouseWheel_CallbackEntry :: struct {
	id : i32,
	callback : MouseWheel_CallbackSignature,
}

MouseMotion_CallbackSignature :: #type proc(mouse_pos: [2]f32, mouse_delta: [2]f32);
MouseMotion_CallbackEntry :: struct {
	id : i32,
	callback : MouseMotion_CallbackSignature,
}

Keyboard_CallbackSignature :: #type proc(is_press: bool, is_repeat: bool)
Keyboard_CallbackEntry :: struct {
	id : i32,
	callback    : Keyboard_CallbackSignature,
	key_code    : Key,
	key_actions : KeyActionSet,
	key_mods    : KeymodFlags,
}

GamepadDeviceEvent_CallbackSignature :: #type proc(device_id : u32)

GamepadAnalog_CallbackSignature :: #type proc(device_id: u32, value: [2]f32, delta: [2]f32)
GamepadAnalog_CallbackEntry :: struct {
	id: i32,
	callback: GamepadAnalog_CallbackSignature,
	analog_type: GamepadAnalog,
}

GamepadButton_CallbackSignature :: #type proc(device_id: u32, is_press: bool);
GamepadButton_CallbackEntry :: struct {
	id: i32,
	callback: GamepadButton_CallbackSignature,
	btn: GamepadButton,
	btn_actions : GamepadButtonActionSet,
}



InputSystemState :: struct{

	process_user_inputs: bool,
	
	// updated every frame using sdl.GetMouseState().
	relative_mouse_pos : [2]f32, // relative to the focused window.
	global_mouse_pos : [2]f32, // global to the entire screen
	mouse_delta : [2]f32,
	mouse_btn_state_flags : sdl.MouseButtonFlags, 


	keyboard_state : [^]bool,

	sdl_events_callbacks: [dynamic]SDLEvent_CallbackEntry,

	mouse_button_callbacks: [dynamic]MouseButton_CallbackEntry,
	mouse_wheel_callbacks: 	[dynamic]MouseWheel_CallbackEntry,
	mouse_motion_callbacks: [dynamic]MouseMotion_CallbackEntry,
	keyboard_callbacks: 	[dynamic]Keyboard_CallbackEntry,

	gp_added_callback: GamepadDeviceEvent_CallbackSignature,
	gp_removed_callback: GamepadDeviceEvent_CallbackSignature,
	gp_remapped_callback: GamepadDeviceEvent_CallbackSignature,

	gp_analog_callbacks: [dynamic]GamepadAnalog_CallbackEntry,
	gp_button_callbacks: [dynamic]GamepadButton_CallbackEntry,



	// @Note - Fulcrum
	// when we receive a gamepad added event, we add the gamepads device id (sdl.JoystickID) 
	// to the gp_ids if there is a free spot (only up to 4 supported atm) and create a new GamepadAnalogState in the 'gp_states' array
	gp_ids: [4]GamepadStateID,
	gp_states: [dynamic]GamepadAnalogState,
}

@(private="file")
istate : InputSystemState;


@(private="package")
input_system_init :: proc(){

	istate.process_user_inputs = true;
	istate.keyboard_state = sdl.GetKeyboardState(nil);

	for i in 0..<4 {
		istate.gp_ids[i].array_index = -1;
	}
}

@(private="package")
input_system_update :: proc(){

	event : sdl.Event;

	// NOTE:
	// if process user inputs is turned off 
	// we still want to listen to some events but only reveant ones to the engine.
	//

	for sdl.PollEvent(&event) {

		input_call_sdl_event_callbacks(&event);

		if(!istate.process_user_inputs){
			continue;
		}


		#partial switch (event.type) {

			case sdl.EventType.QUIT:
			

			// Keyboard
			case sdl.EventType.KEY_DOWN:
				key_code : Key = cast(Key)event.key.key; // we can do this cast bc the enum values match SDL keycodes
				is_repeat := event.key.repeat;				
				mods: KeymodFlags = transmute(KeymodFlags)event.key.mod;
				input_call_keyboard_callbacks(key_code, is_repeat ? .REPEAT : .PRESS, true, is_repeat, mods);	
			case sdl.EventType.KEY_UP:
				key_code : Key = cast(Key)event.key.key; // we can do this cast bc the enum values match SDL keycodes
				input_call_keyboard_callbacks(key_code, KeyAction.RELEASE, false, false, {}); // note the empty keymods here bc release atm always goes through regardless of keymods
			
			// Mouse Motion
			case sdl.EventType.MOUSE_MOTION:
				input_call_mouse_motion_callbacks([2]f32{event.motion.x, event.motion.y}, [2]f32{event.motion.xrel, event.motion.yrel} );

			// Mouse Buttons
			case sdl.EventType.MOUSE_BUTTON_DOWN:				
				if(event.button.button == 0 || event.button.button > 5) do continue;
				input_call_mouse_button_callbacks(cast(MouseButton)event.button.button, MouseButtonAction.PRESS, is_pressed = true, is_double_click = event.button.clicks == 2, mouse_pos = [2]f32{event.button.x, event.button.y});
			case sdl.EventType.MOUSE_BUTTON_UP:
				if(event.button.button == 0 || event.button.button > 5) do continue;
				input_call_mouse_button_callbacks(cast(MouseButton)event.button.button, MouseButtonAction.RELEASE,is_pressed = false, is_double_click = false, mouse_pos = [2]f32{event.button.x, event.button.y});

			// Mouse Wheel
			case sdl.EventType.MOUSE_WHEEL:
				input_call_mouse_wheel_callbacks([2]f32{event.wheel.mouse_x, event.wheel.mouse_y}, [2]f32{event.wheel.x, event.wheel.y}, event.wheel.direction == sdl.MouseWheelDirection.FLIPPED);


			// GAMEPAD
			case sdl.EventType.GAMEPAD_ADDED:	input_internal_handle_gamepad_added(event.gdevice.which);   // also calls user callback
			case sdl.EventType.GAMEPAD_REMOVED: input_internal_handle_gamepad_removed(event.gdevice.which); // also calls user callback
			case sdl.EventType.GAMEPAD_REMAPPED:
				if(istate.gp_remapped_callback != nil){
					istate.gp_remapped_callback(cast(u32)event.gdevice.which);
				}
			
			case sdl.EventType.GAMEPAD_BUTTON_DOWN:	
				input_call_gamepad_button_callbacks(cast(u32)event.gbutton.which, cast(GamepadButton)event.gbutton.button, GamepadButtonAction.PRESS, event.gbutton.down)
			case sdl.EventType.GAMEPAD_BUTTON_UP:   
				input_call_gamepad_button_callbacks(cast(u32)event.gbutton.which, cast(GamepadButton)event.gbutton.button, GamepadButtonAction.RELEASE, event.gbutton.down)
				
			case sdl.EventType.GAMEPAD_AXIS_MOTION:

				axis := cast(sdl.GamepadAxis)event.gaxis.axis
				val: i16 = event.gaxis.value;
				device_id := cast(u32)event.gaxis.which;
				gp := input_get_gamepad_analog_state_for_device_id(device_id);
				//log.debugf("val: {} ",val)
				if(gp != nil) {
					switch (axis) {
						case .INVALID:
						case .RIGHT_TRIGGER:
							gp.trigger_R =  val;
							gp.event_happend_set |= {.RIGHT_TRIGGER};
						case .LEFT_TRIGGER:
							gp.trigger_L = val;
							gp.event_happend_set |= {.LEFT_TRIGGER};
						case .LEFTX:
							gp.stick_L.x = val;
							gp.event_happend_set |= {.LEFT_STICK};				
						case .LEFTY:
							gp.stick_L.y = val;
							gp.event_happend_set |= {.LEFT_STICK};
						case .RIGHTX:
							gp.stick_R.x = val;
							gp.event_happend_set |= {.RIGHT_STICK};
						case .RIGHTY:
							gp.stick_R.y = val;
							gp.event_happend_set |= {.RIGHT_STICK};
					}
				}

			case:
		} // switch end
	} // poll events end


	new_relative_mouse_pos : [2]f32;
	//istate.mouse_btn_state_flags = sdl.GetMouseState(&istate.rel_mouse_pos.x, &istate.rel_mouse_pos.y);
	istate.mouse_btn_state_flags = sdl.GetMouseState(&new_relative_mouse_pos.x, &new_relative_mouse_pos.y);
	
	istate.mouse_delta = new_relative_mouse_pos - istate.relative_mouse_pos;
	istate.relative_mouse_pos = new_relative_mouse_pos;

	global_mouse_state := sdl.GetGlobalMouseState(&istate.global_mouse_pos.x, &istate.global_mouse_pos.y);

	// Continuous press registers for mouse and keyboard are handled seperatly each frame.
	input_call_mouse_button_callbacks_continuous_presses(istate.relative_mouse_pos);
	input_call_keyboard_callbacks_continuous_presses();

	true_delta_time := clock_get_true_delta_time();
	input_evaluate_gamepad_states_and_call_analog_callbacks(true_delta_time);
}

@(private="package")
input_system_shutdown :: proc(){

	delete(istate.sdl_events_callbacks);
	delete(istate.mouse_button_callbacks);
	delete(istate.mouse_wheel_callbacks);
	delete(istate.mouse_motion_callbacks);
	delete(istate.keyboard_callbacks);
	delete(istate.gp_analog_callbacks);
	delete(istate.gp_button_callbacks);
	delete(istate.gp_states);
}

@(private="package")
input_system_set_process_user_input :: proc(process_user_inputs: bool){
	istate.process_user_inputs = process_user_inputs;
}

// ============================================================================================================================
// SDL Event Callbacks
// NOTE: Sdl event callbacks are only for internal engine usage!
@(private="package")
input_register_sdl_event_callback :: proc(callback_proc: SDLEvent_CallbackSignature) -> i32 {
	if(callback_proc == nil){
		return -1;
	}


	entry_id : i32 = -1;

	for i in 0..<len(istate.sdl_events_callbacks){

		if(istate.sdl_events_callbacks[i].id == -1) {
			// We found an unused spot
			entry_id = cast(i32)i;
			break;
		}
	}

	if(entry_id == -1){
		// If we haven't found an empty spot. Id is equal to array size
		entry_id = cast(i32)len(istate.sdl_events_callbacks);
	}


	entry : SDLEvent_CallbackEntry = {
		id = entry_id,
		callback = callback_proc,
	}

	append(&istate.sdl_events_callbacks, entry);

	return entry.id;
}

@(private="package")
input_unregister_sdl_event_callback :: proc(id : ^i32){

	if(id^ < 0) { // invalid id
		return;
	}

	for i in 0..<len(istate.sdl_events_callbacks){

		if(istate.sdl_events_callbacks[i].id == id^){
			// we found the id
			istate.sdl_events_callbacks[i].id = -1;
			istate.sdl_events_callbacks[i].callback = nil;
			id^ = -1; // invalidate the user id
			return;
		}
	}
}

@(private="file")
input_call_sdl_event_callbacks :: proc(sdl_event: ^sdl.Event){

	for i in 0..<len(istate.sdl_events_callbacks){

		if(istate.sdl_events_callbacks[i].id >= 0 && istate.sdl_events_callbacks[i].callback != nil){
			istate.sdl_events_callbacks[i].callback(sdl_event);
		}
	}
}


// ============================================================================================================================
// MOUSE BUTTON

input_register_mouse_button_callback :: proc(callback_proc: MouseButton_CallbackSignature, mouse_button : MouseButton, button_actions: MouseButtonActionSet = {MouseButtonAction.PRESS}) -> i32 {

	if(callback_proc == nil){
		return -1;
	}

	entry_id : i32 = -1;

	for i in 0..<len(istate.mouse_button_callbacks){

		if(istate.mouse_button_callbacks[i].id == -1) {
			// We found an unused spot
			entry_id = cast(i32)i;
			break;
		}
	}

	if(entry_id == -1){
		// If we haven't found an empty spot. Id is equal to array size
		entry_id = cast(i32)len(istate.mouse_button_callbacks);
	}


	entry : MouseButton_CallbackEntry = {
		id = entry_id,
		callback = callback_proc,
		mouse_button = mouse_button,
		mouse_button_actions = button_actions,
	}

	append(&istate.mouse_button_callbacks, entry);

	return entry.id;
}

input_unregister_mouse_button_callback :: proc(id : ^i32){

	if(id^ < 0) { // invalid id
		return;
	}

	for i in 0..<len(istate.mouse_button_callbacks){

		if(istate.mouse_button_callbacks[i].id == id^){
			// we found the id
			istate.mouse_button_callbacks[i].id = -1;
			istate.mouse_button_callbacks[i].callback = nil;
			id^ = -1; // invalidate the user id
			return;
		}
	}
}

@(private="file")
input_call_mouse_button_callbacks :: proc(mouse_button: MouseButton, action: MouseButtonAction, is_pressed: bool, is_double_click : bool, mouse_pos : [2]f32){

	for &entry in istate.mouse_button_callbacks {

		if(entry.id >= 0 && entry.callback != nil){

			if(mouse_button != entry.mouse_button || action not_in entry.mouse_button_actions) {
				continue;
			}

			entry.callback(mouse_pos,is_pressed, is_double_click);
		}
	}
}

// Here we process only registered entries with the MouseButtonAction.PRESS_CONTINUOUS flag
@(private="file")
input_call_mouse_button_callbacks_continuous_presses :: proc(mouse_pos : [2]f32){

	for &entry in istate.mouse_button_callbacks {

		// Check if entry is used
		if(entry.id >= 0 && entry.callback != nil){

			// only care about entries with continuous presses
			if(MouseButtonAction.PRESS_CONTINUOUS not_in entry.mouse_button_actions){
				continue;
			}

			if(#force_inline input_is_mouse_button_pressed(entry.mouse_button)){
				entry.callback(mouse_pos, true, false);
			}
		}
	}
}

input_is_mouse_button_pressed :: proc(mouse_button : MouseButton) -> bool {

	if(!istate.process_user_inputs){
		return false;
	}

	// SDL MouseButtonFlag is defined like this
	// MouseButtonFlag :: enum Uint32 {
	// 	LEFT   = 1 - 1,
	// 	MIDDLE = 2 - 1,
	// 	RIGHT  = 3 - 1,
	// 	X1     = 4 - 1,
	// 	X2     = 5 - 1,
	// }

	return cast(sdl.MouseButtonFlag)u32(cast(u32)mouse_button - 1) in istate.mouse_btn_state_flags;
}

// ============================================================================================================================
// MOUSE WHEEL
input_register_mouse_wheel_callback :: proc(callback_proc: MouseWheel_CallbackSignature) -> i32 {

	if(callback_proc == nil){
		return -1;
	}

	entry_id : i32 = -1;

	for i in 0..<len(istate.mouse_wheel_callbacks){

		if(istate.mouse_wheel_callbacks[i].id == -1) {
			// We found an unused spot
			entry_id = cast(i32)i;
			break;
		}
	}

	if(entry_id == -1){
		// If we haven't found an empty spot. Id is equal to array size
		entry_id = cast(i32)len(istate.mouse_wheel_callbacks);
	}

	entry : MouseWheel_CallbackEntry = {
		id = entry_id,
		callback = callback_proc,
	}

	append(&istate.mouse_wheel_callbacks, entry);

	return entry.id;
}

input_unregister_mouse_wheel_callback :: proc(id : ^i32){

	if(id^ < 0) { // invalid id
		return;
	}

	for i in 0..<len(istate.mouse_wheel_callbacks){

		if(istate.mouse_wheel_callbacks[i].id == id^){
			// we found the id
			istate.mouse_wheel_callbacks[i].id = -1;
			istate.mouse_wheel_callbacks[i].callback = nil;
			id^ = -1; // invalidate the user id
			return;
		}
	}
}

@(private="file")
input_call_mouse_wheel_callbacks :: proc(mouse_pos : [2]f32, mouse_scroll : [2]f32, is_flipped_direction : bool){

	for &entry in istate.mouse_wheel_callbacks {

		// Check if entry is used
		if(entry.id >= 0 && entry.callback != nil){
			entry.callback(mouse_pos, mouse_scroll, is_flipped_direction);
		}
	}
}


// ============================================================================================================================
// MOUSE MOTION

input_register_mouse_motion_callback :: proc(callback_proc: MouseMotion_CallbackSignature) -> i32 {

	if(callback_proc == nil){
		return -1;
	}

	entry_id : i32 = -1;

	for i in 0..<len(istate.mouse_motion_callbacks){

		if(istate.mouse_motion_callbacks[i].id == -1) {
			// We found an unused spot
			entry_id = cast(i32)i;
			break;
		}
	}

	if(entry_id == -1){
		// If we haven't found an empty spot. Id is equal to array size
		entry_id = cast(i32)len(istate.mouse_motion_callbacks);
	}

	entry : MouseMotion_CallbackEntry = {
		id = entry_id,
		callback = callback_proc,
	}

	append(&istate.mouse_motion_callbacks, entry);

	return entry.id;
}

input_unregister_mouse_motion_callback :: proc(id : ^i32){

	if(id^ < 0) { // invalid id
		return;
	}

	for i in 0..<len(istate.mouse_motion_callbacks){

		if(istate.mouse_motion_callbacks[i].id == id^){
			// we found the id
			istate.mouse_motion_callbacks[i].id = -1;
			istate.mouse_motion_callbacks[i].callback = nil;
			id^ = -1; // invalidate the user id
			return;
		}
	}
}

@(private="file")
input_call_mouse_motion_callbacks :: proc(mouse_pos : [2]f32, mouse_delta : [2]f32){

	for &entry in istate.mouse_motion_callbacks {

		// Check if entry is used
		if(entry.id >= 0 && entry.callback != nil){
			entry.callback(mouse_pos, mouse_delta);
		}
	}
}


input_get_global_mouse_position :: proc() -> [2]f32{
	return istate.global_mouse_pos;
}

input_get_relative_mouse_position :: proc() -> [2]f32{
	return istate.relative_mouse_pos;
}

input_get_mouse_delta :: proc() -> [2]f32 {
	return istate.mouse_delta;
}

// ============================================================================================================================
// KEYBOARD

input_register_keyboard_callback :: proc(callback_proc: Keyboard_CallbackSignature, key_code: Key, key_actions: KeyActionSet = {KeyAction.PRESS}, key_mods: KeymodFlags = {}) -> i32 {

	if(callback_proc == nil){
		return -1;
	}

	entry_id : i32 = -1;

	for i in 0..<len(istate.keyboard_callbacks){

		if(istate.keyboard_callbacks[i].id == -1) {
			// We found an unused spot
			entry_id = cast(i32)i;
			break;
		}
	}

	if(entry_id == -1){
		// If we haven't found an empty spot. Id is equal to array size
		entry_id = cast(i32)len(istate.keyboard_callbacks);
	}


	entry : Keyboard_CallbackEntry = {
		id = entry_id,
		callback = callback_proc,
		key_code = key_code,
		key_actions = key_actions,
		key_mods = key_mods,
	}

	append(&istate.keyboard_callbacks, entry);

	return entry.id;
}

input_unregister_keyboard_callback :: proc(id : ^i32){

	if(id^ < 0) { // invalid id
		return;
	}

	for i in 0..<len(istate.keyboard_callbacks){

		if(istate.keyboard_callbacks[i].id == id^){
			// we found the id
			istate.keyboard_callbacks[i].id = -1;
			istate.keyboard_callbacks[i].callback = nil;
			id^ = -1; // invalidate the user id
			return;
		}
	}
}

@(private="file")
input_call_keyboard_callbacks :: proc(key_code : Key, action : KeyAction, is_pressed: bool, is_repeat : bool, key_mods: KeymodFlags){

	for &entry in istate.keyboard_callbacks {

		// Check if entry is used
		if(entry.id >= 0 && entry.callback != nil){

			if(entry.key_code != key_code || action not_in entry.key_actions){
				continue;
			}

			// @Note: -fulcrum
			// if this is a key release event (!is_pressed), we always send the event through, 
			// even if specified keymodFlags are not pressed. I would say this is the more intuitive behavior.

			if(!is_pressed || entry.key_mods <= key_mods){ // A <= B - subset relation (A is a subset of B or equal to B)
				entry.callback(is_pressed, is_repeat);
			}

		}
	}
}

// Here we process only registered entry with the KeyAction.PRESS_CONTINUOUS
@(private="file")
input_call_keyboard_callbacks_continuous_presses :: proc(){
	
	for &entry in istate.keyboard_callbacks {

		// Check if entry is used
		if(entry.id >= 0 && entry.callback != nil){

			if(KeyAction.PRESS_CONTINUOUS not_in entry.key_actions) {
				continue;
			}
			
			if(input_is_key_pressed(entry.key_code)){
				entry.callback(true, false);
			}
		}
	}
}

input_is_key_pressed :: proc(key_code : Key) -> bool {

	if(!istate.process_user_inputs){
		return false;
	}

	// modstate : sdl.Keymod; // Modstate gives some info about CAPS, CTRL etc.

	// sdl.Keycode is just a u32 so we can just cast to it since our Key enum match with SDL Keycodes
	scancode : sdl.Scancode = sdl.GetScancodeFromKey(cast(sdl.Keycode)key_code, nil);
	return istate.keyboard_state[cast(int)scancode];
}

// ============================================================================================================================
// GAMEPAD

input_set_gamepad_added_callback :: proc(callback_proc : GamepadDeviceEvent_CallbackSignature){
	istate.gp_added_callback = callback_proc;
}

input_set_gamepad_removed_callback :: proc(callback_proc : GamepadDeviceEvent_CallbackSignature){
	istate.gp_removed_callback = callback_proc;
}

input_set_gamepad_remapped_callback :: proc(callback_proc : GamepadDeviceEvent_CallbackSignature){
	istate.gp_remapped_callback = callback_proc;
}



// GAMEPAD ANALOG
@(private="file")
input_internal_handle_gamepad_added :: proc(joystick_id : sdl.JoystickID){

	log.debugf("gamepad added");

	device_id: u32 = cast(u32)joystick_id;
	
	// Find a free spot to allocate a new GamepadState structure to track	
	// Note that we only support up to 4 atm.
	free_spot: i32 = -1;
	for i in 0..<4 {
		
		//log.debugf("handle added, i = {}, device_id {}, arr_inedx {}",i,istate.gp_ids[i].device_id, istate.gp_ids[i].array_index)
		
		if(istate.gp_ids[i].array_index == -1){

			free_spot = cast(i32)i;
			break;
		}
	}


	if(free_spot == -1){
		// 4 gamepads are already connected.
		log.errorf("To many gamepads connected: The Engine only supports up to 4 gamepads at one time.")
	}
	else {

		gp_state : GamepadAnalogState;
		append(&istate.gp_states, gp_state);
		
		istate.gp_ids[free_spot].device_id = device_id;
		istate.gp_ids[free_spot].array_index = cast(i32)len(istate.gp_states) -1;
	}

	// call user proc
	if(istate.gp_added_callback != nil){
		istate.gp_added_callback(device_id);
	}
}

@(private="file")
input_internal_handle_gamepad_removed :: proc(joystick_id : sdl.JoystickID){

	device_id: u32 = cast(u32)joystick_id;

	remove_index: i32 = -1;
	for i in 0..<4 {
		if(istate.gp_ids[i].device_id == device_id){
			remove_index = cast(i32)i;
			break;
		}
	}

	if remove_index == -1 {
		// @Note - fulcrum
		// this is kinda bad, device has been removed but we didn't even had it registered.
		// this could happen if it was a 5th gampad device and we only support 4 atm so in which case we don't care.
		// or maybe if there is something to remapping that changed device ids.? should prob look into that
	}else {

		ordered_remove(&istate.gp_states, int(remove_index));

		istate.gp_ids[remove_index].device_id = 0;
		istate.gp_ids[remove_index].array_index = -1;

		if(remove_index < 3){
			for i in (remove_index+1)..<4{
				istate.gp_ids[i].array_index -= 1;
			}
		}
	}

	// call user proc
	if(istate.gp_removed_callback != nil){
		istate.gp_removed_callback(device_id);
	}
}

@(private="file")
input_get_gamepad_analog_state_for_device_id :: proc(device_id: u32) -> ^GamepadAnalogState {

	for i in 0..<4{
		if(istate.gp_ids[i].device_id == device_id){
			return &istate.gp_states[istate.gp_ids[i].array_index];
		}
	}
	// @Note - Apparently this can fail if we dont receive an gamepad added event but sdl forwards gamepad events even
	// if it didn't tell us one was added during runtime..
	//engine_assert(false); // a wrong device id we havent registered....

	return nil;
}

@(private="file")
input_evaluate_gamepad_states_and_call_analog_callbacks :: proc(true_delta_seconds: f64){


	if(len(istate.gp_analog_callbacks) <= 0){
		return;
	}

	// @Note - Fuclrum
	// Constants for normalizing analog/axis gamepad inputs.
	// Analog gamepad inputs are received by SDL in the Range -32768..32767 as an int16
	_MAX ::  32767.0
	_MIN :: -32768.0
	_RANGE :: _MAX - _MIN
	_INV_RANGE2 :: 1.0 / _RANGE * 2.0
	_INV_MAX :: 1.0 / _MAX


	// @Note - Fulcrum
	// We receive gampad axis/analog events only if there was a change.
	// However we want to send out messages to all callbacks every frame if the axis is not in idle (currently being pressed).
	// It can be tricky though to determine when its not being pressed anymore because the last events we receive,
	// may likely not be perfect zero values, especially for the gamepad sticks.
	// To mitigate this we perform a gernal idle threshold (_IDLE_THRESHOLD) check for each event.
	// Under this value we just dont consider it any input.
	// For Triggers a rather small value seems to be sufficiant. For me, they mostly even report a zero as the last event.
	// For gamepad sticks we aditionally reevalute if its Idle when no events happend for some time.
	// This is because stick axis inputs can be much less precise and it might happen that the last event we receive 
	// is still with a fairly large value (I observed as much as 2000).
	// As I don't gernerally want to ignore stick inputs below such a large value and it's not even clear how large they may
	// be with for example not perfecly functioning sensors. I resort to using a time base fallback system.
	// So if no events are happening for extended time we check if its below a fairly large value,
	// and only then consider it idle and reset it.
	
	_IDLE_THRESHOLD :: 327 // normalized about 0.01
	_IDLE_THRESHOLD_STICK :: 3370 // normalized about 0.1

	_STICK_EVALUTATE_RESET_TIME :: 0.75 // in seconds

	for i in 0..<4 {
		
		if istate.gp_ids[i].array_index == -1 {
			continue;
		}

		device_id: u32 = istate.gp_ids[i].device_id;
		gp := input_get_gamepad_analog_state_for_device_id(device_id);

		if(gp == nil){
			continue;
		}

		// For each event that happend do a general Idle Threshold check
		for changed_analog_type in gp.event_happend_set {
			switch changed_analog_type {
				
				case .RIGHT_TRIGGER:					
					if gp.trigger_R < _IDLE_THRESHOLD {
						gp.trigger_R = 0;	
						gp.trigger_R_last = 0;	
					}

				case .LEFT_TRIGGER:
					if gp.trigger_L < _IDLE_THRESHOLD {
						gp.trigger_L = 0;	
						gp.trigger_L_last = 0;	
					}
				
				case .RIGHT_STICK:	

					gp.stick_R_sec_since_event = 0.0
					if abs(gp.stick_R.x) < _IDLE_THRESHOLD && abs(gp.stick_R.y) < _IDLE_THRESHOLD {
						gp.stick_R 		= {0,0};
						gp.stick_R_last = {0,0};
					}

				case .LEFT_STICK:
					gp.stick_L_sec_since_event = 0.0
					if abs(gp.stick_L.x) < _IDLE_THRESHOLD && abs(gp.stick_L.y) < _IDLE_THRESHOLD {
						gp.stick_L 		= {0,0};
						gp.stick_L_last = {0,0};
					}
			}
		}

		gp.event_happend_set = {}; // reset events happend 



		type: for analog_type in GamepadAnalog {

			value: [2]f32;
			delta: [2]f32;

			switch (analog_type) {
				
				case .RIGHT_TRIGGER:

					if gp.trigger_R == 0 {
						continue type;
					}

					delta_i: i16 = gp.trigger_R - gp.trigger_R_last;
					gp.trigger_R_last = gp.trigger_R;
					// Trigger input is given by SDL in range 0..32767
					// map to range 0..1
					delta.x = _INV_MAX * f32(delta_i);
					value.x = _INV_MAX * f32(gp.trigger_R);
				
				case .LEFT_TRIGGER:
					
					if gp.trigger_L == 0 {
						continue type;
					}

					delta_i : i16 = gp.trigger_L - gp.trigger_L_last;
					gp.trigger_L_last = gp.trigger_L;
					// Trigger input is given by SDL in range 0..32767
					// map to range 0..1
					delta.x = _INV_MAX * f32(delta_i);
					value.x = _INV_MAX * f32(gp.trigger_L);

				case .RIGHT_STICK:

					if gp.stick_R.x == 0 && gp.stick_R.y == 0 {
						continue type;
					}


					delta_i : [2]i16 = gp.stick_R - gp.stick_R_last;
					gp.stick_R_last = gp.stick_R;
					// Stick input is given by SDL in range -32768..32767
					// map to range -1..1
					delta = ([2]f32{f32(delta_i.x), f32(delta_i.y)} - _MIN) * _INV_RANGE2 -1.0;
					value = ([2]f32{f32(gp.stick_R.x), f32(gp.stick_R.y)} - _MIN) * _INV_RANGE2 -1.0;
					
					// If no events happend for some time, evaluate if stick is in Idle to reset it.
					// We do this before filling out 'value' and 'delta' so callbacks always receive 0 as last value
					gp.stick_R_sec_since_event += cast(f32)true_delta_seconds;
					if gp.stick_R_sec_since_event >= _STICK_EVALUTATE_RESET_TIME {

						if abs(gp.stick_R.x) < _IDLE_THRESHOLD_STICK && abs(gp.stick_R.y) < _IDLE_THRESHOLD_STICK {
							gp.stick_R = {0,0}
							gp.stick_R_last = {0,0}
							delta = {0.0,0.0};
							value = {0.0,0.0};
						}
						gp.stick_R_sec_since_event = 0.0;
					}

					

				case .LEFT_STICK:

					if gp.stick_L.x == 0 && gp.stick_L.y == 0 {
						continue type;
					}


					delta_i : [2]i16 = gp.stick_L - gp.stick_L_last;
					gp.stick_L_last = gp.stick_L;
					// Stick input is given by SDL in range -32768..32767
					// map to range -1..1
					delta = ([2]f32{f32(delta_i.x), f32(delta_i.y)} - _MIN) * _INV_RANGE2 - 1.0; 
					value = ([2]f32{f32(gp.stick_L.x), f32(gp.stick_L.y)} - _MIN) * _INV_RANGE2 - 1.0;
					
					// If no events happend for some time, evaluate if stick is in Idle to reset it.
					// We do this before filling out 'value' and 'delta' so callbacks always receive 0 as last value
					gp.stick_L_sec_since_event += cast(f32)true_delta_seconds;
					if gp.stick_L_sec_since_event >= _STICK_EVALUTATE_RESET_TIME {

						if abs(gp.stick_L.x) < _IDLE_THRESHOLD_STICK && abs(gp.stick_L.y) < _IDLE_THRESHOLD_STICK {
							gp.stick_L = {0,0}
							gp.stick_L_last = {0,0}
							delta = {0.0,0.0};
							value = {0.0,0.0};
						}

						gp.stick_L_sec_since_event = 0.0;
					}
			}


			for &entry in istate.gp_analog_callbacks {

				if entry.id >= 0 && entry.callback != nil {
					if entry.analog_type == analog_type {

						entry.callback(device_id, value, delta);
					}
				}
			}
		
		}
	}

}


input_register_gamepad_analog_callback :: proc(callback_proc: GamepadAnalog_CallbackSignature, analog_type: GamepadAnalog) -> i32 {

	if(callback_proc == nil){
		return -1;
	}

	entry_id : i32 = -1;

	// Look for an unused spot.
	for i in 0..<len(istate.gp_analog_callbacks){

		if(istate.gp_analog_callbacks[i].id == -1) {
			// We found an unused spot
			entry_id = cast(i32)i;
			break;
		}
	}

	// If we haven't found an empty spot. Id is equal to array size
	if(entry_id == -1){
		entry_id = cast(i32)len(istate.gp_analog_callbacks);
	}

	entry : GamepadAnalog_CallbackEntry = {
		id = entry_id,
		callback = callback_proc,
		analog_type = analog_type,
	}

	append(&istate.gp_analog_callbacks, entry);

	return entry.id;
}

input_unregister_gamepad_analog_callback :: proc(id : ^i32){

	if(id^ < 0) { // invalid id
		return;
	}

	for i in 0..<len(istate.gp_analog_callbacks){

		if(istate.gp_analog_callbacks[i].id == id^){
			// we found the id
			istate.gp_analog_callbacks[i].id = -1;
			istate.gp_analog_callbacks[i].callback = nil;
			id^ = -1; // invalidate the user id
			return;
		}
	}
}

// Gamepad Button
input_register_gamepad_button_callback :: proc(callback_proc: GamepadButton_CallbackSignature, button: GamepadButton, actions: GamepadButtonActionSet = {GamepadButtonAction.PRESS}) -> i32 {

	if(callback_proc == nil){
		return -1;
	}

	entry_id : i32 = -1;

	// Look for an unused spot.
	for i in 0..<len(istate.gp_button_callbacks){

		if(istate.gp_button_callbacks[i].id == -1) {
			// We found an unused spot
			entry_id = cast(i32)i;
			break;
		}
	}

	// If we haven't found an empty spot. Id is equal to array size
	if(entry_id == -1){
		entry_id = cast(i32)len(istate.gp_button_callbacks);
	}

	entry : GamepadButton_CallbackEntry = {
		id = entry_id,
		callback = callback_proc,
		btn = button,
		btn_actions = actions,
	}

	append(&istate.gp_button_callbacks, entry);

	return entry.id;
}


input_unregister_gamepad_button_callback :: proc(id : ^i32){

	if(id^ < 0) { // invalid id
		return;
	}

	for i in 0..<len(istate.gp_button_callbacks){

		if(istate.gp_button_callbacks[i].id == id^){
			// we found the id
			istate.gp_button_callbacks[i].id = -1;
			istate.gp_button_callbacks[i].callback = nil;
			id^ = -1; // invalidate the user id
			return;
		}
	}
}

@(private="file")
input_call_gamepad_button_callbacks :: proc(device_id: u32, button: GamepadButton, action: GamepadButtonAction, is_press : bool){

	// first we want to update the pressed buttons for the gamepad

	gp_state := input_get_gamepad_analog_state_for_device_id(device_id);
	if(gp_state != nil) {

		switch (action) {
			case .PRESS:
				gp_state.pressed_btns_set |= {button};
			case .RELEASE:
				gp_state.pressed_btns_set -= {button};
		}
	}

	for &entry in istate.gp_button_callbacks {

		if(entry.id >= 0 && entry.callback != nil){

			if(button != entry.btn || action not_in entry.btn_actions) {
				continue;
			}

			entry.callback(device_id, is_press);
		}
	}
}