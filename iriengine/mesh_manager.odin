package iri

import "core:log"
import "core:strings"
import "core:mem"
import "core:c"
import "core:math"
import "core:math/linalg"

import iricom "iricommon"
import sdl "vendor:sdl3"

import "odinary:mathy"
import geo "odinary:geometry"
import "odinary:geometry/meshopt"


// @Note: MeshID's are runtime stable IDs, not between executable sessions.
// They are also stable between loaded universes. 
// So two loaded universes can refer to the same MeshID.
MeshID :: iricom.MeshID   // == i32

DRAW_INSTANCE_FLAGS_DEFAULT :: iricom.DRAW_INSTANCE_FLAGS_DEFAULT
DrawInstanceFlags 	:: iricom.DrawInstanceFlags
DrawInstanceFlag 	:: iricom.DrawInstanceFlag
DrawInstance 		:: iricom.DrawInstance

MeshGPUData :: struct{
	num_indecies  	: u32,
	num_vertecies 	: u32,
	index_buf  		: ^sdl.GPUBuffer,
	vertex_buf 		: ^sdl.GPUBuffer,
	vertex_pos_buf 	: ^sdl.GPUBuffer,
	vertex_layout   : VertexDataLayout,
}

MeshGlobalBufferInfo :: struct {
	bvh_nodes_offset     : u32,
	num_bvh_nodes        : u32,

	// @Note: the indecies are reordered for pupose of bvh traversal and not optimally chache friend as what meshoptimizer would give us.
	indecies_offset  : u32,
	num_indecies     : u32,

	vertecies_offset : u32,
	num_vertecies    : u32,
}

Mesh :: struct {
	used : bool,
	name : string,
	gpu_data : MeshGPUData,
	aabb : geo.AABB, // @Note: technically bvh_data root node will store the same aabb.
	
	global_buf_info : MeshGlobalBufferInfo, 

	//@Note Transform of the loaded mesh file which we keep stored but its not used for rendering directly but will be copied to a drawables
	transform : Transform, 
}

// @Note: Struct replicated on GPU
// Similar to MeshGlobalBufferInfo but less info and we use this one to upload to gpu.
DrawableGlobalBufferInfo :: struct #align(16) {
	bl_bvh_root_offset      : u32, // offset into global bl bvh buffer
	global_indecies_offset  : u32, // offset into global index buffer
	global_vertecies_offset : u32, // offset into global vertex buffer
	_ : u32, // Padding. Maybe material ID ? but then we need material type too. or we say only pbr materials are supported for gpu raytracing.
}

Drawable :: struct {
	entity : Entity,
	draw_instance  : DrawInstance,
	world_aabb : geo.AABB, // world space aabb
	world_oobb : geo.OBB,  // world space obb
	world_mat  : matrix[4,4]f32, // Local to World
	inv_world_mat  : matrix[4,4]f32, // World to Local
	global_buf_info : DrawableGlobalBufferInfo,
	prev_physics_world_transform : Transform, // World Transform of the previous physics state!
}

MeshManager :: struct {
	num_loaded_meshes : u32,
	meshes : #soa[dynamic]Mesh,
	id_map : map[AssetUUID]MeshID,

	global_vertecies 	: [dynamic][4]f32,
	// @Note: the indecies are reorderd for pupose of bvh traversal and not optimally chache friendly as what meshoptimizer would give us.
	global_indecies  	: [dynamic]u32,
	global_bl_bvh_nodes : [dynamic]geo.BvhNode, // 'bottom level acceleration structure'

	global_vertecies_freelist 		: [dynamic]MultiFreelistEntry,
	global_indecies_freelist  	 	: [dynamic]MultiFreelistEntry,
	global_bl_bvh_nodes_freelist 	: [dynamic]MultiFreelistEntry,

	global_bl_bvh_nodes_buf 		: BasicGPUBuffer,
	global_vertecies_buf 			: BasicGPUBuffer,
	global_indecies_buf 			: BasicGPUBuffer,
}

