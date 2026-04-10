package iri

import "core:log"
import "core:strings"
import "core:math/rand"

import iricom "iricommon"

Entity :: iricom.Entity
EntityInvalid :: iricom.EntityInvalid

EntityFlag  :: iricom.EntityFlag
EntityFlags :: iricom.EntityFlags

EntityInfo :: iricom.EntityInfo

COMPONENT_SET_ALL :: iricom.ComponentSet{.Transform, .Camera, .Light, .Skybox, .MeshRenderer}
ComponentSet  :: iricom.ComponentSet
ComponentType :: iricom.ComponentType

ComponentCommon :: struct {
	entity : Entity,
	parent_ecs : ^ECData
}

EcsError :: enum {
	None = 0,
	InvalidEntity = 1,
	NullptrParameter = 2,
	InvalidInputParameter = 3,
	ComponentAlreadyAttached = 4,
	ComponentNotAttached = 5,
	EntityIsMarkedForDestroy,
}

// EntityComponentData
ECData :: struct {

	active_entities_count : u32,

	// Free list is last in first out | Stores indexes into components_indexes arrays
	entities_free_list : [dynamic]i32, 
	pending_destroy    : [dynamic]Entity,

	// @Note: Every Entity is REQUIRED to have a 'EntityInfo' as well as a TransformComponent
	// This means 'entity.id' can be used directly to index into transform_componets array.
	// TransformComponent.entity.id may only be -1 if the corresponding entity has been destroyed 
	// and no new entity has taken its array spot.

	// for each component type there is an indexes array 'component_indexes' to index into the various actual componets arrays
	// all of these arrays are of same length. when adding an entity it will have and index for each component type
	// that might just be '-1' if the component is not attached. 
	// the memory cost of one entity is therefore one 'i32' per component type + tranform component + entity info.
	
	entity_infos: [dynamic]EntityInfo,

	component_indexes : [ComponentType][dynamic]i32,

	transform_components 		: [dynamic]TransformComponent, // All entities have this
	camera_components 			: [dynamic]CameraComponent,
	light_components 			: [dynamic]LightComponent,
	skybox_components 			: [dynamic]SkyboxComponent,
	mesh_renderer_components 	: [dynamic]MeshRendererComponent,
	collider_components 	    : [dynamic]ColliderComponent,

	active_camera_entity : Entity,
	active_skybox_entity : Entity,
	active_skybox_is_dirty : bool,
	
	any_light_is_dirty : bool, // set to false each frame by light_manager after updates

	drawables : #soa[dynamic]Drawable,
}


// @Note: Proc must be updated when adding new components
@(private="file")
ecs_get_components_array :: proc(ecs : ^ECData, $T : typeid) -> (^[dynamic]T) {

	engine_assert(ecs != nil);

	switch typeid_of(T) {
		case typeid_of(TransformComponent):		return cast(^[dynamic]T)&ecs.transform_components;
		case typeid_of(CameraComponent):		return cast(^[dynamic]T)&ecs.camera_components;
		case typeid_of(LightComponent):			return cast(^[dynamic]T)&ecs.light_components;
		case typeid_of(SkyboxComponent): 		return cast(^[dynamic]T)&ecs.skybox_components;
		case typeid_of(MeshRendererComponent):	return cast(^[dynamic]T)&ecs.mesh_renderer_components;
		case typeid_of(ColliderComponent):		return cast(^[dynamic]T)&ecs.collider_components;
	}

	panic("should not be called with anything other than a component type");
}

// @Note: Proc must be updated when adding new components
@(private="file")
ecs_get_component_type_from_typeid :: proc(comp_typeid : typeid) -> ComponentType {

	switch comp_typeid {
		case typeid_of(TransformComponent):		return ComponentType.Transform;
		case typeid_of(CameraComponent):		return ComponentType.Camera;
		case typeid_of(LightComponent):			return ComponentType.Light;
		case typeid_of(SkyboxComponent): 		return ComponentType.Skybox;
		case typeid_of(MeshRendererComponent):	return ComponentType.MeshRenderer;
		case typeid_of(ColliderComponent):		return ComponentType.Collider;
	}

	panic("should not be called with anything other than a component type");
}

