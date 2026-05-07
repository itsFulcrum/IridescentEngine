package iri

import "core:c"
import "core:sort"

// Multi free list is designed to be used as a free list for buffer type data
// where we want to keep track of unsued blocks of multiple consequitve elements.
// Each entry stores the index to the biggining of an unsuded (free) block and
// an amount of consequtive elements that are considered unsused.
// effectivly a mini pool type allocator however actual allocation of source buffers is handled by callers.


MultiFreelistEntry :: struct {
	index : u64,
	amount : u64,
}

// Seach a freelist for and entry that points to a free block which can accomodate the 'required_amount' of elements of a source buffer.
// using a simple scheme to try and avoid fragmentation by filling up small blocks first.
// Returns the index to an entry in the free_list or -1 if none was found.
multi_freelist_try_find_entry :: proc(free_list : ^[dynamic]MultiFreelistEntry, required_amount : u64) -> (free_list_entry_index : int) {

	if len(free_list) <= 0 {
		return -1;
	}

	free_list_entry_index = -1;
	curr_free_length : u64 = c.UINT64_MAX;

	for entry, entry_index in free_list {

		if required_amount == entry.amount {
			free_list_entry_index = entry_index;
			break;
		} else if required_amount < entry.amount {
			
			if entry.amount < curr_free_length {
				free_list_entry_index = entry_index;
				curr_free_length = entry.amount;
			}
		}					
	}

	return free_list_entry_index;
}

// Update the freelist by consumeing 'consume_amount' from and entry in the freelist.
// Entry index should point to an entry in the provided free list that can acomodate the consume amount
// typically you would call this procedure with an index returned by 'multi_freelist_try_find_entry()'
// e.g: 
// free_entry_index := multi_freelist_try_find_entry(&free_list, required_amount);
// if free_entry_index >= 0 {
//		multi_freelist_consume_entry_amount(&free_list,free_entry_index, required_amount);
// } else {
//	.. no block found in the freelist that can accomodate the 'required_amount'
//  so proceed by growing your source buffer.	
// }
multi_freelist_consume_entry_amount :: proc(free_list : ^[dynamic]MultiFreelistEntry, entry_index : int, consume_amount : u64){
	
	engine_assert(entry_index >= 0 && entry_index < len(free_list));
	engine_assert(free_list[entry_index].amount >= consume_amount);

	if free_list[entry_index].amount == consume_amount {
		// remove entry from freelist.
		unordered_remove(free_list, entry_index);
	} else {
		free_list[entry_index].index  = free_list[entry_index].index  + consume_amount;
		free_list[entry_index].amount = free_list[entry_index].amount - consume_amount;
	}
}

// Use this procedure to add new free list entries. 
// This will first try to merge the entry with an existing one if it is directly after or before an existing entry.
multi_freelist_add_or_merge_entry :: proc(free_list : ^[dynamic]MultiFreelistEntry, new_entry : MultiFreelistEntry){
	

	append(free_list, new_entry);

	if len(free_list) <= 1 {
		return;
	}

	// To make sure that entries that point to blocks next to each other get merged together we
	// first add the new entry, then sort the list by index an then walk it in reverse.
	// We then just check if we can merge entries toggether while also removing merged ones.
	
	compare_multi_freelist_entry_proc :: proc (a,b : MultiFreelistEntry) -> int {
		return sort.compare_u64s(a.index, b.index);
	}

	sort.quick_sort_proc(free_list[:], compare_multi_freelist_entry_proc);

	#reverse for &curr_entry, curr_entry_index in free_list {

		if curr_entry_index == 0 {
			break;
		}

		before_entry := &free_list[curr_entry_index -1];

		if before_entry.index + before_entry.amount == curr_entry.index {

			// merge current into entry before and remove current.
			before_entry.amount = before_entry.amount + curr_entry.amount;
			// @Note: technically we could do an unorderd remove too but i feel its nicer if entries stay sorted by index
			ordered_remove(free_list, curr_entry_index); 
		}
	}
}