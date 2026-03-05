package iri

import "core:log"

import "core:mem"
import "core:strings"
import "core:fmt"
import "core:os"


import sdl "vendor:sdl3"
import "odinary:filey"
import "odinary:shady"



ShaderID :: distinct i32
ShaderHash :: u64

ShaderManager :: struct {

	spirv_folder_path : string,

	entries : #soa[dynamic]ShaderEntry,

	gfx_shader_cache : map[ShaderHash]^sdl.GPUShader,
	// For hot reloading
	watchers : [dynamic]ShaderSourceWatcher,
	hotreload_interval : f32,
    hotreload_accumulator : f32,
}

// SHADER_VARIANT_EMPTY :: ShaderVariant{}


// ShaderVariant :: distinct bit_set[ShaderDefines; u32]
// ShaderDefines :: enum u32 {
// 	USE_ALPHA_TEST = 0,
// 	USE_ALPHA_BLEND,
// 	VERT_LAYOUT_MINIMAL,
// 	VERT_LAYOUT_STANDARD,
// 	VERT_LAYOUT_EXTENDED,
// 	SMAA_PASS_EDGE_DETECTION,
// 	SMAA_PASS_BLEND_WEIGHT,
// 	SMAA_PASS_NEIGHBORHOOD_BLEND,
// }

ShaderVariant :: union {
	VertShaderVariant,
	FragShaderVariant,
	RenderEffectShaderVariant,
}

VERT_SHADER_VARIANT_EMPTY :: VertShaderVariant{}
FRAG_SHADER_VARIANT_EMPTY :: FragShaderVariant{}
RENDER_EFFECT_SHADER_VARIANT_EMPTY :: RenderEffectShaderVariant{}

RenderEffectShaderVariant :: distinct bit_set[RenderEffectShaderDefines; u32]
RenderEffectShaderDefines :: enum u32 {
	SMAA_PASS_EDGE_DETECTION = 0,
	SMAA_PASS_BLEND_WEIGHT,
	SMAA_PASS_NEIGHBORHOOD_BLEND,
}

VertShaderVariant :: distinct bit_set[VertShaderDefines; u32]
VertShaderDefines :: enum u32 {
	VERT_LAYOUT_MINIMAL = 0,
	VERT_LAYOUT_STANDARD,
	VERT_LAYOUT_EXTENDED,
}

FragShaderVariant :: distinct bit_set[FragShaderDefines; u32]
FragShaderDefines :: enum u32 {
	USE_ALPHA_TEST = 0,
	USE_ALPHA_BLEND,
}



ShaderEntryFlags :: distinct bit_set[ShaderEntryFlag]
ShaderEntryFlag :: enum u8 {
	EntryIsUsed,
	HotReloadEnabled,
}

@(private="file")
ShaderEntry :: struct {
	flags : ShaderEntryFlags,
	path : string,
	compile_info : ShaderCompileInfo2,
}

@(private="file")
ShaderSourceWatcher :: struct {
    shader_id : ShaderID,
    file_watcher: filey.FileWatcherData,
}



@(private="package")
shader_manager_init :: proc(manager : ^ShaderManager){

	manager.spirv_folder_path = strings.join({get_resources_path(), "shaders/spirv"}, "/", context.allocator);

	manager.hotreload_interval = 1.0;
    manager.hotreload_accumulator = 0.0;

    // This cache is only for graphics shaders (.VERTEX or .FRAGMENT) no .COMPUTE
    manager.gfx_shader_cache = make_map(map[ShaderHash]^sdl.GPUShader, context.allocator);
}

@(private="package")
shader_manager_deinit :: proc(manager : ^ShaderManager, gpu_device : ^sdl.GPUDevice){

	for i in 0..<len(manager.entries){
		if .EntryIsUsed in manager.entries.flags[i] {
			
			delete(manager.entries.path[i]);	
		}
	}

	delete(manager.entries);


	for &watcher in manager.watchers {
		filey.destroy(&watcher.file_watcher);
	}
	delete(manager.watchers);


	shader_manager_clear_gfx_shader_cache(manager, gpu_device);

	delete(manager.gfx_shader_cache);

	delete(manager.spirv_folder_path);
}

