package iri

import "core:log"
import "core:mem"
import "core:strings"
import "core:math/linalg"
import "odinary:poly"


AssetLight :: struct{

	type : LightType,
	color: [3]f32,
	strength : f32,
	spot_angle_inner_deg : f32,
	spot_angle_outer_deg : f32,

	transform : Transform,
}

AssetScene :: struct{
	mesh_instances : []MeshInstance,
	lights : []AssetLight,
}

AssetLoadFlags :: distinct bit_set[AssetLoadFlag]
AssetLoadFlag :: enum {
	LoadMaterials,
	LoadLights,
	ForceVertexLayout,
}

asset_loader_load_gltf_file_as_separate_meshes :: proc(filename : string, load_materials : bool = true) -> (mesh_instances : []MeshInstance, ok : bool){

	mesh_manager := engine.mesh_manager;
	gpu_device := get_gpu_device();

	
	load_flags := poly.LoadFlags{.LogErrors};
	if load_materials {
		load_flags += poly.LoadFlags{.LoadMaterials};
	}

	poly_scene := poly.load_gltf_from_path(filename, load_flags) or_return;

	//poly_scene := poly.load_assimp_gltf_from_file(filename, load_materials = load_materials, load_lights = false, fill_missing_vertex_attributes = false) or_return;


	defer {
		poly.destroy_scene(poly_scene);
		free(poly_scene);
		poly_scene = nil;
	}

	out_mesh_instances : [dynamic]MeshInstance;

	model_material_ids : [dynamic]MaterialID;
	defer delete(model_material_ids);

	if load_materials {
		for &poly_mat in poly_scene.materials {
			
			mat : Material;
			mat.render_technique = create_default_render_technique();
			mat.render_technique.alpha_mode = get_AlphaBlendMode_from_poly_AlphaBlendModes(poly_mat.alpha_mode);

			mat.variant = PbrMaterialData {
				albedo_color = poly_mat.albedo_color,
				emissive_color = poly_mat.emissive_color,
				emissive_strength = poly_mat.emissive_strength,
				roughness = poly_mat.roughness,
				metallic = poly_mat.metallic,

				alpha_value = poly_mat.alpha_value,
				//alpha_mode = get_AlphaBlendMode_from_poly_AlphaBlendModes(poly_mat.alpha_mode),
			}


			id : MaterialID = register_add_material(mat);

			append(&model_material_ids, id);
		}
	}


	for &poly_mesh in poly_scene.meshes {

		mesh_instance : MeshInstance = {
			flags = MESH_INSTANCE_FLAGS_DEFAULT,
			mesh_id = -1,
			mat_id  = -1,
			transform = Transform{
				position 	= poly_mesh.transform_position,
				scale 		= poly_mesh.transform_scale,
				orientation = poly_mesh.transform_orientation,
			}
		};

		mesh_data : ^MeshData = asset_loader_copy_poly_MeshData_to_MeshData(&poly_mesh, force_layout = true, forced_layout = .Minimal) or_continue;

		defer if mesh_data != nil {
			mesh_data_destroy(mesh_data);
			free(mesh_data);
		}

		mesh_id := mesh_manager_add_mesh(mesh_manager, gpu_device,mesh_data);
		
		if(mesh_id == -1){
			log.errorf("Failed to register mesh data");
			continue;
		}

		mesh_instance.mesh_id = mesh_id;

		if load_materials {

			poly_index: i32 = poly_mesh.material_index;
			if poly_index >= 0 {
				mesh_instance.mat_id = model_material_ids[poly_index];
			}
		}

		append(&out_mesh_instances, mesh_instance);
	}

	return out_mesh_instances[:], true;
}


asset_loader_load_gltf_file_as_combined_mesh :: proc(filename : string, load_first_material: bool = false) -> (mesh_instance: MeshInstance, ok : bool) {

	mesh_manager := engine.mesh_manager;
	gpu_device := get_gpu_device();

	mesh_instance.flags = MESH_INSTANCE_FLAGS_DEFAULT;
	mesh_instance.mesh_id = -1;
	mesh_instance.mat_id = -1;
	mesh_instance.transform = transform_create_identity();

	ok = false;

	load_flags := poly.LoadFlags{.LogErrors};
	if load_first_material {
		load_flags += poly.LoadFlags{.LoadMaterials};
	}

	poly_scene := poly.load_gltf_from_path(filename, load_flags) or_return;
	//poly_scene := poly.load_assimp_gltf_from_file(filename, load_materials = load_first_material, load_lights = false, fill_missing_vertex_attributes = false) or_return;

	defer {
		poly.destroy_scene(poly_scene);
		free(poly_scene);
		poly_scene = nil;
	}


	poly_combined_mesh := poly.join_scene_meshes(poly_scene, apply_transforms = true) or_return;

	defer {
		poly.destroy_mesh(poly_combined_mesh)
		free(poly_combined_mesh);
		poly_combined_mesh = nil;
	}


	mesh_data : ^MeshData = asset_loader_copy_poly_MeshData_to_MeshData(poly_combined_mesh, force_layout = true, forced_layout = .Minimal) or_return;


	defer if mesh_data != nil {
		mesh_data_destroy(mesh_data);
		free(mesh_data);
	}

	mesh_id := mesh_manager_add_mesh(mesh_manager,gpu_device, mesh_data);
	
	if mesh_id == -1 {
		log.errorf("Failed to register mesh data");
		return;
	}

	mesh_instance.mesh_id = mesh_id;

	if load_first_material && len(poly_scene.materials) > 0 {

		poly_mat := poly_scene.materials[0];

		mat : Material;
		mat.render_technique = create_default_render_technique();
		mat.render_technique.alpha_mode = get_AlphaBlendMode_from_poly_AlphaBlendModes(poly_mat.alpha_mode);

		mat.variant = PbrMaterialData{
			albedo_color = poly_mat.albedo_color,
			emissive_color = poly_mat.emissive_color,
			emissive_strength = poly_mat.emissive_strength,
			roughness = poly_mat.roughness,
			metallic = poly_mat.metallic,

			alpha_value = poly_mat.alpha_value,
		}

		mesh_instance.mat_id = register_add_material(mat);
	}

	ok = true;

	return;
}

