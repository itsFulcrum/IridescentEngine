package iri

import "base:runtime"
import "core:log"
import "core:mem"
import "core:os"

import "core:strings"
import "core:math/linalg"

import geo   "odinary:geometry"
import poly  "odinary:geometry/poly"
import mathy "odinary:mathy"

import iricom "iricommon"
import iria   "iriasset"


// @Note:
// - load  ops: load from asset_id expecting the asset file it belongs to to exist inside the project.
// - store ops: take a runtime type and an Optional store_filepath. They convert into a Serialisable Asset Type. If the Runtime Type came with an existing AssetID it will overwrite the existing Asset File with the new Data.
// 	 			If The runtime type does not Have en existing AssetID, it is expected that the store filepath is provided with the function call otherwise it fail, A new AssetID will be Generated.
// - make ops: create a new asset and store it into the provided directory


asset_io_load_model_asset :: proc(asset_manager : ^AssetManager, mesh_manager : ^MeshManager, asset_id : AssetID) -> (runtime_handle : AssetHandleModel, ok : bool) {
	
	IRI_PROFILE_PROCEDURE()

	if model_handle, exists := asset_manager.model_handles[asset_id]; exists {

		model_handle.ref_count += 1;
		asset_manager.model_handles[asset_id] = model_handle;

		return model_handle.runtime_handle, true;
	}


	path := asset_manager_get_absolute_filepath(asset_manager, asset_id, expected_type = .Model) or_return;

	asset_model := iria.asset_model_read_from_path(path) or_return;
	defer iria.asset_model_free(asset_model);

	num_primitives : int = len(asset_model.meshes);

	engine_assert(num_primitives == len(asset_model.material_asset_ids));

	model_runtime_handle := AssetHandleModel{
		mesh_ids 		    = make_slice([]MeshID, num_primitives, context.allocator),
		material_asset_ids  = make_slice([]AssetID, num_primitives, context.allocator),
	}

	mem.copy(&model_runtime_handle.material_asset_ids[0], &asset_model.material_asset_ids[0], num_primitives * size_of(AssetID));

	
	gpu_device := get_gpu_device();
	
	for &mesh_data, mesh_index in asset_model.meshes {

		mesh_id := mesh_manager_add_mesh(mesh_manager, gpu_device, mesh_data)

		model_runtime_handle.mesh_ids[mesh_index] = mesh_id;

		if mesh_id == MeshID_INVALID {
			log.warnf("Failed to add mesh data to mesh manager");
		}
	}

	asset_load_handle := AssetLoadHandleModel {
		runtime_handle = model_runtime_handle,
		ref_count = 1,
	}

	asset_manager.model_handles[asset_id] = asset_load_handle;

	if load_handle, exists := asset_manager.model_handles[asset_id]; exists{
		return load_handle.runtime_handle, true;
	}

	return;
}

asset_io_return_model_asset :: proc(asset_manager : ^AssetManager, mesh_manager : ^MeshManager, asset_id : AssetID) {

	if load_handle, exists := asset_manager.model_handles[asset_id]; exists {

		load_handle.ref_count -= 1;

		if load_handle.ref_count <= 0 {

			gpu_device := get_gpu_device();

			runtime_handle := &load_handle.runtime_handle;

			for i in 0..<len(runtime_handle.mesh_ids) {
				mesh_manager_remove_mesh(mesh_manager, gpu_device, &runtime_handle.mesh_ids[i]);
			}
			
			delete_slice(runtime_handle.mesh_ids);	
			delete_slice(runtime_handle.material_asset_ids);	

			delete_key(&asset_manager.model_handles, asset_id);
		} else {

			asset_manager.model_handles[asset_id] = load_handle;
		}
	}
}

asset_io_load_material_asset :: proc(asset_manager : ^AssetManager, material_manager : ^MaterialManager, asset_id : AssetID) -> (runtime_handle : AssetHandleMaterial, ok : bool) {
	IRI_PROFILE_PROCEDURE()

	if mat_handle, exists := asset_manager.material_handles[asset_id]; exists {

		mat_handle.ref_count += 1;
		asset_manager.material_handles[asset_id] = mat_handle;

		return mat_handle.runtime_handle, true;
	}


	mat_id : MaterialID = material_manager.fallback_material;

	path := asset_manager_get_absolute_filepath(asset_manager, asset_id, expected_type = .Material) or_return;


	//mat_asset := iria.asset_material_read_from_path(path);
	mat_asset, asset_ok := iria.asset_material_read_from_path(path);
	if !asset_ok {
		return runtime_handle, false;
	}
	// @Note: we dont free contents of mat asset which is just the name string of the material, 
	// because we can just keep the name string allocation. but asset itself needs to be freed.
	defer iria.asset_material_free(mat_asset); 

	mat_id = material_manager_add_material(material_manager, &mat_asset.mat);
	
	if mat_id == 0 {
		return runtime_handle, false,
	}


	load_handle := AssetLoadHandleMaterial {
		runtime_handle = AssetHandleMaterial{
			mat_id = mat_id,
		},
		ref_count = 1,
	}

	asset_manager.material_handles[asset_id] = load_handle;

	return load_handle.runtime_handle, true;
}

