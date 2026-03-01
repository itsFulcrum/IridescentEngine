package iri

import "core:log"
import "core:strings"
import "core:mem"


import sdl "vendor:sdl3"
import "odinary:mathy"


MeshID :: distinct i32


MeshGPUData :: struct{
	num_indecies  	: u32,
	num_vertecies 	: u32,
	index_buf  		: ^sdl.GPUBuffer,
	vertex_buf 		: ^sdl.GPUBuffer,
	vertex_pos_buf 	: ^sdl.GPUBuffer,
	vertex_layout : VertexDataLayout,
}

Mesh :: struct {
	used : bool,
	name : string,
	gpu_data : MeshGPUData,
	aabb : AABB,
//	mesh_data : rawptr, // ptrs to raw mesh data ??
	bvh : rawptr, // ptr to a accelartion strutcure of the mesh
}

MESH_INSTANCE_FLAGS_DEFAULT :: MeshInstanceFlags{.IS_VISIBLE, .CAST_SHADOWS}
MeshInstanceFlags :: distinct bit_set[MeshInstanceFlag]
MeshInstanceFlag :: enum u32 {
	IS_STATIC = 0,
	IS_VISIBLE,
	CAST_SHADOWS,
}

MeshInstance :: struct {
	flags : MeshInstanceFlags,
	mesh_id : MeshID,
	mat_id  : MaterialID,
	transform : Transform,
}

Drawable :: struct {
	entity : Entity,
	mesh_instance : MeshInstance,
	//transform : Transform, 		// in world space (transformed by entity transform)
	world_obb : OBB, // world space obb
	//aabb : AABB,	// in world space..
	world_mat : matrix[4,4]f32,
}

MeshManager :: struct {
	meshes : #soa[dynamic]Mesh,
}


@(private="package")
mesh_manager_init :: proc(manager : ^MeshManager){

}

@(private="package")
mesh_manager_deinit :: proc(manager : ^MeshManager, gpu_device : ^sdl.GPUDevice){

	// @speed
	// we could prob loop through elements seperatly since this is a #soa array
	for &mesh in manager.meshes {

		if(mesh.gpu_data.index_buf != nil){
			sdl.ReleaseGPUBuffer(gpu_device, mesh.gpu_data.index_buf);
		}
		if(mesh.gpu_data.vertex_buf != nil){
			sdl.ReleaseGPUBuffer(gpu_device, mesh.gpu_data.vertex_buf);
		}

		delete(mesh.name);
	}


	delete_soa(manager.meshes);
}

@(private="package")
mesh_manager_add_mesh :: proc(manager : ^MeshManager, gpu_device : ^sdl.GPUDevice, mesh_data : ^MeshData) -> MeshID {

	engine_assert(mesh_data != nil);

	id : MeshID = -1;

	
	gpu_mesh_data, upload_ok := mesh_manager_upload_mesh_data_to_gpu(gpu_device, mesh_data);
	
	if !upload_ok {
		log.errorf("faild to upload mesh data to gpu");
		return id;
	}

	mesh : Mesh;
	mesh.used = true;
	//mesh.vertex_layout = mesh_data.vertex_data_layout;
	mesh.name = strings.clone(mesh_data.name);
	mesh.gpu_data = gpu_mesh_data;
	mesh.aabb = AABB{ 
					min = [4]f32{mesh_data.aabb_min.x, mesh_data.aabb_min.y, mesh_data.aabb_min.z, 0.0}, 
					max = [4]f32{mesh_data.aabb_max.x, mesh_data.aabb_max.y, mesh_data.aabb_max.z, 0.0}
				};
	mesh.bvh = nil;


	free_spot : int = -1;
	for i in 0..<len(manager.meshes){

		if(!manager.meshes.used[i]){
			free_spot = i;
			break;
		}
	}

	if(free_spot == -1){
		append_soa(&manager.meshes, mesh);
		id = cast(MeshID)(len(manager.meshes) -1);
	} else {
		manager.meshes[free_spot] = mesh;
		id = cast(MeshID)free_spot;
	}

	return id;
}

