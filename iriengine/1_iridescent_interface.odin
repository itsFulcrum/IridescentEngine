package iri

import "core:log"

init :: proc(init_info : EngineInitInfo) -> bool {
	return iri_init(init_info);
}

begin_init_phase :: proc() {
	iri_begin_init_phase();
}

end_init_phase :: proc() {
	iri_end_init_phase();
}

run :: proc(){
	iri_run();
}

deinit :: proc(){
	iri_deinit();
}


get_performance_counters :: proc() -> ^PerformanceCounters{
	return &engine.perf_counters;
}

get_frame_size :: proc() -> [2]u32 {
	return engine.render_context.current_frame_size
}

get_swapchain_size :: proc() -> [2]u32 {
	return engine.render_context.current_swapchain_size
}

quit_application :: proc(store_active_universe : bool = false) {

	engine.running = false;

	if engine.universe == nil {
		return;
	}

	if engine.universe_update_callbacks.deinit != nil {
		engine.universe_update_callbacks.deinit(engine.universe);
	}
	if engine.universe_update_callbacks.deinit_late != nil {
		engine.universe_update_callbacks.deinit_late(engine.universe);
	}

	// - store active universe state
	if store_active_universe {
		store_ok := asset_io_store_universe(engine.universe);
		if !store_ok {
			log.warnf("Failed to store active unvierse state, Name: {}, Tag: {}", engine.universe.name, engine.universe.tag);
		}
	}

	// - free active universe mem
	universe_deinit(engine.universe);
	free(engine.universe);
	engine.universe = nil;
}

get_window_context :: proc() -> ^WindowContext {
	return &engine.window;
}


// Prefer not to use this and instead try to keep universe calls within universe update callbacks.
// returns nill when no active universe is set.
get_active_universe :: proc() -> ^Universe {
	return engine.universe;
}


// ======= Callbacks =========

OnMultiverseJumped_CallbackSignature :: #type proc(new_universe : ^Universe, name : string, tag : u32);

GlobalFrameUpdate_CallbackSignature   :: #type proc(delta_time : f32)
GlobalPhysicsUpdate_CallbackSignature :: #type proc(timestep   : f32)

UniverseInit_CallbackSignature   :: #type proc(universe : ^Universe);
UniverseDeinit_CallbackSignature :: #type proc(universe : ^Universe);

UniverseFrameUpdate_CallbackSignature   :: #type proc(universe : ^Universe, delta_time : f32);
UniversePhysicsUpdate_CallbackSignature :: #type proc(universe : ^Universe, timestep : f32);

UniverseDebugGuiDraw_CallbackSignature :: #type proc(universe : ^Universe);

UniverseUpdateCallbacks :: struct{
	init 	  : UniverseInit_CallbackSignature,
	init_late : UniverseInit_CallbackSignature,

	frame_update      : UniverseFrameUpdate_CallbackSignature,
	frame_update_late : UniverseFrameUpdate_CallbackSignature,

	physics_update 		: UniversePhysicsUpdate_CallbackSignature,
	physics_update_late : UniversePhysicsUpdate_CallbackSignature,

	deinit      : UniverseDeinit_CallbackSignature,
	deinit_late : UniverseDeinit_CallbackSignature,

	imgui_debug_draw : UniverseDebugGuiDraw_CallbackSignature,
}

set_global_frame_update_callback_proc :: proc(callback_procedure : GlobalFrameUpdate_CallbackSignature){
	engine.global_frame_update_callback = callback_procedure;
}

set_global_physics_update_callback_proc :: proc(callback_procedure : GlobalPhysicsUpdate_CallbackSignature){
	engine.global_physics_update_callback = callback_procedure;
}

set_on_multiverse_jumped_callback_proc :: proc(callback_procedure : OnMultiverseJumped_CallbackSignature){
	engine.on_multiverse_jumped_callback = callback_procedure;
}

overwrite_universe_update_callback_procs :: proc(callbacks : UniverseUpdateCallbacks){
	engine.universe_update_callbacks = callbacks;
}


// Switch to a differant unvierse. Use 'asset_manager_find_universe_asset_by_tag_and_name()' to
// obtain the asset uuid and provide new update callback procedures.
multiverse_jump :: proc(asset_uuid : AssetUUID, update_callbacks : UniverseUpdateCallbacks, store_active_universe : bool) {
	
	asset_manager := engine.asset_manager;

	curr_universe := engine.universe;

	// maybe we do want to allow hard reset of current unverse?
	if curr_universe != nil {
		if curr_universe.asset_uuid == asset_uuid {
			return;
		}
	}

	// - validate that we can load the universe at uuid
	// - load and init new universe
	new_universe, load_ok := asset_io_load_universe_asset(asset_uuid);
	if !load_ok {
		return
	}
	
	// - run active universe deinit
	if curr_universe != nil {
		if engine.universe_update_callbacks.deinit != nil {
			engine.universe_update_callbacks.deinit(curr_universe);
		}
		if engine.universe_update_callbacks.deinit_late != nil {
			engine.universe_update_callbacks.deinit_late(curr_universe);
		}

		// - store active universe state
		if store_active_universe {
			store_ok := asset_io_store_universe(curr_universe);
			if !store_ok {
				log.warnf("Failed to store active unvierse state, Name: {}, Tag: {}", curr_universe.name, curr_universe.tag);
			}
		}

		// - free active universe mem
		universe_deinit(curr_universe);
		free(curr_universe);
		engine.universe = nil;
	}

	collision_manager_reset(engine.collision_manager);

	// - switch universe pointer
	engine.universe = new_universe;

	// - switch update callbacks
	engine.universe_update_callbacks = update_callbacks;

	// - run on universe switch callback 
	// This must come after setting new update callbacks
	// if user want to use the on switch callback to overwrite the update callbacks
	if engine.on_multiverse_jumped_callback != nil {
		engine.on_multiverse_jumped_callback(engine.universe, engine.universe.name, engine.universe.tag);
	}

	// - run new universe init
	if engine.universe_update_callbacks.init != nil {
		engine.universe_update_callbacks.init(engine.universe);
	}
	if engine.universe_update_callbacks.init_late != nil {
		engine.universe_update_callbacks.init_late(engine.universe);
	}
}