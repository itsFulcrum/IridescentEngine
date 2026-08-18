package iri

import "core:c"
import "core:os"
import "core:log"
import "core:math/linalg"
import "odinary:mathy"
import "core:strings"
import "odinary:clay"
import sdl "vendor:sdl3"

import "odinary:picy"
import iria "iriasset"

// Maybe should be part of universe ?

// because clay only provides a u16 for fontid and we want to store generation aswell we have to shrink the maximum number of fonts 
// that can be loaded at one time to make our FontID compatible with clays fontID u16..... bruh
UI_MAX_NUM_FONTS :: c.UINT8_MAX

// CAST THIS TO u16 font id for clay layout.
FontID :: struct{index : u8, generation : u8}



UiManager :: struct {

    fonts      : [dynamic]FontAtlas,
    century_font : FontID,
	// Do we need multiple if we want multiple layouts for world space ??
	ctx : ^clay.Context,

	clay_arena_mem_size : uint,
	clay_arena_mem_buf : [^]byte,


    global_ui_rendering_enabled : bool,

    clay_render_commands : clay.ClayArray(clay.RenderCommand),

    // Rebuild each frame.
    frame_draw_commands  : [dynamic]UiDrawCommand,    
    frame_vert_draw_data : [dynamic]UiRectVertDrawDataGPU,
    frame_frag_draw_data : [dynamic]UiRectFragDrawDataGPU,

    frame_vert_draw_data_gpu_buf : BasicGPUBuffer,
    frame_frag_draw_data_gpu_buf : BasicGPUBuffer,
}

// 
// Public Interface
// 

ui_enable_rendering :: proc(){
    engine.ui_manager.global_ui_rendering_enabled = true;
}

ui_disable_rendering :: proc(){
    engine.ui_manager.global_ui_rendering_enabled = false;
}

ui_is_rendering_enabled :: proc() -> bool {
    return engine.ui_manager.global_ui_rendering_enabled;
}

// @Note: This should be as fast as possible.
ui_manager_measure_text_dimentions :: proc "c" ( text: clay.StringSlice, config: ^clay.TextElementConfig, userData: rawptr) -> clay.Dimensions {
    
    ui_manager : ^UiManager = cast(^UiManager)userData;
    txt_str := string(text.chars[0:text.length]);



    font_id : FontID = transmute(FontID)config.fontId;

    font := ui_manager_get_font(ui_manager, font_id)
    if font == nil {
        // Fallback but without font we cannot render this..
        // OLD Default BBox Creation: 
        return clay.Dimensions{f32(text.length * i32(config.fontSize)), f32(config.fontSize) }
    }

    letter_spacing : f32 = cast(f32)config.letterSpacing;

    font_scale : f32 = f32(config.fontSize) / font.info.font_size_px;

    xpos : f32 = 0.0;
    for codepoint, index in txt_str {

        x_advance, exists := font.rune_measure_lookup[codepoint];

        if !exists do continue; // TODO: produce empty quad with nothing or missing

        xpos += (x_advance * font_scale) + letter_spacing;
    }


    return clay.Dimensions{xpos, font.info.font_size_px * font_scale};
}

// can use this to assing FontID to clay text declaration font id.
font2clay :: proc "contextless" (font_id : FontID) -> (clay_font_id : u16) {
    return transmute(u16)font_id;
}

// 
// - Private stuff
// 


@(private="package")
ui_manager_init :: proc(ui : ^UiManager, frame_size : [2]u32) {

    log.warnf("VertData size: {}", size_of(UiRectVertDrawDataGPU))
    log.warnf("FragData size: {}", size_of(UiRectFragDrawDataGPU))

    ui_manager_load_default_font_asset(ui);

    ui.global_ui_rendering_enabled = true;

    century_font_asset_id , _ := asset_get_id_from_alias("UI.Fonts.Century", .FontAtlas)
    ui.century_font , _ = asset_manager_io_load_font_atlas_asset(engine.asset_manager, ui, century_font_asset_id);

	ui.clay_arena_mem_size = cast(uint)clay.MinMemorySize()
	ui.clay_arena_mem_buf = make([^]u8, ui.clay_arena_mem_size, context.allocator);

	arena: clay.Arena = clay.CreateArenaWithCapacityAndMemory(ui.clay_arena_mem_size, ui.clay_arena_mem_buf)
	
    ui.ctx = clay.Initialize(arena, {cast(f32)frame_size.x, cast(f32)frame_size.y}, { handler = ui_manager_clay_error_handler })

	clay.SetMeasureTextFunction(ui_manager_measure_text_dimentions, userData = ui)

}

