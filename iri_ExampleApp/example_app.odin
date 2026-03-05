package app

import "base:runtime"
import "core:log"
import "core:c"

import "core:math/linalg"

import iri "iriengine:iriengine"
import imgui "odinary:dear_imguy"

ExampleApp :: struct {
	player_entity : iri.Entity,
	universe : ^iri.Universe,
	draw_debug_ui_window : bool,
	debug_ui_selected_entity : iri.Entity,
}

app : ExampleApp;

main :: proc() {

	// Create Consol Logger
	Logger_Opts : bit_set[runtime.Logger_Option] : log.Options{log.Options.Level, log.Options.Terminal_Color}
	console_logger := log.create_console_logger(log.Level.Debug)
	console_logger.options = Logger_Opts;
	context.logger = console_logger;
	defer log.destroy_console_logger(console_logger);
	

	ok := init();
	if !ok {
		return;
	}

	// iri.run() will start the main game loop until the programm 
	// is closed by the user, by the OS or by manually calling iri.quit_application()
	iri.run();
	deinit();
}


init :: proc() -> (ok : bool) {
	
	// Provide the path to the engine resources. You can copy this folder anywhere you want.
	engine_resources_path : string = "../engine_resources"

	iri.init("Iri Example App", [2]u32{1014, 720}, engine_resources_path, start_fullscreen = false) or_return;
	
	iri.begin_init_phase();
	defer iri.end_init_phase();

	// register a callback for the frame update
	iri.set_update_callback_proc(frame_update);
	// register a callback for physics update.
	iri.set_physics_update_callback_proc(physics_update);

	// Iri Engine has the concept of a universe (aka. a Scene)
	// by default an empty universe will be created by the engine during the iri.init() call.

	// all entity operations happen inside a universe.
	// we can get a refernce to the currently active universe like this

	universe : ^iri.Universe = iri.get_active_universe();
	assert(universe != nil);

	// lets keep a pointer to the universe ourselves
	app.universe = universe;

	// Create a camera
	{
		// Create a new entity
		cam_ent := iri.entity_create();
		// assing a CameraComponent to the entity
		cam_comp, err := iri.entity_add_component(cam_ent, iri.CameraComponent);
		
		// Get the transform component, every entity has a TransformComponent automatically, so it must not be created manually and cannot be removed.
		cam_transform_comp := iri.entity_get_transform(cam_ent);
		cam_transform_comp.position = {0.0, 10.0, 15.0}
		cam_transform_comp.orientation = linalg.quaternion_angle_axis_f32(linalg.to_radians(f32(-45.0)), iri.TRANSFORM_WORLD_RIGHT);
		cam_comp.fov_deg = 65.0;

		// We must tell the universe that we want to use this entity with this camera component as the active camera used for rendering
		// we can have multiple entities with camera components and switch between them any time.
		iri.universe_set_active_camera_entity(universe, cam_ent);
	}

	// Create a skybox
	{
		// we can create entities directly with a set (bitset) of components
		// we can also explicitly pass the universe where we want to create the entity. 
		// if nil or nothing is passed the active universe will be used by internally calling
		// iri.get_active_universe(); Note that this will fail if no universe is active.
		sky_ent := iri.entity_create({iri.ComponentType.Skybox}, app.universe);

		// Get the component of type 'SkyboxComponent'
		// this proc can return nil if the entity does not exist or the component we ask for is not attached to the entity;
		// you may call iri.entity_is_component_attached(sky_ent) beforehand to verify it.
		sky_comp := iri.entity_get_component(sky_ent, iri.SkyboxComponent);

		sky_comp.color_zenith  = [3]f32{0.2, 0.0, 0.6};
		sky_comp.color_horizon = [3]f32{0.5, 0.9, 0.8};
		sky_comp.color_nadir   = [3]f32{0.0, 0.0, 0.0};

		// sky_comp.color_zenith  = [3]f32{0.0, 0.0, 0.0};
		// sky_comp.color_horizon = [3]f32{1.0, 0.0, 1.0};
		// sky_comp.color_nadir   = [3]f32{0.0, 0.0, 0.0};
		sky_comp.exposure = 0.0;

		// similar to cameras we must also tell the universe that we want this entity with this skybox component to be the active skybox component used for rendering
		// we can have multiple entities with skybox compoents but only one can be active during rendering.
		iri.universe_set_active_skybox_entity(universe, sky_ent);
	}

	// Create a player
	{
		// Create entity with a MeshRendererComponent
		app.player_entity = iri.entity_create({.MeshRenderer});
		
		// First lets create a custom material for the player

		player_mat : iri.Material;
		// Render technique holds information for how the material should be rendered
		// it includes things like alpha blend modes, cull options ect.
		// try using as little variations of render techniques in your materials
		// to minimize the number of graphics pipeline variations and shader permutations needed. 
		player_mat.render_technique = iri.create_default_render_technique();
		// Materials have a union variant
		// there are 3 types of material variants currently
		// PBR, Unlit and Custom. (although custom is not fully implemented yet)
		player_mat.variant = iri.PbrMaterialData {
			albedo_color = {1.0, 0.0, 0.0},
			roughness = 0.2,
			metallic = 0.0,
			emissive_color = {0,0,0},
			emissive_strength = 0.0
		};

		// Materials must be registerd so they can be applied to multiple meshes
		player_mat_id : iri.MaterialID = iri.register_add_material(player_mat);

		// load a singular mesh from file without material information
		mesh_instance, load_ok := iri.asset_loader_load_gltf_file_as_combined_mesh("Assets/Suzanne.gltf", load_first_material = false);
		// assign the material id to the mesh instance.
		mesh_instance.mat_id = player_mat_id;

		// @Note: mesh instances also have a meshID which can be similarly obtained by registering a meshData first.
		// The asset loader function already to this for you. Note that without both valid meshID and valid MaterialID a mesh instance wont be rendererd.

		if load_ok {
			// We can add multiple mesh instances to a MeshRendererComponent	
			mesh_renderer_comp := iri.entity_get_component(app.player_entity, iri.MeshRendererComponent);

			iri.comp_meshrenderer_add_mesh_instance(mesh_renderer_comp, mesh_instance);
		}

		transform := iri.entity_get_transform(app.player_entity);
		
		transform.position = {0.0, 1.5,0.0};
	}

	// Load the example scene from gltf including materials and lights
	{
		asset_scene, load_ok := iri.asset_loader_load_gltf_file_as_asset_scene("Assets/ExampleScene.gltf", load_materials = true, load_lights = true);
		defer if load_ok {
			if asset_scene.lights != nil {
				delete(asset_scene.lights);
			}
			if asset_scene.mesh_instances != nil {
				delete(asset_scene.mesh_instances);
			}
			free(asset_scene);
		}

		if load_ok {

			// Create light entity for every light in the asset scene
			for &asset_light in asset_scene.lights {

				light_ent := iri.entity_create({.Light});

				light_comp := iri.entity_get_component(light_ent, iri.LightComponent);

				iri.comp_light_set_values_from_asset_light(light_comp, asset_light);

				transform_comp := iri.entity_get_transform(light_ent);
				transform_comp.transform = asset_light.transform;
			}

			scene_entity := iri.entity_create({.MeshRenderer});

			if len(asset_scene.mesh_instances) > 0 {

				// add static flag to all mesh instances
				for &instance in asset_scene.mesh_instances {
					instance.flags |= {.IS_STATIC};
				}

				mesh_renderer_comp := iri.entity_get_component(scene_entity, iri.MeshRendererComponent);

				iri.comp_meshrenderer_add_mesh_instances(mesh_renderer_comp, asset_scene.mesh_instances[:]);
			}
		}
	}

	


	// Setup Debug dear imgui rendering
	iri.debug_gui_set_enable(true);
	iri.debug_gui_set_callback_procedure(debug_dear_imgui_callback);
	app.debug_ui_selected_entity.id = -1;
	app.draw_debug_ui_window = true;

	// register a callback proc when ALT+F is pressed
	iri.input_register_keyboard_callback(toggle_debug_ui_window   , iri.Key.F   , {.PRESS}, {.LEFT_ALT} );

	return true;
}

