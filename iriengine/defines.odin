package iri

ENGINE_DEVELOPMENT :: true
ENGINE_ASSERT :: true

ENGINE_SHADER_HOT_RELOADING :: true

when ENGINE_ASSERT {

	engine_assert :: proc(condition : bool, msg := #caller_expression, loc := #caller_location){
		assert(condition, msg, loc = loc);
	}
} else {

	engine_assert :: proc(condition : bool, msg : string = "", loc := #caller_location){
	}
}