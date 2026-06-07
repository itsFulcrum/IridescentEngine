#ifndef RES_DRAW_INFO_BUFFER
#define RES_DRAW_INFO_BUFFER


#ifndef RES_DRAW_INFO_BUFFER_SET
#define RES_DRAW_INFO_BUFFER_SET 0
#endif

#ifndef RES_DRAW_INFO_BUFFER_BIND
#define RES_DRAW_INFO_BUFFER_BIND 0
#endif


struct DrawInfo {
    uint bl_bvh_root_offset;
    uint global_indecies_offset;
    uint global_vertecies_offset;
    uint _padding;
};


layout (std140, set=RES_DRAW_INFO_BUFFER_SET, binding=RES_DRAW_INFO_BUFFER_BIND) readonly buffer draw_info_buffer {
    DrawInfo _draw_info_buffer[];
};

#endif