@(private="package")
shader_manager_update :: proc(manager : ^ShaderManager, gpu_device : ^sdl.GPUDevice, true_delta_seconds : f64){

	//log.debugf("Shader manager")

	when ENGINE_SHADER_HOT_RELOADING == true {


		manager.hotreload_accumulator += cast(f32)true_delta_seconds;

		hot_reload_check: if manager.hotreload_accumulator >= manager.hotreload_interval {
        	manager.hotreload_accumulator = 0.0;

        	changed_gfx_shader_ids : [dynamic]ShaderID;
        	defer {
        		delete(changed_gfx_shader_ids);
        	}

            for &watcher in manager.watchers {

                if filey.did_any_file_change(&watcher.file_watcher) {

                	compile_info := shader_manager_get_compile_info_ptr(manager, watcher.shader_id);

                	if compile_info.shader_stage == .COMPUTE {
                		compute_pipe_manager_on_shader_source_changed(engine.compute_pipe_manager, manager,gpu_device, watcher.shader_id);
                	} else {

                		// As a first step we should invalidate all variants in the shader cache that use this shaderID
                		shader_manager_clear_all_variants_for_shader_id_from_gfx_shader_cache(manager, gpu_device, watcher.shader_id);

                		append(&changed_gfx_shader_ids, watcher.shader_id);
                	}
                }
            }

            if len(changed_gfx_shader_ids) > 0 {
            	pipe_manager_on_shaders_changed(engine.pipeline_manager, gpu_device, changed_gfx_shader_ids[:]);
            }
        }
	}
}

@(private="package")
shader_manager_register_shader_source :: proc(manager : ^ShaderManager, source_path : string, shader_stage : ShaderStage, enable_hot_reloading : bool = false) -> ShaderID{

	shader_id : ShaderID = -1;

	if !os.exists(source_path) || !os.is_file(source_path) {
		log.errorf("Faild to register shader source. Path is not an existing file. Path: {}", source_path);
		return shader_id;
	}

	clean_path , alloc_err := os.clean_path(source_path, context.allocator);
	if alloc_err != nil {
		log.errorf("Faild to register shader source. Memory Allocation error");
		return shader_id;
	}

	new_entry := ShaderEntry{
		flags = {.EntryIsUsed},
		path  = clean_path,
		compile_info = ShaderCompileInfo2{shader_stage = shader_stage}
	}

	if enable_hot_reloading {
		new_entry.flags += {.HotReloadEnabled};
	}

	free_spot : int = -1;

	for i in 0..<len(manager.entries) {

		if .EntryIsUsed not_in manager.entries.flags[i] {
			free_spot = i;
			break;
		}
	}

	if free_spot != -1 {
		// Found a free spot.
		shader_id = cast(ShaderID)free_spot;

		manager.entries[shader_id] = new_entry;

	} else {

		shader_id = cast(ShaderID)len(manager.entries);
		append_soa(&manager.entries, new_entry);
	}
	
	if enable_hot_reloading {
		// Assign a file watcher
		
		free_watcher_spot : int = -1;

		for &watcher, index in manager.watchers {
			
			if watcher.shader_id < 0 { // Unused
				free_watcher_spot = index;
				break;
			}
		}

		if free_watcher_spot != -1 {
			// Found a free spot
			manager.watchers[free_watcher_spot].shader_id = shader_id;
			filey.clear_contents(&manager.watchers[free_watcher_spot].file_watcher)
		} else {

			watcher : ShaderSourceWatcher = {
				shader_id = shader_id,
			}
			append(&manager.watchers, watcher);
		}

	}

	return shader_id;
}

@(private="package")
shader_manager_unregister_shader_source :: proc(manager : ^ShaderManager, shader_id : ^ShaderID){

	engine_assert(manager != nil);
	engine_assert(shader_id != nil);

	defer shader_id^ = -1; // invalidate user id.

	id : int = cast(int)shader_id^;

	if id < 0 || id >= len(manager.entries) {
		return; // already invalid.
	}

	if .EntryIsUsed not_in manager.entries[id].flags {
		return; // already invalid.
	}


	if .HotReloadEnabled in manager.entries.flags[id] {
		
		// if hot reload was enabaled, unassign its file watcher
		// for which we currently must itterate them to find the matching ShaderID.

		for &watcher in manager.watchers {

			if watcher.shader_id == shader_id^{
				watcher.shader_id = -1;
				filey.clear_contents(&watcher.file_watcher);
				break;
			}
		}
	}

	delete(manager.entries[id].path); // free old path string
	manager.entries[id].flags = ShaderEntryFlags{}; // clear flags.
	manager.entries[id].compile_info = ShaderCompileInfo2{}; // clear compile info structure.

	return;
}

