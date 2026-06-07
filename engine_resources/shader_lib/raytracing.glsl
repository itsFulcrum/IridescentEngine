#ifndef RAYTRACING_GLSL
#define RAYTRACING_GLSL


// All these includes are the required buffers.
// We are assuming Set is 0 for all of them
// All the binding defines should be defined in the src file
// before including this file.
// you may just define the bind offset and keep these buffers ordered the same
#ifndef RAYTRACING_BUFFERS_BIND_OFFSET
#define RAYTRACING_BUFFERS_BIND_OFFSET 0
#endif

// Read-Only Storage Buffers
#ifndef RES_MATRIX_BUFFER_BIND
#define RES_MATRIX_BUFFER_BIND RAYTRACING_BUFFERS_BIND_OFFSET + 0
#endif
#include "resources/resource_matrix_buffer.glsl"

#ifndef RES_INV_MATRIX_BUFFER_BIND
#define RES_INV_MATRIX_BUFFER_BIND RAYTRACING_BUFFERS_BIND_OFFSET + 1
#endif
#include "resources/resource_inv_matrix_buffer.glsl"

// - Global Indecies Buffer | uint _global_index_buffer[];
#ifndef RES_GLOBAL_INDEX_BUFFER_BIND
#define RES_GLOBAL_INDEX_BUFFER_BIND RAYTRACING_BUFFERS_BIND_OFFSET + 2
#endif
#include "resources/resource_global_index_buffer.glsl"

// - Global Vertecies Buffer | vec3 _global_vertex_buffer[];
#ifndef RES_GLOBAL_VERTEX_BUFFER_BIND
#define RES_GLOBAL_VERTEX_BUFFER_BIND RAYTRACING_BUFFERS_BIND_OFFSET + 3
#endif
#include "../shader_lib/resources/resource_global_vertex_buffer.glsl"

// // - TL Bvh draw Indexes | uint _tl_bvh_draw_indecies[];
#ifndef RES_TL_BVH_DRAW_INDECIES_BUFFER_BIND
#define RES_TL_BVH_DRAW_INDECIES_BUFFER_BIND RAYTRACING_BUFFERS_BIND_OFFSET + 4
#endif
// // - Global Tl BvhNodes  | BvhNode _tl_bvh_nodes[];
#ifndef RES_TL_BVH_NODES_BUFFER_BIND
#define RES_TL_BVH_NODES_BUFFER_BIND RAYTRACING_BUFFERS_BIND_OFFSET + 5
#endif

// - Global Bl BvhNodes  | BvhNode _global_bl_bvh_nodes[];
#ifndef RES_GLOBAL_BL_BVH_NODES_BUFFER_BIND
#define RES_GLOBAL_BL_BVH_NODES_BUFFER_BIND RAYTRACING_BUFFERS_BIND_OFFSET + 6
#endif
#include "../shader_lib/resources/resource_bvh_buffers.glsl"

// - DrawableGlobalBufInfo | DrawInfo _draw_info_buffer[]
#ifndef RES_DRAW_INFO_BUFFER_BIND
#define RES_DRAW_INFO_BUFFER_BIND RAYTRACING_BUFFERS_BIND_OFFSET + 7
#endif
#include "../shader_lib/resources/resource_drawables_global_infos_buffer.glsl"


//#define RAY_FLOAT_INF 1e20
#define RAY_FLOAT_INF 1000000000.0f
#define TOP_LEVEL_STACK_SIZE 32
#define BOT_LEVEL_STACK_SIZE 32

struct Ray {
	vec3 origin;
	vec3 dir;
	vec3 inv_dir;
};

struct RayHit {
	vec3 position;
	float distance;
	vec3 normal;
	uint draw_index;
};

