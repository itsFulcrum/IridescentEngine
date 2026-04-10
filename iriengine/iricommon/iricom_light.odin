package iricom

LightType :: enum u8 { 
	DIRECTIONAL = 0,
	POINT = 1,
	SPOT = 2,
}


SHADOWMAP_MAX_RESOLUTION :: 4096
SHADOWMAP_MIN_RESOLUTION :: 32

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