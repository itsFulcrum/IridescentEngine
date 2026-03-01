package iri

import "core:log"
import "core:hash"
import "core:strings"
import sdl "vendor:sdl3"

MaterialPipelineHash :: u32

// First 32 bits are enum 'DepthOnlyPipelineShaders' as u32, second 32 bits are RenderTechnique Hash
DepthOnlyPipelineHash :: u64 

PipelineShader :: enum {
    STANDARD_VERT,
    FORWARD_PBR_FRAG,
    FORWARD_UNLIT_FRAG,
    SKYBOX_VERT,
    SKYBOX_FRAG,
    SCREENQUAD_VERT,
    POST_COLOR_CORRECT_FRAG,
    DEAR_IMGUI_VERT,
    DEAR_IMGUI_FRAG,
    SWAPCHAIN_COMPOSIT_FRAG,
    UNIT_CUBE_VERT,
    UNLIT_BASIC_FRAG,
    DEPTH_ONLY_VERT,
    DEPTH_ONLY_FRAG,
    DEPTH_ONLY_ALPHATEST_FRAG,
    SHADOWMAP_VERT,
    SHADOWMAP_FRAG,
    SMAA_VERT,
    SMAA_EDGE_DETECTION_FRAG,
    SMAA_BLEND_WEIGHT_FRAG,
    SMAA_NEIGHBORHOOD_BLEND_FRAG,
}

MaterialPipelineShaders :: enum {
    PBR,
    UNLIT,
}

DEPTHONLY_PIPELINE_SHADER_SET_ALL :: DepthOnlyPipelineShadersSet{.DepthPre, .DepthPreAlphaTest, .Shadowmap, .ShadowmapAlphaTest}
DEPTHONLY_PIPELINE_SHADER_SET_EMPTY :: DepthOnlyPipelineShadersSet{}
DepthOnlyPipelineShadersSet :: bit_set[DepthOnlyPipelineShaders]
DepthOnlyPipelineShaders :: enum u32 {
    DepthPre = 0,
    DepthPreAlphaTest,
    Shadowmap,
    ShadowmapAlphaTest,   
}

CorePipeline :: enum u32 {
	Skybox,
    DearImGUI,
    PostColorCorrect,
    SWAPCHAIN_COMPOSIT,
    WIREFRAME_CUBE,
    SOLID_CUBE,
    SMAA_EDGE_DETECTION,
    SMAA_BLEND_WEIGHT,
    SMAA_NEIGHBORHOOD_BLEND,
}

PipelineManager :: struct {

    pipeline_shader_ids :   [PipelineShader]ShaderID,

	core_pipelines:         [CorePipeline]^sdl.GPUGraphicsPipeline,
    core_pipeline_configs:  [CorePipeline]PipelineConfig,

    vertex_buf_descriptor_infos : [VertexBufDescriptorType]VertexBufDescriptorInfo,
    
    material_pipeline_shader_combinations : [MaterialPipelineShaders]ShaderCombination,
    material_pipeline_cache : map[MaterialPipelineHash]^sdl.GPUGraphicsPipeline,
    
    depthonly_pipeline_shader_combinations : [DepthOnlyPipelineShaders]ShaderCombination,
    depthonly_pipeline_cache : map[DepthOnlyPipelineHash]^sdl.GPUGraphicsPipeline,
}


PipelineConfig :: struct {
    raster_fill_mode : FillMode,
    raster_cull_mode : CullMode,
    raster_disable_depth_clip : bool,

    // Depth Stencil
    enable_depth_test   : bool,
    enable_depth_write  : bool,
    enable_stencil_test : bool,
    depth_stencil_compare_op : CompareOp,

    // Color Render Target
    enable_blend: bool,
    col_target_src_color_blendfactor:   BlendFactor,          // The value to be multiplied by the source RGB value.
    col_target_dst_color_blendfactor:   BlendFactor,          // The value to be multiplied by the destination RGB value.
    col_target_color_blend_op:          BlendOp,              // The blend operation for the RGB components.
    col_target_src_alpha_blendfactor:   BlendFactor,          // The value to be multiplied by the source alpha.
    col_target_dst_alpha_blendfactor:   BlendFactor,          // The value to be multiplied by the destination alpha.
    col_target_alpha_blend_op:          BlendOp,              // The blend operation for the alpha component.
}

ShaderCombination :: struct{
    vert : PipelineShader,
    frag : PipelineShader,
    vert_variant : ShaderVariant,
    frag_variant : ShaderVariant,
}


VertexBufDescriptorType :: enum {
    None = 0,
    PositionOnly,
    LayoutMinimal,
    LayoutStandard,
    LayoutExtended,
    DearImgui,
}

VertexBufDescriptorInfo :: struct{
    type :       VertexBufDescriptorType,
    attributes:  [dynamic]sdl.GPUVertexAttribute,
    descriptors: [dynamic]sdl.GPUVertexBufferDescription,
}


// Note: Proc must be updated when adding new pipeline types
@(private="file")
pipe_manager_get_core_pipeline_shader_combination :: proc(pipeline : CorePipeline) -> ShaderCombination {

    switch pipeline {
        case .Skybox:                   return ShaderCombination{vert = .SKYBOX_VERT    , frag = .SKYBOX_FRAG};
        case .DearImGUI:                return ShaderCombination{vert = .DEAR_IMGUI_VERT, frag = .DEAR_IMGUI_FRAG};
        case .PostColorCorrect:         return ShaderCombination{vert = .SCREENQUAD_VERT, frag = .POST_COLOR_CORRECT_FRAG};
        case .SWAPCHAIN_COMPOSIT:       return ShaderCombination{vert = .SCREENQUAD_VERT, frag = .SWAPCHAIN_COMPOSIT_FRAG};
        case .WIREFRAME_CUBE:           return ShaderCombination{vert = .UNIT_CUBE_VERT , frag = .UNLIT_BASIC_FRAG};
        case .SOLID_CUBE:               return ShaderCombination{vert = .UNIT_CUBE_VERT , frag = .UNLIT_BASIC_FRAG};
        case .SMAA_EDGE_DETECTION:      return ShaderCombination{vert = .SMAA_VERT, frag = .SMAA_EDGE_DETECTION_FRAG    , vert_variant = {.SMAA_PASS_EDGE_DETECTION}};
        case .SMAA_BLEND_WEIGHT:        return ShaderCombination{vert = .SMAA_VERT, frag = .SMAA_BLEND_WEIGHT_FRAG      , vert_variant = {.SMAA_PASS_BLEND_WEIGHT}};
        case .SMAA_NEIGHBORHOOD_BLEND:  return ShaderCombination{vert = .SMAA_VERT, frag = .SMAA_NEIGHBORHOOD_BLEND_FRAG, vert_variant = {.SMAA_PASS_NEIGHBORHOOD_BLEND}};
    }

    panic("invalid codepath")
}

// Note: Proc must be updated when adding new pipeline types
@(private="file")
pipe_manager_get_core_pipeline_vertex_buf_descriptor_type :: proc(pipeline : CorePipeline) -> VertexBufDescriptorType{
    
    switch pipeline {
        case .Skybox:               return .PositionOnly;
        case .DearImGUI:            return .DearImgui;
        case .PostColorCorrect:     return .None;
        case .SWAPCHAIN_COMPOSIT:   return .None;
        case .WIREFRAME_CUBE:       return .None;
        case .SOLID_CUBE:           return .None;
        case .SMAA_EDGE_DETECTION:  return .None;
        case .SMAA_BLEND_WEIGHT:    return .None;
        case .SMAA_NEIGHBORHOOD_BLEND:    return .None;
    }

    panic("invalid codepath")
}

