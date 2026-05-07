package iri

import "base:runtime"
import "core:log"
import "core:mem"
import "core:os"

import "core:strings"
import "core:math/linalg"
import "odinary:geometry/poly"
import "odinary:mathy"

import iricom "iricommon"
import iria "iriasset"


// @Note:
// load ops load from asset_uuid
// store ops expect the asset to exist on disk and will overwrite the file. They dont take filepath as input but expect uuid of asset to point to a file.
// write ops write to a filepath and may generate new uuids if path doesn't exist yet.

asset_io_load_scene_collection_asset :: proc(asset_manager : ^AssetManager, asset_uuid : AssetUUID) -> (collection : ^iria.SceneCollectionAsset, ok : bool) {
	
	path := asset_manager_get_absolute_filepath(asset_manager, asset_uuid, expected_type = .SceneCollection) or_return;

	collection = iria.asset_scene_collection_read_from_path(path) or_return;

	return collection, true;
}

asset_io_load_mesh_asset_id :: proc(asset_manager : ^AssetManager, mesh_manager : ^MeshManager, asset_uuid : AssetUUID) -> (mesh_id : MeshID, ok : bool) {
	
	// check if its loaded already
	if m_id, exists := mesh_manager_get_id_from_asset_uuid(mesh_manager, asset_uuid); exists == true {
		return m_id, true;
	}

	mesh_id = -1;

	path := asset_manager_get_absolute_filepath(asset_manager, asset_uuid, expected_type = .Mesh) or_return;

	mesh_data := iria.asset_mesh_read_from_path(path) or_return;
	defer free_mesh_data(mesh_data);

	gpu_device := get_gpu_device();
	mesh_id = mesh_manager_add_mesh(mesh_manager, gpu_device, mesh_data);
	
	if mesh_id == -1 {
		log.errorf("Failed to register mesh data from asset. {}", path);
		return -1, false;
	}

	return mesh_id, true;
}


asset_io_load_material_asset_id :: proc(asset_manager : ^AssetManager, material_manager : ^MaterialManager, asset_uuid : AssetUUID) -> (mat_id : MaterialID, ok : bool){


	if m_id, exists := material_manager_get_id_from_asset_uuid(material_manager, asset_uuid); exists == true {
		return m_id, true;
	}


	mat_id = material_manager.fallback_material;

	path := asset_manager_get_absolute_filepath(asset_manager, asset_uuid, expected_type = .Material) or_return;


	mat_asset := iria.asset_material_read_from_path(path) or_return;
	// @Note: we dont free contents of mat asset which is just the name string of the material, 
	// because we can just keep the name string allocation. but asset itself needs to be freed.
	free(mat_asset); 

	mat_id = material_manager_add_material_asset(material_manager, mat_asset);
	
	if mat_id == 0 {
		return mat_id, false,
	}

	return mat_id, true;
}

asset_io_load_light_asset :: proc(asset_manager : ^AssetManager, asset_uuid : iria.AssetUUID) -> (asset : iria.LightAsset, ok : bool) {

	abs_path := asset_manager_get_absolute_filepath(asset_manager, asset_uuid, .Light) or_return;

	return iria.asset_light_read_from_path(abs_path);
}

asset_io_load_universe_asset :: proc(asset_uuid : iria.AssetUUID) -> (universe : ^Universe, ok : bool) {
	asset_manager := engine.asset_manager;

	path : string = asset_manager_get_absolute_filepath(asset_manager, asset_uuid, .Universe) or_return;

	uni_asset := iria.asset_universe_read_from_path(path) or_return;
	defer iria.free_universe_asset(uni_asset);

	uni : ^Universe = new(Universe);
	universe_init(uni, uni_asset);

	return uni, true;
}