// @Note: Proc must be updated when adding new components
@(private="package")
ecs_remove_component_from_component_type :: proc (ecs : ^ECData, entity : Entity, component_type : ComponentType) -> EcsError{
	
	switch component_type {
			case ComponentType.Transform:		return ecs_remove_component(ecs, entity, TransformComponent)
			case ComponentType.Camera:			return ecs_remove_component(ecs, entity, CameraComponent)
			case ComponentType.Light:			return ecs_remove_component(ecs, entity, LightComponent)
			case ComponentType.Skybox:			return ecs_remove_component(ecs, entity, SkyboxComponent)
			case ComponentType.MeshRenderer:	return ecs_remove_component(ecs, entity, MeshRendererComponent)
			case ComponentType.Collider:		return ecs_remove_component(ecs, entity, ColliderComponent)
	}

	panic("invalid codepath")
}

// @Note: Proc must be updated when adding new components
@(private="package")
ecs_add_component_from_component_type :: proc (ecs : ^ECData, entity : Entity, component_type : ComponentType) ->( any, EcsError){
	
	switch component_type {
			case ComponentType.Transform:		return ecs_add_component(ecs, entity, TransformComponent)
			case ComponentType.Camera:			return ecs_add_component(ecs, entity, CameraComponent)
			case ComponentType.Light:			return ecs_add_component(ecs, entity, LightComponent)
			case ComponentType.Skybox:			return ecs_add_component(ecs, entity, SkyboxComponent)
			case ComponentType.MeshRenderer:	return ecs_add_component(ecs, entity, MeshRendererComponent)
			case ComponentType.Collider:		return ecs_add_component(ecs, entity, ColliderComponent)
	}

	panic("invalid codepath")
}

// @Note: Proc must be updated when adding new components
@(private="file")
ecs_delete_component_list_for_component_type :: proc(ecs : ^ECData, component_type : ComponentType) {

	engine_assert(ecs != nil);

	switch component_type {
		case ComponentType.Transform:  		delete(ecs.transform_components);
		case ComponentType.Camera:	 		delete(ecs.camera_components);
		case ComponentType.Light:			delete(ecs.light_components);
		case ComponentType.Skybox:			delete(ecs.skybox_components);
		case ComponentType.MeshRenderer:	delete(ecs.mesh_renderer_components);
		case ComponentType.Collider:		delete(ecs.collider_components);
	}

	return;
}

// @Note: Proc must be updated when adding new components
@(private="file")
ecs_init_component :: proc(component: ^$T, ecs : ^ECData, entity : Entity) {

	component.common.entity = entity;
	component.common.parent_ecs = ecs;

	switch  typeid_of(T) {
		case typeid_of(TransformComponent):		comp_transform_init(cast(^TransformComponent)component);      
		case typeid_of(CameraComponent):		comp_camera_init(cast(^CameraComponent)component);
		case typeid_of(LightComponent):			comp_light_init(cast(^LightComponent)component);
		case typeid_of(SkyboxComponent): 		comp_skybox_init(cast(^SkyboxComponent)component);
		case typeid_of(MeshRendererComponent):	comp_meshrenderer_init(cast(^MeshRendererComponent)component);
		case typeid_of(ColliderComponent):		comp_collider_init(cast(^ColliderComponent)component);
		case: panic("Inavlid Type");
	}
}

// @Note: Proc must be updated when adding new components
@(private="file")
ecs_deinit_component :: proc(component : ^$T) {

	switch  typeid_of(T) {
		case typeid_of(TransformComponent):		comp_transform_deinit(cast(^TransformComponent)component);      
		case typeid_of(CameraComponent):		comp_camera_deinit(cast(^CameraComponent)component);         
		case typeid_of(LightComponent):			comp_light_deinit(cast(^LightComponent)component);          
		case typeid_of(SkyboxComponent): 		comp_skybox_deinit(cast(^SkyboxComponent)component);         
		case typeid_of(MeshRendererComponent):	comp_meshrenderer_deinit(cast(^MeshRendererComponent)component);
		case typeid_of(ColliderComponent):		comp_collider_deinit(cast(^ColliderComponent)component);
		case: panic("Inavlid Type");
	}

	component.common.entity.id = -1;
}

// @Note: Proc must be updated when adding new components
@(private="file")
ecs_deinit_all_components :: proc(ecs : ^ECData){

	// Transform Component
	for &comp in ecs.transform_components {
		comp_transform_deinit(&comp);
	}

	// Camera Component
	for &comp in ecs.camera_components {
		comp_camera_deinit(&comp);
	}

	// Light Component
	for &comp in ecs.light_components {
		comp_light_deinit(&comp);
	}

	// Skybox Component
	for &comp in ecs.skybox_components {
		comp_skybox_deinit(&comp);
	}

	// Mesh Renderer Component
	for &comp in ecs.mesh_renderer_components {
		comp_meshrenderer_deinit(&comp);
	}

	// Collider Component
	for &comp in ecs.collider_components {
		comp_collider_deinit(&comp);
	}
}


