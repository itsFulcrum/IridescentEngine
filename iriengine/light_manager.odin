package iri

import "core:log"
import "core:mem"
import "core:math"
import "core:math/linalg"

import sdl "vendor:sdl3"

LightType :: enum u8 { 
	DIRECTIONAL = 0,
	POINT = 1,
	SPOT = 2,
}

// Layout mirrors gpu structure
@(private="package")
LightDataGPU :: struct #align(16) {
	position: [3]f32,
	type: u32,
	direction: [3]f32,
	shadowmap_index : i32,
	radiance: [3]f32,
	spot_angle_scale:  f32,
	spot_angle_offset: f32,
	// Note: We could use these for per light shadowmap bias settings 
	padding1 	 : u32,
	padding2     : f32,
	padding3     : f32,
}

@(private="file")
LightsGPUBufferHeader :: struct #align(16) {
	// Dirs   range: '0..<directional_lights_end'
	// Points range: 'directional_lights_end..<point_lights_end'
	// Spot   range: 'point_lights_end..<array_len'
	array_len : u32,
	directional_lights_end : u32,
	point_lights_end: u32,
	padding1 : u32
}

@(private="file")
ShadowmapGPUBufferHeader :: struct #align(16) {
	array_len : u32,
	directional_lights_end : u32,
	padding1 : u32,
	padding2 : u32
}

@(private="file")
LightManagerUpdateBufferInfo :: struct {
	must_update_lights_buf_header : bool,
	must_update_lights : bool,
	
	must_update_shadowmaps_buf_header : bool,
	must_update_non_dir_shadowmap_infos : bool,

	gpu_lights_min_update_index : i32,
	gpu_lights_max_update_index : i32,
	
	// not including directional lights which are at the beggining of the array
	// and likely need updating every frame
	shadowmaps_min_update_index : i32,
	shadowmaps_max_update_index : i32,
}

@(private="package")
LightManager :: struct {

	// @Note: The light components array is ecs is not ordered while
	// gpu_lights is ordered by light types. Therefore we use gpu_lights_indexes to
	// to know which light component belongs to which gpu_light.
	// e.g: gpu_light := gpu_lights[gpu_lights_indexes[component_index]], 
	// where component_index is the array index of light component of the ecs array
	gpu_lights : [dynamic]LightDataGPU,
	gpu_lights_indexes : [dynamic]u32, 
	
	gpu_lights_header : LightsGPUBufferHeader,
	gpu_lights_data_buf: 		^sdl.GPUBuffer,
	gpu_lights_transfer_buf: 	^sdl.GPUTransferBuffer,
	gpu_lights_buf_byte_size:  u32,

	gpu_lights_upload_info : QueryBufferUploadInfo,

	// Shadowmap stuff
	gpu_shadowmap_header : ShadowmapGPUBufferHeader,
	gpu_shadowmap_infos : [dynamic]ShadowmapInfoGPU,
	
	gpu_shadowmap_buf_byte_size:  u32,
	gpu_shadowmap_infos_buf: 			^sdl.GPUBuffer,
	gpu_shadowmap_infos_transfer_buf: 	^sdl.GPUTransferBuffer,

	gpu_shadowmap_infos_upload_info : QueryBufferUploadInfo,
	gpu_dir_lights_shadowmap_infos_upload_info : QueryBufferUploadInfo,

	num_shadowmap_array_textures: u32,
	gpu_shadowmap_mip_occupied : [dynamic]ShadowmapMipLevelFlags, // To track which mip levels in the array are occupied
	shadowmap_array_binding : sdl.GPUTextureSamplerBinding,
}

@(private="package")
light_manager_init :: proc(gpu_device: ^sdl.GPUDevice, manager: ^LightManager) {

	manager.gpu_lights_buf_byte_size = 0;
	manager.gpu_shadowmap_buf_byte_size = 0;
	manager.num_shadowmap_array_textures = 0;

	shadowmap_array_sampler_ci : sdl.GPUSamplerCreateInfo = {
        min_filter      = sdl.GPUFilter.NEAREST,
        mag_filter      = sdl.GPUFilter.NEAREST,
        mipmap_mode     = sdl.GPUSamplerMipmapMode.NEAREST,
        address_mode_u  = sdl.GPUSamplerAddressMode.CLAMP_TO_EDGE,
        address_mode_v  = sdl.GPUSamplerAddressMode.CLAMP_TO_EDGE,
        address_mode_w  = sdl.GPUSamplerAddressMode.CLAMP_TO_EDGE,
        min_lod = 0,
        max_lod = SHADOWMAP_MAX_MIP_LEVEL,
        //enable_compare = false,
    };

    manager.shadowmap_array_binding.sampler = sdl.CreateGPUSampler(gpu_device, shadowmap_array_sampler_ci);
}

@(private="package")
light_manager_deinit :: proc(gpu_device: ^sdl.GPUDevice, manager: ^LightManager) {


	if(manager.gpu_lights_data_buf != nil){
		sdl.ReleaseGPUBuffer(gpu_device, manager.gpu_lights_data_buf);
		manager.gpu_lights_data_buf = nil;
	}
	if(manager.gpu_lights_transfer_buf != nil){
		sdl.ReleaseGPUTransferBuffer(gpu_device, manager.gpu_lights_transfer_buf);
		manager.gpu_lights_transfer_buf = nil;
	}

	if manager.gpu_shadowmap_infos_buf != nil {
		sdl.ReleaseGPUBuffer(gpu_device, manager.gpu_shadowmap_infos_buf);
		manager.gpu_shadowmap_infos_buf = nil;
	}
	if manager.gpu_shadowmap_infos_transfer_buf != nil {
		sdl.ReleaseGPUTransferBuffer(gpu_device, manager.gpu_shadowmap_infos_transfer_buf);
		manager.gpu_shadowmap_infos_transfer_buf = nil;
	}

	if manager.shadowmap_array_binding.texture != nil {
		sdl.ReleaseGPUTexture(gpu_device, manager.shadowmap_array_binding.texture);
	}
	if manager.shadowmap_array_binding.sampler != nil {
		sdl.ReleaseGPUSampler(gpu_device, manager.shadowmap_array_binding.sampler)
	}

	manager.gpu_lights_buf_byte_size = 0;
	manager.gpu_shadowmap_buf_byte_size = 0;
	manager.shadowmap_array_binding.texture = nil;
	manager.shadowmap_array_binding.sampler = nil;

	delete(manager.gpu_lights);
	delete(manager.gpu_lights_indexes);
	delete(manager.gpu_shadowmap_infos);
	delete(manager.gpu_shadowmap_mip_occupied)
}

