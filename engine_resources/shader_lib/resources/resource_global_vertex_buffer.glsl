#ifndef RES_GLOBAL_VERTEX_BUFFER
#define RES_GLOBAL_VERTEX_BUFFER


#ifndef RES_GLOBAL_VERTEX_BUFFER_SET
#define RES_GLOBAL_VERTEX_BUFFER_SET 0
#endif

#ifndef RES_GLOBAL_VERTEX_BUFFER_BIND
#define RES_GLOBAL_VERTEX_BUFFER_BIND 0
#endif

layout (std140, set=RES_GLOBAL_VERTEX_BUFFER_SET, binding=RES_GLOBAL_VERTEX_BUFFER_BIND) readonly buffer global_vertex_buffer {
    vec4 _global_vertex_buffer[];
};

#endif