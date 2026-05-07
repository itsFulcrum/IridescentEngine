package iri

import geo "odinary:geometry"
import iria "iriasset"
import "core:math/linalg"

ColliderType :: enum u8 {
	Sphere,
	Box,
}

// Collider Variants store world space transformed collider primitves!
SphereCollider :: struct {
	world_position : [3]f32,
	world_radius : f32,
}

BoxCollider :: struct {
	world_obb : geo.OBB,
}

Collider :: union #no_nil {
	SphereCollider,
	BoxCollider
}

// COLLIDER_FLAGS_INTERNAL :: ColliderFlags{._Internal_ForceUpdate, ._Internal_EntityDisabled}
COLLIDER_FLAGS_INTERNAL :: ColliderFlags{}
ColliderFlags :: bit_set[ColliderFlag; u32]
ColliderFlag :: enum u32 {
	GenerateOverlapEvents = 0,
	ReceiveOverlapEvents,
	IsStatic,

	_Internal_EntityDisabled,
}

ColliderOnOverlap_CallbackSignature :: #type proc(universe : ^Universe, self_comp : ^ColliderComponent, self_entity_tag : u32, other_comp : ^ColliderComponent, other_entity_tag : u32)

ColliderComponent :: struct {
	using common : ComponentCommon,
	
	flags : ColliderFlags,
	offset : [3]f32,	
	extent : [3]f32,			 // .yz ignored for sphere
	orientation : quaternion128, // ignored for sphere

	variant : Collider,

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

	comp.flags = ColliderFlags{.GenerateOverlapEvents, .ReceiveOverlapEvents};
	comp.variant = SphereCollider{}; // sphere_collider_create_default();
	
	comp.offset = [3]f32{0,0,0};
	comp.extent = [3]f32{1,1,1};
	comp.orientation = linalg.QUATERNIONF32_IDENTITY;
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
		case .Sphere: {
			comp.variant = SphereCollider{};
		}
		case .Box:{
			comp.variant = BoxCollider{}
		} 		
	}

	comp_collider_recompute_collider_primitve(comp);
}

comp_collider_set_flags :: proc(comp : ^ColliderComponent, flags : ColliderFlags, substract_flags : bool = false){
	flgs : ColliderFlags = flags - COLLIDER_FLAGS_INTERNAL;

	if substract_flags {
		comp.flags -= flgs;

	} else {
		comp.flags += flgs;
	}
}

// Assumes Collider is of type sphere
comp_collider_set_radius :: proc(comp : ^ColliderComponent, radius : f32){
	comp.extent = [3]f32{radius, radius, radius};
}

// Assumes Collider is of type sphere
comp_collider_get_radius :: proc(comp : ^ColliderComponent) -> f32 {
	return comp.extent.x;
}

// Bypasses IsStatic flag
// comp_collider_force_update :: proc(comp : ^ColliderComponent){
// 	//comp.flags += ColliderFlags{._Internal_ForceUpdate};
// }


comp_collider_recompute_collider_primitve :: proc(comp : ^ColliderComponent) {
	
	ent_trans := ecs_get_transform(comp.parent_ecs, comp.entity);

	switch &v in comp.variant{
		case SphereCollider: {
			v.world_position = ent_trans.position + linalg.quaternion128_mul_vector3(ent_trans.orientation, comp.offset * ent_trans.scale);
			v.world_radius = comp.extent.x * max(max(ent_trans.scale.x, ent_trans.scale.y), ent_trans.scale.z);
		}
		case BoxCollider: 	{
			world_transform := Transform {
				position 	= ent_trans.position + linalg.quaternion128_mul_vector3(ent_trans.orientation, comp.offset * ent_trans.scale),
				scale 		= ent_trans.scale * comp.extent,
				orientation = linalg.quaternion_mul_quaternion(ent_trans.orientation,comp.orientation),
			}
			v.world_obb = geo.obb_from_world_transform(world_transform);
		}
	}
}


comp_collider_init_from_comp_data :: proc(comp : ^ColliderComponent, comp_data : iria.ColliderCompData){

	comp.flags = transmute(ColliderFlags)comp_data.flags;
	comp.offset = comp_data.offset;
	comp.extent = comp_data.extent;
	comp.orientation = comp_data.orientation;

	type : ColliderType = cast(ColliderType)cast(u8)comp_data.type;
	comp_collider_set_type(comp, type); // This will also recompute the collider primitve.
} 

comp_collider_create_collider_comp_data :: proc(comp : ^ColliderComponent) -> iria.ColliderCompData {
	flags : ColliderFlags = comp.flags - COLLIDER_FLAGS_INTERNAL;

	return iria.ColliderCompData{
		type  		= cast(u32)comp_collider_get_type(comp),
		flags 		= transmute(u32)flags,
		offset 		= comp.offset,
		extent 		= comp.extent,
		orientation = comp.orientation,
	}
}