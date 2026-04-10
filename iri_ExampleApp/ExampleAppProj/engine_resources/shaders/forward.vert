#version 450 core

// Vertex Attribute Data
layout (location=0) in vec3 a_pos;

#ifdef VERT_LAYOUT_MINIMAL
layout (location=1) in vec4 a_qtangent;
layout (location=2) in vec2 a_texcoord_0;
#endif 

#ifdef VERT_LAYOUT_STANDARD
layout (location=1) in vec4 a_qtangent;
layout (location=2) in vec2 a_texcoord_0;
layout (location=3) in vec4 a_color_0;
#endif 

#ifdef VERT_LAYOUT_EXTENDED
layout (location=1) in vec4 a_qtangent;
layout (location=2) in vec2 a_texcoord_0;
layout (location=3) in vec2 a_texcoord_1;
layout (location=4) in vec4 a_color_0;
layout (location=5) in vec4 a_color_1;
#endif

#include "../shader_lib/mathy.glsl"

// Uniform Data
// in SDL GPU uniform buffers in vertex shader must be bound to 'set=1' in fragment shader it is 'set=3'
// https://wiki.libsdl.org/SDL3/SDL_CreateGPUShader

#include "../shader_lib/resources/resource_matrix_buffer.glsl"

layout(set=1,binding=0) uniform global_vertex_ubo {
	mat4 view_mat;
	mat4 proj_mat;
	mat4 view_proj_mat;
} _global_vertex;

layout(set=1,binding=1) uniform draw_instance_vertex_ubo {
	uint drawable_index;
	uint padding1;
	uint padding2;
	uint padding3;
} _draw_inst;

// Output Vertex Data
layout (location = 0) out vertex_data {	
	vec3 position_ws;
	vec3 normal_ws;
	vec4 color_0;
	vec4 color_1;
	vec2 uv_0;
	vec2 uv_1;
	mat3 tangent_to_world_mat;
	mat3 tbn_mat;
} vert_data;

void decode_qtangent(vec4 q, out vec3 T, out vec3 B, out vec3 N) {

    q = normalize(q);

    float x2 = q.x + q.x;
    float y2 = q.y + q.y;
    float z2 = q.z + q.z;

    float xx = q.x * x2;
    float yy = q.y * y2;
    float zz = q.z * z2;
    float xy = q.x * y2;
    float xz = q.x * z2;
    float yz = q.y * z2;
    float wx = q.w * x2;
    float wy = q.w * y2;
    float wz = q.w * z2;

    T = vec3(1.0f - (yy + zz), xy + wz, xz - wy);
    B = vec3(xy - wz, 1.0f - (xx + zz), yz + wx);
    N = vec3(xz + wy, yz - wx, 1.0f - (xx + yy));
}


void main() {

	mat4 world_mat = _matrix_buffer.data[_draw_inst.drawable_index];

	vec4 position_ws = world_mat * vec4(a_pos.xyz, 1.0f);

	vec4 position_cs = _global_vertex.view_proj_mat * vec4(position_ws.xyz, 1.0f);

	gl_Position = position_cs;
	
	mat3 normal_mat = adjoint(mat3(world_mat));

	//vec3 normal_os  = oct_decode(a_normal.xy);
	//vec3 tangent_os = oct_decode(a_tangent.xy);
	//vec3 bitangent_os = cross(normal_os, tangent_os) * a_tangent.z; // tan.z sign bit encodes handedness of tangent space

	// TODO: clean this whole q tangent stuff up.

	// decode qTangent
	// we dont do 16-bit SNORM quatization right now..
	// float4 qtangent = normalize( input.qtangent ); //Needed because of the quantization caused by 16-bit SNORM
	//vec4 qtan = normalize(a_qtangent);

	vec3 T = vec3(0.0f);//quat_rotate(qtan, vec3(1.0, 0.0, 0.0));
    vec3 B = vec3(0.0f);//quat_rotate(qtan, vec3(0.0, 1.0, 0.0));
    vec3 N = vec3(0.0f);//quat_rotate(qtan, vec3(0.0, 0.0, 1.0));

    decode_qtangent(a_qtangent, T,B,N);
	
	vec3 tangent_ws   = normalize(vec3(normal_mat * T));
  	vec3 bitangent_ws = normalize(vec3(normal_mat * B));
	vec3 normal_ws    = normalize(vec3(normal_mat * N));
	

  	vert_data.tbn_mat = mat3(tangent_ws, bitangent_ws, normal_ws);
  	// TODO: we dont need this i belive and if so we should prob do it in fragment shader.
	vert_data.tangent_to_world_mat = adjoint(vert_data.tbn_mat);

	vert_data.position_ws = position_ws.xyz;
	vert_data.normal_ws = normal_ws;

//	vert_data.color_0.xyz = tangent_os.xyz ;
//	vert_data.color_0.xyz = T;
	
	//vert_data.color_0.xyz = B.xyz;
	
	//vert_data.color_0.xyz = normal_os.xyz;
	//vert_data.color_0.xyz = N.xyz;

	// TODO: pass viewspace pos seperatily or do shadowmap cascade sampling different..
	vert_data.color_0 = _global_vertex.view_mat  * vec4(position_ws.xyz, 1.0f);
	//vert_data.color_0 = a_color_0 ;
	vert_data.uv_0 = a_texcoord_0;
	
	#ifdef VERT_LAYOUT_STANDARD
		vert_data.uv_1    = vec2(0.0f);
		vert_data.color_0 = a_color_0;
		vert_data.color_1 = vec4(1.0f);
	#endif

	#ifdef VERT_LAYOUT_EXTENDED
		vert_data.uv_1    = a_texcoord_1;
		vert_data.color_0 = a_color_0;
		vert_data.color_1 = a_color_1;
	#endif
	/*
	*/
}