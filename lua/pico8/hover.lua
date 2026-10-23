-- Hover documentation: API functions, callbacks, glyphs, user functions
-- (with their token cost), locals, numbers (fixed point / hex / memory
-- addresses), stat() indices and PICO-8 operators.
-- All text is plain text (no markdown).

local analysis = require("pico8.analysis")
local api = require("pico8.api")
local cart = require("pico8.cart")
local lexer = require("pico8.lexer")

local M = {}

local OPERATORS = {
  ["\\"] = "integer division: a\\b == flr(a/b)",
  ["\\="] = "integer division assignment: a\\=b",
  ["^^"] = "bitwise xor (bxor)",
  ["^^="] = "bitwise xor assignment",
  ["&"] = "bitwise and (band)",
  ["|"] = "bitwise or (bor)",
  ["~"] = "bitwise not (bnot) / xor",
  ["<<"] = "shift left (shl)",
  [">>"] = "arithmetic shift right (shr)",
  [">>>"] = "logical shift right (lshr)",
  ["<<>"] = "rotate left (rotl)",
  [">><"] = "rotate right (rotr)",
  ["@"] = "peek operator: @addr == peek(addr)",
  ["$"] = "peek4 operator: $addr == peek4(addr)",
  ["!="] = "not equal (same as ~=)",
  ["?"] = "print shorthand: ?\"hi\",x,y,col == print(\"hi\",x,y,col)",
  ["..="] = "concatenation assignment: s..=\"x\"",
}

--- Parse a PICO-8 number literal into its 16.16 fixed point value.
---@return number value, integer raw 32-bit pattern
function M.parse_number(text)
  local s = text:lower()
  local base, digits
  if s:sub(1, 2) == "0x" then
    base, digits = 16, s:sub(3)
  elseif s:sub(1, 2) == "0b" then
    base, digits = 2, s:sub(3)
  else
    base, digits = 10, s
  end
  local ip, fp = digits:match("^([^.]*)%.?(.*)$")
  local value = 0
  if base == 10 then
    value = tonumber(digits) or tonumber(digits .. "0") or 0
  else
    for c in ip:gmatch(".") do
      value = value * base + (tonumber(c, base) or 0)
    end
    local scale = 1 / base
    for c in fp:gmatch(".") do
      value = value + (tonumber(c, base) or 0) * scale
      scale = scale / base
    end
  end
  -- 16.16 fixed point, wrapping like PICO-8
  local raw = math.floor(value * 65536 + 0.5) % 0x100000000
  local signed = raw >= 0x80000000 and raw - 0x100000000 or raw
  return signed / 65536, raw
end

local function fmt_dec(v)
  if v == math.floor(v) then
    return tostring(math.floor(v))
  end
  return (("%.5f"):format(v):gsub("0+$", ""))
end

local function region_of(addr)
  local best, best_addr
  for a, doc in pairs(api.MEMORY) do
    if a <= addr and (not best_addr or a > best_addr) and doc:find("%(") then
      best, best_addr = doc, a
    end
  end
  return best, best_addr
end