// Note: Proc must be updated when adding new pipeline types
@(private="file")
pipe_manager_get_core_pipeline_render_pass_type :: proc(pipeline: CorePipeline) -> RenderPassType{

    switch pipeline {
        case .Skybox:             return RenderPassType.Main;
        case .DearImGUI:          return RenderPassType.DebugGui;
        case .PostColorCorrect:   return RenderPassType.PostColorCorrect;
        case .SWAPCHAIN_COMPOSIT: return RenderPassType.SWAPCHAIN_COMPOSIT;
        case .WIREFRAME_CUBE:     return RenderPassType.Main;
        case .SOLID_CUBE:         return RenderPassType.Main;
        case .SMAA_EDGE_DETECTION:return RenderPassType.SMAA;
        case .SMAA_BLEND_WEIGHT:  return RenderPassType.SMAA;
        case .SMAA_NEIGHBORHOOD_BLEND:  return RenderPassType.SMAA;
    }

    // Invalid Codepath
    return RenderPassType{};
}

// Note: Proc must be updated when adding new pipeline types
@(private="file")
pipe_manager_create_core_pipeline_config :: proc(pipeline : CorePipeline) -> PipelineConfig {

    switch pipeline {
        case .Skybox:
            return PipelineConfig {
                    raster_fill_mode = FillMode.Fill,
                    raster_cull_mode = CullMode.Front,

                    // Depth Stencil
                    enable_depth_test   = true,
                    enable_depth_write  = true,
                    enable_stencil_test = false,
                    depth_stencil_compare_op = CompareOp.LESS_OR_EQUAL,

                    // Color Render Target
                    enable_blend = false,
                    col_target_color_blend_op        = BlendOp.ADD,                     // The blend operation for the RGB components.
                    col_target_src_color_blendfactor = BlendFactor.SRC_ALPHA,           // The value to be multiplied by the source RGB value.
                    col_target_dst_color_blendfactor = BlendFactor.ONE_MINUS_SRC_ALPHA, // The value to be multiplied by the destination RGB value.
                    col_target_alpha_blend_op        = BlendOp.ADD,                     // The blend operation for the alpha component.
                    col_target_src_alpha_blendfactor = BlendFactor.SRC_ALPHA,           // The value to be multiplied by the source alpha.
                    col_target_dst_alpha_blendfactor = BlendFactor.ONE_MINUS_SRC_ALPHA, // The value to be multiplied by the destination alpha.
            }

        case .DearImGUI:
            return PipelineConfig {
                    raster_fill_mode = FillMode.Fill,
                    raster_cull_mode = CullMode.None,

                    // Depth Stencil
                    enable_depth_test   = false,
                    enable_depth_write  = false,
                    enable_stencil_test = false,
                    depth_stencil_compare_op = CompareOp.ALWAYS,

                    // Color Render Target
                    enable_blend = true,
                    col_target_color_blend_op        = BlendOp.ADD,                      // The blend operation for the RGB components.
                    col_target_src_color_blendfactor = BlendFactor.SRC_ALPHA,           // The value to be multiplied by the source RGB value.
                    col_target_dst_color_blendfactor = BlendFactor.ONE_MINUS_SRC_ALPHA, // The value to be multiplied by the destination RGB value.
                    col_target_alpha_blend_op        = BlendOp.ADD,                     // The blend operation for the alpha component.
                    col_target_src_alpha_blendfactor = BlendFactor.ONE,           // The value to be multiplied by the source alpha.
                    col_target_dst_alpha_blendfactor = BlendFactor.ONE_MINUS_SRC_ALPHA, // The value to be multiplied by the destination alpha.
                }

        case .PostColorCorrect:
            return PipelineConfig {
                    raster_fill_mode = FillMode.Fill,
                    raster_cull_mode = CullMode.Back,

                    // Depth Stencil
                    enable_depth_test   = false,
                    enable_depth_write  = false,
                    enable_stencil_test = false,
                    depth_stencil_compare_op = CompareOp.ALWAYS,

                    // Color Render Target
                    enable_blend = false,
                    col_target_color_blend_op        = BlendOp.ADD,                      // The blend operation for the RGB components.
                    col_target_src_color_blendfactor = BlendFactor.SRC_ALPHA,           // The value to be multiplied by the source RGB value.
                    col_target_dst_color_blendfactor = BlendFactor.ONE_MINUS_SRC_ALPHA, // The value to be multiplied by the destination RGB value.
                    col_target_alpha_blend_op        = BlendOp.ADD,                     // The blend operation for the alpha component.
                    col_target_src_alpha_blendfactor = BlendFactor.SRC_ALPHA,           // The value to be multiplied by the source alpha.
                    col_target_dst_alpha_blendfactor = BlendFactor.ONE_MINUS_SRC_ALPHA, // The value to be multiplied by the destination alpha.
                }
        case .SWAPCHAIN_COMPOSIT:
            return PipelineConfig {
                    raster_fill_mode = FillMode.Fill,
                    raster_cull_mode = CullMode.Back,

                    // Depth Stencil
                    enable_depth_test   = false,
                    enable_depth_write  = false,
                    enable_stencil_test = false,
                    depth_stencil_compare_op = CompareOp.ALWAYS,

                    // Color Render Target
                    enable_blend = false,
            }
        case .WIREFRAME_CUBE:
            return PipelineConfig {
                    raster_fill_mode = FillMode.Line,
                    raster_cull_mode = CullMode.None,

                    // Depth Stencil
                    enable_depth_test   = true,
                    enable_depth_write  = true,
                    enable_stencil_test = false,
                    depth_stencil_compare_op = CompareOp.LESS_OR_EQUAL,

                    // Color Render Target
                    enable_blend = false,
            }
        case .SOLID_CUBE:
            return PipelineConfig {
                    raster_fill_mode = FillMode.Fill,
                    raster_cull_mode = CullMode.None,

                    // Depth Stencil
                    enable_depth_test   = true,
                    enable_depth_write  = true,
                    enable_stencil_test = false,
                    depth_stencil_compare_op = CompareOp.LESS_OR_EQUAL,

                    // Color Render Target
                    enable_blend = false,
            }
        case .SMAA_EDGE_DETECTION:
            return PipelineConfig {
                    raster_fill_mode = FillMode.Fill,
                    raster_cull_mode = CullMode.Back,
                }
        case .SMAA_BLEND_WEIGHT:
            return PipelineConfig {
                    raster_fill_mode = FillMode.Fill,
                    raster_cull_mode = CullMode.Back,
                }
        case .SMAA_NEIGHBORHOOD_BLEND:
            return PipelineConfig {
                    raster_fill_mode = FillMode.Fill,
                    raster_cull_mode = CullMode.Back,
                }
            case:
    }

    // Invalid codepath
    return PipelineConfig{}
}

