package iri


MouseButtonActionSet :: bit_set[MouseButtonAction]
MouseButtonAction :: enum u8{
	PRESS 							= 0,
	PRESS_CONTINUOUS				= 1,
	RELEASE 						= 2,
}

MouseButton :: enum u8 {
	LEFT 	= 1,
	MIDDLE 	= 2,
	RIGHT 	= 3,
	X1 		= 4,
	X2 		= 5,
}

KeyActionSet :: bit_set[KeyAction]
KeyAction :: enum u8{
	PRESS 							= 0,
	PRESS_CONTINUOUS				= 1, // ignores KeymodFlags
	REPEAT 							= 2,
	RELEASE 						= 3, // ignores KeymodFlags
}

// This enum mirrors 'sdl.Keycode' exacly
Key :: enum u32 {
	EXTENDED_MASK          = 1 << 29,
	SCANCODE_MASK          = 1 << 30,
	UNKNOWN                = 0x00000000, /**< 0 */
	RETURN                 = 0x0000000d, /**< '\r' */
	ESCAPE                 = 0x0000001b, /**< '\x1B' */
	BACKSPACE              = 0x00000008, /**< '\b' */
	TAB                    = 0x00000009, /**< '\t' */
	SPACE                  = 0x00000020, /**< ' ' */
	EXCLAIM                = 0x00000021, /**< '!' */
	DBLAPOSTROPHE          = 0x00000022, /**< '"' */
	HASH                   = 0x00000023, /**< '#' */
	DOLLAR                 = 0x00000024, /**< '$' */
	PERCENT                = 0x00000025, /**< '%' */
	AMPERSAND              = 0x00000026, /**< '&' */
	APOSTROPHE             = 0x00000027, /**< '\'' */
	LEFTPAREN              = 0x00000028, /**< '(' */
	RIGHTPAREN             = 0x00000029, /**< ')' */
	ASTERISK               = 0x0000002a, /**< '*' */
	PLUS                   = 0x0000002b, /**< '+' */
	COMMA                  = 0x0000002c, /**< ',' */
	MINUS                  = 0x0000002d, /**< '-' */
	PERIOD                 = 0x0000002e, /**< '.' */
	SLASH                  = 0x0000002f, /**< '/' */
	_0                     = 0x00000030, /**< '0' */
	_1                     = 0x00000031, /**< '1' */
	_2                     = 0x00000032, /**< '2' */
	_3                     = 0x00000033, /**< '3' */
	_4                     = 0x00000034, /**< '4' */
	_5                     = 0x00000035, /**< '5' */
	_6                     = 0x00000036, /**< '6' */
	_7                     = 0x00000037, /**< '7' */
	_8                     = 0x00000038, /**< '8' */
	_9                     = 0x00000039, /**< '9' */
	COLON                  = 0x0000003a, /**< ':' */
	SEMICOLON              = 0x0000003b, /**< ';' */
	LESS                   = 0x0000003c, /**< '<' */
	EQUALS                 = 0x0000003d, /**< '=' */
	GREATER                = 0x0000003e, /**< '>' */
	QUESTION               = 0x0000003f, /**< '?' */
	AT                     = 0x00000040, /**< '@' */
	LEFTBRACKET            = 0x0000005b, /**< '[' */
	BACKSLASH              = 0x0000005c, /**< '\\' */
	RIGHTBRACKET           = 0x0000005d, /**< ']' */
	CARET                  = 0x0000005e, /**< '^' */
	UNDERSCORE             = 0x0000005f, /**< '_' */
	GRAVE                  = 0x00000060, /**< '`' */
	A                      = 0x00000061, /**< 'a' */
	B                      = 0x00000062, /**< 'b' */
	C                      = 0x00000063, /**< 'c' */
	D                      = 0x00000064, /**< 'd' */
	E                      = 0x00000065, /**< 'e' */
	F                      = 0x00000066, /**< 'f' */
	G                      = 0x00000067, /**< 'g' */
	H                      = 0x00000068, /**< 'h' */
	I                      = 0x00000069, /**< 'i' */
	J                      = 0x0000006a, /**< 'j' */
	K                      = 0x0000006b, /**< 'k' */
	L                      = 0x0000006c, /**< 'l' */
	M                      = 0x0000006d, /**< 'm' */
	N                      = 0x0000006e, /**< 'n' */
	O                      = 0x0000006f, /**< 'o' */
	P                      = 0x00000070, /**< 'p' */
	Q                      = 0x00000071, /**< 'q' */
	R                      = 0x00000072, /**< 'r' */
	S                      = 0x00000073, /**< 's' */
	T                      = 0x00000074, /**< 't' */
	U                      = 0x00000075, /**< 'u' */
	V                      = 0x00000076, /**< 'v' */
	W                      = 0x00000077, /**< 'w' */
	X                      = 0x00000078, /**< 'x' */
	Y                      = 0x00000079, /**< 'y' */
	Z                      = 0x0000007a, /**< 'z' */
	LEFTBRACE              = 0x0000007b, /**< '{' */
	PIPE                   = 0x0000007c, /**< '|' */
	RIGHTBRACE             = 0x0000007d, /**< '}' */
	TILDE                  = 0x0000007e, /**< '~' */
	DELETE                 = 0x0000007f, /**< '\x7F' */
	PLUSMINUS              = 0x000000b1, /**< '\xB1' */
	CAPSLOCK               = 0x40000039, /**< SCANCODE_TO_KEYCODE(.CAPSLOCK) */
	F1                     = 0x4000003a, /**< SCANCODE_TO_KEYCODE(.F1) */
	F2                     = 0x4000003b, /**< SCANCODE_TO_KEYCODE(.F2) */
	F3                     = 0x4000003c, /**< SCANCODE_TO_KEYCODE(.F3) */
	F4                     = 0x4000003d, /**< SCANCODE_TO_KEYCODE(.F4) */
	F5                     = 0x4000003e, /**< SCANCODE_TO_KEYCODE(.F5) */
	F6                     = 0x4000003f, /**< SCANCODE_TO_KEYCODE(.F6) */
	F7                     = 0x40000040, /**< SCANCODE_TO_KEYCODE(.F7) */
	F8                     = 0x40000041, /**< SCANCODE_TO_KEYCODE(.F8) */
	F9                     = 0x40000042, /**< SCANCODE_TO_KEYCODE(.F9) */
	F10                    = 0x40000043, /**< SCANCODE_TO_KEYCODE(.F10) */
	F11                    = 0x40000044, /**< SCANCODE_TO_KEYCODE(.F11) */
	F12                    = 0x40000045, /**< SCANCODE_TO_KEYCODE(.F12) */
	PRINTSCREEN            = 0x40000046, /**< SCANCODE_TO_KEYCODE(.PRINTSCREEN) */
	SCROLLLOCK             = 0x40000047, /**< SCANCODE_TO_KEYCODE(.SCROLLLOCK) */
	PAUSE                  = 0x40000048, /**< SCANCODE_TO_KEYCODE(.PAUSE) */
	INSERT                 = 0x40000049, /**< SCANCODE_TO_KEYCODE(.INSERT) */
	HOME                   = 0x4000004a, /**< SCANCODE_TO_KEYCODE(.HOME) */
	PAGEUP                 = 0x4000004b, /**< SCANCODE_TO_KEYCODE(.PAGEUP) */
	END                    = 0x4000004d, /**< SCANCODE_TO_KEYCODE(.END) */
	PAGEDOWN               = 0x4000004e, /**< SCANCODE_TO_KEYCODE(.PAGEDOWN) */
	RIGHT                  = 0x4000004f, /**< SCANCODE_TO_KEYCODE(.RIGHT) */
	LEFT                   = 0x40000050, /**< SCANCODE_TO_KEYCODE(.LEFT) */
	DOWN                   = 0x40000051, /**< SCANCODE_TO_KEYCODE(.DOWN) */
	UP                     = 0x40000052, /**< SCANCODE_TO_KEYCODE(.UP) */
	NUMLOCKCLEAR           = 0x40000053, /**< SCANCODE_TO_KEYCODE(.NUMLOCKCLEAR) */
	KP_DIVIDE              = 0x40000054, /**< SCANCODE_TO_KEYCODE(.KP_DIVIDE) */
	KP_MULTIPLY            = 0x40000055, /**< SCANCODE_TO_KEYCODE(.KP_MULTIPLY) */
	KP_MINUS               = 0x40000056, /**< SCANCODE_TO_KEYCODE(.KP_MINUS) */
	KP_PLUS                = 0x40000057, /**< SCANCODE_TO_KEYCODE(.KP_PLUS) */
	KP_ENTER               = 0x40000058, /**< SCANCODE_TO_KEYCODE(.KP_ENTER) */
	KP_1                   = 0x40000059, /**< SCANCODE_TO_KEYCODE(.KP_1) */
	KP_2                   = 0x4000005a, /**< SCANCODE_TO_KEYCODE(.KP_2) */
	KP_3                   = 0x4000005b, /**< SCANCODE_TO_KEYCODE(.KP_3) */
	KP_4                   = 0x4000005c, /**< SCANCODE_TO_KEYCODE(.KP_4) */
	KP_5                   = 0x4000005d, /**< SCANCODE_TO_KEYCODE(.KP_5) */
	KP_6                   = 0x4000005e, /**< SCANCODE_TO_KEYCODE(.KP_6) */
	KP_7                   = 0x4000005f, /**< SCANCODE_TO_KEYCODE(.KP_7) */
	KP_8                   = 0x40000060, /**< SCANCODE_TO_KEYCODE(.KP_8) */
	KP_9                   = 0x40000061, /**< SCANCODE_TO_KEYCODE(.KP_9) */
	KP_0                   = 0x40000062, /**< SCANCODE_TO_KEYCODE(.KP_0) */
	KP_PERIOD              = 0x40000063, /**< SCANCODE_TO_KEYCODE(.KP_PERIOD) */
	APPLICATION            = 0x40000065, /**< SCANCODE_TO_KEYCODE(.APPLICATION) */
	POWER                  = 0x40000066, /**< SCANCODE_TO_KEYCODE(.POWER) */
	KP_EQUALS              = 0x40000067, /**< SCANCODE_TO_KEYCODE(.KP_EQUALS) */
	F13                    = 0x40000068, /**< SCANCODE_TO_KEYCODE(.F13) */
	F14                    = 0x40000069, /**< SCANCODE_TO_KEYCODE(.F14) */
	F15                    = 0x4000006a, /**< SCANCODE_TO_KEYCODE(.F15) */
	F16                    = 0x4000006b, /**< SCANCODE_TO_KEYCODE(.F16) */
	F17                    = 0x4000006c, /**< SCANCODE_TO_KEYCODE(.F17) */
	F18                    = 0x4000006d, /**< SCANCODE_TO_KEYCODE(.F18) */
	F19                    = 0x4000006e, /**< SCANCODE_TO_KEYCODE(.F19) */
	F20                    = 0x4000006f, /**< SCANCODE_TO_KEYCODE(.F20) */
	F21                    = 0x40000070, /**< SCANCODE_TO_KEYCODE(.F21) */
	F22                    = 0x40000071, /**< SCANCODE_TO_KEYCODE(.F22) */
	F23                    = 0x40000072, /**< SCANCODE_TO_KEYCODE(.F23) */
	F24                    = 0x40000073, /**< SCANCODE_TO_KEYCODE(.F24) */
	EXECUTE                = 0x40000074, /**< SCANCODE_TO_KEYCODE(.EXECUTE) */
	HELP                   = 0x40000075, /**< SCANCODE_TO_KEYCODE(.HELP) */
	MENU                   = 0x40000076, /**< SCANCODE_TO_KEYCODE(.MENU) */
	SELECT                 = 0x40000077, /**< SCANCODE_TO_KEYCODE(.SELECT) */
	STOP                   = 0x40000078, /**< SCANCODE_TO_KEYCODE(.STOP) */
	AGAIN                  = 0x40000079, /**< SCANCODE_TO_KEYCODE(.AGAIN) */
	UNDO                   = 0x4000007a, /**< SCANCODE_TO_KEYCODE(.UNDO) */
	CUT                    = 0x4000007b, /**< SCANCODE_TO_KEYCODE(.CUT) */
	COPY                   = 0x4000007c, /**< SCANCODE_TO_KEYCODE(.COPY) */
	PASTE                  = 0x4000007d, /**< SCANCODE_TO_KEYCODE(.PASTE) */
	FIND                   = 0x4000007e, /**< SCANCODE_TO_KEYCODE(.FIND) */
	MUTE                   = 0x4000007f, /**< SCANCODE_TO_KEYCODE(.MUTE) */
	VOLUMEUP               = 0x40000080, /**< SCANCODE_TO_KEYCODE(.VOLUMEUP) */
	VOLUMEDOWN             = 0x40000081, /**< SCANCODE_TO_KEYCODE(.VOLUMEDOWN) */
	KP_COMMA               = 0x40000085, /**< SCANCODE_TO_KEYCODE(.KP_COMMA) */
	KP_EQUALSAS400         = 0x40000086, /**< SCANCODE_TO_KEYCODE(.KP_EQUALSAS400) */
	ALTERASE               = 0x40000099, /**< SCANCODE_TO_KEYCODE(.ALTERASE) */
	SYSREQ                 = 0x4000009a, /**< SCANCODE_TO_KEYCODE(.SYSREQ) */
	CANCEL                 = 0x4000009b, /**< SCANCODE_TO_KEYCODE(.CANCEL) */
	CLEAR                  = 0x4000009c, /**< SCANCODE_TO_KEYCODE(.CLEAR) */
	PRIOR                  = 0x4000009d, /**< SCANCODE_TO_KEYCODE(.PRIOR) */
	RETURN2                = 0x4000009e, /**< SCANCODE_TO_KEYCODE(.RETURN2) */
	SEPARATOR              = 0x4000009f, /**< SCANCODE_TO_KEYCODE(.SEPARATOR) */
	OUT                    = 0x400000a0, /**< SCANCODE_TO_KEYCODE(.OUT) */
	OPER                   = 0x400000a1, /**< SCANCODE_TO_KEYCODE(.OPER) */
	CLEARAGAIN             = 0x400000a2, /**< SCANCODE_TO_KEYCODE(.CLEARAGAIN) */
	CRSEL                  = 0x400000a3, /**< SCANCODE_TO_KEYCODE(.CRSEL) */
	EXSEL                  = 0x400000a4, /**< SCANCODE_TO_KEYCODE(.EXSEL) */
	KP_00                  = 0x400000b0, /**< SCANCODE_TO_KEYCODE(.KP_00) */
	KP_000                 = 0x400000b1, /**< SCANCODE_TO_KEYCODE(.KP_000) */
	THOUSANDSSEPARATOR     = 0x400000b2, /**< SCANCODE_TO_KEYCODE(.THOUSANDSSEPARATOR) */
	DECIMALSEPARATOR       = 0x400000b3, /**< SCANCODE_TO_KEYCODE(.DECIMALSEPARATOR) */
	CURRENCYUNIT           = 0x400000b4, /**< SCANCODE_TO_KEYCODE(.CURRENCYUNIT) */
	CURRENCYSUBUNIT        = 0x400000b5, /**< SCANCODE_TO_KEYCODE(.CURRENCYSUBUNIT) */
	KP_LEFTPAREN           = 0x400000b6, /**< SCANCODE_TO_KEYCODE(.KP_LEFTPAREN) */
	KP_RIGHTPAREN          = 0x400000b7, /**< SCANCODE_TO_KEYCODE(.KP_RIGHTPAREN) */
	KP_LEFTBRACE           = 0x400000b8, /**< SCANCODE_TO_KEYCODE(.KP_LEFTBRACE) */
	KP_RIGHTBRACE          = 0x400000b9, /**< SCANCODE_TO_KEYCODE(.KP_RIGHTBRACE) */
	KP_TAB                 = 0x400000ba, /**< SCANCODE_TO_KEYCODE(.KP_TAB) */
	KP_BACKSPACE           = 0x400000bb, /**< SCANCODE_TO_KEYCODE(.KP_BACKSPACE) */
	KP_A                   = 0x400000bc, /**< SCANCODE_TO_KEYCODE(.KP_A) */
	KP_B                   = 0x400000bd, /**< SCANCODE_TO_KEYCODE(.KP_B) */
	KP_C                   = 0x400000be, /**< SCANCODE_TO_KEYCODE(.KP_C) */
	KP_D                   = 0x400000bf, /**< SCANCODE_TO_KEYCODE(.KP_D) */
	KP_E                   = 0x400000c0, /**< SCANCODE_TO_KEYCODE(.KP_E) */
	KP_F                   = 0x400000c1, /**< SCANCODE_TO_KEYCODE(.KP_F) */
	KP_XOR                 = 0x400000c2, /**< SCANCODE_TO_KEYCODE(.KP_XOR) */
	KP_POWER               = 0x400000c3, /**< SCANCODE_TO_KEYCODE(.KP_POWER) */
	KP_PERCENT             = 0x400000c4, /**< SCANCODE_TO_KEYCODE(.KP_PERCENT) */
	KP_LESS                = 0x400000c5, /**< SCANCODE_TO_KEYCODE(.KP_LESS) */
	KP_GREATER             = 0x400000c6, /**< SCANCODE_TO_KEYCODE(.KP_GREATER) */
	KP_AMPERSAND           = 0x400000c7, /**< SCANCODE_TO_KEYCODE(.KP_AMPERSAND) */
	KP_DBLAMPERSAND        = 0x400000c8, /**< SCANCODE_TO_KEYCODE(.KP_DBLAMPERSAND) */
	KP_VERTICALBAR         = 0x400000c9, /**< SCANCODE_TO_KEYCODE(.KP_VERTICALBAR) */
	KP_DBLVERTICALBAR      = 0x400000ca, /**< SCANCODE_TO_KEYCODE(.KP_DBLVERTICALBAR) */
	KP_COLON               = 0x400000cb, /**< SCANCODE_TO_KEYCODE(.KP_COLON) */
	KP_HASH                = 0x400000cc, /**< SCANCODE_TO_KEYCODE(.KP_HASH) */
	KP_SPACE               = 0x400000cd, /**< SCANCODE_TO_KEYCODE(.KP_SPACE) */
	KP_AT                  = 0x400000ce, /**< SCANCODE_TO_KEYCODE(.KP_AT) */
	KP_EXCLAM              = 0x400000cf, /**< SCANCODE_TO_KEYCODE(.KP_EXCLAM) */
	KP_MEMSTORE            = 0x400000d0, /**< SCANCODE_TO_KEYCODE(.KP_MEMSTORE) */
	KP_MEMRECALL           = 0x400000d1, /**< SCANCODE_TO_KEYCODE(.KP_MEMRECALL) */
	KP_MEMCLEAR            = 0x400000d2, /**< SCANCODE_TO_KEYCODE(.KP_MEMCLEAR) */
	KP_MEMADD              = 0x400000d3, /**< SCANCODE_TO_KEYCODE(.KP_MEMADD) */
	KP_MEMSUBTRACT         = 0x400000d4, /**< SCANCODE_TO_KEYCODE(.KP_MEMSUBTRACT) */
	KP_MEMMULTIPLY         = 0x400000d5, /**< SCANCODE_TO_KEYCODE(.KP_MEMMULTIPLY) */
	KP_MEMDIVIDE           = 0x400000d6, /**< SCANCODE_TO_KEYCODE(.KP_MEMDIVIDE) */
	KP_PLUSMINUS           = 0x400000d7, /**< SCANCODE_TO_KEYCODE(.KP_PLUSMINUS) */
	KP_CLEAR               = 0x400000d8, /**< SCANCODE_TO_KEYCODE(.KP_CLEAR) */
	KP_CLEARENTRY          = 0x400000d9, /**< SCANCODE_TO_KEYCODE(.KP_CLEARENTRY) */
	KP_BINARY              = 0x400000da, /**< SCANCODE_TO_KEYCODE(.KP_BINARY) */
	KP_OCTAL               = 0x400000db, /**< SCANCODE_TO_KEYCODE(.KP_OCTAL) */
	KP_DECIMAL             = 0x400000dc, /**< SCANCODE_TO_KEYCODE(.KP_DECIMAL) */
	KP_HEXADECIMAL         = 0x400000dd, /**< SCANCODE_TO_KEYCODE(.KP_HEXADECIMAL) */
	LCTRL                  = 0x400000e0, /**< SCANCODE_TO_KEYCODE(.LCTRL) */
	LSHIFT                 = 0x400000e1, /**< SCANCODE_TO_KEYCODE(.LSHIFT) */
	LALT                   = 0x400000e2, /**< SCANCODE_TO_KEYCODE(.LALT) */
	LGUI                   = 0x400000e3, /**< SCANCODE_TO_KEYCODE(.LGUI) */
	RCTRL                  = 0x400000e4, /**< SCANCODE_TO_KEYCODE(.RCTRL) */
	RSHIFT                 = 0x400000e5, /**< SCANCODE_TO_KEYCODE(.RSHIFT) */
	RALT                   = 0x400000e6, /**< SCANCODE_TO_KEYCODE(.RALT) */
	RGUI                   = 0x400000e7, /**< SCANCODE_TO_KEYCODE(.RGUI) */
	MODE                   = 0x40000101, /**< SCANCODE_TO_KEYCODE(.MODE) */
	SLEEP                  = 0x40000102, /**< SCANCODE_TO_KEYCODE(.SLEEP) */
	WAKE                   = 0x40000103, /**< SCANCODE_TO_KEYCODE(.WAKE) */
	CHANNEL_INCREMENT      = 0x40000104, /**< SCANCODE_TO_KEYCODE(.CHANNEL_INCREMENT) */
	CHANNEL_DECREMENT      = 0x40000105, /**< SCANCODE_TO_KEYCODE(.CHANNEL_DECREMENT) */
	MEDIA_PLAY             = 0x40000106, /**< SCANCODE_TO_KEYCODE(.MEDIA_PLAY) */
	MEDIA_PAUSE            = 0x40000107, /**< SCANCODE_TO_KEYCODE(.MEDIA_PAUSE) */
	MEDIA_RECORD           = 0x40000108, /**< SCANCODE_TO_KEYCODE(.MEDIA_RECORD) */
	MEDIA_FAST_FORWARD     = 0x40000109, /**< SCANCODE_TO_KEYCODE(.MEDIA_FAST_FORWARD) */
	MEDIA_REWIND           = 0x4000010a, /**< SCANCODE_TO_KEYCODE(.MEDIA_REWIND) */
	MEDIA_NEXT_TRACK       = 0x4000010b, /**< SCANCODE_TO_KEYCODE(.MEDIA_NEXT_TRACK) */
	MEDIA_PREVIOUS_TRACK   = 0x4000010c, /**< SCANCODE_TO_KEYCODE(.MEDIA_PREVIOUS_TRACK) */
	MEDIA_STOP             = 0x4000010d, /**< SCANCODE_TO_KEYCODE(.MEDIA_STOP) */
	MEDIA_EJECT            = 0x4000010e, /**< SCANCODE_TO_KEYCODE(.MEDIA_EJECT) */
	MEDIA_PLAY_PAUSE       = 0x4000010f, /**< SCANCODE_TO_KEYCODE(.MEDIA_PLAY_PAUSE) */
	MEDIA_SELECT           = 0x40000110, /**< SCANCODE_TO_KEYCODE(.MEDIA_SELECT) */
	AC_NEW                 = 0x40000111, /**< SCANCODE_TO_KEYCODE(.AC_NEW) */
	AC_OPEN                = 0x40000112, /**< SCANCODE_TO_KEYCODE(.AC_OPEN) */
	AC_CLOSE               = 0x40000113, /**< SCANCODE_TO_KEYCODE(.AC_CLOSE) */
	AC_EXIT                = 0x40000114, /**< SCANCODE_TO_KEYCODE(.AC_EXIT) */
	AC_SAVE                = 0x40000115, /**< SCANCODE_TO_KEYCODE(.AC_SAVE) */
	AC_PRINT               = 0x40000116, /**< SCANCODE_TO_KEYCODE(.AC_PRINT) */
	AC_PROPERTIES          = 0x40000117, /**< SCANCODE_TO_KEYCODE(.AC_PROPERTIES) */
	AC_SEARCH              = 0x40000118, /**< SCANCODE_TO_KEYCODE(.AC_SEARCH) */
	AC_HOME                = 0x40000119, /**< SCANCODE_TO_KEYCODE(.AC_HOME) */
	AC_BACK                = 0x4000011a, /**< SCANCODE_TO_KEYCODE(.AC_BACK) */
	AC_FORWARD             = 0x4000011b, /**< SCANCODE_TO_KEYCODE(.AC_FORWARD) */
	AC_STOP                = 0x4000011c, /**< SCANCODE_TO_KEYCODE(.AC_STOP) */
	AC_REFRESH             = 0x4000011d, /**< SCANCODE_TO_KEYCODE(.AC_REFRESH) */
	AC_BOOKMARKS           = 0x4000011e, /**< SCANCODE_TO_KEYCODE(.AC_BOOKMARKS) */
	SOFTLEFT               = 0x4000011f, /**< SCANCODE_TO_KEYCODE(.SOFTLEFT) */
	SOFTRIGHT              = 0x40000120, /**< SCANCODE_TO_KEYCODE(.SOFTRIGHT) */
	CALL                   = 0x40000121, /**< SCANCODE_TO_KEYCODE(.CALL) */
	ENDCALL                = 0x40000122, /**< SCANCODE_TO_KEYCODE(.ENDCALL) */
	LEFT_TAB               = 0x20000001, /**< Extended key Left Tab */
	LEVEL5_SHIFT           = 0x20000002, /**< Extended key Level 5 Shift */
	MULTI_KEY_COMPOSE      = 0x20000003, /**< Extended key Multi-key Compose */
	LMETA                  = 0x20000004, /**< Extended key Left Meta */
	RMETA                  = 0x20000005, /**< Extended key Right Meta */
	LHYPER                 = 0x20000006, /**< Extended key Left Hyper */
	RHYPER                 = 0x20000007, /**< Extended key Right Hyper */
}


