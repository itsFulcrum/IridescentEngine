package iri

import "core:log"

import iria "iriasset"
import iricom "iricommon"


MeshRendererComponent :: struct{
	using common : ComponentCommon,

	draw_groups : [dynamic]iricom.DrawGroup
}

@(private="package")
comp_meshrenderer_init :: proc (comp: ^MeshRendererComponent){
	if comp == nil {
		return;
	}

	#force_inline comp_meshrenderer_set_defaults(comp);
}

@(private="package")
comp_meshrenderer_deinit :: proc(comp: ^MeshRendererComponent){
	
	if comp == nil {
		return;
	}

	#force_inline comp_meshrenderer_set_defaults(comp);

	// This should be a safe way to remove all drawables 
	// because ecs_drawable_remove may update indexes of this components
	// array we cannot just iterate normally. But by doing a while loop
	// and first poping it should be safe.
	#reverse for &group, group_index in comp.draw_groups {
		comp_meshrenderer_remove_draw_group(comp, group_index);
	}

	delete(comp.draw_groups);
}


comp_meshrenderer_set_defaults :: proc(comp : ^MeshRendererComponent){
	// if(comp == nil){
	// 	return;
	// }
}


// =====================================================================
// Component procedures
// =====================================================================


// Get the draw instance that the specific primitve in the draw_group references.
// mostly for internal and editor usage. To Add Model Materials use the other procedures that take AssetID's directly.
comp_meshrenderer_get_draw_instance :: proc(comp : ^MeshRendererComponent, group_index : int, draw_index_in_group : int) -> ^DrawInstance {
	
	if !comp_meshrenderer_is_valid_group_index(comp, group_index) {
		return nil;
	}

	group := comp.draw_groups[group_index];

	if draw_index_in_group < 0 || draw_index_in_group >= len(group.drawable_index_refs){
		return nil;
	}

	drawable_index := group.drawable_index_refs[draw_index_in_group].drawable_index
	return ecs_drawable_get_draw_instance(comp.parent_ecs, drawable_index);
}

// Force Update everything by just passing the component. Optionally specify a group_index if only force updating one group. 
// Also optinally specfy a specific draw_index_in_group if only force updating one drawable inside the group.
comp_meshrenderer_force_update :: proc(comp : ^MeshRendererComponent, group_index : int = - 1, draw_index_in_group : int = -1){

	if comp_meshrenderer_is_valid_group_index(comp, group_index) {
		

		group := & comp.draw_groups[group_index];

		if draw_index_in_group >= 0 && draw_index_in_group < len(group.drawable_index_refs) {

			ecs_drawable_force_update(comp.parent_ecs, group.drawable_index_refs[draw_index_in_group].drawable_index);
			return;
		}

		for index_ref in group.drawable_index_refs {

			ecs_drawable_force_update(comp.parent_ecs, index_ref.drawable_index);
		}

		return;
	}

	// otherwise force update everything.
	ecs_entity_force_update(comp.parent_ecs, comp.entity);
}