@(private="package")
ecs_init :: proc(ecs : ^ECData, reserve_mem_for_n_entities : u32 = 16) {
	
	engine_assert(ecs != nil);

	reserve_amount := reserve_mem_for_n_entities;

	reserve_dynamic_array(&ecs.entity_infos, reserve_amount);
	reserve_dynamic_array(&ecs.transform_components, reserve_amount);
	
	// for each component reserve memory in the indexes list
	for comp_type in ComponentType {

		if comp_type == .Transform {
			continue;
		}

		reserve_dynamic_array(&ecs.component_indexes[comp_type], reserve_amount);
	}


	ecs.active_camera_entity.id = -1;
	ecs.active_skybox_entity.id = -1;
	ecs.active_skybox_is_dirty  = true;
}

@(private="package")
ecs_destroy :: proc(ecs : ^ECData) -> EcsError{

	engine_assert(ecs != nil);

	ecs_deinit_all_components(ecs);

	delete(ecs.entities_free_list);
	
	for &info in ecs.entity_infos {
		if len(info.name) > 0 {
			delete_string(info.name);
		}
	}
	delete(ecs.entity_infos);


	for comp_type in ComponentType {

		ecs_delete_component_list_for_component_type(ecs, comp_type);

		// @Note: transform comp doesn't have a indexes list.
		if comp_type == .Transform {
			continue;
		}

		delete(ecs.component_indexes[comp_type]);
	}

	delete(ecs.pending_destroy);
	delete(ecs.drawables);

	return EcsError.None;
}

@(private="package")
ecs_process_pending_destroy :: proc (ecs : ^ECData){

	for &ent in ecs.pending_destroy {
		ecs_entity_destroy_actual(ecs, &ent);
	}

	clear(&ecs.pending_destroy);
}

// Set an existing entity with a camera component attached to it as the active camera used for rendering
ecs_set_active_camera_entity :: proc(ecs : ^ECData, entity : Entity) -> EcsError {
	
	engine_assert(ecs != nil);

	if !ecs_component_is_attached(ecs, entity, ComponentType.Camera) {
		return EcsError.ComponentNotAttached;
	}

	ecs.active_camera_entity = entity;

	return EcsError.None;
}


ecs_get_active_camera_component :: proc (ecs : ^ECData) -> ^CameraComponent {
	cam_comp, err := ecs_get_component(ecs, ecs.active_camera_entity, CameraComponent);
	if err != EcsError.None {
		return nil;
	}

	return cam_comp;
}


// Set an existing entity with a skybox component attached to it as the active skybox used for rendering
ecs_set_active_skybox_entity :: proc(ecs : ^ECData, entity : Entity) -> EcsError {
	
	engine_assert(ecs != nil);

	if !ecs_component_is_attached(ecs, entity, ComponentType.Skybox) {
		return EcsError.ComponentNotAttached;
	}

	ecs.active_skybox_entity = entity;
	ecs.active_skybox_is_dirty = true;

	return EcsError.None;
}

// returns nill if no active skybox is set
ecs_get_active_skybox_component :: proc(ecs : ^ECData) -> ^SkyboxComponent {
	sky_comp, err := ecs_get_component(ecs, ecs.active_skybox_entity, SkyboxComponent);
	if err != EcsError.None {
		return nil;
	}
	return sky_comp;
}


// =================================================================================
// GATHER & FIND ENTITY PROCEDURES
// =================================================================================

// Gather all entities that have all the components in the include_set and none of the components in the exclude_set
ecs_gather_entities_by_components :: proc(ecs : ^ECData, include_set: ComponentSet, exclude_set: ComponentSet = {}, include_disabled: bool = false, allocator := context.allocator) -> []Entity {

	engine_assert(ecs != nil);

	ents_arr: [dynamic]Entity = make_dynamic_array([dynamic]Entity, allocator);
	reserve_dynamic_array(&ents_arr, len(ecs.entity_infos));

	empty_set := ComponentSet{};

	for ent_info, index in ecs.entity_infos {

		if EntityFlag._Internal_Exists not_in ent_info.flags || !include_disabled && ._Internal_IsEnabled not_in ent_info.flags {
			continue;
		}

		exclude_intersection := exclude_set & ent_info.component_set;
		if exclude_intersection != empty_set  do continue;

		if include_set <= ent_info.component_set { // A <= B -> subset relation (A is a subset of B or equal to B)	

			append(&ents_arr, Entity{id=cast(i32)index, identifier = ent_info.identifier});
		}

	}

	return ents_arr[:];
}

