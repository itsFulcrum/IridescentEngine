package iri

import "base:runtime"
import "core:log"
import "core:mem"
import "core:c"
import "core:strings"
import os "core:os/os2"

import sdl "vendor:sdl3"

EngineContext :: struct {

	default_context : runtime.Context,

	window : WindowContext,
	
	// Applications can register 'one' main frame update callback that is called each frame with delta time
	// and one physics update that runns at fixed delta timestep.
	update_callback : proc(f32), 
	physics_update_callback : proc(),
	
	universe : ^Universe, // current/Active universe

	render_context : ^RenderContext,

	mesh_manager : ^MeshManager,
	event_manager : ^EventManager,
	pipeline_manager : ^PipelineManager,
	compute_pipe_manager : ^ComputePipeManager,
	shader_manager : ^ShaderManager,

	in_init_phase: bool,
	running : bool,
	window_is_minimized: bool,

	resources_path : string,

	perf_counters : PerformanceCounters,
}

@(private="package")
engine : ^EngineContext;

@(require_results) 
init :: proc(window_title : cstring, window_size : [2]u32, engine_resources_path : string, start_fullscreen: bool = false) -> bool  {


	engine_assert(engine == nil);
	log.debug("Engine: Init")


	if !os.exists(engine_resources_path) || !os.is_directory(engine_resources_path) {
		log.errorf("Failed to initialize Iri Engine. data path does not point to a valid folder path");
		return false;
	}

	// Initialize engine state
	engine = new(EngineContext);

	engine.default_context = context;

	engine.resources_path = strings.clone(engine_resources_path, context.allocator);


	// Initialize SDL
	success : bool;
		
	sdl.SetLogPriorities(sdl.LogPriority.VERBOSE);
	sdl.SetLogOutputFunction(sdl_log_output, nil);

	
	init_flags := sdl.InitFlags{.VIDEO, .AUDIO, .EVENTS, .GAMEPAD, .JOYSTICK, .HAPTIC }
	success = sdl.Init(init_flags);
	if !success {
		log.errorf("Failed to Initialize SDL3: {}", sdl.GetError());
		return false;
	}

	// create a SDL window
	validation_layers : bool = false;
    when ODIN_DEBUG || ENGINE_DEVELOPMENT {
        validation_layers = true;
    }

	engine.window, success = window_create_context(window_title, window_size, start_fullscreen, validation_layers);
	if !success {

		sdl.Quit();
    	free(engine);
    	engine = nil;

		return false;
	}

	target_swapchain_settings : SwapchainSettings = {
    	color_space = SwapchainColorSpace.Srgb,
    	present_mode = SwapchainPresentMode.VSync,
    }

	success = window_context_set_swapchain_settings(&engine.window, target_swapchain_settings);
	engine_assert(success); // these default settings should be supported everywhere according to SDL Docs

	clock_init();


    // Initialize input system and Callbacks.
    input_system_init();
    event_callback_id := input_register_sdl_event_callback(sdl_event_callback);
    //id := input_register_quit_callback(engine_quit_application);

	window_draw_size := window_context_get_size_pixels(&engine.window);
	window_draw_size_u : [2]u32 = {cast(u32)window_draw_size.x, cast(u32)window_draw_size.y};


	gpu_device := engine.window.gpu_device;

	engine.render_context = new(RenderContext);
	renderer_init(engine.render_context, engine.window.gpu_device, window_draw_size_u);
    
	material_register_init();

	engine.mesh_manager = new(MeshManager);
	mesh_manager_init(engine.mesh_manager);

	engine.event_manager = new(EventManager);
	event_manager_init(engine.event_manager);
    
    engine.shader_manager = new(ShaderManager);
    shader_manager_init(engine.shader_manager);

    engine.pipeline_manager = new(PipelineManager);
    pipe_manager_init(engine.pipeline_manager, gpu_device, engine.shader_manager);

    engine.compute_pipe_manager = new(ComputePipeManager);
    compute_pipe_manager_init(engine.compute_pipe_manager, gpu_device, engine.shader_manager);

    
    // Initialize Debug GUI system
	render_pass_info := renderer_get_render_pass_info(engine.render_context, .DebugGui);
	debug_gui_init(&engine.window, render_pass_info.color_target_format, MSAA.OFF);
    // Make a universe
    engine.universe = new(Universe);
    universe_init(engine.window.gpu_device, engine.universe);


    begin_init_phase();

    return true;
}

