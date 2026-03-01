package iri

// /* 
// NOTE: 

// This gui implementation is NOT used atm and replaced by debug_gui.odin which useses DearImGui instead of microUi

// Below is the code to use for rendering with sdl

// 	dui_draw_anything, dui_atlas_tex_sampler_binding, dui_storage_buf, dui_num_instances := dui_get_draw_resources();

// 	if(dui_draw_anything) {

// 	ui_color_target := sdl.GPUColorTargetInfo {
// 	    texture = ren_ctx.render_target_tex,
// 	    clear_color = sdl.FColor{0.4,0,0,1},
// 	    load_op  = sdl.GPULoadOp.LOAD,
// 	    store_op = sdl.GPUStoreOp.STORE,
// 	}

// 	ui_depth_stencil_target_info : sdl.GPUDepthStencilTargetInfo = sdl.GPUDepthStencilTargetInfo{
// 	    texture = ren_ctx.depth_stencil_tex,
// 	    clear_depth = 1,                        // The value to clear the depth component to at the beginning of the render pass. Ignored if GPU_LOADOP_CLEAR is not used. 
// 	    load_op = sdl.GPULoadOp.LOAD,          // What is done with the depth contents at the beginning of the render pass.
// 	    store_op = sdl.GPUStoreOp.STORE,    // What is done with the depth results of the render pass.
// 	    stencil_load_op = sdl.GPULoadOp.CLEAR,
// 	    stencil_store_op = sdl.GPUStoreOp.STORE,
// 	    cycle = false,         // true cycles the texture if the texture is bound and any load ops are not LOAD 
// 	    clear_stencil = 0,        // The value to clear the stencil component to at the beginning of the render pass. Ignored if GPU_LOADOP_CLEAR is not used. 
// 	}

// 	dui_render_pass : ^sdl.GPURenderPass = sdl.BeginGPURenderPass(cmd_buf, &ui_color_target, 1, &ui_depth_stencil_target_info);


// 	pipeline_dui := pipeline_manager_get_pipeline(.DebugUI);

// 	sdl.BindGPUGraphicsPipeline(dui_render_pass, pipeline_dui);

// 	// Bind the Atlas texture. In theory this only need to happen once. Not every frame.
// 	sdl.BindGPUFragmentSamplers(dui_render_pass, 0, &dui_atlas_tex_sampler_binding, 1);

// 	// Bind the Storage Buffer
// 	sdl.BindGPUVertexStorageBuffers(dui_render_pass, 0, &dui_storage_buf, 1);

// 	// Note: for each quad draw instance we need 6 vertecies
// 	sdl.DrawGPUPrimitives(dui_render_pass, dui_num_instances * 6, 1, 0, 0);


// 	sdl.EndGPURenderPass(dui_render_pass);


// */


// import "core:log"
// import "core:mem"

// import mu "vendor:microui"
// import sdl "vendor:sdl3"


// DebugUI_CallbackSignature :: #type proc(ctx : ^mu.Context, window_size : [2]u32);

// @(private="file")
// dui_atlas_size_f :: [2]f32{mu.DEFAULT_ATLAS_WIDTH, mu.DEFAULT_ATLAS_HEIGHT};

// // Mirrors a shader UBO struct must be 16byte aligned
// @(private="file")
// UIInstanceDrawData :: struct {
//     color 		 	  : [4]f32,
//     vert_offset_scale : [4]f32,
//     uv_offset_scale	  : [4]f32,
//     use_atlas_tex : f32, // 0 if not using atlas 1 if using atlas.
//     padding1 : f32,
//     padding2 : f32,
//     padding3 : f32,
// }

// @(private="file")
// DebugUIState :: struct {

// 	ctx : ^mu.Context,

// 	process_callback : DebugUI_CallbackSignature,

// 	wants_capture_input : bool,


// 	atlas_tex : ^sdl.GPUTexture,
// 	atlas_sampler : ^sdl.GPUSampler,

// 	draw_data : [dynamic]UIInstanceDrawData,
// 	draw_data_byte_size_last_frame : u32,
// 	num_draws_last_frame : u32,

// 	draw_data_gpu_buf : ^sdl.GPUBuffer,
// 	draw_data_transfer_buf : ^sdl.GPUTransferBuffer,
// }