@(private="package")
mesh_manager_init :: proc(manager : ^MeshManager){
}

@(private="package")
mesh_manager_deinit :: proc(manager : ^MeshManager, gpu_device : ^sdl.GPUDevice){

	// @speed
	// we could prob loop through elements seperatly since this is a #soa array
	for &mesh in manager.meshes {

		if mesh.gpu_data.index_buf != nil {
			sdl.ReleaseGPUBuffer(gpu_device, mesh.gpu_data.index_buf);
		}
		if mesh.gpu_data.vertex_buf != nil {
			sdl.ReleaseGPUBuffer(gpu_device, mesh.gpu_data.vertex_buf);
		}

		if len(mesh.name) > 0 {
			delete(mesh.name);
		}
	}

	delete_soa(manager.meshes);
	delete_map(manager.id_map);

	delete(manager.global_vertecies);
	delete(manager.global_indecies);
	delete(manager.global_bl_bvh_nodes);

	delete(manager.global_vertecies_freelist);
	delete(manager.global_indecies_freelist);
	delete(manager.global_bl_bvh_nodes_freelist);

	gpu_buffer_release_buffers(gpu_device, &manager.global_bl_bvh_nodes_buf);
	gpu_buffer_release_buffers(gpu_device, &manager.global_vertecies_buf);
	gpu_buffer_release_buffers(gpu_device, &manager.global_indecies_buf);

	manager.num_loaded_meshes = 0;
}


// update any buffer uploads and put them into transfer buffers for next frames copy data pass. 
@(private="package")
mesh_manager_frame_update :: proc(manager : ^MeshManager, gpu_device : ^sdl.GPUDevice){

	bl_bvh_nodes_buf: {

		// check if required size is bigger than curr size
		buf_data := &manager.global_bl_bvh_nodes_buf;
		upinfo   := &buf_data.upload_info;

		element_byte_size  : int = size_of(geo.BvhNode);
		required_byte_size : int = len(manager.global_bl_bvh_nodes) * element_byte_size;

		if required_byte_size == 0 {
			break bl_bvh_nodes_buf;
		}

		if required_byte_size > cast(int)buf_data.curr_byte_size {
			// Reupload everything
			usage_flags := sdl.GPUBufferUsageFlags{.COMPUTE_STORAGE_READ}
			gpu_buffer_reallocate_buffers(gpu_device, buf_data, cast(u32)required_byte_size,usage_flags);
			// Define the entire buffer as the new upload region
			upinfo.requires_upload = true;
			upinfo.region_min_index = 0;
			upinfo.region_max_index = len(manager.global_bl_bvh_nodes) - 1;
		}

		if upinfo.region_max_index < upinfo.region_min_index {
			upinfo.requires_upload = false;
			break bl_bvh_nodes_buf;
		}
		
		upinfo.requires_upload = true;

		gpu_buffer_memcopy_upload_info_min_max_region_to_transfer_buffer(gpu_device, buf_data, &manager.global_bl_bvh_nodes[0], element_byte_size, false);
	}

	global_indecies_buf: {

		// check if required size is bigger than curr size
		buf_data := &manager.global_indecies_buf;
		upinfo   := &buf_data.upload_info;

		element_byte_size  : int = size_of(u32);
		required_byte_size : int = len(manager.global_indecies) * element_byte_size;

		if required_byte_size == 0 {
			break global_indecies_buf;
		}

		if required_byte_size > cast(int)buf_data.curr_byte_size {
			// Reupload everything
			usage_flags := sdl.GPUBufferUsageFlags{.COMPUTE_STORAGE_READ, .INDEX}
			gpu_buffer_reallocate_buffers(gpu_device, buf_data, cast(u32)required_byte_size, usage_flags);
			// Define the entire buffer as the new upload region
			upinfo.requires_upload = true;
			upinfo.region_min_index = 0;
			upinfo.region_max_index = len(manager.global_indecies) - 1;
		}

		if upinfo.region_max_index < upinfo.region_min_index {
			upinfo.requires_upload = false;
			break global_indecies_buf;
		}
		
		upinfo.requires_upload = true;

		gpu_buffer_memcopy_upload_info_min_max_region_to_transfer_buffer(gpu_device, buf_data, &manager.global_indecies[0], element_byte_size, false);
	}

	global_vertecies_buf: {

		// check if required size is bigger than curr size
		buf_data := &manager.global_vertecies_buf;
		upinfo   := &buf_data.upload_info;

		element_byte_size  : int = size_of([4]f32);
		required_byte_size : int = len(manager.global_vertecies) * element_byte_size;

		if required_byte_size == 0 {
			break global_vertecies_buf;
		}
		
		if required_byte_size > cast(int)buf_data.curr_byte_size {
			// Reupload everything
			usage_flags := sdl.GPUBufferUsageFlags{.COMPUTE_STORAGE_READ, .VERTEX}
			gpu_buffer_reallocate_buffers(gpu_device, buf_data, cast(u32)required_byte_size, usage_flags);
			// Define the entire buffer as the new upload region
			upinfo.requires_upload = true;
			upinfo.region_min_index = 0;
			upinfo.region_max_index = len(manager.global_vertecies) - 1;
		}

		if upinfo.region_max_index < upinfo.region_min_index {
			upinfo.requires_upload = false;
			break global_vertecies_buf;
		}
		
		upinfo.requires_upload = true;

		gpu_buffer_memcopy_upload_info_min_max_region_to_transfer_buffer(gpu_device, buf_data, &manager.global_vertecies[0], element_byte_size, false);
	}

}

