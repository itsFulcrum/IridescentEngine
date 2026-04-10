package iri

import "core:log"
import "core:math/linalg"
import "core:sort"



CollisionPair :: struct {
	ent_a : Entity,
	ent_b : Entity,
}

// TOOD: clear both on universe swithes!!
CollisionManager :: struct {
	pairs_buf_a : [dynamic]CollisionPair,
	pairs_buf_b : [dynamic]CollisionPair,

	// ping pong buffers
	curr_pairs : ^[dynamic]CollisionPair,
	prev_pairs : ^[dynamic]CollisionPair,
}

collision_manager_init :: proc(manager : ^CollisionManager){
	manager.curr_pairs = &manager.pairs_buf_a;
	manager.prev_pairs = &manager.pairs_buf_b;
}

collision_manager_deinit :: proc(manager : ^CollisionManager){

	delete(manager.pairs_buf_a)
	delete(manager.pairs_buf_b)

	manager.curr_pairs = nil;
	manager.prev_pairs = nil;
}

collision_manager_reset :: proc(manager : ^CollisionManager){
	clear(&manager.pairs_buf_a);
	clear(&manager.pairs_buf_b);
}

@(private="package")
physics_universe_update :: proc(manager : ^CollisionManager, universe : ^Universe, timestep : f32){
	
	if universe == nil {
		return
	}

	ecs := &universe.ecs;

	// produce and cache world transform
	for &comp in ecs.collider_components {
		
		if ecs_entity_is_enabled(ecs, comp.entity){
			comp.flags -= ColliderFlags{._Internal_EntityDisabled}
		} else {
			comp.flags += ColliderFlags{._Internal_EntityDisabled}
			continue;
		}

		// dont write to this
		ent_trans := ecs_get_transform(ecs, comp.entity);

		switch &var in comp.variant {
			case SphereCollider: {
				comp._world_transform.position = ent_trans.position + linalg.quaternion128_mul_vector3(ent_trans.orientation, comp.offset * ent_trans.scale);
				radi : f32 = var.radius * max(max(ent_trans.scale.x, ent_trans.scale.y), ent_trans.scale.z);
				comp._world_transform.scale = [3]f32{radi,radi,radi};
				// no need orientation for sphere
			}
			case BoxCollider: {
				comp._world_transform = Transform {
					position 	= ent_trans.position + linalg.quaternion128_mul_vector3(ent_trans.orientation, comp.offset * ent_trans.scale),
					scale 		= ent_trans.scale * var.extent,
					orientation = ent_trans.orientation * var.orientation,
				}
			}
		}
	}

	// For loooop go brrrrr

	clear(manager.curr_pairs);

	r_loop: for r := 0; r < len(ecs.collider_components); r += 1 {
		
		r_comp := &ecs.collider_components[r];

		if ._Internal_EntityDisabled in r_comp.flags {
			continue r_loop;
		}

		g_loop: for g := r+1; g < len(ecs.collider_components); g += 1 {
			
			g_comp := &ecs.collider_components[g];
			
			if ._Internal_EntityDisabled in g_comp.flags {
				continue g_loop;
			}
			

			if colliders_overlap(r_comp.variant, r_comp._world_transform, g_comp.variant, g_comp._world_transform){

				r_smaller_g : bool = r_comp.entity.id < g_comp.entity.id;
				pair := CollisionPair {
					ent_a = r_smaller_g ? r_comp.entity : g_comp.entity,
					ent_b = r_smaller_g ? g_comp.entity : r_comp.entity,
				}
				append(manager.curr_pairs, pair);
			}
		} 
	}

	sort_compare_proc :: proc (a : CollisionPair, b : CollisionPair) -> int {

		if a.ent_a.id < b.ent_a.id do return -1;
	    if a.ent_a.id > b.ent_a.id do return  1;

	    if a.ent_b.id < b.ent_b.id do return -1;
	    if a.ent_b.id > b.ent_b.id do return  1;

	    return 0;
	}

	sort.quick_sort_proc(manager.curr_pairs[:], sort_compare_proc);

	// merge walk
	{
		i : int = 0
		j : int = 0

		current  := manager.curr_pairs;
		previous := manager.prev_pairs;

		for i < len(current) || j < len(previous){

		    if i >= len(current) {
		    	// remaining previous pairs means no longer overlapping
		        fire_overlap_event(.End, universe, previous[j])
		        j += 1;
		        continue;
		    }

		    if j >= len(previous) {
		        // remaining current pairs means pair started to overlap
		        fire_overlap_event(.Begin,universe, current[i])
		        i+=1;
		        continue;
		    }

		    curr_pair := current[i]
		    prev_pair := previous[j]

		    compare_val : int = #force_inline sort_compare_proc(curr_pair, prev_pair);
		    if compare_val == 0 { // equal
				fire_overlap_event(.Stay,universe,  curr_pair)
		        i += 1;
		        j += 1;
		    } else if compare_val < 0 { // curr < prev

		        fire_overlap_event(.Begin, universe, curr_pair)
		        i+=1;
		    }  else {
		        fire_overlap_event(.End, universe, prev_pair)
		        j+=1;
		    }
		}
	}

	// swap curr/previous
	{
		tmp := manager.prev_pairs;
		manager.prev_pairs = manager.curr_pairs;
		manager.curr_pairs = tmp;	
	}

	OverlapState :: enum {
		Begin,
		Stay,
		End
	}

	fire_overlap_event :: proc(state : OverlapState, uni : ^Universe, pair : CollisionPair) {

		a_comp , e1 := ecs_get_component(&uni.ecs, pair.ent_a, ColliderComponent);
		b_comp , e2 := ecs_get_component(&uni.ecs, pair.ent_b, ColliderComponent);

		if a_comp == nil || b_comp == nil {
			return;
		}

		a_tag, err1 := ecs_entity_get_tag(&uni.ecs, pair.ent_a);
		b_tag, err2 := ecs_entity_get_tag(&uni.ecs, pair.ent_b);
		
		if .ReceiveOverlapEvents in a_comp.flags && .GenerateOverlapEvents in b_comp.flags {

			cb_proc : ColliderOnOverlap_CallbackSignature = nil;
			switch state {
				case .Begin: cb_proc = a_comp.callback_on_overlap_begin
				case .Stay:  cb_proc = a_comp.callback_on_overlap_stay
				case .End:   cb_proc = a_comp.callback_on_overlap_end
			}

			if cb_proc != nil {
				cb_proc(uni, a_comp, a_tag, b_comp, b_tag);
			}
		}

		if .ReceiveOverlapEvents in b_comp.flags && .GenerateOverlapEvents in a_comp.flags {
			cb_proc : ColliderOnOverlap_CallbackSignature = nil;
			switch state {
				case .Begin: cb_proc = b_comp.callback_on_overlap_begin
				case .Stay:  cb_proc = b_comp.callback_on_overlap_stay
				case .End:   cb_proc = b_comp.callback_on_overlap_end

			}

			if cb_proc != nil {
				cb_proc(uni, b_comp, b_tag, a_comp, a_tag);
			}
		}
	}
}


