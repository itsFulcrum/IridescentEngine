package iria


import "core:log"

import "core:os"
import "core:mem"
import "core:strings"

import reader "odinary:readbinary"
import iricom "../iricommon"


// FILE IO
// TODO: better doc.



/*
Material Asset is currently quite simplisticly implemented.
We start the file with the AssetFileCommonHeader, which is imidiatly followed by the 'MaterialAssetHeader_v1'
After that we store RenderTechnique structure directly and without caring about packing alignment. its okey if theres some paddign bytes there.
The 'MaterialAssetHeader_v1' stores the byte size of the material string name utf8 which will come directly after the RenderTechnique
But the name is not required so 'name_str_byte_size' can be 0 if the material does not have a name.
After the name comes directly the material data which currtly is just a raw dump of the material variant structures
(PbrMaterialData & UnlitMaterialData) custom material variant is not implemented yet.
the type of material variant is also stored in the material header.

CommonHeader
AssetAlias128
MatHeader -> includes RenderTechnique
MatNameStr64

Material Type specific data blob



*/

AssetMaterial :: struct {
	asset_id : AssetID,
	asset_alias : string,
	mat : iricom.Material,
}

asset_material_free :: proc(mat_asset : ^AssetMaterial) {

	if len(mat_asset.asset_alias) > 0 {
		delete_string(mat_asset.asset_alias)
	}

	iricom.material_free_contents(&mat_asset.mat);
	free(mat_asset);
}



ASSET_MATERIAL_FILE_CURRENT_VERSION : u32 : 1

AssetMaterialHeader_v1 :: struct #packed {
	mat_type : iricom.MaterialShaderType,
	render_technique : iricom.RenderTechnique,

	_ : [8]u32,
}


asset_material_read_from_path :: proc(filepath : string) -> (material : ^AssetMaterial, ok : bool) {

	file, open_err := os.open(filepath);
	if open_err != os.ERROR_NONE {
		return;
	}
	defer os.close(file);

	b_reader := reader.create_file_reader(file);
	return asset_material_read(&b_reader);
}

asset_material_read_from_memory :: proc(data : []byte) -> (material : ^AssetMaterial, ok : bool) {
	b_reader := reader.create_memory_reader(data);
	return asset_material_read(&b_reader);
}

@(private="file")
asset_material_read :: proc(b_reader : ^$T) -> (material : ^AssetMaterial, ok : bool) where T == reader.FileBinaryReader || T == reader.MemBinaryReader {

	common_hdr := reader.consume_copy_type(b_reader, AssetFileCommonHeader) or_return;

	if common_hdr.asset_type != AssetType.Material {
		return material, false;
	}

	switch common_hdr.asset_type_version {
		case 1: return asset_material_read_v1(b_reader, common_hdr);
	}

	// invalid or depricated version
	return material, false;
}

@(private="file")
asset_material_read_v1 :: proc(b_reader : ^$T, common_hdr : AssetFileCommonHeader) -> (material_asset : ^AssetMaterial, ok : bool) where T == reader.FileBinaryReader || T == reader.MemBinaryReader {


	asset_material : ^AssetMaterial = new(AssetMaterial);

	defer if !ok {
		asset_material_free(asset_material);
	}

	// Read Alias string
	asset_alias128 : AssetFileString128 = reader.consume_copy_type(b_reader, AssetFileString128) or_return;
	asset_alias_str, has_alias := string_clone_from_asset_string128(&asset_alias128, context.allocator);
	if has_alias {
		asset_material.asset_alias = asset_alias_str;
	}


	asset_material.asset_id = common_hdr.asset_id;

	mat_hdr : ^AssetMaterialHeader_v1 = reader.consume_make_type(b_reader, AssetMaterialHeader_v1, context.temp_allocator) or_return;


	// Name String
	mat_name_str64 : AssetFileString64 = reader.consume_copy_type(b_reader, AssetFileString64) or_return;
	mat_name_str, has_name_str := string_clone_from_asset_string64(&mat_name_str64, context.allocator);
	if has_name_str {
		asset_material.mat.name = mat_name_str;
	} else {
		asset_material.mat.name = strings.clone(string("Unnamed"), context.allocator);
	}
	
	asset_material.mat.render_technique = mat_hdr.render_technique; // copy


	switch mat_hdr.mat_type {
		case .None: {
			asset_material.mat.variant = nil;
		}
		case .Pbr: {
			asset_material.mat.variant = iricom.PbrMaterialVariant{};
			reader.consume_mem_copy(b_reader, &asset_material.mat.variant, size_of(iricom.PbrMaterialVariant)) or_return;
		}
		case .Unlit: {
			asset_material.mat.variant = iricom.UnlitMaterialVariant{};
			reader.consume_mem_copy(b_reader, &asset_material.mat.variant, size_of(iricom.UnlitMaterialVariant)) or_return;
		}
		case .Custom: {
			asset_material.mat.variant = iricom.CustomMaterialVariant{};
			unimplemented()
		}
	}

	return asset_material, true;
}