@(private="package")
mesh_manager_add_mesh :: proc(manager : ^MeshManager, gpu_device : ^sdl.GPUDevice, mesh_data : ^MeshData) -> MeshID {

	IRI_PROFILE_PROCEDURE()

	engine_assert(mesh_data != nil);

	id : MeshID = -1;

	// @Note: invalid uuid is allowed! 
	// We generally want this system to allow storing meshes that are not stored with an
	// asset_uuid but perhaps be programatically generated
	invalid_uuid : bool = mesh_data.asset_uuid == AssetUUID_INVALID;

	if !invalid_uuid {
		if mesh_data.asset_uuid in manager.id_map {
			return manager.id_map[mesh_data.asset_uuid];
		}
	}
	
	gpu_mesh_data, upload_ok := mesh_manager_upload_mesh_data_to_gpu(gpu_device, mesh_data);
	
	if !upload_ok {
		log.errorf("faild to upload mesh data to gpu");
		return id;
	}

	mesh : Mesh;
	mesh.used = true;
	mesh.name = strings.clone(mesh_data.name);
	mesh.gpu_data = gpu_mesh_data;
	mesh.aabb = geo.aabb_from_min_max_vec3(mesh_data.aabb_min, mesh_data.aabb_max);
	mesh.transform = mesh_data.transform;

	vertex_position_byte_size : int = size_of([4]f32);

	mesh.global_buf_info = MeshGlobalBufferInfo{};
	// Copy mesh and bvh data to respective scene buffers.
	{
		// Blas Bvh Nodes
		{
			num_nodes : int = cast(int)mesh_data.bvh_num_nodes;
			
			mesh.global_buf_info.num_bvh_nodes = cast(u32)num_nodes;

			free_list_entry_index : int = multi_freelist_try_find_entry(&manager.global_bl_bvh_nodes_freelist, cast(u64)num_nodes);

			if free_list_entry_index >= 0 {

				free_entry := &manager.global_bl_bvh_nodes_freelist[free_list_entry_index];
				mesh.global_buf_info.bvh_nodes_offset = cast(u32)free_entry.index;
				
				upload_info_update_min_max(&manager.global_bl_bvh_nodes_buf.upload_info, int(free_entry.index), int(free_entry.index) + num_nodes);

				mem.copy_non_overlapping(&manager.global_bl_bvh_nodes[free_entry.index], &mesh_data.bvh_nodes[0], num_nodes * size_of(geo.BvhNode));
				multi_freelist_consume_entry_amount(&manager.global_bl_bvh_nodes_freelist, free_list_entry_index, cast(u64)num_nodes);

			} else {

				curr_len : int = len(manager.global_bl_bvh_nodes);

				mesh.global_buf_info.bvh_nodes_offset = cast(u32)curr_len;
				non_zero_append_elems(&manager.global_bl_bvh_nodes, ..mesh_data.bvh_nodes[0:num_nodes]);
				
				now_last_index : int = len(manager.global_bl_bvh_nodes) - 1;

				upload_info_update_min_max(&manager.global_bl_bvh_nodes_buf.upload_info, curr_len, now_last_index);
			}
		}

		// Blas Indecies 
		{
			num_indecies : int = cast(int)mesh_data.num_indecies;
			mesh.global_buf_info.num_indecies = cast(u32)num_indecies;

			free_list_entry_index : int = multi_freelist_try_find_entry(&manager.global_indecies_freelist, cast(u64)num_indecies);
			if free_list_entry_index >= 0 {

				free_entry := &manager.global_indecies_freelist[free_list_entry_index];
				mesh.global_buf_info.indecies_offset = cast(u32)free_entry.index;

				upload_info_update_min_max(&manager.global_indecies_buf.upload_info, int(free_entry.index), int(free_entry.index) + num_indecies);

				mem.copy_non_overlapping(&manager.global_indecies[free_entry.index], &mesh_data.bvh_indecies[0], num_indecies * size_of(u32));
				multi_freelist_consume_entry_amount(&manager.global_indecies_freelist, free_list_entry_index, cast(u64)num_indecies);
			} else {
				
				curr_len : int = len(manager.global_indecies);

				mesh.global_buf_info.indecies_offset = cast(u32)len(manager.global_indecies);
				non_zero_append_elems(&manager.global_indecies, ..mesh_data.bvh_indecies[0:num_indecies]);
				
				now_last_index : int = len(manager.global_indecies) - 1;

				upload_info_update_min_max(&manager.global_indecies_buf.upload_info, curr_len, now_last_index);
			}
		}

		// Blas Vertecies 
		{
			num_vertecies : int = cast(int)mesh_data.num_vertecies;
			mesh.global_buf_info.num_vertecies = cast(u32)num_vertecies;

			free_list_entry_index : int = multi_freelist_try_find_entry(&manager.global_vertecies_freelist, cast(u64)num_vertecies);

			if free_list_entry_index >= 0 {

				free_entry := &manager.global_vertecies_freelist[free_list_entry_index];
				mesh.global_buf_info.vertecies_offset = cast(u32)free_entry.index;

				upload_info_update_min_max(&manager.global_vertecies_buf.upload_info, int(free_entry.index), int(free_entry.index) + num_vertecies);

				mem.copy_non_overlapping(&manager.global_vertecies[free_entry.index], &mesh_data.positions[0], num_vertecies * vertex_position_byte_size);
				multi_freelist_consume_entry_amount(&manager.global_vertecies_freelist, free_list_entry_index, cast(u64)num_vertecies);
			} else {
				// cast to slice of same type to global_vertecies so we can use appen_elems
				_positions      : [^][4]f32 = cast([^][4]f32)mesh_data.positions;
				positions_slice : [][4]f32 = _positions[0:num_vertecies];

				curr_len : int = len(manager.global_vertecies);

				mesh.global_buf_info.vertecies_offset = cast(u32)len(manager.global_vertecies);
				non_zero_append_elems(&manager.global_vertecies, ..positions_slice[:]);

				now_last_index : int = len(manager.global_vertecies) - 1;

				upload_info_update_min_max(&manager.global_vertecies_buf.upload_info, curr_len, now_last_index);
			}
		}
	}

	free_spot : int = -1;
	for i in 0..<len(manager.meshes){

		if !manager.meshes.used[i] {
			free_spot = i;
			break;
		}
	}

	if free_spot == -1 {
		append_soa(&manager.meshes, mesh);
		id = cast(MeshID)(len(manager.meshes) -1);
	} else {
		manager.meshes[free_spot] = mesh;
		id = cast(MeshID)free_spot;
	}

	if !invalid_uuid {
		manager.id_map[mesh_data.asset_uuid] = id;
	}


	manager.num_loaded_meshes += 1;

	return id;
}