// Gather all entities with a specific tag.
ecs_gather_entities_by_tag :: proc(ecs : ^ECData, ent_tag : u32 = 0, include_disabled : bool = false, only_first : bool = false, allocator := context.allocator) -> []Entity {

	engine_assert(ecs != nil);

	ents_arr: [dynamic]Entity = make_dynamic_array([dynamic]Entity, allocator);

	for ent_info, index in ecs.entity_infos {

		if EntityFlag._Internal_Exists not_in ent_info.flags || !include_disabled && ._Internal_IsEnabled not_in ent_info.flags {
			continue;
		}
		
		if ent_info.tag == ent_tag {

			append(&ents_arr, Entity{id=cast(i32)index, identifier = ent_info.identifier});
			
			if only_first do break;
		}
	}

	return ents_arr[:];
}

// Gather all entities that have all compoents in the include_set and a specific tag. If ent_tag is 0, only search by components.
ecs_gather_entities_by_components_and_tag :: proc(ecs : ^ECData, component_include_set: ComponentSet, ent_tag : u32 = 0 , include_disabled: bool = false, only_first : bool = false, allocator := context.allocator) -> []Entity {

	engine_assert(ecs != nil);

	ents_arr: [dynamic]Entity = make_dynamic_array([dynamic]Entity, allocator);

	for ent_info, index in ecs.entity_infos {

		if EntityFlag._Internal_Exists not_in ent_info.flags || !include_disabled && ._Internal_IsEnabled not_in ent_info.flags {
			continue;
		}

		if ent_tag == 0 {
			
			if component_include_set <= ent_info.component_set { // A <= B -> subset relation (A is a subset of B or equal to B)	

				append(&ents_arr, Entity{id=cast(i32)index, identifier = ent_info.identifier});

				if only_first do break;
			}
		} else if ent_info.tag == ent_tag {

			if component_include_set <= ent_info.component_set { // A <= B -> subset relation (A is a subset of B or equal to B)	

				append(&ents_arr, Entity{id=cast(i32)index, identifier = ent_info.identifier});
				
				if only_first do break;
			}
		}
	}

	return ents_arr[:];
}

// Gather all entities with a specific tag and name. If tag is 0 only search by name (but slow)
ecs_gather_entities_by_name_and_tag :: proc(ecs : ^ECData, ent_name : string, ent_tag : u32 = 0, include_disabled: bool = false, only_first : bool = false, allocator := context.allocator) -> []Entity {

	engine_assert(ecs != nil);

	ents_arr: [dynamic]Entity = make_dynamic_array([dynamic]Entity, allocator);

	for ent_info, index in ecs.entity_infos {

		if EntityFlag._Internal_Exists not_in ent_info.flags || !include_disabled && ._Internal_IsEnabled not_in ent_info.flags {
			continue;
		}

		if ent_tag == 0 {

			if ent_name == ent_info.name {
				append(&ents_arr, Entity{id=cast(i32)index, identifier = ent_info.identifier});

				if only_first do break;
			}
		} else if  ent_info.tag == ent_tag {

			if ent_name == ent_info.name {
				append(&ents_arr, Entity{id=cast(i32)index, identifier = ent_info.identifier});

				if only_first do break;
			}
		}
	}

	return ents_arr[:];
}

// Return first entity found with a tag, returns EntityInvalid if non is found.
ecs_find_first_entity_by_tag :: proc(ecs : ^ECData, ent_tag : u32, include_disabled: bool = false) -> (Entity) {
	ents := ecs_gather_entities_by_tag(ecs, ent_tag, include_disabled, true, context.temp_allocator);

	if len(ents) > 0{
		return ents[0];
	}

	return EntityInvalid;
}

ecs_find_first_entity_by_components_and_tag :: proc(ecs : ^ECData, component_include_set: ComponentSet, ent_tag : u32 = 0, include_disabled: bool = false) -> (Entity) {
	ents := ecs_gather_entities_by_components_and_tag(ecs, component_include_set, ent_tag, include_disabled, true, context.temp_allocator);

	if len(ents) > 0{
		return ents[0];
	}

	return EntityInvalid;
}

