-- Diagnostics: syntax errors, PICO-8 limits, missing #include files,
-- undefined globals (with "did you mean" hints), standard Lua library use,
-- unused locals and too many arguments for API functions.

local analysis = require("pico8.analysis")
local api = require("pico8.api")
local config = require("pico8.config")
local tokens = require("pico8.tokens")

local M = {}

M.ns = vim.api.nvim_create_namespace("pico8")

local S = vim.diagnostic.severity

local function distance(a, b, max)
  local la, lb = #a, #b
  if math.abs(la - lb) > max then
    return max + 1
  end
  local prev = {}
  for j = 0, lb do
    prev[j] = j
  end
  for i = 1, la do
    local cur = { [0] = i }
    local best = i
    local ca = a:byte(i)
    for j = 1, lb do
      local cost = ca == b:byte(j) and 0 or 1
      cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
      best = math.min(best, cur[j])
    end
    if best > max then
      return max + 1
    end
    prev = cur
  end
  return prev[lb]
end
M.distance = distance

--- Best "did you mean" candidate for an unknown name.
local function suggest(name, user_globals)
  -- glyph typed without its variation selector: ⬅ instead of ⬅️
  if api.glyphs[name .. "\239\184\143"] then
    return name .. "\239\184\143", "PICO-8 needs the glyph with its variation selector (U+FE0F)"
  end
  local lower = name:lower()
  if lower ~= name and (api.functions[lower] or user_globals[lower]) then
    return lower, "PICO-8 names are lowercase"
  end
  if #name < 3 then
    return nil
  end
  local max = #name <= 5 and 1 or 2
  local best, best_d = nil, max + 1
  local function try(cand)
    if cand ~= name then
      local d = distance(name, cand, max)
      if d < best_d then
        best, best_d = cand, d
      end
    end
  end
  for _, e in ipairs(api.list) do
    try(e.name)
  end
  for cand in pairs(user_globals) do
    try(cand)
  end
  for cand in pairs(api.CALLBACKS) do
    try(cand)
  end
  return best
end

