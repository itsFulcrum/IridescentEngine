package iri

import "core:math/linalg"

TransformComponent :: struct {
	using common : ComponentCommon,

	using transform : Transform,
}

@(private="package")
comp_transform_init :: proc (comp: ^TransformComponent){
	if(comp == nil){
		return;
	}

	#force_inline comp_transform_set_defaults(comp);
}

@(private="package")
comp_transform_deinit :: proc(comp: ^TransformComponent){
	// if(comp == nil){
	// 	return;
	// }
}


comp_transform_set_defaults :: proc(t: ^TransformComponent){
	if(t == nil){
		return;
	}

	t.transform = transform_create_identity();
}

// =====================================================================
// Component procedures
// =====================================================================
