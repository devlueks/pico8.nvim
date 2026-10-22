-- pico8.nvim — PICO-8 0.2.7 support for Neovim:
-- token count, completion, snippets, syntax highlighting and diagnostics.

local config = require("pico8.config")

local M = {}

local attached = {} -- bufnr -> true
local timers = {} -- bufnr -> uv timer

local function set_highlights()
  local links = {
    Pico8Tokens = "Comment",
    Pico8TokensWarn = "DiagnosticWarn",
    Pico8TokensError = "DiagnosticError",
    Pico8TabTokens = "Comment",
    Pico8FunctionTokens = "Comment",
  }
  for name, link in pairs(links) do
    vim.api.nvim_set_hl(0, name, { link = link, default = true })
  end
  -- __gfx__ / __label__ pixels in the PICO-8 palette
  for k, c in pairs(require("pico8.api").PALETTE) do
    vim.api.nvim_set_hl(0, "pico8Px" .. k, { fg = c[1], bg = c[1], ctermfg = c[2], ctermbg = c[2], default = true })
  end
end

local function refresh_now(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) or not attached[bufnr] then
    return
  end
  require("pico8.diagnostics").refresh(bufnr)
  local ok, err = pcall(require("pico8.ui").refresh, bufnr)
  if not ok then
    vim.notify_once("pico8.nvim: " .. tostring(err), vim.log.levels.WARN)
  end
end

--- Schedule a (debounced) refresh of diagnostics and token counts.
function M.refresh(bufnr, delay)
  bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
  delay = delay or config.get().diagnostics.debounce
  local timer = timers[bufnr]
  if not timer then
    timer = vim.uv.new_timer()
    timers[bufnr] = timer
  end
  timer:stop()
  timer:start(delay, 0, vim.schedule_wrap(function()
    refresh_now(bufnr)
  end))
end

local function refresh_all()
  require("pico8.analysis").invalidate()
  for b in pairs(attached) do
    M.refresh(b, 0)
  end
end

local function detach(bufnr)
  attached[bufnr] = nil
  if timers[bufnr] then
    timers[bufnr]:stop()
    timers[bufnr]:close()
    timers[bufnr] = nil
  end
  require("pico8.analysis").forget(bufnr)
end

local function maybe_insert_template(bufnr)
  if not config.get().template then
    return
  end
  local name = vim.api.nvim_buf_get_name(bufnr)
  if not name:lower():match("%.p8$") or vim.uv.fs_stat(name) then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if #lines > 1 or (lines[1] or "") ~= "" then
    return
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, require("pico8.cart").template())
end

--- Attach pico8.nvim to a buffer (called from ftplugin/pico8.lua).
function M.attach(bufnr)
  bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
  if not attached[bufnr] then
    attached[bufnr] = true
    maybe_insert_template(bufnr)

    local group = vim.api.nvim_create_augroup("pico8_buf_" .. bufnr, { clear = true })
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertLeave" }, {
      group = group,
      buffer = bufnr,
      callback = function()
        M.refresh(bufnr)
      end,
    })
    vim.api.nvim_create_autocmd("BufEnter", {
      group = group,
      buffer = bufnr,
      callback = function()
        require("pico8.analysis").invalidate()
        M.refresh(bufnr, 0)
      end,
    })
    -- includes and including carts may have changed
    vim.api.nvim_create_autocmd("BufWritePost", {
      group = group,
      buffer = bufnr,
      callback = refresh_all,
    })
    vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
      group = group,
      buffer = bufnr,
      callback = function()
        detach(bufnr)
        pcall(vim.api.nvim_del_augroup_by_id, group)
      end,
    })
  end

  if config.get().lsp.enabled then
    require("pico8.lsp").attach(bufnr)
  else
    vim.bo[bufnr].omnifunc = "v:lua.require'pico8.completion'.omnifunc"
  end
  M.refresh(bufnr, 0)
end

--- Configure the plugin. Optional: everything works with the defaults.
---@param opts? pico8.Config
function M.setup(opts)
  config.setup(opts)
  set_highlights()
  for b in pairs(attached) do
    if vim.api.nvim_buf_is_valid(b) then
      if not config.get().lsp.enabled then
        for _, client in ipairs(vim.lsp.get_clients({ bufnr = b, name = "pico8" })) do
          vim.lsp.buf_detach_client(b, client.id)
        end
      end
      M.attach(b)
      if not config.get().diagnostics.enabled then
        vim.diagnostic.reset(require("pico8.diagnostics").ns, b)
      end
    end
  end
end

--- Statusline component: "1234/8192 tokens 15%" (empty outside PICO-8 buffers).
function M.statusline(bufnr)
  return require("pico8.ui").statusline(bufnr)
end

--- Token / character counts of a buffer as a table.
function M.stats(bufnr)
  return require("pico8.ui").stats(bufnr)
end

set_highlights()
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("pico8_highlights", { clear = true }),
  callback = set_highlights,
})

return M
