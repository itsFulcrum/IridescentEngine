package iri

import "core:log"

import "core:mem"
import "core:strings"
import "core:path/filepath"
import "core:fmt"
import "core:os"

import sdl "vendor:sdl3"
import "odinary:filey"
import "odinary:shady"



ShaderStage :: enum {
    VERTEX = 0,
    FRAGMENT = 1,
    COMPUTE  = 2,
}

ShaderCompileInfo2 :: struct {
    shader_stage  : ShaderStage,

    num_samplers : u16, 
    num_uniform_buffers : u16,

    num_readonly_storage_textures  : u16,
    num_writeonly_storage_textures : u16,
    num_readwrite_storage_textures : u16,
    
    num_readonly_storage_buffers   : u16,
    num_writeonly_storage_buffers  : u16,
    num_readwrite_storage_buffers  : u16,

    num_storage_textures : u16,             // writeonly + readwrite + readonly
    num_writeable_storage_textures : u16,   // writeonly + readwrite

    num_storage_buffers : u16,              // writeonly + readwrite + readonly
    num_writeable_storage_buffers : u16,    // writeonly + readwrite

    compute_threadcount : [3]u32,
}

ShaderCompileInfo :: struct {
    src_filename         : string,  // The filename of the glsl source code. ONLY filename without entire path (like unlit.frag) 
    shader_stage         : ShaderStage,
    num_samplers         : u32, // The number of samplers defined in the shader.
    num_storage_textures : u32, // The number of storage textures defined in the shader.
    num_storage_buffers  : u32, // The number of storage buffers defined in the shader.
    num_uniform_buffers  : u32, // The number of uniform buffers defined in the shader.
}

CUSTOM_SPIRV_HEADER_VERSION : u32 : 1
CustomSpirvHeader :: struct #packed {
    hdr_version   : u32, 
    hdr_byte_size : u32,

    shader_stage  : u16, 
    num_samplers : u16, 
    num_uniform_buffers : u16,

    num_readonly_storage_textures  : u16,
    num_writeonly_storage_textures : u16,
    num_readwrite_storage_textures : u16,
    num_readonly_storage_buffers   : u16,
    num_writeonly_storage_buffers  : u16,
    num_readwrite_storage_buffers  : u16,

    compute_threadcount_x : u16,
    compute_threadcount_y : u16,
    compute_threadcount_z : u16,
}

@(private="package")
create_sdl_shader_from_spirv :: proc(gpu_device: ^sdl.GPUDevice, spirv_code: []byte, compile_info: ShaderCompileInfo) -> ^sdl.GPUShader {

    engine_assert(spirv_code != nil);

    shader_create_info := sdl.GPUShaderCreateInfo {
        code_size = len(spirv_code),                   // The size in bytes of the code pointed to.
        code = raw_data(spirv_code),                   // A pointer to shader code.
        
        entrypoint = "main",                            // A pointer to a null-terminated UTF-8 string specifying the entry point function name for the shader.
        format = {sdl.GPUShaderFormat.SPIRV},
        stage = get_sdl_GPUShaderStage_from_ShaderStage(compile_info.shader_stage),

        num_samplers         = compile_info.num_samplers,
        num_storage_textures = compile_info.num_storage_textures,
        num_storage_buffers  = compile_info.num_storage_buffers,
        num_uniform_buffers  = compile_info.num_uniform_buffers,
    }

    return sdl.CreateGPUShader(gpu_device, shader_create_info);
}

@(private="package")
create_sdl_shader_from_spirv_2 :: proc(gpu_device: ^sdl.GPUDevice, spirv_code: []byte, compile_info: ShaderCompileInfo2) -> ^sdl.GPUShader {

    engine_assert(spirv_code != nil);

    shader_create_info := sdl.GPUShaderCreateInfo {
        code_size = len(spirv_code),                   // The size in bytes of the code pointed to.
        code = raw_data(spirv_code),                   // A pointer to shader code.
        
        entrypoint = "main",                            // A pointer to a null-terminated UTF-8 string specifying the entry point function name for the shader.
        format = {sdl.GPUShaderFormat.SPIRV},
        stage = get_sdl_GPUShaderStage_from_ShaderStage(compile_info.shader_stage),

        num_samplers         = cast(u32)compile_info.num_samplers,
        num_storage_textures = cast(u32)compile_info.num_storage_textures,
        num_storage_buffers  = cast(u32)compile_info.num_storage_buffers,
        num_uniform_buffers  = cast(u32)compile_info.num_uniform_buffers,
    }

    return sdl.CreateGPUShader(gpu_device, shader_create_info);
}


