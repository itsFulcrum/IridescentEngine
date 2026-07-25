package iri

SDLEvent_CallbackEntry :: struct {
	id : InputID,
	callback: SDLEvent_CallbackSignature,
}

MouseButton_CallbackEntry :: struct {
	id 			 : InputID,
	callback 	 : MouseButton_CallbackSignature,
	mouse_button : MouseButton,
	press_flags  : PressEventFlags,
}

MouseWheel_CallbackEntry :: struct {
	id : InputID,
	callback : MouseWheel_CallbackSignature,
}

MouseMotion_CallbackEntry :: struct {
	id : InputID,
	callback : MouseMotion_CallbackSignature,
}

Keyboard_CallbackEntry :: struct {
	id : InputID,
	callback    : Keyboard_CallbackSignature,
	key_code    : Key,
	press_flags  : PressEventFlags,
	key_mods    : KeymodFlags,
}

GamepadAnalog_CallbackEntry :: struct {
	id: InputID,
	callback: GamepadAnalog_CallbackSignature,
	analog_type: GamepadAnalog,
}

GamepadButton_CallbackEntry :: struct {
	id: InputID,
	callback: GamepadButton_CallbackSignature,
	btn: GamepadButton,
	press_flags  : PressEventFlags,
}

GamepadState :: struct {
	trigger_R: 		i16,
	trigger_R_last: i16,
	trigger_R_normalized_01 : f32,
	
	trigger_L: 		i16,
	trigger_L_last: i16,
	trigger_L_normalized_01 : f32,
	

	stick_R: 		[2]i16,
	stick_R_last: 	[2]i16,
	stick_R_sec_since_event: f32, // when stick is not idle (0,0) we track time since last event to reevaluate if its idle now
	stick_R_normalized : [2]f32, // -1..1 range

	stick_L: 		[2]i16,
	stick_L_last: 	[2]i16,
	stick_L_sec_since_event: f32, // when stick is not idle (0,0) we track time since last event to reevaluate if its idle now
	stick_L_normalized : [2]f32, // -1..1 range
	
	event_happend_set: GamepadAnalogFlags, // The set of Analog/Axis events that occured this frame for this gamepad. Must be reset every frame.
	
	pressed_btns_now :  GamepadButtonFlags, // A set to keep track of which buttons ar currently pressed.
	pressed_btns_last:  GamepadButtonFlags, // A set to keep track of which buttons ar currently pressed.
}