#ifndef RES_GLOBAL_INDEX_BUFFER
#define RES_GLOBAL_INDEX_BUFFER


#ifndef RES_GLOBAL_INDEX_BUFFER_SET
#define RES_GLOBAL_INDEX_BUFFER_SET 0
#endif

#ifndef RES_GLOBAL_INDEX_BUFFER_BIND
#define RES_GLOBAL_INDEX_BUFFER_BIND 0
#endif

// @NOTE:!! layout = std430. base alignement 4 bytes not 16. so we can use a uint array.
layout (std430, set=RES_GLOBAL_INDEX_BUFFER_SET, binding=RES_GLOBAL_INDEX_BUFFER_BIND) readonly buffer global_index_buffer {
    uint _global_index_buffer[]; // u32
};

#endif