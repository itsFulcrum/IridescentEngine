package iri

import "core:math/linalg"
import "core:simd"
import "base:intrinsics"
import "odinary:mathy/simdy"

OBB :: struct {
	center  : [4]f32,
	extents : [4]f32,
	axis : [3][4]f32, // Orthonormal axis as normalized vectors.
}


obb_from_world_transform :: proc "contextless" (t : Transform) -> OBB #no_bounds_check {
	obb : OBB 
	obb.center.xyz  = t.position;
	obb.center.w    = 1;
	obb.extents.xyz = t.scale;
	obb.axis[0].xyz = get_right(t);
	obb.axis[1].xyz = get_up(t);
	obb.axis[2].xyz = get_forward(t);
	return obb;
}

obb_from_aabb_and_transform :: proc "contextless" (aabb : AABB, to_world : Transform) -> OBB #no_bounds_check {

    corner_0 : [3]f32 = to_world.position + linalg.quaternion128_mul_vector3(to_world.orientation, to_world.scale * [3]f32{aabb.min.x, aabb.min.y, aabb.min.z});
    corner_1 : [3]f32 = to_world.position + linalg.quaternion128_mul_vector3(to_world.orientation, to_world.scale * [3]f32{aabb.max.x, aabb.min.y, aabb.min.z});
    corner_2 : [3]f32 = to_world.position + linalg.quaternion128_mul_vector3(to_world.orientation, to_world.scale * [3]f32{aabb.min.x, aabb.max.y, aabb.min.z});
    corner_3 : [3]f32 = to_world.position + linalg.quaternion128_mul_vector3(to_world.orientation, to_world.scale * [3]f32{aabb.min.x, aabb.min.y, aabb.max.z});

    oobb : OBB;

    oobb.axis[0].xyz = corner_1 - corner_0;
    oobb.axis[1].xyz = corner_2 - corner_0;
    oobb.axis[2].xyz = corner_3 - corner_0;

    oobb.center.xyz = corner_0 + [3]f32{0.5,0.5,0.5} * (oobb.axis[0].xyz + oobb.axis[1].xyz + oobb.axis[2].xyz);
    oobb.center.w   = 1.0;

    oobb.extents = [4]f32{linalg.length(oobb.axis[0].xyz), linalg.length(oobb.axis[1].xyz), linalg.length(oobb.axis[2].xyz), 0.0};
    
    // normalize axis
    oobb.axis[0] /= oobb.extents.x
    oobb.axis[1] /= oobb.extents.y
    oobb.axis[2] /= oobb.extents.z
    // make .w = 0 since they are direction, so we can transform them with any other matrix
    oobb.axis[0].w = 0.0;
    oobb.axis[1].w = 0.0;
    oobb.axis[2].w = 0.0;

    // extent should be half the lenght of each side
   oobb.extents.xyz *= 0.5;

   return oobb;
}

obb_to_transform_matrix :: proc "contextless" (obb : OBB) -> matrix[4,4]f32 {

	mat := matrix[4,4]f32 {
		1, 0, 0, obb.center.x,
		0, 1, 0, obb.center.y,
		0, 0, 1, obb.center.z,
		0, 0, 0, 1
	};

	mat[0].xyz = obb.axis[0].xyz * obb.extents.x;
	mat[1].xyz = obb.axis[1].xyz * obb.extents.y;
	mat[2].xyz = obb.axis[2].xyz * obb.extents.z;
	return mat;
}



