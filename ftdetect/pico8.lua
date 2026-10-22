vim.filetype.add({
  extension = {
    p8 = "pico8",
  },
  pattern = {
    -- code meant to be #included into a cart
    [".*%.p8%.lua"] = "pico8",
  },
})
