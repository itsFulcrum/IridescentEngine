package iriedit

import "core:log"
import "core:c"
import "core:math"
import "core:math/linalg"
import "core:strings"

import iri "../iriengine"
import iria "../iriengine/iriasset"
import im "odinary:dear_imguy"

draw_universe_settings :: proc(universe: ^iri.Universe){

	uni := universe;

	im.Checkbox("Do Frustum Culling", &uni.do_frustum_culling);
	im.SetItemTooltip("set variable: universe.do_frustum_culling");
	im.Checkbox("Cull shadowmap draws", &uni.cull_shadow_draws);
	im.SetItemTooltip("set variable: universe.cull_shadow_draws");

	im.Spacing()
	im.Spacing()
	im.SliderFloat("cascade near_far_scale ", &uni.shadow_cascade_near_far_scale, 0.0, 10.0)
	im.SliderFloat("cascade side_scale ",     &uni.shadow_cascade_side_scale, 0.0, 10.0);

	split_1 : f32 = uni.shadow_cascade_split_1;
	split_2 : f32 = uni.shadow_cascade_split_2;
	split_3 : f32 = uni.shadow_cascade_split_3;

	if im.SliderFloat("cascade split 1 ", &split_1, 0.0, 1.0) {
		uni.shadow_cascade_split_1 = linalg.clamp(split_1, 0.0, split_2);
	}
	if im.SliderFloat("cascade split 2 ", &split_2, 0.0, 1.0){
		uni.shadow_cascade_split_2 = linalg.clamp(split_2, split_1, split_3);
	}
	if im.SliderFloat("cascade split 3 ", &split_3, 0.0, 1.0){
		uni.shadow_cascade_split_3 = linalg.clamp(split_3, split_2, 1.0);
	}
	im.Spacing()
	im.Spacing()

}

