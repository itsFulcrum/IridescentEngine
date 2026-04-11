package iri

import "base:runtime"
import "core:log"
import "core:mem"
import "core:c"
import "core:strings"
import "core:os"
import "core:io"

import sdl "vendor:sdl3"

EngineContext :: struct {
	default_context : runtime.Context,

	
	global_frame_update_callback   : GlobalFrameUpdate_CallbackSignature, 
	global_physics_update_callback : GlobalPhysicsUpdate_CallbackSignature,
	
	universe : ^Universe, // current/Active universe
	universe_update_callbacks : UniverseUpdateCallbacks,
	on_multiverse_jumped_callback   : OnMultiverseJumped_CallbackSignature,

	window : WindowContext,
	render_context : ^RenderContext,

	asset_manager    : ^AssetManager,
	mesh_manager     : ^MeshManager,
	material_manager : ^MaterialManager,
	shader_manager   : ^ShaderManager,
	pipeline_manager : ^PipelineManager,
	compute_pipe_manager : ^ComputePipeManager,
	event_manager    : ^EventManager,
	debug_draw_manager : ^DebugDrawManager,
	collision_manager : ^CollisionManager,

	in_init_phase: bool,
	running : bool,
	window_is_minimized: bool,

	project_path : string,
	project_content_path : string,
	engine_resources_path : string,

	perf_counters : PerformanceCounters,
}

EngineInitInfo :: struct {
	window_title 		: string,
	window_size 		: [2]u32,
	start_fullscreen 	: bool,
	project_path 		: string, 			// relative path (from executable) to the application project folder.
	initialize_empty_project : bool, 		// if 'project_path' does not exist, create a new project folder at this path. // Without a valid project path we can't start the engine.
	enable_gpu_validation_layers : bool, 	// enable vulkan validation layers
}

@(private="package")
engine : ^EngineContext;


@(private="package")
@(require_results)
iri_init :: proc(init_info : EngineInitInfo) -> bool  {

	if engine != nil {
		log.errorf("Iri Engine is already initialized.");
		return false;
	}
	
	project_validate_or_create_project_folder(init_info) or_return;

	// Initialize engine state
	engine = new(EngineContext);
	engine.default_context = context;

	// project path
	{
		abs_path, err1 := os.get_absolute_path(init_info.project_path, context.temp_allocator);
		clean_path, alloc_err1 := os.clean_path(abs_path, context.allocator);
		engine.project_path = clean_path;

		engine.project_content_path, alloc_err1 = os.join_path({engine.project_path, "content"}, context.allocator);
	}

	when ENGINE_DEVELOPMENT {
		
		// during engine development we require that the engine_resources_path is set to the 
		// original 'engine_resources' subfolder provided with this engine because we may modify things there and for users
		// it should only be required during project creation to provide it.
		
		this_file_dir := #directory; // get the directory of this file.

		original_resources_path, alloc_err1 := os.join_path({this_file_dir, "../engine_resources"}, context.temp_allocator);
		original_resources_path, alloc_err1 = os.clean_path(original_resources_path, context.temp_allocator);

		original_res_path_ok := project_validate_engine_resources_path(original_resources_path);
		if !original_res_path_ok {
			log.errorf("During engine development (ENGINE_DEVELOPMENT=true) the 'engine_resources' path in EngineInitInfo must be valid and point to the original 'engine_resources' folder provided with the Engine.");
			free(engine);
			return false;
		}

		abs_path, err1 := os.get_absolute_path(original_resources_path, context.allocator);
		engine.engine_resources_path = abs_path;

	} else {
		
		// use engine resources path of project which was validated at the call above
		res_path, alloc_err1 := os.join_path({engine.project_path, "engine_resources"}, context.allocator);
		engine.engine_resources_path = res_path;
	}

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
	validation_layers : bool = init_info.enable_gpu_validation_layers;
	when ENGINE_ENABLE_VALIDATION_LAYERS {
		validation_layers = true; // force true
	}


	engine.window, success = window_create_context(init_info.window_title, init_info.window_size, init_info.start_fullscreen, validation_layers);
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

	window_draw_size := window_context_get_size_pixels(&engine.window);
	window_draw_size_u : [2]u32 = {cast(u32)window_draw_size.x, cast(u32)window_draw_size.y};

	engine.asset_manager = new(AssetManager);
	asset_manager_init(engine.asset_manager);
	asset_manager_rescan_entire_project();

	gpu_device := engine.window.gpu_device;

	engine.render_context = new(RenderContext);
	renderer_init(engine.render_context, engine.window.gpu_device, window_draw_size_u);
    
    engine.material_manager = new(MaterialManager)
	material_manager_init(engine.material_manager);

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

    engine.debug_draw_manager = new(DebugDrawManager);
    debug_draw_manager_init(engine.debug_draw_manager);

    engine.collision_manager = new(CollisionManager);
    collision_manager_init(engine.collision_manager);

    // Initialize ImidiateMode DebugGUI system. (Dear-ImGui )
	render_pass_info := renderer_get_render_pass_info(engine.render_context, .DebugGui);
	debug_gui_init(&engine.window, render_pass_info.color_target_format, MSAA.OFF);
    

    engine.universe = nil;

    begin_init_phase();

    return true;
}

