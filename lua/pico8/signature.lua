-- Signature help for API and user functions.

local analysis = require("pico8.analysis")
local api = require("pico8.api")
local lexer = require("pico8.lexer")

local M = {}

local STOP = {
  ["then"] = true, ["do"] = true, ["end"] = true, ["else"] = true, ["elseif"] = true,
  ["local"] = true, ["return"] = true, ["if"] = true, ["while"] = true, ["for"] = true,
  ["repeat"] = true, ["until"] = true, ["function"] = true,
}

--- Find the call around (line, col): returns the token index of its "("
--- and the number of commas before the cursor.
function M.enclosing_call(toks, line, col)
  local i = lexer.token_before(toks, line, col)
  local depth, commas = 0, 0
  while i and i >= 1 do
    local t = toks[i]
    if t.type == "op" then
      local v = t.value
      if v == ")" or v == "]" or v == "}" then
        depth = depth + 1
      elseif v == "(" or v == "[" or v == "{" then
        if depth == 0 then
          if v == "(" then
            return i, commas
          end
          return nil
        end
        depth = depth - 1
      elseif v == "," and depth == 0 then
        commas = commas + 1
      end
    elseif t.type == "keyword" and STOP[t.value] and depth == 0 then
      return nil
    end
    i = i - 1
  end
end

local function param_offsets(label, names)
  local out = {}
  local pos = (label:find("(", 1, true) or 0) + 1
  for _, n in ipairs(names) do
    local s, e = label:find(n, pos, true)
    if s then
      out[#out + 1] = { label = { s - 1, e } }
      pos = e + 1
    else
      out[#out + 1] = { label = n }
    end
  end
  return out
end

local function user_signature(fn)
  local names = vim.deepcopy(fn.params)
  if fn.vararg then
    names[#names + 1] = "..."
  end
  local label = (fn.name or "function") .. "(" .. table.concat(names, ", ") .. ")"
  return { label = label, parameters = param_offsets(label, names), vararg = fn.vararg }
end

--- LSP SignatureHelp for (line, col), or nil.
function M.get(bufnr, line, col)
  local res = analysis.get(bufnr)
  local toks = res.lex.tokens
  local open, commas = M.enclosing_call(toks, line, col)
  if not open then
    return nil
  end
  local callee = toks[open - 1]
  if not callee or callee.type ~= "name" then
    return nil
  end
  local before = toks[open - 2]
  if before and before.type == "keyword" and before.value == "function" then
    return nil -- a definition, not a call
  end
  local name = callee.value
  local member = before and before.type == "op" and (before.value == "." or before.value == ":")

  local parse = res.parse
  local sigs = {}
  if not member and not parse.refs[callee] then
    local own = parse.globals[name]
    local ctx = (not own) and analysis.context(bufnr) or nil
    local other = ctx and ctx.globals[name]
    local fn = (own and own.fn) or (other and other.fn)
    if fn then
      sigs[1] = user_signature(fn)
    elseif api.functions[name] then
      local e = api.functions[name]
      for _, s in ipairs(e.signatures) do
        local names = {}
        for _, p in ipairs(s.params) do
          names[#names + 1] = p.name
        end
        local params = param_offsets(s.label, names)
        for k, p in ipairs(s.params) do
          local doc = e.param_docs[p.name]
          if doc then
            params[k].documentation = doc
          end
        end
        sigs[#sigs + 1] = {
          label = s.label,
          parameters = params,
          documentation = { kind = "markdown", value = e.description },
          vararg = s.vararg,
        }
      end
    end
  elseif parse.refs[callee] and parse.refs[callee].fn then
    sigs[1] = user_signature(parse.refs[callee].fn)
  elseif member then
    for _, fn in ipairs(parse.functions) do
      if fn.name and fn.name:match("[.:]" .. vim.pesc(name) .. "$") then
        sigs[1] = user_signature(fn)
        -- obj:m() passes self implicitly; obj.m() on a method needs it explicitly
        if fn.method and before.value == "." then
          table.insert(fn.params, 1, "self")
          sigs[1] = user_signature(fn)
          table.remove(fn.params, 1)
        end
        break
      end
    end
  end
  if #sigs == 0 then
    return nil
  end

  local active = 1
  for k, s in ipairs(sigs) do
    if #s.parameters > commas or s.vararg then
      active = k
      break
    end
  end
  for _, s in ipairs(sigs) do
    s.activeParameter = math.min(commas, math.max(#s.parameters - 1, 0))
    s.vararg = nil
  end
  return {
    signatures = sigs,
    activeSignature = active - 1,
    activeParameter = sigs[active].activeParameter,
  }
end

return M