@(private="package")
light_manager_frame_update :: proc(gpu_device: ^sdl.GPUDevice, universe : ^Universe){

	manager := &universe.light_manager;

	// initialize to false each frame.
	// may change during this update.
	manager.gpu_lights_upload_info.requires_upload = false;
	manager.gpu_shadowmap_infos_upload_info.requires_upload = false;
	manager.gpu_dir_lights_shadowmap_infos_upload_info.requires_upload = false;


	update_info : LightManagerUpdateBufferInfo = light_manager_frame_update_cpu_side_buffers(universe);

	// now gpu_lights and shadowmap info array are updated with pushed light changes
	// but we still need to (at least for directional lights)
	// recalculate the view_proj matrecies in the shadowmap infos for rendering
	{
		// All this is non lightsource dependent
		//cascade_frustum_view_proj_mats : [3]matrix[4,4]f32;
		cascade_frustum_centers_ws : [3][4]f32;
		cascade_frustum_extents : [3]f32;
		cascade_ortho_proj_mats : [3]matrix[4,4]f32;

		near_far_scale : f32 = universe.shadow_cascade_near_far_scale; // tunable multiplier to include more of the scene.

		for c in 0..<3 {

			// A view proj for the splited frustum
	        view_proj := universe.frame_camera_info.shadow_cascade_proj_mats[c] * universe.frame_camera_info.view_mat;

        	inv_view_proj := linalg.matrix4_inverse(view_proj);

        	// We want to position the light matrix such that it enclosed the splited frustum
	        // we know the frustum coordinates in clip space which are just between -1..1
	        // so we can use inv_view_proj to bring them to world space
        	near_plane_center : [4]f32 = inv_view_proj * [4]f32{ 0, 0, 0, 1};
        	far_plane_center  : [4]f32 = inv_view_proj * [4]f32{ 0, 0, 1, 1};
        	far_plane_corner  : [4]f32 = inv_view_proj * [4]f32{ 1, 1, 1, 1}; // upper right corner but any corner would do
        	// perspective divide
        	near_plane_center.xyz /= near_plane_center.w;
        	far_plane_center.xyz  /= far_plane_center.w;
        	far_plane_corner.xyz  /= far_plane_corner.w;

			frustum_center_ws : [4]f32 = near_plane_center + 0.5 * (far_plane_center - near_plane_center) ;
			frustum_center_ws.w = 1.0;

			// we use the length from frustum center to corner as the minimum extent in each axis for the orthographic 
			// projection matrix. This ensures that the entire camera frustum split is convered plus a little bit of extra room
			// one can also thing of this as a minimum radius.
        	extent : f32 = linalg.length(frustum_center_ws.xyz - far_plane_corner.xyz);
			
			cascade_frustum_extents[c] = extent;
			cascade_frustum_centers_ws[c] = frustum_center_ws;
			cascade_ortho_proj_mats[c] = linalg.matrix_ortho3d_f32(-extent, extent, -extent, extent, -extent * near_far_scale, extent * near_far_scale, true);
		}


		for i in 0..<manager.gpu_lights_header.directional_lights_end {

			gpu_light := &manager.gpu_lights[i];


			if gpu_light.shadowmap_index >= 0 {
				// casts shadows

				first_shadowmap_index : i32 = gpu_light.shadowmap_index;

				light_dir := -gpu_light.direction;

				// For each cascade
				for cascade in 0..<3 {

					shadowmap_info : ^ShadowmapInfoGPU = &manager.gpu_shadowmap_infos[first_shadowmap_index + i32(cascade)];

					frust_center_ws := cascade_frustum_centers_ws[cascade];
					extent := cascade_frustum_extents[cascade];

					shadowmap_resolution := shadowmap_info.resolution;

	        		// how many texels per 1 (meter) world unit. 
	        		texels_per_unit : f32 = f32(shadowmap_resolution) / (extent * 2.0);

	        		// Snap frustum center to texel units.
	        		{
						// I don't fully understand why this works and if all this math is needed
	        			// but the point of this is to snap the frustum center to texel units
	        			// to avoid aliasing when the camera moves.
	        			// from this article: https://alextardif.com/shadowmapping.html

        				scale_mat := linalg.matrix4_scale_f32([3]f32{texels_per_unit, texels_per_unit,texels_per_unit});

	        			// create a dummy look at view matrix for the light and scale it by texel units
			        	look_at := scale_mat * linalg.matrix4_look_at_f32(eye = {0,0,0}, centre = light_dir, up = TRANSFORM_WORLD_UP, flip_z_axis = true); 
			        	// frustum center to light space
			        	frust_center_vs : [4]f32 = look_at * frust_center_ws;
			        	// floor to snap to texel units.
			        	frust_center_vs.xyz = linalg.floor(frust_center_vs.xyz);

			        	// back to world space
			        	frust_center_ws = linalg.inverse(look_at) * frust_center_vs;
	        		}

	        		eye : [3]f32 = frust_center_ws.xyz - (light_dir * extent);
	        		light_view_mat := linalg.matrix4_look_at_f32(eye, frust_center_ws.xyz, TRANSFORM_WORLD_UP, true);

	        		//log.debugf("Cascade {}, texels_per_world_unit {}",cascade, texels_per_unit)
	        		shadowmap_info.texels_per_world_unit = texels_per_unit;
	        		shadowmap_info.view_proj =  cascade_ortho_proj_mats[cascade] * light_view_mat;
				}
			}
		}
	}

	num_gpu_lights: u32 = cast(u32)len(manager.gpu_lights);
	num_shadowmap_infos: u32 = cast(u32)len(manager.gpu_shadowmap_infos);

	lights_buf_required_byte_size  			: u32 = size_of(LightsGPUBufferHeader)    + num_gpu_lights * size_of(LightDataGPU);
	shadowmap_info_buf_required_byte_size 	: u32 = size_of(ShadowmapGPUBufferHeader) + num_shadowmap_infos * size_of(ShadowmapInfoGPU);
	shadowmap_textures_required_amount      : u32 = max(1 , cast(u32)len(manager.gpu_shadowmap_mip_occupied)); // we take max of 1 bc we always want at least one to have something to bind to the shader.


	lights_buf_requires_complete_reupload : bool = false;
	// @Note:
	// if the required buffer size grows we must create a new gpu buffer.
	// if it shrinks we dont have to but for simplicity right now we also recreate a new one and reupload everything
	if lights_buf_required_byte_size != manager.gpu_lights_buf_byte_size {		
		manager.gpu_lights_data_buf, manager.gpu_lights_transfer_buf = light_manager_recreate_buffers(gpu_device, manager.gpu_lights_data_buf, manager.gpu_lights_transfer_buf, lights_buf_required_byte_size);
		manager.gpu_lights_buf_byte_size = lights_buf_required_byte_size;

		lights_buf_requires_complete_reupload = true;
	}


    shadowmap_buffer_require_complete_reupload : bool = false;

	// also if shadowmap info buffer size changes, reupload everything anew.
	if shadowmap_info_buf_required_byte_size != manager.gpu_shadowmap_buf_byte_size {

		manager.gpu_shadowmap_infos_buf, manager.gpu_shadowmap_infos_transfer_buf = light_manager_recreate_buffers(gpu_device, manager.gpu_shadowmap_infos_buf, manager.gpu_shadowmap_infos_transfer_buf, shadowmap_info_buf_required_byte_size);
		manager.gpu_shadowmap_buf_byte_size = shadowmap_info_buf_required_byte_size;

		shadowmap_buffer_require_complete_reupload = true;
	}

	engine_assert(manager.gpu_lights_data_buf != nil);
	engine_assert(manager.gpu_lights_transfer_buf != nil);
	engine_assert(manager.gpu_shadowmap_infos_buf != nil);
	engine_assert(manager.gpu_shadowmap_infos_transfer_buf != nil);


	must_rerender_all_shadowmaps : bool = false;

	if shadowmap_textures_required_amount > manager.num_shadowmap_array_textures {

		if manager.shadowmap_array_binding.texture != nil {
			sdl.ReleaseGPUTexture(gpu_device, manager.shadowmap_array_binding.texture);
		}
		
		shadowmap_array_create_info : sdl.GPUTextureCreateInfo = {
        	type = sdl.GPUTextureType.D2_ARRAY, 
        	format = sdl.GPUTextureFormat.R32_FLOAT,
        	usage = sdl.GPUTextureUsageFlags{.COLOR_TARGET, .SAMPLER},
        	width  = SHADOWMAP_MAX_RESOLUTION,
        	height = SHADOWMAP_MAX_RESOLUTION,
        	layer_count_or_depth = shadowmap_textures_required_amount,
        	num_levels = SHADOWMAP_MAX_MIP_LEVEL + 1,
        	sample_count = sdl.GPUSampleCount._1,
    	}

		manager.shadowmap_array_binding.texture = sdl.CreateGPUTexture(gpu_device, shadowmap_array_create_info);
		manager.num_shadowmap_array_textures = shadowmap_textures_required_amount;

		must_rerender_all_shadowmaps = true;
	}


	// ==============================================================================================
	// COPY TO TRANSFER BUFFERS
	// ==============================================================================================

	//lights_buf_requires_complete_reupload = true; // force reupload | nocheckin

	if lights_buf_requires_complete_reupload {
		// Reupload entire gpu_lights buffer to transfer buffer
		transfer_buf_data_ptr : rawptr = sdl.MapGPUTransferBuffer(gpu_device, manager.gpu_lights_transfer_buf, false);
		{
			byte_ptr: [^]byte = cast([^]byte)transfer_buf_data_ptr;

			// copy header
			mem.copy_non_overlapping(&byte_ptr[0], &manager.gpu_lights_header, size_of(LightsGPUBufferHeader));

			gpu_lights_array_byte_size : u32 = num_gpu_lights * size_of(LightDataGPU);

			if(gpu_lights_array_byte_size > 0){
				mem.copy_non_overlapping(&byte_ptr[size_of(LightsGPUBufferHeader)], &manager.gpu_lights[0], cast(int)gpu_lights_array_byte_size);
			}
		}
		sdl.UnmapGPUTransferBuffer(gpu_device, manager.gpu_lights_transfer_buf);

		manager.gpu_lights_upload_info.transfer_buf_location = {
    		transfer_buffer = manager.gpu_lights_transfer_buf,
    		offset = 0,
    	}
    	manager.gpu_lights_upload_info.transfer_buf_region = {
    		buffer = manager.gpu_lights_data_buf,
    		offset = 0,
    		size = lights_buf_required_byte_size,
    	}

    	manager.gpu_lights_upload_info.requires_upload = true;
    } else {

    	if update_info.must_update_lights || update_info.must_update_lights_buf_header {

    		min_index := update_info.gpu_lights_min_update_index;
    		max_index := update_info.gpu_lights_max_update_index;

    		engine_assert(min_index >= 0);
    		engine_assert(max_index < i32(num_gpu_lights));
    		engine_assert(min_index <= max_index);

    		transfer_buf_data_ptr : rawptr = sdl.MapGPUTransferBuffer(gpu_device, manager.gpu_lights_transfer_buf, false);
    		
				byte_ptr: [^]byte = cast([^]byte)transfer_buf_data_ptr;

	    		if update_info.must_update_lights_buf_header {
	    			mem.copy_non_overlapping(&byte_ptr[0], &manager.gpu_lights_header, size_of(LightsGPUBufferHeader));
	    		}

	    		// Copy entire region between min...max light indexes
	    		gpu_lights_starting_byte  : u32 = cast(u32)size_of(LightsGPUBufferHeader) + cast(u32)min_index * cast(u32)size_of(LightDataGPU);
	    		gpu_lights_copy_byte_size : u32 = u32(cast(u32)max_index + 1 - cast(u32)min_index) * size_of(LightDataGPU);

	    		mem.copy_non_overlapping(&byte_ptr[gpu_lights_starting_byte], &manager.gpu_lights[min_index], cast(int)gpu_lights_copy_byte_size);
    		
    		sdl.UnmapGPUTransferBuffer(gpu_device, manager.gpu_lights_transfer_buf);

    		upload_starting_byte : u32 = gpu_lights_starting_byte;
    		upload_region : u32 = gpu_lights_copy_byte_size;

    		if update_info.must_update_lights_buf_header {
    			// upload entire region to max index including header
    			upload_starting_byte = 0; 
    			upload_region = cast(u32)size_of(LightsGPUBufferHeader) + (cast(u32)max_index + 1) * cast(u32)size_of(LightDataGPU);
    		}

    		manager.gpu_lights_upload_info.transfer_buf_location = {
	    		transfer_buffer = manager.gpu_lights_transfer_buf,
	    		offset = upload_starting_byte,
	    	}

	    	manager.gpu_lights_upload_info.transfer_buf_region = {
	    		buffer = manager.gpu_lights_data_buf,
	    		offset = upload_starting_byte,
	    		size = upload_region,
	    	}

    		manager.gpu_lights_upload_info.requires_upload = true;
    	}
    }

    // @Note: ===
    // We cycle on transfer buffer uploads, to avoid between frame dependencies,
    // where one frame may not have uploaded the updated data to the gpu while the
    // next  frame already overwrite the data in the transfer buffer to be uploaded
    // which would cause flickering and artifacts.
    // our transfer buffer really is therefore just an intermediary that doesn't contain
    // 'all' of the valid data, just valid data for portions that are to be updated.
    // Complete valid data therefore only exits in our cpu arrays and on the gpu
    // not in the transfer buffers.

    // shadowmap_buffer_require_complete_reupload = true; // Force reupload | nochekin

	if shadowmap_buffer_require_complete_reupload {
		
		// Reupload entire shadowmap info buffer

		transfer_buf_data_ptr : rawptr = sdl.MapGPUTransferBuffer(gpu_device, manager.gpu_shadowmap_infos_transfer_buf, true);
		byte_ptr: [^]byte = cast([^]byte)transfer_buf_data_ptr;

		// copy header
		mem.copy_non_overlapping(&byte_ptr[0], &manager.gpu_shadowmap_header, size_of(ShadowmapGPUBufferHeader));

		gpu_shadowmap_infos_array_byte_size : u32 = num_shadowmap_infos * size_of(ShadowmapInfoGPU);

		if(gpu_shadowmap_infos_array_byte_size > 0){
			mem.copy_non_overlapping(&byte_ptr[size_of(ShadowmapGPUBufferHeader)], &manager.gpu_shadowmap_infos[0], cast(int)gpu_shadowmap_infos_array_byte_size);
		}

		sdl.UnmapGPUTransferBuffer(gpu_device, manager.gpu_shadowmap_infos_transfer_buf);

    	manager.gpu_shadowmap_infos_upload_info.transfer_buf_location = {
    		transfer_buffer = manager.gpu_shadowmap_infos_transfer_buf,
    		offset = 0,
    	}

    	manager.gpu_shadowmap_infos_upload_info.transfer_buf_region = {
    		buffer = manager.gpu_shadowmap_infos_buf,
    		offset = 0,
    		size = shadowmap_info_buf_required_byte_size,
    	}

    	manager.gpu_shadowmap_infos_upload_info.requires_upload = true;

    	// If we upload everything we dont have to upload directional lights shadowmaps seperatly.
    	manager.gpu_dir_lights_shadowmap_infos_upload_info.requires_upload = false;

	} else {

		// For Directiona lights we update their shadowmap infos Every frame.
		directional_lights_exist : bool = manager.gpu_shadowmap_header.directional_lights_end > 0;
		if directional_lights_exist || update_info.must_update_lights_buf_header {

			transfer_buf_data_ptr : rawptr = sdl.MapGPUTransferBuffer(gpu_device, manager.gpu_shadowmap_infos_transfer_buf, true);
			byte_ptr: [^]byte = cast([^]byte)transfer_buf_data_ptr;

			// Copy Header if needed
			if update_info.must_update_shadowmaps_buf_header {
				mem.copy_non_overlapping(&byte_ptr[0], &manager.gpu_shadowmap_header, size_of(ShadowmapGPUBufferHeader));
			}

			shadowmaps_byte_size : u32 = manager.gpu_shadowmap_header.directional_lights_end * size_of(ShadowmapInfoGPU);
			if shadowmaps_byte_size > 0 {
				mem.copy_non_overlapping(&byte_ptr[size_of(ShadowmapGPUBufferHeader)], &manager.gpu_shadowmap_infos[0], cast(int)shadowmaps_byte_size);
			}

			sdl.UnmapGPUTransferBuffer(gpu_device, manager.gpu_shadowmap_infos_transfer_buf);

			starting_byte : u32 = cast(u32)size_of(ShadowmapGPUBufferHeader);
			region_byte_size : u32 = shadowmaps_byte_size;
			
			if update_info.must_update_shadowmaps_buf_header {
				starting_byte = 0;
				region_byte_size = cast(u32)size_of(ShadowmapGPUBufferHeader) + shadowmaps_byte_size;
			}


			manager.gpu_dir_lights_shadowmap_infos_upload_info.transfer_buf_location = {
	    		transfer_buffer = manager.gpu_shadowmap_infos_transfer_buf,
	    		offset = starting_byte,
	    	}
	    	manager.gpu_dir_lights_shadowmap_infos_upload_info.transfer_buf_region = {
	    		buffer = manager.gpu_shadowmap_infos_buf,
	    		offset = starting_byte,
	    		size   = region_byte_size,
	    	}

			manager.gpu_dir_lights_shadowmap_infos_upload_info.requires_upload = true;
		}

		if update_info.must_update_non_dir_shadowmap_infos {

			min_index := max( cast(i32)manager.gpu_shadowmap_header.directional_lights_end, update_info.shadowmaps_min_update_index);
			max_index := max( cast(i32)manager.gpu_shadowmap_header.directional_lights_end, update_info.shadowmaps_max_update_index);

			engine_assert(min_index >= 0);
    		engine_assert(max_index < i32(num_shadowmap_infos));
    		engine_assert(min_index <= max_index);

			transfer_buf_data_ptr : rawptr = sdl.MapGPUTransferBuffer(gpu_device, manager.gpu_shadowmap_infos_transfer_buf, true);
			byte_ptr: [^]byte = cast([^]byte)transfer_buf_data_ptr;

			starting_byte  : u32 = cast(u32)size_of(ShadowmapGPUBufferHeader) + cast(u32)min_index * cast(u32)size_of(ShadowmapInfoGPU);
	    	byte_size : u32 = u32(cast(u32)max_index + 1 - cast(u32)min_index) * size_of(ShadowmapInfoGPU);

			mem.copy_non_overlapping(&byte_ptr[starting_byte], &manager.gpu_shadowmap_infos[min_index], cast(int)byte_size);

			sdl.UnmapGPUTransferBuffer(gpu_device, manager.gpu_shadowmap_infos_transfer_buf);


			manager.gpu_shadowmap_infos_upload_info.transfer_buf_location = {
	    		transfer_buffer = manager.gpu_shadowmap_infos_transfer_buf,
	    		offset = starting_byte,
	    	}
	    	manager.gpu_shadowmap_infos_upload_info.transfer_buf_region = {
	    		buffer = manager.gpu_shadowmap_infos_buf,
	    		offset = starting_byte,
	    		size = byte_size,
	    	}

			manager.gpu_shadowmap_infos_upload_info.requires_upload = true;
		}
	}
}

