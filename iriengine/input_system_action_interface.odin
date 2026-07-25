package iri

import "core:c"
import "core:math/linalg"
import "core:container/bit_array"
import sdl "vendor:sdl3"
import "base:runtime"

// Free all memory inside the input action and including the input 'input_action' 
input_action_free :: proc(input_action : ^InputAction){
	if input_action == nil {
		return;
	}
	input_action_free_contents(input_action);
	free(input_action);
}

// Free all memory inside the input action but not the 'input_action' pointer itself.
input_action_free_contents :: proc(input_action : ^InputAction) {
	delete(input_action.processors);
	delete(input_action.bindings);
	input_action.action_processors_count  = 0;
	input_action.action_processors_offset = 0;
}

input_binding_variant_create_2D_axis_composit_WASD :: proc(axis_to_value_op : AxisToValueOp = AxisToValueOp.Length) -> InputBindingVariant {
	return InputBinding2DAxisComposit {
		pos_y = InputBindingKeyboard{key = Key.W},
		neg_x = InputBindingKeyboard{key = Key.A},
		neg_y = InputBindingKeyboard{key = Key.S},
		pos_x = InputBindingKeyboard{key = Key.D},
		axis_to_value = axis_to_value_op,
	}
}

input_binding_variant_create_2D_axis_composit_ARROWS :: proc(axis_to_value_op : AxisToValueOp = AxisToValueOp.Length) -> InputBindingVariant {
	return InputBinding2DAxisComposit {
		pos_y = InputBindingKeyboard{key = Key.UP},
		neg_x = InputBindingKeyboard{key = Key.LEFT},
		neg_y = InputBindingKeyboard{key = Key.DOWN},
		pos_x = InputBindingKeyboard{key = Key.RIGHT},
		axis_to_value = axis_to_value_op,
	}
}

// Append a binding variant to the input_action with optional input conditon or input processors.
input_action_add_binding :: proc(input_action : ^InputAction, binding_variant : InputBindingVariant, condition : InputCondition = nil, processors : []InputProcessor = nil){
	engine_assert(input_action != nil);

	binding := InputBinding {
		variant = binding_variant,
		data = InputBindingProcessingData{ 
			input_condition = condition,
		}
	}

	if processors != nil && len(processors) > 0 {

		engine_assert(len(processors) < cast(int)c.UINT16_MAX, "InputSystem: A maximum of 65000 InputProcessor's are allowed per input binding.. What are you doing anyway?");
		engine_assert(len(input_action.processors) < cast(int)c.UINT16_MAX)

		offset : u16 = cast(u16)len(input_action.processors);
		count  : u16 = cast(u16)len(processors);

		append_elems(&input_action.processors, ..processors[:]);

		binding.data.processors_offset = offset;
		binding.data.processors_count  = count;
	}

	append(&input_action.bindings, binding);
}

// Remove a binding from the input_action given its array index.
input_action_remove_binding :: proc(input_action : ^InputAction, binding_index : int){
	
	if input_action == nil {
		return;
	}

	if binding_index < 0 || binding_index >= len(input_action.bindings){
		return;
	}

	binding := &input_action.bindings[binding_index];
	if binding.data.processors_count > 0 {
		
		input_action_binding_remove_processors(input_action, binding_index, cast(int)binding.data.processors_offset, cast(int)binding.data.processors_count);
	}

	ordered_remove(&input_action.bindings, binding_index);
}

// Append one or multiple processors to the input action.
input_action_add_processors :: proc(input_action : ^InputAction, processors : []InputProcessor) {

	if input_action == nil {
		return;
	}

	if processors == nil || len(processors) == 0 {
		return
	}

	add_count : int = len(processors);
	engine_assert(add_count < cast(int)c.UINT16_MAX);

	
	a_offset : int = cast(int)input_action.action_processors_offset;

	if input_action.action_processors_count == 0 {
		// The easy case where we can just append to the array.

		new_offset : int = len(input_action.processors);
		
		engine_assert(new_offset < cast(int)c.UINT16_MAX);

		input_action.action_processors_offset = cast(u16)new_offset;
		input_action.action_processors_count  = cast(u16)add_count;

		append_elems(&input_action.processors, ..processors[:])

		return;
	}

	
	prev_range_end : int = a_offset + cast(int)input_action.action_processors_count;


	inject_at_elems(&input_action.processors, prev_range_end, ..processors[:]);

	input_action.action_processors_count += cast(u16)add_count;

	for i in 0..<len(input_action.bindings) {
		bind := &input_action.bindings[i];
		if bind.data.processors_count > 0 {

			if int(bind.data.processors_offset) >= prev_range_end {
				
				engine_assert( ( cast(int)bind.data.processors_offset + add_count) < cast(int)c.UINT16_MAX);
				bind.data.processors_offset += cast(u16)add_count;
			}
		}
	}
}

