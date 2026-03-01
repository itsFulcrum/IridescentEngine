package iri

import "core:log"
import "core:mem"
import "core:math/linalg"
import "odinary:mathy"

import sdl "vendor:sdl3"

@(private="package")
universe_manager_update_universe :: proc(gpu_device : ^sdl.GPUDevice, universe : ^Universe, frame_size : [2]u32){



	perfs := get_performance_counters();

	universe_update_timer := timer_begin();
	defer perfs.universe_total_update_time_ms = timer_end_get_miliseconds(universe_update_timer);
	

	//frame_size := renderer_get_current_frame_size();
	frame_aspect_ratio : f32 = cast(f32)frame_size.x / cast(f32)frame_size.y;

	universe_update_frame_camera_info(universe, frame_aspect_ratio);


	if universe.ecs.active_skybox_is_dirty {
		
		sky_comp := universe_get_active_skybox_component(universe);

		if sky_comp == nil {
			skybox_gpu_data_set_defaults(&universe.skybox_data);
		} else {

			sky_data := &universe.skybox_data;

			has_cubemap_texture : bool = sky_comp.cubemap.binding.texture != nil;

			sky_data.sun_direction 	= sky_comp.sun_direction;
			sky_data.sun_strength 	= sky_comp.sun_strength;
			sky_data.sun_color 		= sky_comp.sun_color;
			sky_data.use_cubemap    = has_cubemap_texture ? 1.0 : 0.0;

			sky_data.color_zenith 	= sky_comp.color_zenith;
			sky_data.color_horizon 	= sky_comp.color_horizon;
			sky_data.color_nadir 	= sky_comp.color_nadir;

			sky_data.exposure = BASE_SKYBOX_EXPOSURE + sky_comp.exposure;
			sky_data.rotation = sky_comp.rotation;

			sky_data.max_cubemap_mip = has_cubemap_texture ? sky_comp.cubemap.num_mipmaps : 0;
		}

		transfer_data : rawptr = sdl.MapGPUTransferBuffer(gpu_device, universe.skybox_transfer_buffer, cycle = false);

		byte_ptr : [^]byte = cast([^]byte)transfer_data;

		//copy_size : int = cast(int)offset_of(SkyboxGPUData, sh_coeficiants);
		copy_size : int = size_of(SkyboxGPUData);

		mem.copy(&byte_ptr[0], &universe.skybox_data, copy_size);

		sdl.UnmapGPUTransferBuffer(gpu_device, universe.skybox_transfer_buffer);
	}


	light_manager_frame_update(gpu_device, universe);


	drawables : ^#soa[dynamic]Drawable = &universe.ecs.drawables;

	// update non static transforms
	universe_update_matrix_buffer(gpu_device, universe);


	// Create a list of indexes into drawables that are inside camera frustum

	// Frustum cull main camera into frame_renderables
	{
		cull_timer := timer_begin();
		culled_instances : u32 = 0;
		defer {
			perfs.frustum_culling_time_ms = timer_end_get_miliseconds(cull_timer);
			perfs.frustum_culled_instance = culled_instances;
		}

		camera_info := &universe.frame_camera_info;

		clear(&universe.frame_renderables);

		for i in 0..<len(drawables) {

			if MeshInstanceFlag.IS_VISIBLE not_in drawables.mesh_instance[i].flags {
				continue;
			}

			// TODO: we should add if entity is disabled..


			inside_frustum : bool = true;

			if universe.do_frustum_culling {
				inside_frustum = frustum_test_obb_inside(camera_info.culling_frustum, camera_info.frustum_view_mat, drawables.world_obb[i]);
			}

			if inside_frustum {
				append(&universe.frame_renderables, cast(u32)i);
			} else {
				culled_instances += 1;
			}
		}
	}

	// TODO: this stuff must change for the new pipeline system.

	// Sort renderables into subbuckets of Opaque, Alpha test and Alpha Blend

	clear(&universe.frame_opaques);
	clear(&universe.frame_alpha_test);
	clear(&universe.frame_alpha_blend);



	for i in 0..<len(universe.frame_renderables) {
        
		drawable_index := universe.frame_renderables[i];

		mat_id := drawables.mesh_instance[drawable_index].mat_id;

        material := register_get_material(mat_id);

        switch material.render_technique.alpha_mode {
        	case .Opaque: 	append(&universe.frame_opaques, drawable_index);
        	case .Clip:		append(&universe.frame_alpha_test, drawable_index);
        	case .Hashed:	append(&universe.frame_alpha_test, drawable_index);
        	case .Blend: 	append(&universe.frame_alpha_blend, drawable_index);
        }
    }

    // Sort 

    when true {

    	// @Note: here we are 'bubble' sorting frame_opaques by technique hash

		for i := 1; i < len(universe.frame_opaques)-1; i+=1 {
			
			i_mat_id := drawables.mesh_instance[i].mat_id;
			i1_mat_id := drawables.mesh_instance[i-1].mat_id;

			i_tech_hash := material_register_get_render_technique_hash(i_mat_id);
			i1_tech_hash := material_register_get_render_technique_hash(i1_mat_id);

			//pipe_manager_get_material_pipeline_variant(engine.pipeline_manager, )

			if i_tech_hash == i1_tech_hash { 
				continue; // early out if already the same as the last one
			}

			for j := i+1; j < len(universe.frame_opaques); j+=1 {

				j_mat_id := drawables[j].mesh_instance.mat_id;
				j_tech_hash := material_register_get_render_technique_hash(j_mat_id);

				if j_tech_hash == i_tech_hash {	
					// swap material index
					index_i := universe.frame_opaques[i];
					universe.frame_opaques[i] = universe.frame_opaques[j];
					universe.frame_opaques[j] = index_i;

					break;
				}
			}
		}
    }

    // TODO: sort blend meshes
}


