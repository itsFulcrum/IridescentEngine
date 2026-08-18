package iri

ENGINE_DEVELOPMENT 				:: #config(ENGINE_DEVELOPMENT, true)
ENGINE_ENABLE_VALIDATION_LAYERS :: #config(ENGINE_FORCE_ENABLE_VALIDATION_LAYERS, true)
ENGINE_ASSERT 					:: #config(ENGINE_ASSERT, true)
ENGINE_SHADER_HOT_RELOADING 	:: #config(ENGINE_SHADER_HOT_RELOADING, true)
ENGINE_SPALL_PROFILING 			:: #config(ENGINE_SPALL_PROFILING, false) // https://gravitymoth.com/spall/spall-web.html

engine_panic_alloc_error :: proc(loc := #caller_location){
	panic("Memory Allocation Error",loc = loc);
}

when ENGINE_ASSERT {
	engine_assert :: proc(condition : bool, msg := #caller_expression, loc := #caller_location){
		assert(condition, msg, loc = loc);
	}
} else {
	engine_assert :: proc(condition : bool, msg : string = "", loc := #caller_location){}
}

import "core:prof/spall"

when ENGINE_SPALL_PROFILING {
	spall_ctx : spall.Context;
	spall_backing_buffer : []u8; // threadlocal ??
	@(thread_local) spall_buffer : spall.Buffer;
}

when ENGINE_SPALL_PROFILING {

	@(deferred_in=_iri_procedure_buffer_end)
	@(no_instrumentation)
	IRI_PROFILE_PROCEDURE :: proc "contextless" (loc := #caller_location) {
		spall._buffer_begin(&spall_ctx, &spall_buffer, loc.procedure, location = loc)
		return;
	}

	@(deferred_in=_iri_scoped_buffer_end)
	@(no_instrumentation)
	IRI_PROFILE_SCOPE :: proc "contextless" (name : string, loc := #caller_location) {
		spall._buffer_begin(&spall_ctx, &spall_buffer, name, location = loc);
	}

	@(private)
	@(no_instrumentation)
	_iri_procedure_buffer_end :: proc(_ := #caller_location) {
		spall._buffer_end(&spall_ctx, &spall_buffer)
	}

	@(private)
	@(no_instrumentation)
	_iri_scoped_buffer_end :: proc(_ : string, _ := #caller_location) {
		spall._buffer_end(&spall_ctx, &spall_buffer)
	}

} else {

	IRI_PROFILE_PROCEDURE :: proc(){}
	IRI_PROFILE_SCOPE :: proc(name : string){}
}