package iri

import geo "odinary:geometry"

// Right Handed coordinate system
TRANSFORM_WORLD_FORWARD :: geo.TRANSFORM_WORLD_FORWARD
TRANSFORM_WORLD_RIGHT   :: geo.TRANSFORM_WORLD_RIGHT
TRANSFORM_WORLD_UP      :: geo.TRANSFORM_WORLD_UP

Transform :: geo.Transform

transform_create_identity :: geo.transform_create_identity

get_forward 			:: geo.transform_get_forward
get_right 				:: geo.transform_get_right
get_up 					:: geo.transform_get_up
get_forward_right 		:: geo.transform_get_forward_right
get_forward_right_up 	:: geo.transform_get_forward_right_up

// carefull! this may fail if forward is exactly up or exactly down ...
transform_set_forward :: geo.transform_set_forward

// carefull! this may fail if forward is exactly up or exactly down ...
transfrom_get_orientation_from_forward :: geo.transfrom_get_orientation_from_forward

transform_rotate_around_axis :: geo.transform_rotate_around_axis

transform_calc_world_matrix :: geo.transform_calc_world_matrix
transform_calc_view_matrix  :: geo.transform_calc_view_matrix

transform_world_matrix_to_normal_matrix :: geo.transform_world_matrix_to_normal_matrix

transform_child_by_parent :: geo.transform_child_by_parent
transform_interpolate 	  :: geo.transform_interpolate
