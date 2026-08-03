package iri

import "core:mem"
import "core:log"
import "core:strings"
import sdl "vendor:sdl3"

import iricom "iricommon"
import iria "iriasset"

// TODO: write some better comments and documentaiton..

MaterialID :: iricom.MaterialID // == u32

MaterialsPerfCounters :: struct {

	num_registered_mats : u32,

	gpu_num_pbr   : u32,
	gpu_num_unlit : u32,

	gpu_pbr_buf_size   : u32, // In bytes
	gpu_unlit_buf_size : u32, // In bytes
}

MaterialManager :: struct {

	// Note: A 'MaterialID' is used to lookup the actual material array index inside the 'material_indexes' list.
	// OR to get the array index of its corresponding GPU representation using the 'material_gpu_indexes' list.
	// e.g: mat = materials[material_indexes[MaterialID]] -> in reality one must check if material_indexes[MaterialID] equals -1 and would therfore not point to a material

	material_indexes: 		[dynamic]int, // indexes into materials array
	material_gpu_indexes: 	[dynamic]int, // indexes into type respective gpu material arrays
	material_enum_type:		[dynamic]MaterialShaderType, // the type in enum form for a given MaterialID
	
	materials: [dynamic]Material,		// sparse/compact material array
	material_render_technique_hashes: [dynamic]RenderTechniqueHash, // same order as materials array, so use same index as for material to get the technique hash

	// stores indexes into gpu materials arrays that need updating..
	gpu_index_update_queue: [MaterialShaderType][dynamic]int,

	unlit_materials_gpu: [dynamic]UnlitMaterialDataGPU,
	pbr_materials_gpu:   [dynamic]PbrMaterialDataGPU,

	// upload infos for each material type that requires it.
	// updated each frame in manager_update and read by renderer.
	frame_upload_info: 		[MaterialShaderType]QueryBufferUploadInfo, 

	gpu_mat_buf_size: 		[MaterialShaderType]int, // Current buffer size of the gpu buffers.
	gpu_mat_buf: 			[MaterialShaderType]^sdl.GPUBuffer, // a seperate GPU buffer fo each material type.
	gpu_mat_transfer_buf: 	[MaterialShaderType]^sdl.GPUTransferBuffer, // a seperate Transfer buffer for each material type.



	fallback_material : MaterialID,
	//default_material : MaterialID,
}

// Note: Must be updated when adding new material type
@(private="file")
material_manager_get_gpu_array_len_for_type :: proc(manager : ^MaterialManager, type: MaterialShaderType) -> int {
	
	switch type {
		case .None: 	return 0;
		case .Pbr:		return len(manager.pbr_materials_gpu);
		case .Unlit:	return len(manager.unlit_materials_gpu);
		case .Custom:	return 0;
	}

	return 0;
}

// Note: Must be updated when adding new material type
@(private="file")
material_manager_get_gpu_element_byte_size_for_type :: proc(type: MaterialShaderType) -> int {
	switch type {
		case .None: 	return 0;
		case .Pbr:		return size_of(PbrMaterialDataGPU);
		case .Unlit:	return size_of(UnlitMaterialDataGPU);
		case .Custom:	return 0;
	}

	return 0;
}

// Note: Must be updated when adding new material type
@(private="file")
material_manager_cast_gpu_array_to_byte_multiptr :: proc(manager : ^MaterialManager, type: MaterialShaderType) -> [^]byte {
	
	switch type {
		case .None: 	return nil;
		case .Pbr:		return cast([^]byte)&manager.pbr_materials_gpu[0];
		case .Unlit:	return cast([^]byte)&manager.unlit_materials_gpu[0];
		case .Custom:	return nil;
	}

	return nil;
}

@(private="package")
material_manager_init :: proc(manager : ^MaterialManager){

	fallback_mat : Material;
	fallback_mat.name = "Iri Default Fallback";
	fallback_mat.render_technique = render_technique_create_default_opaque();
	fallback_mat.variant = UnlitMaterialVariant {
		albedo_color = {1.0, 0.0, 1.0},
		alpha_value = 1.0,
	}

	manager.fallback_material = material_manager_add_material(manager, &fallback_mat)
	
	// default_mat : Material;
	// default_mat.variant = UnlitMaterialVariant {
	// 	albedo_color = {1.0, 0.0, 1.0},
	// 	alpha_value = 1.0,
	// }

	//manager.default_material = material_manager_add_material(manager, default_mat)
}

