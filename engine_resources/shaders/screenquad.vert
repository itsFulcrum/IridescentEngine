#version 450 core


// Output Vertex Data
layout (location = 0) out vertex_data {
	vec2 uv;
} vert_data;


//Static Screen Quad Vertex buffer
const float vertex_buffer[12] = {
	// pos.xy, pos.xy, pos.xy ... 
    // triangle 1
    -1.0f, -1.0f,
     1.0f,  1.0f,
    -1.0f,  1.0f,
    // triangle 2
    -1.0f, -1.0f,
     1.0f, -1.0f,
     1.0f,  1.0f
 };

void main() {

	// The vertex of the screenquad we are currently processing.
	// a screenquad has 6 vertecies.
	const uint vertex = gl_VertexIndex % 6;

    // for a quad we do a trick here and just grab the vertex data inside the shader directly
   	const vec2 vert_pos = vec2(vertex_buffer[vertex * 2], vertex_buffer[vertex * 2 + 1]);
   

	// Flip y axis and Map from -1..1 to 0..1 range 
	// equivalent to: vert_pos.xy * vec2(1.0f, -1.0f) / 2.0f + 0.5f
	vert_data.uv = vert_pos.xy * vec2(0.5f, -0.5f) + 0.5f; 

	// Assign Vertex Data
	gl_Position = vec4(vert_pos.xy, 0.0f , 1.0f);

}