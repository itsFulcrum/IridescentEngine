package binary_reader

// Usage:
/*
	- use one of these to create a reader
	m_reader := create_memory_reader(file_contents)
	- or
	f_reader := create_file_reader(file_handle)

	- then you can use these procedure groups with either reader type.
	- this is nice because you can abstract away reading from memory and reading from
	- file by using polymorphic procedure that takes as input the reader as a polymorphic type

	- e.g.:
	asset_read :: proc(b_reader : ^$T) -> (^Asset, bool) where T == FileBinaryReader || T == MemBinaryReader {
		
		hdr : HeaderStruct = consume_copy_type(b_reader, HeaderStruct) or_return;
		...
	}
	
	- then you can just have two separate procedures for reading form file or memory that just create the 
	- corresponding reader type and call the asset_read function with it. 
	- So you only need one implementation of the actual reading code.
*/


remaining_bytes :: proc {
	fr_remaining_bytes,
	mr_remaining_bytes,
}

advance :: proc {
	fr_advance,
	mr_advance,
}

seek :: proc {
	fr_seek,
	mr_seek,
}

has_enough_remaining_bytes :: proc {
	fr_has_enough_remaining_bytes,
	mr_has_enough_remaining_bytes,
}

consume_mem_copy :: proc {
	fr_consume_mem_copy,
	mr_consume_mem_copy
}

consume_copy_type :: proc {
	fr_consume_copy_type,
	mr_consume_copy_type
}

consume_make_type :: proc {
	fr_consume_make_type,
	mr_consume_make_type
}

consume_make_string :: proc {
	fr_consume_make_string,
	mr_consume_make_string
}

consume_make_slice :: proc {
	fr_consume_make_slice,
	mr_consume_make_slice
}