// Universe Scene View
draw_entity_list :: proc(universe: ^iri.Universe){

	component_checkbox :: proc(label : cstring, component : iri.ComponentType,  component_set : ^iri.ComponentSet) -> bool {

		is_enabled : bool = component in component_set;
		if im.Checkbox(label, &is_enabled) {
			
			if is_enabled {
				component_set^ += iri.ComponentSet{component};
			} else {
				component_set^ -= iri.ComponentSet{component};
			}

			return true;
		}

		return false;
	}

	if universe == nil {
		return;
	}
	
	// Name And Rename field
	{

		if editor_is_initialized() {
			
			im.Text("Name: ");
			im.SameLine();
			
			buf_size : uint = cast(uint)editor.universe_rename_buf_len

			// @Note: we keep this static var ptr just so we can in place detect if universe changes 
			// so we can update our rename buffer with the new name..
			@static uni_id : iri.AssetUUID;
			if uni_id != universe.asset_uuid {
				uni_id = universe.asset_uuid;
				copy_string_to_buffer_null_terminate(editor.universe_rename_buf, cast(int)buf_size, universe.name);
			}

			buf_cstr_alias := cstring(editor.universe_rename_buf);
			if im.InputText("##UniRename", buf_cstr_alias, buf_size, im.InputTextFlags{.ElideLeft,.EnterReturnsTrue}) {
				str := strings.clone_from_cstring(buf_cstr_alias, context.temp_allocator);

				if len(buf_cstr_alias) > 0 {
					
					iri.universe_rename(universe, str);
				}
			}
		} else {
			im.Text("Name %s", universe.name);
		}

	}

	if selected_tag, selection_made := draw_universe_tag_combo_selection("Universe Tag", universe.tag, 100); selection_made == true {
		universe.tag = selected_tag;
	}

	if im.Button("Save to file") {

		save_ok := iri.asset_io_store_universe(universe);
		if !save_ok {
			log.errorf("Failed to save universe..")
		}
	}

	@static apply_comp_filter : bool = false;
	@static comp_include_set := iri.ComponentSet{};

	im.Checkbox("Filter by Components", &apply_comp_filter);

	if apply_comp_filter {
		im.SameLine();	component_checkbox("Camera", iri.ComponentType.Camera, &comp_include_set);
		im.SameLine();	component_checkbox("Light", iri.ComponentType.Light, &comp_include_set);
		im.SameLine();  component_checkbox("Skybox", iri.ComponentType.Skybox, &comp_include_set);
		im.SameLine();  component_checkbox("MeshRenderer", iri.ComponentType.MeshRenderer, &comp_include_set);
		im.SameLine();  component_checkbox("Collider", iri.ComponentType.Collider, &comp_include_set);
	}

	@static apply_tag_filter : bool = false;
	@static tag_filter : u32 = 0;
	
	im.Checkbox("Filter by Tag", &apply_tag_filter);

	if apply_tag_filter {
	
		im.SameLine();
		select_tag, selection_made := draw_entity_tag_combo_selection("Tag",tag_filter);
		if selection_made {
			tag_filter = select_tag;
		}

		//im.SetNextItemWidth(35);
		//im.SameLine(); im.DragInt("##TagFilter", &tag_filter, 1.0, 0, c.INT32_MAX)
	}

	_inc_set := apply_comp_filter ? comp_include_set : iri.ComponentSet{};
	_tag_filter : u32 = apply_tag_filter ? cast(u32)tag_filter : 0;

	entities : []iri.Entity = iri.ecs_gather_entities_by_components_and_tag(&universe.ecs, _inc_set, _tag_filter, true, false, context.temp_allocator);

	im.Spacing();
	
	if editor_is_initialized() {

		selected_ent_id := cast(c.int)editor._selected_entity.id;

		im.SetNextItemWidth(40);
		if im.DragInt("Select Entity by ID", &selected_ent_id, 0.35, -1, c.INT32_MAX) {
			
			select_entity(universe, iri.Entity{id = cast(i32)selected_ent_id});
		}
	}

	im.Spacing();
	im.Separator();
	im.Spacing();
	
	{
		num_collums : i32 = 4;

		//table_flags := im.TableFlags_Resizable | im.TableFlags_RowBg | im.TableFlags_Borders;
		//table_flags := im.TableFlags_Resizable | im.TableFlags_Borders;
		//table_flags := im.TableFlags_Resizable | im.TableFlags_Borders
		table_flags := im.TableFlags_SizingFixedFit | im.TableFlags_Hideable;

		COLUMN_NAME :: 0
		COLUMN_ID   :: 3
		COLUMN_TAG  :: 1
		COLUMN_COMP :: 2

		if im.BeginTable("Entity", num_collums, table_flags) {

			defer im.EndTable();

			im.TableHeadersRow();

			im.TableSetColumnIndex(COLUMN_NAME);
			im.Text("Name");
			im.TableSetColumnIndex(COLUMN_TAG);
			im.Text("TAG");
			im.TableSetColumnIndex(COLUMN_ID);
			im.Text("ID");
			im.TableSetColumnIndex(COLUMN_COMP);
			im.Text("Components");


			for ent in entities {
				
				ent_info, ent_info_ok := iri.ecs_get_entity_info(&universe.ecs, ent);
				
				im.TableNextRow();

				im.TableSetColumnIndex(COLUMN_NAME);
				
				label : cstring = fmt_cstr("%s ##{}", ent_info.name, ent.id);

				is_selected : bool = false;

				if editor_is_initialized() {
					is_selected = ent.id == editor._selected_entity.id 
				}

				if im.Selectable(label, is_selected) {

					if editor_is_initialized() {
						select_entity(universe, ent);
					}
				}

				popup_label : cstring = fmt_cstr("ItemRightClick##{}", ent.id);
				if im.BeginPopupContextItem(popup_label) {
					
					if im.Selectable("Destroy Entity") {
						ent_copy := ent;
						iri.entity_destroy(&ent_copy, universe);
					}

					im.EndPopup();
				}

				im.TableSetColumnIndex(COLUMN_TAG);
				tag_label := fmt_cstr("##Tag{}", ent.id)
				if selected_tag, selection_made := draw_entity_tag_combo_selection(tag_label, ent_info.tag, 100); selection_made == true {
					iri.ecs_entity_set_tag(&universe.ecs, ent, selected_tag);
				}

				// Entity ID
				im.TableSetColumnIndex(COLUMN_ID);
				im.Text("%.4d", cast(i32)ent.id);

				im.TableSetColumnIndex(COLUMN_COMP);


				comp_loop: for comp_type in ent_info.component_set {

					if comp_type == iri.ComponentType.Transform {
						continue comp_loop;
					}

					im.SameLine();
					bullet_label : cstring = fmt_cstr("{}", comp_type);
				
					im.BulletText(bullet_label)
				}
			}

		}
	}

			
	when false {

		for &ent in entities {

			ent_info, ent_info_ok := iri.ecs_get_entity_info(&universe.ecs, ent);

			label : cstring = fmt_cstr("- %8s ##{}", ent_info.name, ent.id);
			
			is_selected : bool = false;

			if editor_is_initialized() {
				is_selected = ent.id == editor._selected_entity.id 
			}

			im.SetNextItemWidth(20);
			if im.Selectable(label, is_selected) {

				if editor_is_initialized() {
					select_entity(universe, ent);
				}
			}

			popup_label : cstring = fmt_cstr("ItemRightClick##{}", ent.id);
			if im.BeginPopupContextItem(popup_label) {
				
				if im.Selectable("Destroy Entity") {
					iri.entity_destroy(&ent, universe);
				}

				im.EndPopup();
			}
			
			im.SameLine();	im.BulletText("ID %.4d" ,ent.id);
			tag_str := get_cstring_for_entity_tag(ent_info.tag);
			im.SameLine();	im.BulletText("TAG %12s", tag_str);

			comp_loop: for comp_type in ent_info.component_set {

				if comp_type == iri.ComponentType.Transform {
					continue comp_loop;
				}

				im.SameLine();
				bullet_label : cstring = fmt_cstr("{}", comp_type);
				
				im.BulletText(bullet_label)
			}
		}
	}


	is_any_hovered : bool = im.IsAnyItemHovered();

	if !is_any_hovered || im.IsPopupOpen("SceneViewRightClickMenu") {

		pop_flags : im.PopupFlags = im.PopupFlags(1);
		// right click menu
		if im.BeginPopupContextWindow("SceneViewRightClickMenu", pop_flags) {

			if im.MenuItem("Create New Entity") {
				iri.entity_create(iri.ComponentSet{}, "NewEntity", 0, universe);
			}

			im.EndPopup();
		}
	}
}

