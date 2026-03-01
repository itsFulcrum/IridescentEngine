package iri


import sdl "vendor:sdl3"

import "core:mem"
import "core:math"
import "core:math/linalg"

import "odinary:picy"

Texture2D :: struct {
	binding : sdl.GPUTextureSamplerBinding, // contains ^texture and ^sampler
	size : [2]u32,
	num_mipmaps : u32,
	format : sdl.GPUTextureFormat,
}

TextureCube :: struct {
	face_resolution : u32,
	num_mipmaps : u32,
	format : sdl.GPUTextureFormat,
	binding : sdl.GPUTextureSamplerBinding, // contains ^texture and ^sampler
}

SamplerFilter :: enum int {
	NEAREST = 0,
	LINEAR  = 1,
}

SamplerAddressMode :: enum int {
	REPEAT 			= 0,
	MIRRORED_REPEAT = 1,
	CLAMP_TO_EDGE  	= 2,
}

texture_2D_destroy :: proc(gpu_device: ^sdl.GPUDevice, texture : ^Texture2D, zero_out_memory : bool = true){
	engine_assert(texture != nil);

	if(texture.binding.texture != nil){
		sdl.ReleaseGPUTexture(gpu_device, texture.binding.texture);
	}
	if(texture.binding.sampler != nil){
		sdl.ReleaseGPUSampler(gpu_device, texture.binding.sampler);
	}

	if(zero_out_memory == true) {
		texture.size = {0,0};
		texture.num_mipmaps = 0;
		texture.format = sdl.GPUTextureFormat.INVALID;
		texture.binding.texture = nil;
		texture.binding.sampler = nil;
	}
}

texture_cube_destroy :: proc(gpu_device: ^sdl.GPUDevice, texture : ^TextureCube, zero_out_memory : bool = true){
	engine_assert(texture != nil);

	if(texture.binding.texture != nil){
		sdl.ReleaseGPUTexture(gpu_device, texture.binding.texture);
	}
	if(texture.binding.sampler != nil){
		sdl.ReleaseGPUSampler(gpu_device, texture.binding.sampler);
	}

	if(zero_out_memory == true) {
		texture.face_resolution = 0;
		texture.num_mipmaps = 0;
		texture.format = sdl.GPUTextureFormat.INVALID;
		texture.binding.texture = nil;
		texture.binding.sampler = nil;
	}
}

texture_2D_create_basic :: proc(gpu_device: ^sdl.GPUDevice, tex_size: [2]u32, format: sdl.GPUTextureFormat, enable_mipmaps: bool = true, filter := SamplerFilter.LINEAR, address_mode := SamplerAddressMode.REPEAT, usage_flags := sdl.GPUTextureUsageFlags{.SAMPLER, .COLOR_TARGET}) -> Texture2D {
	
	texture : Texture2D;

	engine_assert(tex_size.x > 0);
	engine_assert(tex_size.y > 0);
	engine_assert(format != .INVALID);

	num_mip_levels : u32 = 1;
    if(enable_mipmaps) {
        num_mip_levels = texture_util_calc_max_mip_level(tex_size.x, tex_size.y);
    }

    tex_create_info : sdl.GPUTextureCreateInfo = {
        type = sdl.GPUTextureType.D2, 
        format = format,
        usage = usage_flags,
        width  = tex_size.x,
        height = tex_size.y,
        layer_count_or_depth = 1,
        num_levels = num_mip_levels,
        sample_count = sdl.GPUSampleCount._1,
    }

    // same enums so we can cast.
    sdl_address_mode := cast(sdl.GPUSamplerAddressMode)address_mode; 
    sdl_filter 		 := cast(sdl.GPUFilter)filter;
    sdl_mipmode 	 := cast(sdl.GPUSamplerMipmapMode)filter;

    sampler_create_info := sdl.GPUSamplerCreateInfo{
        min_filter      = sdl_filter,
        mag_filter      = sdl_filter,
        mipmap_mode     = sdl_mipmode,
        address_mode_u  = sdl_address_mode,
        address_mode_v  = sdl_address_mode,
        address_mode_w  = sdl_address_mode,
		//mip_lod_bias:      f32,                    // The bias to be added to mipmap LOD calculation.
		//max_anisotropy:    f32,                    // The anisotropy value clamp used by the sampler. If enable_anisotropy is false, this is ignored.
		//compare_op:        GPUCompareOp,           /**< The comparison operator to apply to fetched data before filtering. */
        min_lod = 0.0,
		max_lod = cast(f32)(num_mip_levels -1),
		enable_anisotropy = false,                   /**< true to enable anisotropic filtering. */
        enable_compare = false,
    };


    texture.binding.texture = sdl.CreateGPUTexture(gpu_device, tex_create_info);
    texture.binding.sampler = sdl.CreateGPUSampler(gpu_device, sampler_create_info);
    texture.size = tex_size;
    texture.format = format;
    texture.num_mipmaps = num_mip_levels;

    return texture;
}


