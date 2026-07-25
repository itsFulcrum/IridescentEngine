package iriedit

import iri "../iriengine"

import im "odinary:dear_imguy"


draw_gui_input_action :: proc(input_action : ^iri.InputAction){

	if input_action == nil {
		return;
	}

	@static selected_binding : int = -1;

	tree_flags_def_open := im.TreeNodeFlags{.DefaultOpen};

	// main subwindow
	{
		im.BeginChild("InputAction",{0, 0}, {.Borders, .ResizeX})
		defer im.EndChild();
		

		im.Text("Input Action");
		im.Checkbox("Disabled ##IA", &input_action.is_disabled);
		
		tree_flags := im.TreeNodeFlags{.AllowOverlap, .DefaultOpen};

		if im.TreeNodeEx("Bindings##IA", tree_flags) {
			defer im.TreePop();
			
			if im.BeginPopupContextItem("##BindingsMenu") {
				defer im.EndPopup();

				if im.Selectable("Add Binding") {
					iri.input_action_add_binding(input_action, nil);
				}
				if im.Selectable("Add WASD Keys Axis Composit") {
					wasd_axis_variant := iri.input_binding_variant_create_2D_axis_composit_WASD();					
					iri.input_action_add_binding(input_action, wasd_axis_variant);
				}
				if im.Selectable("Add ARROW Keys Axis Composit") {
					arrows_axis_variant := iri.input_binding_variant_create_2D_axis_composit_ARROWS();
					iri.input_action_add_binding(input_action, arrows_axis_variant);
				}
			}

			bind_loop: for i in 0..<len(input_action.bindings) {
				binding := &input_action.bindings[i];

				variant_type : iri.InputBindingType = iri.input_binding_variant_to_type(binding.variant);
				variant_type_cstr := fmt_cstr("Binding: {}##{}", variant_type,i);

				if im.Selectable(variant_type_cstr) {
					selected_binding = i;
				}
				
				if im.BeginPopupContextItem(fmt_cstr("BindingSubmenu##{}",i)) {
					defer im.EndPopup();

					if im.Selectable(fmt_cstr("Remove Binding##{}",i)) {
						iri.input_action_remove_binding(input_action, i);
						break bind_loop;
					}
				}
			}
		}

		im.Spacing();
		im.Separator();
		draw_gui_input_condition(&input_action.input_condition);

		im.Spacing();
		im.Separator();

		draw_gui_input_action_processors(input_action, use_action = true, binding_index = -1);


	}
	size := im.GetItemRectSize();

	im.SameLine();

	valid_binding : bool = selected_binding >= 0 && selected_binding < len(input_action.bindings);
	

	if valid_binding {

		child_flags := im.ChildFlags{.Borders};

		im.BeginChild("Bindings", {0.0, size.y}, child_flags)
		defer im.EndChild();

		im.Text("Edit Binding");

		binding := &input_action.bindings[selected_binding];

		draw_gui_input_binding_variant(&binding.variant);


		im.Spacing();
		im.Separator();

		draw_gui_input_condition(&binding.data.input_condition);

		im.Spacing();
		im.Separator();


		draw_gui_input_action_processors(input_action, use_action = false, binding_index = selected_binding);

	}

}

draw_gui_input_condition :: proc(input_condition : ^iri.InputCondition) {

	if input_condition == nil {
		return;
	}

	curr_condition_type : iri.InputConditionType = iri.input_condition_to_type(input_condition^);
	curr_condition_type_cstr := fmt_cstr("{}", curr_condition_type);
	
	im.SetNextItemWidth(80)
	if new_type, selected := enum_combo("Input Condition", curr_condition_type_cstr, iri.InputConditionType); selected {
		if new_type != curr_condition_type {
			switch new_type {
				case iri.InputConditionType.None: 	  input_condition^ = nil;
				case iri.InputConditionType.Keyboard: input_condition^ = iri.KeymodFlags{};
				case iri.InputConditionType.Mouse:    input_condition^ = iri.MouseButtonFlags{};
				case iri.InputConditionType.Gamepad:  input_condition^ = iri.GamepadButtonFlags{};
			}
			curr_condition_type = new_type;
		}
	}

	if curr_condition_type != .None {
		if im.TreeNodeEx("Conditions##IA", im.TreeNodeFlags{.DefaultOpen}) {
			defer im.TreePop();

			switch &v in input_condition {
				case iri.KeymodFlags: 
					for flag in iri.KeymodFlag {
						enum_flags_checkbox(fmt_cstr("{}", flag), flag,  &v);
					}

				case iri.MouseButtonFlags:    
					for flag in iri.MouseButton {
						enum_flags_checkbox(fmt_cstr("{}", flag), flag,  &v);
					}
				case iri.GamepadButtonFlags:  
					for flag in iri.GamepadButton {
						enum_flags_checkbox(fmt_cstr("{}", flag), flag,  &v);
					}
				case:;
			}
		}
	}
}