// @(private="file")
// uistate : DebugUIState;


// @(private="file")
// dui_init :: proc(gpu_device : ^sdl.GPUDevice){

// 	uistate.wants_capture_input = false;
// 	uistate.draw_data_byte_size_last_frame = 0;
// 	uistate.num_draws_last_frame = 0;

// 	// initialize micro-ui
// 	uistate.ctx = new(mu.Context);

// 	mu.init(uistate.ctx, nil);

// 	// provide text_width and text_height callbacks. These are the default ones provided by the odin bindings.
// 	uistate.ctx.text_width  =  mu.default_atlas_text_width;
// 	uistate.ctx.text_height =  mu.default_atlas_text_height;

// 	input_register_mouse_motion_callback(dui_cb_mouse_motion);

// 	input_register_mouse_button_callback(dui_cb_l_mouse_press  , MouseButton.LEFT  , {MouseButtonAction.PRESS});
// 	input_register_mouse_button_callback(dui_cb_l_mouse_release, MouseButton.LEFT  , {MouseButtonAction.RELEASE});
// 	input_register_mouse_button_callback(dui_cb_r_mouse_press  , MouseButton.RIGHT , {MouseButtonAction.PRESS});
// 	input_register_mouse_button_callback(dui_cb_r_mouse_release, MouseButton.RIGHT , {MouseButtonAction.RELEASE});
// 	input_register_mouse_button_callback(dui_cb_m_mouse_press  , MouseButton.MIDDLE, {MouseButtonAction.PRESS});
// 	input_register_mouse_button_callback(dui_cb_m_mouse_release, MouseButton.MIDDLE, {MouseButtonAction.RELEASE});

// 	input_register_mouse_wheel_callback(dui_cb_mouse_scroll);


// 	reserve(&uistate.draw_data, 1024); // prereserve 1024 instances

// 	// Load the atlas texture
// 	dui_load_atlas_as_sdl_texture(gpu_device);
// }


// @(private="file")
// dui_shutdown :: proc(gpu_device : ^sdl.GPUDevice){

// 	if(uistate.ctx != nil){
// 		free(uistate.ctx);
// 	}

// 	delete(uistate.draw_data);

// 	if(uistate.draw_data_gpu_buf != nil){
// 		sdl.ReleaseGPUBuffer(gpu_device, uistate.draw_data_gpu_buf);
// 	}
// 	if(uistate.draw_data_transfer_buf != nil){
// 		sdl.ReleaseGPUTransferBuffer(gpu_device, uistate.draw_data_transfer_buf);
// 	}
// 	if(uistate.atlas_tex != nil){
// 		sdl.ReleaseGPUTexture(gpu_device, uistate.atlas_tex);
// 	}
// 	if(uistate.atlas_sampler != nil){
// 		sdl.ReleaseGPUSampler(gpu_device, uistate.atlas_sampler);
// 	}
// }

// @(private="file")
// dui_set_callback :: proc(callback_proc : DebugUI_CallbackSignature) {
// 	uistate.process_callback = callback_proc;
// }

// @(private="file")
// dui_want_capture_input :: proc() -> bool {
// 	return uistate.wants_capture_input;	
// }



// @(private="file")
// dui_process_ui :: proc(window_size : [2]u32){

// 	if(uistate.process_callback == nil){
// 		uistate.wants_capture_input = false;
// 		return;
// 	}

// 	// Process..
// 	mu.begin(uistate.ctx);
	
// 	uistate.process_callback(uistate.ctx,window_size);
	
// 	mu.end(uistate.ctx);
// }

// @(private="file")
// dui_process_draw_data :: proc(gpu_device: ^sdl.GPUDevice, frame_size : [2]f32) -> (upload_new_data : bool, transfer_buf_location : sdl.GPUTransferBufferLocation, transfer_buf_region : sdl.GPUBufferRegion) {

// 	/* NOTE: 
// 		Here we do a number of things. 
// 		First we iterate the draw commands produced by micro-ui and make linear instance buffer of rectangles to draw later.
// 		TODO: We also determine if mouse hovers any rectangle in the ui.
// 		TODO: We generate a hash based on the draw commands to know if anything has changed compared to last frame.
// 		Then we update/create a transfer buffer with a region and loaction that we return to the caller.
// 		Caller should be the renderer that can then upload that new data to the gpu at the beginning of the frame.
// 	*/
	
