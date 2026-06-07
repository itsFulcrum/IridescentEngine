package iri

import "core:log"
import "core:mem"
import geo "odinary:geometry"

import "core:math"
import "core:math/linalg"

import sdl "vendor:sdl3"

HitInfo :: struct {
	position  : [3]f32,
	normal    : [3]f32,
	distance  : f32,
	entity    : Entity,
	drawable_index : u32,
	mesh_id   : MeshID,
	mat_id    : MaterialID,
}

// maybe cache this structure as part of universe
TLBvhBuildInfo :: struct {
	tl_nodes : []geo.BvhNode,
	tl_num_nodes_used : uint,

	num_split_planes : u32,

	// temp storage
	split_bins : []geo.BvhSplitBin,
	split_plane_area_left   : []f32,
	split_plane_area_right  : []f32,
	split_plane_count_left  : []u32,
	split_plane_count_right : []u32,

	drawables : ^#soa[dynamic]Drawable,
	draw_indecies : []u32,
}

// @FIXME: because raytracing atm works on 1 frame late data, it is possible that when removing drawables the indexes are wrong and we index wrongly and crash!
// Idk how to fix this except maybe dont remove drawables imidiatly but wait 1 frame.
raycast_universe :: proc(uni : ^Universe, origin : [3]f32, dir : [3]f32, max_ray_dist : f32 = math.INF_F32) -> (did_hit : bool, hit_info : HitInfo) {
	IRI_PROFILE_PROCEDURE()

	DEBUG_DRAW :: false

	if len(uni.tlas_nodes) <= 0{
		return false, HitInfo{};
	}
	ray_origin_ws := [4]f32 {origin.x,origin.y,origin.z, 1.0};

	ray_ws := geo.Ray{
		origin = ray_origin_ws.xyz,
		dir = linalg.normalize(dir),
		inv_dir = 1.0 / dir,
	}

	mesh_manager : ^MeshManager = engine.mesh_manager;

	drawables : ^#soa[dynamic]Drawable =  &uni.ecs.drawables;

	STACK_SIZE :: 32

	// stack stores absolute node indexes into blas_bvh_nodes buffer ( node = blas_bvh_nodes[stack[stack_ptr]]);
	stack : [STACK_SIZE]u32; 
	stack_ptr : u32 = 0;
	
	any_hit : bool = false;
	curr_closest_hit := HitInfo {
		distance = max_ray_dist,

	}

	node := &uni.tlas_nodes[0];

	tlas_node_loop: for true {

		engine_assert(stack_ptr < STACK_SIZE);

		if geo.bvh_is_leaf_node(node) {


			for i in 0..<node.count {

				drawable_index := uni.frame_tl_draw_indecies[node.left_first + i];

				inv_mat   := drawables.inv_world_mat[drawable_index];

				// Transform ray from world space to object space of the bottom level bvh
				ray_os := geo.Ray {
					origin = (inv_mat * ray_origin_ws).xyz,
					// @Note: Dont normalize this direction!
					dir = (inv_mat * [4]f32{ray_ws.dir.x,ray_ws.dir.y,ray_ws.dir.z,0.0}).xyz,
				}
				ray_os.inv_dir = 1.0 / ray_os.dir;
	 			
				global_buf_info := drawables.global_buf_info[drawable_index];

				if bl_did_hit, bl_hit_info := raycast_bl_bvh(mesh_manager, &global_buf_info, ray_os, curr_closest_hit.distance, drawables, drawable_index); bl_did_hit == true {

					any_hit = true;
					
					curr_closest_hit.drawable_index = drawable_index;
					
					curr_closest_hit.position = ray_ws.origin + ray_ws.dir * bl_hit_info.distance;
					curr_closest_hit.distance = bl_hit_info.distance;
					
					// normal needs to be transformed from object space to world space
					world_mat := drawables.world_mat[drawable_index];
					inverse_transpose_mat := linalg.matrix4_adjoint(world_mat);				
					normal_os := inverse_transpose_mat * [4]f32{bl_hit_info.normal.x, bl_hit_info.normal.y, bl_hit_info.normal.z, 0.0};
					curr_closest_hit.normal = linalg.normalize(normal_os.xyz);
				}
			}		


			if stack_ptr == 0 {
				break tlas_node_loop;
			} else {
				stack_ptr -= 1;
				node = &uni.tlas_nodes[stack[stack_ptr]];
			}

			continue;
		}

		when DEBUG_DRAW {
			debug_draw_bvh_node(DebugColor.Black, node, world_mat);
		}

		child_1_index : u32 = node.left_first;
		child_2_index : u32 = node.left_first + 1;

		child_1 : ^geo.BvhNode = &uni.tlas_nodes[child_1_index];
		child_2 : ^geo.BvhNode = &uni.tlas_nodes[child_2_index];

		dist_1 : f32 = geo.ray_intersects_aabb_dist(ray_ws, child_1.aabb_min, child_1.aabb_max, curr_closest_hit.distance);
		dist_2 : f32 = geo.ray_intersects_aabb_dist(ray_ws, child_2.aabb_min, child_2.aabb_max, curr_closest_hit.distance);

		// sort so child1 is closer or equal to child2
		if dist_1 > dist_2 {
			// Swap
			dist_1 , dist_2  = dist_2, dist_1;
			child_1, child_2 = child_2, child_1;
			child_1_index, child_2_index = child_2_index, child_1_index;
		}

		if dist_1 < math.INF_F32 {
			// Procced with closer child next and
			// push further child on stack if needed
			node = child_1;
			if dist_2 < math.INF_F32 {
				stack[stack_ptr] = child_2_index;
				stack_ptr += 1;
			}
		} else {

			// Closest child node was not hit so both missed
			// Procced with next on stack or terminate
			if stack_ptr == 0 {
				break tlas_node_loop;
			} else {
				stack_ptr -= 1;
				node = &uni.tlas_nodes[stack[stack_ptr]];
			}
		}
	}


	if any_hit {

		// @Note: we defer full hit info struct making here so we only do it when neccesary.
		// hit_distance, hit_position, hit_normal are calculated during tracing atm but 
		// technically we could also defer it if we also keep track of closest hit triangle.
		curr_closest_hit.entity 		= drawables[curr_closest_hit.drawable_index].entity;
		curr_closest_hit.mat_id  		= drawables[curr_closest_hit.drawable_index].draw_instance.mat_id;
		curr_closest_hit.mesh_id 		= drawables[curr_closest_hit.drawable_index].draw_instance.mesh_id;

		return true, curr_closest_hit;
	}

	return false, HitInfo{};
}

