package iri

import "core:mem"
import "core:log"
import sdl "vendor:sdl3"

// TODO: 
// Push material should update the gpu data arrays already with new data


MaterialID :: distinct i32;

MaterialRegister :: struct {

	// Note: A 'MaterialID' is used to lookup the actual material array index inside the 'material_indexes' list.
	// OR to get the array index of its corresponding GPU representation using the 'material_gpu_indexes' list.
	// e.g: mat = materials[material_indexes[MaterialID]] -> in reality one must check if material_indexes[MaterialID] equals -1 and would therfore not point to a material

	material_indexes: 		[dynamic]i32, 	// indexes into materials array
	material_gpu_indexes: 	[dynamic]i32, // indexes into type respective gpu material arrays
	material_enum_type:		[dynamic]MaterialShaderType, // the type in enum form for a given MaterialID
	
	materials: [dynamic]Material,		// sparse/compact material array
	material_render_technique_hashes: [dynamic]RenderTechniqueHash, // same order as materials array, so use same index as for material to get the technique hash

	material_update_queue: [dynamic]i32,

	unlit_materials_gpu: [dynamic]UnlitMaterialDataGPU,
	pbr_materials_gpu:   [dynamic]PbrMaterialDataGPU,

	gpu_mat_array_len_last: [MaterialShaderType]u32, // stores for each material type the GPU array lenght of last frame.
	gpu_mat_data_buf: 		[MaterialShaderType]^sdl.GPUBuffer, // a seperate GPU buffer fo each material type.
	gpu_mat_transfer_buf: 	[MaterialShaderType]^sdl.GPUTransferBuffer, // a seperate Transfer buffer for each material type.
}

@(private="file")
register : ^MaterialRegister;

// Note: Must be updated when adding new material type
@(private="file")
material_register_get_gpu_array_len_for_type :: proc(type: MaterialShaderType) -> u32 {
	switch type {
		case .NONE: 	return 0;
		case .PBR:		return cast(u32)len(register.pbr_materials_gpu);
		case .UNLIT:	return cast(u32)len(register.unlit_materials_gpu);
		case .CUSTOM:	return 0;
	}

	return 0;
}

// Note: Must be updated when adding new material type
@(private="file")
material_register_get_gpu_element_byte_size_for_type :: proc(type: MaterialShaderType) -> u32 {
	switch type {
		case .NONE: 	return 0;
		case .PBR:		return cast(u32)size_of(PbrMaterialDataGPU);
		case .UNLIT:	return cast(u32)size_of(UnlitMaterialDataGPU);
		case .CUSTOM:	return 0;
	}

	return 0;
}

// Note: Must be updated when adding new material type
// CAREFULL NO BOUND CHECKING.
@(private="file")
material_register_get_gpu_array_rawptr_at_index_for_type :: proc(type: MaterialShaderType, index : u32) -> rawptr {
	switch type {
		case .NONE: 	return nil;
		case .PBR:		return cast(rawptr)&register.pbr_materials_gpu[index];
		case .UNLIT:	return cast(rawptr)&register.unlit_materials_gpu[index];
		case .CUSTOM:	return nil;
	}

	return nil;
}

// Note: Must be updated when adding new material type
// CAREFULL NO BOUND CHECKING.
// Because odin doesn't allow pointer arithmatic with rawptr we have to first convert it to a multi pointer
// do an index offset and then convert back to rawptr in order to interface with sdl transfer buffers;
@(private="file")
material_register_get_offset_transfer_buf_rawptr_to_array_index_for_type :: proc(data_ptr : rawptr, array_index : u32, type: MaterialShaderType) -> rawptr {
	
	switch type {
		case .NONE: 	return nil;
		case .PBR:		return cast(rawptr)&(cast([^]PbrMaterialDataGPU)data_ptr)[array_index];
		case .UNLIT:	return cast(rawptr)&(cast([^]UnlitMaterialDataGPU)data_ptr)[array_index];
		case .CUSTOM:	return nil;
	}

	return nil;
}




