package iriedit

import "core:math"
import "core:math/linalg"

import iri "../iriengine"
import im "odinary:dear_imguy"


draw_render_settings :: proc(){

	window := iri.get_window_context();
	ren_config := iri.get_render_config();


	is_fullscreen := window.in_fullscreen_mode;
	if im.Checkbox("Enable Fullscreen", &is_fullscreen) {
		iri.window_set_fullscreen(is_fullscreen);
	}
	im.SetItemTooltip("call: window_set_fullscreen(fullscreen: bool) -> bool ");

	// Render Resolution
	{
		current_resolution_cstr := fmt_cstr("{}", ren_config.render_resolution);

		im.SetNextItemWidth(150);

		if im.BeginCombo("Render Resolution", current_resolution_cstr){
			for resolution_mode in iri.RenderResolution {

				resolution_mode_cstr := fmt_cstr("{}", resolution_mode);

				if im.Selectable(resolution_mode_cstr) {
					iri.set_render_resolution(resolution_mode);
					break;
				}
			}

			im.EndCombo();
		}

		im.SetItemTooltip("call: set_render_resolution(render_resolution: RenderResolution)");
	}

	// Present Modes
	{
		present_mode_cstr := fmt_cstr("{}", window.swapchain_settings.present_mode);

		im.SetNextItemWidth(150);
		if im.BeginCombo("Present Mode", present_mode_cstr){
			for mode in iri.SwapchainPresentMode {

				mode_cstr := fmt_cstr("{}", mode);

				if im.Selectable(mode_cstr) {

					iri.window_set_present_mode(mode);
					break;
				}
			}

			im.EndCombo();
		}

		im.SetItemTooltip("call: window_set_present_mode(target_mode: SwapchainPresentMode) -> bool ");
	}

	// Swapchain Color Space
	{
		curr_space_cstr := fmt_cstr("{}", window.swapchain_settings.color_space);

		im.SetNextItemWidth(150);
		if im.BeginCombo("Swapchain Color Space", curr_space_cstr) {
			for space in iri.SwapchainColorSpace {

				space_cstr := fmt_cstr("{}", space);

				if im.Selectable(space_cstr) {

					iri.window_set_color_space(space);
					break;
				}
			}

			im.EndCombo();
		}

		im.SetItemTooltip("call: window_set_color_space(target_color_space: SwapchainColorSpace) -> bool ");
	}

	im.Spacing();
	im.Spacing();
	im.Spacing();

	// Render Target
	{
		curr_format_cstr := fmt_cstr("{}", ren_config.geo_color_target_format);

		im.SetNextItemWidth(150);
		if im.BeginCombo("Render Target Format", curr_format_cstr) {
				
				for format in iri.RenderTargetFormat {

					format_cstr := fmt_cstr("{}", format);

					if im.Selectable(format_cstr) {

						iri.set_render_target_format(format);
						break;
					}
				}

			im.EndCombo();
		}

		im.SetItemTooltip("call: set_render_target_format(format: RenderTargetFormat)");
	}

	// Depth Target
	{
		curr_depth_format_cstr := fmt_cstr("{}", ren_config.geo_depth_stencil_format);

		im.SetNextItemWidth(150);
		if im.BeginCombo("Depth Target Format", curr_depth_format_cstr) {
				
				for format in iri.DepthStencilFormat {

					format_cstr := fmt_cstr("{}", format);

					if im.Selectable(format_cstr) {

						iri.set_depth_stencil_target_format(format);
						break;
					}
				}

			im.EndCombo();
		}
		im.SetItemTooltip("call: set_depth_stencil_target_format(format: DepthStencilFormat)");
	}

	
	im.Spacing();
	im.Spacing();
	im.Text("Render Effects ")
	im.Spacing();

	// Render Effect GTAO
	{
		GTAO_effect_enabled : bool = .GTAO in ren_config.ren_effect_flags;

		if im.Checkbox("GTAO Effect Enable", &GTAO_effect_enabled){

			if GTAO_effect_enabled {
				iri.enable_render_effects({.GTAO});
			} else {
				iri.disable_render_effects({.GTAO});
			}
		}
		im.SetItemTooltip("call: enable_render_effects(effects : RenderingEffectFlags)\ncall: set_ren_effect_GTAO_settings(settings : RenEffectGTAOSettings)");

		if GTAO_effect_enabled {

			ao_settings := iri.get_ren_effect_GTAO_settings();

			any_changed : bool = false;

			any_changed |= im.Checkbox("Temporary Disable", &ao_settings.temporary_disabled)
			any_changed |= im.Checkbox("Full Resolution", &ao_settings.full_res)
			
			im.Spacing();

			any_changed |= im.DragFloat("AO strength  ", &ao_settings.strength , 0.05, 0.1, 10.0)

			sample_count_int : i32 = cast(i32)ao_settings.sample_count;
			if im.DragInt("AO sample count  ", &sample_count_int, 1, 1, 100) {
				ao_settings.sample_count = cast(u32)sample_count_int;
				any_changed = true;
			}

			slice_count_int : i32 = cast(i32)ao_settings.slice_count;
			if im.DragInt("AO slice count  ", &slice_count_int, 1, 1, 100) {
				ao_settings.slice_count = cast(u32)slice_count_int;
				any_changed = true;
			}

			any_changed |= im.DragFloat("AO sample radius ", &ao_settings.sample_radius, 0.01, 0.001, 100.0)
			any_changed |= im.DragFloat("AO hit thickness ", &ao_settings.hit_thickness, 0.01, 0.001, 100.0)
			

			if any_changed {
				iri.set_ren_effect_GTAO_settings(ao_settings);
			}

			im.Spacing();
			im.Spacing();
		}
	}

	// Render Effect SMAA
	{
		SMAA_effect_enabled : bool = .SMAA in ren_config.ren_effect_flags;

		if im.Checkbox("SMAA Effect Enable", &SMAA_effect_enabled){

			if SMAA_effect_enabled {
				iri.enable_render_effects({.SMAA});
			} else {
				iri.disable_render_effects({.SMAA});
			}
		}

		if SMAA_effect_enabled {

			smaa_settings := iri.get_ren_effect_SMAA_settings();

			any_changed : bool = false;

			any_changed |= im.Checkbox("SMAA Temporary Disable", &smaa_settings.temporary_disabled)

			if any_changed {
				iri.set_ren_effect_SMAA_settings(smaa_settings);
			}

			im.Spacing();
			im.Spacing();
		}
	}
}