@(private="package")
material_manager_deinit :: proc(manager : ^MaterialManager, gpu_device: ^sdl.GPUDevice){

	delete(manager.material_indexes);
	delete(manager.material_gpu_indexes);
	delete(manager.material_enum_type);

	for &mat in manager.materials {
		iricom.material_free_contents(&mat);
	}
	delete(manager.materials);

	delete(manager.pbr_materials_gpu);
	delete(manager.unlit_materials_gpu);

	for mat_type in MaterialShaderType{
		
		delete(manager.gpu_index_update_queue[mat_type]);

		if manager.gpu_mat_buf[mat_type] != nil {
			sdl.ReleaseGPUBuffer(gpu_device, manager.gpu_mat_buf[mat_type]);
		}

		if manager.gpu_mat_transfer_buf[mat_type] != nil {
			sdl.ReleaseGPUTransferBuffer(gpu_device, manager.gpu_mat_transfer_buf[mat_type]);
		}
	}

	//delete(manager.id_map)

	delete(manager.material_render_technique_hashes);
}


@(private="package")
material_manager_update :: proc(manager : ^MaterialManager, gpu_device: ^sdl.GPUDevice){

	for mat_type in MaterialShaderType {
		if mat_type == .None || mat_type == .Custom {
			continue;
		}

		manager.frame_upload_info[mat_type] = material_manager_update_material_buffer(manager, gpu_device, mat_type);
	}

	// update counters.
	perf_counters := get_performance_counters();
	mat_counters := &perf_counters.material_counters;

	mat_counters.num_registered_mats = cast(u32)len(manager.materials)

	mat_counters.gpu_num_pbr   = cast(u32)len(manager.pbr_materials_gpu)
	mat_counters.gpu_num_unlit = cast(u32)len(manager.unlit_materials_gpu)

	mat_counters.gpu_pbr_buf_size   = cast(u32)manager.gpu_mat_buf_size[.Pbr]
	mat_counters.gpu_unlit_buf_size = cast(u32)manager.gpu_mat_buf_size[.Unlit]
}