// Remove a range of processors from a binding within the input action. The range should be absolute to the input_action.
input_action_remove_processors :: proc(input_action : ^InputAction, processor_remove_offset : int, processor_remove_count : int) {

	if input_action == nil {
		return;
	}

	curr_offset : int = cast(int)input_action.action_processors_offset;
	curr_count  : int = cast(int)input_action.action_processors_count;
	curr_end    : int = curr_offset + curr_count;

	if processor_remove_offset < curr_offset || processor_remove_offset >= curr_end {
		return;
	}

	if processor_remove_count > curr_count || processor_remove_count <= 0 {
		return;
	}

	prev_range_end : int = curr_count;

	// hi is exclusiv
	lo : int = processor_remove_offset;
	hi : int = processor_remove_offset + processor_remove_count;
	remove_range(&input_action.processors, lo, hi);


	input_action.action_processors_count -= cast(u16)processor_remove_count;
	if input_action.action_processors_count == 0 {
		input_action.action_processors_offset = 0; // reset.
	}

	for i in 0..<len(input_action.bindings) {

		bind := &input_action.bindings[i];
		
		if bind.data.processors_count > 0 {

			if int(bind.data.processors_offset) >= prev_range_end {
				
				bind.data.processors_offset -= cast(u16)processor_remove_count;
			}
		}
	}
}

// Swap two processors of an input_action. Swap indexes a and b should be absolute indexes into the actions processors array.
// This is usefull for when implementing a gui for input actions and reordering processors.
input_action_swap_processors :: proc(input_action : ^InputAction, swap_index_a : int, swap_index_b : int){

	// @Note: 
	// e.g.:
	//  swap_index_a = input_action.action_processors_offset
	//  swap_index_b = input_action.action_processors_offset + input_action.action_processors_count -1 
	//  -> this will swap the first and the last processor of this input action.
	// Swaping processors outside the actions processor range defined by 'action_processors_offset' and 'action_processors_count' will not work.

	if input_action == nil {
		return;
	}

	curr_offset : int = cast(int)input_action.action_processors_offset;
	curr_count  : int = cast(int)input_action.action_processors_count;
	curr_end    : int = curr_offset + curr_count;

	if curr_count == 0 {
		return;
	}

	// Validate indexes are in a valid range.
	if swap_index_a == swap_index_b {
		return;
	}

	if swap_index_a < curr_offset || swap_index_a >= curr_end {
		return;
	}

	if swap_index_b < curr_offset || swap_index_b >= curr_end {
		return;
	}

	input_action.processors[swap_index_a], input_action.processors[swap_index_b] = input_action.processors[swap_index_b], input_action.processors[swap_index_a];
}

// Append one or multiple processors to a binding within the input action.
input_action_binding_add_processors :: proc(input_action : ^InputAction, binding_index : int, processors : []InputProcessor) {

	if input_action == nil {
		return;
	}

	if processors == nil || len(processors) == 0 {
		return
	}

	if binding_index < 0 || binding_index >= len(input_action.bindings) {
		return;
	}

	add_count : int = len(processors);
	engine_assert(add_count < cast(int)c.UINT16_MAX);

	binding := &input_action.bindings[binding_index];
	
	b_offset : int = cast(int)binding.data.processors_offset;

	if binding.data.processors_count == 0 {
		// The easy case where we can just append to the array.

		new_offset : int = len(input_action.processors);
		
		engine_assert(new_offset < cast(int)c.UINT16_MAX);

		binding.data.processors_offset = cast(u16)new_offset;
		binding.data.processors_count  = cast(u16)add_count;

		append_elems(&input_action.processors, ..processors[:])

		return;
	}

	prev_range_end : int = b_offset + cast(int)binding.data.processors_count;

	inject_at_elems(&input_action.processors, prev_range_end, ..processors[:]);

	binding.data.processors_count += cast(u16)add_count;

	if int(input_action.action_processors_offset) >= prev_range_end {
		
		engine_assert( ( cast(int)input_action.action_processors_offset + add_count) < cast(int)c.UINT16_MAX);
		input_action.action_processors_offset += cast(u16)add_count;
	}

	for i in 0..<len(input_action.bindings) {
		bind := &input_action.bindings[i];
		if bind.data.processors_count > 0 {

			if int(bind.data.processors_offset) >= prev_range_end {
				
				engine_assert( (cast(int)bind.data.processors_offset + add_count) < cast(int)c.UINT16_MAX);
				bind.data.processors_offset += cast(u16)add_count;
			}
		}
	}
}