@(private="file")
pipe_manager_create_vertex_buffer_descriptor_info :: proc(type : VertexBufDescriptorType) -> VertexBufDescriptorInfo {
    
    pm_append_attr_pos_only :: proc(array: ^[dynamic]sdl.GPUVertexAttribute){
        // Position
        pos : sdl.GPUVertexAttribute = sdl.GPUVertexAttribute{
            buffer_slot = 0,
            location = 0,
            format = sdl.GPUVertexElementFormat.FLOAT3,
            offset = 0,
        };
        append(array, pos);
    }

    pm_append_attr_layout_minimal :: proc(array: ^[dynamic]sdl.GPUVertexAttribute){

        // Position
        pos : sdl.GPUVertexAttribute = sdl.GPUVertexAttribute{
            buffer_slot = 0,
            location = 0,
            format = sdl.GPUVertexElementFormat.FLOAT3,
            offset = 0,
        };

        // Normal_Tangent_oct_encoded
        norm_tan : sdl.GPUVertexAttribute = sdl.GPUVertexAttribute{
            buffer_slot = 1,
            location = 1,
            format = sdl.GPUVertexElementFormat.FLOAT4,
            offset = cast(u32)offset_of(VertexDataMinimal, normal_tangent),
        };

        // Texcoord_0
        tc0 : sdl.GPUVertexAttribute = sdl.GPUVertexAttribute{
            buffer_slot = 1,
            location = 2,
            format = sdl.GPUVertexElementFormat.FLOAT2,
            offset = cast(u32)offset_of(VertexDataMinimal, texcoord_0),
        };

        append(array, pos);
        append(array, norm_tan);
        append(array, tc0);
    }

    pm_append_attr_layout_standard :: proc(array: ^[dynamic]sdl.GPUVertexAttribute){

        // Position
        pos : sdl.GPUVertexAttribute = sdl.GPUVertexAttribute{
            buffer_slot = 0,
            location = 0,
            format = sdl.GPUVertexElementFormat.FLOAT3,
            offset = 0,
        };

        // Normal_Tangent_oct_encoded
        norm_tan : sdl.GPUVertexAttribute = sdl.GPUVertexAttribute{
            buffer_slot = 1,
            location = 1,
            format = sdl.GPUVertexElementFormat.FLOAT4,
            offset = cast(u32)offset_of(VertexDataStandard, normal_tangent),
        };

        // Color_0
        col0 : sdl.GPUVertexAttribute = sdl.GPUVertexAttribute{
            buffer_slot = 1,
            location = 2,
            format = sdl.GPUVertexElementFormat.FLOAT4,
            offset = cast(u32)offset_of(VertexDataStandard, color_0),
        };

        // Texcoord_0
        tc0 : sdl.GPUVertexAttribute = sdl.GPUVertexAttribute{
            buffer_slot = 1,
            location = 3,
            format = sdl.GPUVertexElementFormat.FLOAT2,
            offset = cast(u32)offset_of(VertexDataStandard, texcoord_0),
        };

        append(array, pos);
        append(array, norm_tan);
        append(array, col0);
        append(array, tc0);
    }

    pm_append_attr_layout_extended :: proc(array: ^[dynamic]sdl.GPUVertexAttribute){

        // Position
        pos : sdl.GPUVertexAttribute = sdl.GPUVertexAttribute{
            buffer_slot = 0,
            location = 0,
            format = sdl.GPUVertexElementFormat.FLOAT3,
            offset = 0,
        };

        // Normal_Tangent_oct_encoded
        norm_tan : sdl.GPUVertexAttribute = sdl.GPUVertexAttribute{
            buffer_slot = 1,
            location = 1,
            format = sdl.GPUVertexElementFormat.FLOAT4,
            offset = cast(u32)offset_of(VertexDataExtended, normal_tangent),
        };

        // Color_0
        col0 : sdl.GPUVertexAttribute = sdl.GPUVertexAttribute{
            buffer_slot = 1,
            location = 2,
            format = sdl.GPUVertexElementFormat.FLOAT4,
            offset = cast(u32)offset_of(VertexDataExtended, color_0),
        };

        // Color_1
        col1 : sdl.GPUVertexAttribute = sdl.GPUVertexAttribute{
            buffer_slot = 1,
            location = 3,
            format = sdl.GPUVertexElementFormat.FLOAT4,
            offset = cast(u32)offset_of(VertexDataExtended, color_1),
        };

        // Texcoord_0
        tc0 : sdl.GPUVertexAttribute = sdl.GPUVertexAttribute{
            buffer_slot = 1,
            location = 4,
            format = sdl.GPUVertexElementFormat.FLOAT2,
            offset = cast(u32)offset_of(VertexDataExtended, texcoord_0),
        };

        // Texcoord_1
        tc1 : sdl.GPUVertexAttribute = sdl.GPUVertexAttribute{
            buffer_slot = 1,
            location = 5,
            format = sdl.GPUVertexElementFormat.FLOAT2,
            offset = cast(u32)offset_of(VertexDataExtended, texcoord_1),
        };

        append(array, pos);
        append(array, norm_tan);
        append(array, col0);
        append(array, col1);
        append(array, tc0);
        append(array, tc1);
    }

    dear_imgui_draw_vert :: struct {
        pos : [2]f32,
        uv  : [2]f32,
        col : [4]u8
    }
    pm_append_attr_dear_imgui :: proc(array: ^[dynamic]sdl.GPUVertexAttribute) {
        // Position

            a_pos := sdl.GPUVertexAttribute{
                buffer_slot = 0,
                format = sdl.GPUVertexElementFormat.FLOAT2,
                location = 0,
                offset = cast(u32)offset_of(dear_imgui_draw_vert,pos),
            }

            a_uv := sdl.GPUVertexAttribute{
                buffer_slot = 0,
                format = sdl.GPUVertexElementFormat.FLOAT2,
                location = 1,
                offset = cast(u32)offset_of(dear_imgui_draw_vert,uv),
            }

            a_col := sdl.GPUVertexAttribute{
                buffer_slot = 0,
                format = sdl.GPUVertexElementFormat.UBYTE4_NORM,
                location = 2,
                offset = cast(u32)offset_of(dear_imgui_draw_vert,col),
            }


            append(array, a_pos);
            append(array, a_uv);
            append(array, a_col);
    }

    info : VertexBufDescriptorInfo;
    info.type = type;

    switch info.type {
        case .None:
        case .PositionOnly: {

            pm_append_attr_pos_only(&info.attributes);

            description : sdl.GPUVertexBufferDescription = {
                slot = 0, // buffer slot
                input_rate = sdl.GPUVertexInputRate.VERTEX,
                pitch = size_of([3]f32), // vertex byte size
            }

            append(&info.descriptors,description);
        }

        case .LayoutMinimal: {
            pm_append_attr_layout_minimal(&info.attributes);

            description_0 : sdl.GPUVertexBufferDescription = {
                slot = 0, // buffer slot
                input_rate = sdl.GPUVertexInputRate.VERTEX,
                pitch = size_of([3]f32), // vertex byte size
            }

            description_1 : sdl.GPUVertexBufferDescription = {
                slot = 1, // buffer slot
                input_rate = sdl.GPUVertexInputRate.VERTEX,
                pitch = size_of(VertexDataMinimal), // vertex byte size
            }

            append(&info.descriptors,description_0);
            append(&info.descriptors,description_1);
        }
        case .LayoutStandard: {
            pm_append_attr_layout_standard(&info.attributes);

            description_0 : sdl.GPUVertexBufferDescription = {
                slot = 0, // buffer slot
                input_rate = sdl.GPUVertexInputRate.VERTEX,
                pitch = size_of([3]f32), // vertex byte size
            }

            description_1 : sdl.GPUVertexBufferDescription = {
                slot = 1, // buffer slot
                input_rate = sdl.GPUVertexInputRate.VERTEX,
                pitch = size_of(VertexDataStandard), // vertex byte size
            }

            append(&info.descriptors,description_0);
            append(&info.descriptors,description_1);
        }
        case .LayoutExtended: {
            pm_append_attr_layout_standard(&info.attributes);

            description_0 : sdl.GPUVertexBufferDescription = {
                slot = 0, // buffer slot
                input_rate = sdl.GPUVertexInputRate.VERTEX,
                pitch = size_of([3]f32), // vertex byte size
            }

            description_1 : sdl.GPUVertexBufferDescription = {
                slot = 1, // buffer slot
                input_rate = sdl.GPUVertexInputRate.VERTEX,
                pitch = size_of(VertexDataExtended), // vertex byte size
            }

            append(&info.descriptors,description_0);
            append(&info.descriptors,description_1);
        }
        case .DearImgui: {
            pm_append_attr_dear_imgui(&info.attributes);

            description : sdl.GPUVertexBufferDescription = {
                slot = 0, // buffer slot
                input_rate = sdl.GPUVertexInputRate.VERTEX,
                pitch = size_of(dear_imgui_draw_vert), // vertex byte size
            }

            append(&info.descriptors,description);
        }
    }


    return info;
}

// ===================================================================================================================
// ===================================================================================================================