// Draw input processors of either the input_action or a binding within the input_aciton. If use_action == true
// it will use the action and binding_index can be set to anything.
draw_gui_input_action_processors :: proc(input_action : ^iri.InputAction, use_action : bool, binding_index : int) {

	if input_action == nil {
		return
	}

	if !use_action {
		
		valid_binding : bool = binding_index >= 0 && binding_index < len(input_action.bindings);
		if !valid_binding {
			im.Text("Invalid Binding index");
			return;
		}
	} 

	tree_node_lable := fmt_cstr("Processors##{}{}", binding_index, use_action);
	if im.TreeNodeEx(tree_node_lable, im.TreeNodeFlags{.DefaultOpen}) {
	 	defer im.TreePop();

	 	if im.Button("+") {
	 		if use_action {
	 			iri.input_action_add_processors(input_action,{iri.InputProcessor{}});
	 		} else {
	 			iri.input_action_binding_add_processors(input_action,binding_index, {iri.InputProcessor{}});
	 		}
	 	}
	 	im.SetItemTooltip("Add Input Processor");
		
		offset : int =  use_action ? cast(int)input_action.action_processors_offset : cast(int)input_action.bindings[binding_index].data.processors_offset;
		count  : int =  use_action ? cast(int)input_action.action_processors_count  : cast(int)input_action.bindings[binding_index].data.processors_count;

	 	if count > 0 {

	 		start : int = offset;
	 		end   : int = offset + count;

	 		processor_loop: for i in start..<end {
	 			
		 		processor := &input_action.processors[i];
		 		p_type := iri.input_processor_to_type(processor^);
		 		p_type_cstr := fmt_cstr("{}", p_type);
	 			
	 			im.Spacing();

	 			processor_treenode_label := fmt_cstr("{}##Processor{}", p_type, i);
	 			if im.TreeNodeEx(processor_treenode_label, im.TreeNodeFlags{.DefaultOpen}) {
	 				defer im.TreePop();

		 			type_combo_label := fmt_cstr("Procesor Type##AI{}", i);

		 			if new_type, selected := enum_combo(type_combo_label, p_type_cstr, iri.InputProcessorType); selected {
		 				switch new_type {
			 				case iri.InputProcessorType.None: 			processor^ = nil;
			 				case iri.InputProcessorType.Clamp:			processor^ = iri.InputProcessorClamp{};
			 				case iri.InputProcessorType.Multiply: 		processor^ = iri.InputProcessorMultiply{};
			 				case iri.InputProcessorType.Divide:			processor^ = iri.InputProcessorDivide{};
			 				case iri.InputProcessorType.NormalizeAxis:	processor^ = iri.InputProcessorNormalizeAxis{};
		 				}

		 				p_type = new_type;
					}

		 			switch &v in processor {
		 				case iri.InputProcessorClamp: {
		 					im.DragFloat("Min", &v.min);
		 					im.DragFloat("Max", &v.max);

		 					curr_axis_mask_cstr := fmt_cstr("{}", v.axis_mask);
		 					if new_type, selected := enum_combo("Axis Mask", curr_axis_mask_cstr, iri.AxisMask); selected {
				 				v.axis_mask = new_type;
							}
		 				}
		 				case iri.InputProcessorMultiply: {
		 					im.DragFloat("Scalar", &v.scalar);
		 					curr_axis_mask_cstr := fmt_cstr("{}", v.axis_mask);
		 					if new_type, selected := enum_combo("Axis Mask", curr_axis_mask_cstr, iri.AxisMask); selected {

				 				v.axis_mask = new_type;
							}
		 				}
		 				case iri.InputProcessorDivide: {
		 					im.DragFloat("Denominator", &v.denominator);
		 					curr_axis_mask_cstr := fmt_cstr("{}", v.axis_mask);
		 					if new_type, selected := enum_combo("Axis Mask", curr_axis_mask_cstr, iri.AxisMask); selected {

				 				v.axis_mask = new_type;
							}
		 				}
		 				case iri.InputProcessorNormalizeAxis:
		 				case:
		 			}

		 			delete_btn_lbl := fmt_cstr("Delete##AIP{}", i);
		 			if im.Button(delete_btn_lbl){

		 				if use_action {
		 					iri.input_action_remove_processors(input_action, i, 1);

		 				} else {
		 					iri.input_action_binding_remove_processors(input_action, binding_index, i, 1);
		 				}
		 				break processor_loop;
		 			}
		 			im.SetItemTooltip("Delete Input Processor");

		 			im.SameLine();

		 			move_up_btn_lbl := fmt_cstr("/\\ UP##AIP{}", i);
		 			if im.Button(move_up_btn_lbl){

		 				if use_action {
		 					iri.input_action_swap_processors(input_action, i, i-1);

		 				} else {
		 					iri.input_action_binding_swap_processors(input_action, binding_index, i, i-1);
		 				}
		 				break processor_loop;
		 			}
		 			im.SetItemTooltip("Move Processor up in the stack");

		 			im.SameLine();
		 			move_down_btn_lbl := fmt_cstr(" \\/ Down##AIP{}", i);
		 			if im.Button(move_down_btn_lbl){
		 				if use_action {
		 					iri.input_action_swap_processors(input_action, i, i+1)
		 				} else {
		 					iri.input_action_binding_swap_processors(input_action, binding_index, i, i+1)
		 				}
		 				break processor_loop;
		 			}
		 			im.SetItemTooltip("Move Processor Down in the stack");

	 			}
	 		}
	 	}
	}
}


