-- Token / character counts as virtual text and for the statusline.

local analysis = require("pico8.analysis")
local config = require("pico8.config")
local tokens = require("pico8.tokens")

local M = {}

M.ns = vim.api.nvim_create_namespace("pico8_tokens")

local function level_hl(value, limit)
  local ratio = value / limit
  if ratio > 1 then
    return "Pico8TokensError"
  elseif ratio >= config.get().tokens.warn_ratio then
    return "Pico8TokensWarn"
  end
  return "Pico8Tokens"
end

--- Counts for a buffer.
---@return table { tokens, chars, total_tokens, total_chars, token_limit, char_limit, tabs, project }
function M.stats(bufnr)
  local ctx = analysis.context(bufnr or 0)
  return {
    tokens = ctx.res.tokens,
    chars = ctx.res.chars,
    total_tokens = ctx.total_tokens,
    total_chars = ctx.total_chars,
    token_limit = tokens.TOKEN_LIMIT,
    char_limit = tokens.CHAR_LIMIT,
    tabs = ctx.res.tab_tokens,
    project = ctx.project and ctx.project.path or nil,
  }
end

--- Statusline component, e.g. "1234/8192 tokens 15%".
function M.statusline(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].filetype ~= "pico8" then
    return ""
  end
  local ok, s = pcall(M.stats, bufnr)
  if not ok then
    return ""
  end
  return ("%d/%d tokens %d%%"):format(s.total_tokens, s.token_limit, math.floor(s.total_tokens * 100 / s.token_limit))
end

function M.refresh(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  vim.api.nvim_buf_clear_namespace(bufnr, M.ns, 0, -1)
  local cfg = config.get().tokens
  if not cfg.virtual_text and not cfg.function_hints then
    return
  end
  local ctx = analysis.context(bufnr)
  local res = ctx.res
  local nlines = vim.api.nvim_buf_line_count(bufnr)

  local function mark(line, chunks)
    if line < nlines then
      vim.api.nvim_buf_set_extmark(bufnr, M.ns, line, 0, {
        virt_text = chunks,
        virt_text_pos = "eol",
        hl_mode = "combine",
        priority = 10,
      })
    end
  end

  if cfg.virtual_text then
    local anchor = res.cart.lua_line or 0
    local chunks = {
      { "  ", "Pico8Tokens" },
      { ("%d/%d tokens"):format(ctx.total_tokens, tokens.TOKEN_LIMIT), level_hl(ctx.total_tokens, tokens.TOKEN_LIMIT) },
    }
    local extra = {}
    if ctx.project then
      extra[#extra + 1] = ("%d in this file, cart %s"):format(res.tokens, vim.fs.basename(ctx.project.path))
    elseif ctx.total_tokens ~= res.tokens then
      extra[#extra + 1] = ("%d without #include"):format(res.tokens)
    end
    if #res.cart.tabs > 1 then
      extra[#extra + 1] = ("tab 0: %d"):format(res.tab_tokens[0] or 0)
    end
    if #extra > 0 then
      chunks[#chunks + 1] = { " (" .. table.concat(extra, ", ") .. ")", "Pico8Tokens" }
    end
    chunks[#chunks + 1] = { " · ", "Pico8Tokens" }
    chunks[#chunks + 1] = {
      ("%d/%d chars"):format(ctx.total_chars, tokens.CHAR_LIMIT),
      level_hl(ctx.total_chars, tokens.CHAR_LIMIT),
    }
    mark(anchor, chunks)

    for _, tab in ipairs(res.cart.tabs) do
      if tab.sep then
        mark(tab.sep, { { ("  tab %d: %d tokens"):format(tab.index, res.tab_tokens[tab.index] or 0), "Pico8TabTokens" } })
      end
    end
  end

  if cfg.function_hints then
    for _, fn in ipairs(res.parse.functions) do
      if fn.name and fn.tokens and fn.line ~= (res.cart.lua_line or -1) then
        mark(fn.line, { { ("  %d tokens"):format(fn.tokens), "Pico8FunctionTokens" } })
      end
    end
  end
end

return M
