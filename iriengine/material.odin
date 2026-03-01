package iri

import "core:hash"

MaterialShaderType :: enum u8 {
	NONE 	= 0,
	PBR 	= 1,
	UNLIT 	= 2,
	CUSTOM,
}

AlphaBlendMode :: enum u8 {
	Opaque 	= 0,
	Clip 	= 1,
	Hashed 	= 2,
	Blend 	= 3,
}

BlendConfig :: struct {
	// 714025 possible combinations
    src_color_blendfactor:   BlendFactor,	// The value to be multiplied by the source RGB value.
    dst_color_blendfactor:   BlendFactor,	// The value to be multiplied by the destination RGB value.
    color_blend_op:          BlendOp,    	// The blend operation for the RGB components.
    src_alpha_blendfactor:   BlendFactor,	// The value to be multiplied by the source alpha.
    dst_alpha_blendfactor:   BlendFactor,	// The value to be multiplied by the destination alpha.
    alpha_blend_op:          BlendOp,    	// The blend operation for the alpha component.
}

create_default_blend_config :: proc () -> BlendConfig {
	return BlendConfig{
		src_color_blendfactor = BlendFactor.SRC_ALPHA,
		dst_color_blendfactor = BlendFactor.ONE_MINUS_SRC_ALPHA,
		src_alpha_blendfactor = BlendFactor.SRC_ALPHA,
		dst_alpha_blendfactor = BlendFactor.ONE_MINUS_SRC_ALPHA,
		color_blend_op = BlendOp.ADD,
		alpha_blend_op = BlendOp.ADD,
	};
}

RenderTechniqueHash :: u32

RenderTechniqueFlags :: distinct bit_set[RenderTechniqueFlag]
RenderTechniqueFlag :: enum u8 {
	EnableDepthTest,
	EnableDepthWrite,
	Wireframe,
}
RenderTechnique :: struct {
	// 34273200 possible combinations
	alpha_mode   : AlphaBlendMode,
	blend_config : BlendConfig, // Only If alpha_mode == Blend
	cull_mode    : CullMode,
	flags : RenderTechniqueFlags,
}

create_default_render_technique :: proc() -> RenderTechnique {

	return RenderTechnique{
		alpha_mode = AlphaBlendMode.Opaque,
		blend_config = create_default_blend_config(),
		cull_mode = CullMode.Back,
		flags = {.EnableDepthTest, .EnableDepthWrite}
	}	
}

hash_render_technique :: proc(tech : RenderTechnique) -> RenderTechniqueHash {

	data : [9]u8;
	
	data[0] = transmute(u8)tech.flags;
	data[1] = cast(u8)tech.cull_mode;
	// for sake of pipline hash creation 'Hased' alpha mode is equal to 'Clip' mode. they should use the same pipeline.
	data[2] = tech.alpha_mode == .Hashed ? cast(u8)AlphaBlendMode.Clip : cast(u8)tech.alpha_mode;

	if tech.alpha_mode == .Blend {
		data[3]  = cast(u8)tech.blend_config.color_blend_op;
		data[4]  = cast(u8)tech.blend_config.alpha_blend_op;
		data[5]  = cast(u8)tech.blend_config.src_color_blendfactor;
		data[6]  = cast(u8)tech.blend_config.dst_color_blendfactor;
		data[7]  = cast(u8)tech.blend_config.src_alpha_blendfactor;
		data[8]  = cast(u8)tech.blend_config.dst_alpha_blendfactor;
	}

	return hash.fnv32a(data[:]);
}


Material :: struct {

	render_technique : RenderTechnique,

	variant : MaterialVariant,
}

MaterialVariant :: union {
	PbrMaterialData,
	UnlitMaterialData,
	CustomMaterialVariant
}

CustomMaterialVariant :: struct {
	vert_shader : ShaderID,
	frag_shader : ShaderID,
}


PbrMaterialData :: struct {
	albedo_color : [3]f32,
	emissive_color : [3]f32,
	emissive_strength : f32,
	roughness : f32,
	metallic : f32,

	// TODO: remove
	alpha_value : f32,
	//alpha_mode : AlphaBlendMode,
}


PbrMaterialDataGPU :: struct #align(16) {
	albedo_color: [4]f32,
	emissive_color : [4]f32, // .w contains emissive strength
	roughness   : f32,
	metallic    : f32,
	alpha_value : f32,
	alpha_mode  : u32,
}

@(private="package")
material_convert_PbrMaterialData_to_PbrMaterialDataGPU :: proc(mat : ^PbrMaterialData, alpha_mode : AlphaBlendMode) -> (out : PbrMaterialDataGPU) {

	out.albedo_color = [4]f32{mat.albedo_color.r,mat.albedo_color.g,mat.albedo_color.b, 1};
	out.emissive_color = [4]f32{mat.emissive_color.r, mat.emissive_color.g, mat.emissive_color.b, mat.emissive_strength};
	out.roughness = mat.roughness;
	out.metallic = mat.metallic;
	// TODO: remove
	out.alpha_value = mat.alpha_value;
	out.alpha_mode  = cast(u32)alpha_mode;

	return out;
}


UnlitMaterialData :: struct {

	albedo_color : [3]f32,
	// TODO: remove
	alpha_value : f32,
	//alpha_mode : AlphaBlendMode,
}

UnlitMaterialDataGPU :: struct #align(16) {
	albedo_color : [3]f32,
	alpha_value  : f32,
	alpha_mode   : u32,

	padding_1    : u32,
	padding_2    : u32,
	padding_3    : u32,
}

@(private="package")
material_convert_UnlitMaterialData_to_UnlitMaterialDataGPU :: proc(mat : ^UnlitMaterialData, alpha_mode : AlphaBlendMode) -> (out : UnlitMaterialDataGPU) {

	out.albedo_color   = mat.albedo_color;
	out.alpha_value = mat.alpha_value;
	out.alpha_mode  = cast(u32)alpha_mode;

	return out;
}

// TODO:
material_data_set_defaults :: proc(mat : ^Material){

	switch &m in mat.variant {
		case PbrMaterialData:
			m.albedo_color = {0.8,0.8,0.8};
			m.emissive_color =  {0.0,0.0,0.0};
			m.emissive_strength = 0.0;
			m.roughness = 0.5;
			m.metallic = 0.0;
			m.alpha_value = 1.0;

		case UnlitMaterialData:
			m.albedo_color = {0.8,0.8,0.8};
			m.alpha_value = 1.0;
		case CustomMaterialVariant:
			// Idk yet if we want to set anything here..
	}

	
	//mat.normal_scale = 1.0;
}