@(private="package")
get_sdl_GPUShaderStage_from_ShaderStage :: proc(stage : ShaderStage) -> sdl.GPUShaderStage {

    assert(stage != ShaderStage.COMPUTE, "Cannot Convert Compute shader stage to sdl.GPUShaderStage");

	switch (stage){
		case .VERTEX: 	return sdl.GPUShaderStage.VERTEX;
		case .FRAGMENT: return sdl.GPUShaderStage.FRAGMENT;
        case .COMPUTE:
	}

	return sdl.GPUShaderStage{};
}

@(private="package")
get_shady_ShaderStage_from_ShaderStage :: proc(stage : ShaderStage) -> shady.ShaderStage {

	switch (stage){
		case .VERTEX: 	return shady.ShaderStage.VERTEX;
		case .FRAGMENT: return shady.ShaderStage.FRAGMENT;
        case .COMPUTE:  return shady.ShaderStage.COMPUTE;
	}

	return shady.ShaderStage.VERTEX;
}



// @Note: Load a shader, given its filename, from disk and select wheather to load directly from spirv file or glsl source file. 
// 'src_glsl_filename' should be the GLSL source file and NOT contain the full filepath only the filename itself!

// If 'out_file_watcher' is not nil, the implementation will always try to load from the source glsl file and record all include files into the 'out_file_watcher' and then transpile it to spirv.
// When 'out_file_watcher' is nil procedure will first try to find the spirv compiled version with filename 'src_glsl_filename' + '.spv' extention, in the folder path for spirv within the PipelineContext.
// if '.spv' does not exists, or the source glsl file has been modified more recently, will instead load from glsl, transpile to spirv.
// Every time glsl has been transpiled successfully to spirv, the spirv will be written out to disk.

