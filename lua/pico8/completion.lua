-- Completion items (LSP format) for PICO-8 code: API functions with call
-- snippets, callbacks, button glyphs, keywords, names and fields defined in
-- the cart and its #includes, snippets and #include file names.
-- Also provides an 'omnifunc' for use without the language server.

local analysis = require("pico8.analysis")
local api = require("pico8.api")
local config = require("pico8.config")
local lexer = require("pico8.lexer")

local M = {}

local Kind = {
  Text = 1, Method = 2, Function = 3, Field = 5, Variable = 6, Module = 9,
  Keyword = 14, Snippet = 15, File = 17, Folder = 19, Constant = 21, Event = 23,
}
M.Kind = Kind

local PLAIN, SNIPPET = 1, 2

M.root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(vim.fs.normalize(debug.getinfo(1, "S").source:sub(2)))))

-- snippets --------------------------------------------------------------------

local snippet_list

--- Bundled snippets: { name, prefix, body, description }[]
function M.snippets()
  if snippet_list then
    return snippet_list
  end
  snippet_list = {}
  local f = io.open(M.root .. "/snippets/pico8.json", "rb")
  if not f then
    return snippet_list
  end
  local ok, data = pcall(vim.json.decode, f:read("*a"))
  f:close()
  if not ok then
    return snippet_list
  end
  for name, s in pairs(data) do
    local prefixes = type(s.prefix) == "table" and s.prefix or { s.prefix }
    for _, prefix in ipairs(prefixes) do
      snippet_list[#snippet_list + 1] = {
        name = name,
        prefix = prefix,
        body = type(s.body) == "table" and table.concat(s.body, "\n") or s.body,
        description = s.description,
      }
    end
  end
  table.sort(snippet_list, function(a, b)
    return a.prefix < b.prefix
  end)
  return snippet_list
end

--- Snippet body as plain text (for previews).
function M.snippet_preview(body)
  local s = body:gsub("%${%d+|([^,|]*)[^}]*}", "%1")
  for _ = 1, 3 do -- nested placeholders
    s = s:gsub("%${%d+:([^{}]*)}", "%1")
  end
  s = s:gsub("%$%d+", ""):gsub("%${%d+}", ""):gsub("\\(.)", "%1"):gsub("\t", "  ")
  return s
end

-- context -------------------------------------------------------------------

local function pos_lt(l1, c1, l2, c2)
  return l1 < l2 or (l1 == l2 and c1 < c2)
end

--- Is (line, col) inside a comment or string?
local function in_comment_or_string(res, line, col)
  for _, c in ipairs(res.lex.comments) do
    if c.line <= line and c.eline >= line then
      if c.long then
        local closed = c.text:match("%]=*%]$") ~= nil
        if pos_lt(c.line, c.col, line, col) and (pos_lt(line, col, c.eline, c.ecol) or not closed) then
          return true
        end
      elseif line == c.line and col > c.col then
        return true
      end
    end
  end
  local toks = res.lex.tokens
  local i = lexer.token_before(toks, line, col)
  local t = i and toks[i]
  if t and t.type == "string" then
    local v = t.value
    local q = v:sub(1, 1)
    local closed
    if q == "[" then
      closed = v:match("%]=*%]$") ~= nil and #v >= 4
    else
      closed = #v >= 2 and v:sub(-1) == q and v:sub(-2, -2) ~= "\\"
    end
    if pos_lt(line, col, t.eline, t.ecol) or (not closed and (line < t.eline or (line == t.eline and col <= t.ecol))) then
      return true
    end
  end
  return false
end

