package iri


// @Note
// 'elapsed_time' is the seconds since this time event started executing. May exceed the event duration by a small amout at the last call.
// 'progression_normalized_01' is a normalized progression of the time event (elapsed_time / duration) and ensured to be in range 0..1. Last call always has a value of 1 unless manually stopped. Can be used to lerp stuff over time.
// 'user_data' is just a raw pointer that is passed through. 
TimeEvent_CallbackSignature :: #type proc(event_id : TimeEventID, elapsed_time : f32, progression_normalized_01 : f32, user_data : rawptr)

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