asset_material_write_to_file :: proc(filepath : string, asset_material : ^AssetMaterial, write_flags : AssetWriteFlags) -> (ok : bool) {
	
	log_errors : bool = .LogErrors in write_flags;

	if asset_material == nil {
		return false;
	}

	if asset_material.asset_id == AssetID_NONE {
		if log_errors do log.errorf("IriAsset: Failed to write material asset file, asset has an invalid id: {}", asset_material.asset_id);
		return false;
	}

	file_exists_already := is_valid_write_filepath(filepath, log_errors) or_return;

	if file_exists_already && .OverwriteExisting not_in write_flags {
		if log_errors do log.errorf("IriAsset: Failed to write asset file, 'OverwriteExisting' flag is not set and file already exists. Path: {}", filepath);
		return false;
	}

	file, open_err := os.open(filepath, flags = os.File_Flags{.Write, .Create, .Trunc});

	if open_err != os.ERROR_NONE {
		if log_errors do log.errorf("IriAsset: Failed to open file for writing with error code: {}, path: {}", filepath);
		return false;
	}

	// Cleanup
	defer if !ok {
		try_delete_file(filepath, log_errors)
	}
	defer os.close(file);

	// Common Header And Alias
	write_common_header_and_alias_to_file(file, filepath, AssetType.Material, asset_material.asset_id, asset_material.asset_alias, log_errors) or_return;
	

	mat_type := iricom.material_get_type(&asset_material.mat);
	assert(mat_type != .None);

	// Material Header 
	mat_hdr : AssetMaterialHeader_v1;
	{
		mat_hdr.mat_type = mat_type;	
		mat_hdr.render_technique = asset_material.mat.render_technique;

		written_bytes , write_err := os.write_ptr(file, &mat_hdr, size_of(AssetMaterialHeader_v1));
		check_write_error(write_err, filepath, log_errors) or_return;
	}

	// String Name 64
	{
		mat_name_str64, has_name := string_to_asset_string64(asset_material.mat.name);
		written_bytes , write_err := os.write_ptr(file, &mat_name_str64, size_of(AssetFileString64));
		check_write_error(write_err, filepath, log_errors) or_return;
	}


	// type specific data block
	{
		// @Note:
		// right now we literally just dump the variant
		// but we will likely need something more sophisticated in the future
		switch &variant in asset_material.mat.variant {
			case iricom.PbrMaterialVariant: {

				written_bytes , write_err := os.write_ptr(file, &variant, size_of(iricom.PbrMaterialVariant));
				check_write_error(write_err, filepath, log_errors) or_return;
			}
			case iricom.UnlitMaterialVariant: {
				written_bytes , write_err := os.write_ptr(file, &variant, size_of(iricom.UnlitMaterialVariant));
				check_write_error(write_err, filepath, log_errors) or_return;
			}
			case iricom.CustomMaterialVariant: {
				unimplemented();
			}
		}
	}

	return true;
}