--- Describe what is being completed at (line, col).
---@return table cx { kind = "none"|"include"|"member"|"code", prefix, start, base, funcname, next_char }
function M.context_at(res, line, col)
  local info = res.cart
  if info.is_cart and (line < info.code_start or line >= info.code_end) then
    return { kind = "none" }
  end
  local text = res.lines[line + 1] or ""
  local before = text:sub(1, col)

  local inc = before:match("^%s*#include%s+(.*)$")
  if inc then
    return { kind = "include", prefix = inc, start = col - #inc }
  end
  if in_comment_or_string(res, line, col) then
    return { kind = "none" }
  end

  local prefix = before:match("[%w_\128-\255]*$")
  local start = col - #prefix
  local pre = before:sub(1, start)
  local cx = { prefix = prefix, start = start, next_char = text:sub(col + 1, col + 1) }

  if prefix:match("^%d") then
    return { kind = "none" }
  end
  local sep = pre:match("([%.:])%s*$")
  if sep and not pre:match("%.%.%s*$") then
    local base = pre:match("([%w_\128-\255]+)%s*[%.:]%s*$")
    if base and base:match("^%d") then
      return { kind = "none" } -- a number like 3.
    end
    cx.kind, cx.base, cx.method = "member", base, sep == ":"
    return cx
  end
  cx.kind = "code"
  cx.funcname = pre:match("%f[%w_]function%s+$") ~= nil
  return cx
end

-- names defined in the code ----------------------------------------------------

local RANK = { variable = 1, ["local"] = 2, field = 2, method = 3, ["function"] = 3 }

local function params_after(toks, j)
  -- toks[j] should be "("
  local out = {}
  if not (toks[j] and toks[j].value == "(") then
    return out
  end
  j = j + 1
  while toks[j] and toks[j].type ~= "eof" and toks[j].value ~= ")" do
    if toks[j].type == "name" or toks[j].value == "..." then
      out[#out + 1] = toks[j].value
    end
    j = j + 1
  end
  return out
end

--- Names and fields found in the token stream (robust against syntax errors).
---@return table { names = name -> {kind, params, count}, fields = base -> field -> {kind, params} }
function M.symbols(res)
  if res._symbols then
    return res._symbols
  end
  local toks = res.lex.tokens
  local names, fields, all_fields = {}, {}, {}

  local function set(name, kind, params)
    local cur = names[name]
    if not cur then
      names[name] = { kind = kind, params = params, count = 1 }
    else
      cur.count = cur.count + 1
      if RANK[kind] > RANK[cur.kind] then
        cur.kind, cur.params = kind, params
      end
    end
  end

  local function add_field(base, f, kind, params)
    fields[base] = fields[base] or {}
    local cur = fields[base][f]
    if not cur then
      fields[base][f] = { kind = kind, params = params, count = 1 }
    else
      cur.count = cur.count + 1
      if RANK[kind] > RANK[cur.kind] then
        cur.kind, cur.params = kind, params
      end
    end
    local a = all_fields[f]
    if not a or RANK[fields[base][f].kind] > RANK[a.kind] then
      all_fields[f] = fields[base][f]
    end
  end

  local function is_op(t, v)
    return t and t.type == "op" and t.value == v
  end

  local braces = 0
  for i, t in ipairs(toks) do
    if t.type == "op" then
      if t.value == "{" then
        braces = braces + 1
      elseif t.value == "}" then
        braces = math.max(braces - 1, 0)
      end
    elseif t.type == "name" then
      local prev = toks[i - 1]
      if braces > 0 and is_op(toks[i + 1], "=")
        and (is_op(prev, "{") or is_op(prev, ",") or is_op(prev, ";")) then
        -- table constructor key: { key = value }, collected as a field below
      elseif prev and prev.type == "op" and (prev.value == "." or prev.value == ":") and prev.line == t.line then
        -- (a name on the next line after a trailing "." is most likely the
        -- next statement of code that is being typed)
        local b = toks[i - 2]
        if b and b.type == "name" then
          local kind = prev.value == ":" and "method" or "field"
          local params
          if toks[i - 3] and toks[i - 3].type == "keyword" and toks[i - 3].value == "function" then
            kind, params = prev.value == ":" and "method" or "function", params_after(toks, i + 1)
          end
          add_field(b.value, t.value, kind, params)
        end
      elseif prev and prev.type == "keyword" and prev.value == "function" then
        if is_op(toks[i + 1], "(") then
          set(t.value, "function", params_after(toks, i + 1))
        else
          set(t.value, "variable")
        end
      else
        set(t.value, (prev and prev.type == "keyword" and prev.value == "local") and "local" or "variable")
        -- NAME = { key = ..., key2 = function(...) }
        if is_op(toks[i + 1], "=") and is_op(toks[i + 2], "{") then
          local depth, j = 0, i + 2
          while toks[j] and toks[j].type ~= "eof" do
            local v = toks[j].type == "op" and toks[j].value
            if v == "{" or v == "(" or v == "[" then
              depth = depth + 1
            elseif v == "}" or v == ")" or v == "]" then
              depth = depth - 1
              if depth == 0 then
                break
              end
            elseif depth == 1 and toks[j].type == "name" and is_op(toks[j + 1], "=")
              and (is_op(toks[j - 1], "{") or is_op(toks[j - 1], ",") or is_op(toks[j - 1], ";")) then
              local fn = toks[j + 2] and toks[j + 2].type == "keyword" and toks[j + 2].value == "function"
              add_field(t.value, toks[j].value, fn and "function" or "field", fn and params_after(toks, j + 3) or nil)
            end
            j = j + 1
          end
        end
      end
    end
  end

  res._symbols = { names = names, fields = fields, all_fields = all_fields }
  return res._symbols
end

-- items -----------------------------------------------------------------------

local function call_snippet(name, params, all_required)
  local parts, n = {}, 0
  local has_optional = false
  for _, p in ipairs(params) do
    if p.name ~= "..." and (all_required or not p.optional) then
      n = n + 1
      parts[#parts + 1] = ("${%d:%s}"):format(n, p.name)
    else
      has_optional = true
    end
  end
  if n == 0 then
    return has_optional and (name .. "($1)$0") or (name .. "()")
  end
  return name .. "(" .. table.concat(parts, ", ") .. ")$0"
end

local function params_label(sig)
  return sig.label:match("%b()") or "()"
end

local function md(value)
  return { kind = "markdown", value = value }
end

local function user_fn_doc(name, params, path)
  local s = ("```lua\nfunction %s(%s)\n```"):format(name, table.concat(params or {}, ", "))
  if path then
    s = s .. "\n\n*defined in " .. vim.fs.basename(path) .. "*"
  end
  return s
end

--- Completion items for position (line, col) of a buffer.
---@param opts? { snippet_support?: boolean }
function M.items(bufnr, line, col, opts)
  opts = opts or {}
  local cfg = config.get().completion
  local snippets_ok = opts.snippet_support ~= false
  local call_snips = cfg.call_snippets and snippets_ok

  local res = analysis.get(bufnr)
  local cx = M.context_at(res, line, col)
  if cx.kind == "none" then
    return {}
  end
  local range = {
    start = { line = line, character = cx.start },
    ["end"] = { line = line, character = col },
  }
  local items = {}
  local function add(item, text, format)
    item.textEdit = { range = range, newText = text or item.label }
    item.insertTextFormat = format or PLAIN
    item.plain = item.plain or (format ~= SNIPPET and (text or item.label)) or item.label
    items[#items + 1] = item
  end

  -- #include file names --------------------------------------------------
  if cx.kind == "include" then
    local base = res.path and vim.fs.dirname(res.path) or vim.fn.getcwd()
    local dirpart = cx.prefix:match("^(.*/)") or ""
    local dir = vim.fs.normalize(base .. "/" .. dirpart)
    for name, ty in vim.fs.dir(dir) do
      local full = dirpart .. name
      if ty == "directory" and name:sub(1, 1) ~= "." then
        add({ label = full .. "/", kind = Kind.Folder, sortText = "1" .. full })
      elseif ty ~= "directory" and (name:match("%.lua$") or name:match("%.p8$")) and dir .. "/" .. name ~= res.path then
        add({ label = full, kind = Kind.File, sortText = "2" .. full })
      end
    end
    return items
  end

  local syms = M.symbols(res)
  local ctx = analysis.context(bufnr)

  -- fields after . and : ----------------------------------------------------
  if cx.kind == "member" then
    local set = (cx.base and syms.fields[cx.base]) or syms.all_fields
    for f, info in pairs(set) do
      if not (f == cx.prefix and info.count <= 1) then
        local is_fn = info.kind == "function" or info.kind == "method"
        local item = {
          label = f,
          kind = info.kind == "method" and Kind.Method or (is_fn and Kind.Function or Kind.Field),
          sortText = "1" .. f,
        }
        if is_fn and info.params then
          item.labelDetails = { detail = "(" .. table.concat(info.params, ", ") .. ")" }
        end
        if is_fn and call_snips and cx.next_char ~= "(" and info.params then
          local ps = {}
          for _, p in ipairs(info.params) do
            ps[#ps + 1] = { name = p }
          end
          add(item, call_snippet(f, ps, true), SNIPPET)
        else
          add(item)
        end
      end
    end
    return items
  end

  -- callbacks ------------------------------------------------------------------
  for _, name in ipairs(api.CALLBACK_ORDER) do
    local item = {
      label = name,
      kind = Kind.Event,
      detail = "PICO-8 callback",
      documentation = md("```lua\nfunction " .. name .. "()\n```\n" .. api.CALLBACKS[name]),
      sortText = "2" .. name,
    }
    if cx.funcname and snippets_ok then
      add(item, name .. "()\n\t$0\nend", SNIPPET)
    else
      add(item)
    end
  end

  if cx.funcname then
    -- naming a function: user functions only
    for name, info in pairs(syms.names) do
      if info.kind == "function" and not api.CALLBACKS[name] then
        add({ label = name, kind = Kind.Function, sortText = "1" .. name })
      end
    end
    return items
  end

  -- API ------------------------------------------------------------------------
  for _, e in ipairs(api.list) do
    local sig = e.signatures[1]
    local item = {
      label = e.name,
      kind = Kind.Function,
      detail = sig.label,
      labelDetails = { detail = params_label(sig), description = e.category },
      documentation = md(api.markdown(e)),
      sortText = "2" .. e.name,
      tags = e.deprecated and { 1 } or nil,
    }
    if call_snips and cx.next_char ~= "(" then
      add(item, call_snippet(e.name, sig.params), SNIPPET)
    else
      add(item)
    end
  end

  -- button glyphs --------------------------------------------------------------
  for _, g in ipairs(api.GLYPHS) do
    if g[3] then
      add({
        label = g[1],
        filterText = g[4],
        kind = Kind.Constant,
        detail = g[2],
        labelDetails = { description = g[4] },
        documentation = md(("`%s` = %d — %s"):format(g[1], g[3], g[2])),
        sortText = "3" .. g[4],
      })
    end
  end

  -- names from this file and from included / including files -------------------
  local seen = {}
  for name, info in pairs(syms.names) do
    if not (name == cx.prefix and info.count <= 1) and not api.functions[name] and not api.CALLBACKS[name]
      and not api.glyphs[name] then
      seen[name] = true
      local item = { label = name, sortText = "1" .. name }
      if info.kind == "function" then
        item.kind = Kind.Function
        item.labelDetails = { detail = "(" .. table.concat(info.params or {}, ", ") .. ")" }
        item.documentation = md(user_fn_doc(name, info.params))
        if call_snips and cx.next_char ~= "(" then
          local ps = {}
          for _, p in ipairs(info.params or {}) do
            ps[#ps + 1] = { name = p }
          end
          add(item, call_snippet(name, ps, true), SNIPPET)
        else
          add(item)
        end
      else
        item.kind = Kind.Variable
        add(item)
      end
    end
  end
  for name, g in pairs(ctx.globals) do
    if not seen[name] and not api.functions[name] and not api.CALLBACKS[name] then
      local params = g.fn and g.fn.params
      local item = {
        label = name,
        kind = g.kind == "function" and Kind.Function or Kind.Variable,
        sortText = "1" .. name,
        labelDetails = { description = g.path and vim.fs.basename(g.path) or nil },
      }
      if g.kind == "function" then
        item.labelDetails.detail = "(" .. table.concat(params or {}, ", ") .. ")"
        item.documentation = md(user_fn_doc(name, params, g.path))
      end
      if g.kind == "function" and call_snips and cx.next_char ~= "(" then
        local ps = {}
        for _, p in ipairs(params or {}) do
          ps[#ps + 1] = { name = p }
        end
        add(item, call_snippet(name, ps, true), SNIPPET)
      else
        add(item)
      end
    end
  end

  -- keywords -------------------------------------------------------------------
  for _, kw in ipairs(api.KEYWORDS) do
    add({ label = kw, kind = Kind.Keyword, sortText = "5" .. kw })
  end

  -- snippets -------------------------------------------------------------------
  if cfg.snippets and snippets_ok then
    for _, s in ipairs(M.snippets()) do
      add({
        label = s.prefix,
        kind = Kind.Snippet,
        detail = s.description,
        labelDetails = { description = "snippet" },
        documentation = md("```lua\n" .. M.snippet_preview(s.body) .. "\n```"),
        sortText = "4" .. s.prefix,
      }, s.body, SNIPPET)
    end
  end

  return items
end

-- omnifunc ----------------------------------------------------------------------

local OMNI_KIND = {
  [Kind.Function] = "f", [Kind.Method] = "m", [Kind.Field] = "m", [Kind.Variable] = "v",
  [Kind.Keyword] = "k", [Kind.Snippet] = "s", [Kind.Constant] = "d", [Kind.Event] = "f",
  [Kind.File] = "F", [Kind.Folder] = "D",
}

--- 'omnifunc' implementation (plain words, no snippets).
function M.omnifunc(findstart, base)
  local cur = vim.api.nvim_win_get_cursor(0)
  local line, col = cur[1] - 1, cur[2]
  local res = analysis.get(0)
  if findstart == 1 then
    local cx = M.context_at(res, line, col)
    if cx.kind == "none" then
      return -3
    end
    return cx.start
  end
  -- second call: compute at the start of the completed word
  local start = col - #base
  if (res.lines[line + 1] or ""):sub(start + 1, col) ~= base then
    start = col
  end
  local items = M.items(0, line, start, { snippet_support = false })
  local out = {}
  for _, it in ipairs(items) do
    local word = it.plain or it.label
    if it.kind ~= Kind.Snippet and (vim.startswith(word, base) or (it.filterText and vim.startswith(it.filterText, base))) then
      local doc = it.documentation and it.documentation.value or ""
      out[#out + 1] = {
        word = word,
        abbr = it.label .. ((it.labelDetails and it.labelDetails.detail) or ""),
        menu = it.detail or (it.labelDetails and it.labelDetails.description) or "",
        info = doc,
        kind = OMNI_KIND[it.kind] or "",
        icase = 0,
        dup = 0,
      }
    end
  end
  table.sort(out, function(a, b)
    return a.word < b.word
  end)
  return out
end

return M