// Raycast from a camera. If camera_component is nil. Use the active camera instead.
raycast_universe_from_camera :: proc(universe : ^Universe, pixel_coords : [2]f32, camera_component : ^CameraComponent = nil, max_ray_dist : f32 = math.INF_F32) -> (did_hit : bool, hit_info : HitInfo){

	if universe == nil {
		return;
	}

	cam_comp : ^CameraComponent = camera_component != nil ? camera_component : ecs_get_active_camera_component(&universe.ecs);

	if cam_comp == nil {
		return false, HitInfo{};
	}

	cam_transform := ecs_get_transform(&universe.ecs, cam_comp.entity);
	ray_origin := cam_transform.position;

	// ==  Calculate world space ray direction from pixel coordinates. ==

	window_size := get_window_size();
	window_size_f : vec2 = vec2{cast(f32)window_size.x, cast(f32)window_size.y};
	window_aspect := get_window_aspect_ratio();

	pixel : vec2 = linalg.clamp(pixel_coords, vec2{0,0}, window_size_f);

	screen_uv : vec2 = pixel / window_size_f;
	screen_uv.y = 1.0 - screen_uv.y; // flip vertically

	ndc : vec4;
	ndc.xy = screen_uv * 2.0 - 1.0; // 0..1 to -1..1
	ndc.z = 0.1; // arbitray depth, it doesnt matter as long as not 0.
	ndc.w = 1.0;

	proj := comp_camera_get_projection_matrix(cam_comp, window_aspect);
	view := transform_calc_view_matrix(cam_transform);
	inv_view_proj := linalg.inverse(proj*view);

	point_ws : vec4 = inv_view_proj * ndc;
	point_ws.xyz /= point_ws.w;

	ray_dir : [3]f32 = linalg.normalize(point_ws.xyz - ray_origin);

	//debug_draw_ray(DebugColor.Magenta, ray_origin, ray_dir, 1000.0);

	return raycast_universe(universe, ray_origin, ray_dir, max_ray_dist);
}


