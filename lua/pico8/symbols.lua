-- Navigation: document symbols, go to definition, references, document
-- highlights and rename.

local analysis = require("pico8.analysis")
local api = require("pico8.api")
local lexer = require("pico8.lexer")

local M = {}

local SymbolKind = { Module = 2, Namespace = 3, Method = 6, Field = 8, Function = 12, Variable = 13 }

local function tok_range(t)
  return {
    start = { line = t.line, character = t.col },
    ["end"] = { line = t.eline, character = t.ecol },
  }
end

local function uri_of(path)
  return vim.uri_from_fname(path)
end

local function buf_uri(bufnr)
  return vim.uri_from_bufnr(bufnr)
end

--- Hierarchical DocumentSymbol[] (tabs > functions > nested functions).
function M.document_symbols(bufnr)
  local res = analysis.get(bufnr)
  local toks = res.lex.tokens
  local fns = {}
  for _, fn in ipairs(res.parse.functions) do
    if fn.name and fn.s and fn.e then
      fns[#fns + 1] = fn
    end
  end
  table.sort(fns, function(a, b)
    return a.s < b.s
  end)

  local roots, stack = {}, {}
  for _, fn in ipairs(fns) do
    local sym = {
      name = fn.name,
      detail = ("(%s)%s"):format(table.concat(fn.params, ", "), fn.tokens and (" · " .. fn.tokens .. " tokens") or ""),
      kind = fn.method and SymbolKind.Method or SymbolKind.Function,
      range = {
        start = { line = toks[fn.s].line, character = toks[fn.s].col },
        ["end"] = { line = toks[fn.e].eline, character = toks[fn.e].ecol },
      },
      selectionRange = tok_range(fn.tok),
      children = {},
      _s = fn.s,
      _e = fn.e,
    }
    while #stack > 0 and stack[#stack]._e < fn.s do
      table.remove(stack)
    end
    if #stack > 0 then
      table.insert(stack[#stack].children, sym)
    else
      roots[#roots + 1] = sym
    end
    stack[#stack + 1] = sym
  end

  local function clean(list)
    for _, s in ipairs(list) do
      s._s, s._e = nil, nil
      clean(s.children)
    end
    return list
  end
  clean(roots)

  local tabs = res.cart.tabs
  if #tabs <= 1 then
    return roots
  end
  local out = {}
  for _, tab in ipairs(tabs) do
    local first = tab.sep or tab.start
    local last_line = math.max(tab.stop - 1, first)
    local label = res.lines[tab.start + 1] or ""
    local title = label:match("^%-%-%s*(.-)%s*$")
    local sym = {
      name = ("tab %d%s"):format(tab.index, title and title ~= "" and (": " .. title) or ""),
      detail = (res.tab_tokens[tab.index] or 0) .. " tokens",
      kind = SymbolKind.Namespace,
      range = {
        start = { line = first, character = 0 },
        ["end"] = { line = last_line, character = #(res.lines[last_line + 1] or "") },
      },
      selectionRange = { start = { line = first, character = 0 }, ["end"] = { line = first, character = 0 } },
      children = {},
    }
    for _, r in ipairs(roots) do
      local l = r.range.start.line
      if l >= tab.start and l < tab.stop then
        table.insert(sym.children, r)
      end
    end
    out[#out + 1] = sym
  end
  return out
end

--- The name token at (line, col).
local function name_at(res, line, col)
  local toks = res.lex.tokens
  local idx = lexer.token_at(toks, line, col) or lexer.token_at(toks, line, col, true)
  local t = idx and toks[idx]
  if t and t.type == "name" then
    return t, idx
  end
end

--- What a name token refers to: { local = var } | { global = name } | { member = name }
local function target_of(res, t, idx)
  local v = res.parse.refs[t]
  if v then
    return { var = v }
  end
  local prev = res.lex.tokens[idx - 1]
  if prev and prev.type == "op" and (prev.value == "." or prev.value == ":") then
    return { member = t.value }
  end
  return { global = t.value }
end

--- Location(s) of the definition at (line, col).
function M.definition(bufnr, line, col)
  local res = analysis.get(bufnr)
  local t, idx = name_at(res, line, col)
  if not t then
    return nil
  end
  local target = target_of(res, t, idx)
  local uri = buf_uri(bufnr)
  if target.var then
    local d = target.var.tok
    if d.synthetic then
      return nil
    end
    return { uri = uri, range = tok_range(d) }
  end
  if target.member then
    local out = {}
    for _, fn in ipairs(res.parse.functions) do
      if fn.name and fn.name:match("[.:]" .. vim.pesc(target.member) .. "$") then
        out[#out + 1] = { uri = uri, range = tok_range(fn.tok) }
      end
    end
    return #out > 0 and out or nil
  end
  local g = res.parse.globals[target.global]
  if g and g.tok then
    return { uri = uri, range = tok_range(g.tok) }
  end
  local other = analysis.context(bufnr).globals[target.global]
  if other and other.tok and other.path then
    return { uri = uri_of(other.path), range = tok_range(other.tok) }
  end
  return nil
end

--- Occurrences of the symbol at (line, col): { uri, tok, write }[]
local function occurrences(bufnr, line, col, cross_file)
  local res = analysis.get(bufnr)
  local t, idx = name_at(res, line, col)
  if not t then
    return nil
  end
  local target = target_of(res, t, idx)
  local uri = buf_uri(bufnr)
  local out = {}
  if target.var then
    local v = target.var
    if not v.tok.synthetic then
      out[#out + 1] = { uri = uri, tok = v.tok, write = true }
    end
    for _, r in ipairs(v.refs) do
      out[#out + 1] = { uri = uri, tok = r }
    end
    return out, target
  end
  if target.member then
    return nil, target
  end
  local name = target.global
  local function collect(parse, u)
    for _, g in ipairs(parse.global_refs) do
      if g.name == name then
        out[#out + 1] = { uri = u, tok = g.tok, write = g.assign }
      end
    end
  end
  collect(res.parse, uri)
  if cross_file then
    local ctx = analysis.context(bufnr)
    local files = {}
    for _, inc in ipairs(ctx.includes) do
      files[#files + 1] = inc
    end
    if ctx.project then
      files[#files + 1] = { path = ctx.project.path, res = ctx.project.res }
      for _, inc in ipairs(ctx.project.includes) do
        if inc.path ~= res.path then
          files[#files + 1] = inc
        end
      end
    end
    local seen = { [res.path or ""] = true }
    for _, f in ipairs(files) do
      if f.res and f.res.parse and not seen[f.path] then
        seen[f.path] = true
        collect(f.res.parse, uri_of(f.path))
      end
    end
  end
  return out, target
end

function M.references(bufnr, line, col, include_declaration)
  local occ = occurrences(bufnr, line, col, true)
  if not occ then
    return nil
  end
  local out = {}
  for _, o in ipairs(occ) do
    if include_declaration ~= false or not o.write then
      out[#out + 1] = { uri = o.uri, range = tok_range(o.tok) }
    end
  end
  return out
end

function M.highlights(bufnr, line, col)
  local occ = occurrences(bufnr, line, col, false)
  if not occ then
    return nil
  end
  local out = {}
  for _, o in ipairs(occ) do
    out[#out + 1] = { range = tok_range(o.tok), kind = o.write and 3 or 2 }
  end
  return out
end

--- WorkspaceEdit renaming the symbol at (line, col), or nil, error.
function M.rename(bufnr, line, col, new_name)
  if not new_name:match("^[%a_\128-\255][%w_\128-\255]*$") or lexer.keywords[new_name] then
    return nil, ("'%s' is not a valid name"):format(new_name)
  end
  local occ, target = occurrences(bufnr, line, col, true)
  if not occ then
    return nil, "nothing to rename here"
  end
  if target and target.global then
    local res = analysis.get(bufnr)
    local ctx = analysis.context(bufnr)
    if api.builtins[target.global] and not res.parse.globals[target.global] and not ctx.globals[target.global] then
      return nil, "can't rename the built-in " .. target.global
    end
  end
  local changes = {}
  for _, o in ipairs(occ) do
    changes[o.uri] = changes[o.uri] or {}
    table.insert(changes[o.uri], { range = tok_range(o.tok), newText = new_name })
  end
  return { changes = changes }
end

return M
