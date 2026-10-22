-- Tokenizer for PICO-8 Lua (Lua 5.2 plus the PICO-8 extensions).
--
-- Mirrors the tokenizer PICO-8 uses for its token counter: `//` comments,
-- `!=`, `\`, `^^`, `>>>`, `<<>`, `>><`, compound assignments (`+=`, `..=`,
-- `>>>=`, ...), the peek operators `@ % $`, the `?` print shorthand,
-- binary/hex numbers with fractional parts and `#include` directives.
-- Bytes >= 0x80 (P8SCII glyphs, stored as UTF-8 in .p8 files) are
-- identifier characters, so `⬅️` is lexed as a single name.
--
-- Positions are 0-based: `line` is a buffer line, `col` a byte column.
-- `eline`/`ecol` give the (exclusive) end of the token.

local M = {}

local byte, sub, find = string.byte, string.sub, string.find

M.keywords = {
  ["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true,
  ["elseif"] = true, ["end"] = true, ["false"] = true, ["for"] = true,
  ["function"] = true, ["goto"] = true, ["if"] = true, ["in"] = true,
  ["local"] = true, ["nil"] = true, ["not"] = true, ["or"] = true,
  ["repeat"] = true, ["return"] = true, ["then"] = true, ["true"] = true,
  ["until"] = true, ["while"] = true,
}

local IDENT = {}
for b = 0, 255 do
  IDENT[b] = (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122)
    or b == 95 or b == 0x1e or b == 0x1f or b >= 0x80
end
M.IDENT = IDENT

local IDENT_PATTERN = "^[%w_\30\31\128-\255]*"
M.IDENT_PATTERN = IDENT_PATTERN

local WHITE = { [32] = true, [9] = true, [13] = true, [11] = true, [12] = true }

-- characters that start punctuation
local PUNCT = {}
for c in ("+-*/\\%&|^<>=~#()[]{};,?@$.:"):gmatch(".") do
  PUNCT[byte(c)] = true
end
-- can be doubled: .. :: ^^ << >>  (// is a comment)
local DOUBLE = {}
for c in (".:^<>"):gmatch(".") do
  DOUBLE[byte(c)] = true
end
-- may be followed by '=' to form a compound operator / comparison
local EQ_SUFFIX = {}
for c in ("+-*/\\%&|^<>=~"):gmatch(".") do
  EQ_SUFFIX[byte(c)] = true
end

local B_DOT, B_LT, B_GT, B_EQ = byte("."), byte("<"), byte(">"), byte("=")

--- Tokenize `text`.
---@param text string
---@param opts? { line?: integer }  line: buffer line of the first line of text
---@return table result { tokens, comments, errors, directives }
function M.lex(text, opts)
  opts = opts or {}
  local tokens, comments, errors, directives = {}, {}, {}, {}
  local n = #text
  local i = 1
  local line = opts.line or 0
  local lstart = 1 -- index of the first byte of the current line
  local bol = true -- only whitespace seen so far on this line

  -- Computes the position of [s, e] (s must be on the current line) and
  -- advances the line counter over newlines inside the span.
  local function span(s, e)
    local sl, sc = line, s - lstart
    local p = s
    while true do
      local nl = find(text, "\n", p, true)
      if not nl or nl > e then
        break
      end
      line = line + 1
      lstart = nl + 1
      p = nl + 1
    end
    return sl, sc, line, e - lstart + 1
  end

  local function add(ty, s, e)
    local sl, sc, el, ec = span(s, e)
    local tok = {
      i = #tokens + 1,
      type = ty,
      value = sub(text, s, e),
      s = s,
      e = e,
      line = sl,
      col = sc,
      eline = el,
      ecol = ec,
    }
    if ty == "name" and M.keywords[tok.value] then
      tok.type = "keyword"
    end
    tokens[#tokens + 1] = tok
    return tok
  end

  local function add_error(msg, s, e)
    local sl, sc = line, s - lstart
    local el, ec = sl, sc + math.max(1, (e or s) - s + 1)
    -- clamp multi-line error spans to the first line
    local nl = find(text, "\n", s, true)
    if nl and nl <= (e or s) then
      ec = nl - lstart
    end
    errors[#errors + 1] = { msg = msg, line = sl, col = sc, eline = el, ecol = ec }
  end

  local function add_comment(s, e, long)
    local sl, sc, el, ec = span(s, e)
    comments[#comments + 1] = {
      s = s,
      e = e,
      line = sl,
      col = sc,
      eline = el,
      ecol = ec,
      long = long,
      text = sub(text, s, e),
    }
  end

  -- `[[`, `[=[`, ... at position p; returns the closing index or nil
  local function long_bracket(p)
    local _, e, eq = find(text, "^%[(=*)%[", p)
    if not e then
      return nil
    end
    local close = "]" .. eq .. "]"
    local cs, ce = find(text, close, e + 1, true)
    if not cs then
      return false
    end
    return ce
  end

  while i <= n do
    local b = byte(text, i)
    if b == 10 then
      line = line + 1
      i = i + 1
      lstart = i
      bol = true
    elseif WHITE[b] then
      i = i + 1
    elseif b == 35 and bol and find(text, "^#include[ \t]+[^%s]", i) then
      -- `#include file` at the start of a line (any other '#' is the length operator)
      local e = find(text, "\n", i, true)
      e = (e or (n + 1)) - 1
      local dtext = sub(text, i, e)
      directives[#directives + 1] = {
        text = dtext,
        include = dtext:match("^#include%s+(.-)%s*$"),
        line = line,
        col = i - lstart,
        ecol = e - lstart + 1,
      }
      i = e + 1
    else
      bol = false
      local b2 = byte(text, i + 1)
      if (b >= 48 and b <= 57) or (b == 46 and b2 and b2 >= 48 and b2 <= 57) then
        -- number
        local s = i
        local pattern
        if b == 48 and (b2 == 120 or b2 == 88) then
          i = i + 2
          pattern = "^[%x%.]*"
        elseif b == 48 and (b2 == 98 or b2 == 66) then
          i = i + 2
          pattern = "^[01%.]*"
        else
          pattern = "^[%d%.]*"
        end
        -- Like PICO-8, a name may directly follow a number: `x=0.y=1` is
        -- `x=0.` followed by `y=1`.
        local ds = i
        local _, e = find(text, pattern, i)
        i = e + 1
        local digits = sub(text, ds, e)
        if digits == "" or digits == "." or select(2, digits:gsub("%.", "")) > 1 then
          add_error(("malformed number near '%s'"):format(sub(text, s, e)), s, e)
        end
        add("number", s, e)
      elseif IDENT[b] then
        local _, e = find(text, IDENT_PATTERN, i + 1)
        add("name", i, e)
        i = e + 1
      elseif b == 34 or b == 39 then
        -- quoted string
        local s = i
        i = i + 1
        local closed = false
        while i <= n do
          local c = byte(text, i)
          if c == 10 then
            break
          elseif c == 92 then -- backslash
            local c2 = byte(text, i + 1)
            if c2 == 122 then -- \z skips following whitespace (incl. newlines)
              local _, e = find(text, "^%s*", i + 2)
              i = e + 1
            else
              i = i + 2
            end
          elseif c == b then
            i = i + 1
            closed = true
            break
          else
            i = i + 1
          end
        end
        if not closed then
          local e = math.min(i, n)
          if byte(text, e) == 10 then
            e = e - 1
          end
          add_error(("unfinished string near '%s'"):format(sub(text, s, e)), s, e)
          i = e + 1
          add("string", s, e)
        else
          add("string", s, i - 1)
        end
      elseif b == 91 and (b2 == 91 or b2 == 61) and long_bracket(i) ~= nil then
        -- long string [[...]] / [==[...]==]
        local ce = long_bracket(i)
        if ce then
          add("string", i, ce)
          i = ce + 1
        else
          add_error("unfinished long string", i, i + 1)
          add("string", i, n)
          i = n + 1
        end
      elseif b == 45 and b2 == 45 then
        -- comment
        local ce = nil
        if byte(text, i + 2) == 91 then
          ce = long_bracket(i + 2) -- nil: not a long bracket, false: unterminated
        end
        if ce then
          add_comment(i, ce, true)
          i = ce + 1
        elseif ce == false then
          add_error("unfinished long comment", i, i + 3)
          add_comment(i, n, true)
          i = n + 1
        else
          local e = find(text, "\n", i, true)
          e = (e or (n + 1)) - 1
          add_comment(i, e, false)
          i = e + 1
        end
      elseif b == 47 and b2 == 47 then
        -- C-style line comment (PICO-8)
        local e = find(text, "\n", i, true)
        e = (e or (n + 1)) - 1
        add_comment(i, e, false)
        i = e + 1
      elseif PUNCT[b] then
        -- same rules as the PICO-8 tokenizer
        local s = i
        i = i + 1
        if DOUBLE[b] and byte(text, i) == b then
          i = i + 1
          if (b == B_DOT or b == B_GT) and byte(text, i) == b then
            i = i + 1 -- ... or >>>
            if b == B_GT and byte(text, i) == B_EQ then
              i = i + 1 -- >>>=
            end
          elseif (b == B_LT and byte(text, i) == B_GT) or (b == B_GT and byte(text, i) == B_LT) then
            i = i + 1 -- <<> or >><
            if byte(text, i) == B_EQ then
              i = i + 1
            end
          elseif b ~= 58 and byte(text, i) == B_EQ then -- not "::"
            i = i + 1 -- ..= ^^= <<= >>=
          end
        elseif EQ_SUFFIX[b] and byte(text, i) == B_EQ then
          i = i + 1
        end
        add("op", s, i - 1)
      elseif b == 33 and b2 == 61 then
        add("op", i, i + 1) -- !=
        i = i + 2
      else
        add_error(("unexpected symbol near '%s'"):format(sub(text, i, i)), i, i)
        i = i + 1
      end
    end
  end

  local last_col = n + 1 - lstart
  tokens[#tokens + 1] = {
    i = #tokens + 1,
    type = "eof",
    value = "<eof>",
    s = n + 1,
    e = n,
    line = line,
    col = last_col,
    eline = line,
    ecol = last_col,
  }

  return { tokens = tokens, comments = comments, errors = errors, directives = directives }
end

--- Returns the index of the token covering (line, col), or nil.
---@param tokens table
---@param line integer
---@param col integer
---@param inclusive_end? boolean also match when col == ecol (cursor right after a token)
function M.token_at(tokens, line, col, inclusive_end)
  local lo, hi = 1, #tokens - 1 -- skip eof
  while lo <= hi do
    local mid = math.floor((lo + hi) / 2)
    local t = tokens[mid]
    if t.line > line or (t.line == line and t.col > col) then
      hi = mid - 1
    elseif t.eline < line or (t.eline == line and (t.ecol < col or (t.ecol == col and not inclusive_end))) then
      lo = mid + 1
    else
      return mid
    end
  end
  return nil
end

--- Index of the last token that starts strictly before (line, col).
function M.token_before(tokens, line, col)
  local lo, hi, best = 1, #tokens - 1, nil
  while lo <= hi do
    local mid = math.floor((lo + hi) / 2)
    local t = tokens[mid]
    if t.line < line or (t.line == line and t.col < col) then
      best = mid
      lo = mid + 1
    else
      hi = mid - 1
    end
  end
  return best
end

return M