draw_entity_viewer :: proc(universe: ^iri.Universe, entity : iri.Entity) {

	if universe == nil {
		return;
	}

	ecs := &universe.ecs;

	if !iri.entity_exists(entity, universe) {
		im.Text("No valid entity selected");
		return;
	}

	ent_info, info_ok := iri.ecs_get_entity_info(ecs, entity);

	if editor_is_initialized() {
		im.Text("Name:")
		im.SameLine();
		im.SetNextItemWidth(200);
		buf_size : uint = cast(uint)editor.selected_entity_rename_buf_len;
		rename_buf_cstr_alias := cstring(editor.selected_entity_rename_buf);
		if im.InputText("##EntRenameInput", rename_buf_cstr_alias , buf_size, im.InputTextFlags{.ElideLeft,.EnterReturnsTrue}) {
		
			name_str : string = strings.clone_from_cstring(rename_buf_cstr_alias, context.temp_allocator);
			if len(name_str) > 0 {
				iri.ecs_entity_rename(ecs, entity, name_str);
			}
		} 
	} else {
		imgui_text_fmt("Name: {}", ent_info.name);
	}

	im.SameLine();
	imgui_text_fmt("EntityID: {}", entity.id);

	is_enabled : bool = iri.ecs_entity_is_enabled(&universe.ecs, entity);
	if im.Checkbox("Enabled", &is_enabled) {
		iri.ecs_entity_set_enabled(&universe.ecs, entity, is_enabled);
	}

	im.SameLine();

	if select_tag, selection_made := draw_entity_tag_combo_selection("Tag",ent_info.tag); selection_made == true {
		iri.ecs_entity_set_tag(&universe.ecs, entity, select_tag);
	}


	if enum_flags_checkbox("Non Persistant", iri.EntityFlag.NonPersistant, &ent_info.flags){
		was_disabled : bool = iri.EntityFlag.NonPersistant not_in ent_info.flags;
		iri.ecs_entity_set_flags(&universe.ecs, entity, {.NonPersistant}, subtract_flags = was_disabled);
	}
	im.SetItemTooltip("Non Persistant entities are not written to file")

	im.Spacing();
	im.Separator();
	im.Spacing();

	button_delete_comp_sameline :: proc(comp_type : iri.ComponentType, universe : ^iri.Universe, entity : iri.Entity) -> (pressed : bool) {
		
		if comp_type != .Transform {

			im.SameLine();
			btn_lable := fmt_cstr("X##{}", cast(u32)comp_type);
			
			im.SetCursorPosX( im.GetCursorPosX() + max(0.0, im.GetContentRegionAvail().x - 30) );
				
			if im.Button(btn_lable, im.Vec2{30,0}) {
				switch comp_type {
					case .Transform: 	
					case .Camera: 		iri.entity_remove_component(entity,iri.CameraComponent, universe);
					case .Light: 		iri.entity_remove_component(entity,iri.LightComponent, universe);
					case .Skybox: 		iri.entity_remove_component(entity,iri.SkyboxComponent, universe);
					case .MeshRenderer: iri.entity_remove_component(entity,iri.MeshRendererComponent, universe);
					case .Collider: 	iri.entity_remove_component(entity,iri.ColliderComponent, universe);
				}
				return true;
			}

			im.SetItemTooltip("Delete this component");
		}

		return false;
	}


	comp_loop: for comp_type in ent_info.component_set {

		comp_type_cstr := fmt_cstr("{}", comp_type);

		tree_node_flags := im.TreeNodeFlags{.DefaultOpen, .Framed, .AllowOverlap,.NoTreePushOnOpen};
		
		if im.TreeNodeEx(comp_type_cstr, tree_node_flags) {

			if button_delete_comp_sameline(comp_type, universe, entity) {
				continue comp_loop;
			}

			switch comp_type {
				case .Transform: 
					comp := iri.entity_get_transform(entity);
					draw_component_editor_transform(comp);
				case .Camera: 
					comp := iri.entity_get_component(entity, iri.CameraComponent, universe)
					if comp != nil do draw_component_editor_camera(comp);
				case .Light: 
					comp := iri.entity_get_component(entity, iri.LightComponent, universe)
					if comp != nil do draw_component_editor_light(comp);
				case .Skybox: 
					comp := iri.entity_get_component(entity, iri.SkyboxComponent, universe)
					if comp != nil do draw_component_editor_skybox(comp);
				case .MeshRenderer: 
					comp := iri.entity_get_component(entity, iri.MeshRendererComponent, universe)
					if comp != nil do draw_component_editor_meshrenderer(comp);
				case .Collider: 
					comp := iri.entity_get_component(entity, iri.ColliderComponent, universe)
					if comp != nil do draw_component_editor_collider(comp);

			}

			im.Separator();

		} else {
			if button_delete_comp_sameline(comp_type, universe, entity) {
				continue comp_loop;
			}
		}

		im.Spacing();
		im.Spacing();
	}
	

	is_any_hovered : bool = im.IsAnyItemHovered();


	if !is_any_hovered || im.IsPopupOpen("EntViewerRCM") {

		//log.debugf("RIGHT CLICK MENU")


		pop_flags : im.PopupFlags = im.PopupFlags(1);
		// right click menu
		if im.BeginPopupContextWindow("EntViewerRCM", pop_flags) {

			for comp_type in iri.ComponentType {

				if comp_type in ent_info.component_set {
					continue;
				}

				label : cstring = fmt_cstr("Add Component {}", comp_type);
				if im.MenuItem(label) {

					switch comp_type {
						case .Transform:
						case .Camera: 		iri.entity_add_component(entity, iri.CameraComponent, universe);
						case .Light: 		iri.entity_add_component(entity, iri.LightComponent , universe);
						case .Skybox: 		iri.entity_add_component(entity, iri.SkyboxComponent, universe);
						case .MeshRenderer: iri.entity_add_component(entity, iri.MeshRendererComponent, universe);
						case .Collider: 	iri.entity_add_component(entity, iri.ColliderComponent, universe);
					}
				}
			}

			im.EndPopup();
		}
	}


	// DRAG DROP TARGET

	avail := im.GetContentRegionAvail();
	im.Dummy(im.Vec2{avail.x,avail.y})


	drag_target: if file_info := file_info_drag_drop_target({.AssetFile}, {.Light}); file_info != nil {

		// Redundant check atm but we will add more in the future im sure.
		if file_info.asset_type == iri.AssetType.Light {

			has_light_comp := iri.entity_is_component_attached(entity, .Light, universe);

			if !has_light_comp {

				light_comp, err := iri.entity_add_component(entity, iri.LightComponent, universe);
				if light_comp != nil {

					iri.comp_light_init_from_light_asset_uuid(light_comp, file_info.asset_uuid);
				}

			}

		}
	}
}