@(private="file")
material_manager_update_material_buffer :: proc(manager : ^MaterialManager, gpu_device: ^sdl.GPUDevice, mat_type: MaterialShaderType) -> (upload_info : QueryBufferUploadInfo) {
	
	// @Note: Custom materials currently dont have their own gpu buffer.
	if mat_type == .None || mat_type == .Custom {
		return;
	}

	if manager.frame_upload_info[mat_type].requires_upload {
		// if a previous upload has not yet happend we must wait until it got uploaded.
		// since we would otherwise run risk of loosing data if we just start
		// overwriting the upload info.
		upload_info = manager.frame_upload_info[mat_type];
		return;
	}

	gpu_array_len:         int 	= material_manager_get_gpu_array_len_for_type(manager, mat_type);
	gpu_element_byte_size: int 	= material_manager_get_gpu_element_byte_size_for_type(mat_type);

	required_gpu_buf_size : int = gpu_array_len * gpu_element_byte_size

	curr_gpu_buf_size : int = manager.gpu_mat_buf_size[mat_type]
	
	size_got_bigger 	: bool = required_gpu_buf_size > curr_gpu_buf_size
	size_shrank_in_half : bool = required_gpu_buf_size < (curr_gpu_buf_size / 2)
	size_shrank_to_zero : bool = required_gpu_buf_size == 0

	reallocate_gpu_buffer : bool = size_got_bigger || size_shrank_in_half || size_shrank_to_zero;

	if reallocate_gpu_buffer {

		// Release Old Buffers 
		if manager.gpu_mat_buf[mat_type] != nil {
			sdl.ReleaseGPUBuffer(gpu_device, manager.gpu_mat_buf[mat_type]);
			manager.gpu_mat_buf[mat_type] = nil;
		}
		if manager.gpu_mat_transfer_buf[mat_type] != nil {
			sdl.ReleaseGPUTransferBuffer(gpu_device, manager.gpu_mat_transfer_buf[mat_type]);
			manager.gpu_mat_transfer_buf[mat_type] = nil;
		}

		// Since we reupload everything anyway we can clear the update queue.
		clear(&manager.gpu_index_update_queue[mat_type]);
		
		// Return if we dont need a buffer right now.
		if size_shrank_to_zero {
			manager.gpu_mat_buf_size[mat_type] = 0;
			upload_info.requires_upload = false;
			return upload_info;
		}

		// Create New Buffers.
		gpu_buf_create_info : sdl.GPUBufferCreateInfo = {
    		usage = {sdl.GPUBufferUsageFlag.GRAPHICS_STORAGE_READ},
    		size  =  cast(u32)required_gpu_buf_size,
		};

		transfer_buf_create_info : sdl.GPUTransferBufferCreateInfo = {
	        usage = sdl.GPUTransferBufferUsage.UPLOAD,
	        size  = cast(u32)required_gpu_buf_size,
	    }

		manager.gpu_mat_buf[mat_type] = sdl.CreateGPUBuffer(gpu_device, gpu_buf_create_info);
	    manager.gpu_mat_transfer_buf[mat_type] = sdl.CreateGPUTransferBuffer(gpu_device, transfer_buf_create_info);		

		manager.gpu_mat_buf_size[mat_type] = required_gpu_buf_size;


		// Upload all data to the transfer buffer.
		transfer_buf_data_ptr : rawptr = sdl.MapGPUTransferBuffer(gpu_device, manager.gpu_mat_transfer_buf[mat_type], false);

    	byte_ptr : [^]byte = material_manager_cast_gpu_array_to_byte_multiptr(manager, mat_type);

    	mem.copy_non_overlapping(transfer_buf_data_ptr, &byte_ptr[0], required_gpu_buf_size);

    	sdl.UnmapGPUTransferBuffer(gpu_device, manager.gpu_mat_transfer_buf[mat_type]);

    	// Setup upload info.
    	upload_info.requires_upload = true;

    	upload_info.transfer_buf_location = {
    		transfer_buffer = manager.gpu_mat_transfer_buf[mat_type],
    		offset = 0,
    	}

    	upload_info.transfer_buf_region = {
    		buffer = manager.gpu_mat_buf[mat_type],
    		offset = 0,
    		size = cast(u32)required_gpu_buf_size,
    	}

    	return upload_info;
	}

	if len(manager.gpu_index_update_queue[mat_type]) == 0 {
		return;
	}

	// We find the buffer range that we need to reupload.
	min_index : int = gpu_array_len; // this doesnt make sence -> ? len(manager.gpu_index_update_queue[mat_type]);
	max_index : int = -1;

	for gpu_index in manager.gpu_index_update_queue[mat_type] {

		if gpu_index < 0 || gpu_index >= gpu_array_len {
			// @Note.
			// Mat probably got removed probably. 
			// When we remove a material we swap last element to removed index
			// and then have to update that swap in material. but if we remove many
			// it can happen that we also remove that one an so the update queue is not correct anymore.
			// happen for example when switching scenes.
			continue; 
		}

		min_index = min(min_index, gpu_index);
		max_index = max(max_index, gpu_index);	
	}
	
	clear(&manager.gpu_index_update_queue[mat_type]);

	if max_index <= 0 || min_index >= gpu_array_len {
		return; 
	}

	engine_assert(gpu_array_len > 0);

	starting_byte: int = min_index * gpu_element_byte_size;
	byte_region:   int = (max_index + 1 - min_index) * gpu_element_byte_size; 

	transfer_buf_rawptr: rawptr = sdl.MapGPUTransferBuffer(gpu_device, manager.gpu_mat_transfer_buf[mat_type], false);
	transfer_buf_byte_ptr : [^]byte = cast([^]byte)transfer_buf_rawptr;

	gpu_mat_byte_ptr : [^]byte = material_manager_cast_gpu_array_to_byte_multiptr(manager, mat_type);

	mem.copy_non_overlapping(&transfer_buf_byte_ptr[starting_byte], &gpu_mat_byte_ptr[starting_byte], byte_region);

	sdl.UnmapGPUTransferBuffer(gpu_device, manager.gpu_mat_transfer_buf[mat_type]);

	upload_info.requires_upload = true;
	upload_info.transfer_buf_location = {
		transfer_buffer = manager.gpu_mat_transfer_buf[mat_type],
		offset = cast(u32)starting_byte,
	}

	upload_info.transfer_buf_region = {
		buffer = manager.gpu_mat_buf[mat_type],
		offset = cast(u32)starting_byte,
		size   = cast(u32)byte_region,
	}

	return upload_info;
}

