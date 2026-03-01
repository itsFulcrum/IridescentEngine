package iri

import "core:log"


Entity :: struct {
	id : i32,
}

ComponentCommon :: struct {
	entity : Entity,
	parent_ecs : ^EntityComponentData
}

EntityInfo :: struct {
	exists:   bool,
	enabled:  bool,
	padding1: bool, // we have 2 bytes worth of padding here to use for future stuff
	padding2: bool,
	component_set: ComponentSet,
}

ComponentSet :: bit_set[ComponentType]
ComponentType :: enum u32 {
	Transform 	 = 0,
	Camera 		 ,
	Light 		 ,
	Skybox		 ,
	MeshRenderer ,
	CustomShader,
}


EcsError :: enum {
	Success = 0,
	Invalid_Entity_Id = 1,
	Nullptr_Parameter = 2,
	Invalid_Input_Parameter = 3,
	Component_Already_Attached = 4,
	Component_Not_Attached = 5,
}

EntityComponentData :: struct {

	active_entities_count : u32,

	// Free lists are always last in first out | Stores indexes into xxx_components_indexes arrays
	entities_free_list : [dynamic]i32, 


	// NOTE: Every Entity is REQUIRED and ensured to have a 'EntityInfo' as well as a TransformComponent
	// This means 'entity.id' can be used directly to index into transform_componets array.
	// TransformComponent.entity.id may only be -1 if the corresponding entity has been destroyed 
	// and no new entity has taken its array spot.

	entity_infos: [dynamic]EntityInfo,

	// for each component a indexes array to index into the various actual componets arrays
	// all of these arrays are of same length. when adding an entity it will have and index for each component type
	// that might just be '-1' if the component is not attached. 
	// the memory cost of one entity is therefore one 'i32' per component + tranform component + entity info.

	component_indexes : [ComponentType][dynamic]i32,

	// NOTE: Every entity is Required to have a transform component.
	transform_components 		: [dynamic]TransformComponent,
	camera_components 			: [dynamic]CameraComponent,
	light_components 			: [dynamic]LightComponent,
	skybox_components 			: [dynamic]SkyboxComponent,
	mesh_renderer_components 	: [dynamic]MeshRendererComponent,
	custom_shader_components 	: [dynamic]CustomShaderComponent,


	active_camera_entity : Entity,
	active_skybox_entity : Entity,
	active_skybox_is_dirty : bool,


	drawables : #soa[dynamic]Drawable,
	any_light_is_dirty : bool, // set to false each frame by light_manager after updates
}

// NOTE: Proc must be updated when adding new components
@(private="file")
ecs_get_components_array :: proc(ecs : ^EntityComponentData, $T : typeid) -> (^[dynamic]T) {

	engine_assert(ecs != nil);

	switch typeid_of(T) {
		case typeid_of(TransformComponent):		return cast(^[dynamic]T)&ecs.transform_components;
		case typeid_of(CameraComponent):		return cast(^[dynamic]T)&ecs.camera_components;
		case typeid_of(LightComponent):			return cast(^[dynamic]T)&ecs.light_components;
		case typeid_of(SkyboxComponent): 		return cast(^[dynamic]T)&ecs.skybox_components;
		case typeid_of(MeshRendererComponent):	return cast(^[dynamic]T)&ecs.mesh_renderer_components;
		case typeid_of(CustomShaderComponent):	return cast(^[dynamic]T)&ecs.custom_shader_components;
	}

	panic("should not be called with anything other than a component type");
}


// NOTE: Proc must be updated when adding new components
@(private="file")
ecs_get_component_type_from_typeid :: proc(comp_typeid : typeid) -> ComponentType {

	switch comp_typeid {
		case typeid_of(TransformComponent):		return ComponentType.Transform;
		case typeid_of(CameraComponent):		return ComponentType.Camera;
		case typeid_of(LightComponent):			return ComponentType.Light;
		case typeid_of(SkyboxComponent): 		return ComponentType.Skybox;
		case typeid_of(MeshRendererComponent):	return ComponentType.MeshRenderer;
		case typeid_of(CustomShaderComponent):	return ComponentType.CustomShader;
	}

	panic("should not be called with anything other than a component type");
}

