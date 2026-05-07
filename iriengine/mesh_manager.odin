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
	//shadow_index_buf : ^sdl.GPUBuffer, // not using atm.
	vertex_buf 		: ^sdl.GPUBuffer,
	vertex_pos_buf 	: ^sdl.GPUBuffer,
	vertex_layout   : VertexDataLayout,
}

BlasBvhData :: struct {
	bvh_nodes_offset : u64,
	num_bvh_nodes : u64,

	bvh_indecies_offset : u64,
	num_bvh_indecies : u64,

	bvh_vertecies_offset : u64,
	num_bvh_vertecies : u64,
}

Mesh :: struct {
	used : bool,
	name : string,
	gpu_data : MeshGPUData,
	aabb : geo.AABB, // @Note: technically bvh_data root node will store the same aabb.
	
	bvh_data : BlasBvhData, 

	//@Note Transform of the loaded mesh file which we keep stored but its not used for rendering directly but will be copied to a drawables
	transform : Transform, 
}

Drawable :: struct {
	entity : Entity,
	draw_instance  : DrawInstance,
	world_oobb : geo.OBB, // world space obb
	world_mat  : matrix[4,4]f32,
	prev_physics_world_transform : Transform, // World Transform of the previous physics state!
}

MeshManager :: struct {
	num_loaded_meshes : u32,
	meshes : #soa[dynamic]Mesh,
	id_map : map[AssetUUID]MeshID,

	// blas = 'bottom level acceleration structure'
	blas_vertecies : [dynamic][3]f32,
	blas_indecies  : [dynamic]u32,
	blas_bvh_nodes : [dynamic]geo.BvhNode,

	blas_vertecies_freelist : [dynamic]MultiFreelistEntry,
	blas_indecies_freelist  : [dynamic]MultiFreelistEntry,
	blas_bvh_nodes_freelist : [dynamic]MultiFreelistEntry,
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


	delete(manager.blas_vertecies);
	delete(manager.blas_indecies);
	delete(manager.blas_bvh_nodes);

	delete(manager.blas_vertecies_freelist);
	delete(manager.blas_indecies_freelist);
	delete(manager.blas_bvh_nodes_freelist);

	manager.num_loaded_meshes = 0;
}

