package iri

import "core:fmt"
import "core:strings"
import "core:math"
import "core:math/linalg"

import sdl "vendor:sdl3"

import imgui "odinary:dear_imguy"
import imgui_sdl3 "odinary:dear_imguy/imgui_impl_sdl3"
import imgui_sdl3gpu "odinary:dear_imguy/imgui_impl_sdlgpu3"


DebugGUI_CallbackSignature :: #type proc();

@(private="file")
DebugGuiContext :: struct{
	is_enabled : bool,
	enable_next_frame : bool, // we dont want users to enable it mid frame 


	imgui_ctx: ^imgui.Context,
	imgui_io: ^imgui.IO,
	imgui_curr_draw_data: ^imgui.DrawData,

	debug_gui_callback: DebugGUI_CallbackSignature,

	show_demo_window: bool,

	sdl_event_callback_id : i32,

	tranform_euler_order : linalg.Euler_Angle_Order,
}

@(private="file")
debug_gui_ctx: DebugGuiContext;


@(private="package")
debug_gui_init :: proc(window: ^WindowContext, render_target_format: RenderTargetFormat, msaa: MSAA) {


	debug_gui_ctx.is_enabled = false;
	debug_gui_ctx.enable_next_frame = false;
	debug_gui_ctx.show_demo_window = false;
	debug_gui_ctx.debug_gui_callback = nil;


	debug_gui_ctx.tranform_euler_order = linalg.Euler_Angle_Order.XZY;


	debug_gui_ctx.imgui_ctx = imgui.CreateContext();
	engine_assert(debug_gui_ctx.imgui_ctx != nil);

	imgui.StyleColorsDark();
	setup_imgui_style();


	debug_gui_ctx.imgui_io = imgui.GetIO();

	// TODO: Do style and font setup here.


	// Init backend

	imgui_sdl3.InitForSDLGPU(window.handle);
	init_info := imgui_sdl3gpu.InitInfo{
		Device = window.gpu_device,
		ColorTargetFormat = get_sdl_GPUTextureFormat_from_RenderTargetFormat(render_target_format),
		MSAASamples = get_sdl_GPUSampleCount_from_MSAA(msaa),
		SwapchainComposition = get_sdl_GPUSwapchainComposition_from_SwapchainColorSpace(window.swapchain_settings.color_space),
		PresentMode = get_sdl_GPUPresentMode_from_SwapchainPresentMode(window.swapchain_settings.present_mode),
	}
	imgui_sdl3gpu.Init(&init_info);

	debug_gui_ctx.sdl_event_callback_id = input_register_sdl_event_callback(debug_gui_process_sdl_event);
}


@(private="package")
debug_gui_deinit :: proc() {

	imgui_sdl3.Shutdown();
	imgui_sdl3gpu.Shutdown();
	imgui.DestroyContext(debug_gui_ctx.imgui_ctx);
	debug_gui_ctx.imgui_ctx = nil;
	debug_gui_ctx.imgui_curr_draw_data = nil;

	debug_gui_ctx.debug_gui_callback = nil;

	input_unregister_sdl_event_callback(&debug_gui_ctx.sdl_event_callback_id);
}

@(private="package")
debug_gui_want_capture_input :: proc() -> bool {
	return debug_gui_ctx.imgui_io.WantCaptureMouse || debug_gui_ctx.imgui_io.WantCaptureKeyboard; 
}

@(private="file")
debug_gui_process_sdl_event :: proc(event: ^sdl.Event){
	imgui_sdl3.ProcessEvent(event);
}

@(private="package")
debug_gui_process_frame :: proc(){

	if(debug_gui_ctx.enable_next_frame){
		debug_gui_ctx.is_enabled = true;
		debug_gui_ctx.enable_next_frame = false;
	}


	if(!debug_gui_ctx.is_enabled){
		return;
	}


	imgui_sdl3gpu.NewFrame();
	imgui_sdl3.NewFrame();
	imgui.NewFrame();


	// All dear-imgui ui processing must happen in here
	{
		if(debug_gui_ctx.show_demo_window){
			imgui.ShowDemoWindow(&debug_gui_ctx.show_demo_window);
		}

		if(debug_gui_ctx.debug_gui_callback != nil){
			debug_gui_ctx.debug_gui_callback();
		}

	}

	// This finishes the frame
	imgui.Render();
}

@(private="package")
debug_gui_prepare_and_upload_draw_data :: proc(cmd_buf: ^sdl.GPUCommandBuffer){

	if(!debug_gui_ctx.is_enabled){
		return;
	}

	debug_gui_ctx.imgui_curr_draw_data = imgui.GetDrawData();
	engine_assert(debug_gui_ctx.imgui_curr_draw_data != nil);
	
	imgui_sdl3gpu.PrepareDrawData(debug_gui_ctx.imgui_curr_draw_data, cmd_buf);
}


