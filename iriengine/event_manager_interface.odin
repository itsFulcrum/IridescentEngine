package iri


// @Note
// 'elapsed_time' is the seconds since this time event started executing. May exceed the event duration by a small amout at the last call.
// 'progression_normalized_01' is a normalized progression of the time event (elapsed_time / duration) and ensured to be in range 0..1. Last call always has a value of 1 unless manually stopped. Can be used to lerp stuff over time.
// 'user_data' is just a raw pointer that is passed through. 
TimeEvent_CallbackSignature :: #type proc(event_id : TimeEventID, elapsed_time : f32, progression_normalized_01 : f32, user_data : rawptr)
IntervalEvent_CallbackSignature :: #type proc(event_id : IntervalEventID, interval_elapsed_time : f32, interval_progression_normalized_01 : f32, curr_interval : u32, user_data : rawptr)

// - delay_sec: For how long to wait until starting to executing
// - duration_sec: For how long to execture the callback.
// - use_true_time: wheather to use true unmodified delta time for updating. If false used game delta time which is scaled by a timescale factor and may even be 0 during pause
// - user_data: arbitrary user data to pass along.
schedule_time_event :: proc(callback_proc : TimeEvent_CallbackSignature, delay_sec : f32, duration_sec : f32, use_true_time : bool = false, user_data : rawptr = nil) -> TimeEventID {
	return event_manager_schedule_time_event(engine.event_manager, callback_proc, delay_sec, duration_sec, use_true_time, user_data);
}

unschedule_time_event :: proc(time_event_id : ^TimeEventID) {
	event_manager_unschedule_time_event(engine.event_manager, time_event_id);
}

pause_time_event :: proc(time_event_id : TimeEventID){
	event_manager_pause_time_event(engine.event_manager, time_event_id);
}

resume_time_event :: proc(time_event_id : TimeEventID){
	event_manager_resume_time_event(engine.event_manager, time_event_id);
}

is_valid_time_event :: proc(time_event_id : TimeEventID) -> bool {
	return event_manager_is_valid_time_event_id(engine.event_manager, time_event_id);
}


// - delay_sec: For how long to wait until starting to execute the first interval
// - interval_exec_duration_sec: duration of one interval in seconds. If negative only execute callback once and start the next interval iteration.
// - interval_wait_duration_sec: seconds to wait between intervals   (how long NOT to execute the callback procedure)
// - num_intervals: how many intervals to execute before unsceduleing the interval event. Set to -1 to do infinitly many intervals.
// - use_true_time: wheather to use true unmodified delta time for updating. If false used game delta time which is scaled by a timescale factor and may even be 0 during pause
// - user_data: arbitrary user data to pass along.
schedule_interval_event :: proc(callback_proc : IntervalEvent_CallbackSignature, delay_sec : f32, interval_exec_duration_sec : f32, interval_wait_duration_sec : f32, num_intervals : i32, use_true_time : bool = false, user_data : rawptr = nil) -> IntervalEventID {
	return event_manager_schedule_interval_event(engine.event_manager, callback_proc, delay_sec, interval_exec_duration_sec,interval_wait_duration_sec, num_intervals, use_true_time, user_data);
}

unschedule_interval_event :: proc(interval_event_id : ^IntervalEventID) {
	event_manager_unschedule_interval_event(engine.event_manager, interval_event_id);
}

pause_interval_event :: proc(interval_event_id : IntervalEventID){
	event_manager_pause_interval_event(engine.event_manager, interval_event_id);
}

resume_interval_event :: proc(interval_event_id : IntervalEventID){
	event_manager_resume_interval_event(engine.event_manager, interval_event_id);
}

is_valid_interval_event :: proc(interval_event_id : IntervalEventID) -> bool {
	return event_manager_is_valid_interval_event_id(engine.event_manager, interval_event_id);
}