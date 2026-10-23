-- In-process language server. Runs inside Neovim (no external binary) and
-- reads buffers directly, so every LSP-aware completion plugin
-- (blink.cmp, nvim-cmp + cmp-nvim-lsp, mini.completion, built-in
-- vim.lsp.completion) and the usual LSP keymaps (K, gd, grr, grn, gO, ...)
-- work for PICO-8 code.
--
-- It is registered with vim.lsp.config("pico8", ...) and started by
-- vim.lsp.enable("pico8") for every buffer with filetype pico8, so it shows
-- up in :checkhealth vim.lsp and can be managed with :lsp (Neovim 0.12).

local config = require("pico8.config")

local M = {}

M.name = "pico8"

local IDENT_TRIGGERS = vim.split("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_", "")

local function bufnr_of(params)
  local uri = params.textDocument and params.textDocument.uri
  if not uri then
    return nil
  end
  local bufnr = vim.uri_to_bufnr(uri)
  if not vim.api.nvim_buf_is_loaded(bufnr) then
    vim.fn.bufload(bufnr)
  end
  return bufnr
end

local function pos(params)
  return params.position.line, params.position.character
end

--- The `cmd` of the language server: creates an in-process server.
---@param dispatchers vim.lsp.rpc.Dispatchers
---@return vim.lsp.rpc.PublicClient
function M.cmd(dispatchers)
  local closing = false
  local request_id = 0
  local snippet_support = true

  local handlers = {}

  handlers["initialize"] = function(params)
    local caps = params.capabilities or {}
    local item = vim.tbl_get(caps, "textDocument", "completion", "completionItem") or {}
    snippet_support = item.snippetSupport ~= false
    return {
      capabilities = {
        positionEncoding = "utf-8",
        textDocumentSync = { openClose = false, change = 0 },
        completionProvider = { triggerCharacters = { ".", ":" }, resolveProvider = false },
        hoverProvider = true,
        signatureHelpProvider = { triggerCharacters = { "(", "," }, retriggerCharacters = { "," } },
        definitionProvider = true,
        referencesProvider = true,
        documentHighlightProvider = true,
        documentSymbolProvider = true,
        renameProvider = true,
      },
      serverInfo = { name = "pico8.nvim", version = require("pico8.api").VERSION },
    }
  end

  handlers["shutdown"] = function()
    return nil
  end

  handlers["textDocument/completion"] = function(params)
    local bufnr = bufnr_of(params)
    local items = require("pico8.completion").items(bufnr, params.position.line, params.position.character, {
      snippet_support = snippet_support,
    })
    for _, it in ipairs(items) do
      it.plain = nil
    end
    return { isIncomplete = false, items = items }
  end

  handlers["textDocument/hover"] = function(params)
    return require("pico8.hover").get(bufnr_of(params), pos(params))
  end

  handlers["textDocument/signatureHelp"] = function(params)
    return require("pico8.signature").get(bufnr_of(params), pos(params))
  end

  handlers["textDocument/definition"] = function(params)
    return require("pico8.symbols").definition(bufnr_of(params), pos(params))
  end

  handlers["textDocument/references"] = function(params)
    local l, c = pos(params)
    local incl = params.context and params.context.includeDeclaration
    return require("pico8.symbols").references(bufnr_of(params), l, c, incl)
  end

  handlers["textDocument/documentHighlight"] = function(params)
    return require("pico8.symbols").highlights(bufnr_of(params), pos(params))
  end

  handlers["textDocument/documentSymbol"] = function(params)
    return require("pico8.symbols").document_symbols(bufnr_of(params))
  end

  handlers["textDocument/rename"] = function(params)
    local l, c = pos(params)
    local edit, err = require("pico8.symbols").rename(bufnr_of(params), l, c, params.newName)
    if not edit then
      error({ code = -32602, message = err })
    end
    return edit
  end

  local srv = {}

  function srv.request(method, params, callback, notify_reply_callback)
    request_id = request_id + 1
    local id = request_id
    local handler = handlers[method]
    local err, result
    if handler then
      local ok, res = pcall(handler, params or {})
      if ok then
        result = res
      elseif type(res) == "table" and res.code then
        err = res
      else
        err = { code = -32603, message = "pico8.nvim: " .. tostring(res) }
      end
    else
      err = { code = -32601, message = "method not found: " .. method }
    end
    -- reply asynchronously, like a real server would
    vim.schedule(function()
      if notify_reply_callback then
        notify_reply_callback(id)
      end
      callback(err, result)
    end)
    return true, id
  end

  function srv.notify(method, _)
    if method == "exit" then
      closing = true
      dispatchers.on_exit(0, 15)
    end
    return true
  end

  function srv.is_closing()
    return closing
  end

  function srv.terminate()
    closing = true
  end

  return srv
