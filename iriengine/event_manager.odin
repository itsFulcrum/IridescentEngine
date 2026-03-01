package iri

import "core:math/rand"

EventManager :: struct {
	time_events : [dynamic]TimeEventEntry,
}


//@Note: TimeEventID's are only valid for as long as the TimeEvent is still running or waiting to be exectued. If a time event is finished or stopped, it is automatically 
// unscheduled and the TimeEventID becomes invalid. 
// x = ArrayIndex, y = a random id_hash to verify its the correct Entry.
TimeEventID :: distinct [2]i32 

TimeEventEntry :: struct {
	id_hash : i32, // If negative the entry is in an unused state and can be recycled. If positive it is a random integer that is also returned as the TimeEventID.y to verify its a match and not a recycled entry.
	callback : TimeEvent_CallbackSignature,
	execution_time : f32, // when negative value it specifies how long until start executing, if positive means elapsed time since start of execution
	duration_time : f32,  // for how long to exectute the callback
	user_data : rawptr,
	use_true_time : bool, // wheather to use true unmodified/scaled delta time for updating.
	is_paused : bool,
}

@(private="package")
event_manager_init :: proc(manager : ^EventManager){

}

@(private="package")
event_manager_deinit :: proc(manager : ^EventManager){

	delete(manager.time_events);
}

@(private="package")
event_manager_update :: proc(manager : ^EventManager, delta_time : f32, true_delta_time : f32) {


	event_manager_update_time_events(manager, delta_time, true_delta_time);
}


@(private="file")
event_manager_update_time_events :: proc(manager : ^EventManager, delta_time : f32, true_delta_time : f32) {


	for &entry, index in manager.time_events {

		if entry.id_hash < 0 || entry.callback == nil {
			continue; // unused entry
		}

		if entry.is_paused do continue;

		if entry.execution_time < 0 {
			entry.execution_time += entry.use_true_time ? true_delta_time : delta_time;
			continue;
		}

		event_id := TimeEventID{cast(i32)index, entry.id_hash};	

		if entry.execution_time >= entry.duration_time{
			// last call

			entry.callback(event_id, entry.execution_time, 1.0, entry.user_data);
			event_manager_reset_time_event_entry(&entry);
			continue;
		}
		
		progress01 : f32 = clamp(entry.execution_time / entry.duration_time, 0.0,1.0);

		entry.callback(event_id, entry.execution_time, progress01, entry.user_data);
		entry.execution_time += entry.use_true_time ? true_delta_time : delta_time;
	}


	// check if last entry is currently used, if not pop it of the list.
	if len(manager.time_events) > 0 {
		last_entry_index : int = len(manager.time_events) -1;

		if manager.time_events[last_entry_index].id_hash < 0 {
			pop(&manager.time_events);
		}
	}
}

@(private="package")
event_manager_is_valid_time_event_id :: proc(manager : ^EventManager, time_event_id : TimeEventID) -> bool {

	if time_event_id.x < 0 || time_event_id.x >= cast(i32)len(manager.time_events) {
		return false;
	}

	if manager.time_events[time_event_id.x].id_hash != time_event_id.y {
		return false;
	}

	return true;
}

@(private="package")
event_manager_schedule_time_event :: proc(manager : ^EventManager, callback_proc : TimeEvent_CallbackSignature, delay_sec : f32, duration_sec : f32, use_true_time : bool = false, user_data : rawptr = nil) -> TimeEventID{

	event_id := TimeEventID{-1, -1}

	if callback_proc == nil {
		return event_id;
	}

	event_id.y = rand.int31();

	entry := TimeEventEntry{
		id_hash = event_id.y,
		callback = callback_proc,
		execution_time = delay_sec == 0.0 ? 0.0 : -abs(delay_sec),
		duration_time = abs(duration_sec),
		use_true_time = use_true_time,
		is_paused = false,
		user_data = user_data,
	}

	// find free spot
	free_spot : int = -1;
	for i in 0..<len(manager.time_events) {

		if manager.time_events[i].callback == nil {
			free_spot = i;
			break;
		}
	}

	if free_spot >= 0 {
		manager.time_events[free_spot] = entry;

		event_id.x = cast(i32)free_spot;
	} else {
		event_id.x = cast(i32)len(manager.time_events);
		append(&manager.time_events, entry);
	}

	return event_id;
}

@(private="package")
event_manager_unschedule_time_event :: proc(manager : ^EventManager, time_event_id : ^TimeEventID){

	defer {
		time_event_id.x = -1;
		time_event_id.y = -2;
	}

	if !event_manager_is_valid_time_event_id(manager, time_event_id^) {
		return;
	}

	last_entry : i32 = cast(i32)len(manager.time_events) -1
	if time_event_id.x == last_entry {
		// if last element, pop it form the list
		pop(&manager.time_events);
		return;
	}

	event_manager_reset_time_event_entry(&manager.time_events[time_event_id.x])

	return;
}

@(private="file")
event_manager_reset_time_event_entry :: proc(entry : ^TimeEventEntry){
	entry.id_hash = -1;
	entry.callback = nil;
	entry.execution_time = 0;
	entry.duration_time = 0;
	entry.user_data = nil;
	entry.use_true_time = false;
	entry.is_paused = false;
}

@(private="package")
event_manager_pause_time_event :: proc(manager : ^EventManager, time_event_id : TimeEventID){

	if !event_manager_is_valid_time_event_id(manager, time_event_id) {
		return;
	}

	manager.time_events[time_event_id.x].is_paused = true;
}

@(private="package")
event_manager_resume_time_event :: proc(manager : ^EventManager, time_event_id : TimeEventID){

	if !event_manager_is_valid_time_event_id(manager, time_event_id) {
		return;
	}

	manager.time_events[time_event_id.x].is_paused = false;
}