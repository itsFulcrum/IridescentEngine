package iri

import "core:log"

import iria "iriasset"

MeshRendererComponent :: struct{
	using common : ComponentCommon,

	drawable_indexes : [dynamic]int,
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
	for len(comp.drawable_indexes) > 0 {
		drawable_index := pop(&comp.drawable_indexes);
		ecs_drawable_remove(comp.parent_ecs, &drawable_index);
	}

	delete(comp.drawable_indexes);
}


comp_meshrenderer_set_defaults :: proc(comp : ^MeshRendererComponent){
	// if(comp == nil){
	// 	return;
	// }
}


// =====================================================================
// Component procedures
// =====================================================================

// @Note: Procedures that take and index want the index into the 'drawable_indexes' array of the MeshRendererComponent component.


comp_meshrenderer_create_draw_instance :: proc(comp : ^MeshRendererComponent) {
	
	// actually creates a drawable with a draw instance inside it.
	drawable := Drawable{entity = comp.entity};
	drawable.draw_instance.flags = DRAW_INSTANCE_FLAGS_DEFAULT;
	drawable.draw_instance.mesh_id = -1;
	drawable.draw_instance.transform = transform_create_identity();

	drawable_index : int = ecs_drawable_add(comp.parent_ecs, comp.entity, &drawable);
	
	append(&comp.drawable_indexes, drawable_index);
}

// get the draw instance at the index, returns nil if invalid.
comp_meshrenderer_get_draw_instance :: proc(comp : ^MeshRendererComponent, index : u32) -> ^DrawInstance {
	
	if !comp_meshrenderer_is_valid_index(comp, index) {
		return nil;
	}

	return ecs_drawable_get_draw_instance(comp.parent_ecs, comp.drawable_indexes[index]);
}

comp_meshrenderer_force_update_all_draw_instances :: proc(comp : ^MeshRendererComponent){

	for draw_index in comp.drawable_indexes {

		ecs_drawable_force_update(comp.parent_ecs, draw_index);
	}
}

// Force update bypasses if draw instance is marked as static or entity is disabled.
// usefull for editors mainly because we want to be able to skip static mesh updates usually.
comp_meshrenderer_force_update_draw_instance :: proc(comp : ^MeshRendererComponent, index : u32){
	
	if !comp_meshrenderer_is_valid_index(comp, index) {
		return;
	}

	ecs_drawable_force_update(comp.parent_ecs, comp.drawable_indexes[index]);
}

comp_meshrenderer_remove_draw_instance :: proc(comp : ^MeshRendererComponent, index : u32) {
	
	if !comp_meshrenderer_is_valid_index(comp, index) {
		return;
	}

	ecs_drawable_remove(comp.parent_ecs, &comp.drawable_indexes[index]);

	unordered_remove(&comp.drawable_indexes, cast(int)index);
}

@(private="file")
comp_meshrenderer_is_valid_index :: #force_inline proc(comp : ^MeshRendererComponent, index : u32) -> bool {
	return cast(int)index < len(comp.drawable_indexes);
}


