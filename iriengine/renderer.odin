package iri

import "core:log"
import "core:mem"
import "core:c"
import "core:math/linalg"
import "odinary:mathy"

import sdl "vendor:sdl3"

import "core:math/rand"

@(private="package")
RenderContext :: struct {

    // Note: it is the renderers job to ensure that all render pass infos are correctly setup
    render_pass_infos: [RenderPassType]RenderPassInfo,

    geo_depth_stencil_target_tex : ^sdl.GPUTexture,
    geo_color_target_tex : ^sdl.GPUTexture,   
    geo_color_target_sampler: ^sdl.GPUSampler,

    brdf_lut : Texture2D,
    dummy_cubemap : TextureCube,
    white_texture : Texture2D,
    
    // A depth texture for each mip level that we support for shadowmap rendering.
    shadowmap_depth_textures : [dynamic]^sdl.GPUTexture,

    min_max_depth : ^sdl.GPUTexture,
    //gtao_tex : ^sdl.GPUTexture, 

    debug_gui_color_format : RenderTargetFormat, // hardcoded and non changable by users
    debug_gui_color_target_tex: ^sdl.GPUTexture,
    debug_gui_color_target_sampler: ^sdl.GPUSampler,



    post_correct_color_target_sampler: ^sdl.GPUSampler,
    post_correct_color_target_tex : ^sdl.GPUTexture,

    sampler_linear_mip_nearest_clamp : ^sdl.GPUSampler,


    nearest_depth_sampler: ^sdl.GPUSampler,    
    linear_depth_sampler: ^sdl.GPUSampler,

    global_vertex_ubo : GlobalVertexUBO,

    global_fragment_buffer : GlobalFragmentBuffer,
    global_fragment_gpu_buffer : ^sdl.GPUBuffer,
    global_fragment_transfer_buffer : ^sdl.GPUTransferBuffer,

    prim_icosphere  : ^Primitive,




    current_frame_size      : [2]u32,
    current_swapchain_size  : [2]u32,

    config : RenderConfig,
    effects : RenderEffectsData,
    
    debug_config : RenderDebugConfig
}


RenderConfig :: struct {
    ren_effect_flags : RenderingEffectFlags,
    geo_depth_stencil_format : DepthStencilFormat, // triggers pipeline rebuilds
    geo_color_target_format  : RenderTargetFormat, // triggers pipeline rebuilds
    //post_correct_color_target_format : RenderTargetFormat, // triggers pipeline rebuilds
    render_resolution : RenderResolution,
}

RENDER_PASS_SET_ALL :: RenderPassSet{.Main,.DebugGui,.PostColorCorrect,.SWAPCHAIN_COMPOSIT,.DEPTH_PREPASS, .SHADOWMAP, .SMAA};
RenderPassSet :: bit_set[RenderPassType]
RenderPassType :: enum {
    // @NOTE: When adding new passes dont forget to add them to the bit set all above
    Main,
    DebugGui,
    PostColorCorrect,
    SWAPCHAIN_COMPOSIT,
    DEPTH_PREPASS,
    SHADOWMAP,
    SMAA,
}

RenderPassInfo :: struct {
    has_color_target: bool,
    has_depth_target: bool,
    color_target_format: RenderTargetFormat,
    depth_target_format: DepthStencilFormat,
}

RenderDebugConfig :: struct  {
    // TODO: can make this into flags..
    draw_bounding_box : bool,
    draw_bounding_box_axis_aligned : bool,
    draw_camera_frustum_box : bool, // render frustum of a camera as wireframe box if the frustum culling camera was set in universe to not be the main camera
}

renderer_debug_config_create_default :: proc() -> RenderDebugConfig {
    return RenderDebugConfig{
        draw_bounding_box = false,
        draw_bounding_box_axis_aligned = false,
        draw_camera_frustum_box = false,
    }
}


@(private="package")
renderer_recreate_all_render_targets :: proc(ren_ctx : ^RenderContext, gpu_device: ^sdl.GPUDevice) {

    config := ren_ctx.config;
    frame_size := ren_ctx.current_frame_size;

    // debug gui
    if(ren_ctx.debug_gui_color_target_tex != nil){
        sdl.ReleaseGPUTexture(gpu_device, ren_ctx.debug_gui_color_target_tex);
        ren_ctx.debug_gui_color_target_tex = nil;
    }
    ren_ctx.debug_gui_color_target_tex = renderer_create_render_target_texture(gpu_device, ren_ctx.current_swapchain_size, ren_ctx.debug_gui_color_format, MSAA.OFF, {.COLOR_TARGET,.SAMPLER});
    
    // post texture

    post_correct_target_format := RenderTargetFormat.RGBA8_SRGB; // Hardcoded, if change here remember to change in init function too.

    if(ren_ctx.post_correct_color_target_tex != nil){
        sdl.ReleaseGPUTexture(gpu_device,ren_ctx.post_correct_color_target_tex);
        ren_ctx.post_correct_color_target_tex = nil;
    }
    ren_ctx.post_correct_color_target_tex = renderer_create_render_target_texture(gpu_device, frame_size, post_correct_target_format, MSAA.OFF, {.COLOR_TARGET,.SAMPLER});


    // depth stencil
    if(ren_ctx.geo_depth_stencil_target_tex != nil){
        sdl.ReleaseGPUTexture(gpu_device, ren_ctx.geo_depth_stencil_target_tex);
        ren_ctx.geo_depth_stencil_target_tex = nil;
    }
    ren_ctx.geo_depth_stencil_target_tex = renderer_create_depth_stencil_texture(gpu_device, frame_size, config.geo_depth_stencil_format, MSAA.OFF, {.DEPTH_STENCIL_TARGET, .SAMPLER});
    

    // min-max depth pyramid
    if(ren_ctx.min_max_depth != nil){
        sdl.ReleaseGPUTexture(gpu_device, ren_ctx.min_max_depth);
        ren_ctx.min_max_depth = nil;
    }
    ren_ctx.min_max_depth = texture_create_2D(gpu_device, frame_size, sdl.GPUTextureFormat.R32G32_FLOAT, true, {.SAMPLER, .COMPUTE_STORAGE_READ, .COMPUTE_STORAGE_WRITE});


    // release color target & color msaa resole
    if ren_ctx.geo_color_target_tex != nil {
        sdl.ReleaseGPUTexture(gpu_device, ren_ctx.geo_color_target_tex);
        ren_ctx.geo_color_target_tex = nil;
    }

    ren_ctx.geo_color_target_tex = renderer_create_render_target_texture(gpu_device, frame_size, config.geo_color_target_format, MSAA.OFF, {.COLOR_TARGET,.SAMPLER});

    render_effects_reinit(gpu_device, &ren_ctx.effects, ren_ctx.config.ren_effect_flags, frame_size);
}


@(private="package")
renderer_init :: proc(ren_ctx : ^RenderContext, gpu_device: ^sdl.GPUDevice, window_size : [2]u32) {

    engine_assert(ren_ctx != nil);

    ren_ctx.debug_gui_color_format = RenderTargetFormat.RGBA8_SRGB;

    // Setup Default Render Config
    ren_ctx.config = renderer_render_config_create_default();

    // debug cofnig
    ren_ctx.debug_config = renderer_debug_config_create_default();


    // Setup initial render pass infos, 
    // Doing a for loop + switch here so i get missing switch-case compile error when adding new pass types and forgetting to set it up here.
    for pass_type in RenderPassType {

        // NOTE: 
        // We have to take care here when changing things, some passes may use the same color/depth targets to render to
        // for example 'DebugGui' renders into the same Color target as 'Main' but doesn't use a depth target therefore when we initially set this up 

        pass_info : RenderPassInfo;

        switch pass_type {
            case .Main:
                pass_info.has_color_target = true;
                pass_info.color_target_format = ren_ctx.config.geo_color_target_format;
                pass_info.has_depth_target = true;
                pass_info.depth_target_format = ren_ctx.config.geo_depth_stencil_format;
            
            case .DebugGui:
                pass_info.has_color_target = true;
                pass_info.color_target_format = ren_ctx.debug_gui_color_format;
                pass_info.has_depth_target = false;

            case .PostColorCorrect:
                pass_info.has_color_target = true;
                pass_info.color_target_format = RenderTargetFormat.RGBA8_SRGB; // Hardcoded, if change here remember to change in recreate_all_rendertargets() too.
                pass_info.has_depth_target = false;
                pass_info.depth_target_format = ren_ctx.config.geo_depth_stencil_format;

            case .SWAPCHAIN_COMPOSIT:
                pass_info.has_color_target = true;
                pass_info.color_target_format =   RenderTargetFormat.SWAPCHAIN;
                pass_info.has_depth_target = false;

            case .DEPTH_PREPASS:
                pass_info.has_depth_target = true;
                //pass_info.depth_target_format = DepthStencilFormat.D32_FLOAT;
                pass_info.depth_target_format = ren_ctx.config.geo_depth_stencil_format;
                pass_info.has_color_target = false;
                //pass_info.color_target_format = RenderTargetFormat.RGBA32_FLOAT;
            case .SHADOWMAP:
                pass_info.has_depth_target = true;
                pass_info.depth_target_format = DepthStencilFormat.D32_FLOAT;
                pass_info.has_color_target = true;
                pass_info.color_target_format = RenderTargetFormat.R32_FLOAT;
            case .SMAA:
                pass_info.has_depth_target = false;
                pass_info.has_color_target = true;
                pass_info.color_target_format = RenderTargetFormat.RGBA8_UNORM;

        }
    
        ren_ctx.render_pass_infos[pass_type] = pass_info;
    }

    ren_ctx.current_swapchain_size = window_size;
    ren_ctx.current_frame_size = renderer_calculate_frame_size_from_swapchain_size(window_size, ren_ctx.config.render_resolution);

    ren_ctx.prim_icosphere = primitive_create_uniticosphere(gpu_device);


    ren_ctx.dummy_cubemap = texture_cube_create_basic(gpu_device, 128, .R8G8B8A8_UNORM);

    // Create sampelrs
    basic_sampler_ci : sdl.GPUSamplerCreateInfo = {
        min_filter      = sdl.GPUFilter.LINEAR,
        mag_filter      = sdl.GPUFilter.LINEAR,
        mipmap_mode     = sdl.GPUSamplerMipmapMode.NEAREST,
        address_mode_u  = sdl.GPUSamplerAddressMode.REPEAT,
        address_mode_v  = sdl.GPUSamplerAddressMode.REPEAT,
        address_mode_w  = sdl.GPUSamplerAddressMode.REPEAT,
        enable_compare = false,
    };

    ren_ctx.geo_color_target_sampler = sdl.CreateGPUSampler(gpu_device, basic_sampler_ci);
    ren_ctx.post_correct_color_target_sampler = sdl.CreateGPUSampler(gpu_device, basic_sampler_ci);
    ren_ctx.debug_gui_color_target_sampler = sdl.CreateGPUSampler(gpu_device, basic_sampler_ci); // its the same sampler basically

    ren_ctx.linear_depth_sampler  = texture_create_sampler(gpu_device, .LINEAR  , .NEAREST,  .CLAMP_TO_EDGE);
    ren_ctx.nearest_depth_sampler = texture_create_sampler(gpu_device, .NEAREST , .NEAREST,  .CLAMP_TO_EDGE);

    ren_ctx.sampler_linear_mip_nearest_clamp  = texture_create_sampler(gpu_device, .LINEAR  , .NEAREST,  .CLAMP_TO_EDGE);


    // Shadowmap Depth Textures.
    for resolution_enum in ShadowmapResolution {
        res : u32 = cast(u32)resolution_enum;
        shadowmap_size : [2]u32 = {res, res};
        depth_tex := renderer_create_depth_stencil_texture(gpu_device, shadowmap_size, .D32_FLOAT, MSAA.OFF, {.DEPTH_STENCIL_TARGET});
        append(&ren_ctx.shadowmap_depth_textures, depth_tex);
    }


    {
        buf_ci := sdl.GPUBufferCreateInfo{
            usage = sdl.GPUBufferUsageFlags{.GRAPHICS_STORAGE_READ},
            size = size_of(GlobalFragmentBuffer),
        }

        transfer_buf_ci := sdl.GPUTransferBufferCreateInfo{
                usage = sdl.GPUTransferBufferUsage.UPLOAD,
                size = size_of(GlobalFragmentBuffer),
        }
        ren_ctx.global_fragment_gpu_buffer = sdl.CreateGPUBuffer(gpu_device, buf_ci)
        ren_ctx.global_fragment_transfer_buffer = sdl.CreateGPUTransferBuffer(gpu_device, transfer_buf_ci)
    }

    render_effects_reinit(gpu_device, &ren_ctx.effects, ren_ctx.config.ren_effect_flags, ren_ctx.current_frame_size);
}