function M.number_text(text)
  local v, raw = M.parse_number(text)
  local int = math.floor(raw / 65536)
  local frac = raw % 65536
  local lines = {
    ("%s = %s"):format(text, fmt_dec(v)),
    ("hex 0x%04x.%04x"):format(int, frac),
  }
  if frac == 0 and int < 0x10000 then
    local bits = {}
    for b = 15, 0, -1 do
      bits[#bits + 1] = math.floor(int / 2 ^ b) % 2
    end
    lines[#lines + 1] = "bin 0b" .. table.concat(bits)
  end
  if frac == 0 and v >= 0 then
    local addr = math.floor(v)
    local doc = api.MEMORY[addr]
    if doc then
      lines[#lines + 1] = ""
      lines[#lines + 1] = ("memory 0x%04x: %s"):format(addr, doc)
    elseif addr >= 0x5f00 and addr < 0x10000 then
      local r, ra = region_of(addr)
      if r then
        lines[#lines + 1] = ""
        lines[#lines + 1] = ("memory 0x%04x (0x%04x + %d): %s"):format(addr, ra, addr - ra, r)
      end
    end
  end
  return table.concat(lines, "\n")
end

--- Comment lines directly above line l (doc comments).
local function doc_comment(lines, l)
  local out = {}
  local i = l
  while i >= 1 do
    local text = lines[i]
    local c = text and (text:match("^%s*%-%-+%s?(.*)$") or text:match("^%s*//%s?(.*)$"))
    if not c or text:match("^%-%->8") then
      break
    end
    table.insert(out, 1, c)
    i = i - 1
  end
  return #out > 0 and table.concat(out, "\n") or nil
end

local function function_text(fn, lines, where)
  local params = table.concat(fn.params, ", ")
  if fn.vararg then
    params = params == "" and "..." or (params .. ", ...")
  end
  local head = fn.kind == "local" and "local function " or "function "
  local out = { head .. (fn.name or "?") .. "(" .. params .. ")" }
  local doc = lines and doc_comment(lines, fn.line)
  if doc then
    out[#out + 1] = ""
    out[#out + 1] = doc
  end
  out[#out + 1] = ""
  local meta = {}
  if fn.tokens then
    meta[#meta + 1] = ("%d tokens"):format(fn.tokens)
  end
  meta[#meta + 1] = ("line %d%s"):format(fn.line + 1, where and (" of " .. where) or "")
  out[#out + 1] = table.concat(meta, ", ")
  return table.concat(out, "\n")
end

--- Hover (LSP Hover with plain text contents) for (line, col), or nil.
function M.get(bufnr, line, col)
  local res = analysis.get(bufnr)
  local toks = res.lex.tokens
  local idx = lexer.token_at(toks, line, col) or lexer.token_at(toks, line, col, true)
  if not idx then
    return nil
  end
  local t = toks[idx]
  local range = {
    start = { line = t.line, character = t.col },
    ["end"] = { line = t.eline, character = t.ecol },
  }
  local function ret(value)
    return { contents = { kind = "plaintext", value = value }, range = range }
  end
  local parse = res.parse

  if t.type == "number" then
    local p1, p2 = toks[idx - 1], toks[idx - 2]
    if p1 and p1.value == "(" and p2 and p2.type == "name" and p2.value == "stat" and not parse.refs[p2] then
      local v = M.parse_number(t.value)
      local doc = api.STAT[v]
      if doc then
        return ret(("stat(%s): %s"):format(fmt_dec(v), doc))
      end
    end
    return ret(M.number_text(t.value))
  end

  if t.type == "op" then
    local doc = OPERATORS[t.value]
    if t.value == "%" then
      local prev = toks[idx - 1]
      local unary = not prev or not (prev.type == "name" or prev.type == "number" or prev.type == "string"
        or (prev.type == "op" and (prev.value == ")" or prev.value == "]" or prev.value == "}")))
      doc = unary and "peek2 operator: %addr == peek2(addr)" or "modulo"
    end
    if doc then
      return ret(("%s  %s"):format(t.value, doc))
    end
    return nil
  end

  if t.type == "keyword" and t.value == "function" then
    for _, fn in ipairs(parse.functions) do
      if fn.s == idx then
        return ret(function_text(fn, res.lines))
      end
    end
    return nil
  end

  if t.type ~= "name" then
    return nil
  end
  local name = t.value

  -- local variables
  local v = parse.refs[t]
  if v then
    if v.fn then
      return ret(function_text(v.fn, res.lines))
    end
    local what = ({ param = "parameter", ["for"] = "loop variable", self = "self", ["function"] = "local function" })[v.kind]
      or "local variable"
    local s = ("local %s\n\n%s"):format(name, what)
    if not v.tok.synthetic then
      s = s .. (", declared on line %d"):format(v.tok.line + 1)
    end
    return ret(s)
  end

  -- member functions: obj.fn / obj:fn
  local prev = toks[idx - 1]
  if prev and prev.type == "op" and (prev.value == "." or prev.value == ":") then
    for _, fn in ipairs(parse.functions) do
      if fn.name and (fn.name:match("[.:]" .. vim.pesc(name) .. "$")) then
        return ret(function_text(fn, res.lines))
      end
    end
    return nil
  end

  local g = api.glyphs[name]
  if g then
    local s = ("%s  %s"):format(name, g.doc)
    if g.value then
      s = s .. ("\n\n%s == %d"):format(name, g.value)
    end
    return ret(s)
  end

  local ctx = analysis.context(bufnr)
  local own = parse.globals[name]
  if own and own.kind == "function" and own.fn then
    local s = function_text(own.fn, res.lines)
    if api.CALLBACKS[name] then
      s = s .. "\n\n" .. api.CALLBACKS[name]
    elseif api.functions[name] then
      s = s .. "\n\nOverrides the built-in " .. name .. "()."
    end
    return ret(s)
  end
  local other = ctx.globals[name]
  if other and other.kind == "function" and other.fn then
    return ret(function_text(other.fn, other.path and cart.file_lines(other.path), vim.fs.basename(other.path or "")))
  end

  if api.CALLBACKS[name] then
    return ret(("function %s()\n\n%s"):format(name, api.CALLBACKS[name]))
  end
  local e = api.functions[name]
  if e and not own and not other then
    return ret(api.doc_text(e))
  end

  local gv = own or other
  if gv then
    local s = ("global %s"):format(name)
    if gv.tok then
      s = s .. ("\n\nfirst assigned on line %d"):format(gv.tok.line + 1)
      if other and other.path then
        s = s .. " of " .. vim.fs.basename(other.path)
      end
    end
    return ret(s)
  end
  return nil
end

return M
