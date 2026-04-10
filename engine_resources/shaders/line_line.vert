#version 450 core

layout(set=1,binding=0) uniform global_vertex_ubo {
	mat4 view_mat;
	mat4 proj_mat;
	mat4 view_proj_mat;
} global_ubo;

layout(set=1,binding=1) uniform mesh_vertex_ubo {
	mat4 model_mat;
} mesh_ubo;


void main() {

	// World pos is directly written into the matrix since for line all we need is 2 positons.
	vec4 pos_ws = mesh_ubo.model_mat[gl_VertexIndex];

   	vec4 pos_cs = global_ubo.view_proj_mat * vec4(pos_ws.xyz, 1.0f);

	gl_Position = pos_cs;
}