// NOTE: Proc must be updated when adding new components
@(private="package")
ecs_remove_component_from_component_type :: proc (ecs : ^EntityComponentData, entity : Entity, component_type : ComponentType) -> EcsError{
	
	switch component_type {
			case ComponentType.Transform:		return ecs_remove_component(ecs, entity, TransformComponent)
			case ComponentType.Camera:			return ecs_remove_component(ecs, entity, CameraComponent)
			case ComponentType.Light:			return ecs_remove_component(ecs, entity, LightComponent)
			case ComponentType.Skybox:			return ecs_remove_component(ecs, entity, SkyboxComponent)
			case ComponentType.MeshRenderer:	return ecs_remove_component(ecs, entity, MeshRendererComponent)
			case ComponentType.CustomShader:	return ecs_remove_component(ecs, entity, CustomShaderComponent)
	}

	panic("invalid codepath")
}

// NOTE: Proc must be updated when adding new components
@(private="package")
ecs_add_component_from_component_type :: proc (ecs : ^EntityComponentData, entity : Entity, component_type : ComponentType) ->( any, EcsError){
	
	switch component_type {
			case ComponentType.Transform:		return ecs_add_component(ecs, entity, TransformComponent)
			case ComponentType.Camera:			return ecs_add_component(ecs, entity, CameraComponent)
			case ComponentType.Light:			return ecs_add_component(ecs, entity, LightComponent)
			case ComponentType.Skybox:			return ecs_add_component(ecs, entity, SkyboxComponent)
			case ComponentType.MeshRenderer:	return ecs_add_component(ecs, entity, MeshRendererComponent)
			case ComponentType.CustomShader:	return ecs_add_component(ecs, entity, CustomShaderComponent)
	}


	panic("invalid codepath")
}

// NOTE: Proc must be updated when adding new components
@(private="file")
ecs_delete_component_list_for_component_type :: proc(ecs : ^EntityComponentData, component_type : ComponentType) {

	engine_assert(ecs != nil);

	switch (component_type) {
		case ComponentType.Transform:  		delete(ecs.transform_components);
		case ComponentType.Camera:	 		delete(ecs.camera_components);
		case ComponentType.Light:			delete(ecs.light_components);
		case ComponentType.Skybox:			delete(ecs.skybox_components);
		case ComponentType.MeshRenderer:	delete(ecs.mesh_renderer_components);
		case ComponentType.CustomShader:	delete(ecs.custom_shader_components);
	}

	return;
}

//NOTE: Proc must be updated when adding new components
@(private="file")
ecs_init_component :: proc(component: ^$T, ecs : ^EntityComponentData, entity : Entity) {

	component.common.entity = entity;
	component.common.parent_ecs = ecs;

	switch  typeid_of(T) {
		case typeid_of(TransformComponent):		comp_transform_init(cast(^TransformComponent)component);      
		case typeid_of(CameraComponent):		comp_camera_init(cast(^CameraComponent)component);
		case typeid_of(LightComponent):			comp_light_init(cast(^LightComponent)component);
		case typeid_of(SkyboxComponent): 		comp_skybox_init(cast(^SkyboxComponent)component);
		case typeid_of(MeshRendererComponent):	comp_meshrenderer_init(cast(^MeshRendererComponent)component);
		case typeid_of(CustomShaderComponent):	comp_customshader_init(cast(^CustomShaderComponent)component);
		case: panic("Inavlid Type");
	}
}

//NOTE: Proc must be updated when adding new components
@(private="file")
ecs_deinit_component :: proc(component : ^$T) {

	switch  typeid_of(T) {
		case typeid_of(TransformComponent):		comp_transform_deinit(cast(^TransformComponent)component);      
		case typeid_of(CameraComponent):		comp_camera_deinit(cast(^CameraComponent)component);         
		case typeid_of(LightComponent):			comp_light_deinit(cast(^LightComponent)component);          
		case typeid_of(SkyboxComponent): 		comp_skybox_deinit(cast(^SkyboxComponent)component);         
		case typeid_of(MeshRendererComponent):	comp_meshrenderer_deinit(cast(^MeshRendererComponent)component);
		case typeid_of(CustomShaderComponent):	comp_customshader_deinit(cast(^CustomShaderComponent)component);
		case: panic("Inavlid Type");
	}

	component.common.entity.id = -1;
}

// NOTE: Proc must be updated when adding new components
@(private="file")
ecs_deinit_all_components :: proc(ecs : ^EntityComponentData){

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

	// Custom Shader Component
	for &comp in ecs.custom_shader_components {
		comp_customshader_deinit(&comp);
	}
}