@(private="file")
light_manager_frame_update_cpu_side_buffers :: proc(universe : ^Universe) -> LightManagerUpdateBufferInfo {

	// @Note: 
	// This structure is used to track which ranges in the 
	// CPU buffers changed and need to be updated on the GPU
	// we use a min/max index strategy where we update the entire 
	// buffer region where changes occured.
	// This means if the first element in the array changed and the 
	// last element changed we update the entire buffer.
	update_info : LightManagerUpdateBufferInfo = {
		must_update_lights_buf_header = false,
		must_update_lights = false,

		must_update_shadowmaps_buf_header = false,
		must_update_non_dir_shadowmap_infos = false,
	
		gpu_lights_min_update_index = -1,
		gpu_lights_max_update_index = -1,
		shadowmaps_min_update_index = -1,
		shadowmaps_max_update_index = -1,
	}

	manager := &universe.light_manager;

	num_gpu_lights: u32 = cast(u32)len(manager.gpu_lights);
	num_light_components: u32 = cast(u32)len(universe.ecs.light_components);
	num_shadowmap_infos : u32 = cast(u32)len(manager.gpu_shadowmap_infos);

	// @Note:
	// When light components got added or removed we must rewrite our internal gpu_lights array
	// since we atm dont track which got added or removed. So we do a full rebuild and reupload to GPU
	// We return from inside this if branch
	components_amount_changed : bool = num_gpu_lights != num_light_components;
	if components_amount_changed {

		// Clear Internal Buffers
		clear(&manager.gpu_lights);
		clear(&manager.gpu_shadowmap_infos);
		clear(&manager.gpu_shadowmap_mip_occupied);
		
		// Clear Header infos
		manager.gpu_lights_header = LightsGPUBufferHeader{};
		manager.gpu_shadowmap_header = ShadowmapGPUBufferHeader{};

		// Create LightDataGPU array and fill with values from lights component
		// Add lights to gpu array in this order:  Directonal then Point then Spot
		// The lights buffer for the gpu relies on the grouping by light type in that order.
		// coupled with the header info where the light types are ending, effectivly slicing it manually
		delete(manager.gpu_lights_indexes);
		manager.gpu_lights_indexes = make_dynamic_array_len([dynamic]u32, cast(int)num_light_components, context.allocator);

		for light_enum_type in LightType {

			for &light_comp, comp_index in universe.ecs.light_components {

				light_type := comp_light_get_type(&light_comp);

				if light_type == light_enum_type {
					gpu_light := comp_light_create_LightDataGPU(&light_comp);
					gpu_light.shadowmap_index = -1; // set to -1 initally, shadowmap allocation will happen after this loop

					gpu_arr_index : u32 = cast(u32)len(manager.gpu_lights);					
					append(&manager.gpu_lights, gpu_light);

					// map component index to gpu array spot
					manager.gpu_lights_indexes[comp_index] = gpu_arr_index;
				}
			}

			if light_enum_type == LightType.DIRECTIONAL {
				manager.gpu_lights_header.directional_lights_end = cast(u32)len(manager.gpu_lights);
			} else if light_enum_type == LightType.POINT {
				manager.gpu_lights_header.point_lights_end = cast(u32)len(manager.gpu_lights);
			}
		}

		num_gpu_lights = cast(u32)len(manager.gpu_lights);
		manager.gpu_lights_header.array_len = num_gpu_lights;
		engine_assert(num_gpu_lights == cast(u32)num_light_components);
		
		// First allocate shadowmap infos for all Directional lights
		for &light_comp, comp_index in universe.ecs.light_components {

			light_type := comp_light_get_type(&light_comp);

			if light_type != .DIRECTIONAL || light_comp.cast_shadows == false {
				continue;
			}

			directional_variant, ok := light_comp.variant.(DirectionalLightVariant);
			engine_assert(ok);

			gpu_light_index : u32 = manager.gpu_lights_indexes[comp_index];

			manager.gpu_lights[gpu_light_index].shadowmap_index = cast(i32)len(manager.gpu_shadowmap_infos);

			for cascade in 0..<3 {
				cascade_shadowmap_info := light_manager_create_new_shadowmap_info_for_resolution(manager, directional_variant.shadowmap_cascade_resolutions[cascade]);
				append(&manager.gpu_shadowmap_infos, cascade_shadowmap_info);
			}
		}

		manager.gpu_shadowmap_header.directional_lights_end = cast(u32)len(manager.gpu_shadowmap_infos);

		// Now allocate Shadowmap Infos for Point and Spot lights
		for &light_comp, comp_index in universe.ecs.light_components {

			light_type := comp_light_get_type(&light_comp);

			if light_type == .DIRECTIONAL || light_comp.cast_shadows == false {
				continue;
			}

			light_transform := ecs_get_transform(light_comp.parent_ecs, light_comp.entity);

			gpu_light_index : u32 = manager.gpu_lights_indexes[comp_index];
			gpu_light := &manager.gpu_lights[gpu_light_index];
			gpu_light.shadowmap_index = cast(i32)len(manager.gpu_shadowmap_infos);


			switch &variant in light_comp.variant {
				case DirectionalLightVariant: // we handled them already above^
				case PointLightVariant:
					for face_index in 0..<6 {
						shadow_info := light_manager_create_new_shadowmap_info_for_resolution(manager, variant.shadowmap_resolution);
						shadow_info.texels_per_world_unit, shadow_info.view_proj = light_manager_calculate_point_light_shadowmap_info(gpu_light, cast(u32)face_index, shadow_info.resolution);
						append(&manager.gpu_shadowmap_infos, shadow_info);
					}
				case SpotLightVariant:
					shadow_info := light_manager_create_new_shadowmap_info_for_resolution(manager, variant.shadowmap_resolution);
					shadow_info.texels_per_world_unit, shadow_info.view_proj = light_manager_calculate_spot_light_shadowmap_info(gpu_light, variant.outer_cone_angle_deg, shadow_info.resolution);
					append(&manager.gpu_shadowmap_infos, shadow_info);
			}
		}

		// update amounts
		num_shadowmap_infos  = cast(u32)len(manager.gpu_shadowmap_infos);

		manager.gpu_shadowmap_header.array_len = num_shadowmap_infos;

		engine_assert(num_gpu_lights == num_light_components);

		update_info.must_update_lights_buf_header = true;
		update_info.must_update_lights = true;
		update_info.gpu_lights_min_update_index = 0;
		update_info.gpu_lights_max_update_index = max(0, i32(num_gpu_lights) -1);

		update_info.must_update_shadowmaps_buf_header = true;

		if manager.gpu_shadowmap_header.directional_lights_end < num_shadowmap_infos {
			update_info.must_update_non_dir_shadowmap_infos = true;
			update_info.shadowmaps_min_update_index = 0;
			update_info.shadowmaps_max_update_index = max(0, i32(num_shadowmap_infos) -1);
		}

		return update_info;
	}


	// If there were no changes reported we return early
	if universe.ecs.any_light_is_dirty == false {
		
		update_info.must_update_lights_buf_header = false;
		update_info.must_update_lights = false;
		update_info.must_update_shadowmaps_buf_header = false;
		update_info.must_update_non_dir_shadowmap_infos = false;

		return update_info;
	}

	defer universe.ecs.any_light_is_dirty = false;

	update_info.must_update_lights = true;

	update_info.gpu_lights_min_update_index = i32(num_gpu_lights);
	update_info.gpu_lights_max_update_index = -1;

	// @Note: we assume that shadowmap header needs updating even if its not neccesarly the case
	// but its likely since almost all paramter in some way would trigger a recalculation of the
	// shadowmap view projection matrix.
	update_info.must_update_non_dir_shadowmap_infos = false;

	shadowmaps_min_update_index : i32 = i32(num_shadowmap_infos); // not including directional lights which are at the beggining of the array
	shadowmaps_max_update_index : i32 = -1; 					  // not including directional lights which are at the beggining of the array

	// make a copy so we can compare later if header needs updating
	lights_head_copy : LightsGPUBufferHeader = manager.gpu_lights_header;
	shadowmap_header_copy : ShadowmapGPUBufferHeader = manager.gpu_shadowmap_header;

	// Update internal buffers for any light that got changed (is marked as is_dirty)
	for &light_comp, component_index in universe.ecs.light_components {
		
		if light_comp._is_dirty == false {
			continue;
		}

		defer light_comp._is_dirty = false;

		// Now we check what which part got changed to determine 
		// how to update the internal buffers
		light_type_now := comp_light_get_type(&light_comp);

		gpu_light_arr_idx : u32 = manager.gpu_lights_indexes[component_index];

		// This is a copy of the previous gpu light
		gpu_light_previous  := manager.gpu_lights[gpu_light_arr_idx];
		light_type_previous := cast(LightType)gpu_light_previous.type;


		light_type_changed : bool = light_type_now != light_type_previous;
		if light_type_changed {			
			// @Note
			// When the light type changes we perform a complete remove and then insert. This is potentially very slow. 
			// We could do it faster but it would be a hell to reason about and maintain since we need to maintain
			// light types being grouped together in the gpu_lights array AND also that directional ligths
			// shadowmap infos are grouped at the beginnning of that array.
			// its complex as it stands already, and changing types at runtime is an edge case anyway so i am okey with this 
			// beeing a little slow atm.
			// @Note: It is Important to Note though, that it would be invalid to remove a gpu_light from a light component
			// and not insert it again. We Assume that all light components are represented in the gpu_lights array!

			light_manager_remove_gpu_light_for_light_component_at(manager, component_index);

			update_info.gpu_lights_min_update_index = min(cast(i32)gpu_light_arr_idx, update_info.gpu_lights_min_update_index);
			update_info.gpu_lights_max_update_index = max(cast(i32)gpu_light_arr_idx, update_info.gpu_lights_max_update_index);

			gpu_arr_insert_index : i32 = light_manager_insert_light_component_at(manager, &light_comp, component_index, &update_info);

			update_info.gpu_lights_min_update_index = min(gpu_arr_insert_index, update_info.gpu_lights_min_update_index);
			update_info.gpu_lights_max_update_index = max(gpu_arr_insert_index, update_info.gpu_lights_max_update_index);
			
		} else {

			// Light type didn't change
			new_gpu_light := comp_light_create_LightDataGPU(&light_comp);

			// Check if cast shadows changed 
			cast_shadows_previous : bool = gpu_light_previous.shadowmap_index >= 0;

			if light_comp.cast_shadows != cast_shadows_previous {

				if light_comp.cast_shadows { 
					// shadows got turned on
					light_manager_allocate_new_shadowmap_infos_for_gpu_light(manager, &new_gpu_light, &light_comp, &update_info);
				
				} else { 
					// shadows got turned off
					update_min, update_max := light_manager_deallocate_shadowmap_infos_for_gpu_light(manager, &gpu_light_previous);
					
					if light_type_now != .DIRECTIONAL { // Directional Light shadowmap infos are updated every frame regardless, so we don't track that.
						update_info.must_update_non_dir_shadowmap_infos = true;

						// If we deallocated shadowmap infos from the end of the array 
						// we may not need to update with min/max so we check here first if they are in a valid range
						if update_min >= 0 && update_max >= 0 && update_min <= update_max {
							update_info.shadowmaps_min_update_index = min(update_min, update_info.shadowmaps_min_update_index);
							update_info.shadowmaps_max_update_index = max(update_max, update_info.shadowmaps_max_update_index);
						}
					}
				}

			} else {  // Cast shadows didn't change

				

				light_casts_shadows : bool = cast_shadows_previous;
				if light_casts_shadows {

					// The new_gpu_light should keep the previous shadowmap infos
					first_info_index : i32 = gpu_light_previous.shadowmap_index;
					new_gpu_light.shadowmap_index = first_info_index;

					switch &light_variant in light_comp.variant {

						case DirectionalLightVariant:
						{
							for cascade in 0..<3 {
								shadowmap_res_now_enum := light_variant.shadowmap_cascade_resolutions[cascade];
								shadowmap_res_now_uint := cast(u32)shadowmap_res_now_enum;

								cascade_info : ^ShadowmapInfoGPU = &manager.gpu_shadowmap_infos[first_info_index + cast(i32)cascade];

								shadowmap_resolution_changed : bool = cascade_info.resolution != shadowmap_res_now_uint;
								if shadowmap_resolution_changed {
									light_manager_deallocate_texture_array_spot(manager, cascade_info.array_layer, cascade_info.mip_level);
									new_array_layer, new_mip_level := light_manager_find_next_free_shadowmap_array_spot_for_resolution(manager, shadowmap_res_now_enum);
									cascade_info.array_layer = cast(i32)new_array_layer;
									cascade_info.mip_level   = new_mip_level;
									cascade_info.resolution  = shadowmap_res_now_uint;
									// @Note: we dont update 'view_proj' and 'texels_per_world_unit' here since
									// they have to be recalculated each frame anyway for directional lights. 
									// This happens elsewhere after cpu buffers are otherwise updated.
								}
							}
							// Directional lights shadowmaps are always updated each frame so we don't have to set any update info here.
						}
						case PointLightVariant:
						{
							shadowmap_res_now_enum := light_variant.shadowmap_resolution;
							shadowmap_res_now_uint := cast(u32)shadowmap_res_now_enum;

							first_shadow_info : ^ShadowmapInfoGPU = &manager.gpu_shadowmap_infos[first_info_index];

							shadowmap_resolution_changed : bool = first_shadow_info.resolution != shadowmap_res_now_uint;
							for face_index in 0..<6 {

								face_info : ^ShadowmapInfoGPU = &manager.gpu_shadowmap_infos[first_info_index + cast(i32)face_index];
								if shadowmap_resolution_changed {
									light_manager_deallocate_texture_array_spot(manager, face_info.array_layer, face_info.mip_level);	
									new_array_layer, new_mip_level := light_manager_find_next_free_shadowmap_array_spot_for_resolution(manager, shadowmap_res_now_enum);

									face_info.array_layer = cast(i32)new_array_layer;
									face_info.mip_level   = new_mip_level;
									face_info.resolution  = shadowmap_res_now_uint;
								}

								// @Note: We are not explicitly checking what parameters changed for the point light but
								// almost anything would trigger recalculation of the view matrix so we just do it for any case.
								face_info.texels_per_world_unit, face_info.view_proj = light_manager_calculate_point_light_shadowmap_info(&new_gpu_light, cast(u32)face_index, face_info.resolution);
							}

							update_info.must_update_non_dir_shadowmap_infos = true;
							update_info.shadowmaps_min_update_index = min(first_info_index, update_info.shadowmaps_min_update_index);
							update_info.shadowmaps_max_update_index = max(first_info_index + 6, update_info.shadowmaps_max_update_index);
						}
						case SpotLightVariant:
						{							
							res_now_enum := light_variant.shadowmap_resolution;
							res_now_uint := cast(u32)res_now_enum;

							spot_shadow_info : ^ShadowmapInfoGPU = &manager.gpu_shadowmap_infos[first_info_index];

							shadowmap_resolution_changed : bool = spot_shadow_info.resolution != res_now_uint
							if shadowmap_resolution_changed {
								
								light_manager_deallocate_texture_array_spot(manager, spot_shadow_info.array_layer, spot_shadow_info.mip_level);
								new_array_layer, new_mip_level := light_manager_find_next_free_shadowmap_array_spot_for_resolution(manager, res_now_enum);

								spot_shadow_info.array_layer = cast(i32)new_array_layer;
								spot_shadow_info.mip_level   = new_mip_level;
								spot_shadow_info.resolution  = res_now_uint;
							}
							// @Note: We are not explicitly checking what parameters changed for the spot light but
							// almost anything would trigger recalculation of the view matrix so we just do it for any case.
							spot_shadow_info.texels_per_world_unit, spot_shadow_info.view_proj = light_manager_calculate_spot_light_shadowmap_info(&new_gpu_light, light_variant.outer_cone_angle_deg, spot_shadow_info.resolution);
							
							update_info.must_update_non_dir_shadowmap_infos = true;
							update_info.shadowmaps_min_update_index = min(first_info_index, update_info.shadowmaps_min_update_index);
							update_info.shadowmaps_max_update_index = max(first_info_index, update_info.shadowmaps_max_update_index);
						}
					}



				} else {
					engine_assert(new_gpu_light.shadowmap_index == -1);
				}
			}

			update_info.gpu_lights_min_update_index = min(cast(i32)gpu_light_arr_idx, update_info.gpu_lights_min_update_index);
			update_info.gpu_lights_max_update_index = max(cast(i32)gpu_light_arr_idx, update_info.gpu_lights_max_update_index);

			manager.gpu_lights[gpu_light_arr_idx] = new_gpu_light;
		}

	} // End ecs.Lgihts_components loop

	engine_assert(update_info.gpu_lights_max_update_index != -1);
	engine_assert(update_info.gpu_lights_min_update_index != i32(num_gpu_lights));

	if update_info.shadowmaps_max_update_index != -1 {
		// make sure update max is not out of bounds in cases where stuff got dealocated.
		update_info.shadowmaps_max_update_index = min(update_info.shadowmaps_max_update_index, i32(manager.gpu_shadowmap_header.array_len -1));
		// Min should never be smaller than end of directional lights, sinde these update indexes only refer to non directional lights shadowmaps.
		update_info.shadowmaps_min_update_index = max(update_info.shadowmaps_min_update_index, i32(manager.gpu_shadowmap_header.directional_lights_end));
	}

	if lights_head_copy != manager.gpu_lights_header {
		update_info.must_update_lights_buf_header = true;
	}

	if shadowmap_header_copy != manager.gpu_shadowmap_header {
		update_info.must_update_shadowmaps_buf_header = true;
	}

	return update_info;
}