@(private="package")
material_register_init :: proc(){

	engine_assert(register == nil);

	register = new(MaterialRegister);
}

@(private="package")
material_register_shutdown :: proc(gpu_device: ^sdl.GPUDevice){
	delete(register.material_indexes);
	delete(register.material_gpu_indexes);
	delete(register.material_enum_type);
	delete(register.materials);

	delete(register.pbr_materials_gpu);
	delete(register.unlit_materials_gpu);

	delete(register.material_update_queue);

	for mat_type in MaterialShaderType{
		if register.gpu_mat_data_buf[mat_type] != nil {
			sdl.ReleaseGPUBuffer(gpu_device, register.gpu_mat_data_buf[mat_type]);
		}

		if register.gpu_mat_transfer_buf[mat_type] != nil {
			sdl.ReleaseGPUTransferBuffer(gpu_device, register.gpu_mat_transfer_buf[mat_type]);
		}
	}

	delete(register.material_render_technique_hashes);

	free(register);
}

@(private="package")
material_register_query_material_upload_for_type :: proc(gpu_device: ^sdl.GPUDevice, mat_type: MaterialShaderType) -> (require_update: bool, transfer_buf_location: sdl.GPUTransferBufferLocation, transfer_buf_region: sdl.GPUBufferRegion){

	engine_assert(mat_type != .NONE);

	if mat_type == .CUSTOM {
		return false, transfer_buf_location, transfer_buf_region;
	}

	//gpu_array_len: u32 = cast(u32)len(register.pbr_materials_gpu);
	gpu_array_len: u32 = material_register_get_gpu_array_len_for_type(mat_type);
	gpu_element_byte_size: u32 = material_register_get_gpu_element_byte_size_for_type(mat_type);

	//defer register.pbr_materials_gpu_array_len_last = gpu_array_len;
	// Update array len last for this type at the End
	defer register.gpu_mat_array_len_last[mat_type] = gpu_array_len;


	buffer_byte_size: u32 = gpu_array_len * gpu_element_byte_size;
	
	// If array growed we have to make a new gpu buffer and a new transfer buffer
	// If it shrinks we don't care for now and will keep the allocated memory.
	// Future implementation may offer a way to compact memory on demand with a call like 'pack_memory_buffers'
	size_got_bigger: bool = false;
	if(gpu_array_len > register.gpu_mat_array_len_last[mat_type]) {
		size_got_bigger = true;

		// Create a new gpu buffer with bigger size.
		if(register.gpu_mat_data_buf[mat_type] != nil){
			sdl.ReleaseGPUBuffer(gpu_device, register.gpu_mat_data_buf[mat_type]);
		}


		gpu_buf_ci : sdl.GPUBufferCreateInfo = {
    		usage = {sdl.GPUBufferUsageFlag.GRAPHICS_STORAGE_READ},
    		size  =  buffer_byte_size,
		};

		register.gpu_mat_data_buf[mat_type] = sdl.CreateGPUBuffer(gpu_device, gpu_buf_ci);

		// Create a new transfer buffer with bigger size.
		if(register.gpu_mat_transfer_buf[mat_type] != nil){
			sdl.ReleaseGPUTransferBuffer(gpu_device, register.gpu_mat_transfer_buf[mat_type]);
		}

		transfer_buf_ci : sdl.GPUTransferBufferCreateInfo = {
	        usage = sdl.GPUTransferBufferUsage.UPLOAD,
	        size  = buffer_byte_size,
	    }

	    register.gpu_mat_transfer_buf[mat_type] = sdl.CreateGPUTransferBuffer(gpu_device, transfer_buf_ci);
	}

	// in this case we have to copy and reupload the entire array
	if(size_got_bigger) {

		// Remove any material that is of the same material type from the update queue as we are about to upload everything anew.
		for i: i32 = i32(len(register.material_update_queue) -1); i >= 0; i -= 1 {

			mat_id: i32 = register.material_update_queue[i];
			if(register.material_enum_type[mat_id] == mat_type) {
				unordered_remove(&register.material_update_queue, i);
			}
		}

		transfer_buf_data_ptr : rawptr = sdl.MapGPUTransferBuffer(gpu_device, register.gpu_mat_transfer_buf[mat_type], false);
    	
    	gpu_mat_array_rawptr : rawptr = material_register_get_gpu_array_rawptr_at_index_for_type(mat_type, 0);
    	mem.copy_non_overlapping(transfer_buf_data_ptr, gpu_mat_array_rawptr, cast(int)buffer_byte_size);

    	sdl.UnmapGPUTransferBuffer(gpu_device, register.gpu_mat_transfer_buf[mat_type]);

    	transfer_buf_location = {
    		transfer_buffer = register.gpu_mat_transfer_buf[mat_type],
    		offset = 0,
    	}

    	transfer_buf_region = {
    		buffer = register.gpu_mat_data_buf[mat_type],
    		offset = 0,
    		size = buffer_byte_size,
    	}

    	return true, transfer_buf_location, transfer_buf_region;
	}


	if(len(register.material_update_queue) == 0){
		return false, transfer_buf_location, transfer_buf_region;
	}


	// Now we still have to check if there are any pbr materials in the update queue
	// what we will do is loop through and find the lowest and highest array index and just reupload that region.
	// Chances are that we only need to update a single material so it would be wastefull 
	// to reupload the entire buffer every time a single material changes.
	lowest_gpu_index: i32 = -1;
	highest_gpu_index: i32 = -1;
	for i: i32 = i32(len(register.material_update_queue) -1); i >= 0; i -= 1 {

		mat_id: i32 = register.material_update_queue[i];
		if(register.material_enum_type[mat_id] == mat_type) {
			
			gpu_index: i32 = register.material_gpu_indexes[mat_id];

			if(gpu_index > highest_gpu_index){
				highest_gpu_index = gpu_index;
			}

			if(lowest_gpu_index == -1 || gpu_index < lowest_gpu_index){
				lowest_gpu_index = gpu_index;
			}

			unordered_remove(&register.material_update_queue, i);
		}
	}

	if lowest_gpu_index ==  -1 || highest_gpu_index == -1 {
		return false, transfer_buf_location, transfer_buf_region;
	}

	// TODO: we have to copy the data now also into the transfer buffer!

	starting_byte: u32 = cast(u32)lowest_gpu_index * gpu_element_byte_size;
	byte_region: u32 = (cast(u32)highest_gpu_index + 1 - cast(u32)lowest_gpu_index) * gpu_element_byte_size; 
	
	//	[0][1][2][3][4][5][6] -> len 7		
	//	lowest = 2;
	//	highest = 4;
	//  starting_byte: 2 * sizeof()
	//	byte_region: (4+1-2) * sizeof() = 3 * sizeof()



	transfer_buf_data_ptr: rawptr = sdl.MapGPUTransferBuffer(gpu_device, register.gpu_mat_transfer_buf[mat_type], false);
    	
	// TODO: generalize!
	gpu_mat_array_rawptr : rawptr = material_register_get_gpu_array_rawptr_at_index_for_type(mat_type, cast(u32)lowest_gpu_index);

	// some skety rawptr offsetting because odin doesn't allow to offset rawptrs directly.
	transfer_buf_offset: rawptr = material_register_get_offset_transfer_buf_rawptr_to_array_index_for_type(transfer_buf_data_ptr, cast(u32)lowest_gpu_index, mat_type);

	mem.copy_non_overlapping(transfer_buf_offset, gpu_mat_array_rawptr, cast(int)byte_region);

	sdl.UnmapGPUTransferBuffer(gpu_device, register.gpu_mat_transfer_buf[mat_type]);


	// now we have a index range of lowest_gpu_index .. highest_gpu_index that should be reuploaded to gpu.
	transfer_buf_location = {
		transfer_buffer = register.gpu_mat_transfer_buf[mat_type],
		offset = starting_byte,
	}

	transfer_buf_region = {
		buffer = register.gpu_mat_data_buf[mat_type],
		offset = starting_byte,
		size = byte_region,
	}

	return true, transfer_buf_location, transfer_buf_region;
}