@(private="package")
shader_manager_is_valid_shader_id :: proc(manager : ^ShaderManager, shader_id : ShaderID) -> bool {

	id : int = cast(int)shader_id;

	if id < 0 || id >= len(manager.entries) {
		return false;
	}

	if .EntryIsUsed not_in manager.entries[id].flags {
		return false;
	}

	return true;
}

@(private="package")
shader_manager_get_file_watcher_if_exists :: proc(manager : ^ShaderManager, shader_id : ShaderID) -> ^filey.FileWatcherData {
	
	engine_assert(shader_manager_is_valid_shader_id(manager, shader_id), "do not call this function before checking if the id is valid.")

	if .HotReloadEnabled in manager.entries.flags[shader_id] {

		for &watcher in manager.watchers {

			if watcher.shader_id == shader_id {
				return &watcher.file_watcher;
			}
		}
	}

	return nil;
}

@(private="package")
shader_manager_get_compile_info_ptr :: proc(manager : ^ShaderManager, shader_id : ShaderID) -> ^ShaderCompileInfo2{
	engine_assert(manager != nil)
	engine_assert(shader_manager_is_valid_shader_id(manager, shader_id), "Check before calling this function")

	return &manager.entries[shader_id].compile_info;
}

@(private="package")
shader_manager_get_shader_variant_hash :: proc(variant : ShaderVariant) -> u32 {

	hash : u32 = 0;

	if variant != nil {
		switch v in variant {
			case VertShaderVariant: 		hash = transmute(u32)v;
			case FragShaderVariant: 		hash = transmute(u32)v;
			case RenderEffectShaderVariant: hash = transmute(u32)v;
		}
	}

	return hash;
}

// Only For graphics stage shader .VERTEX or .FRAGMENT, otherwise probably crash
@(private="package")
shader_manager_get_or_load_gfx_shader_variant :: proc(manager : ^ShaderManager, gpu_device : ^sdl.GPUDevice, shader_id : ShaderID, variant : ShaderVariant = nil) -> ^sdl.GPUShader{

	engine_assert(manager != nil);
	engine_assert(shader_manager_is_valid_shader_id(manager, shader_id));

	// Shader hash is u64 and low 32 bits are the variant hash, high 32 bits the shader id.
	// There might just be a potential issue when removing shader source and recycling the shader id on next shader source register
	// where the shader cache might still be filled.
	// so we would have to somehow find all the shader_hash entries with the shader id we want to remove and remove them from the hashmap..
	shader_hash : u64;
	shader_hash_ : [^]u32 = cast([^]u32)&shader_hash;
	shader_hash_[0] = transmute(u32)shader_id
	shader_hash_[1] = shader_manager_get_shader_variant_hash(variant);
	

	shader, exists := manager.gfx_shader_cache[shader_hash]

	if exists && shader != nil {
		return shader;
	}


	spirv_or_err_str, compile_info, load_ok := shader_manager_load_or_compile_spirv_variant(manager, shader_id, variant);

	//log.warnf("Loading shaderID {}, variant {}", shader_id, variant);

	defer if load_ok {
		delete(spirv_or_err_str);
	}

	if !load_ok {
		log.errorf("Failed to load shader variant. ShaderID: {}, Variant: {}", shader_id, variant);
        log.errorf("{}", transmute(string)(spirv_or_err_str)); 
		return nil;
	}

	engine_assert(compile_info.shader_stage != .COMPUTE);



	// {

	// 	glsl_filepath : string = manager.entries.path[shader_id]; // the full path to the glsl source file.
	// 	glsl_filename : string = filepath.base(glsl_filepath); // the filename of the glsl source file.

	// 	log.debugf("load_shader {}, compile_info:\n{}", glsl_filename, compile_info);
	// }
	
	shader_variant : ^sdl.GPUShader = create_sdl_shader_from_spirv_2(gpu_device, spirv_or_err_str, compile_info)

	if shader_variant != nil {

		manager.gfx_shader_cache[shader_hash] = shader_variant;
	}

	return shader_variant;
}