@(private="package")
pipe_manager_init :: proc(manager : ^PipelineManager, gpu_device : ^sdl.GPUDevice, shader_manager : ^ShaderManager){

	engine_assert(manager != nil);

    // Register Shaders with shader manager

    // @Note: im doing a for loop and switch here just because i want to get compiler messages when 
    // i add new compute shader enum so i remember to add it here.
    
    shaders_path :string = strings.join({get_resources_path(), "shaders"}, "/", context.temp_allocator);

    for pipe_shader in PipelineShader {

        id : ShaderID = -1;

        switch pipe_shader {
            case .STANDARD_VERT:            id = shader_manager_register_shader_source(shader_manager, strings.join({shaders_path, "forward.vert"              }, "/", context.temp_allocator) , .VERTEX  , enable_hot_reloading = true);
            case .FORWARD_PBR_FRAG:         id = shader_manager_register_shader_source(shader_manager, strings.join({shaders_path, "forward_pbr.frag"          }, "/", context.temp_allocator) , .FRAGMENT, enable_hot_reloading = true);
            case .FORWARD_UNLIT_FRAG:       id = shader_manager_register_shader_source(shader_manager, strings.join({shaders_path, "forward_unlit.frag"        }, "/", context.temp_allocator) , .FRAGMENT, enable_hot_reloading = false);
            case .SKYBOX_VERT:              id = shader_manager_register_shader_source(shader_manager, strings.join({shaders_path, "skybox.vert"               }, "/", context.temp_allocator) , .VERTEX  , enable_hot_reloading = false);
            case .SKYBOX_FRAG:              id = shader_manager_register_shader_source(shader_manager, strings.join({shaders_path, "skybox.frag"               }, "/", context.temp_allocator) , .FRAGMENT, enable_hot_reloading = true);
            case .SCREENQUAD_VERT:          id = shader_manager_register_shader_source(shader_manager, strings.join({shaders_path, "screenquad.vert"           }, "/", context.temp_allocator) , .VERTEX  , enable_hot_reloading = false);
            case .POST_COLOR_CORRECT_FRAG:  id = shader_manager_register_shader_source(shader_manager, strings.join({shaders_path, "post_process.frag"         }, "/", context.temp_allocator) , .FRAGMENT, enable_hot_reloading = false);        
            case .DEAR_IMGUI_VERT:          id = shader_manager_register_shader_source(shader_manager, strings.join({shaders_path, "dear_imgui.vert"           }, "/", context.temp_allocator) , .VERTEX  , enable_hot_reloading = false);
            case .DEAR_IMGUI_FRAG:          id = shader_manager_register_shader_source(shader_manager, strings.join({shaders_path, "dear_imgui.frag"           }, "/", context.temp_allocator) , .FRAGMENT, enable_hot_reloading = false);
            case .SWAPCHAIN_COMPOSIT_FRAG:  id = shader_manager_register_shader_source(shader_manager, strings.join({shaders_path, "swapchain_composit.frag"   }, "/", context.temp_allocator) , .FRAGMENT, enable_hot_reloading = false);
            case .UNIT_CUBE_VERT:           id = shader_manager_register_shader_source(shader_manager, strings.join({shaders_path, "unit_cube.vert"            }, "/", context.temp_allocator) , .VERTEX  , enable_hot_reloading = false);
            case .UNLIT_BASIC_FRAG:         id = shader_manager_register_shader_source(shader_manager, strings.join({shaders_path, "unlit_basic.frag"          }, "/", context.temp_allocator) , .FRAGMENT, enable_hot_reloading = false);
            case .DEPTH_ONLY_VERT:          id = shader_manager_register_shader_source(shader_manager, strings.join({shaders_path, "depth_pre.vert"            }, "/", context.temp_allocator) , .VERTEX  , enable_hot_reloading = false);
            case .DEPTH_ONLY_FRAG:          id = shader_manager_register_shader_source(shader_manager, strings.join({shaders_path, "depth_pre.frag"            }, "/", context.temp_allocator) , .FRAGMENT, enable_hot_reloading = false);
            case .DEPTH_ONLY_ALPHATEST_FRAG:id = shader_manager_register_shader_source(shader_manager, strings.join({shaders_path, "depth_pre_alpha_test.frag" }, "/", context.temp_allocator) , .FRAGMENT, enable_hot_reloading = false);
            case .SHADOWMAP_VERT:           id = shader_manager_register_shader_source(shader_manager, strings.join({shaders_path, "shadowmap.vert"            }, "/", context.temp_allocator) , .VERTEX  , enable_hot_reloading = false);
            case .SHADOWMAP_FRAG:           id = shader_manager_register_shader_source(shader_manager, strings.join({shaders_path, "shadowmap.frag"            }, "/", context.temp_allocator) , .FRAGMENT, enable_hot_reloading = false);
            case .SMAA_VERT:                id = shader_manager_register_shader_source(shader_manager, strings.join({shaders_path, "smaa.vert"                 }, "/", context.temp_allocator) , .VERTEX  , enable_hot_reloading = true);
            case .SMAA_EDGE_DETECTION_FRAG: id = shader_manager_register_shader_source(shader_manager, strings.join({shaders_path, "smaa_edge_detection.frag"  }, "/", context.temp_allocator) , .FRAGMENT, enable_hot_reloading = true);
            case .SMAA_BLEND_WEIGHT_FRAG:   id = shader_manager_register_shader_source(shader_manager, strings.join({shaders_path, "smaa_blend_weight.frag"    }, "/", context.temp_allocator) , .FRAGMENT, enable_hot_reloading = true);
            case .SMAA_NEIGHBORHOOD_BLEND_FRAG:   id = shader_manager_register_shader_source(shader_manager, strings.join({shaders_path, "smaa_neighborhood_blend.frag"    }, "/", context.temp_allocator) , .FRAGMENT, enable_hot_reloading = true);
            case: 
        }

        engine_assert(id >= 0);

        manager.pipeline_shader_ids[pipe_shader] = id;
    }

    for mat_pipe_shader in MaterialPipelineShaders {

        combi : ShaderCombination;
        switch mat_pipe_shader {
            case .PBR:      combi =  ShaderCombination{vert = .STANDARD_VERT, frag = .FORWARD_PBR_FRAG};
            case .UNLIT:    combi =  ShaderCombination{vert = .STANDARD_VERT, frag = .FORWARD_UNLIT_FRAG};   
        }
        manager.material_pipeline_shader_combinations[mat_pipe_shader] = combi;
    }

    for depth_only_shader in DepthOnlyPipelineShaders {
        combi : ShaderCombination;

        switch depth_only_shader {
            case .DepthPre:             combi = ShaderCombination{vert = .DEPTH_ONLY_VERT, frag = .DEPTH_ONLY_FRAG};
            case .DepthPreAlphaTest:    combi = ShaderCombination{vert = .DEPTH_ONLY_VERT, frag = .DEPTH_ONLY_ALPHATEST_FRAG};
            case .Shadowmap:            combi = ShaderCombination{vert = .SHADOWMAP_VERT , frag = .SHADOWMAP_FRAG};
            case .ShadowmapAlphaTest:   combi = ShaderCombination{vert = .SHADOWMAP_VERT , frag = .SHADOWMAP_FRAG};
        }

        manager.depthonly_pipeline_shader_combinations[depth_only_shader] = combi;
    }

    manager.depthonly_pipeline_cache = make_map(map[DepthOnlyPipelineHash]^sdl.GPUGraphicsPipeline, context.allocator);


    for vert_buf_descriptor_type in VertexBufDescriptorType {
        manager.vertex_buf_descriptor_infos[vert_buf_descriptor_type] = pipe_manager_create_vertex_buffer_descriptor_info(vert_buf_descriptor_type);
    }

    manager.material_pipeline_cache = make_map(map[MaterialPipelineHash]^sdl.GPUGraphicsPipeline, context.allocator);

    for pipe in CorePipeline {
        manager.core_pipeline_configs[pipe] = pipe_manager_create_core_pipeline_config(pipe);
    }
}

