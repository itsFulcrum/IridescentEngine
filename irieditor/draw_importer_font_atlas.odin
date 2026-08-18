package iriedit

import "core:log"
import "core:c"
import "core:strings"

import im "odinary:dear_imguy"
import iri "../iriengine"
import iria "../iriengine/iriasset"

import sdl "vendor:sdl3"

// Should be called each frame with no parameter
// and can be called with paramter true to open it next time its called normally
// because modals and popups have to be opened in the same scope.
editor_proj_browser_popup_modal_import_font_ttf :: proc(open_modal : bool = false) {

	@static do_open : bool = false;
	@static is_open : bool = false;
	
	if open_modal {

		if !is_open {
			do_open = true;
		}

		return;
	}

	if do_open {

		im.OpenPopup("Import Font ttf");
		is_open = true;
		do_open = false;
	}

	flags := im.WindowFlags{.AlwaysAutoResize}

	if im.BeginPopupModal("Import Font ttf", nil, flags) {

		importer_settings := &editor.importer_settings;

		draw_font_atlas_create_info(&importer_settings.font_create_info);

		im.Spacing();
		im.Separator()
		im.Spacing();

		if len(importer_settings.curr_import_path) > 0 {
			p_cstr : cstring = strings.clone_to_cstring(importer_settings.curr_import_path, context.temp_allocator);
			im.Text("Path: %s", p_cstr);
		} else {
			im.Text("Path: ---");
		}

		if im.Button("Open File...") {
			window := iri.get_window_context();
			default_dir : cstring = strings.clone_to_cstring(iri.get_project_path(), context.temp_allocator);
			sdl.ShowOpenFileDialog(callback = proj_browser_set_current_import_path_from_file_dialog_callback, userdata = nil, window = window.handle, filters = nil, nfilters = 0, default_location = default_dir, allow_many = false)
		}


		im.Spacing();

		import_btn: if im.Button("Import"){
			
			if len(importer_settings.curr_import_path) <= 0 {
				log.warnf("No import path set.")
				break import_btn;
			}

			
			import_ok := iri.asset_importer_import_font_to_project(importer_settings.curr_import_path, editor.curr_proj_dir, importer_settings.font_create_info);
			
			proj_browser_reload_curr_proj_dir_file_infos();

			
			if import_ok {
				is_open = false;
				do_open = false;
				im.CloseCurrentPopup();
			}
		}

		im.SameLine();

		if im.Button("Cancel"){
			
			is_open = false;
			do_open = false;
			im.CloseCurrentPopup();
		}

		im.EndPopup();
	}
}