// Remove a range of processors from a binding within the input action. The range should be absolute to the input_action.
input_action_binding_remove_processors :: proc(input_action : ^InputAction, binding_index : int, processor_remove_offset : int, processor_remove_count : int) {

	if input_action == nil {
		return;
	}

	if binding_index < 0 || binding_index >= len(input_action.bindings) {
		return; // Invalid binding index.
	}

	binding := &input_action.bindings[binding_index];

	curr_offset : int = cast(int)binding.data.processors_offset;
	curr_count  : int = cast(int)binding.data.processors_count;
	curr_end    : int = curr_offset + curr_count;

	if processor_remove_offset < curr_offset || processor_remove_offset >= curr_end {
		return;
	}

	if processor_remove_count > curr_count || processor_remove_count <= 0 {
		return;
	}

	prev_range_end : int = curr_count;

	// hi is exclusiv
	lo : int = processor_remove_offset;
	hi : int = processor_remove_offset + processor_remove_count;
	runtime.remove_range(&input_action.processors, lo, hi);


	binding.data.processors_count -= cast(u16)processor_remove_count;
	if binding.data.processors_count == 0 {
		binding.data.processors_offset = 0; // reset.
	}


	if input_action.action_processors_count > 0 && cast(int)input_action.action_processors_offset >= prev_range_end {
		
		input_action.action_processors_offset -= cast(u16)processor_remove_count;
	}

	for i in 0..<len(input_action.bindings) {

		bind := &input_action.bindings[i];
		
		if bind.data.processors_count > 0 {

			if int(bind.data.processors_offset) >= prev_range_end {
				
				bind.data.processors_offset -= cast(u16)processor_remove_count;
			}
		}
	}
}

// Swap two processors of an input binding. Swap indexes a and b should be absolute indexes into the actions processors array.
// This is usefull for when implementing a gui for input actions and reordering processors.
input_action_binding_swap_processors :: proc(input_action : ^InputAction, binding_index : int, swap_index_a : int, swap_index_b : int){

	// @Note: 
	// e.g.:
	//  binding := &input_action.bindings[binding_index];
	//  swap_index_a = binding.data.processors_offset
	//  swap_index_b = binding.data.processors_offset + binding.data.processors_count -1 
	//  -> this will swap the first and the last processor of this input binding.
	// Swaping processors outside the actions processor range defined by 'processors_offset' and 'processors_count' will not work.

	if input_action == nil {
		return;
	}

	if binding_index < 0 || binding_index >= len(input_action.bindings) {
		return; // Invalid binding index.
	}

	binding := &input_action.bindings[binding_index];

	curr_offset : int = cast(int)binding.data.processors_offset;
	curr_count  : int = cast(int)binding.data.processors_count;
	curr_end    : int = curr_offset + curr_count;

	if curr_count == 0 {
		return;
	}

	// Validate indexes are in a valid range.
	if swap_index_a == swap_index_b {
		return;
	}

	if swap_index_a < curr_offset || swap_index_a >= curr_end {
		return;
	}

	if swap_index_b < curr_offset || swap_index_b >= curr_end {
		return;
	}

	input_action.processors[swap_index_a], input_action.processors[swap_index_b] = input_action.processors[swap_index_b], input_action.processors[swap_index_a];
}


// ==============================================
// ---- Input Polling ---------------------------
// ==============================================