@(private="package")
debug_gui_draw_frame :: proc(cmd_buf: ^sdl.GPUCommandBuffer, render_pass: ^sdl.GPURenderPass, pipeline: ^sdl.GPUGraphicsPipeline = nil) {

	imgui_sdl3gpu.RenderDrawData(debug_gui_ctx.imgui_curr_draw_data, cmd_buf, render_pass, pipeline);
	debug_gui_ctx.imgui_curr_draw_data = nil;
}

debug_gui_set_enable :: proc(enable: bool) {

	if(enable == debug_gui_ctx.is_enabled){
		return;
	}

	if(enable == true){
		debug_gui_ctx.enable_next_frame = true;
		return;
	}

	debug_gui_ctx.is_enabled = false;
}

debug_gui_is_enabled :: proc() -> bool {
	return debug_gui_ctx.is_enabled;
}

debug_gui_set_callback_procedure :: proc(callback: DebugGUI_CallbackSignature){

	debug_gui_ctx.debug_gui_callback = callback;
}


debug_gui_toggle_imgui_debug_window :: proc(enable: bool){
	debug_gui_ctx.show_demo_window = enable;
}




@(private="file")
setup_imgui_style :: proc(){

	// =================================================
	// Setup Font
	// =================================================
	
	// font_atlas := guistate.io.fonts;
	
	// fonts_path := "Assets/Fonts/RobotoRegular.ttf" 

	// // @note: soo to do custom fonts we apparently have to build the atlas then we need to get the image data and upload it as a texture to the gpu manually
	// // 		  then we tell imgui the texture id it needs to use to access the atlas texture

	// guistate.roboto_font = imgui.font_atlas_add_font_from_file_ttf(font_atlas,fonts_path,20);

	// build_atlas_success := imgui.ImFontAtlas_Build(font_atlas);
	// if(!build_atlas_success){
	// 	log.error("Font Atlas not build");
	// }

	// // here we get the pixel data from imgui's font atlas
	// font_tex_pixel_data: ^u8; // no need to free, owned by the font atlas
	// font_tex_width, font_tex_height, font_tex_bytes_per_pixel: i32;

	// imgui.font_atlas_get_tex_data_as_rgba32(font_atlas, &font_tex_pixel_data, &font_tex_width, &font_tex_height, &font_tex_bytes_per_pixel );

	// if (font_tex_pixel_data == nil || font_tex_width <= 0 || font_tex_height <= 0) {
	// 	log.error("Failed to get font atlas data");
	// }
	// else{

	// 	// if the data is ok we create a gl texture and upload it to the gpu.
	// 	gl.GenTextures(1, &guistate.roboto_font_atlas_gl_id);
	// 	gl.BindTexture(gl.TEXTURE_2D, guistate.roboto_font_atlas_gl_id);
	// 	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, font_tex_width, font_tex_height, 0, gl.RGBA, gl.UNSIGNED_BYTE, font_tex_pixel_data);
	// 	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
	// 	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);

	// 	// here we tell imgui the texture id
	// 	// weird casting stuff bc imgui has defined id as a void*
	// 	tex_id := transmute(imgui.Texture_ID) (cast(uintptr) guistate.roboto_font_atlas_gl_id);
	// 	imgui.font_atlas_set_tex_id(font_atlas, tex_id );		

	// 	// now we set the font as default font
	// 	guistate.io.font_default = guistate.roboto_font;
	// }

	// =================================================
	// Setup Style
	// =================================================

	style : ^imgui.Style = imgui.GetStyle();

	style.FrameRounding = 2;
	style.WindowRounding = 2;
	style.GrabRounding = 2;
	//style.docking_separator_size = 2;
	//style.separator_text_padding.x = 6;

	style.Colors[imgui.Col.Text]				= imgui.Vec4{0.68, 0.68, 0.68, 1.00};
	style.Colors[imgui.Col.WindowBg]			= imgui.Vec4{0.11, 0.11, 0.11, 0.95};
	style.Colors[imgui.Col.PopupBg]				= imgui.Vec4{0.15, 0.15, 0.15, 1.00};
	style.Colors[imgui.Col.Border]				= imgui.Vec4{0.20, 0.20, 0.19, 1.00};
	style.Colors[imgui.Col.FrameBg]				= imgui.Vec4{0.17, 0.19, 0.19, 1.00};
	style.Colors[imgui.Col.FrameBgHovered]		= imgui.Vec4{0.23, 0.27, 0.28, 1.00};
	style.Colors[imgui.Col.FrameBgActive]		= imgui.Vec4{0.23, 0.33, 0.36, 1.00};
	style.Colors[imgui.Col.TitleBg]				= imgui.Vec4{0.10, 0.12, 0.12, 1.00};
	style.Colors[imgui.Col.TitleBgActive]		= imgui.Vec4{0.25, 0.13, 0.11, 1.00};
	style.Colors[imgui.Col.MenuBarBg]			= imgui.Vec4{0.19, 0.21, 0.22, 1.00};
	style.Colors[imgui.Col.ScrollbarBg]			= imgui.Vec4{0.11, 0.11, 0.11, 0.00};
	style.Colors[imgui.Col.CheckMark]			= imgui.Vec4{0.61, 0.54, 0.49, 1.00};
	style.Colors[imgui.Col.SliderGrab]			= imgui.Vec4{0.61, 0.54, 0.49, 1.00};
	style.Colors[imgui.Col.SliderGrabActive]	= imgui.Vec4{0.35, 0.19, 0.16, 1.00};
	style.Colors[imgui.Col.Button]				= imgui.Vec4{0.18, 0.21, 0.25, 1.00};
	style.Colors[imgui.Col.ButtonHovered]		= imgui.Vec4{0.31, 0.38, 0.47, 1.00};
	style.Colors[imgui.Col.ButtonActive]		= imgui.Vec4{0.36, 0.47, 0.60, 1.00};
	style.Colors[imgui.Col.Header]				= imgui.Vec4{0.18, 0.21, 0.25, 1.00};
	style.Colors[imgui.Col.HeaderHovered]		= imgui.Vec4{0.31, 0.38, 0.47, 1.00};
	style.Colors[imgui.Col.HeaderActive]		= imgui.Vec4{0.37, 0.47, 0.60, 1.00};
	style.Colors[imgui.Col.Separator]			= imgui.Vec4{0.24, 0.25, 0.25, 1.00};
	style.Colors[imgui.Col.ResizeGrip]			= imgui.Vec4{0.33, 0.33, 0.33, 1.00};
	style.Colors[imgui.Col.ResizeGripHovered]	= imgui.Vec4{0.40, 0.26, 0.24, 1.00};
	style.Colors[imgui.Col.ResizeGripActive]	= imgui.Vec4{0.42, 0.13, 0.10, 1.00};
	style.Colors[imgui.Col.Tab]					= imgui.Vec4{0.37, 0.34, 0.32, 1.00};
	style.Colors[imgui.Col.TabHovered]			= imgui.Vec4{0.51, 0.29, 0.20, 1.00};
	style.Colors[imgui.Col.TabActive]			= imgui.Vec4{0.36, 0.13, 0.11, 1.00};
	style.Colors[imgui.Col.TabUnfocused]		= imgui.Vec4{0.24, 0.24, 0.23, 1.00};
	style.Colors[imgui.Col.TabUnfocusedActive] 	= imgui.Vec4{0.30, 0.14, 0.12, 1.00};
	//style.Colors[imgui.Col.DockingPreview]		= imgui.Vec4{0.44, 0.31, 0.27, 0.70};
	//style.Colors[imgui.Col.DockingEmptyBg]		= imgui.Vec4{0.08, 0.08, 0.08, 1.00};
	style.Colors[imgui.Col.NavHighlight]		= imgui.Vec4{0.77, 0.30, 0.09, 1.00};
	style.Colors[imgui.Col.DragDropTarget]		= imgui.Vec4{0.88, 0.63, 0.08, 1.00};

}