// 	ctx : ^mu.Context = uistate.ctx;

// 	mouse_hovers_ui : bool = false;


// 	clear(&uistate.draw_data);

// 	// Itterate micro-ui command list.
// 	command : ^mu.Command = nil;
//     for (mu.next_command(ctx, &command)){
    
//         switch cmd in command.variant {
//             case ^mu.Command_Jump: continue; // We dont care about this..
//             case ^mu.Command_Clip: continue;
//                 //log.debugf("dui. CLIP");
//             case ^mu.Command_Rect:
                
//                 ui_data : UIInstanceDrawData = {
//                     color = {   cast(f32)cmd.color.r / 255.0,
//                                 cast(f32)cmd.color.g / 255.0,
//                                 cast(f32)cmd.color.b / 255.0,
//                                 cast(f32)cmd.color.a / 255.0},
//                     vert_offset_scale = dui_get_vert_offset_scale_from_rect(cmd.rect, frame_size),
//                     uv_offset_scale   = {0,0,0,0},
//                     use_atlas_tex = 0, // 0 if not using atlas 1 if using atlas.
//                     //padding1 : u32,
//                     //padding2 : u32,
//                     //padding3 : u32,
//                 }

//                 append(&uistate.draw_data, ui_data);

//                 if(!mouse_hovers_ui){
//                 	// Apparently this is not how to do this... prob this proc is not intended to use durring command itteration...
//                 	//mouse_hovers_ui = mu.mouse_over(ctx, cmd.rect);
//                 }

//             case ^mu.Command_Text:

//             	// Note: For text we dont check if mouse hovers it..

//                 txt_color : [4]f32 = {  cast(f32)cmd.color.r / 255.0,
//                                     cast(f32)cmd.color.g / 255.0,
//                                     cast(f32)cmd.color.b / 255.0,
//                                     cast(f32)cmd.color.a / 255.0};
                

//                 curr_pos := cmd.pos;

//                 // loop over each caracter
//                 for char in cmd.str {

//                     // Get Rect for character 
//                     // we can kinda just do that bc its all asci for now!
//                     char_atlas_rect : mu.Rect = mu.default_atlas[ cast(i32)mu.DEFAULT_ATLAS_FONT + cast(i32)char];

//                     draw_rect : mu.Rect = {curr_pos.x, curr_pos.y, char_atlas_rect.w, char_atlas_rect.h};

//                     //log.debugf("Char: {} -- Rect: {}", char, char_atlas_rect);

//                     char_spacing :: 0;
//                     curr_pos.x += char_atlas_rect.w + char_spacing;

//                     ui_data : UIInstanceDrawData = {
//                         color = txt_color,
//                         vert_offset_scale = dui_get_vert_offset_scale_from_rect(draw_rect, frame_size),
//                         uv_offset_scale   = dui_get_uv_offset_and_scale_from_atlas_rect(char_atlas_rect),
//                         use_atlas_tex = 1.0, // 0 if not using atlas 1 if using atlas.
//                         //padding1 : u32,
//                         //padding2 : u32,
//                         //padding3 : u32,
//                     }

//                     append(&uistate.draw_data, ui_data);
//                 }

//             case ^mu.Command_Icon:
//                 //log.debugf("dui. ICON: rectangle {}, id, {}, color: {}", cmd.rect, cmd.id, cmd.color);

//                 icon : mu.Icon = cmd.id;

//                 if(icon == mu.Icon.NONE) do continue;

//                 ui_data : UIInstanceDrawData = {
//                     color = {   cast(f32)cmd.color.r / 255.0,
//                                 cast(f32)cmd.color.g / 255.0,
//                                 cast(f32)cmd.color.b / 255.0,
//                                 cast(f32)cmd.color.a / 255.0},
//                     vert_offset_scale = dui_get_vert_offset_scale_from_rect(cmd.rect, frame_size),
//                     uv_offset_scale   = dui_get_uv_offset_and_scale_from_icon(icon),
//                     use_atlas_tex = 1.0, // 0 if not using atlas 1 if using atlas.
//                     //padding1 : u32,
//                     //padding2 : u32,
//                     //padding3 : u32,
//                 }

