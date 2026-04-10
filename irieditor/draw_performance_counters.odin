package iriedit

import iri "../iriengine"

import im "odinary:dear_imguy"

draw_performance_counters :: proc(){

	perfs := iri.get_performance_counters();

	im.Text("Universe total update time %f", perfs.universe_total_update_time_ms);

	im.Text("Frustum Culled instance %u", perfs.frustum_culled_instance);
	im.Text("Frustum Culling Time %f ms", perfs.frustum_culling_time_ms);


	im.Spacing()
	im.Spacing()

	im.Text("Rendering");
	
	im.Spacing()
	im.Text("Depth Prepass CPU %f ms", perfs.depth_prepass_cpu_ms);
	im.Spacing()
	im.Text("Depth Prepass draw calls    %u", perfs.depth_prepass_drawcalls);
	im.Text("Depth Prepass pipe switches %u", perfs.depth_prepass_num_pipeline_switches);

	
	im.Spacing()
	im.Text("Shadowmap Pass CPU %f ms", perfs.shadowmap_pass_cpu_ms);
	im.Spacing()
	im.Text("Shadowmap Pass draw calls    %u", perfs.shadowmap_pass_drawcalls);
	im.Text("Shadowmap Pass pipe switches %u", perfs.shadowmap_pass_num_pipeline_switches);
	im.Text("Shadowmap Pass rendered shadomaps %u", perfs.shadowmap_pass_num_rendered_shadowmaps);


	im.Spacing()
	im.Spacing()
	im.Text("Forward Pass CPU %f ms"   , perfs.forward_pass_cpu_ms);
	im.Spacing()
	im.Text("Forward Pass draw calls    %u", perfs.forward_pass_drawcalls);
	im.Text("Forward Pass pipe switches %u", perfs.forward_pass_num_pipeline_switches);
}