-- :checkhealth pico8

local M = {}

function M.check()
  local health = vim.health
  health.start("pico8.nvim")

  if vim.fn.has("nvim-0.10") == 1 then
    health.ok("Neovim " .. tostring(vim.version()))
  else
    health.error("Neovim 0.10 or newer is required")
  end

  local api = require("pico8.api")
  health.info(("PICO-8 API: %s (%d functions)"):format(api.VERSION, vim.tbl_count(api.functions)))

  local config = require("pico8.config").get()
  local exe = require("pico8.commands").find_pico8()
  if exe then
    health.ok("PICO-8 executable: " .. exe)
  else
    health.warn("PICO-8 executable not found (only needed for :Pico8Run)", {
      "Put pico8 on your $PATH or set `pico8_path` in require('pico8').setup()",
    })
  end

  if vim.filetype.match({ filename = "x.p8" }) == "pico8" then
    health.ok("*.p8 files are detected as filetype pico8")
  else
    health.error("*.p8 files are not detected as pico8", { "Is ftdetect/pico8.lua on the runtimepath?" })
  end

  if config.lsp.enabled then
    health.ok("built-in language server enabled (completion, hover, signature help, symbols, rename)")
    local clients = vim.lsp.get_clients({ name = "pico8" })
    health.info(("pico8 language server clients running: %d"):format(#clients))
  else
    health.info("built-in language server disabled: completion via omnifunc (<C-x><C-o>)")
  end

  local plugins = {}
  if package.loaded["blink.cmp"] then
    plugins[#plugins + 1] = "blink.cmp"
  end
  if package.loaded["cmp"] then
    plugins[#plugins + 1] = "nvim-cmp" .. (package.loaded["cmp_nvim_lsp"] and " + cmp-nvim-lsp" or "")
    if not package.loaded["cmp_nvim_lsp"] then
      health.warn("nvim-cmp is loaded without cmp-nvim-lsp: PICO-8 completion needs the 'nvim_lsp' source")
    end
  end
  if #plugins > 0 then
    health.ok("completion plugin: " .. table.concat(plugins, ", "))
  elseif vim.lsp.completion then
    health.info("no completion plugin found: using Neovim's built-in LSP completion (completion.native)")
  else
    health.info("no completion plugin found: use <C-x><C-o>")
  end

  local snippets = require("pico8.completion").snippets()
  if #snippets > 0 then
    health.ok(("%d snippets loaded (also available to LuaSnip / vsnip via package.json)"):format(#snippets))
  else
    health.error("snippets/pico8.json could not be loaded")
  end
end

return M
