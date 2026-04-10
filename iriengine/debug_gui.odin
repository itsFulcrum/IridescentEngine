package iri

import "core:log"
import "core:fmt"
import "core:strings"
import "core:math"
import "core:math/linalg"
import "core:os"

import sdl "vendor:sdl3"

import imgui "odinary:dear_imguy"
import imgui_sdl3 "odinary:dear_imguy/imgui_impl_sdl3"
import imgui_sdl3gpu "odinary:dear_imguy/imgui_impl_sdlgpu3"


DebugGUI_CallbackSignature :: #type proc();

@(private="file")
DebugGuiContext :: struct{
	is_enabled : bool,
	enable_next_frame : bool, // we dont want users to enable/disable it mid frame 


	imgui_ctx: ^imgui.Context,
	imgui_io: ^imgui.IO,
	imgui_curr_draw_data: ^imgui.DrawData,

	debug_gui_editor_callback : DebugGUI_CallbackSignature,
	debug_gui_callback: DebugGUI_CallbackSignature,

	show_demo_window: bool,

	sdl_event_callback_id : i32,
}

@(private="file")
debug_gui_ctx: DebugGuiContext;


@(private="package")
debug_gui_init :: proc(window: ^WindowContext, render_target_format: RenderTargetFormat, msaa: MSAA) {


	debug_gui_ctx.is_enabled = false;
	debug_gui_ctx.enable_next_frame = false;
	debug_gui_ctx.show_demo_window = false;
	debug_gui_ctx.debug_gui_callback = nil;

	debug_gui_ctx.imgui_ctx = imgui.CreateContext();
	engine_assert(debug_gui_ctx.imgui_ctx != nil);

	imgui.StyleColorsDark();
	setup_imgui_style();


	debug_gui_ctx.imgui_io = imgui.GetIO();

	debug_gui_ctx.imgui_io.ConfigFlags += {.DockingEnable}
	debug_gui_ctx.imgui_io.ConfigFlags += {.ViewportsEnable}

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

	if debug_gui_ctx.enable_next_frame {
		debug_gui_ctx.is_enabled = true;
		debug_gui_ctx.enable_next_frame = false;
	}

	if !debug_gui_ctx.is_enabled {
		return;
	}

	imgui_sdl3gpu.NewFrame();
	imgui_sdl3.NewFrame();
	imgui.NewFrame();

	// All dear-imgui ui processing must happen in here
	{
		if debug_gui_ctx.show_demo_window {
			imgui.ShowDemoWindow(&debug_gui_ctx.show_demo_window);
		}

		if debug_gui_ctx.debug_gui_editor_callback != nil {
			debug_gui_ctx.debug_gui_editor_callback();
		}

		if debug_gui_ctx.debug_gui_callback != nil {
			debug_gui_ctx.debug_gui_callback();
		}

	}

	// This finishes the frame
	imgui.Render();
}

@(private="package")
debug_gui_prepare_and_upload_draw_data :: proc(cmd_buf: ^sdl.GPUCommandBuffer){

	if !debug_gui_ctx.is_enabled {
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

	if enable == debug_gui_ctx.is_enabled {
		return;
	}

	if enable == true {
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

debug_gui_set_editor_callback_procedure :: proc(callback: DebugGUI_CallbackSignature){

	debug_gui_ctx.debug_gui_editor_callback = callback;
}

debug_gui_toggle_imgui_debug_window :: proc() {
	debug_gui_ctx.show_demo_window = !debug_gui_ctx.show_demo_window;
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