package iriedit

import iri "../iriengine"
import im "odinary:dear_imguy"

draw_main_menu_bar :: proc() {

	if im.BeginMainMenuBar() {
		defer im.EndMainMenuBar();

		draw_views_menu();
		draw_debug_display_menu();
	}
}


@(private="file")
draw_views_menu :: proc(){


	if im.BeginMenu("Views") {
		defer im.EndMenu();

		enum_flags_checkbox("Settings"        , EditorWindow.Settings      , &editor.enabled_windows);
		enum_flags_checkbox("Universe Viewer" , EditorWindow.UniverseViewer, &editor.enabled_windows);
		enum_flags_checkbox("Project Browser" , EditorWindow.ProjectBrowser, &editor.enabled_windows);
		enum_flags_checkbox("Properties Panel", EditorWindow.Properties    , &editor.enabled_windows);
	}
}

@(private="file")
draw_debug_display_menu :: proc() {

	flags : iri.DebugDisplayFlags = iri.debug_draw_manager_get_display_flags();

	if im.BeginMenu("Debug Display") {
		defer im.EndMenu();

		enabled : bool = iri.debug_draw_manager_is_enabled();
		all_disabled : bool = !enabled;
		if im.Checkbox("Disable All", &all_disabled){
			iri.debug_draw_manager_set_enabled(!all_disabled);

		}


		any_changed : bool = false;

		any_changed |= enum_flags_checkbox("Draw AABB"      , iri.DebugDisplayFlag.DrawAABB     , &flags);
		any_changed |= enum_flags_checkbox("Draw OOBB"  	, iri.DebugDisplayFlag.DrawOOBB		, &flags);
		any_changed |= enum_flags_checkbox("Draw Colliders" , iri.DebugDisplayFlag.DrawCollider	, &flags);
		any_changed |= enum_flags_checkbox("Draw Lights"    , iri.DebugDisplayFlag.DrawLights 	, &flags);
		any_changed |= enum_flags_checkbox("Draw Camera Frustum" , iri.DebugDisplayFlag.DrawCameraFrustum 	, &flags);

		if any_changed {
			iri.debug_draw_manager_set_display_flags(flags);
		}
	}
}