raycast_universe_tl_looping :: proc(uni : ^Universe, origin : [3]f32, dir : [3]f32, max_ray_dist : f32 = math.INF_F32) -> (did_hit : bool, hit_info : HitInfo) {
	
	IRI_PROFILE_PROCEDURE()

	DEBUG_DRAW :: false

	if len(uni.tlas_nodes) <= 0{
		return false, HitInfo{};
	}
	ray_origin_ws := [4]f32 {origin.x,origin.y,origin.z, 1.0};
	ray_ws := geo.Ray{
		origin = ray_origin_ws.xyz,
		dir = linalg.normalize(dir),
		inv_dir = 1.0 / dir,
	}

	mesh_manager : ^MeshManager = engine.mesh_manager;

	drawables : ^#soa[dynamic]Drawable =  &uni.ecs.drawables;

	
	any_hit : bool = false;
	curr_closest_hit := HitInfo {
		distance = max_ray_dist
	}

	for drawable_index in uni.frame_renderables {

		inv_mat := drawables.inv_world_mat[drawable_index];

		// Transform Ray from world space to the object space of the bottom level bvh
		ray_os := geo.Ray {
			origin 	= (inv_mat * ray_origin_ws).xyz,
			dir 	= (inv_mat * [4]f32{ray_ws.dir.x,ray_ws.dir.y,ray_ws.dir.z,0.0}).xyz,	// @Note: Dont normalize this!
		}
		ray_os.inv_dir = 1.0 / ray_os.dir;
				
		global_buf_info := drawables.global_buf_info[drawable_index];

		if bl_did_hit, bl_hit_info := raycast_bl_bvh(mesh_manager, &global_buf_info, ray_os, curr_closest_hit.distance, drawables, drawable_index); bl_did_hit == true {

			any_hit = true;
			
			curr_closest_hit.drawable_index = drawable_index;
			curr_closest_hit.position = ray_ws.origin + ray_ws.dir * bl_hit_info.distance;
			curr_closest_hit.distance = bl_hit_info.distance;
			
			world_mat := drawables.world_mat[drawable_index];
			inverse_transpose_mat := linalg.matrix4_adjoint(world_mat);				
			normal_os := inverse_transpose_mat * [4]f32{bl_hit_info.normal.x, bl_hit_info.normal.y, bl_hit_info.normal.z, 0.0};
			curr_closest_hit.normal = linalg.normalize(normal_os.xyz);
			
			curr_closest_hit.entity  = drawables[drawable_index].entity;
			curr_closest_hit.mat_id  = drawables[drawable_index].draw_instance.mat_id;
			curr_closest_hit.mesh_id = drawables[drawable_index].draw_instance.mesh_id;
		}
	}

	if any_hit {
		return true, curr_closest_hit;
	}

	return false, HitInfo{};
}


get_bvh_triangle :: #force_inline proc "contextless" (mesh_manager : ^MeshManager, global_buf_info : ^DrawableGlobalBufferInfo, relative_triangle_index : u32) -> (tri_corners : [3][3]f32) {
						
	v_index_0 : u32 = mesh_manager.global_indecies[global_buf_info.global_indecies_offset + relative_triangle_index * 3 + 0];
	v_index_1 : u32 = mesh_manager.global_indecies[global_buf_info.global_indecies_offset + relative_triangle_index * 3 + 1];
	v_index_2 : u32 = mesh_manager.global_indecies[global_buf_info.global_indecies_offset + relative_triangle_index * 3 + 2];

	tri_corners[0] = mesh_manager.global_vertecies[global_buf_info.global_vertecies_offset + v_index_0].xyz;
	tri_corners[1] = mesh_manager.global_vertecies[global_buf_info.global_vertecies_offset + v_index_1].xyz;
	tri_corners[2] = mesh_manager.global_vertecies[global_buf_info.global_vertecies_offset + v_index_2].xyz;
	return tri_corners;
}


