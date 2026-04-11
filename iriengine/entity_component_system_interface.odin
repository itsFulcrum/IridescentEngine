package iri

import "core:log"

// These are procedures that a user application uses to interact with the ecs

entity_create :: proc(component_set : ComponentSet = {.Transform}, name : string = "NewEntity", tag : u32 = 0, universe : ^Universe = nil) -> Entity {

	uni := universe == nil ? get_active_universe() : universe;
	if uni == nil do return EntityInvalid;

	ent := ecs_entity_create(&uni.ecs, name, tag);

	for comp_type in component_set {

		if comp_type == .Transform do continue;

		comp , err := ecs_add_component_from_component_type(&uni.ecs, ent, comp_type);
		engine_assert(err == .None);
	}

	return ent;
}

entity_destroy :: proc(entity : ^Entity, universe : ^Universe = nil) -> EcsError {
	engine_assert(entity != nil);
	uni := universe == nil ? get_active_universe() : universe;
	if uni == nil do return EcsError.InvalidInputParameter;
	return ecs_entity_destroy(&uni.ecs, entity);
}

entity_exists :: proc(entity : Entity, universe : ^Universe = nil) -> bool {
	uni := universe == nil ? get_active_universe() : universe;
	if uni == nil do return false;
	return ecs_entity_exists(&uni.ecs, entity);
}

entity_is_component_attached :: proc(entity : Entity, component_type : ComponentType, universe : ^Universe = nil) -> bool {
	uni := universe == nil ? get_active_universe() : universe;
	if uni == nil do return false;
	return ecs_component_is_attached(&uni.ecs, entity, component_type);
}

entity_add_component :: proc(entity : Entity, $T : typeid, universe : ^Universe = nil) -> (^T , EcsError) {
	uni := universe == nil ? get_active_universe() : universe;
	if uni == nil do return nil, EcsError.InvalidInputParameter;
	return ecs_add_component(&uni.ecs, entity, T);
}
entity_remove_component :: proc(entity: Entity, $T : typeid, universe : ^Universe = nil) -> EcsError {
	uni := universe == nil ? get_active_universe() : universe;
	if uni == nil do return EcsError.InvalidInputParameter;
	return ecs_remove_component(&uni.ecs, entity, T);
}

entity_get_component :: proc(entity : Entity, $T : typeid, universe : ^Universe = nil) -> ^T {	
	uni := universe == nil ? get_active_universe() : universe;
	if uni == nil do return nil;
	comp, err := ecs_get_component(&uni.ecs, entity, T);
	return comp;
}

entity_get_transform :: proc(entity: Entity, universe: ^Universe = nil) -> ^TransformComponent{
	uni := universe == nil ? get_active_universe() : universe;
	if uni == nil do return nil;
	return ecs_get_transform(&uni.ecs, entity);
}


// @Note: Prefer not to use this unless you need to get all fields. EntInfo is SOA
entity_get_entity_info_copy :: proc(entity: Entity, universe: ^Universe = nil) -> (EntityInfo,EcsError) {
	uni := universe == nil ? get_active_universe() : universe;
	if uni == nil do return EntityInfo{}, EcsError.InvalidInputParameter;
	return ecs_get_entity_info_copy(&uni.ecs, entity);
}

entity_get_name :: proc(entity: Entity, universe: ^Universe = nil) -> (string, EcsError){
	uni := universe == nil ? get_active_universe() : universe;
	if uni == nil do return "", EcsError.InvalidInputParameter;
	return ecs_entity_get_name(&uni.ecs, entity);
}

entity_set_name :: proc(entity : Entity, new_name : string, universe: ^Universe = nil) -> EcsError{
	
	uni := universe == nil ? get_active_universe() : universe;
	if uni == nil do return EcsError.InvalidInputParameter;

	return ecs_entity_set_name(&uni.ecs, entity, new_name);
}

entity_get_tag :: proc(entity : Entity, universe : ^Universe = nil) -> (u32, EcsError){
	uni := universe == nil ? get_active_universe() : universe;
	if uni == nil do return 0, EcsError.InvalidInputParameter;
	return ecs_entity_get_tag(&uni.ecs, entity);
}

entity_set_tag :: proc(entity : Entity, new_tag : u32, universe: ^Universe = nil) -> EcsError {
	uni := universe == nil ? get_active_universe() : universe;
	if uni == nil do return EcsError.InvalidInputParameter;

	return ecs_entity_set_tag(&uni.ecs,entity, new_tag);
}

entity_get_component_set :: proc(entity : Entity, universe : ^Universe = nil) -> (ComponentSet, EcsError){
	uni := universe == nil ? get_active_universe() : universe;
	if uni == nil do return ComponentSet{}, EcsError.InvalidInputParameter;
	return ecs_entity_get_component_set(&uni.ecs, entity);
}

// @Note: Returns only non _Internal flags
entity_get_flags :: proc(entity : Entity, universe: ^Universe = nil ) -> (EntityFlags, EcsError) {
	uni := universe == nil ? get_active_universe() : universe;
	if uni == nil do return EntityFlags{}, EcsError.InvalidInputParameter;

	return ecs_entity_get_flags(&uni.ecs, entity);
}
// @Note: only allows setting non _Internal flags
entity_set_flags :: proc(entity : Entity, flags : EntityFlags, subtract_flags : bool = false, universe: ^Universe = nil ) -> EcsError{
	uni := universe == nil ? get_active_universe() : universe;
	if uni == nil do return EcsError.InvalidInputParameter;
	
	return ecs_entity_set_flags(&uni.ecs, entity, flags, subtract_flags);
}

entity_set_enabled :: proc(entity : Entity, new_enabled : bool, universe: ^Universe = nil) -> EcsError {
	uni := universe == nil ? get_active_universe() : universe;
	if uni == nil do return EcsError.InvalidInputParameter;

	return ecs_entity_set_enabled(&uni.ecs, entity, new_enabled);
}

entity_is_enabled :: proc(entity : Entity, universe: ^Universe = nil) -> bool {
	uni := universe == nil ? get_active_universe() : universe;
	if uni == nil do return false;

	return ecs_entity_is_enabled(&uni.ecs, entity);
}

entity_get_user_data :: proc(entity : Entity, universe: ^Universe = nil) -> (uintptr, EcsError) {
	uni := universe == nil ? get_active_universe() : universe;
	if uni == nil do return 0, EcsError.InvalidInputParameter;

	return ecs_entity_get_user_data(&uni.ecs, entity);
}

entity_set_user_data :: proc(entity : Entity, data : uintptr, universe: ^Universe = nil) -> EcsError {
	uni := universe == nil ? get_active_universe() : universe;
	if uni == nil do return EcsError.InvalidInputParameter;

	return ecs_entity_set_user_data(&uni.ecs, entity, data);
}


entity_force_update ::  proc(entity : Entity, universe: ^Universe = nil) -> EcsError {
	uni := universe == nil ? get_active_universe() : universe;
	if uni == nil do return EcsError.InvalidInputParameter;

	return ecs_entity_force_update(&uni.ecs, entity);
}

comp_get_entity :: proc(comp_common : ComponentCommon) -> Entity {
	return comp_common.entity;

}

