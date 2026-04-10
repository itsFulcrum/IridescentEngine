package iriedit


import iri "../iriengine"
import iria "../iriengine/iriasset"

EditorWindowsFlags :: bit_set[EditorWindow]
EditorWindow :: enum u64 {
	Settings = 0,
	UniverseViewer,
	ProjectBrowser,
	Properties,
}

FileInfoTypeFlags :: bit_set[FileInfoType]
FileInfoType :: enum u8 {
	Directory = 0,
	RegularFile,
	AssetFile,
}

FileInfo :: struct {
	fullpath   : string,
	file_type  : FileInfoType,
	asset_uuid : iria.AssetUUID, // only valid if file_type == AssetFile
	asset_type : iria.AssetType, // only valid if file_type == AssetFile
}

// @Note: 
// Entity and Universe Tags in Iridescent Engine are deliberatly defined as just a u32 integer value.
// Tag values don't have any meaning to the engine. It is up to the user Application to Assign meaning 
// to these tags.
// This editor Predefines Tags using the enums 'EntityTag' and 'UniverseTag' below, HOWEVER, this is just meant
// to be used as an example.
// You should define your own Tags in your project, the only restriction is that the 0 value should be a 'None' Tag. 
// To Display your custom Tags (probably an enum) using this editor you should overwrite the following callbacks
// below once before the editor is initialized.
EntityTag :: enum u32 {
	None   		= 0,
	Player 		= 1,
	Enemy  		= 2,
	MainCamera 	= 3,
	Camera 		= 4,
	Skybox 		= 5,
	SunLight 	= 6,
	Collectable = 7,
}

GetCStringForEntityTag_CallbackSignature :: #type proc(tag_val : u32) -> cstring
GetNumDefinedEntityTags_CallbackSignature :: #type proc() -> u32

// Overwrite these two callbacks with you own functions once before the editor is initialized.
get_cstring_for_entity_tag  : GetCStringForEntityTag_CallbackSignature  = get_cstring_for_entity_tag_editor_default
get_num_defined_entity_tags : GetNumDefinedEntityTags_CallbackSignature = get_num_of_defined_entity_tags_editor_default

@(private="file")
get_num_of_defined_entity_tags_editor_default :: proc() -> u32 {
	return len(EntityTag)
}

@(private="file")
get_cstring_for_entity_tag_editor_default :: proc(tag_val : u32) -> cstring {

	if tag_val < len(EntityTag) {
		tag_enum : EntityTag = cast(EntityTag)tag_val;

		return fmt_cstr("{}", tag_enum, allocator = context.temp_allocator);
	}

	return fmt_cstr("UndefinedTag_{}", tag_val, allocator = context.temp_allocator);
}


// Overwrite these two callbacks with you own functions once before the editor is initialized.
get_cstring_for_universe_tag  : GetCStringForUniverseTag_CallbackSignature  = get_cstring_for_universe_tag_editor_default
get_num_defined_universe_tags : GetNumDefinedUniverseTags_CallbackSignature = get_num_of_defined_universe_tags_editor_default

GetCStringForUniverseTag_CallbackSignature :: #type proc(tag_val : u32) -> cstring
GetNumDefinedUniverseTags_CallbackSignature :: #type proc() -> u32

UniverseTag :: enum u32 {
	None   		= 0,
	Level_1 	= 1,
	Level_2 	= 2,
}

@(private="file")
get_num_of_defined_universe_tags_editor_default :: proc() -> u32 {
	return len(UniverseTag)
}

@(private="file")
get_cstring_for_universe_tag_editor_default :: proc(tag_val : u32) -> cstring {

	if tag_val < len(UniverseTag) {
		tag_enum : UniverseTag = cast(UniverseTag)tag_val;

		return fmt_cstr("{}", tag_enum, allocator = context.temp_allocator);
	}

	return fmt_cstr("UndefinedTag_{}", tag_val, allocator = context.temp_allocator);
}