//                 append(&uistate.draw_data, ui_data);

//                 if(!mouse_hovers_ui){
//                 	// Apparently this is not how to do this... prob this proc is not intended to use durring command itteration...
//                 	//mouse_hovers_ui = mu.mouse_over(ctx, cmd.rect);
//                 }

//             case:
//         }
//     }

//     // TODO: Would be nice to have some way of checking if anything in the ui has changed
//     // so that we can potentially skip changing the transfer buffer and avoid unneccesary uploads to the gpu
//     // in the renderer. A naive way of doing this would be to itterate the entire draw_data list and produce a hash based on every entry
//     // that we can compare with last frame. we can of course skip doing that if the array length is already different.


//     // Update/Create Transfer Buffer
//     draw_data_byte_size : u32 = cast(u32)len(uistate.draw_data) * cast(u32)size_of(UIInstanceDrawData);

//     defer {
//     	uistate.draw_data_byte_size_last_frame = draw_data_byte_size;
//     	uistate.num_draws_last_frame = cast(u32)len(uistate.draw_data);
//     }

    
//     found_draw_commands : bool = draw_data_byte_size > 0;
    
//     uistate.wants_capture_input = found_draw_commands ? mouse_hovers_ui : false;

//     if(!found_draw_commands){

//     	return false, sdl.GPUTransferBufferLocation{}, sdl.GPUBufferRegion{};
//     }

//     // If the byte size is bigger then last frame we need to create a new transfer buffer and gpu buffer
//     // We don't check for if the size is smaller because it's not unreasonable to assume 
//     // that it can get bigger again so we want to keep the storage we alocated already and dont throw it away.
//     if(draw_data_byte_size > uistate.draw_data_byte_size_last_frame) {

//     	// Create a new GPU Buffer with bigger size
//     	if(uistate.draw_data_gpu_buf != nil){
//     		sdl.ReleaseGPUBuffer(gpu_device, uistate.draw_data_gpu_buf);
//     	}

// 		draw_data_gpu_buf_ci : sdl.GPUBufferCreateInfo = {
//     		usage = {sdl.GPUBufferUsageFlag.GRAPHICS_STORAGE_READ},
//     		size  =  draw_data_byte_size,
// 		};

// 		uistate.draw_data_gpu_buf = sdl.CreateGPUBuffer(gpu_device, draw_data_gpu_buf_ci);

//     	// Create a new Transfer Buffer with bigger size
//     	if(uistate.draw_data_transfer_buf != nil){
//     		// First Release the old one
//     		sdl.ReleaseGPUTransferBuffer(gpu_device, uistate.draw_data_transfer_buf);
//     	}

// 		transfer_buf_ci : sdl.GPUTransferBufferCreateInfo = {
// 	        size = draw_data_byte_size,
// 	        usage = sdl.GPUTransferBufferUsage.UPLOAD,
// 	    }

// 		uistate.draw_data_transfer_buf = sdl.CreateGPUTransferBuffer(gpu_device, transfer_buf_ci);
//     }


//     // copy our UI Instance Data to the transfer buffer.

//     transfer_buf_data_ptr : rawptr = sdl.MapGPUTransferBuffer(gpu_device, uistate.draw_data_transfer_buf, false);
    
//     mem.copy(transfer_buf_data_ptr, &uistate.draw_data[0], cast(int)draw_data_byte_size);

//     sdl.UnmapGPUTransferBuffer(gpu_device, uistate.draw_data_transfer_buf);


//     // Upload Ui draw data to our buffer.
//     transfer_buf_location = {
//         transfer_buffer = uistate.draw_data_transfer_buf,
//         offset = 0,
//     }

//     transfer_buf_region = {
//        buffer = uistate.draw_data_gpu_buf,
//        offset = 0,
//        size = draw_data_byte_size,
//     }

//     return true, transfer_buf_location, transfer_buf_region;
// }

// @(private="file")
// dui_get_num_draws_last_frame :: proc() -> u32 {
// 	return uistate.num_draws_last_frame;
// }