@(private="package")
mesh_manager_remove_mesh :: proc(manager : ^MeshManager, gpu_device : ^sdl.GPUDevice, id : ^MeshID){

	index : i32 = cast(i32)id^;

	if index < 0 || index >= cast(i32)len(manager.meshes) {
		// invalid mesh id;
		return;
	}

	delete(manager.meshes[index].name);

	manager.meshes[index].used = false;
	manager.meshes[index].aabb = AABB{{0,0,0,0}, {0,0,0,0}};	
	manager.meshes[index].gpu_data.vertex_layout = .Minimal;
	manager.meshes[index].gpu_data.num_indecies  = 0; 
	manager.meshes[index].gpu_data.num_vertecies = 0;

	if manager.meshes[index].gpu_data.index_buf != nil {
		sdl.ReleaseGPUBuffer(gpu_device, manager.meshes[index].gpu_data.index_buf);
		manager.meshes[index].gpu_data.index_buf = nil;
	}

	if manager.meshes[index].gpu_data.vertex_buf != nil {
		sdl.ReleaseGPUBuffer(gpu_device, manager.meshes[index].gpu_data.vertex_buf);
		manager.meshes[index].gpu_data.vertex_buf = nil;
	}

	if manager.meshes[index].gpu_data.vertex_pos_buf != nil {
		sdl.ReleaseGPUBuffer(gpu_device, manager.meshes[index].gpu_data.vertex_pos_buf);
		manager.meshes[index].gpu_data.vertex_pos_buf = nil;
	}


	// invalidate user id
	id^ = -1;

	return;
}

mesh_manager_get_num_loaded_meshes :: proc(manager : ^MeshManager) -> u32 {
	return cast(u32)len(manager.meshes);
}

@(private="file")
mesh_manager_make_interleaved_vertex_buffer :: proc(mesh_data: ^MeshData) -> (data : [^]byte, size : int) {

	engine_assert(mesh_data != nil);

	num_indecies  : u32 = mesh_data.num_indecies;
	num_vertecies : u32 = mesh_data.num_vertecies;

	layout := mesh_data.vertex_data_layout;
	interleaved_buf_byte_size : int;
	
	switch layout {
		case .Minimal:  interleaved_buf_byte_size = cast(int)num_vertecies * size_of(VertexDataMinimal);
		case .Standard: interleaved_buf_byte_size = cast(int)num_vertecies * size_of(VertexDataStandard);
		case .Extended: interleaved_buf_byte_size = cast(int)num_vertecies * size_of(VertexDataExtended);
	}

	interleaved_vertex_buffer , alloc_err := make_multi_pointer([^]byte, interleaved_buf_byte_size, context.allocator);
	if alloc_err != .None {
		log.fatalf("Memory Allocation Error: {}", alloc_err);
		return nil, 0;
	}

	switch layout {
		case .Minimal: {

			buf : [^]VertexDataMinimal = cast([^]VertexDataMinimal)interleaved_vertex_buffer;
			for i in 0..<num_vertecies {
				normal_oct  : [2]f32 = mathy.oct_encode(mesh_data.normals[i]);
				tangent_oct : [2]f32 = mathy.oct_encode(mesh_data.tangents[i]);

				buf[i] = VertexDataMinimal {
					normal_tangent = [4]f32{normal_oct.x, normal_oct.y, tangent_oct.x, tangent_oct.y},
					texcoord_0 = mesh_data.texcoords_0[i],
				}
			}
		}
		case .Standard: {
			buf : [^]VertexDataStandard = cast([^]VertexDataStandard)interleaved_vertex_buffer;

			for i in 0..<num_vertecies {
				normal_oct  : [2]f32 = mathy.oct_encode(mesh_data.normals[i]);
				tangent_oct : [2]f32 = mathy.oct_encode(mesh_data.tangents[i]);

				buf[i] = VertexDataStandard {
					normal_tangent 	= [4]f32{normal_oct.x, normal_oct.y, tangent_oct.x, tangent_oct.y},
					color_0 	   	= mesh_data.colors_0[i],
					texcoord_0 		= mesh_data.texcoords_0[i],
				}
			}
		}
		case .Extended: {
			buf : [^]VertexDataExtended = cast([^]VertexDataExtended)interleaved_vertex_buffer;

			for i in 0..<num_vertecies {
				normal_oct  : [2]f32 = mathy.oct_encode(mesh_data.normals[i]);
				tangent_oct : [2]f32 = mathy.oct_encode(mesh_data.tangents[i]);

				buf[i] = VertexDataExtended {
					normal_tangent 	= [4]f32{normal_oct.x, normal_oct.y, tangent_oct.x, tangent_oct.y},
					color_0 	   	= mesh_data.colors_0[i],
					color_1 	   	= mesh_data.colors_1[i],
					texcoord_0 		= mesh_data.texcoords_0[i],
					texcoord_1 		= mesh_data.texcoords_1[i],
				}
			}
		}
	}

	return interleaved_vertex_buffer, interleaved_buf_byte_size;
}


