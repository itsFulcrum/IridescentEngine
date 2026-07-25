package iri

import "core:math/linalg"
import sdl "vendor:sdl3"

@(private="package")
mouse_button_to_sdl_mouse_button_flag :: #force_inline proc(mouse_button : MouseButton) -> sdl.MouseButtonFlag {
	
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


// Apply the axis_to_value_op on the axis value and return it in the x component while y will be 0.0.
@(private="package")
input_apply_axis_to_value_op :: #force_inline proc(axis : [2]f32, op : AxisToValueOp) -> [2]f32 {
	
	switch op {
		case AxisToValueOp.Use_X:  return [2]f32{axis.x, 0.0}
		case AxisToValueOp.Use_Y:  return [2]f32{axis.y, 0.0}
		case AxisToValueOp.Length: return [2]f32{linalg.length(axis), 0.0};
	}

	return [2]f32{axis.x, 0.0};
}

@(private="package")
input_binding_composable_to_variant :: proc(input_binding : InputBindingComposable) -> InputBindingVariant {
		
	switch v in input_binding {
		case InputBindingKeyboard:      return v;
		case InputBindingMouseButton:	return v;
		case InputBindingMouseWheel:	return v;
		case InputBindingMousePosition:	return v;
		case InputBindingMouseDelta:	return v;
		case InputBindingGamepadButton:	return v;
		case InputBindingGamepadAnalog: return v;
		case: return nil;
	}

	return nil;
}

input_binding_variant_to_type :: proc(binding_variant : InputBindingVariant) -> InputBindingType {
	
	switch v in binding_variant {
		case InputBindingKeyboard:       return InputBindingType.Keyboard;
		case InputBindingMouseButton:	 return InputBindingType.MouseButton;
		case InputBindingMouseWheel:	 return InputBindingType.MouseWheel;
		case InputBindingMousePosition:	 return InputBindingType.MousePosition;
		case InputBindingMouseDelta:	 return InputBindingType.MouseDelta;
		case InputBindingGamepadButton:	 return InputBindingType.GamepadButton;
		case InputBindingGamepadAnalog:  return InputBindingType.GamepadAnalog;
		case InputBinding1DAxisComposit: return InputBindingType.Axis1DComposit;
		case InputBinding2DAxisComposit: return InputBindingType.Axis2DComposit;
		case: return .None;
	}

	return InputBindingType.None;
}

input_binding_composable_to_type :: proc(binding_variant : InputBindingComposable) -> InputBindingType {
	
	switch v in binding_variant {
		case InputBindingKeyboard:       return InputBindingType.Keyboard;
		case InputBindingMouseButton:	 return InputBindingType.MouseButton;
		case InputBindingMouseWheel:	 return InputBindingType.MouseWheel;
		case InputBindingMousePosition:	 return InputBindingType.MousePosition;
		case InputBindingMouseDelta:	 return InputBindingType.MouseDelta;
		case InputBindingGamepadButton:	 return InputBindingType.GamepadButton;
		case InputBindingGamepadAnalog:  return InputBindingType.GamepadAnalog;
		case: return .None;
	}

	return InputBindingType.None;
}

input_condition_to_type :: proc(condition : InputCondition) -> InputConditionType {
	
	switch v in condition {
		case KeymodFlags:       	return InputConditionType.Keyboard;
		case MouseButtonFlags:	 	return InputConditionType.Mouse;
		case GamepadButtonFlags: 	return InputConditionType.Gamepad;
		case: return .None;
	}

	return InputConditionType.None;
}

input_processor_to_type :: proc(processor : InputProcessor) -> InputProcessorType {
	
	switch v in processor {
		case InputProcessorClamp:       	return InputProcessorType.Clamp;
		case InputProcessorMultiply:	 	return InputProcessorType.Multiply;
		case InputProcessorDivide: 			return InputProcessorType.Divide;
		case InputProcessorNormalizeAxis: 	return InputProcessorType.NormalizeAxis;
		case: return .None;
	}

	return InputProcessorType.None;
}