texture_cube_create_basic :: proc(gpu_device: ^sdl.GPUDevice, face_resolution : u32, format: sdl.GPUTextureFormat, num_mip_levels: u32 = 1, filter := SamplerFilter.LINEAR, address_mode := SamplerAddressMode.REPEAT) -> TextureCube {
	
	texture : TextureCube;

	engine_assert(face_resolution > 0);
	engine_assert(format != .INVALID);
	engine_assert(num_mip_levels > 0);


    tex_create_info : sdl.GPUTextureCreateInfo = {
        type = sdl.GPUTextureType.CUBE, 
        format = format,
        usage = {.SAMPLER, .COMPUTE_STORAGE_READ, .COMPUTE_STORAGE_WRITE},
        width  = face_resolution,
        height = face_resolution,
        layer_count_or_depth = 6,
        num_levels = num_mip_levels,
        sample_count = sdl.GPUSampleCount._1,
    }

    // same enums so we can cast.
    sdl_address_mode := cast(sdl.GPUSamplerAddressMode)address_mode; 
    sdl_filter 		 := cast(sdl.GPUFilter)filter;
    sdl_mipmode 	 := cast(sdl.GPUSamplerMipmapMode)filter;

    sampler_create_info := sdl.GPUSamplerCreateInfo{
        min_filter      = sdl_filter,
        mag_filter      = sdl_filter,
        mipmap_mode     = sdl_mipmode,
        address_mode_u  = sdl_address_mode,
        address_mode_v  = sdl_address_mode,
        address_mode_w  = sdl_address_mode,
		//mip_lod_bias:      f32,                    // The bias to be added to mipmap LOD calculation.
		//max_anisotropy:    f32,                    // The anisotropy value clamp used by the sampler. If enable_anisotropy is false, this is ignored.
		//compare_op:        GPUCompareOp,           /**< The comparison operator to apply to fetched data before filtering. */
        min_lod = 0.0,
		max_lod = cast(f32)(num_mip_levels -1),
		enable_anisotropy = false,                   /**< true to enable anisotropic filtering. */
        enable_compare = false,
    };


    texture.binding.texture = sdl.CreateGPUTexture(gpu_device, tex_create_info);
    texture.binding.sampler = sdl.CreateGPUSampler(gpu_device, sampler_create_info);
    texture.face_resolution = face_resolution;
    texture.format = format;
    texture.num_mipmaps = num_mip_levels;

    return texture;
}



texture_create_2D :: proc(gpu_device : ^sdl.GPUDevice, tex_size : [2]u32, tex_format : sdl.GPUTextureFormat, calc_mip_levels : bool = false, usage_flags : sdl.GPUTextureUsageFlags = {.SAMPLER}) -> ^sdl.GPUTexture{

    mip_levels : u32 = 1;
    if(calc_mip_levels) {
        mip_levels = texture_util_calc_max_mip_level(tex_size.x, tex_size.y);
    }

    create_info : sdl.GPUTextureCreateInfo = {
        type = sdl.GPUTextureType.D2, 
        format = tex_format,
        usage = usage_flags,
        width  = tex_size.x,
        height = tex_size.y,
        layer_count_or_depth = 1,
        num_levels = mip_levels,
        sample_count = sdl.GPUSampleCount._1,
    }

    return sdl.CreateGPUTexture(gpu_device, create_info)
}

texture_create_sampler :: proc(gpu_device : ^sdl.GPUDevice, min_mag_filter := sdl.GPUFilter.LINEAR, mip_mode := sdl.GPUSamplerMipmapMode.LINEAR, address_mode := sdl.GPUSamplerAddressMode.REPEAT) -> ^sdl.GPUSampler{

    basic_sampler_ci : sdl.GPUSamplerCreateInfo = {
        min_filter      = min_mag_filter,
        mag_filter      = min_mag_filter,
        mipmap_mode     = mip_mode,
        address_mode_u  = address_mode,
        address_mode_v  = address_mode,
        address_mode_w  = address_mode,
        min_lod = 0,                    /**< Clamps the minimum of the computed LOD value. */
		max_lod = 10,                    /**< Clamps the maximum of the computed LOD value. */
        enable_compare = false,
    };

    return sdl.CreateGPUSampler(gpu_device, basic_sampler_ci);
}


texture_create_shadowmap_sampler :: proc(gpu_device : ^sdl.GPUDevice, min_mag_filter := sdl.GPUFilter.LINEAR, mip_mode := sdl.GPUSamplerMipmapMode.LINEAR, address_mode := sdl.GPUSamplerAddressMode.REPEAT) -> ^sdl.GPUSampler{

    basic_sampler_ci : sdl.GPUSamplerCreateInfo = {
        min_filter      = sdl.GPUFilter.LINEAR,
        mag_filter      = sdl.GPUFilter.LINEAR,
        mipmap_mode     = sdl.GPUSamplerMipmapMode.NEAREST,
        address_mode_u  = sdl.GPUSamplerAddressMode.REPEAT,
        address_mode_v  = sdl.GPUSamplerAddressMode.REPEAT,
        address_mode_w  = sdl.GPUSamplerAddressMode.REPEAT,
        min_lod = 0,
		max_lod = 0,
        enable_compare = false,
    };

    return sdl.CreateGPUSampler(gpu_device, basic_sampler_ci);
}


