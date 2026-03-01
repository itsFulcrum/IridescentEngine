package iri

import "core:log"

MeshRendererComponent :: struct{
	using common : ComponentCommon,

	drawables_indexes : [dynamic]u32,
}

@(private="package")
comp_meshrenderer_init :: proc (comp: ^MeshRendererComponent){
	if(comp == nil){
		return;
	}

	#force_inline comp_meshrenderer_set_defaults(comp);
}

@(private="package")
comp_meshrenderer_deinit :: proc(comp: ^MeshRendererComponent){
	if(comp == nil){
		return;
	}

	comp_meshrenderer_remove_all_mesh_instances(comp);

	#force_inline comp_meshrenderer_set_defaults(comp);

	//delete(comp.mesh_instances);
	// TODO: remove from ecs drawables array..

	//delete(comp.mesh_instances);
	delete(comp.drawables_indexes);
}


comp_meshrenderer_set_defaults :: proc(comp : ^MeshRendererComponent){
	// if(comp == nil){
	// 	return;
	// }
}


// =====================================================================
// Component procedures
// =====================================================================

comp_meshrenderer_add_mesh_instances :: proc(comp : ^MeshRendererComponent, instances : []MeshInstance){

	for &instance in instances {
		comp_meshrenderer_add_mesh_instance(comp, instance);
	}
}




comp_meshrenderer_add_mesh_instance :: proc(comp : ^MeshRendererComponent, instance : MeshInstance){

	entity_transform := ecs_get_transform(comp.parent_ecs, comp.entity);

	mesh_aabb := mesh_manager_get_aabb(engine.mesh_manager, instance.mesh_id);

	drawable : Drawable;
	drawable.entity = comp.entity;
	drawable.mesh_instance = instance;

	world_transform := transform_child_by_parent(entity_transform, instance.transform);

	drawable.world_mat = calc_transform_matrix(world_transform);
	drawable.world_obb = aabb_to_transformed_obb(mesh_aabb, world_transform);

	ecs := comp.common.parent_ecs;

	index := len(ecs.drawables);
	append_soa(&ecs.drawables,drawable);

	append(&comp.drawables_indexes, cast(u32)index);
}


comp_meshrenderer_remove_all_mesh_instances :: proc(comp : ^MeshRendererComponent){

	// if(comp == nil) do return;

	// ecs := comp.common.parent_ecs;


	// #reverse for drawable_index in comp.drawables_indexes {

	// 	last_element_index : u32 = cast(u32)len(ecs.drawables) -1;

	// 	if(drawable_index == last_element_index){
	// 		// if we want to remove the last element in drawables we can just pop..
	// 		//pop(&ecs.drawables);
	// 		unordered_remove_soa(&ecs.drawables, drawable_index);
	// 		continue;
	// 	}

	// 	// entity of the last element in ecs.drawables array.
	// 	last_drawables_entity := ecs.drawables[last_element_index].entity;

	// 	// Copy last to ours (unordered remove)
	// 	ecs.drawables[drawable_index] = ecs.drawables[last_element_index];


	// 	// Now we need to update the specific index that previously pointed to the last element
	// 	// so we get the meshrenderer_component of the entity (last_drawables_entity) we cached.

	// 	// loop through all its drawable_indexes until we find the one that points to last.
	// 	// replace it with the index we copied it to.

	// 	// @note: Actually its possilbe that 'other_mesh_renderer_comp' is in fact the same one as this one
	// 	// this can happen if this one also contains the index to the last_drawable in ecs.drawables
	// 	// but we havent reached it yet inside this loop.
	// 	// but i think that shouldn't cause problems ?
	// 	other_mesh_renderer_comp , err := ecs_get_component(ecs, last_drawables_entity, MeshRendererComponent);
	// 	// since the drawable existed, we must assume the mesh renderer of its entity also exists...
	// 	engine_assert(other_mesh_renderer_comp != nil);

	// 	if(other_mesh_renderer_comp == comp) {
	// 		log.warnf("Operating on same comp!!");
	// 	}


	// 	index_to_replace : i32 = -1;
	// 	for i in 0..<len(other_mesh_renderer_comp.drawables_indexes) {

	// 		index_at_i : u32 = other_mesh_renderer_comp.drawables_indexes[i];

	// 		if(index_at_i == last_element_index){
				
	// 			index_to_replace = cast(i32)i;
	// 			break;
	// 		}
	// 	}

	// 	engine_assert(index_to_replace != -1);

	// 	other_mesh_renderer_comp.drawables_indexes[index_to_replace] = drawable_index;

	// 	unordered_remove_soa(&ecs.drawables, last_element_index);

	// 	// we do a reverse loop and always pop of last to be a bit safer that we dont mess things up
	// 	// because we could be modifying element indexes while iterating through here. see above comment ^
	// 	pop(&comp.drawables_indexes);
	// }


	// clear(&comp.drawables_indexes);
}