// Ray aabb intersection
float ray_intersects_aabb_dist(const Ray ray, const vec3 aabb_min, const vec3 aabb_max, float max_ray_dist) {


    vec3 t_min = (aabb_min - ray.origin) * ray.inv_dir;
    vec3 t_max = (aabb_max - ray.origin) * ray.inv_dir;

    vec3 mi = min(t_min, t_max);
    vec3 ma = max(t_min, t_max);

    float dist_near = max(max(mi.x, mi.y), mi.z);
    float dist_far  = min(min(ma.x, ma.y), ma.z);

    // if dist_near > dist_far, ray doesn't intersect AABB
    // if dist_far < 0, ray (line) is intersecting AABB, but the AABB is behind ray direction
    bool did_hit = dist_far >= dist_near && dist_near < max_ray_dist && dist_far > 0.000f;

    if (did_hit){
    	return dist_near;
    }

    return RAY_FLOAT_INF;

    //return did_hit ? dist_near : RAY_FLOAT_INF;
}

// Ray Triangle intersection
float ray_intersects_triangle_dist(const Ray ray, const vec3 tri_vert_a, const vec3 tri_vert_b,const vec3 tri_vert_c, float max_ray_dist) {

	// could actually pre precompute per triangle..
    vec3 edge_ab = tri_vert_b - tri_vert_a;
    vec3 edge_ac = tri_vert_c - tri_vert_a;

    vec3 normal = cross(edge_ab, edge_ac);

    vec3 ao  = ray.origin - tri_vert_a;
    vec3 dao = cross(ao, ray.dir);


    float determinant = -dot(ray.dir, normal.xyz);
    float inv_det = 1.0 / determinant;

    float distance = dot(ao.xyz,normal.xyz) * inv_det;

    float u =  dot(edge_ac.xyz,dao.xyz) * inv_det;
    float v = -dot(edge_ab.xyz,dao.xyz) * inv_det;
    float w = 1.0 - u -v;

    bool did_miss = distance >= max_ray_dist || distance < 0.0001 || u < 0 || v < 0 || w < 0;
    // @Note: use additional determinant check if we want to backface cull
    //did_miss := determinant < 0.00001 || distance < 0 || u < 0 || v < 0 || w < 0; // use deteiminant check if we want to backface cull

    if (did_miss) {
    	return RAY_FLOAT_INF;
    }

    return distance;

    //return did_miss ? RAY_FLOAT_INF : distance;
}

bool ray_intersects_triangle(const Ray ray, const vec3 tri_vert_a, const vec3 tri_vert_b,const vec3 tri_vert_c, float max_ray_dist) {

	// could actually pre precompute per triangle..
    vec3 edge_ab = tri_vert_b - tri_vert_a;
    vec3 edge_ac = tri_vert_c - tri_vert_a;

    vec3 normal = cross(edge_ab, edge_ac);

    vec3 ao  = ray.origin - tri_vert_a;

    float determinant = -dot(ray.dir, normal.xyz);
    float inv_det = 1.0f / determinant;
    float distance = dot(ao.xyz,normal.xyz) * inv_det;

    if (distance >= max_ray_dist || distance < 0.00001f) {
    	return false;
    }
    
    vec3 dao = cross(ao, ray.dir);

    float u =  dot(edge_ac.xyz,dao.xyz) * inv_det;
    float v = -dot(edge_ab.xyz,dao.xyz) * inv_det;
    float w = 1.0f - u -v;

    bool did_miss = u < 0.0f || v < 0.0f || w < 0.0f;
    // @Note: use additional determinant check if we want to backface cull
    //did_miss := determinant < 0.00001 || distance < 0 || u < 0 || v < 0 || w < 0; // use deteiminant check if we want to backface cull

    return !did_miss;
}