@(private="package")
renderer_setup :: proc(ren_ctx : ^RenderContext, gpu_device: ^sdl.GPUDevice){

    renderer_recreate_all_render_targets(ren_ctx, gpu_device);


    // Create BRDF LUT
    {
        brdf_lut_res : u32 = 512;

        brdf_tex_2D : Texture2D;
        brdf_tex_2D.format = .R16G16_FLOAT;
        brdf_tex_2D.num_mipmaps = 0;
        brdf_tex_2D.size = [2]u32{brdf_lut_res,brdf_lut_res};

        brdf_tex_2D.binding.texture = texture_create_2D(gpu_device,  brdf_tex_2D.size , .R16G16_FLOAT , false , sdl.GPUTextureUsageFlags{.SAMPLER,.COMPUTE_STORAGE_WRITE});
        brdf_tex_2D.binding.sampler = texture_create_sampler(gpu_device, .LINEAR , .LINEAR,  .CLAMP_TO_EDGE);
    
        ren_ctx.brdf_lut = brdf_tex_2D;
    }

    ren_ctx.white_texture = texture_2D_create_basic(gpu_device, {512,512}, .R8G8B8A8_UNORM, true);


    cmd_buf := sdl.AcquireGPUCommandBuffer(gpu_device);

    renderer_setup_render_brdf_lut(cmd_buf, &ren_ctx.brdf_lut);


    renderer_clear_texture(cmd_buf, ren_ctx.white_texture.binding.texture, [4]f32{1.0, 1.0,1.0,1.0}, true);

    ok := sdl.SubmitGPUCommandBuffer(cmd_buf);
    engine_assert(ok);

    ok = sdl.WaitForGPUIdle(gpu_device);
    engine_assert(ok);
}


@(private="package")
renderer_deinit :: proc(ren_ctx : ^RenderContext, gpu_device: ^sdl.GPUDevice) {


    primitive_destroy(gpu_device, ren_ctx.prim_icosphere);
    free(ren_ctx.prim_icosphere);

    render_effects_deinit_and_destroy(ren_ctx, gpu_device, ren_ctx.config.ren_effect_flags);

    sdl.ReleaseGPUSampler(gpu_device, ren_ctx.geo_color_target_sampler);
    sdl.ReleaseGPUSampler(gpu_device, ren_ctx.debug_gui_color_target_sampler);
    sdl.ReleaseGPUSampler(gpu_device, ren_ctx.sampler_linear_mip_nearest_clamp);

    sdl.ReleaseGPUTexture(gpu_device, ren_ctx.geo_color_target_tex);
    sdl.ReleaseGPUTexture(gpu_device, ren_ctx.geo_depth_stencil_target_tex);
    sdl.ReleaseGPUTexture(gpu_device, ren_ctx.debug_gui_color_target_tex);
    sdl.ReleaseGPUTexture(gpu_device, ren_ctx.post_correct_color_target_tex);

    texture_2D_destroy(gpu_device, &ren_ctx.brdf_lut, false);
    texture_cube_destroy(gpu_device, &ren_ctx.dummy_cubemap, false);

    sdl.ReleaseGPUBuffer(gpu_device, ren_ctx.global_fragment_gpu_buffer);
    sdl.ReleaseGPUTransferBuffer(gpu_device, ren_ctx.global_fragment_transfer_buffer)

    for i in 0..<len(ren_ctx.shadowmap_depth_textures){
        sdl.ReleaseGPUTexture(gpu_device, ren_ctx.shadowmap_depth_textures[i]);
    }
    delete(ren_ctx.shadowmap_depth_textures);
}