@(private="package")
universe_query_skybox_buffer_upload :: proc(gpu_device : ^sdl.GPUDevice, universe : ^Universe) -> (requires_upload: bool, transfer_buf_location : sdl.GPUTransferBufferLocation, buf_region : sdl.GPUBufferRegion) {

	if !universe.ecs.active_skybox_is_dirty {
		return false, transfer_buf_location, buf_region;
	}

	// we want to upload up until sh coeficiants as to not overwrite them..
	//copy_size : u32 = cast(u32)offset_of(SkyboxGPUData, sh_coeficiants);
	copy_size : u32 = cast(u32)size_of(SkyboxGPUData);

	transfer_buf_location = sdl.GPUTransferBufferLocation {
		transfer_buffer = universe.skybox_transfer_buffer,
		offset = 0,
	}

	buf_region = sdl.GPUBufferRegion {
		buffer = universe.skybox_gpu_buffer,
		offset = 0,
		size = copy_size,
	}

	universe.ecs.active_skybox_is_dirty = false;

	return true, transfer_buf_location, buf_region;
}


@(private="file")
universe_update_frame_camera_info :: proc (universe : ^Universe, frame_aspect_ratio : f32){


	info : ^FrameCameraInfo = &universe.frame_camera_info;

    if universe_has_active_camera(universe) {

        cam_transform := ecs_get_transform(&universe.ecs, universe.ecs.active_camera_entity);
        info.position_ws = cam_transform.position;
        info.direction_ws = get_forward(cam_transform);
            
        info.view_mat = calc_view_matrix(cam_transform);

        cam_comp, err2 := ecs_get_component(&universe.ecs, universe.ecs.active_camera_entity, CameraComponent);
        info.proj_mat = comp_camera_get_projection_matrix(cam_comp, frame_aspect_ratio);

        info.fov_radians = linalg.to_radians(cam_comp.fov_deg);
        info.near_plane  = cam_comp.near_clip;
        info.far_plane   = cam_comp.far_clip;
        info.camera_exposure = comp_camera_get_exposure(cam_comp);

    } else {
        // default values
        info.fov_radians = linalg.to_radians(cast(f32)65.0);
        info.near_plane  = 0.01;
        info.far_plane   = 1000.0;

        // Fill with default tranform
        info.position_ws  = [3]f32{0,0,0};
        info.direction_ws = TRANSFORM_WORLD_FORWARD;
        info.view_mat     = linalg.MATRIX4F32_IDENTITY;
        info.proj_mat     = linalg.matrix4_perspective_f32(info.fov_radians, frame_aspect_ratio , info.near_plane, info.far_plane, flip_z_axis = true);
    	info.camera_exposure = linalg.pow(f32(2.0), -8.0);
    }

    info.view_proj_mat 		= info.proj_mat * info.view_mat;

    info.inv_view_mat 		= linalg.inverse(info.view_mat);
    info.inv_proj_mat 		= linalg.inverse(info.proj_mat);
    info.inv_view_proj_mat 	= linalg.inverse(info.view_proj_mat);


    // Calc shadow map cascade projection matrecies
    // These are effectivly subregions of our main camera frustum.
    // the really only need to be recalculated if the split values change or aspect ratio or fov.
    // however i dont feel like abstracting on those combinations so we just redo it every frame.
    {

	    split_1 : f32 = linalg.lerp(info.near_plane, info.far_plane, universe.shadow_cascade_split_1);
	    split_2 : f32 = linalg.lerp(info.near_plane, info.far_plane, universe.shadow_cascade_split_2);
	    split_3 : f32 = linalg.lerp(info.near_plane, info.far_plane, universe.shadow_cascade_split_3);

	    info.shadow_cascade_proj_mats[0] = linalg.matrix4_perspective_f32(info.fov_radians, frame_aspect_ratio, info.near_plane, split_1, flip_z_axis = true);
	    info.shadow_cascade_proj_mats[1] = linalg.matrix4_perspective_f32(info.fov_radians, frame_aspect_ratio, split_1, split_2, flip_z_axis = true);
	    info.shadow_cascade_proj_mats[2] = linalg.matrix4_perspective_f32(info.fov_radians, frame_aspect_ratio, split_2, split_3, flip_z_axis = true);
    }


    // Frustum Culling Stuff

    // if we want to use a different camera for frustum cullling math that main camera
    // useful for debugging 
    if ecs_component_is_attached(&universe.ecs, universe.frustum_cull_camera_entity, .Camera) {
           
        cam_transform := ecs_get_transform(&universe.ecs, universe.frustum_cull_camera_entity);
        cam_comp, err := ecs_get_component(&universe.ecs, universe.frustum_cull_camera_entity, CameraComponent);
        
        info.frustum_view_mat = calc_view_matrix(cam_transform);
        info.frustum_proj_mat = comp_camera_get_projection_matrix(cam_comp, frame_aspect_ratio);

        info.culling_frustum = create_culling_frustum(frame_aspect_ratio, linalg.to_radians(cam_comp.fov_deg), cam_comp.near_clip, cam_comp.far_clip);
        
        // nocheckin
        // calculate shadow cascade projections for debug camera..

		split_1 : f32 = linalg.lerp(info.near_plane, info.far_plane, universe.shadow_cascade_split_1);
	    split_2 : f32 = linalg.lerp(info.near_plane, info.far_plane, universe.shadow_cascade_split_2);
	    split_3 : f32 = linalg.lerp(info.near_plane, info.far_plane, universe.shadow_cascade_split_3);

        info.shadow_cascade_proj_mats[0] = linalg.matrix4_perspective_f32(linalg.to_radians(cam_comp.fov_deg), frame_aspect_ratio, cam_comp.near_clip, split_1, flip_z_axis = true);
        info.shadow_cascade_proj_mats[1] = linalg.matrix4_perspective_f32(linalg.to_radians(cam_comp.fov_deg), frame_aspect_ratio, split_1, split_2, flip_z_axis = true);
    	info.shadow_cascade_proj_mats[2] = linalg.matrix4_perspective_f32(linalg.to_radians(cam_comp.fov_deg), frame_aspect_ratio, split_2, split_3, flip_z_axis = true);

    } else {
        
        info.culling_frustum = create_culling_frustum(frame_aspect_ratio, info.fov_radians, info.near_plane, info.far_plane);
        info.frustum_view_mat = info.view_mat;
        info.frustum_proj_mat = info.proj_mat;
    }
}