@(private="package")
mesh_manager_remove_mesh :: proc(manager : ^MeshManager, gpu_device : ^sdl.GPUDevice, id : ^MeshID){

	IRI_PROFILE_PROCEDURE()

	engine_assert(id != nil)

	mesh_id : MeshID = id^;
	index : i32 = cast(i32)mesh_id;

	if !mesh_manager_is_valid_id(manager, mesh_id) {
		return;
	}

	if len(manager.meshes[index].name) > 0 {
		delete(manager.meshes[index].name);
	}

	if manager.meshes[index].gpu_data.index_buf != nil {
		sdl.ReleaseGPUBuffer(gpu_device, manager.meshes[index].gpu_data.index_buf);
	}

	// if manager.meshes[index].gpu_data.shadow_index_buf != nil {
	// 	sdl.ReleaseGPUBuffer(gpu_device, manager.meshes[index].gpu_data.shadow_index_buf);
	// }

	if manager.meshes[index].gpu_data.vertex_buf != nil {
		sdl.ReleaseGPUBuffer(gpu_device, manager.meshes[index].gpu_data.vertex_buf);
	}

	if manager.meshes[index].gpu_data.vertex_pos_buf != nil {
		sdl.ReleaseGPUBuffer(gpu_device, manager.meshes[index].gpu_data.vertex_pos_buf);
	}


	global_buf_info := manager.meshes[index].global_buf_info;

	global_bl_bvh_nodes_freelist_entry := MultiFreelistEntry{
		index  = cast(u64)global_buf_info.bvh_nodes_offset,
		amount = cast(u64)global_buf_info.num_bvh_nodes,
	}
	multi_freelist_add_or_merge_entry(&manager.global_bl_bvh_nodes_freelist, global_bl_bvh_nodes_freelist_entry);

	global_vertecies_freelist_entry := MultiFreelistEntry{
		index  = cast(u64)global_buf_info.vertecies_offset,
		amount = cast(u64)global_buf_info.num_vertecies,
	}
	multi_freelist_add_or_merge_entry(&manager.global_vertecies_freelist, global_vertecies_freelist_entry);

	global_indecies_freelist_entry := MultiFreelistEntry{
		index  = cast(u64)global_buf_info.indecies_offset,
		amount = cast(u64)global_buf_info.num_indecies,
	}
	multi_freelist_add_or_merge_entry(&manager.global_indecies_freelist, global_indecies_freelist_entry);


	last : int = len(manager.meshes) -1;
	if int(index) == last {
		// if last entry, pop it of. there is no built in pop for #soa but this should be the same
		ordered_remove_soa(&manager.meshes, last);
	} else {
		manager.meshes[index] = Mesh{}; // Zero memory.
	}


	manager.num_loaded_meshes -= 1;

	// @Note: For now we will do the slow thing and iterate the entire id map to see if id exists there (it may not).
	// we could also store the UUID yet again inside Mesh structure when loading to make this faster but more memory..
	for key, value in manager.id_map {
		if value == mesh_id {
			delete_key(&manager.id_map, key);
			break;
		}  
	}

	// invalidate callers id
	id^ = -1;

	return;
}

