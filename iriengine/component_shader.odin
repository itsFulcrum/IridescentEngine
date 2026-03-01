package iri

import sdl "vendor:sdl3"

CustomShaderComponent :: struct{
	using common : ComponentCommon,

	render_technique : RenderTechnique,
	
	_vert_shader : ^sdl.GPUShader,
	_frag_shader : ^sdl.GPUShader,

	_vert_buff_size : u32,
	_frag_buff_size : u32,
	_vert_buff_data : rawptr,
	_frag_buff_data : rawptr,
}

@(private="package")
comp_customshader_init :: proc (comp: ^CustomShaderComponent){
	if comp == nil {
		return;
	}

	#force_inline comp_customshader_set_defaults(comp);
}

@(private="package")
comp_customshader_deinit :: proc(comp: ^CustomShaderComponent){
	if comp == nil {
		return;
	}

	#force_inline comp_customshader_set_defaults(comp);
}


comp_customshader_set_defaults :: proc(comp : ^CustomShaderComponent){
	if comp == nil {
		return;
	}

	comp.render_technique = create_default_render_technique();

}


// =====================================================================
// Component procedures
// =====================================================================


comp_custom_shader_assign_fragment_buffer :: proc(comp : ^CustomShaderComponent, data : rawptr, byte_size : u32){

}