draw_entity_tag_combo_selection :: proc(label : cstring, curr_tag : u32, width : f32 = 200) -> (selected_tag : u32, selection_made : bool){
	
	selected_tag = 0;
	selection_made = false;

	im.SetNextItemWidth(width);
	curr_tag_str := get_cstring_for_entity_tag(curr_tag);
	
	if im.BeginCombo(label, curr_tag_str){
		
		num_defined_tags : u32 = get_num_defined_entity_tags();
		for tag_val in 0..<num_defined_tags {

			combo_tag_str := get_cstring_for_entity_tag(tag_val);

			if im.Selectable(combo_tag_str) {
				selected_tag = tag_val;
				selection_made = true;
				break;
			}
		}

		im.EndCombo();
	}

	return;
}

draw_universe_tag_combo_selection :: proc(label : cstring, curr_tag : u32, width : f32 = 200) -> (selected_tag : u32, selection_made : bool){
	
	selected_tag = 0;
	selection_made = false;

	im.SetNextItemWidth(width);
	curr_tag_str := get_cstring_for_universe_tag(curr_tag);
	
	if im.BeginCombo(label, curr_tag_str){
		
		num_defined_tags : u32 = get_num_defined_universe_tags();
		for tag_val in 0..<num_defined_tags {

			combo_tag_str := get_cstring_for_universe_tag(tag_val);

			if im.Selectable(combo_tag_str) {
				selected_tag = tag_val;
				selection_made = true;
				break;
			}
		}

		im.EndCombo();
	}

	return;
}