// Add a Model Asset to the MeshRenderer
comp_meshrenderer_add_model_asset :: proc(comp : ^MeshRendererComponent, asset_id : AssetID) -> (group_index : int) {

	asset_manager 	  := engine.asset_manager
	mesh_manager  	  := engine.mesh_manager;
	material_manager  := engine.material_manager;
	pipe_manager      := engine.pipeline_manager;

	model_runtime_handle, model_load_ok := asset_io_load_model_asset(asset_manager, mesh_manager, asset_id);

	if !model_load_ok {
		return -1;
	}
	
	draw_group := iricom.DrawGroup {
		asset_id = asset_id,
		asset_drawable_type = iricom.DrawGroupAssetType.Model,
	}

	engine_assert(len(model_runtime_handle.mesh_ids) == len(model_runtime_handle.material_asset_ids));

	gpu_device := get_gpu_device();

	for submesh_index in 0..<len(model_runtime_handle.mesh_ids) {


		mesh_id : MeshID = mesh_manager_is_valid_id(mesh_manager, model_runtime_handle.mesh_ids[submesh_index]) ? model_runtime_handle.mesh_ids[submesh_index] : MeshID_INVALID;

		mat_asset_id : AssetID = model_runtime_handle.material_asset_ids[submesh_index];
		
		//mat_id : MaterialID = asset_io_load_material_asset_by_id(asset_manager, material_manager, mat_asset_id) or_else 0;
		mat_handle : AssetHandleMaterial = asset_io_load_material_asset(asset_manager, material_manager, mat_asset_id) or_else AssetHandleMaterial{};
		mat_id : MaterialID = mat_handle.mat_id;
		
		// init new drawable
		drawable := Drawable{entity = comp.entity};
		drawable.draw_instance.flags     = DRAW_INSTANCE_FLAGS_DEFAULT;
		drawable.draw_instance.transform = mesh_manager_get_original_transform(mesh_manager, mesh_id);
				
		drawable.draw_instance.mesh_id   = mesh_id;
		drawable.draw_instance.mat_id 	 = mat_id;

		drawable_index : int = ecs_drawable_add(comp.parent_ecs, comp.entity, &drawable);

		index_ref := iricom.DrawableIndexReference {
			drawable_index = drawable_index,
			material_asset_id = mat_asset_id,
		}

		append(&draw_group.drawable_index_refs, index_ref);

		build_pipeline_cache :: true
		if build_pipeline_cache && mat_id > 0 {

			pipe_manager_update_depthonly_pipeline_cache_with_material(pipe_manager, gpu_device, material_manager, mat_id);

			if mesh_id != MeshID_INVALID {

				gpu_data := mesh_manager_get_mesh_gpu_data(mesh_manager, mesh_id);
				engine_assert(gpu_data != nil); // this holds because we checked id for valid above. otherwise it wouldnt!

				pipe_manager_update_material_pipeline_cache_with_material_and_vertex_layouts(pipe_manager, gpu_device, material_manager, mat_id, {gpu_data.vertex_layout});
			}
		}
	}

	group_index = len(comp.draw_groups);

	append(&comp.draw_groups, draw_group);

	ecs_entity_force_update(comp.parent_ecs, comp.entity);


	return group_index;
}

// Remove a specifc draw group from the MeshRenderer
comp_meshrenderer_remove_draw_group :: proc(comp : ^MeshRendererComponent, group_index : int){

	if !comp_meshrenderer_is_valid_group_index(comp, group_index){
		return;
	}

	group := &comp.draw_groups[group_index];

	asset_manager 		:= engine.asset_manager;
	material_manager 	:= engine.material_manager;
	mesh_manager 		:= engine.mesh_manager;

	for len(group.drawable_index_refs) > 0 {	
		index_ref := pop(&group.drawable_index_refs);
		ecs_drawable_remove(comp.parent_ecs, &index_ref.drawable_index);

		asset_io_return_material_asset(asset_manager, material_manager, index_ref.material_asset_id);
	}

	delete(group.drawable_index_refs);


	switch group.asset_drawable_type {
		case .Model: {
	 		asset_io_return_model_asset(asset_manager, mesh_manager, group.asset_id);
		}
	}


	ordered_remove(&comp.draw_groups, cast(int)group_index);
}

comp_meshrenderer_assign_material_asset_to_draw_instance_in_draw_group :: proc(comp : ^MeshRendererComponent, asset_id : AssetID, group_index : int , draw_index : int){
	
	if !comp_meshrenderer_is_valid_group_index(comp, group_index){
		return
	}

	group := &comp.draw_groups[group_index]

	if draw_index < 0 || draw_index >= len(group.drawable_index_refs) {
		return
	}

	asset_manager := engine.asset_manager;
	material_manager := engine.material_manager;
		
	new_mat_handle, load_ok := asset_io_load_material_asset(asset_manager, material_manager, asset_id);
	if !load_ok {
		return;
	}

	index_ref := &group.drawable_index_refs[draw_index];

	if index_ref.material_asset_id != AssetID_NONE {
		asset_io_return_material_asset(asset_manager, material_manager, index_ref.material_asset_id);
	}

	group.drawable_index_refs[draw_index].material_asset_id = asset_id

	draw_inst := ecs_drawable_get_draw_instance(comp.parent_ecs, index_ref.drawable_index);
	if draw_inst != nil {
		draw_inst.mat_id = new_mat_handle.mat_id;
	}
}

