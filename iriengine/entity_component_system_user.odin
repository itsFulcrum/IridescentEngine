package iri

import "core:log"

// These are procedures that a user application uses to interact with the ecs

entity_create :: proc(component_set : ComponentSet = {.Transform}, universe : ^Universe = nil) -> Entity {

	uni := universe == nil ? get_current_universe() : universe;

	ent := ecs_entity_create(&uni.ecs);

	for comp_type in component_set {

		if(comp_type == .Transform) do continue;

		comp , err := ecs_add_component_from_component_type(&uni.ecs, ent, comp_type);
		engine_assert(err == .Success);
	}

	return ent;
}

entity_destroy :: proc(entity : ^Entity, universe : ^Universe = nil) -> EcsError {
	engine_assert(entity != nil);
	uni := universe == nil ? get_current_universe() : universe;
	return ecs_entity_destroy(&uni.ecs, entity);
}

entity_exists :: proc(entity : Entity, universe : ^Universe = nil) -> bool {
	uni := universe == nil ? get_current_universe() : universe;
	return ecs_entity_exists(&uni.ecs, entity);
}

entity_is_component_attached :: proc(entity : Entity, component_type : ComponentType, universe : ^Universe = nil) -> bool {
	uni := universe == nil ? get_current_universe() : universe;
	return ecs_component_is_attached(&uni.ecs, entity, component_type);
}

entity_add_component :: proc(entity : Entity, $T : typeid, universe : ^Universe = nil) -> (^T , EcsError) {
	uni := universe == nil ? get_current_universe() : universe;
	return ecs_add_component(&uni.ecs, entity, T);
}

entity_remove_component :: proc(entity: Entity, $T : typeid, universe : ^Universe = nil) -> EcsError {
	uni := universe == nil ? get_current_universe() : universe;
	return ecs_remove_component(&uni.ecs, entity, T);
}

entity_get_component :: proc(entity : Entity, $T : typeid, universe : ^Universe = nil) -> ^T {	
	uni := universe == nil ? get_current_universe() : universe;
	comp, err := ecs_get_component(&uni.ecs, entity, T);
	return comp;
}

entity_get_transform :: proc(entity: Entity, universe: ^Universe = nil) -> ^TransformComponent{
	
	uni := universe == nil ? get_current_universe() : universe;
	return ecs_get_transform(&uni.ecs, entity);
}