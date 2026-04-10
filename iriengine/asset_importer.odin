package iri


import "base:runtime"
import "core:log"
import "core:mem"
import "core:os"

import "core:strings"
import "core:math/linalg"
import "odinary:poly"
import "odinary:mathy"

import iricom "iricommon"
import iria "iriasset"

// @Note: The Importers job generally is to take common interchange formats, like glTF or .png etc 
// and convert them into runtime ready formats for the engine. This can invlolve
// producing several differnt output files from one imput file. Especially in the case of meshes.
// Ideally the importer is never called at runtime of a distributed application.

AssetWriteFlags :: iria.WriteFlags
AssetWriteFlag  :: iria.WriteFlag

AssetImportFlags :: distinct bit_set[AssetImportFlag]
AssetImportFlag :: enum {
	LogErrors,
	OverwriteExisting, // if not set and asset exists already, import will fail
	
	MeshImportMaterials,
	MeshImportLights,
	MeshCombineMeshes,				// combine all meshes into one, loses material information.
	MeshCreateCollection, 	   	   // 	
	MeshForceVertexLayout,		   // enables forcing a vertex layout. specified by setting one of the 3 following flags.
	MeshForceVertexLayoutMinimal,  // ignored if 'MeshForceVertexLayout' is not set.
	MeshForceVertexLayoutStandard, // ignored if force minimal is set.
	MeshForceVertexLayoutExtended, // ignored if force standard or force minimal is set
}

