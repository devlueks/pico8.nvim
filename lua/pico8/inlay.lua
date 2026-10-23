-- Inlay hints: parameter names in calls of built-in functions,
--   rectfill(x0: 12, y0: 20, x1: 115, y1: 105, col: 0)
-- optionally also in calls of your own functions.
--
-- Works on the token stream, so hints stay in place while a line is being
-- typed and the file has a syntax error.

local analysis = require("pico8.analysis")
local api = require("pico8.api")
local config = require("pico8.config")

local M = {}

local PARAMETER = 2 -- InlayHintKind.Parameter

-- keywords that cannot appear inside an argument list (an unfinished call)
local STOP = {
  ["then"] = true, ["do"] = true, ["end"] = true, ["else"] = true, ["elseif"] = true,
  ["local"] = true, ["return"] = true, ["if"] = true, ["while"] = true, ["for"] = true,
  ["repeat"] = true, ["until"] = true, ["goto"] = true,
}

local function is_op(t, v)
  return t and t.type == "op" and t.value == v
end

--- Start tokens of the arguments of the call whose "(" is toks[open].
--- Stops at an anonymous function: its body may contain commas.
local function arguments(toks, open)
  local args = {}
  local depth = 0
  local i = open + 1
  local expect_arg = true
  local closed = false
  while toks[i] and toks[i].type ~= "eof" do
    local t = toks[i]
    if t.type == "op" then
      local v = t.value
      if v == "(" or v == "[" or v == "{" then
        if expect_arg and depth == 0 then
          args[#args + 1] = i
          expect_arg = false
        end
        depth = depth + 1
      elseif v == ")" or v == "]" or v == "}" then
        if depth == 0 then
          closed = v == ")"
          break
        end
        depth = depth - 1
      elseif v == "," and depth == 0 then
        expect_arg = true
      elseif expect_arg and depth == 0 then
        args[#args + 1] = i
        expect_arg = false
      end
    elseif t.type == "keyword" and t.value == "function" then
      if expect_arg and depth == 0 then
        args[#args + 1] = i
      end
      closed = true
      break
    elseif t.type == "keyword" and STOP[t.value] then
      break
    else
      if expect_arg and depth == 0 then
        args[#args + 1] = i
        expect_arg = false
      end
    end
    i = i + 1
  end
  if not closed then
    -- a call that is still being typed: the next lines are other statements
    local line = toks[open].line
    while #args > 0 and toks[args[#args]].line > line do
      args[#args] = nil
    end
  end
  return args
end

--- Does the argument starting at toks[i] already say what it is?
--- (x for param x, p.x / self.x, or a button glyph like ⬅️)
local function self_describing(toks, i, name)
  local g = toks[i].type == "name" and api.glyphs[toks[i].value]
  if g and g.value then
    return true
  end
  local last
  while toks[i] and toks[i].type == "name" do
    last = toks[i].value
    if not is_op(toks[i + 1], ".") then
      break
    end
    i = i + 2
  end
  local after = toks[i + 1]
  return last == name and (is_op(after, ",") or is_op(after, ")"))
end

--- Pick the signature of a built-in function that matches the call.
local function pick_signature(entry, toks, args)
  local n = #args
  local first_is_table = n > 0 and is_op(toks[args[1]], "{")
  local fallback
  for _, s in ipairs(entry.signatures) do
    local required = 0
    for _, p in ipairs(s.params) do
      if not p.optional then
        required = required + 1
      end
    end
    if n >= required and (n <= #s.params or s.vararg) then
      local takes_table = s.params[1] and s.params[1].name == "tbl"
      if takes_table == first_is_table then
        return s
      end
      fallback = fallback or s
    end
  end
  return fallback or entry.signatures[1]
end

local function names_of(params)
  local out = {}
  for _, p in ipairs(params) do
    out[#out + 1] = p.name or p
  end
  return out
end

--- InlayHint[] for the lines first..last (0-based, inclusive) of a buffer.
function M.hints(bufnr, first, last)
  local opts = config.get().inlay_hints
  if not opts.enabled then
    return {}
  end
  local res = analysis.get(bufnr)
  local toks = res.lex.tokens
  local parse = res.parse
  local ctx
  local out = {}

  for i = 1, #toks - 1 do
    local t = toks[i]
    if t.type == "name" and t.line >= (first or 0) and t.line <= (last or math.huge) and is_op(toks[i + 1], "(") then
      local prev = toks[i - 1]
      local member = prev and prev.type == "op" and (prev.value == "." or prev.value == ":")
      local definition = prev and prev.type == "keyword" and prev.value == "function"
      if not member and not definition then
        local params
        local var = parse.refs[t]
        local own = parse.globals[t.value]
        if var then
          if opts.user_functions and var.fn then
            params = var.fn.params
          end
        elseif own and own.kind == "function" then
          if opts.user_functions and own.fn then
            params = own.fn.params
          end
        else
          ctx = ctx or analysis.context(bufnr)
          local other = ctx.globals[t.value]
          if other and other.kind == "function" then
            if opts.user_functions and other.fn then
              params = other.fn.params
            end
          elseif api.functions[t.value] then
            local args = arguments(toks, i + 1)
            local sig = pick_signature(api.functions[t.value], toks, args)
            params = names_of(sig.params)
            -- flr(x), mid(x, y, z), band(x, y): one-letter names say nothing
            local informative = false
            for _, name in ipairs(params) do
              informative = informative or #name > 1
            end
            if not informative then
              params = nil
            end
          end
        end
        if params then
          local args = arguments(toks, i + 1)
          for k, a in ipairs(args) do
            local name = params[k]
            if not name or name == "..." then
              break
            end
            if not self_describing(toks, a, name) then
              local at = toks[a]
              out[#out + 1] = {
                position = { line = at.line, character = at.col },
                label = name .. ":",
                kind = PARAMETER,
                paddingRight = true,
              }
            end
          end
        end
      end
    end
  end
  return out
end

return M