// =============================================================
// 		COMPONENT EDITORS
// =============================================================


draw_editor_transform :: proc (transform : ^iri.Transform) -> (any_changed : bool){

	any_changed = false;

	// Position
	im.Text("Position:")
	im.SameLine();
	im.SetNextItemWidth(225);
	any_changed |= im.DragFloat3("##Position", &transform.position, v_speed = 0.1, v_min = -math.F32_MAX, v_max = math.F32_MAX);
	im.SameLine();
	if im.Button("Reset##Pos") {
		transform.position = {0,0,0};
		any_changed = true;
	}

	// Scale
	im.Text("Scale:   ")
	im.SameLine();
	im.SetNextItemWidth(225);
	any_changed |= im.DragFloat3("##Scale", &transform.scale, v_speed = 0.01, v_min = -math.F32_MAX, v_max = math.F32_MAX);
	im.SameLine();
	if im.Button("Reset##Scale") {
		transform.scale = {1,1,1};
		any_changed = true;
	}
	
	im.Text("Rotation:")
	im.SameLine();

	im.SetNextItemWidth(225);
	any_changed |= draw_quaternion("##Rotation", &transform.orientation);

	im.SameLine();
	if im.Button("Reset##Rot") {
		transform.orientation = linalg.QUATERNIONF32_IDENTITY;
		any_changed = true;
	}

	imgui_text_fmt("Quaternion - [x:{}, y: {}, z: {}, w: {}]", transform.orientation.x,transform.orientation.y,transform.orientation.z,transform.orientation.w);

	return any_changed;
}



draw_component_editor_transform :: proc (comp : ^iri.TransformComponent){

	any_changed : bool = draw_editor_transform(&comp.transform)
	if any_changed {

		if light_comp , err := iri.ecs_get_component(comp.parent_ecs, comp.entity, iri.LightComponent); light_comp != nil{

			iri.comp_light_push_changes(light_comp);
		}

		if meshren_comp , err := iri.ecs_get_component(comp.parent_ecs, comp.entity, iri.MeshRendererComponent); meshren_comp != nil {

			iri.comp_meshrenderer_force_update_all_draw_instances(meshren_comp);
		}
	}
}

draw_component_editor_camera :: proc (comp : ^iri.CameraComponent) {

	im.DragFloat("Field of View"  , &comp.fov_deg  , v_speed = 0.01 , v_min = 0.001, v_max = 180.0);
	im.DragFloat("Near Clip Plane", &comp.near_clip, v_speed = 0.001, v_min = 0.001, v_max = math.F32_MAX);
	im.DragFloat("Far  Clip Plane", &comp.far_clip , v_speed = 0.1  , v_min = 0.01 , v_max = math.F32_MAX);

	im.Spacing();

	im.DragFloat("Aperture", &comp.aperture  , v_speed = 0.01 , v_min = 0.001, v_max = 100.0);
	im.DragFloat("Shutter Speed", &comp.shutter_speed  , v_speed = 0.001 , v_min = 0.00001, v_max = 1.0);
	im.DragFloat("Sensitivity ISO", &comp.iso  , v_speed = 50.0 , v_min = 1.0, v_max = 10_000.0);
	im.DragFloat("Exposure Correction", &comp.exposure_correction  , v_speed = 0.001 , v_min = -10.0, v_max = 10.0);

	if im.Button("Set as active Rendering Camera"){
		iri.comp_camera_set_as_active(comp);
	}

}

