#version 450 core


// Output Vertex Data
layout (location = 0) out vertex_data {
	vec3 position_os;
	float padding1;
	vec3 position_ws;
	float padding2;
//	vec2 uv;
} vert_data;


layout(set=1,binding=0) uniform global_vertex_ubo {
	mat4 view_mat;
	mat4 proj_mat;
	mat4 view_proj_mat;
} global_ubo;

layout(set=1,binding=1) uniform mesh_vertex_ubo {
	mat4 model_mat;
} mesh_ubo;


const float vertex_buffer[36 * 3] = {
	//pos-xyz  				| norm-xyz  			| tan-xyz
	 -1.0f,-1.0f, 1.0f,   //-1.0f, 0.0f, 0.0f,   0.0f,1.0f,0.0f,
	 -1.0f, 1.0f, 1.0f,   //-1.0f, 0.0f, 0.0f,   0.0f,1.0f,0.0f,
	 -1.0f, 1.0f,-1.0f,   //-1.0f, 0.0f, 0.0f,   0.0f,1.0f,0.0f,
	 -1.0f,-1.0f, 1.0f,   //-1.0f, 0.0f, 0.0f,   0.0f,1.0f,0.0f,
	 -1.0f, 1.0f,-1.0f,   //-1.0f, 0.0f, 0.0f,   0.0f,1.0f,0.0f,
	 -1.0f,-1.0f,-1.0f,   //-1.0f, 0.0f, 0.0f,   0.0f,1.0f,0.0f,
	 -1.0f,-1.0f,-1.0f,   // 0.0f, 0.0f,-1.0f,   0.0f,1.0f,0.0f,
	 -1.0f, 1.0f,-1.0f,   // 0.0f, 0.0f,-1.0f,   0.0f,1.0f,0.0f,
	  1.0f, 1.0f,-1.0f,   // 0.0f, 0.0f,-1.0f,   0.0f,1.0f,0.0f,
	 -1.0f,-1.0f,-1.0f,   // 0.0f, 0.0f,-1.0f,   0.0f,1.0f,0.0f,
	  1.0f, 1.0f,-1.0f,   // 0.0f, 0.0f,-1.0f,   0.0f,1.0f,0.0f,
	  1.0f,-1.0f,-1.0f,   // 0.0f, 0.0f,-1.0f,   0.0f,1.0f,0.0f,
	  1.0f,-1.0f,-1.0f,   // 1.0f, 0.0f, 0.0f,   0.0f,1.0f,0.0f,
	  1.0f, 1.0f,-1.0f,   // 1.0f, 0.0f, 0.0f,   0.0f,1.0f,0.0f,
	  1.0f, 1.0f, 1.0f,   // 1.0f, 0.0f, 0.0f,   0.0f,1.0f,0.0f,
	  1.0f,-1.0f,-1.0f,   // 1.0f, 0.0f, 0.0f,   0.0f,1.0f,0.0f,
	  1.0f, 1.0f, 1.0f,   // 1.0f, 0.0f, 0.0f,   0.0f,1.0f,0.0f,
	  1.0f,-1.0f, 1.0f,   // 1.0f, 0.0f, 0.0f,   0.0f,1.0f,0.0f,
	  1.0f,-1.0f, 1.0f,   // 0.0f, 0.0f, 1.0f,   0.0f,1.0f,0.0f,
	  1.0f, 1.0f, 1.0f,   // 0.0f, 0.0f, 1.0f,   0.0f,1.0f,0.0f,
	 -1.0f, 1.0f, 1.0f,   // 0.0f, 0.0f, 1.0f,   0.0f,1.0f,0.0f,
	  1.0f,-1.0f, 1.0f,   // 0.0f, 0.0f, 1.0f,   0.0f,1.0f,0.0f,
	 -1.0f, 1.0f, 1.0f,   // 0.0f, 0.0f, 1.0f,   0.0f,1.0f,0.0f,
	 -1.0f,-1.0f, 1.0f,   // 0.0f, 0.0f, 1.0f,   0.0f,1.0f,0.0f,
	 -1.0f,-1.0f,-1.0f,   // 0.0f,-1.0f, 0.0f,   1.0f,0.0f,0.0f,
	  1.0f,-1.0f,-1.0f,   // 0.0f,-1.0f, 0.0f,   1.0f,0.0f,0.0f,
	  1.0f,-1.0f, 1.0f,   // 0.0f,-1.0f, 0.0f,   1.0f,0.0f,0.0f,
	 -1.0f,-1.0f,-1.0f,   // 0.0f,-1.0f, 0.0f,   1.0f,0.0f,0.0f,
	  1.0f,-1.0f, 1.0f,   // 0.0f,-1.0f, 0.0f,   1.0f,0.0f,0.0f,
	 -1.0f,-1.0f, 1.0f,   // 0.0f,-1.0f, 0.0f,   1.0f,0.0f,0.0f,
	  1.0f, 1.0f,-1.0f,   // 0.0f, 1.0f, 0.0f,  -1.0f,0.0f,0.0f,
	 -1.0f, 1.0f,-1.0f,   // 0.0f, 1.0f, 0.0f,  -1.0f,0.0f,0.0f,
	 -1.0f, 1.0f, 1.0f,   // 0.0f, 1.0f, 0.0f,  -1.0f,0.0f,0.0f,
	  1.0f, 1.0f,-1.0f,   // 0.0f, 1.0f, 0.0f,  -1.0f,0.0f,0.0f,
	 -1.0f, 1.0f, 1.0f,   // 0.0f, 1.0f, 0.0f,  -1.0f,0.0f,0.0f,
	  1.0f, 1.0f, 1.0f   // 0.0f, 1.0f, 0.0f,  -1.0f,0.0f,0.0f 
};


void main() {

	const uint offset = gl_VertexIndex % 36 * 3;
   	vec3 pos_os = vec3(vertex_buffer[offset + 0], vertex_buffer[offset + 1], vertex_buffer[offset + 2]);


   	vec4 pos_ws = mesh_ubo.model_mat * vec4(pos_os.xyz, 1.0f);
   	vert_data.position_os = pos_os;
   	vert_data.position_ws = pos_ws.xyz;

   	vec4 pos_cs = global_ubo.view_proj_mat * pos_ws;

	// Flip y axis and Map from -1..1 to 0..1 range 
	// equivalent to: vert_pos.xy * vec2(1.0f, -1.0f) / 2.0f + 0.5f
	//vert_data.uv = vert_pos.xy * vec2(0.5f, -0.5f) + 0.5f; 

	// Assign Vertex Data
	gl_Position = pos_cs;

}