// Hit info returnd is not neccesarly in world space if ray is not in world space!
// @Note: drawables array and drawable_index are only needed for debug drawing.
raycast_bl_bvh :: proc (mesh_manager : ^MeshManager, global_buf_info : ^DrawableGlobalBufferInfo, ray : geo.Ray, max_ray_dist : f32 = math.INF_F32, drawables : ^#soa[dynamic]Drawable, drawable_index : u32) -> (bool, HitInfo) {

	IRI_PROFILE_PROCEDURE()
	
	DEBUG_DRAW :: false

	when DEBUG_DRAW {
		world_mat : matrix[4,4]f32 = drawables[drawable_index].world_mat;
	}
	// initialze to root node.
	node : ^geo.BvhNode = &mesh_manager.global_bl_bvh_nodes[cast(u32)global_buf_info.bl_bvh_root_offset];
	
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

			engine_assert(node.count > 0);

			when DEBUG_DRAW {
				debug_draw_bvh_node(DebugColor.Cyan, node, world_mat);
			}

			for i in 0..<node.count {
				
				tri : [3][3]f32 = #force_inline get_bvh_triangle(mesh_manager, global_buf_info, node.left_first + i);

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
				node = &mesh_manager.global_bl_bvh_nodes[stack[stack_ptr]];
			}

			continue;
		}

		when DEBUG_DRAW {
			debug_draw_bvh_node(DebugColor.Black, node, world_mat);
		}

		child_1_index_abs : u32 = cast(u32)global_buf_info.bl_bvh_root_offset + node.left_first;
		child_2_index_abs : u32 = cast(u32)global_buf_info.bl_bvh_root_offset + node.left_first + 1;

		child_1 : ^geo.BvhNode = &mesh_manager.global_bl_bvh_nodes[child_1_index_abs];
		child_2 : ^geo.BvhNode = &mesh_manager.global_bl_bvh_nodes[child_2_index_abs];

		dist_1 : f32 = geo.ray_intersects_aabb_dist(ray, child_1.aabb_min, child_1.aabb_max, curr_closest_hit_dist);
		dist_2 : f32 = geo.ray_intersects_aabb_dist(ray, child_2.aabb_min, child_2.aabb_max, curr_closest_hit_dist);

		// sort so child1 is closer or equal to child2
		if dist_1 > dist_2 {
			// Swap
			dist_1 , dist_2  = dist_2, dist_1;
			child_1, child_2 = child_2, child_1;
			child_1_index_abs, child_2_index_abs = child_2_index_abs, child_1_index_abs;
		}

		if dist_1 < math.INF_F32 {
			// Procced with closer child next and
			// push further child on stack if needed
			node = child_1;
			if dist_2 < math.INF_F32 {
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
				node = &mesh_manager.global_bl_bvh_nodes[stack[stack_ptr]];
			}
		}
	}
	
	if any_hit {
		hit_info : HitInfo;	

		hit_info.position = ray.origin + ray.dir * curr_closest_hit_dist;
		hit_info.distance = curr_closest_hit_dist;

		edge_ab : [3]f32 = curr_closest_hit_triangle[1]-curr_closest_hit_triangle[0];
    	edge_ac : [3]f32 = curr_closest_hit_triangle[2]-curr_closest_hit_triangle[0];
    	normal  : [3]f32 = linalg.cross(edge_ab, edge_ac);
		hit_info.normal = linalg.normalize(normal);

		return true, hit_info;
	}

	return false, HitInfo{};
}