@(private="file")
universe_manager_recreate_matrix_buffers :: proc(gpu_device: ^sdl.GPUDevice, curr_gpu_buffer : ^sdl.GPUBuffer, curr_transfer_buffer : ^sdl.GPUTransferBuffer, byte_size : u32) -> (^sdl.GPUBuffer, ^sdl.GPUTransferBuffer){

	if curr_gpu_buffer != nil {
		sdl.ReleaseGPUBuffer(gpu_device, curr_gpu_buffer);
	}

	if curr_transfer_buffer != nil {
		sdl.ReleaseGPUTransferBuffer(gpu_device, curr_transfer_buffer);
	}

	gpu_buf_create_info : sdl.GPUBufferCreateInfo = {
		usage = {sdl.GPUBufferUsageFlag.GRAPHICS_STORAGE_READ, sdl.GPUBufferUsageFlag.COMPUTE_STORAGE_READ},
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
universe_update_matrix_buffer :: proc(gpu_device : ^sdl.GPUDevice, universe : ^Universe) {


	drawables : ^#soa[dynamic]Drawable = &universe.ecs.drawables;

	universe.matrix_upload_info.requires_upload = false;
	universe.matrix_upload_info.transfer_buf_location = {};
	universe.matrix_upload_info.transfer_buf_region = {};
	
	if len(drawables) == 0 {
		return;
	}

	min_index : int = len(drawables);
	max_index : int = -1;

	// update non static transforms cpu side.
	{
		last_entity : Entity = drawables.entity[0];
		ent_transform := ecs_get_transform(&universe.ecs, last_entity).transform;

		for i in 0..<len(drawables) {

			if MeshInstanceFlag.IS_STATIC not_in drawables.mesh_instance[i].flags {

				if last_entity.id != drawables.entity[i].id {

					last_entity = drawables.entity[i];
					ent_transform = ecs_get_transform(&universe.ecs, drawables.entity[i]).transform;
				}

				world_transform := transform_child_by_parent(ent_transform, drawables.mesh_instance[i].transform);

				aabb := mesh_manager_get_aabb(engine.mesh_manager, drawables.mesh_instance[i].mesh_id);

				drawables.world_obb[i] = aabb_to_transformed_obb(aabb, world_transform);
				drawables.world_mat[i] = calc_transform_matrix(world_transform);

				min_index = min(min_index, i);
				max_index = max(max_index, i);
			}
		}
	}


	required_gpu_buf_byte_size : int = len(drawables) * size_of(matrix[4,4]f32);

	require_complete_reupload : bool = required_gpu_buf_byte_size != universe.matrix_buf_byte_size;

	if require_complete_reupload {
		// Recreate buffers and reupload everything.
		defer {
			universe.matrix_buf_byte_size = required_gpu_buf_byte_size;
		}

		if required_gpu_buf_byte_size == 0 {
			return; // this would mean we have nothing to draw at all.
		}

		universe.matrix_upload_info.requires_upload = true;
		universe.matrix_buf, universe.matrix_transfer_buf = universe_manager_recreate_matrix_buffers(gpu_device, universe.matrix_buf, universe.matrix_transfer_buf, cast(u32)required_gpu_buf_byte_size);


		// Reupload entire gpu buffer to transfer buffer
		transfer_buf_data_ptr : rawptr = sdl.MapGPUTransferBuffer(gpu_device, universe.matrix_transfer_buf, false);
		{
			byte_ptr: [^]byte = cast([^]byte)transfer_buf_data_ptr;
			
			mem.copy_non_overlapping(&byte_ptr[0], &drawables.world_mat[0], required_gpu_buf_byte_size);
		}
		sdl.UnmapGPUTransferBuffer(gpu_device, universe.matrix_transfer_buf);

		universe.matrix_upload_info.transfer_buf_location = {
    		transfer_buffer = universe.matrix_transfer_buf,
    		offset = 0,
    	}

    	universe.matrix_upload_info.transfer_buf_region = {
    		buffer = universe.matrix_buf,
    		offset = 0,
    		size = cast(u32)required_gpu_buf_byte_size,
    	}

    	return;
	}


	num_drawables : int = len(drawables);

	if min_index >= num_drawables || max_index <= -1 {
		return;
	}


	engine_assert(min_index >= 0 && min_index < num_drawables);
	engine_assert(max_index >= 0 && max_index < num_drawables);
	engine_assert(max_index >= min_index);


	mat_size : int = size_of(matrix[4,4]f32);

	starting_byte : int = min_index *  mat_size;
	copy_byte_size : int = (max_index + 1 - min_index) * mat_size;


	transfer_buf_data_ptr : rawptr = sdl.MapGPUTransferBuffer(gpu_device, universe.matrix_transfer_buf, true);
	{
		byte_ptr: [^]byte = cast([^]byte)transfer_buf_data_ptr;
		
		mem.copy_non_overlapping(&byte_ptr[starting_byte], &drawables.world_mat[min_index], copy_byte_size);
	}
	sdl.UnmapGPUTransferBuffer(gpu_device, universe.matrix_transfer_buf);

	universe.matrix_upload_info.requires_upload = true;

	universe.matrix_upload_info.transfer_buf_location = {
		transfer_buffer = universe.matrix_transfer_buf,
		offset = cast(u32)starting_byte,
	}

	universe.matrix_upload_info.transfer_buf_region = {
		buffer = universe.matrix_buf,
		offset = cast(u32)starting_byte,
		size = cast(u32)copy_byte_size,
	}
}