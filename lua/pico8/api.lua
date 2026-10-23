-- The PICO-8 0.2.7 API: functions, callbacks, glyph constants, stat()
-- indices and notable memory addresses. Only functions from the API
-- reference of the official 0.2.7 manual that can be called from a cart are
-- listed (console commands like save, folder or reboot are not).

local M = {}

M.VERSION = "0.2.7"

-- { category, signature(s), description, extra }
-- Signatures use the manual's notation: [x] is optional, ... is variadic.
-- extra: params = { name = doc }, ret = doc, since = version,
--        check = false (don't check the argument count)
local DEFS = {
  -- System ------------------------------------------------------------------
  { "system", "load(filename, [breadcrumb], [param_str])",
    "Load and run a cartridge. When called from a running cart, a pause menu item named BREADCRUMB is added that returns to the previous cart, and PARAM_STR can be read with stat(6). Filenames starting with '#' are BBS cart ids, e.g. load(\"#mygame_level2\").",
    { check = false } },
  { "system", "ls([directory])",
    "List .p8 and .p8.png files in DIRECTORY (relative to the current directory). Returns a table of names when called from a running cart (nil from BBS carts); directories end with a slash." },
  { "system", "run([param_str])",
    "Run from the start of the program; can be called from a running program to reset it. PARAM_STR is available via stat(6)." },
  { "system", "stop([message])",
    "Stop the cart and optionally print MESSAGE.", { check = false } },
  { "system", "assert(condition, [message])",
    "If CONDITION is false, stop the program and print MESSAGE.\n\n    assert(addr >= 0 and addr <= 0x7fff, \"out of range\")" },
  { "system", "reset()",
    "Reset the draw state (RAM 0x5f00..0x5f7f): palette, camera, clipping, fill pattern, ..." },
  { "system", "flip()",
    "Flip the back buffer to the screen and wait for the next frame. Not needed when _draw() or _update() are defined; used for custom main loops." },
  { "system", "printh(str, [filename], [overwrite], [save_to_desktop])",
    "Print STR to the host console. With FILENAME, append to that file instead (OVERWRITE=true replaces it). Use filename \"@clip\" to write to the host clipboard." },
  { "system", "time()",
    "Seconds elapsed since the cart was started (counted in _update calls, not real time). Calls in the same frame return the same value.",
    { ret = "number" } },
  { "system", "t()",
    "Alias of time(): seconds elapsed since the cart was started.", { ret = "number" } },
  { "system", "stat(x)",
    "Get system status X, e.g. 0 memory usage, 1 CPU usage, 7 framerate, 30..39 devkit keyboard/mouse, 46..57 audio state, 80..85 UTC time, 90..95 local time. Hover a number inside stat(...) for details.",
    { params = { x = "status index (see :Pico8Docs stat)" } } },
  { "system", "extcmd(cmd_str, [p1, p2])",
    "Special system command: \"pause\", \"reset\", \"go_back\", \"label\", \"screen\", \"rec\", \"rec_frames\", \"video\", \"audio_rec\", \"audio_end\", \"shutdown\", \"folder\", \"set_filename\", \"set_title\". \"video\"/\"screen\": P1 = scale, P2 > 0 saves to the current folder.",
    { params = { cmd_str = "\"pause\" \"reset\" \"go_back\" \"label\" \"screen\" \"rec\" \"rec_frames\" \"video\" \"audio_rec\" \"audio_end\" \"shutdown\" \"folder\" \"set_filename\" \"set_title\"" } } },

  -- Graphics ----------------------------------------------------------------
  { "graphics", { "clip(x, y, w, h, [clip_previous])", "clip()" },
    "Set the clipping rectangle in pixels. clip() resets it. With CLIP_PREVIOUS=true the new region is clipped by the old one." },
  { "graphics", "pset(x, y, [col])",
    "Set the pixel at X, Y to colour COL (0..15). Without COL the current draw colour is used." },
  { "graphics", "pget(x, y)",
    "Returns the colour of the screen pixel at X, Y (0 when out of bounds).", { ret = "colour" } },
  { "graphics", "sget(x, y)",
    "Returns the colour of the sprite sheet pixel at X, Y.", { ret = "colour" } },
  { "graphics", "sset(x, y, [col])",
    "Set the colour of the sprite sheet pixel at X, Y." },
  { "graphics", "fget(n, [f])",
    "Get flag F (0..7) of sprite N as a boolean. Without F all 8 flags are returned as a bitfield.",
    { ret = "boolean | bitfield" } },
  { "graphics", "fset(n, [f], val)",
    "Set flag F (0..7) of sprite N to VAL (true/false). Without F, VAL sets all flags as a bitfield: fset(2, 1|2|8)." },
  { "graphics", { "print(str, x, y, [col])", "print(str, [col])" },
    "Print STR at X, Y (or at the cursor, followed by a newline) and optionally set the draw colour. Returns the right-most x position. Shorthand: ?\"hi\". See P8SCII control codes, e.g. \"\\f8\" colour, \"\\#1\" background, \"\\^w\" wide, \"\\^o\" outline (0.2.7), \"\\^u\" underline (0.2.7).",
    { ret = "right-most x position",
      params = { str = "string (P8SCII control codes allowed)", col = "colour 0..15" } } },
  { "graphics", "cursor(x, y, [col])",
    "Set the print cursor position and optionally the draw colour." },
  { "graphics", "color([col])",
    "Set the current draw colour (defaults to 6)." },
  { "graphics", "cls([col])",
    "Clear the screen to colour COL (default 0) and reset the clipping rectangle." },
  { "graphics", { "camera(x, y)", "camera()" },
    "Set a screen offset of -X, -Y for all drawing operations. camera() resets it." },
  { "graphics", "circ(x, y, r, [col])",
    "Draw a circle at X, Y with radius R (not drawn when R is negative)." },
  { "graphics", "circfill(x, y, r, [col])",
    "Draw a filled circle at X, Y with radius R. With bits 0x1800.0000 set in COL and (@0x5f34 & 2) == 2 it is drawn inverted." },
  { "graphics", "oval(x0, y0, x1, y1, [col])",
    "Draw an ellipse inside the bounding rectangle X0, Y0 .. X1, Y1." },
  { "graphics", "ovalfill(x0, y0, x1, y1, [col])",
    "Draw a filled ellipse inside the bounding rectangle X0, Y0 .. X1, Y1." },
  { "graphics", "line(x0, y0, [x1, y1, [col]])",
    "Draw a line from X0, Y0 to X1, Y1. Without X1, Y1 the line continues from the end of the last line; line() resets that point." },
  { "graphics", "rect(x0, y0, x1, y1, [col])",
    "Draw a rectangle with corners X0, Y0 and X1, Y1." },
  { "graphics", "rectfill(x0, y0, x1, y1, [col])",
    "Draw a filled rectangle with corners X0, Y0 and X1, Y1." },
  { "graphics", "rrect(x, y, w, h, r, [col])",
    "Draw a rounded rectangle at X, Y of size W x H (both must be > 0). R is the corner radius (default 0), clamped to 0..min(w,h)/2.",
    { since = "0.2.7", params = { w = "width in pixels (> 0)", h = "height in pixels (> 0)", r = "corner radius" } } },
  { "graphics", "rrectfill(x, y, w, h, r, [col])",
    "Draw a filled rounded rectangle at X, Y of size W x H with corner radius R.\n\n    rrectfill(50,80,40,30,2,8) -- red, 40x30, radius 2\n\nWith bits 0x1800.0000 set in COL and (peek(0x5f34) & 2) == 2 it is drawn inverted.",
    { since = "0.2.7", params = { w = "width in pixels (> 0)", h = "height in pixels (> 0)", r = "corner radius" } } },
  { "graphics", { "pal(c0, c1, [p])", "pal(tbl, [p])", "pal([p])" },
    "Swap colour C0 for C1 in palette P: 0 draw palette (default), 1 display palette (whole screen, e.g. fades), 2 secondary palette (fill patterns). pal(tbl, p) assigns several entries at once, e.g. pal({[12]=9, [14]=8}). pal() resets all palettes.",
    { params = { p = "0 draw palette, 1 display palette, 2 secondary palette" } } },
  { "graphics", { "palt(c, [t])", "palt([bitfield])" },
    "Set transparency of colour C to T (boolean) for spr, sspr, map and tline. palt() resets (only colour 0 transparent). With a single number it is a bitfield for all 16 colours: palt(0b1100000000000000)." },
  { "graphics", "spr(n, x, y, [w, h], [flip_x], [flip_y])",
    "Draw sprite N (0..255) at X, Y. W, H (default 1, 1) give how many sprites wide/high to draw. Colour 0 is transparent by default (see palt).",
    { params = { n = "sprite index 0..255", w = "width in sprites (default 1)", h = "height in sprites (default 1)", flip_x = "flip horizontally", flip_y = "flip vertically" } } },
  { "graphics", "sspr(sx, sy, sw, sh, dx, dy, [dw, dh], [flip_x], [flip_y])",
    "Stretch the sprite sheet rectangle SX, SY, SW, SH (pixels) to the screen rectangle DX, DY, DW, DH. DW, DH default to SW, SH.",
    { params = { sx = "sprite sheet x (pixels)", sy = "sprite sheet y (pixels)", dw = "destination width (default sw)", dh = "destination height (default sh)" } } },
  { "graphics", "fillp([p])",
    "Set the 4x4 fill pattern used by circ, circfill, rect, rectfill, oval, ovalfill, pset, line (and sprites with bit 0b0.010). P is a 16-bit bitfield in reading order; bits 0b0.100 transparency, 0b0.010 apply to sprites, 0b0.001 apply secondary palette globally. Glyph constants work too: fillp(▒)." },

  -- Tables ------------------------------------------------------------------
  { "tables", "add(tbl, val, [index])",
    "Add VAL to the end of TBL (or insert it at INDEX). Returns VAL.", { ret = "val" } },
  { "tables", "del(tbl, val)",
    "Delete the first instance of value VAL from TBL, shifting the remaining entries left. Returns the deleted item.", { ret = "deleted item" } },
  { "tables", "deli(tbl, [i])",
    "Delete the item at index I (default: the last item) from TBL and return it.", { ret = "deleted item" } },
  { "tables", "count(tbl, [val])",
    "Returns the length of TBL (same as #tbl), or the number of instances of VAL in it.", { ret = "number" } },
  { "tables", "all(tbl)",
    "Iterator over all items of a 1-based array in the order they were added:\n\n    for v in all(t) do print(v) end" },
  { "tables", "foreach(tbl, func)",
    "Call FUNC with each item of TBL as its single argument: foreach(t, print)." },
  { "tables", "pairs(tbl)",
    "Iterator over all keys and values of TBL (any indexing scheme, unordered):\n\n    for k,v in pairs(t) do ... end" },

  -- Input -------------------------------------------------------------------
  { "input", "btn([b], [pl])",
    "Is button B held for player PL (default 0)? B: 0 ⬅️, 1 ➡️, 2 ⬆️, 3 ⬇️, 4 🅾️, 5 ❎ (glyphs can be used). Without arguments returns a bitfield of all buttons for players 0 and 1.",
    { ret = "boolean | bitfield", params = { b = "button 0..5 (⬅️ ➡️ ⬆️ ⬇️ 🅾️ ❎)", pl = "player 0..7" } } },
  { "input", "btnp([b], [pl])",
    "True when button B was pressed this frame (not held last frame). Repeats after 15 frames, then every 4 frames (custom delays: poke 0x5f5c, 0x5f5d).",
    { ret = "boolean | bitfield", params = { b = "button 0..5 (⬅️ ➡️ ⬆️ ⬇️ 🅾️ ❎)", pl = "player 0..7" } } },

  -- Audio -------------------------------------------------------------------
  { "audio", "sfx(n, [channel], [offset], [length])",
    "Play sfx N (0..63) on CHANNEL (0..3, -1 = auto) from note OFFSET for LENGTH notes. N = -1 stops, N = -2 releases looping; CHANNEL = -2 stops sfx N on any channel. Returns the channel index it was played on (new in 0.2.7).",
    { ret = "channel index (0.2.7)", params = { n = "sfx 0..63, -1 stop, -2 release loop", channel = "0..3, -1 auto (default), -2 stop N everywhere", offset = "start note 0..31", length = "number of notes" } } },
  { "audio", "music(n, [fade_len], [channel_mask])",
    "Play music starting from pattern N (0..63); N = -1 stops. FADE_LEN in ms. CHANNEL_MASK reserves channels for music: music(0, nil, 7) uses channels 0..2.",
    { params = { n = "pattern 0..63, -1 to stop", fade_len = "fade in/out time in ms", channel_mask = "bitfield of reserved channels" } } },

  -- Map ---------------------------------------------------------------------
  { "map", "mget(x, y)",
    "Get the map value (tile) at X, Y.", { ret = "tile index" } },
  { "map", "mset(x, y, val)",
    "Set the map value (tile) at X, Y to VAL." },
  { "map", "map(tile_x, tile_y, [sx, sy], [tile_w, tile_h], [layers])",
    "Draw a section of the map starting at TILE_X, TILE_Y to screen position SX, SY (pixels). TILE_W, TILE_H default to the whole map. LAYERS is a sprite flag bitfield: only sprites with matching flags are drawn. Sprite 0 is not drawn.",
    { params = { tile_x = "map cell x", tile_y = "map cell y", sx = "screen x (pixels)", sy = "screen y (pixels)", tile_w = "width in cells", tile_h = "height in cells", layers = "sprite flag mask" } } },
  { "map", { "tline(x0, y0, x1, y1, mx, my, [mdx, mdy], [layers])", "tline(precision_bits)" },
    "Draw a textured line from X0, Y0 to X1, Y1, sampling colours from the map at MX, MY (in tiles), adding MDX, MDY (default 0.125, 0) per pixel. tline(16) sets the precision so that coordinates are in pixels.",
    { params = { mx = "map x in tiles", my = "map y in tiles", mdx = "delta x per pixel (default 0.125)", mdy = "delta y per pixel (default 0)" } } },

  -- Memory ------------------------------------------------------------------
  { "memory", "peek(addr, [n])",
    "Read a byte from base RAM at ADDR. With N, returns N bytes. Operator form: @addr", { ret = "byte(s)" } },
  { "memory", "poke(addr, [val, ...])",
    "Write one or more bytes to base RAM starting at ADDR." },
  { "memory", "peek2(addr)",
    "Read a 16-bit value (little-endian). Operator form: %addr", { check = false } },
  { "memory", "poke2(addr, val)",
    "Write a 16-bit value (little-endian).", { check = false } },
  { "memory", "peek4(addr)",
    "Read a 32-bit value (16:16 fixed point). Operator form: $addr", { check = false } },
  { "memory", "poke4(addr, val)",
    "Write a 32-bit value (16:16 fixed point).", { check = false } },
  { "memory", "memcpy(dest_addr, source_addr, len)",
    "Copy LEN bytes of base RAM from SOURCE_ADDR to DEST_ADDR (regions may overlap)." },
  { "memory", "reload([dest_addr, source_addr, len], [filename])",
    "Like memcpy, but copies from cart ROM (or from the cart FILENAME). reload() restores all data." },
  { "memory", "cstore([dest_addr, source_addr, len], [filename])",
    "Copy from base RAM to cart ROM (or into the cart FILENAME on disk). cstore() is cstore(0, 0, 0x4300)." },
  { "memory", "memset(dest_addr, val, len)",
    "Write the byte VAL into LEN bytes of memory starting at DEST_ADDR." },

  -- Math --------------------------------------------------------------------
  { "math", "max(x, y)", "Returns the larger of X and Y.", { ret = "number" } },
  { "math", "min(x, y)", "Returns the smaller of X and Y.", { ret = "number" } },
  { "math", "mid(x, y, z)", "Returns the middle value: mid(7,5,10) == 7. Handy for clamping.", { ret = "number" } },
  { "math", "flr(x)", "Round down: flr(4.1) == 4, flr(-2.3) == -3.", { ret = "number" } },
  { "math", "ceil(x)", "Round up: ceil(4.1) == 5, ceil(-2.3) == -2.", { ret = "number" } },
  { "math", "cos(x)", "Cosine of X, where 1.0 is a full turn.", { ret = "number" } },
  { "math", "sin(x)", "Sine of X, where 1.0 is a full turn. Inverted to suit screen space: sin(0.25) == -1.", { ret = "number" } },
  { "math", "atan2(dx, dy)", "Converts DX, DY into an angle 0..1 (anticlockwise in screen space).", { ret = "angle 0..1" } },
  { "math", "sqrt(x)", "Square root of X.", { ret = "number" } },
  { "math", "abs(x)", "Absolute value of X.", { ret = "number" } },
  { "math", { "rnd([x])", "rnd(tbl)" },
    "Random number 0 <= n < X (default 1). For an integer use flr(rnd(x)). With an array-style table, returns a random element.",
    { ret = "number | element" } },
  { "math", "srand(x)", "Set the random number seed." },
  { "math", "sgn(x)", "Returns 1 if X >= 0, else -1 (note: sgn(0) == 1).", { ret = "1 | -1" } },
  { "math", "band(x, y)", "Bitwise and. Operator: x & y", { ret = "number" } },
  { "math", "bor(x, y)", "Bitwise or. Operator: x | y", { ret = "number" } },
  { "math", "bxor(x, y)", "Bitwise xor. Operator: x ^^ y", { ret = "number" } },
  { "math", "bnot(x)", "Bitwise not. Operator: ~x", { ret = "number" } },
  { "math", "shl(x, n)", "Shift left by N bits. Operator: x << n", { ret = "number" } },
  { "math", "shr(x, n)", "Arithmetic shift right by N bits. Operator: x >> n", { ret = "number" } },
  { "math", "lshr(x, n)", "Logical shift right by N bits. Operator: x >>> n", { ret = "number" } },
  { "math", "rotl(x, n)", "Rotate bits left by N. Operator: x <<> n", { ret = "number" } },
  { "math", "rotr(x, n)", "Rotate bits right by N. Operator: x >>< n", { ret = "number" } },

  -- Menu --------------------------------------------------------------------
  { "menu", "menuitem(index, [label], [callback])",
    "Add, update or (without label/callback) remove pause menu item INDEX (1..5). LABEL is up to 16 characters. CALLBACK(b) receives a bitfield of L, R, X presses; return true to keep the menu open. Bits 0xff00 of INDEX filter buttons.",
    { params = { index = "1..5 (bits 0xff00: button mask)", label = "up to 16 characters", callback = "function(b) ... end" } } },

  -- Strings -----------------------------------------------------------------
  { "strings", "tostr(val, [format_flags])",
    "Convert VAL to a string. Flags: 0x1 raw hex value, 0x2 as a signed 32-bit integer (shifted left 16 bits). tostr(nil) == \"[nil]\".",
    { ret = "string" } },
  { "strings", "tonum(val, [format_flags])",
    "Convert VAL to a number (no value if it fails). Flags: 0x1 read as hex without 0x, 0x2 as a signed 32-bit integer, 0x4 return 0 on failure.",
    { ret = "number" } },
  { "strings", "chr(val, ...)",
    "Convert one or more ordinal character codes to a string: chr(104,105) == \"hi\".", { ret = "string" } },
  { "strings", "ord(str, [index], [num_results])",
    "Character code (0..255) of the character at INDEX (default 1) of STR. With NUM_RESULTS, returns several codes.",
    { ret = "number(s)" } },
  { "strings", "sub(str, pos0, [pos1])",
    "Substring from POS0 up to and including POS1 (default: the end). If POS1 is not a number, a single character is returned.",
    { ret = "string" } },
  { "strings", "split(str, [separator], [convert_numbers])",
    "Split STR into a table by SEPARATOR (default \",\"); a number splits into groups of that many characters. Numbers are converted unless CONVERT_NUMBERS is false.",
    { ret = "table" } },
  { "strings", "type(val)",
    "Returns the type of VAL as a string: \"number\", \"string\", \"boolean\", \"table\", \"function\", \"thread\" or \"nil\".",
    { ret = "string" } },

  -- Cartridge data ----------------------------------------------------------
  { "cartdata", "cartdata(id)",
    "Open the permanent data slot ID (up to 64 chars of a..z, 0..9, _) for 64 numbers of persistent data (0x5e00..0x5eff). Returns true if data was loaded. Can switch between up to 4 ids per session (0.2.7).",
    { ret = "boolean" } },
  { "cartdata", "dget(index)", "Get the persistent number at INDEX (0..63). Call cartdata() first.", { ret = "number" } },
  { "cartdata", "dset(index, value)", "Set the persistent number at INDEX (0..63). Call cartdata() first." },

  -- GPIO --------------------------------------------------------------------
  { "gpio", "serial(channel, address, length)",
    "Buffered GPIO / serial IO. CHANNEL: 0x000..0x0fe gpio pins, 0x0ff delay, 0x400.. ws281x, 0x800 dropped file, 0x802 dropped image, 0x804 stdin, 0x805 stdout, 0x806/0x807 files given with -i / -o." },

  -- Lua ---------------------------------------------------------------------
  { "lua", "setmetatable(tbl, m)", "Set the metatable of TBL to M. Returns TBL.", { ret = "tbl" } },
  { "lua", "getmetatable(tbl)", "Returns the metatable of TBL, or nil.", { ret = "table | nil" } },
  { "lua", "rawset(tbl, key, value)", "Set TBL[KEY] = VALUE without invoking metamethods." },
  { "lua", "rawget(tbl, key)", "Get TBL[KEY] without invoking metamethods." },
  { "lua", "rawequal(tbl1, tbl2)", "Compare without invoking metamethods.", { ret = "boolean" } },
  { "lua", "rawlen(tbl)", "Length of TBL without invoking metamethods.", { ret = "number" } },
  { "lua", "select(index, ...)", "Returns all arguments after INDEX; select(\"#\", ...) returns the number of arguments." },
  { "lua", "cocreate(f)", "Create a coroutine for function F.", { ret = "coroutine" } },
  { "lua", "coresume(c, [p0, p1, ...])",
    "Run or continue coroutine C, passing the parameters. Returns true, or false and an error message. Runtime errors in coroutines don't stop the program: wrap in assert(coresume(c)).",
    { ret = "boolean, values... | false, error" } },
  { "lua", "costatus(c)", "Status of coroutine C: \"running\", \"suspended\" or \"dead\".", { ret = "string" } },
  { "lua", "yield(...)", "Suspend the running coroutine and return to the caller of coresume." },
}

-- Globals that exist at runtime but are not part of the documented API.
-- They are not offered anywhere; they are only known so that using them is
-- not reported as an undefined global.
M.UNDOCUMENTED = {
  "ipairs", "inext", "next", "pack", "unpack", "tostring", "trace", "mapdraw",
  "holdframe", "_set_fps", "_update_buttons", "_mark_cpu", "_startframe",
  "_update_framerate", "_set_mainloop_exists", "_map_display",
  "_get_menu_item_selected", "_pausemenu", "set_draw_slice", "_ENV",
}

M.CALLBACKS = {
  _init = "Called once on program startup.",
  _update = "Called once per update at 30fps.",
  _update60 = "Called at 60fps instead of _update(); _draw() is then also called at 60fps (half the CPU per frame).",
  _draw = "Called once per visible frame. Drops to 15fps (calling _update twice) when it can't complete in time.",
}
M.CALLBACK_ORDER = { "_init", "_update", "_update60", "_draw" }

-- Glyph constants (P8SCII 0x80..0x99). Buttons are 0..5, the rest are
-- predefined fill patterns that look like the glyph: fillp(▒).
M.GLYPHS = {
  { "█", "fill pattern" }, { "▒", "fill pattern" }, { "🐱", "fill pattern" },
  { "⬇️", "button 3: down", 3, "down" }, { "░", "fill pattern" }, { "✽", "fill pattern" },
  { "●", "fill pattern" }, { "♥", "fill pattern" }, { "☉", "fill pattern" }, { "웃", "fill pattern" },
  { "⌂", "fill pattern" }, { "⬅️", "button 0: left", 0, "left" }, { "😐", "fill pattern" },
  { "♪", "fill pattern" }, { "🅾️", "button 4: O (Z, C, N)", 4, "obutton" }, { "◆", "fill pattern" },
  { "…", "fill pattern" }, { "➡️", "button 1: right", 1, "right" }, { "★", "fill pattern" },
  { "⧗", "fill pattern" }, { "⬆️", "button 2: up", 2, "up" }, { "ˇ", "fill pattern" },
  { "∧", "fill pattern" }, { "❎", "button 5: X (X, V, M)", 5, "xbutton" }, { "▤", "fill pattern" },
  { "▥", "fill pattern" },
}

-- PICO-8 palette: hex digit -> { rgb, xterm-256 approximation }.
-- g..v are the "secret" colours 128..143 (used by __label__ data).
M.PALETTE = {
  ["0"] = { "#000000", 16 }, ["1"] = { "#1d2b53", 17 }, ["2"] = { "#7e2553", 89 }, ["3"] = { "#008751", 29 },
  ["4"] = { "#ab5236", 131 }, ["5"] = { "#5f574f", 59 }, ["6"] = { "#c2c3c7", 251 }, ["7"] = { "#fff1e8", 255 },
  ["8"] = { "#ff004d", 197 }, ["9"] = { "#ffa300", 214 }, a = { "#ffec27", 226 }, b = { "#00e436", 41 },
  c = { "#29adff", 39 }, d = { "#83769c", 103 }, e = { "#ff77a8", 211 }, f = { "#ffccaa", 223 },
  g = { "#291814", 233 }, h = { "#111d35", 234 }, i = { "#422136", 236 }, j = { "#125359", 23 },
  k = { "#742f29", 88 }, l = { "#49333b", 237 }, m = { "#a28879", 138 }, n = { "#f3ef7d", 228 },
  o = { "#be1250", 161 }, p = { "#ff6c24", 202 }, q = { "#a8e72e", 148 }, r = { "#00b543", 35 },
  s = { "#065ab5", 25 }, t = { "#754665", 96 }, u = { "#ff6e59", 203 }, v = { "#ff9d81", 216 },
}

-- stat(x) indices
M.STAT = {
  [0] = "Memory usage (0..2048)",
  [1] = "CPU used since last flip (1.0 == 100% CPU)",
  [4] = "Clipboard contents (after the user pressed CTRL-V)",
  [6] = "Parameter string (from load() / run())",
  [7] = "Current framerate",
  [16] = "Legacy audio state: sfx playing on channel 0 (use 46)",
  [17] = "Legacy audio state: sfx playing on channel 1 (use 47)",
  [18] = "Legacy audio state: sfx playing on channel 2 (use 48)",
  [19] = "Legacy audio state: sfx playing on channel 3 (use 49)",
  [20] = "Legacy audio state: note on channel 0 (use 50)",
  [21] = "Legacy audio state: note on channel 1 (use 51)",
  [22] = "Legacy audio state: note on channel 2 (use 52)",
  [23] = "Legacy audio state: note on channel 3 (use 53)",
  [24] = "Legacy audio state: current pattern (use 54)",
  [25] = "Legacy audio state: patterns played (use 55)",
  [26] = "Legacy audio state: ticks on pattern (use 56)",
  [30] = "Devkit: (boolean) true when a keypress is available",
  [31] = "Devkit: (string) character returned by keyboard",
  [32] = "Devkit: mouse x",
  [33] = "Devkit: mouse y",
  [34] = "Devkit: mouse buttons (bitfield)",
  [36] = "Devkit: mouse wheel event",
  [38] = "Devkit: relative x movement (requires pointer lock, flag 0x4)",
  [39] = "Devkit: relative y movement (requires pointer lock, flag 0x4)",
  [46] = "Index of the sfx playing on channel 0",
  [47] = "Index of the sfx playing on channel 1",
  [48] = "Index of the sfx playing on channel 2",
  [49] = "Index of the sfx playing on channel 3",
  [50] = "Note number (0..31) on channel 0",
  [51] = "Note number (0..31) on channel 1",
  [52] = "Note number (0..31) on channel 2",
  [53] = "Note number (0..31) on channel 3",
  [54] = "Currently playing pattern index",
  [55] = "Total patterns played",
  [56] = "Ticks played on current pattern",
  [57] = "(boolean) true when music is playing",
  [80] = "UTC time: year",
  [81] = "UTC time: month",
  [82] = "UTC time: day",
  [83] = "UTC time: hour",
  [84] = "UTC time: minute",
  [85] = "UTC time: second",
  [90] = "Local time: year",
  [91] = "Local time: month",
  [92] = "Local time: day",
  [93] = "Local time: hour",
  [94] = "Local time: minute",
  [95] = "Local time: second",
  [100] = "Current breadcrumb label, or nil",
  [110] = "True when in frame-by-frame mode",
  [120] = "True when a dropped file is available on serial channel 0x800",
  [121] = "True when a dropped image is available on serial channel 0x802",
}

-- Notable memory addresses
M.MEMORY = {
  [0x0000] = "GFX: sprite sheet (0x0000..0x0fff)",
  [0x1000] = "GFX2 / MAP2: shared sprite sheet bottom half / map bottom half (0x1000..0x1fff)",
  [0x2000] = "MAP (0x2000..0x2fff)",
  [0x3000] = "GFX flags: sprite flags (0x3000..0x30ff)",
  [0x3100] = "SONG: music patterns (0x3100..0x31ff)",
  [0x3200] = "SFX (0x3200..0x42ff)",
  [0x4300] = "User data (0x4300..0x55ff)",
  [0x5600] = "Custom font (if one is defined, 0x5600..0x5dff)",
  [0x5e00] = "Persistent cart data (256 bytes, after cartdata())",
  [0x5f00] = "Draw state (0x5f00..0x5f3f)",
  [0x5f2d] = "Devkit input mode: 0x1 enable, 0x2 mouse buttons trigger btn(4)..btn(6), 0x4 pointer lock",
  [0x5f34] = "Draw flags: 0x1 fill pattern in colour high bits, 0x2 inversion mode (circfill, rectfill, rrectfill ...)",
  [0x5f36] = "Misc flags: 0x8 draw sprite 0 in map/tline, 0x10 custom out-of-bounds values for pget/sget/mget, 0x40 disable print scrolling",
  [0x5f37] = "1: don't reload cart rom into base ram when leaving the editor",
  [0x5f38] = "tline: map x loop mask (power of 2 width)",
  [0x5f39] = "tline: map y loop mask (power of 2 height)",
  [0x5f3a] = "tline: map x offset (tiles)",
  [0x5f3b] = "tline: map y offset (tiles)",
  [0x5f40] = "Hardware state (0x5f40..0x5f7f)",
  [0x5f54] = "GFX memory mapping: 0x00 (default) or 0x60 (use screen as sprite sheet)",
  [0x5f55] = "SCREEN memory mapping: 0x60 (default) or 0x00 (draw into the sprite sheet)",
  [0x5f56] = "MAP memory mapping: 0x20 (default), 0x10..0x2f, or 0x80 and above",
  [0x5f57] = "Map width (0 means 256, default 128)",
  [0x5f58] = "Default print attributes (bitfield: 0x1 enable, 0x2 padding, 0x4 wide, 0x8 tall, 0x10 solid bg, 0x20 invert, 0x40 stripey, 0x80 custom font)",
  [0x5f59] = "Default print char_w (low nibble) / char_h (high) — also custom sget() out-of-bounds value",
  [0x5f5a] = "Default print char_w2 (low) / tab_w (high) — also custom mget() out-of-bounds value",
  [0x5f5b] = "Default print offset_x (low) / offset_y (high) — also custom pget() out-of-bounds value",
  [0x5f5c] = "btnp() initial repeat delay in frames (255: never repeat, 0: default 15)",
  [0x5f5d] = "btnp() repeat delay in frames (0: default 4)",
  [0x5f80] = "GPIO pins (128 bytes, 0x5f80..0x5fff)",
  [0x6000] = "SCREEN (8k, 0x6000..0x7fff)",
  [0x8000] = "Upper user data (0x8000..0xffff)",
}

M.KEYWORDS = {
  "and", "break", "do", "else", "elseif", "end", "false", "for", "function",
  "goto", "if", "in", "local", "nil", "not", "or", "repeat", "return",
  "then", "true", "until", "while",
}

-- Standard Lua libraries that do NOT exist in PICO-8, with replacements.
M.STDLIB = {
  math = {
    _ = "PICO-8 has no 'math' library",
    floor = "flr(x)", ceil = "ceil(x)", abs = "abs(x)", sqrt = "sqrt(x)",
    random = "rnd(x)", randomseed = "srand(x)", min = "min(x, y)", max = "max(x, y)",
    sin = "sin(x) (1.0 = full turn, inverted y)", cos = "cos(x) (1.0 = full turn)",
    atan = "atan2(dx, dy)", atan2 = "atan2(dx, dy)", pi = "3.14159 (sin/cos take turns, not radians)",
    huge = "32767.99999 (0x7fff.ffff)", fmod = "x % y", modf = "flr(x), x % 1",
  },
  string = {
    _ = "PICO-8 has no 'string' library",
    sub = "sub(str, i, j)", len = "#str", char = "chr(...)", byte = "ord(str, i)",
    format = "string concatenation with ..", upper = "a custom function (PICO-8 uses puny font for capitals)",
    lower = "a custom function", rep = "a loop", find = "a loop with sub()", split = "split(str, sep)",
  },
  table = {
    _ = "PICO-8 has no 'table' library",
    insert = "add(tbl, val, [index])", remove = "deli(tbl, [i])", unpack = "tbl[1], tbl[2], ...",
    pack = "{...} and select(\"#\", ...)", concat = "a loop with ..", sort = "a custom sort function",
  },
  coroutine = {
    _ = "PICO-8 has no 'coroutine' library",
    create = "cocreate(f)", resume = "coresume(c, ...)", status = "costatus(c)",
    yield = "yield(...)", wrap = "cocreate + coresume",
  },
  os = { _ = "PICO-8 has no 'os' library", time = "time() / stat(80..95)", clock = "time()", date = "stat(80..95)" },
  io = { _ = "PICO-8 has no 'io' library", write = "print() / printh()", read = "stat(30)/stat(31) (devkit keyboard)" },
  debug = { _ = "PICO-8 has no 'debug' library" },
  bit32 = { _ = "PICO-8 has no 'bit32' library: use the operators & | ^^ ~ << >> >>> <<> >><" },
  utf8 = { _ = "PICO-8 has no 'utf8' library (strings are P8SCII)" },
  package = { _ = "PICO-8 has no 'package' library" },
  require = { _ = "'require' does not exist in PICO-8: use #include file.lua" },
  dofile = { _ = "'dofile' does not exist in PICO-8: use #include file.lua" },
  loadstring = { _ = "'loadstring' does not exist in PICO-8" },
  tonumber = { _ = "'tonumber' does not exist in PICO-8: use tonum(val)" },
  pcall = { _ = "'pcall' does not exist in PICO-8 (coroutines can catch errors: coresume)" },
  xpcall = { _ = "'xpcall' does not exist in PICO-8" },
  error = { _ = "'error' does not exist in PICO-8: use assert(false, msg) or stop(msg)" },
}

-- Build lookup tables ---------------------------------------------------------

--- Parse "spr(n, x, y, [w, h], [flip_x])" into name and params.
local function parse_signature(sig)
  local name, args = sig:match("^([%w_]+)%((.*)%)$")
  local params = {}
  local depth = 0
  local cur = ""
  local vararg = false
  local function flush()
    local p = vim.trim(cur)
    if p ~= "" then
      if p == "..." then
        vararg = true
      end
      params[#params + 1] = { name = p, optional = depth > 0 or p == "..." }
    end
    cur = ""
  end
  for ch in args:gmatch(".") do
    if ch == "[" then
      flush()
      depth = depth + 1
    elseif ch == "]" then
      flush()
      depth = depth - 1
    elseif ch == "," then
      flush()
    else
      cur = cur .. ch
    end
  end
  flush()
  return name, params, vararg
end
M.parse_signature = parse_signature

M.functions = {} -- name -> entry
M.list = {} -- the same entries in manual order
M.categories = {
  { "system", "System" }, { "graphics", "Graphics" }, { "tables", "Tables" },
  { "input", "Input" }, { "audio", "Audio" }, { "map", "Map" }, { "memory", "Memory" },
  { "math", "Math & bitwise" }, { "menu", "Custom menu items" }, { "strings", "Strings & types" },
  { "cartdata", "Cartridge data" }, { "gpio", "GPIO" }, { "lua", "Lua: metatables & coroutines" },
}

for _, d in ipairs(DEFS) do
  local cat, sigs, desc, extra = d[1], d[2], d[3], d[4] or {}
  if type(sigs) == "string" then
    sigs = { sigs }
  end
  local entry = {
    category = cat,
    signatures = {},
    description = desc,
    ret = extra.ret,
    since = extra.since,
    check = extra.check ~= false,
    param_docs = extra.params or {},
    max_args = 0,
  }
  for _, sig in ipairs(sigs) do
    local name, params, vararg = parse_signature(sig)
    entry.name = entry.name or name
    entry.signatures[#entry.signatures + 1] = { label = sig, params = params, vararg = vararg }
    if vararg then
      entry.max_args = math.huge
    elseif entry.max_args ~= math.huge then
      entry.max_args = math.max(entry.max_args, #params)
    end
  end
  M.functions[entry.name] = entry
  M.list[#M.list + 1] = entry
end

M.glyphs = {} -- glyph -> { doc, value, name }
for _, g in ipairs(M.GLYPHS) do
  M.glyphs[g[1]] = { doc = g[2], value = g[3], name = g[4] }
end

--- Every predefined global name.
M.builtins = {}
for name in pairs(M.functions) do
  M.builtins[name] = true
end
for _, name in ipairs(M.UNDOCUMENTED) do
  M.builtins[name] = true
end
for g in pairs(M.glyphs) do
  M.builtins[g] = true
end

--- Names for syntax highlighting.
function M.builtin_function_names()
  local names = vim.tbl_keys(M.functions)
  table.sort(names)
  return names
end

--- Plain text documentation of a function (no markdown: it is shown as is
--- by hover windows and completion menus).
---@param entry table
---@param opts? { signatures?: boolean } signatures = false leaves them out
function M.doc_text(entry, opts)
  opts = opts or {}
  local out = {}
  if opts.signatures ~= false then
    for _, s in ipairs(entry.signatures) do
      out[#out + 1] = s.label
    end
    out[#out + 1] = ""
  end
  out[#out + 1] = entry.description
  local pdocs, width, seen = {}, 0, {}
  for _, s in ipairs(entry.signatures) do
    for _, p in ipairs(s.params) do
      local doc = entry.param_docs[p.name]
      if doc and not seen[p.name] then
        seen[p.name] = true
        pdocs[#pdocs + 1] = { p.name, doc }
        width = math.max(width, #p.name)
      end
    end
  end
  if #pdocs > 0 then
    out[#out + 1] = ""
    for _, pd in ipairs(pdocs) do
      out[#out + 1] = ("  %-" .. width .. "s  %s"):format(pd[1], pd[2])
    end
  end
  if entry.ret then
    out[#out + 1] = ""
    out[#out + 1] = "Returns: " .. entry.ret
  end
  out[#out + 1] = ""
  local footer = ("PICO-8 %s, %s"):format(M.VERSION, entry.category)
  if entry.since then
    footer = footer .. (" (new in %s)"):format(entry.since)
  end
  out[#out + 1] = footer
  return table.concat(out, "\n")
end

return M
