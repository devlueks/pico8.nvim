" Vim syntax file
" Language: PICO-8 0.2.7 (.p8 cartridges and PICO-8 Lua)

if exists("b:current_syntax")
  finish
endif

let s:cpo_save = &cpo
set cpo&vim

syn case match
" carts are small and data sections are long regions: always sync from the start
syn sync fromstart

" ---------------------------------------------------------------------------
" Lua (PICO-8 dialect)
" ---------------------------------------------------------------------------

" Operators come first: for items starting at the same position the one
" defined last wins, so comments (--, //) must be defined after - and /.
" PICO-8 adds \ ^^ >>> <<> >>< != @ % $ and compound assignments.
syn match   pico8Operator "[-+*/%^#@$&|~<>=!\\]"
syn match   pico8Operator "\.\.\.\="
syn match   pico8PrintShorthand "^\s*\zs?"
syn match   pico8PrintShorthand "\%([;)=]\|\<then\|\<else\|\<do\)\s*\zs?"

syn keyword pico8Todo contained TODO FIXME XXX NOTE HACK BUG todo fixme

syn match   pico8Comment "--.*$" contains=pico8Todo,@Spell
syn match   pico8Comment "//.*$" contains=pico8Todo,@Spell
syn region  pico8Comment matchgroup=pico8Comment start="--\[\z(=*\)\[" end="\]\z1\]" contains=pico8Todo,@Spell
" code tab separator
syn match   pico8TabSeparator "^-->8$"

syn keyword pico8Statement return break goto
syn keyword pico8Local local
syn keyword pico8Conditional if then else elseif
syn keyword pico8Repeat for while repeat until in do
syn keyword pico8End end
syn keyword pico8Operator and or not
syn keyword pico8Boolean true false
syn keyword pico8Nil nil
syn keyword pico8Self self
syn keyword pico8Callback _init _update _update60 _draw
syn keyword pico8Special _ENV

syn keyword pico8FunctionKw function nextgroup=pico8FuncName skipwhite
syn match   pico8FuncName "[[:alpha:]_][[:alnum:]_]*\%([.:][[:alpha:]_][[:alnum:]_]*\)*" contained contains=pico8Callback

syn match   pico8FuncCall "\<[[:alpha:]_][[:alnum:]_]*\ze\s*("

" built-in API functions (generated from lua/pico8/api.lua)
let s:builtins = luaeval('require("pico8.api").builtin_function_names()')
execute 'syn keyword pico8Builtin ' . join(s:builtins, ' ')

syn match   pico8Metamethod "\<__\%(index\|newindex\|call\|add\|sub\|mul\|div\|idiv\|mod\|pow\|unm\|concat\|len\|eq\|lt\|le\|tostring\|gc\|mode\|metatable\|band\|bor\|bxor\|bnot\|shl\|shr\|lshr\|rotl\|rotr\|close\)\>"

" button glyphs and fill pattern glyphs (P8SCII 0x80..0x99)
syn match   pico8Button "\%(⬅️\|➡️\|⬆️\|⬇️\|🅾️\|❎\)"
syn match   pico8Glyph  "[█▒🐱░✽●♥☉웃⌂😐♪◆…★⧗ˇ∧▤▥]"

syn match   pico8Label "::[[:alpha:]_][[:alnum:]_]*::"

" numbers: decimal, hex and binary with fractional parts
syn match   pico8Number "\<\d\+\%(\.\d*\)\="
syn match   pico8Number "\%([[:alnum:]_.]\)\@<!\.\d\+"
syn match   pico8Number "\<0[xX]\x*\%(\.\x*\)\="
syn match   pico8Number "\<0[bB][01]*\%(\.[01]*\)\="