// @(private="file")
// dui_get_draw_resources :: proc() -> (draw_anything : bool, sampler_binding: sdl.GPUTextureSamplerBinding, storage_buf: ^sdl.GPUBuffer, num_instances : u32) {

// 	engine_assert(uistate.atlas_tex != nil);
// 	engine_assert(uistate.atlas_sampler != nil);
// 	engine_assert(uistate.draw_data_gpu_buf != nil);

// 	if(len(uistate.draw_data) == 0) {
// 		return false, sdl.GPUTextureSamplerBinding{texture = nil, sampler = nil} , nil, 0;
// 	}

// 	sampler_binding = {
// 		texture = uistate.atlas_tex,
//         sampler = uistate.atlas_sampler,
// 	};

// 	storage_buf = uistate.draw_data_gpu_buf;
	
// 	num_instances = cast(u32)len(uistate.draw_data);

// 	return true, sampler_binding, storage_buf, num_instances;
// }


// @(private="file")
// dui_load_atlas_as_sdl_texture :: proc(gpu_device : ^sdl.GPUDevice) {

// 	create_info : sdl.GPUTextureCreateInfo = {
//         type = sdl.GPUTextureType.D2, 
//         format = sdl.GPUTextureFormat.A8_UNORM,
//         usage = {sdl.GPUTextureUsageFlag.SAMPLER},
//         width  = mu.DEFAULT_ATLAS_WIDTH,
//         height = mu.DEFAULT_ATLAS_HEIGHT,
//         layer_count_or_depth = 1,
//         num_levels = 1,
//         sample_count = sdl.GPUSampleCount._1,
//     }

//     uistate.atlas_tex = sdl.CreateGPUTexture(gpu_device, create_info);


//     atlas_byte_size : uint = cast(uint)mu.DEFAULT_ATLAS_WIDTH * cast(uint)mu.DEFAULT_ATLAS_HEIGHT;

//     transfer_buf_ci : sdl.GPUTransferBufferCreateInfo ={
//     	usage = sdl.GPUTransferBufferUsage.UPLOAD,  /**< How the transfer buffer is intended to be used by the client. */
// 		size = cast(u32)atlas_byte_size,                  /**< The size in bytes of the transfer buffer. */
//     };

//     transfer_buf := sdl.CreateGPUTransferBuffer(gpu_device, transfer_buf_ci);
//     defer sdl.ReleaseGPUTransferBuffer(gpu_device, transfer_buf);


//     data : rawptr = sdl.MapGPUTransferBuffer(gpu_device, transfer_buf, false);

//     sdl.memcpy(data, &mu.default_atlas_alpha, atlas_byte_size);

//     sdl.UnmapGPUTransferBuffer(gpu_device, transfer_buf);


//     // now upload  the data to the texture somehow...

//     cmd_buf := sdl.AcquireGPUCommandBuffer(gpu_device);

//     copy_pass := sdl.BeginGPUCopyPass(cmd_buf);

//     source : sdl.GPUTextureTransferInfo = {
//     	transfer_buffer = transfer_buf,  /**< The transfer buffer used in the transfer operation. */
// 		offset = 0,              /**< The starting byte of the image data in the transfer buffer. */
// 		pixels_per_row = mu.DEFAULT_ATLAS_WIDTH * 1,              /**< The number of pixels from one row to the next. */
// 		rows_per_layer = mu.DEFAULT_ATLAS_HEIGHT,  /**< The number of rows from one layer/depth-slice to the next. */
//     }

//     destination : sdl.GPUTextureRegion = {
//     	texture = uistate.atlas_tex,  /**< The texture used in the copy operation. */
// 		mip_level = 0,       /**< The mip level index to transfer. */
// 		layer = 0,       /**< The layer index to transfer. */
// 		x = 0,       /**< The left offset of the region. */
// 		y = 0,       /**< The top offset of the region. */
// 		z = 0,       /**< The front offset of the region. */
// 		w = mu.DEFAULT_ATLAS_WIDTH,       /**< The width of the region. */
// 		h = mu.DEFAULT_ATLAS_HEIGHT,       /**< The height of the region. */
// 		d = 1,       /**< The depth of the region. */
//     }