@(private="package")
asset_io_write_universe_to_file :: proc(full_store_filepath : string, universe : ^Universe, write_flags : AssetWriteFlags) -> bool {

	engine_assert(universe != nil);

	log_errors : bool = .LogErrors in write_flags;
	can_overwrite_existing : bool = .OverwriteExisting in write_flags;

	file_exists := iria.validate_write_filepath(full_store_filepath, log_errors) or_return;
	
	if file_exists && !can_overwrite_existing {
		if log_errors do log.warnf("Faild to export asset file {}. 'OverwriteExisting' flag is not set and file already exists", full_store_filepath);
		return false;
	}

	// create the UniverseAsset structure from the universe.

	uni_asset : ^iria.UniverseAsset = new(iria.UniverseAsset);
	defer iria.free_universe_asset(uni_asset);

	uni_asset.asset_uuid = asset_manager_get_or_generate_asset_uuid(full_store_filepath, iria.AssetType.Universe, log_errors) or_return;

	uni_asset.tag = universe.tag;

	if len(universe.name) > 0 {
		uni_asset.name = strings.clone(universe.name, context.allocator);
	}

	uni_asset.settings = iria.UniverseAssetSettings {
		shadow_cascade_near_far_scale 	= universe.shadow_cascade_near_far_scale,
		shadow_cascade_side_scale 		= universe.shadow_cascade_side_scale,
		shadow_cascade_split_1 			= universe.shadow_cascade_split_1,
		shadow_cascade_split_2 			= universe.shadow_cascade_split_2,
		shadow_cascade_split_3 			= universe.shadow_cascade_split_3,
		cull_shadow_draws 				= cast(b8)universe.cull_shadow_draws,
	    do_frustum_culling 				= cast(b8)universe.do_frustum_culling,
	}

	entity_info_to_entity_info_packed :: proc(ent_info : EntityInfo) -> iria.EntityInfoPacked {

		info_flags := ent_info.flags - iricom.ENTITY_FLAGS_NOSTORE;

		return iria.EntityInfoPacked {
			flags 		= info_flags,
			comp_set 	= ent_info.component_set,
			tag 		= ent_info.tag,
		}
	}

	ecs := &universe.ecs;

	// default initialize these to -1 meaning none is active.
	uni_asset.active_camera_entity = -1;
	uni_asset.active_skybox_entity = -1;

	ent_infos : [dynamic]iria.EntityInfoPacked;
	ent_trans : [dynamic]Transform;
	ent_names : [dynamic]string;
	ent_comp_indexes : [dynamic]iria.CompIndexes;

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

		info_packed := entity_info_to_entity_info_packed(info);

		new_index : int = len(ent_infos);
		ent_index_map[ent_id] = new_index;

		// because components are stored sparcely without any unused spots, we should be able to reuse the indexes.
		// since we also just linearly load the components data as they are in the ecs's arrays.
		comp_indexes := iria.CompIndexes{
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
		uni_asset.camera_comp_data = make_slice([]iricom.CameraCompData, num_camera_components, context.allocator);

		for &comp, index in ecs.camera_components {
			uni_asset.camera_comp_data[index] = comp.data;
		}
	}
	// Skybox
	if num_skybox_components > 0 {
		uni_asset.skybox_comp_data = make_slice([]iricom.SkyboxCompData, num_skybox_components, context.allocator);

		for &comp, index in ecs.skybox_components {
			uni_asset.skybox_comp_data[index] = comp.data;
		}
	}
	// Lights
	if num_light_components > 0 {
		uni_asset.light_comp_data = make_slice([]iria.LightAsset, num_light_components, context.allocator);

		for &comp, index in ecs.light_components {
			uni_asset.light_comp_data[index] = comp_light_create_light_asset(&comp);
		}
	}

	if num_collider_components > 0 {
		uni_asset.collider_comp_data = make_slice([]iria.ColliderCompData, num_collider_components, context.allocator);

		for &comp, index in ecs.collider_components {
			uni_asset.collider_comp_data[index] = comp_collider_create_collider_comp_data(&comp);
		}
	}

	// Mesh renderers & drawables
	// @Note: The way this works is that we store drawables that meshrenderers are referencing
	// consecutively in the file. We then only need to store per meshrenderer an offset into this
	// array and a number of how many starting at that offset belong to this meshrenderer.
	// this also has the benifit that on each store of the universe file, we sort the drawables
	// array by meshrenderers which generally should be good for cache locatilty when rendering.

	if num_meshren_components > 0 {
		
		num_drawables : int = len(ecs.drawables);
		
		uni_asset.meshren_comp_data = make_slice([]iria.MeshRendererCompData, num_meshren_components, context.allocator);

		drawable_assets_array : [dynamic]iria.DrawableAsset;
		
		material_manager := engine.material_manager;
		mesh_manager := engine.mesh_manager;

		for &comp, comp_index in ecs.mesh_renderer_components {

			// number of drawables this meshrendere refers to.
			num_drawable_indexes : u32 = cast(u32)len(comp.drawable_indexes);

			comp_data := iria.MeshRendererCompData{
				num_drawable_assets = num_drawable_indexes,
				array_offset = cast(u32)len(drawable_assets_array),
			}
			uni_asset.meshren_comp_data[comp_index] = comp_data;

			if num_drawable_indexes > 0 {
				for drawable_index in comp.drawable_indexes {
					draw_instance := &ecs.drawables.draw_instance[drawable_index];
				
					drawable_asset := iria.DrawableAsset{
						draw_instance_asset = iria.DrawInstanceAsset{
							flags   	= draw_instance.flags,
							// @Speed: these are slow right now. O(n) lookups
							mesh_uuid = mesh_manager_get_asset_uuid_from_mesh_id(mesh_manager, draw_instance.mesh_id) or_else AssetUUID_INVALID,
							mat_uuid  = material_manager_get_asset_uuid_from_material_id(material_manager, draw_instance.mat_id) or_else AssetUUID_INVALID,
						},
						transform = draw_instance.transform,
					}

					drawable_asset.draw_instance_asset.flags -= iricom.DRAW_INSTANCE_FLAGS_INTERNAL;
	
					append(&drawable_assets_array, drawable_asset);
				}
			}

			engine_assert(int(comp_data.array_offset + comp_data.num_drawable_assets) == len(drawable_assets_array));
		}

		engine_assert(len(drawable_assets_array) == len(ecs.drawables));


		if len(drawable_assets_array) > 0 {
			uni_asset.drawable_assets_array = drawable_assets_array[:];
		}

	}

	iria.asset_universe_write_to_file(full_store_filepath, uni_asset, write_flags) or_return;

	asset_manager_register_asset_file_by_path(engine.asset_manager, full_store_filepath);

	return true;
}