asset_importer_import_gltf_to_project :: proc(load_path : string, store_directory_path : string, import_flags : AssetImportFlags) -> (ok : bool) {
	
	log_errors : bool = .LogErrors in import_flags;

	store_dir_path_abs := clean_path_absolute(store_directory_path) or_return;
	if !os.is_directory(store_dir_path_abs){

		make_err := os.make_directory_all(store_dir_path_abs);
		if make_err != os.ERROR_NONE {
			log.errorf("AssetImporter: Failed to create directory to write assets to {}", store_dir_path_abs);
			return false;
		}
	}

	// load flags
	load_flags : poly.LoadFlags = importer_get_poly_load_flags_from_asset_import_flags(import_flags);

	poly_scene := poly.load_gltf_from_path(load_path, load_flags) or_return;
	defer poly.free_scene(poly_scene);


	// EXPORT STAGE:
	
	// We need asset manager to register files	
	asset_manager := engine.asset_manager;


	_ , load_file_name  := os.split_path(load_path);
	load_file_name_only := os.short_stem(load_file_name);

	can_overwrite_existing : bool = .OverwriteExisting in import_flags;
	write_flags : iria.WriteFlags = importer_iria_write_flags_from_asset_import_flags(import_flags);

	// @Note:
	// we temp store the uuid of the materials we loaded and exported.
	// even if exporting faild we write an Invalid ID because we need to ensure 
	// that meshes can later reference the correct uuid
	material_uuids : []AssetUUID = nil;
	defer if material_uuids != nil {
		delete(material_uuids);
	}

	create_collection : bool = .MeshCreateCollection in import_flags;

	scene_collection : ^iria.SceneCollectionAsset = nil;
	scene_collection_draw_insts : [dynamic]iria.DrawInstanceAsset;
	scene_collection_lights     : [dynamic]AssetUUID;

	if create_collection {
		scene_collection = new(iria.SceneCollectionAsset, context.allocator);
	}
	defer if scene_collection != nil {
		iria.free_scene_collection_asset(scene_collection);
	}


	// Get the full path we want to write the asset to.  "store_dir/asset_name.iria"
	// If asset_name is empty string ("") use fallback name instead.
	// retruns if file exists already and returns !ok when can_overwrite_existing is false but file exists.
	get_write_filepath :: proc(store_dir_path : string, asset_name : string, fallback_name : string = "NewAsset", can_overwrite_existing : bool = false, log_errors : bool = false) -> (path : string, file_exists : bool, ok : bool) {

		file_name_only : string = asset_name;

		if len(asset_name) <= 0 {
			file_name_only = fallback_name;
			engine_assert(len(fallback_name) > 0);
		}

		store_filename , osErr := os.join_filename(asset_name, iria.FILE_EXTENTION_NAME, context.temp_allocator);
		engine_assert(osErr == os.ERROR_NONE);

		full_store_filepath, alloc_err := os.join_path({store_dir_path, store_filename}, context.temp_allocator);
		engine_assert(alloc_err == nil);

		exists := os.exists(full_store_filepath);
		
		if exists && !can_overwrite_existing {
			if log_errors do log.warnf("Cannot export asset file with name {} to project directory {}. 'OverwriteExisting' flag is not set and file already exists at", store_filename, store_dir_path);
			return full_store_filepath, true , false;
		}

		return full_store_filepath, exists, true;
	}

	ImportMaterials: if .MeshImportMaterials in import_flags {

		num_mats : int = len(poly_scene.materials);
		if num_mats <= 0 {
			break ImportMaterials;
		}

		material_uuids = make_slice([]AssetUUID, num_mats, context.allocator);

		mats_store_dir : string = store_dir_path_abs;
		if create_collection {
			mats_dir_name : string = strings.join({load_file_name_only, "_Materials"},"", context.temp_allocator);
			mats_store_dir = os.join_path({store_dir_path_abs, mats_dir_name}, context.temp_allocator) or_else store_dir_path_abs;

			if !os.exists(mats_store_dir){
				os.make_directory(mats_store_dir);
			}
		}

		for i in 0..<num_mats {

			poly_mat := &poly_scene.materials[i];

			mat := importer_create_material_from_poly_MaterialData(poly_mat);
			// TODO we should make a generic free / deinit funciton..
			defer {
				delete_string(mat.name);
			}

			full_store_filepath, file_exists := get_write_filepath(mats_store_dir, mat.name, "NewMaterial", can_overwrite_existing, log_errors) or_continue;

			mat_asset : iria.MaterialAsset;
			mat_asset.mat = mat;
			mat_asset.asset_uuid = asset_manager_get_or_generate_asset_uuid(full_store_filepath, iria.AssetType.Material, log_errors) or_continue;

			iria.asset_material_write_to_file(full_store_filepath, &mat_asset, write_flags) or_continue

			is_registered := asset_manager_register_asset_file_by_path(asset_manager, full_store_filepath);

			material_uuids[i] = mat_asset.asset_uuid;
		}
	}

	// Export Meshes
	combined_mesh: if .MeshCombineMeshes in import_flags {

		poly_combined_mesh := poly.join_scene_meshes(poly_scene, apply_transforms = true) or_break combined_mesh;
		defer poly.free_mesh(poly_combined_mesh);

		mesh_data : ^MeshData = importer_make_MeshData_from_poly_MeshData(poly_combined_mesh, import_flags) or_break combined_mesh;
		defer free_mesh_data(mesh_data);

		full_store_filepath, file_exists := get_write_filepath(store_dir_path_abs, mesh_data.name, "CombinedMesh", can_overwrite_existing, log_errors) or_break combined_mesh;
		
		mesh_data.asset_uuid = asset_manager_get_or_generate_asset_uuid(full_store_filepath, iria.AssetType.Mesh, log_errors) or_break combined_mesh;
		
		iria.asset_mesh_write_to_file(full_store_filepath, mesh_data, write_flags) or_break combined_mesh;

		if create_collection {
			draw_asset : iria.DrawInstanceAsset;
			draw_asset.flags     = iricom.DRAW_INSTANCE_FLAGS_DEFAULT;
			draw_asset.mesh_uuid = mesh_data.asset_uuid;

			if poly_combined_mesh.material_index > -1 && material_uuids != nil {
				draw_asset.mat_uuid = material_uuids[poly_combined_mesh.material_index];
			}

			append(&scene_collection_draw_insts, draw_asset);
		}


		is_registered := asset_manager_register_asset_file_by_path(asset_manager, full_store_filepath);

	} else {


		mesh_store_dir : string = store_dir_path_abs;

		if create_collection {
			mesh_dir_name : string = strings.join({load_file_name_only, "_Meshes"},"", context.temp_allocator);
			mesh_store_dir = os.join_path({store_dir_path_abs, mesh_dir_name}, context.temp_allocator) or_else store_dir_path_abs;

			if !os.exists(mesh_store_dir){
				os.make_directory(mesh_store_dir);
			}
		}


		for &poly_mesh in poly_scene.meshes {

			mesh_data : ^MeshData = importer_make_MeshData_from_poly_MeshData(&poly_mesh, import_flags) or_continue;
			defer free_mesh_data(mesh_data);

			full_store_filepath, file_exists := get_write_filepath(mesh_store_dir, mesh_data.name, "NewMesh", can_overwrite_existing, log_errors) or_break combined_mesh;

			mesh_data.asset_uuid = asset_manager_get_or_generate_asset_uuid(full_store_filepath, iria.AssetType.Mesh, log_errors) or_continue;

			iria.asset_mesh_write_to_file(full_store_filepath, mesh_data, write_flags) or_continue;

			if create_collection {
				draw_asset : iria.DrawInstanceAsset;
				draw_asset.flags     = iricom.DRAW_INSTANCE_FLAGS_DEFAULT;
				draw_asset.mesh_uuid = mesh_data.asset_uuid;

				if poly_mesh.material_index > -1 && material_uuids != nil {
					draw_asset.mat_uuid = material_uuids[poly_mesh.material_index];
				}

				append(&scene_collection_draw_insts, draw_asset);
			}

			is_registered := asset_manager_register_asset_file_by_path(asset_manager, full_store_filepath);
		}
	}

	lights_import: if .MeshImportLights in import_flags {

		
		lights_store_dir : string = store_dir_path_abs;

		if create_collection {
			lights_dir_name : string = strings.join({load_file_name_only, "_Lights"},"", context.temp_allocator);
			lights_store_dir = os.join_path({store_dir_path_abs, lights_dir_name}, context.temp_allocator) or_else lights_store_dir;

			if !os.exists(lights_store_dir){
				os.make_directory(lights_store_dir);
			}

		}

		for &poly_light in poly_scene.lights {

			light_asset := importer_create_light_asset_from_poly_LightData(&poly_light);

			full_store_filepath, file_exists := get_write_filepath(lights_store_dir, poly_light.name, "NewLight", can_overwrite_existing, log_errors) or_continue;

			asset_uuid := asset_manager_get_or_generate_asset_uuid(full_store_filepath, iria.AssetType.Light, log_errors) or_continue;

			iria.asset_light_write_to_file(full_store_filepath, &light_asset, asset_uuid, write_flags) or_continue
			
			if create_collection {
				append(&scene_collection_lights, asset_uuid);
			}

			is_registered := asset_manager_register_asset_file_by_path(asset_manager, full_store_filepath);

		}
	}

	collection: if create_collection {

		if len(scene_collection_draw_insts) > 0 {
			scene_collection.draw_inst_assets = scene_collection_draw_insts[:];
		}

		if len(scene_collection_lights) > 0 {
			scene_collection.light_assets = scene_collection_lights[:];
		}

		// Filename will be   LoadFilename + "_IriCollection" + ".iria"
		collection_filename : string = strings.join({load_file_name_only,"_SceneCollection"},"", context.temp_allocator);

		collection_store_filepath, file_exists := get_write_filepath(store_dir_path_abs, collection_filename, "NewSceneCollection", can_overwrite_existing, log_errors) or_break collection;

		scene_collection.asset_uuid = asset_manager_get_or_generate_asset_uuid(collection_store_filepath, iria.AssetType.SceneCollection, log_errors) or_break collection;

		collection_write_ok := iria.asset_scene_collection_write_to_file(collection_store_filepath, scene_collection, write_flags);
		if !collection_write_ok {
			log.warnf("Failed to write Scene Collection asset to path: {}", collection_store_filepath);
			break collection
		}

		is_registered := asset_manager_register_asset_file_by_path(asset_manager, collection_store_filepath);
	}


	return true;
}