KeymodFlags :: bit_set[KeymodFlag; u16]
// This enum mirrors 'sdl.KeymodFlag' exacly
KeymodFlag :: enum u16 {
	LEFT_SHIFT 	= 0,  /**< the left Shift key is down. */
	RIGHT_SHIFT = 1,  /**< the right Shift key is down. */
	LEVEL5 		= 2,  /**< the Level 5 Shift key is down. */
	LEFT_CTRL  	= 6,  /**< the left Ctrl (Control) key is down. */
	RIGHT_CTRL  = 7,  /**< the right Ctrl (Control) key is down. */
	LEFT_ALT   	= 8,  /**< the left Alt key is down. */
	RIGHT_ALT   = 9,  /**< the right Alt key is down. */
	LEFT_GUI   	= 10, /**< the left GUI key (often the Windows key) is down. */
	RIGHT_GUI   = 11, /**< the right GUI key (often the Windows key) is down. */
	NUM    		= 12, /**< the Num Lock key (may be located on an extended keypad) is down. */
	CAPS   		= 13, /**< the Caps Lock key is down. */
	MODE   		= 14, /**< the !AltGr key is down. */
	SCROLL 		= 15, /**< the Scroll Lock key is down. */
}


GamepadButtonSet :: bit_set[GamepadButton; u32]
// This enum mirrors 'sdl.GamepadButton' exacly EXCETP
// that sdl.GamepadButton has a 'INVALID' of -1;
// However when we poll events from SDL the GamepadButtonEvent event gives us only a uint8 to represent the button so i guess its fine? lets hope they filter out INVALIDS on their end.
GamepadButton :: enum u32 {
	SOUTH,           /**< Bottom face button (e.g. Xbox A button) */
	EAST,            /**< Right face button (e.g. Xbox B button) */
	WEST,            /**< Left face button (e.g. Xbox X button) */
	NORTH,           /**< Top face button (e.g. Xbox Y button) */
	BACK,
	GUIDE,
	START,
	LEFT_STICK,
	RIGHT_STICK,
	LEFT_SHOULDER,
	RIGHT_SHOULDER,
	DPAD_UP,
	DPAD_DOWN,
	DPAD_LEFT,
	DPAD_RIGHT,
	MISC1,           /**< Additional button (e.g. Xbox Series X share button, PS5 microphone button, Nintendo Switch Pro capture button, Amazon Luna microphone button, Google Stadia capture button) */
	RIGHT_PADDLE1,   /**< Upper or primary paddle, under your right hand (e.g. Xbox Elite paddle P1) */
	LEFT_PADDLE1,    /**< Upper or primary paddle, under your left hand (e.g. Xbox Elite paddle P3) */
	RIGHT_PADDLE2,   /**< Lower or secondary paddle, under your right hand (e.g. Xbox Elite paddle P2) */
	LEFT_PADDLE2,    /**< Lower or secondary paddle, under your left hand (e.g. Xbox Elite paddle P4) */
	TOUCHPAD,        /**< PS4/PS5 touchpad button */
	MISC2,           /**< Additional button */
	MISC3,           /**< Additional button */
	MISC4,           /**< Additional button */
	MISC5,           /**< Additional button */
	MISC6,           /**< Additional button */
}