end

--- Is a completion plugin installed (loaded or not yet loaded)?
local function has_completion_plugin()
  for _, mod in ipairs({ "blink.cmp", "cmp", "mini.completion", "coq" }) do
    if package.loaded[mod] then
      return true
    end
  end
  local ok, lazy = pcall(require, "lazy.core.config")
  if ok and type(lazy.plugins) == "table" then
    for _, name in ipairs({ "blink.cmp", "nvim-cmp", "mini.completion", "coq_nvim" }) do
      if lazy.plugins[name] then
        return true
      end
    end
  end
  for _, file in ipairs({ "lua/blink/cmp/init.lua", "lua/cmp/init.lua", "lua/mini/completion.lua" }) do
    if #vim.api.nvim_get_runtime_file(file, false) > 0 then
      return true
    end
  end
  return false
end

local function use_native()
  local native = config.get().completion.native
  if native == "auto" then
    return not has_completion_plugin()
  end
  return native == true
end

--- Neovim 0.12's 'autocomplete' is on for this buffer.
local function autocomplete_on(bufnr)
  if vim.fn.exists("+autocomplete") == 0 then
    return false
  end
  -- global-local option: the buffer value is nil unless set locally
  local on = vim.api.nvim_get_option_value("autocomplete", { buf = bufnr })
  if on == nil then
    on = vim.go.autocomplete
  end
  return on == true
end

--- Called on LspAttach for the pico8 client.
function M.on_attach(client, bufnr)
  if not vim.lsp.completion then
    return
  end
  local autotrigger = false
  if use_native() then
    if autocomplete_on(bufnr) then
      -- Neovim 0.12 'autocomplete': feed it from the server via 'omnifunc'
      local sources = vim.split(vim.bo[bufnr].complete, ",", { trimempty = true })
      local has_omni = vim.iter(sources):any(function(src)
        return src == "o" or vim.startswith(src, "o^")
      end)
      if not has_omni then
        vim.bo[bufnr].complete = table.concat(vim.list_extend({ "o" }, sources), ",")
      end
    else
      -- complete while typing, not only after "." and ":" (see :h lsp-autocompletion)
      local provider = client.server_capabilities.completionProvider
      if provider and #(provider.triggerCharacters or {}) <= 2 then
        vim.list_extend(provider.triggerCharacters, IDENT_TRIGGERS)
      end
      autotrigger = true
    end
  end
  -- also makes <C-y> on items from 'omnifunc' expand snippets
  vim.lsp.completion.enable(true, client.id, bufnr, { autotrigger = autotrigger })
end

--- Register the server with vim.lsp.config(); users can override any field
--- with their own vim.lsp.config("pico8", { ... }).
function M.register()
  vim.lsp.config(M.name, {
    cmd = M.cmd,
    filetypes = { "pico8" },
    offset_encoding = "utf-8",
  })
end

--- Enable or disable the server for pico8 buffers.
function M.enable(enable)
  vim.lsp.enable(M.name, enable ~= false)
end

return M