// Debug Windows To Draw 
debug_gui_draw_scene_info :: proc(){

	// num loaded meshes

	num_loaded_meshes : u32 = mesh_manager_get_num_loaded_meshes(engine.mesh_manager);

	imgui.Text("Loaded Meshes: %i", num_loaded_meshes);


	// num loaded materials
	num_loaded_materials := material_register_get_num_loaded_material();
	imgui.Text("Loaded Materials: %i", num_loaded_materials);
}

debug_gui_draw_render_settings :: proc(){


	window := get_window_context();

	ren_config := get_render_config();

	is_fullscreen := window.in_fullscreen_mode;
	if imgui.Checkbox("Enable Fullscreen", &is_fullscreen) {
		window_set_fullscreen(is_fullscreen);
	}
	imgui.SetItemTooltip("call: window_set_fullscreen(fullscreen: bool) -> bool ");

	// Render Resolution
	{

		current_resolution := fmt.aprintf("{}", ren_config.render_resolution, allocator = context.temp_allocator);

		imgui.SetNextItemWidth(150);

		if imgui.BeginCombo("Render Resolution", strings.clone_to_cstring(current_resolution, context.temp_allocator)){
			for resolution_mode in RenderResolution {

				resolution_mode_str := fmt.aprintf("{}", resolution_mode, allocator = context.temp_allocator);

				if imgui.Selectable(strings.clone_to_cstring(resolution_mode_str, context.temp_allocator)) {

					set_render_resolution(resolution_mode);
					break;
				}
			}

			imgui.EndCombo();
		}

		imgui.SetItemTooltip("call: set_render_resolution(render_resolution: RenderResolution)");
	}

	// Present Modes
	{
		present_mode_str := fmt.aprintf("{}", window.swapchain_settings.present_mode, allocator = context.temp_allocator);

		imgui.SetNextItemWidth(150);
		if imgui.BeginCombo("Present Mode", strings.clone_to_cstring(present_mode_str, context.temp_allocator)){
			for mode in SwapchainPresentMode {

				mode_str := fmt.aprintf("{}", mode, allocator = context.temp_allocator);

				if imgui.Selectable(strings.clone_to_cstring(mode_str, context.temp_allocator)) {

					window_set_present_mode(mode);
					break;
				}
			}

			imgui.EndCombo();
		}

		imgui.SetItemTooltip("call: window_set_present_mode(target_mode: SwapchainPresentMode) -> bool ");
	}

	// Swapchain Color Space
	{
		curr_space_str := fmt.aprintf("{}", window.swapchain_settings.color_space, allocator = context.temp_allocator);

		imgui.SetNextItemWidth(150);
		if imgui.BeginCombo("Swapchain Color Space", strings.clone_to_cstring(curr_space_str, context.temp_allocator)){
			for space in SwapchainColorSpace {

				space_str := fmt.aprintf("{}", space, allocator = context.temp_allocator);

				if imgui.Selectable(strings.clone_to_cstring(space_str, context.temp_allocator)) {

					window_set_color_space(space);
					break;
				}
			}

			imgui.EndCombo();
		}

		imgui.SetItemTooltip("call: window_set_color_space(target_color_space: SwapchainColorSpace) -> bool ");
	}

	imgui.Spacing();
	imgui.Spacing();
	imgui.Spacing();

	// Render Target
	{
		curr_format_str := fmt.aprintf("{}", ren_config.geo_color_target_format, allocator = context.temp_allocator);

		imgui.SetNextItemWidth(150);
		if imgui.BeginCombo("Render Target Format", strings.clone_to_cstring(curr_format_str, context.temp_allocator)){
				

				for format in RenderTargetFormat {

					format_str := fmt.aprintf("{}", format, allocator = context.temp_allocator);

					if imgui.Selectable(strings.clone_to_cstring(format_str, context.temp_allocator)) {


						set_render_target_format(format);
						break;
					}
				}

			imgui.EndCombo();
		}
		imgui.SetItemTooltip("call: set_render_target_format(format: RenderTargetFormat)");
	}

	// Depth Target
	{
		curr_depth_format_str := fmt.aprintf("{}", ren_config.geo_depth_stencil_format, allocator = context.temp_allocator);

		imgui.SetNextItemWidth(150);
		if imgui.BeginCombo("Depth Target Format", strings.clone_to_cstring(curr_depth_format_str, context.temp_allocator)){
				

				for format in DepthStencilFormat {

					format_str := fmt.aprintf("{}", format, allocator = context.temp_allocator);

					if imgui.Selectable(strings.clone_to_cstring(format_str, context.temp_allocator)) {

						set_depth_stencil_target_format(format);
						break;
					}
				}

			imgui.EndCombo();
		}
		imgui.SetItemTooltip("call: set_depth_stencil_target_format(format: DepthStencilFormat)");
	}

	
	imgui.Spacing();
	imgui.Spacing();
	imgui.Text("Render Effects ")
	imgui.Spacing();

	// Render Effect GTAO
	{
		GTAO_effect_enabled : bool = .GTAO in ren_config.ren_effect_flags;

		if imgui.Checkbox("GTAO Effect Enable", &GTAO_effect_enabled){

			if GTAO_effect_enabled {
				enable_render_effects({.GTAO});
			} else {
				disable_render_effects({.GTAO});
			}
		}
		imgui.SetItemTooltip("call: enable_render_effects(effects : RenderingEffectFlags)\ncall: set_ren_effect_GTAO_settings(settings : RenEffectGTAOSettings)");

		if GTAO_effect_enabled {

			ao_settings := get_ren_effect_GTAO_settings();

			any_changed : bool = false;

			any_changed |= imgui.Checkbox("Temporary Disable", &ao_settings.temporary_disabled)
			any_changed |= imgui.Checkbox("Full Resolution", &ao_settings.full_res)
			
			imgui.Spacing();


			any_changed |= imgui.DragFloat("AO strength  ", &ao_settings.strength , 0.05, 0.1, 10.0)

			sample_count_int : i32 = cast(i32)ao_settings.sample_count;
			if imgui.DragInt("AO sample count  ", &sample_count_int, 1, 1, 100) {
				ao_settings.sample_count = cast(u32)sample_count_int;
				any_changed = true;
			}

			slice_count_int : i32 = cast(i32)ao_settings.slice_count;
			if imgui.DragInt("AO slice count  ", &slice_count_int, 1, 1, 100) {
				ao_settings.slice_count = cast(u32)slice_count_int;
				any_changed = true;
			}

			any_changed |= imgui.DragFloat("AO sample radius ", &ao_settings.sample_radius, 0.01, 0.001, 100.0)
			any_changed |= imgui.DragFloat("AO hit thickness ", &ao_settings.hit_thickness, 0.01, 0.001, 100.0)
			

			if any_changed {
				set_ren_effect_GTAO_settings(ao_settings);
			}

			imgui.Spacing();
			imgui.Spacing();
		}
	}

	// Render Effect SMAA
	{
		SMAA_effect_enabled : bool = .SMAA in ren_config.ren_effect_flags;

		if imgui.Checkbox("SMAA Effect Enable", &SMAA_effect_enabled){

			if SMAA_effect_enabled {
				enable_render_effects({.SMAA});
			} else {
				disable_render_effects({.SMAA});
			}
		}

		if SMAA_effect_enabled {

			smaa_settings := get_ren_effect_SMAA_settings();

			any_changed : bool = false;

			any_changed |= imgui.Checkbox("SMAA Temporary Disable", &smaa_settings.temporary_disabled)

			if any_changed {
				set_ren_effect_SMAA_settings(smaa_settings);
			}

			imgui.Spacing();
			imgui.Spacing();
		}
	}
}