// @Note normal and tangent Must be valid orthogonal values and not just 0 initialized.
importer_encode_qtangent :: proc(normal : [3]f32, tangent : [4]f32) -> [4]f32 {

	N : [3]f32 = normal;	
	T : [3]f32 = tangent.xyz;
	B := linalg.cross(N,T);

	tbn : matrix[3,3]f32;
	tbn[0] = T;
	tbn[1] = B;
	tbn[2] = N;

	qtan : quaternion128 = linalg.quaternion_from_matrix3_f32(tbn);
	qtan = linalg.quaternion_normalize(qtan);

	// make sure its always positve
	if qtan.w < 0.0 {
		qtan = -qtan;
	}


	// @Note: when we will use 16 bit SNORM we would need to add a bias
	// I dont want to switch to 16-bit SNORM yet because i want to have textures
	// and normal maps working first to see how much impackt the precision loss makes.

	// https://www.yosoygames.com.ar/wp/2018/03/vertex-formats-part-1-compression/

	// "Because '-0' sign information is lost when using integers,
	// we need to apply a "bias"; while making sure the Quatenion
	// stays normalized."

	/*
	//Bias = 1 / [2^(bits-1) - 1]
	bias : f32 : 1.0 / 32767.0;

	// ** Also our shaders assume qTangent.w is never 0. **
	if qtan.w < bias {
	    normFactor : f32 = math.sqrt_f32( 1.0 - bias * bias );
	    qtan.w = bias;
	    qtan.x *= normFactor;
	    qtan.y *= normFactor;
	    qtan.z *= normFactor;
	}

	*/


	// encode bitangent sign as flipped quaternion
	if tangent.w <= 0 {
		qtan = -qtan;
	}

	return [4]f32{qtan.x, qtan.y, qtan.z, qtan.w};
}


