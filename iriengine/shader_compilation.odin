package iri

import "core:log"

import "core:mem"
import "core:strings"
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

	switch stage {
		case .VERTEX: 	return sdl.GPUShaderStage.VERTEX;
		case .FRAGMENT: return sdl.GPUShaderStage.FRAGMENT;
        case .COMPUTE:
	}

	return sdl.GPUShaderStage{};
}

@(private="package")
get_shady_ShaderStage_from_ShaderStage :: proc(stage : ShaderStage) -> shady.ShaderStage {

	switch stage {
		case .VERTEX: 	return shady.ShaderStage.VERTEX;
		case .FRAGMENT: return shady.ShaderStage.FRAGMENT;
        case .COMPUTE:  return shady.ShaderStage.COMPUTE;
	}

	return shady.ShaderStage.VERTEX;
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