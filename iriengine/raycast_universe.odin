package iri

import "core:log"
import geo "odinary:geometry"

import "core:math"
import "core:math/linalg"

HitInfo :: struct {
	position  : [3]f32,
	normal   : [3]f32,
	distance : f32,
	entity : Entity,
	mesh_id : MeshID,
	mat_id : MaterialID,
}


raycast_universe :: proc(uni : ^Universe, origin : [3]f32, dir : [3]f32, max_ray_dist : f32 = math.F32_MAX) -> (out_did_hit : bool, out_hit_info : HitInfo) {
	
	// @NOTE: doing inverse transpose for every object may be ok but doing also for every ray agian seems expensive, we should cache it at least on the cpu
	// on gpu we could recalculate it once from the matrix buffer in a compute shader and then after that trace ray or just also uplaod it from cpu next to standart matrix buffer.

	ray_origin_ws := [4]f32 {origin.x,origin.y,origin.z, 1.0};

	ray_ws := geo.Ray{
		origin = ray_origin_ws.xyz,
		dir = linalg.normalize(dir),
		inv_dir = 1.0 / dir,
	}

	mesh_manager : ^MeshManager = engine.mesh_manager;

	drawables : ^#soa[dynamic]Drawable =  &uni.ecs.drawables;

	any_hit : bool = false;
	curr_closest_hit := HitInfo{
		distance = max_ray_dist
	}

	// @Note: frame renderables would be one frame behind if we call this proc from game code.
	for drawable_index in uni.frame_renderables {

		mesh_id := drawables[drawable_index].draw_instance.mesh_id;

		// use inverse_transpose for dir because off non-uniform scaling ??
		// Transform ray into object space using the inverse matrix
		world_mat := drawables[drawable_index].world_mat
		world_trans := drawables[drawable_index].prev_physics_world_transform;
		inv_mat := linalg.matrix4_inverse(world_mat);
		//inv_trans_mat := linalg.transpose(inv_mat);

		origin_os := inv_mat * ray_origin_ws; 

		ray_os := geo.Ray {
			origin = origin_os.xyz,
			// @Note: Dont normalize this!
			dir = (inv_mat * [4]f32{ray_ws.dir.x,ray_ws.dir.y,ray_ws.dir.z,0.0}).xyz,
		}

		ray_os.inv_dir = 1.0 / ray_os.dir;

		bvh_data := mesh_manager.meshes[mesh_id].bvh_data

		if did_hit, hit_info := raycast_blas_bvh_stackbased(mesh_manager, &bvh_data, ray_os, curr_closest_hit.distance, world_mat); did_hit == true {

			any_hit = true;
			
			inverse_transpose_mat := linalg.matrix4_adjoint(world_mat);
			
			hit_info.position = ray_ws.origin + ray_ws.dir * hit_info.distance;
			
			norm := inverse_transpose_mat * [4]f32{hit_info.normal.x, hit_info.normal.y, hit_info.normal.z, 0.0};
			hit_info.normal = linalg.normalize(norm.xyz);

			hit_info.entity = drawables[drawable_index].entity;
			hit_info.mat_id = drawables[drawable_index].draw_instance.mat_id;
			hit_info.mesh_id = mesh_id;

			curr_closest_hit = hit_info;
		}
	}

	if any_hit {
		out_did_hit = true;
		out_hit_info = curr_closest_hit;
	}

	return out_did_hit, out_hit_info;
}


get_bvh_get_triangle :: #force_inline proc "contextless" (mesh_manager : ^MeshManager, bvh_data : ^BlasBvhData, relative_triangle_index : u32) -> (tri_corners : [3][3]f32) {
						
	v_index_0 : u32 = mesh_manager.blas_indecies[ bvh_data.bvh_indecies_offset + cast(u64)(relative_triangle_index) * 3 + 0];
	v_index_1 : u32 = mesh_manager.blas_indecies[ bvh_data.bvh_indecies_offset + cast(u64)(relative_triangle_index) * 3 + 1];
	v_index_2 : u32 = mesh_manager.blas_indecies[ bvh_data.bvh_indecies_offset + cast(u64)(relative_triangle_index) * 3 + 2];

	tri_corners[0] = mesh_manager.blas_vertecies[bvh_data.bvh_vertecies_offset + cast(u64)v_index_0];
	tri_corners[1] = mesh_manager.blas_vertecies[bvh_data.bvh_vertecies_offset + cast(u64)v_index_1];
	tri_corners[2] = mesh_manager.blas_vertecies[bvh_data.bvh_vertecies_offset + cast(u64)v_index_2];
	return tri_corners;
}