@(private="package")
material_register_get_gpu_buffer_for_type :: proc(mat_type: MaterialShaderType) -> ^sdl.GPUBuffer{
	return register.gpu_mat_data_buf[mat_type];
}

@(private="package")
material_register_get_gpu_array_index_for_type :: proc(mat_type: MaterialShaderType, mat_id : MaterialID) -> i32 {
	return register.material_gpu_indexes[i32(mat_id)];
}


material_register_get_num_loaded_material :: proc() -> u32 {
	return cast(u32)len(register.materials);
}

// User procedures

register_add_material :: proc(material : Material) -> MaterialID {

	if material.variant == nil {
		log.errorf("Failed to register material, variant is nil");
		return -1;
	}

	render_technique_hash := hash_render_technique(material.render_technique);

	append(&register.materials, material);
	append(&register.material_render_technique_hashes, render_technique_hash);

	gpu_array_index : i32 = -1;
	
	mat_enum_type : MaterialShaderType = .NONE;
	
	switch &mat_variant in material.variant{
		case PbrMaterialData:
			mat_enum_type = .PBR;	
			gpu_mat := material_convert_PbrMaterialData_to_PbrMaterialDataGPU(&mat_variant, material.render_technique.alpha_mode);
			gpu_array_index = cast(i32)len(register.pbr_materials_gpu);
			append(&register.pbr_materials_gpu, gpu_mat);
		case UnlitMaterialData:
			mat_enum_type = .UNLIT;	
			gpu_mat := material_convert_UnlitMaterialData_to_UnlitMaterialDataGPU(&mat_variant, material.render_technique.alpha_mode);
			gpu_array_index = cast(i32)len(register.unlit_materials_gpu);
			append(&register.unlit_materials_gpu, gpu_mat);
		case CustomMaterialVariant: 
			mat_enum_type = .CUSTOM;
			gpu_array_index = -1;
	}


	arr_index : i32 = cast(i32)len(register.materials) -1; // last element;

	reg_id : MaterialID = -1;

	// See if there is a free spot in the indexes list.
	for i in 0..<len(register.material_indexes) {
		if register.material_indexes[i] == -1 {

			reg_id = cast(MaterialID)i;
			break;
		}
	}

	if reg_id == -1 {
		reg_id = cast(MaterialID)len(&register.material_indexes);
		append(&register.material_indexes, arr_index);
		append(&register.material_gpu_indexes, gpu_array_index);
		append(&register.material_enum_type, mat_enum_type);
	} else {
		register.material_indexes[i32(reg_id)] 		= arr_index;
		register.material_gpu_indexes[i32(reg_id)] 	= gpu_array_index;
		register.material_enum_type[i32(reg_id)] 	= mat_enum_type;
	}
	
	return reg_id;
}


