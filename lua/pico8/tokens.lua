-- PICO-8 token and character counting.
--
-- Rules (as implemented by PICO-8 and verified by shrinko8):
--   * every token counts 1, except `,` `.` `:` `;` `::` `)` `]` `}` `end`
--     `local` and comments, which are free
--   * a pair of brackets counts once (the opening bracket)
--   * a unary `-` or `~` directly attached to a number literal is part of the
--     literal (`-1` is one token), unless the previous token is a value
--     (name, number, string, `)`, `]`, `}`, `;`, `end`)

local M = {}

M.TOKEN_LIMIT = 8192
M.CHAR_LIMIT = 65535
M.COMPRESSED_LIMIT = 15360

local FREE = {
  [","] = true, ["."] = true, [":"] = true, [";"] = true, ["::"] = true,
  [")"] = true, ["]"] = true, ["}"] = true, ["end"] = true, ["local"] = true,
}

local VALUE_TYPES = { number = true, string = true, name = true }
local VALUE_ENDS = { [")"] = true, ["]"] = true, ["}"] = true, [";"] = true, ["end"] = true }

--- Is tokens[i] a unary minus/bnot that gets merged into the following number?
local function merged_sign(tokens, i)
  local t = tokens[i]
  local nxt = tokens[i + 1]
  if not nxt or nxt.type ~= "number" or t.e + 1 ~= nxt.s then
    return false
  end
  local prev = tokens[i - 1]
  if not prev then
    return false
  end
  if VALUE_TYPES[prev.type] then
    return false
  end
  if (prev.type == "op" or prev.type == "keyword") and VALUE_ENDS[prev.value] then
    return false
  end
  return true
end

--- Returns 1 if tokens[i] counts towards the token limit, else 0.
function M.weight(tokens, i)
  local t = tokens[i]
  local ty = t.type
  if ty == "eof" then
    return 0
  end
  if ty == "op" or ty == "keyword" then
    local v = t.value
    if FREE[v] then
      return 0
    end
    if (v == "-" or v == "~") and merged_sign(tokens, i) then
      return 0
    end
  end
  return 1
end

--- Count tokens in tokens[from..to] (inclusive).
function M.count(tokens, from, to)
  from = from or 1
  to = to or #tokens
  local n = 0
  for i = from, to do
    n = n + M.weight(tokens, i)
  end
  return n
end

-- Non-ASCII P8SCII characters as they appear in .p8 files (UTF-8).
-- ⬇️ ⬅️ 🅾️ ➡️ ⬆️ carry a variation selector (U+FE0F) and are still one char.
local P8SCII_LIST = "¹ ² ³ ⁴ ⁵ ⁶ ⁷ ⁸ ᵇ ᶜ ᵉ ᶠ ▮ ■ □ ⁙ ⁘ ‖ ◀ ▶ 「 」 ¥ • 、 。 ゛ ゜ ○ "
  .. "█ ▒ 🐱 ⬇️ ░ ✽ ● ♥ ☉ 웃 ⌂ ⬅️ 😐 ♪ 🅾️ ◆ … ➡️ ★ ⧗ ⬆️ ˇ ∧ ❎ ▤ ▥ "
  .. "あ い う え お か き く け こ さ し す せ そ た ち つ て と な に ぬ ね の は ひ ふ へ ほ "
  .. "ま み む め も や ゆ よ ら り る れ ろ わ を ん っ ゃ ゅ ょ "
  .. "ア イ ウ エ オ カ キ ク ケ コ サ シ ス セ ソ タ チ ツ テ ト ナ ニ ヌ ネ ノ ハ ヒ フ ヘ ホ "
  .. "マ ミ ム メ モ ヤ ユ ヨ ラ リ ル レ ロ ワ ヲ ン ッ ャ ュ ョ ◜ ◝ "
  -- "puny font" capitals as PICO-8 writes them when copying
  .. "𝘢 𝘣 𝘤 𝘥 𝘦 𝘧 𝘨 𝘩 𝘪 𝘫 𝘬 𝘭 𝘮 𝘯 𝘰 𝘱 𝘲 𝘳 𝘴 𝘵 𝘶 𝘷 𝘸 𝘹 𝘺 𝘻"

M.P8SCII = {}
for ch in P8SCII_LIST:gmatch("%S+") do
  M.P8SCII[ch] = true
end

local byte, sub = string.byte, string.sub

local function cp_len(b)
  if b >= 0xF0 then
    return 4
  elseif b >= 0xE0 then
    return 3
  elseif b >= 0xC0 then
    return 2
  end
  return 1
end

--- Number of PICO-8 characters in a UTF-8 encoded string, using the same
--- conversion PICO-8 applies when loading a .p8 file: known P8SCII glyphs
--- are one character, anything else counts one character per byte.
function M.chars(text)
  if not text:find("[\128-\255]") then
    return #text
  end
  local n, i, len = 0, 1, #text
  local skip_next = false
  while i <= len do
    local b = byte(text, i)
    if b < 0x80 then
      n = n + 1
      i = i + 1
    else
      local l = cp_len(b)
      local ch = sub(text, i, i + l - 1)
      if M.P8SCII[ch] then
        n = n + 1
      elseif skip_next then
        skip_next = false
      else
        local nb = byte(text, i + l)
        local pair = nb and (ch .. sub(text, i + l, i + l + cp_len(nb) - 1))
        if pair and M.P8SCII[pair] then
          n = n + 1
          skip_next = true
        else
          n = n + l
        end
      end
      i = i + l
    end
  end
  return n
end

return M