@(private="package")
shader_manager_clear_gfx_shader_cache :: proc(manager : ^ShaderManager, gpu_device : ^sdl.GPUDevice){

	for key in manager.gfx_shader_cache {
		
		shader : ^sdl.GPUShader = manager.gfx_shader_cache[key];

		if shader != nil {
			sdl.ReleaseGPUShader(gpu_device, shader);
		}
		manager.gfx_shader_cache[key] = nil;
	}

	clear(&manager.gfx_shader_cache);
}



// Release and invalidate all variants of a shader_id in the gfx shader cache.
// this can be quite slow if there are a lot of shaders.
@(private="package")
shader_manager_clear_all_variants_for_shader_id_from_gfx_shader_cache :: proc(manager : ^ShaderManager, gpu_device : ^sdl.GPUDevice, shader_id : ShaderID) {

	// This can potentially be quite slow.
	for shader_hash in manager.gfx_shader_cache {

		s_hash_copy : u64 = shader_hash;

		s_hash : [^]i32 = cast([^]i32)&s_hash_copy;

		// ShaderID is encoded in the first 32 bits of the u64 hash key.
		cached_id : ShaderID = cast(ShaderID)s_hash[0];

		if cached_id == shader_id {
			shader : ^sdl.GPUShader = manager.gfx_shader_cache[shader_hash];
			sdl.ReleaseGPUShader(gpu_device, shader);
			manager.gfx_shader_cache[shader_hash] = nil;
		}
	}
}