run :: proc() {
	
	engine_assert(engine != nil);

	// post init setup
	if engine.in_init_phase {
		
		end_init_phase()
	}


	log.debug("Engine Run");

	engine.running = true;


    // THE LOOP
    for engine.running {

    	delta_time : f64 = clock_tick_frame();
    	true_delta_time : f64 = clock_get_true_delta_time();

    	// TODO: input system some way to stop broadcasting events when ui wants it..
    	// also would be nice to seperate recording and breadcasting of events so we can 
    	// broadcast in the Game Update section..


    	process_user_inputs: bool = true;
    	if debug_gui_is_enabled() && debug_gui_want_capture_input() {
    		process_user_inputs = false;
    	}
    	
    	input_system_set_process_user_input(process_user_inputs);
    	

    	// Input System
    	// poll and broadcast events
    	input_system_update();

    	if engine.window_is_minimized {

    		wait_event_ok := sdl.WaitEvent(nil);
    		if !wait_event_ok {
    			log.errorf("Failed to wait for event?: {}", sdl.GetError());
    		}
    		continue;
    	}

    	// Physics UPDATE
    	for clock_should_advance_fixed_timestep() == true {
    		physics_update();
    		clock_advance_fixed_timestep();
    	}

    	// GAME UPDATE    	
    	frame_update(delta_time);

    	event_manager_update(engine.event_manager, cast(f32)delta_time, cast(f32)true_delta_time);

    	// Process debug ui
    	debug_gui_process_frame();

    	universe_manager_update_universe(engine.window.gpu_device, engine.universe, engine.render_context.current_frame_size);

    	shader_manager_update(engine.shader_manager,engine.window.gpu_device, true_delta_time);

    	// RENDERING
    	renderer_draw_frame(engine.render_context, &engine.window, engine.universe);


    	free_all(context.temp_allocator);
    }
}

deinit :: proc() {
	log.debug("Engine Shutdown")

	

	material_register_shutdown(engine.window.gpu_device);

	//light_system_destroy_context(&engine.light_sys_context, engine.window.gpu_device);


	input_system_shutdown();


	debug_gui_deinit();


	if(engine.universe != nil){

		universe_deinit(engine.window.gpu_device, engine.universe);
		free(engine.universe);
		engine.universe = nil;
	}

	
	mesh_manager_deinit(engine.mesh_manager, engine.window.gpu_device);
	free(engine.mesh_manager);
	engine.mesh_manager = nil;

	pipe_manager_deinit(engine.pipeline_manager, engine.window.gpu_device);
	free(engine.pipeline_manager);
	engine.pipeline_manager = nil;

	compute_pipe_manager_deinit(engine.compute_pipe_manager, engine.window.gpu_device);
	free(engine.compute_pipe_manager);
	engine.compute_pipe_manager = nil;

	shader_manager_deinit(engine.shader_manager, engine.window.gpu_device);
	free(engine.shader_manager);
	engine.shader_manager = nil;
	
	renderer_deinit(engine.render_context, engine.window.gpu_device);
	free(engine.render_context);
	engine.render_context = nil;

	event_manager_deinit(engine.event_manager);
	free(engine.event_manager);


	window_destroy_context(&engine.window);

    sdl.Quit();

    free(engine);
    engine = nil;

    free_all(context.temp_allocator);
}

begin_init_phase :: proc() {
	engine.in_init_phase = true;
}