comp_meshrenderer_load_mesh_asset_to_draw_instance :: proc(comp : ^MeshRendererComponent, index : u32, asset_uuid : AssetUUID){

	// we can save an valid index check and just check if this return nil.
	draw_instance := comp_meshrenderer_get_draw_instance(comp, index);

	if draw_instance == nil {
		return;
	}

	asset_manager := engine.asset_manager
	mesh_manager  := engine.mesh_manager;
	pipe_manager  := engine.pipeline_manager;

	gpu_device := get_gpu_device();

	mesh_id := asset_io_load_mesh_asset_id(asset_manager, mesh_manager, asset_uuid) or_else -1;
	
	if mesh_id == -1 {
		return;
	}

	draw_instance.mesh_id   = mesh_id;
	draw_instance.transform = mesh_manager_get_original_transform(mesh_manager, mesh_id);

	comp_meshrenderer_force_update_draw_instance(comp, index);

	// update pipeline caches
	// We need to do this because if a material is on this draw instance
	// it may have pipelines only bulild with a differant vertex data layout
	// then the mesh we are loading now has.
	if material_exists(draw_instance.mat_id) {
		material_manager := engine.material_manager;

  		pipe_manager_update_depthonly_pipeline_cache_with_material(pipe_manager, gpu_device, material_manager, draw_instance.mat_id);
		
		gpu_data := mesh_manager_get_mesh_gpu_data(mesh_manager, mesh_id);

		pipe_manager_update_material_pipeline_cache_with_material_and_vertex_layouts(pipe_manager, gpu_device, material_manager, draw_instance.mat_id, {gpu_data.vertex_layout});
	}

	//mesh_id := mesh_manager_add_mesh(mesh_manager, gpu_device, mesh_data : ^MeshData);
}


comp_meshrenderer_load_material_asset_to_draw_instance :: proc(comp : ^MeshRendererComponent, index : u32, asset_uuid : AssetUUID){

	// we can save an valid index check and just check if this returns nil.
	draw_instance := comp_meshrenderer_get_draw_instance(comp, index);
	if draw_instance == nil {
		return;
	}

	previous_id := draw_instance.mat_id;

	// all the managers, get em.
	asset_manager 		:= engine.asset_manager;
	material_manager 	:= engine.material_manager;
	mesh_manager 		:= engine.mesh_manager;
	pipe_manager 		:= engine.pipeline_manager;
	
	mat_id, load_ok := asset_io_load_material_asset_id(asset_manager, material_manager, asset_uuid) 
	if !load_ok {
		return;
	}

	draw_instance.mat_id = mat_id;

	if  previous_id != draw_instance.mat_id {
		
		gpu_device := get_gpu_device();
	
		pipe_manager_update_depthonly_pipeline_cache_with_material(pipe_manager, gpu_device, material_manager, draw_instance.mat_id);

		if !mesh_manager_is_valid_id(mesh_manager, draw_instance.mesh_id) {
			return;
		}

		gpu_data := mesh_manager_get_mesh_gpu_data(mesh_manager, draw_instance.mesh_id);
		engine_assert(gpu_data != nil); // this holds because we checked id for valid above. otherwise it wont!

		vertex_layout := gpu_data.vertex_layout;

		pipe_manager_update_material_pipeline_cache_with_material_and_vertex_layouts(pipe_manager, gpu_device, material_manager, draw_instance.mat_id, {vertex_layout});
	}
}


comp_meshrenderer_append_scene_collection_asset :: proc(comp : ^MeshRendererComponent, asset_uuid : AssetUUID) {

	// all the managers, get em.
	asset_manager 		:= engine.asset_manager;
	material_manager 	:= engine.material_manager;
	mesh_manager 		:= engine.mesh_manager;
	pipe_manager 		:= engine.pipeline_manager;
	gpu_device 			:= get_gpu_device();


	collection, collection_ok := asset_io_load_scene_collection_asset(asset_manager, asset_uuid);
	if !collection_ok {
		log.warnf("Failed to load collection. AssetUUID for scene_collection is not registered with asset manager: {}", asset_uuid);
		return;
	}
	defer iria.free_scene_collection_asset(collection);


	for &draw_asset in collection.draw_inst_assets {

		drawable := Drawable{entity = comp.entity};
		drawable.draw_instance.flags = draw_asset.flags;

		mat_id  := asset_io_load_material_asset_id(asset_manager, material_manager, draw_asset.mat_uuid) or_else material_manager.fallback_material;
		mesh_id := asset_io_load_mesh_asset_id(asset_manager, mesh_manager, draw_asset.mesh_uuid) or_else -1;
		
		drawable.draw_instance.mat_id  = mat_id;
		drawable.draw_instance.mesh_id = mesh_id
		drawable.draw_instance.transform = mesh_manager_get_original_transform(mesh_manager, mesh_id);
		

		drawable_index : int = ecs_drawable_add(comp.parent_ecs, comp.entity, &drawable);
		append(&comp.drawable_indexes, drawable_index);
		
		if mat_id > 0 {

			pipe_manager_update_depthonly_pipeline_cache_with_material(pipe_manager, gpu_device, material_manager, mat_id);

			if !mesh_manager_is_valid_id(mesh_manager, mesh_id) {
				continue;
			}

			gpu_data := mesh_manager_get_mesh_gpu_data(mesh_manager, mesh_id);
			engine_assert(gpu_data != nil); // this holds because we checked id for valid above. otherwise it wouldnt!

			vertex_layout := gpu_data.vertex_layout;

			pipe_manager_update_material_pipeline_cache_with_material_and_vertex_layouts(pipe_manager, gpu_device, material_manager, mat_id, {vertex_layout});
	
		}
	}
}


