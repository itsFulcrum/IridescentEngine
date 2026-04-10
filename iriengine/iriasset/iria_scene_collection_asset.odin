package iria

import "core:log"

import "core:os"
import "core:mem"
import "core:strings"

import reader "binary_reader"
import iricom "../iricommon"


DrawInstanceAsset :: struct {
	flags   	: iricom.DrawInstanceFlags,
	mesh_uuid 	: AssetUUID,
	mat_uuid  	: AssetUUID,
}

SceneCollectionAsset :: struct {
	asset_uuid : AssetUUID,
	draw_inst_assets : []DrawInstanceAsset,
	light_assets     : []AssetUUID,
}

free_scene_collection_asset :: proc(collection : ^SceneCollectionAsset){
	if collection == nil {
		return;
	}

	if collection.light_assets != nil {
		delete(collection.light_assets);
	}

	if collection.draw_inst_assets != nil {
		delete(collection.draw_inst_assets)
	}

	free(collection);
}

// === FILE IO =====
// Scene collection asset is currently an extreamly simple format.
// It basically just stores asset_uuid's to other assets with some draw instance data for meshes.

// We store the IriCommonHeader first as usual, we then store the SceneCollectionAssetHeader_v1
// After that if 'num_draw_inst_assets' is bigger 0 all of those are stored coniguesly.
// After that if 'num_light_assets' > 0 all of the light AssetUUID's are store contiguesly.
// Thats it.

SCENE_COLLECTION_ASSET_CURRENT_VERSION : u32 : 1

SceneCollectionAssetHeader_v1 :: struct #packed {
	num_draw_inst_assets : u32,
	num_light_assets     : u32,
}

asset_scene_collection_read_from_path :: proc(filepath : string) -> (collection : ^SceneCollectionAsset, ok : bool) {

	file, open_err := os.open(filepath);
	if open_err != os.ERROR_NONE {
		return;
	}
	defer os.close(file);

	b_reader := reader.create_file_reader(file);
	return asset_scene_collection_read(&b_reader);
}


asset_scene_collection_read_from_memory :: proc(data : []byte) -> (collection : ^SceneCollectionAsset, ok : bool) {
	b_reader := reader.create_memory_reader(data);
	return asset_scene_collection_read(&b_reader);
}

@(private="file")
asset_scene_collection_read :: proc(b_reader : ^$T) -> (collection : ^SceneCollectionAsset, ok : bool) where T == reader.FileBinaryReader || T == reader.MemBinaryReader {

	common_hdr := reader.consume_copy_type(b_reader, IriAssetCommonHeader) or_return;

	if common_hdr.asset_type != AssetType.SceneCollection {
		return nil, false;
	}

	switch common_hdr.asset_type_version {
		case 1: return asset_scene_collection_read_v1(b_reader, common_hdr);
	}

	// invalid or depricated version
	return nil, false;
}

@(private="file")
asset_scene_collection_read_v1 :: proc(b_reader : ^$T, common_hdr : IriAssetCommonHeader) -> (collection : ^SceneCollectionAsset, ok : bool) where T == reader.FileBinaryReader || T == reader.MemBinaryReader {

	collection = new(SceneCollectionAsset);

	// Cleanup
	defer if !ok{
		free_scene_collection_asset(collection);
		collection = nil;
	}

	collection.asset_uuid = common_hdr.asset_uuid;

	collection_hdr : ^SceneCollectionAssetHeader_v1 = reader.consume_make_type(b_reader, SceneCollectionAssetHeader_v1, context.temp_allocator) or_return;

	num_draw_inst_assets : int = cast(int)collection_hdr.num_draw_inst_assets;
	num_light_assets     : int = cast(int)collection_hdr.num_light_assets;

	if num_draw_inst_assets > 0 {
		collection.draw_inst_assets = reader.consume_make_slice(b_reader, []DrawInstanceAsset, num_draw_inst_assets, context.allocator) or_return;
	}

	if num_light_assets > 0 {
		collection.light_assets = reader.consume_make_slice(b_reader, []AssetUUID, num_light_assets, context.allocator) or_return;
	}

	return collection, true;
}

asset_scene_collection_write_to_file :: proc(filepath : string, collection : ^SceneCollectionAsset, write_flags : WriteFlags) -> (ok : bool) {

	log_errors : bool = .LogErrors in write_flags;

	if collection == nil {
		return false;
	}
	
	assert(collection.asset_uuid != AssetUUID_INVALID);

	file_exists_already := validate_write_filepath(filepath, log_errors) or_return;
	if file_exists_already && .OverwriteExisting not_in write_flags {
		if log_errors do log.errorf("IriAsset: Failed to write asset file, 'OverwriteExisting' flag is not set and file already exists. Path: {}", filepath);
		return false;
	}

	file, open_err := os.open(filepath, flags = os.File_Flags{.Write, .Create, .Trunc});
	if open_err != os.ERROR_NONE {
		if log_errors do log.errorf("IriAsset: Failed to open file for writing: {}. path: {}", filepath);
		return false;
	}

	// Cleanup
	defer os.close(file);
	defer if ! ok {
		try_delete_file(filepath, log_errors);
	}

	// Common Header
	{
		hdr : IriAssetCommonHeader = create_common_header(AssetType.SceneCollection, collection.asset_uuid);
		written_bytes , write_err := os.write_ptr(file, &hdr, size_of(IriAssetCommonHeader));
		is_no_write_error(write_err, filepath, log_errors) or_return;	
	}

	// Asset Header
	asset_hdr : SceneCollectionAssetHeader_v1;
	{
		asset_hdr.num_draw_inst_assets = collection.draw_inst_assets == nil ? 0 : cast(u32)len(collection.draw_inst_assets)
		asset_hdr.num_light_assets     = collection.light_assets     == nil ? 0 : cast(u32)len(collection.light_assets)

		written_bytes , write_err := os.write_ptr(file, &asset_hdr, size_of(SceneCollectionAssetHeader_v1));
		is_no_write_error(write_err, filepath, log_errors) or_return;	
	}

	// write DrawInstanceAssets
	if asset_hdr.num_draw_inst_assets > 0 {
		byte_size : int = len(collection.draw_inst_assets) * size_of(DrawInstanceAsset);
		written_bytes , write_err := os.write_ptr(file, &collection.draw_inst_assets[0], byte_size);
		is_no_write_error(write_err, filepath, log_errors) or_return;
	}
		
	// Write light assets array
	if asset_hdr.num_light_assets > 0 {
		byte_size : int = len(collection.light_assets) * size_of(AssetUUID);
		written_bytes , write_err := os.write_ptr(file, &collection.light_assets[0], byte_size);
		is_no_write_error(write_err, filepath, log_errors) or_return;
	}

	return true;
}