@(private="package")
ui_manager_deinit :: proc(ui : ^UiManager, gpu_device : ^sdl.GPUDevice) {

    for &font in ui.fonts {
        font_atlas_free_contents(gpu_device, &font);
    }

    delete(ui.fonts);

	free(ui.clay_arena_mem_buf);
    ui.clay_arena_mem_buf = nil;
    ui.clay_arena_mem_size = 0;


    delete(ui.frame_draw_commands)
    delete(ui.frame_vert_draw_data)
    delete(ui.frame_frag_draw_data)

    gpu_buffer_release_buffers(gpu_device, &ui.frame_vert_draw_data_gpu_buf);
    gpu_buffer_release_buffers(gpu_device, &ui.frame_frag_draw_data_gpu_buf);
}


@(private="package")
ui_manager_clay_error_handler :: proc "c" (errorData: clay.ErrorData) {
    // Do something with the error data.

    context = engine.default_context;
    msg := strings.clone_from_ptr(errorData.errorText.chars, cast(int)errorData.errorText.length, context.temp_allocator)

    log.warnf("UI: Clay Error: {} - msg: {}", errorData.errorType, msg);
}

@(private="file")
ui_manager_load_default_font_asset :: proc(ui_manager : ^UiManager){

    // @Note: I intentionally avoid going through the asset manager api because the Default Font is part of engine_resources
    // which is in theory fine but when we are in EngineDevelopment mode and want to regenerate the FontAtlas for it by deleting it's awkward
    // because the asset_manager api does not know about the different engine resources folder an assumes there only exists the one in the ProjectPath
    // which is not neccesarly in sync with the one of this repostiory.. This Whole thing should probably work differently. Maybe just always use the one from Prjoect path
    // and only use the repositories one for copying and creating a new project. We will manaually have to copy paste it though to keep it in sync..

    res_path : string = get_resources_path();

    def_font_atlas_filepath , _ := os.join_path({res_path, "rendering/default_font/RobotoRegular.iria"}, context.temp_allocator);

    if os.exists(def_font_atlas_filepath){
        
        asset_font, read_ok := iria.asset_font_atlas_read_from_path(def_font_atlas_filepath)       
        defer if read_ok {
            iria.asset_font_atlas_free(asset_font);
        }

        if read_ok {
           id , add_ok := ui_manager_add_font(ui_manager, asset_font);
            if add_ok {
                engine_assert(id == FontID{})// Default font should be registered as the first one so that FontID zero is always the default one.

                return;
            }
        }
    }

    log.warnf("UiManager: Default Font Atlas was not found in Engine Resources. Attempting to generate new Atlas From raw .ttf");
        
    // Something went wrong, we didn't find the default font atlas in engine resources or it is corrupted.
    // Instead now try to find the original .ttf and recreate the font_atlas.


    def_font_filepath, _ := os.join_path({res_path, "rendering/default_font/RobotoRegular.ttf"}, context.temp_allocator)
    atlas_store_directory, _ := os.join_path({res_path, "rendering/default_font/"}, context.temp_allocator)

    if !os.exists(def_font_filepath){

        log.errorf("UiManager: Default Font .ttf file is also missing at: {}. Engine cannot render text with the aefault Font - Ui's may be broken.", def_font_filepath)
        return;
    }
    
    default_font_alias : string = "IriEngine.DefResource.Font.Roboto"

    create_info := FontAtlasCreateInfo{
        asset_alias = default_font_alias,

        import_flags = AssetImportFlags{.LogErrors, .OverwriteExisting},
        font_size      = 32,

        use_nearest_neighboor_filtering = false,
        oversampling_x = 2,
        oversampling_y = 2,
        glyph_range_flags = FontGlyphRangeFlags{.Ascii, .AsciiExtention, .LatinExtentionA},    
       // custom_codepoints : string,
    }

    import_ok := asset_importer_import_font_to_project(def_font_filepath, atlas_store_directory, create_info)

    if !import_ok {
        log.errorf("UiManager: Faild to import default font .ttf {}, Engine cannot render text with the default Font - Ui's may be broken.", def_font_filepath)
        return;
    }

    // Try loading again now.
    asset_font, read_ok := iria.asset_font_atlas_read_from_path(def_font_atlas_filepath)       
    if !read_ok {
        log.errorf("UiManager: Second Attempt at reading Default Font atlas after regenerating it Succesfully Failed. This should not happen actually.", def_font_atlas_filepath)
        return;
    }

    defer  {
        iria.asset_font_atlas_free(asset_font);
    }
    
    id , add_ok := ui_manager_add_font(ui_manager, asset_font);
    if !add_ok {
        log.errorf("UiManager: Idk man I tried. :(")
    }
}

