package binary_reader

import "core:os"
import "core:mem"
import "core:strings"

FileBinaryReader :: struct {
	file   : ^os.File,
	file_offset : int,
	file_size   : int
}

create_file_reader :: proc(file : ^os.File) -> FileBinaryReader {
	file_size , err := os.file_size(file);
	if err != nil || file_size <= 0 {
		return FileBinaryReader{};
	}

	return FileBinaryReader {
		file = file,
		file_offset = 0,
		file_size = cast(int)file_size,
	};
}


fr_remaining_bytes :: proc(reader : ^FileBinaryReader) -> int {
	return reader.file_size - reader.file_offset;
}

fr_has_enough_remaining_bytes :: proc(reader : ^FileBinaryReader, size : int) -> bool {
	return reader.file_size - reader.file_offset < size ? false : true;
}

fr_advance :: proc(reader : ^FileBinaryReader, num_bytes : int) -> bool {
	fr_has_enough_remaining_bytes(reader, num_bytes) or_return;
	new_offset, err := os.seek(reader.file, cast(i64)max(0,num_bytes), .Current);
	reader.file_offset = cast(int)new_offset; 
	return true;
}

fr_seek :: proc(reader : ^FileBinaryReader, offset : int) -> bool {
	
	if offset < 0 || offset >= reader.file_size {
		return false;
	}
	new_offset, err := os.seek(reader.file, cast(i64)offset, .Start);
	reader.file_offset = cast(int)new_offset; 
	return true;
}

fr_consume_mem_copy :: proc(reader : ^FileBinaryReader, dst : rawptr, num_bytes : int) -> (ok : bool){
	fr_has_enough_remaining_bytes(reader, num_bytes) or_return;
	read_bytes , err := os.read_ptr(reader.file, dst, num_bytes)
	if err != os.ERROR_NONE || read_bytes != num_bytes {
		return false;
	}
	reader.file_offset += num_bytes;
	return true;
}

fr_consume_copy_type :: proc(reader : ^FileBinaryReader, $T : typeid) -> (copy : T, ok : bool){
	fr_has_enough_remaining_bytes(reader, size_of(T)) or_return;
	read_bytes , err := os.read_ptr(reader.file, &copy, size_of(T))
	if err != os.ERROR_NONE || read_bytes != size_of(T) {
		return;
	}
	reader.file_offset += size_of(T);
	return copy, true;
}

fr_consume_make_type :: proc(reader : ^FileBinaryReader, $T : typeid, allocator := context.allocator) -> (type : ^T, ok : bool) {
	fr_has_enough_remaining_bytes(reader, size_of(T)) or_return;
	type = new(T, allocator);
	read_bytes , err := os.read_ptr(reader.file, type, size_of(T))
	if err != os.ERROR_NONE || read_bytes != size_of(T) {
		return;
	}
	reader.file_offset += size_of(T);
	return type, true;
}

fr_consume_make_string :: proc(reader : ^FileBinaryReader, byte_size : int, allocator := context.allocator) -> (str : string, ok : bool) {
	if byte_size <= 0 {
		return;
	}
	fr_has_enough_remaining_bytes(reader, byte_size) or_return;
	str_bytes : []u8 = make_slice([]u8, byte_size, allocator);
	read_bytes , err := os.read_ptr(reader.file, &str_bytes[0], byte_size);
	str = string(str_bytes); // we do this before err check so users could dealloc if os error happens
	if err != os.ERROR_NONE || read_bytes != byte_size {
		return;
	}
	reader.file_offset += byte_size;
	return str, true;
}

fr_consume_make_slice :: proc(reader : ^FileBinaryReader, $T: typeid/[]$E, len : int, allocator := context.allocator) -> (out_slice : []E, ok : bool){
	num_bytes : int = len * size_of(E);
	if num_bytes <= 0 {
		return nil, false;
	}
	fr_has_enough_remaining_bytes(reader, num_bytes) or_return;
	out_slice = make_slice([]E, len, allocator);
	read_bytes , err := os.read_ptr(reader.file, &out_slice[0], num_bytes);
	if err != os.ERROR_NONE || read_bytes != num_bytes {
		return;
	}
	reader.file_offset += num_bytes;
	return out_slice, true;	
}