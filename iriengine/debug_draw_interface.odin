package iri 

import "core:math/linalg"
import "odinary:mathy"
import geo "odinary:geometry"

DebugDrawColor :: union #no_nil {
	DebugColor,
	[3]f32,
	[3]u8,
}

DebugColor :: enum {
	Black = 0,
	White,
	Gray,
	Red,
	Green,
	Blue,
	Yellow,
	Magenta,
	Cyan
}

// BOX
debug_draw_box :: proc {
	debug_draw_box_mat4,
	debug_draw_box_transform,
	debug_draw_box_obb,
}

debug_draw_box_mat4 :: proc(color : DebugDrawColor, mat : matrix[4,4]f32) {
	command := DebugDrawCommand{
		type  = DebugDrawType.Box,
		color = debug_draw_color_to_f32(color),
		mat   = mat,
	}
	debug_draw_manager_push_command(command);
}

debug_draw_box_transform :: proc(color : DebugDrawColor, trans : Transform) {
	command := DebugDrawCommand{
		type  = DebugDrawType.Box,
		color = debug_draw_color_to_f32(color),
		mat   = transform_calc_world_matrix(trans),
	}
	debug_draw_manager_push_command(command);
}

debug_draw_box_obb :: proc(color : DebugDrawColor, obb : geo.OBB) {
	command := DebugDrawCommand {
		type  = DebugDrawType.Box,
		color = debug_draw_color_to_f32(color),
		mat   = geo.obb_to_transform_matrix(obb),
	}
	debug_draw_manager_push_command(command);
}

// CIRCLE
debug_draw_circle :: proc {
	debug_draw_circle_pos_radius_up,
	debug_draw_circle_transform,
}

debug_draw_circle_pos_radius_up :: proc(color : DebugDrawColor, pos : [3]f32, radius : f32, up : [3]f32) {
	
	trans := Transform {
		position = pos,
		scale    = radius,
		orientation = linalg.quaternion_from_forward_and_up(mathy.any_perpendicular(up), up),
	}

	command := DebugDrawCommand {
		type  = DebugDrawType.Circle,
		color = debug_draw_color_to_f32(color),
		mat   = transform_calc_world_matrix(trans),
	}
	debug_draw_manager_push_command(command);
}

debug_draw_circle_transform :: proc(color : DebugDrawColor, trans : Transform) {
	command := DebugDrawCommand {
		type  = DebugDrawType.Circle,
		color = debug_draw_color_to_f32(color),
		mat   = transform_calc_world_matrix(trans),
	}
	debug_draw_manager_push_command(command);
}

// SPHERE
debug_draw_sphere :: proc {
	debug_draw_sphere_pos_radius,
	debug_draw_sphere_pos_radius_orientation
}

debug_draw_sphere_pos_radius :: proc(color : DebugDrawColor, pos : [3]f32, radius : f32) {
	debug_draw_circle(color, pos, radius, TRANSFORM_WORLD_UP);
	debug_draw_circle(color, pos, radius, TRANSFORM_WORLD_RIGHT);
	debug_draw_circle(color, pos, radius, TRANSFORM_WORLD_FORWARD);
}

debug_draw_sphere_pos_radius_orientation :: proc(color : DebugDrawColor, pos : [3]f32, radius : f32, orientation : quaternion128) {
	debug_draw_circle(color, pos, radius, linalg.quaternion128_mul_vector3(orientation,TRANSFORM_WORLD_UP     ));
	debug_draw_circle(color, pos, radius, linalg.quaternion128_mul_vector3(orientation,TRANSFORM_WORLD_RIGHT  ));
	debug_draw_circle(color, pos, radius, linalg.quaternion128_mul_vector3(orientation,TRANSFORM_WORLD_FORWARD));
}

// LINE
debug_draw_line :: proc(color : DebugDrawColor, pos_a: [3]f32, pos_b : [3]f32){
	manager := engine.debug_draw_manager;

	clr := debug_draw_color_to_f32(color);

	// @Note this seems to be broken!
	// last_command : int = len(manager.commands)-1;
	// // We can draw 2 lines at once so we attempt to inline batch if we can
	// // When last command was line too and color matches we attemt to write a second line at the same time.
	// if last_command >= 0 {
	// 	cmd := &manager.commands[last_command];
	// 	if cmd.type == .Line && cmd.color == clr {
	// 		if cmd.mat[3][3] < 3 {

	// 			cmd.mat[2].xyz = pos_a.z;
	// 			cmd.mat[3].xyz = pos_b.z;	
	// 			cmd.mat[3][3] = 4; // <- writ enum of vertecies here.
	// 			return;
	// 		}
	// 	}
	// }
	command := DebugDrawCommand {
		type  = DebugDrawType.Line,
		color = clr,
		mat   = matrix[4,4]f32{
			pos_a.x,pos_b.x,0,0,
			pos_a.y,pos_b.y,0,0,
			pos_a.z,pos_b.z,0,0,
			0      , 0     ,0,2, // <- we write the num of vertecies here
		},
	};
	debug_draw_manager_push_command(command);
}

debug_draw_ray :: proc(color : DebugDrawColor, origin: [3]f32, direction : [3]f32, length : f32 = 1.0){
	pos_b := origin + direction * length;
	debug_draw_line(color, origin, pos_b);
}

debug_draw_color_to_f32 :: #force_inline proc(color : DebugDrawColor) -> [3]f32 {

	switch var in color {
		case DebugColor:{
			switch var {
				case .Black  :return [3]f32{0.0, 0.0, 0.0};
				case .White  :return [3]f32{1.0, 1.0, 1.0};
				case .Gray   :return [3]f32{0.5, 0.5, 0.5};
				case .Red    :return [3]f32{1.0, 0.0, 0.0};
				case .Green  :return [3]f32{0.0, 1.0, 0.0};
				case .Blue   :return [3]f32{0.0, 0.0, 1.0};
				case .Yellow :return [3]f32{1.0, 1.0, 0.0};
				case .Magenta:return [3]f32{1.0, 0.0, 1.0};
				case .Cyan   :return [3]f32{0.0, 1.0, 1.0};			
			}
		}
		case [3]f32: return var;
		case [3]u8:  return [3]f32{cast(f32)var.r,cast(f32)var.g,cast(f32)var.b} / 256.0;
	}

	return [3]f32{0,0,0};
}