// @Note: 'build_pipeline_cache' should be true if calling this at runtime! if initializing many meshrenderers
// you can set it to false and instead update the pipeline chache for the entire universe once all drawables are added.
@(private="package")
comp_meshrenderer_append_drawable_assets :: proc(comp : ^MeshRendererComponent, drawable_assets : []iria.DrawableAsset, build_pipeline_cache : bool = true) {

	// all the managers, get em.
	asset_manager 		:= engine.asset_manager;
	material_manager 	:= engine.material_manager;
	mesh_manager 		:= engine.mesh_manager;
	pipe_manager 		:= engine.pipeline_manager;
	gpu_device 			:= get_gpu_device();


	for &draw_asset in drawable_assets {

		draw_inst_asset := &draw_asset.draw_instance_asset;

		drawable := Drawable{entity = comp.entity};
		drawable.draw_instance.flags = draw_inst_asset.flags;

		mat_id  := asset_io_load_material_asset_id(asset_manager, material_manager, draw_inst_asset.mat_uuid) or_else material_manager.fallback_material;
		mesh_id := asset_io_load_mesh_asset_id(asset_manager, mesh_manager, draw_inst_asset.mesh_uuid) or_else -1;
		
		drawable.draw_instance.mat_id  = mat_id;
		drawable.draw_instance.mesh_id = mesh_id
		drawable.draw_instance.transform = draw_asset.transform;		

		drawable_index : int = ecs_drawable_add(comp.parent_ecs, comp.entity, &drawable);
		append(&comp.drawable_indexes, drawable_index);
		
		if build_pipeline_cache && mat_id > 0 {

			pipe_manager_update_depthonly_pipeline_cache_with_material(pipe_manager, gpu_device, material_manager, mat_id);

			if !mesh_manager_is_valid_id(mesh_manager, mesh_id) {
				continue;
			}

			gpu_data := mesh_manager_get_mesh_gpu_data(mesh_manager, mesh_id);
			engine_assert(gpu_data != nil); // this holds because we checked id for valid above. otherwise it wouldnt!

			vertex_layout := gpu_data.vertex_layout;

			pipe_manager_update_material_pipeline_cache_with_material_and_vertex_layouts(pipe_manager, gpu_device, material_manager, mat_id, {vertex_layout});
	
		}
	}
}

comp_meshrenderer_make_all_static :: proc(comp : ^MeshRendererComponent, make_static : bool){

	if len(comp.drawable_indexes) <= 0 {
		return;
	}


	for drawable_index in comp.drawable_indexes {
		draw_inst := ecs_drawable_get_draw_instance(comp.parent_ecs, drawable_index);


		if draw_inst != nil {
			if make_static {
				draw_inst.flags += DrawInstanceFlags{.IsStatic};
			} else {
				draw_inst.flags -= DrawInstanceFlags{.IsStatic};
			}
		}
	}
}