debug_gui_draw_render_debug_settings :: proc(){


	debug_config := get_render_debug_config();

	imgui.Checkbox("Draw Bounding Box OBB", &debug_config.draw_bounding_box);
	imgui.SetItemTooltip("set variable: renderer_get_debug_config().draw_bounding_box ");
	imgui.Checkbox("Draw Bounding Box AABB", &debug_config.draw_bounding_box_axis_aligned);
	imgui.SetItemTooltip("set variable: renderer_get_debug_config().draw_bounding_box_axis_aligned ");
	imgui.Checkbox("Draw Camera Frustum", &debug_config.draw_camera_frustum_box);
}


debug_gui_draw_performance_counters :: proc(){

	perfs := get_performance_counters();

	imgui.Text("Universe total update time %f", perfs.universe_total_update_time_ms);

	imgui.Text("Frustum Culled instance %u", perfs.frustum_culled_instance);
	imgui.Text("Frustum Culling Time %f ms", perfs.frustum_culling_time_ms);


	imgui.Spacing()
	imgui.Spacing()

	imgui.Text("Rendering");
	
	imgui.Spacing()
	imgui.Text("Depth Prepass CPU %f ms", perfs.depth_prepass_cpu_ms);
	imgui.Spacing()
	imgui.Text("Depth Prepass draw calls    %u", perfs.depth_prepass_drawcalls);
	imgui.Text("Depth Prepass pipe switches %u", perfs.depth_prepass_num_pipeline_switches);

	
	imgui.Spacing()
	imgui.Text("Shadowmap Pass CPU %f ms", perfs.shadowmap_pass_cpu_ms);
	imgui.Spacing()
	imgui.Text("Shadowmap Pass draw calls    %u", perfs.shadowmap_pass_drawcalls);
	imgui.Text("Shadowmap Pass pipe switches %u", perfs.shadowmap_pass_num_pipeline_switches);
	imgui.Text("Shadowmap Pass rendered shadomaps %u", perfs.shadowmap_pass_num_rendered_shadowmaps);


	imgui.Spacing()
	imgui.Spacing()
	imgui.Text("Forward Pass CPU %f ms"   , perfs.forward_pass_cpu_ms);
	imgui.Spacing()
	imgui.Text("Forward Pass draw calls    %u", perfs.forward_pass_drawcalls);
	imgui.Text("Forward Pass pipe switches %u", perfs.forward_pass_num_pipeline_switches);
}