--- Compute the diagnostics for a buffer.
---@return vim.Diagnostic[]
function M.compute(bufnr)
  local opts = config.get().diagnostics
  local ctx = analysis.context(bufnr)
  local res = ctx.res
  local parse = res.parse
  local out = {}

  local function add(severity, msg, l, c, el, ec, code, extra)
    local d = {
      lnum = l,
      col = c,
      end_lnum = el or l,
      end_col = ec or c,
      severity = severity,
      message = msg,
      source = "pico8",
      code = code,
    }
    if extra then
      d = vim.tbl_extend("force", d, extra)
    end
    out[#out + 1] = d
  end

  local function add_tok(severity, msg, t, code, extra)
    add(severity, msg, t.line, t.col, t.eline, t.ecol, code, extra)
  end

  -- syntax ------------------------------------------------------------------
  for _, e in ipairs(res.lex.errors) do
    add(S.ERROR, e.msg, e.line, e.col, e.eline, e.ecol, "syntax")
  end
  if #res.lex.errors == 0 and not parse.ok then
    local e = parse.error
    add(S.ERROR, e.msg, e.line, e.col, e.eline, e.ecol, "syntax")
  end

  -- limits ------------------------------------------------------------------
  local anchor = res.cart.lua_line or 0
  local anchor_len = #(res.lines[anchor + 1] or "")
  local where = ctx.project and (" (cart " .. vim.fs.basename(ctx.project.path) .. ")") or ""
  if ctx.total_tokens > tokens.TOKEN_LIMIT then
    add(S.ERROR, ("token limit exceeded: %d/%d%s"):format(ctx.total_tokens, tokens.TOKEN_LIMIT, where),
      anchor, 0, anchor, anchor_len, "token-limit")
  end
  if ctx.total_chars > tokens.CHAR_LIMIT then
    add(S.ERROR, ("character limit exceeded: %d/%d%s"):format(ctx.total_chars, tokens.CHAR_LIMIT, where),
      anchor, 0, anchor, anchor_len, "char-limit")
  end

  -- includes ----------------------------------------------------------------
  for _, inc in ipairs(ctx.includes) do
    local d = inc.directive
    if inc.err then
      local err = inc.err:find("^file not found") and ("file not found: " .. d.include) or inc.err
      add(S.WARN, "#include: " .. err, d.line, d.col, d.line, d.ecol, "include")
    elseif inc.res and #inc.res.lex.errors + (inc.res.parse.ok and 0 or 1) > 0 then
      local e = #inc.res.lex.errors > 0 and inc.res.lex.errors[1] or inc.res.parse.error
      add(S.WARN, ("#include: %s:%d: %s"):format(vim.fs.basename(inc.path), e.line + 1, e.msg),
        d.line, d.col, d.line, d.ecol, "include")
    end
  end

  if not parse.ok or #res.lex.errors > 0 then
    return out
  end

  -- undefined globals ------------------------------------------------------
  local user = {}
  for name in pairs(parse.globals) do
    user[name] = true
  end
  for name in pairs(ctx.globals) do
    user[name] = true
  end
  for name in pairs(res.lint_globals) do
    user[name] = true
  end
  for _, name in ipairs(opts.globals or {}) do
    user[name] = true
  end

  if opts.undefined_globals then
    for _, g in ipairs(parse.global_refs) do
      local name = g.name
      if not g.assign and not user[name] and not api.builtins[name] then
        local std = api.STDLIB[name]
        if std then
          local msg = std._
          local repl = g.member and std[g.member]
          if repl then
            msg = ("%s.%s doesn't exist: %s, use %s"):format(name, g.member, std._, repl)
          end
          add_tok(S.ERROR, msg, g.tok, "stdlib")
        else
          local cand, why = suggest(name, user)
          local msg = ("undefined global '%s'"):format(name)
          if g.compound then
            msg = ("global '%s' is updated but never assigned"):format(name)
          end
          if cand then
            msg = msg .. (" - did you mean '%s'?"):format(cand) .. (why and (" (" .. why .. ")") or "")
          end
          add_tok(S.WARN, msg, g.tok, "undefined-global", { user_data = { suggestion = cand } })
        end
      end
    end
  end

  -- unused locals -----------------------------------------------------------
  if opts.unused then
    for _, v in ipairs(parse.unused) do
      local msg
      if v.kind == "param" then
        if opts.unused_params and v.last_param then
          msg = ("unused parameter '%s' (removing it saves a token)"):format(v.name)
        end
      elseif v.kind == "for" then
        if opts.unused_loop_vars then
          msg = ("unused loop variable '%s'"):format(v.name)
        end
      elseif v.kind == "function" then
        msg = ("unused local function '%s'"):format(v.name)
      elseif v.assigned then
        msg = ("local '%s' is assigned but never read"):format(v.name)
      else
        msg = ("unused local '%s'"):format(v.name)
      end
      if msg and not v.tok.synthetic then
        add_tok(S.HINT, msg, v.tok, "unused", { _tags = { unnecessary = true } })
      end
    end
  end

  -- argument counts ---------------------------------------------------------
  if opts.arg_count then
    for _, c in ipairs(parse.calls) do
      local e = api.functions[c.name]
      if e and e.check and not user[c.name] and not c.multi and c.nargs > e.max_args then
        add_tok(S.WARN, ("too many arguments for %s(): expected at most %d, got %d"):format(c.name, e.max_args, c.nargs),
          c.tok, "arg-count")
      end
    end
  end

  return out
end

--- Recompute and publish diagnostics for a buffer.
function M.refresh(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  if not config.get().diagnostics.enabled then
    vim.diagnostic.reset(M.ns, bufnr)
    return
  end
  local ok, diags = pcall(M.compute, bufnr)
  if not ok then
    vim.diagnostic.set(M.ns, bufnr, {
      { lnum = 0, col = 0, severity = S.ERROR, source = "pico8", message = "pico8.nvim internal error: " .. tostring(diags) },
    })
    return
  end
  vim.diagnostic.set(M.ns, bufnr, diags)
end

return M