@(private="package")
iri_run :: proc() {
	
	engine_assert(engine != nil);

	// post init setup
	if engine.in_init_phase {
		
		end_init_phase()
	}


	log.debug("Engine Run");

	engine.running = true;

    // THE LOOP
    for engine.running {
    	fixed_timestep : f64 = clock_get_physics_timestep();
    	delta_time : f64 = clock_tick_frame();
    	true_delta_time : f64 = clock_get_true_delta_time();

    	// TODO: input system some way to stop broadcasting events when ui wants it..
    	// also would be nice to seperate recording and broadcasting of events so we can 
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
    	for clock_should_advance_fixed_timestep() {
    		if engine.universe != nil {
				// @Note: this should run before physics any integration. (previous_state = current state)
				physics_universe_update_previous_transform_state(engine.collision_manager, engine.universe, cast(f32)fixed_timestep);
			}	

    		iri_global_physics_update(fixed_timestep);
    		
    		if engine.universe != nil {
    			ecs_process_pending_destroy(&engine.universe.ecs)
    		}


    		clock_advance_fixed_timestep();
    	}

    	fixed_alpha_interpolator : f64 = clock_calc_fixed_alpha_interpolator();

    	event_manager_update(engine.event_manager, cast(f32)delta_time, cast(f32)true_delta_time);
    	
    	// GAME UPDATE    	
    	iri_global_frame_update(delta_time);


    	// Process debug ui
    	debug_gui_process_frame();

    	shader_manager_update(engine.shader_manager, engine.window.gpu_device, true_delta_time);
    	material_manager_update(engine.material_manager, engine.window.gpu_device);
    	universe_manager_update_universe(engine.window.gpu_device, engine.universe, engine.render_context.current_frame_size, cast(f32)fixed_alpha_interpolator);
    	

    	// RENDERING
    	if engine.universe != nil {
    		debug_draw_manager_push_universe_components(engine.debug_draw_manager, engine.universe);
    		
    		renderer_draw_frame(engine.render_context, &engine.window, engine.universe);
    	
    		ecs_process_end_of_frame(&engine.universe.ecs)
    	} else {
    		renderer_draw_frame_UI_only(engine.render_context, &engine.window);
    	}
    	

    	debug_draw_manager_clear_commands(engine.debug_draw_manager);

    	
    	free_all(context.temp_allocator);
    }
}