asset_io_return_material_asset :: proc(asset_manager : ^AssetManager, mat_manager : ^MaterialManager, asset_id : AssetID){

	if load_handle, exists := asset_manager.material_handles[asset_id]; exists {

		load_handle.ref_count -= 1;

		if load_handle.ref_count <= 0 {

			gpu_device := get_gpu_device();


			material_manager_remove_material(mat_manager, &load_handle.runtime_handle.mat_id);

			delete_key(&asset_manager.material_handles, asset_id);
		} else {

			asset_manager.material_handles[asset_id] = load_handle;
		}
	}
}

asset_io_load_light_asset :: proc(asset_manager : ^AssetManager, asset_id : AssetID) -> (asset : iria.AssetLight, ok : bool) {
	IRI_PROFILE_PROCEDURE()
	abs_path := asset_manager_get_absolute_filepath(asset_manager, asset_id, .Light) or_return;

	return iria.asset_light_read_from_path(abs_path);
}

asset_io_load_universe_asset :: proc(asset_manager : ^AssetManager, asset_id : AssetID) -> (universe_asset : ^iria.AssetUniverse, ok : bool) {
	
	IRI_PROFILE_PROCEDURE()

	path : string = asset_manager_get_absolute_filepath(asset_manager, asset_id, .Universe) or_return;

	return iria.asset_universe_read_from_path(path);
}

