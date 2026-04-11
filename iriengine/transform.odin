package iri

import iricom "iricommon"

// Right Handed coordinate system
TRANSFORM_WORLD_FORWARD :: iricom.TRANSFORM_WORLD_FORWARD
TRANSFORM_WORLD_RIGHT   :: iricom.TRANSFORM_WORLD_RIGHT
TRANSFORM_WORLD_UP      :: iricom.TRANSFORM_WORLD_UP

Transform :: iricom.Transform

transform_create_identity :: iricom.transform_create_identity

get_forward :: iricom.transform_get_forward
get_right 	:: iricom.transform_get_right
get_up 		:: iricom.transform_get_up
get_forward_right 		:: iricom.transform_get_forward_right
get_forward_right_up 	:: iricom.transform_get_forward_right_up


// carefull! this may fail if forward is exactly up or exactly down ...
transform_set_forward :: iricom.transform_set_forward

// carefull! this may fail if forward is exactly up or exactly down ...
transfrom_get_orientation_from_forward :: iricom.transfrom_get_orientation_from_forward

transform_rotate_around_axis :: iricom.transform_rotate_around_axis

transform_calc_world_matrix :: iricom.transform_calc_world_matrix
transform_calc_view_matrix  :: iricom.transform_calc_view_matrix

transform_world_matrix_to_normal_matrix :: iricom.transform_world_matrix_to_normal_matrix

transform_child_by_parent :: iricom.transform_child_by_parent
transform_interpolate :: iricom.transform_interpolate