ecs_find_first_entity_by_name_and_tag :: proc(ecs : ^ECData, ent_name : string, ent_tag : u32 = 0, include_disabled: bool = false) -> (Entity) {
	ents := ecs_gather_entities_by_name_and_tag(ecs, ent_name, ent_tag, include_disabled, true, context.temp_allocator);

	if len(ents) > 0{
		return ents[0];
	}

	return EntityInvalid;
}

// =================================================================================
// ENTITY PROCEDURES
// =================================================================================

ecs_entity_create :: proc(ecs : ^ECData, ent_name : string = "NewEntity", ent_tag : u32 = 0) -> Entity {

	engine_assert(ecs != nil);

	entity := EntityInvalid;
	
	identifier : i32 = rand.int31();

	new_entity_info : EntityInfo = EntityInfo {
		name = strings.clone(ent_name, context.allocator),
		identifier = identifier,
		flags  = EntityFlags{._Internal_IsEnabled, ._Internal_Exists},
		component_set = ComponentSet{.Transform},
		tag = ent_tag,
		user_data = 0,
	}


	defer ecs.active_entities_count += 1;

	// Check freelist of entities
	if len(ecs.entities_free_list) > 0 {

		entity.id = ecs.entities_free_list[len(ecs.entities_free_list) - 1];
		entity.identifier = identifier;

		pop(&ecs.entities_free_list);

		// set entity_info and transform component to default values and assert that they are not used
		entity_info := &ecs.entity_infos[entity.id];
		engine_assert(EntityFlag._Internal_Exists not_in entity_info.flags);
		
		ecs.entity_infos[entity.id] = new_entity_info;

		
		transform_comp := &ecs.transform_components[entity.id];
		engine_assert(transform_comp.entity.id == -1);

		ecs_init_component(transform_comp, ecs, entity);

		return entity;
	}

	// Allocate memory for new entity
	// append one entity component index (initialized to -1) to all components
	
	entity.id = cast(i32)len(&ecs.entity_infos); // no '-1' neccesary since we are about to append one
	entity.identifier = identifier;

	append(&ecs.entity_infos, new_entity_info);

	//NOTE: Transform Component is a special case, Every Entity is Required to have a transform component attached so we create it directly.
	transform_comp : TransformComponent;

	ecs_init_component(&transform_comp, ecs, entity);
	append(&ecs.transform_components, transform_comp);

	engine_assert(len(ecs.transform_components) == len(ecs.entity_infos));

	// for each component append new component index with -1 meaning the component is not attached
	for comp_type in ComponentType {
		
		// @Note - Transform component doesn't have an indexes list
		if comp_type == ComponentType.Transform {
			continue;
		}

		append(&ecs.component_indexes[comp_type], -1);
	}

	return entity;
}

ecs_entity_destroy :: proc(ecs : ^ECData, entity : ^Entity) -> EcsError {

	if !ecs_entity_exists(ecs, entity^) {
		return EcsError.InvalidEntity;
	}

	ecs.entity_infos[entity.id].flags -= EntityFlags{._Internal_IsEnabled};
	ecs.entity_infos[entity.id].flags += EntityFlags{._Internal_PendingDestroy};

	ecs_on_enabled_changed(ecs, entity^);

	append(&ecs.pending_destroy, entity^);

	entity^ = EntityInvalid;
	return EcsError.None;
}

@(private="file")
ecs_entity_destroy_actual :: proc(ecs : ^ECData, entity : ^Entity) -> EcsError {

	engine_assert(ecs != nil);
	engine_assert(entity != nil);

	// Check entity has a valid id
	if !ecs_entity_exists(ecs, entity^) {
		return EcsError.InvalidEntity;
	}

	defer {
	 	ecs.active_entities_count -= 1;
	 	// invalidize the input entity
		entity.id = -1;
		entity.identifier = -1;
	}

	// Remove all components this entity has
	for comp_type in ComponentType {
		
		// Note: special case for transform comp, is already handeled above ^^
		if comp_type == ComponentType.Transform {
			continue; 
		}

		err := ecs_remove_component_from_component_type(ecs, entity^, comp_type);
	}

	// Mark EntityInfo as non existent
	entity_info := &ecs.entity_infos[entity.id];
	if len(entity_info.name) > 0 {
		delete_string(entity_info.name)
		entity_info.name = ""; // This is required because delete string does not reset the length to 0..
	}
	entity_info.identifier 		= -1;
	entity_info.flags 			= EntityFlags{};
	entity_info.component_set 	= ComponentSet{};
	entity_info.tag 			= 0;
	entity_info.user_data 		= 0;

	// Deinit the transform Component.
	ecs_deinit_component(&ecs.transform_components[entity.id]);

	// add entity ID to free list
	append(&ecs.entities_free_list, entity.id);

	return EcsError.None;
}