asset_io_store_universe :: proc(universe : ^Universe, full_store_filepath : string = "") -> (ok : bool){
	
	IRI_PROFILE_PROCEDURE()

	engine_assert(universe != nil);

	asset_manager := engine.asset_manager;

	write_flags := iria.AssetWriteFlags{.LogErrors, .OverwriteExisting}

	uni_asset : ^iria.AssetUniverse = new(iria.AssetUniverse);
	defer iria.asset_universe_free(uni_asset);


	store_filepath, asset_exists_already := asset_manager_get_absolute_filepath(asset_manager, universe.asset_id, .Universe, context.temp_allocator);
	if !asset_exists_already {
		//log.errorf("Failed to save universe '{}' to file. UUID is not registered with asset manager", universe.name);

		_ = iria.is_valid_write_filepath(full_store_filepath, can_overwrite_existing = false, log_errors = true) or_return;

		write_flags -= iria.AssetWriteFlags{.OverwriteExisting}; // if creating a new asset we are not allowed to overwrite others.

		store_filepath = full_store_filepath;
		
		uni_asset.asset_id = iria.generate_new_asset_id();
		
	} else {

		// Existing Asset, Keep AssetID and Alias.
		
		uni_asset.asset_id = universe.asset_id;
		
		asset_entry, asset_exists := asset_manager_get_entry(asset_manager, universe.asset_id)
		engine_assert(asset_exists);

		if len(asset_entry.alias) > 0 {
			uni_asset.asset_alias = strings.clone(asset_entry.alias, context.allocator);
		}

		// Here we can and want to overwrite existing. but for sanity check we still check if path is still valid.
		_ = iria.is_valid_write_filepath(store_filepath, can_overwrite_existing = true, log_errors = true) or_return;
	}




	uni_asset.tag = universe.tag;


	if len(universe.name) > 0 {
		uni_asset.name = strings.clone(universe.name, context.allocator);
	}

	uni_asset.settings = iria.AssetUniverseSettings {
		shadow_cascade_near_far_scale 	= universe.shadow_cascade_near_far_scale,
		shadow_cascade_side_scale 		= universe.shadow_cascade_side_scale,
		shadow_cascade_split_1 			= universe.shadow_cascade_split_1,
		shadow_cascade_split_2 			= universe.shadow_cascade_split_2,
		shadow_cascade_split_3 			= universe.shadow_cascade_split_3,
		cull_shadow_draws 				= cast(b8)universe.cull_shadow_draws,
	    do_frustum_culling 				= cast(b8)universe.do_frustum_culling,
	}

	entity_info_to_asset_entity_info :: proc(ent_info : EntityInfo) -> iria.AssetEntityInfo {

		info_flags := ent_info.flags - iricom.ENTITY_FLAGS_NOSTORE;

		return iria.AssetEntityInfo {
			flags 		= info_flags,
			comp_set 	= ent_info.component_set,
			tag 		= ent_info.tag,
		}
	}

	ecs := &universe.ecs;

	// default initialize these to -1 meaning none is active.
	uni_asset.active_camera_entity = -1;
	uni_asset.active_skybox_entity = -1;

	ent_infos : [dynamic]iria.AssetEntityInfo;
	ent_trans : [dynamic]Transform;
	ent_names : [dynamic]string;
	ent_comp_indexes : [dynamic]iria.AssetComponentIndexes;

	// Temporary map to map EntityIDs to new indexes into sparse arrays above.
	// @Note: not sure we actually need this map though, we can probably do everything in place

	EntID :: i32
	ent_index_map : map[EntID]int = make_map(map[EntID]int, context.allocator); 
	defer delete(ent_index_map);

	for &info, entity_id in ecs.entity_infos {

		if EntityFlag._Internal_Exists not_in info.flags || EntityFlag.NonPersistant in info.flags {
			continue;
		}
		
		ent_id : EntID = cast(EntID)entity_id;

		info_packed := entity_info_to_asset_entity_info(info);

		new_index : int = len(ent_infos);
		ent_index_map[ent_id] = new_index;

		// because components are stored sparcely without any unused spots, we should be able to reuse the indexes.
		// since we also just linearly load the components data as they are in the ecs's arrays.
		comp_indexes := iria.AssetComponentIndexes{
			camera_index   = ecs.component_indexes[.Camera][ent_id],
			skybox_index   = ecs.component_indexes[.Skybox][ent_id],
			light_index    = ecs.component_indexes[.Light][ent_id],
			meshren_index  = ecs.component_indexes[.MeshRenderer][ent_id],
			collider_index = ecs.component_indexes[.Collider][ent_id],
		}

		append(&ent_infos, info_packed);
		append(&ent_trans, ecs.transform_components[ent_id].transform);
		append(&ent_names, info.name);
		append(&ent_comp_indexes, comp_indexes);
	}

	num_ents : int = len(ent_infos);
	engine_assert(len(ent_names) == num_ents)
	engine_assert(len(ent_trans) == num_ents)
	engine_assert(len(ent_comp_indexes) == num_ents)

	uni_asset.num_entities = cast(u32)num_ents;
	uni_asset.entity_names = ent_names[:];
	uni_asset.entity_infos = ent_infos[:];
	uni_asset.entity_trans = ent_trans[:];
	uni_asset.entity_comp_indexes = ent_comp_indexes[:];

	// We effectivly just remap these to the index in the constant compact array above.
	if ecs.active_camera_entity.id > -1 {
		uni_asset.active_camera_entity = ent_index_map[ecs.active_camera_entity.id] or_else -1;
	}

	if ecs.active_skybox_entity.id > -1 {
		uni_asset.active_skybox_entity = ent_index_map[ecs.active_skybox_entity.id] or_else -1;
	}

	num_camera_components  : int  = len(ecs.camera_components);
	num_skybox_components  : int  = len(ecs.skybox_components);
	num_light_components   : int  = len(ecs.light_components);
	num_meshren_components : int  = len(ecs.mesh_renderer_components);
	num_collider_components : int = len(ecs.collider_components);

	// Camera
	if num_camera_components > 0 {
		uni_asset.camera_comp_data = make_slice([]iria.AssetCameraComponentData, num_camera_components, context.allocator);

		for &comp, index in ecs.camera_components {
			uni_asset.camera_comp_data[index] = comp.data;
		}
	}
	// Skybox
	if num_skybox_components > 0 {
		uni_asset.skybox_comp_data = make_slice([]iria.AssetSkyboxComponentData, num_skybox_components, context.allocator);

		for &comp, index in ecs.skybox_components {
			uni_asset.skybox_comp_data[index] = comp.data;
		}
	}

	// Lights
	if num_light_components > 0 {
		uni_asset.light_comp_data = make_slice([]iria.AssetLightComponentData, num_light_components, context.allocator);

		for &comp, index in ecs.light_components {
			uni_asset.light_comp_data[index] = comp_light_create_asset_light_component_data(&comp);
		}
	}

	if num_collider_components > 0 {
		uni_asset.collider_comp_data = make_slice([]iria.AssetColliderComponentData, num_collider_components, context.allocator);

		for &comp, index in ecs.collider_components {
			uni_asset.collider_comp_data[index] = comp_collider_create_asset_collider_component_data(&comp);
		}
	}

	// Mesh renderers & drawables / Draw Group

	// @Note: The way this works is that we store all Draw Groups that meshrenderers are referencing
	// consecutively in the file. We then only need to store per meshrenderer an offset into this
	// array and a number of how many draw groups belong to this meshrenderer.
	// This also has the benifit that on each store of the universe file, we sort the Draw Groups and Draw Primitves inside them
	// by meshrenderers which generally should be good for cache locatilty when rendering.

	if num_meshren_components > 0 {
		
		num_drawables : int = len(ecs.drawables);
		
		uni_asset.meshren_comp_data = make_slice([]iria.AssetMeshRendererComponentData, num_meshren_components, context.allocator);
		
		drawable_group_array : [dynamic]iria.AssetDrawGroup;		

		material_manager := engine.material_manager;
		mesh_manager 	 := engine.mesh_manager;

		for &comp, comp_index in ecs.mesh_renderer_components {


			comp_num_draw_groups : u32 = cast(u32)len(comp.draw_groups)

			comp_data := iria.AssetMeshRendererComponentData{
				num_draw_groups = comp_num_draw_groups,
				array_offset = comp_num_draw_groups > 0 ? cast(u32)len(drawable_group_array) : 0,
			}

			uni_asset.meshren_comp_data[comp_index] = comp_data;

			if comp_num_draw_groups > 0 {
				
				for &group, group_index in comp.draw_groups {

					group_num_drawables : int = len(group.drawable_index_refs);
					
					asset_drawable_group := iria.AssetDrawGroup{
						asset_id = group.asset_id,
						asset_drawable_type = group.asset_drawable_type,
						num_primitives = cast(u32)group_num_drawables,
					}

					asset_drawable_group.flags   	    = make_slice([]iricom.DrawInstanceFlags,group_num_drawables,context.allocator)
					asset_drawable_group.transforms     = make_slice([]geo.Transform, group_num_drawables, context.allocator)
					asset_drawable_group.material_asset_ids = make_slice([]iria.AssetID, group_num_drawables, context.allocator)

					for k in 0..<group_num_drawables {

						draw_index_ref := &group.drawable_index_refs[k];
						drawable_index := draw_index_ref.drawable_index;
						draw_instance := &ecs.drawables.draw_instance[drawable_index];

						asset_drawable_group.flags[k] 			= draw_instance.flags
						asset_drawable_group.transforms[k] 		= draw_instance.transform;
						asset_drawable_group.material_asset_ids[k] 	= draw_index_ref.material_asset_id;
					}


					append(&drawable_group_array,  asset_drawable_group);
				}



				engine_assert(int(comp_data.array_offset + comp_data.num_draw_groups) == len(drawable_group_array));
			}
		}

		if len(drawable_group_array) > 0 {
			uni_asset.drawable_groups = drawable_group_array[:];
		}

	}

	iria.asset_universe_write_to_file(store_filepath, uni_asset, write_flags) or_return;


	if !asset_exists_already {
		asset_manager_register_asset_file_by_path(asset_manager, store_filepath);
	}


	return true;
}