texture_upload_pic_info_to_gpu_texture_2D :: proc(gpu_device : ^sdl.GPUDevice, gpu_texture : ^sdl.GPUTexture , pic_info : ^picy.PicInfo) -> bool {

	if gpu_texture == nil do return false;
	
	if !picy.is_valid_picinfo(pic_info) do return false;

	transfer_buf_ci := sdl.GPUTransferBufferCreateInfo{
		usage = sdl.GPUTransferBufferUsage.UPLOAD,
        size  = pic_info.num_bytes,
	}

	transfer_buf := sdl.CreateGPUTransferBuffer(gpu_device, transfer_buf_ci);

	defer sdl.ReleaseGPUTransferBuffer(gpu_device, transfer_buf);

	data_ptr: rawptr = sdl.MapGPUTransferBuffer(gpu_device, transfer_buf, cycle = false);

	mem.copy_non_overlapping(data_ptr, pic_info.pixels, cast(int)pic_info.num_bytes);

	sdl.UnmapGPUTransferBuffer(gpu_device, transfer_buf);

	cmd_buf := sdl.AcquireGPUCommandBuffer(gpu_device);

	copy_pass := sdl.BeginGPUCopyPass(cmd_buf);


	tex_transfer_info := sdl.GPUTextureTransferInfo{
		transfer_buffer = transfer_buf,
		offset = 0,              			// The starting byte of the image data in the transfer buffer.
		pixels_per_row = pic_info.width,        // The number of pixels from one row to the next.
		rows_per_layer = pic_info.height,        // The number of rows from one layer/depth-slice to the next.
	}

	tex_region := sdl.GPUTextureRegion {
		texture = gpu_texture, 
		mip_level = 0,       	
		layer = 0,       		// The layer index to transfer.
		x = 0,       			// The left offset of the region.
		y = 0,       			// The top offset of the region.
		z = 0,       			// The front offset of the region.
		w = pic_info.width,       	// The width of the region.
		h = pic_info.height,       	// The height of the region.
		d = 1,       			// The depth of the region.
	}


	sdl.UploadToGPUTexture(copy_pass,tex_transfer_info, tex_region, cycle = false);

	sdl.EndGPUCopyPass(copy_pass);

	ok := sdl.SubmitGPUCommandBuffer(cmd_buf);

	return ok;
}


texture_util_calc_max_mip_level :: proc "contextless" (width, height : u32) -> u32 {

	min_dimention : u32 = math.min(width, height);
	return cast(u32)math.log2_f32(cast(f32)min_dimention);
}


texture_get_sdl_GPUTextureFormat_from_picy_PicFormat :: proc(picy_format : picy.PicFormat) -> sdl.GPUTextureFormat {

	switch picy_format {

		case .NONE			: return sdl.GPUTextureFormat.INVALID; // undefined
		
		case .R8_UNORM		: return sdl.GPUTextureFormat.R8_UNORM;       		// 1 component 8 bit: unsigned normalized
		case .RG8_UNORM		: return sdl.GPUTextureFormat.R8G8_UNORM;     		// 2 component 8 bit: unsigned normalized
		case .RGB8_UNORM	: return sdl.GPUTextureFormat.INVALID;        		// invalid
		case .RGBA8_UNORM	: return sdl.GPUTextureFormat.R8G8B8A8_UNORM; 		// 4 component 8 bit: unsigned normalized

		case .R16_UNORM		: return sdl.GPUTextureFormat.R16_UNORM; 		  	// 1 component 16 bit: unsigned normalized
		case .RG16_UNORM	: return sdl.GPUTextureFormat.R16G16_UNORM; 	  	// 2 component 16 bit: unsigned normalized
		case .RGB16_UNORM	: return sdl.GPUTextureFormat.INVALID; 			  	// invalid
		case .RGBA16_UNORM	: return sdl.GPUTextureFormat.R16G16B16A16_UNORM; 	// 4 component 16 bit: unsigned normalized

		case .R16_F			: return sdl.GPUTextureFormat.R16_FLOAT;  			// 1 component 16 bit: singed half float (16bit)
		case .RG16_F		: return sdl.GPUTextureFormat.R16G16_FLOAT; 		// 2 component 16 bit: singed half float (16bit)
		case .RGB16_F		: return sdl.GPUTextureFormat.INVALID; 				// invalid
		case .RGBA16_F		: return sdl.GPUTextureFormat.R16G16B16A16_FLOAT; 	// 4 component 16 bit: singed half float (16bit)
		
		case .R32_F			: return sdl.GPUTextureFormat.R32_FLOAT; 			// 1 component 32 bit: signed float (32bit)
		case .RG32_F		: return sdl.GPUTextureFormat.R32G32_FLOAT; 		// 2 component 32 bit: signed float (32bit)
		case .RGB32_F		: return sdl.GPUTextureFormat.INVALID; 				// invalid
		case .RGBA32_F		: return sdl.GPUTextureFormat.R32G32B32A32_FLOAT; 	// 4 component 32 bit: signed float (32bit)
	}

	panic("Invalid Codepath");

}