@(private="file")
light_manager_create_new_shadowmap_info_for_resolution :: proc(manager : ^LightManager, resolution : ShadowmapResolution) -> ShadowmapInfoGPU {

	array_layer, miplevel := light_manager_find_next_free_shadowmap_array_spot_for_resolution(manager, resolution);

	return ShadowmapInfoGPU{
		array_layer = cast(i32)array_layer,
		mip_level   = miplevel,
		resolution  = cast(u32)resolution,
		// view_proj and texels_per_world_unit are recalculated each frame for direactional lights, 
		// and seperatily upon creation or change for point & spot lights
		// texels_per_world_unit = 0,
		// view_proj : matrix[4,4]f32,
	}
}

@(private="file")
light_manager_allocate_new_shadowmap_infos_for_gpu_light :: proc(manager : ^LightManager, gpu_light : ^LightDataGPU, light_component : ^LightComponent, update_info : ^LightManagerUpdateBufferInfo) {

	light_type : LightType = cast(LightType)gpu_light.type;

	required_contiguous_spots : i32 = 1;

	switch light_type {
		case .DIRECTIONAL: 	required_contiguous_spots = 3;
		case .POINT: 		required_contiguous_spots = 6;
		case .SPOT: 		required_contiguous_spots = 1;
	}

	free_spot : i32 = -1;

	// First we loop through shadowmap infos array and try to find a spot where 
	// there are enough contigous free spots to fit the new light type
	// To ensure that directional lights are always first in the shadowmap infos and we can update them in bluk every frame.
	// for directional lights, this free spot must be before any point or spot light infos in the array.
	// likewise, point and spot lights must find shadowmap_info spots After directional lights shadowmaps.
	shadowmap_info_loop: for &info, info_index in manager.gpu_shadowmap_infos {

		// if array_layer <= -1 its been marked as an unused spot
		if info.array_layer <= -1 {
			
			// other lights must find their free spots AFTER directional lights
			if light_type != .DIRECTIONAL && u32(info_index) < manager.gpu_shadowmap_header.directional_lights_end {

				continue shadowmap_info_loop;
			}
			// Special case for directional lights, because
			// we enforce that directional light shadowmap infos are all at the beggining of the array.
			if light_type == .DIRECTIONAL && u32(info_index) >= manager.gpu_shadowmap_header.directional_lights_end {
				break shadowmap_info_loop;
			}

			if required_contiguous_spots == 1{
				free_spot = cast(i32)info_index;
				break shadowmap_info_loop;
			}

			// bounds check
			if (info_index + cast(int)required_contiguous_spots -1) >= len(manager.gpu_shadowmap_infos){
				break shadowmap_info_loop; // not enough spots left in the array
			}

			all_next_are_also_free : bool = true;

			check_next_loop: for j in 1..<cast(int)required_contiguous_spots {

				spot : int = info_index + j;

				if manager.gpu_shadowmap_infos[spot].array_layer >= 0 {

					all_next_are_also_free = false;
					break check_next_loop;
				}
			}

			if all_next_are_also_free {

				free_spot = cast(i32)info_index;
				break shadowmap_info_loop;
			}
		}
	}

	if free_spot == -1 {
		// no free spot found, create new shadowmap infos

		if light_type == .DIRECTIONAL && manager.gpu_shadowmap_header.array_len > manager.gpu_shadowmap_header.directional_lights_end {

			// we are in the unlucky position that we must insert shadowmap infos in the array
			// because we must ensure that directional lights shadowmaps come before any other light type shadowmaps.
			// this means we will have to update all following gpu_lights with new shadowmap indexes..

			// first create the shadowmap infos we want to insert					
			directional_light_variant, union_cast_ok := &light_component.variant.(DirectionalLightVariant);
			engine_assert(union_cast_ok);

			insert_shadowmap_infos : [3]ShadowmapInfoGPU;
			for c in 0..<3 {
				insert_shadowmap_infos[c] = light_manager_create_new_shadowmap_info_for_resolution(manager, directional_light_variant.shadowmap_cascade_resolutions[c]);
			}

			insert_pos : i32 = cast(i32)manager.gpu_shadowmap_header.directional_lights_end;


			update_indexes_loop: for i in 0..<len(manager.gpu_lights) {

				if manager.gpu_lights[i].shadowmap_index >= insert_pos {

					manager.gpu_lights[i].shadowmap_index += 3; // 3 because we ofcourse inject 3 shadowmap cascades for directional light
					
					// must update those lights ehh
					update_info.gpu_lights_min_update_index = min(i32(i), update_info.gpu_lights_min_update_index);
					update_info.gpu_lights_max_update_index = max(i32(i), update_info.gpu_lights_max_update_index);
				}
			}

			inject_at_elems(&manager.gpu_shadowmap_infos, insert_pos, insert_shadowmap_infos[0], insert_shadowmap_infos[1], insert_shadowmap_infos[2]);

			gpu_light.shadowmap_index = insert_pos;

			manager.gpu_shadowmap_header.directional_lights_end += 3;
			manager.gpu_shadowmap_header.array_len += 3;

			engine_assert(manager.gpu_shadowmap_header.array_len == cast(u32)len(manager.gpu_shadowmap_infos));

			update_info.must_update_shadowmaps_buf_header = true;

			// we efectivly need to update all thats after the directional light shadowmaps. But this is probably anyway taken care of since the array size got bigger
			// so we likely alloc new gpu array and upload everything anyway.
			update_info.must_update_non_dir_shadowmap_infos = true;
			update_info.shadowmaps_min_update_index = cast(i32)manager.gpu_shadowmap_header.directional_lights_end;
			update_info.shadowmaps_max_update_index = cast(i32)manager.gpu_shadowmap_header.array_len -1;
			//update_info.shadowmaps_min_update_index = min(insert_pos, update_info.shadowmaps_min_update_index)
			//update_info.shadowmaps_max_update_index = max(insert_pos + 2, update_info.shadowmaps_max_update_index)

		} else {

			update_info.must_update_shadowmaps_buf_header = true;
			
			shadowmap_last_elem_before_append : i32 = cast(i32)manager.gpu_shadowmap_header.array_len -1;

			gpu_light.shadowmap_index = cast(i32)len(manager.gpu_shadowmap_infos);

			was_directional_light : bool = false;
			switch &light_variant in light_component.variant {

				case DirectionalLightVariant:
					// @Note: This should only happen if there are no shadowcasting point or spot lights at all
					// since we require that directional lights shadowmaps are first in the shadowmap info array.
					was_directional_light = true;

					for cascade_index in 0..<3 {
						new_info := light_manager_create_new_shadowmap_info_for_resolution(manager, light_variant.shadowmap_cascade_resolutions[cascade_index]);
						append(&manager.gpu_shadowmap_infos, new_info);
					}

					manager.gpu_shadowmap_header.directional_lights_end += 3;

				case PointLightVariant:
					resolution := light_variant.shadowmap_resolution;
					for face_index in 0..<6 {
						new_info := light_manager_create_new_shadowmap_info_for_resolution(manager, resolution);
						new_info.texels_per_world_unit, new_info.view_proj = light_manager_calculate_point_light_shadowmap_info(gpu_light, cast(u32)face_index, new_info.resolution);
						append(&manager.gpu_shadowmap_infos, new_info);
					}

				case SpotLightVariant:
					new_info := light_manager_create_new_shadowmap_info_for_resolution(manager, light_variant.shadowmap_resolution);
					new_info.texels_per_world_unit, new_info.view_proj = light_manager_calculate_spot_light_shadowmap_info(gpu_light, light_variant.outer_cone_angle_deg, new_info.resolution);
					append(&manager.gpu_shadowmap_infos, new_info);
			}

			manager.gpu_shadowmap_header.array_len = cast(u32)len(manager.gpu_shadowmap_infos);

			if !was_directional_light {
				shadowmap_last_elem_after_append : i32 = cast(i32)manager.gpu_shadowmap_header.array_len -1;
				
				update_info.must_update_non_dir_shadowmap_infos = true;
				update_info.shadowmaps_min_update_index = min(shadowmap_last_elem_before_append, update_info.shadowmaps_min_update_index)
				update_info.shadowmaps_max_update_index = max(shadowmap_last_elem_after_append, update_info.shadowmaps_max_update_index)
			}
		}


	} else { // free spot found

		// @Note:
		// we actually dont need to update the shadowmap_header here because 
		// we enforced above when searching for free spots, that free spots directional lights
		// must be within the range of '0..<shadowmap_header.directional_lights_end' (before point and spot lights)
		// so the 'directional_lights_end' field will not change and since its a free spot, array len didn't change either..

		gpu_light.shadowmap_index = free_spot;
		
		// Create new shadowmap infos and insert at free_spot location
		switch &light_variant in light_component.variant {

			case DirectionalLightVariant:
				for s in 0..<3 {
					new_info := light_manager_create_new_shadowmap_info_for_resolution(manager, light_variant.shadowmap_cascade_resolutions[s]);
					manager.gpu_shadowmap_infos[free_spot + i32(s)] = new_info;
				}

				// update_info.must_update_shadowmap_infos = true;
				// update_info.shadowmaps_min_update_index = min(free_spot, update_info.shadowmaps_min_update_index)
				// update_info.shadowmaps_max_update_index = max(free_spot + 2, update_info.shadowmaps_max_update_index)

			case PointLightVariant:
				resolution := light_variant.shadowmap_resolution;
				for face_index in 0..<6 {
					new_info := light_manager_create_new_shadowmap_info_for_resolution(manager, resolution);
					new_info.texels_per_world_unit, new_info.view_proj = light_manager_calculate_point_light_shadowmap_info(gpu_light, cast(u32)face_index, new_info.resolution);
					manager.gpu_shadowmap_infos[free_spot + i32(face_index)] = new_info;
				}
				update_info.must_update_non_dir_shadowmap_infos = true;
				update_info.shadowmaps_min_update_index = min(free_spot, update_info.shadowmaps_min_update_index)
				update_info.shadowmaps_max_update_index = max(free_spot + 5, update_info.shadowmaps_max_update_index)

			case SpotLightVariant:
				new_info := light_manager_create_new_shadowmap_info_for_resolution(manager, light_variant.shadowmap_resolution);
				new_info.texels_per_world_unit, new_info.view_proj = light_manager_calculate_spot_light_shadowmap_info(gpu_light,light_variant.outer_cone_angle_deg, new_info.resolution);				
				manager.gpu_shadowmap_infos[free_spot] = new_info;

				update_info.must_update_non_dir_shadowmap_infos = true;
				update_info.shadowmaps_min_update_index = min(free_spot, update_info.shadowmaps_min_update_index)
				update_info.shadowmaps_max_update_index = max(free_spot, update_info.shadowmaps_max_update_index)
		}
	}
}