draw_component_editor_light :: proc (comp : ^iri.LightComponent){

	draw_shadowmap_resolution_combo :: proc(combo_name : cstring, current_resolution : iri.ShadowmapResolution) -> (changed : bool, changed_to_res : iri.ShadowmapResolution) {

		curr_res_cstr := fmt_cstr("{}", current_resolution);

		changed = false;

		im.SetNextItemWidth(150);

		if im.BeginCombo(combo_name, curr_res_cstr) {
			
			for res in iri.ShadowmapResolution {

				res_cstr := fmt_cstr("{}", res);

				if im.Selectable(res_cstr) {
					
					changed_to_res = res;
					changed = true;
					break;
				}
			}

			im.EndCombo();
		}

		return;
	}

	any_changed : bool = false;
	light_type := iri.comp_light_get_type(comp);
	{

		curr_type_cstr := fmt_cstr("{}", light_type);

		im.SetNextItemWidth(150);

		if im.BeginCombo("Light Type", curr_type_cstr) {
			
			for type in iri.LightType {


				type_cstr := fmt_cstr("{}", type);

				if im.Selectable(type_cstr) {
					
					iri.comp_light_set_type(comp, type);
					any_changed  |= true;
					
					break;
				}
			}

			im.EndCombo();
		}
	}

	any_changed |= im.ColorEdit3("Color", &comp.color);
	any_changed |= im.DragFloat("Strength"  , &comp.strength , v_speed = 0.01, v_min = 0.000, v_max = 10000000.0);
	any_changed |= im.Checkbox("Cast Shadows", &comp.cast_shadows);

	if comp.cast_shadows {		
		switch &variant in comp.variant {
			case iri.DirectionalLightVariant: 

				for cascade in 0..<3 {

					curr_res := variant.shadowmap_cascade_resolutions[cascade];

					combo_name := fmt_cstr("Cascade {} Shadowmap Resolution", cascade);

					res_changed, changed_to := draw_shadowmap_resolution_combo(combo_name, curr_res);

					if res_changed {
						variant.shadowmap_cascade_resolutions[cascade] = changed_to;
					}

					any_changed |= res_changed;
				}

			case iri.PointLightVariant:

				curr_res := variant.shadowmap_resolution

				res_changed, changed_to := draw_shadowmap_resolution_combo("Shadowmap Resolution", curr_res);

				im.Checkbox("Draw Cone", &variant.draw_cone);
				
				if im.DragInt("Draw Cone Index", &variant.draw_cone_index, v_speed = 0.25, v_min = -1, v_max = 5) {

				}

				if res_changed {
					variant.shadowmap_resolution = changed_to;
				}

				any_changed |= res_changed;

			case iri.SpotLightVariant:

				any_changed |= im.DragFloat("inner cone angle", &variant.inner_cone_angle_deg , v_speed = 0.01, v_min = 0.001, v_max = variant.outer_cone_angle_deg);
				any_changed |= im.DragFloat("outer cone angle", &variant.outer_cone_angle_deg , v_speed = 0.01, v_min = 0.001, v_max = 90.0);
				
				im.Checkbox("Draw Cone", &variant.draw_cone);

				im.Spacing();

				curr_res := variant.shadowmap_resolution

				res_changed, changed_to := draw_shadowmap_resolution_combo("Shadowmap Resolution", curr_res);

				if res_changed {
					variant.shadowmap_resolution = changed_to;
				}

				any_changed |= res_changed;
		}
	}

	if any_changed {
		iri.comp_light_push_changes(comp);
	}
}


draw_component_editor_skybox :: proc (comp : ^iri.SkyboxComponent) {

	changed : bool = false;

	changed |= im.DragFloat("Exposure"  , &comp.exposure , v_speed = 0.01, v_min = -10.0, v_max = 10.0);
	changed |= im.DragFloat("Rotation"  , &comp.rotation , v_speed = 1.0, v_min = -360, v_max = 360.0);

	im.Spacing();

	changed |= im.ColorEdit3("Zenith", &comp.color_zenith);
	changed |= im.ColorEdit3("Horizon", &comp.color_horizon);
	changed |= im.ColorEdit3("Nadir", &comp.color_nadir);



	if im.Button("Set as active Skybox"){
		iri.comp_skybox_set_as_active(comp);
	}



	if changed {
		iri.comp_skybox_push_changes(comp);
	}
}

