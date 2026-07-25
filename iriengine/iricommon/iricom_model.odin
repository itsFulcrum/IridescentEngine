package iricom

import geo "odinary:geometry"
import "core:encoding/uuid"


// TODO: this sould go into iricom.
ModelAsset :: struct {

	asset_id : uuid.Identifier,
	asset_alias : string, // can be nothing.
	name : string,

	// Foreach Meshdata there is a corresponding AssetUUID but its allowed to be Invalid meaning no material.
	meshes       : []^MeshData,
	material_ids : []uuid.Identifier,

	aabb      : geo.AABB,
	transform : geo.Transform,
}


free_contents_model_asset :: proc(model : ^ModelAsset){

	if model == nil {
		return;
	}

	if len(model.asset_alias) > 0 {
		delete_string(model.asset_alias)
		model.asset_alias = "";
	}

	if len(model.name) > 0 {
		delete_string(model.name)
		model.name = "";
	}

	for mesh in model.meshes {
		free_mesh_data(mesh);
	}


	delete_slice(model.meshes);
	delete_slice(model.material_ids);
	model.meshes = nil;
	model.material_ids = nil;
}

free_model_asset :: proc(model : ^ModelAsset){

	if model == nil {
		return;
	}

	free_contents_model_asset(model);
	free(model);
}