// TODO: test rebuild performance when we disable bounds check!
// TODO: implement max tree depth
tl_bvh_rebuild :: proc(gpu_device : ^sdl.GPUDevice, uni : ^Universe, mesh_manager : ^MeshManager, num_split_planes : u32 = 8, max_tree_depth : u32 = 32){

	IRI_PROFILE_PROCEDURE()

	upload_info_reset(&uni.tlas_nodes_buf.upload_info);
	upload_info_reset(&uni.frame_tl_draw_indecies_buf.upload_info);

	num_renderables : int = len(uni.frame_renderables);
	if num_renderables == 0 {
		// TODO: if we went from N renderables to 0 renderables 
		// we would have to upload this information to gpu buffer 
		// For now releasing the buffers should be okey.
		if len(uni.tlas_nodes) > 0 {
			clear(&uni.tlas_nodes);
		}
		gpu_buffer_release_buffers(gpu_device, &uni.tlas_nodes_buf);
		return;
	}

	bl_count : int = num_renderables;
	tl_num_nodes : int = bl_count * 2; // -1 // skip -1 bc we resever one extra after root node.
	
	// FIXME: resize will copy old data when reallocating which is not what we want here!
	resize_dynamic_array(&uni.tlas_nodes, tl_num_nodes);

	info : TLBvhBuildInfo = {}
	info.tl_nodes = uni.tlas_nodes[:];
	info.num_split_planes = num_split_planes;

	// Temp allocate split bin storages
	num_intervals : u32 = num_split_planes + 1;
	info.split_bins = make_slice([]geo.BvhSplitBin, cast(int)num_intervals, context.temp_allocator);

	info.split_plane_area_left   = make_slice([]f32, cast(int)(num_split_planes), context.temp_allocator);
	info.split_plane_area_right  = make_slice([]f32, cast(int)(num_split_planes), context.temp_allocator);
	info.split_plane_count_left  = make_slice([]u32, cast(int)(num_split_planes), context.temp_allocator);
	info.split_plane_count_right = make_slice([]u32, cast(int)(num_split_planes), context.temp_allocator);


	info.drawables = &uni.ecs.drawables;

	// copy current renderables indexes list so we can reorder it for bvh traversal.
	resize_dynamic_array(&uni.frame_tl_draw_indecies, num_renderables);
	mem.copy_non_overlapping(&uni.frame_tl_draw_indecies[0], &uni.frame_renderables[0], num_renderables * size_of(u32));

	info.draw_indecies = uni.frame_tl_draw_indecies[:];

	root := &info.tl_nodes[0];
	root.left_first = 0;
	root.count = cast(u32)num_renderables;

	info.tl_num_nodes_used  = 1; // root node
	info.tl_num_nodes_used += 1; // Skip 1 node after root.
	
	tl_bvh_recalculate_node_aabb(&info, root);

	tl_bvh_subdivide_recursiv(&info, root);


	// copy tl nodes to transfer buffer to copy onto the gpu.
	{
		gpu_buf_data := &uni.tlas_nodes_buf;
		required_byte_size : int = len(uni.tlas_nodes) * size_of(geo.BvhNode);

		if required_byte_size > cast(int)gpu_buf_data.curr_byte_size {
			gpu_buffer_reallocate_buffers(gpu_device, gpu_buf_data, cast(u32)required_byte_size);
		}

		if required_byte_size > 0 {
			upinfo := &gpu_buf_data.upload_info;
			upinfo.requires_upload = true;
			upinfo.region_min_index = 0;
			upinfo.region_max_index = len(uni.tlas_nodes) -1;
			
			gpu_buffer_memcopy_upload_info_min_max_region_to_transfer_buffer(gpu_device, gpu_buf_data, &uni.tlas_nodes[0], size_of(geo.BvhNode), cycle = true);
		}
	}

	{
		element_byte_size : int = size_of(u32)
		gpu_buf_data := &uni.frame_tl_draw_indecies_buf;
		required_byte_size : int = len(uni.frame_tl_draw_indecies) * element_byte_size;

		if required_byte_size > cast(int)gpu_buf_data.curr_byte_size {
			gpu_buffer_reallocate_buffers(gpu_device, gpu_buf_data, cast(u32)required_byte_size);
		}

		if required_byte_size > 0 {
			upinfo := &gpu_buf_data.upload_info;
			upinfo.requires_upload = true;
			upinfo.region_min_index = 0;
			upinfo.region_max_index = len(uni.frame_tl_draw_indecies) -1;
			
			gpu_buffer_memcopy_upload_info_min_max_region_to_transfer_buffer(gpu_device, gpu_buf_data, &uni.frame_tl_draw_indecies[0], element_byte_size, cycle = true);
		}
	}
}

