package iri

import "core:math/rand"

EventManager :: struct {
	time_events : [dynamic]TimeEventEntry,
	interval_events : [dynamic]IntervalEventEntry,
}


//@Note: TimeEventID's are only valid for as long as the TimeEvent is still running or waiting to be exectued. 
// If a time event is finished or stopped, it is automatically 
// unscheduled and the TimeEventID becomes invalid. 
// x = ArrayIndex, y = a random id_hash to verify its the correct Entry.
TimeEventID :: distinct [2]i32 
IntervalEventID :: distinct [2]i32 // same but should only be used with interval event procedures.

TimeEventFlags :: distinct bit_set[TimeEventFlag; u32]
TimeEventFlag :: enum u32 {
	IsUsed = 0,
	IsPaused,
	UseTrueTime,
}


TimeEventEntry :: struct {
	id_hash 		: i32, // If negative the entry is in an unused state and can be recycled. If positive it is a random integer that is also returned as the TimeEventID.y to verify its a match and not a recycled entry.
	callback 		: TimeEvent_CallbackSignature,
	execution_time 	: f32, // when negative value it specifies how long until start executing, if positive means elapsed time since start of execution
	duration_time 	: f32,  // for how long to exectute the callback
	user_data 		: rawptr,
	flags 			: TimeEventFlags,
}

IntervalEventEntry :: struct {
	callback : IntervalEvent_CallbackSignature,
	id_hash : i32, 			// Random integer that is also returned as the TimeEventID.y to verify its a match and not a recycled entry.
	flags : TimeEventFlags,
	
	// when this is a negative value it means how long until start executing the next interval.
	// if its positive it means elapsed time since start of the interval 
	execution_time     : f32, 
	
	interval_exec_duration  : f32,  // duration of one interval
	interval_wait_duration  : f32,  // for how long to wait between intervals.
	
	num_intervals  : i32,  // how many intervals to execute, -1 to do infinitely many 
	curr_interval  : u32,  // current interval

	user_data : rawptr,
}

@(private="package")
event_manager_init :: proc(manager : ^EventManager){

}

@(private="package")
event_manager_deinit :: proc(manager : ^EventManager){

	delete(manager.time_events);
	delete(manager.interval_events);
}

@(private="package")
event_manager_update :: proc(manager : ^EventManager, delta_time : f32, true_delta_time : f32) {


	event_manager_update_time_events(manager, delta_time, true_delta_time);
	event_manager_update_interval_events(manager, delta_time, true_delta_time);
}



// ================================
// TIME EVENTS
// ================================


