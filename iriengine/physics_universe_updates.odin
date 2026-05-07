package iri

import "core:log"
import "core:math/linalg"
import "core:sort"
import geo "odinary:geometry"

CollisionPair :: struct {
	ent_a : Entity,
	ent_b : Entity,
}

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

// @Note: this should run in physics update BEFORE any physics intergration happens, we copy transforms of the current state and store them 
// such that when rendering we can interpolate between last and current physics states for smoooothnes.
@(private="package")
physics_universe_update_previous_transform_state :: proc(manager : ^CollisionManager, universe : ^Universe, timestep : f32){

	ecs := &universe.ecs;

	{
		// Copy current transform state for all components that may need interpolation for rendering frames.
		ents : []Entity = ecs_gather_entities_with_component(ecs, {.MeshRenderer, .Camera, .Light}, {}, include_disabled = false, allocator = context.temp_allocator);

		for ent in ents {
			universe.ecs.previous_physics_transforms[ent.id] = ecs.transform_components[ent.id].transform;
		}
	}


	drawables : ^#soa[dynamic]Drawable = &ecs.drawables;

	for index in 0..<len(drawables) {
		
		entity := drawables.entity[index];
		ent_flags := ecs.entity_infos.flags[entity.id];
		engine_assert(._Internal_Exists in ent_flags);

		draw_flags := drawables.draw_instance[index].flags;

		// @Note: force update may not reach this procedure which mean we may skip
		// all statics here but it should be okey since we update force updates also in normal frame update
		
		if ._Internal_IsEnabled not_in ent_flags && ._Internal_ForceUpdate not_in ent_flags {
			continue;
		}

		if .IsStatic in draw_flags && ._Internal_ForceUpdate not_in ent_flags {
			continue;
		}

		ecs.drawables[index].prev_physics_world_transform = transform_child_by_parent(ecs.previous_physics_transforms[entity.id], drawables.draw_instance[index].transform)
	}
}


// Collision detection and boradcast overlap callback events
@(private="package")
physics_universe_update :: proc(manager : ^CollisionManager, universe : ^Universe, timestep : f32){
	
	if universe == nil {
		return
	}

	ecs := &universe.ecs;

	// Update collider primitives
	for &comp in ecs.collider_components {

		if ecs_entity_is_enabled(ecs, comp.entity){
			comp.flags -= ColliderFlags{._Internal_EntityDisabled}
		} else {
			comp.flags += ColliderFlags{._Internal_EntityDisabled}
			continue;
		}

		ent_flags := ecs.entity_infos.flags[comp.entity.id];

		if .IsStatic in comp.flags && ._Internal_ForceUpdate not_in ent_flags {
			continue;
		}
		
		comp_collider_recompute_collider_primitve(&comp);
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
			

			if collider_overlaps_collider(r_comp.variant, g_comp.variant){

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


collider_overlaps_collider :: proc(a_col: Collider, b_col : Collider) -> bool {

	switch &a_var in a_col {
		case SphereCollider: {

			switch &b_var in b_col {
				case SphereCollider: return #force_inline collider_sphere_overlaps_sphere(a_var, b_var);
				case BoxCollider:	 return #force_inline collider_sphere_overlaps_box(a_var, b_var);
			}
		}
		case BoxCollider: {
			switch &b_var in b_col {
				case SphereCollider: return #force_inline collider_sphere_overlaps_box(b_var, a_var);
				case BoxCollider:	 return #force_inline collider_box_overlaps_box(a_var, b_var);
			}
		}
	}

	return false;
}


collider_sphere_overlaps_sphere :: #force_inline proc "contextless" (a : SphereCollider, b : SphereCollider) -> bool {
	return linalg.distance(a.world_position, b.world_position) <= (a.world_radius + b.world_radius);
}

collider_sphere_overlaps_box :: #force_inline proc "contextless" (sphere : SphereCollider, box : BoxCollider) -> bool {
	return geo.obb_overlaps_sphere(box.world_obb, sphere.world_position, sphere.world_radius)
}

collider_box_overlaps_sphere :: #force_inline proc "contextless" (box : BoxCollider, sphere : SphereCollider) -> bool {
	return geo.obb_overlaps_sphere(box.world_obb, sphere.world_position, sphere.world_radius)
}


collider_box_overlaps_box :: #force_inline proc "contextless" (a : BoxCollider, b : BoxCollider) -> bool {
	return geo.obb_overlaps_obb(a.world_obb, b.world_obb);
}

