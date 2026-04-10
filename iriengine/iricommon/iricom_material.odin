package iricom

import "core:hash"
import "core:strings"

MaterialID :: u32

MaterialShaderType :: enum u8 {
	None 	= 0, // since material has union variant which can be nil we must kinda keep the 'None' type..
	Pbr,
	Unlit,
	Custom,
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
	blend_config : BlendConfig, 	// ignored if alpha_mode != .Blend
	cull_mode    : CullMode,
	flags : RenderTechniqueFlags,
}

Material :: struct {
	name : string,
	render_technique : RenderTechnique,
	variant : MaterialVariant,
}

MaterialVariant :: union {
	PbrMaterialVariant,
	UnlitMaterialVariant,
	CustomMaterialVariant
}

PbrMaterialVariant :: struct {
	albedo_color : [3]f32,
	emissive_color : [3]f32,
	emissive_strength : f32,
	roughness : f32,
	metallic : f32,

	alpha_value : f32,
}

PbrMaterialDataGPU :: struct #align(16) {
	albedo_color: [4]f32,
	emissive_color : [4]f32, // .w contains emissive strength
	roughness   : f32,
	metallic    : f32,
	alpha_value : f32,
	alpha_mode  : u32,
}

UnlitMaterialVariant :: struct {
	albedo_color : [3]f32,
	alpha_value : f32,
}

UnlitMaterialDataGPU :: struct #align(16) {
	albedo_color : [3]f32,
	alpha_value  : f32,

	alpha_mode   : u32,
	padding_1    : u32,
	padding_2    : u32,
	padding_3    : u32,
}

CustomMaterialVariant :: struct {
	vert_shader : ShaderID,
	frag_shader : ShaderID,
}

render_technique_create_default_opaque :: proc() -> RenderTechnique {

	return RenderTechnique{
		alpha_mode = AlphaBlendMode.Opaque,
		blend_config = blend_config_create_default(),
		cull_mode = CullMode.Back,
		flags = {.EnableDepthTest, .EnableDepthWrite}
	}
}

render_technique_calc_hash :: proc(tech : RenderTechnique) -> RenderTechniqueHash {

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

blend_config_create_default :: proc () -> BlendConfig {
	return BlendConfig{
		src_color_blendfactor = BlendFactor.SRC_ALPHA,
		dst_color_blendfactor = BlendFactor.ONE_MINUS_SRC_ALPHA,
		src_alpha_blendfactor = BlendFactor.SRC_ALPHA,
		dst_alpha_blendfactor = BlendFactor.ONE_MINUS_SRC_ALPHA,
		color_blend_op = BlendOp.ADD,
		alpha_blend_op = BlendOp.ADD,
	};
}

pbr_material_variant_create_default :: proc() -> PbrMaterialVariant {
	return PbrMaterialVariant{
		albedo_color = {0.8,0.8,0.8},
		emissive_color =  {0.0,0.0,0.0},
		emissive_strength = 0.0,
		roughness = 0.5,
		metallic = 0.0,
		alpha_value = 1.0,
	}
}

PbrMaterialVariant_to_PbrMaterialDataGPU :: proc(mat : ^PbrMaterialVariant, alpha_mode : AlphaBlendMode) -> (out : PbrMaterialDataGPU) {
	out.albedo_color   	= [4]f32{mat.albedo_color.r,mat.albedo_color.g,mat.albedo_color.b, 1};
	out.emissive_color 	= [4]f32{mat.emissive_color.r, mat.emissive_color.g, mat.emissive_color.b, mat.emissive_strength};
	out.roughness 		= mat.roughness;
	out.metallic 		= mat.metallic;
	out.alpha_value = mat.alpha_value;
	out.alpha_mode  = cast(u32)alpha_mode;
	return out;
}

unlit_material_variant_create_default :: proc() -> UnlitMaterialVariant {
	return UnlitMaterialVariant{
		albedo_color = {0.8,0.8,0.8},
		alpha_value = 1.0,
	}
}

UnlitMaterialVariant_to_UnlitMaterialDataGPU :: proc(mat : ^UnlitMaterialVariant, alpha_mode : AlphaBlendMode) -> (out : UnlitMaterialDataGPU) {

	out.albedo_color   	= mat.albedo_color;
	out.alpha_value 	= mat.alpha_value;
	out.alpha_mode  	= cast(u32)alpha_mode;
	return out;
}

material_get_type :: proc(mat : ^Material) -> MaterialShaderType {
	
	if mat.variant == nil {
		return .None;
	}

	switch &m in mat.variant {
		case PbrMaterialVariant: 	return .Pbr;
		case UnlitMaterialVariant: 	return .Unlit;
		case CustomMaterialVariant: return .Custom;
	}

	return .None;
}

material_create_default_pbr :: proc(name : string = "UnnamedMaterial") -> Material {
	mat : Material;
	mat.name = strings.clone(name, context.allocator);
	mat.variant = pbr_material_variant_create_default();
	mat.render_technique = render_technique_create_default_opaque();
	return mat;
}

material_create_default_unlit :: proc(name : string = "UnnamedMaterial") -> Material {
	mat : Material;
	mat.name = strings.clone(name, context.allocator);
	mat.variant = unlit_material_variant_create_default();
	mat.render_technique = render_technique_create_default_opaque();
	return mat;
}

material_set_default_values :: proc(mat : ^Material){
	
	mat.render_technique = render_technique_create_default_opaque();

	switch &m in mat.variant {
		case PbrMaterialVariant:   m = pbr_material_variant_create_default();
		case UnlitMaterialVariant: m = unlit_material_variant_create_default();
		case CustomMaterialVariant: // Idk yet if we want to set anything here..
	}
}

material_free_contents :: proc(mat : ^Material){
	if mat == nil {
		return
	}
	if len(mat.name) > 0 {
		delete(mat.name);
	}
}