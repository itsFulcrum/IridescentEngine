package iri

SHADOWMAP_MAX_RESOLUTION :: 4096
SHADOWMAP_MIN_RESOLUTION :: 32
SHADOWMAP_MAX_MIP_LEVEL :: 7

ShadowmapResolution :: enum u32 {
	_4096 = 4096,
	_2048 = 2048,
	_1024 = 1024,
	_512  = 512,
	_256  = 256,
	_128  = 128,
	_64   = 64,
	_32   = 32,
}

shadowmap_resolution_to_mip_level:: proc(shadow_res : ShadowmapResolution) -> u32{

	switch shadow_res {
		case ._4096: return 0;
		case ._2048: return 1;
		case ._1024: return 2;
		case ._512 : return 3;
		case ._256 : return 4;
		case ._128 : return 5;
		case ._64  : return 6;
		case ._32  : return 7;
	}

	panic("invalid codepath")
}



// This is used for a 'data structure' in light_manager to keep track of which spots are taken in the shadowmap array
ShadowmapMipLevelFlags :: distinct bit_set[ShadowmapMipLevelEnum]
ShadowmapMipLevelEnum :: enum u8{
	_0 = 0,
	_1 = 1,
	_2 = 2,
	_3 = 3,
	_4 = 4,
	_5 = 5,
	_6 = 6,
	_7 = 7,
}

ShadowmapInfoGPU :: struct #align(16) {
	view_proj : matrix[4,4]f32,
	array_layer : i32, // -1 == unused spot..
	mip_level   : u32,
	resolution  : u32,
	texels_per_world_unit : f32,
}


ShadowmapInfo :: union {
	ShadowmapInfoDirectionalLight,
	ShadowmapInfoPointLight,
	ShadowmapInfoSpotLight
}


ShadowmapInfoDirectionalLight :: struct{
	shadow_cascade_resolutions : [3]ShadowmapResolution,
}

ShadowmapInfoSpotLight :: struct{
	resolution : ShadowmapResolution,
}

ShadowmapInfoPointLight :: struct{
	resolution : ShadowmapResolution,
}