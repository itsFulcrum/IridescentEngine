#ifndef RES_MATRIX_BUFFER
#define RES_MATRIX_BUFFER


#ifndef RES_MATRIX_BUFFER_SET
#define RES_MATRIX_BUFFER_SET 0
#endif

#ifndef RES_MATRIX_BUFFER_BIND
#define RES_MATRIX_BUFFER_BIND 0
#endif


// Set and binding of 0 work for all vertex shaders atm.
layout (std140, set=RES_MATRIX_BUFFER_SET, binding=RES_MATRIX_BUFFER_BIND) readonly buffer matrix_buffer {
    mat4 data[];
} _matrix_buffer;

#endif