asset_io_store_universe :: proc(universe : ^Universe) -> (ok : bool){
	engine_assert(universe != nil);

	manager := engine.asset_manager;

	abs_path, entry_exists := asset_manager_get_absolute_filepath(manager, universe.asset_uuid, .Universe, context.temp_allocator);
	if !entry_exists {
		log.errorf("Failed to save universe '{}' to file. UUID is not registered with asset manager", universe.name);
		return false;
	}

	asset_io_write_universe_to_file(abs_path, universe, AssetWriteFlags{.LogErrors, .OverwriteExisting}) or_return;

	return true;
}

asset_io_create_new_universe_asset :: proc(directory_path : string, name : string = "NewUniverse") -> (universe : ^Universe, ok : bool) {
	
	log_errors : bool = true;

	if len(name) <= 0 {
		engine_assert(false, "Invalid Universe Name")
		return nil, false;
	}
	// TODO: could validate that directory path is subdirector of the current project.

	if !os.is_directory(directory_path){
		return;
	}
	// TODO: Could to validation if a universe of same name already exists.

	store_filename, osErr := os.join_filename(name, iria.FILE_EXTENTION_NAME, context.temp_allocator);
	engine_assert(osErr == os.ERROR_NONE);

	full_store_filepath, alloc_err1 := os.join_path({directory_path, store_filename}, context.temp_allocator);
	engine_assert(alloc_err1 == nil);
	
	full_store_filepath = clean_path_absolute(full_store_filepath) or_return;

	file_exists := iria.validate_write_filepath(full_store_filepath, log_errors) or_return;
	if file_exists {
		log.errorf("Cannot Create a new universe in directory because a file with same name already exists. {}", full_store_filepath);
		return nil, false;
	}

	universe = new(Universe, context.allocator);
	universe_init(universe);

	defer if !ok {
		universe_deinit(universe);
		free(universe);
		universe = nil;
	}

	cam_ent := ecs_entity_create(&universe.ecs, "Camera");
	cam_comp, err1 := ecs_add_component(&universe.ecs, cam_ent, CameraComponent);
	comp_camera_set_as_active(cam_comp);

	sky_ent := ecs_entity_create(&universe.ecs, "Skysphere");
	sky_comp, err2 := ecs_add_component(&universe.ecs, sky_ent, SkyboxComponent);
	comp_skybox_set_as_active(sky_comp);

	universe.name = strings.clone(name, context.allocator);

	asset_io_write_universe_to_file(full_store_filepath, universe, AssetWriteFlags{.LogErrors}) or_return;

	return universe, true;
}


// return the first found universe asset that matches tag and name. return false if non is found.
// use a tag of 0 to only search by name. 
// use empty string ("") to only search by tag. 
asset_manager_find_universe_asset_by_tag_and_name :: proc(tag : u32, name : string) -> (asset_uuid : iria.AssetUUID, found : bool){

	manager := engine.asset_manager;
	
	use_tag  : bool = tag > 0;
	use_name : bool = name != "";

	if !use_tag && use_name {
		// search only by name
		
		for &uni_info in manager.universe_infos {
			if uni_info.uni_name == name {
				return uni_info.asset_uuid, true;
			}
		}

	}  else if use_tag && !use_name {
		// search only by tag

		for &uni_info in manager.universe_infos {
			if uni_info.uni_tag == tag {
				return uni_info.asset_uuid, true;
			}
		}

	} else if use_tag && use_name {
		// search with tag and name

		for &uni_info in manager.universe_infos {
			if uni_info.uni_tag == tag && uni_info.uni_name == name {
				return uni_info.asset_uuid, true;
			}
		}
	}

	return AssetUUID_INVALID, false;
}