end_init_phase :: proc() {

	engine.in_init_phase = false;
	
	pipe_manager_rebuild_all_pipelines_for_render_pass_types(engine.pipeline_manager, engine.window.gpu_device, RENDER_PASS_SET_ALL);

	//pipe_manager_update_graphics_pipeline_cache_for_universe(engine.universe);

	// FIXME: not sure if we want to do this here tbh.
	// recreating render targets might make sense but we dont need to recreate the BRDF lut which happens in this function
	// that should only be done once. maybe we need to split this function in two parts ?
	renderer_setup(engine.render_context, engine.window.gpu_device);
}

physics_update :: proc() {

	if engine.physics_update_callback != nil {
		engine.physics_update_callback();
	}
}

frame_update :: proc(delta_time : f64) {

	if engine.update_callback != nil {
		engine.update_callback(cast(f32)delta_time);	
	}
}


sdl_event_callback :: proc(event: ^sdl.Event) {

	#partial switch (event.type) {
		case sdl.EventType.QUIT: quit_application();
		

		case sdl.EventType.WINDOW_LEAVE_FULLSCREEN: //log.debugf("{}", event.type);
		case sdl.EventType.WINDOW_ENTER_FULLSCREEN:	//log.debugf("{}", event.type);

		// //case sdl.EventType.WINDOW_DISPLAY_CHANGED: // e.g. dragging window to another monitor

		// Resized and PIXEL_SIZE_CHANGED are both fired when resizing however if i understand correctly PIXEL_SIZE_CHANGED
		// is also fired when we change the window size through an API call at runtime and RESIZED only if user resizes the window..
		case sdl.EventType.WINDOW_RESIZED:
			//log.debugf("{} to: {}x{}", event.type, event.window.data1,event.window.data2);			
		case sdl.EventType.WINDOW_PIXEL_SIZE_CHANGED:
			// log.debugf("{} to: {}x{}", event.type, event.window.data1,event.window.data2);

		case sdl.EventType.WINDOW_MINIMIZED: engine.window_is_minimized = true;
		case sdl.EventType.WINDOW_RESTORED:	 engine.window_is_minimized = false;
	}
}



set_update_callback_proc :: proc(callback_procedure : proc(f32)){
	engine.update_callback = callback_procedure;
}

set_physics_update_callback_proc :: proc(callback_procedure : proc() ){
	engine.physics_update_callback = callback_procedure;
}

get_current_universe :: proc() -> ^Universe{
	return engine.universe;
}

quit_application :: proc() {
	engine.running = false;
}


get_window_context :: proc() -> ^WindowContext {
	return &engine.window;
}

@(private="package")
get_gpu_device :: proc() -> ^sdl.GPUDevice {
	return engine.window.gpu_device;
}

get_resources_path :: proc() -> string {
	return engine.resources_path;
}

get_performance_counters :: proc() -> ^PerformanceCounters{
	return &engine.perf_counters;
}


@(private="file")
sdl_log_output :: proc "c" (userdata: rawptr, category: sdl.LogCategory, priority : sdl.LogPriority, message : cstring) {

	context = engine.default_context;

	switch (priority) {
		case sdl.LogPriority.TRACE: 	log.debugf("SDL: {}", message);
		case sdl.LogPriority.DEBUG: 	log.debugf("SDL: {}", message);
		case sdl.LogPriority.INFO : 	log.infof ("SDL: {}", message);
		case sdl.LogPriority.WARN : 	log.warnf ("SDL: {}", message);
		case sdl.LogPriority.ERROR: 	log.errorf("SDL: {}", message);
		case sdl.LogPriority.CRITICAL: 	log.fatalf("SDL: {}", message);
		case sdl.LogPriority.VERBOSE: 	log.debugf("SDL: {}", message);
		case sdl.LogPriority.INVALID: 	log.debugf("SDL: {}", message);
	}
}