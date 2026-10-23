-- :checkhealth pico8

local M = {}

function M.check()
  local health = vim.health
  health.start("pico8.nvim")

  local v = vim.version()
  if vim.fn.has("nvim-0.12") == 1 then
    health.ok("Neovim " .. tostring(v))
  elseif vim.fn.has("nvim-0.11") == 1 then
    health.ok("Neovim " .. tostring(v) .. " (0.12 recommended: 'autocomplete', :lsp)")
  else
    health.error("Neovim 0.11 or newer is required")
  end

  local api = require("pico8.api")
  health.info(("PICO-8 API: %s (%d functions)"):format(api.VERSION, #api.list))

  local config = require("pico8.config").get()
  local exe = require("pico8.commands").find_pico8()
  if exe then
    health.ok("PICO-8 executable: " .. exe)
  else
    health.warn("PICO-8 executable not found (only needed for :Pico8Run)", {
      "Put pico8 on your $PATH or set pico8_path in require('pico8').setup()",
    })
  end

  if vim.filetype.match({ filename = "x.p8" }) == "pico8" then
    health.ok("*.p8 files are detected as filetype pico8")
  else
    health.error("*.p8 files are not detected as pico8", { "Is ftdetect/pico8.lua on the runtimepath?" })
  end

  if config.lsp.enabled and vim.lsp.is_enabled and vim.lsp.is_enabled("pico8") then
    health.ok("language server 'pico8' is enabled (see also :checkhealth vim.lsp)")
  elseif config.lsp.enabled then
    health.ok("language server 'pico8' is configured")
  else
    health.info("language server disabled: completion via 'omnifunc' (<C-x><C-o>)")
  end
  local clients = vim.lsp.get_clients({ name = "pico8" })
  health.info(("running pico8 clients: %d"):format(#clients))

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
  elseif config.completion.native ~= false then
    if vim.fn.exists("+autocomplete") == 1 and vim.o.autocomplete then
      health.ok("Neovim 'autocomplete' is on: the server is added to 'complete' in PICO-8 buffers")
    else
      health.ok("no completion plugin: Neovim's built-in LSP completion is triggered while typing")
    end
  else
    health.info("no completion plugin and completion.native = false: use <C-x><C-o>")
  end

  local snippets = require("pico8.completion").snippets()
  if #snippets > 0 then
    health.ok(("%d snippets loaded (also available to LuaSnip / vim-vsnip via package.json)"):format(#snippets))
  else
    health.error("snippets/pico8.json could not be loaded")
  end
end

return M