deinit :: proc(){

	// deinitialize the engine.
	iri.deinit();
}


// frame update callback, called each frame
frame_update :: proc(delta_seconds : f32){


	// basic WASD controller

	transform := iri.entity_get_transform(app.player_entity);

	target_dir : [3]f32;

	forward, right := iri.get_forward_right(transform);

	if iri.input_is_key_pressed(iri.Key.W) {
		target_dir += forward
	}
	if iri.input_is_key_pressed(iri.Key.A) {
		target_dir -= right;
	}
	if iri.input_is_key_pressed(iri.Key.S) {
		target_dir -= forward;
	}
	if iri.input_is_key_pressed(iri.Key.D) {
		target_dir += right;
	}

	// Update pos 
	if linalg.length(target_dir) > 0.0 {

		move_speed : f32 = 10;
		speed := move_speed * delta_seconds;
		transform.position += linalg.normalize(target_dir) * speed;
	}
}

// physics update callback, called in fixed timestep intervalls.
physics_update :: proc(){

}


toggle_debug_ui_window :: proc(is_press: bool, is_repeat: bool){
	app.draw_debug_ui_window = !app.draw_debug_ui_window;
}

// callback for debug DearImgui rendering.
debug_dear_imgui_callback :: proc(){
	// dear imgui setup is already done by the engine
	// in this callback you can just do everything you know from imgui. 

	if !app.draw_debug_ui_window {
		return;
	}

	// Iri engine provides some procedure to draw example settings and stuff.
	if imgui.Begin("Debug UI", &app.draw_debug_ui_window) {
		
		if imgui.TreeNode("Render Settings")  {
			iri.debug_gui_draw_render_settings();
			imgui.TreePop();
		}

		if imgui.TreeNode("Universe Settings") {


			iri.debug_gui_draw_universe_settings(app.universe);
			
			imgui.TreePop();
		}


		if imgui.TreeNode("ECS Table") {

			iri.debug_gui_draw_entity_component_table(app.universe);

			imgui.TreePop();
		}

		if imgui.TreeNode("Entity Viewer") {

			ent_id := cast(c.int)app.debug_ui_selected_entity.id; 

			if imgui.DragInt("Entity Selection", &ent_id, 1.0, -1, c.INT32_MAX) {
				app.debug_ui_selected_entity.id = cast(i32)ent_id;
			}

			imgui.Spacing();

			iri.debug_gui_draw_entity_viewer(app.universe, app.debug_ui_selected_entity);
			imgui.TreePop();
		}	
	}
	imgui.End();
}