ecs_add_component ::proc(ecs : ^ECData, entity : Entity,  $T : typeid) -> (^T, EcsError) {

	engine_assert(ecs != nil);

	if !ecs_entity_exists(ecs, entity) {
		return nil, EcsError.InvalidEntity;
	}

	if ._Internal_PendingDestroy in ecs.entity_infos[entity.id].flags {
		return nil, EcsError.EntityIsMarkedForDestroy;
	}

	component_type : ComponentType = ecs_get_component_type_from_typeid(T);

	if component_type in ecs.entity_infos[entity.id].component_set {
		return nil, EcsError.ComponentAlreadyAttached;
	}

	// The TransformComponent bit in the component_set (Bitset) should always be 1 (unless the entity does not exist) 
	// Therefore we can assert that is got cought by the above two if checks
	engine_assert(component_type != ComponentType.Transform); 

	comp_common := ComponentCommon{
		entity = entity,
		parent_ecs = ecs,
	}

	component : T = T{};
	ecs_init_component(&component, ecs, entity);

	components_array := ecs_get_components_array(ecs, T);

	append(components_array, component);

	comp_index := i32(len(components_array) -1)
	// make a new component and append it	
	//comp_index := ecs_append_new_component_for_component_type(ecs, component_type, entity);
	
	components_indexes_array: ^[dynamic]i32 = &ecs.component_indexes[component_type];
	
	engine_assert(components_indexes_array != nil);
	engine_assert(components_indexes_array[entity.id] == -1); // Component must not exist!

	components_indexes_array[entity.id] = comp_index;


	// Update the Component bit Set
	ecs.entity_infos[entity.id].component_set = ecs.entity_infos[entity.id].component_set + ComponentSet{component_type};

	return &components_array[comp_index], EcsError.None;
}

ecs_remove_component ::proc(ecs : ^ECData, entity : Entity,  $T : typeid) -> EcsError {

	engine_assert(ecs != nil)

	if !ecs_entity_exists(ecs, entity) {
		return EcsError.InvalidEntity;
	}

	component_type := ecs_get_component_type_from_typeid(T);

	if component_type not_in ecs.entity_infos[entity.id].component_set {
		return EcsError.ComponentNotAttached;
	}

	// transform components cannot be removed manually
	if component_type == .Transform {
		return EcsError.InvalidInputParameter; 
	}

	components_indexes_list := &ecs.component_indexes[component_type];
	comp_index := components_indexes_list[entity.id];
	engine_assert(comp_index >= 0); // Component Must Exists

	components_array := ecs_get_components_array(ecs, T);
	component := &components_array[comp_index];

	// Special Case Camera if it is active one
	if component_type == .Camera {
		if entity == ecs.active_camera_entity {
			ecs.active_camera_entity.id = -1;
		}
	}

	if component_type == .Skybox {
		if entity == ecs.active_skybox_entity {
			ecs.active_skybox_entity.id = -1;
			ecs.active_skybox_is_dirty = true;
		}
	}

	// First reset the component we want to destroy so all resources are cleaned up.
	ecs_deinit_component(component);
		
	defer {
		// Mark Entity to not have this component
		components_indexes_list[entity.id] = -1; 
		// Also Remove from component bit set of the entity
		ecs.entity_infos[entity.id].component_set -= ComponentSet{component_type};
	}

	// if we are removing the last component in the components array, we can just pop it off
	if(comp_index == cast(i32)len(components_array) -1) {
		pop(components_array);
		return EcsError.None;
	}

	// Note:
	// here we do an unordered remove, so we copy the last component element to the component we want to remove
	// then we pop back the last element since its a dublicate now.
	// then we must re-assign the comp_index of the copied component.
	// so we use the entitiy-id stored in the component we copyied to know which comp_index in the 
	// 'components_indexes_list' we must set to the copied-to postion.

	// Copy last element to remove postion and pop of last.
	components_array[comp_index] = components_array[len(components_array)-1];
	pop(components_array);

	// get id of copied element and reassing its index
	id := components_array[comp_index].entity.id;
	components_indexes_list[id] = comp_index;

	return EcsError.None;
}