// Poll the input action for butten events. This works even for value driven inputs like mouse wheel or Gamepad Triggers/Sticks.
// In value driven cases we consider the provided 'analog_press_threshold' to determine if the current input should be considered as a press or not.
// In case of 2D axis inputs (Mouse Delta or Gamepad Sticks) we convert them to a single value first using the 'AxisToValueOp' of the binding.
// @Note: InputBinding2DAxisComposit and InputBinding1DAxisComposit can only trigger IsPressed or IsReleased Events because last frames state is not stored for these bindings.
// @Note: MousePosition binding uses mouse Delta to determine if mouse has moved and should register press events. 
//        Otherwise this would be useless and always return just return IsPressed. 
// 		  Further note that polling for mouse position or delta as button is really only usefull to get notified if mouse has moved 
//		  and IsPressed/WasPressed behaves basically the same.
input_action_poll_as_button :: proc(input_action : ^InputAction, press_events : PressEventFlags, analog_press_threshold : f32 = 0.1, ctx : ^InputContext = nil) -> PressResult {

	engine_assert(input_action != nil);
	
	if input_action.is_disabled {
		return PressResult{};
	}

	input_sys := engine.input_system;
	if !input_sys.process_user_inputs {

		return PressResult{};
	}

	loop: for binding in input_action.bindings {

		switch &variant in binding.variant {
			case InputBindingKeyboard: {
				if res := input_keyboard(variant.key, press_events, binding.data.input_condition, ctx); res.triggered {
					return res;
				}
			}
			case InputBindingMouseButton: {
				if res := input_mouse_button(variant.btn, press_events, binding.data.input_condition, ctx); res.triggered {
					return res;
				}
			}
			case InputBindingMouseWheel: {				

				if !input_is_condition_satisfied(binding.data.input_condition, ctx) {
					continue loop;
				}

				wheel_now  : f32 = abs(input_apply_axis_to_value_op(input_sys.mouse_wheel_now , variant.axis_to_value).x);
				wheel_last : f32 = abs(input_apply_axis_to_value_op(input_sys.mouse_wheel_last, variant.axis_to_value).x);

				is_down_now   : bool = wheel_now  > analog_press_threshold;
				was_down_last : bool = wheel_last > analog_press_threshold;

				wheel_press_flags : PressEventFlags;
				wheel_press_flags += is_down_now ? {.IsPressed} : {.IsReleased};

				if is_down_now && !was_down_last {
					wheel_press_flags += {.WasPressed};
				}
				if !is_down_now && was_down_last {
					wheel_press_flags += {.WasReleased};
				}

				triggered : bool = (wheel_press_flags & press_events) != PressEventFlags{};
				if triggered {
					return PressResult{
						triggered = true,
						is_down = is_down_now,
					}
				}
			}
			case InputBindingMousePosition: {

				if !input_is_condition_satisfied(binding.data.input_condition, ctx) {
					continue loop;
				}

				// @Note: we use mouse DELTA here because postion doesn't make sense.
				delta_val_now  : f32 = input_apply_axis_to_value_op(input_sys.mouse_delta     , variant.axis_to_value).x;
				delta_val_last : f32 = input_apply_axis_to_value_op(input_sys.mouse_delta_last, variant.axis_to_value).x;

				is_down_now   : bool = delta_val_now  > analog_press_threshold;
				was_down_last : bool = delta_val_last > analog_press_threshold;

				delta_press_flags : PressEventFlags;
				delta_press_flags += is_down_now ? {.IsPressed} : {.IsReleased};

				if is_down_now && !was_down_last {
					delta_press_flags += {.WasPressed};
				}
				if !is_down_now && was_down_last {
					delta_press_flags += {.WasReleased};
				}

				triggered : bool = (delta_press_flags & press_events) != PressEventFlags{};
				if triggered {
					return PressResult{
						triggered = true,
						is_down = is_down_now,
					}
				}
			}
			case InputBindingMouseDelta: {
				
				if !input_is_condition_satisfied(binding.data.input_condition, ctx) {
					continue loop;
				}

				delta_val_now  : f32 = input_apply_axis_to_value_op(input_sys.mouse_delta     , variant.axis_to_value).x;
				delta_val_last : f32 = input_apply_axis_to_value_op(input_sys.mouse_delta_last, variant.axis_to_value).x;

				is_down_now   : bool = delta_val_now  > analog_press_threshold;
				was_down_last : bool = delta_val_last > analog_press_threshold;

				delta_press_flags : PressEventFlags;
				delta_press_flags += is_down_now ? {.IsPressed} : {.IsReleased};

				if is_down_now && !was_down_last {
					delta_press_flags += {.WasPressed};
				}
				if !is_down_now && was_down_last {
					delta_press_flags += {.WasReleased};
				}

				triggered : bool = (delta_press_flags & press_events) != PressEventFlags{};
				if triggered {
					return PressResult{
						triggered = true,
						is_down = is_down_now,
					}
				}
			}
			case InputBindingGamepadButton: {
				if res := input_gamepad_button(variant.btn, press_events, binding.data.input_condition, ctx); res.triggered {
					return res;
				}
			}
			case InputBindingGamepadAnalog: {
				if res := input_gamepad_analog_as_button(variant.analog, press_events, variant.axis_to_value, analog_press_threshold, binding.data.input_condition, ctx); res.triggered {
					return res;
				}
			}
			case InputBinding1DAxisComposit: {

				if !input_is_condition_satisfied(binding.data.input_condition, ctx) {
					continue loop;
				}

				// @Note: we can only support IsPresssed or IsReleased events here.
				axis_1d : f32;

				if vals, triggered := input_action_binding_evaluate_internal(input_sys, input_action, ctx, variant, binding.data, as_single_value = true); triggered {
					axis_1d = vals.x;	
				}

				
				is_down_now : bool = abs(axis_1d) > analog_press_threshold;
				this_press_flags : PressEventFlags = is_down_now ? {.IsPressed} : {.IsReleased};

				triggered : bool = (this_press_flags & press_events) != PressEventFlags{};
				if triggered {
					return PressResult{
						triggered = true,
						is_down = is_down_now,
					}
				}
			}
			case InputBinding2DAxisComposit: {
				// @Note: we can only support IsPresssed or IsReleased events here.				
				
				if !input_is_condition_satisfied(binding.data.input_condition, ctx) {
					continue loop;
				}

				axis : [2]f32;
				if vals, triggered := input_action_binding_evaluate_internal(input_sys, input_action, ctx, variant, binding.data, as_single_value = true); triggered {
					axis = vals;	
				}
				
				is_down_now : bool = abs(axis.x) > analog_press_threshold || abs(axis.y) > analog_press_threshold;
				this_press_flags : PressEventFlags = is_down_now ? {.IsPressed} : {.IsReleased};

				triggered : bool = (this_press_flags & press_events) != PressEventFlags{};
				if triggered {
					return PressResult{
						triggered = true,
						is_down = is_down_now,
					}
				}
			}
			case: continue;
		}
	}

	return PressResult{};
}