@(private="package")
pipe_manager_deinit :: proc(manager : ^PipelineManager, gpu_device : ^sdl.GPUDevice){

    engine_assert(manager != nil);

    for pipe in CorePipeline {
        
        if manager.core_pipelines[pipe] != nil {
            sdl.ReleaseGPUGraphicsPipeline(gpu_device, manager.core_pipelines[pipe]);
        }
    }

    for type in VertexBufDescriptorType {
        delete(manager.vertex_buf_descriptor_infos[type].attributes);
        delete(manager.vertex_buf_descriptor_infos[type].descriptors);
    }

    pipe_manager_clear_material_pipeline_cache(manager, gpu_device);
    delete_map(manager.material_pipeline_cache)

    pipe_manager_clear_depthonly_pipeline_cache(manager, gpu_device, DEPTHONLY_PIPELINE_SHADER_SET_ALL);
    delete_map(manager.depthonly_pipeline_cache)
}

@(private="package")
pipe_manager_on_shaders_changed :: proc(manager : ^PipelineManager, gpu_device : ^sdl.GPUDevice, shader_ids : []ShaderID){

    material_pipe_shader_changed : bool = false;

    core_pipeline_requires_rebuild : [CorePipeline]bool; 

    depthonly_rebuild_set := DepthOnlyPipelineShadersSet{};

    // This will most likely only be an array with only one element.
    for id in shader_ids {

        for mat_pipe_shader in MaterialPipelineShaders{
            
            mat_pipe_combi := manager.material_pipeline_shader_combinations[mat_pipe_shader];
            vert_id := manager.pipeline_shader_ids[mat_pipe_combi.vert];
            frag_id := manager.pipeline_shader_ids[mat_pipe_combi.frag];

            if vert_id == id || frag_id == id {
                material_pipe_shader_changed = true;
            }
        }

        for core_pipe in CorePipeline {

            core_pipe_shader_combi := pipe_manager_get_core_pipeline_shader_combination(core_pipe);

            vert_id := manager.pipeline_shader_ids[core_pipe_shader_combi.vert];
            frag_id := manager.pipeline_shader_ids[core_pipe_shader_combi.frag];

            if vert_id == id || frag_id == id {
                core_pipeline_requires_rebuild[core_pipe] = true;
            }
        }

        for depthonly_pipe_shader in DepthOnlyPipelineShaders {

            depthonly_pipe_shader_combi := manager.depthonly_pipeline_shader_combinations[depthonly_pipe_shader];

            vert_id := manager.pipeline_shader_ids[depthonly_pipe_shader_combi.vert];
            frag_id := manager.pipeline_shader_ids[depthonly_pipe_shader_combi.frag];

            if vert_id == id || frag_id == id {
                depthonly_rebuild_set += DepthOnlyPipelineShadersSet{depthonly_pipe_shader};
            }
        }

    }

    for core_pipe in CorePipeline {

        if !core_pipeline_requires_rebuild[core_pipe]{
            continue;
        }

        pipe_manager_rebuild_core_pipeline(manager, gpu_device, core_pipe);
    }

    if material_pipe_shader_changed {
        // @Note: I dont have a good way yet to only rebuild specific pipelines.

        pipe_manager_clear_material_pipeline_cache(manager, gpu_device);
        pipe_manager_update_material_pipeline_cache_for_universe(manager, gpu_device, engine.universe);
    }

    if depthonly_rebuild_set != DEPTHONLY_PIPELINE_SHADER_SET_EMPTY {

        pipe_manager_clear_depthonly_pipeline_cache(manager, gpu_device, depthonly_rebuild_set);
        pipe_manager_update_depthonly_pipeline_cache_for_universe(manager, gpu_device, engine.universe);
    }
}

@(private="package")
pipe_manager_get_core_pipeline :: proc(manager : ^PipelineManager, pipeline : CorePipeline) -> ^sdl.GPUGraphicsPipeline {
	return manager.core_pipelines[pipeline];
}

@(private="package")
// Do a rebuild of all graphics pipelines that are associated to the specified render passes
pipe_manager_rebuild_all_pipelines_for_render_pass_types :: proc(manager : ^PipelineManager, gpu_device : ^sdl.GPUDevice, render_pass_set: RenderPassSet){

    for pipe in CorePipeline {

        pipe_render_pass_type := pipe_manager_get_core_pipeline_render_pass_type(pipe);
        if pipe_render_pass_type in render_pass_set {

            pipe_manager_rebuild_core_pipeline(manager, gpu_device, pipe);
        }
    }

    if RenderPassType.Main in render_pass_set {
        
        // If Main Render Pass changed, we must unfortunately rebuild all cached material pipelines.

        if engine.universe != nil {
            pipe_manager_clear_material_pipeline_cache(manager, gpu_device);
            pipe_manager_update_material_pipeline_cache_for_universe(manager, gpu_device, engine.universe);
        } else {
            log.warnf("Active universe is currently nil!")
        }
    }

    // IF both we update both at the same time.
    if .DEPTH_PREPASS in render_pass_set && .SHADOWMAP in render_pass_set {

        if engine.universe != nil {
                pipe_manager_clear_depthonly_pipeline_cache(manager, gpu_device, DEPTHONLY_PIPELINE_SHADER_SET_ALL);
                pipe_manager_update_depthonly_pipeline_cache_for_universe(manager, gpu_device, engine.universe)
        } else {
            log.warnf("Active universe is currently nil!")
        }
    } else {
        if RenderPassType.DEPTH_PREPASS in render_pass_set {
            if engine.universe != nil {
                pipe_manager_clear_depthonly_pipeline_cache(manager, gpu_device, {.DepthPre, .DepthPreAlphaTest});
                pipe_manager_update_depthonly_pipeline_cache_for_universe(manager, gpu_device, engine.universe)
            } else {
                log.warnf("Active universe is currently nil!")
            }
        }

        if RenderPassType.SHADOWMAP in render_pass_set {
            if engine.universe != nil {
                pipe_manager_clear_depthonly_pipeline_cache(manager, gpu_device, {.Shadowmap, .ShadowmapAlphaTest});
                pipe_manager_update_depthonly_pipeline_cache_for_universe(manager, gpu_device, engine.universe)
            } else {
                log.warnf("Active universe is currently nil!")
            }
        }
    }

}

@(private="package")
pipe_manager_rebuild_core_pipeline :: proc(manager : ^PipelineManager, gpu_device: ^sdl.GPUDevice, pipe: CorePipeline){

    shader_manager := engine.shader_manager;

    pipe_render_pass_type := pipe_manager_get_core_pipeline_render_pass_type(pipe);
    render_pass_info      := renderer_get_render_pass_info(engine.render_context, pipe_render_pass_type);

    shader_combination := pipe_manager_get_core_pipeline_shader_combination(pipe);
    vert_id := manager.pipeline_shader_ids[shader_combination.vert];
    frag_id := manager.pipeline_shader_ids[shader_combination.frag];

    vert := shader_manager_get_or_load_gfx_shader_variant(shader_manager, gpu_device, vert_id, shader_combination.vert_variant);
    frag := shader_manager_get_or_load_gfx_shader_variant(shader_manager, gpu_device, frag_id, shader_combination.frag_variant);

    if vert == nil {
        log.errorf("Failed to Create Graphics Pipline: {} - vertex shader not loaded", pipe);
        return;
    } else if frag == nil {
        log.errorf("Failed to Create Graphics Pipline: {} - fragment shader not loaded", pipe);
        return;
    }

    vert_buf_descpt_type := pipe_manager_get_core_pipeline_vertex_buf_descriptor_type(pipe);

    pipeline := pipe_manager_create_graphics_pipeline(gpu_device, vert, frag, &manager.core_pipeline_configs[pipe], &manager.vertex_buf_descriptor_infos[vert_buf_descpt_type], &render_pass_info);

    if pipeline == nil {
        log.errorf("Failed to Create Graphics Pipline: {}", pipe);
        return;
    }

    engine_assert(pipeline != nil);

    if manager.core_pipelines[pipe] != nil {
        sdl.ReleaseGPUGraphicsPipeline(gpu_device, manager.core_pipelines[pipe]);
    }

     log.debugf("Build Graphics Pipline: {}", pipe);

    manager.core_pipelines[pipe] = pipeline;
}