@(private="file")
light_manager_deallocate_shadowmap_infos_for_gpu_light :: proc(manager : ^LightManager, gpu_light : ^LightDataGPU) -> (shadowmap_update_min, shadowmap_update_max : i32){

	if(gpu_light.shadowmap_index <= -1){
		return;
	}

	shadowmap_update_min = -1;
	shadowmap_update_max = -1;

	first_shadowmap_index : u32 = cast(u32)gpu_light.shadowmap_index;
	gpu_light_type : LightType = cast(LightType)gpu_light.type;

	amount_of_shadowmaps : u32 = 1;
	switch gpu_light_type {
		case .DIRECTIONAL: 	amount_of_shadowmaps = 3;
		case .POINT: 		amount_of_shadowmaps = 6;
		case .SPOT:			amount_of_shadowmaps = 1;
	}

	// if they are at the end of the array we can just pop them off
	if (first_shadowmap_index + amount_of_shadowmaps) == cast(u32)len(manager.gpu_shadowmap_infos){

		engine_assert(manager.gpu_shadowmap_header.array_len == cast(u32)len(manager.gpu_shadowmap_infos))

		for i in 0..<amount_of_shadowmaps { 

			offseted_idx : u32 = first_shadowmap_index + i;

			// update ocupied map
			texture_layer    := manager.gpu_shadowmap_infos[offseted_idx].array_layer;
			texture_mip_enum := cast(ShadowmapMipLevelEnum)manager.gpu_shadowmap_infos[offseted_idx].mip_level;
			
			// mark unused in shadowmap texture array.
			manager.gpu_shadowmap_mip_occupied[texture_layer] -= {texture_mip_enum};
		}

		// Go in reverse to pop back from arrays
		for i : int = int(amount_of_shadowmaps -1); i >= 0; i -= 1 {

			pop(&manager.gpu_shadowmap_infos);
		}

		// check if we can remove textures from the shadowmap_array by checking
		// if any mip is still ocupied.
		empty_bitset := ShadowmapMipLevelFlags{};
		for true {

			last : i32 = cast(i32)len(manager.gpu_shadowmap_mip_occupied) -1;
			if last == -1 {
				break;
			}

			if manager.gpu_shadowmap_mip_occupied[last] == empty_bitset {
				pop(&manager.gpu_shadowmap_mip_occupied);
			}else {
				break;
			}
		}

		manager.gpu_shadowmap_header.array_len -= amount_of_shadowmaps;

		engine_assert(manager.gpu_shadowmap_header.array_len == cast(u32)len(manager.gpu_shadowmap_infos))

		// if directional light
		if gpu_light.type == 0 {
			manager.gpu_shadowmap_header.directional_lights_end -= amount_of_shadowmaps;
		}

	} else { // not at he end of the shaowmap infos array

		for i in 0..<amount_of_shadowmaps {

			offseted_idx : u32 = first_shadowmap_index + i;

			//log.debugf("Deallocating shadowmap {}, amount_of_shadowmaps {}, type {}", offseted_idx, amount_of_shadowmaps, gpu_light_type);

			// update ocupied map
			texture_layer    := manager.gpu_shadowmap_infos[offseted_idx].array_layer;
			texture_mip      := manager.gpu_shadowmap_infos[offseted_idx].mip_level;
			texture_mip_enum := cast(ShadowmapMipLevelEnum)texture_mip;
			
			// mark unused in shadowmap texture array.
			manager.gpu_shadowmap_mip_occupied[texture_layer] -= {texture_mip_enum};

			// mark as unused.
			manager.gpu_shadowmap_infos[offseted_idx].array_layer = -1;
		}

		shadowmap_update_min = i32(first_shadowmap_index);
		shadowmap_update_max = i32(first_shadowmap_index + amount_of_shadowmaps -1);
	}

	return shadowmap_update_min, shadowmap_update_max;
}