//     sdl.UploadToGPUTexture(copy_pass, source, destination, false);

//     sdl.EndGPUCopyPass(copy_pass);

//     ok := sdl.SubmitGPUCommandBuffer(cmd_buf);


//     // Create the sampler

//     sampler_ci : sdl.GPUSamplerCreateInfo = {
//     	min_filter = sdl.GPUFilter.LINEAR,              /**< The minification filter to apply to lookups. */
// 		mag_filter = sdl.GPUFilter.LINEAR,              /**< The magnification filter to apply to lookups. */
// 		mipmap_mode = sdl.GPUSamplerMipmapMode.NEAREST,   /**< The mipmap filter to apply to lookups. */
// 		address_mode_u = sdl.GPUSamplerAddressMode.REPEAT,  /**< The addressing mode for U coordinates outside [0, 1). */
// 		address_mode_v = sdl.GPUSamplerAddressMode.REPEAT,  /**< The addressing mode for V coordinates outside [0, 1). */
// 		address_mode_w = sdl.GPUSamplerAddressMode.REPEAT,  /**< The addressing mode for W coordinates outside [0, 1). */
// 		//mip_lod_bias:      f32,                    /**< The bias to be added to mipmap LOD calculation. */
// 		//max_anisotropy:    f32,                    /**< The anisotropy value clamp used by the sampler. If enable_anisotropy is false, this is ignored. */
// 		//compare_op:        GPUCompareOp,           /**< The comparison operator to apply to fetched data before filtering. */
// 		//min_lod:           f32,                    /**< Clamps the minimum of the computed LOD value. */
// 		//max_lod:           f32,                    /**< Clamps the maximum of the computed LOD value. */
// 		//enable_anisotropy: bool,                   /**< true to enable anisotropic filtering. */
// 		enable_compare = false,                   /**< true to enable comparison against a reference value during lookups. */
// 	};

//     uistate.atlas_sampler = sdl.CreateGPUSampler(gpu_device, sampler_ci);

//     engine_assert(uistate.atlas_tex != nil);
//     engine_assert(uistate.atlas_sampler != nil);
// }


// // ============================================================================
// // Helper procedures.

// // Used for the rendering engine to quad vertex scaling and offsets into the atlas texture.
// @(private="file")
// dui_get_vert_offset_scale_from_rect :: proc( rect : mu.Rect, frame_size_f : [2]f32) -> (center_scale : [4]f32){

// 	//rect_f : [4]f32 = { cast(f32)rect.x, cast(f32)rect.y, cast(f32)rect.w, cast(f32)rect.h};

//     // center in 0..1 space
//     //center_scale.xy = (rect_f.xy + rect_f.zw / 2) / frame_size_f;
//     // now transform to ndc (-1..1) but flip y axis.
//     //center_scale.x = center_scale.x * 2 - 1; 
//     //center_scale.y = 1 - center_scale.y * 2; // flip y axis

//     // calculate scale


// 	center_scale.xy = [2]f32{cast(f32)rect.x, cast(f32)rect.y} / frame_size_f;

// 	center_scale.zw = [2]f32{cast(f32)rect.w, cast(f32)rect.h} / frame_size_f;

// 	return center_scale;
// }

// // Used for the rendering engine to determine uv offsets into the atlas texture.
// @(private="file")
// dui_get_uv_offset_and_scale_from_icon :: proc(icon : mu.Icon) -> (uv_offset_scale : [4]f32) {
// 	rect := dui_get_rect_from_icon(icon);
// 	return #force_inline dui_get_uv_offset_and_scale_from_atlas_rect(rect);
// }

// // Used for the rendering engine to determine uv offsets into the atlas texture.
// @(private="file")
// dui_get_uv_offset_and_scale_from_atlas_rect :: proc(rect : mu.Rect) -> (uv_offset_scale : [4]f32) {

// 	uv_offset_scale.xy = [2]f32{cast(f32)rect.x, cast(f32)rect.y} / dui_atlas_size_f;
// 	uv_offset_scale.zw  = [2]f32{cast(f32)rect.w, cast(f32)rect.h} / dui_atlas_size_f;

