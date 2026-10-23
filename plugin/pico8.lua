if vim.g.loaded_pico8 then
  return
end
vim.g.loaded_pico8 = true

if vim.fn.has("nvim-0.11") == 0 then
  vim.notify_once("pico8.nvim requires Neovim 0.11 or newer (0.12 recommended)", vim.log.levels.ERROR)
  return
end

-- Built-in language server (completion, hover, signature help, symbols, ...):
-- registered like any other server, so `vim.lsp.config("pico8", {...})`,
-- `vim.lsp.enable("pico8", false)`, :checkhealth vim.lsp and :lsp work.
require("pico8.lsp").register()
require("pico8.lsp").enable(require("pico8.config").get().lsp.enabled)

vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("pico8_lsp", { clear = true }),
  callback = function(ev)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if client and client.name == "pico8" then
      require("pico8.lsp").on_attach(client, ev.buf)
    end
  end,
})

local function cmds()
  return require("pico8.commands")
end

vim.api.nvim_create_user_command("Pico8Tokens", function(o)
  if o.range > 0 then
    cmds().tokens(0, o.line1, o.line2)
  else
    cmds().tokens(0)
  end
end, { range = true, desc = "PICO-8: token / char count report (or count of the selected lines)" })

vim.api.nvim_create_user_command("Pico8Run", function()
  cmds().run(0)
end, { desc = "PICO-8: save and run the cart in PICO-8" })

vim.api.nvim_create_user_command("Pico8Docs", function(o)
  cmds().docs(o.args)
end, {
  nargs = "?",
  complete = function(lead)
    return vim.tbl_filter(function(n)
      return vim.startswith(n, lead)
    end, cmds().doc_names())
  end,
  desc = "PICO-8: API documentation (cheat sheet without argument)",
})

vim.api.nvim_create_user_command("Pico8Toggle", function(o)
  local config = require("pico8.config").get()
  local what = o.args
  if what == "inlay_hints" then
    config.inlay_hints.enabled = not config.inlay_hints.enabled
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].filetype == "pico8" then
        require("pico8.lsp").set_inlay_hints(b, config.inlay_hints.enabled)
      end
    end
    return
  elseif what == "diagnostics" then
    config.diagnostics.enabled = not config.diagnostics.enabled
  elseif what == "function_hints" then
    config.tokens.function_hints = not config.tokens.function_hints
  elseif what == "virtual_text" or what == "" then
    config.tokens.virtual_text = not config.tokens.virtual_text
  else
    vim.notify("pico8: unknown option " .. what, vim.log.levels.ERROR)
    return
  end
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].filetype == "pico8" then
      require("pico8").refresh(b, 0)
    end
  end
end, {
  nargs = "?",
  complete = function()
    return { "virtual_text", "function_hints", "inlay_hints", "diagnostics" }
  end,
  desc = "PICO-8: toggle token virtual text, function token hints, parameter name hints or diagnostics",
})