ecs_get_component :: proc(ecs : ^ECData, entity : Entity,  $T : typeid) -> (^T, EcsError) {

	engine_assert(ecs != nil);

	component_type := ecs_get_component_type_from_typeid(T);

	if !ecs_component_is_attached(ecs, entity, component_type) {
		return nil, EcsError.ComponentNotAttached;
	}

	if typeid_of(T) == typeid_of(TransformComponent) {
		return cast(^T)&ecs.transform_components[entity.id], EcsError.None;
	}


	component_index := ecs.component_indexes[component_type][entity.id];

	engine_assert(component_index >= 0);

	components_array := ecs_get_components_array(ecs, T);

	return &components_array[component_index], EcsError.None;
}

ecs_get_transform :: proc(ecs : ^ECData, entity : Entity) -> ^TransformComponent {
	engine_assert(ecs != nil);

	if !ecs_entity_exists(ecs, entity) {
		return nil;
	}

	return &ecs.transform_components[entity.id];
}

ecs_entity_exists :: proc(ecs : ^ECData, entity : Entity) -> bool {

	engine_assert(ecs != nil);

	if entity.id < 0 || entity.id >= cast(i32)len(ecs.entity_infos) {
		return false;
	}

	if EntityFlag._Internal_Exists not_in ecs.entity_infos[entity.id].flags {
		return false;
	}

	if ecs.entity_infos[entity.id].identifier != entity.identifier {
		return false;
	}

	return true;
}

ecs_entity_get_name :: proc(ecs : ^ECData, entity : Entity) -> (string, EcsError){
	if !ecs_entity_exists(ecs, entity) {
		return "", EcsError.InvalidEntity;
	}

	return ecs.entity_infos[entity.id].name, EcsError.None;
}

ecs_entity_rename :: proc(ecs : ^ECData, entity : Entity, new_name : string) -> EcsError{

	if len(new_name) <= 0 {
		return EcsError.InvalidInputParameter;
	}

	if !ecs_entity_exists(ecs, entity) {
		return EcsError.InvalidEntity;
	}

	info := &ecs.entity_infos[entity.id];

	if len(info.name) > 0 {
		delete_string(info.name);
	}

	info.name = strings.clone(new_name, context.allocator);

	return EcsError.None;
}
	
ecs_entity_set_tag :: proc(ecs : ^ECData, entity : Entity, new_tag : u32) -> EcsError {
	
	if !ecs_entity_exists(ecs, entity) {
		return EcsError.InvalidEntity;
	}

	ecs.entity_infos[entity.id].tag = new_tag;

	return EcsError.None;
}

ecs_entity_get_tag :: proc(ecs : ^ECData, entity : Entity) -> (u32, EcsError) {
	
	if !ecs_entity_exists(ecs, entity) {
		return 0, EcsError.InvalidEntity;
	}

	return ecs.entity_infos[entity.id].tag, EcsError.None;
}

ecs_entity_is_enabled :: proc(ecs : ^ECData, entity : Entity) -> bool {
	
	if !ecs_entity_exists(ecs, entity) {
		return false;
	}

	return EntityFlag._Internal_IsEnabled in ecs.entity_infos[entity.id].flags;
}

ecs_entity_set_enabled :: proc(ecs : ^ECData, entity : Entity, new_enabled : bool) -> EcsError{
	
	if !ecs_entity_exists(ecs, entity) {
		return EcsError.InvalidEntity;
	}

	if ._Internal_PendingDestroy in ecs.entity_infos[entity.id].flags {
		return EcsError.EntityIsMarkedForDestroy;
	}

	if new_enabled == true {
		ecs.entity_infos[entity.id].flags += EntityFlags{._Internal_IsEnabled};
	} else {
		ecs.entity_infos[entity.id].flags -= EntityFlags{._Internal_IsEnabled};
	}
	ecs_on_enabled_changed(ecs, entity);

	return EcsError.None;
}

// @Note. only allows setting non _Internal flags
ecs_entity_set_flags :: proc(ecs : ^ECData, entity : Entity, flags : EntityFlags, subtract_flags : bool = false) -> EcsError{
	if !ecs_entity_exists(ecs, entity) {
		return EcsError.InvalidEntity;
	}

	// Remove any internal flags form the input flags
	flgs : EntityFlags = flags - iricom.ENTITY_FLAGS_INTERNAL;

	if subtract_flags {
		ecs.entity_infos[entity.id].flags -= flgs;
	} else {
		ecs.entity_infos[entity.id].flags += flgs;
	}

	return EcsError.None;
}