@(private="package")
load_spirv_direct_or_transpile_glsl :: proc(gpu_device: ^sdl.GPUDevice, src_glsl_filename: string, glsl_folder_path : string, spirv_folder_path : string, shader_stage: ShaderStage, out_file_watcher: ^filey.FileWatcherData = nil) -> (spriv_or_error_str : []byte, ok : bool) {

    spirv_filename := strings.join({src_glsl_filename, ".spv"}, "", context.temp_allocator);

    spirv_filepath_clean := filepath.clean(filepath.join({spirv_folder_path, spirv_filename}, context.temp_allocator), context.temp_allocator);    
    glsl_filepath_clean  := filepath.clean(filepath.join({glsl_folder_path, src_glsl_filename}, context.temp_allocator), context.temp_allocator);

    glsl_exists  := os.exists(glsl_filepath_clean);
    spirv_exists := os.exists(spirv_filepath_clean);

    if !glsl_exists && !spirv_exists{

        err_str : string = fmt.aprintf("Failed to load shader from file, Neither glsl nor spirv filepaths exist: glsl-path: {}", glsl_filepath_clean, allocator = context.temp_allocator);
        return transmute([]u8)err_str, false;
    }



    // We want to prefer loading from spirv directly however if spirv doesn't exist yet or the glsl version is newer than spirv 
    // we choose glsl. Also if a out_file_watcher is not nil we always want to load glsl if possible because then we want to unfold the include files and record them for hot reloading..

    load_from_glsl: bool = false;

    if !spirv_exists {
        load_from_glsl = true;
    } else {

        if glsl_exists {

            if out_file_watcher != nil {
                load_from_glsl = true;
            } else {

                // check if glsl file is newer then spriv file in wich case we always want to load from glsl and update our spirv compilation
                glsl_file_time , err1 := os.last_write_time_by_name(glsl_filepath_clean);
                spirv_file_time , err2 := os.last_write_time_by_name(spirv_filepath_clean);

                engine_assert(err1 == os.ERROR_NONE);
                engine_assert(err2 == os.ERROR_NONE);

                if(glsl_file_time > spirv_file_time){
                    load_from_glsl = true;
                }
            }
        }
    }


    if load_from_glsl {


        record_include_files: bool = out_file_watcher == nil ? false : true;

        include_files: [dynamic]string;
        defer {
            for &str in include_files{
                delete(str);
            }
            delete(include_files);
        }

        parse_info := shady.ParseInfo {
            parse_flags = {.UnfoldIncludes, .GenerateHeaderguards, .ReplaceVersionString},
            out_include_files = record_include_files ? &include_files : nil,
            //insert_defines = ci.insert_defines[:],
            version_str  = "450",
        }

        glsl_src_code, parse_ok := shady.parse_glsl_file(glsl_filepath_clean, &parse_info, context.allocator); 
        defer if glsl_src_code != nil {
            delete(glsl_src_code);
        }

        if !parse_ok {
            err_str : string = fmt.aprintf("Faild to parse glsl file: \n{}", parse_info.error_string, allocator = context.temp_allocator);
            return transmute([]u8)err_str, false;
        }
        
        
        WRITE_ASCI_SRC :: false
        when WRITE_ASCI_SRC {
            spirv_filepath_Asci := strings.join({spirv_filepath_clean, ".asci.glsl"}, "", context.temp_allocator);
            test := os.write_entire_file(spirv_filepath_Asci, glsl_src_code);
        }

        // if parsing succeded we want to write the include files to filewatcher even if we are later not able to transpile or create the shader succesfully so that we may hot reload it when a change (maybe typo fix) was made to one of the files.
        if out_file_watcher != nil && len(include_files) > 0 {
            filey.clear_contents(out_file_watcher);
            filey.add_files(out_file_watcher, include_files[:]);
        }


        reflect_info := shady.reflect_parse_glsl_src_code(glsl_src_code);

        TEST_REFLECT :: false
        when TEST_REFLECT {
            log.debugf("ReflectInfo: {} \n{}",src_glsl_filename, reflect_info);
        }


        shady_shader_stage := get_shady_ShaderStage_from_ShaderStage(shader_stage);
        
        files : []string = nil;
        if out_file_watcher != nil{
            files = out_file_watcher._filepaths[:];
        }
        
        spriv_or_error_str, transpile_success := shady.transpile_glsl_to_SPIRV(glsl_src_code , shady_shader_stage, shady.SpirvVersion.SPV_1_3, shady.ClientVersion.VULKAN_1_2,files);
        defer if transpile_success {
            delete(spriv_or_error_str);
        }

        if !transpile_success {            
            err_str : string = fmt.aprintf("Shader Compilation Failed: {}\n{}", glsl_filepath_clean, transmute(string)spriv_or_error_str, allocator = context.temp_allocator);
            return transmute([]u8)err_str, false;
            //@Note: We don't free spriv_or_error_str here because when its an error message it was allocated using temp_allocator
        }

        hdr := create_custom_spirv_header(reflect_info, shader_stage);

        hdr_size : int = size_of(CustomSpirvHeader);
        spirv_size : int = len(spriv_or_error_str);
        byte_size : int = hdr_size + spirv_size;

        custom_spirv := make_slice([]byte,  byte_size , context.allocator);
        //custom_spirv := make_slice([]byte,  spirv_size , context.allocator);

        mem.copy(&custom_spirv[0],&hdr, hdr_size);
        mem.copy(&custom_spirv[hdr_size], &spriv_or_error_str[0], spirv_size);
        //mem.copy(&custom_spirv[0], &spriv_or_error_str[0], spirv_size);

        write_success := os.write_entire_file(spirv_filepath_clean, custom_spirv);
        if !write_success {
            log.warnf("Faild to write spirv file to disk after succesful compilation, Path: {}", spirv_filepath_clean);
        }

        return custom_spirv, true;

    } else { // Load from spir-v file

        spirv_code, read_success := os.read_entire_file_from_filename(spirv_filepath_clean);

        if !read_success {

            err_str : string = fmt.aprintf("Failed to load shader from SPIR-V file even though the file exists, path: {}", spirv_filepath_clean, allocator = context.temp_allocator);
            return transmute([]u8)err_str, false;
        }

        return spirv_code, true;
    }

    panic("Invalid Codepath")
}