draw_gui_input_binding_variant :: proc(binding_variant : ^iri.InputBindingVariant) {

	if binding_variant == nil {
		return;
	}

	curr_variant_type : iri.InputBindingType = iri.input_binding_variant_to_type(binding_variant^);

	curr_variant_type_cstr := fmt_cstr("{}", curr_variant_type);

	binding_selection: if new_variant_type, selected := enum_combo("Binding Type", curr_variant_type_cstr, iri.InputBindingType); selected {

		if new_variant_type == curr_variant_type {
			break binding_selection;
		}

		switch new_variant_type {
			case .None: 			binding_variant^ = nil;
			case .Keyboard:     	binding_variant^ = iri.InputBindingKeyboard{}; 
			case .MouseButton:  	binding_variant^ = iri.InputBindingMouseButton{};
			case .MouseWheel:		binding_variant^ = iri.InputBindingMouseWheel{};
			case .MousePosition:	binding_variant^ = iri.InputBindingMousePosition{};
			case .MouseDelta:		binding_variant^ = iri.InputBindingMouseDelta{};
			case .GamepadButton:	binding_variant^ = iri.InputBindingGamepadButton{};
			case .GamepadAnalog:	binding_variant^ = iri.InputBindingGamepadAnalog{};
			case .Axis1DComposit:	binding_variant^ = iri.InputBinding1DAxisComposit{};
			case .Axis2DComposit:	binding_variant^ = iri.InputBinding2DAxisComposit{};
		}
	}

	im.Spacing();
	im.Separator();
	im.Spacing();

	switch &v in binding_variant^ {
		case: {
			im.Text("Nothin ...");
		}
		case iri.InputBindingKeyboard: {

			key_cstr := fmt_cstr("{}", v.key);
			im.Text("Keyboard - %s", key_cstr);
			if new_key, selected := enum_combo("Key", key_cstr, iri.Key); selected {
				v.key = new_key;
			}
		}
		case iri.InputBindingMouseButton: {
			btn_cstr := fmt_cstr("{}", v.btn);
			im.Text("Mouse Button - %s", btn_cstr);
			if new_btn, selected := enum_combo("Mouse Button", btn_cstr, iri.MouseButton); selected {
				v.btn = new_btn;
			}
		}
		case iri.InputBindingMouseWheel: {
			im.Text("Mouse Wheel");
			axis_to_value_cstr := fmt_cstr("{}", v.axis_to_value);

			if new_op, selected := enum_combo("Axis To Value", axis_to_value_cstr, iri.AxisToValueOp); selected {
				v.axis_to_value = new_op;
			}
			im.SetItemTooltip("The Operation to use when polling this binding for a single value or press event");
		}
		case iri.InputBindingMousePosition:	{
			im.Text("Mouse Position");
			axis_to_value_cstr := fmt_cstr("{}", v.axis_to_value);
			if new_op, selected := enum_combo("Axis To Value", axis_to_value_cstr, iri.AxisToValueOp); selected {
				v.axis_to_value = new_op;
			}
			im.SetItemTooltip("The Operation to use when polling this binding for a single value or press event");
		}
		case iri.InputBindingMouseDelta: {
			im.Text("Mouse Delta");
			axis_to_value_cstr := fmt_cstr("{}", v.axis_to_value);
			if new_op, selected := enum_combo("Axis To Value", axis_to_value_cstr, iri.AxisToValueOp); selected {
				v.axis_to_value = new_op;
			}
			im.SetItemTooltip("The Operation to use when polling this binding for a single value or press event");
		}
		case iri.InputBindingGamepadButton:	{
			btn_cstr := fmt_cstr("{}", v.btn);
			im.Text("Gamepad Button - %s", btn_cstr);
			if new_btn, selected := enum_combo("Gamepad Button", btn_cstr, iri.GamepadButton); selected {
				v.btn = new_btn;
			}
			im.SetItemTooltip("The Operation to use when polling this binding for a single value or press event");
		}
		case iri.InputBindingGamepadAnalog:	{
			analog_cstr := fmt_cstr("{}", v.analog);
			im.Text("Gamepad Analog - %s", analog_cstr);
			if new_analog, selected := enum_combo("Gamepad Analog", analog_cstr, iri.GamepadAnalog); selected {
				v.analog = new_analog;
			}

			axis_to_value_cstr := fmt_cstr("{}", v.axis_to_value);
			if new_op, selected := enum_combo("Axis To Value", axis_to_value_cstr, iri.AxisToValueOp); selected {
				v.axis_to_value = new_op;
			}
			im.SetItemTooltip("The Operation to use when polling this binding for a single value or press event");
		}
		case iri.InputBinding1DAxisComposit: {

			im.Text("Negative X");
			im.SameLine();
			draw_gui_input_binding_composable(&v.neg_x, "NegX");


			im.Spacing();
			im.Separator();
			im.Spacing();
			im.Text("Positive X");
			im.SameLine();
			draw_gui_input_binding_composable(&v.pos_x, "PosX");

		}
		case iri.InputBinding2DAxisComposit: {


			im.Text("Negative X");
			im.SameLine();
			draw_gui_input_binding_composable(&v.neg_x, "NegX");


			im.Spacing();
			im.Separator();
			im.Spacing();

			im.Text("Positive X");
			im.SameLine();
			draw_gui_input_binding_composable(&v.pos_x, "PosX");


			im.Spacing();
			im.Separator();
			im.Spacing();
			
			im.Text("Negative Y");
			im.SameLine();
			draw_gui_input_binding_composable(&v.neg_y, "NegY");

			im.Spacing();
			im.Separator();
			im.Spacing();

			im.Text("Positive Y");
			im.SameLine();
			draw_gui_input_binding_composable(&v.pos_y, "PosY");

			im.Spacing();
			
			axis_to_value_cstr := fmt_cstr("{}", v.axis_to_value);
			if new_op, selected := enum_combo("Axis To Value", axis_to_value_cstr, iri.AxisToValueOp); selected {
				v.axis_to_value = new_op;
			}
		}
	}

}

