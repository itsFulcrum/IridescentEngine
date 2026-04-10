package iri 

import "core:log"
import "core:math/linalg"
import "odinary:mathy"

DebugDisplayFlags :: bit_set[DebugDisplayFlag; u32]
DebugDisplayFlag :: enum u32{
	DrawAABB,
	DrawOOBB,
	DrawLights,
	DrawCollider,
	DrawCameraFrustum,
}

DebugDrawType :: enum u32 {
	Box = 0,
	//Sphere,// drawn as 3 cricles.
	Circle, 
	Line,
}

DebugDrawCommand :: struct {
	type  : DebugDrawType,
	color : [3]f32,
	mat   : matrix[4,4]f32,
}

DebugDrawManager :: struct {
	display_flags : DebugDisplayFlags,
	is_enabled : bool,
	commands : [dynamic]DebugDrawCommand,
}

@(private="package")
debug_draw_manager_init :: proc(manager : ^DebugDrawManager){
	manager.is_enabled = true;
}

@(private="package")
debug_draw_manager_deinit :: proc(manager : ^DebugDrawManager){
	delete(manager.commands);
}

@(private="package")
debug_draw_manager_clear_commands :: proc(manager : ^DebugDrawManager){
	clear(&manager.commands);
}


@(private="package")
debug_draw_manager_push_command :: #force_inline proc(command : DebugDrawCommand){
	if engine.debug_draw_manager.is_enabled {
		append(&engine.debug_draw_manager.commands, command);
	}
}



debug_draw_manager_get_display_flags :: proc() -> DebugDisplayFlags {
	return engine.debug_draw_manager.display_flags;
}

debug_draw_manager_add_display_flags :: proc(flags : DebugDisplayFlags, remove_flags_instead : bool = false) {
	
	if remove_flags_instead{
		engine.debug_draw_manager.display_flags += flags;
	} else {
		engine.debug_draw_manager.display_flags -= flags;
	}
}

debug_draw_manager_set_display_flags :: proc(flags : DebugDisplayFlags) {
	engine.debug_draw_manager.display_flags = flags;
}

debug_draw_manager_is_enabled :: proc() -> bool {
	return engine.debug_draw_manager.is_enabled;
}

debug_draw_manager_set_enabled :: proc(enabled : bool){
	engine.debug_draw_manager.is_enabled = enabled;
}

@(private="package")
debug_draw_manager_push_universe_components :: proc(manager : ^DebugDrawManager, universe : ^Universe){

	if !manager.is_enabled {
		return;
	}

	disp_flags : DebugDisplayFlags = manager.display_flags;

	if transmute(u32)disp_flags == 0 {
		return;
	}

	ecs := &universe.ecs;

	// AABB or OOBB
	if .DrawAABB in disp_flags || .DrawOOBB in disp_flags {

		mesh_manager := engine.mesh_manager;

		for drawable_index in universe.frame_camera_visible {

            mesh_id : MeshID = ecs.drawables[drawable_index].draw_instance.mesh_id;
            aabb := mesh_manager_get_aabb(mesh_manager, mesh_id);

            if .DrawAABB in disp_flags {
            	// Note maybe can construct transform mat directly from obb stored in drawable ??
            	model_mat := aabb_transform_by_mat4_and_get_tranform_mat(aabb, ecs.drawables.world_mat[drawable_index]);
            	debug_draw_box(DebugColor.Black,  model_mat);
            }

            if .DrawOOBB in disp_flags {
            	model_mat := ecs.drawables.world_mat[drawable_index] * aabb_get_transform_matrix(aabb)
				debug_draw_box(DebugColor.Blue,  model_mat);
            }
        }
	}

	if .DrawCollider in disp_flags {

        for &collider_comp in ecs.collider_components {

        	if ColliderFlags._Internal_EntityDisabled in collider_comp.flags {
        		continue;
        	}

            switch &var in collider_comp.variant {
                case SphereCollider: {
                    debug_draw_sphere(DebugColor.Green, collider_comp._world_transform.position, collider_comp._world_transform.scale.x)
                }
                case BoxCollider: {
                    debug_draw_box(DebugColor.Green, collider_comp._world_transform)
                }
            }
        }
	}

	if .DrawCameraFrustum in disp_flags {

		frame_size := get_frame_size();
		frame_aspect_ratio : f32 = cast(f32)frame_size.x / cast(f32)frame_size.y;

		for &cam_comp in ecs.camera_components {
			
			if cam_comp.entity == ecs.active_camera_entity {
				continue;
			}

			if !ecs_entity_is_enabled(ecs,cam_comp.entity){
        		continue;
        	}

			// using the inv_view_proj matrix of the camera we can 
			// transform a unit cubeinto world space which will represent its frustum.
			transform_comp := ecs_get_transform(ecs, cam_comp.entity);
			view_mat := transform_calc_view_matrix(transform_comp);
			proj_mat := comp_camera_get_projection_matrix(&cam_comp, frame_aspect_ratio);
			model_mat := linalg.matrix4_inverse(proj_mat * view_mat, );
			debug_draw_box(DebugColor.White, model_mat);
		}
	}

	if .DrawLights in disp_flags {

		// Draw lights as solid meshes..
        light_manager := &universe.light_manager;
		dbg_color := DebugColor.Yellow;

        for &light_comp, comp_index in ecs.light_components {

        	if !ecs_entity_is_enabled(ecs, light_comp.entity){
        		continue;
        	}

            transform_comp := ecs_get_transform(ecs, light_comp.entity);

            switch &var in light_comp.variant {
            	case DirectionalLightVariant: {
            		debug_draw_sphere(dbg_color, transform_comp.position, 0.15, transform_comp.orientation);
            		forward := get_forward(transform_comp);
            		debug_draw_ray(dbg_color, transform_comp.position, forward, 6.0);
            	}
            	case PointLightVariant: {
            		debug_draw_sphere(dbg_color, transform_comp.position, 0.15, transform_comp.orientation);
            	}
            	case SpotLightVariant: {

            		light_pos := transform_comp.position;

            		debug_draw_sphere(dbg_color, light_pos, 0.15, transform_comp.orientation);
            		forward, right, up := get_forward_right_up(transform_comp);
            		debug_draw_ray(dbg_color, light_pos, forward, 6.0);

            		inner_radians : f32 = linalg.to_radians(var.inner_cone_angle_deg)
            		outer_radians : f32 = linalg.to_radians(var.outer_cone_angle_deg)

            		s : f32 = linalg.sin(outer_radians);
            		c : f32 = linalg.cos(outer_radians);            		
            		fc := forward * c;
            		rs := right * s;
            		us := up * s;

            		circ_dist : f32 = 3.0;
            		circ_pos : [3]f32 = light_pos + forward * circ_dist;

            		circ_outer_radius : f32 = circ_dist * linalg.tan(outer_radians);
            		circ_inner_radius : f32 = circ_dist * linalg.tan(inner_radians);

            		outer_ray_length  : f32 = circ_outer_radius / linalg.sin(outer_radians)

            		debug_draw_ray(dbg_color, light_pos, fc + rs, outer_ray_length);
            		debug_draw_ray(dbg_color, light_pos, fc - rs, outer_ray_length);
            		debug_draw_ray(dbg_color, light_pos, fc + us, outer_ray_length);
            		debug_draw_ray(dbg_color, light_pos, fc - us, outer_ray_length);

            		debug_draw_circle(dbg_color, circ_pos, circ_outer_radius, forward);
            		debug_draw_circle(dbg_color, circ_pos, circ_inner_radius, forward);
            	}
            }
        }
	}

}