@(private="file")
event_manager_update_time_events :: proc(manager : ^EventManager, delta_time : f32, true_delta_time : f32) {


	for &entry, index in manager.time_events {

		if .IsUsed not_in entry.flags || .IsPaused in entry.flags {
			continue;
		}

		if entry.execution_time < 0 {
			entry.execution_time += .UseTrueTime in entry.flags ? true_delta_time : delta_time;
			continue;
		}

		event_id := TimeEventID{cast(i32)index, entry.id_hash};	

		if entry.execution_time >= entry.duration_time{

			// last call
			entry.callback(event_id, entry.execution_time, 1.0, entry.user_data);

			entry = TimeEventEntry{}; // Zero Out.
			continue;
		}
		
		progress01 : f32 = clamp(entry.execution_time / entry.duration_time, 0.0,1.0);

		entry.callback(event_id, entry.execution_time, progress01, entry.user_data);
		entry.execution_time += .UseTrueTime in entry.flags ? true_delta_time : delta_time;
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
event_manager_schedule_time_event :: proc(manager : ^EventManager, callback_proc : TimeEvent_CallbackSignature, delay_sec : f32, duration_sec : f32, use_true_time : bool = false, user_data : rawptr = nil) -> TimeEventID{

	event_id := TimeEventID{-1, -1}

	if callback_proc == nil {
		return event_id;
	}

	event_id.y = rand.int31();

	event_flags := TimeEventFlags{.IsUsed};
	if use_true_time {
		event_flags += TimeEventFlags{.UseTrueTime};
	}

	entry := TimeEventEntry{
		id_hash 		= event_id.y,
		callback 		= callback_proc,
		execution_time 	= delay_sec == 0.0 ? 0.0 : -abs(delay_sec),
		duration_time 	= abs(duration_sec),
		flags 			= event_flags,
		user_data 		= user_data,
	}

	// find free spot
	free_spot : int = -1;
	for i in 0..<len(manager.time_events) {

		if .IsUsed not_in manager.time_events[i].flags {
			free_spot = i;
			break;
		}
	}

	if free_spot >= 0 {
		event_id.x = cast(i32)free_spot;
		manager.time_events[free_spot] = entry;
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
		time_event_id.y = -1;
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

	manager.time_events[time_event_id.x] = TimeEventEntry{}; // Zero Out
	return;
}

@(private="package")
event_manager_pause_time_event :: proc(manager : ^EventManager, time_event_id : TimeEventID){

	if !event_manager_is_valid_time_event_id(manager, time_event_id) {
		return;
	}

	manager.time_events[time_event_id.x].flags += TimeEventFlags{.IsPaused};
}

@(private="package")
event_manager_resume_time_event :: proc(manager : ^EventManager, time_event_id : TimeEventID){

	if !event_manager_is_valid_time_event_id(manager, time_event_id) {
		return;
	}

	manager.time_events[time_event_id.x].flags -= TimeEventFlags{.IsPaused};
}

@(private="package")
event_manager_is_valid_time_event_id :: proc(manager : ^EventManager, time_event_id : TimeEventID) -> bool {

	if time_event_id.x < 0 || time_event_id.x >= cast(i32)len(manager.time_events) {
		return false;
	}

	if manager.time_events[time_event_id.x].id_hash != time_event_id.y {
		return false;
	}

	if .IsUsed not_in manager.time_events[time_event_id.x].flags {
		return false;
	}

	return true;
}


// ================================
// INTERVAL EVENTS
// ================================


@(private="file")
event_manager_update_interval_events :: proc(manager : ^EventManager, delta_time : f32, true_delta_time : f32) {


	for &entry, index in manager.interval_events {

		if .IsUsed not_in entry.flags || .IsPaused in entry.flags {
			continue;
		}

		if entry.execution_time < 0 {
			entry.execution_time += .UseTrueTime in entry.flags ? true_delta_time : delta_time;
			continue;
		}

		event_id := IntervalEventID{cast(i32)index, entry.id_hash};	


		if entry.execution_time >= entry.interval_exec_duration || entry.interval_exec_duration < 0.0 {
			
			// last call of interval.
			entry.callback(event_id, entry.execution_time, 1.0, entry.curr_interval, entry.user_data);

			
			// @Note num_intervals can be negative which mean infinitly many intervals.
			if entry.num_intervals < 0 || entry.curr_interval < cast(u32)entry.num_intervals{
				entry.curr_interval += 1;
				entry.execution_time = -entry.interval_wait_duration;

			} else {
				entry = IntervalEventEntry{}; // zero out.
			}			

			continue;
		}
		
		progress01 : f32 = clamp(entry.execution_time / entry.interval_exec_duration, 0.0, 1.0);

		entry.callback(event_id, entry.execution_time, progress01, entry.curr_interval, entry.user_data);


		entry.execution_time += .UseTrueTime in entry.flags ? true_delta_time : delta_time;
	}


	// check if last entry is currently used, if not pop it of the list.
	if len(manager.interval_events) > 0 {
		last_entry_index : int = len(manager.interval_events) -1;

		if manager.interval_events[last_entry_index].id_hash < 0 {
			pop(&manager.interval_events);
		}
	}
}

@(private="package")
event_manager_schedule_interval_event :: proc(manager : ^EventManager, callback_proc : IntervalEvent_CallbackSignature, delay_sec : f32, interval_exec_duration_sec : f32, interval_wait_duration_sec : f32, num_intervals : i32, use_true_time : bool = false, user_data : rawptr = nil) -> IntervalEventID {

	event_id := IntervalEventID{-1, -1}

	if callback_proc == nil {
		return event_id;
	}

	event_id.y = rand.int31();

	event_flags := TimeEventFlags{.IsUsed};
	if use_true_time {
		event_flags += TimeEventFlags{.UseTrueTime};
	}

	entry := IntervalEventEntry{
		id_hash = event_id.y,
		callback = callback_proc,
		execution_time = delay_sec == 0.0 ? 0.0 : -abs(delay_sec), // @Note: I dont want this to end up as '-0'
		
		user_data = user_data,

		flags = event_flags,
	
		interval_exec_duration  = interval_exec_duration_sec,
		interval_wait_duration  = abs(interval_wait_duration_sec),
	
		num_intervals  = num_intervals, // can be negative to indicate infinite intervals.
		curr_interval   = 0,
	}

	// find free spot
	free_spot : int = -1;
	for i in 0..<len(manager.interval_events) {

		if .IsUsed not_in manager.interval_events[i].flags {
			free_spot = i;
			break;
		}
	}

	if free_spot >= 0 {
		event_id.x = cast(i32)free_spot;
		manager.interval_events[free_spot] = entry;
	} else {
		event_id.x = cast(i32)len(manager.interval_events);
		append(&manager.interval_events, entry);
	}

	return event_id;
}

@(private="package")
event_manager_unschedule_interval_event :: proc(manager : ^EventManager, interval_event_id : ^IntervalEventID) {

	defer {
		interval_event_id.x = -1;
		interval_event_id.y = -2;
	}

	if !event_manager_is_valid_interval_event_id(manager, interval_event_id^) {
		return;
	}

	last_entry : i32 = cast(i32)len(manager.interval_events) -1
	if interval_event_id.x == last_entry {
		// if last element, pop it form the list
		pop(&manager.interval_events);
		return;
	}

	manager.interval_events[interval_event_id.x] = IntervalEventEntry{}; // zero out.

	return;
}

@(private="package")
event_manager_pause_interval_event :: proc(manager : ^EventManager, interval_event_id : IntervalEventID){

	if !event_manager_is_valid_interval_event_id(manager, interval_event_id) {
		return;
	}

	manager.interval_events[interval_event_id.x].flags += TimeEventFlags{.IsPaused};
}

@(private="package")
event_manager_resume_interval_event :: proc(manager : ^EventManager, interval_event_id : IntervalEventID){

	if !event_manager_is_valid_interval_event_id(manager, interval_event_id) {
		return;
	}

	manager.interval_events[interval_event_id.x].flags -= TimeEventFlags{.IsPaused};
}

@(private="package")
event_manager_is_valid_interval_event_id :: proc(manager : ^EventManager, interval_event_id : IntervalEventID) -> bool {

	if interval_event_id.x < 0 || interval_event_id.x >= cast(i32)len(manager.interval_events) {
		return false;
	}

	if manager.interval_events[interval_event_id.x].id_hash != interval_event_id.y {
		return false;
	}

	if .IsUsed not_in manager.interval_events[interval_event_id.x].flags {
		return false;
	}

	return true;
}