@(private="package")
renderer_draw_frame :: proc(ren_ctx : ^RenderContext, window: ^WindowContext, universe : ^Universe) {

    mesh_manager := engine.mesh_manager;
    gpu_device: ^sdl.GPUDevice = window.gpu_device;
    pipe_manager : ^PipelineManager = engine.pipeline_manager;

    // Get a refrence to the ecs
    ecs : ^EntityComponentData = &universe.ecs;

    frame_size : [2]u32 = ren_ctx.current_frame_size;
    frame_aspect_ratio : f32 = cast(f32)frame_size.x / cast(f32)frame_size.y;

    camera_info := &universe.frame_camera_info;

    // Update global uniform buffer objects
    ren_ctx.global_vertex_ubo.view_mat = camera_info.view_mat;
    ren_ctx.global_vertex_ubo.proj_mat = camera_info.proj_mat;
    ren_ctx.global_vertex_ubo.view_proj_mat = camera_info.view_proj_mat;

    ren_ctx.global_fragment_buffer.camera_pos_ws = camera_info.position_ws;
    ren_ctx.global_fragment_buffer.camera_dir_ws = camera_info.direction_ws;
    //ren_ctx.global_fragment_buffer.inv_view_proj_mat  = camera_info.inv_view_proj_mat;

    ren_ctx.global_fragment_buffer.time_seconds = clock_get_elapsed_time();
    ren_ctx.global_fragment_buffer.frame_size = frame_size;

    ren_ctx.global_fragment_buffer.near_plane = camera_info.near_plane;
    ren_ctx.global_fragment_buffer.far_plane = camera_info.far_plane;

    ren_ctx.global_fragment_buffer.cascade_frust_split_1 = universe.shadow_cascade_split_1;
    ren_ctx.global_fragment_buffer.cascade_frust_split_2 = universe.shadow_cascade_split_2;
    ren_ctx.global_fragment_buffer.cascade_frust_split_3 = universe.shadow_cascade_split_3;
    ren_ctx.global_fragment_buffer.camera_exposure = camera_info.camera_exposure;

    // reset debug counters
    // ren_ctx.debug_counters = RenderDebugCounters{};

    debug_config := &ren_ctx.debug_config;
    perfs := get_performance_counters();

    // ============================================================================================================
    // COPY DATA PASS
    // ============================================================================================================
    {

        upload_cmd_buf := sdl.AcquireGPUCommandBuffer(gpu_device);    
        engine_assert(upload_cmd_buf != nil);

        renderer_push_debug_group(upload_cmd_buf, "Data Upload Command Buffer");
        // ============================================================================================================
        // Query Data uploads and perform transfer buffer updates
        // ============================================================================================================
        
        mats_requires_upload_unlit, mats_transfer_buf_loc_unlit, mats_buf_region_unlit := material_register_query_material_upload_for_type(gpu_device, MaterialShaderType.UNLIT);
        mats_requires_upload_pbr  , mats_transfer_buf_loc_pbr  , mats_buf_region_pbr   := material_register_query_material_upload_for_type(gpu_device, MaterialShaderType.PBR);
        skybox_requires_upload, skybox_transfer_buf_loc, skybox_buf_region := universe_query_skybox_buffer_upload(gpu_device, universe);

        // NOTE: We want to perform data uploads as early in the frame as possible.
        copy_pass :  ^sdl.GPUCopyPass = sdl.BeginGPUCopyPass(upload_cmd_buf);



        // Global Fragment Buffer
        {

            data : rawptr = sdl.MapGPUTransferBuffer(gpu_device, ren_ctx.global_fragment_transfer_buffer, true);
            mem.copy(data, &ren_ctx.global_fragment_buffer, size_of(GlobalFragmentBuffer));
            sdl.UnmapGPUTransferBuffer(gpu_device, ren_ctx.global_fragment_transfer_buffer);

            transfer_buf_location := sdl.GPUTransferBufferLocation {
                transfer_buffer = ren_ctx.global_fragment_transfer_buffer,
                offset = 0,
            }

            buf_region := sdl.GPUBufferRegion {
                buffer = ren_ctx.global_fragment_gpu_buffer,
                offset = 0,
                size = cast(u32)size_of(GlobalFragmentBuffer),
            }


            // @Note: here we can/should actually cycle because we resubmit this every frame.
            sdl.UploadToGPUBuffer(copy_pass, transfer_buf_location, buf_region, cycle = true); 
        }

        // Matrix buffer

        if universe.matrix_upload_info.requires_upload {
            sdl.UploadToGPUBuffer(copy_pass, universe.matrix_upload_info.transfer_buf_location, universe.matrix_upload_info.transfer_buf_region, cycle = false);
        }


        // light buffers
        {
            light_manager := &universe.light_manager;
            lights_upload_info := light_manager.gpu_lights_upload_info;
            dir_shadowmap_upload_info := light_manager.gpu_dir_lights_shadowmap_infos_upload_info;
            shadowmap_upload_info := light_manager.gpu_shadowmap_infos_upload_info;

            if(lights_upload_info.requires_upload) {                
                //log.debugf("Upload to lights buffer");
                sdl.UploadToGPUBuffer(copy_pass, lights_upload_info.transfer_buf_location, lights_upload_info.transfer_buf_region, false);
            }

            
            if shadowmap_upload_info.requires_upload {
                //log.debugf("Upload to Shadowmap buffer");
                sdl.UploadToGPUBuffer(copy_pass, shadowmap_upload_info.transfer_buf_location , shadowmap_upload_info.transfer_buf_region, false);
            }

            //seperate upload call for directional lights shadowmaps because we need to upload it every frame pretty much
            //unleass there are no directional lights.
            if dir_shadowmap_upload_info.requires_upload {                
                //log.debugf("Upload to DIRECTIONAL Shadowmap buffer");
                sdl.UploadToGPUBuffer(copy_pass, dir_shadowmap_upload_info.transfer_buf_location , dir_shadowmap_upload_info.transfer_buf_region, false);
            }
        }

        // Upload changed material data
        if mats_requires_upload_unlit {
            sdl.UploadToGPUBuffer(copy_pass, mats_transfer_buf_loc_unlit, mats_buf_region_unlit, false);
        }

        if mats_requires_upload_pbr {
            sdl.UploadToGPUBuffer(copy_pass, mats_transfer_buf_loc_pbr, mats_buf_region_pbr, false);
        }

        if skybox_requires_upload {
            sdl.UploadToGPUBuffer(copy_pass, skybox_transfer_buf_loc, skybox_buf_region, false);
        }

        sdl.EndGPUCopyPass(copy_pass);


        // @Note: Imgui has its own copy pass but we still want to perform our data upload early in the frame.
        if debug_gui_is_enabled() {
            debug_gui_prepare_and_upload_draw_data(upload_cmd_buf);
        }


        renderer_pop_debug_group(upload_cmd_buf);

        upload_cmd_buf_ok := sdl.SubmitGPUCommandBuffer(upload_cmd_buf);
        engine_assert(upload_cmd_buf_ok);
    }


    cmd_buf := sdl.AcquireGPUCommandBuffer(gpu_device);    
    engine_assert(cmd_buf != nil);

    swapchain_texture : ^sdl.GPUTexture;
    swapchain_tex_size : [2]u32;
    swapchain_ok := sdl.WaitAndAcquireGPUSwapchainTexture(cmd_buf, window.handle, &swapchain_texture, &swapchain_tex_size.x, &swapchain_tex_size.y);
    
    // just wait and dont do any rendering, its likely that the window was just minimized
    if !swapchain_ok || swapchain_texture == nil {
        log.errorf("Renderer failed to aquire swapchain texture: {}", sdl.GetError());
        return;
    }

    if swapchain_tex_size != ren_ctx.current_swapchain_size {

        // unfortunatly updated size will happen one frame late because we already submitted the upload command buffer
        engine_assert(swapchain_tex_size.x > 0 && swapchain_tex_size.y > 0);

        ren_ctx.current_swapchain_size = swapchain_tex_size;
        ren_ctx.current_frame_size = renderer_calculate_frame_size_from_swapchain_size(swapchain_tex_size, ren_ctx.config.render_resolution);
        renderer_recreate_all_render_targets(ren_ctx, gpu_device);


        frame_size = ren_ctx.current_frame_size;
        frame_aspect_ratio = cast(f32)frame_size.x / cast(f32)frame_size.y;
    }

    draw_depthonly_drawable_index_array :: proc(cmd_buf : ^sdl.GPUCommandBuffer, 
                                                render_pass : ^sdl.GPURenderPass, 
                                                drawable_index_array : ^[dynamic]u32, 
                                                pipe_manager : ^PipelineManager,
                                                mesh_manager : ^MeshManager,
                                                universe : ^Universe,
                                                depthonly_shader_type : DepthOnlyPipelineShaders) -> (num_draw_calls : u32, num_pipeline_switches : u32)
    {

        last_pipeline_variant : ^sdl.GPUGraphicsPipeline = nil;

        // Draw all opaque geometry
        for drawable_index in drawable_index_array {
            
            mesh_id := universe.ecs.drawables[drawable_index].mesh_instance.mesh_id;
            mat_id  := universe.ecs.drawables[drawable_index].mesh_instance.mat_id;

            technique_hash := material_register_get_render_technique_hash(mat_id);

            pipeline_variant := pipe_manager_get_depthonly_pipeline_variant(pipe_manager, depthonly_shader_type, technique_hash);
            engine_assert(pipeline_variant != nil);
            
            if pipeline_variant != last_pipeline_variant {
                sdl.BindGPUGraphicsPipeline(render_pass, pipeline_variant);
                last_pipeline_variant = pipeline_variant;
                num_pipeline_switches += 1;
            }
            
            mesh_gpu_data := mesh_manager_get_mesh_gpu_data(mesh_manager,mesh_id);

            draw_instance_ubo := VertexDrawInstanceUBO{
                drawable_index = cast(u32)drawable_index,
            }

            sdl.PushGPUVertexUniformData(cmd_buf, 1, &draw_instance_ubo, size_of(VertexDrawInstanceUBO) );
            
            renderer_DRAW_CALL_draw_mesh_instance_gpu_data(render_pass, mesh_gpu_data, only_position_buf = true);
            

            num_draw_calls += 1;
        }

        return num_draw_calls, num_pipeline_switches;
    }

    // Idk not ideal ?
    any_draws_exist : bool = len(universe.ecs.drawables) > 0 ;

    // ============================================================================================================
    //                                      DEPTH PRE PASS
    // ============================================================================================================
    
    {
        renderer_push_debug_group(cmd_buf, "Depth Pre Pass");
        defer renderer_pop_debug_group(cmd_buf);

        timer := timer_begin()
        defer perfs.depth_prepass_cpu_ms = timer_end_get_miliseconds(timer);
        perfs.depth_prepass_drawcalls = 0;
        perfs.depth_prepass_num_pipeline_switches = 0;
        
        depth_pre_depth_stencil_target_info : sdl.GPUDepthStencilTargetInfo = sdl.GPUDepthStencilTargetInfo {
            texture     = ren_ctx.geo_depth_stencil_target_tex,
            clear_depth = 1,                        // The value to clear the depth component with
            load_op     = sdl.GPULoadOp.CLEAR,
            store_op    = sdl.GPUStoreOp.STORE,
            
            stencil_load_op = sdl.GPULoadOp.CLEAR,
            stencil_store_op = sdl.GPUStoreOp.STORE,
            cycle = false,         // true cycles the texture if the texture is bound and any load ops are not LOAD */
            clear_stencil = 0,        // The value to clear the stencil component to at the beginning of the render pass. Ignored if GPU_LOADOP_CLEAR is not used. */
        }

        depth_pre_pass : ^sdl.GPURenderPass = sdl.BeginGPURenderPass(cmd_buf, nil, 0, &depth_pre_depth_stencil_target_info);        
        
        if any_draws_exist {

            sdl.PushGPUVertexUniformData(cmd_buf, 0, &ren_ctx.global_vertex_ubo, size_of(GlobalVertexUBO));
            
            // TODO: maybe we should have matrix buffer have always one identity matrix as first index.
            // otherwise if its nil here we crash on this call. but if we dont bind anything we also crash at least in validation mode.
            sdl.BindGPUVertexStorageBuffers(depth_pre_pass, 0, &universe.matrix_buf, 1);
            

            draws, switches := draw_depthonly_drawable_index_array(cmd_buf, depth_pre_pass, &universe.frame_opaques   , pipe_manager, mesh_manager, universe, .DepthPre);
            perfs.depth_prepass_drawcalls += draws;
            perfs.depth_prepass_num_pipeline_switches += switches;
            draws, switches = draw_depthonly_drawable_index_array(cmd_buf, depth_pre_pass, &universe.frame_alpha_test, pipe_manager, mesh_manager, universe, .DepthPreAlphaTest);
            perfs.depth_prepass_drawcalls += draws;
            perfs.depth_prepass_num_pipeline_switches += switches;

        }
        sdl.EndGPURenderPass(depth_pre_pass);
    }



    // ============================================================================================================
    //                                      MIN MAX DEPTH HIERARCHY
    // ============================================================================================================

    // Build a min max depth hierarchy recursivly
    // the min max depth texture has same base resolution as the framesize so for the first
    // iteration we will just perform a copy from the depth stencil target.
    // otherwise we use the previous mip level to construct a min and max depth for the current mip level
    {
        renderer_push_debug_group(cmd_buf, "MinMax Depth Compute");
        defer renderer_pop_debug_group(cmd_buf);

        // ubo layout in shader
        MinMaxDepthHierary_UBO :: struct {
                _src_dimentions  : [2]u32,
                _dest_dimentions : [2]u32,
                _dest_mip_level : u32,
                _padding1       : u32,
                _padding2       : u32,
                _padding3       : u32,
        }

        ubo : MinMaxDepthHierary_UBO;

        // The first is src mip (high resolution) the second is dest mip (lower resolution)
        storage_rw_bindings : [2]sdl.GPUStorageTextureReadWriteBinding = {
            {  texture = ren_ctx.min_max_depth , mip_level = 0},
            {  texture = ren_ctx.min_max_depth , mip_level = 0}
        }


        compute_pipeline , thread_count := get_compute_pipeline(.MIN_MAX_DEPTH_HIERARCHY);
        
        // The first pass will esentially jut do a copy into mip_level 0 at same resolution

        curr_src_dimentions  : [2]u32 = frame_size;
        curr_dest_dimentions : [2]u32 = frame_size;

        pyramid_depth : u32 = 5; // how deep do we want to perform the pyramid

        for dest_mip_level in 0..<pyramid_depth {


            // @Note - fulcrum
            // In the case of the first iteration. We will not read from src mip and instead 
            // perform a copy from the actual depth buffer.
            // so src_mip and dest mip will both be zero.
            // We are not allowed to bind the same resource (mip) to two different shader bindings.
            // so in the first iteration we will just bind dest_mip + 1 to avoid clashes

            src_mip_level : u32 =  dest_mip_level == 0 ? dest_mip_level + 1 : dest_mip_level - 1;

            // src mip level (higher resolution)
            storage_rw_bindings[0].mip_level = src_mip_level;

            // dest mip level (lower resolution)
            storage_rw_bindings[1].mip_level = dest_mip_level;


            compute_pass := sdl.BeginGPUComputePass(cmd_buf, &storage_rw_bindings[0], 2, nil, 0);

            sdl.BindGPUComputePipeline(compute_pass, compute_pipeline);

            // Bind depth buffer texture.
            // we have to do this in every iteration because of alignment of resources or something
            // but we only use it in the first iteration.           
            depth_stencil_target_tex_sampler_binding := sdl.GPUTextureSamplerBinding {
                //texture = ren_ctx.pre_depth_stencil_target_tex,
                texture = ren_ctx.geo_depth_stencil_target_tex,
                sampler = ren_ctx.nearest_depth_sampler,
            }
        
            sdl.BindGPUComputeSamplers(compute_pass, 0, &depth_stencil_target_tex_sampler_binding, 1);

            ubo._src_dimentions  = curr_src_dimentions
            ubo._dest_dimentions = curr_dest_dimentions;
            ubo._dest_mip_level  = dest_mip_level;
            
            sdl.PushGPUComputeUniformData(cmd_buf,0, &ubo, size_of(ubo));


            work_groups : [3]u32 = calc_work_groups_from_thread_counts_and_invocations(thread_count, [3]u32{ubo._dest_dimentions.x, ubo._dest_dimentions.y, 1});

            sdl.DispatchGPUCompute(compute_pass, work_groups.x, work_groups.y , 1);

            sdl.EndGPUComputePass(compute_pass);


            curr_src_dimentions  = curr_dest_dimentions;
            curr_dest_dimentions = curr_dest_dimentions / 2;
        }
    }

    // ============================================================================================================
    //                                      SSAO / GTAO
    // ============================================================================================================
    

    gtao_enabled : bool = .GTAO in ren_ctx.config.ren_effect_flags && !ren_ctx.effects.gtao.settings.temporary_disabled;

    if gtao_enabled {
        renderer_push_debug_group(cmd_buf, "Render Effect: GTAO Compute");
        defer renderer_pop_debug_group(cmd_buf);

        gtao := ren_ctx.effects.gtao;

        engine_assert(gtao != nil)
        engine_assert(gtao.target_tex != nil);

        full_res_ao : bool = gtao.settings.full_res;

        ao_tex_dimentions : [2]u32 = full_res_ao ? frame_size : renderer_calculate_frame_size_from_swapchain_size(frame_size, RenderResolution.Half);

        // GTAO Compute pass
        {            
            compute_pipeline , thread_count := get_compute_pipeline(.GTAO);
            
            ao_tex_storage_rw_binding := sdl.GPUStorageTextureReadWriteBinding{
                texture   = gtao.target_tex,
                mip_level = full_res_ao ? 0 : 1, // if full res we write directly into mip 0
                layer     = 0,
                cycle = true,
            }

            //dimentions := ao_dimentions;

            //log.debugf("Ran GTAO, is nil ? {}", gtao.target_tex)
            compute_pass := sdl.BeginGPUComputePass(cmd_buf, &ao_tex_storage_rw_binding, 1, nil, 0);
            sdl.BindGPUComputePipeline(compute_pass, compute_pipeline);

            min_max_depth_tex_sampler_binding := sdl.GPUTextureSamplerBinding {
                texture = ren_ctx.min_max_depth,
                sampler = ren_ctx.nearest_depth_sampler,
            }
            sdl.BindGPUComputeSamplers(compute_pass, 0, &min_max_depth_tex_sampler_binding, 1);
            

            // Matches shader ubo struct
            GTAO_UBO :: struct {
                _inv_proj_mat : matrix[4,4]f32,
                // _inv_view_mat : matrix[4,4]f32, // we need this when we want to do Bent Normals, see shader for explanation
                _ao_tex_size : [2]u32,
                _sample_count   : u32,
                _slice_count    : u32,
                _sample_radius  : f32,
                _hit_thickness  : f32,
                _min_max_depth_mip_level : i32,
                _strength  : f32,
            }

            ubo : GTAO_UBO = {
                _inv_proj_mat  = camera_info.inv_proj_mat,            
                _ao_tex_size   = ao_tex_dimentions,
                _sample_count  = gtao.settings.sample_count ,
                _slice_count   = gtao.settings.slice_count  ,
                _sample_radius = gtao.settings.sample_radius,
                _hit_thickness = gtao.settings.hit_thickness,

                _min_max_depth_mip_level = full_res_ao ? 0 : 1,
                _strength = gtao.settings.strength,
            }

            sdl.PushGPUComputeUniformData(cmd_buf,0, &ubo, size_of(ubo))

            work_groups : [3]u32 = calc_work_groups_from_thread_counts_and_invocations(thread_count, [3]u32{ao_tex_dimentions.x, ao_tex_dimentions.y, 1});

            sdl.DispatchGPUCompute(compute_pass, work_groups.x, work_groups.y , 1);

            sdl.EndGPUComputePass(compute_pass);
        }
        
        // Upscale AO Pass
        // @Note we only need to upscale if we dont do full resolution ao
        if !full_res_ao {
            UpscaleUBO :: struct {
                _inv_proj_mat : matrix[4,4]f32,     
                _src_dimentions  : [2]u32,
                _dest_dimentions : [2]u32,
                _dst_mip  : i32,
                _multiply_dest   : i32,
                _camera_near     : f32,
                _camera_far      : f32,
            }

            rw_bindings : [2]sdl.GPUStorageTextureReadWriteBinding = {
                // destination mip 0 (full res)
                sdl.GPUStorageTextureReadWriteBinding{
                    texture   = gtao.target_tex,
                    mip_level = 0,
                    layer     = 0,
                    cycle = false,
                },
                // src mip 1 (half res) 
                sdl.GPUStorageTextureReadWriteBinding{
                    texture   = gtao.target_tex,
                    mip_level = 1,
                    layer     = 0,
                    cycle = false,
                },
            }

            compute_pass := sdl.BeginGPUComputePass(cmd_buf, &rw_bindings[0], 2, nil, 0);

            compute_pipeline , thread_count := get_compute_pipeline(.UPSCALE_AO);
            sdl.BindGPUComputePipeline(compute_pass, compute_pipeline);

            // Min Max Depth tex
            min_max_depth_tex_sampler_binding := sdl.GPUTextureSamplerBinding {
                    texture = ren_ctx.min_max_depth,
                    sampler = ren_ctx.nearest_depth_sampler,
            }
            sdl.BindGPUComputeSamplers(compute_pass, 0, &min_max_depth_tex_sampler_binding, 1);

            upscale_ubo : UpscaleUBO = {
                _inv_proj_mat = camera_info.inv_view_proj_mat,
                _src_dimentions  = ao_tex_dimentions,
                _dest_dimentions = frame_size,
                _dst_mip         = 0,
                _multiply_dest   = 0, // dont need this anymore
                _camera_near = camera_info.near_plane,
                _camera_far  = camera_info.far_plane,
            }

            sdl.PushGPUComputeUniformData(cmd_buf,0, &upscale_ubo, size_of(upscale_ubo));

            work_groups : [3]u32 = calc_work_groups_from_thread_counts_and_invocations(thread_count, [3]u32{upscale_ubo._dest_dimentions.x, upscale_ubo._dest_dimentions.y, 1});
            sdl.DispatchGPUCompute(compute_pass, work_groups.x, work_groups.y , 1);
            sdl.EndGPUComputePass(compute_pass);
        }
    }

    ao_sampler_binding := sdl.GPUTextureSamplerBinding {
        texture = gtao_enabled ? ren_ctx.effects.gtao.target_tex : ren_ctx.white_texture.binding.texture,
        sampler = ren_ctx.nearest_depth_sampler, // for testings
    }


    // ============================================================================================================
    //                                     SHADOWMAP PASS
    // ============================================================================================================

    // TODO maybe move ligth pass after depth pre and ao so while ao is doing compute workload, 
    // gemetry gpu parts can do depht buffer stuff.
    {   
        light_manager : ^LightManager = &universe.light_manager;
        
        draw_calls : u32 = 0;
        num_rendered_shadowmaps : u32 = 0;
        num_pipe_switches : u32 = 0;

        timer := timer_begin();
        defer {            
            perfs.shadowmap_pass_cpu_ms = timer_end_get_miliseconds(timer);
            perfs.shadowmap_pass_drawcalls = draw_calls;
            perfs.shadowmap_pass_num_rendered_shadowmaps = num_rendered_shadowmaps;
            perfs.shadowmap_pass_num_pipeline_switches = num_pipe_switches;
        }
        
        if len(light_manager.gpu_shadowmap_infos) > 0 {
        
            renderer_push_debug_group(cmd_buf, "Shadowmaps");
            defer renderer_pop_debug_group(cmd_buf);
        
            for &sinfo, index in light_manager.gpu_shadowmap_infos {

                if sinfo.array_layer <= -1 {
                    continue; // skip unused shadowmap infos.
                }

                renderer_push_debug_group(cmd_buf, "Shadowmap Pass");
                defer renderer_pop_debug_group(cmd_buf);

                //log.debugf("Rendering sinfo {},   array_layer {}, mip {}", index, cast(u32)sinfo.array_layer, sinfo.mip_level);

                color_target := sdl.GPUColorTargetInfo {
                    texture =  light_manager.shadowmap_array_binding.texture,
                    mip_level = sinfo.mip_level,
                    layer_or_depth_plane = cast(u32)sinfo.array_layer,
                    clear_color = sdl.FColor{1.0,1.0,1.0,1.0},
                    load_op  = sdl.GPULoadOp.CLEAR,
                    store_op = .STORE,
                    cycle = false,
                }

                depth_target_info : sdl.GPUDepthStencilTargetInfo = sdl.GPUDepthStencilTargetInfo {
                    texture     = ren_ctx.shadowmap_depth_textures[sinfo.mip_level],
                    clear_depth = 1,                        // The value to clear the depth component with
                    load_op     = sdl.GPULoadOp.CLEAR,
                    store_op    = sdl.GPUStoreOp.DONT_CARE,


                    stencil_load_op = sdl.GPULoadOp.DONT_CARE,
                    stencil_store_op = sdl.GPUStoreOp.DONT_CARE,
                    cycle = false,         // true cycles the texture if the texture is bound and any load ops are not LOAD */
                    clear_stencil = 0,    // The value to clear the stencil component to at the beginning of the render pass. Ignored if GPU_LOADOP_CLEAR is not used. */
                }

                shadowmap_pass := sdl.BeginGPURenderPass(cmd_buf, &color_target, 1, &depth_target_info);

                sdl.BindGPUVertexStorageBuffers(shadowmap_pass, 0, &universe.matrix_buf, 1);
                sdl.BindGPUVertexStorageBuffers(shadowmap_pass, 1, &light_manager.gpu_shadowmap_infos_buf, 1);

                // Note we souldn't do all but exclude blend meshes and probably also frustum cull from light!
                
                last_shadow_pipeline_variant : ^sdl.GPUGraphicsPipeline = nil;

                for drawable_index in 0..<len(ecs.drawables) {

                    mesh_id := ecs.drawables[drawable_index].mesh_instance.mesh_id;
                    mat_id := ecs.drawables[drawable_index].mesh_instance.mat_id;

                    mat  := register_get_material(mat_id);

                    if mat.render_technique.alpha_mode == .Blend {
                        continue;
                    }

                    if universe.cull_shadow_draws {
                        render_draw : bool = test_shadow_draw(sinfo.view_proj, ecs.drawables[drawable_index].world_obb, sinfo.resolution)
                        if !render_draw {
                            continue;
                        }
                    }

                    technique_hash := material_register_get_render_technique_hash(mat_id);

                    pipeline_variant : ^sdl.GPUGraphicsPipeline = nil;

                    if mat.render_technique.alpha_mode == .Opaque {
                        pipeline_variant = pipe_manager_get_depthonly_pipeline_variant(pipe_manager, DepthOnlyPipelineShaders.Shadowmap, technique_hash);
                    } else {
                        pipeline_variant = pipe_manager_get_depthonly_pipeline_variant(pipe_manager, DepthOnlyPipelineShaders.ShadowmapAlphaTest, technique_hash);
                    }

                    if pipeline_variant != last_shadow_pipeline_variant {

                        sdl.BindGPUGraphicsPipeline(shadowmap_pass, pipeline_variant);
                        last_shadow_pipeline_variant = pipeline_variant;
                        num_pipe_switches += 1;
                    }

                    
                    draw_instance_ubo := VertexDrawInstanceUBO{
                        drawable_index = cast(u32)drawable_index,
                        padding1 = cast(u32)index,
                    }
                    
                    sdl.PushGPUVertexUniformData(cmd_buf, 0, &draw_instance_ubo, size_of(VertexDrawInstanceUBO));

                    mesh_gpu_data := mesh_manager_get_mesh_gpu_data(mesh_manager, mesh_id);

                    renderer_DRAW_CALL_draw_mesh_instance_gpu_data(shadowmap_pass, mesh_gpu_data, true);
                    
                    draw_calls += 1;
                }

                num_rendered_shadowmaps += 1;
                sdl.EndGPURenderPass(shadowmap_pass);
            }

        }
    }

    // ============================================================================================================
    //                                      MAIN FORWARD RENDER PASS
    // ============================================================================================================
    {
        renderer_push_debug_group(cmd_buf, "Main Forward Pass");
        defer renderer_pop_debug_group(cmd_buf);

        forward_draw_calls : u32 = 0;
        forward_pipe_switches : u32 = 0;
        forward_pass_timer := timer_begin();


        color_target := sdl.GPUColorTargetInfo {
            texture = ren_ctx.geo_color_target_tex,
            clear_color = sdl.FColor{0.4,0,0,1},
            load_op = sdl.GPULoadOp.CLEAR,
            store_op = .STORE,

            cycle = true,
        }

        // @Note its kinda ineficiant to redo depth.. we shouldn't do that....

        depth_stencil_target_info : sdl.GPUDepthStencilTargetInfo = sdl.GPUDepthStencilTargetInfo{
            texture =  ren_ctx.geo_depth_stencil_target_tex,
            clear_depth = 1,                        // The value to clear the depth component to at the beginning of the render pass. Ignored if GPU_LOADOP_CLEAR is not used. 
            
            load_op  = sdl.GPULoadOp.LOAD,          // What is done with the depth contents at the beginning of the render pass.
            store_op = sdl.GPUStoreOp.DONT_CARE,
            
            stencil_load_op = sdl.GPULoadOp.LOAD,
            stencil_store_op = sdl.GPUStoreOp.DONT_CARE,
            cycle = false,         // true cycles the texture if the texture is bound and any load ops are not LOAD 
            clear_stencil = 0,        // The value to clear the stencil component to at the beginning of the render pass. Ignored if GPU_LOADOP_CLEAR is not used.
        }


        render_pass : ^sdl.GPURenderPass = sdl.BeginGPURenderPass(cmd_buf, &color_target,1, &depth_stencil_target_info);

        // Push global data for all pipline in this render pass
        sdl.PushGPUVertexUniformData(cmd_buf, 0, &ren_ctx.global_vertex_ubo, size_of(GlobalVertexUBO));
        
        sky_gpu_buffer := universe.skybox_gpu_buffer;
        sky_comp := universe_get_active_skybox_component(universe);


        sky_cubemap_binding : ^sdl.GPUTextureSamplerBinding = &ren_ctx.dummy_cubemap.binding;    
        if sky_comp != nil &&  sky_comp.cubemap.binding.texture != nil && sky_comp.cubemap.binding.sampler != nil{
            sky_cubemap_binding = &sky_comp.cubemap.binding;
        }

        // BIND GLOBAL FRAGMENT BUFFER TO BUFFER SLOT 0
        sdl.BindGPUFragmentStorageBuffers(render_pass, 0, &ren_ctx.global_fragment_gpu_buffer, 1);

        // SKYBOX BUFFER SLOT 1
        sdl.BindGPUFragmentStorageBuffers(render_pass, 1, &sky_gpu_buffer, 1);

        //Skybox Pass
        // The skybox pass must happen before alpha blended materials.
        {
            pipeline_skybox := pipe_manager_get_core_pipeline(pipe_manager, .Skybox);
            sdl.BindGPUGraphicsPipeline(render_pass, pipeline_skybox);

            sdl.BindGPUFragmentSamplers(render_pass, 0, sky_cubemap_binding ,1);

            // bind vertex buffer
            vert_buffer_binding := sdl.GPUBufferBinding {
                buffer = ren_ctx.prim_icosphere.vert_buf,
                offset = 0,
            }

            sdl.BindGPUVertexBuffers(render_pass, 0, &vert_buffer_binding, 1);

            sdl.DrawGPUPrimitives(render_pass, ren_ctx.prim_icosphere.num_vertecies , 1, 0, 0);
        }


        bind_unlit_material_resources :: proc(render_pass : ^sdl.GPURenderPass){

            unlit_mat_storage_buffer := material_register_get_gpu_buffer_for_type(.UNLIT);
            
            sdl.BindGPUFragmentStorageBuffers(render_pass, 0, &unlit_mat_storage_buffer, 1);
        }

        bind_pbr_material_resources :: proc(ren_ctx : ^RenderContext, render_pass : ^sdl.GPURenderPass, universe : ^Universe, ao_sampler_binding : ^sdl.GPUTextureSamplerBinding, sky_cubemap_binding : ^sdl.GPUTextureSamplerBinding) {
            
            // Brdf Lut
            sdl.BindGPUFragmentSamplers(render_pass, 0 , &ren_ctx.brdf_lut.binding, 1);

            // AO Texture
            sdl.BindGPUFragmentSamplers(render_pass, 1 ,ao_sampler_binding, 1);

            // Skybox cubemap
            sdl.BindGPUFragmentSamplers(render_pass, 2, sky_cubemap_binding ,1);


            // Shadowmap Array
            sdl.BindGPUFragmentSamplers(render_pass, 3, &universe.light_manager.shadowmap_array_binding ,1);


            // Bind buffers specific to opaque pbr pass..
            sdl.BindGPUFragmentStorageBuffers(render_pass, 0, &ren_ctx.global_fragment_gpu_buffer, 1);

            // Skybox Buffer
            sdl.BindGPUFragmentStorageBuffers(render_pass, 1, &universe.skybox_gpu_buffer, 1);

            // PBR material buffer
            pbr_mat_storage_buffer := material_register_get_gpu_buffer_for_type(.PBR);
            sdl.BindGPUFragmentStorageBuffers(render_pass, 2, &pbr_mat_storage_buffer, 1);

            // lights
            sdl.BindGPUFragmentStorageBuffers(render_pass, 3, &universe.light_manager.gpu_lights_data_buf, 1);
            sdl.BindGPUFragmentStorageBuffers(render_pass, 4, &universe.light_manager.gpu_shadowmap_infos_buf, 1);
        }

        draw_drawable_index_array :: proc(ren_ctx : ^RenderContext, 
                                        cmd_buf : ^sdl.GPUCommandBuffer, 
                                        render_pass : ^sdl.GPURenderPass, 
                                        mesh_manager : ^MeshManager, 
                                        pipe_manager : ^PipelineManager, 
                                        drawables_index_array : ^[dynamic]u32, 
                                        universe : ^Universe, 
                                        ao_sampler_binding : ^sdl.GPUTextureSamplerBinding, 
                                        sky_cubemap_binding : ^sdl.GPUTextureSamplerBinding) ->(draw_calls : u32, pipeline_switches : u32) {

            last_pipeline_variant : ^sdl.GPUGraphicsPipeline = nil;
            last_material_shader_type : MaterialShaderType = .NONE; 

            for drawable_index in drawables_index_array {

                    mesh_id := universe.ecs.drawables[drawable_index].mesh_instance.mesh_id;
                    mat_id  := universe.ecs.drawables[drawable_index].mesh_instance.mat_id;
                    

                    material := register_get_material(mat_id);
                    mat_shader_type := register_get_material_shader_type(mat_id);


                    mesh_gpu_data := mesh_manager_get_mesh_gpu_data(mesh_manager, mesh_id);
                    vert_layout   := mesh_gpu_data.vertex_layout;


                    pipeline_variant := pipe_manager_get_material_pipeline_variant(pipe_manager, mat_id, vert_layout);

                    if pipeline_variant != last_pipeline_variant {

                        sdl.BindGPUGraphicsPipeline(render_pass, pipeline_variant);
                        last_pipeline_variant = pipeline_variant;

                        pipeline_switches += 1;

                        if mat_shader_type != last_material_shader_type {

                            switch mat_shader_type {
                                case .NONE:
                                case .PBR:   bind_pbr_material_resources(ren_ctx, render_pass, universe, ao_sampler_binding, sky_cubemap_binding);
                                case .UNLIT: bind_unlit_material_resources(render_pass);
                                case .CUSTOM:
                            }

                            last_material_shader_type = last_material_shader_type;
                        }

                    }
                    
                    if pipeline_variant == nil {
                        log.debugf("DrawFrame: cannont exxecture draw call, pipeline not build");
                        continue;
                    }

                    // This can be the same for all pipelines even custom shaders.
                    // but eventually we should change it to only push an id to lockup model matrix directly on the gpu in a buffer.
                    // vertex data
                    
                    draw_instance_ubo := VertexDrawInstanceUBO{
                        drawable_index = cast(u32)drawable_index,
                    }
                    
                    sdl.PushGPUVertexUniformData(cmd_buf, 1, &draw_instance_ubo, size_of(VertexDrawInstanceUBO));

                    
                    // @Note:
                    // this part must adapt to which shader model is in use. 
                    // we can stick to just pushing an ID for lookup for engine shaders but still we must query the id based
                    // on shader type atm.
                    // for custom shaders we would instead need to bind a buffer which we will need to get from somewhere
                    // it would probably be stored in a shader component of an entity.
                    // however we might want to iterate custom shaders seperatly ??
                    // fragment data
                    switch &mat_variant in material.variant {
                        case PbrMaterialData: {

                            //sdl.PushGPUVertexUniformData(cmd_buf, 1, &mesh_vertex_ubo, size_of(MeshVertexUBO) );

                            material_gpu_index: i32 = material_register_get_gpu_array_index_for_type(MaterialShaderType.PBR, mat_id);
                            
                            frag_mat_ubo: MatUBO = MatUBO{
                                mat_index = cast(u32)material_gpu_index,
                            };

                            sdl.PushGPUFragmentUniformData(cmd_buf, 0, &frag_mat_ubo, size_of(MatUBO));

                        }
                        case UnlitMaterialData: {
                            
                            //sdl.PushGPUVertexUniformData(cmd_buf, 1, &mesh_vertex_ubo, size_of(MeshVertexUBO) );

                            material_gpu_index: i32 = material_register_get_gpu_array_index_for_type(MaterialShaderType.UNLIT, mat_id);
                            frag_mat_ubo: MatUBO = MatUBO{
                                mat_index = cast(u32)material_gpu_index,
                            };

                            sdl.PushGPUFragmentUniformData(cmd_buf, 0, &frag_mat_ubo, size_of(MatUBO));
                        }
                        case CustomMaterialVariant: {
                            unimplemented();
                        }


                    }

                    draw_calls += 1;
                    renderer_DRAW_CALL_draw_mesh_instance_gpu_data(render_pass, mesh_gpu_data, false);
            }

            return draw_calls, pipeline_switches;
        }
        
        if any_draws_exist {

            // @Note: if no draws exist, matrix buffer will be nill
            sdl.BindGPUVertexStorageBuffers(render_pass, 0, &universe.matrix_buf, 1);

            draws, switches := draw_drawable_index_array(ren_ctx, cmd_buf, render_pass, mesh_manager, pipe_manager, &universe.frame_opaques    , universe, &ao_sampler_binding, sky_cubemap_binding);
            forward_draw_calls += draws;
            forward_pipe_switches += switches;

            draws, switches = draw_drawable_index_array(ren_ctx, cmd_buf, render_pass, mesh_manager, pipe_manager, &universe.frame_alpha_test , universe, &ao_sampler_binding, sky_cubemap_binding);
            forward_draw_calls += draws;
            forward_pipe_switches += switches;
            
            draws, switches = draw_drawable_index_array(ren_ctx, cmd_buf, render_pass, mesh_manager, pipe_manager, &universe.frame_alpha_blend, universe, &ao_sampler_binding, sky_cubemap_binding);
            forward_draw_calls += draws;
            forward_pipe_switches += switches;
        }

        draw_debug_lights_vis :: true

        when draw_debug_lights_vis {

            // Draw lights as solid meshes..
            if(len(ecs.light_components) > 0) {

                pipe_solid_cube := pipe_manager_get_core_pipeline(pipe_manager, .SOLID_CUBE);
                sdl.BindGPUGraphicsPipeline(render_pass, pipe_solid_cube);


                for &light_comp in ecs.light_components {

                    transform := ecs_get_transform(ecs, light_comp.entity);

                    transform_mod := transform^;

                    light_type := comp_light_get_type(&light_comp);
                    switch light_type {
                        case .DIRECTIONAL:  transform_mod.scale = {0.25, 0.25, 3.0};
                        case .POINT:        transform_mod.scale = {0.10, 0.10, 0.10};
                        case .SPOT:         transform_mod.scale = {0.25, 0.25, 3.0};
                    }

                    color: [4]f32 = {light_comp.color.r , light_comp.color.g, light_comp.color.b, 1.0} * light_comp.strength;
                    sdl.PushGPUFragmentUniformData(cmd_buf, 0, &color , size_of([4]f32));

                    mat := calc_transform_matrix(transform_mod);

                    renderer_DRAW_CALL_draw_unit_cube(cmd_buf, render_pass, mat);
                }
            }

            light_manager := &universe.light_manager;

            wire_cube_pipe := pipe_manager_get_core_pipeline(pipe_manager, .WIREFRAME_CUBE);
            sdl.BindGPUGraphicsPipeline(render_pass, wire_cube_pipe);
            wire_color : [4]f32 = {0.0,0.0,0.0,1.0} // black

            sdl.PushGPUFragmentUniformData(cmd_buf, 0, &wire_color , size_of([4]f32));

            for &light_comp, comp_index in ecs.light_components {

                transform := ecs_get_transform(ecs, light_comp.entity);

                switch &variant in light_comp.variant {

                    case DirectionalLightVariant:
                    case PointLightVariant:
                    {
                        if !variant.draw_cone do continue;
                        gpu_index := light_manager.gpu_lights_indexes[comp_index];
                        gpu_light := &light_manager.gpu_lights[gpu_index];

                        if gpu_light.shadowmap_index <= -1 do continue;

                        if variant.draw_cone_index < 0 || variant.draw_cone_index > 5 { // DRAW ALL OF THEM

                            for i in 0..<6{
                                shadow_info := &light_manager.gpu_shadowmap_infos[gpu_light.shadowmap_index + cast(i32)i];
                                mat := linalg.inverse(shadow_info.view_proj);
                                renderer_DRAW_CALL_draw_unit_cube(cmd_buf, render_pass, mat);
                            }

                        } else { // only draw the specified index

                            shadow_info := &light_manager.gpu_shadowmap_infos[gpu_light.shadowmap_index + variant.draw_cone_index];
                            mat := linalg.inverse(shadow_info.view_proj);
                            renderer_DRAW_CALL_draw_unit_cube(cmd_buf, render_pass, mat);
                        }

                    }
                    case SpotLightVariant:
                    {
                        if !variant.draw_cone do continue;

                        gpu_index := light_manager.gpu_lights_indexes[comp_index];
                        gpu_light := &light_manager.gpu_lights[gpu_index];

                        if gpu_light.shadowmap_index <= -1 do continue;

                        shadow_info := &light_manager.gpu_shadowmap_infos[gpu_light.shadowmap_index];

                        mat := linalg.inverse(shadow_info.view_proj);
                        renderer_DRAW_CALL_draw_unit_cube(cmd_buf, render_pass, mat);
                    }

                }
            }
        }


        // AABB WIREFRAME

        // @Note maybe expose this as debug config setting
        render_view_frustum_box : bool = ren_ctx.debug_config.draw_camera_frustum_box && universe.frustum_cull_camera_entity.id >= 0 ? true : false; 

        if ren_ctx.debug_config.draw_bounding_box || ren_ctx.debug_config.draw_bounding_box_axis_aligned || render_view_frustum_box {

            pipeline_wire_cube := pipe_manager_get_core_pipeline(pipe_manager, .WIREFRAME_CUBE);

            sdl.BindGPUGraphicsPipeline(render_pass, pipeline_wire_cube);


            // Render view frustum in ws
            if(render_view_frustum_box){
                
                wire_color: [4]f32 = {1.0,1.0,0.0,1.0}; // yellow
                sdl.PushGPUFragmentUniformData(cmd_buf,0, &wire_color , size_of([4]f32));

                // using the inv_view_proj matrix of the frustum camera we can transform a unit cube into world space
                // which will then be rendered from the point of view of the rendering camera.
                model_mat := linalg.matrix4_inverse(camera_info.frustum_proj_mat * camera_info.frustum_view_mat);

                renderer_DRAW_CALL_draw_unit_cube(cmd_buf, render_pass, model_mat);
            }

            // Draw aabbs but as object-aligned bounding box by just transforming with tranform mat.
            if(ren_ctx.debug_config.draw_bounding_box) {
            //when false {
                
                wire_color: [4]f32 = {0.0,0.0,1.0,1.0};
                sdl.PushGPUFragmentUniformData(cmd_buf,0, &wire_color , size_of([4]f32));

                for drawable_index in universe.frame_renderables {

                    mesh_id := ecs.drawables[drawable_index].mesh_instance.mesh_id;

                    aabb := mesh_manager_get_aabb(mesh_manager, mesh_id);

                    // Note maybe can construct transform mat directly from obb stored in drawable ??
                    model_mat := ecs.drawables.world_mat[drawable_index] * aabb_get_transform_matrix(aabb)

                    renderer_DRAW_CALL_draw_unit_cube(cmd_buf,render_pass, model_mat);
                }
            }  

            if(ren_ctx.debug_config.draw_bounding_box_axis_aligned) {
            
                // draw propper AABBS
                wire_color: [4]f32 = {1.0,0.0,0.0,1.0};
                sdl.PushGPUFragmentUniformData(cmd_buf,0, &wire_color , size_of([4]f32));

                for drawable_index in universe.frame_renderables {

                    mesh_id : MeshID = ecs.drawables[drawable_index].mesh_instance.mesh_id;

                    aabb := mesh_manager_get_aabb(mesh_manager, mesh_id);

                    // Note maybe can construct transform mat directly from obb stored in drawable ??
                    model_mat := aabb_transform_by_mat4_and_get_tranform_mat(aabb, ecs.drawables.world_mat[drawable_index]);

                    renderer_DRAW_CALL_draw_unit_cube(cmd_buf,render_pass, model_mat);
                }
            }
        }


        // End render pass
        sdl.EndGPURenderPass(render_pass);

        perfs.forward_pass_drawcalls = forward_draw_calls;
        perfs.forward_pass_num_pipeline_switches = forward_pipe_switches;
        perfs.forward_pass_cpu_ms = timer_end_get_miliseconds(forward_pass_timer);

    }

    // POST COLOR CORRECT PASS
    // Here we just color correct the scene rendered img with tonemapping and srgb convertion

    {
        renderer_push_debug_group(cmd_buf, "Post Process Color Correction");
        defer renderer_pop_debug_group(cmd_buf);

        post_correct_color_target := sdl.GPUColorTargetInfo {
                texture = ren_ctx.post_correct_color_target_tex,
                // clear_color = sdl.FColor{0,0,0,1},
                load_op  = sdl.GPULoadOp.DONT_CARE,
                store_op = sdl.GPUStoreOp.STORE,
                cycle = true,
        }

        post_process_render_pass := sdl.BeginGPURenderPass(cmd_buf, &post_correct_color_target,1,nil);
        sdl.BindGPUGraphicsPipeline(post_process_render_pass, pipe_manager_get_core_pipeline(pipe_manager, .PostColorCorrect));

        geo_color_target_sampler_binding := sdl.GPUTextureSamplerBinding {
            texture = ren_ctx.geo_color_target_tex,
            sampler = ren_ctx.geo_color_target_sampler,
        }

        sdl.BindGPUFragmentSamplers(post_process_render_pass, 0, &geo_color_target_sampler_binding, 1);
        
        // TODO: expose this with settings
        post_settings := PostProcessSettingsUBO{
            exposure = 0.0,
            tone_map_mode = 0,
            convert_to_srgb = window.swapchain_settings.color_space == SwapchainColorSpace.Srgb ? true : false,
        }

        sdl.PushGPUFragmentUniformData(cmd_buf,0, &post_settings, size_of(PostProcessSettingsUBO));

        // Draw 6 verts aka 2 triangles aka 1 screenquad
        sdl.DrawGPUPrimitives(post_process_render_pass, 6, 1, 0,0);

        sdl.EndGPURenderPass(post_process_render_pass);
    }

    // SMAA PASS
    smaa_pass_enabled : bool = .SMAA in ren_ctx.config.ren_effect_flags && !ren_ctx.effects.smaa.settings.temporary_disabled
    //smaa_pass_enabled = false; // force off rn
    if smaa_pass_enabled {

        renderer_push_debug_group(cmd_buf, "Render Effect: SMAA");
        defer renderer_pop_debug_group(cmd_buf);

        smaa := ren_ctx.effects.smaa;

        engine_assert(smaa != nil);
        engine_assert(smaa.edges_target != nil);
        engine_assert(smaa.blend_target != nil);
        engine_assert(smaa.area_tex     != nil);
        engine_assert(smaa.search_tex   != nil);

        SMAAEdgeDetectionUBO :: struct {
            input_dimentions : [4]f32,
        }

        edge_detection_ubo := SMAAEdgeDetectionUBO{
            input_dimentions = [4]f32{1.0 / f32(frame_size.x), 1.0 / f32(frame_size.y), f32(frame_size.x), f32(frame_size.y)},
        }

        input_color_target_sampler_binding := sdl.GPUTextureSamplerBinding{
            texture = ren_ctx.post_correct_color_target_tex,
            sampler = ren_ctx.sampler_linear_mip_nearest_clamp,
        }

        // FIRST PASS: EDGE DETECTION
        {   
            color_target := sdl.GPUColorTargetInfo {
                texture = smaa.edges_target,
                clear_color = sdl.FColor{0.0,0,0,0},
                load_op = sdl.GPULoadOp.CLEAR,
                store_op = .STORE,

                cycle = true,
            }

            smaa_ren_pass := sdl.BeginGPURenderPass(cmd_buf, &color_target, 1, nil);

            smaa_edge_detection_pipe := pipe_manager_get_core_pipeline(pipe_manager, .SMAA_EDGE_DETECTION)
            engine_assert(smaa_edge_detection_pipe != nil)
            sdl.BindGPUGraphicsPipeline(smaa_ren_pass, smaa_edge_detection_pipe);


            sdl.BindGPUFragmentSamplers(smaa_ren_pass, 0 , &input_color_target_sampler_binding,1);


            sdl.PushGPUFragmentUniformData(cmd_buf, 0, &edge_detection_ubo , size_of(SMAAEdgeDetectionUBO));
            sdl.PushGPUVertexUniformData(cmd_buf, 0, &edge_detection_ubo , size_of(SMAAEdgeDetectionUBO));

            // Draw 6 verts aka 2 triangles aka 1 screenquad
            sdl.DrawGPUPrimitives(smaa_ren_pass, 6, 1, 0,0);

            sdl.EndGPURenderPass(smaa_ren_pass);
        }


         // SECOND PASS: BLEND WEIGHT CALCULATION
        {
            color_target := sdl.GPUColorTargetInfo {
                texture = smaa.blend_target,
                clear_color = sdl.FColor{0.0,0,0,0},
                load_op = sdl.GPULoadOp.CLEAR,
                store_op = .STORE,

                cycle = true,
            }

            smaa_ren_pass := sdl.BeginGPURenderPass(cmd_buf, &color_target, 1, nil);

            smaa_blend_weight_pipe := pipe_manager_get_core_pipeline(pipe_manager, .SMAA_BLEND_WEIGHT)
            engine_assert(smaa_blend_weight_pipe != nil)
            sdl.BindGPUGraphicsPipeline(smaa_ren_pass, smaa_blend_weight_pipe);



            // TODO: since we pushed them before to the same slots we can omit these calls here i think??
            sdl.PushGPUFragmentUniformData(cmd_buf, 0, &edge_detection_ubo , size_of(SMAAEdgeDetectionUBO));
            sdl.PushGPUVertexUniformData(cmd_buf, 0, &edge_detection_ubo , size_of(SMAAEdgeDetectionUBO));


            edges_target_sampler_binding := sdl.GPUTextureSamplerBinding{
                texture = smaa.edges_target,
                sampler = ren_ctx.sampler_linear_mip_nearest_clamp,
            }


            area_tex_sampler_binding := sdl.GPUTextureSamplerBinding{
                texture = smaa.area_tex,
                sampler = ren_ctx.sampler_linear_mip_nearest_clamp,
            }

            search_tex_sampler_binding := sdl.GPUTextureSamplerBinding{
                texture = smaa.search_tex,
                sampler = ren_ctx.sampler_linear_mip_nearest_clamp,
            }
            // TODO: can bind in one call.
            sdl.BindGPUFragmentSamplers(smaa_ren_pass, 0 , &edges_target_sampler_binding,1);
            sdl.BindGPUFragmentSamplers(smaa_ren_pass, 1 , &area_tex_sampler_binding,1);
            sdl.BindGPUFragmentSamplers(smaa_ren_pass, 2 , &search_tex_sampler_binding,1);

            // Draw 6 verts aka 2 triangles aka 1 screenquad
            sdl.DrawGPUPrimitives(smaa_ren_pass, 6, 1, 0,0);

            sdl.EndGPURenderPass(smaa_ren_pass);
        }

        // THIRD PASS NEIGHBORHOOD BLENDING
        {
            color_target := sdl.GPUColorTargetInfo {
                texture = smaa.edges_target, // we can recylce the edges target as final output for now
                clear_color = sdl.FColor{0.0,0,0,0},
                load_op = sdl.GPULoadOp.CLEAR,
                store_op = .STORE,

                cycle = true,
            }

            smaa_ren_pass := sdl.BeginGPURenderPass(cmd_buf, &color_target, 1, nil);

            smaa_neighborhood_blend_pipe := pipe_manager_get_core_pipeline(pipe_manager, .SMAA_NEIGHBORHOOD_BLEND)
            engine_assert(smaa_neighborhood_blend_pipe != nil)
            sdl.BindGPUGraphicsPipeline(smaa_ren_pass, smaa_neighborhood_blend_pipe);


            // TODO: since we pushed them before to the same slots we can omit these calls here i think??
            sdl.PushGPUFragmentUniformData(cmd_buf, 0, &edge_detection_ubo , size_of(SMAAEdgeDetectionUBO));
            sdl.PushGPUVertexUniformData(cmd_buf, 0, &edge_detection_ubo , size_of(SMAAEdgeDetectionUBO));

            blend_target_sampler_binding := sdl.GPUTextureSamplerBinding{
                texture = smaa.blend_target,
                sampler = ren_ctx.sampler_linear_mip_nearest_clamp,
            }

            sdl.BindGPUFragmentSamplers(smaa_ren_pass, 0 , &input_color_target_sampler_binding,1);
            sdl.BindGPUFragmentSamplers(smaa_ren_pass, 1 , &blend_target_sampler_binding,1);

            // Draw 6 verts aka 2 triangles aka 1 screenquad
            sdl.DrawGPUPrimitives(smaa_ren_pass, 6, 1, 0,0);

            sdl.EndGPURenderPass(smaa_ren_pass);
        }
    }



    // UI (DearImgui) RENDER PASS
    if debug_gui_is_enabled() {

        renderer_push_debug_group(cmd_buf, "Debug GUI Pass");
        defer renderer_pop_debug_group(cmd_buf);

        ui_color_target := sdl.GPUColorTargetInfo {
            texture = ren_ctx.debug_gui_color_target_tex,
            clear_color = sdl.FColor{0,0,0,0},
            load_op  = sdl.GPULoadOp.CLEAR,
            store_op = sdl.GPUStoreOp.STORE,
            cycle = true,
        }

        debug_gui_render_pass : ^sdl.GPURenderPass = sdl.BeginGPURenderPass(cmd_buf, &ui_color_target, 1, nil);

        debug_gui_draw_frame(cmd_buf, debug_gui_render_pass, pipe_manager_get_core_pipeline(pipe_manager, .DearImGUI));

        sdl.EndGPURenderPass(debug_gui_render_pass);
    }


    // FINAL COMPOSIT INTO SWAPCHAIN
    {
        renderer_push_debug_group(cmd_buf, "Swapchain Composit Pass");
        defer renderer_pop_debug_group(cmd_buf);

        swapchain_target := sdl.GPUColorTargetInfo {
                texture = swapchain_texture,
                // clear_color = sdl.FColor{0,0,0,1},
                load_op  = sdl.GPULoadOp.DONT_CARE,
                store_op = sdl.GPUStoreOp.STORE,
                cycle = false,
        }

        swapchain_blit_pass := sdl.BeginGPURenderPass(cmd_buf, &swapchain_target,1, nil);
        sdl.BindGPUGraphicsPipeline(swapchain_blit_pass, pipe_manager_get_core_pipeline(pipe_manager, .SWAPCHAIN_COMPOSIT));


        post_correct_tex_sampler_binding := sdl.GPUTextureSamplerBinding {
            //texture = ren_ctx.effects.smaa.edges_target, // nocheckin
            //texture = ren_ctx.post_correct_color_target_tex,
            texture = smaa_pass_enabled ?  ren_ctx.effects.smaa.edges_target : ren_ctx.post_correct_color_target_tex,
            sampler = ren_ctx.post_correct_color_target_sampler, // its just s standart sampler..
        }

        debug_gui_tex_sampler_binding := sdl.GPUTextureSamplerBinding {
            texture = ren_ctx.debug_gui_color_target_tex,
            sampler = ren_ctx.debug_gui_color_target_sampler,
        }

        sdl.BindGPUFragmentSamplers(swapchain_blit_pass, 0, &post_correct_tex_sampler_binding, 1);
        sdl.BindGPUFragmentSamplers(swapchain_blit_pass, 1, &debug_gui_tex_sampler_binding, 1);
        
        SwapchainCompositUBO :: struct {
            convert_to_srgb : u32,
            convert_scene_tex_to_linear_on_load : u32,
            padding1 : u32,
            padding2 : u32,
        }

        swap_composit_ubo := SwapchainCompositUBO {
            convert_to_srgb = window.swapchain_settings.color_space == SwapchainColorSpace.Srgb ? 1 : 0,
            convert_scene_tex_to_linear_on_load = smaa_pass_enabled ? 1 : 0,
        }


        sdl.PushGPUFragmentUniformData(cmd_buf,0, &swap_composit_ubo, size_of(SwapchainCompositUBO));

        // Draw 6 verts aka 2 triangles aka 1 screenquad
        sdl.DrawGPUPrimitives(swapchain_blit_pass, 6, 1, 0,0);

        sdl.EndGPURenderPass(swapchain_blit_pass);
    }

    submit_ok := sdl.SubmitGPUCommandBuffer(cmd_buf);
    engine_assert(submit_ok);
}


