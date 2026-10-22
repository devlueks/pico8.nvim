-- Cached analysis of PICO-8 buffers and files: cart layout, tokens, token
-- and character counts, parse results, #include resolution and the
-- "project" a .lua file belongs to (the cart that #includes it).

local cart = require("pico8.cart")
local lexer = require("pico8.lexer")
local parser = require("pico8.parser")
local tokens = require("pico8.tokens")

local M = {}

local buf_cache = {} -- bufnr -> { tick, res }
local file_cache = {} -- path:tab -> { stamp, res }
local scan_cache = {} -- cart path -> { stamp, includes = { abs path = true } }
local ctx_cache = {} -- bufnr -> { tick, time, ctx }

local CONTEXT_TTL = 1000 -- ms before #include files are checked again

-- `res.parse` is computed on first access: completion only needs tokens.
local lazy_parse = {
  __index = function(res, key)
    if key ~= "parse" then
      return nil
    end
    local p = parser.parse(res.lex)
    for _, fn in ipairs(p.functions) do
      fn.tokens = tokens.count(res.lex.tokens, fn.s, fn.e)
    end
    rawset(res, "parse", p)
    return p
  end,
}

--- Analyse code text starting at buffer line `line0`.
local function analyze_code(text, line0)
  local lx = lexer.lex(text, { line = line0 })
  local res = setmetatable({
    text = text,
    lex = lx,
    tokens = tokens.count(lx.tokens),
    chars = tokens.chars(text),
  }, lazy_parse)
  -- names declared with shrinko8-style `--lint: name, name` comments
  res.lint_globals = {}
  for _, c in ipairs(lx.comments) do
    local list = c.text:match("^%-%-%s*lint:(.*)$") or c.text:match("^//%s*lint:(.*)$")
    if list then
      for name in list:gmatch("[^%s,]+") do
        if not name:find("::", 1, true) then
          res.lint_globals[name] = true
        end
      end
    end
  end
  return res
end

--- Full analysis of the lines of a buffer or file.
---@param lines string[]
---@param path? string
function M.analyze(lines, path)
  local info = cart.parse(lines, { force_cart = path and cart.is_cart_path(path) })
  local text = cart.code_text(lines, info)
  local res = analyze_code(text, info.code_start)
  res.lines = lines
  res.cart = info
  res.path = path

  -- tokens per code tab
  local toks = res.lex.tokens
  local ti = 1
  res.tab_tokens = {}
  for _, tab in ipairs(info.tabs) do
    local n = 0
    while ti <= #toks and toks[ti].type ~= "eof" and toks[ti].line < tab.stop do
      if toks[ti].line >= tab.start then
        n = n + tokens.weight(toks, ti)
      end
      ti = ti + 1
    end
    res.tab_tokens[tab.index] = n
  end
  return res
end

--- Analysis of a buffer, cached by changedtick.
function M.get(bufnr)
  if not bufnr or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  local c = buf_cache[bufnr]
  if c and c.tick == tick then
    return c.res
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local name = vim.api.nvim_buf_get_name(bufnr)
  local res = M.analyze(lines, name ~= "" and vim.fs.normalize(name) or nil)
  res.bufnr = bufnr
  buf_cache[bufnr] = { tick = tick, res = res }
  return res
end

function M.forget(bufnr)
  buf_cache[bufnr] = nil
  ctx_cache[bufnr] = nil
end

--- Drop cached contexts (after files were written).
function M.invalidate()
  ctx_cache = {}
end

-- files ---------------------------------------------------------------------

local function file_stamp(path)
  local bufnr = cart.find_buf(path)
  if bufnr then
    return "b" .. bufnr .. ":" .. vim.api.nvim_buf_get_changedtick(bufnr)
  end
  local st = vim.uv.fs_stat(path)
  if not st then
    return nil
  end
  return ("f%d.%d:%d"):format(st.mtime.sec, st.mtime.nsec or 0, st.size)
end

--- Resolve an #include target relative to the including file.
---@return string path, integer|nil tab
function M.resolve_include(from_path, target)
  target = target:gsub("\\", "/")
  local tab
  local base, tabdigit = target:match("^(.*):(%x)$")
  if base then
    target, tab = base, tonumber(tabdigit, 16)
  end
  local dir = from_path and vim.fs.dirname(from_path) or vim.fn.getcwd()
  local path = target:sub(1, 1) == "/" and target or (dir .. "/" .. target)
  return vim.fs.normalize(path), tab
end

--- Analysis of an included file (or one tab of an included cart).
---@return table|nil res, string|nil err
function M.file(path, tab)
  local stamp = file_stamp(path)
  if not stamp then
    return nil, "file not found: " .. path
  end
  local key = path .. ":" .. (tab or "")
  local c = file_cache[key]
  if c and c.stamp == stamp then
    return c.res, c.err
  end
  local lines = cart.file_lines(path)
  local res, err
  if not lines then
    err = "cannot read " .. path
  else
    local sel, offset = cart.include_lines(lines, path, tab)
    if not sel then
      err = offset
    else
      res = analyze_code(table.concat(sel, "\n"), offset)
      res.path = path
    end
  end
  file_cache[key] = { stamp = stamp, res = res, err = err }
  return res, err
end

local full_cache = {} -- path -> { stamp, res }

--- Full analysis of a file by path (the buffer's, when it is loaded).
function M.get_path(path)
  local bufnr = cart.find_buf(path)
  if bufnr then
    return M.get(bufnr)
  end
  local stamp = file_stamp(path)
  if not stamp then
    return nil
  end
  local c = full_cache[path]
  if c and c.stamp == stamp then
    return c.res
  end
  local lines = cart.read_lines(path)
  if not lines then
    return nil
  end
  local res = M.analyze(lines, path)
  full_cache[path] = { stamp = stamp, res = res }
  return res
end

--- Includes of an analysed buffer: { directive, path, tab, res, err }[]
function M.includes(res)
  local out = {}
  for _, d in ipairs(res.lex.directives) do
    if d.include then
      local path, tab = M.resolve_include(res.path, d.include)
      local inc, err = M.file(path, tab)
      out[#out + 1] = { directive = d, path = path, tab = tab, res = inc, err = err }
    end
  end
  return out
end

--- Absolute paths #included by the cart at `cart_path` (cheap line scan).
local function scan_includes(cart_path)
  local stamp = file_stamp(cart_path)
  local c = scan_cache[cart_path]
  if c and c.stamp == stamp then
    return c.includes
  end
  local set = {}
  local lines = cart.file_lines(cart_path) or {}
  for _, l in ipairs(lines) do
    local target = l:match("^%s*#include%s+(.-)%s*$")
    if target then
      set[(M.resolve_include(cart_path, target))] = true
    end
  end
  scan_cache[cart_path] = { stamp = stamp, includes = set }
  return set
end

--- For a .lua file: the cart (in the same or the parent directory) that
--- #includes it.
function M.find_project_cart(path)
  if not path or cart.is_cart_path(path) then
    return nil
  end
  local dir = vim.fs.dirname(path)
  for _, d in ipairs({ dir, vim.fs.dirname(dir) }) do
    local carts = vim.fn.glob(d .. "/*.p8", false, true)
    if #carts <= 50 then
      for _, cp in ipairs(carts) do
        cp = vim.fs.normalize(cp)
        if scan_includes(cp)[path] then
          return cp
        end
      end
    end
  end
end

--- Everything the editor features need for a buffer: its analysis, its
--- includes, the project cart, globals defined in other files and the
--- token/char totals that count against the limits.
function M.context(bufnr)
  if not bufnr or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  local res = M.get(bufnr)
  local now = vim.uv.now()
  local cached = ctx_cache[bufnr]
  if cached and cached.res == res and now - cached.time < CONTEXT_TTL then
    return cached.ctx
  end
  local ctx = { res = res, includes = M.includes(res), globals = {} }
  ctx_cache[bufnr] = { res = res, time = now, ctx = ctx }

  local function add_globals(r, path)
    if not r or not r.parse then
      return
    end
    for name, g in pairs(r.parse.globals) do
      if not ctx.globals[name] or (g.kind == "function" and ctx.globals[name].kind ~= "function") then
        ctx.globals[name] = { tok = g.tok, kind = g.kind, fn = g.fn, path = path }
      end
    end
    for name in pairs(r.lint_globals or {}) do
      ctx.globals[name] = ctx.globals[name] or { kind = "variable", path = path }
    end
  end

  local function totals(r, includes)
    local t, ch = r.tokens, r.chars
    for _, inc in ipairs(includes) do
      if inc.res then
        t = t + inc.res.tokens
        ch = ch + inc.res.chars - tokens.chars(inc.directive.text)
      end
    end
    return t, ch
  end

  for _, inc in ipairs(ctx.includes) do
    add_globals(inc.res, inc.path)
  end
  ctx.total_tokens, ctx.total_chars = totals(res, ctx.includes)

  local project = M.find_project_cart(res.path)
  if project then
    local pres = M.get_path(project)
    if pres then
      local pinc = M.includes(pres)
      ctx.project = { path = project, res = pres, includes = pinc }
      add_globals(pres, project)
      for _, inc in ipairs(pinc) do
        if inc.path ~= res.path then
          add_globals(inc.res, inc.path)
        end
      end
      ctx.total_tokens, ctx.total_chars = totals(pres, pinc)
    end
  end
  return ctx
end

return M
