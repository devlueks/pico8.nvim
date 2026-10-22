-- :Pico8Tokens, :Pico8Run, :Pico8Docs

local analysis = require("pico8.analysis")
local api = require("pico8.api")
local config = require("pico8.config")
local tokens = require("pico8.tokens")

local M = {}

local function pct(v, limit)
  return ("%5.1f%%"):format(v * 100 / limit)
end

--- Token report for the buffer, or for lines l1..l2 (1-based) when given.
function M.tokens(bufnr, l1, l2)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].filetype ~= "pico8" then
    vim.notify("pico8: not a PICO-8 buffer", vim.log.levels.WARN)
    return
  end
  local ctx = analysis.context(bufnr)
  local res = ctx.res
  local chunks = {}
  local function line(...)
    for _, c in ipairs({ ... }) do
      chunks[#chunks + 1] = type(c) == "table" and c or { c }
    end
    chunks[#chunks + 1] = { "\n" }
  end

  if l1 and l2 then
    local toks = res.lex.tokens
    local n = 0
    for i, t in ipairs(toks) do
      if t.type ~= "eof" and t.line >= l1 - 1 and t.line <= l2 - 1 then
        n = n + tokens.weight(toks, i)
      end
    end
    local sel = {}
    for l = l1, l2 do
      sel[#sel + 1] = res.lines[l] or ""
    end
    line({ ("lines %d-%d: "):format(l1, l2), "Title" }, { ("%d tokens"):format(n), "Number" },
      (", %d chars"):format(tokens.chars(table.concat(sel, "\n"))))
    vim.api.nvim_echo(chunks, false, {})
    return
  end

  local name = res.path and vim.fs.basename(res.path) or "[No Name]"
  line({ "PICO-8 " .. api.VERSION .. " · " .. name, "Title" })
  line("  tokens  ", { ("%5d / %d"):format(ctx.total_tokens, tokens.TOKEN_LIMIT), "Number" },
    "  " .. pct(ctx.total_tokens, tokens.TOKEN_LIMIT))
  line("  chars   ", { ("%5d / %d"):format(ctx.total_chars, tokens.CHAR_LIMIT), "Number" },
    " " .. pct(ctx.total_chars, tokens.CHAR_LIMIT))
  line({ "  (compressed size is only checked by PICO-8 itself: limit 15360 bytes for .p8.png)", "Comment" })
  if ctx.project then
    line("  cart    ", vim.fs.basename(ctx.project.path), (" — this file: %d tokens"):format(res.tokens))
  end
  if #res.cart.tabs > 1 then
    local parts = {}
    for _, tab in ipairs(res.cart.tabs) do
      parts[#parts + 1] = ("%d: %d"):format(tab.index, res.tab_tokens[tab.index] or 0)
    end
    line("  tabs    ", table.concat(parts, "  "))
  end
  local incs = ctx.project and ctx.project.includes or ctx.includes
  for _, inc in ipairs(incs) do
    if inc.res then
      line("  include ", inc.directive.include, ": ", { tostring(inc.res.tokens), "Number" }, " tokens")
    else
      line("  include ", inc.directive.include, ": ", { inc.err or "?", "ErrorMsg" })
    end
  end
  local fns = {}
  for _, fn in ipairs(res.parse.functions) do
    if fn.tokens then
      fns[#fns + 1] = fn
    end
  end
  table.sort(fns, function(a, b)
    return a.tokens > b.tokens
  end)
  if #fns > 0 then
    line({ "  most expensive functions:", "Title" })
    for i = 1, math.min(10, #fns) do
      local fn = fns[i]
      line({ ("  %6d  "):format(fn.tokens), "Number" }, fn.name or "function", { ("  :%d"):format(fn.line + 1), "Comment" })
    end
  end
  vim.api.nvim_echo(chunks, false, {})
end

-- running carts -------------------------------------------------------------------

local CANDIDATES = {
  "~/pico-8/pico8",
  "~/pico-8/pico8_64",
  "~/.local/bin/pico8",
  "/opt/pico-8/pico8",
  "/usr/local/bin/pico8",
  "/Applications/PICO-8.app/Contents/MacOS/pico8",
  "C:/Program Files (x86)/PICO-8/pico8.exe",
  "C:/Program Files/PICO-8/pico8.exe",
}

--- Path of the PICO-8 executable, or nil.
function M.find_pico8()
  local configured = config.get().pico8_path
  if configured then
    configured = vim.fn.expand(configured)
    return vim.fn.executable(configured) == 1 and configured or nil
  end
  for _, exe in ipairs({ "pico8", "pico8_64", "pico-8" }) do
    local p = vim.fn.exepath(exe)
    if p ~= "" then
      return p
    end
  end
  for _, c in ipairs(CANDIDATES) do
    local p = vim.fn.expand(c)
    if vim.fn.executable(p) == 1 then
      return p
    end
  end
end

--- Run the cart of the current buffer (the including cart for .lua files).
function M.run(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local exe = M.find_pico8()
  if not exe then
    vim.notify("pico8: PICO-8 executable not found; set pico8_path in setup()", vim.log.levels.ERROR)
    return
  end
  local ctx = analysis.context(bufnr)
  local target = ctx.project and ctx.project.path or ctx.res.path
  if not target or not target:lower():match("%.p8$") then
    vim.notify("pico8: no .p8 cart to run (a .lua file must be #included by a cart next to it)", vim.log.levels.ERROR)
    return
  end
  -- PICO-8 loads the cart from disk
  if vim.bo[bufnr].modified then
    vim.api.nvim_buf_call(bufnr, function()
      vim.cmd("silent update")
    end)
  end
  local cmd = { exe }
  vim.list_extend(cmd, config.get().run_args or {})
  vim.list_extend(cmd, { "-run", target })
  local ok, err = pcall(vim.system, cmd, { detach = true, cwd = vim.fs.dirname(target) })
  if not ok then
    vim.notify("pico8: failed to start PICO-8: " .. tostring(err), vim.log.levels.ERROR)
    return
  end
  vim.notify("pico8: running " .. vim.fs.basename(target))
end

-- docs ------------------------------------------------------------------------------

local function doc_lines(name)
  if name == "stat" or name == "stat()" then
    local out = { "# stat(x)", "" }
    local keys = vim.tbl_keys(api.STAT)
    table.sort(keys)
    for _, k in ipairs(keys) do
      out[#out + 1] = ("- `stat(%d)` %s"):format(k, api.STAT[k])
    end
    return out
  elseif name == "memory" then
    local out = { "# Memory map", "" }
    local keys = vim.tbl_keys(api.MEMORY)
    table.sort(keys)
    for _, k in ipairs(keys) do
      out[#out + 1] = ("- `0x%04x` %s"):format(k, api.MEMORY[k])
    end
    return out
  end
  local e = api.functions[name]
  if e then
    return vim.split(api.markdown(e), "\n")
  end
  if api.CALLBACKS[name] then
    return { "```lua", "function " .. name .. "()", "```", api.CALLBACKS[name] }
  end
end

local function cheatsheet()
  local out = { "# PICO-8 " .. api.VERSION .. " API", "" }
  for _, cat in ipairs(api.categories) do
    out[#out + 1] = "## " .. cat[2]
    out[#out + 1] = ""
    out[#out + 1] = "```lua"
    for _, e in ipairs(api.list) do
      if e.category == cat[1] then
        for _, s in ipairs(e.signatures) do
          out[#out + 1] = s.label .. (e.since and ("  -- new in " .. e.since) or "")
        end
      end
    end
    out[#out + 1] = "```"
    out[#out + 1] = ""
  end
  out[#out + 1] = "## Callbacks"
  out[#out + 1] = ""
  for _, name in ipairs(api.CALLBACK_ORDER) do
    out[#out + 1] = ("- `%s()` %s"):format(name, api.CALLBACKS[name])
  end
  out[#out + 1] = ""
  out[#out + 1] = "## Buttons"
  out[#out + 1] = ""
  for _, g in ipairs(api.GLYPHS) do
    if g[3] then
      out[#out + 1] = ("- `%s` = %d  %s"):format(g[1], g[3], g[2])
    end
  end
  out[#out + 1] = ""
  out[#out + 1] = "See also `:Pico8Docs stat` and `:Pico8Docs memory`."
  return out
end

--- :Pico8Docs [name] — documentation float for NAME (or the word under the
--- cursor); without either, a cheat sheet buffer.
function M.docs(name)
  if not name or name == "" then
    local word = vim.fn.expand("<cword>")
    if doc_lines(word) then
      name = word
    end
  end
  local lines = name and name ~= "" and doc_lines(name)
  if name and name ~= "" and not lines then
    vim.notify("pico8: no documentation for " .. name, vim.log.levels.WARN)
    return
  end
  if lines then
    vim.lsp.util.open_floating_preview(lines, "markdown", { border = "rounded", focus_id = "pico8_docs", max_width = 80 })
    return
  end
  vim.cmd("botright vnew")
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, cheatsheet())
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "markdown"
  pcall(vim.api.nvim_buf_set_name, buf, "pico8://api")
end

function M.doc_names()
  local names = { "stat", "memory" }
  for _, e in ipairs(api.list) do
    names[#names + 1] = e.name
  end
  vim.list_extend(names, api.CALLBACK_ORDER)
  table.sort(names)
  return names
end

return M
