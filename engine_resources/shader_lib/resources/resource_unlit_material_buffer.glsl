#ifndef RES_UNLIT_MATERIAL_BUFFER_GLSL
#define RES_UNLIT_MATERIAL_BUFFER_GLSL


#ifndef RES_UNLIT_BUF_SET
#define RES_UNLIT_BUF_SET 2
#endif

#ifndef RES_UNLIT_BUF_BIND
#define RES_UNLIT_BUF_BIND 1
#endif

struct UnlitMaterial {
	vec3  albedo_color;
	float alpha_value;
	uint  alpha_mode;

	uint padding1;
	uint padding2;
	uint padding3;
};


layout (std140, set=RES_UNLIT_BUF_SET, binding=RES_UNLIT_BUF_BIND) readonly buffer unlit_material_buffer {
    UnlitMaterial _unlit_materials[];
};


#endif // 