@(private="package")
mesh_manager_add_mesh :: proc(manager : ^MeshManager, gpu_device : ^sdl.GPUDevice, mesh_data : ^MeshData) -> MeshID {

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

	vertex_position_byte_size : int = size_of([3]f32);

	//mesh.bvh_info = geo.bvh_build_bottom_level(mesh_data.positions, cast(uint)size_of([3]f32), mesh_data.indecies, cast(uint)mesh_data.num_indecies);
	bvh_info := geo.bvh_build_bottom_level(mesh_data.positions, cast(uint)vertex_position_byte_size, mesh_data.indecies, cast(uint)mesh_data.num_indecies);
	defer {
		delete(bvh_info.nodes)
		delete(bvh_info.indecies)
	}

	mesh.bvh_data = BlasBvhData{};
	// Copy mesh and bvh data to respective scene buffers.
	{

		// Blas Bvh Nodes
		{
			num_nodes : int = len(bvh_info.nodes);
			
			mesh.bvh_data.num_bvh_nodes = cast(u64)num_nodes;

			free_list_entry_index : int = multi_freelist_try_find_entry(&manager.blas_bvh_nodes_freelist, cast(u64)num_nodes);

			if free_list_entry_index >= 0 {

				free_entry := &manager.blas_bvh_nodes_freelist[free_list_entry_index];
				mem.copy_non_overlapping(&manager.blas_bvh_nodes[free_entry.index], &bvh_info.nodes[0], num_nodes * size_of(geo.BvhNode));

				mesh.bvh_data.bvh_nodes_offset = free_entry.index;

				multi_freelist_consume_entry_amount(&manager.blas_bvh_nodes_freelist, free_list_entry_index, cast(u64)num_nodes);

			} else {
				curr_length : int = len(manager.blas_bvh_nodes);
				mesh.bvh_data.bvh_nodes_offset = cast(u64)curr_length;
				
				resize(&manager.blas_bvh_nodes, curr_length + num_nodes);
				mem.copy_non_overlapping(&manager.blas_bvh_nodes[curr_length], &bvh_info.nodes[0], num_nodes * size_of(geo.BvhNode));
			}
		}

		// Blas Indecies 
		{
			num_indecies : int = len(bvh_info.indecies);
			mesh.bvh_data.num_bvh_indecies = cast(u64)num_indecies;

			free_list_entry_index : int = multi_freelist_try_find_entry(&manager.blas_indecies_freelist, cast(u64)num_indecies);
			if free_list_entry_index >= 0 {

				free_entry := &manager.blas_indecies_freelist[free_list_entry_index];
				mem.copy_non_overlapping(&manager.blas_indecies[free_entry.index], &bvh_info.indecies[0], num_indecies * size_of(u32));

				multi_freelist_consume_entry_amount(&manager.blas_indecies_freelist, free_list_entry_index, cast(u64)num_indecies);
			} else {
				curr_length : int = len(manager.blas_indecies);
				mesh.bvh_data.bvh_indecies_offset = cast(u64)curr_length;
				
				resize(&manager.blas_indecies, curr_length + num_indecies);
				mem.copy_non_overlapping(&manager.blas_indecies[curr_length], &bvh_info.indecies[0], num_indecies * size_of(u32));
			}
		}

		// Blas Vertecies 
		{
			num_vertecies : int = cast(int)mesh_data.num_vertecies;
			mesh.bvh_data.num_bvh_vertecies = cast(u64)num_vertecies;

			free_list_entry_index : int = multi_freelist_try_find_entry(&manager.blas_vertecies_freelist, cast(u64)num_vertecies);

			if free_list_entry_index >= 0 {

				free_entry := &manager.blas_vertecies_freelist[free_list_entry_index];
				
				mem.copy(&manager.blas_vertecies[free_entry.index], &mesh_data.positions[0], num_vertecies * vertex_position_byte_size);

				multi_freelist_consume_entry_amount(&manager.blas_vertecies_freelist, free_list_entry_index, cast(u64)num_vertecies);
			} else {				
				curr_length : int = len(manager.blas_vertecies);
				mesh.bvh_data.bvh_vertecies_offset = cast(u64)curr_length;
				
				resize(&manager.blas_vertecies, curr_length + num_vertecies);
				mem.copy_non_overlapping(&manager.blas_vertecies[curr_length], &mesh_data.positions[0], num_vertecies * vertex_position_byte_size);
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


	bvh_data := manager.meshes[index].bvh_data;

	blas_bvh_nodes_freelist_entry := MultiFreelistEntry{
		index  = bvh_data.bvh_nodes_offset,
		amount = bvh_data.num_bvh_nodes,
	}
	multi_freelist_add_or_merge_entry(&manager.blas_bvh_nodes_freelist, blas_bvh_nodes_freelist_entry);

	blas_vertecies_freelist_entry := MultiFreelistEntry{
		index  = bvh_data.bvh_vertecies_offset,
		amount = bvh_data.num_bvh_vertecies,
	}
	multi_freelist_add_or_merge_entry(&manager.blas_vertecies_freelist, blas_vertecies_freelist_entry);

	blas_indecies_freelist_entry := MultiFreelistEntry{
		index  = bvh_data.bvh_indecies_offset,
		amount = bvh_data.num_bvh_indecies,
	}
	multi_freelist_add_or_merge_entry(&manager.blas_indecies_freelist, blas_indecies_freelist_entry);





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
	
	engine_assert(mesh_data != nil);

	num_indecies  : u32 = mesh_data.num_indecies;
	num_vertecies : u32 = mesh_data.num_vertecies;

	// Not in use atm.
	// shadow_indecies : [^]u32 = make_multi_pointer([^]u32, cast(int)num_indecies);
	// defer free(shadow_indecies)
	// meshopt.generateShadowIndexBuffer(&shadow_indecies[0], &mesh_data.indecies[0], cast(uint)num_indecies, &mesh_data.positions[0], cast(uint)num_vertecies, cast(uint)size_of([3]f32), cast(uint)size_of([3]f32));
	// meshopt.optimizeVertexCache(&shadow_indecies[0], &shadow_indecies[0], cast(uint)num_indecies, cast(uint)num_vertecies);

	
	layout := mesh_data.vertex_data_layout;


	// Index Buffer
	index_buf_create_info : sdl.GPUBufferCreateInfo = {
		size  = num_indecies * size_of(u32),
		usage = {sdl.GPUBufferUsageFlag.INDEX},
	}

	// Vertex Buffer positions only
	vertex_pos_buf_create_info : sdl.GPUBufferCreateInfo = {
		size  = num_vertecies * size_of([3]f32),
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
	//gpu_data.shadow_index_buf  = sdl.CreateGPUBuffer(gpu_device, index_buf_create_info); // can use same index buf create info.
	gpu_data.vertex_buf     = sdl.CreateGPUBuffer(gpu_device, vertex_buf_create_info);
	gpu_data.vertex_pos_buf = sdl.CreateGPUBuffer(gpu_device, vertex_pos_buf_create_info)

	engine_assert(gpu_data.index_buf != nil);
	engine_assert(gpu_data.vertex_buf != nil);

	// copy into transfer buffer
	transfer_buf_info : sdl.GPUTransferBufferCreateInfo = {
		size = index_buf_create_info.size + vertex_pos_buf_create_info.size + vertex_buf_create_info.size,
		// shadow index buf 
		//size = index_buf_create_info.size + index_buf_create_info.size + vertex_pos_buf_create_info.size + vertex_buf_create_info.size,
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
	// Shadow Index Buffer of same size
	//mem.copy(&transfer_buf_data[dst_offset], &shadow_indecies[0], cast(int)index_buf_create_info.size);
	//dst_offset += cast(int)index_buf_create_info.size;

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


		// shadow_index_region : sdl.GPUBufferRegion = {
		// 	buffer 	= gpu_data.shadow_index_buf,
		// 	size 	= index_buf_create_info.size,
		// 	offset 	= 0,
		// }

		// transfer_loc.offset = index_buf_create_info.size;		
		// sdl.UploadToGPUBuffer(copy_pass, transfer_loc, shadow_index_region, false);


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