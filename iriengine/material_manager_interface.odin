package iri

import "core:strings"


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

// Returns Default fallback material if id is invalid. pointers are only valid for as long as no other materials are added or removed.
material_get_by_id :: proc(mat_id : MaterialID) -> ^Material {
	
	manager := engine.material_manager;

	if !material_manager_is_valid_id(manager, mat_id) {
		return material_manager_get_material_unsafe(manager, manager.fallback_material);
	}

	return material_manager_get_material_unsafe(manager, mat_id)
}

// Returns a clone of the material name string allocated using context.temp_allocator.
// Returns empty string if Id is invalid.
material_get_name_clone :: proc(mat_id : MaterialID, allocator := context.temp_allocator) -> string {
	
	manager := engine.material_manager;

	if !material_exists(mat_id) {
		return "";
	}

	mat := material_get_by_id(mat_id)
	return strings.clone(mat.name, allocator);
}


// Push changes made to a material variant so they get uploaded to the gpu next frame.
// If changes were made on the render_technique like changing the blend mode, use 'material_push_technique_changes' instead.
material_push_changes :: proc(mat_id : MaterialID) {
	manager := engine.material_manager;
	material_manager_push_material_changes(manager, mat_id);
}

// @Note: This can be very slow !! Might rebuild pipelines and recompile shaders!
// Avoid changing material technique at runtime, create speparate materials instead.
// this also calls normal 'material_push_changes' so no need to call that also.
material_push_technique_changes :: proc(mat_id : MaterialID) {
	manager := engine.material_manager;
	pipe_manager := engine.pipeline_manager;
	gpu_device := get_gpu_device();

	material_manager_push_material_technique_changes(manager, mat_id, pipe_manager, gpu_device);
}