GamepadButtonActionSet :: bit_set[GamepadButtonAction]
GamepadButtonAction :: enum u8{
	PRESS 							= 0,
	RELEASE 						= 1,
}

GamepadAnalogSet :: bit_set[GamepadAnalog]
GamepadAnalog :: enum u8 {
	RIGHT_TRIGGER,
	LEFT_TRIGGER,
	RIGHT_STICK,
	LEFT_STICK,
}


// These two structures are used to keep track of added gamepads
GamepadStateID :: struct{
	device_id:   u32,	// gamepad device id (sdl.JoystickID)
	array_index: i32,	// index into the array gp_states
}

GamepadAnalogState :: struct {
	trigger_R: 		i16,
	trigger_R_last: i16,
	
	trigger_L: 		i16,
	trigger_L_last: i16,
	
	stick_R: 		[2]i16,
	stick_R_last: 	[2]i16,
	stick_R_sec_since_event: f32, // when stick is not idle (0,0) we track time since last event to reevaluate if its idle now
	
	stick_L: 		[2]i16,
	stick_L_last: 	[2]i16,
	stick_L_sec_since_event: f32, // when stick is not idle (0,0) we track time since last event to reevaluate if its idle now
	
	event_happend_set: GamepadAnalogSet, // The set of Analog/Axis events that occured this frame for this gamepad. Must be reset every frame.
	pressed_btns_set:  GamepadButtonSet, // A set to keep track of which buttons ar currently pressed.
}