" strings with Lua and P8SCII escapes
syn match   pico8Escape contained +\\\%([abfnrtvz\\"'\n]\|x\x\x\|\d\{1,3}\)+
" P8SCII control codes: \* \# \- \| take one parameter, \+ two, \f colour,
" \v decoration, \^ special commands (incl. 0.2.7: \^o outline, \^u
" underline, \^, \^; one-off characters that respect padding)
syn match   pico8P8scii contained "\\[*#|-][0-9a-zA-Z]"
syn match   pico8P8scii contained "\\+[0-9a-zA-Z]\{2}"
syn match   pico8P8scii contained "\\f[0-9a-zA-Z]"
syn match   pico8P8scii contained "\\v[0-9a-zA-Z]."
syn match   pico8P8scii contained "\\a\%(\d\{1,2}\)\="
syn match   pico8P8scii contained "\\^\%([1-9gh]\|[cdrsxy][0-9a-zA-Z]\|j[0-9a-zA-Z]\{2}\|-\=[wt=pibu#]\|o[0-9a-zA-Z$!]\x\x\|[:;]\x\{16}\|[.,].\{8}\|@\x\{8}\|!\x\{4}\)"
syn region  pico8String start=+"+ skip=+\\\\\|\\"+ end=+"+ end=+$+ contains=pico8Escape,pico8P8scii,@Spell
syn region  pico8String start=+'+ skip=+\\\\\|\\'+ end=+'+ end=+$+ contains=pico8Escape,pico8P8scii,@Spell
syn region  pico8LongString start="\[\z(=*\)\[" end="\]\z1\]" contains=@Spell

" #include directives
syn match   pico8Include "^\s*#include\>" nextgroup=pico8IncludeFile skipwhite
syn match   pico8IncludeFile ".*$" contained

" ---------------------------------------------------------------------------
" Cartridge structure
" ---------------------------------------------------------------------------

syn match   pico8CartHeader "\%1l^pico-8 cartridge.*$"
syn match   pico8CartVersion "\%2l^version \d\+$"
syn match   pico8Section "^__\%(lua\|gfx\|gff\|label\|map\|sfx\|music\|meta:[^_ ]*\)__$"

let s:next = '^\ze__\%(lua\|gfx\|gff\|label\|map\|sfx\|music\|meta:[^_ ]*\)__$'

if luaeval('require("pico8.config").get().highlight.gfx_colors')
  execute 'syn region pico8Gfx matchgroup=pico8Section start="^__gfx__$" end="' . s:next . '" contains=@pico8Pixels'
  execute 'syn region pico8LabelData matchgroup=pico8Section start="^__label__$" end="' . s:next . '" contains=@pico8Pixels,@pico8SecretPixels'
  for s:c in split('0123456789abcdef', '\zs')
    execute 'syn match pico8Px' . s:c . ' "' . s:c . '" contained'
    execute 'syn cluster pico8Pixels add=pico8Px' . s:c
  endfor
  for s:c in split('ghijklmnopqrstuv', '\zs')
    execute 'syn match pico8Px' . s:c . ' "' . s:c . '" contained'
    execute 'syn cluster pico8SecretPixels add=pico8Px' . s:c
  endfor
else
  execute 'syn region pico8Data matchgroup=pico8Section start="^__\%(gfx\|label\)__$" end="' . s:next . '"'
endif
execute 'syn region pico8Data matchgroup=pico8Section start="^__\%(gff\|map\|sfx\|music\)__$" end="' . s:next . '"'
execute 'syn region pico8Meta matchgroup=pico8Section start="^__meta:[^_ ]*__$" end="' . s:next . '"'

" ---------------------------------------------------------------------------
" Highlight links
" ---------------------------------------------------------------------------

hi def link pico8Comment        Comment
hi def link pico8Todo           Todo
hi def link pico8TabSeparator   Title
hi def link pico8Statement      Statement
hi def link pico8Local          Keyword
hi def link pico8Conditional    Conditional
hi def link pico8Repeat         Repeat
hi def link pico8End            Keyword
hi def link pico8Operator       Operator
hi def link pico8Boolean        Boolean
hi def link pico8Nil            Constant
hi def link pico8Self           Special
hi def link pico8Special        Special
hi def link pico8Callback       Special
hi def link pico8FunctionKw     Keyword
hi def link pico8FuncName       Function
hi def link pico8FuncCall       Function
hi def link pico8Builtin        Function
hi def link pico8Metamethod     Special
hi def link pico8Button         Constant
hi def link pico8Glyph          Constant
hi def link pico8PrintShorthand Function
hi def link pico8Label          Label
hi def link pico8Number         Number
hi def link pico8String         String
hi def link pico8LongString     String
hi def link pico8Escape         SpecialChar
hi def link pico8P8scii         SpecialChar
hi def link pico8Include        Include
hi def link pico8IncludeFile    String
hi def link pico8CartHeader     PreProc
hi def link pico8CartVersion    PreProc
hi def link pico8Section        Title
hi def link pico8Data           Comment
hi def link pico8Meta           Comment

" pixel colours (pico8Px0..pico8Pxv) are defined in Lua so that they
" survive colorscheme changes
lua require("pico8")

let b:current_syntax = "pico8"

let &cpo = s:cpo_save
unlet s:cpo_save
