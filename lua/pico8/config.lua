local M = {}

---@class pico8.Config
M.defaults = {
  -- Path of the PICO-8 executable for :Pico8Run (nil: search $PATH and
  -- the usual install locations)
  pico8_path = nil,
  -- extra arguments for :Pico8Run, e.g. { "-windowed", "1" }
  run_args = {},

  -- Built-in (in-process) language server "pico8": completion, hover,
  -- signature help, document symbols, go to definition, references, rename.
  -- Started with vim.lsp.enable("pico8"); fields can be overridden with
  -- vim.lsp.config("pico8", { ... }).
  lsp = {
    enabled = true,
  },

  completion = {
    -- insert required parameters as snippet placeholders: spr(${1:n}, ${2:x}, ${3:y})
    call_snippets = true,
    -- offer the bundled snippets (_init, _update, game loop, ...) in completion
    snippets = true,
    -- Neovim's built-in completion while typing, used when no completion
    -- plugin (blink.cmp, nvim-cmp, mini.completion) is installed:
    -- "auto" | true | false. With Neovim 0.12's 'autocomplete' option on,
    -- the server is added to 'complete' instead.
    native = "auto",
  },

  -- parameter names in calls of built-in functions (LSP inlay hints):
  --   rectfill(x0: 12, y0: 20, x1: 115, y1: 105, col: 0)
  inlay_hints = {
    enabled = true,
    -- also in calls of your own functions
    user_functions = false,
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
    -- show __gfx__ / __label__ data as pixels in the PICO-8 palette
    gfx_colors = true,
    -- color of black (0) pixels: "auto" uses #000000, or a dark gray when
    -- the background is too dark to tell black pixels apart; or a "#rrggbb"
    black = "auto",
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