tl_bvh_recalculate_node_aabb :: proc(info : ^TLBvhBuildInfo, node : ^geo.BvhNode){
	//IRI_PROFILE_PROCEDURE()

	first_drawable_index := info.draw_indecies[node.left_first + 0];
	aabb := geo.obb_to_aabb(info.drawables.world_oobb[first_drawable_index]);

	for i : u32 = 1; i < node.count; i+=1 {

		drawable_index := info.draw_indecies[node.left_first + i];
		aabb = geo.aabb_combine(aabb, geo.obb_to_aabb(info.drawables.world_oobb[drawable_index]));
	}

	node.aabb_min = aabb.min.xyz;
	node.aabb_max = aabb.max.xyz;
}

tl_bvh_find_best_split_plane :: proc(info : ^TLBvhBuildInfo, node : ^geo.BvhNode) -> (split_axis : u32, split_pos_along_axis : f32, split_cost : f32){
	//IRI_PROFILE_PROCEDURE()

	engine_assert(geo.bvh_is_leaf_node(node));

	best_axis : u32 = 0;
	best_pos  : f32 = 0;
	best_cost : f32 = math.INF_F32;

	// Intialze axis candidate to xyz order, then sort so longest two axis are first.
	// We then only evalute the two longest axis and skip the shortest one for faster builds.
	axis_candidates := [3]u32{0,1,2};
	extent : [3]f32 = node.aabb_max - node.aabb_min;

	if extent.y > extent.x {
		axis_candidates.xy = axis_candidates.yx;
	}
	if extent.z > extent[axis_candidates[0]]{
		axis_candidates.xyz = axis_candidates.zxy;
	} else if extent.z > extent[axis_candidates[1]] {
		axis_candidates.yz = axis_candidates.zy;
	}
	
	num_intervals : u32 = info.num_split_planes + 1;

	// At least for lumberyard it seems second longest axis is chosen very rarly and third longest never.
	// So for top level we only evaluate the longest axis and can maybe afford more a couple more split planes instead
	for a in 0..<2 {
		axis : u32 = axis_candidates[a];

		// Find bounds of the centroids which is smaller than the bounds of the whole aabb
		
		// Skiping thight bounds calculation improved build speed for lumberyard by 1 ms
		// But likely reduced quality tree
		bounds_min : f32 = info.drawables.world_oobb[info.draw_indecies[node.left_first]].center[axis];
		bounds_max : f32 = info.drawables.world_oobb[info.draw_indecies[node.left_first]].center[axis];

		for i : u32 = 1; i < node.count; i+=1 {
			draw_index := info.draw_indecies[node.left_first + i];

			bounds_min = min(bounds_min, info.drawables.world_oobb[draw_index].center[axis]);
			bounds_max = max(bounds_max, info.drawables.world_oobb[draw_index].center[axis]);
		}

		if bounds_min == bounds_max {
			continue;
		}

		num_bins : u32 = num_intervals;
		geo.bvh_reset_all_bins(info.split_bins);

		bin_scale : f32 = f32(num_bins) / (bounds_max - bounds_min)

		// Figure out which bin the object belongs to and update the bin.
		for i : u32 = 0; i < node.count; i+=1 {
			
			draw_index : u32 = info.draw_indecies[node.left_first + i];

			center := info.drawables.world_oobb[draw_index].center;
			bin_index : u32 = min(num_bins - 1, cast(u32)((center[axis] - bounds_min) * bin_scale));
			
			info.split_bins[bin_index].count += 1;
			info.split_bins[bin_index].aabb = geo.aabb_combine(info.split_bins[bin_index].aabb, info.drawables.world_aabb[draw_index]);
		}

		// For each split plane we calculate the left and right aabb surface area and count
		// Sweep left to right and right to left simulatneously to gather per split plane data.
		left_aabb  : geo.AABB = geo.aabb_create_inverse_infinite();
		right_aabb : geo.AABB = geo.aabb_create_inverse_infinite();
		left_sum, right_sum : u32 = 0, 0;

		for i : u32 = 0; i < info.num_split_planes; i +=1 {
			
			left_sum += info.split_bins[i].count;
			info.split_plane_count_left[i] = left_sum;
			left_aabb = geo.aabb_combine(left_aabb, info.split_bins[i].aabb);
			info.split_plane_area_left[i] = geo.aabb_calculate_surface_area(left_aabb);

			right_sum += info.split_bins[num_bins - 1 - i].count;
			info.split_plane_count_right[num_bins - 2 - i] = right_sum;
			right_aabb = geo.aabb_combine(right_aabb, info.split_bins[num_bins - 1 - i].aabb);
			info.split_plane_area_right[num_bins - 2 - i] = geo.aabb_calculate_surface_area(right_aabb);
		}

		// Find best split plane with lowest surface area cost.
		interval_size : f32 = (bounds_max - bounds_min) / f32(num_intervals);

		for i : u32 = 0; i < info.num_split_planes; i+=1 {
			plane_cost : f32 = cast(f32)info.split_plane_count_left[i] * info.split_plane_area_left[i] + cast(f32)info.split_plane_count_right[i] * info.split_plane_area_right[i];
			if plane_cost < best_cost {
				best_cost = plane_cost;
				best_axis = axis;
				best_pos  = bounds_min + f32(i + 1) * interval_size;
			}
		}

	}

	return best_axis, best_pos, best_cost;
}

