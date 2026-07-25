package iri

// Which axis should be returned/considered when polling for a single value.
// This applies when using input_action_poll_value or input_action_poll_button on anything that is considered a 2D axis.
AxisToValueOp :: enum u8 {
	Use_X,
	Use_Y,
	Length,
}

InputBindingKeyboard    :: struct {
	key : Key 
}
InputBindingMouseButton :: struct {
	btn : MouseButton
}
InputBindingMouseWheel  :: struct {
	// The normal mouse wheel is horizontal so most likely you want this to be set to 'Use_Y'
	axis_to_value : AxisToValueOp, 
}
InputBindingMousePosition :: struct {
	axis_to_value    : AxisToValueOp
}
InputBindingMouseDelta    :: struct {
	axis_to_value : AxisToValueOp
}
InputBindingGamepadButton :: struct {
	btn : GamepadButton
}
InputBindingGamepadAnalog :: struct {
	analog : GamepadAnalog,
	axis_to_value : AxisToValueOp,
}


InputBindingComposable :: union {
	InputBindingKeyboard,
	InputBindingMouseButton,
	InputBindingMouseWheel,
	InputBindingMousePosition,
	InputBindingMouseDelta,
	InputBindingGamepadButton,
	InputBindingGamepadAnalog,
}

InputBinding1DAxisComposit :: struct {
	neg_x : InputBindingComposable,
	pos_x : InputBindingComposable,
}

InputBinding2DAxisComposit :: struct {
	neg_x : InputBindingComposable,
	pos_x : InputBindingComposable,
	neg_y : InputBindingComposable,
	pos_y : InputBindingComposable,
	axis_to_value : AxisToValueOp,
}

InputBindingType :: enum {
	None = 0,
	Keyboard,
	MouseButton,
	MouseWheel,
	MousePosition,
	MouseDelta,
	GamepadButton,
	GamepadAnalog,
	Axis1DComposit,
	Axis2DComposit,
}

InputBindingVariant :: union {
	// RawDevice/Composable
	InputBindingKeyboard,
	InputBindingMouseButton,
	InputBindingMouseWheel,
	InputBindingMousePosition,
	InputBindingMouseDelta,
	InputBindingGamepadButton,
	InputBindingGamepadAnalog,
	// Composits
	InputBinding1DAxisComposit,
	InputBinding2DAxisComposit,
}

InputBindingProcessingData :: struct {
	processors_count  : u16,
	processors_offset : u16,
	input_condition   : InputCondition,
}

InputBinding :: struct {
	variant : InputBindingVariant,
	data    : InputBindingProcessingData,
}


InputAction :: struct {
	
	bindings   : [dynamic]InputBinding,
	processors : [dynamic]InputProcessor,
	input_condition : InputCondition,
	action_processors_offset : u16,
	action_processors_count  : u16,

	is_disabled 	 : bool,
}

AxisMask :: enum u8 {
	Both,
	Only_X,
	Only_Y,
}

InputProcessorClamp :: struct {
	min : f32,
	max : f32,
	axis_mask   : AxisMask, // which axis to apply the clamping to.
}

InputProcessorMultiply :: struct {
	scalar : f32,
	axis_mask   : AxisMask, // which axis to apply the multiply to.
}

InputProcessorDivide :: struct {
	denominator : f32,
	axis_mask   : AxisMask, // which axis to apply the division to.
}

InputProcessorNormalizeAxis :: struct {
	// Applies always to 2D axis.
	_ : f32,
}

InputProcessor :: union {
	InputProcessorClamp,
	InputProcessorMultiply,
	InputProcessorDivide,
	InputProcessorNormalizeAxis,
}

InputProcessorType :: enum {
	None = 0,
	Clamp,
	Multiply,
	Divide,
	NormalizeAxis,
}
