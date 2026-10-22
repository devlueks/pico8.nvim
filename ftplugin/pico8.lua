if vim.b.did_ftplugin or vim.fn.has("nvim-0.10") == 0 then
  return
end
vim.b.did_ftplugin = 1

local bo = vim.bo
bo.commentstring = "-- %s"
bo.comments = ":--,://"
bo.suffixesadd = ".lua,.p8"
-- [i, [d, gf etc. follow #include lines
bo.include = [[^\s*#include\s\+]]
bo.formatoptions = bo.formatoptions:gsub("t", "") .. "croql"

vim.b.undo_ftplugin = "setlocal commentstring< comments< suffixesadd< include< formatoptions< omnifunc<"

require("pico8").attach(0)
