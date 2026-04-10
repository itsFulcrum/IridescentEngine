package iri

import iricom "iricommon"

import sdl "vendor:sdl3"
import "core:c"

RenderResolution :: iricom.RenderResolution


FrameCameraInfo :: struct  {
    position_ws  : [3]f32,
    direction_ws : [3]f32,

	view_mat : matrix[4,4]f32,
    proj_mat : matrix[4,4]f32,
    view_proj_mat: matrix[4,4]f32,

    inv_view_mat : matrix[4,4]f32,
    inv_proj_mat : matrix[4,4]f32,
    inv_view_proj_mat : matrix[4,4]f32,

    fov_radians : f32,
    near_plane : f32,
    far_plane  : f32,
    camera_exposure : f32,

    // These may be different when using a different camera for frustum cullen then rendering camera
    frustum_view_mat : matrix[4,4]f32,
    frustum_proj_mat : matrix[4,4]f32,
    culling_frustum : CullingFrustum,

    // directional light shadow map cascades
    shadow_cascade_proj_mats : [3]matrix[4,4]f32,
}



// GPU UBO Structure

// Mirrors a shader UBO struct must be 16byte aligned
GlobalVertexUBO :: struct #align(16) {
    view_mat : matrix[4,4]f32,
    proj_mat : matrix[4,4]f32,
    view_proj_mat : matrix[4,4]f32,
}

DepthPreVertexUBO :: struct #align(16) {
    view_proj_mat : matrix[4,4]f32,
}

GlobalFragmentBuffer :: struct #align(16) {
	camera_pos_ws : [3]f32,
	time_seconds  : f32,
	camera_dir_ws : [3]f32,
	near_plane    : f32,
	frame_size    : [2]u32,
	far_plane     : f32,
	cascade_frust_split_1  : f32,
	cascade_frust_split_2  : f32,
	cascade_frust_split_3  : f32,
	camera_exposure  : f32,
	padding4  : f32,
	//inv_view_proj_mat : matrix[4,4]f32,
}

// Mirrors a shader UBO struct must be 16byte aligned
MeshVertexUBO :: struct #align(16) {
    model_mat : matrix[4,4]f32,
}

VertexShadowmapUBO :: struct #align(16) {
    view_proj_mat : matrix[4,4]f32,
}

VertexDrawInstanceUBO :: struct #align(16) {
	drawable_index : u32,
	padding1 : u32,
	padding2 : u32,
	padding3 : u32,
}

MatUBO :: struct #align(16) {
	mat_index : u32
}

// Mirrors a shader UBO struct must be 16byte aligned
PostProcessSettingsUBO :: struct #align(16) {
	exposure: f32,
	tone_map_mode: u32,
	convert_to_srgb: b8,
	padding1 : u8, 
	padding2 : u8, 
	padding3 : u8, 
}

DepthStencilFormat :: iricom.DepthStencilFormat
RenderTargetFormat :: iricom.RenderTargetFormat

MSAA :: iricom.MSAA
FillMode :: iricom.FillMode
CullMode :: iricom.CullMode
CompareOp :: iricom.CompareOp
StencilOp :: iricom.StencilOp
BlendOp :: iricom.BlendOp
BlendFactor :: iricom.BlendFactor
PrimitiveType :: iricom.PrimitiveType

get_sdl_GPUTextureFormat_from_DepthStencilFormat :: iricom.DepthStencilFormat_to_sdl_GPUTextureFormat
get_sdl_GPUTextureFormat_from_RenderTargetFormat :: iricom.RenderTargetFormat_to_sdl_GPUTextureFormat
get_sdl_GPUSampleCount_from_MSAA :: iricom.MSAA_to_sdl_GPUSampleCount
get_sdl_GPUFillMode_from_FillMode :: iricom.FillMode_to_sdl_GPUFillMode
get_sdl_GPUCullMode_from_CullMode :: iricom.CullMode_to_sdl_GPUCullMode
get_sdl_GPUCompareOp_from_CompareOp :: iricom.CompareOp_to_sdl_GPUCompareOp
get_sdl_GPUStencilOp_from_StencilOp :: iricom.StencilOp_to_sdl_GPUStencilOp
get_sdl_GPUBlendOp_from_BlendOp :: iricom.BlendOp_to_sdl_GPUBlendOp
get_sdl_GPUBlendFactor_from_BlendFactor :: iricom.BlendFactor_to_sdl_GPUBlendFactor
PrimitiveType_to_sdl_GPUPrimitiveType :: iricom.PrimitiveType_to_sdl_GPUPrimitiveType


@(private="package")
QueryBufferUploadInfo :: struct {
	requires_upload       : bool,
	transfer_buf_location : sdl.GPUTransferBufferLocation,
	transfer_buf_region   : sdl.GPUBufferRegion,
}