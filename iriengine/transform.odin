package iri

import "core:math/linalg"

// Right Handed coordinate system
TRANSFORM_WORLD_FORWARD :	[3]f32 = {0.0, 0.0, -1.0};
TRANSFORM_WORLD_RIGHT   : 	[3]f32 = {1.0, 0.0,  0.0};
TRANSFORM_WORLD_UP      :	[3]f32 = {0.0, 1.0,  0.0};

Transform :: struct {
	position: 	[3]f32,
	scale: 		[3]f32,
	orientation: quaternion128,
}

transform_create_identity :: proc "contextless" () -> Transform {
	return Transform{
		position 	= {0.0, 0.0, 0.0},
		scale 		= {1.0, 1.0, 1.0},
		orientation = quaternion(x = 0.0, y = 0.0, z = 0.0, w = 1.0),
	}
}


get_forward :: proc "contextless" (t: Transform) -> [3]f32 {
	return linalg.quaternion128_mul_vector3(t.orientation, TRANSFORM_WORLD_FORWARD);
}

get_right :: proc "contextless" (t: Transform) -> [3]f32 {
	return linalg.quaternion128_mul_vector3(t.orientation, TRANSFORM_WORLD_RIGHT);
}

get_up :: proc "contextless" (t: Transform) -> [3]f32 {
	return linalg.quaternion128_mul_vector3(t.orientation, TRANSFORM_WORLD_UP);
}

get_forward_right :: proc "contextless" (t: Transform) -> (forward, right : [3]f32) {
	return #force_inline get_forward(t), #force_inline get_right(t);
}

get_forward_right_up :: proc "contextless" (t: Transform) -> (forward, right, up : [3]f32) {
	return #force_inline get_forward(t), #force_inline get_right(t), #force_inline get_up(t);
}


// carefull! this may fail if forward is exactly up or exactly down ...
transform_set_forward :: proc "contextless" (t: ^Transform, forward : [3]f32) {

	right := linalg.cross(TRANSFORM_WORLD_UP, forward);
	up    := linalg.cross(forward, right);

	t.orientation = linalg.quaternion_from_forward_and_up(forward,up);
}

// carefull! this may fail if forward is exactly up or exactly down ...
transfrom_get_orientation_from_forward :: proc "contextless" (forward : [3]f32) -> quaternion128 {

	right := linalg.cross(TRANSFORM_WORLD_UP, forward);
	up    := linalg.cross(forward, right);

	return linalg.quaternion_from_forward_and_up(forward,up);
}

transform_rotate_around_axis :: proc "contextless" (t: ^Transform, angle_degrees: f32, axis: [3]f32) {
	rotate_quat := linalg.quaternion_angle_axis_f32(linalg.to_radians(angle_degrees),axis);
	t.orientation = linalg.quaternion_mul_quaternion(rotate_quat,t.orientation);
}

calc_transform_matrix :: proc "contextless" (t: Transform) -> matrix[4,4]f32 {

	transation:	matrix[4,4]f32 = linalg.matrix4_translate_f32(t.position);
	rotation:	matrix[4,4]f32 = linalg.matrix4_from_quaternion_f32(t.orientation);
	scale: 		matrix[4,4]f32 = linalg.matrix4_scale_f32(t.scale);
	return transation * rotation * scale;
}

calc_view_matrix :: proc "contextless" (t: Transform) -> matrix[4,4]f32 {

	forward := #force_inline get_forward(t);
	right := #force_inline get_right(t);
	up := #force_inline get_up(t);

	return linalg.matrix4_look_at_from_fru_f32(t.position, forward, right, up, flip_z_axis = true);
}

transform_matrix_to_normal_matrix :: proc "contextless" (transform_mat: matrix[4,4]f32) -> matrix[4,4]f32 {

	return linalg.matrix4_inverse_transpose_f32(transform_mat);
}

transform_child_by_parent :: proc "contextless" (parent, child: Transform) -> Transform {

    return Transform{
    	//@Note - child positon must first be scaled by parent scale and rotated by parent orientation before adding to parent position
        position    = parent.position + linalg.quaternion128_mul_vector3(parent.orientation, child.position * parent.scale),
        scale       = parent.scale * child.scale,
        orientation = parent.orientation * child.orientation,
    };
}