/*
	Load the spirv for a shader_id with a given variant (aka. a set of defines).
	This procedure will select automatically wheather to load the spirv directly from file or if it needs to 
	load the glsl source code and transpile it to spirv.

	If hot reloading is enabled for the shader, it will always load from glsl source and transpile it to spirv.
	Otherwise the procedure will prefer to load the spirv variant directly from disk if
	it already exists and if the source glsl file was not modified more recently than the spirv.
	Every time glsl source has been transpiled successfully to spirv, the spirv will be written out to disk with a
	variant hash added to the filename. This hash is simply a u64 that is the bit cast from the variant bitset.  e.g. variant_hash : u64 = transmute(u64)ShaderVariant{.USE_ALPHA_TEST};
	This way, the hash is guranteed to be unique for each possible variant.
	If glsl source file does not exist, but spirv variant does. It will load spirv. For this HotReloading must be disabled.
	
	Returns spirv and a compile info struct if there was no error. If there was an error spirv will instead be an error string that contains also compile errors.
	The Error string is allocated using context.temp_allocator so it SHOULD NOT be freed.

	usage example:
	spirv_or_err_str, compile_info, load_ok := shader_manager_load_or_compile_spirv_variant(shader_manager, shader_id, ShaderVariant{.USE_ALPHA_TEST});	
	defer if load_ok {
		delete(spirv_or_err_str); // Only free memory if there was no error.
	}
	if !load_ok {
		log.errorf("Failed to load shader variant. msg:\n{}", transmute(string)(spirv_or_err_str)); 
		return;
	}
*/
@(private="package")
shader_manager_load_or_compile_spirv_variant :: proc(manager : ^ShaderManager, shader_id : ShaderID, variant : ShaderVariant = nil) -> (spirv_or_error_str : []byte, compile_info : ShaderCompileInfo2, ok : bool) {
	

	if !shader_manager_is_valid_shader_id(manager, shader_id) {
		err_str : string = fmt.aprintf("Failed to load shader variant for shader_id: '{}', id is invalid", cast(i32)shader_id, allocator = context.temp_allocator);
        return transmute([]u8)err_str, ShaderCompileInfo2{}, false;
	}


	shader_stage : ShaderStage = manager.entries[shader_id].compile_info.shader_stage;


	glsl_filepath : string = manager.entries.path[shader_id]; // the full path to the glsl source file.
	glsl_filename : string = os.base(glsl_filepath); // the filename of the glsl source file.

	variant_hash : u32 = shader_manager_get_shader_variant_hash(variant);

	variant_str_extention : string = fmt.aprintf("variant_{}", variant_hash, allocator = context.temp_allocator);

	// add variant to filename (filename.variant_000)
	spirv_filename, join_err := os.join_filename(glsl_filename, variant_str_extention, context.temp_allocator);
	engine_assert(join_err == os.ERROR_NONE);
	// add spv to filename (filename.variant_0.spv)
	spirv_filename, join_err = os.join_filename(spirv_filename,"spv", context.temp_allocator);
	engine_assert(join_err == os.ERROR_NONE);


	spirv_filepath , alloc_err := os.join_path({manager.spirv_folder_path, spirv_filename}, context.temp_allocator)
	engine_assert(alloc_err == nil);

	spirv_filepath , alloc_err = os.clean_path(spirv_filepath, context.temp_allocator);
	engine_assert(alloc_err == nil);

    glsl_exists  : bool = os.exists(glsl_filepath)  && os.is_file(glsl_filepath);
    spirv_exists : bool = os.exists(spirv_filepath) && os.is_file(spirv_filepath);

    if !glsl_exists && !spirv_exists{

        err_str : string = fmt.aprintf("Failed to load shader_id: '{}' from file, Neither glsl nor spirv filepaths exist: glsl-path: {}",cast(i32)shader_id, glsl_filepath, allocator = context.temp_allocator);
        return transmute([]u8)err_str, ShaderCompileInfo2{}, false;
    }	

    out_file_watcher : ^filey.FileWatcherData = shader_manager_get_file_watcher_if_exists(manager, shader_id);

    // @Note:
    // We want to prefer loading from spirv files directly since this is much faster.
    // However if spirv doesn't exist yet or the glsl source file was modified more recently than the spirv we choose glsl. 
    // Also if HotReloading is enabled and an out_file_watcher exsist, we always want to load from glsl 
    // because then we want to unfold the include files and record them for hot reloading..

    load_from_glsl: bool = false;

    if !spirv_exists {
        load_from_glsl = true;
    } else {

        if glsl_exists {

            if out_file_watcher != nil {
                load_from_glsl = true;
            } else {

                // check if glsl file is newer then spriv file in wich case we always want to load from glsl and update our spirv compilation
                glsl_file_time  , err1 := os.modification_time_by_path(glsl_filepath);
                spirv_file_time , err2 := os.modification_time_by_path(spirv_filepath);

                engine_assert(err1 == os.ERROR_NONE);
                engine_assert(err2 == os.ERROR_NONE);

                if glsl_file_time._nsec > spirv_file_time._nsec {
                    load_from_glsl = true;
                }
            }
        }
    }

    if load_from_glsl {

        record_include_files: bool = out_file_watcher == nil ? false : true;

        // @Note: for parsing the glsl we always record the include files so we can potentially print propper error messages with file path later
        // but we may not store them past this scope if hot reloading was not enabled.
        include_files: [dynamic]string;
        defer {
            for &str in include_files{
                delete(str);
            }
            delete(include_files);
        }

        parse_info := shady.ParseInfo {
            parse_flags = {.UnfoldIncludes, .ReplaceVersionString},
            out_include_files = &include_files,
            version_str  = "450",
        }

        define_strings : [dynamic]string;
        defer {
        	// for &str in define_strings{
            //     delete(str);
            // }
            delete(define_strings);
        }

        
        if variant != nil {

        	switch &v in variant {
        		case VertShaderVariant: {
        			if v != VERT_SHADER_VARIANT_EMPTY {
			        	for define_enum in v {
			        		append(&define_strings, fmt.aprintf("{}", define_enum , allocator = context.temp_allocator));
			        	}
        			}
        		}
        		case FragShaderVariant: {
        			if v != FRAG_SHADER_VARIANT_EMPTY {
			        	for define_enum in v {
			        		append(&define_strings, fmt.aprintf("{}", define_enum , allocator = context.temp_allocator));
			        	}
        			}
        		}
        		case RenderEffectShaderVariant: {
        			if v != RENDER_EFFECT_SHADER_VARIANT_EMPTY {
			        	for define_enum in v {
			        		append(&define_strings, fmt.aprintf("{}", define_enum , allocator = context.temp_allocator));
			        	}
        			}
        		}
        	}        

        	parse_info.insert_defines = define_strings[:];
        }

        glsl_src_code, parse_ok := shady.parse_glsl_file(glsl_filepath, &parse_info, context.allocator); 
        defer if glsl_src_code != nil {
            delete(glsl_src_code);
        }

        if !parse_ok {
            err_str : string = fmt.aprintf("Faild to parse glsl file: \n{}", parse_info.error_string, allocator = context.temp_allocator);
            return transmute([]u8)err_str,ShaderCompileInfo2{}, false;
        }
        
        // if parsing succeded, we want to write the include files to the filewatcher
        // even if we are later not able to transpile or create the shader succesfully because
        // we may hot reload it when a change (maybe typo fix) was made to one of the files.
        if out_file_watcher != nil && len(include_files) > 0 {
            filey.clear_contents(out_file_watcher);
            filey.add_files(out_file_watcher, include_files[:]);
        }
        
        WRITE_ASCI_SRC :: false
        when WRITE_ASCI_SRC {

            spirv_filepath_Asci, join_err := os.join_filename(spirv_filepath, "asci.glsl", context.temp_allocator);
            assert(join_err == os.ERROR_NONE)
            write_asci_err := os.write_entire_file_from_bytes(spirv_filepath_Asci, glsl_src_code)
        	assert(write_asci_err == os.ERROR_NONE);
        }

        reflect_info := shady.reflect_parse_glsl_src_code(glsl_src_code);
        shady_shader_stage := get_shady_ShaderStage_from_ShaderStage(shader_stage);
        
        spriv_or_error_str, transpile_success := shady.transpile_glsl_to_SPIRV(glsl_src_code , shady_shader_stage, shady.SpirvVersion.SPV_1_3, shady.ClientVersion.VULKAN_1_2,include_files[:]);

        if !transpile_success {            
            err_str : string = fmt.aprintf("Shader Compilation Failed: {}\n{}", glsl_filepath, transmute(string)spriv_or_error_str, allocator = context.temp_allocator);
            return transmute([]u8)err_str, ShaderCompileInfo2{} , false;
            //@Note: We don't free spriv_or_error_str here because when its an error message it was allocated using temp_allocator
        }


        hdr := create_custom_spirv_header(reflect_info, shader_stage);
        

        // Write Spirv with custom header to file.
        {
	        hdr_size : int = size_of(CustomSpirvHeader);
	        spirv_size : int = len(spriv_or_error_str);
	        byte_size : int = hdr_size + spirv_size;

	        custom_spirv := make_slice([]byte,  byte_size , context.allocator);
	        defer delete(custom_spirv);

	        mem.copy(&custom_spirv[0],&hdr, hdr_size);
	        mem.copy(&custom_spirv[hdr_size], &spriv_or_error_str[0], spirv_size);

	        write_err := os.write_entire_file_from_bytes(spirv_filepath, custom_spirv);
	        if write_err != os.ERROR_NONE {
	            log.errorf("Faild to write spirv file to disk after succesful compilation, Path: {}", spirv_filepath);
	        }
        }

        update_shader_compile_info2_with_custom_spirv_header(&manager.entries.compile_info[shader_id], hdr);

        return spriv_or_error_str, manager.entries.compile_info[shader_id], true;
    } 

    // Load from spir-v file directly

    custom_spirv, read_err := os.read_entire_file_from_path(spirv_filepath, context.allocator);
    defer if custom_spirv != nil {
    	delete(custom_spirv);
    }

    if read_err != os.ERROR_NONE {
        err_str : string = fmt.aprintf("Failed to load shader from SPIR-V file even though the file exists, path: {}", spirv_filepath, allocator = context.temp_allocator);
        return transmute([]u8)err_str,ShaderCompileInfo2{}, false;
    }

    // Extract header info
    hdr_size : int = size_of(CustomSpirvHeader);
    hdr : ^CustomSpirvHeader = cast(^CustomSpirvHeader)raw_data(custom_spirv[:hdr_size]);

    update_shader_compile_info2_with_custom_spirv_header(&manager.entries.compile_info[shader_id], hdr^);

    spirv_byte_size : int = len(custom_spirv) - size_of(CustomSpirvHeader);
    spirv_code := make_slice([]byte, spirv_byte_size, context.allocator);
    mem.copy(&spirv_code[0], &custom_spirv[hdr_size], spirv_byte_size);

    return spirv_code, manager.entries.compile_info[shader_id], true;
}