package iri

import iria "iriasset"

// @Note:
// In IriEngine all assets have a unique 'AssetID' which is a UUID (v7).
// If you want to load Assets programatically, you first have to optain its AssetID. 
// This can be done in multiple ways:
// 1. You can use 'asset_get_id_from_path(relative/path/to/the/asset.iria)' to obtain it using a known filepath.
// 2. You can hardcode the UUID directly and optionally use 'asset_id_from_uuid_string()' to convert uuid string to the 16 byte AssetID.
// 3. You can use the Alias system. An Alias is just a string of maximally 127 bytes/characters. 
//    The string must be unique for each asset and it is your responsibility to ensure that. A zero string ("") means that an Asset has no Alias.
//    The Alias can be assigned to an asset through the Editor or through 'asset_set_alias()' 
//    Aliases are stored within the asset file and at runtime you can use this string to lookup the AssetID it belongs to using 'asset_get_id_from_alias()'
//
// Once you have an AssetID you can load asset through the asset_io interfaces. For example 'asset_io_load_material_asset()'
// Note that when using asset_io_load_.. for some assets like Models and Materials you need to call asset_io_return_..  once you dont need the asset anymore, otherwise it will stay loaded forever.
// More often though you can use it directly for common functionality
// For example to add a Model to an entity, use 'comp_meshrenderer_add_model_asset(comp : ^MeshRendererComponent, asset_id : AssetID)'
// To load and switch to a new scene/universe, use 'multiverse_jump(asset_id : AssetID, update_callbacks : UniverseUpdateCallbacks, store_active_universe : bool)'

asset_id_from_uuid_string :: proc(uuid_string : string) -> (asset_id : AssetID, ok : bool){
	return iria.asset_id_from_uuid_string(uuid_string);	
}

// Get the AssetID from a path to an asset file, relative to the project folder.
asset_get_id_from_path :: proc(rel_asset_path : string) -> (asset_id : AssetID, exists : bool) {
	return asset_manager_get_asset_id_from_path(engine.asset_manager, rel_asset_path);
}

// Get the AsseID from an Asset alias string
asset_get_id_from_alias :: proc(asset_alias : string, expected_type : iria.AssetType = iria.AssetType.None) -> (asset_id : AssetID, exists : bool) {
	return asset_manager_get_asset_id_from_alias(engine.asset_manager, asset_alias, expected_type);
}

asset_exists :: proc(asset_id : AssetID) -> bool {
	return asset_id in engine.asset_manager.asset_entries;
}

// Read Only! useful for Editor Things.
asset_get_entry :: proc(asset_id : iria.AssetID) -> (entry : AssetEntry, exists : bool) {
	return engine.asset_manager.asset_entries[asset_id];
}

// Set a string alias for an Asset.
asset_set_alias :: proc(asset_id : iria.AssetID, alias : string){
	asset_manager_set_asset_alias(engine.asset_manager, asset_id, alias);
}