mesh_manager_get_num_loaded_meshes :: proc(manager : ^MeshManager) -> u32 {
	return manager.num_loaded_meshes;
}

@(private="file")
mesh_manager_upload_mesh_data_to_gpu :: proc(gpu_device: ^sdl.GPUDevice, mesh_data: ^MeshData) -> (MeshGPUData, bool) {
	
	IRI_PROFILE_PROCEDURE()

	engine_assert(mesh_data != nil);

	num_indecies  : u32 = mesh_data.num_indecies;
	num_vertecies : u32 = mesh_data.num_vertecies;
	
	layout := mesh_data.vertex_data_layout;

	// Index Buffer
	index_buf_create_info : sdl.GPUBufferCreateInfo = {
		size  = num_indecies * size_of(u32),
		usage = {sdl.GPUBufferUsageFlag.INDEX},
	}

	// Vertex Buffer positions only
	vertex_pos_buf_create_info : sdl.GPUBufferCreateInfo = {
		size  = num_vertecies * size_of([4]f32),
		usage = {sdl.GPUBufferUsageFlag.VERTEX},
	}

	// Vertex Buffer Interleaved vert data
	interleaved_buf_byte_size : int = cast(int)mesh_data.num_vertecies * iricom.get_vertex_layout_byte_size(mesh_data.vertex_data_layout);

	vertex_buf_create_info : sdl.GPUBufferCreateInfo = {
		size  = cast(u32)interleaved_buf_byte_size,
		usage = {sdl.GPUBufferUsageFlag.VERTEX},
	}

	gpu_data : MeshGPUData;
	gpu_data.vertex_layout = layout;
	gpu_data.num_indecies  = num_indecies;
	gpu_data.num_vertecies = num_vertecies;
	gpu_data.index_buf      = sdl.CreateGPUBuffer(gpu_device, index_buf_create_info);
	gpu_data.vertex_buf     = sdl.CreateGPUBuffer(gpu_device, vertex_buf_create_info);
	gpu_data.vertex_pos_buf = sdl.CreateGPUBuffer(gpu_device, vertex_pos_buf_create_info)

	engine_assert(gpu_data.index_buf != nil);
	engine_assert(gpu_data.vertex_buf != nil);

	// copy into transfer buffer
	transfer_buf_info : sdl.GPUTransferBufferCreateInfo = {
		size = index_buf_create_info.size + vertex_pos_buf_create_info.size + vertex_buf_create_info.size,
		usage = sdl.GPUTransferBufferUsage.UPLOAD,
	}

	transfer_buf : ^sdl.GPUTransferBuffer = sdl.CreateGPUTransferBuffer(gpu_device, transfer_buf_info);
	defer sdl.ReleaseGPUTransferBuffer(gpu_device,transfer_buf);
	// map the transfer buffer to a pointer
	transfer_buf_data : [^]byte = transmute([^]byte)sdl.MapGPUTransferBuffer(gpu_device, transfer_buf,false);

	// copy data to transfer buffer

	// Index Buffer
	dst_offset : int = 0;
	mem.copy(&transfer_buf_data[dst_offset], &mesh_data.indecies[0], cast(int)index_buf_create_info.size);
	dst_offset += cast(int)index_buf_create_info.size;
	
	// Vertex Pos Buffer
	mem.copy(&transfer_buf_data[dst_offset], &mesh_data.positions[0], cast(int)vertex_pos_buf_create_info.size);
	dst_offset += cast(int)vertex_pos_buf_create_info.size;
	// Vertex Buffer
	mem.copy(&transfer_buf_data[dst_offset], &mesh_data.vertex_data[0], cast(int)vertex_buf_create_info.size);

	sdl.UnmapGPUTransferBuffer(gpu_device, transfer_buf);


	// UPLOAD TO GPU
	cmd_buf := sdl.AcquireGPUCommandBuffer(gpu_device);

    copy_pass : ^sdl.GPUCopyPass = sdl.BeginGPUCopyPass(cmd_buf);
    {
    	// Index Buffer
		transfer_loc : sdl.GPUTransferBufferLocation;
		transfer_loc.transfer_buffer = transfer_buf;
		transfer_loc.offset = 0;

		index_region : sdl.GPUBufferRegion = {
			buffer 	= gpu_data.index_buf,
			size 	= index_buf_create_info.size,
			offset 	= 0,
		}

		sdl.UploadToGPUBuffer(copy_pass, transfer_loc, index_region, false);

		// Position vertex Buffer
		pos_region : sdl.GPUBufferRegion = {
			buffer = gpu_data.vertex_pos_buf,
			size   = vertex_pos_buf_create_info.size,
			offset = 0,
		}

		//transfer_loc.offset = index_buf_create_info.size + index_buf_create_info.size;
		transfer_loc.offset = index_buf_create_info.size;
		sdl.UploadToGPUBuffer(copy_pass, transfer_loc, pos_region, false);

		// Interleaved Vertex buffer
		vertex_region : sdl.GPUBufferRegion = {
			buffer 	= gpu_data.vertex_buf,
			size 	= vertex_buf_create_info.size,
			offset 	= 0,
		}

		transfer_loc.offset = index_buf_create_info.size + vertex_pos_buf_create_info.size;
		sdl.UploadToGPUBuffer(copy_pass, transfer_loc, vertex_region, false);
    }
    sdl.EndGPUCopyPass(copy_pass);
    
    submit_ok := sdl.SubmitGPUCommandBuffer(cmd_buf);

    engine_assert(submit_ok);


    return gpu_data, true;
}