tl_bvh_subdivide_recursiv :: proc(info : ^TLBvhBuildInfo, node : ^geo.BvhNode, curr_tree_depth : uint = 1){
	//IRI_PROFILE_PROCEDURE()

	assert(geo.bvh_is_leaf_node(node));

	axis, split_pos, split_cost := tl_bvh_find_best_split_plane(info, node);
	node_no_split_cost : f32 = geo.bvh_calculate_node_cost(node);
	if split_cost >= node_no_split_cost  {
		// abort if splitting does not improve the cost of the node
		return; 
	}

	// sort bl drawables left and right to the split axis position
	// @Note: i and j Must be signed intergers!
	i : int = cast(int)node.left_first;
	j : int = i + cast(int)node.count - 1;
	
	for i <= j {
		i_drawable_index := info.draw_indecies[i];
		i_center := info.drawables.world_oobb[i_drawable_index].center;
		if i_center[axis] < split_pos {
			i += 1;	
		} else {
			// swap
			info.draw_indecies[i], info.draw_indecies[j] = info.draw_indecies[j], info.draw_indecies[i];
			j -= 1;
		}
	}

	left_count : u32 = cast(u32)i - node.left_first;
	if left_count == 0 || left_count == node.count {
		return; // abort if one of the childs would be empty.
	}

	// create child nodes
	left_child_idx : u32 = cast(u32)info.tl_num_nodes_used;
	info.tl_num_nodes_used += 1;

	right_child_idx : u32 = cast(u32)info.tl_num_nodes_used;
	info.tl_num_nodes_used += 1;

	info.tl_nodes[left_child_idx].left_first = node.left_first;
	info.tl_nodes[left_child_idx].count = left_count;

	info.tl_nodes[right_child_idx].left_first = cast(u32)i;
	info.tl_nodes[right_child_idx].count = node.count - left_count;

	// make the current node a parent node
	node.left_first = left_child_idx;
	node.count = 0;

	left_child_node  := &info.tl_nodes[left_child_idx];
	right_child_node := &info.tl_nodes[right_child_idx];

	tl_bvh_recalculate_node_aabb(info, left_child_node);
	tl_bvh_recalculate_node_aabb(info, right_child_node);

	tl_bvh_subdivide_recursiv(info, left_child_node , curr_tree_depth + 1);
	tl_bvh_subdivide_recursiv(info, right_child_node, curr_tree_depth + 1);

	return;
}



// ==============  Debug draw util =====================

debug_draw_bvh_node :: proc(color : DebugDrawColor, node : ^geo.BvhNode, world_mat : matrix[4,4]f32){

	node_aabb := geo.aabb_from_min_max_vec3(node.aabb_min, node.aabb_max);
	aabb_model_mat := world_mat * geo.aabb_to_transform_matrix(node_aabb);

	debug_draw_box(color, aabb_model_mat);
}

debug_draw_tl_bvh_node :: proc(color : DebugDrawColor, node : ^geo.BvhNode) {

	node_aabb := geo.aabb_from_min_max_vec3(node.aabb_min, node.aabb_max);
	aabb_model_mat := geo.aabb_to_transform_matrix(node_aabb);

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