// returns 0 on failure, which is the default fallback materal.
@(private="package")
material_manager_add_material :: proc(manager : ^MaterialManager, material : ^Material) -> MaterialID {

	if material.variant == nil {
		log.errorf("Failed to register material, variant is nil");
		return 0;
	}

	render_technique_hash := render_technique_calc_hash(material.render_technique);

	mat_arr_index : int = len(manager.materials); 
	append_nothing(&manager.materials);
	mem.copy(&manager.materials[mat_arr_index], material, size_of(Material));

	if len(material.name) > 0 {
		manager.materials[mat_arr_index].name = strings.clone(material.name, context.allocator);
	} else {
		manager.materials[mat_arr_index].name = "";
	}

	append(&manager.material_render_technique_hashes, render_technique_hash);


	gpu_array_index : int = -1;
	mat_enum_type : MaterialShaderType = .None;
	
	switch &mat_variant in material.variant{
		case PbrMaterialVariant:{

			mat_enum_type = .Pbr;	
			gpu_mat := PbrMaterialVariant_to_PbrMaterialDataGPU(&mat_variant, material.render_technique.alpha_mode);
			gpu_array_index = len(manager.pbr_materials_gpu);
			append(&manager.pbr_materials_gpu, gpu_mat);
		}
		case UnlitMaterialVariant: {

			mat_enum_type = .Unlit;	
			gpu_mat := UnlitMaterialVariant_to_UnlitMaterialDataGPU(&mat_variant, material.render_technique.alpha_mode);
			gpu_array_index = len(manager.unlit_materials_gpu);
			append(&manager.unlit_materials_gpu, gpu_mat);
		}
		case CustomMaterialVariant: {
			mat_enum_type = .Custom;
			gpu_array_index = -1;
		}
	}


	free_spot_index : int = -1;

	for i in 0..<len(manager.material_indexes) {
		
		if manager.material_indexes[i] == -1 {
			free_spot_index = i;
			break;
		}
	}
		
	if mat_enum_type != .Custom && mat_enum_type != .None {
		engine_assert(gpu_array_index != -1);
	}
	

	mat_id : MaterialID = 0;

	if free_spot_index == -1 {
		// no free spot.

		mat_id = cast(MaterialID)len(&manager.material_indexes);
		append(&manager.material_indexes, mat_arr_index);
		append(&manager.material_gpu_indexes, gpu_array_index);
		append(&manager.material_enum_type, mat_enum_type);
	} else {

		mat_id = cast(MaterialID)free_spot_index;
		manager.material_indexes[mat_id] 		= mat_arr_index;
		manager.material_gpu_indexes[mat_id] 	= gpu_array_index;
		manager.material_enum_type[mat_id] 		= mat_enum_type;
	}
	
	return mat_id;
}

