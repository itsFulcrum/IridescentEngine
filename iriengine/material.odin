package iri

import iricom "iricommon"

MaterialShaderType 	:: iricom.MaterialShaderType

AlphaBlendMode 		:: iricom.AlphaBlendMode

BlendConfig 		:: iricom.BlendConfig
blend_config_create_default :: iricom.blend_config_create_default

RenderTechnique 	 :: iricom.RenderTechnique
RenderTechniqueHash  :: iricom.RenderTechniqueHash
RenderTechniqueFlags :: iricom.RenderTechniqueFlags
RenderTechniqueFlag  :: iricom.RenderTechniqueFlag

render_technique_create_default_opaque 	:: iricom.render_technique_create_default_opaque
render_technique_calc_hash 				:: iricom.render_technique_calc_hash

Material :: iricom.Material

MaterialVariant :: iricom.MaterialVariant

PbrMaterialVariant    :: iricom.PbrMaterialVariant
PbrMaterialDataGPU    :: iricom.PbrMaterialDataGPU
PbrMaterialVariant_to_PbrMaterialDataGPU :: iricom.PbrMaterialVariant_to_PbrMaterialDataGPU
pbr_material_variant_create_default      :: iricom.pbr_material_variant_create_default

UnlitMaterialVariant    :: iricom.UnlitMaterialVariant
UnlitMaterialDataGPU :: iricom.UnlitMaterialDataGPU
UnlitMaterialVariant_to_UnlitMaterialDataGPU :: iricom.UnlitMaterialVariant_to_UnlitMaterialDataGPU
unlit_material_variant_create_default :: iricom.unlit_material_variant_create_default

CustomMaterialVariant :: iricom.CustomMaterialVariant


material_get_type 				:: iricom.material_get_type
material_set_default_values 	:: iricom.material_set_default_values
material_create_default_pbr 	:: iricom.material_create_default_pbr
material_create_default_unlit 	:: iricom.material_create_default_unlit