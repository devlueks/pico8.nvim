" Vim indent file
" Language: PICO-8 Lua
" Based on the Lua indent script shipped with Vim/Neovim, extended for
" PICO-8's one-line shorthand `if (cond) stmt` / `while (cond) stmt`.

if exists("b:did_indent")
  finish
endif
let b:did_indent = 1

setlocal indentexpr=GetPico8Indent()
setlocal indentkeys+=0=end,0=until,0=elseif,0=else
setlocal autoindent

let b:undo_indent = "setlocal autoindent< indentexpr< indentkeys<"

if exists("*GetPico8Indent")
  finish
endif

function! s:InComment(lnum, col) abort
  let name = synIDattr(synID(a:lnum, a:col, 1), "name")
  return name =~# 'pico8\%(Comment\|String\|LongString\)'
endfunction

function! GetPico8Indent() abort
  let ignorecase_save = &ignorecase
  try
    let &ignorecase = 0
    return s:Indent()
  finally
    let &ignorecase = ignorecase_save
  endtry
endfunction

function! s:Indent() abort
  let prevlnum = prevnonblank(v:lnum - 1)
  if prevlnum == 0
    return 0
  endif
  " don't indent cart data or section headers
  if getline(v:lnum) =~# '^__\w\+__$'
    return 0
  endif

  let ind = indent(prevlnum)
  let prevline = getline(prevlnum)

  " drop trailing comments
  let code = substitute(prevline, '\s*\%(--\|//\).*$', '', '')

  let midx = match(code, '^\s*\%(if\>\|for\>\|while\>\|repeat\>\|else\>\|elseif\>\|do\>\|then\>\)')
  if midx == -1
    let midx = match(code, '\%({\|(\)\s*$')
    if midx == -1
      let midx = match(code, '\<function\>\s*\%(\k\|[.:]\)\{-}\s*(')
    endif
  endif

  if midx != -1 && !s:InComment(prevlnum, midx + 1) && code !~# '\<end\>\|\<until\>'
    " shorthand `if (cond) stmt` / `while (cond) stmt`: no block follows
    let short = code =~# '^\s*\%(if\|while\)\s*(.*)\s*\S' && code !~# '\<\%(then\|do\)\>'
    if !short
      let ind += shiftwidth()
    endif
  endif

  let midx = match(getline(v:lnum), '^\s*\%(end\>\|else\>\|elseif\>\|until\>\|}\|)\)')
  if midx != -1 && !s:InComment(v:lnum, midx + 1)
    let ind -= shiftwidth()
  endif

  return max([ind, 0])
endfunction