draw_component_editor_meshrenderer :: proc (comp : ^iri.MeshRendererComponent) {


	button_remove_draw_inst_sameline :: proc(comp : ^iri.MeshRendererComponent, index : u32) -> (pressed : bool) {
		
		im.SameLine();
		btn_lable := fmt_cstr("X##DrawInst{}", index);
		
		im.SetCursorPosX( im.GetCursorPosX() + max(0.0, im.GetContentRegionAvail().x - 30) );
			
		if im.Button(btn_lable, im.Vec2{30,0}) {
			iri.comp_meshrenderer_remove_draw_instance(comp, index);
			
			return true;
		}

		im.SetItemTooltip("Remove Draw Instance");
	
		return false;
	}

	// TODO replace with 
	draw_inst_flag_checkbox :: proc(label : cstring, flag : iri.DrawInstanceFlag,  flags : ^iri.DrawInstanceFlags) -> bool {

		is_enabled : bool = flag in flags;
		if im.Checkbox(label, &is_enabled) {
			
			if is_enabled {
				flags^ += iri.DrawInstanceFlags{flag};
			} else {
				flags^ -= iri.DrawInstanceFlags{flag};
			}

			return true;
		}

		return false;
	}

	im.Spacing();

	if im.Button("Create Draw Instance") {
		iri.comp_meshrenderer_create_draw_instance(comp);
	}

	im.Text("Number Draw Instances %d", len(comp.drawable_indexes));

	if im.Button("All Static") {
		iri.comp_meshrenderer_make_all_static(comp, true);
	}
	im.SameLine()
	if im.Button("All Dynamic") {
		iri.comp_meshrenderer_make_all_static(comp, false);
	}

	im.Selectable("Load/Drag Scene Collection")
	collection_drop: if file_info := file_info_drag_drop_target({.AssetFile}, {.SceneCollection}); file_info != nil {
		iri.comp_meshrenderer_append_scene_collection_asset(comp, file_info.asset_uuid);
	}


	tree_node_flags := im.TreeNodeFlags{.DefaultOpen};
	trans_tree_node_flags := im.TreeNodeFlags{};
	
	im.Spacing();
	im.Spacing();

	inst_loop: for i in 0..<len(comp.drawable_indexes) {
		
		index : u32 = cast(u32)i;

		draw_inst : ^iri.DrawInstance = iri.comp_meshrenderer_get_draw_instance(comp, index);
		if draw_inst == nil {
			continue;
		}

		drawable_index : int = comp.drawable_indexes[index]; // index into ecs.drawables array.
		node_lable := fmt_cstr("DrawInstance: {}", index);

		if im.TreeNodeEx(node_lable, tree_node_flags) {
			defer im.TreePop();
			
			if button_remove_draw_inst_sameline(comp, index) {
				// For mem acces safty we want to break the entire loop after remove of an item!
				// This is because the engine may have modified from 
				// meshrenderers component array that we are currently iterating.
				// Therefore its better to just skip a frame on the remaining indexes.
				break inst_loop; 
			}

			any_changed : bool = false;

			is_static_lable := fmt_cstr("Is Static##{}", index);
			is_visible_lable := fmt_cstr("Is Visible##{}", index);
			cast_shadow_lable := fmt_cstr("Cast Shadows##{}", index);
			
			any_changed |= enum_flags_checkbox(is_static_lable  , iri.DrawInstanceFlag.IsStatic, &draw_inst.flags);
			im.SameLine();
			any_changed |= enum_flags_checkbox(is_visible_lable , iri.DrawInstanceFlag.IsVisible, &draw_inst.flags);
			im.SameLine();
			any_changed |= enum_flags_checkbox(cast_shadow_lable, iri.DrawInstanceFlag.CastShadows, &draw_inst.flags);



			im.Text("DrawableIndex: %d", drawable_index);

			im.BulletText("MeshID: %d", draw_inst.mesh_id);
			im.SameLine();
			im.Selectable("Load/Drag Mesh Asset")

			mesh_drop: if file_info := file_info_drag_drop_target({.AssetFile}, {.Mesh}); file_info != nil {	
				iri.comp_meshrenderer_load_mesh_asset_to_draw_instance(comp,index, file_info.asset_uuid);
			}


			im.BulletText("MatID : %d", draw_inst.mat_id);
			im.SameLine();
			im.Selectable("Load/Drag Material Asset")
			mat_drop: if file_info := file_info_drag_drop_target({.AssetFile}, {.Material}); file_info != nil {
				iri.comp_meshrenderer_load_material_asset_to_draw_instance(comp,index, file_info.asset_uuid);
			}

			trans_node_lable := fmt_cstr("Transform: ##{}", index);
			if im.TreeNodeEx(trans_node_lable, trans_tree_node_flags) {
				any_changed |= draw_editor_transform(&draw_inst.transform)
				im.TreePop();
			}

			if any_changed {
				iri.comp_meshrenderer_force_update_draw_instance(comp, cast(u32)i);
			}

		} else {

			if button_remove_draw_inst_sameline(comp, index) {
				// same here as above break and skip frame for remaining entries.
				break inst_loop; 
			}
		}
	}

	im.Spacing();
}