debug_gui_draw_universe_settings :: proc(universe: ^Universe){

	uni := universe;

	imgui.Checkbox("Do Frustum Culling", &uni.do_frustum_culling);
	imgui.SetItemTooltip("set variable: universe.do_frustum_culling");
	imgui.Checkbox("Cull shadowmap draws", &uni.cull_shadow_draws);
	imgui.SetItemTooltip("set variable: universe.cull_shadow_draws");

	imgui.Spacing()
	imgui.Spacing()
	imgui.SliderFloat("cascade near_far_scale ", &uni.shadow_cascade_near_far_scale, 0.0, 10.0)
	imgui.SliderFloat("cascade side_scale ",     &uni.shadow_cascade_side_scale, 0.0, 10.0);

	split_1 : f32 = uni.shadow_cascade_split_1;
	split_2 : f32 = uni.shadow_cascade_split_2;
	split_3 : f32 = uni.shadow_cascade_split_3;

	if imgui.SliderFloat("cascade split 1 ", &split_1, 0.0, 1.0) {
		uni.shadow_cascade_split_1 = linalg.clamp(split_1, 0.0, split_2);
	}
	if imgui.SliderFloat("cascade split 2 ", &split_2, 0.0, 1.0){
		uni.shadow_cascade_split_2 = linalg.clamp(split_2, split_1, split_3);
	}
	if imgui.SliderFloat("cascade split 3 ", &split_3, 0.0, 1.0){
		uni.shadow_cascade_split_3 = linalg.clamp(split_3, split_2, 1.0);
	}
	imgui.Spacing()
	imgui.Spacing()

	//imgui.DragFloat("tmp_spot_near", &uni.tmp_spot_near, 0.1, 0.0, 100 );
	//imgui.DragFloat("tmp_spot_far ", &uni.tmp_spot_far , 0.1, 0.0, 100 );


	//imgui.SliderFloat("TMP DEBUG: Skybox Lerp Irradiance Map", &uni.debug_test_float, 0.0, 1.0);
}

