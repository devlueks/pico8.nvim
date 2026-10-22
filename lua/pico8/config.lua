local M = {}

---@class pico8.Config
M.defaults = {
  -- Path of the PICO-8 executable for :Pico8Run (nil: search $PATH and
  -- the usual install locations)
  pico8_path = nil,
  -- extra arguments for :Pico8Run, e.g. { "-windowed", "1" }
  run_args = {},

  -- Built-in (in-process) language server: completion, hover,
  -- signature help, document symbols, go to definition, references, rename.
  lsp = {
    enabled = true,
  },

  completion = {
    -- insert required parameters as snippet placeholders: spr(${1:n}, ${2:x}, ${3:y})
    call_snippets = true,
    -- offer the bundled snippets (_init, _update, game loop, ...) in completion
    snippets = true,
    -- Neovim 0.11+ built-in completion with auto-trigger when neither
    -- nvim-cmp nor blink.cmp is installed: "auto" | true | false
    native = "auto",
  },

  diagnostics = {
    enabled = true,
    debounce = 250, -- ms
    undefined_globals = true,
    unused = true, -- unused locals and local functions
    unused_params = true, -- an unused last parameter (it costs a token)
    unused_loop_vars = false,
    arg_count = true, -- too many arguments for an API function
    -- globals defined elsewhere (e.g. by code the plugin can't see)
    globals = {},
  },

  tokens = {
    -- token / char counts as virtual text on the __lua__ line and on
    -- every "-->8" tab separator
    virtual_text = true,
    -- token count of each function at the end of its first line
    function_hints = false,
    -- warn (highlight) when this fraction of a limit is used
    warn_ratio = 0.9,
  },

  highlight = {
    -- show __gfx__ / __label__ data in the PICO-8 palette
    gfx_colors = true,
  },

  -- insert a cart skeleton into new, empty .p8 files
  template = true,
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  return M.options
end

function M.get()
  return M.options
end

return M
