package iri


material_manager_get_num_loaded :: proc() -> uint {
	return cast(uint)len(engine.material_manager.materials);
}

material_register_asset :: proc(material : ^MaterialAsset) -> MaterialID {
	manager := engine.material_manager;
	return material_manager_add_material_asset(manager, material)
}

material_register :: proc(material : ^Material) -> MaterialID {
	
	manager := engine.material_manager;
	return material_manager_add_material(manager, material)
}

material_unregister :: proc(mat_id : ^MaterialID) {
	manager := engine.material_manager;
	material_manager_remove_material(manager, mat_id);
}


material_exists :: proc(mat_id : MaterialID) -> bool {
	manager := engine.material_manager;
	return material_manager_is_valid_id(manager, mat_id)
}

material_is_asset_loaded :: proc(asset_uuid : AssetUUID) -> bool {
	return material_manager_is_asset_loaded(engine.material_manager, asset_uuid);
}

material_get_id_from_asset_uuid :: proc(asset_uuid : AssetUUID) -> (mat_id : MaterialID, exists : bool) {
	return material_manager_get_id_from_asset_uuid(engine.material_manager, asset_uuid);
}

// Returns Default fallback material if id is invalid. pointers are only valid for as long as no other materials are added or removed.
material_get_by_id :: proc(mat_id : MaterialID) -> ^Material {
	
	manager := engine.material_manager;

	if !material_manager_is_valid_id(manager, mat_id) {
		return material_manager_get_material_unsafe(manager, manager.fallback_material);
	}

	return material_manager_get_material_unsafe(manager, mat_id)
}


material_load_from_asset_uuid :: proc(asset_uuid : AssetUUID) -> (mat_id : MaterialID, ok : bool){
	return asset_io_load_material_asset_id(engine.asset_manager, engine.material_manager, asset_uuid)
}


// Push changes made to a material variants so they get uploaded to the gpu next frame.
// If changes were made on the render_technique like changing the blend mode, use 'material_push_technique_changes' instead.
material_push_changes :: proc(mat_id : MaterialID) {
	manager := engine.material_manager;
	material_manager_push_material_changes(manager, mat_id);
}

// @Note: This can be very slow !! Might rebuild pipelines and recompile shaders!
// Avoid changing material technique at runtime, create sperare materials instead.
// this also calls normal 'material_push_changes' so no need to call that also.
material_push_technique_changes :: proc(mat_id : MaterialID) {
	manager := engine.material_manager;
	pipe_manager := engine.pipeline_manager;
	gpu_device := get_gpu_device();

	material_manager_push_material_technique_changes(manager, mat_id, pipe_manager, gpu_device);
}