@(private="file")
mesh_manager_upload_mesh_data_to_gpu :: proc(gpu_device: ^sdl.GPUDevice, mesh_data: ^MeshData) -> (MeshGPUData, bool) {
	
	engine_assert(mesh_data != nil);

	num_indecies  : u32 = mesh_data.num_indecies;
	num_vertecies : u32 = mesh_data.num_vertecies;

	layout := mesh_data.vertex_data_layout;

	interleaved_vertex_buffer , interleaved_buf_byte_size := mesh_manager_make_interleaved_vertex_buffer(mesh_data);
	defer free(interleaved_vertex_buffer);

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
	// Vertex Pos Buffer
	dst_offset += cast(int)index_buf_create_info.size;
	mem.copy(&transfer_buf_data[dst_offset], &mesh_data.positions[0], cast(int)vertex_pos_buf_create_info.size);
	// Vertex Buffer
	dst_offset += cast(int)vertex_pos_buf_create_info.size;
	mem.copy(&transfer_buf_data[dst_offset], &interleaved_vertex_buffer[0], cast(int)vertex_buf_create_info.size);

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
		transfer_loc.offset = index_buf_create_info.size;
		pos_region : sdl.GPUBufferRegion = {
			buffer = gpu_data.vertex_pos_buf,
			size   = vertex_pos_buf_create_info.size,
			offset = 0,
		}

		sdl.UploadToGPUBuffer(copy_pass, transfer_loc, pos_region, false);

		// Interleaved Vertex buffer
		transfer_loc.offset = index_buf_create_info.size + vertex_pos_buf_create_info.size;
		vertex_region : sdl.GPUBufferRegion = {
			buffer 	= gpu_data.vertex_buf,
			size 	= vertex_buf_create_info.size,
			offset 	= 0,
		}

		sdl.UploadToGPUBuffer(copy_pass, transfer_loc, vertex_region, false);
    }
    sdl.EndGPUCopyPass(copy_pass);
    
    submit_ok := sdl.SubmitGPUCommandBuffer(cmd_buf);

    engine_assert(submit_ok);


    return gpu_data, true;
}


@(private="package")
mesh_manager_is_valid_id :: proc(manager : ^MeshManager, id: MeshID) -> bool {

	index : i32 = cast(i32)id;

	if index < 0 || index >= cast(i32)len(manager.meshes) {
		return false;
	}

	return manager.meshes.used[index];
}


@(private="package")
mesh_manager_get_mesh_gpu_data :: proc(manager : ^MeshManager, id : MeshID) -> ^MeshGPUData{

	index : i32 = cast(i32)id;

	if index < 0 || index >= cast(i32)len(manager.meshes) {
		// invalid mesh id;
		return nil;
	}

	gpu_data := &manager.meshes.gpu_data[index];

	if gpu_data.vertex_buf == nil || gpu_data.index_buf == nil {
		return nil;
	}

	return gpu_data;
}

@(private="package")
mesh_manager_get_aabb :: proc(manager : ^MeshManager, id: MeshID) -> AABB {

	index : i32 = cast(i32)id;

	if index < 0 || index >= cast(i32)len(manager.meshes) {
		return AABB{};
	}

	
	return manager.meshes.aabb[index];
}