// Poll the input_action for a single value. Binary Buttons/Keys return 0 when not pressed and 1.0 if pressed.
// 2D Axis bindings such as Gampad Sticks are converted from 2D to 1D using the 'AxisToValueOp' for the binding.
input_action_poll_as_value :: proc(input_action : ^InputAction, ctx : ^InputContext = nil) -> f32 {

	engine_assert(input_action != nil);
	
	
	if input_action.is_disabled {
		return 0.0;
	}

	input_sys := engine.input_system;

	if !input_sys.process_user_inputs {
		return 0.0;
	}

	loop: for &binding in input_action.bindings {
		if values, was_triggered := input_action_binding_evaluate_internal(input_sys, input_action, ctx, binding.variant, binding.data, as_single_value = false); was_triggered {	
	 		processed := input_action_apply_input_processors(input_action, values, input_action.action_processors_offset, input_action.action_processors_count);
	 		return processed.x;
		}
	}

	return 0.0;
}


// Same as input_action_poll_value() but 2D axis bindings are not converted to a single value and are instead returned as such.
// Anything that doesn't have a second axis is returned in the X Component and Y will be 0.
input_action_poll_as_2D_axis :: proc(input_action : ^InputAction, ctx : ^InputContext = nil) -> [2]f32 {

	engine_assert(input_action != nil);
	
	
	if input_action.is_disabled {
		return [2]f32{0.0,0.0};
	}

	input_sys := engine.input_system;
	if !input_sys.process_user_inputs {
		return [2]f32{0.0,0.0};
	}

	loop: for &binding in input_action.bindings {

		//binding_internal : InputBindingInternal = #force_inline input_binding_to_binding_internal(binding);
		if values, was_triggered := input_action_binding_evaluate_internal(input_sys, input_action, ctx, binding.variant, binding.data, as_single_value = false); was_triggered {
	 		return input_action_apply_input_processors(input_action, values, input_action.action_processors_offset, input_action.action_processors_count);
		}
	}

	return [2]f32{0.0,0.0};
}