@(private="package")
renderer_get_render_pass_info :: proc(ren_ctx : ^RenderContext, render_pass_type: RenderPassType) -> RenderPassInfo{
    return ren_ctx.render_pass_infos[render_pass_type];
}


@(private="file")
renderer_DRAW_CALL_draw_mesh_instance_gpu_data :: proc "contextless" (render_pass : ^sdl.GPURenderPass, mesh_gpu_data : ^MeshGPUData, only_position_buf : bool = false){
                
    // bind vertex buffer
    if only_position_buf {
        
        buffer_bindings : [1]sdl.GPUBufferBinding;
        buffer_bindings[0].buffer = mesh_gpu_data.vertex_pos_buf;
        buffer_bindings[0].offset = 0;
        sdl.BindGPUVertexBuffers(render_pass, 0, &buffer_bindings[0], 1);
    } else {

        buffer_bindings : [2]sdl.GPUBufferBinding;
        buffer_bindings[0].buffer = mesh_gpu_data.vertex_pos_buf;
        buffer_bindings[0].offset = 0;

        buffer_bindings[1].buffer = mesh_gpu_data.vertex_buf;
        buffer_bindings[1].offset = 0;
        sdl.BindGPUVertexBuffers(render_pass, 0, &buffer_bindings[0], 2);
    }

    // bind index buffer
    index_buf_binding : sdl.GPUBufferBinding;
    index_buf_binding.buffer = mesh_gpu_data.index_buf;
    index_buf_binding.offset = 0;
    sdl.BindGPUIndexBuffer(render_pass, index_buf_binding, sdl.GPUIndexElementSize._32BIT);


    num_indecies : u32 = mesh_gpu_data.num_indecies;
    sdl.DrawGPUIndexedPrimitives(render_pass, num_indecies, 1, 0, 0, 0);
}


// Note: must use a pipeline with unit_cube vertex shader
@(private="file")
renderer_DRAW_CALL_draw_unit_cube :: proc "contextless" (command_buffer : ^sdl.GPUCommandBuffer, render_pass : ^sdl.GPURenderPass, transform_matrix : matrix[4,4]f32){
    
    mesh_vertex_ubo : MeshVertexUBO = {
        model_mat = transform_matrix,
    }

    sdl.PushGPUVertexUniformData(command_buffer, 1, &mesh_vertex_ubo, size_of(MeshVertexUBO));

    sdl.DrawGPUPrimitives(render_pass, 36 * 3, 1, 0,0)
}

@(private="file")
renderer_push_debug_group :: proc(command_buffer : ^sdl.GPUCommandBuffer, name : cstring) {

    when ENGINE_DEVELOPMENT {
        sdl.PushGPUDebugGroup(command_buffer, name);
    }
}

@(private="file")
renderer_pop_debug_group :: proc(command_buffer : ^sdl.GPUCommandBuffer){

    when ENGINE_DEVELOPMENT {
        sdl.PopGPUDebugGroup(command_buffer);
    }
}