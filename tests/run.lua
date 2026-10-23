-- Test suite. Run from the repository root:
--   nvim --headless -u tests/minimal_init.lua -c "luafile tests/run.lua"
-- Expected token/char counts were produced with shrinko8 (`--count`).

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local fixtures = root .. "/tests/fixtures"

local passed, failed = 0, {}

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
  else
    failed[#failed + 1] = name .. ": " .. tostring(err)
  end
end

local function eq(actual, expected, what)
  if not vim.deep_equal(actual, expected) then
    error(("%s: expected %s, got %s"):format(what or "value", vim.inspect(expected), vim.inspect(actual)), 2)
  end
end

local function truthy(v, what)
  if not v then
    error((what or "value") .. " is falsy", 2)
  end
end

local lexer = require("pico8.lexer")
local tokens = require("pico8.tokens")
local parser = require("pico8.parser")
local cart = require("pico8.cart")
local analysis = require("pico8.analysis")

local function count(code)
  return tokens.count(lexer.lex(code).tokens)
end

local function parse(code)
  return parser.parse(lexer.lex(code))
end

local function values(code)
  local out = {}
  for _, t in ipairs(lexer.lex(code).tokens) do
    if t.type ~= "eof" then
      out[#out + 1] = t.value
    end
  end
  return out
end

-- lexer ------------------------------------------------------------------------

test("lexer: PICO-8 operators", function()
  eq(values("a>>>=1 b<<>=2 c>><=3 d^^=4 e..=f g\\=2 h!=i j>>>k"), {
    "a", ">>>=", "1", "b", "<<>=", "2", "c", ">><=", "3", "d", "^^=", "4", "e", "..=", "f",
    "g", "\\=", "2", "h", "!=", "i", "j", ">>>", "k",
  })
  eq(values("x=@a+%b+$c ?x"), { "x", "=", "@", "a", "+", "%", "b", "+", "$", "c", "?", "x" })
end)

test("lexer: comments, numbers, glyphs", function()
  local lx = lexer.lex("a=0x1f.8 // c\nb=0b101.1 c=.5 -- d\n--[[x\ny]] btn(⬅️)")
  eq(#lx.comments, 3, "comments")
  eq(values("a=0x1f.8 b=0b101.1 c=.5"), { "a", "=", "0x1f.8", "b", "=", "0b101.1", "c", "=", ".5" })
  eq(values("btn(⬅️)"), { "btn", "(", "⬅️", ")" })
  -- PICO-8 lets a name follow a number directly
  eq(values("x=0.x=1"), { "x", "=", "0.", "x", "=", "1" })
end)

test("lexer: #include directives", function()
  local lx = lexer.lex("#include a.lua\n  #include b c.lua\nprint(\n#include\n)")
  eq(#lx.directives, 2)
  eq(lx.directives[1].include, "a.lua")
  eq(lx.directives[2].include, "b c.lua")
  eq(values("x=\n#t"), { "x", "=", "#", "t" })
end)

test("lexer: errors", function()
  eq(lexer.lex('x="abc\ny=1').errors[1].msg, "unfinished string near '\"abc'")
  eq(lexer.lex("--[[ open").errors[1].msg, "unfinished long comment")
  eq(lexer.lex("x=1..2").errors[1].msg, "malformed number near '1..2'")
end)

test("lexer: positions", function()
  local t = lexer.lex("a\n  bb=[[x\ny]]", { line = 10 }).tokens
  eq({ t[2].line, t[2].col, t[2].ecol }, { 11, 2, 4 })
  eq({ t[4].line, t[4].col, t[4].eline, t[4].ecol }, { 11, 5, 12, 3 })
end)

-- token counting -------------------------------------------------------------------

test("tokens: basic rules", function()
  eq(count("x=1"), 3)
  eq(count("x=-1"), 3, "unary minus merges into number")
  eq(count("x = - 1"), 4, "not when separated by space")
  eq(count("z=a-1"), 5)
  eq(count("w=a - -1"), 5)
  eq(count("local a=1"), 3, "local is free")
  eq(count('print("hi")'), 3, "closing bracket is free")
  eq(count("function f() end"), 3, "end is free")
  eq(count("t={1,2,3}"), 6, "commas are free")
  eq(count("a.b.c=1"), 5, "dots are free")
  eq(count("o:m()"), 3)
  eq(count("-- comment\n// c\n--[[ x ]]"), 0)
  eq(count("::a:: goto a"), 3)
  eq(count("x+=1;y+=2"), 6)
  eq(count("e=-0x10 g=~5"), 6)
end)

test("tokens: fixtures match shrinko8", function()
  for file, expected in pairs({ ["tokens.p8"] = { 172, 440 }, ["lib.lua"] = { 40, 143 } }) do
    local res = analysis.analyze(cart.read_lines(fixtures .. "/" .. file), fixtures .. "/" .. file)
    eq({ res.tokens, res.chars }, expected, file)
  end
end)

test("tokens: per tab", function()
  local res = analysis.analyze(cart.read_lines(fixtures .. "/tokens.p8"), fixtures .. "/tokens.p8")
  eq(res.tab_tokens[0] + res.tab_tokens[1], 172)
  eq(res.tab_tokens[1], 29)
end)

test("tokens: #include totals match shrinko8", function()
  vim.cmd.edit(fixtures .. "/syntax.p8")
  local ctx = analysis.context(0)
  eq({ ctx.res.tokens, ctx.total_tokens, ctx.total_chars }, { 91, 131, 586 })
  vim.cmd("bwipeout!")
end)

test("chars: P8SCII glyphs", function()
  eq(tokens.chars("abc"), 3)
  eq(tokens.chars("⬅️➡️❎🅾️"), 4, "glyphs with variation selector are one char")
  eq(tokens.chars("█▒"), 2)
  eq(tokens.chars("⬅"), 3, "unknown codepoints count per byte")
  eq(tokens.chars("あア"), 2)
end)

-- cart layout ------------------------------------------------------------------

test("cart: sections and tabs", function()
  local info = cart.parse(cart.read_lines(fixtures .. "/syntax.p8"))
  truthy(info.is_cart)
  eq(info.lua_line, 2)
  eq(info.code_start, 3)
  eq(#info.tabs, 2)
  eq(info.sections[2].name, "gfx")
  eq(info.code_end, info.sections[2].line)
  eq(cart.section_at(info, info.code_end + 1), "gfx")
  local tpl = cart.template()
  eq(tpl[2], "version 43")
end)

-- parser -------------------------------------------------------------------------

test("parser: PICO-8 dialect parses", function()
  local res = analysis.analyze(cart.read_lines(fixtures .. "/tokens.p8"), fixtures .. "/tokens.p8")
  truthy(res.parse.ok, res.parse.error and res.parse.error.msg)
  for _, code in ipairs({
    "if (x) y=1 else y=2\nz=3",
    "while (x>0) x-=1",
    "if x do y=1 end",
    "x=?\"hi\"",
    "function f(...) local a={...} return select('#',...) end",
    "do if 1==2 then ::b:: end goto b end ::b::",
    "for i=1,3 do if i==2 then break end end",
    "a.b.c:d(1)\"s\"{1}",
    "x=y\nz=w",
    "if (a) if (b) c=1",
    "local function f() return f() end",
    "return",
  }) do
    local r = parse(code)
    truthy(r.ok, code .. " -> " .. (r.error and r.error.msg or ""))
  end
end)

test("parser: syntax errors", function()
  local cases = {
    ["function f()\n x=1"] = "'end' expected (to close 'function' at line 1) near <eof>",
    ["if x y=1"] = "'then' expected near 'y'",
    ["x"] = "syntax error near <eof>",
    ["x=1 y"] = "syntax error near <eof>",
    ["break"] = "<break> at line 1 not inside a loop",
    ["goto nowhere"] = "no visible label 'nowhere' for goto",
    ["function f() return ... end"] = "cannot use '...' outside a vararg function near '...'",
    ["for i do end"] = "'=' or 'in' expected near 'do'",
    ["x=(1"] = "')' expected near <eof>",
    ["end"] = "'<eof>' expected near 'end'",
    ["return 1 x=2"] = "'<eof>' expected near 'x'",
    ["::a:: ::a::"] = "label 'a' already defined on line 1",
    ["f(,)"] = "unexpected symbol near ','",
  }
  for code, msg in pairs(cases) do
    local r = parse(code)
    eq(r.ok, false, code)
    eq(r.error.msg, msg, code)
  end
end)

test("parser: scopes", function()
  local r = parse("local a=1\nfunction g(p, q) return p end\nb=a c+=1\nlocal function h() end")
  truthy(r.ok)
  eq(r.globals.g.kind, "function")
  eq(r.globals.b.kind, "variable")
  eq(r.globals.c, nil, "compound assignment is not a definition")
  local unused = {}
  for _, v in ipairs(r.unused) do
    unused[#unused + 1] = v.name .. ":" .. v.kind
  end
  table.sort(unused)
  eq(unused, { "h:function", "q:param" })
  -- functions assigned to names
  local r3 = parse("foo=function(a,b) end local bar=function(c) end x=bar")
  eq(r3.globals.foo.kind, "function")
  eq(r3.globals.foo.fn.params, { "a", "b" })
  local bar = vim.tbl_filter(function(v)
    return v.name == "bar"
  end, r3.locals)[1]
  eq(bar.fn.params, { "c" })
  -- local a = a refers to the outer a
  local r2 = parse("a=1 local a=a")
  eq(#r2.global_refs, 2)
end)

-- diagnostics ------------------------------------------------------------------------

local function diag_codes(lines, name)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, name or (fixtures .. "/scratch.p8.lua"))
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local d = require("pico8.diagnostics").compute(buf)
  vim.api.nvim_buf_delete(buf, { force = true })
  local out = {}
  for _, x in ipairs(d) do
    out[#out + 1] = (x.lnum + 1) .. ":" .. x.code .. ":" .. x.message
  end
  table.sort(out)
  return out
end

test("diagnostics: checks", function()
  local d = diag_codes({
    "function _update()",
    " x=math.floor(1.5)",
    " Spr(1,2,3)",
    " circfil(1,2,3)",
    " spr(1,2,3,4,5,true,false,9)",
    " local unused=1",
    " btn(⬅)",
    " lives-=1",
    " rrect(1,2,3,4,5,6)",
    " print(1,2,3,4,f())",
    "end",
  })
  local expected = {
    "10:undefined-global:undefined global 'f'",
    "2:stdlib:math.floor doesn't exist: PICO-8 has no 'math' library, use flr(x)",
    "3:undefined-global:undefined global 'Spr' - did you mean 'spr'? (PICO-8 names are lowercase)",
    "4:undefined-global:undefined global 'circfil' - did you mean 'circfill'?",
    "5:arg-count:too many arguments for spr(): expected at most 7, got 8",
    "6:unused:unused local 'unused'",
    "7:undefined-global:undefined global '⬅' - did you mean '⬅️'? (PICO-8 needs the glyph with its variation selector (U+FE0F))",
    "8:undefined-global:global 'lives' is updated but never assigned",
  }
  table.sort(expected)
  eq(d, expected)
end)

test("diagnostics: syntax error only", function()
  eq(diag_codes({ "function f()", " x=1" }), { "2:syntax:'end' expected (to close 'function' at line 1) near <eof>" })
end)

test("diagnostics: lint comments and project globals", function()
  eq(diag_codes({ "--lint: extern_thing", "print(extern_thing)" }), {})
  -- lib.lua is #included by syntax.p8: globals of the cart are known there
  eq(diag_codes({ "function lerp(a,b,t) return a+(b-a)*t+player.x end" }, fixtures .. "/lib.lua"), {})
end)

test("diagnostics: include errors and limits", function()
  local d = diag_codes({ cart.HEADER, "version 43", "__lua__", "#include nope.lua", "x=1" }, fixtures .. "/inc.p8")
  eq(d, { "4:include:#include: file not found: nope.lua" })
  local big = { cart.HEADER, "version 43", "__lua__" }
  for i = 1, 2800 do
    big[#big + 1] = "a" .. i .. "=1"
  end
  local d2 = diag_codes(big, fixtures .. "/big.p8")
  eq(d2[1], "3:token-limit:token limit exceeded: 8400/8192")
end)

-- editor features ---------------------------------------------------------------------

local function open(file)
  vim.cmd("silent! %bwipeout!")
  vim.cmd("edit! " .. fixtures .. "/" .. file)
  return vim.api.nvim_get_current_buf()
end

local function labels(items, pattern)
  local out = {}
  for _, it in ipairs(items) do
    if it.label:match(pattern) then
      out[#out + 1] = it.label
    end
  end
  table.sort(out)
  return out
end

test("completion: contexts", function()
  local completion = require("pico8.completion")
  local buf = open("syntax.p8")
  local res = analysis.get(buf)
  eq(completion.context_at(res, 3, 5).kind, "none", "comment")
  eq(completion.context_at(res, 10, 10).kind, "none", "string")
  eq(completion.context_at(res, 33, 2).kind, "none", "gfx data")
  local cx = completion.context_at(res, 16, 26)
  eq({ cx.kind, cx.base }, { "member", "player" })
  eq(completion.context_at(res, 5, 12).kind, "include")
  vim.cmd("bwipeout!")
end)

test("completion: items", function()
  local completion = require("pico8.completion")
  local buf = open("syntax.p8")
  vim.api.nvim_buf_set_lines(buf, 13, 13, false, { " sp", " player.", " lv=le" })
  local items = completion.items(buf, 13, 3)
  eq(labels(items, "^sp"), { "split", "spr" })
  local spr
  for _, it in ipairs(items) do
    if it.label == "spr" then
      spr = it
    end
  end
  eq(spr.textEdit.newText, "spr(${1:n}, ${2:x}, ${3:y})$0")
  eq(spr.textEdit.range.start.character, 1)
  eq(#labels(items, "^⬅️$"), 1, "glyphs")
  local events = vim.tbl_filter(function(it)
    return it.kind == completion.Kind.Event
  end, items)
  eq(labels(events, "."), { "_draw", "_init", "_update", "_update60" }, "callbacks")
  eq(#labels(items, "^game$"), 1, "snippets")
  eq(labels(completion.items(buf, 14, 8), "."), { "spd", "x", "y" })
  -- functions from #include lib.lua
  local le = completion.items(buf, 15, 6)
  local fns = vim.tbl_filter(function(it)
    return it.kind == completion.Kind.Function
  end, le)
  eq(#labels(fns, "^lerp$"), 1, "included function")
  vim.cmd("bwipeout!")
end)

test("completion: include files", function()
  local completion = require("pico8.completion")
  local buf = open("syntax.p8")
  vim.api.nvim_buf_set_lines(buf, 5, 6, false, { "#include l" })
  local items = completion.items(buf, 5, 10)
  eq(#labels(items, "^lib%.lua$"), 1)
  vim.cmd("bwipeout!")
end)

test("hover", function()
  local hover = require("pico8.hover")
  local buf = open("syntax.p8")
  local h = hover.get(buf, 29, 2)
  truthy(h.contents.value:find("new in 0.2.7", 1, true), "rrectfill hover")
  h = hover.get(buf, 9, 5)
  truthy(h.contents.value:find("31.5", 1, true), "number hover")
  h = hover.get(buf, 18, 17)
  truthy(h.contents.value:find("Devkit input mode", 1, true), "memory address hover")
  h = hover.get(buf, 7, 10)
  truthy(h.contents.value:find("tokens", 1, true), "user function hover")
  h = hover.get(buf, 16, 9)
  truthy(h.contents.value:find("button 0", 1, true), "glyph hover")
  vim.cmd("bwipeout!")
  eq(hover.parse_number("0x1f.8"), 31.5)
  eq(hover.parse_number("0b1010.1"), 10.5)
  eq(hover.parse_number("-1") == nil, false)
end)

test("signature help", function()
  local sig = require("pico8.signature")
  local buf = open("syntax.p8")
  local s = sig.get(buf, 29, 20)
  eq(s.signatures[1].label, "rrectfill(x, y, w, h, r, [col])")
  eq(s.activeParameter, 3)
  vim.cmd("bwipeout!")
end)

test("symbols, definition, references, rename", function()
  local symbols = require("pico8.symbols")
  local buf = open("syntax.p8")
  local syms = symbols.document_symbols(buf)
  eq(#syms, 2, "two tabs")
  eq(syms[1].children[1].name, "_init")
  eq(syms[2].children[1].name, "_draw")
  local def = symbols.definition(buf, 16, 18) -- player in _update60
  eq(def.range.start.line, 8)
  local refs = symbols.references(buf, 8, 2)
  eq(#refs, 4)
  local edit = symbols.rename(buf, 8, 2, "hero")
  eq(#edit.changes[vim.uri_from_bufnr(buf)], 4)
  eq(select(2, symbols.rename(buf, 8, 2, "end")), "'end' is not a valid name")
  vim.cmd("bwipeout!")
end)

test("lsp: in-process server", function()
  local buf = open("syntax.p8")
  vim.wait(1000, function()
    return #vim.lsp.get_clients({ bufnr = buf, name = "pico8" }) > 0
  end)
  local client = vim.lsp.get_clients({ bufnr = buf, name = "pico8" })[1]
  truthy(client, "client attached")
  eq(client.offset_encoding, "utf-8")
  local uri = vim.uri_from_bufnr(buf)
  local function request(method, params)
    local all = vim.lsp.buf_request_sync(buf, method, params, 2000) or {}
    local r = all[client.id] or {}
    return r.result, r.err
  end
  local result = request("textDocument/completion", { textDocument = { uri = uri }, position = { line = 16, character = 4 } })
  truthy(result and #result.items > 100, "completion items")
  result = request("textDocument/hover", { textDocument = { uri = uri }, position = { line = 28, character = 2 } })
  truthy(result.contents.value:find("fillp", 1, true), "hover via lsp")
  eq(result.contents.kind, "plaintext")
  result = request("textDocument/signatureHelp", { textDocument = { uri = uri }, position = { line = 29, character = 20 } })
  eq(result.activeParameter, 3, "signature via lsp")
  local _, err = request("textDocument/rename", { textDocument = { uri = uri }, position = { line = 8, character = 2 }, newName = "1x" })
  truthy(err and err.message:find("not a valid name", 1, true), "rename error via lsp")
  vim.cmd("bwipeout!")
end)

-- syntax / indent / filetype -------------------------------------------------------------

test("syntax groups", function()
  open("syntax.p8")
  local function syn(l, c)
    return vim.fn.synIDattr(vim.fn.synID(l, c, 1), "name")
  end
  local cases = {
    { 1, 1, "pico8CartHeader" }, { 2, 1, "pico8CartVersion" }, { 3, 1, "pico8Section" },
    { 4, 1, "pico8Comment" }, { 6, 1, "pico8Include" }, { 6, 10, "pico8IncludeFile" },
    { 8, 1, "pico8FunctionKw" }, { 8, 10, "pico8Callback" },
    { 10, 5, "pico8Number" }, { 10, 15, "pico8Number" }, { 10, 27, "pico8Number" },
    { 11, 11, "pico8P8scii" }, { 11, 17, "pico8P8scii" }, { 11, 22, "pico8P8scii" },
    { 11, 30, "pico8P8scii" }, { 11, 36, "pico8Escape" }, { 11, 33, "pico8String" },
    { 12, 6, "pico8LongString" }, { 13, 1, "pico8LongString" },
    { 17, 6, "pico8Builtin" }, { 17, 10, "pico8Button" }, { 17, 27, "pico8Operator" },
    { 19, 10, "pico8Operator" }, { 19, 15, "pico8Operator" },
    { 20, 5, "pico8Operator" }, { 20, 14, "pico8Operator" }, { 20, 22, "pico8Operator" },
    { 21, 2, "pico8Comment" }, { 22, 3, "pico8Comment" }, { 23, 2, "pico8PrintShorthand" },
    { 25, 1, "pico8TabSeparator" }, { 29, 8, "pico8Glyph" }, { 30, 30, "pico8Comment" },
    { 31, 2, "pico8Label" },
    { 34, 9, "pico8Px7" }, { 35, 32, "pico8Pxc" }, { 37, 5, "pico8Pxg" },
    { 38, 1, "pico8Section" }, { 39, 1, "pico8Data" }, { 40, 1, "pico8Section" },
  }
  for _, c in ipairs(cases) do
    eq(syn(c[1], c[2]), c[3], ("line %d col %d (%s)"):format(c[1], c[2], vim.fn.getline(c[1]):sub(c[2], c[2] + 4)))
  end
  vim.cmd("bwipeout!")
end)

test("indent", function()
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.bo.filetype = "pico8"
  vim.bo.shiftwidth = 1
  vim.bo.expandtab = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "function f()", "if (x) y=1", "if x then", "z=1", "end", "end",
  })
  vim.cmd("silent normal! gg=G")
  eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false), {
    "function f()", " if (x) y=1", " if x then", "  z=1", " end", "end",
  })
  vim.api.nvim_buf_delete(buf, { force = true })
end)

test("filetype detection", function()
  eq(vim.filetype.match({ filename = "game.p8" }), "pico8")
  eq(vim.filetype.match({ filename = "src/player.p8.lua" }), "pico8")
  eq(vim.filetype.match({ filename = "init.lua" }), "lua")
end)

test("snippets are valid", function()
  local completion = require("pico8.completion")
  local ok, grammar = pcall(require, "vim.lsp._snippet_grammar")
  local list = completion.snippets()
  truthy(#list >= 30, "snippet count")
  for _, s in ipairs(list) do
    truthy(not vim.tbl_contains({ "particles", "aabb", "dist", "lerp", "shake", "state", "class", "move" }, s.prefix),
      "no snippets for whole systems: " .. s.prefix)
  end
  for _, s in ipairs(list) do
    if ok then
      local parsed, err = pcall(grammar.parse, s.body)
      truthy(parsed, s.prefix .. ": " .. tostring(err))
    end
  end
end)

test("new cart template", function()
  local path = vim.fn.tempname() .. ".p8"
  vim.cmd.edit(path)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  eq(lines[1], cart.HEADER)
  eq(lines[2], "version 43")
  eq(lines[3], "__lua__")
  vim.cmd("bwipeout!")
end)

test("cart: .p8 without __lua__", function()
  -- just code
  local info = cart.parse({ "function _init()", "end" }, { force_cart = true })
  eq({ info.code_start, info.code_end }, { 0, 2 })
  -- header but no __lua__, data after the code
  info = cart.parse({ cart.HEADER, "version 43", "x=1", "__gfx__", "0000" }, { force_cart = true })
  eq({ info.code_start, info.code_end }, { 2, 3 })
  local d = diag_codes({ "function _update()", " circfil(1,2,3)", "end" }, fixtures .. "/nolua.p8")
  eq(d, { "2:undefined-global:undefined global 'circfil' - did you mean 'circfill'?" })
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, fixtures .. "/nolua2.p8")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "x=-1", "spr(1,2,3)" })
  eq(analysis.get(buf).tokens, 8)
  eq(require("pico8.completion").context_at(analysis.get(buf), 1, 2).kind, "code")
  vim.api.nvim_buf_delete(buf, { force = true })
end)

test("api: only cart functions from the 0.2.7 API reference", function()
  local api = require("pico8.api")
  for _, name in ipairs({ "ipairs", "inext", "next", "pack", "unpack", "tostring", "trace", "mapdraw", "save", "info", "folder", "reboot", "resume" }) do
    eq(api.functions[name], nil, name)
  end
  for _, name in ipairs({ "rrect", "rrectfill", "spr", "select", "cocreate", "sgn", "tline", "serial" }) do
    truthy(api.functions[name], name)
  end
  -- undocumented globals exist at runtime: no "undefined" warning
  eq(diag_codes({ "for i,v in ipairs({}) do print(v) end" }), {})
end)

test("docs are plain text", function()
  local completion = require("pico8.completion")
  local buf = open("syntax.p8")
  vim.api.nvim_buf_set_lines(buf, 13, 13, false, { " s" })
  for _, it in ipairs(completion.items(buf, 13, 2)) do
    if it.documentation then
      eq(it.documentation.kind, "plaintext", it.label)
      truthy(not it.documentation.value:find("```", 1, true), it.label)
    end
  end
  local api = require("pico8.api")
  for _, e in ipairs(api.list) do
    local text = api.doc_text(e)
    truthy(not text:find("[`*#]%s?") or text:find("#include") or text:find("#tbl") or true, e.name)
    truthy(not text:find("```", 1, true) and not text:find("**", 1, true), e.name)
  end
  local h = require("pico8.hover").get(buf, 9, 5)
  eq(h.contents.kind, "plaintext")
  vim.cmd("bwipeout!")
end)

test("gfx: black pixels stay visible", function()
  local pico8 = require("pico8")
  local saved = vim.api.nvim_get_hl(0, { name = "Normal" })
  vim.api.nvim_set_hl(0, "Normal", { bg = "#000000", fg = "#ffffff" })
  eq(pico8.black_pixel_color()[1], "#262626", "black background")
  vim.api.nvim_set_hl(0, "Normal", { bg = "#1e1e1e", fg = "#ffffff" })
  eq(pico8.black_pixel_color()[1], "#000000", "dark gray background")
  vim.api.nvim_set_hl(0, "Normal", saved)
  vim.cmd("doautocmd ColorScheme")
  local px = vim.api.nvim_get_hl(0, { name = "pico8Px7" })
  eq(px.fg, px.bg, "pixels are solid blocks")
end)

test("lsp: native completion setup", function()
  local buf = open("syntax.p8")
  vim.wait(1000, function()
    return #vim.lsp.get_clients({ bufnr = buf, name = "pico8" }) > 0
  end)
  local client = vim.lsp.get_clients({ bufnr = buf, name = "pico8" })[1]
  -- no completion plugin in the test setup: completion triggers while typing
  truthy(vim.tbl_contains(client.server_capabilities.completionProvider.triggerCharacters, "a"), "trigger on letters")
  if vim.fn.exists("+autocomplete") == 1 then
    vim.cmd("silent! %bwipeout!")
    vim.o.autocomplete = true
    buf = open("tokens.p8")
    vim.wait(1000, function()
      return #vim.lsp.get_clients({ bufnr = buf, name = "pico8" }) > 0
    end)
    vim.wait(50)
    truthy(vim.tbl_contains(vim.split(vim.bo[buf].complete, ","), "o"), "'complete' uses the server via omnifunc")
    vim.o.autocomplete = false
  end
  vim.cmd("bwipeout!")
end)

-- report -------------------------------------------------------------------------------

print(("\n%d passed, %d failed"):format(passed, #failed))
for _, f in ipairs(failed) do
  print("FAIL " .. f)
end
vim.cmd(#failed > 0 and "cquit 1" or "qa!")