// Internal evaluation procedure.
@(private="package")
input_action_binding_evaluate_internal :: proc(input_sys : ^InputSystem, input_action : ^InputAction, ctx : ^InputContext, binding_variant : InputBindingVariant, binding_data : InputBindingProcessingData, as_single_value : bool) -> (values : [2]f32, was_triggered : bool) {
	
	raw_values : [2]f32;

	switch &variant in binding_variant {
		case InputBindingKeyboard: {

			if !input_is_condition_satisfied(binding_data.input_condition, ctx) {
				return;
			}

			scancode : sdl.Scancode = sdl.GetScancodeFromKey(cast(sdl.Keycode)variant.key, nil);
			is_down, ok:= bit_array.get(&input_sys.keyboard_state_now, cast(uint)scancode);
			if is_down {
				raw_values.x = 1.0;
				processed : [2]f32 = input_action_apply_input_processors(input_action, raw_values, binding_data.processors_offset, binding_data.processors_count);
				return processed, true;
			}
		}
		case InputBindingMouseButton: {
			if !input_is_condition_satisfied(binding_data.input_condition, ctx) {
				return;
			}

			is_down : bool = .IsPressed in input_sys.mouse_btn_curr_press_events[variant.btn];
			if is_down {
				raw_values.x = 1.0;
				processed : [2]f32 = input_action_apply_input_processors(input_action, raw_values, binding_data.processors_offset, binding_data.processors_count);
				return processed, true;				
			}
		}
		case InputBindingMouseWheel: {
			if !input_is_condition_satisfied(binding_data.input_condition, ctx) {
				return;
			}
			
			raw_values : [2]f32 = input_sys.mouse_wheel_now;

			if as_single_value {
				raw_values = input_apply_axis_to_value_op(raw_values, variant.axis_to_value);
			}

			if abs(raw_values.x) > 0.0 || abs(raw_values.y) > 0.0 {
				processed : [2]f32 = input_action_apply_input_processors(input_action, raw_values, binding_data.processors_offset, binding_data.processors_count);
				return processed, true;
			}
		}
		case InputBindingMousePosition: {
			
			if !input_is_condition_satisfied(binding_data.input_condition, ctx) {
				return;
			}

			raw_values : [2]f32 = input_sys.relative_mouse_pos;
			if as_single_value {
				raw_values = input_apply_axis_to_value_op(raw_values, variant.axis_to_value);
			}
			
			if abs(input_sys.mouse_delta.x) > 0.0 || abs(input_sys.mouse_delta.y) > 0.0 {
				processed : [2]f32 = input_action_apply_input_processors(input_action, raw_values, binding_data.processors_offset, binding_data.processors_count);
				return processed, true;
			}
		}
		case InputBindingMouseDelta: {
			if !input_is_condition_satisfied(binding_data.input_condition, ctx) {
				return;
			}

			raw_values : [2]f32 = input_sys.mouse_delta;
			
			if as_single_value {
				raw_values = input_apply_axis_to_value_op(raw_values, variant.axis_to_value);
			}

			if abs(raw_values.x) > 0.0 || abs(raw_values.y) > 0.0 {
				processed : [2]f32 = input_action_apply_input_processors(input_action, raw_values, binding_data.processors_offset, binding_data.processors_count);
				return processed, true;
			}
		}
		case InputBindingGamepadButton: {
			
			is_down := input_gamepad_button(variant.btn, {.IsPressed}, binding_data.input_condition, ctx).triggered;
			if is_down {
				raw_values.x = 1.0;
				processed : [2]f32 = input_action_apply_input_processors(input_action, raw_values, binding_data.processors_offset, binding_data.processors_count);
				return processed, true;	
			}
		}
		case InputBindingGamepadAnalog: {
			
			raw_values : [2]f32 = input_gamepad_analog(variant.analog, binding_data.input_condition, ctx);
			if as_single_value {
				raw_values = input_apply_axis_to_value_op(raw_values, variant.axis_to_value);
			}

			if abs(raw_values.x) > 0.0 || abs(raw_values.y) > 0.0 {
				processed : [2]f32 = input_action_apply_input_processors(input_action, raw_values, binding_data.processors_offset, binding_data.processors_count);
				return processed, true;
			}
		}
		case InputBinding1DAxisComposit: {
			
			if !input_is_condition_satisfied(binding_data.input_condition, ctx) {
				return;
			}
			
			// positive X
			if vals, triggered := input_action_binding_evaluate_internal(input_sys, input_action, ctx, input_binding_composable_to_variant(variant.pos_x), InputBindingProcessingData{}, as_single_value = true); triggered {
				raw_values.x += vals.x;
			}
			// negative X
			if vals, triggered := input_action_binding_evaluate_internal(input_sys, input_action, ctx, input_binding_composable_to_variant(variant.neg_x), InputBindingProcessingData{}, as_single_value = true); triggered {
				raw_values.x -= vals.x;
			}

			if abs(raw_values.x) > 0.0 {
				processed : [2]f32 = input_action_apply_input_processors(input_action, raw_values, binding_data.processors_offset, binding_data.processors_count);
				return processed, true;
			}
		}
		case InputBinding2DAxisComposit: {
			
			if !input_is_condition_satisfied(binding_data.input_condition, ctx) {
				return;
			}

			// Positive X
			if vals, triggered := input_action_binding_evaluate_internal(input_sys, input_action, ctx, input_binding_composable_to_variant(variant.pos_x), InputBindingProcessingData{}, as_single_value = true); triggered {
				raw_values.x += vals.x;
			}
			// Negative X
			if vals, triggered := input_action_binding_evaluate_internal(input_sys, input_action, ctx, input_binding_composable_to_variant(variant.neg_x), InputBindingProcessingData{}, as_single_value = true); triggered {
				raw_values.x -= vals.x;
			}

			// Positive Y
			if vals, triggered := input_action_binding_evaluate_internal(input_sys, input_action, ctx, input_binding_composable_to_variant(variant.pos_y), InputBindingProcessingData{}, as_single_value = true); triggered {
				raw_values.y += vals.x;
			}
			// Negative Y
			if vals, triggered := input_action_binding_evaluate_internal(input_sys, input_action, ctx, input_binding_composable_to_variant(variant.neg_y), InputBindingProcessingData{}, as_single_value = true); triggered {
				raw_values.y -= vals.x;
			}

			if as_single_value {
				raw_values = input_apply_axis_to_value_op(raw_values, variant.axis_to_value);
			}

			if abs(raw_values.x) > 0.0 || abs(raw_values.y) > 0.0 {
				processed : [2]f32 = input_action_apply_input_processors(input_action, raw_values, binding_data.processors_offset, binding_data.processors_count);
				return processed, true;
			}
		}
		case:;
	}

	return [2]f32{0.0, 0.0}, false;
}