@(private="file")
light_manager_remove_gpu_light_for_light_component_at :: proc(manager : ^LightManager, light_component_index : int) {


	gpu_light_array_index := manager.gpu_lights_indexes[light_component_index];
	gpu_light := manager.gpu_lights[gpu_light_array_index];

	gpu_light_type : LightType = cast(LightType)gpu_light.type;

	// First remove shadowmap infos and deallocate their texture array spots..
	if gpu_light.shadowmap_index >= 0 {
		
		// If it had shadowmaps allocated remove them
		// We do this for now by just marking them unused by setting array_layer to -1
		light_manager_deallocate_shadowmap_infos_for_gpu_light(manager, &gpu_light);
	}

	//  update indexes...
	for i in 0..<len(manager.gpu_lights_indexes) {		
		if manager.gpu_lights_indexes[i] >= gpu_light_array_index {
			manager.gpu_lights_indexes[i] -= 1;
		}
	}

	// Remove at 
	ordered_remove(&manager.gpu_lights, gpu_light_array_index);
	manager.gpu_lights_indexes[light_component_index] = u32(0xffffffff); // invalidate to max u32

	// update offsets in header..
	switch gpu_light_type {
		case .DIRECTIONAL: 
			// Have to update both here
			manager.gpu_lights_header.directional_lights_end -= 1;
			manager.gpu_lights_header.point_lights_end -= 1;
		case .POINT:       
			manager.gpu_lights_header.point_lights_end -= 1;
		case .SPOT:
	}

	manager.gpu_lights_header.array_len -= 1;
}