@(private="package")
ui_manager_add_font :: proc(ui : ^UiManager, asset_font : ^iria.AssetFontAtlas) -> (FontID, bool) {
    
    if ui == nil || asset_font == nil {
        return FontID{}, false;
    }

    free_spot : int = -1;

    if len(ui.fonts) > 0 {
        for &font, arr_index in ui.fonts {
            if !font.font_is_loaded {
                free_spot = arr_index;
                break;
            }
        }
    }

    font_id : FontID;
    gpu_device := get_gpu_device();

    if free_spot >= 0 {

        free_font := &ui.fonts[free_spot];
        font_generation := free_font.font_id_generation + 1; // This might wrap if its larger than u8_max but thats okey. what i'd do anyway in that case.

        font_init_ok := ui_manager_init_font_atlas_from_asset(gpu_device, free_font, asset_font);
        if !font_init_ok {
            font_atlas_clear_contents(gpu_device, free_font);
            free_font.font_is_loaded = false;
            font_id.generation = font_generation; // keep generation.
            return FontID{}, false;
        }
        engine_assert(free_spot < cast(int)UI_MAX_NUM_FONTS);
        font_id.index = cast(u8)free_spot;
        font_id.generation = font_generation;
        free_font.font_is_loaded = true;

        return font_id, true;
    }

    // No free Spot
    arr_index : int = len(ui.fonts);
    if arr_index >= cast(int)UI_MAX_NUM_FONTS {
        return FontID{}, false; // can only support up to 255 to make FontID fit into u16.
    }

    font_id.index = cast(u8)arr_index;
    font_id.generation = 0;

    append_nothing(&ui.fonts);
    new_font := &ui.fonts[arr_index];

    new_font.font_id_generation = 0;

    font_init_ok := ui_manager_init_font_atlas_from_asset(gpu_device, new_font, asset_font);
    if !font_init_ok {
        font_atlas_clear_contents(gpu_device, new_font);
        new_font.font_is_loaded = false;
        return FontID{}, false;
    }

    new_font.font_is_loaded = true;

    return font_id, true;
}

@(private="package")
ui_manager_remove_font :: proc(ui : ^UiManager, font_id : FontID) {

    if !ui_manager_font_exists(ui, font_id){
        return;
    }

    font := &ui.fonts[font_id.index];

    gpu_device := get_gpu_device()

    font_atlas_clear_contents(gpu_device, font);

    // keep generation 
    font.font_id_generation = font_id.generation;
    font.font_is_loaded = false;
}

@(private="package")
ui_manager_font_exists :: proc "contextless" (ui : ^UiManager, font_id : FontID) -> bool {

    if cast(int)font_id.index >= len(ui.fonts) {
        return false;
    }

    font := &ui.fonts[font_id.index];

    if font.font_id_generation != font_id.generation {
        return false;
    }

    if !font.font_is_loaded {
        return false;
    }

    return true; 
}

@(private="package")
ui_manager_get_font :: proc "contextless" (ui : ^UiManager, font_id : FontID) -> ^FontAtlas {
    
    if !ui_manager_font_exists(ui, font_id){
        return nil;
    }

    return &ui.fonts[font_id.index];
}

@(private="package")
ui_manager_init_font_atlas_from_asset :: proc(gpu_device : ^sdl.GPUDevice, font_atlas : ^FontAtlas, asset_font : ^iria.AssetFontAtlas) -> (ok : bool) {
    
    if font_atlas == nil || asset_font == nil {
        return false;
    }

    if asset_font.atlas_pixels == nil {
        return false;
    }

    if asset_font.num_rune_codepoints == 0 {
        return false;
    }

    engine_assert(asset_font.rune_codepoints != nil)
    engine_assert(asset_font.rune_info != nil)
    engine_assert(len(asset_font.rune_codepoints) == len(asset_font.rune_info));

    sampler_filter : SamplerFilter = asset_font.use_nearest_neighbour_filtering ? SamplerFilter.NEAREST : SamplerFilter.LINEAR;

    width  : u32 = asset_font.info.atlas_width;
    height : u32 = asset_font.info.atlas_height;

    font_atlas.altas_tex = texture_2D_create_basic(gpu_device, {width, height}, sdl.GPUTextureFormat.R8_UNORM, true, sampler_filter, SamplerAddressMode.REPEAT, sdl.GPUTextureUsageFlags{.SAMPLER, .COLOR_TARGET});

    pic_info := picy.PicInfo {
        format = picy.PicFormat.R8_UNORM,   
        width  = width,
        height = height,
        num_bytes = picy.calc_bytes_for_img(width, height, .R8_UNORM),
        pixels = asset_font.atlas_pixels,
    }

    upload_gpu_ok := texture_upload_pic_info_to_gpu_texture_2D(gpu_device, font_atlas.altas_tex.binding.texture, &pic_info, gen_mips = true);
    if !upload_gpu_ok {
        return false;
    }

    // fill lookup tables.
    for i in 0..<asset_font.num_rune_codepoints {

        codepoint := asset_font.rune_codepoints[i];
        font_atlas.rune_measure_lookup[codepoint] = asset_font.rune_info[i].x_advance_px;
        font_atlas.rune_render_lookup[codepoint]  = asset_font.rune_info[i];
    }

    font_atlas.info = asset_font.info;

    return true;
}