// Mostly for internal use when loading scene files.
comp_meshrenderer_add_asset_draw_groups :: proc(comp : ^MeshRendererComponent, asset_draw_groups : []iria.AssetDrawGroup, build_pipeline_cache : bool = true){

	asset_manager 		:= engine.asset_manager
	mesh_manager 		:= engine.mesh_manager;
	material_manager 	:= engine.material_manager;
	pipe_manager 		:= engine.pipeline_manager;

	gpu_device := get_gpu_device();

	asset_group_loop: for &asset_draw_group in asset_draw_groups {


		draw_group := iricom.DrawGroup {
			asset_id = asset_draw_group.asset_id,
			asset_drawable_type = asset_draw_group.asset_drawable_type,
		}

		switch asset_draw_group.asset_drawable_type {
			case .Model: {

				model_runtime_handle, model_load_ok := asset_io_load_model_asset(asset_manager, mesh_manager, asset_draw_group.asset_id);

				if !model_load_ok {
					log.warnf("Meshrenderer: Failed to load model asset from draw group. AssetID: {}", iria.asset_id_to_string(asset_draw_group.asset_id))
					continue asset_group_loop;
				}

				num_primitives : int = cast(int)asset_draw_group.num_primitives;
				// Sanity checks
				engine_assert(num_primitives == len(model_runtime_handle.mesh_ids))
				engine_assert(len(model_runtime_handle.mesh_ids) == len(model_runtime_handle.material_asset_ids));
				

				for submesh_index in 0..<num_primitives {

					mesh_id := model_runtime_handle.mesh_ids[submesh_index];
					if !mesh_manager_is_valid_id(mesh_manager, mesh_id) {
						mesh_id = MeshID_INVALID;
					}
					
					//mat_asset_id : AssetID = model_runtime_handle.material_asset_ids[submesh_index];
					mat_asset_id : AssetID = asset_draw_group.material_asset_ids[submesh_index];

					mat_handle, handle_ok := asset_io_load_material_asset(asset_manager, material_manager, mat_asset_id);
					
					mat_id : MaterialID = handle_ok ? mat_handle.mat_id : 0;

					// Initialize and Create new drawable even if bot mesh and material ids are invalid!

					drawable := Drawable{entity = comp.entity}
					drawable.draw_instance.flags     = asset_draw_group.flags[submesh_index]
					drawable.draw_instance.transform = asset_draw_group.transforms[submesh_index]

					drawable.draw_instance.mesh_id = mesh_id;
					drawable.draw_instance.mat_id = mat_id;

					drawable_index : int = ecs_drawable_add(comp.parent_ecs, comp.entity, &drawable);

					index_ref := iricom.DrawableIndexReference {
						drawable_index = drawable_index,
						material_asset_id = mat_asset_id,
					}

					append(&draw_group.drawable_index_refs, index_ref);

					if build_pipeline_cache && mat_id > 0 {

						pipe_manager_update_depthonly_pipeline_cache_with_material(pipe_manager, gpu_device, material_manager, mat_id);

						if mesh_id != MeshID_INVALID {
							gpu_data := mesh_manager_get_mesh_gpu_data(mesh_manager, mesh_id);
							engine_assert(gpu_data != nil); // this holds because we checked id for valid above. otherwise it wouldnt!

							pipe_manager_update_material_pipeline_cache_with_material_and_vertex_layouts(pipe_manager, gpu_device, material_manager, mat_id, {gpu_data.vertex_layout});
						}
					}
				}
			}
		}

		append(&comp.draw_groups, draw_group);
	}


	ecs_entity_force_update(comp.parent_ecs, comp.entity);
}

// specifiy group index if it should only apply to one group. 
comp_meshrenderer_add_or_remove_draw_instance_flags_all :: proc(comp : ^MeshRendererComponent,flags : DrawInstanceFlags, remove_flags_instead : bool = false, group_index : int = -1) {

	if len(comp.draw_groups) <= 0 {
		return;
	}

	non_internal_flags := flags - iricom.DRAW_INSTANCE_FLAGS_INTERNAL;

	specified_valid_group_index : bool = group_index >= 0 && group_index < len(comp.draw_groups);

	for &group, g_index in comp.draw_groups {

		if specified_valid_group_index && group_index != g_index {
			continue;
		}

		if len(group.drawable_index_refs) <= 0 {
			continue;
		}

		for draw_index_ref in group.drawable_index_refs {
			draw_inst := ecs_drawable_get_draw_instance(comp.parent_ecs, draw_index_ref.drawable_index);

			if remove_flags_instead {
				draw_inst.flags -= non_internal_flags
			} else {
				draw_inst.flags += non_internal_flags
			}
		}
	}
}

@(private="file")
comp_meshrenderer_is_valid_group_index :: #force_inline proc "contextless" (comp : ^MeshRendererComponent, group_index : int) -> bool {
	return group_index >= 0 && group_index < len(comp.draw_groups);
}