package iri

import "core:math/linalg"

import sdl "vendor:sdl3"


Universe :: struct {
	ecs : EntityComponentData,
	active_camera_entity : Entity,
	active_skybox_entity : Entity,

	frame_camera_info : FrameCameraInfo,

	skybox_data_is_dirty : bool,
	skybox_data : SkyboxGPUData,
	skybox_transfer_buffer : ^sdl.GPUTransferBuffer, // Note maybe we should have a transfer buffer for multiple things ..?
	skybox_gpu_buffer : ^sdl.GPUBuffer,

	light_manager : LightManager,

	shadow_cascade_near_far_scale : f32,
	shadow_cascade_side_scale : f32,
	shadow_cascade_split_1 : f32,
	shadow_cascade_split_2 : f32,
	shadow_cascade_split_3 : f32,

	cull_shadow_draws : bool,
    do_frustum_culling : bool,
	frustum_cull_camera_entity : Entity, // if we want to use different camera for frustum culling

	matrix_buf : ^sdl.GPUBuffer,
	matrix_transfer_buf : ^sdl.GPUTransferBuffer,
	matrix_upload_info : QueryBufferUploadInfo,
	matrix_buf_byte_size : int,


	// indexes into ecs.drawables
	frame_renderables : [dynamic]u32, // subset ecs.drawables camera culled.
	
	frame_opaques : [dynamic]u32,
	frame_alpha_test : [dynamic]u32,
	frame_alpha_blend : [dynamic]u32,

	debug_test_float : f32,
}






@(private="package")
universe_init :: proc(gpu_device : ^sdl.GPUDevice, universe : ^Universe, reserve_mem_for_n_entities : u32 = 20) {
	engine_assert(universe != nil);

	ecs_init(&universe.ecs , reserve_mem_for_n_entities);
	
	universe.active_camera_entity.id = -1;
	universe.active_skybox_entity.id = -1;

	universe.cull_shadow_draws = true;
	universe.do_frustum_culling = true;
	universe.frustum_cull_camera_entity.id = -1;
	
	universe.shadow_cascade_near_far_scale = 2.0;
	universe.shadow_cascade_side_scale = 1.0;

	// Shadow map cascade splits for directional lights.
	universe.shadow_cascade_split_1 = 0.05; // percentage between near and far
	universe.shadow_cascade_split_2 = 0.25; // percentage between near and far
	universe.shadow_cascade_split_3 = 0.60; // percentage between near and far

	// Skybox 
	{
		universe.skybox_data_is_dirty = true;
		// skybox_gpu_data_set_defaults(&manager.skybox_data); // will happen during update

		skybox_gpu_buffer_create_info := sdl.GPUBufferCreateInfo{
			usage = sdl.GPUBufferUsageFlags{.GRAPHICS_STORAGE_READ, .COMPUTE_STORAGE_READ, .COMPUTE_STORAGE_WRITE},
			size = size_of(SkyboxGPUData),
		}

		universe.skybox_gpu_buffer = sdl.CreateGPUBuffer(gpu_device, skybox_gpu_buffer_create_info);

		skybox_gpu_transfer_buf_create_info := sdl.GPUTransferBufferCreateInfo{
			usage = sdl.GPUTransferBufferUsage.UPLOAD,
			size = size_of(SkyboxGPUData),
		}

		universe.skybox_transfer_buffer = sdl.CreateGPUTransferBuffer(gpu_device, skybox_gpu_transfer_buf_create_info)
	}

	// Light manager
	light_manager_init(gpu_device, &universe.light_manager);


}

@(private="package")
universe_deinit :: proc(gpu_device : ^sdl.GPUDevice, universe : ^Universe) {
	engine_assert(universe != nil);

	ecs_destroy(&universe.ecs);
	universe.active_camera_entity.id = -1;
	universe.active_skybox_entity.id = -1;

	// skybox buffer
	if universe.skybox_gpu_buffer != nil {
		sdl.ReleaseGPUBuffer(gpu_device, universe.skybox_gpu_buffer);
		universe.skybox_gpu_buffer = nil;
	}

	if universe.skybox_transfer_buffer != nil {
		sdl.ReleaseGPUTransferBuffer(gpu_device, universe.skybox_transfer_buffer);
		universe.skybox_transfer_buffer = nil;
	}

	// Matrix buffer
	if universe.matrix_buf != nil {
		sdl.ReleaseGPUBuffer(gpu_device, universe.matrix_buf);
		universe.matrix_buf = nil;
	}

	if universe.matrix_transfer_buf != nil {
		sdl.ReleaseGPUTransferBuffer(gpu_device, universe.matrix_transfer_buf);
		universe.matrix_transfer_buf = nil;
	}


	light_manager_deinit(gpu_device, &universe.light_manager);

	delete(universe.frame_renderables)
	delete(universe.frame_opaques); 
	delete(universe.frame_alpha_test); 
	delete(universe.frame_alpha_blend);
}


// Set an existing entity with a camera component attached to it as the active camera used for rendering
universe_set_active_camera_entity :: proc(universe : ^Universe, entity : Entity) -> bool {
	
	engine_assert(universe != nil);

	if(!ecs_component_is_attached(&universe.ecs, entity, ComponentType.Camera)) {
		return false;
	}

	universe.active_camera_entity = entity;

	return true;
}

// Set an existing entity with a skybox component attached to it as the active skybox used for rendering
universe_set_active_skybox_entity :: proc(universe : ^Universe, entity : Entity) -> bool {
	
	engine_assert(universe != nil);

	if(!ecs_component_is_attached(&universe.ecs, entity, ComponentType.Skybox)) {
		return false;
	}

	universe.active_skybox_entity = entity;

	universe.skybox_data_is_dirty = true;

	return true;
}

universe_push_skybox_changes :: proc(universe : ^Universe, comp : ^SkyboxComponent){
	
	if(universe.active_skybox_entity.id != comp.entity.id){
		return;
	}

	universe.skybox_data_is_dirty = true;
}


universe_has_active_camera :: proc (universe : ^Universe) -> bool {

	return ecs_component_is_attached(&universe.ecs, universe.active_camera_entity, ComponentType.Camera);
}

// returns nill if no active skybox is set
@(private="package")
universe_get_active_skybox_component :: proc(universe : ^Universe) -> ^SkyboxComponent {

	if(universe.active_skybox_entity.id >= 0){

		if(ecs_component_is_attached(&universe.ecs, universe.active_skybox_entity, ComponentType.Skybox)){

			sky_comp , err := ecs_get_component(&universe.ecs, universe.active_skybox_entity, SkyboxComponent);
			engine_assert(sky_comp != nil);
			return sky_comp;
		}
	}

	return nil;
}