// ===================================================================================================================
// ===================================================================================================================

@(private="file")
pipe_manager_create_graphics_pipeline :: proc(gpu_device: ^sdl.GPUDevice, vert_shader, frag_shader: ^sdl.GPUShader, config: ^PipelineConfig, vertex_buf_info: ^VertexBufDescriptorInfo, render_pass_info: ^RenderPassInfo) -> ^sdl.GPUGraphicsPipeline {

    engine_assert(vert_shader != nil);
    engine_assert(frag_shader != nil);

    // Pipeline Info
    pipeline_info : sdl.GPUGraphicsPipelineCreateInfo;
    pipeline_info.vertex_shader     = vert_shader;
    pipeline_info.fragment_shader   = frag_shader;
    pipeline_info.primitive_type    = sdl.GPUPrimitiveType.TRIANGLELIST;

    if vertex_buf_info.type != .None {

        // Vertex Input State
        pipeline_info.vertex_input_state.num_vertex_buffers = cast(u32)len(vertex_buf_info.descriptors);
        pipeline_info.vertex_input_state.vertex_buffer_descriptions = &vertex_buf_info.descriptors[0];

        pipeline_info.vertex_input_state.num_vertex_attributes = cast(u32)len(vertex_buf_info.attributes);
        pipeline_info.vertex_input_state.vertex_attributes = &vertex_buf_info.attributes[0];
    }

    // RASTERIZER Settings
    pipeline_info.rasterizer_state = sdl.GPURasterizerState{
        fill_mode = get_sdl_GPUFillMode_from_FillMode(config.raster_fill_mode),
        cull_mode = get_sdl_GPUCullMode_from_CullMode(config.raster_cull_mode),
        front_face = sdl.GPUFrontFace.COUNTER_CLOCKWISE, // Winding Order
        enable_depth_bias = false,
        enable_depth_clip = !config.raster_disable_depth_clip,
    }


    // MSAA -> NOT SUPPORTED ANYMORE
    pipeline_info.multisample_state = sdl.GPUMultisampleState{
        // MSAA not supported anymore:   get_sdl_GPUSampleCount_from_MSAA(render_pass_info.msaa),
        sample_count = sdl.GPUSampleCount._1, 
        sample_mask = 0, // must be 0
        enable_mask = false, // must be false
    }



    // DEPTH STENCIL 
    pipeline_info.depth_stencil_state = sdl.GPUDepthStencilState {
        compare_op = get_sdl_GPUCompareOp_from_CompareOp(config.depth_stencil_compare_op),

        // NOTE: we don't care for most of this now as we disable stencil test atm
        // back_stencil_state:  GPUStencilOpState,  /**< The stencil op state for back-facing triangles. */
        // front_stencil_state: GPUStencilOpState,  /**< The stencil op state for front-facing triangles. */
        // compare_mask:        Uint8,              /**< Selects the bits of the stencil values participating in the stencil test. */
        // write_mask:          Uint8,              /**< Selects the bits of the stencil values updated by the stencil test. */
        enable_depth_test   = config.enable_depth_test,
        enable_depth_write  = config.enable_depth_write,     // true enables depth writes. Depth writes are always disabled when enable_depth_test is false.
        enable_stencil_test = config.enable_stencil_test,          
    };

    has_color_target :bool =  render_pass_info.has_color_target;
    has_depth_target :bool =  render_pass_info.has_depth_target;


    col_target_description : sdl.GPUColorTargetDescription = !has_color_target ? sdl.GPUColorTargetDescription{} : sdl.GPUColorTargetDescription {
        format = get_sdl_GPUTextureFormat_from_RenderTargetFormat(render_pass_info.color_target_format),
        blend_state = sdl.GPUColorTargetBlendState{
            src_color_blendfactor   = get_sdl_GPUBlendFactor_from_BlendFactor(config.col_target_src_color_blendfactor),
            dst_color_blendfactor   = get_sdl_GPUBlendFactor_from_BlendFactor(config.col_target_dst_color_blendfactor),
            color_blend_op          = get_sdl_GPUBlendOp_from_BlendOp(config.col_target_color_blend_op),
            src_alpha_blendfactor   = get_sdl_GPUBlendFactor_from_BlendFactor(config.col_target_src_alpha_blendfactor),
            dst_alpha_blendfactor   = get_sdl_GPUBlendFactor_from_BlendFactor(config.col_target_dst_alpha_blendfactor),
            alpha_blend_op          = get_sdl_GPUBlendOp_from_BlendOp(config.col_target_alpha_blend_op),
            // color_write_mask:        GPUColorComponentFlags,  // A bitmask specifying which of the RGBA components are enabled for writing. Writes to all channels if enable_color_write_mask is false.
            enable_blend = config.enable_blend,
            enable_color_write_mask = false, // apparently one can mask specific color channels from being writable
        },
    }

    // Target info
    pipeline_info.target_info = sdl.GPUGraphicsPipelineTargetInfo{
        num_color_targets           = has_color_target ? 1 : 0,
        color_target_descriptions   = has_color_target ? &col_target_description : nil,
        has_depth_stencil_target    = has_depth_target,
        depth_stencil_format        = has_depth_target ? get_sdl_GPUTextureFormat_from_DepthStencilFormat(render_pass_info.depth_target_format) : sdl.GPUTextureFormat.INVALID,
    }

    return sdl.CreateGPUGraphicsPipeline(gpu_device, pipeline_info);
}

@(private="package")
pipe_manager_get_material_pipeline_shader_variants :: proc(manager : ^PipelineManager, material : ^Material, vertex_layout : VertexDataLayout) -> (vert_shader_id : ShaderID, vert_variant : ShaderVariant, frag_shader_id : ShaderID, frag_variant : ShaderVariant) {
    
    technique := &material.render_technique;

    vert_shader_variant : ShaderVariant = SHADER_VARIANT_EMPTY;
    switch vertex_layout {
        case .Minimal : vert_shader_variant += {.VERT_LAYOUT_MINIMAL};
        case .Standard: vert_shader_variant += {.VERT_LAYOUT_STANDARD};
        case .Extended: vert_shader_variant += {.VERT_LAYOUT_EXTENDED};
    }

    frag_shader_variant : ShaderVariant = SHADER_VARIANT_EMPTY;

    if technique.alpha_mode == .Clip || technique.alpha_mode == .Hashed {
        frag_shader_variant += {.USE_ALPHA_TEST};
    }

    if technique.alpha_mode == .Blend {
        frag_shader_variant += {.USE_ALPHA_BLEND};
    }

    vert_id : ShaderID = -1;
    frag_id : ShaderID = -1;

    switch &mat_variant in material.variant {
        case PbrMaterialData: {
            combi := manager.material_pipeline_shader_combinations[.PBR];
            vert_id = manager.pipeline_shader_ids[combi.vert];
            frag_id = manager.pipeline_shader_ids[combi.frag];
        }
        case UnlitMaterialData: {
            combi := manager.material_pipeline_shader_combinations[.UNLIT];
            vert_id = manager.pipeline_shader_ids[combi.vert];
            frag_id = manager.pipeline_shader_ids[combi.frag];
        }
        case CustomMaterialVariant: {
            vert_id = mat_variant.vert_shader;
            frag_id = mat_variant.frag_shader;
        }
    }

    engine_assert(vert_id != -1);
    engine_assert(frag_id != -1);

    return vert_id, vert_shader_variant ,frag_id, frag_shader_variant;
}

