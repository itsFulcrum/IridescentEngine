package iri

PerformanceCounters :: struct {

	// Universe 
	universe_total_update_time_ms : f64,
	frustum_culled_instance : u32,
	frustum_culling_time_ms : f64,


	// Rendering
    //num_rendered_meshes_instances : u32,

    depth_prepass_cpu_ms : f64,
    depth_prepass_drawcalls : u32,
    depth_prepass_num_pipeline_switches : u32,

    forward_pass_cpu_ms : f64,
    forward_pass_drawcalls : u32,
    forward_pass_num_pipeline_switches : u32,

    shadowmap_pass_cpu_ms : f64,
    shadowmap_pass_drawcalls : u32,
    shadowmap_pass_num_rendered_shadowmaps : u32,
    shadowmap_pass_num_pipeline_switches : u32,
}