@(private="package")
ecs_init :: proc(ecs : ^EntityComponentData, reserve_mem_for_n_entities : u32 = 20) {
	
	engine_assert(ecs != nil);

	reserve_amount := reserve_mem_for_n_entities;

	reserve_dynamic_array(&ecs.entity_infos, reserve_amount);
	reserve_dynamic_array(&ecs.transform_components, reserve_amount);
	
	// for each component reserve memory in the indexes list
	for comp_type in ComponentType {

		if(comp_type == ComponentType.Transform){
			continue;
		}

		reserve_dynamic_array(&ecs.component_indexes[comp_type], reserve_amount);
	}


	ecs.active_camera_entity.id = -1;
	ecs.active_skybox_entity.id = -1;
	ecs.active_skybox_is_dirty  = true;
}

@(private="package")
ecs_destroy :: proc(ecs : ^EntityComponentData) -> EcsError{

	engine_assert(ecs != nil);

	ecs_deinit_all_components(ecs);

	delete(ecs.entities_free_list);
	delete(ecs.entity_infos);

	for comp_type in ComponentType {

		ecs_delete_component_list_for_component_type(ecs, comp_type);

		// @Note: transform comp doesn't have a indexes list.
		if(comp_type == ComponentType.Transform){
			continue;
		}

		delete(ecs.component_indexes[comp_type]);
	}

	delete(ecs.drawables);

	return EcsError.Success;
}

@(private="package")
ecs_entity_exists :: proc(ecs : ^EntityComponentData, entity : Entity) -> bool {

	engine_assert(ecs != nil);

	if(entity.id < 0 || entity.id >= cast(i32)len(ecs.entity_infos)) {
		return false;
	}

	return ecs.entity_infos[entity.id].exists;
}


// Get a list of entities that all have the components in include_set and none in the exclude_set
@(private="package")
ecs_gather_all_entities_with_components :: proc(ecs : ^EntityComponentData, component_include_set: ComponentSet, component_exclude_set: ComponentSet =  {}, include_disabled_entities: bool = false, allocator := context.allocator) -> []Entity {

	engine_assert(ecs != nil);

	ents_arr: [dynamic]Entity = make_dynamic_array([dynamic]Entity, allocator);
	reserve_dynamic_array(&ents_arr, len(ecs.entity_infos));

	empty_set := ComponentSet{};

	for ent_info, index in ecs.entity_infos {

		if(!ent_info.exists || !include_disabled_entities && !ent_info.enabled) do continue;

		exclude_intersection := component_exclude_set & ent_info.component_set;
		if(exclude_intersection != empty_set) do continue;

		if(component_include_set <= ent_info.component_set){ // A <= B -> subset relation (A is a subset of B or equal to B)	

			append(&ents_arr, Entity{id=cast(i32)index});
		}

	}

	return ents_arr[:];
}

// =================================================================================
// ENTITY PROCEDURES
// =================================================================================

@(private="package")
ecs_entity_create :: proc(ecs : ^EntityComponentData) -> Entity {

	engine_assert(ecs != nil);

	entity := Entity{id = -1};

	defer ecs.active_entities_count += 1;

	// Check freelist of entities
	if(len(ecs.entities_free_list) > 0){

		entity.id = ecs.entities_free_list[len(ecs.entities_free_list) - 1];
		pop(&ecs.entities_free_list);

		// set entity_info and transform component to default values and assert that they are not used
		entity_info := &ecs.entity_infos[entity.id];
		engine_assert(entity_info.exists == false);
		entity_info.exists = true;
		entity_info.enabled = true;
		entity_info.component_set = ComponentSet{.Transform};

		transform_comp := &ecs.transform_components[entity.id];
		engine_assert(transform_comp.entity.id == -1);

		ecs_init_component(transform_comp, ecs, entity);

		return entity;
	}

	// Allocate memory for new entity
	// append one entity component index (initialized to -1) to all components
	
	entity.id = cast(i32)len(&ecs.entity_infos); // no '-1' neccesary since we are about to append one

	entity_info: EntityInfo = EntityInfo{
		exists = true,
		enabled = true,
		component_set = ComponentSet{.Transform},
	}

	append(&ecs.entity_infos, entity_info);

	//NOTE: Transform Component is a special case, Every Entity is Required to have a transform component attached so we create it directly.
	transform_comp : TransformComponent;

	ecs_init_component(&transform_comp, ecs, entity);
	append(&ecs.transform_components, transform_comp);

	engine_assert(len(ecs.transform_components) == len(ecs.entity_infos));

	// for each component append new component index with -1 meaning the component is not attached
	for comp_type in ComponentType {
		
		// @Note - Transform component doesn't have an indexes list
		if(comp_type == ComponentType.Transform){
			continue;
		}

		append(&ecs.component_indexes[comp_type], -1);
	}

	return entity;
}