asset_loader_load_gltf_file_as_asset_scene :: proc(filename : string, load_materials : bool = true, load_lights: bool = true) -> (asset_scene : ^AssetScene, ok : bool) {

	mesh_manager := engine.mesh_manager;
	gpu_device := get_gpu_device();

	load_flags := poly.LoadFlags{.LogErrors};
	if load_materials {
		load_flags += poly.LoadFlags{.LoadMaterials};
	}
	if load_lights {
		load_flags += poly.LoadFlags{.LoadLights};
	}

	poly_scene := poly.load_gltf_from_path(filename, load_flags) or_return;

	//poly_scene := poly.load_assimp_gltf_from_file(filename, load_materials = load_materials, load_lights = load_lights, fill_missing_vertex_attributes = false) or_return;

	defer {
		poly.destroy_scene(poly_scene);
		free(poly_scene);
		poly_scene = nil;
	}

	out_scene := new(AssetScene);


	// load lights
	if len(poly_scene.lights) > 0 {

		out_scene.lights = make_slice([]AssetLight, len(poly_scene.lights))
	}

	for &poly_light, index in poly_scene.lights {

		out_scene.lights[index] = AssetLight {

			type = get_LightType_from_poly_LightType(poly_light.type),
			color    = poly_light.color, 
			strength = poly_light.intensity,
			spot_angle_inner_deg = linalg.to_degrees(poly_light.spot_inner_cone_angle_radians),
			spot_angle_outer_deg = linalg.to_degrees(poly_light.spot_outer_cone_angle_radians),

			transform = Transform{
				scale = {1.0,1.0,1.0},
				position = poly_light.position,
				orientation = poly_light.orientation,
			}
		}
	}

	model_material_ids : [dynamic]MaterialID;
	defer delete(model_material_ids);

	if load_materials {
		for &poly_mat in poly_scene.materials {

			mat : Material;
			mat.render_technique = create_default_render_technique();
			mat.render_technique.alpha_mode = get_AlphaBlendMode_from_poly_AlphaBlendModes(poly_mat.alpha_mode);

			mat.variant = PbrMaterialData {
				albedo_color = poly_mat.albedo_color,
				emissive_color = poly_mat.emissive_color,
				emissive_strength = poly_mat.emissive_strength,
				roughness = poly_mat.roughness,
				metallic = poly_mat.metallic,

				alpha_value = poly_mat.alpha_value,
				//alpha_mode = get_AlphaBlendMode_from_poly_AlphaBlendModes(poly_mat.alpha_mode),
			}

			id : MaterialID = register_add_material(mat);

			append(&model_material_ids, id);
		}
	}
	
	out_mesh_instances : [dynamic]MeshInstance;


	for &poly_mesh, index in poly_scene.meshes {

		mesh_instance : MeshInstance = {
			flags = MESH_INSTANCE_FLAGS_DEFAULT,
			mesh_id = -1,
			mat_id  = -1,
			transform = Transform{
				position 	= poly_mesh.transform_position,
				scale 		= poly_mesh.transform_scale,
				orientation = poly_mesh.transform_orientation,
			}
		};

		mesh_data : ^MeshData = asset_loader_copy_poly_MeshData_to_MeshData(&poly_mesh, force_layout = true, forced_layout = .Minimal) or_continue;

		defer {
			mesh_data_destroy(mesh_data);
			free(mesh_data);
		}

		mesh_id := mesh_manager_add_mesh(mesh_manager, gpu_device, mesh_data);
		
		if(mesh_id == -1){
			log.errorf("Failed to register mesh data");
			continue;
		}

		mesh_instance.mesh_id = mesh_id;

		if(load_materials) {

			poly_index: i32 = poly_mesh.material_index;
			if(poly_index >= 0) {
				mesh_instance.mat_id = model_material_ids[poly_index];
			}
		}

		append(&out_mesh_instances, mesh_instance);
	}


	out_scene.mesh_instances = out_mesh_instances[:];

	return out_scene, true;
}