debug_gui_draw_entity_component_table :: proc(universe: ^Universe){

	num_collums : i32 = len(ComponentType) + 2;

	table_flags := imgui.TableFlags_Resizable | imgui.TableFlags_RowBg | imgui.TableFlags_Borders;

	if(imgui.BeginTable("Entity", num_collums, table_flags )){

		imgui.TableHeadersRow();

		imgui.TableSetColumnIndex(0);
		imgui.Text("ID");
		imgui.TableSetColumnIndex(1);
		imgui.Text("Info");

		for comp_type in ComponentType{
			
			imgui.TableSetColumnIndex(2 + cast(i32)comp_type);
			
			txt := fmt.aprintf("{}", comp_type, allocator = context.temp_allocator);
			imgui.Text(strings.clone_to_cstring(txt, context.temp_allocator));
		}


		for &info, index in universe.ecs.entity_infos {
			imgui.TableNextRow();

			// Entity ID
			imgui.TableSetColumnIndex(0);
			imgui.Text("%i", cast(i32)index);

			imgui.TableSetColumnIndex(1);
			info_txt := fmt.aprintf("Exists:  {}\nEnabled: {}\n", info.exists, info.enabled, allocator = context.temp_allocator);
			imgui.Text(strings.clone_to_cstring(info_txt, context.temp_allocator));


			for comp_type in ComponentType{
				imgui.TableSetColumnIndex(2 + cast(i32)comp_type);
				if(comp_type in info.component_set){
					imgui.Text("Attached");
				}
			}

		}


		imgui.EndTable();
	}
}



debug_gui_draw_entity_viewer :: proc(universe: ^Universe, entity : Entity) {

	ecs := &universe.ecs;

	if(!ecs_entity_exists(ecs, entity)){
		imgui.Text("Entity does not exist in this universe. Entity ID: %i", entity.id);
		return;
	}



	ent_info := &ecs.entity_infos[entity.id];

	imgui_text_fmt("Entity ID {}", entity.id);
	imgui.Checkbox("Enabled", &ent_info.enabled);


	imgui.Spacing()
	imgui.Spacing()

	for comp_type in ent_info.component_set {

		comp_type_cstr := fmt_cstring("{}", comp_type);

		if imgui.TreeNode(comp_type_cstr) {

			switch comp_type {
				case .Transform: 
					comp := ecs_get_transform(ecs, entity);
					debug_gui_draw_component_editor_transform(comp);
				case .Camera: 
					comp, err := ecs_get_component(ecs, entity, CameraComponent)
					if err == .Success do debug_gui_draw_component_editor_camera(comp);
				case .Light: 
					comp, err := ecs_get_component(ecs, entity, LightComponent)
					if err == .Success do debug_gui_draw_component_editor_light(comp);
				case .Skybox: 
					comp, err := ecs_get_component(ecs, entity, SkyboxComponent)
					if err == .Success do debug_gui_draw_component_editor_skybox(comp);
				case .MeshRenderer: 
					comp, err := ecs_get_component(ecs, entity, MeshRendererComponent)
					if err == .Success do debug_gui_draw_component_editor_meshrenderer(comp);
				case .CustomShader: 
					comp, err := ecs_get_component(ecs, entity, CustomShaderComponent)

			}

			imgui.TreePop();
		}
	}
}