// TODO: for custom materials we probably want to unload any buffers it has set up here?

register_remove_material :: proc(mat_id : ^MaterialID) {

	id: MaterialID = mat_id^;

	if !register_contains_material_id(id) {
		return;
	}

	mat_arr_index: i32 = register.material_indexes[id];
	mat_gpu_index: i32 = register.material_gpu_indexes[id];
	mat_enum_type: MaterialShaderType = register.material_enum_type[id];

	engine_assert(mat_arr_index < cast(i32)len(register.materials));

	// We first delete the GPU material data entry in its respective array based on the material type.
	// We will do an unordered_remove(), meaning the last element will be copied to the remove location and then the last element can be poped of.
	// The entry we want to remove is at the array location of 'mat_gpu_index' -> unordered_remove(&gpu_array, mat_gpu_index).
	// Because the last element will be swaped to this location, we first have to find the MaterialID that currently points to 
	// the last element of the gpu_array, so that we can update its 'material_gpu_index' to point to the new location.
	// If the entry we want to remove is already the last one in the list we can of course skip that.

	last_gpu_array_index: i32 = -1;

	switch mat_enum_type {
		case .NONE:		engine_assert(false);
		case .PBR:		last_gpu_array_index = cast(i32)len(register.pbr_materials_gpu) -1;
		case .UNLIT:	last_gpu_array_index = cast(i32)len(register.unlit_materials_gpu) -1;
		case .CUSTOM:
	}

	if mat_enum_type != .CUSTOM {
		engine_assert(last_gpu_array_index >= 0);
	}

	if mat_gpu_index != last_gpu_array_index && mat_enum_type != .CUSTOM {

		// The entry we want to remove is NOT already the last one in the gpu array, so we have to search and update it first.

		material_id_pointing_to_last_gpu_array_index: i32 = -1;
		for i := i32(len(register.material_indexes) -1); i >= 0; i-=1 {

	 		if(register.material_enum_type[i] != mat_enum_type){
	 			continue;
	 		}

	 		gpu_index := register.material_gpu_indexes[i];

	 		if(gpu_index == last_gpu_array_index) {
	 			// Found it!
	 			material_id_pointing_to_last_gpu_array_index = i32(i);
	 			break;
	 		}
	 	}

	 	// It must exist otherwise something is broken
	 	engine_assert(material_id_pointing_to_last_gpu_array_index != -1);

		register.material_gpu_indexes[material_id_pointing_to_last_gpu_array_index] = mat_gpu_index;
	}

	// Now we can perform the unordered_remove()
 	switch mat_enum_type {
		case .NONE:		engine_assert(false);
		case .PBR:		unordered_remove(&register.pbr_materials_gpu, mat_gpu_index);
		case .UNLIT:	unordered_remove(&register.unlit_materials_gpu, mat_gpu_index);
		case .CUSTOM:
	}


	// Now we also want to remove the material in the 'materials' list.
	// We will do the same approach as with the gpu entries and first update the index pointing to the last element
	// before performing an unordered_remove().


	last_mat_array_index: i32 = cast(i32)len(register.materials) -1;

	// Again we first check that we are not already the last element in witch case we would not have to update anything.
	if mat_arr_index != last_mat_array_index {

		material_id_pointing_to_last_mat_array_index: i32 = -1;

		// @Note: We walk backwards with the assumption that the MaterialID pointing to the last element will also be quite far back in indexes list.
		// This is only true if useres dont remove and add many materials at runtime. 
		for i := i32(len(register.material_indexes) -1); i >= 0; i-=1 {

			if(register.material_indexes[i] == last_mat_array_index){
				material_id_pointing_to_last_mat_array_index = i;
				break;
			}
		}

		// It must exist otherwise something is broken.
		engine_assert(material_id_pointing_to_last_mat_array_index != -1); 

		register.material_indexes[material_id_pointing_to_last_mat_array_index] = mat_arr_index;
	}

	// TODO: Unload custom material buffers

	// unordered_remove now copies last element to the one we want to remove and then deletes the last
	unordered_remove(&register.materials, mat_arr_index);
	unordered_remove(&register.material_render_technique_hashes, mat_arr_index);

	// invalidate id
	register.material_indexes[id] = -1;
	register.material_gpu_indexes[id] = -1;
	register.material_enum_type[id] = .NONE;

	mat_id^ = -1;

	engine_assert(len(register.material_indexes) == len(register.material_gpu_indexes));
	engine_assert(len(register.material_indexes) == len(register.material_enum_type));
	engine_assert(len(register.materials) == len(register.material_render_technique_hashes));
}