// Should be called only once per frame.
@(private="package")
ui_manager_process_clay_layouts :: proc(ui_manager : ^UiManager, frame_size : [2]u32, delta_time : f32, true_delta_time : f32, universe : ^Universe = nil, universe_ui_callback : UniverseUI_CallbackSignature = nil) {

    IRI_PROFILE_PROCEDURE()

    if !ui_manager.global_ui_rendering_enabled {
        return;
    }

    frame_size_f := [2]f32{f32(frame_size.x), f32(frame_size.y)}; 
    layout_dims := clay.Dimensions{frame_size_f.x, frame_size_f.y};

    clay.SetLayoutDimensions(layout_dims);

    is_down : bool = input_mouse_button(.LEFT, {.IsPressed}).is_down;
    rel_mouse_pos := input_relative_mouse_position();

    wheels := input_mouse_wheel()

    clay.SetPointerState(rel_mouse_pos, is_down);

    // @NOTE: we want delta time here to actually be 'TRUE'
    clay.UpdateScrollContainers(enableDragScrolling = false, scrollDelta = wheels, deltaTime = true_delta_time);
    
    clay.BeginLayout()
    {
        // UI Callbacks here.

        if universe != nil && universe_ui_callback != nil {

            universe_ui_callback(universe, frame_size_f, delta_time);
        }

    }
    ui_manager.clay_render_commands = clay.EndLayout(delta_time);
}


UiRectShaderMode :: enum u32 {
    NonTexturedRect = 0,
    Text            = 1,    
    // TexturedRect = 2, Not Implemented
}

UiRectVertDrawDataGPU :: struct { // 32 bytes.
    position   : [2]f32,
    norm_z_depth : f32, // z-index normalized to 0..1 range. 1 = far, 0 = close;
    // as bit-packed u32 on GPU
    width       : u16,
    height      : u16,
    uv_offset  : [2]f32,
    uv_scale   : [2]f32,
}

UiRectFragDrawDataGPU :: struct { // 32 bytes
    rect_size       : [2]f32,
    mode            : UiRectShaderMode, // u32
    color_4u8       : u32, // bit-packed 4 u8 rgba 0..255

    // as 2 bit-packed u32 on GPU.
    corner_radius_tl : u16,
    corner_radius_tr : u16,
    corner_radius_bl : u16,
    corner_radius_br : u16,
    // As 2 bit-packed u32 on GPU.
    border_width_left  : u16,
    border_width_right : u16,
    border_width_top   : u16,
    border_width_bot   : u16,
}


UiDrawCommandRect :: struct{
    dummy : u32, // dummy
}

UiDrawCommandText :: struct{
    font_atlas_tex_binding : sdl.GPUTextureSamplerBinding,
}

UiDrawCommandSetScissors :: struct{
   rect : sdl.Rect,
}

UIDrawCommandType :: enum u32 {
    Rect,
    Text,
    SetSiccors,
}

UiDrawCommandVariant :: union #no_nil {
    UiDrawCommandRect,
    UiDrawCommandText,
    UiDrawCommandSetScissors,
}

UiDrawCommand :: struct {
    variant : UiDrawCommandVariant,
    base_instance_index : u32,
    num_instances       : u32,
}

@(private="package")
ui_get_command_type_from_variant :: proc "contextless" (variant : UiDrawCommandVariant) -> UIDrawCommandType {

    switch v in variant {
        case UiDrawCommandRect: return UIDrawCommandType.Rect;
        case UiDrawCommandText: return UIDrawCommandType.Text;
        case UiDrawCommandSetScissors: return UIDrawCommandType.SetSiccors;
    }

    return UIDrawCommandType.Rect;
}

// @Note: this can quite easily run on another thread and sync before rendering. 
@(private="package")
ui_manager_prepare_frame_draw_data_for_rendering :: proc(ui_manager : ^UiManager, gpu_device : ^sdl.GPUDevice, frame_size : [2]u32){
    ui_manager_prepare_frame_draw_data(ui_manager, frame_size);
    ui_manager_prepare_frame_gpu_buffers(ui_manager, gpu_device);
}