// 	return uv_offset_scale;
// }

// // Get the corresponding rect to an icon in the atlas texture.
// @(private="file")
// dui_get_rect_from_icon :: proc(icon : mu.Icon) -> mu.Rect{

// 	switch icon {
// 		case mu.Icon.NONE:  	return mu.default_atlas[mu.DEFAULT_ATLAS_WHITE];
// 		case mu.Icon.CLOSE: 	return mu.default_atlas[mu.DEFAULT_ATLAS_ICON_CLOSE];
// 		case mu.Icon.CHECK: 	return mu.default_atlas[mu.DEFAULT_ATLAS_ICON_CHECK];
// 		case mu.Icon.COLLAPSED:	return mu.default_atlas[mu.DEFAULT_ATLAS_ICON_COLLAPSED];
// 		case mu.Icon.EXPANDED:	return mu.default_atlas[mu.DEFAULT_ATLAS_ICON_EXPANDED];
// 		case mu.Icon.RESIZE:	return mu.default_atlas[mu.DEFAULT_ATLAS_ICON_RESIZE];
// 	}

// 	// invalid codepath
// 	return mu.Rect{0,0,0,0};
// }





// // ============================================================================
// // ============================================================================
// // Input callbacks from our input system and forward to micro-ui.

// @(private="file")
// dui_cb_mouse_motion :: proc(delta_seconds: f64, mouse_pos: [2]f32, mouse_delta: [2]f32) {
// 	mu.input_mouse_move(uistate.ctx, cast(i32)mouse_pos.x, cast(i32)mouse_pos.y);
// }

// @(private="file")
// dui_cb_l_mouse_press :: proc(delta_seconds: f64, mouse_pos: [2]f32,is_pressed: bool, is_double_click : bool){
// 	mu.input_mouse_down(uistate.ctx, cast(i32)mouse_pos.x, cast(i32)mouse_pos.y, mu.Mouse.LEFT);
// }

// @(private="file")
// dui_cb_l_mouse_release :: proc(delta_seconds: f64, mouse_pos: [2]f32,is_pressed: bool, is_double_click : bool){
// 	mu.input_mouse_up(uistate.ctx, cast(i32)mouse_pos.x, cast(i32)mouse_pos.y, mu.Mouse.LEFT);
// }

// @(private="file")
// dui_cb_r_mouse_press :: proc(delta_seconds: f64, mouse_pos: [2]f32,is_pressed: bool, is_double_click : bool){
// 	mu.input_mouse_down(uistate.ctx, cast(i32)mouse_pos.x, cast(i32)mouse_pos.y, mu.Mouse.RIGHT);
// }

// @(private="file")
// dui_cb_r_mouse_release :: proc(delta_seconds: f64, mouse_pos: [2]f32,is_pressed: bool, is_double_click : bool){
// 	mu.input_mouse_up(uistate.ctx, cast(i32)mouse_pos.x, cast(i32)mouse_pos.y, mu.Mouse.RIGHT);
// }

// @(private="file")
// dui_cb_m_mouse_press :: proc(delta_seconds: f64, mouse_pos: [2]f32,is_pressed: bool, is_double_click : bool){
// 	mu.input_mouse_down(uistate.ctx, cast(i32)mouse_pos.x, cast(i32)mouse_pos.y, mu.Mouse.MIDDLE);
// }

// @(private="file")
// dui_cb_m_mouse_release :: proc(delta_seconds: f64, mouse_pos: [2]f32,is_pressed: bool, is_double_click : bool){
// 	mu.input_mouse_up(uistate.ctx, cast(i32)mouse_pos.x, cast(i32)mouse_pos.y, mu.Mouse.MIDDLE);
// }

// @(private="file")
// dui_cb_mouse_scroll :: proc(delta_seconds: f64, mouse_pos: [2]f32, mouse_scroll: [2]f32, is_flipped_direction : bool){
// 	mu.input_scroll(uistate.ctx, cast(i32)mouse_scroll.x, cast(i32)mouse_scroll.y);
// }

// @(private="file")
// dui_cb_key_down :: proc(delta_seconds: f64, mouse_pos: [2]f32, mouse_scroll: [2]f32, is_flipped_direction : bool){

// }