@(private="package")
iri_deinit :: proc() {
	
	input_system_shutdown();

	debug_gui_deinit();

	if engine.universe != nil {
		universe_deinit(engine.universe);
		free(engine.universe);
		engine.universe = nil;
	}
	
	gpu_device := engine.window.gpu_device;

	pipe_manager_deinit(engine.pipeline_manager, gpu_device);
	free(engine.pipeline_manager);
	engine.pipeline_manager = nil;

	compute_pipe_manager_deinit(engine.compute_pipe_manager, gpu_device);
	free(engine.compute_pipe_manager);
	engine.compute_pipe_manager = nil;

	shader_manager_deinit(engine.shader_manager, gpu_device);
	free(engine.shader_manager);
	engine.shader_manager = nil;
	
	collision_manager_deinit(engine.collision_manager);
	free(engine.collision_manager);
	engine.collision_manager = nil;	

    debug_draw_manager_deinit(engine.debug_draw_manager);
    free(engine.debug_draw_manager);
    engine.debug_draw_manager = nil;

	renderer_deinit(engine.render_context, gpu_device);
	free(engine.render_context);
	engine.render_context = nil;
	
	mesh_manager_deinit(engine.mesh_manager, gpu_device);
	free(engine.mesh_manager);
	engine.mesh_manager = nil;
	
	material_manager_deinit(engine.material_manager, gpu_device);
	free(engine.material_manager);
	engine.material_manager = nil;

	event_manager_deinit(engine.event_manager);
	free(engine.event_manager);

	asset_manager_deinit(engine.asset_manager);
	free(engine.asset_manager);
	engine.asset_manager = nil;

	delete_string(engine.project_path);
	delete_string(engine.project_content_path);
	delete_string(engine.engine_resources_path);

	window_destroy_context(&engine.window);

    sdl.Quit();

    free(engine);
    engine = nil;

    free_all(context.temp_allocator);
}


@(private="package")
iri_begin_init_phase :: proc() {
	engine.in_init_phase = true;
}

@(private="package")
iri_end_init_phase :: proc() {

	wait_ok := sdl.WaitForGPUIdle(engine.window.gpu_device);


	free_all(context.temp_allocator);
	engine.in_init_phase = false;
	pipe_manager_rebuild_all_pipelines_for_render_pass_types(engine.pipeline_manager, engine.window.gpu_device, RENDER_PASS_SET_ALL);
	//log.warnf("ending init phase")
	
	wait_ok = sdl.WaitForGPUIdle(engine.window.gpu_device);

	//pipe_manager_update_graphics_pipeline_cache_for_universe(engine.universe);

	// FIXME: not sure if we want to do this here tbh.
	// recreating render targets might make sense but we dont need to recreate the BRDF lut which happens in this function
	// that should only be done once. maybe we need to split this function in two parts ?
	renderer_setup(engine.render_context, engine.window.gpu_device);
	
	wait_ok = sdl.WaitForGPUIdle(engine.window.gpu_device);
}

@(private="file")
iri_global_physics_update :: proc(timestep : f64) {

	ts : f32 = cast(f32)timestep;

	if engine.global_physics_update_callback != nil {
		engine.global_physics_update_callback(ts);
	}

	if engine.universe != nil {

		if engine.universe_update_callbacks.physics_update != nil {
			engine.universe_update_callbacks.physics_update(engine.universe, ts)
		}

		if engine.universe_update_callbacks.physics_update_late != nil {
			engine.universe_update_callbacks.physics_update_late(engine.universe, ts)
		}
		
		physics_universe_update(engine.collision_manager, engine.universe, ts);
	}
}

@(private="file")
iri_global_frame_update :: proc(delta_time : f64) {
	
	dt : f32 = cast(f32)delta_time;

	if engine.global_frame_update_callback != nil {
		engine.global_frame_update_callback(dt);	
	}

	if engine.universe != nil {

		if engine.universe_update_callbacks.frame_update != nil {
			engine.universe_update_callbacks.frame_update(engine.universe, dt)
		}

		if engine.universe_update_callbacks.frame_update_late != nil {
			engine.universe_update_callbacks.frame_update_late(engine.universe, dt)
		}
	}
}




@(private="file")
sdl_event_callback :: proc(event: ^sdl.Event) {

	#partial switch event.type {
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

@(private="package")
get_gpu_device :: proc() -> ^sdl.GPUDevice {
	return engine.window.gpu_device;
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