// ==============================================
// ---- Input Processing ---------------------------
// ==============================================

// @Note: This happens automatically when polling. You dont need to use this manually.

// Internal input processing procedure.
// This does Not apply input processors of the input_action only those of the bindings.
@(private="package")
input_action_apply_input_processors :: proc(input_action : ^InputAction, in_values : [2]f32, offset : u16, count : u16) -> [2]f32 {

	if count == 0 {
		return in_values;
	}

	start : u32 = u32(offset);
	end   : u32 = u32(offset) + u32(count);

	engine_assert(start <  cast(u32)len(input_action.processors));
	engine_assert(end   <= cast(u32)len(input_action.processors));

	out_values : [2]f32 = in_values;

	for i in start..<end {
		processor := &input_action.processors[i];

		switch &variant in processor {
			case InputProcessorClamp: {
				switch variant.axis_mask {
					case .Both:   out_values   = linalg.clamp(out_values, variant.min, variant.max);
					case .Only_X: out_values.x = clamp(out_values.x, variant.min, variant.max);
					case .Only_Y: out_values.y = clamp(out_values.y, variant.min, variant.max);;
				}
			}
			case InputProcessorMultiply: {
				switch variant.axis_mask {
					case .Both:   out_values   *= variant.scalar;
					case .Only_X: out_values.x *= variant.scalar;
					case .Only_Y: out_values.y *= variant.scalar;
				}
			}
			case InputProcessorDivide: {
				switch variant.axis_mask {
					case .Both:   out_values   /= variant.denominator;
					case .Only_X: out_values.x /= variant.denominator;
					case .Only_Y: out_values.y /= variant.denominator;
				}
			}
			case InputProcessorNormalizeAxis: out_values = linalg.normalize(out_values);
			case: continue;
		}
	}

	return out_values;
}