@(private="package")
mesh_manager_is_valid_id :: proc(manager : ^MeshManager, mesh_id: MeshID) -> bool {

	index : i32 = cast(i32)mesh_id;

	if index < 0 || index >= cast(i32)len(manager.meshes) {
		return false;
	}

	return manager.meshes.used[index];
}

@(private="package")
mesh_manager_get_id_from_asset_uuid :: proc(manager : ^MeshManager, asset_uuid : AssetUUID) -> (id : MeshID, exists : bool) {
	return manager.id_map[asset_uuid];
}

// @Speed. this is slow..
@(private="package")
mesh_manager_get_asset_uuid_from_mesh_id :: proc(manager : ^MeshManager, mesh_id : MeshID) -> (asset_uuid : AssetUUID, exists : bool){
	
	if !mesh_manager_is_valid_id(manager, mesh_id) {
		return AssetUUID_INVALID, false;
	}

	for a_uuid, m_id in manager.id_map {
		if m_id == mesh_id {
			return a_uuid, true;
		}
	}

	return AssetUUID_INVALID, false;
}

@(private="package")
mesh_manager_get_mesh_gpu_data :: proc(manager : ^MeshManager, id : MeshID) -> ^MeshGPUData{

	index : i32 = cast(i32)id;

	if !mesh_manager_is_valid_id(manager, id) {
		return nil;
	}

	gpu_data := &manager.meshes.gpu_data[index];

	if gpu_data.vertex_buf == nil || gpu_data.index_buf == nil {
		return nil;
	}

	return gpu_data;
}

@(private="package")
mesh_manager_get_aabb :: proc(manager : ^MeshManager, id: MeshID) -> geo.AABB {

	if !mesh_manager_is_valid_id(manager, id) {
		return geo.AABB{};
	}
	return manager.meshes.aabb[cast(i32)id];
}

// returns an identity transform if mesh id is invalid. Use 'mesh_manager_is_valid_id' if you need to know.
@(private="package")
mesh_manager_get_original_transform :: proc(manager :^MeshManager, id : MeshID) -> Transform {
	
	if !mesh_manager_is_valid_id(manager, id) {
		return transform_create_identity();
	}

	return manager.meshes.transform[cast(i32)id];
}

// ===================================================================
// public interface 
// ===================================================================


// get a copy of the mesh name allocated using context.temp_allocator.
// returns empty string on failure.
mesh_get_mesh_name :: proc(id : MeshID) -> string {
	manager :^MeshManager = engine.mesh_manager;


	if !mesh_manager_is_valid_id(manager, id) {
		return "";
	}

	return strings.clone(manager.meshes[id].name, context.temp_allocator);
}