// Rays should be in bvh's object space
float raycast_bl_bvh(const DrawInfo draw_info, const Ray ray, const float max_ray_dist) {

	RayHit closest_hit;
	closest_hit.distance = max_ray_dist;

	// stack stores absolute node indexes into _global_bl_bvh_nodes ( node = _global_bl_bvh_nodes[stack[stack_ptr]]);
	uint stack[BOT_LEVEL_STACK_SIZE];
	int stack_ptr = 0;

	float curr_closest_hit_dist = max_ray_dist;
	
	// Initialize to root node;
	BvhNode node = _global_bl_bvh_nodes[draw_info.bl_bvh_root_offset];


	uvec3 curr_clostest_hit_triangle = uvec3(0,0,0); // indecies into global vertex buffer!

	while (true) {

		if(node.count > 0) { // if node is leaf
			// TODO: check all triangles.
			
			for (uint i = 0; i < node.count; i++){
				
				uint relative_tri_index =  node.left_first + i;
				
				// get triangle
				uint v_index_0 = _global_index_buffer[draw_info.global_indecies_offset + relative_tri_index * 3 + 0];
				uint v_index_1 = _global_index_buffer[draw_info.global_indecies_offset + relative_tri_index * 3 + 1];
				uint v_index_2 = _global_index_buffer[draw_info.global_indecies_offset + relative_tri_index * 3 + 2];

				vec3 vert_0 = _global_vertex_buffer[draw_info.global_vertecies_offset + v_index_0].xyz;
				vec3 vert_1 = _global_vertex_buffer[draw_info.global_vertecies_offset + v_index_1].xyz;
				vec3 vert_2 = _global_vertex_buffer[draw_info.global_vertecies_offset + v_index_2].xyz;
				
				
				float hit_dist = ray_intersects_triangle_dist(ray, vert_0, vert_1, vert_2, curr_closest_hit_dist);
				if (hit_dist < curr_closest_hit_dist) {
					curr_closest_hit_dist = hit_dist;
					curr_clostest_hit_triangle = uvec3(v_index_0, v_index_1, v_index_2);	
				}
			}

			if (stack_ptr == 0) {
				break;
			} else {
				stack_ptr -= 1;
				node = _global_bl_bvh_nodes[stack[stack_ptr]];
			}

			continue;
		}

		uvec2 childs = uvec2(draw_info.bl_bvh_root_offset + node.left_first, draw_info.bl_bvh_root_offset + node.left_first + 1);

		vec2 dists = vec2(0.0f);
		dists.x = ray_intersects_aabb_dist(ray, _global_bl_bvh_nodes[childs.x].aabb_min, _global_bl_bvh_nodes[childs.x].aabb_max, curr_closest_hit_dist);
		dists.y = ray_intersects_aabb_dist(ray, _global_bl_bvh_nodes[childs.y].aabb_min, _global_bl_bvh_nodes[childs.y].aabb_max, curr_closest_hit_dist);

		if (dists.x > dists.y){
			// Swap;
			childs.xy = childs.yx;
			dists.xy = dists.yx;
		}

		if (dists.x < RAY_FLOAT_INF) { 
			// closer dist if was hit procced with closer child first
			// and push further child on stack if it was also hit.
			node = _global_bl_bvh_nodes[childs.x];
			if (dists.y < RAY_FLOAT_INF) {
				stack[stack_ptr] = childs.y;
				stack_ptr += 1;
			}
		} else {

			if (stack_ptr == 0){
				break;
			} else {
				stack_ptr -= 1;
				node = _global_bl_bvh_nodes[stack[stack_ptr]];
			}
		}
	}

	return curr_closest_hit_dist;
}