// Component Editors

debug_gui_draw_component_editor_transform :: proc (comp : ^TransformComponent){

	any_changed : bool = false;

	any_changed |= imgui.DragFloat3("Position", &comp.position, v_speed = 0.1, v_min = -math.F32_MAX, v_max = math.F32_MAX);
	any_changed |= imgui.DragFloat3("Scale", &comp.scale, v_speed = 0.01, v_min = -math.F32_MAX, v_max = math.F32_MAX);

	
	x,y,z := linalg.euler_angles_from_quaternion_f32(comp.orientation, linalg.Euler_Angle_Order.XYZ);
	x = linalg.to_degrees(x);
	y = linalg.to_degrees(y);
	z = linalg.to_degrees(z);
	angles : [3]f32 = {x,y,z}; // copy




	if imgui.DragFloat3("Rotation Euler XYZ", &angles, v_speed = 1.0, v_min = -361, v_max = 361) {

		// users can only modify one value at a time
		// so only one of these will be executed here. 
		// Therefore order of rotation does not matter much and is efectivly dirven by the sequence of 
		// slider inputs by the user anyway.

		if(x != angles.x) {
			// Rotate around local right axis
			x_dif : f32 = angles.x - x;
			//x_dif : f32 = angles.x;
			right := get_right(comp);
			rot_quat := linalg.quaternion_angle_axis(linalg.to_radians(x_dif), right);
			comp.orientation = linalg.quaternion_mul_quaternion(rot_quat, comp.orientation );

		}
		if(y != angles.y){
			// Rotate around local up axis
			y_dif : f32 = angles.y - y;
			up := get_up(comp);
			rot_quat := linalg.quaternion_angle_axis(linalg.to_radians(y_dif), up);
			comp.orientation = linalg.quaternion_mul_quaternion(rot_quat, comp.orientation);
		}
		if(z != angles.z){
			z_dif : f32 = angles.z - z;
			// Rotate around local forward axis
			forward  := get_forward(comp);
			rot_quat := linalg.quaternion_angle_axis(linalg.to_radians(z_dif), forward);
			comp.orientation = linalg.quaternion_mul_quaternion(rot_quat, comp.orientation);
		}

		any_changed |= true;
	}

	if imgui.Button("Reset Rotation") {
		comp.orientation = linalg.QUATERNIONF32_IDENTITY;
		any_changed |= true;
	}

	imgui_text_fmt("Orientation x: {}, y: {}, z: {}, w: {}", comp.orientation.x,comp.orientation.y,comp.orientation.z,comp.orientation.w);


	if(any_changed){

		if ecs_component_is_attached(comp.parent_ecs, comp.entity, .Light ){

			light_comp , err := ecs_get_component(comp.parent_ecs, comp.entity, LightComponent);

			comp_light_push_changes(light_comp);
		}
	}
}

debug_gui_draw_component_editor_camera :: proc (comp : ^CameraComponent) {

	imgui.DragFloat("Field of View"  , &comp.fov_deg  , v_speed = 0.01 , v_min = 0.001, v_max = 180.0);
	imgui.DragFloat("Near Clip Plane", &comp.near_clip, v_speed = 0.001, v_min = 0.001, v_max = math.F32_MAX);
	imgui.DragFloat("Far  Clip Plane", &comp.far_clip , v_speed = 0.1  , v_min = 0.01 , v_max = math.F32_MAX);

	imgui.Spacing();

	imgui.DragFloat("Aperture", &comp.aperture  , v_speed = 0.01 , v_min = 0.001, v_max = 100.0);
	imgui.DragFloat("Shutter Speed", &comp.shutter_speed  , v_speed = 0.001 , v_min = 0.00001, v_max = 1.0);
	imgui.DragFloat("Sensitivity ISO", &comp.iso  , v_speed = 50.0 , v_min = 1.0, v_max = 10_000.0);
	imgui.DragFloat("Exposure Correction", &comp.exposure_correction  , v_speed = 0.001 , v_min = -10.0, v_max = 10.0);

}