importer_iria_write_flags_from_asset_import_flags :: proc(import_flags : AssetImportFlags) -> iria.WriteFlags {
	
	write_flags : iria.WriteFlags = iria.WriteFlags{};
	
	if .LogErrors in import_flags {
		write_flags += iria.WriteFlags{.LogErrors}
	}
	if .OverwriteExisting in import_flags {
		write_flags += iria.WriteFlags{.OverwriteExisting}
	}

	return write_flags;
}


// ======= Conversions from poly lib ==================

@(private="package")
importer_get_poly_load_flags_from_asset_import_flags :: proc(import_flags : AssetImportFlags) -> poly.LoadFlags {

	load_flags := poly.LoadFlags{};
	if .LogErrors in import_flags {
		load_flags += poly.LoadFlags{.LogErrors};
	}
	if .MeshImportMaterials in import_flags {
		load_flags += poly.LoadFlags{.LoadMaterials};
	}
	if .MeshImportLights in import_flags {
		load_flags += poly.LoadFlags{.LoadLights};
	}

	return load_flags;
}

importer_make_MeshData_from_poly_MeshData :: proc(poly_mesh : ^poly.MeshData, import_flags : AssetImportFlags) -> (^MeshData, bool) {
	
	forced_layout : VertexDataLayout = .Minimal;
	force_layout : bool = .MeshForceVertexLayout in import_flags;

	if force_layout {
		if .MeshForceVertexLayoutMinimal in import_flags {
			forced_layout = .Minimal;
		} else if .MeshForceVertexLayoutStandard in import_flags {
			forced_layout = .Standard;
		} else if .MeshForceVertexLayoutExtended in import_flags {
			forced_layout = .Extended;
		}
	}

	if poly_mesh == nil {
		return nil, false;
	}

	if poly_mesh.num_indecies == 0 || poly_mesh.num_vertecies == 0 {
		return nil, false;
	}

	if poly_mesh.positions == nil {
		return nil, false;
	}

	if poly_mesh.indecies == nil {
		return nil, false;
	}

	mesh_data: ^MeshData = new(MeshData, context.allocator);
	mesh_data.name = strings.clone(poly_mesh.name);

	mesh_data.transform = cast(Transform)poly_mesh.transform;

	mesh_data.aabb_min = poly_mesh.aabb_min;
	mesh_data.aabb_max = poly_mesh.aabb_max;
		
	mesh_data.num_indecies  = poly_mesh.num_indecies;
	mesh_data.num_vertecies = poly_mesh.num_vertecies;	

	num_indecies  : int = cast(int)poly_mesh.num_indecies;
	num_vertecies : int = cast(int)poly_mesh.num_vertecies;
	
	mesh_data.indecies = make_multi_pointer([^]u32, num_indecies);
	mem.copy(&mesh_data.indecies[0], &poly_mesh.indecies[0], num_indecies * size_of(u32));

	layout : iria.VertexDataLayout = .Minimal;

	if force_layout {
		layout = forced_layout;
	} else {
		// Find the layout that contains all data that is present

		 if poly_mesh.texcoords_1 != nil || poly_mesh.colors_1 != nil {
		 	layout = .Extended;
		 } else if poly_mesh.colors_0 != nil {
		 	layout = .Standard;
		 }
	}

	mesh_data.vertex_data_layout = layout;

	positions_buf_byte_size : int = num_vertecies * size_of([3]f32);

	mesh_data.positions   = make_multi_pointer([^]byte, positions_buf_byte_size, context.allocator);
	mem.copy(&mesh_data.positions[0], &poly_mesh.positions[0], positions_buf_byte_size);
	
	vertex_data_buf_byte_size : int = num_vertecies * iricom.get_vertex_layout_byte_size(layout);

	mesh_data.vertex_data = make_multi_pointer([^]byte, vertex_data_buf_byte_size, context.allocator);

	// @Note: does no bound checking and assumes positions are present.
	get_valid_normal :: proc(poly_mesh : ^poly.MeshData, index : int) -> [3]f32 {

		if poly_mesh.normals != nil {
			return linalg.normalize(poly_mesh.normals[index]);
		}

		// as fallback we can maybe use normalized position as normal.
		// better than nothing.
		N : [3]f32 = poly_mesh.positions[index];

		if linalg.length(N) < 0.0001 {
			return TRANSFORM_WORLD_UP;	
		}

		return linalg.normalize(N);
	}

	// @Note: does no bound checking.
	get_valid_tangent :: proc(poly_mesh : ^poly.MeshData, index : int, normal : [3]f32) -> [4]f32 {

		T : [4]f32 = {0,0,0,1};

		if poly_mesh.tangents != nil {
			T = poly_mesh.tangents[0];
		}

		// Gram-Schmidt orthogonalize
		// because its quite possible that we get some drift in loading vertex data from files.
		T.xyz = T.xyz - normal * linalg.dot(normal, T.xyz);
		
		// If tangents are invalid (length 0)
		// we fallback to something so we get at least correct normals in vertex shader decoding		
		if linalg.length(T.xyz) < 1e-5 {
		    // invalid tanget, compute anything perpendicular to normal as fallback
			T.xyz = mathy.any_perpendicular(normal);
		} else {
		    T.xyz = linalg.normalize(T.xyz);
		}

		return T;
	}

	switch layout {
		case .Minimal: {
			buf_minimal : [^]VertexDataMinimal = cast([^]VertexDataMinimal)mesh_data.vertex_data;
			for v in 0..<num_vertecies {

				normal  : [3]f32 = get_valid_normal(poly_mesh, v);
				tangent : [4]f32 = get_valid_tangent(poly_mesh, v, normal);

				buf_minimal[v] = VertexDataMinimal {
					qtangent = importer_encode_qtangent(normal, tangent),
					texcoord_0 = poly_mesh.texcoords_0 == nil ? [2]f32{0,0} : poly_mesh.texcoords_0[v],
				}
			}
		}
		case .Standard: {
			buf_standard : [^]VertexDataStandard = cast([^]VertexDataStandard)mesh_data.vertex_data;
			
			for v in 0..<num_vertecies {

				normal  : [3]f32 = get_valid_normal(poly_mesh, v);
				tangent : [4]f32 = get_valid_tangent(poly_mesh, v, normal);

				buf_standard[v] = VertexDataStandard {
					qtangent    = importer_encode_qtangent(normal, tangent),
					texcoord_0  = poly_mesh.texcoords_0 != nil ? poly_mesh.texcoords_0[v] : [2]f32{0,0},
					color_0 	= poly_mesh.colors_0    != nil ? poly_mesh.colors_0[v] : [4]f32{1,1,1,1},
				}
			}
		}
		case .Extended: {
			buf_extended : [^]VertexDataExtended = cast([^]VertexDataExtended)mesh_data.vertex_data;
			
			for v in 0..<num_vertecies {

				normal  : [3]f32 = get_valid_normal(poly_mesh, v);
				tangent : [4]f32 = get_valid_tangent(poly_mesh, v, normal);

				buf_extended[v] = iria.VertexDataExtended {
					qtangent    = importer_encode_qtangent(normal, tangent),
					texcoord_0  = poly_mesh.texcoords_0 != nil ? poly_mesh.texcoords_0[v] : [2]f32{0,0},
					texcoord_1  = poly_mesh.texcoords_1 != nil ? poly_mesh.texcoords_1[v] : [2]f32{0,0},
					color_0 	= poly_mesh.colors_0    != nil ? poly_mesh.colors_0[v]    : [4]f32{1,1,1,1},
					color_1 	= poly_mesh.colors_1    != nil ? poly_mesh.colors_1[v]    : [4]f32{1,1,1,1},
				}
			}
		}
	}

	return mesh_data, true;
}

