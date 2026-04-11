package iriedit

import iri "../iriengine"

import im "odinary:dear_imguy"


draw_base_info :: proc(){
	
	fps := iri.clock_get_fps();
	
	frametime := iri.clock_get_true_delta_time() * 1000.0; // to miliseconds

	im.Text("FPS: %i", fps);
	im.Text("Frametime: %f ms", frametime);


	im.Spacing();

	frame_size := iri.get_frame_size();
	swap_size := iri.get_swapchain_size();

	im.Text("Frame Size:     %dx%dpx", frame_size.x, frame_size.y);
	im.Text("Swapchain Size: %dx%dpx", swap_size.x, swap_size.y);

	interp : f32 = cast(f32)iri.clock_get_fixed_alpha_interpolator();
	im.Text("Alpha Interpolator: %f", interp);
}