@(private="file")
ui_manager_prepare_frame_draw_data :: proc(ui_manager : ^UiManager, frame_size : [2]u32){

    IRI_PROFILE_PROCEDURE();

    if !ui_manager.global_ui_rendering_enabled {

        if len(ui_manager.frame_draw_commands) > 0 {
            clear(&ui_manager.frame_vert_draw_data);
            clear(&ui_manager.frame_frag_draw_data);
            clear(&ui_manager.frame_draw_commands);
        }

        return;
    }

    frame_vert_draw_data := &ui_manager.frame_vert_draw_data
    frame_frag_draw_data := &ui_manager.frame_frag_draw_data
    frame_draw_commands  := &ui_manager.frame_draw_commands

    clear(&ui_manager.frame_vert_draw_data);
    clear(&ui_manager.frame_frag_draw_data);
    clear(&ui_manager.frame_draw_commands);

    overlay_color_stack : [dynamic]clay.Color   = make_dynamic_array_len_cap([dynamic]clay.Color, 0, 16, context.temp_allocator);
    scissor_rect_stack  : [dynamic]sdl.Rect     = make_dynamic_array_len_cap([dynamic]sdl.Rect  , 0, 8, context.temp_allocator);

    clay_commands := &ui_manager.clay_render_commands;

    apply_overlay_and_pack_color :: proc "contextless" (overlay_color_stack : ^[dynamic]clay.Color, color : clay.Color) -> u32 {

        //return color;
        ONE_OVER :: 1.0 / 255.0

        interp : [4]f32 = color

        if len(overlay_color_stack) > 0 {
        
            overlay := overlay_color_stack[len(overlay_color_stack)-1];

            mix_factor : f32 = overlay.a * ONE_OVER;
            interp.rgb = linalg.lerp(color.rgb, overlay.rgb, mix_factor);
        }

        clamped : [4]f32 = linalg.clamp(interp, 0.0, 255.0);
        return transmute(u32)[4]u8{cast(u8)clamped.r, cast(u8)clamped.g, cast(u8)clamped.b, cast(u8)clamped.a};
    }


    normalize_z_index :: proc "contextless" (z_index : i16) -> f32 {

        z_index_f : f32 = cast(f32)z_index;

        depth : f32 = mathy.inv_lerp(f32(c.INT16_MIN), f32(c.INT16_MAX),z_index_f);
        return linalg.clamp(depth, 0.0, 1.0);
    }

    instance_index : u32 = 0;

    curr_z_index : i16 = cast(i16)c.INT16_MAX -1;

    clay_cmd_loop: for i in 0..<i32(clay_commands.length) {

        ren_command := clay.RenderCommandArray_Get(clay_commands, i)
        render_data := &ren_command.renderData;
        bbox := ren_command.boundingBox;

        switch ren_command.commandType {
            case .None: continue clay_cmd_loop;
            case .Rectangle: {
                
                // For now repeat this call for each rect but we really dont want this..
                // sdl.BindGPUFragmentSamplers(clay_ren_pass, 0, &ren_ctx.white_texture.binding, 1);

                rect_size := [2]f32{bbox.width, bbox.height};

                append(frame_vert_draw_data, UiRectVertDrawDataGPU{
                    position = {bbox.x, bbox.y},
                    norm_z_depth = normalize_z_index(ren_command.zIndex == 0 ? curr_z_index : ren_command.zIndex),
                    width    = cast(u16)rect_size.x,
                    height   = cast(u16)rect_size.y,
                    uv_scale = {1.0,1.0},
                });

                frag_data := UiRectFragDrawDataGPU {
                    rect_size           = rect_size,
                    mode                = .NonTexturedRect,
                    color_4u8           = apply_overlay_and_pack_color(&overlay_color_stack, render_data.rectangle.backgroundColor),
                    corner_radius_tl    = cast(u16)render_data.rectangle.cornerRadius.topLeft,
                    corner_radius_tr    = cast(u16)render_data.rectangle.cornerRadius.topRight,
                    corner_radius_bl    = cast(u16)render_data.rectangle.cornerRadius.bottomLeft, 
                    corner_radius_br    = cast(u16)render_data.rectangle.cornerRadius.bottomRight,
                }

                append(frame_frag_draw_data, frag_data);
                

                draw_command := UiDrawCommand {
                  variant =  UiDrawCommandRect{},
                  base_instance_index = instance_index,
                  num_instances = 1,
                }

                append(frame_draw_commands, draw_command);

                instance_index += 1;
                curr_z_index   -= 1;
            }
            case .Border: {

                // @Note: Detection of bordered rectangles happens inside the frag shader so we 
                // can just emit a normal rectangle command where border_width is non zero.
                border := render_data.border;

                append(frame_vert_draw_data, UiRectVertDrawDataGPU {
                    position = {bbox.x, bbox.y},
                    norm_z_depth = normalize_z_index(ren_command.zIndex == 0 ? curr_z_index : ren_command.zIndex),
                    width    = cast(u16)bbox.width,
                    height   = cast(u16)bbox.height,
                    uv_scale  = {1.0,1.0},
                });

                frag_data := UiRectFragDrawDataGPU {
                    rect_size           = {bbox.width, bbox.height},
                    color_4u8           = apply_overlay_and_pack_color(&overlay_color_stack, border.color),
                    mode                = .NonTexturedRect,
                    corner_radius_tl    = cast(u16)border.cornerRadius.topLeft,
                    corner_radius_tr    = cast(u16)border.cornerRadius.topRight,
                    corner_radius_bl    = cast(u16)border.cornerRadius.bottomLeft, 
                    corner_radius_br    = cast(u16)border.cornerRadius.bottomRight,

                    border_width_left  = border.width.left,
                    border_width_right = border.width.right,
                    border_width_top   = border.width.top,
                    border_width_bot   = border.width.bottom,
                }

                append(frame_frag_draw_data, frag_data);
                


                draw_command := UiDrawCommand {
                  variant =  UiDrawCommandRect{},
                  base_instance_index = instance_index,
                  num_instances = 1,
                }

                append(frame_draw_commands, draw_command);
                
                instance_index += 1;
                curr_z_index   -= 1;
            }
            case .Text: {

                txt_data := &ren_command.renderData.text;
                
                font_id : FontID = transmute(FontID)txt_data.fontId;
                font := ui_manager_get_font(ui_manager, font_id);

                if font == nil {
                    
                    // Draw Rectangle Enlcosing the string to indicate font is missing.

                    append(frame_vert_draw_data, UiRectVertDrawDataGPU{
                        position = {bbox.x, bbox.y},
                        norm_z_depth = normalize_z_index(ren_command.zIndex == 0 ? curr_z_index : ren_command.zIndex),
                        width    = cast(u16)bbox.width,
                        height   = cast(u16)bbox.height,
                        uv_scale  = {1.0,1.0},
                    })
                    
                    frag_data := UiRectFragDrawDataGPU {
                        color_4u8   = transmute(u32)[4]u8{255, 0.0, 255, 255}, // PINK
                        rect_size   = {bbox.width, bbox.height},
                    }
                    append(frame_frag_draw_data, frag_data)
                    

                    draw_command := UiDrawCommand {
                      variant =  UiDrawCommandRect{},
                      base_instance_index = instance_index,
                      num_instances = 1,
                    }

                    append(frame_draw_commands, draw_command);

                    instance_index += 1;
                    curr_z_index   -= 1;
                    continue clay_cmd_loop; 
                }

                engine_assert(font.altas_tex.binding.texture != nil);
                engine_assert(font.altas_tex.binding.sampler != nil);


                str := string(txt_data.stringContents.chars[0:txt_data.stringContents.length])
                                
                frag_data := UiRectFragDrawDataGPU {
                    color_4u8   = apply_overlay_and_pack_color(&overlay_color_stack, txt_data.textColor),
                    mode        = UiRectShaderMode.Text,
                }

                font_scale : f32 = f32(txt_data.fontSize) / font.info.font_size_px;
                letter_spacing : f32 = cast(f32)txt_data.letterSpacing;

                // Assuming that we calculate the bounds correctly during the measure text callback and we do the exact same here
                // then baseline should just be bbox.y + ascent_px; and this should also be true then -> bbox.y + ascent_px - decent_px = bbox.height.

                baseline : f32 = bbox.y + (font.info.ascent_px * font_scale);
                xpos     : f32 = bbox.x;

                base_index : u32 = instance_index;

                for codepoint, index in str {

                    rune_info, exists := font.rune_render_lookup[codepoint];
                    if !exists do continue; // Skip for now but maybe we should Emit something else instead..
                    
                    defer {
                        xpos += (rune_info.x_advance_px * font_scale) + letter_spacing;
                    }

                    rect_size := rune_info.size_px * font_scale;

                    append(frame_vert_draw_data, UiRectVertDrawDataGPU{
                        position  = [2]f32{xpos, baseline} + rune_info.offset_px * font_scale,
                        norm_z_depth = normalize_z_index(ren_command.zIndex == 0 ? curr_z_index : ren_command.zIndex),
                        width    = cast(u16)rect_size.x,
                        height   = cast(u16)rect_size.y,
                        uv_offset = rune_info.uv_offset, 
                        uv_scale  = rune_info.uv_scale,
                    });

                    frag_data.rect_size = rect_size;
                    append(frame_frag_draw_data, frag_data);

                    instance_index += 1;
                }

                num_glyphs_instances : u32 = instance_index - base_index;

                draw_command := UiDrawCommand {
                    variant =  UiDrawCommandText{
                        font_atlas_tex_binding = font.altas_tex.binding
                    },
                    base_instance_index = base_index,
                    num_instances = num_glyphs_instances,
                }

                append(frame_draw_commands, draw_command);

                curr_z_index -= 1;
            }
            case .Image: { // Same as Rectangle for now.
                
                append(frame_vert_draw_data, UiRectVertDrawDataGPU{
                    position = {bbox.x, bbox.y},
                    norm_z_depth = normalize_z_index(ren_command.zIndex == 0 ? curr_z_index : ren_command.zIndex),
                    width    = cast(u16)bbox.width,
                    height   = cast(u16)bbox.height,
                    uv_scale  = {1.0,1.0},
                });

               frag_data := UiRectFragDrawDataGPU {
                    rect_size           = {bbox.width, bbox.height},
                    mode                = .NonTexturedRect, 
                    color_4u8           = apply_overlay_and_pack_color(&overlay_color_stack, render_data.rectangle.backgroundColor),
                    corner_radius_tl    = cast(u16)ren_command.renderData.rectangle.cornerRadius.topLeft,
                    corner_radius_tr    = cast(u16)ren_command.renderData.rectangle.cornerRadius.topRight,
                    corner_radius_bl    = cast(u16)ren_command.renderData.rectangle.cornerRadius.bottomLeft, 
                    corner_radius_br    = cast(u16)ren_command.renderData.rectangle.cornerRadius.bottomRight,
                }
                append(frame_frag_draw_data, frag_data);                

                draw_command := UiDrawCommand {
                  variant =  UiDrawCommandRect{},
                  base_instance_index = instance_index,
                  num_instances = 1,
                }

                append(frame_draw_commands, draw_command);

                instance_index += 1;
                curr_z_index -= 1;
            }
            case .ScissorStart: {                
                // @Note: I think technically we have to consider if we should only clip vertically or horzontally. buut.. tbh fuck that.

                scissor_rect := sdl.Rect{x = cast(i32)bbox.x, y = cast(i32)bbox.y, w = cast(i32)bbox.width, h = cast(i32)bbox.height}
                
                scis_draw_command := UiDrawCommand {
                  variant =  UiDrawCommandSetScissors{
                     rect = scissor_rect,
                  },
                }

                append(frame_draw_commands, scis_draw_command)
                append(&scissor_rect_stack, scissor_rect)
            }
            case .ScissorEnd: {

                pop(&scissor_rect_stack)
                
                if len(scissor_rect_stack) > 0 {
                    
                    scis_draw_command := UiDrawCommand {
                      variant =  UiDrawCommandSetScissors{
                         rect = scissor_rect_stack[len(scissor_rect_stack) - 1],
                      },
                    }
                    append(frame_draw_commands, scis_draw_command)

                } else {
                    // Nothing on the stack .. Return to whole screen.
                    scis_draw_command := UiDrawCommand {
                      variant =  UiDrawCommandSetScissors{
                         rect = sdl.Rect{x = 0, y = 0, w = cast(i32)frame_size.x, h = cast(i32)frame_size.y},
                      },
                    }
                    append(frame_draw_commands, scis_draw_command)
                }
            }
            case .OverlayColorStart: append(&overlay_color_stack, ren_command.renderData.overlayColor.color);
            case .OverlayColorEnd:   pop(&overlay_color_stack);                
            case .Custom:
        }


        cmd_type := ren_command.commandType;
        was_instancable_command : bool = cmd_type == .Rectangle || cmd_type == .Border || cmd_type == .Text || cmd_type == .Image;

        try_instance: if was_instancable_command && len(frame_draw_commands) >= 2 {

            last_cmd := &frame_draw_commands[len(frame_draw_commands) - 2];
            last_type := ui_get_command_type_from_variant(last_cmd.variant);

            this_cmd := &frame_draw_commands[len(frame_draw_commands) - 1];
            this_type := ui_get_command_type_from_variant(this_cmd.variant);

            // Siccors must go through.
            if last_type == .SetSiccors {
                break try_instance;
            }

            // This also should go for images which we dont have yet.
            if this_type == .Text && last_type != .Text {
                // We must set the atlas texture to use.
                break try_instance;
            }

            if this_type == .Text && last_type == .Text {
                // mem compare the variants to see if they use different font_atlas/sampler
                if this_cmd.variant != last_cmd.variant{
                    break try_instance;
                }
            }

            //if this_cmd.variant == last_cmd.variant {
                last_cmd.num_instances += this_cmd.num_instances;
                pop(frame_draw_commands)
            //}
        }

    }


    engine_assert(len(ui_manager.frame_frag_draw_data) == len(ui_manager.frame_vert_draw_data))
}