RayHit raycast_tl_bvh(const vec3 ray_origin, const vec3 ray_dir, const float max_ray_dist) {

	RayHit closest_hit;
	closest_hit.distance = max_ray_dist;

	Ray ray_ws;
	ray_ws.origin = ray_origin;
	ray_ws.dir = ray_dir;
	ray_ws.inv_dir = 1.0f / ray_dir;

	uint stack[TOP_LEVEL_STACK_SIZE];
	int stack_ptr = 0;

	// Initialize to root node;
	BvhNode node = _tl_bvh_nodes[0];

	bool any_bl_hit = false;

	while (true) {

		if(node.count > 0) { // if node is leaf

			for (uint i = 0; i < node.count; i++){

				uint draw_index = _tl_bvh_draw_indecies[node.left_first + i];
				mat4 inv_mat = _inv_matrix_buffer[draw_index];
				

				Ray ray_os;
				ray_os.origin.xyz = (inv_mat * vec4(ray_ws.origin.xyz, 1.0f)).xyz;
				ray_os.dir.xyz    = (inv_mat * vec4(ray_ws.dir.xyz, 0.0f)).xyz;
				ray_os.inv_dir = 1.0f / ray_os.dir;

				DrawInfo draw_info = _draw_info_buffer[draw_index];
				BvhNode bl_root = _global_bl_bvh_nodes[draw_info.bl_bvh_root_offset];

				
				float hit_dist = raycast_bl_bvh(draw_info, ray_os, closest_hit.distance);

				if (hit_dist < closest_hit.distance) {
					closest_hit.distance = hit_dist;
					closest_hit.draw_index = draw_index;
					any_bl_hit = true;
				}

			}

			if (stack_ptr == 0) {
				break;
			} else {
				node = _tl_bvh_nodes[stack[--stack_ptr]];
			}

			continue;
		}

		uvec2 childs = uvec2(node.left_first, node.left_first + 1);

		vec2 dists = vec2(0.0f);
		dists.x = ray_intersects_aabb_dist(ray_ws, _tl_bvh_nodes[childs.x].aabb_min, _tl_bvh_nodes[childs.x].aabb_max, closest_hit.distance);
		dists.y = ray_intersects_aabb_dist(ray_ws, _tl_bvh_nodes[childs.y].aabb_min, _tl_bvh_nodes[childs.y].aabb_max, closest_hit.distance);

		if (dists.x > dists.y){
			// Swap;
			childs.xy = childs.yx;
			dists.xy = dists.yx;
		}

		if (dists.x < RAY_FLOAT_INF) { 
			// closer dist if was hit procced with closer child first
			// and push further child on stack if it was also hit.
			node = _tl_bvh_nodes[childs.x];
			if (dists.y < RAY_FLOAT_INF) {
				stack[stack_ptr++] = childs.y;
			}
		} else {

			if (stack_ptr == 0){
				break;
			} else {
				node = _tl_bvh_nodes[stack[--stack_ptr]];
			}
		}
	}

	return closest_hit;
}



bool raycast_bl_bvh_anyhit(const DrawInfo draw_info, const Ray ray, const float max_ray_dist) {


	// stack stores absolute node indexes into _global_bl_bvh_nodes ( node = _global_bl_bvh_nodes[stack[stack_ptr]]);
	uint stack[BOT_LEVEL_STACK_SIZE];
	int stack_ptr = 0;

	
	// Initialize to root node;
	//BvhNode node = _global_bl_bvh_nodes[draw_info.bl_bvh_root_offset];
	uint node_idx = draw_info.bl_bvh_root_offset; 

	while (true) {

		if(_global_bl_bvh_nodes[node_idx].count > 0) { // if node is leaf
			
			for (uint i = 0; i < _global_bl_bvh_nodes[node_idx].count; i++){
				
				uint tri_index = draw_info.global_indecies_offset + (_global_bl_bvh_nodes[node_idx].left_first + i) * 3;
				
				vec4 vert_0 = _global_vertex_buffer[draw_info.global_vertecies_offset + _global_index_buffer[tri_index + 0]];
				vec4 vert_1 = _global_vertex_buffer[draw_info.global_vertecies_offset + _global_index_buffer[tri_index + 1]];
				vec4 vert_2 = _global_vertex_buffer[draw_info.global_vertecies_offset + _global_index_buffer[tri_index + 2]];
				
				if (ray_intersects_triangle(ray, vert_0.xyz, vert_1.xyz, vert_2.xyz, max_ray_dist)) {
					return true;	
				}
			}

			if (stack_ptr == 0) {
				break;
			} else {
				node_idx = stack[--stack_ptr];
			}

			continue;
		}

		uvec2 childs = uvec2(draw_info.bl_bvh_root_offset + _global_bl_bvh_nodes[node_idx].left_first, draw_info.bl_bvh_root_offset + _global_bl_bvh_nodes[node_idx].left_first + 1);

		vec2 dists = vec2(0.0f);
		dists.x = ray_intersects_aabb_dist(ray, _global_bl_bvh_nodes[childs.x].aabb_min, _global_bl_bvh_nodes[childs.x].aabb_max, max_ray_dist);
		dists.y = ray_intersects_aabb_dist(ray, _global_bl_bvh_nodes[childs.y].aabb_min, _global_bl_bvh_nodes[childs.y].aabb_max, max_ray_dist);

		if (dists.x > dists.y){
			// Swap;
			childs.xy = childs.yx;
			dists.xy  = dists.yx;
		}

		if (dists.x < RAY_FLOAT_INF) { 
			// closer dist if was hit procced with closer child first
			// and push further child on stack if it was also hit.
			node_idx = childs.x;
			if (dists.y < RAY_FLOAT_INF) {
				stack[stack_ptr++] = childs.y;
			}
		} else {

			if (stack_ptr == 0){
				break;
			} else {
				node_idx = stack[--stack_ptr];
			}
		}
	}

	return false;
}

