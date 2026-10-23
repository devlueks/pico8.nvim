# pico8.nvim

[PICO-8](https://www.lexaloffle.com/pico-8.php) **0.2.7** support for Neovim:
token count, completion, snippets, syntax highlighting and diagnostics.
Pure Lua, no external programs.

![pico8.nvim](doc/screenshot.png)

## Features

- **Token count**, using PICO-8's own rules (verified against
  [shrinko8](https://github.com/thisismypassport/shrinko8), including carts with more than 8000 tokens):
  - total `1234/8192 tokens · 5678/65535 chars` as virtual text on the `__lua__` line
  - tokens per code tab on every `-->8` line, optionally per function
  - code pulled in with `#include` is counted, like PICO-8 does when running the cart
  - `:Pico8Tokens` report (most expensive functions), `:'<,'>Pico8Tokens` for a selection
  - statusline component `require("pico8").statusline()`
- **Completion** from a built-in, in-process language server (no external binary).
  Works with blink.cmp, nvim-cmp (+ cmp-nvim-lsp), mini.completion, Neovim's built-in
  LSP completion, 0.12's `'autocomplete'` and `<C-x><C-o>`:
  - the PICO-8 0.2.7 API (only functions that carts can call) with signatures and documentation
  - placeholders for required arguments: `spr(${1:n}, ${2:x}, ${3:y})`
  - callbacks `_init`, `_update`, `_update60`, `_draw`
  - button glyphs by name: `left` → `⬅️`, `xbutton` → `❎`
  - your own functions and variables, also from `#include`d files, and table fields after `.` / `:`
  - file names after `#include `
- **Snippets** for language constructs and single API calls: game loop, cart skeleton, callbacks,
  `if`/`for`/`while` variants, `for o in all(t)`, `btnp`, `menuitem`, `cartdata`, coroutines,
  `fillp`, outlined (`\^o`) and underlined (`\^u`) text (new in 0.2.7), `#include`, `-->8` …
  Offered by the completion and also shipped as VSCode snippets (`package.json`) for LuaSnip & co.
- **Syntax highlighting** for `.p8` carts:
  - PICO-8 Lua: `!=`, `+=`, `..=`, `\`, `^^`, `>>>`, `<<>`, `>><`, `@ % $`, the `?` shorthand,
    `//` comments, hex/binary numbers with fractions, glyphs, `#include`, labels
  - P8SCII control codes in strings (`\f8`, `\#1`, `\^w`, `\^o8ff`, `\^u` …)
  - cart sections; `__gfx__` and `__label__` data is drawn as pixels in the PICO-8 palette
    (black pixels stay visible on black backgrounds)
- **Diagnostics**:
  - syntax errors (including PICO-8 shorthands, `goto`/labels, `break`, `...`)
  - token and character limit exceeded
  - undefined globals with suggestions: `circfil` → `circfill`, `Spr` → `spr`, `⬅` → `⬅️`
  - Lua standard library functions PICO-8 doesn't have: `math.floor` → `flr(x)`, `table.insert` → `add` …
  - `score += 1` while `score` is never assigned
  - too many arguments for API functions
  - unused locals / local functions / last parameters (each one costs tokens)
  - missing `#include` files and errors inside them
- **More**: hover documentation (`K`) including the token cost of your functions, hex/binary values
  of numbers, memory addresses (`0x5f2d` …) and `stat(n)` meanings; signature help; go to definition
  (also into `#include`d files); references; rename; document symbols grouped by tab; `:Pico8Run`;
  indentation that understands the one-line `if (cond) stmt`; `:checkhealth pico8`.

All documentation is plain text, so it looks right in every completion menu and hover window.

## Requirements

- Neovim **0.12** recommended (tested with 0.12.6); 0.11 works too
- optional: PICO-8 for `:Pico8Run`

## Installation

With Neovim 0.12's built-in plugin manager:

```lua
vim.pack.add({ "https://github.com/USERNAME/pico8.nvim" })
```

[lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "USERNAME/pico8.nvim",
  ft = "pico8",
  opts = {}, -- optional, see Configuration
}
```

Calling `setup()` is optional, the defaults work out of the box.

`*.p8` files (carts) and `*.p8.lua` files (code for `#include`) get the filetype `pico8`.
A `.p8` file does not need a `__lua__` section: without one, the whole file (after the optional
`pico-8 cartridge` / `version` header, up to the first data section) is treated as code.
For other `.lua` files:

```lua
vim.filetype.add({ pattern = { [".*/my_game/.*%.lua"] = "pico8" } })
```

## Configuration

Defaults:

```lua
require("pico8").setup({
  pico8_path = nil,        -- PICO-8 executable for :Pico8Run (nil: $PATH and the usual places)
  run_args = {},           -- e.g. { "-windowed", "1" }

  lsp = { enabled = true }, -- built-in language server "pico8"

  completion = {
    call_snippets = true,  -- insert required arguments as placeholders
    snippets = true,       -- offer the snippets in the completion menu
    native = "auto",       -- built-in completion while typing when no completion plugin is installed
  },

  diagnostics = {
    enabled = true,
    debounce = 250,
    undefined_globals = true,
    unused = true,
    unused_params = true,     -- an unused last parameter
    unused_loop_vars = false,
    arg_count = true,
    globals = {},             -- extra known globals
  },

  tokens = {
    virtual_text = true,      -- counts on __lua__ and -->8
    function_hints = false,   -- token count of every function
    warn_ratio = 0.9,         -- highlight counts as a warning from 90 % of a limit
  },

  highlight = {
    gfx_colors = true,        -- __gfx__ / __label__ as pixels in the PICO-8 palette
    black = "auto",           -- color of black pixels: "auto" or "#rrggbb"
  },

  template = true,            -- fill new, empty .p8 files with a cart skeleton
})
```

### Language server

The server is registered with `vim.lsp.config("pico8", ...)` and started with
`vim.lsp.enable("pico8")`, so the usual tools work: `:checkhealth vim.lsp`, and in Neovim 0.12
`:lsp restart pico8` etc. Any field can be overridden:

```lua
vim.lsp.config("pico8", { on_attach = function(client, bufnr) ... end })
```

### Completion

- **blink.cmp**: works as is (the LSP source is enabled by default).
- **nvim-cmp**: needs [cmp-nvim-lsp](https://github.com/hrsh7th/cmp-nvim-lsp) with the `nvim_lsp` source.
- **No completion plugin**: Neovim's built-in LSP completion pops up while typing
  (`completion.native = "auto"`). With Neovim 0.12's `'autocomplete'` option on, the server is
  added to `'complete'` instead, so it shows up in the same menu.
- **LuaSnip**: `require("luasnip.loaders.from_vscode").lazy_load()` loads the snippets from
  `package.json`. Set `completion = { snippets = false }` to avoid seeing them twice.

### Keymaps

The default LSP keymaps apply, e.g. `K` (hover), `grn` (rename), `grr` (references),
`gO` (document symbols) and `<C-s>` in insert mode (signature help). For example:

```lua
vim.api.nvim_create_autocmd("FileType", {
  pattern = "pico8",
  callback = function(ev)
    vim.keymap.set("n", "gd", vim.lsp.buf.definition, { buf = ev.buf })
    vim.keymap.set("n", "<leader>r", "<cmd>Pico8Run<cr>", { buf = ev.buf })
  end,
})
```

(Neovim 0.11: use `buffer = ev.buf`.)

### Statusline

```lua
-- lualine
sections = { lualine_x = { function() return require("pico8").statusline() end } }
-- or your own format:
local s = require("pico8").stats() -- { tokens, total_tokens, chars, total_chars, tabs, ... }
```

## Commands

| Command | Description |
| --- | --- |
| `:Pico8Tokens` | token / character report with tabs, `#include`s and the most expensive functions |
| `:'<,'>Pico8Tokens` | tokens of the selected lines |
| `:Pico8Run` | save and run the cart in PICO-8 (for a `.lua` file: the cart that includes it) |
| `:Pico8Docs [name]` | API documentation in a float; without an argument a cheat sheet. Also `:Pico8Docs stat` / `memory` |
| `:Pico8Toggle [virtual_text\|function_hints\|diagnostics]` | toggle what is shown |

## Diagnostics

| Code | Meaning |
| --- | --- |
| `syntax` | syntax error (the first one, like PICO-8) |
| `token-limit` / `char-limit` | more than 8192 tokens / 65535 characters (including `#include`) |
| `include` | `#include` file is missing or contains an error |
| `undefined-global` | a global that is read but never assigned |
| `stdlib` | Lua standard library (`math`, `string`, `table`, `require`, …) does not exist in PICO-8 |
| `arg-count` | too many arguments for an API function |
| `unused` | unused locals, local functions, last parameters |

Globals the plugin can't see can be declared in the code (compatible with shrinko8):

```lua
--lint: my_global, other_global
```

Globals from `#include`d files are known automatically. For a `.lua` file the plugin looks for the
`.p8` cart that includes it (in the same and in the parent directory) and then knows that cart's
globals, the globals of its other includes and the cart's total token count.

The API covers the functions of the 0.2.7 manual's API reference that a cart can call. Console
commands (`save`, `folder`, `reboot`, …) are left out. A few undocumented globals that exist at
runtime (`ipairs`, `next`, `unpack`, …) are not offered anywhere, but using them is not reported
as an error either.

## How tokens are counted

Like PICO-8: every name, literal and operator counts 1. Free are `,` `.` `:` `;` `::`, closing
brackets `)` `]` `}`, `end`, `local` and comments. A `-` or `~` directly in front of a number
belongs to the number (`x=-1` is 3 tokens, `a - 1` is 3 as well, but `x = - 1` is 4).
Characters are counted in P8SCII (`⬅️` is one character). The compressed size for `.p8.png`
(limit 15360 bytes) is only computed by PICO-8 itself (`INFO`).

## Tips

- PICO-8 reloads a `.p8` file changed by another editor on `CTRL-R`, as long as there are no unsaved
  changes in PICO-8's own editors.
- Put code into `.lua` files and `#include` them: tokens, completion, hover and go to definition
  work across files.
- `gf` on the file name of an `#include` line opens that file.

## Tests

```sh
make test
# or
nvim --headless -u tests/minimal_init.lua -c "luafile tests/run.lua"
```

## License

MIT
