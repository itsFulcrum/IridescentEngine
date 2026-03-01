package iri

import "core:log"
import "core:mem"
import sdl "vendor:sdl3"
import "odinary:picy"

SkyboxComponent :: struct{
	using common : ComponentCommon,

	sun_direction : [3]f32,
	sun_strength  : f32,
	sun_color     : [3]f32,

	color_zenith 	: [3]f32,
	color_horizon 	: [3]f32,
	color_nadir 	: [3]f32,

	exposure : f32,
	
	rotation : f32,
	
	// @Note:  
	// mip 0 contains just unfiltered cubemap, 
	// other mips contain prefiltered verisons for different roughness values
	// I ommit creation of a 'irradiance convolution' and instead just use
	// the last mip level of this prefilitered verison because at roughness 1.0 this 
	// also effectivly converges to the irradiance convolution.
	cubemap : TextureCube,
}

@(private="package")
comp_skybox_init :: proc (comp: ^SkyboxComponent){
	if(comp == nil){
		return;
	}

	#force_inline comp_skybox_set_defaults(comp);
}

@(private="package")
comp_skybox_deinit :: proc(comp: ^SkyboxComponent){
	if(comp == nil){
		return;
	}

	#force_inline comp_skybox_set_defaults(comp);

	gpu_device := get_gpu_device();
	texture_cube_destroy(gpu_device, &comp.cubemap);
}


comp_skybox_set_defaults :: proc(comp : ^SkyboxComponent){
	if(comp == nil){
		return;
	}

	comp.sun_direction = {0.0,-1.0,0.0};
	comp.sun_strength  = 1.0;
	comp.sun_color     = {1.0,1.0,1.0};

	comp.color_zenith  = {0.5, 0.6, 0.8 };
	comp.color_horizon = {0.7, 0.7, 0.75};
	comp.color_nadir   = {0.2, 0.2, 0.3 };
	comp.exposure = 0.0;

	comp.rotation = 0;
}


// =====================================================================
// Component procedures
// =====================================================================



comp_skybox_load_hdr_cubemap :: proc(comp : ^SkyboxComponent, filename : string) {

	engine_assert(comp != nil);

	gpu_device := get_gpu_device();

	texture_cube_destroy(gpu_device, &comp.cubemap);

	pic_info, ok := picy.read_from_file(filename, {.FLIP_VERTICALLY, .RGB_TO_RGBA});

	if(!ok){
		log.errorf("Failed to read image from file: {}", filename);
		return;
	}

	defer picy.free_pixels_if_allocated(&pic_info);

	sdl_tex_format := texture_get_sdl_GPUTextureFormat_from_picy_PicFormat(pic_info.format);

	if(sdl_tex_format == .INVALID){
		log.errorf("Failed to load skybox image has invalid texture format: {}, {}", pic_info.format, filename);
		return;
	}

	tex_size :[2]u32 ={pic_info.width, pic_info.height};

	equirectangluar_tex := texture_2D_create_basic(gpu_device, tex_size, sdl_tex_format, enable_mipmaps = true);

	defer texture_2D_destroy(gpu_device, &equirectangluar_tex, zero_out_memory = false);
	
	success := texture_upload_pic_info_to_gpu_texture_2D(gpu_device, equirectangluar_tex.binding.texture, &pic_info);

	if(!success){
		log.errorf("Failed to upload equirectangular img to gpu texture: width: {}, height: {}, format {}, {}",pic_info.width, pic_info.height, pic_info.format, filename);
		return;
	}

	// we asume a ratio of 2/1 so width is double height. standard for equirectangluar cube textures.
	face_resolution : u32 = pic_info.height; 
	
	// @Note we dont want to do the entire mipchain so we substract 2 here.
	cube_max_mip_level : u32 = texture_util_calc_max_mip_level(face_resolution, face_resolution) - 2;

	comp.cubemap = texture_cube_create_basic(gpu_device, face_resolution, .R32G32B32A32_FLOAT, cube_max_mip_level);


	// write equirectangular to cubemap

	// shader ube layout
	EquiToCube_UBO :: struct {
		_cube_face_resolution 	: u32,
		_current_cube_face 		: u32,
		_mode 					: u32, // mode 0 = map equirectangluar to cube, // mode 1 = prefilter convolute based on roughness
		_roughness 				: f32,
	}

	ubo := EquiToCube_UBO{
		_cube_face_resolution = face_resolution,
		_current_cube_face = 0,
		_mode = 0,
		_roughness = 0.0,
	}

	rw_binding := sdl.GPUStorageTextureReadWriteBinding{
        texture   = comp.cubemap.binding.texture,
        mip_level = 0,
        layer     = 0,
        cycle = false,
    }

	
	cmd_buf := sdl.AcquireGPUCommandBuffer(gpu_device);

	sdl.GenerateMipmapsForGPUTexture(cmd_buf, equirectangluar_tex.binding.texture);

	pipeline_equi_to_cube, thread_count := get_compute_pipeline(.EQUIRECTANGULAR_TO_CUBEMAP);



	mip_resolution : u32 = comp.cubemap.face_resolution;

	for mip in 0..<comp.cubemap.num_mipmaps {
		
		rw_binding.mip_level = mip;
		ubo._mode = mip == 0 ? 0 : 1; // for mip 0 just copy equirectangular withought convolute.
		ubo._roughness = cast(f32)mip / cast(f32)comp.cubemap.num_mipmaps;
		ubo._cube_face_resolution = mip_resolution;

		for face_index in 0..<6 {

			rw_binding.layer = cast(u32)face_index;
			ubo._current_cube_face = cast(u32)face_index;

			compute_pass := sdl.BeginGPUComputePass(cmd_buf, &rw_binding, 1, nil, 0);
	        sdl.BindGPUComputePipeline(compute_pass, pipeline_equi_to_cube);


	        sdl.BindGPUComputeSamplers(compute_pass, 0, &equirectangluar_tex.binding ,1);

	        sdl.PushGPUComputeUniformData(cmd_buf, 0, &ubo, size_of(EquiToCube_UBO));

	        work_groups := calc_work_groups_from_thread_counts_and_invocations(thread_count, [3]u32{ubo._cube_face_resolution, ubo._cube_face_resolution, 1});

	        sdl.DispatchGPUCompute(compute_pass, work_groups.x, work_groups.y, 1);

	        sdl.EndGPUComputePass(compute_pass);
		}

		mip_resolution /= 2;
	}

	submit_ok := sdl.SubmitGPUCommandBuffer(cmd_buf);
	engine_assert(submit_ok);
}
