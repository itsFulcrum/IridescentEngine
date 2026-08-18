package iriedit

import "core:fmt"
import "core:strings"
import "base:intrinsics"

import im "odinary:dear_imguy"

imgui_text_fmt :: #force_inline proc(fmt_string : string, args: ..any){

	formated : string = fmt.aprintf(fmt_string, ..args, allocator  =  context.temp_allocator);
	txt : cstring = strings.clone_to_cstring(formated, allocator = context.temp_allocator);
	im.Text(txt);
}

fmt_cstr :: #force_inline proc(fmt_string : string, args: ..any, allocator := context.temp_allocator) -> cstring {
	formated : string = fmt.aprintf(fmt_string, ..args, allocator = allocator);
	return strings.clone_to_cstring(formated, allocator = allocator);
}


// Copy a string to a byte buffer and append a null terminator.
// if len(str) exceeds buffer size it will be cut off.
@(private="package")
copy_string_to_buffer_null_terminate :: proc(buf : [^]u8, buf_size : int, str : string) {

	if buf_size <= 0 {
		return;
	}

	last_byte : int = min(len(str), buf_size-1);

	for i in 0..<last_byte {
		
		buf[i] = str[i];
	}
	buf[last_byte] = 0x00; // null termination for cstring..
}

InputTextBuffer :: struct {
	buffer : []u8,
}

input_text_buffer_init :: proc(txt_buf : ^InputTextBuffer, capacity : int){

	txt_buf.buffer = make_slice([]u8, capacity + 1, context.allocator);
}

input_text_buffer_free :: proc(txt_buf : ^InputTextBuffer){
	delete_slice(txt_buf.buffer);
	txt_buf.buffer = nil;
}

input_text_buffer_get_string :: proc(txt_buf : ^InputTextBuffer) -> string {
	return string(txt_buf.buffer);
}





/*
Generic procedure to Draw a Checkbox for an enum flag in a bitset.
'flag' (EnumType) must be an enum. 'flags' (EnumBitset) must be a bit_set[EnumType]

Example:

Foo :: enum { Bar = 0, BarBar = 1, Barbara = 2}
FooFlags :: bit_set[Foo]

foo_flags := FooFlags{.Bar, .BarBar};

// @Note: We cannot do '.Barbara' it must be 'Foo.Barbara'. The type for 'flag' can't be implicitly selected.
if enum_flags_checkbox("Enable Barbara", Foo.Barbara, &foo_flags) {
	assert(.Barbara in foo_flags)
}
*/
enum_flags_checkbox :: proc(label : cstring, flag : $EnumType,  flags : ^$EnumBitset) -> bool where intrinsics.type_is_enum(EnumType), intrinsics.type_is_bit_set(EnumBitset) {

	is_enabled : bool = flag in flags;

	if im.Checkbox(label, &is_enabled) {
		
		if is_enabled {
			flags^ += EnumBitset{flag};
		} else {
			flags^ -= EnumBitset{flag};
		}

		return true;
	}

	return false;
}

// same as above but skips any flags not in include set. Can be useful for writing gernal purpose functions that only operate on 
// a subset of flags.
enum_flags_checkbox_include_set :: proc(label : cstring, flag : $EnumType,  flags : ^$EnumBitset, include_set : EnumBitset) -> bool where intrinsics.type_is_enum(EnumType), intrinsics.type_is_bit_set(EnumBitset) {

	if flag not_in include_set {
		return false;
	}

	is_enabled : bool = flag in flags;

	if im.Checkbox(label, &is_enabled) {
		
		if is_enabled {
			flags^ += EnumBitset{flag};
		} else {
			flags^ -=  EnumBitset{flag};
		}

		return true;
	}

	return false;
}


enum_combo :: proc(label : cstring, curr_selected_cstr : cstring, $T : typeid) -> (T, bool) where intrinsics.type_is_enum(T) {

	selection_made : bool = false;
	selected_type : T;

	if im.BeginCombo(label, curr_selected_cstr){
		for type in T {

			type_cstr := fmt_cstr("{}", type);

			if im.Selectable(type_cstr) {
				selected_type = type;
				selection_made = true;
				break;
			}
		}

		im.EndCombo();
	}

	return selected_type, selection_made;
}



button_align_right_sameline :: proc(btn_label : cstring, btn_size : im.Vec2 = im.Vec2{20.0, 0.0}) -> (pressed : bool) {
	
	im.SameLine();
	
	im.SetCursorPosX( im.GetCursorPosX() + max(0.0, im.GetContentRegionAvail().x - btn_size.x) );
		
	if im.Button(btn_label, btn_size) {
		return true;
	}

	return false;
}