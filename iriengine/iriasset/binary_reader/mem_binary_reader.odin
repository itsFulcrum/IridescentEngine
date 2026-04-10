package binary_reader

import "core:mem"
import "core:strings"

MemBinaryReader :: struct {
	file_data : []byte,
	file_offset : int,
}

create_memory_reader :: proc(data : []byte) -> (MemBinaryReader) {
	return MemBinaryReader{
		file_data = data,
		file_offset = 0,
	};
}

mr_remaining_bytes :: proc(reader : ^MemBinaryReader) -> int {
	return len(reader.file_data) - reader.file_offset;
}

mr_has_enough_remaining_bytes :: proc(reader : ^MemBinaryReader, size : int) -> bool {
	return len(reader.file_data) - reader.file_offset < size ? false : true;
}

mr_advance :: proc(reader : ^MemBinaryReader, num_bytes : int) -> bool {
	mr_has_enough_remaining_bytes(reader, num_bytes) or_return;
	reader.file_offset += max(0,num_bytes);
	return true;
}

mr_seek :: proc(reader : ^MemBinaryReader, offset : int) -> bool {
	
	if offset < 0 || offset >= len(reader.file_data) {
		return false;
	}

	reader.file_offset = offset;
	return true;
}

// Copy 'num_bytes' into 'dst' and advance by 'num_bytes'. return false on errors.
mr_consume_mem_copy :: proc(reader : ^MemBinaryReader, dst : rawptr, num_bytes : int) -> (ok : bool){
	mr_has_enough_remaining_bytes(reader, num_bytes) or_return;
	mem.copy(dst, &reader.file_data[reader.file_offset], num_bytes);
	reader.file_offset += num_bytes;
	return true;
}

// Allocate a slice of type '$E' and length 'len' given the allocator, Copy data into this slice and return it. returns nil/false on errors.
mr_consume_make_slice :: proc(reader : ^MemBinaryReader, $T: typeid/[]$E, len : int, allocator := context.allocator) -> (out_slice : []E, ok : bool){
	num_bytes : int = len * size_of(E);
	if num_bytes <= 0 {
		return nil, false;
	}
	mr_has_enough_remaining_bytes(reader, num_bytes) or_return;
	slc : []E = make_slice([]E, len, allocator);
	dest_ptr := mem.copy(&slc[0], &reader.file_data[reader.file_offset], num_bytes);
	reader.file_offset += num_bytes;
	return slc, true;	
}

mr_consume_make_type :: proc(reader : ^MemBinaryReader, $T : typeid, allocator := context.allocator) -> (type : ^T, ok : bool) {
	mr_has_enough_remaining_bytes(reader, size_of(T)) or_return;
	type = new(T, allocator);
	mem.copy(type, &reader.file_data[reader.file_offset], size_of(T));
	reader.file_offset += size_of(T);
	return type, true;
}


mr_consume_copy_type :: proc(reader : ^MemBinaryReader, $T : typeid) -> (copy : T, ok : bool){
	mr_has_enough_remaining_bytes(reader, size_of(T)) or_return;
	t_ptr : ^T = cast(^T)&reader.file_data[reader.file_offset];
	reader.file_offset += size_of(T);
	return t_ptr^, true;
}

mr_consume_make_string :: proc(reader : ^MemBinaryReader, byte_size : int, allocator := context.allocator) -> (str_copy : string, ok : bool) {
	str_view : string = mr_consume_cast_string(reader, byte_size) or_return;
	str : string = strings.clone(str_view, allocator);
	return str, true;
}

// these cast things are nice for memory reader but they have not equivalent for file reader as we cant really just take the mem addres of the file contents
// we must first allocate.
mr_consume_cast_ptr :: proc(reader : ^MemBinaryReader, $T : typeid) -> (ptr : ^T, ok : bool) {
	mr_has_enough_remaining_bytes(reader, size_of(T)) or_return;
	ptr = cast(^T)&reader.file_data[reader.file_offset];
	reader.file_offset += size_of(T);
	return ptr, true;
}

mr_consume_cast_string :: proc(reader : ^MemBinaryReader, byte_size : int) -> (str_view : string, ok : bool) {
	mr_has_enough_remaining_bytes(reader, byte_size) or_return;
	str_bytes : []u8 = reader.file_data[reader.file_offset : reader.file_offset + byte_size];
	reader.file_offset += byte_size;
	return string(str_bytes), true;
}