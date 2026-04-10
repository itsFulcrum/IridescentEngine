package iri

import "core:math/linalg"
import "core:encoding/uuid"
import "core:strings"
import iria "iriasset"

import sdl "vendor:sdl3"


Universe :: struct {
	name : string, // Readonly, use 'universe_rename()' to rename
	tag : u32,
	asset_uuid : AssetUUID,

	ecs : ECData,

	frame_camera_info : FrameCameraInfo,

	//skybox_data_is_dirty : bool,
	skybox_data : SkyboxGPUData,
	skybox_transfer_buffer : ^sdl.GPUTransferBuffer, // Note maybe we should have a transfer buffer for multiple things ..?
	skybox_gpu_buffer : ^sdl.GPUBuffer,

	light_manager : LightManager,

	shadow_cascade_near_far_scale 	: f32,
	shadow_cascade_side_scale 		: f32,
	shadow_cascade_split_1 			: f32, // percentage between near and far
	shadow_cascade_split_2 			: f32, // percentage between near and far
	shadow_cascade_split_3 			: f32, // percentage between near and far

	cull_shadow_draws 			: bool,
    do_frustum_culling 			: bool,
	frustum_cull_camera_entity 	: Entity, // if we want to use different camera for frustum culling

	matrix_buf : ^sdl.GPUBuffer,
	matrix_transfer_buf : ^sdl.GPUTransferBuffer,
	matrix_upload_info : QueryBufferUploadInfo,
	matrix_buf_byte_size : int,

	// indexes into ecs.drawables
	frame_renderables 	 : [dynamic]u32, // subset ecs.drawables. only drawbles with valid data and enabled entities.
	
	frame_camera_visible : [dynamic]u32, // subset frame_renderables. camera / distance culled
	frame_opaques 		 : [dynamic]u32, // subset frame_camera_visible. only opaques
	frame_alpha_test 	 : [dynamic]u32, // subset frame_camera_visibly. only alpha test
	frame_alpha_blend 	 : [dynamic]u32, // subset frame_camera_visible. only blend

	debug_test_float : f32,
}