@(private="package")
pipe_manager_calc_material_pipeline_hash :: proc(vert_shader_id : ShaderID, vert_variant_hash : u32, frag_shader_id : ShaderID, frag_variant_hash : u32, render_technique_hash : u32) -> MaterialPipelineHash {

    hash_data : [20]u8;
    hash_data_u32 : [^]u32 = cast([^]u32)&hash_data[0];

    hash_data_u32[0] = transmute(u32)vert_shader_id;
    hash_data_u32[1] = vert_variant_hash;
    hash_data_u32[2] = transmute(u32)frag_shader_id;
    hash_data_u32[3] = frag_variant_hash;
    hash_data_u32[4] = render_technique_hash;

    pipeline_hash : u32 = hash.fnv32a(hash_data[:]);

    return pipeline_hash;
}

@(private="package")
pipe_manager_get_material_pipeline_variant :: proc(manager : ^PipelineManager, mat_id : MaterialID, vertex_layout : VertexDataLayout) -> ^sdl.GPUGraphicsPipeline {

    engine_assert(register_contains_material_id(mat_id));

    material := register_get_material(mat_id)

    vert_shader_id, vert_shader_variant, frag_shader_id, frag_shader_variant := pipe_manager_get_material_pipeline_shader_variants(manager, material, vertex_layout);
        
    vert_variant_hash : u32 = transmute(u32)vert_shader_variant;
    frag_variant_hash : u32 = transmute(u32)frag_shader_variant;
    technique_hash := material_register_get_render_technique_hash(mat_id);

    pipe_hash := pipe_manager_calc_material_pipeline_hash(vert_shader_id, vert_variant_hash, frag_shader_id, frag_variant_hash, technique_hash);
    

    pipe, exists := manager.material_pipeline_cache[pipe_hash];

    if !exists {
        return nil;
    }

    return pipe;
}

@(private="package")
pipe_manager_clear_material_pipeline_cache :: proc(manager : ^PipelineManager, gpu_device: ^sdl.GPUDevice) {

    for pipe_hash in manager.material_pipeline_cache {

        pipe := manager.material_pipeline_cache[pipe_hash];

        if pipe != nil {
            sdl.ReleaseGPUGraphicsPipeline(gpu_device, pipe);
        }
        manager.material_pipeline_cache[pipe_hash] = nil;
    }

    clear(&manager.material_pipeline_cache);
}

@(private="package")
pipe_manager_update_material_pipeline_cache_for_universe :: proc(manager : ^PipelineManager, gpu_device : ^sdl.GPUDevice, universe : ^Universe){




    // First we must iterate all materials and meshes and find all unique combinations.
    // For this we can probably iterate the drawables array from teh ecs.

    mesh_manager := engine.mesh_manager;
    shader_manager := engine.shader_manager;

    ecs := &universe.ecs;

    for i in 0..<len(ecs.drawables) {

        mesh_inst := &ecs.drawables[i].mesh_instance;

        mesh_id := mesh_inst.mesh_id;
        mat_id  := mesh_inst.mat_id;

        vertex_layout : VertexDataLayout = mesh_manager_get_mesh_gpu_data(mesh_manager, mesh_id).vertex_layout;
        material : ^Material = register_get_material(mat_id);

        engine_assert(material != nil)

        vert_shader_id, vert_shader_variant, frag_shader_id, frag_shader_variant := pipe_manager_get_material_pipeline_shader_variants(manager, material, vertex_layout);
        
        vert_variant_hash : u32 = transmute(u32)vert_shader_variant;
        frag_variant_hash : u32 = transmute(u32)frag_shader_variant;
        technique_hash := material_register_get_render_technique_hash(mat_id);

        pipe_hash := pipe_manager_calc_material_pipeline_hash(vert_shader_id, vert_variant_hash, frag_shader_id, frag_variant_hash, technique_hash);

        // If pipeline already exists in the cache we can skip
        {
            pipe_ , exists := manager.material_pipeline_cache[pipe_hash];

            if exists && pipe_ != nil {
                continue
            }
        }

        vert_buff_descrip_type : VertexBufDescriptorType;
        switch vertex_layout {
            case .Minimal:  vert_buff_descrip_type = .LayoutMinimal;
            case .Standard: vert_buff_descrip_type = .LayoutStandard;
            case .Extended: vert_buff_descrip_type = .LayoutExtended;
        }

        render_pass_info := renderer_get_render_pass_info(engine.render_context, RenderPassType.Main);

        pipe_config := pipe_manager_create_pipeline_config_from_render_technique(material.render_technique);

        vert_shader := shader_manager_get_or_load_gfx_shader_variant(shader_manager, gpu_device, vert_shader_id, vert_shader_variant);
        frag_shader := shader_manager_get_or_load_gfx_shader_variant(shader_manager, gpu_device, frag_shader_id, frag_shader_variant);

        engine_assert(vert_shader != nil);
        engine_assert(frag_shader != nil);

        pipeline := pipe_manager_create_graphics_pipeline(gpu_device, vert_shader, frag_shader, &pipe_config, &manager.vertex_buf_descriptor_infos[vert_buff_descrip_type], &render_pass_info);

        if pipeline != nil {
            
            LOG_MORE_STUFF :: false

            when LOG_MORE_STUFF {

                mat_shader_type := register_get_material_shader_type(mat_id);
                log.debugf("Build Material Pipeline Variant: shader_type: {}, vert_layout: {}, alpha: {}, pipe_hash: {}", mat_shader_type, vertex_layout, material.render_technique.alpha_mode, pipe_hash);
            } else {
                log.debugf("Build Material Pipeline Variant: shader_type: {}, vert_layout: {}, alpha: {}, pipe_hash: {}", typeid_of(type_of(material.variant)), vertex_layout, material.render_technique.alpha_mode, pipe_hash);
            }

            manager.material_pipeline_cache[pipe_hash] = pipeline;
        } else {
            log.errorf("Pipe: failed to create pipeline")
        }
    }

}

@(private="package")
pipe_manager_get_depthonly_pipeline_variant :: proc(manager : ^PipelineManager, depthonly_shader_type : DepthOnlyPipelineShaders, render_technique_hash : u32) -> ^sdl.GPUGraphicsPipeline {

    pipe_hash : DepthOnlyPipelineHash = pipe_manager_calc_depthonly_pipeline_hash(depthonly_shader_type, render_technique_hash);

    pipeline, exists := manager.depthonly_pipeline_cache[pipe_hash];
    if exists && pipeline != nil {
        return pipeline;
    }

    log.errorf("Failed to get depthonly pipeline variant");
    return nil;
}

@(private="package")
pipe_manager_calc_depthonly_pipeline_hash :: proc(shader_type : DepthOnlyPipelineShaders, render_technique_hash : u32) -> DepthOnlyPipelineHash {
    
    depth_only_pipe_hash : u64;

    depth_only_pipe_hash_ : [^]u32 = cast([^]u32)&depth_only_pipe_hash;

    depth_only_pipe_hash_[0] = cast(u32)shader_type;
    depth_only_pipe_hash_[1] = render_technique_hash;

    return depth_only_pipe_hash;
}