// from: https://web.archive.org/web/19991129035017/http://www.gamasutra.com/features/19991018/Gomez_5.htm
obb_overlaps_obb :: proc "contextless" (a, b : OBB) -> bool #no_bounds_check {
	// @Speed. maybe simdfy but should test perf on this because
	// it may actually be slower since we will need to do a bunch of
	// swizlles and jump between simd and normal registers.

	//translation, in parent frame
	v : [3]f32 = (b.center - a.center).xyz;

	//translation, in A's frame
	T := [3]f32{ linalg.dot(v, a.axis[0].xyz), linalg.dot(v,a.axis[1].xyz), linalg.dot(v,a.axis[2].xyz)}


	//B's basis with respect to A's local frame
	R : [3][3]f32 = ---;
	
	//calculate rotation matrix
	for i:=0 ; i<3 ; i+=1 {
		for k:=0 ; k<3 ; k+=1 {
			R[i][k] = linalg.dot(a.axis[i].xyz, b.axis[k].xyz);
		}
	}

	ra, rb, t : f32;

	/*ALGORITHM: Use the separating axis test for all 15 potential
	separating axes. If a separating axis could not be found, the two
	boxes overlap. */

	//A's basis vectors
	for i := 0 ; i < 3 ; i+=1 {
		ra = a.extents[i];
		rb = linalg.dot(b.extents.xyz, linalg.abs(R[i]));

		t = abs(T[i]);
		
		if t > ra + rb {
			return false;
		}
	}

	//B's basis vectors
	for k:=0 ; k<3 ; k+=1 {

		ra = a.extents.x * abs(R[0][k]) + a.extents.y * abs(R[1][k]) + a.extents.z * abs(R[2][k]);
		rb = b.extents[k];

		t = abs( T.x * R[0][k] + T.y * R[1][k] + T.z * R[2][k] );

		if t > ra + rb {
			return false;
		}
	}

	//9 cross products ?? where ?

	// @Note: fulcrum most of these are dot product that we could do simd. 
	// if we use a masked simd dot product this could be super fast...

	//L = A0 x B0
	ra = a.extents.y * abs(R[2][0]) + a.extents.z * abs(R[1][0]);
	rb = b.extents.y * abs(R[0][2]) + b.extents.z * abs(R[0][1]);

	t =	abs( T.z * R[1][0] - T.y * R[2][0] );

	if t > ra + rb {
		return false;
	}


	//L = A0 x B1
	ra = a.extents.y * abs(R[2][1]) + a.extents.z * abs(R[1][1]);
	rb = linalg.dot(b.extents.xz, linalg.abs(R[0].zx));

	t =	abs( T.z * R[1][1] - T.y * R[2][1] );

	if t > ra + rb {
		return false;
	}

	//L = A0 x B2
	ra = a.extents[1]*abs(R[2][2]) + a.extents[2]*abs(R[1][2]);
	rb = linalg.dot(b.extents.xy , linalg.abs(R[0].xy));

	t =	abs( T[2]*R[1][2] -	T[1]*R[2][2] );

	if t > ra + rb {
		return false;
	}

	//L = A1 x B0
	ra = a.extents[0]*abs(R[2][0]) + a.extents.z*abs(R[0][0]);
	rb = b.extents[1]*abs(R[1][2]) + b.extents.z*abs(R[1][1]);

	t =	abs( T[0]*R[2][0] - T[2]*R[0][0] );

	if t > ra + rb {
		return false;
	} 

	//L = A1 x B1
	ra = a.extents.x*abs(R[2][1]) + a.extents.z*abs(R[0][1]);
	rb = b.extents.x*abs(R[1][2]) + b.extents.z*abs(R[1][0]);

	t =	abs( T[0]*R[2][1] - T[2]*R[0][1] );

	if t > ra + rb {
		return false;
	}

	//L = A1 x B2
	ra = a.extents[0]*abs(R[2][2]) + a.extents[2]*abs(R[0][2]);
	rb = b.extents[0]*abs(R[1][1]) + b.extents[1]*abs(R[1][0]);

	t =	abs( T[0]*R[2][2] - T[2]*R[0][2] );

	if t > ra + rb {
		return false;
	}

	//L = A2 x B0
	ra = a.extents.y*abs(R[1][0]) + a.extents.z*abs(R[0][0]);
	rb = b.extents.z*abs(R[2][2]) + b.extents.z*abs(R[2][1]);

	t =	abs( T.y*R[0][0] - T.x*R[1][0] );

	if t > ra + rb {
		return false;
	}

	//L = A2 x B1
	ra = a.extents.x*abs(R[1][1]) + a.extents.y*abs(R[0][1]);
	rb = b.extents.x*abs(R[2][2]) + b.extents.z*abs(R[2][0]);

	t =	abs( T[1]*R[0][1] - T[0]*R[1][1] );

	if t > ra + rb {
		return false;
	}

	//L = A2 x B2
	ra = a.extents.x*abs(R[1][2]) + a.extents.y*abs(R[0][2]);
	rb = b.extents.x*abs(R[2][1]) + b.extents.y*abs(R[2][0]);

	t =	abs( T[1]*R[0][2] - T[0]*R[1][2] );

	if t > ra + rb {
		return false;
	}

	/*no separating axis found,
	the two boxes overlap */

	return true;
}

obb_closest_point :: proc "contextless" (obb : OBB, point : [3]f32) -> [3]f32 #no_bounds_check {
	result : [3]f32 = obb.center.xyz;

	dir : [3]f32 = point - obb.center.xyz;

	for  i := 0; i < 3; i+=1 {

		axis : [3]f32 = obb.axis[i].xyz;
		distance : f32 = linalg.dot(dir, obb.axis[i].xyz);

		if distance > obb.extents[i] {
			distance = obb.extents[i];
		}
		
		if distance < -obb.extents[i] {
			distance = -obb.extents[i];
		}

		result += axis * distance;
	}

	return result.xyz;
}

obb_closest_point_simd :: proc "contextless" (obb : OBB, point : #simd[4]f32) -> #simd[4]f32 #no_bounds_check {
	
	_result : #simd[4]f32 = simd.from_array(obb.center);
	_dir    : #simd[4]f32 = simd.sub(point, _result)
	// Force last lane to 0 for use with dot_unsafe()
	_dir = simd.replace(_dir, 3, 0.0);

	for  i := 0; i < 3; i+=1 {

		_axis : #simd[4]f32 = simd.from_array(obb.axis[i]);

		distance : f32 = simdy.dot_unsafe(_dir, _axis);

		if distance > obb.extents[i] {
			distance = obb.extents[i];
		}
		
		if distance < -obb.extents[i] {
			distance = -obb.extents[i];
		}

		_result = simd.fused_mul_add(_axis, simdy.from_scalar(distance), _result)
	}

	_result = simd.replace(_result, 3, 0.0);
	return _result;
}

obb_overlaps_sphere :: proc "contextless" (obb : OBB, sphere_position : [3]f32, sphere_radius : f32) -> bool {
	_sphere_pos : #simd[4]f32 = simdy.from_vec3_f32(sphere_position, 0.0);
	_closest_point : #simd[4]f32 = obb_closest_point_simd(obb, _sphere_pos);
	_vec := simd.sub(_sphere_pos, _closest_point)
	dist_sq   := simdy.masked_dot(_vec, _vec);
	radius_sq := sphere_radius * sphere_radius;
	return dist_sq < radius_sq;
}