@(private="file")
light_manager_insert_light_component_at :: proc(manager : ^LightManager, light_component : ^LightComponent,  light_component_index : int, update_info : ^LightManagerUpdateBufferInfo) -> (gpu_lights_array_insert_index : i32){

	light_type := comp_light_get_type(light_component);

	new_gpu_light := comp_light_create_LightDataGPU(light_component);

	if light_component.cast_shadows {
		// allocate new shadowinfos and shadowmap array spots
		light_manager_allocate_new_shadowmap_infos_for_gpu_light(manager, &new_gpu_light, light_component, update_info);
	}

	insert_index : i32 = -1;

	switch light_type {
		case .DIRECTIONAL: 	insert_index = cast(i32)manager.gpu_lights_header.directional_lights_end;
		case .POINT: 		insert_index = cast(i32)manager.gpu_lights_header.point_lights_end;
		case .SPOT: 		insert_index = cast(i32)manager.gpu_lights_header.array_len;
	}

	engine_assert(insert_index != -1);

	insert_index_u32 : u32 = cast(u32)insert_index;

	// update indexes...
	for i in 0..<len(manager.gpu_lights_indexes) {
		if manager.gpu_lights_indexes[i] >= insert_index_u32 {
			manager.gpu_lights_indexes[i] += 1;
		}
	}

	inject_at(&manager.gpu_lights, insert_index, new_gpu_light);
	// Note: we must set this after updating the indexes list because otherwise we may add +1 to it.
	manager.gpu_lights_indexes[light_component_index] = insert_index_u32;

	switch light_type {
		case .DIRECTIONAL: 	
			// have to update both here.
			manager.gpu_lights_header.directional_lights_end += 1;
			manager.gpu_lights_header.point_lights_end += 1;
		case .POINT:
			manager.gpu_lights_header.point_lights_end += 1;
		case .SPOT:
	}
	manager.gpu_lights_header.array_len += 1;

	engine_assert(manager.gpu_lights_header.array_len == cast(u32)len(manager.gpu_lights));

	return insert_index;
}

