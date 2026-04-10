package iri

ColliderType :: enum u8 {
	Sphere,
	Box,
}

SphereCollider :: struct {
	radius : f32,
}

BoxCollider :: struct {
	extent : [3]f32,
	orientation : quaternion128,
}

Collider :: union #no_nil {
	SphereCollider,
	BoxCollider
}

COLLIDER_FLAGS_INTERNAL :: ColliderFlags{._Internal_IsOverlapped, ._Internal_ForceUpdate, ._Internal_EntityDisabled}
ColliderFlags :: bit_set[ColliderFlag]
ColliderFlag :: enum u32 {
	GenerateOverlapEvents = 0,
	ReceiveOverlapEvents,
	IsStatic,

	_Internal_IsOverlapped,
	_Internal_ForceUpdate,
	_Internal_EntityDisabled,
}

ColliderOnOverlap_CallbackSignature :: #type proc(universe : ^Universe, self_comp : ^ColliderComponent, self_entity_tag : u32, other_comp : ^ColliderComponent, other_entity_tag : u32)

ColliderComponent :: struct {
	using common : ComponentCommon,
	
	flags : ColliderFlags,
	offset : [3]f32,	
	variant : Collider,

	// TODO: cache stuff respecting isStatic flag and force updates.
	// but maybe for box we want to cache obb directly??
	_world_transform : Transform,

	// Callbacks
	callback_on_overlap_begin : ColliderOnOverlap_CallbackSignature,
	callback_on_overlap_end   : ColliderOnOverlap_CallbackSignature,
	callback_on_overlap_stay  : ColliderOnOverlap_CallbackSignature,
}


@(private="package")
comp_collider_init :: proc (comp: ^ColliderComponent){
	if comp == nil {
		return;
	}

	#force_inline comp_collider_set_defaults(comp);
}

@(private="package")
comp_collider_deinit :: proc(comp: ^ColliderComponent){
	if comp == nil {
		return;
	}
}

comp_collider_set_defaults :: proc(comp : ^ColliderComponent){
	if comp == nil {
		return;
	}

	comp.offset = [3]f32{0,0,0};
	comp.flags = ColliderFlags{.GenerateOverlapEvents, .ReceiveOverlapEvents};
	comp.variant = sphere_collider_create_default();
}

// =====================================================================
// Component procedures
// =====================================================================

comp_collider_get_type :: proc(comp : ^ColliderComponent) -> ColliderType {

	switch &v in comp.variant{
		case SphereCollider: 	return ColliderType.Sphere;
		case BoxCollider: 		return ColliderType.Box;
	}

	panic("Invalid Codepath");
}

comp_collider_set_type :: proc(comp : ^ColliderComponent, type : ColliderType){

	switch type {
		case .Sphere: 	comp.variant = sphere_collider_create_default()
		case .Box: 		comp.variant = box_collider_create_default()
	}
}

comp_collider_set_flags :: proc(comp : ^ColliderComponent, flags : ColliderFlags, substract_flags : bool = false){
	flgs : ColliderFlags = flags - COLLIDER_FLAGS_INTERNAL;

	if substract_flags {
		comp.flags -= flgs;

	} else {
		comp.flags += flgs;
	}
}

// Bypasses IsStatic flag
comp_collider_force_update :: proc(comp : ^ColliderComponent){
	comp.flags += ColliderFlags{._Internal_ForceUpdate};
}

sphere_collider_create_default :: proc() -> SphereCollider {
	return SphereCollider {
		radius = 1.0,
	}
}

box_collider_create_default :: proc() -> BoxCollider {
	return BoxCollider {
		extent = {1,1,1},
		orientation = quaternion(x=0, y=0,z=0,w=1),
	}
}