asset_loader_copy_poly_MeshData_to_MeshData :: proc(poly_mesh : ^poly.MeshData, force_layout : bool = false, forced_layout : VertexDataLayout = VertexDataLayout.Minimal) -> (^MeshData, bool) {
	
	if poly_mesh == nil {
		return nil, false;
	}

	if poly_mesh.num_indecies == 0 || poly_mesh.num_vertecies == 0 {
		return nil, false;
	}

	mesh_data : ^MeshData = new(MeshData, context.allocator);
	mesh_data.name = strings.clone(poly_mesh.name);

	mesh_data.transform.scale 		= poly_mesh.transform_scale;
	mesh_data.transform.position 	= poly_mesh.transform_position;
	mesh_data.transform.orientation = poly_mesh.transform_orientation;

	mesh_data.aabb_min = poly_mesh.aabb_min;
	mesh_data.aabb_max = poly_mesh.aabb_max;
		
	mesh_data.num_indecies  = poly_mesh.num_indecies;
	mesh_data.num_vertecies = poly_mesh.num_vertecies;	

	num_indecies  : int = cast(int)poly_mesh.num_indecies;
	num_vertecies : int = cast(int)poly_mesh.num_vertecies;
	
	mesh_data.indecies = make_multi_pointer([^]u32, num_indecies);
	mem.copy(&mesh_data.indecies[0], &poly_mesh.indecies[0], num_indecies * size_of(u32));

	layout : VertexDataLayout = .Minimal;

	if force_layout {
		layout = forced_layout;
	} else {
		// Find the layout that contains all data that is present

		 if poly_mesh.texcoords_1 != nil || poly_mesh.colors_1 != nil {
		 	layout = VertexDataLayout.Extended;
		 } else if poly_mesh.colors_0 != nil {
		 	layout = VertexDataLayout.Standard;
		 }
	}

	mesh_data.vertex_data_layout = layout;

	// Minimal Layout.
	mesh_data.positions   = make_multi_pointer([^][3]f32, num_vertecies);
	mesh_data.normals     = make_multi_pointer([^][3]f32, num_vertecies);
	mesh_data.tangents    = make_multi_pointer([^][4]f32, num_vertecies);
	mesh_data.texcoords_0 = make_multi_pointer([^][2]f32, num_vertecies);

	if poly_mesh.positions   != nil do mem.copy(&mesh_data.positions[0]  , &poly_mesh.positions[0]  , num_vertecies * size_of([3]f32));
	if poly_mesh.normals     != nil do mem.copy(&mesh_data.normals[0]    , &poly_mesh.normals[0]    , num_vertecies * size_of([3]f32));
	if poly_mesh.tangents    != nil do mem.copy(&mesh_data.tangents[0]   , &poly_mesh.tangents[0]   , num_vertecies * size_of([4]f32));
	if poly_mesh.texcoords_0 != nil do mem.copy(&mesh_data.texcoords_0[0], &poly_mesh.texcoords_0[0], num_vertecies * size_of([2]f32));

	if layout == .Standard || layout == .Extended {
		mesh_data.colors_0    = make_multi_pointer([^][4]f32, num_vertecies);
		if poly_mesh.colors_0    != nil do mem.copy(&mesh_data.colors_0[0]   , &poly_mesh.colors_0[0]   , num_vertecies * size_of([4]f32));
	}
	
	if layout == .Extended {
		// Only in extended layout
		mesh_data.colors_1    = make_multi_pointer([^][4]f32, num_vertecies);
		mesh_data.texcoords_1 = make_multi_pointer([^][2]f32, num_vertecies);
		if poly_mesh.colors_1    != nil do mem.copy(&mesh_data.colors_1[0]   , &poly_mesh.colors_1[0]   , num_vertecies * size_of([4]f32));
		if poly_mesh.texcoords_1 != nil do mem.copy(&mesh_data.texcoords_1[0], &poly_mesh.texcoords_1[0], num_vertecies * size_of([2]f32));
	}


	return mesh_data, true;
}


get_AlphaBlendMode_from_poly_AlphaBlendModes :: proc(alpha_blend_mode : poly.AlphaBlendModes) -> AlphaBlendMode {
	
	switch alpha_blend_mode {
		case .Opaque: return AlphaBlendMode.Opaque;
		case .Clip:   return AlphaBlendMode.Clip;
		case .Blend:  return AlphaBlendMode.Blend;
	}

	return AlphaBlendMode.Opaque;
}


get_LightType_from_poly_LightType :: proc(light_type : poly.LightType) -> LightType {
	
	switch light_type {
		case .DIRECTIONAL: 	return LightType.DIRECTIONAL;
		case .POINT: 		return LightType.POINT;
		case .SPOT: 		return LightType.SPOT;
	}

	return LightType.POINT;
}