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
			flags^ -=  EnumBitset{flag};
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