@(private="package")
ecs_entity_destroy :: proc(ecs : ^EntityComponentData, entity : ^Entity) -> EcsError {

	engine_assert(ecs != nil);
	engine_assert(entity != nil);

	// Check entity has a valid id
	if(!ecs_entity_exists(ecs, entity^)){
		return EcsError.Invalid_Entity_Id;
	}

	defer ecs.active_entities_count -= 1;

	// Remove all components this entity has
	for comp_type in ComponentType {
		
		// Note: special case for transform comp, is already handeled above ^^
		if(comp_type == ComponentType.Transform){
			continue; 
		}

		err := ecs_remove_component_from_component_type(ecs, entity^, comp_type);
	}

	// Mark EntityInfo as non existent
	entity_info := &ecs.entity_infos[entity.id];
	entity_info.exists = false;
	entity_info.enabled = false;
	entity_info.component_set = ComponentSet{};

	// Deinit the transform Component.
	ecs_deinit_component(&ecs.transform_components[entity.id]);

	// add entity ID to free list
	append(&ecs.entities_free_list, entity.id);

	entity.id = -1; // invalidize the input entity id.

	return EcsError.Success;
}

@(private="package")
ecs_component_is_attached :: proc(ecs : ^EntityComponentData, entity : Entity,  component_type : ComponentType) -> bool {

	engine_assert(ecs != nil);

	if(!ecs_entity_exists(ecs, entity)){
		return false;
	}

	if(component_type in ecs.entity_infos[entity.id].component_set){
		return true;
	}

	return false;
}

@(private="package")
ecs_add_component ::proc(ecs : ^EntityComponentData, entity : Entity,  $T : typeid) -> (^T, EcsError) {

	engine_assert(ecs != nil);

	if(!ecs_entity_exists(ecs, entity)){
		return nil, EcsError.Invalid_Entity_Id;
	}

	component_type : ComponentType = ecs_get_component_type_from_typeid(T);

	if(component_type in ecs.entity_infos[entity.id].component_set ){
		return nil, EcsError.Component_Already_Attached;
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

	return &components_array[comp_index], EcsError.Success;
}

@(private="package")
ecs_remove_component ::proc(ecs : ^EntityComponentData, entity : Entity,  $T : typeid) -> EcsError {

	engine_assert(ecs != nil)

	if(!ecs_entity_exists(ecs, entity)){
		return EcsError.Invalid_Entity_Id;
	}

	component_type := ecs_get_component_type_from_typeid(T);

	if(component_type not_in ecs.entity_infos[entity.id].component_set){
		return EcsError.Component_Not_Attached;
	}

	// transform components cannot be removed manually
	if(component_type == ComponentType.Transform){
		return EcsError.Invalid_Input_Parameter; 
	}

	components_indexes_list := &ecs.component_indexes[component_type];
	comp_index := components_indexes_list[entity.id];
	engine_assert(comp_index >= 0); // Component Must Exists


	components_array := ecs_get_components_array(ecs, T);
	component := &components_array[comp_index];

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
		return EcsError.Success;
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

	return EcsError.Success;
}


@(private="package")
ecs_get_component :: proc(ecs : ^EntityComponentData, entity : Entity,  $T : typeid) -> (^T, EcsError) {

	engine_assert(ecs != nil);

	component_type := ecs_get_component_type_from_typeid(T);

	if(!ecs_component_is_attached(ecs, entity, component_type)){
		return nil, EcsError.Component_Not_Attached;
	}

	if(typeid_of(T) == typeid_of(TransformComponent)){
		return cast(^T)&ecs.transform_components[entity.id], EcsError.Success;
	}


	component_index := ecs.component_indexes[component_type][entity.id];

	engine_assert(component_index >= 0);

	components_array := ecs_get_components_array(ecs, T);

	return &components_array[component_index], EcsError.Success;
}

@(private="package")
ecs_get_transform :: proc(ecs : ^EntityComponentData, entity : Entity) -> ^TransformComponent {
	engine_assert(ecs != nil);

	if(!ecs_entity_exists(ecs, entity)){
		return nil;
	}

	return &ecs.transform_components[entity.id];
}