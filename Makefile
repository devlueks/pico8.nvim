NVIM ?= nvim

.PHONY: test
test:
	$(NVIM) --headless -u tests/minimal_init.lua -c "luafile tests/run.lua"