colliders_overlap :: proc(a_col: Collider, a_transform : Transform, b_col : Collider, b_transform : Transform) -> bool {

	switch &a_var in a_col {
		case SphereCollider: {

			switch &b_var in b_col {
				case SphereCollider:{
					return collider_test_sphere_vs_sphere(a_transform.position, a_transform.scale.x, b_transform.position, b_transform.scale.x);
				}
				case BoxCollider: {
					return collider_test_sphere_vs_box(a_var, a_transform.position, a_transform.scale.x, b_var, b_transform);
				}
			}
		}
		case BoxCollider: {
			switch &b_var in b_col {
				case SphereCollider:{
					return collider_test_sphere_vs_box(b_var, b_transform.position, b_transform.scale.x, a_var, a_transform);
				}
				case BoxCollider: {
					return collider_test_box_vs_box(a_var, a_transform, b_var, b_transform);
				}
			}
		}
	}

	return false;
}

collider_test_sphere_vs_sphere :: #force_inline proc "contextless" (a_pos : [3]f32, a_radius : f32, b_pos : [3]f32, b_radius : f32) -> bool {
	return linalg.distance(a_pos, b_pos) <= (a_radius + b_radius);
}

collider_test_sphere_vs_box :: proc(a_col : SphereCollider, sphere_pos : [3]f32, sphere_radius : f32, box_col : BoxCollider, box_transform : Transform) -> bool{
	
	obb : OBB = obb_from_transform(box_transform);
	return obb_overlaps_sphere(obb, sphere_pos, sphere_radius)
}

collider_test_box_vs_box :: proc(a_col : BoxCollider, a_transform : Transform, b_col : BoxCollider, b_transform : Transform) -> bool {
	obb_a : OBB = obb_from_transform(a_transform);
	obb_b : OBB = obb_from_transform(b_transform);
	
	// TODO: optimize..
	return obb_overlaps_obb(obb_a, obb_b);
}