@(private="package")
create_custom_spirv_header :: proc(reflect_info : shady.ReflectInfo, shader_stage : ShaderStage) -> CustomSpirvHeader {

    hdr : CustomSpirvHeader;
    hdr.hdr_version = CUSTOM_SPIRV_HEADER_VERSION;
    hdr.hdr_byte_size = size_of(CustomSpirvHeader);

    hdr.shader_stage = cast(u16)shader_stage;

    hdr.num_samplers                    = cast(u16)reflect_info.num_samplers;
    hdr.num_uniform_buffers             = cast(u16)reflect_info.num_uniform_buffers;

    hdr.num_readonly_storage_textures   = cast(u16)reflect_info.num_readonly_storage_textures;
    hdr.num_writeonly_storage_textures  = cast(u16)reflect_info.num_writeonly_storage_textures;
    hdr.num_readwrite_storage_textures  = cast(u16)reflect_info.num_readwrite_storage_textures;

    hdr.num_readonly_storage_buffers    = cast(u16)reflect_info.num_readonly_storage_buffers;
    hdr.num_writeonly_storage_buffers   = cast(u16)reflect_info.num_writeonly_storage_buffers;
    hdr.num_readwrite_storage_buffers   = cast(u16)reflect_info.num_readwrite_storage_buffers;

    hdr.compute_threadcount_x           = cast(u16)reflect_info.compute_threadcount.x;
    hdr.compute_threadcount_y           = cast(u16)reflect_info.compute_threadcount.y;
    hdr.compute_threadcount_z           = cast(u16)reflect_info.compute_threadcount.z;

    return hdr;
}

@(private="package")
update_shader_compile_info2_with_custom_spirv_header :: proc(info : ^ShaderCompileInfo2, hdr : CustomSpirvHeader){

    info.shader_stage = cast(ShaderStage)hdr.shader_stage;
    
    info.num_samplers         = hdr.num_samplers;
    info.num_uniform_buffers  = hdr.num_uniform_buffers;

    info.num_readonly_storage_textures  = hdr.num_readonly_storage_textures;
    info.num_writeonly_storage_textures = hdr.num_writeonly_storage_textures;
    info.num_readwrite_storage_textures = hdr.num_readwrite_storage_textures;
    
    info.num_readonly_storage_buffers   = hdr.num_readonly_storage_buffers;
    info.num_writeonly_storage_buffers  = hdr.num_writeonly_storage_buffers;
    info.num_readwrite_storage_buffers  = hdr.num_readwrite_storage_buffers;

    // writeonly + readwrite + readonly
    info.num_storage_textures = hdr.num_readonly_storage_textures + hdr.num_writeonly_storage_textures + hdr.num_readwrite_storage_textures;
    // writeonly + readwrite
    info.num_writeable_storage_textures = hdr.num_writeonly_storage_textures + hdr.num_readwrite_storage_textures; 

    // writeonly + readwrite + readonly
    info.num_storage_buffers  = hdr.num_readonly_storage_buffers  + hdr.num_writeonly_storage_buffers  + hdr.num_readwrite_storage_buffers;
    // writeonly + readwrite
    info.num_writeable_storage_buffers = hdr.num_writeonly_storage_buffers + hdr.num_readwrite_storage_buffers;  

    info.compute_threadcount = [3]u32{cast(u32)hdr.compute_threadcount_x, cast(u32)hdr.compute_threadcount_y, cast(u32)hdr.compute_threadcount_z};
}



@(private="package")
update_shader_compile_info_with_custom_spirv_header :: proc(info : ^ShaderCompileInfo, hdr : CustomSpirvHeader){

    info.shader_stage         = cast(ShaderStage)hdr.shader_stage;
    info.num_samplers         = cast(u32)hdr.num_samplers;
    info.num_storage_textures = cast(u32)(hdr.num_readonly_storage_textures + hdr.num_writeonly_storage_textures + hdr.num_readwrite_storage_textures);
    info.num_storage_buffers  = cast(u32)(hdr.num_readonly_storage_buffers  + hdr.num_writeonly_storage_buffers  + hdr.num_readwrite_storage_buffers);
    info.num_uniform_buffers  = cast(u32)hdr.num_uniform_buffers;
}