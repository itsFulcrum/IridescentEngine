package iria


import "core:log"

import "core:os"
import "core:mem"
import "core:strings"

import reader "binary_reader"
import iricom "../iricommon"


// typedefs

Material        :: iricom.Material
MaterialVariant :: iricom.MaterialVariant
PbrMaterialVariant   :: iricom.PbrMaterialVariant
UnlitMaterialVariant :: iricom.UnlitMaterialVariant
CustomMaterialVariant :: iricom.CustomMaterialVariant

RenderTechnique :: iricom.RenderTechnique

MaterialAsset :: struct {
	asset_uuid : AssetUUID,
	mat : Material,
}

free_material_asset :: proc(mat_asset : ^MaterialAsset){

	iricom.material_free_contents(&mat_asset.mat);
	free(mat_asset);
}
// FILE IO

/*
Material Asset is currently quite simplisticly implemented.
We start the file with the IriAssetCommonHeader, which is imidiatly followed by the 'MaterialAssetHeader_v1'
After that we store RenderTechnique structure directly and without caring about packing alignment. its okey if theres some paddign bytes there.
The 'MaterialAssetHeader_v1' stores the byte size of the material string name utf8 which will come directly after the RenderTechnique
But the name is not required so 'name_str_byte_size' can be 0 if the material does not have a name.
After the name comes directly the material data which currtly is just a raw dump of the material variant structures
(PbrMaterialData & UnlitMaterialData) custom material variant is not implemented yet.
the type of material variant is also stored in the material header.

*/


MATERIAL_ASSET_CURRENT_VERSION : u32 : 1

MaterialAssetHeader_v1 :: struct #packed {
	mat_type : iricom.MaterialShaderType,
	name_str_byte_size : u32, // can be 0 if there is no name
}


asset_material_read_from_path :: proc(filepath : string) -> (material : ^MaterialAsset, ok : bool) {

	file, open_err := os.open(filepath);
	if open_err != os.ERROR_NONE {
		return;
	}
	defer os.close(file);

	b_reader := reader.create_file_reader(file);
	return asset_material_read(&b_reader);
}

asset_material_read_from_memory :: proc(data : []byte) -> (material : ^MaterialAsset, ok : bool) {
	b_reader := reader.create_memory_reader(data);
	return asset_material_read(&b_reader);
}

@(private="file")
asset_material_read :: proc(b_reader : ^$T) -> (material : ^MaterialAsset, ok : bool) where T == reader.FileBinaryReader || T == reader.MemBinaryReader {

	common_hdr := reader.consume_copy_type(b_reader, IriAssetCommonHeader) or_return;

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
asset_material_read_v1 :: proc(b_reader : ^$T, common_hdr : IriAssetCommonHeader) -> (material_asset : ^MaterialAsset, ok : bool) where T == reader.FileBinaryReader || T == reader.MemBinaryReader {

	material : ^MaterialAsset = new(MaterialAsset);

	defer if !ok {
		free_material_asset(material);
	}

	material.asset_uuid = common_hdr.asset_uuid;

	mat_hdr : ^MaterialAssetHeader_v1 = reader.consume_make_type(b_reader, MaterialAssetHeader_v1, context.temp_allocator) or_return;

	reader.consume_mem_copy(b_reader, &material.mat.render_technique, size_of(RenderTechnique))
	
	if mat_hdr.name_str_byte_size > 0 {
		material.mat.name = reader.consume_make_string(b_reader, cast(int)mat_hdr.name_str_byte_size, context.allocator) or_return;	
	} else {
		material.mat.name = strings.clone(string("Unnamed"), context.allocator);
	}

	switch mat_hdr.mat_type {
		case .None: {
			material.mat.variant = nil;
		}
		case .Pbr: {
			material.mat.variant = PbrMaterialVariant{};
			reader.consume_mem_copy(b_reader, &material.mat.variant, size_of(PbrMaterialVariant)) or_return;
		}
		case .Unlit: {
			material.mat.variant = UnlitMaterialVariant{};
			reader.consume_mem_copy(b_reader, &material.mat.variant, size_of(UnlitMaterialVariant)) or_return;
		}
		case .Custom: {
			material.mat.variant = CustomMaterialVariant{};
			unimplemented()
		}
	}

	return material, true;
}

asset_material_write_to_file :: proc(filepath : string, material : ^MaterialAsset, write_flags : WriteFlags) -> (ok : bool) {
	
	log_errors : bool = .LogErrors in write_flags;

	if material == nil {
		return false;
	}

	if material.asset_uuid == AssetUUID_INVALID {
		if log_errors do log.errorf("IriAsset: Failed to write material asset file, asset has an invalid uuid: {}", material.asset_uuid);
		return false;
	}

	file_exists_already := validate_write_filepath(filepath, log_errors) or_return;

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
	defer os.close(file);
	defer if !ok {
		try_delete_file(filepath, log_errors)
	}

	is_no_write_error :: proc(err : os.Error, filepath : string, log_error : bool) -> bool {
		
		if err != os.ERROR_NONE {
			if log_error do log.errorf("IriAsset: Failed to write into file: Error Code: {}, filepath: {}", err, filepath);
			return false;
		}

		return true;
	}

	// Common Header
	{
		hdr : IriAssetCommonHeader = create_common_header(AssetType.Material, material.asset_uuid);

		written_bytes , write_err := os.write_ptr(file, &hdr, size_of(IriAssetCommonHeader));
		is_no_write_error(write_err, filepath, log_errors) or_return;
				
	}

	mat_type := iricom.material_get_type(&material.mat);
	assert(mat_type != .None);

	// Material Header 
	mat_hdr : MaterialAssetHeader_v1;
	{
		mat_hdr.name_str_byte_size = cast(u32)len(material.mat.name);
		mat_hdr.mat_type = mat_type;
		
		written_bytes , write_err := os.write_ptr(file, &mat_hdr, size_of(MaterialAssetHeader_v1));
		is_no_write_error(write_err, filepath, log_errors) or_return;
	}

	// render technique
	{
		written_bytes , write_err := os.write_ptr(file, &material.mat.render_technique, size_of(RenderTechnique));
		is_no_write_error(write_err, filepath, log_errors) or_return;
	}

	// string name
	{
		if len(material.mat.name) > 0 {

			written_bytes , write_err := os.write_string(file, material.mat.name);
			is_no_write_error(write_err, filepath, log_errors) or_return;

			assert(written_bytes == len(material.mat.name));
		}
	}

	// type specific data block
	{
		// @Note:
		// right now we literally just dump the variant
		// but we will likely need something more sophisticated in the future
		switch &variant in material.mat.variant {
			case PbrMaterialVariant: {

				written_bytes , write_err := os.write_ptr(file, &variant, size_of(PbrMaterialVariant));
				is_no_write_error(write_err, filepath, log_errors) or_return;
			}
			case UnlitMaterialVariant: {
				written_bytes , write_err := os.write_ptr(file, &variant, size_of(UnlitMaterialVariant));
				is_no_write_error(write_err, filepath, log_errors) or_return;
			}
			case CustomMaterialVariant: {
				unimplemented();
			}
		}
	}

	return true;
}