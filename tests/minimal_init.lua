-- nvim --headless -u tests/minimal_init.lua ...
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
vim.opt.swapfile = false
vim.cmd("filetype plugin indent on")
vim.cmd("syntax on")