// return 1 on hit and 0 when no hit
float raycast_tl_bvh_anyhit(const vec3 ray_origin, const vec3 ray_dir, const float max_ray_dist) {

	Ray ray_ws;
	ray_ws.origin = ray_origin;
	ray_ws.dir = ray_dir;
	ray_ws.inv_dir = 1.0f / ray_dir;

	uint stack[TOP_LEVEL_STACK_SIZE];
	int stack_ptr = 0;

	// Initialize to root node;
	//BvhNode node = _tl_bvh_nodes[0];
	uint node_idx = 0;

	while (true) {

		if(_tl_bvh_nodes[node_idx].count > 0) { // if node is leaf

			for (uint i = 0; i < _tl_bvh_nodes[node_idx].count; i++){

				uint draw_index = _tl_bvh_draw_indecies[_tl_bvh_nodes[node_idx].left_first + i];
				mat4 inv_mat = _inv_matrix_buffer[draw_index];
				

				Ray ray_os;
				ray_os.origin.xyz = (inv_mat * vec4(ray_ws.origin.xyz, 1.0f)).xyz;
				ray_os.dir.xyz    = (inv_mat * vec4(ray_ws.dir.xyz, 0.0f)).xyz;
				ray_os.inv_dir    = 1.0f / ray_os.dir;

				DrawInfo draw_info = _draw_info_buffer[draw_index];
				BvhNode bl_root = _global_bl_bvh_nodes[draw_info.bl_bvh_root_offset];

				if (raycast_bl_bvh_anyhit(draw_info, ray_os, max_ray_dist)) {
					return 1.0f;
				}
			}

			if (stack_ptr == 0) {
				break;
			} else {
				node_idx = stack[--stack_ptr];
			}

			continue;
		}

		uvec2 childs = uvec2(_tl_bvh_nodes[node_idx].left_first, _tl_bvh_nodes[node_idx].left_first + 1);

		vec2 dists = vec2(0.0f);
		dists.x = ray_intersects_aabb_dist(ray_ws, _tl_bvh_nodes[childs.x].aabb_min, _tl_bvh_nodes[childs.x].aabb_max, max_ray_dist);
		dists.y = ray_intersects_aabb_dist(ray_ws, _tl_bvh_nodes[childs.y].aabb_min, _tl_bvh_nodes[childs.y].aabb_max, max_ray_dist);

		if (dists.x > dists.y){
			// Swap;
			childs.xy = childs.yx;
			dists.xy = dists.yx;
		}

		if (dists.x < RAY_FLOAT_INF) { 
			// closer dist if was hit procced with closer child first
			// and push further child on stack if it was also hit.
			node_idx = childs.x;
			if (dists.y < RAY_FLOAT_INF) {
				stack[stack_ptr++] = childs.y;
			}
		} else {

			if (stack_ptr == 0){
				break;
			} else {
				node_idx = stack[--stack_ptr];
			}
		}
	}

	return 0.0f;
}



#endif // RAYTRACING_GLSL