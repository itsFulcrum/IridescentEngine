package iri


import sdl "vendor:sdl3"
import "core:c"


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


RenderResolution :: enum u8{
	Native	= 0, // same as current window and display settings
	Half 	= 1,
	Quarter = 2,
	Double	= 3,
	Quadruple = 4,
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

DepthStencilFormat :: enum u8{
	D16_UNORM 			= 0,
	D24_UNORM 			= 1,
	D24_UNORM_S8_UINT 	= 2,
	D32_FLOAT			= 3,
	D32_FLOAT_S8_UINT 	= 4,
}

@(private="package")
get_sdl_GPUTextureFormat_from_DepthStencilFormat :: proc(format : DepthStencilFormat) -> sdl.GPUTextureFormat {

	switch (format){
		case DepthStencilFormat.D16_UNORM: 			return sdl.GPUTextureFormat.D16_UNORM;
		case DepthStencilFormat.D24_UNORM: 			return sdl.GPUTextureFormat.D24_UNORM;
		case DepthStencilFormat.D24_UNORM_S8_UINT:	return sdl.GPUTextureFormat.D24_UNORM_S8_UINT;
		case DepthStencilFormat.D32_FLOAT: 			return sdl.GPUTextureFormat.D32_FLOAT;
		case DepthStencilFormat.D32_FLOAT_S8_UINT:	return sdl.GPUTextureFormat.D32_FLOAT_S8_UINT;
	}

	// invalid codepath
	return sdl.GPUTextureFormat.D24_UNORM_S8_UINT;
}

RenderTargetFormat :: enum u8{
	SWAPCHAIN 		= 0,
	RGBA8_UNORM 	,
	RGBA8_SRGB 		,
	RGB10A2_UNORM 	,
	RGBA16_FLOAT 	,
	R32_FLOAT 	    ,
	RG32_FLOAT 	    ,
	RGBA32_FLOAT	,
}

@(private="package")
get_sdl_GPUTextureFormat_from_RenderTargetFormat :: proc(format : RenderTargetFormat) -> sdl.GPUTextureFormat {

	switch (format){
		case RenderTargetFormat.SWAPCHAIN: // this is kinda dirty.
			window := get_window_context()
			return sdl.GetGPUSwapchainTextureFormat(window.gpu_device, window.handle);
		case RenderTargetFormat.RGBA8_UNORM: 	return sdl.GPUTextureFormat.R8G8B8A8_UNORM;
		case RenderTargetFormat.RGBA8_SRGB: 	return sdl.GPUTextureFormat.R8G8B8A8_UNORM_SRGB;
		case RenderTargetFormat.RGB10A2_UNORM:	return sdl.GPUTextureFormat.R10G10B10A2_UNORM;
		case RenderTargetFormat.RGBA16_FLOAT:	return sdl.GPUTextureFormat.R16G16B16A16_FLOAT;
		case RenderTargetFormat.R32_FLOAT:		return sdl.GPUTextureFormat.R32_FLOAT;
		case RenderTargetFormat.RG32_FLOAT:		return sdl.GPUTextureFormat.R32G32_FLOAT;
		case RenderTargetFormat.RGBA32_FLOAT:	return sdl.GPUTextureFormat.R32G32B32A32_FLOAT;
	}

	// invalid codepath
	return sdl.GPUTextureFormat.R8G8B8A8_UNORM;
}

MSAA :: enum u8 {
	OFF	= 0,
	X2	= 2,
	X4	= 4,
	X8	= 8,
}

@(private="package")
get_sdl_GPUSampleCount_from_MSAA :: proc(msaa_samples : MSAA) -> sdl.GPUSampleCount {

	switch (msaa_samples){
		case MSAA.OFF: 	return sdl.GPUSampleCount._1;
		case MSAA.X2: 	return sdl.GPUSampleCount._2;
		case MSAA.X4:	return sdl.GPUSampleCount._4;
		case MSAA.X8: 	return sdl.GPUSampleCount._8;
	}

	panic("Invalid codepath")
}

FillMode :: enum u8 {
	Fill = 0,
	Line = 1,
}

@(private="package")
get_sdl_GPUFillMode_from_FillMode :: proc(fill_mode : FillMode) -> sdl.GPUFillMode {

	switch (fill_mode){
		case FillMode.Fill: return sdl.GPUFillMode.FILL;
		case FillMode.Line: return sdl.GPUFillMode.LINE;
	}
	// invalid codepath
	return sdl.GPUFillMode.FILL;
}

CullMode :: enum u8 {
	None 	= 0,
	Front 	= 1,
	Back 	= 2,
}

@(private="package")
get_sdl_GPUCullMode_from_CullMode :: proc(cull_mode : CullMode) -> sdl.GPUCullMode {

	switch (cull_mode){
		case CullMode.None: 	return sdl.GPUCullMode.NONE;
		case CullMode.Front: 	return sdl.GPUCullMode.FRONT;
		case CullMode.Back: 	return sdl.GPUCullMode.BACK;
	}
	// invalid codepath
	return sdl.GPUCullMode.NONE;
}

CompareOp :: enum u32 {
	NEVER,             /**< The comparison always evaluates false. */
	LESS,              /**< The comparison evaluates reference < test. */
	EQUAL,             /**< The comparison evaluates reference == test. */
	LESS_OR_EQUAL,     /**< The comparison evaluates reference <= test. */
	GREATER,           /**< The comparison evaluates reference > test. */
	NOT_EQUAL,         /**< The comparison evaluates reference != test. */
	GREATER_OR_EQUAL,  /**< The comparison evalutes reference >= test. */
	ALWAYS,            /**< The comparison always evaluates true. */
}

@(private="package")
get_sdl_GPUCompareOp_from_CompareOp :: proc(compare_op : CompareOp) -> sdl.GPUCompareOp {

	switch (compare_op){
		case CompareOp.NEVER: 				return sdl.GPUCompareOp.NEVER;
		case CompareOp.LESS: 				return sdl.GPUCompareOp.LESS;
		case CompareOp.EQUAL: 				return sdl.GPUCompareOp.EQUAL;
		case CompareOp.LESS_OR_EQUAL: 		return sdl.GPUCompareOp.LESS_OR_EQUAL;
		case CompareOp.GREATER: 			return sdl.GPUCompareOp.GREATER;
		case CompareOp.NOT_EQUAL: 			return sdl.GPUCompareOp.NOT_EQUAL;
		case CompareOp.GREATER_OR_EQUAL:	return sdl.GPUCompareOp.GREATER_OR_EQUAL;
		case CompareOp.ALWAYS: 				return sdl.GPUCompareOp.ALWAYS;
	}
	// invalid codepath
	return sdl.GPUCompareOp.ALWAYS;
}

StencilOp :: enum u32 {
	KEEP,                 /**< Keeps the current value. */
	ZERO,                 /**< Sets the value to 0. */
	REPLACE,              /**< Sets the value to reference. */
	INCREMENT_AND_CLAMP,  /**< Increments the current value and clamps to the maximum value. */
	DECREMENT_AND_CLAMP,  /**< Decrements the current value and clamps to 0. */
	INVERT,               /**< Bitwise-inverts the current value. */
	INCREMENT_AND_WRAP,   /**< Increments the current value and wraps back to 0. */
	DECREMENT_AND_WRAP,   /**< Decrements the current value and wraps to the maximum value. */
}

@(private="package")
get_sdl_GPUStencilOp_from_StencilOp :: proc(stencil_op : StencilOp) -> sdl.GPUStencilOp {

	switch (stencil_op){
		case StencilOp.KEEP: 				return sdl.GPUStencilOp.KEEP;
		case StencilOp.ZERO: 				return sdl.GPUStencilOp.ZERO;
		case StencilOp.REPLACE: 			return sdl.GPUStencilOp.REPLACE;
		case StencilOp.INCREMENT_AND_CLAMP: return sdl.GPUStencilOp.INCREMENT_AND_CLAMP;
		case StencilOp.DECREMENT_AND_CLAMP: return sdl.GPUStencilOp.DECREMENT_AND_CLAMP;
		case StencilOp.INVERT:				return sdl.GPUStencilOp.INVERT;
		case StencilOp.INCREMENT_AND_WRAP: 	return sdl.GPUStencilOp.INCREMENT_AND_WRAP;
		case StencilOp.DECREMENT_AND_WRAP: 	return sdl.GPUStencilOp.DECREMENT_AND_WRAP;
	}
	// invalid codepath
	return sdl.GPUStencilOp.KEEP;
}

BlendOp :: enum u32 {
	ADD,               /**< (source * source_factor) + (destination * destination_factor) */
	SUBTRACT,          /**< (source * source_factor) - (destination * destination_factor) */
	REVERSE_SUBTRACT,  /**< (destination * destination_factor) - (source * source_factor) */
	MIN,               /**< min(source, destination) */
	MAX,               /**< max(source, destination) */
}

@(private="package")
get_sdl_GPUBlendOp_from_BlendOp :: proc(blend_op : BlendOp) -> sdl.GPUBlendOp {

	switch (blend_op){
		case BlendOp.ADD: 				return sdl.GPUBlendOp.ADD;
		case BlendOp.SUBTRACT: 			return sdl.GPUBlendOp.SUBTRACT;
		case BlendOp.REVERSE_SUBTRACT: 	return sdl.GPUBlendOp.REVERSE_SUBTRACT;
		case BlendOp.MIN: 				return sdl.GPUBlendOp.MIN;
		case BlendOp.MAX: 				return sdl.GPUBlendOp.MAX;
	}
	// invalid codepath
	return sdl.GPUBlendOp.ADD;
}

BlendFactor :: enum u32 {
	ZERO,                      /**< 0 */
	ONE,                       /**< 1 */
	SRC_COLOR,                 /**< source color */
	ONE_MINUS_SRC_COLOR,       /**< 1 - source color */
	DST_COLOR,                 /**< destination color */
	ONE_MINUS_DST_COLOR,       /**< 1 - destination color */
	SRC_ALPHA,                 /**< source alpha */
	ONE_MINUS_SRC_ALPHA,       /**< 1 - source alpha */
	DST_ALPHA,                 /**< destination alpha */
	ONE_MINUS_DST_ALPHA,       /**< 1 - destination alpha */
	CONSTANT_COLOR,            /**< blend constant */
	ONE_MINUS_CONSTANT_COLOR,  /**< 1 - blend constant */
	SRC_ALPHA_SATURATE,        /**< min(source alpha, 1 - destination alpha) */
}

@(private="package")
get_sdl_GPUBlendFactor_from_BlendFactor :: proc(blend_factor : BlendFactor) -> sdl.GPUBlendFactor {

	switch (blend_factor){
		case BlendFactor.ZERO: 						return sdl.GPUBlendFactor.ZERO;
		case BlendFactor.ONE: 						return sdl.GPUBlendFactor.ONE;
		case BlendFactor.SRC_COLOR: 				return sdl.GPUBlendFactor.SRC_COLOR;
		case BlendFactor.ONE_MINUS_SRC_COLOR: 		return sdl.GPUBlendFactor.ONE_MINUS_SRC_COLOR;
		case BlendFactor.DST_COLOR: 				return sdl.GPUBlendFactor.DST_COLOR;
		case BlendFactor.ONE_MINUS_DST_COLOR: 		return sdl.GPUBlendFactor.ONE_MINUS_DST_COLOR;
		case BlendFactor.SRC_ALPHA: 				return sdl.GPUBlendFactor.SRC_ALPHA;
		case BlendFactor.ONE_MINUS_SRC_ALPHA: 		return sdl.GPUBlendFactor.ONE_MINUS_SRC_ALPHA;
		case BlendFactor.DST_ALPHA: 				return sdl.GPUBlendFactor.DST_ALPHA;
		case BlendFactor.ONE_MINUS_DST_ALPHA: 		return sdl.GPUBlendFactor.ONE_MINUS_DST_ALPHA;
		case BlendFactor.CONSTANT_COLOR: 			return sdl.GPUBlendFactor.CONSTANT_COLOR;
		case BlendFactor.ONE_MINUS_CONSTANT_COLOR:	return sdl.GPUBlendFactor.ONE_MINUS_CONSTANT_COLOR;
		case BlendFactor.SRC_ALPHA_SATURATE: 		return sdl.GPUBlendFactor.SRC_ALPHA_SATURATE;
	}
	// invalid codepath
	return sdl.GPUBlendFactor.ZERO;
}


@(private="package")
QueryBufferUploadInfo :: struct {
	requires_upload       : bool,
	transfer_buf_location : sdl.GPUTransferBufferLocation,
	transfer_buf_region   : sdl.GPUBufferRegion,
}