universe_init :: proc(universe : ^Universe, uni_asset : ^iria.UniverseAsset = nil) {
	
	gpu_device := get_gpu_device();

	engine_assert(universe != nil);


	num_reserve : u32 = uni_asset == nil ? 16 : max(16, uni_asset.num_entities);

	ecs_init(&universe.ecs, num_reserve);


	if  uni_asset != nil {
		
		if len(uni_asset.name) >  0 {
			universe.name = strings.clone(uni_asset.name, context.allocator);
		}
		
		universe.asset_uuid = uni_asset.asset_uuid;
		universe.tag = uni_asset.tag;
	}

	// TODO: should also be stored in uni_asset.
	universe.frustum_cull_camera_entity.id = -1;
	
	settings : ^iria.UniverseAssetSettings = uni_asset != nil ? &uni_asset.settings : nil;

	universe.cull_shadow_draws 				= settings == nil ? true : cast(bool)settings.cull_shadow_draws;
	universe.do_frustum_culling 			= settings == nil ? true : cast(bool)settings.do_frustum_culling;
	universe.shadow_cascade_near_far_scale 	= settings == nil ? 2.0  : settings.shadow_cascade_near_far_scale;
	universe.shadow_cascade_side_scale 		= settings == nil ? 1.0  : settings.shadow_cascade_side_scale;

	// Shadow map cascade splits for directional lights.
	universe.shadow_cascade_split_1 = settings == nil ? 0.05 : settings.shadow_cascade_split_1;
	universe.shadow_cascade_split_2 = settings == nil ? 0.25 : settings.shadow_cascade_split_2;
	universe.shadow_cascade_split_3 = settings == nil ? 0.60 : settings.shadow_cascade_split_3; 


	// Skybox 
	{
		universe.ecs.active_skybox_is_dirty = true;

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


	// Serialize with data stored in the unverser asset loaded from disk

	if uni_asset == nil {
		return;
	}

	num_ents : int = cast(int)uni_asset.num_entities;

	if num_ents <= 0 {
		return;
	}

	engine_assert(num_ents == len(uni_asset.entity_infos))
	engine_assert(num_ents == len(uni_asset.entity_trans))
	engine_assert(num_ents == len(uni_asset.entity_names))

	for id in 0..<num_ents {

		packed_info := &uni_asset.entity_infos[id];

		name : string = len(uni_asset.entity_names[id]) > 0 ? uni_asset.entity_names[id] : string("NewEntity");

		entity := entity_create(packed_info.comp_set, name, packed_info.tag, universe);

		trans_comp := ecs_get_transform(&universe.ecs, entity);
		trans_comp.transform = uni_asset.entity_trans[id];

		ent_comp_indexes : iria.CompIndexes = uni_asset.entity_comp_indexes[id];

		for comp_type in packed_info.comp_set {
			#partial switch comp_type {
				case .Camera: {
					comp, err := ecs_get_component(&universe.ecs, entity, CameraComponent);
					engine_assert(comp != nil);
					engine_assert(ent_comp_indexes.camera_index > -1)
					comp_data := uni_asset.camera_comp_data[ent_comp_indexes.camera_index];

					comp.data = comp_data;
				}
				case .Skybox: {
					comp, err := ecs_get_component(&universe.ecs, entity, SkyboxComponent);
					engine_assert(comp != nil);
					engine_assert(ent_comp_indexes.skybox_index > -1)
					comp_data := uni_asset.skybox_comp_data[ent_comp_indexes.skybox_index];
					comp.data = comp_data;
				}
				case .Light: {
					comp, err := ecs_get_component(&universe.ecs, entity, LightComponent);
					engine_assert(comp != nil);
					engine_assert(ent_comp_indexes.light_index > -1)
					
					comp_light_init_from_light_asset(comp, uni_asset.light_comp_data[ent_comp_indexes.light_index] , true)
				}
				case .MeshRenderer: {
					comp, err := ecs_get_component(&universe.ecs, entity, MeshRendererComponent);
					engine_assert(comp != nil);
					engine_assert(ent_comp_indexes.meshren_index > -1)

					meshren_data := uni_asset.meshren_comp_data[ent_comp_indexes.meshren_index];

					num : int = cast(int)meshren_data.num_drawable_assets;
					offset : int = cast(int)meshren_data.array_offset;

					if num > 0 {
						comp_meshrenderer_append_drawable_assets(comp, uni_asset.drawable_assets_array[offset:offset+num], build_pipeline_cache = false)
					}
				}
			}
		}

		// update pipe cache for all drawables at once instead of per drawable asset we add.
		pipe_manager := engine.pipeline_manager;
		pipe_manager_update_material_and_depthonly_pipeline_cache_for_universe(pipe_manager, gpu_device, universe);
	}
	
	// Maybe we should do validation that the corresponding entities we just created 
	// actually have the components but if we wrote the asset file correctly these should
	// just be correct since we just created entities now, didnt remove any and their
	// id's should be the same as stored in the universe_asset.
	if uni_asset.active_camera_entity > -1 {
		universe.ecs.active_camera_entity.id = cast(i32)uni_asset.active_camera_entity;
	}

	if uni_asset.active_skybox_entity > -1 {
		universe.ecs.active_skybox_entity.id = cast(i32)uni_asset.active_skybox_entity;
		universe.ecs.active_skybox_is_dirty = true;
	}
}

universe_deinit :: proc(universe : ^Universe) {
	
	gpu_device := get_gpu_device();

	engine_assert(universe != nil);

	ecs_destroy(&universe.ecs);
	
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

	if len(universe.name) > 0 {
		delete_string(universe.name)
	}

	light_manager_deinit(gpu_device, &universe.light_manager);

	delete(universe.frame_renderables)
	delete(universe.frame_camera_visible)
	delete(universe.frame_opaques); 
	delete(universe.frame_alpha_test); 
	delete(universe.frame_alpha_blend);
}

universe_rename :: proc(universe : ^Universe, new_name : string) {
	if universe == nil {
		return;
	}

	if len(universe.name) > 0 {
		delete(universe.name);
	}
	universe.name = strings.clone(new_name, context.allocator);
	asset_manager_update_universe_name(engine.asset_manager, universe.asset_uuid, universe.name);
}
