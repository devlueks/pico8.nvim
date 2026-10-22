-- .p8 cartridge structure: header, sections and code tabs.
--
-- A .p8 file looks like
--
--   pico-8 cartridge // http://www.pico-8.com
--   version 43
--   __lua__
--   ...code (tabs separated by "-->8" lines)...
--   __gfx__
--   ...
--
-- Plain .lua files (e.g. files pulled in with #include) are code only.
-- All line numbers in here are 0-based buffer lines.

local M = {}

M.VERSION = 43 -- cart format version written by PICO-8 0.2.7
M.HEADER = "pico-8 cartridge // http://www.pico-8.com"
M.TAB_SEPARATOR = "-->8"

M.SECTIONS = { lua = true, gfx = true, gff = true, label = true, map = true, sfx = true, music = true }

--- Returns the section name if `line` is a section header ("__gfx__" -> "gfx").
function M.section_name(line)
  local name = line:match("^__([%w:_%-%.]-)__%s*$")
  if name and (M.SECTIONS[name] or name:match("^meta:")) then
    return name
  end
end

--- Analyse the layout of a list of lines (1-based Lua list).
---@param lines string[]
---@param opts? { force_cart?: boolean }
---@return table info
---   is_cart     boolean
---   lua_line    integer|nil  line of the "__lua__" header
---   code_start  integer      first code line
---   code_end    integer      one past the last code line
---   sections    { name, line }[]
---   tabs        { index, start, stop, sep }[]  (sep = line of the "-->8" before the tab)
function M.parse(lines, opts)
  opts = opts or {}
  local info = { is_cart = false, sections = {}, tabs = {} }
  local nlines = #lines

  local lua_line
  for i, l in ipairs(lines) do
    local name = l:sub(1, 2) == "__" and M.section_name(l)
    if name then
      info.sections[#info.sections + 1] = { name = name, line = i - 1 }
      if name == "lua" and not lua_line then
        lua_line = i - 1
      end
    end
  end

  if lua_line or (lines[1] and lines[1]:find("^pico%-8 cartridge")) or opts.force_cart then
    info.is_cart = true
  end

  if info.is_cart then
    info.lua_line = lua_line
    if lua_line then
      info.code_start = lua_line + 1
      info.code_end = nlines
      for _, s in ipairs(info.sections) do
        if s.line > lua_line then
          info.code_end = s.line
          break
        end
      end
    else
      info.code_start, info.code_end = nlines, nlines
    end
  else
    info.code_start, info.code_end = 0, nlines
  end

  -- code tabs
  local tab_start, sep = info.code_start, nil
  for l = info.code_start, info.code_end - 1 do
    if lines[l + 1] == M.TAB_SEPARATOR then
      info.tabs[#info.tabs + 1] = { index = #info.tabs, start = tab_start, stop = l, sep = sep }
      tab_start, sep = l + 1, l
    end
  end
  info.tabs[#info.tabs + 1] = { index = #info.tabs, start = tab_start, stop = info.code_end, sep = sep }

  return info
end

--- The code of the cart as a single string.
function M.code_text(lines, info)
  if info.code_end <= info.code_start then
    return ""
  end
  return table.concat(lines, "\n", info.code_start + 1, info.code_end)
end

--- Which section is line `l` in? Returns "lua" for code lines, the section
--- name for data lines and "header" for the cart header.
function M.section_at(info, l)
  if not info.is_cart then
    return "lua"
  end
  local current = "header"
  for _, s in ipairs(info.sections) do
    if s.line == l then
      return "section"
    end
    if s.line < l then
      current = s.name
    else
      break
    end
  end
  return current
end

--- Tab containing line l (or nil).
function M.tab_at(info, l)
  for _, t in ipairs(info.tabs) do
    if l >= t.start and l < t.stop then
      return t
    end
  end
end

local function read_lines(path)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local data = f:read("*a")
  f:close()
  data = data:gsub("\r\n", "\n")
  local lines = vim.split(data, "\n", { plain = true })
  if lines[#lines] == "" then
    lines[#lines] = nil
  end
  return lines
end
M.read_lines = read_lines

--- The loaded buffer showing `path` (normalized absolute path), if any.
function M.find_buf(path)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) then
      local name = vim.api.nvim_buf_get_name(b)
      if name ~= "" and vim.fs.normalize(name) == path then
        return b
      end
    end
  end
end

--- Lines of a file, taken from a loaded buffer when there is one (so that
--- unsaved changes are seen), else from disk.
---@return string[]|nil lines, integer|nil bufnr
function M.file_lines(path)
  local bufnr = M.find_buf(path)
  if bufnr then
    return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), bufnr
  end
  return read_lines(path), nil
end

--- Is this a .p8 cartridge file name?
function M.is_cart_path(path)
  return path:lower():match("%.p8$") ~= nil
end

--- Code lines selected by an #include target: whole file, or a single tab
--- of a cart ("game.p8:2"). Returns lines, line_offset or nil, error.
function M.include_lines(lines, path, tab)
  if not M.is_cart_path(path) then
    return lines, 0
  end
  local info = M.parse(lines, { force_cart = true })
  local first, stop = info.code_start, info.code_end
  if tab then
    local t = info.tabs[tab + 1]
    if not t then
      return nil, ("cart has no tab %d"):format(tab)
    end
    first, stop = t.start, t.stop
  end
  local out = {}
  for l = first, stop - 1 do
    out[#out + 1] = lines[l + 1]
  end
  return out, first
end

--- A fresh cart, as written by PICO-8 0.2.7.
function M.template()
  return {
    M.HEADER,
    "version " .. M.VERSION,
    "__lua__",
    "function _init()",
    "end",
    "",
    "function _update()",
    "end",
    "",
    "function _draw()",
    " cls()",
    "end",
  }
end

return M
