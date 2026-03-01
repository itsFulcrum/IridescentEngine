package iri

BASE_SKYBOX_EXPOSURE :: 8.0

// Mirrors shader struct in skybox.glsl
SkyboxGPUData :: struct #align(16) {
	sun_direction : [3]f32,
	sun_strength  : f32,

	sun_color     : [3]f32,
	use_cubemap   : f32, // 0 if no cubemap 1 when using cubemap

	color_zenith  : [3]f32,
	exposure      : f32, 

	color_horizon : [3]f32,
	rotation      : f32, 

	color_nadir   : [3]f32,
	max_cubemap_mip  : u32, 
}

skybox_gpu_data_set_defaults :: proc(skybox_data : ^SkyboxGPUData) {

	skybox_data.sun_direction 	= {0.0,-1.0,0.0};
	skybox_data.sun_strength 	= 1.0;
	skybox_data.sun_color 		= {1.0,1.0,1.0};
	skybox_data.use_cubemap = 0.0;

	// TODO: make better defaults
	skybox_data.color_zenith 	= {1.0,1.0,1.0};
	skybox_data.color_horizon 	= {1.0,1.0,1.0};
	skybox_data.color_nadir 	= {1.0,1.0,1.0};

	skybox_data.exposure = BASE_SKYBOX_EXPOSURE;
	skybox_data.rotation = 0.0;

	skybox_data.max_cubemap_mip = 0;
}