ecs_component_is_attached :: proc(ecs : ^ECData, entity : Entity,  component_type : ComponentType) -> bool {

	engine_assert(ecs != nil);

	if !ecs_entity_exists(ecs, entity) {
		return false;
	}

	if component_type in ecs.entity_infos[entity.id].component_set {
		return true;
	}

	return false;
}

ecs_get_entity_info :: proc(ecs : ^ECData, entity : Entity) -> (info : EntityInfo, err : EcsError) {

	engine_assert(ecs != nil);

	if !ecs_entity_exists(ecs, entity){
		return EntityInfo{}, EcsError.InvalidEntity;
	}

	// Explicitly a copy because we dont want userers to mess this the info struct it should be read only..
	// string name will be modifiable but that should mostly not break anything.
	return ecs.entity_infos[entity.id], EcsError.None;
}

@(private="package")
ecs_on_enabled_changed :: proc(ecs : ^ECData, entity : Entity){
	
	light_comp , err := ecs_get_component(ecs, entity, LightComponent);
	if light_comp != nil {
		comp_light_push_changes(light_comp);
	}
}


// =================================================================================
// DRAWABLES
// =================================================================================


// Returns -1 if entity doesnt exist.
@(private="package")
ecs_drawable_add :: proc(ecs : ^ECData, entity : Entity, drawable : ^Drawable) -> (id : int) {

	if !ecs_entity_exists(ecs, entity) {
		return -1;
	}

	drawable.entity = entity;

	entity_transform := ecs_get_transform(ecs, drawable.entity);

	world_transform    := transform_child_by_parent(entity_transform, drawable.draw_instance.transform);
	drawable.world_mat = transform_calc_world_matrix(world_transform);

	if mesh_manager_is_valid_id(engine.mesh_manager, drawable.draw_instance.mesh_id) {	
		mesh_aabb := mesh_manager_get_aabb(engine.mesh_manager, drawable.draw_instance.mesh_id);
		drawable.world_oobb = aabb_to_transformed_oobb(mesh_aabb, world_transform);
	} else {
		drawable.draw_instance.flags += DrawInstanceFlags{._Internal_NoValidMesh}
	}

	index := len(ecs.drawables);

	append_soa(&ecs.drawables, drawable^);

	return index;
}

@(private="package")
ecs_drawable_remove :: proc(ecs : ^ECData, index : ^int) {

	defer {
		index^ = -1; // invalidate callers id.
	}

	_index := index^;

	if !ecs_drawable_valid_index(ecs, _index) {
		return;
	}

	// We want to do an unordered remove but we need to iterate the ids of the MeshRendererComponent
	// that holds the index to the last element afterwards to update its index.

	last : int = len(ecs.drawables) -1;

	if _index == last {
		// we can just remove it and dont have to update any indexes.
		ordered_remove_soa(&ecs.drawables, _index);
		return;
	}

	// this will remove the element at index and copy last element there instead.
	unordered_remove_soa(&ecs.drawables, _index);

	// we must force update this entity.
	ecs_drawable_force_update(ecs, _index);

	// Since drawable already stores the entity to which it belongs.
	// we know which meshrenderer component holds the index to the swaped item
	// so we just have to iterate the meshrenderer's indexes list
	// to find the index that pointed to the last element which is now removed.

	mesh_renderer, ecsErr := ecs_get_component(ecs, ecs.drawables[_index].entity, MeshRendererComponent);
	engine_assert(mesh_renderer != nil);

	found : bool = false;
	for i in 0..<len(mesh_renderer.drawable_indexes) {

		if mesh_renderer.drawable_indexes[i] == last {

			mesh_renderer.drawable_indexes[i] = _index;
			found = true;
			break;
		}
	}

	engine_assert(found);
}

@(private="package")
ecs_drawable_force_update :: proc(ecs : ^ECData, index : int) {

	if !ecs_drawable_valid_index(ecs, index){
		return;
	}

	entity := ecs.drawables.entity[index];

	ecs.drawables[index].draw_instance.flags += DrawInstanceFlags{._Internal_ForceUpdate};
}

@(private="package")
ecs_drawable_get_draw_instance :: proc(ecs : ^ECData, index : int) -> ^DrawInstance {

	if !ecs_drawable_valid_index(ecs, index){
		return nil;
	}

	return &ecs.drawables.draw_instance[index];
}

@(private="package")
ecs_drawable_valid_index :: #force_inline proc(ecs : ^ECData, index : int) -> bool {
	return index >= 0 && index < len(ecs.drawables);
}