// @This is a potentially very slow operation and can trigger rebuilding of pipeline objects and shaders compilations
register_push_material_technique_changes :: proc(mat_id: MaterialID){
	
	if !register_contains_material_id(mat_id) {
		return;
	}

	register_push_material_changes(mat_id);

	universe := engine.universe;

	if universe == nil {
		return;
	}

	pipe_manager := engine.pipeline_manager;
	gpu_device := get_gpu_device();

	pipe_manager_update_material_pipeline_cache_for_universe(pipe_manager, gpu_device, universe);
	pipe_manager_update_depthonly_pipeline_cache_for_universe(pipe_manager, gpu_device, universe);
}

// @Note: push changes of material variants so they get uploaded to the gpu next frame.
// for material technique changes like changine blend modes use 'push_material_technique_changes()' instead.
register_push_material_changes :: proc(mat_id: MaterialID){
	
	if !register_contains_material_id(mat_id) {
		return;
	}

	shader_type := register_get_material_shader_type(mat_id);
	if shader_type == .CUSTOM {
		return; // not supported right now but we probably want something like this but we should redesign this api..
	}


	id : i32 = cast(i32)mat_id;

	mat_arr_index := register.material_indexes[id];
	gpu_arr_index := register.material_gpu_indexes[id];

	engine_assert(mat_arr_index >= 0);
	engine_assert(gpu_arr_index >= 0);

	// copy new changes into the respective array element
	mat := &register.materials[mat_arr_index];

	switch &mat_variant in mat.variant {
		case PbrMaterialData:
			gpu_mat := material_convert_PbrMaterialData_to_PbrMaterialDataGPU(&mat_variant, mat.render_technique.alpha_mode);
			register.pbr_materials_gpu[gpu_arr_index] = gpu_mat;
		case UnlitMaterialData:
			gpu_mat := material_convert_UnlitMaterialData_to_UnlitMaterialDataGPU(&mat_variant, mat.render_technique.alpha_mode);
			register.unlit_materials_gpu[gpu_arr_index] = gpu_mat;
		case CustomMaterialVariant:
	}


	append(&register.material_update_queue, cast(i32)mat_id);
}

