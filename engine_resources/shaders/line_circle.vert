#version 450 core


layout(set=1,binding=0) uniform global_vertex_ubo {
	mat4 view_mat;
	mat4 proj_mat;
	mat4 view_proj_mat;
} global_ubo;

layout(set=1,binding=1) uniform mesh_vertex_ubo {
	mat4 model_mat;
} mesh_ubo;

#define PI 3.14159265359f

// This shader must be called with Linestrip primitive type and DrawPrimitves draw command with 33 vertecies, NOT 32 because 
// we want 1 extra vert to connect last line segment back to start of circle.
// We can certainly also pass num verts as a uniform to make segment count dynamic
#define NumVerts 32.0f 

void main() {

	const float radians_per_segment = 1.0f / NumVerts * (2.0f * PI); 

	float angle = float(gl_VertexIndex) * radians_per_segment;

	float x = sin(angle);
	float z = cos(angle);

   	vec4 pos_ws = mesh_ubo.model_mat * vec4(x, 0.0f,z, 1.0f);
   	vec4 pos_cs = global_ubo.view_proj_mat * pos_ws;

	gl_Position = pos_cs;

}