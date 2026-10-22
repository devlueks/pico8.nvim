-- In-process language server. Runs inside Neovim (no external binary) and
-- reads buffers directly, so every LSP-aware completion plugin
-- (blink.cmp, nvim-cmp + cmp-nvim-lsp, mini.completion, built-in
-- vim.lsp.completion) and the usual LSP keymaps (K, gd, grr, grn, gO, ...)
-- work for PICO-8 code.

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

--- Create the server; `opts.native` adds identifier trigger characters
--- for Neovim's built-in auto completion.
function M.server(opts)
  opts = opts or {}
  return function(dispatchers)
    local closing = false
    local request_id = 0
    local snippet_support = true

    local handlers = {}

    handlers["initialize"] = function(params)
      local caps = params.capabilities or {}
      local item = vim.tbl_get(caps, "textDocument", "completion", "completionItem") or {}
      snippet_support = item.snippetSupport ~= false
      local triggers = { ".", ":" }
      if opts.native then
        vim.list_extend(triggers, IDENT_TRIGGERS)
      end
      return {
        capabilities = {
          positionEncoding = "utf-8",
          textDocumentSync = { openClose = false, change = 0 },
          completionProvider = { triggerCharacters = triggers, resolveProvider = false },
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
end

local function has_completion_plugin()
  return package.loaded["cmp"] ~= nil or package.loaded["blink.cmp"] ~= nil or package.loaded["mini.completion"] ~= nil
end

local function use_native()
  local native = config.get().completion.native
  if native == "auto" then
    return vim.lsp.completion ~= nil and not has_completion_plugin()
  end
  return native == true and vim.lsp.completion ~= nil
end

--- Start (or reuse) the client and attach it to bufnr.
function M.attach(bufnr)
  if not config.get().lsp.enabled then
    return
  end
  local native = use_native()
  local name = vim.api.nvim_buf_get_name(bufnr)
  local client_id = vim.lsp.start({
    name = M.name,
    cmd = M.server({ native = native }),
    root_dir = name ~= "" and vim.fs.dirname(name) or vim.fn.getcwd(),
    offset_encoding = "utf-8",
  }, {
    bufnr = bufnr,
    reuse_client = function(client, conf)
      return client.name == conf.name
    end,
  })
  if client_id and native then
    pcall(vim.lsp.completion.enable, true, client_id, bufnr, { autotrigger = true })
  end
  return client_id
end

return M