register_contains_material_id :: proc(mat_id: MaterialID) -> bool {

	id: i32 = cast(i32)mat_id;

	if(id < 0 || id >= cast(i32)len(register.material_indexes)){
		return false;
	}

	if(register.material_indexes[id] <= -1){
		return false;
	}

	return true;
}

register_get_material_shader_type :: proc(mat_id: MaterialID) -> MaterialShaderType{

	id: i32 = cast(i32)mat_id;

	if(id < 0 || id >= cast(i32)len(register.material_indexes)){
		return MaterialShaderType.NONE;
	}

	return register.material_enum_type[id];
}

// Returns a pointer to previously registered material. 
// The pointer is only valid for as long as no other materials are registered or unregistered
register_get_material :: proc(mat_id : MaterialID) -> ^Material {

	engine_assert(register_contains_material_id(mat_id));

	mat_arr_index := register.material_indexes[i32(mat_id)];

	return &register.materials[mat_arr_index];
}

material_register_get_render_technique_hash :: proc(mat_id : MaterialID) -> RenderTechniqueHash {
	
	engine_assert(register_contains_material_id(mat_id));

	mat_arr_index := register.material_indexes[i32(mat_id)];

	return register.material_render_technique_hashes[mat_arr_index];

}

// NOTE: Careful! Use this only if you definitly know the type of the material. 
// If the passed typeid doesn't match the materials type 'nil' is returned.
// Otherwise same as 'register_get_material()'
register_get_material_as_variant :: proc(id : MaterialID, $T : typeid) -> ^T {

	if(i32(id) < 0 || i32(id) >= cast(i32)len(register.material_indexes)){
		return nil;
	}

	mat_arr_index := register.material_indexes[i32(id)];

	mat : ^Material = &register.materials[mat_arr_index];

	mat_type , ok := &mat.variant.(T);

	if(!ok){
		return nil;
	}

	return mat_type;
}