// TODO: for custom materials we probably want to unload any buffers it has set up here?
@(private="package")
material_manager_remove_material :: proc(manager : ^MaterialManager, mat_id : ^MaterialID) {

	_mat_id: MaterialID = mat_id^;
	defer {
		mat_id^ = 0; // invalidate.
	}

	if !material_manager_is_valid_id(manager, _mat_id) {
		return;
	}

	mat_arr_index: int = manager.material_indexes[_mat_id];
	mat_gpu_index: int = manager.material_gpu_indexes[_mat_id];
	mat_enum_type: MaterialShaderType = manager.material_enum_type[_mat_id];

	engine_assert(mat_arr_index < len(manager.materials));
	engine_assert(mat_enum_type != .None);

	// @Note:
	// We first delete the GPU material data entry in its respective array based on the material type.
	// We will do an unordered_remove(), meaning the last element will be copied to the remove location and then the last element can be poped of.
	// The entry we want to remove is at the array location of 'mat_gpu_index' -> unordered_remove(&gpu_array, mat_gpu_index).
	// Because the last element will be swaped to this location, we first have to find the MaterialID that currently points to 
	// the last element of the gpu_array, so that we can update its 'material_gpu_index' to point to the new location.
	// If the entry we want to remove is already the last one in the list we can of course skip that.


	// First we remove the gpu material that corresponds to this materialID.

	last_gpu_array_index: int = cast(int)material_manager_get_gpu_array_len_for_type(manager, mat_enum_type) -1;

	// @Note: for .Custom we dont have a gpu array so we skip this step.
	if mat_gpu_index != last_gpu_array_index && mat_enum_type != .Custom {

		// The GpuMaterial we want to remove is NOT already the last one in the gpu array,
		// so we have to search it and update it first.


		found : bool = false;
		material_id_pointing_to_last_gpu_array_index: int = -1;
		
		// @Note: we go backwards because we assume that it will be further back in the array.
		for i : int = len(manager.material_indexes) -1; i >= 0; i-=1 {

			// we must check the type because 'material_gpu_indexes' is type respective
			// it gives the index into the array of the type so there can be dublicate values.
	 		if manager.material_enum_type[i] != mat_enum_type {
	 			continue;
	 		}

	 		gpu_index : int = manager.material_gpu_indexes[i];

	 		if gpu_index == last_gpu_array_index {
	 			found = true;
	 			material_id_pointing_to_last_gpu_array_index = i;
	 			break;
	 		}
	 	}

	 	// It must exist otherwise something is broken
	 	engine_assert(found);

		manager.material_gpu_indexes[material_id_pointing_to_last_gpu_array_index] = mat_gpu_index;
	}

	// Now we can perform the unordered_remove()
 	switch mat_enum_type {
		case .None:		panic("Invalid Codepath")
		case .Pbr:		unordered_remove(&manager.pbr_materials_gpu  , mat_gpu_index);
		case .Unlit:	unordered_remove(&manager.unlit_materials_gpu, mat_gpu_index);
		case .Custom:   // we dont have a gpu array for custom mats. no work to do here.
	}

	// We must update it also in the gpu buffer.
	append(&manager.gpu_index_update_queue[mat_enum_type], mat_gpu_index);

	// Now we also want to remove the material in the 'materials' list.
	// We will do the same approach as with the gpu entries and first update the index pointing to the last element
	// before performing an unordered_remove().

	last_mat_array_index: int = len(manager.materials) -1;

	// Again we first check that we are not already the last element in witch case we would not have to update anything.
	if mat_arr_index != last_mat_array_index {

		found : bool = false;
		material_id_pointing_to_last_mat_array_index: int = -1;

		// @Note: We walk backwards with the assumption that the MaterialID pointing to the last element will also be quite far back in indexes list.
		// This is only true if useres dont remove and add many materials at runtime. 
		for i := len(manager.material_indexes) -1; i >= 0; i-=1 {

			if manager.material_indexes[i] == last_mat_array_index {
				found = true;
				material_id_pointing_to_last_mat_array_index = i;
				break;
			}
		}

		// It must exist otherwise something is broken.
		engine_assert(found); 

		manager.material_indexes[material_id_pointing_to_last_mat_array_index] = mat_arr_index;
	}

	// TODO: Unload custom material buffers

	iricom.material_free_contents(&manager.materials[mat_arr_index]);
	// unordered_remove now copies last element to the one we want to remove and then deletes the last
	unordered_remove(&manager.materials, mat_arr_index);
	unordered_remove(&manager.material_render_technique_hashes, mat_arr_index);

	// invalidate MaterialID by reseting these mark as free spot.
	manager.material_indexes[_mat_id]     = -1;
	manager.material_gpu_indexes[_mat_id] = -1;
	manager.material_enum_type[_mat_id]   = .None;

	engine_assert(len(manager.material_indexes) == len(manager.material_gpu_indexes));
	engine_assert(len(manager.material_indexes) == len(manager.material_enum_type));
	engine_assert(len(manager.materials)        == len(manager.material_render_technique_hashes));
}


