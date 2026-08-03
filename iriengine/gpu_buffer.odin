package iri

import "core:math"
import "core:mem"
import "core:c"
import sdl "vendor:sdl3"


// TODO: rename to GPUUploadInfo
@(private="package")
QueryBufferUploadInfo :: struct {
	requires_upload       : bool,
	region_min_index : int,
	region_max_index : int,
	
	transfer_buf_location : sdl.GPUTransferBufferLocation,
	transfer_buf_region   : sdl.GPUBufferRegion,
}

BasicGPUBuffer :: struct {
	buf 			: ^sdl.GPUBuffer,
	transfer_buf    : ^sdl.GPUTransferBuffer,
	upload_info 	: QueryBufferUploadInfo,
	curr_byte_size  : u32,
}


gpu_buffer_release_buffers :: proc(gpu_device: ^sdl.GPUDevice, gpu_buf : ^BasicGPUBuffer){
	
	if gpu_buf.buf != nil {
		sdl.ReleaseGPUBuffer(gpu_device, gpu_buf.buf);
		gpu_buf.buf = nil;
	}

	if gpu_buf.transfer_buf != nil {
		sdl.ReleaseGPUTransferBuffer(gpu_device, gpu_buf.transfer_buf);
		gpu_buf.transfer_buf = nil;
	}

	gpu_buf.curr_byte_size = 0;
}

gpu_buffer_reallocate_buffers :: proc(gpu_device: ^sdl.GPUDevice, gpu_buf : ^BasicGPUBuffer, byte_size : u32, buf_usage := sdl.GPUBufferUsageFlags{.GRAPHICS_STORAGE_READ,.COMPUTE_STORAGE_READ}) {

	gpu_buffer_release_buffers(gpu_device, gpu_buf);

	if byte_size == 0 {
		return;
	}

	buf_create_info : sdl.GPUBufferCreateInfo = {
		usage = buf_usage,
		size  = byte_size,
	};

	transfer_buf_create_info : sdl.GPUTransferBufferCreateInfo = {
    	usage = sdl.GPUTransferBufferUsage.UPLOAD,
    	size  = byte_size,
	}

	gpu_buf.buf = sdl.CreateGPUBuffer(gpu_device, buf_create_info);
	gpu_buf.transfer_buf = sdl.CreateGPUTransferBuffer(gpu_device, transfer_buf_create_info);

	gpu_buf.curr_byte_size = byte_size;
}


// Copy the region defined through upload info min-max indexes from the src_buffer to the transfer buffer
// and set the upload_info transfer_buf_loacation and transfer_buf_region accordingly.
// Transfer buffer must be big enough for the entire region.
// src buffer should not be offset it should start at 0.
// The idea with BasicGPUBuffer is that the transfer and gpu buffer efectivly shadow a src buffer and are
// at least the same size as the src buffer or bigger in which case the remaining bytes are unused for future data.
gpu_buffer_memcopy_upload_info_min_max_region_to_transfer_buffer :: proc(
	gpu_device: ^sdl.GPUDevice, 
	gpu_buf : ^BasicGPUBuffer, 
	src_buffer : rawptr, 
	element_byte_size : int, 
	cycle : bool = false)
{

	upinfo := &gpu_buf.upload_info;

	engine_assert(upinfo.region_min_index >= 0)
	engine_assert(upinfo.region_max_index >= 0)
	engine_assert(upinfo.region_max_index >= upinfo.region_min_index)

	starting_byte  : int = upinfo.region_min_index *  element_byte_size;
	copy_byte_size : int = (upinfo.region_max_index + 1 - upinfo.region_min_index) * element_byte_size;

	transfer_ptr : rawptr = sdl.MapGPUTransferBuffer(gpu_device, gpu_buf.transfer_buf, cycle);
	{
		transfer_byte_ptr: [^]byte = cast([^]byte)transfer_ptr;		
		src_byte_ptr: [^]byte = cast([^]byte)src_buffer;		
		mem.copy_non_overlapping(&transfer_byte_ptr[starting_byte], &src_byte_ptr[starting_byte], copy_byte_size);
	}
	sdl.UnmapGPUTransferBuffer(gpu_device, gpu_buf.transfer_buf);

	upinfo.transfer_buf_location = {
		transfer_buffer = gpu_buf.transfer_buf,
		offset = cast(u32)starting_byte,
	}

	upinfo.transfer_buf_region = {
		buffer = gpu_buf.buf,
		offset = cast(u32)starting_byte,
		size   = cast(u32)copy_byte_size,
	}
}

upload_info_reset :: proc(info : ^QueryBufferUploadInfo){
	info^ = QueryBufferUploadInfo{
		requires_upload = false,
		region_min_index = cast(int)c.INT64_MAX,
		region_max_index = -1,
	};
}

// @Note: does not set 'requires_upload' to true!
upload_info_update_min_max :: proc(info : ^QueryBufferUploadInfo, min_index : int, max_index : int){

	engine_assert(min_index >= 0)
	engine_assert(max_index >= 0)

	info.region_min_index = min(info.region_min_index, min_index);
	info.region_max_index = max(info.region_max_index, max_index);
}

