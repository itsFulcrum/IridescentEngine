package iriedit

import iri "../iriengine"
import im "odinary:dear_imguy"

import "core:encoding/uuid"

draw_assets_view :: proc(){


	asset_entries := iri.asset_manager_get_entries_map_read_only();

	if im.Button("Rescan Project") {
		iri.asset_manager_rescan_entire_project();	
	}

	num_collums : i32 = 3;

	table_flags := im.TableFlags_Resizable |  im.TableFlags_Borders;

	if im.BeginTable("Entity", num_collums, table_flags) {

		defer im.EndTable();

		im.TableHeadersRow();

		im.TableSetColumnIndex(0);
		im.Text("Type");
		im.TableSetColumnIndex(1);
		im.Text("Path");
		im.TableSetColumnIndex(2);
		im.Text("UUID");

		for id, &entry in asset_entries {

			im.TableNextRow();


			// Type
			im.TableSetColumnIndex(0);
			im.Text(fmt_cstr("{}", entry.type));
			

			// Path
			im.TableSetColumnIndex(1);
			im.Text("%s", entry.path);

			// UUID
			im.TableSetColumnIndex(2);
			//im.Text("%i", cast(i32)index);
			str := uuid.to_string_allocated(id, context.temp_allocator);
			im.Text("%s", str);
		}

	}
}