// TODO: avoid stack copyies.
@(private="package")
importer_create_light_asset_from_poly_LightData :: proc(poly_light : ^poly.LightData) -> iria.LightAsset {

	is_directonal : bool = poly_light.type == .DIRECTIONAL;
	
	light_flags := iria.LightAssetFlags{.CastShadows};

	light_asset := iria.LightAsset {
		
		color    = poly_light.color, 
		strength = poly_light.intensity,
		flags 	= light_flags,
		type = importer_get_LightType_from_poly_LightType(poly_light.type),
		
		spot_inner_cone_angle_radians = poly_light.spot_inner_cone_angle_radians,
		spot_outer_cone_angle_radians = poly_light.spot_outer_cone_angle_radians,

		shadowmap_res_0 = is_directonal ? ._4096 : ._2048,
		shadowmap_res_1 = ._2048,
		shadowmap_res_2 = ._2048,

		transform = Transform {
			scale 		= {1.0,1.0,1.0},
			position 	= poly_light.position,
			orientation = poly_light.orientation,
		}
	}

	return light_asset;
}

// TODO: avoid stack copyies.
@(private="package")
importer_create_material_from_poly_MaterialData :: proc(poly_mat : ^poly.MaterialData) -> Material{
	
	mat : Material;
	mat.render_technique = render_technique_create_default_opaque();
	mat.render_technique.alpha_mode = importer_get_AlphaBlendMode_from_poly_AlphaBlendModes(poly_mat.alpha_mode);

	if len(poly_mat.name) >= 0 {
		mat.name = strings.clone(poly_mat.name,context.allocator);
	} else{
		mat.name = strings.clone(string("UnnamedMat"),context.allocator);
	}

	mat.variant = PbrMaterialVariant {
		albedo_color 		= poly_mat.albedo_color,
		emissive_color 		= poly_mat.emissive_color,
		emissive_strength 	= poly_mat.emissive_strength,
		roughness 			= poly_mat.roughness,
		metallic 			= poly_mat.metallic,

		alpha_value 		= poly_mat.alpha_value,
	}

	return mat;
}


@(private="package")
importer_get_AlphaBlendMode_from_poly_AlphaBlendModes :: proc(alpha_blend_mode : poly.AlphaBlendModes) -> AlphaBlendMode {
	
	switch alpha_blend_mode {
		case .Opaque: return AlphaBlendMode.Opaque;
		case .Clip:   return AlphaBlendMode.Clip;
		case .Blend:  return AlphaBlendMode.Blend;
	}

	return AlphaBlendMode.Opaque;
}

@(private="package")
importer_get_LightType_from_poly_LightType :: proc(light_type : poly.LightType) -> LightType {
	
	switch light_type {
		case .DIRECTIONAL: 	return LightType.DIRECTIONAL;
		case .POINT: 		return LightType.POINT;
		case .SPOT: 		return LightType.SPOT;
	}

	return LightType.POINT;
}