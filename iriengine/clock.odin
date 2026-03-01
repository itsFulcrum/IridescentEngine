package iri

import sdl "vendor:sdl3"

PerfTimer :: struct{
	begin_ns : u64,
}

timer_begin :: proc() -> PerfTimer {
	return PerfTimer{
		begin_ns = sdl.GetTicksNS(),
	}
}

timer_end_get_miliseconds :: proc(timer : PerfTimer) -> f64{
	timed_ns : u64 = sdl.GetTicksNS() - timer.begin_ns;

	return cast(f64)timed_ns * 0.000001; // to milisec
}


ClockData :: struct {

	elapsed_time : f64, // advances by delta time not true delta time.
	delta_time : f64, // scaled and clamped delta true delta time.
	
	true_elapsed_time : f64, // in seconds
	true_delta_time : f64, // in seconds

	max_delta_time : f64,
	timescale : f64,

	// Physics time stuff
	fixed_delta_accumulator : f64,
	fixed_delta_timestep : f64,
	fixed_elapsed_time : f64,
	should_advance_fixed : bool, // a variable for error handling


 	// FPS stuff
	second_accumulator: f64,
 	frames_since_last_second: u32,
 	current_fps: u32,
}

@(private="file")
clock_data: ClockData;


// @(private="file")
// clock_delta_seconds_min :: 0.0000000001;
// @(private="file")
// clock_delta_seconds_max :: 0.16; 
@(private="package")
clock_init :: proc(){
	clock_data.max_delta_time = 0.25;
	clock_data.timescale = 1.0;

	clock_data.elapsed_time = 0;
	clock_data.true_elapsed_time = clock_get_ticks_seconds();

	clock_data.delta_time = 0.0;
	clock_data.true_delta_time = 0.0;

	// physics
	clock_data.fixed_elapsed_time 		= 0.0;
	clock_data.fixed_delta_accumulator 	= 0.0;
	clock_data.fixed_delta_timestep 	= 0.01666; // 1 / 60 fps
	//clock_data.fixed_delta_timestep 	= 0.00606; // 1 / 165 fps
	clock_data.should_advance_fixed = false;
}

// Call this once per frame
@(private="package")
clock_tick_frame :: proc() -> f64{

	new_time : f64 = clock_get_ticks_seconds();
	clock_data.true_delta_time = new_time - clock_data.true_elapsed_time; 

	delta_time : f64 = clock_data.true_delta_time * clock_data.timescale;
	clock_data.delta_time = min(delta_time, clock_data.max_delta_time);

	clock_data.elapsed_time += clock_data.delta_time;
	clock_data.true_elapsed_time = new_time;

	clock_data.fixed_delta_accumulator += delta_time;

	// fps	
	clock_data.second_accumulator += clock_data.true_delta_time;
	
	clock_data.frames_since_last_second += 1;

	if(clock_data.second_accumulator >= 1.0){
		clock_data.second_accumulator = 0;
		
		clock_data.current_fps = clock_data.frames_since_last_second;
		clock_data.frames_since_last_second = 0;
	}

	return clock_data.delta_time;
}


// @Note - fulcrum.
// the next two procedures are used to determine the fixed update calls for physics updated.
// call 'clock_should_advance_fixed_timestep()' in a while loop and if we enter the while loop
// call 'clock_advance_fixed_timestep()'
// for clock_should_advance_fixed_timestep() {
// 	do_physics_update();
// 	clock_advance_fixed_timestep();
// }

@(private="package")
clock_should_advance_fixed_timestep :: proc() -> bool {

	engine_assert(clock_data.should_advance_fixed == false, "clock_advance_fixed_timestep() Must be called if this procedure returns true!");

	clock_data.should_advance_fixed = clock_data.fixed_delta_accumulator >= clock_data.fixed_delta_timestep;

	return clock_data.should_advance_fixed;
}

@(private="package")
clock_advance_fixed_timestep :: proc() {
	clock_data.fixed_elapsed_time += clock_data.fixed_delta_timestep;
	clock_data.fixed_delta_accumulator -= clock_data.fixed_delta_timestep;
	clock_data.should_advance_fixed = false;
}


clock_get_elapsed_time :: proc() -> f32 {
	return cast(f32)clock_data.elapsed_time;
}

clock_get_delta_time :: proc() -> f32{
	return cast(f32)clock_data.delta_time;
}

clock_get_true_elapsed_time :: proc() -> f64 {
	return clock_data.true_elapsed_time;
}

clock_get_true_delta_time :: proc() -> f64 {
	return clock_data.true_delta_time;
}

clock_get_fps :: proc() -> u32{
	return clock_data.current_fps;
}

// how often do we want to do physics updates
// for example timestep may be '1/60' to update 60 times per second;
clock_set_physics_timestep :: proc(timestep : f64){
	clock_data.fixed_delta_timestep = timestep;
}

clock_set_max_delta_time :: proc(max_delta_time : f64){
	clock_data.max_delta_time = max_delta_time;
}

clock_set_timescale :: proc(timescale : f64){
	clock_data.timescale = timescale;
}

clock_get_ticks_seconds :: proc() -> f64 {
	return cast(f64)sdl.GetTicks() / 1000.0;
}

clock_get_ticks_miliseconds :: proc() -> u64{
	return sdl.GetTicks();
}

clock_get_ticks_nanoseconds :: proc() -> u64{
	return sdl.GetTicksNS();	
}