// Hit info returnd is not neccesarly in world space if ray is not in world space!
raycast_blas_bvh_stackbased :: proc (mesh_manager : ^MeshManager, bvh_data : ^BlasBvhData, ray : geo.Ray, max_ray_dist : f32 = math.F32_MAX, world_mat : matrix[4,4]f32) -> (bool, HitInfo) {

	DEBUG_DRAW :: true

	// initialze to root node.
	node : ^geo.BvhNode = &mesh_manager.blas_bvh_nodes[cast(u32)bvh_data.bvh_nodes_offset];
	
	STACK_SIZE :: 32

	// stack stores absolute node indexes into blas_bvh_nodes buffer ( node = blas_bvh_nodes[stack[stack_ptr]]);
	stack : [STACK_SIZE]u32; 
	stack_ptr : u32 = 0;
	
	any_hit : bool = false;
	curr_closest_hit_dist : f32 = max_ray_dist;
	// store the 3 (closest) triangle vertecies to construct face normal later
	curr_closest_hit_triangle : [3][3]f32; 


	node_loop: for true {

		engine_assert(stack_ptr < STACK_SIZE);

		if geo.bvh_is_leaf_node(node) {

			engine_assert(node.tri_count > 0);

			when DEBUG_DRAW {
				debug_draw_bvh_node(DebugColor.Cyan, node, world_mat);
			}

			for i in 0..<node.tri_count {
				
				tri : [3][3]f32 = #force_inline get_bvh_get_triangle(mesh_manager, bvh_data, node.left_first + i);

				if _did_hit, hit_dist := geo.ray_intersects_triangle(ray, tri[0], tri[1], tri[2], curr_closest_hit_dist); _did_hit == true {
					any_hit = true;
					curr_closest_hit_dist = hit_dist;
					curr_closest_hit_triangle = tri;

					when DEBUG_DRAW {
						debug_draw_bvh_triangle(DebugColor.Green, &tri, world_mat);
					}
				} else {
					when DEBUG_DRAW {
						debug_draw_bvh_triangle(DebugColor.Red, &tri, world_mat);
					}
				}
			}

			if stack_ptr == 0 {
				break node_loop;
			} else {
				stack_ptr -= 1;
				node = &mesh_manager.blas_bvh_nodes[stack[stack_ptr]];
			}

			continue;
		}

		when DEBUG_DRAW {
			debug_draw_bvh_node(DebugColor.Black, node, world_mat);
		}

		child_1_index_abs : u32 = cast(u32)bvh_data.bvh_nodes_offset + node.left_first;
		child_2_index_abs : u32 = cast(u32)bvh_data.bvh_nodes_offset + node.left_first + 1;

		child_1 : ^geo.BvhNode = &mesh_manager.blas_bvh_nodes[child_1_index_abs];
		child_2 : ^geo.BvhNode = &mesh_manager.blas_bvh_nodes[child_2_index_abs];

		dist_1 : f32 = geo.ray_intersects_aabb_dist(ray, child_1.aabb_min, child_1.aabb_max, curr_closest_hit_dist);
		dist_2 : f32 = geo.ray_intersects_aabb_dist(ray, child_2.aabb_min, child_2.aabb_max, curr_closest_hit_dist);

		// sort so child1 is closer or equal to child2
		if dist_1 > dist_2 {
			// Swap
			dist_1 , dist_2  = dist_2, dist_1;
			child_1, child_2 = child_2, child_1;
			child_1_index_abs, child_2_index_abs = child_2_index_abs, child_1_index_abs;
		}

		if dist_1 < math.F32_MAX {
			// Procced with closer child and 
			node = child_1;
			if dist_2 < math.F32_MAX {
				// Push further child on stack if needed
				stack[stack_ptr] = child_2_index_abs;
				stack_ptr += 1;
			}
		} else {

			// Closest child node was not hit so both missed
			// Procced with next on stack or terminate
			if stack_ptr == 0 {
				break node_loop;
			} else {
				stack_ptr -= 1;
				node = &mesh_manager.blas_bvh_nodes[stack[stack_ptr]];
			}
		}
	}


	
	if any_hit {
		hit_info : HitInfo;	

		hit_info.position = ray.origin + ray.dir * curr_closest_hit_dist;
		hit_info.distance = curr_closest_hit_dist;

		edge_ab : [3]f32 = curr_closest_hit_triangle[1]-curr_closest_hit_triangle[0];
    	edge_ac : [3]f32 = curr_closest_hit_triangle[2]-curr_closest_hit_triangle[0];
    	normal : [3]f32 = linalg.cross(edge_ab, edge_ac);
		hit_info.normal = linalg.normalize(normal);

		return true, hit_info;
	}

	return false, HitInfo{};
}


debug_draw_bvh_node :: proc(color : DebugDrawColor, node : ^geo.BvhNode, world_mat : matrix[4,4]f32){

	node_aabb := geo.aabb_from_min_max_vec3(node.aabb_min, node.aabb_max);
	aabb_model_mat := world_mat * geo.aabb_to_transform_matrix(node_aabb);

	debug_draw_box(color, aabb_model_mat);
}

debug_draw_bvh_triangle :: proc(color : DebugDrawColor, tri : ^[3][3]f32, world_mat : matrix[4,4]f32){
	
	v0 : [3]f32 = [3]f32{tri[0].x,tri[0].y,tri[0].z};
	v1 : [3]f32 = [3]f32{tri[1].x,tri[1].y,tri[1].z};
	v2 : [3]f32 = [3]f32{tri[2].x,tri[2].y,tri[2].z};

	center := (tri[0] + tri[1] + tri[2]) * 0.333333;

	v0_to_c := center - v0;
	v1_to_c := center - v1;
	v2_to_c := center - v2;

	// longest vector from tri center to vertex
	max_length : f32 = linalg.sqrt(max(max(linalg.dot(v0_to_c,v0_to_c), linalg.dot(v1_to_c,v1_to_c)),linalg.dot(v2_to_c,v2_to_c)));

	v0 += linalg.normalize(v0_to_c) * max_length * 0.10;
	v1 += linalg.normalize(v1_to_c) * max_length * 0.10;
	v2 += linalg.normalize(v2_to_c) * max_length * 0.10;

	_v0 : [4]f32 = world_mat * [4]f32{v0.x,v0.y,v0.z, 1.0};
	_v1 : [4]f32 = world_mat * [4]f32{v1.x,v1.y,v1.z, 1.0};
	_v2 : [4]f32 = world_mat * [4]f32{v2.x,v2.y,v2.z, 1.0};

	debug_draw_line(color, _v0.xyz, _v1.xyz);
	debug_draw_line(color, _v1.xyz, _v2.xyz);
	debug_draw_line(color, _v2.xyz, _v0.xyz);
}