@(private="file")
ui_manager_prepare_frame_gpu_buffers :: proc(ui_manager : ^UiManager, gpu_device : ^sdl.GPUDevice) {

    IRI_PROFILE_PROCEDURE();

    // if buffer need to get larger, how much do we grow them.
    BUFFER_GROW_PERCENTAGE :: 10.0
    
    //
    // - Vertex Buffer
    //
    vert_buffer: {

        num_elements : int = len(ui_manager.frame_vert_draw_data)

        gpu_buf := &ui_manager.frame_vert_draw_data_gpu_buf;

        element_byte_size     : int = size_of(UiRectVertDrawDataGPU)
        required_gpu_buf_size : int = num_elements * element_byte_size;
        curr_gpu_buf_size     : int = cast(int)gpu_buf.curr_byte_size

        size_got_bigger     : bool = required_gpu_buf_size > curr_gpu_buf_size
        size_shrank_in_half : bool = required_gpu_buf_size < (curr_gpu_buf_size / 2)
        size_shrank_to_zero : bool = required_gpu_buf_size == 0

        reallocate_gpu_buffer : bool = size_got_bigger || size_shrank_in_half || size_shrank_to_zero;

        if reallocate_gpu_buffer {

            new_byte_size : int = required_gpu_buf_size;

            if size_got_bigger {

                new_byte_size = required_gpu_buf_size +  cast(int)(f64(required_gpu_buf_size) * (1.0 / BUFFER_GROW_PERCENTAGE))
            }

            // @Note: Sply frees buffer if byte size is 0
            gpu_buffer_reallocate_buffers(gpu_device, gpu_buf, cast(u32)new_byte_size, {.GRAPHICS_STORAGE_READ});
        }

        upload_info  := &gpu_buf.upload_info;
        if !size_shrank_to_zero {
            // Upload Everything
            upload_info.requires_upload = true;
            upload_info.region_min_index = 0;
            upload_info.region_max_index = num_elements - 1;
        } else {
            upload_info.requires_upload = false;
            upload_info.region_min_index = 0;
            upload_info.region_max_index = 0;

            break vert_buffer;    
        }

        gpu_buffer_memcopy_upload_info_min_max_region_to_transfer_buffer(gpu_device, gpu_buf, &ui_manager.frame_vert_draw_data[0], element_byte_size, cycle = true);
    }

    //
    // - Fragment Buffer
    //
    frag_buffer: {

        num_elements : int = len(ui_manager.frame_frag_draw_data)

        gpu_buf := &ui_manager.frame_frag_draw_data_gpu_buf;

        element_byte_size     : int = size_of(UiRectFragDrawDataGPU)
        required_gpu_buf_size : int = num_elements * element_byte_size;
        curr_gpu_buf_size     : int = cast(int)gpu_buf.curr_byte_size

        size_got_bigger     : bool = required_gpu_buf_size > curr_gpu_buf_size
        size_shrank_in_half : bool = required_gpu_buf_size < (curr_gpu_buf_size / 2)
        size_shrank_to_zero : bool = required_gpu_buf_size == 0

        reallocate_gpu_buffer : bool = size_got_bigger || size_shrank_in_half || size_shrank_to_zero;

        if reallocate_gpu_buffer {

            new_byte_size : int = required_gpu_buf_size;

            if size_got_bigger {

                new_byte_size = required_gpu_buf_size +  cast(int)(f64(required_gpu_buf_size) * (1.0 / BUFFER_GROW_PERCENTAGE))
            }

            // @Note: Sply frees buffer if byte size is 0
            gpu_buffer_reallocate_buffers(gpu_device, gpu_buf, cast(u32)new_byte_size, {.GRAPHICS_STORAGE_READ});
        }

        upload_info  := &gpu_buf.upload_info;
        if !size_shrank_to_zero {
            // Upload Everything
            upload_info.requires_upload = true;
            upload_info.region_min_index = 0;
            upload_info.region_max_index = num_elements - 1;
        } else {
            upload_info.requires_upload = false;
            upload_info.region_min_index = 0;
            upload_info.region_max_index = 0;

            break frag_buffer;    
        }

        gpu_buffer_memcopy_upload_info_min_max_region_to_transfer_buffer(gpu_device, gpu_buf, &ui_manager.frame_frag_draw_data[0], element_byte_size, cycle = true);
    }
}