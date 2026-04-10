package iri

ENGINE_DEVELOPMENT 				:: #config(ENGINE_DEVELOPMENT, true)
ENGINE_ENABLE_VALIDATION_LAYERS :: #config(ENGINE_FORCE_ENABLE_VALIDATION_LAYERS, true)
ENGINE_ASSERT 					:: #config(ENGINE_ASSERT, true)
ENGINE_SHADER_HOT_RELOADING 	:: #config(ENGINE_SHADER_HOT_RELOADING, true)

engine_panic_alloc_error :: proc(loc := #caller_location){
	panic("Memory Allocation Error",loc = loc);
}

when ENGINE_ASSERT {

	engine_assert :: proc(condition : bool, msg := #caller_expression, loc := #caller_location){
		assert(condition, msg, loc = loc);
	}


} else {

	engine_assert :: proc(condition : bool, msg : string = "", loc := #caller_location){
	}

}