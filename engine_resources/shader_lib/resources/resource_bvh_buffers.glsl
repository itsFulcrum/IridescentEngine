#ifndef RES_BVH_BUFFERS
#define RES_BVH_BUFFERS


#ifndef RES_TL_BVH_DRAW_INDECIES_BUFFER_SET
#define RES_TL_BVH_DRAW_INDECIES_BUFFER_SET 0
#endif
#ifndef RES_TL_BVH_DRAW_INDECIES_BUFFER_BIND
#define RES_TL_BVH_DRAW_INDECIES_BUFFER_BIND 0
#endif

#ifndef RES_TL_BVH_NODES_BUFFER_SET
#define RES_TL_BVH_NODES_BUFFER_SET 0
#endif
#ifndef RES_TL_BVH_NODES_BUFFER_BIND
#define RES_TL_BVH_NODES_BUFFER_BIND 1
#endif


#ifndef RES_GLOBAL_BL_BVH_NODES_BUFFER_SET
#define RES_GLOBAL_BL_BVH_NODES_BUFFER_SET 0
#endif
#ifndef RES_GLOBAL_BL_BVH_NODES_BUFFER_BIND
#define RES_GLOBAL_BL_BVH_NODES_BUFFER_BIND 2
#endif

struct BvhNode { // 32 bytes
    vec3 aabb_min;
    uint left_first; // if leaf, this is first draw/triangle index. if not a leaf this is the left child index. right child index is left_first + 1
    vec3 aabb_max;
    uint count;      // draw/triangle count. if > 0 node is a leaf.
};

// @Note: Drawable indexes which are indexable by TL Bvh leaf nodes. 
// A Top Level Leaf node left_first + count define the range drawable_indexes in this buffer
// e.g. uint first_drawable_leaf = _frame_tl_bvh_draw_indecies[node.left_first]
// e.g. uint last_drawable_leaf  = _frame_tl_bvh_draw_indecies[node.left_first + node.count]
// @NOTE:!! layout = std430. base alignement 4 bytes not 16. so we can use a uint array.
layout (std430, set=0, binding=4) readonly buffer tl_bvh_draw_indecies {
    uint _tl_bvh_draw_indecies[];
};


// Top Level Acceleration Structure
layout (std140, set=RES_TL_BVH_NODES_BUFFER_SET, binding=RES_TL_BVH_NODES_BUFFER_BIND) readonly buffer global_tl_bvh_buffer {
    BvhNode _tl_bvh_nodes[];
};

// Bottom Level Acceleration Structures. -> All bottom bvh's for each mesh are in this large buffer and we need additional per mesh offsets
// to index it.
layout (std140, set=RES_GLOBAL_BL_BVH_NODES_BUFFER_SET, binding=RES_GLOBAL_BL_BVH_NODES_BUFFER_BIND) readonly buffer global_bl_bvh_buffer {
    BvhNode _global_bl_bvh_nodes[];
};

#endif