debug_gui_draw_component_editor_light :: proc (comp : ^LightComponent){

	draw_shadowmap_resolution_combo :: proc(combo_name : cstring, current_resolution : ShadowmapResolution) -> (changed : bool, changed_to_res : ShadowmapResolution) {

		curr_res_cstr := fmt_cstring("{}", current_resolution);

		changed = false;

		imgui.SetNextItemWidth(150);

		if imgui.BeginCombo(combo_name, curr_res_cstr) {
			
			for res in ShadowmapResolution {

				res_cstr := fmt_cstring("{}", res);

				if imgui.Selectable(res_cstr) {
					
					changed_to_res = res;
					changed = true;
					break;
				}
			}

			imgui.EndCombo();
		}

		return;

	}

	any_changed : bool = false;
	light_type := comp_light_get_type(comp);
	{

		curr_type_cstr := fmt_cstring("{}", light_type);

		imgui.SetNextItemWidth(150);

		if imgui.BeginCombo("Light Type", curr_type_cstr) {
			
			for type in LightType {


				type_cstr := fmt_cstring("{}", type);

				if imgui.Selectable(type_cstr) {
					
					comp_light_set_type(comp, type);
					any_changed  |= true;
					
					break;
				}
			}


			imgui.EndCombo();
		}
	}

	any_changed |= imgui.ColorEdit3("Color", &comp.color);
	any_changed |= imgui.DragFloat("Strength"  , &comp.strength , v_speed = 0.01, v_min = 0.000, v_max = 10000000.0);
	any_changed |= imgui.Checkbox("Cast Shadows", &comp.cast_shadows);

	if comp.cast_shadows {		
		switch &variant in comp.variant {
			case DirectionalLightVariant: 

				for cascade in 0..<3 {

					curr_res := variant.shadowmap_cascade_resolutions[cascade];

					combo_name := fmt_cstring("Cascade {} Shadowmap Resolution", cascade);

					res_changed, changed_to := draw_shadowmap_resolution_combo(combo_name, curr_res);

					if(res_changed){
						variant.shadowmap_cascade_resolutions[cascade] = changed_to;
					}

					any_changed |= res_changed;
				}

			case PointLightVariant:

				curr_res := variant.shadowmap_resolution

				res_changed, changed_to := draw_shadowmap_resolution_combo("Shadowmap Resolution", curr_res);

				imgui.Checkbox("Draw Cone", &variant.draw_cone);
				
				if imgui.DragInt("Draw Cone Index", &variant.draw_cone_index, v_speed = 0.25, v_min = -1, v_max = 5) {

				}

				if(res_changed){
					variant.shadowmap_resolution = changed_to;
				}

				any_changed |= res_changed;

			case SpotLightVariant:

				any_changed |= imgui.DragFloat("inner cone angle", &variant.inner_cone_angle_deg , v_speed = 0.01, v_min = 0.001, v_max = variant.outer_cone_angle_deg);
				any_changed |= imgui.DragFloat("outer cone angle", &variant.outer_cone_angle_deg , v_speed = 0.01, v_min = 0.001, v_max = 360.0);
				
				imgui.Checkbox("Draw Cone", &variant.draw_cone);

				imgui.Spacing();

				curr_res := variant.shadowmap_resolution

				res_changed, changed_to := draw_shadowmap_resolution_combo("Shadowmap Resolution", curr_res);

				if(res_changed){
					variant.shadowmap_resolution = changed_to;
				}

				any_changed |= res_changed;
		}
	}


	if any_changed {
		comp_light_push_changes(comp);
	}
}


debug_gui_draw_component_editor_skybox :: proc (comp : ^SkyboxComponent) {

	changed : bool = false;

	changed |= imgui.DragFloat("Exposure"  , &comp.exposure , v_speed = 0.01, v_min = -10.0, v_max = 10.0);
	changed |= imgui.DragFloat("Rotation"  , &comp.rotation , v_speed = 1.0, v_min = -360, v_max = 360.0);

	imgui.Spacing();

	changed |= imgui.ColorEdit3("Zenith", &comp.color_zenith);
	changed |= imgui.ColorEdit3("Horizon", &comp.color_horizon);
	changed |= imgui.ColorEdit3("Nadir", &comp.color_nadir);


	if changed {
		comp_skybox_push_changes(comp);
	}
}

debug_gui_draw_component_editor_meshrenderer :: proc (comp : ^MeshRendererComponent) {

	imgui.Text("Not Implemented yet");
}

// UTILITY

imgui_text_fmt :: #force_inline proc(fmt_string : string, args: ..any){

	formated : string = fmt.aprintf(fmt_string, ..args, allocator  =  context.temp_allocator);
	txt : cstring = strings.clone_to_cstring(formated, allocator = context.temp_allocator);
	imgui.Text(txt);
}

fmt_cstring :: #force_inline proc(fmt_string : string, args: ..any) -> cstring {
	formated : string = fmt.aprintf(fmt_string, ..args, allocator  =  context.temp_allocator);
	return strings.clone_to_cstring(formated, allocator = context.temp_allocator);
}