@(private="package")
pipe_manager_clear_depthonly_pipeline_cache :: proc(manager : ^PipelineManager, gpu_device: ^sdl.GPUDevice, depthonly_shaders_set : DepthOnlyPipelineShadersSet) {

    clear_all : bool = depthonly_shaders_set == DEPTHONLY_PIPELINE_SHADER_SET_ALL;

    if clear_all {
        // Fast path for clearing all.

        for pipe_hash, &pipeline in manager.depthonly_pipeline_cache {

           //pipe := manager.depthonly_pipeline_cache[pipe_hash];

            if pipeline != nil {
                sdl.ReleaseGPUGraphicsPipeline(gpu_device, pipeline);
            }
           // manager.depthonly_pipeline_cache[pipe_hash] = nil;
        }

        clear(&manager.depthonly_pipeline_cache);
        return;
    }


    hashes_to_clear : [dynamic]DepthOnlyPipelineHash;
    defer delete(hashes_to_clear);

    for pipe_hash in manager.depthonly_pipeline_cache {

        pipe_hash_copy : DepthOnlyPipelineHash = pipe_hash;

        // @Note: the DepthOnlyPipelineShader type is encoded in the first 32 bits of the hash value.
        // So we can do this weird stuff here to only clear specific shader types.
        pipe_hash_ : [^]u32 = cast([^]u32)&pipe_hash_copy;
        shader_type : DepthOnlyPipelineShaders = cast(DepthOnlyPipelineShaders)pipe_hash_[0];

        if shader_type not_in depthonly_shaders_set {
            continue;
        }

        append(&hashes_to_clear, pipe_hash);
    }

    for pipe_hash in hashes_to_clear {

        pipeline := manager.depthonly_pipeline_cache[pipe_hash];

        if pipeline != nil {
            sdl.ReleaseGPUGraphicsPipeline(gpu_device, pipeline);
        }

        delete_key(&manager.depthonly_pipeline_cache, pipe_hash);
    }
}

@(private="package")
pipe_manager_update_depthonly_pipeline_cache_for_universe :: proc(manager : ^PipelineManager, gpu_device : ^sdl.GPUDevice, universe : ^Universe){

    mesh_manager := engine.mesh_manager;
    shader_manager := engine.shader_manager;

    ecs := &universe.ecs;

    drawables_loop: for i in 0..<len(ecs.drawables) {

        mesh_inst := &ecs.drawables[i].mesh_instance;

        mesh_id := mesh_inst.mesh_id;
        mat_id  := mesh_inst.mat_id;

        
        material : ^Material = register_get_material(mat_id);

        engine_assert(material != nil)

        mat_shader_type := register_get_material_shader_type(mat_id);

        // Compute the pipeline_hash

        technique_hash := material_register_get_render_technique_hash(mat_id);

        for depth_only_shader_type in DepthOnlyPipelineShaders {

            pipe_hash : DepthOnlyPipelineHash = pipe_manager_calc_depthonly_pipeline_hash(depth_only_shader_type, technique_hash);

            pipe_ , exists := manager.depthonly_pipeline_cache[pipe_hash];

            if exists && pipe_ != nil {
                continue;
            }

            // Create the pipeline.

            render_pass_info : RenderPassInfo;
            pipe_config : PipelineConfig;

            switch depth_only_shader_type {
                case .DepthPre: {
                    render_pass_info = renderer_get_render_pass_info(engine.render_context, .DEPTH_PREPASS)
                    pipe_config = pipe_manager_create_pipeline_config_from_render_technique_depth_pre(material.render_technique);
                }
                case .DepthPreAlphaTest: {
                    render_pass_info = renderer_get_render_pass_info(engine.render_context, .DEPTH_PREPASS)
                    pipe_config = pipe_manager_create_pipeline_config_from_render_technique_depth_pre(material.render_technique);
                }
                case .Shadowmap: {
                    render_pass_info = renderer_get_render_pass_info(engine.render_context, .SHADOWMAP)
                    pipe_config = pipe_manager_create_pipeline_config_from_render_technique_shadowmap(material.render_technique);
                }
                case .ShadowmapAlphaTest: {
                    render_pass_info = renderer_get_render_pass_info(engine.render_context, .SHADOWMAP)
                    pipe_config = pipe_manager_create_pipeline_config_from_render_technique_shadowmap(material.render_technique);
                }
            }

            shader_combination := manager.depthonly_pipeline_shader_combinations[depth_only_shader_type];
            vert_shader_id : ShaderID = manager.pipeline_shader_ids[shader_combination.vert];
            frag_shader_id : ShaderID = manager.pipeline_shader_ids[shader_combination.frag];                

            vert_shader := shader_manager_get_or_load_gfx_shader_variant(shader_manager, gpu_device, vert_shader_id, SHADER_VARIANT_EMPTY);
            frag_shader := shader_manager_get_or_load_gfx_shader_variant(shader_manager, gpu_device, frag_shader_id, SHADER_VARIANT_EMPTY);

            engine_assert(vert_shader != nil);
            engine_assert(frag_shader != nil);

            pipeline := pipe_manager_create_graphics_pipeline(gpu_device, vert_shader, frag_shader, &pipe_config, &manager.vertex_buf_descriptor_infos[VertexBufDescriptorType.PositionOnly], &render_pass_info);

            if pipeline != nil {
                log.debugf("Build Pipeline Variant Depthonly: shader_type: {}, depthonly_pipe_hash: {}", depth_only_shader_type, pipe_hash);
                manager.depthonly_pipeline_cache[pipe_hash] = pipeline;
            } else {
                log.errorf("PipeVariantDepthonly: failed to create pipeline")
            }
        }
    }
}

@(private="file")
pipe_manager_create_pipeline_config_from_render_technique_shadowmap :: proc(tech : RenderTechnique) -> PipelineConfig {

    return PipelineConfig {
        raster_fill_mode = .Wireframe in tech.flags ? FillMode.Line : FillMode.Fill,
        raster_cull_mode = tech.cull_mode,
        raster_disable_depth_clip = true, // Hardcoded atm.

        // Depth Stencil
        enable_depth_test   = .EnableDepthTest in tech.flags,
        enable_depth_write  = .EnableDepthWrite in tech.flags, // Note: doing a shadowmap draw with depth write disabled makes not sense
        enable_stencil_test = false, // hardcoded
        depth_stencil_compare_op = CompareOp.LESS_OR_EQUAL,

        // Color Render Target
        enable_blend = false,
    }
}

@(private="file")
pipe_manager_create_pipeline_config_from_render_technique_depth_pre :: proc(tech : RenderTechnique) -> PipelineConfig {

    return PipelineConfig {
        raster_fill_mode = .Wireframe in tech.flags ? FillMode.Line : FillMode.Fill,
        raster_cull_mode = tech.cull_mode,
        raster_disable_depth_clip = false, // Hardcoded atm.

        // Depth Stencil
        enable_depth_test   = .EnableDepthTest in tech.flags,
        enable_depth_write  = .EnableDepthWrite in tech.flags, // Note: doing a depth prepass with depth write disabled makes not sense
        enable_stencil_test = false, // hardcoded
        depth_stencil_compare_op = CompareOp.LESS_OR_EQUAL,

        // Color Render Target
        enable_blend = false,
    }
}

@(private="file")
pipe_manager_create_pipeline_config_from_render_technique :: proc(tech : RenderTechnique) -> PipelineConfig {

    is_blend : bool = tech.alpha_mode == AlphaBlendMode.Blend;

    return PipelineConfig {
        raster_fill_mode = .Wireframe in tech.flags ? FillMode.Line : FillMode.Fill,
        raster_cull_mode = tech.cull_mode,
        raster_disable_depth_clip = false, // Hardcoded atm.

        // Depth Stencil
        enable_depth_test   = .EnableDepthTest in tech.flags,
        enable_depth_write  = .EnableDepthWrite in tech.flags,
        enable_stencil_test = false, // hardcoded
        depth_stencil_compare_op = CompareOp.LESS_OR_EQUAL,

        // Color Render Target
        enable_blend = tech.alpha_mode == AlphaBlendMode.Blend,
        col_target_src_color_blendfactor = tech.blend_config.src_color_blendfactor,
        col_target_dst_color_blendfactor = tech.blend_config.dst_color_blendfactor,
        col_target_color_blend_op        = tech.blend_config.color_blend_op,
        col_target_src_alpha_blendfactor = tech.blend_config.src_alpha_blendfactor,
        col_target_dst_alpha_blendfactor = tech.blend_config.dst_alpha_blendfactor,
        col_target_alpha_blend_op        = tech.blend_config.alpha_blend_op,
    }
}