@(private="file")
light_manager_find_next_free_shadowmap_array_spot_for_resolution :: proc(manager : ^LightManager, resolution : ShadowmapResolution) -> (array_layer: u32, mip_level : u32) {

	mip_level = shadowmap_resolution_to_mip_level(resolution);
	mip_level_enum : ShadowmapMipLevelEnum = cast(ShadowmapMipLevelEnum)mip_level;

	tmp_array_layer : i32 = -1;

	for layer in 0..<len(manager.gpu_shadowmap_mip_occupied) {

		if mip_level_enum not_in manager.gpu_shadowmap_mip_occupied[layer] {

			tmp_array_layer = cast(i32)layer; // we found a free spot

			manager.gpu_shadowmap_mip_occupied[layer] += {mip_level_enum};
			break;
		}
	}

	// if we couldn't find a free mipmap spot we allocate a complete new texture in the shadowmap array.
	if tmp_array_layer == -1 {

		new_entry : ShadowmapMipLevelFlags;
		new_entry += {mip_level_enum};

		tmp_array_layer = cast(i32)len(manager.gpu_shadowmap_mip_occupied);

		append(&manager.gpu_shadowmap_mip_occupied, new_entry);
	}

	engine_assert(tmp_array_layer >= 0);

	array_layer = cast(u32)tmp_array_layer;

	return array_layer, mip_level;
}

@(private="file")
light_manager_deallocate_texture_array_spot :: proc(manager : ^LightManager, array_layer: i32, mip_level : u32) {
	engine_assert(array_layer >= 0 && array_layer < cast(i32)len(manager.gpu_shadowmap_mip_occupied));
	engine_assert(mip_level <= cast(u32)SHADOWMAP_MAX_MIP_LEVEL);
	manager.gpu_shadowmap_mip_occupied[array_layer] -= {cast(ShadowmapMipLevelEnum)mip_level};
}

@(private="file")
light_manager_recreate_buffers :: proc(gpu_device: ^sdl.GPUDevice, gpu_buffer : ^sdl.GPUBuffer, transfer_buffer : ^sdl.GPUTransferBuffer, byte_size : u32) -> (^sdl.GPUBuffer, ^sdl.GPUTransferBuffer){

	if gpu_buffer != nil {
		sdl.ReleaseGPUBuffer(gpu_device, gpu_buffer);
	}

	if transfer_buffer != nil {
		sdl.ReleaseGPUTransferBuffer(gpu_device, transfer_buffer);
	}

	gpu_buf_create_info : sdl.GPUBufferCreateInfo = {
		usage = {sdl.GPUBufferUsageFlag.GRAPHICS_STORAGE_READ},
		size  =  byte_size,
	};

	transfer_buf_create_info : sdl.GPUTransferBufferCreateInfo = {
    	usage = sdl.GPUTransferBufferUsage.UPLOAD,
    	size  = byte_size,
	}

	out_gpu_buf := sdl.CreateGPUBuffer(gpu_device, gpu_buf_create_info);
	out_transfer_buf := sdl.CreateGPUTransferBuffer(gpu_device, transfer_buf_create_info);
	return out_gpu_buf, out_transfer_buf;
}


@(private="file")
light_manager_calculate_light_visible_range :: proc(light_radiance :[3]f32, threshold_fudge : f32 = 0.0) -> f32 {
	
	luma_linear :: proc "contextless" (rgb : [3]f32) ->f32 {
    	return linalg.dot(rgb, [3]f32{0.2126729,  0.7151522, 0.0721750});
	}

	// Light attenuation is = 1 / (dist * dist)   inv square law
	// light never reaches 0 so we need a threshold value to calculate percepulat light is not visible.
	base_threshold : f32 = 0.05;
	return linalg.sqrt(#force_inline luma_linear(light_radiance) / (base_threshold + threshold_fudge));
}


@(private="file")
light_manager_calculate_spot_light_shadowmap_info :: proc(gpu_light : ^LightDataGPU, outer_cone_angle_degrees : f32, texture_resolution : u32) -> (texels_per_world_unit : f32 , view_proj : matrix[4,4]f32){
	
	forward := -gpu_light.direction;
	view_mat := linalg.matrix4_look_at_f32(gpu_light.position, gpu_light.position + forward, TRANSFORM_WORLD_UP);

	far_clip : f32 = light_manager_calculate_light_visible_range(gpu_light.radiance);
	fudge : f32 = 0.001;

	cone_angle_rad : f32 = linalg.to_radians(outer_cone_angle_degrees);
	proj_mat := linalg.matrix4_perspective_f32(cone_angle_rad * 2 + 0.001, aspect = 1.0, near = 0.05, far = far_clip, flip_z_axis = true);


	view_proj = proj_mat * view_mat;

	// calc far corners of the view frustum in worldspace
	// to get far plane distance
	inv_view_proj := linalg.inverse(view_proj);
	far_corner_top_left  := inv_view_proj * [4]f32{-1.0,1.0,1.0,1.0};
	far_corner_top_right := inv_view_proj * [4]f32{ 1.0,1.0,1.0,1.0};
	far_corner_top_left.xyz /= far_corner_top_left.w;
	far_corner_top_right.xyz /= far_corner_top_right.w;


	far_dist : f32 = linalg.distance(far_corner_top_left, far_corner_top_right);

	texels_per_world_unit = f32(texture_resolution) / far_dist;


	return  texels_per_world_unit,  view_proj;
}


@(private="file")
light_manager_calculate_point_light_shadowmap_info :: proc(gpu_light : ^LightDataGPU, face_index : u32, texture_resolution : u32) -> (texels_per_world_unit : f32 , view_proj : matrix[4,4]f32){
	
	face_dirs : [6][3]f32 = {
		{ 1, 0, 0}, // +x
		{-1, 0, 0}, // -x
		{ 0, 1, 0},	// +y
		{ 0,-1, 0},	// -y
		{ 0, 0, 1}, // +z
		{ 0, 0,-1}, // -z
	};

	face_dir := face_dirs[face_index];
	up := TRANSFORM_WORLD_UP;

	if face_index == 2 {
		up = -TRANSFORM_WORLD_FORWARD;
	} else if face_index == 3 {
		up = TRANSFORM_WORLD_FORWARD;
	}

	view_mat := linalg.matrix4_look_at_f32(gpu_light.position, gpu_light.position + face_dir, up);

	// Maybe make this threshold value a parameter on the light component
	far_clip : f32 = light_manager_calculate_light_visible_range(gpu_light.radiance, 10.0);

	proj_mat := linalg.matrix4_perspective_f32( linalg.to_radians(f32(90)), aspect = 1.0, near = 0.05, far = far_clip, flip_z_axis = true);

	view_proj = proj_mat * view_mat;

	// calc far corners of the view frustum in worldspace
	// to get far plane distance
	inv_view_proj := linalg.inverse(view_proj);
	far_corner_top_left  := inv_view_proj * [4]f32{-1.0,1.0,1.0,1.0};
	far_corner_top_right := inv_view_proj * [4]f32{ 1.0,1.0,1.0,1.0};
	far_corner_top_left.xyz /= far_corner_top_left.w;
	far_corner_top_right.xyz /= far_corner_top_right.w;

	far_dist : f32 = linalg.distance(far_corner_top_left, far_corner_top_right);
	texels_per_world_unit = f32(texture_resolution) / far_dist;
	return  texels_per_world_unit,  view_proj;
}