@(private="package")
material_manager_push_material_changes :: proc(manager : ^MaterialManager, mat_id: MaterialID){
	
	if !material_manager_is_valid_id(manager,mat_id){
		return;
	}

	mat_type := manager.material_enum_type[mat_id];

	if mat_type == .None || mat_type == .Custom {
		return;
	}

	mat_arr_index := manager.material_indexes[mat_id];
	gpu_arr_index := manager.material_gpu_indexes[mat_id];

	engine_assert(mat_arr_index >= 0);
	engine_assert(gpu_arr_index >= 0);

	// copy new changes into the respective array element
	mat := &manager.materials[mat_arr_index];

	switch &mat_variant in mat.variant {
		case PbrMaterialVariant:
			gpu_mat := PbrMaterialVariant_to_PbrMaterialDataGPU(&mat_variant, mat.render_technique.alpha_mode);
			manager.pbr_materials_gpu[gpu_arr_index] = gpu_mat;
			append(&manager.gpu_index_update_queue[.Pbr], gpu_arr_index);
		case UnlitMaterialVariant:
			gpu_mat := UnlitMaterialVariant_to_UnlitMaterialDataGPU(&mat_variant, mat.render_technique.alpha_mode);
			manager.unlit_materials_gpu[gpu_arr_index] = gpu_mat;
			append(&manager.gpu_index_update_queue[.Unlit], gpu_arr_index);
		case CustomMaterialVariant: {
			panic("Invalid Codepath")
		}
	}
}

// @Note: This is a potentially very slow operation and can trigger rebuilding of pipeline objects and shaders
@(private="package")
material_manager_push_material_technique_changes :: proc(manager : ^MaterialManager, mat_id: MaterialID, pipe_manager : ^PipelineManager, gpu_device : ^sdl.GPUDevice) {
	
	if !material_manager_is_valid_id(manager, mat_id){
		return;
	}

	material_manager_push_material_changes(manager, mat_id);

	// @Note: Since we dont know at this stage wich vertex layouts are combined with this material, we will build pipelines for all of them.
	pipe_manager_update_material_pipeline_cache_with_material_and_vertex_layouts(pipe_manager, gpu_device, manager, mat_id, VERTEX_LAYOUTS_ALL);
	pipe_manager_update_depthonly_pipeline_cache_with_material(pipe_manager, gpu_device, manager, mat_id);
}

@(private="package")
material_manager_is_valid_id :: proc(manager : ^MaterialManager, mat_id: MaterialID) -> bool {

	if mat_id >= cast(u32)len(manager.material_indexes) {
		return false;
	}

	if manager.material_indexes[mat_id] < 0 || manager.material_indexes[mat_id] >= len(manager.materials) {
		return false;
	}

	return true;
}


@(private="package")
material_manager_get_material_shader_type_unsafe :: proc "contextless" (manager : ^MaterialManager, mat_id: MaterialID) -> MaterialShaderType  {
	return manager.material_enum_type[mat_id];
}

// Returns a pointer to previously registered material. 
// The pointer is only valid for as long as no other materials are added or removed
@(private="package")
material_manager_get_material_unsafe :: proc "contextless" (manager : ^MaterialManager, mat_id : MaterialID) -> ^Material  {
	return &manager.materials[manager.material_indexes[mat_id]];
}

@(private="package")
material_manager_get_render_technique_hash_unsafe :: proc "contextless" (manager : ^MaterialManager, mat_id : MaterialID) -> RenderTechniqueHash   {
	return manager.material_render_technique_hashes[manager.material_indexes[mat_id]];
}