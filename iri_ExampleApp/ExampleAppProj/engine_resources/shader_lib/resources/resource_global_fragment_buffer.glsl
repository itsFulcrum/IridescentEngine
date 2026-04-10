#ifndef RES_GLOBAL_FRAG_BUFFER_GLSL
#define RES_GLOBAL_FRAG_BUFFER_GLSL

#ifndef RES_GLOBAL_FRAG_BUFFER_SET
#define RES_GLOBAL_FRAG_BUFFER_SET 2
#endif

#ifndef RES_GLOBAL_FRAG_BUFFER_BIND
#define RES_GLOBAL_FRAG_BUFFER_BIND 0
#endif

layout (std140, set=RES_GLOBAL_FRAG_BUFFER_SET, binding = RES_GLOBAL_FRAG_BUFFER_BIND) readonly buffer global_fragment {
    vec3 camera_pos_ws;
	float time_sec;

	vec3 camera_dir_ws;
	float near_plane;
	
	uvec2 frame_size;
	float far_plane;
	float cascade_frust_split_1;
	
	float cascade_frust_split_2;
	float cascade_frust_split_3;
	float camera_exposure;
	float padding7;
} _global;


#endif