draw_component_editor_collider :: proc(comp : ^iri.ColliderComponent){

	any_changed : bool = false;

	any_changed |= im.DragFloat3("Offset", &comp.offset, v_speed = 0.01, v_min = -math.F32_MAX, v_max = math.F32_MAX);
	
	curr_type := iri.comp_collider_get_type(comp);

	curr_type_cstr := fmt_cstr("{}", curr_type, allocator = context.temp_allocator)

	any_changed |= enum_flags_checkbox("IsStatic" , iri.ColliderFlag.IsStatic , &comp.flags)
	any_changed |= enum_flags_checkbox("Generate Overlap Events", iri.ColliderFlag.GenerateOverlapEvents, &comp.flags)
	any_changed |= enum_flags_checkbox("Receive Overlap Events" , iri.ColliderFlag.ReceiveOverlapEvents , &comp.flags)

	if im.BeginCombo("Collider Type", curr_type_cstr) {
			
		for type in iri.ColliderType {

			type_cstr := fmt_cstr("{}", type);

			if im.Selectable(type_cstr) {
				
				iri.comp_collider_set_type(comp, type);

				any_changed = true;
				break;
			}
		}
		im.EndCombo();
	}



	switch &v in comp.variant {
		case iri.SphereCollider:{
			any_changed |=  im.DragFloat("Radius"  , &v.radius , v_speed = 0.1, v_min = 0.0, v_max = math.F32_MAX);
		}
		case iri.BoxCollider: {
			im.Text("Box Collider is not yet implemented!")
			any_changed |= im.DragFloat3("Extent", &v.extent, v_speed = 0.1, v_min = -math.F32_MAX, v_max = math.F32_MAX);
			any_changed |= draw_quaternion("Rotation##Collider", &v.orientation);
		}
	}
}


draw_quaternion :: proc(label : cstring, orientation : ^quaternion128) -> bool {
	

	ori := orientation^;

	x,y,z := linalg.euler_angles_from_quaternion_f32(ori, linalg.Euler_Angle_Order.XYZ);
	x = linalg.to_degrees(x);
	y = linalg.to_degrees(y);
	z = linalg.to_degrees(z);
	angles : [3]f32 = {x,y,z}; // copy

	if im.DragFloat3(label, &angles, v_speed = 1.0, v_min = -361, v_max = 361) {

		// users can only modify one value at a time
		// so only one of these will be executed here. 
		// Therefore order of rotation does not matter much and is efectivly dirven by the sequence of 
		// slider inputs by the user anyway.

		if x != angles.x {
			// Rotate around local right axis
			x_dif : f32 = angles.x - x;
			//x_dif : f32 = angles.x;
			right := linalg.quaternion128_mul_vector3(ori, iri.TRANSFORM_WORLD_RIGHT);
			rot_quat := linalg.quaternion_angle_axis(linalg.to_radians(x_dif), right);
			orientation^ = linalg.quaternion_mul_quaternion(rot_quat, ori);

		}
		if y != angles.y {
			// Rotate around local up axis
			y_dif : f32 = angles.y - y;
			up := linalg.quaternion128_mul_vector3(ori, iri.TRANSFORM_WORLD_UP);
			rot_quat := linalg.quaternion_angle_axis(linalg.to_radians(y_dif), up);
			orientation^ = linalg.quaternion_mul_quaternion(rot_quat, ori);
		}
		if z != angles.z {
			z_dif : f32 = angles.z - z;
			// Rotate around local forward axis
			forward  := linalg.quaternion128_mul_vector3(ori, iri.TRANSFORM_WORLD_FORWARD);
			rot_quat := linalg.quaternion_angle_axis(linalg.to_radians(z_dif), forward);
			orientation^ = linalg.quaternion_mul_quaternion(rot_quat, ori);
		}

		return true;
	}

	return false;
}