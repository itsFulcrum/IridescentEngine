package iri

import "core:log"
import "core:mem"
import "core:math/linalg"
import "core:sort"
import "odinary:mathy"
import geo "odinary:geometry"

import sdl "vendor:sdl3"

@(private="file")
tmp_store_universe_ptr : ^Universe = nil; // because we need it inside sort procedures. // we could use active universe from engine but maybe we want to update non active universes in the future.

@(private="package")
universe_manager_update_universe :: proc(gpu_device : ^sdl.GPUDevice, universe : ^Universe, frame_size : [2]u32, fixed_alpha_interpolator : f32){

	IRI_PROFILE_PROCEDURE()

	perfs := get_performance_counters();

	universe_update_timer := timer_begin();
	defer perfs.universe_total_update_time_ms = timer_end_get_miliseconds(universe_update_timer);
	
	if universe == nil {
		return;
	}

	frame_aspect_ratio : f32 = cast(f32)frame_size.x / cast(f32)frame_size.y;

	universe_update_frame_camera_info(universe, frame_aspect_ratio, fixed_alpha_interpolator);

	if universe.ecs.active_skybox_is_dirty {
		
		sky_comp := ecs_get_active_skybox_component(&universe.ecs);

		if sky_comp == nil {
			skybox_gpu_data_set_defaults(&universe.skybox_data);
		} else {

			sky_data := &universe.skybox_data;

			has_cubemap_texture : bool = sky_comp.cubemap.binding.texture != nil;

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


	light_manager_frame_update(gpu_device, universe, fixed_alpha_interpolator);

	ecs := &universe.ecs;
	drawables : ^#soa[dynamic]Drawable = &universe.ecs.drawables;

	// ==== update drawables ====

	{
		IRI_PROFILE_SCOPE("Universe Update: Update Drawables")
		// Here we produce a subset of drawables that includes all renderable drawables
		// which means they have a valid mesh/material to render with 
		// and entity is enabled. We update _Internal draw inst flags accordingly.
		clear(&universe.frame_renderables);

		entity : Entity = EntityInvalid;
		entity_flags := EntityFlags{};

		for i in 0..<len(drawables) {

			entity = drawables.entity[i];

			if !ecs_entity_exists_officially(ecs, entity) {
				continue;
			}

			entity_flags = ecs.entity_infos.flags[entity.id];
			

			// We do this here for EVERY Drawable before we start culling out any.
			if ._Internal_ForceUpdate in entity_flags {
				drawables[i].prev_physics_world_transform = transform_child_by_parent(ecs.transform_components[entity.id].transform, drawables.draw_instance[i].transform);
			}
			
			if ._Internal_IsEnabled not_in entity_flags {
				continue;
			}
			
			draw_flags := drawables.draw_instance[i].flags;

			if !mesh_manager_is_valid_id(engine.mesh_manager, drawables.draw_instance[i].mesh_id) {
				if ._Internal_NoValidMesh not_in draw_flags {
					drawables.draw_instance[i].flags += DrawInstanceFlags{._Internal_NoValidMesh};
				}
				continue;
			} else if ._Internal_NoValidMesh in draw_flags {
				drawables.draw_instance[i].flags -= DrawInstanceFlags{._Internal_NoValidMesh}; 
			}

			append(&universe.frame_renderables, cast(u32)i);
		}
	}


	universe_update_matrix_buffer(gpu_device, universe, &universe.frame_renderables, fixed_alpha_interpolator);

	// @Note: this we could do on another thread or do a worker job.
	{
		tlas_timer := timer_begin();
		tl_bvh_rebuild(gpu_device, universe, engine.mesh_manager, universe.settings.bvh_num_split_planes, universe.settings.bvh_max_tree_depth);
		perfs.tl_bvh_cpu_ms = timer_end_get_miliseconds(tlas_timer);
	}

	// Create a list of indexes into drawables that are inside camera frustum

	// Cull Drawables for Camera into frame_renderables
	{
		IRI_PROFILE_SCOPE("Universe Update: Camera Frustum Culling")

		cull_timer := timer_begin();
		culled_instances : u32 = 0;
		defer {
			perfs.frustum_culling_time_ms = timer_end_get_miliseconds(cull_timer);
			perfs.frustum_culled_instance = culled_instances;
		}

		material_manager := engine.material_manager;
		camera_info := &universe.frame_camera_info;

		clear(&universe.frame_camera_visible);
		clear(&universe.frame_shadow_draws);

		for drawable_index in universe.frame_renderables {

			flags := drawables.draw_instance[drawable_index].flags;

			shadow_draws: if .CastShadows in flags {
				
				mat_id  := ecs.drawables[drawable_index].draw_instance.mat_id;
				mat := material_manager_get_material_unsafe(material_manager, mat_id);

				if mat.render_technique.alpha_mode == .Blend {
					break shadow_draws;
				}

				shadow_drawable_info := ShadowDrawableInfo{
					shader_type = mat.render_technique.alpha_mode == .Opaque ? DepthOnlyPipelineShaders.Shadowmap : DepthOnlyPipelineShaders.ShadowmapAlphaTest,
					drawable_index = drawable_index,
					technique_hash = material_manager_get_render_technique_hash_unsafe(material_manager, mat_id),
				}
				
				append(&universe.frame_shadow_draws, shadow_drawable_info);
			}

			if .IsVisible in flags {
				
				if universe.do_frustum_culling {
					if obb_overlaps_frustum(camera_info.culling_frustum, camera_info.frustum_view_mat, drawables.world_oobb[drawable_index]) {
						append(&universe.frame_camera_visible, drawable_index);
					} else {
						culled_instances += 1;
					}
				} else {
					append(&universe.frame_camera_visible, drawable_index);
				}
			}
		}
	}

	// Sort renderables into subbuckets of Opaque, Alpha test and Alpha Blend

	{
		IRI_PROFILE_SCOPE("Universe Update: Bucket sort frame camera visible")

		clear(&universe.frame_opaques);
		clear(&universe.frame_alpha_test);
		clear(&universe.frame_alpha_blend);

		for drawable_index in universe.frame_camera_visible {
			
			mat_id := drawables.draw_instance[drawable_index].mat_id;

	        material := material_get_by_id(mat_id);
	        
	        engine_assert(material != nil); // if id is invalid this should return us the default mat.
	        
	        switch material.render_technique.alpha_mode {
	        	case .Opaque: 	append(&universe.frame_opaques, drawable_index);
	        	case .Clip:		append(&universe.frame_alpha_test, drawable_index);
	        	case .Hashed:	append(&universe.frame_alpha_test, drawable_index);
	        	case .Blend: 	append(&universe.frame_alpha_blend, drawable_index);
	        }
	    
	    }
	}

    // Sort 

    {
    	IRI_PROFILE_SCOPE("Universe Update: Sort Frame Opaque by render technique")	
    	// @Note: here we are 'bubble' sorting frame_opaques by technique hash
    	material_manager := engine.material_manager;

    	// Frame opaques MUST at this stage not contain any invalid material ids.
		for i := 1; i < len(universe.frame_opaques)-1; i+=1 {
			
			i_mat_id  := drawables.draw_instance[i].mat_id;
			i1_mat_id := drawables.draw_instance[i-1].mat_id;

			i_tech_hash  := material_manager_get_render_technique_hash_unsafe(material_manager, i_mat_id);
			i1_tech_hash := material_manager_get_render_technique_hash_unsafe(material_manager, i1_mat_id);

			//pipe_manager_get_material_pipeline_variant(engine.pipeline_manager, )

			if i_tech_hash == i1_tech_hash { 
				continue; // early out if already the same as the last one
			}

			for j := i+1; j < len(universe.frame_opaques); j+=1 {

				j_mat_id := drawables[j].draw_instance.mat_id;
				j_tech_hash := material_manager_get_render_technique_hash_unsafe(material_manager, j_mat_id);

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

    SORT_SHADOW_DRAWS :: true
    when SORT_SHADOW_DRAWS {
    	
    	shadow_draw_sort_proc :: proc(a : ShadowDrawableInfo, b : ShadowDrawableInfo) -> int {

    		if a.shader_type == .Shadowmap && b.shader_type == .ShadowmapAlphaTest {
    			return -1;
    		}

    		if a.shader_type == .ShadowmapAlphaTest && b.shader_type == .Shadowmap {
    			return 1;
    		}

    		if a.technique_hash < b.technique_hash {
    			return -1;
    		}

    		return 1;
    	}

    	if len(universe.frame_shadow_draws) > 2 {
    		IRI_PROFILE_SCOPE("Universe Update: Sort Shadowmap Draws by render technique")

    		tmp_store_universe_ptr = universe;
	    	defer tmp_store_universe_ptr = nil;   		

	    	sort.quick_sort_proc(universe.frame_shadow_draws[:], shadow_draw_sort_proc);
    	}
    }


    // TODO: sort blend meshes

    SORT_BLEND_MESHES_BY_DISTANCE :: true
    when SORT_BLEND_MESHES_BY_DISTANCE {

    	if len(universe.frame_alpha_blend) > 1 {
    		IRI_PROFILE_SCOPE("Universe Update: Sort Frame alpha blend draws by camera distance")

	    	tmp_store_universe_ptr = universe;
	    	defer tmp_store_universe_ptr = nil;

	    	alpha_blend_sort_proc :: proc(a : u32, b : u32) -> int {

	    		a_to_cam := tmp_store_universe_ptr.frame_camera_info.position_ws - tmp_store_universe_ptr.ecs.drawables[a].world_oobb.center.xyz;
	    		b_to_cam := tmp_store_universe_ptr.frame_camera_info.position_ws - tmp_store_universe_ptr.ecs.drawables[b].world_oobb.center.xyz;

	    		// sort back to front based on distance squared to camera.
	    		if linalg.dot(a_to_cam, a_to_cam) <= linalg.dot(b_to_cam, b_to_cam)  {
	    			return 1;
	    		}

	    		return -1;
	    	}

	    	sort.quick_sort_proc(universe.frame_alpha_blend[:], alpha_blend_sort_proc);


    	}
    }



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
universe_update_frame_camera_info :: proc (universe : ^Universe, frame_aspect_ratio : f32, fixed_alpha_interpolator : f32){

	IRI_PROFILE_PROCEDURE()

	info : ^FrameCameraInfo = &universe.frame_camera_info;

    if cam_comp := ecs_get_active_camera_component(&universe.ecs); cam_comp != nil {

        cam_transform := ecs_get_transform(&universe.ecs, universe.ecs.active_camera_entity).transform;

        ent_flags := universe.ecs.entity_infos.flags[cam_comp.entity.id];

        if .PhysicsInterpolation in ent_flags && ._Internal_ForceUpdate not_in ent_flags {
        	prev_trans := universe.ecs.previous_physics_transforms[cam_comp.entity.id];
        	cam_transform = transform_interpolate( prev_trans, cam_transform , fixed_alpha_interpolator);
        }

        info.position_ws = cam_transform.position;
        info.direction_ws = get_forward(cam_transform);
            
        info.view_mat = transform_calc_view_matrix(cam_transform);

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
        
        info.frustum_view_mat = transform_calc_view_matrix(cam_transform);
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

@(private="package")
universe_manager_recreate_gpu_buffers :: proc(gpu_device: ^sdl.GPUDevice, curr_gpu_buffer : ^sdl.GPUBuffer, curr_transfer_buffer : ^sdl.GPUTransferBuffer, byte_size : u32) -> (^sdl.GPUBuffer, ^sdl.GPUTransferBuffer){
	IRI_PROFILE_PROCEDURE()

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
universe_update_matrix_buffer :: proc(gpu_device : ^sdl.GPUDevice, universe : ^Universe, frame_renderables : ^[dynamic]u32, fixed_alpha_interpolator : f32) {

	IRI_PROFILE_PROCEDURE()

	ecs := &universe.ecs;
	drawables : ^#soa[dynamic]Drawable = &universe.ecs.drawables;

	// Reset upload infos.
	universe.matrix_upload_info.requires_upload 		= false;
	universe.matrix_upload_info.transfer_buf_location 	= {};
	universe.matrix_upload_info.transfer_buf_region   	= {};
	
	universe.inv_matrix_upload_info.requires_upload 	  = false;
	universe.inv_matrix_upload_info.transfer_buf_location = {};
	universe.inv_matrix_upload_info.transfer_buf_region   = {};

	upload_info_reset(&universe.drawables_globals_info_buf.upload_info);
	// universe.tlas_leaf_info_upload_info.requires_upload 	  = false;
	// universe.tlas_leaf_info_upload_info.transfer_buf_location = {};
	// universe.tlas_leaf_info_upload_info.transfer_buf_region   = {};


	if len(drawables) == 0 {
		return;
	}

	// These are effective drawable indexes
	min_index : int = len(drawables);
	max_index : int = -1;

	// update drawables and track where we need to update the data!
	{
		// We only need to update what may be visibile in any way so we operate on the frame_renderables
		// which already sorted out drawables with no valid meshes and disabled entities.

		for drawable_index in frame_renderables {
			
			entity : Entity = drawables.entity[drawable_index];

			ent_flags := ecs.entity_infos.flags[entity.id];
			draw_flags := drawables.draw_instance[drawable_index].flags;

			can_skip : bool = ._Internal_ForceUpdate not_in ent_flags && ._Internal_ReuploadMatrixGPU not_in draw_flags;

			if .IsStatic in draw_flags && can_skip {
				continue;
			}
			
			world_transform := transform_child_by_parent(ecs.transform_components[entity.id].transform, drawables.draw_instance[drawable_index].transform);			

			if .PhysicsInterpolation in ent_flags {
				world_transform = transform_interpolate(drawables.prev_physics_world_transform[drawable_index], world_transform, fixed_alpha_interpolator);
			}

			drawables.world_mat[drawable_index] = transform_calc_world_matrix(world_transform);
			drawables.inv_world_mat[drawable_index] = linalg.inverse(drawables.world_mat[drawable_index]);

			mesh_id := drawables.draw_instance[drawable_index].mesh_id;

			aabb := mesh_manager_get_aabb(engine.mesh_manager, mesh_id);
			drawables.world_oobb[drawable_index] = geo.obb_from_aabb_and_transform(aabb, world_transform);
			drawables.world_aabb[drawable_index] = geo.obb_to_aabb(drawables.world_oobb[drawable_index]);

			// not sure if we actually need to copy this but playing safe for now.
			// @Note: FIXME: these global buf infos dont actually change on a frame to frame basis, 
			// only if drawables change the underlying mesh which i belive just removes the drawables compleatly and creates a new one anyway.
			// This shouldn't really be handled here.
			mesh_global_buf_info := engine.mesh_manager.meshes[mesh_id].global_buf_info;
			drawables.global_buf_info[drawable_index] = DrawableGlobalBufferInfo {
				bl_bvh_root_offset      = mesh_global_buf_info.bvh_nodes_offset,
				global_indecies_offset  = mesh_global_buf_info.indecies_offset,
				global_vertecies_offset = mesh_global_buf_info.vertecies_offset,
			}

			min_index = min(min_index, cast(int)drawable_index);
			max_index = max(max_index, cast(int)drawable_index);
			upload_info_update_min_max(&universe.drawables_globals_info_buf.upload_info, cast(int)drawable_index, cast(int)drawable_index)
		}
	}

	// drawables Globals. TODO: should not happen in here really.
	{
		globals_buf := &universe.drawables_globals_info_buf;
		upinfo      := &globals_buf.upload_info;

		drawables_globals_element_size : int = size_of(DrawableGlobalBufferInfo)
		drawables_globals_required_byte_size : int = len(drawables) * drawables_globals_element_size;

		if drawables_globals_required_byte_size > cast(int)globals_buf.curr_byte_size {

			gpu_buffer_reallocate_buffers(gpu_device, &universe.drawables_globals_info_buf, cast(u32)drawables_globals_required_byte_size);
			upinfo.requires_upload = true;
			upinfo.region_min_index = 0;
			upinfo.region_max_index = len(drawables) - 1;
		}

		if upinfo.region_max_index >= upinfo.region_min_index {
			upinfo.requires_upload = true;
			gpu_buffer_memcopy_upload_info_min_max_region_to_transfer_buffer(gpu_device,&universe.drawables_globals_info_buf, &drawables.global_buf_info[0],drawables_globals_element_size, true);
		}
	}

	// This accounts for both matrix buffer and inv_matrix buffer!
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
		universe.matrix_buf, universe.matrix_transfer_buf = universe_manager_recreate_gpu_buffers(gpu_device, universe.matrix_buf, universe.matrix_transfer_buf, cast(u32)required_gpu_buf_byte_size);
		
		universe.inv_matrix_upload_info.requires_upload = true;
		universe.inv_matrix_buf, universe.inv_matrix_transfer_buf = universe_manager_recreate_gpu_buffers(gpu_device, universe.inv_matrix_buf, universe.inv_matrix_transfer_buf, cast(u32)required_gpu_buf_byte_size);

		drawables_globals_element_size : int = size_of(DrawableGlobalBufferInfo)
		drawables_globals_required_byte_size : int = len(drawables) * drawables_globals_element_size;

		// matrix buffer
		{

			transfer_buf_data_ptr : rawptr = sdl.MapGPUTransferBuffer(gpu_device, universe.matrix_transfer_buf, false);
			{
				mem.copy_non_overlapping(transfer_buf_data_ptr, &drawables.world_mat[0], required_gpu_buf_byte_size);
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
		}

		// inverse matrix buffer
		{
			inv_matrix_transfer_buf_data_ptr : rawptr = sdl.MapGPUTransferBuffer(gpu_device, universe.inv_matrix_transfer_buf, false);
			{
				mem.copy_non_overlapping(inv_matrix_transfer_buf_data_ptr, &drawables.inv_world_mat[0], required_gpu_buf_byte_size);
			}
			sdl.UnmapGPUTransferBuffer(gpu_device, universe.inv_matrix_transfer_buf);

			universe.inv_matrix_upload_info.transfer_buf_location = {
	    		transfer_buffer = universe.inv_matrix_transfer_buf,
	    		offset = 0,
	    	}

	    	universe.inv_matrix_upload_info.transfer_buf_region = {
	    		buffer = universe.inv_matrix_buf,
	    		offset = 0,
	    		size = cast(u32)required_gpu_buf_byte_size,
	    	}
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

	// update region for matrix and inv_matrix buffer which is same byte region just on different buffers.
	{
		matrix_byte_size : int = size_of(matrix[4,4]f32);

		starting_byte : int = min_index *  matrix_byte_size;
		copy_byte_size : int = (max_index + 1 - min_index) * matrix_byte_size;

		mat_transfer_buf_data_ptr : rawptr = sdl.MapGPUTransferBuffer(gpu_device, universe.matrix_transfer_buf, true);
		{
			byte_ptr: [^]byte = cast([^]byte)mat_transfer_buf_data_ptr;			
			mem.copy_non_overlapping(&byte_ptr[starting_byte], &drawables.world_mat[min_index], copy_byte_size);
		}
		sdl.UnmapGPUTransferBuffer(gpu_device, universe.matrix_transfer_buf);


		inv_mat_transfer_buf_data_ptr : rawptr = sdl.MapGPUTransferBuffer(gpu_device, universe.inv_matrix_transfer_buf, true);
		{
			byte_ptr: [^]byte = cast([^]byte)inv_mat_transfer_buf_data_ptr;			
			mem.copy_non_overlapping(&byte_ptr[starting_byte], &drawables.inv_world_mat[min_index], copy_byte_size);
		}
		sdl.UnmapGPUTransferBuffer(gpu_device, universe.inv_matrix_transfer_buf);

		universe.matrix_upload_info.requires_upload = true;
		universe.inv_matrix_upload_info.requires_upload = true;

		universe.matrix_upload_info.transfer_buf_location = {
			transfer_buffer = universe.matrix_transfer_buf,
			offset = cast(u32)starting_byte,
		}

		universe.matrix_upload_info.transfer_buf_region = {
			buffer = universe.matrix_buf,
			offset = cast(u32)starting_byte,
			size   = cast(u32)copy_byte_size,
		}
		// same as matrix buffer just other buffers lel.
		universe.inv_matrix_upload_info = universe.matrix_upload_info;
		universe.inv_matrix_upload_info.transfer_buf_location.transfer_buffer = universe.inv_matrix_transfer_buf;
		universe.inv_matrix_upload_info.transfer_buf_region.buffer = universe.inv_matrix_buf;
	}
}