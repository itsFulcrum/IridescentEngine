package iri

import sdl "vendor:sdl3"

SwapchainSettings :: struct {
    present_mode : SwapchainPresentMode,
    color_space  : SwapchainColorSpace,
}

WindowContext :: struct {
	handle: ^sdl.Window,
	gpu_device: ^sdl.GPUDevice,
	swapchain_settings: SwapchainSettings,
    in_fullscreen_mode : bool, // only read don't write manually, use window_set_fullscreen();
}



SwapchainPresentMode :: enum {
    VSync = 0,
    Immediate,
    Mailbox,
}

@(private="package")
get_sdl_GPUPresentMode_from_SwapchainPresentMode :: proc(swapchain_present_mode : SwapchainPresentMode) -> sdl.GPUPresentMode {

    switch (swapchain_present_mode){
        case SwapchainPresentMode.VSync:                  return sdl.GPUPresentMode.VSYNC;
        case SwapchainPresentMode.Immediate:    return sdl.GPUPresentMode.IMMEDIATE;
        case SwapchainPresentMode.Mailbox:      return sdl.GPUPresentMode.MAILBOX;
    }
    // invalid codepath
    return sdl.GPUPresentMode.VSYNC;
}

@(private="package")
get_SwapchainPresentMode_from_sdl_GPUPresentMode :: proc(gpu_present_mode: sdl.GPUPresentMode) -> SwapchainPresentMode {

    #partial switch (gpu_present_mode){
        case sdl.GPUPresentMode.VSYNC:		return SwapchainPresentMode.VSync;
        case sdl.GPUPresentMode.IMMEDIATE:  return SwapchainPresentMode.Immediate;
        case sdl.GPUPresentMode.MAILBOX:    return SwapchainPresentMode.Mailbox;
    }
    // invalid codepath
    return SwapchainPresentMode.VSync;
}



/*
    Srgb means that the swapchain texture expects values to be in sRGB color space. When we write to the swapchain our values need to be in sRGB space.
    Linear means that values are still stored in sRGB in memory but the GPU automatically performs sRGB to Linear on reads and Linear to sRGB on writes. 
    Thus we can effectivly treat it as a linear buffer and write linear values to it. (GPU converts them to sRGB automatically).

    The Engine will do all its lighting calculations in linear space, therefore when using Srgb we need to manually convert at the very end, and if using Linear, we don't as GPU does it.
    Linear is generally preffered as the GPU can do the convertions more efficiantly that we can using pow() function. However we may want to specify a custom 'or user specified' gamma value
    Since not all moitors are the same. In that case we would use Srgb and do it ourselves.
    The Engine will automatically apply manual sRGB conversion in its pos prosessing pass when using Srgb but skip it if using Linear.


    The underling texture Formats for Srgb are either R8B8G8A8 or B8G8R8A, 
    For Linear the formats are R8G8B8A8_SRGB or B8G8R8A_SRGB. The '_SRGB' prefix in Graphics API lands mean that GPU will do sRGB convertions for us.
*/

SwapchainColorSpace :: enum {
    Srgb = 0,
    Linear = 1,
    Hdr_Linear_Extended = 2,
    Hdr10_st2084 = 3,
}

@(private="package")
get_sdl_GPUSwapchainComposition_from_SwapchainColorSpace :: proc(swapchain_color_space : SwapchainColorSpace) -> sdl.GPUSwapchainComposition {

    switch (swapchain_color_space){
        case SwapchainColorSpace.Srgb:                  return sdl.GPUSwapchainComposition.SDR;
        case SwapchainColorSpace.Linear:                return sdl.GPUSwapchainComposition.SDR_LINEAR;
        case SwapchainColorSpace.Hdr_Linear_Extended:   return sdl.GPUSwapchainComposition.HDR_EXTENDED_LINEAR;
        case SwapchainColorSpace.Hdr10_st2084:          return sdl.GPUSwapchainComposition.HDR10_ST2084;
    }
    // invalid codepath
    return sdl.GPUSwapchainComposition.SDR;
}

@(private="package")
get_SwapchainColorSpace_from_sdl_GPUSwapchainComposition :: proc(swapchain_composition: sdl.GPUSwapchainComposition) -> SwapchainColorSpace {

    switch (swapchain_composition){
        case sdl.GPUSwapchainComposition.SDR:					return SwapchainColorSpace.Srgb;
        case sdl.GPUSwapchainComposition.SDR_LINEAR:			return SwapchainColorSpace.Linear;
        case sdl.GPUSwapchainComposition.HDR_EXTENDED_LINEAR: 	return SwapchainColorSpace.Hdr_Linear_Extended;
        case sdl.GPUSwapchainComposition.HDR10_ST2084: 			return SwapchainColorSpace.Hdr10_st2084;
    }
    // invalid codepath
    return SwapchainColorSpace.Srgb;
}