asset_io_make_universe_asset :: proc(directory_path : string, name : string = "NewUniverse") -> (universe : ^Universe, ok : bool) {
	
	log_errors : bool = true;

	if len(name) <= 0 {
		engine_assert(false, "Invalid Universe Name")
		return nil, false;
	}
	// TODO: could validate that directory path is subdirector of the current project.

	if !os.is_directory(directory_path){
		return;
	}

	store_filename, osErr := os.join_filename(name, iria.FILE_EXTENTION_NAME, context.temp_allocator);
	engine_assert(osErr == os.ERROR_NONE);

	full_store_filepath, alloc_err1 := os.join_path({directory_path, store_filename}, context.temp_allocator);
	engine_assert(alloc_err1 == nil);
	
	full_store_filepath = clean_path_absolute(full_store_filepath) or_return;

	file_exists := iria.is_valid_write_filepath(full_store_filepath, can_overwrite_existing = false, log_errors = log_errors) or_return;
	
	// Initialize new Universe
	new_universe : ^Universe = new(Universe, context.allocator);
	universe_init(new_universe);

	defer if !ok {
		universe_deinit(new_universe);
		free(new_universe);
		new_universe = nil;
	}

	cam_ent := ecs_entity_create(&new_universe.ecs, "Camera");
	cam_comp, err1 := ecs_add_component(&new_universe.ecs, cam_ent, CameraComponent);
	comp_camera_set_as_active(cam_comp);

	sky_ent := ecs_entity_create(&new_universe.ecs, "Skysphere");
	sky_comp, err2 := ecs_add_component(&new_universe.ecs, sky_ent, SkyboxComponent);
	comp_skybox_set_as_active(sky_comp);

	new_universe.name = strings.clone(name, context.allocator);

	new_universe.asset_id = AssetID_NONE // Explicitly no asset yet.

	asset_io_store_universe(new_universe, full_store_filepath) or_return;

	return new_universe, true;
}