draw_font_atlas_create_info :: proc(create_info : ^iri.FontAtlasCreateInfo){

	enum_flags_checkbox("Log Errors", iri.AssetImportFlag.LogErrors,  &create_info.import_flags) 
	enum_flags_checkbox("Overwrite Existing Files", iri.AssetImportFlag.OverwriteExisting,  &create_info.import_flags) 
	
	im.Spacing();
	im.Text("Fonts are imported directly as Atlas Textures.\nConfigure how the Font Atlas Texture should be generated.")
	im.Spacing();

	im.DragFloat("Font Size", &create_info.font_size);
	im.SameLine()
	im.TextDisabled("(?)")
	im.SetItemTooltip("Number of pixels for the tallest Glyph in the Font\nIt is generally better to generate the Atlas at a higher Font Size than what you intend to use for Ui Rendering.")

	im.TextDisabled("(?)")
	im.SetItemTooltip("Oversampling is better for Anti-Alializing Fonts.\nBut it increases the Font Atlas Size.\nIt can look better to Oversample more in the x axis.\nSet this to 1 to when using Point Filtering (Pixel Art Fonts)")
	oversample_x : i32 = cast(i32)create_info.oversampling_x;
	oversample_y : i32 = cast(i32)create_info.oversampling_y;
	if im.DragInt("Oversample X", &oversample_x, 0.1, 0, 16) do create_info.oversampling_x = cast(u32)oversample_x;
	if im.DragInt("Oversample Y", &oversample_y, 0.1, 0, 16) do create_info.oversampling_y = cast(u32)oversample_y;

	im.Checkbox("Point Filtering", &create_info.use_nearest_neighboor_filtering);
	im.SameLine();
	im.TextDisabled("(?)")
	im.SetItemTooltip("Check this for Pixel Art Fonts")

	im.Spacing()
	im.Text("Glyph Ranges")
	im.SameLine()
	im.TextDisabled("(?)")
	im.SetItemTooltip("Which Character Glyphs should be included in the Atlas Texture.\nThis is not a gurantee since only those actually included in the font file can be rendered to the Atlas texture.\n-Extentions- do _Not_ include the base. So -AsciiExtention- does _Not_ include statdard Ascii characters only the extended ones\nConsider using multiple different Font Atlases for supporting multiple languages as the Atlas Textures could get very large.")
	enum_flags_checkbox("Ascii"            , iri.FontGlyphRange.Ascii          , &create_info.glyph_range_flags);
	enum_flags_checkbox("Ascii Extention"  , iri.FontGlyphRange.AsciiExtention , &create_info.glyph_range_flags);
	enum_flags_checkbox("Latin Extention A", iri.FontGlyphRange.LatinExtentionA, &create_info.glyph_range_flags);
	enum_flags_checkbox("Latin Extention B", iri.FontGlyphRange.LatinExtentionB, &create_info.glyph_range_flags);

	im.Spacing();
	im.Text("Custom UTF-8 Codepoint Range");
	im.SameLine()
	im.TextDisabled("(?)")
	im.SetItemTooltip("Specify A custom Range of UTF-8 codepoints in decimal values. e.g. Ascii is 32..127")
	
	custom_range_min : i32 = cast(i32)create_info.custom_range_min_decimal;
	custom_range_max : i32 = cast(i32)create_info.custom_range_max_decimal;
	if im.DragInt("Range Min", &custom_range_min, 0.5, 0, c.INT32_MAX) do create_info.custom_range_min_decimal = cast(u32)custom_range_min;
	if im.DragInt("Range Max", &custom_range_max, 0.5, 0, c.INT32_MAX) do create_info.custom_range_max_decimal = cast(u32)custom_range_max;



	im.Spacing();
	im.Text("Custom UTF-8 String Range");
	im.SameLine()
	im.TextDisabled("(?)")
	im.SetItemTooltip("Specify A custom UTF-8 string of character glyphs to include\nNote that the characters you input here may not be Rendered correctly.\nEspecially if they are special glyphs for Icon Fonts or non english languages.\nHowever as long as the input is valid UTF-8 it should render them into the atlas")
	

	if editor_is_initialized() {
		importer_settings := &editor.importer_settings;

		//input_flags := im.InputTextFlags{.ElideLeft, .EnterReturnsTrue};
		input_flags := im.InputTextFlags{ .EnterReturnsTrue};
			
		//custom_codepoints_cstr := strings.clone_to_cstring(create_info.custom_codepoints, context.temp_allocator);

		buf_cstr : cstring = cstring(&importer_settings.font_custom_utf8_input_txt_buffer.buffer[0]);
		if im.InputTextMultiline("##CustomUtf8GlyphRangeStr", buf_cstr, cast(uint)len(importer_settings.font_custom_utf8_input_txt_buffer.buffer),im.Vec2{0, 0}, input_flags) {

			//create_info.custom_codepoints = input_text_buffer_get_string(&importer_settings.font_custom_utf8_input_txt_buffer);
		}
		
		@static show_codepoints : bool = false;

		im.Checkbox("Show Custom Codepoints", & show_codepoints)

		if show_codepoints {
			
			lop: for codepoint, _ in create_info.custom_codepoints {
				
				decimal : i32 = cast(i32)codepoint;
				
				switch decimal {
					case  0: break    lop; // Null Termination of string
					case 32: continue lop; // blank space.
					case 10: continue lop; // Enter Escape key.
				}
				im.BulletText("- %c - Decimal: %4d - Hex: %x", codepoint, decimal, cast(u32)decimal)
			}
		}

	}
}