draw_gui_input_binding_composable :: proc(binding_variant : ^iri.InputBindingComposable, str_id : cstring) {

	if binding_variant == nil {
		return;
	}

	curr_variant_type : iri.InputBindingType = iri.input_binding_composable_to_type(binding_variant^);

	curr_variant_type_cstr := fmt_cstr("{}", curr_variant_type);

	binding_type_label := fmt_cstr("Binding Type##{}", str_id);
	binding_selection: if new_variant_type, selected := enum_combo(binding_type_label, curr_variant_type_cstr, iri.InputBindingType); selected {

		if new_variant_type == curr_variant_type {
			break binding_selection;
		}

		switch new_variant_type {
			case .None: 			binding_variant^ = nil;
			case .Keyboard:     	binding_variant^ = iri.InputBindingKeyboard{}; 
			case .MouseButton:  	binding_variant^ = iri.InputBindingMouseButton{};
			case .MouseWheel:		binding_variant^ = iri.InputBindingMouseWheel{};
			case .MousePosition:	binding_variant^ = iri.InputBindingMousePosition{};
			case .MouseDelta:		binding_variant^ = iri.InputBindingMouseDelta{};
			case .GamepadButton:	binding_variant^ = iri.InputBindingGamepadButton{};
			case .GamepadAnalog:	binding_variant^ = iri.InputBindingGamepadAnalog{};
			case .Axis1DComposit:	;
			case .Axis2DComposit:	;
		}
	}

	im.Spacing();

	switch &v in binding_variant^ {
		case: {
			im.Text("Nothin ...");
		}
		case iri.InputBindingKeyboard: {

			key_cstr := fmt_cstr("{}", v.key);
			im.Text("Keyboard - %s", key_cstr);
			combo_label := fmt_cstr("Key##{}", str_id);
			if new_key, selected := enum_combo(combo_label, key_cstr, iri.Key); selected {
				v.key = new_key;
			}
		}
		case iri.InputBindingMouseButton: {
			btn_cstr := fmt_cstr("{}", v.btn);
			im.Text("Mouse Button - %s", btn_cstr);
			combo_label := fmt_cstr("Mouse Button##{}", str_id);
			if new_btn, selected := enum_combo(combo_label, btn_cstr, iri.MouseButton); selected {
				v.btn = new_btn;
			}
		}
		case iri.InputBindingMouseWheel: {
			im.Text("Mouse Wheel");
			axis_to_value_cstr := fmt_cstr("{}", v.axis_to_value);

			combo_label := fmt_cstr("Axis To Value##{}", str_id);
			if new_op, selected := enum_combo(combo_label, axis_to_value_cstr, iri.AxisToValueOp); selected {
				v.axis_to_value = new_op;
			}
			im.SetItemTooltip("The Operation to use when polling this binding for a single value or press event");
		}
		case iri.InputBindingMousePosition:	{
			im.Text("Mouse Position");
			axis_to_value_cstr := fmt_cstr("{}", v.axis_to_value);
			combo_label := fmt_cstr("Axis To Value##{}", str_id);
			if new_op, selected := enum_combo(combo_label, axis_to_value_cstr, iri.AxisToValueOp); selected {
				v.axis_to_value = new_op;
			}
			im.SetItemTooltip("The Operation to use when polling this binding for a single value or press event");
		}
		case iri.InputBindingMouseDelta: {
			im.Text("Mouse Delta");
			axis_to_value_cstr := fmt_cstr("{}", v.axis_to_value);
			combo_label := fmt_cstr("Axis To Value##{}", str_id);
			if new_op, selected := enum_combo(combo_label, axis_to_value_cstr, iri.AxisToValueOp); selected {
				v.axis_to_value = new_op;
			}
			im.SetItemTooltip("The Operation to use when polling this binding for a single value or press event");
		}
		case iri.InputBindingGamepadButton:	{
			btn_cstr := fmt_cstr("{}", v.btn);
			im.Text("Gamepad Button - %s", btn_cstr);
			combo_label := fmt_cstr("Gamepad Button##{}", str_id);
			if new_btn, selected := enum_combo(combo_label, btn_cstr, iri.GamepadButton); selected {
				v.btn = new_btn;
			}
			im.SetItemTooltip("The Operation to use when polling this binding for a single value or press event");
		}
		case iri.InputBindingGamepadAnalog:	{
			analog_cstr := fmt_cstr("{}", v.analog);
			im.Text("Gamepad Analog - %s", analog_cstr);
			combo_label := fmt_cstr("Gamepad Analog##{}", str_id);
			if new_analog, selected := enum_combo(combo_label, analog_cstr, iri.GamepadAnalog); selected {
				v.analog = new_analog;
			}

			axis_to_value_cstr := fmt_cstr("{}", v.axis_to_value);
			combo_label_op := fmt_cstr("Axis To Value##{}", str_id);
			if new_op, selected := enum_combo(combo_label_op, axis_to_value_cstr, iri.AxisToValueOp); selected {
				v.axis_to_value = new_op;
			}
			im.SetItemTooltip("The Operation to use when polling this binding for a single value or press event");
		}
	}

}

