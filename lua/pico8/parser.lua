-- Recursive descent parser for PICO-8 Lua with scope analysis.
--
-- Accepts the PICO-8 dialect: shorthand `if (cond) stmt [else stmt]` and
-- `while (cond) stmt` on one line, `if cond do`, compound assignment
-- operators, `?` print shorthand, `!=` and the extra operators with PICO-8's
-- precedence table. Reports the first syntax error (like PICO-8 does) and
-- collects what the editor features need: global definitions and uses,
-- locals with their references, function definitions and API calls.

local M = {}

local BINARY = {
  ["or"] = 1, ["and"] = 2,
  ["<"] = 3, [">"] = 3, ["<="] = 3, [">="] = 3, ["~="] = 3, ["!="] = 3, ["=="] = 3,
  ["|"] = 4, ["^^"] = 5, ["~"] = 5, ["&"] = 6,
  ["<<"] = 7, [">>"] = 7, [">>>"] = 7, ["<<>"] = 7, [">><"] = 7,
  [".."] = 8,
  ["+"] = 9, ["-"] = 9,
  ["*"] = 10, ["/"] = 10, ["\\"] = 10, ["%"] = 10,
  ["^"] = 12,
}
local RIGHT = { [".."] = true, ["^"] = true }
local UNARY = { ["-"] = true, ["~"] = true, ["not"] = true, ["#"] = true, ["@"] = true, ["%"] = true, ["$"] = true }
local UNARY_PREC = 11

M.COMPOUND = {
  ["+="] = true, ["-="] = true, ["*="] = true, ["/="] = true, ["\\="] = true,
  ["%="] = true, ["^="] = true, ["..="] = true, ["|="] = true, ["&="] = true,
  ["^^="] = true, ["<<="] = true, [">>="] = true, [">>>="] = true,
  ["<<>="] = true, [">><="] = true,
}
local COMPOUND = M.COMPOUND

local BLOCK_END = { ["end"] = true, ["else"] = true, ["elseif"] = true, ["until"] = true }

local ParseError = {}

local function near(t)
  if t.type == "eof" then
    return "<eof>"
  end
  local v = t.value:gsub("\n.*", "...")
  if #v > 24 then
    v = v:sub(1, 21) .. "..."
  end
  return "'" .. v .. "'"
end

--- Parse the token stream produced by lexer.lex().
---@return table result
---   ok, error = { msg, line, col, eline, ecol }
---   globals      name -> { tok, kind = "function"|"variable", fn }
---   global_refs  { name, tok, assign, member }[]
---   locals       { name, tok, kind, used, assigned, refs, last_param }[]
---   unused       locals that are never read
---   calls        { name, tok, nargs, multi }[]  (calls of global functions)
---   functions    { name, tok, kind, params, vararg, s, e, line, eline }[]
---   refs         token -> local declaration
function M.parse(lex)
  local tokens = lex.tokens
  local p = 1
  local tok = tokens[1]

  local R = {
    ok = true,
    globals = {},
    global_refs = {},
    locals = {},
    unused = {},
    calls = {},
    functions = {},
    refs = {},
  }

  local function fail(msg, t)
    error({ [ParseError] = true, msg = msg, tok = t or tok }, 0)
  end

  local function advance()
    local t = tok
    p = p + 1
    tok = tokens[p] or tokens[#tokens]
    return t
  end

  local function is(v)
    return (tok.type == "op" or tok.type == "keyword") and tok.value == v
  end

  local function accept(v)
    if is(v) then
      return advance()
    end
  end

  local function expect(v)
    if is(v) then
      return advance()
    end
    fail(("'%s' expected near %s"):format(v, near(tok)))
  end

  local function expect_match(v, what, opener)
    if is(v) then
      return advance()
    end
    if opener.line == tok.line then
      fail(("'%s' expected near %s"):format(v, near(tok)))
    end
    fail(("'%s' expected (to close '%s' at line %d) near %s"):format(v, what, opener.line + 1, near(tok)))
  end

  local function expect_name()
    if tok.type == "name" then
      return advance()
    end
    fail("<name> expected near " .. near(tok))
  end

  -- scopes ------------------------------------------------------------------

  -- A scope is a block: { parent, vars = name -> var, list = var[],
  -- labels = name -> token, gotos = token[], func_top = bool }
  local scope
  local fs -- function state { parent, vararg, loops }

  local function open_scope(func_top)
    scope = { parent = scope, vars = {}, list = {}, labels = {}, gotos = {}, func_top = func_top }
  end

  local function close_scope()
    for _, v in ipairs(scope.list) do
      if not v.used and v.kind ~= "self" and v.name:sub(1, 1) ~= "_" then
        R.unused[#R.unused + 1] = v
      end
    end
    -- Lua 5.2 rules: a goto sees labels of its block and of the enclosing
    -- blocks of the same function
    for _, g in ipairs(scope.gotos) do
      if not scope.labels[g.value] then
        if scope.func_top then
          fail(("no visible label '%s' for goto"):format(g.value), g)
        end
        table.insert(scope.parent.gotos, g)
      end
    end
    scope = scope.parent
  end

  local function declare(t, kind)
    local v = { name = t.value, tok = t, kind = kind, used = false, assigned = false, refs = {} }
    scope.vars[v.name] = v
    scope.list[#scope.list + 1] = v
    R.locals[#R.locals + 1] = v
    R.refs[t] = v
    return v
  end

  local function resolve(name)
    local s = scope
    while s do
      local v = s.vars[name]
      if v then
        return v
      end
      s = s.parent
    end
  end

  --- Record a use (or assignment) of the name token t.
  local function use_name(t, assign, also_read)
    local v = resolve(t.value)
    if v then
      if assign then
        v.assigned = true
      end
      if not assign or also_read then
        v.used = true
      end
      v.refs[#v.refs + 1] = t
      R.refs[t] = v
      return v, nil
    end
    local g = { name = t.value, tok = t, assign = assign and not also_read, compound = also_read }
    R.global_refs[#R.global_refs + 1] = g
    -- `x += 1` reads x, so it does not count as a definition
    if assign and not also_read and not R.globals[t.value] then
      R.globals[t.value] = { tok = t, kind = "variable" }
    end
    return nil, g
  end

  local function finish(node)
    if node.k == "name" and not node.done then
      node.done = true
      node.var, node.gref = use_name(node.tok, false)
    end
    return node
  end

  -- expressions ---------------------------------------------------------------

  local expr, block, body

  local function table_cons()
    local open = advance() -- '{'
    while not is("}") do
      if is("[") then
        local b = advance()
        expr()
        expect_match("]", "[", b)
        expect("=")
        expr()
      elseif tok.type == "name" and tokens[p + 1].type == "op" and tokens[p + 1].value == "=" then
        local key = advance()
        advance()
        expr(0, { name = key.value, tok = key, kind = "field" })
      else
        expr()
      end
      if not (accept(",") or accept(";")) then
        break
      end
    end
    expect_match("}", "{", open)
  end

  -- returns the number of arguments and whether the last one can expand to
  -- multiple values (a call or ...)
  local function callargs()
    if tok.type == "string" then
      advance()
      return 1, false
    end
    if is("{") then
      table_cons()
      return 1, false
    end
    local open = expect("(")
    if accept(")") then
      return 0, false
    end
    local n, last = 0, nil
    repeat
      n = n + 1
      last = expr()
    until not accept(",")
    expect_match(")", "(", open)
    return n, last.k == "call" or last.k == "vararg"
  end

  local function primary()
    local t = tok
    if t.type == "name" then
      advance()
      return { k = "name", tok = t, path = t.value }
    end
    if is("(") then
      advance()
      expr()
      expect_match(")", "(", t)
      return { k = "paren", tok = t }
    end
    fail("unexpected symbol near " .. near(t))
  end

  local function call(node)
    local fname = node.k == "name" and node.tok
    finish(node)
    local open = tok
    local nargs, multi = callargs()
    if fname and node.gref then
      R.calls[#R.calls + 1] = { name = fname.value, tok = fname, open = open, nargs = nargs, multi = multi }
    end
    return { k = "call", tok = node.tok }
  end

  local function suffixed()
    local node = primary()
    while true do
      if tok.type == "op" then
        local v = tok.value
        if v == "." then
          finish(node)
          advance()
          local f = expect_name()
          if node.gref and not node.gref.member then
            node.gref.member = f.value
          end
          node = { k = "index", tok = node.tok, field = f, path = node.path and (node.path .. "." .. f.value) }
        elseif v == "[" then
          finish(node)
          local open = advance()
          expr()
          expect_match("]", "[", open)
          node = { k = "index", tok = node.tok }
        elseif v == ":" then
          finish(node)
          advance()
          local m = expect_name()
          if node.gref and not node.gref.member then
            node.gref.member = m.value
          end
          callargs()
          node = { k = "call", tok = node.tok, method = true }
        elseif v == "(" or v == "{" then
          node = call(node)
        else
          break
        end
      elseif tok.type == "string" then
        node = call(node)
      else
        break
      end
    end
    return node
  end

  local function simple(hint)
    local t = tok
    local ty = t.type
    if ty == "number" or ty == "string" then
      advance()
      return { k = "value", tok = t }
    elseif ty == "keyword" then
      local v = t.value
      if v == "nil" or v == "true" or v == "false" then
        advance()
        return { k = "value", tok = t }
      elseif v == "function" then
        advance()
        local fn = body(t, hint and hint.name, hint and hint.tok, hint and hint.kind or "anonymous", false)
        return { k = "func", tok = t, fn = fn }
      end
    elseif ty == "op" then
      if t.value == "?" then
        -- print shorthand used as a value: x=?"hi"
        advance()
        repeat
          expr()
        until not accept(",")
        return { k = "value", tok = t }
      elseif t.value == "..." then
        if not fs.vararg then
          fail("cannot use '...' outside a vararg function near '...'")
        end
        advance()
        return { k = "vararg", tok = t }
      elseif t.value == "{" then
        table_cons()
        return { k = "table", tok = t }
      end
    end
    return finish(suffixed())
  end

  expr = function(limit, hint)
    limit = limit or 0
    local node
    local t = tok
    if (t.type == "op" or t.type == "keyword") and UNARY[t.value] then
      advance()
      expr(UNARY_PREC)
      node = { k = "value", tok = t }
    else
      node = simple(hint)
    end
    while true do
      local op = tok
      local prec = (op.type == "op" or op.type == "keyword") and BINARY[op.value]
      if not prec then
        break
      end
      if RIGHT[op.value] then
        if prec < limit then
          break
        end
      elseif prec <= limit then
        break
      end
      advance()
      expr(prec)
      node = { k = "value", tok = t }
    end
    return node
  end

  -- functions -----------------------------------------------------------------

  body = function(functok, name, name_tok, kind, is_method)
    local newfs = { parent = fs, vararg = false, loops = 0 }
    local fn = { name = name, tok = name_tok or functok, kind = kind, params = {}, vararg = false, method = is_method }
    expect("(")
    fs = newfs
    open_scope(true)
    if is_method then
      declare({ type = "name", value = "self", line = functok.line, col = functok.col, synthetic = true }, "self")
    end
    local last_param
    if not is(")") then
      repeat
        if tok.type == "name" then
          local pt = advance()
          fn.params[#fn.params + 1] = pt.value
          last_param = declare(pt, "param")
        elseif is("...") then
          advance()
          newfs.vararg = true
          fn.vararg = true
          break
        else
          fail("<name> expected near " .. near(tok))
        end
      until not accept(",")
    end
    if last_param then
      last_param.last_param = true
    end
    expect(")")
    block()
    local endtok = expect_match("end", "function", functok)
    close_scope()
    fs = newfs.parent
    fn.s, fn.e = functok.i, endtok.i
    fn.line, fn.eline = functok.line, endtok.eline
    R.functions[#R.functions + 1] = fn
    return fn
  end

  -- statements ----------------------------------------------------------------

  local function scoped_block(short_line)
    open_scope()
    block(short_line)
    close_scope()
  end

  local function loop_block(short_line, decls)
    fs.loops = fs.loops + 1
    open_scope()
    for _, d in ipairs(decls or {}) do
      declare(d, "for")
    end
    block(short_line)
    close_scope()
    fs.loops = fs.loops - 1
  end

  local function ifstat(t)
    advance()
    expr()
    local last = tokens[p - 1]
    if accept("then") or accept("do") then
      scoped_block()
      while is("elseif") do
        advance()
        expr()
        if not (accept("then") or accept("do")) then
          fail("'then' expected near " .. near(tok))
        end
        scoped_block()
      end
      if accept("else") then
        scoped_block()
      end
      expect_match("end", "if", t)
    elseif last.type == "op" and last.value == ")" then
      -- shorthand: if (cond) stmt [else stmt] on one line
      local line = last.eline
      scoped_block(line)
      if tok.line == line and is("else") then
        advance()
        scoped_block(line)
      end
    else
      fail("'then' expected near " .. near(tok))
    end
  end

  local function whilestat(t)
    advance()
    expr()
    local last = tokens[p - 1]
    if accept("do") then
      loop_block()
      expect_match("end", "while", t)
    elseif last.type == "op" and last.value == ")" then
      loop_block(last.eline)
    else
      fail("'do' expected near " .. near(tok))
    end
  end

  local function forstat(t)
    advance()
    local n1 = expect_name()
    if is("=") then
      advance()
      expr()
      expect(",")
      expr()
      if accept(",") then
        expr()
      end
      expect("do")
      loop_block(nil, { n1 })
    elseif is(",") or is("in") then
      local names = { n1 }
      while accept(",") do
        names[#names + 1] = expect_name()
      end
      expect("in")
      repeat
        expr()
      until not accept(",")
      expect("do")
      loop_block(nil, names)
    else
      fail("'=' or 'in' expected near " .. near(tok))
    end
    expect_match("end", "for", t)
  end

  local function repeatstat(t)
    advance()
    fs.loops = fs.loops + 1
    open_scope()
    block()
    expect_match("until", "repeat", t)
    expr() -- the condition can see the body's locals
    close_scope()
    fs.loops = fs.loops - 1
  end

  local function funcstat(t)
    advance()
    local n1 = expect_name()
    local full, name_tok, parts, is_method = n1.value, n1, 0, false
    while is(".") do
      advance()
      local f = expect_name()
      full, name_tok, parts = full .. "." .. f.value, f, parts + 1
    end
    if is(":") then
      advance()
      local m = expect_name()
      full, name_tok, parts, is_method = full .. ":" .. m.value, m, parts + 1, true
    end
    local kind
    if parts == 0 then
      local v = use_name(n1, true)
      kind = v and "local" or "global"
    else
      use_name(n1, false)
      kind = is_method and "method" or "field"
    end
    local fn = body(t, full, name_tok, kind, is_method)
    if kind == "global" then
      local g = R.globals[n1.value]
      if not g or g.kind ~= "function" then
        R.globals[n1.value] = { tok = n1, kind = "function", fn = fn }
      end
    end
  end

  local function localstat()
    advance()
    if is("function") then
      local ft = advance()
      local n = expect_name()
      local v = declare(n, "function")
      v.fn = body(ft, n.value, n, "local", false)
      return
    end
    local names, values = {}, {}
    repeat
      names[#names + 1] = expect_name()
    until not accept(",")
    if accept("=") then
      local i = 0
      repeat
        i = i + 1
        local n = names[i]
        values[i] = expr(0, n and { name = n.value, tok = n, kind = "local" })
      until not accept(",")
    end
    for i, n in ipairs(names) do
      local v = declare(n, "local")
      if values[i] and values[i].k == "func" then
        v.fn = values[i].fn -- local f = function() ... end
      end
    end
  end

  local function exprstat()
    local node = suffixed()
    if is("=") or is(",") then
      local targets = { node }
      while accept(",") do
        targets[#targets + 1] = suffixed()
      end
      for _, tg in ipairs(targets) do
        if tg.k ~= "name" and tg.k ~= "index" then
          fail("syntax error near " .. near(tok))
        end
      end
      expect("=")
      local values = {}
      local i = 0
      repeat
        i = i + 1
        local tg = targets[i]
        local hint
        if tg and tg.path then
          hint = { name = tg.path, tok = tg.field or tg.tok, kind = tg.k == "name" and "global" or "field" }
        end
        values[i] = expr(0, hint)
      until not accept(",")
      for k, tg in ipairs(targets) do
        if tg.k == "name" then
          local v = use_name(tg.tok, true)
          local fnode = values[k] and values[k].k == "func" and values[k]
          if fnode and v then
            v.fn = v.fn or fnode.fn
          elseif fnode then
            local g = R.globals[tg.tok.value]
            if not g or g.kind ~= "function" then
              -- foo = function() ... end
              R.globals[tg.tok.value] = { tok = tg.tok, kind = "function", fn = fnode.fn }
            end
          end
        end
      end
    elseif tok.type == "op" and COMPOUND[tok.value] then
      if node.k ~= "name" and node.k ~= "index" then
        fail("syntax error near " .. near(tok))
      end
      advance()
      expr()
      if node.k == "name" then
        use_name(node.tok, true, true)
      end
    elseif node.k ~= "call" then
      fail("syntax error near " .. near(tok))
    end
  end

  local function statement()
    local t = tok
    local ty, v = t.type, t.value
    if ty == "op" then
      if v == ";" then
        advance()
        return
      elseif v == "::" then
        advance()
        local name = expect_name()
        expect("::")
        local prev = scope.labels[name.value]
        if prev then
          fail(("label '%s' already defined on line %d"):format(name.value, prev.line + 1), name)
        end
        scope.labels[name.value] = name
        return
      elseif v == "?" then
        -- print shorthand: ?expr, ...
        advance()
        local nargs, last = 0, nil
        repeat
          nargs = nargs + 1
          last = expr()
        until not accept(",")
        if not resolve("print") then
          R.calls[#R.calls + 1] = {
            name = "print", tok = t, nargs = nargs, multi = last.k == "call" or last.k == "vararg", implicit = true,
          }
        end
        return
      end
    elseif ty == "keyword" then
      if v == "if" then
        return ifstat(t)
      elseif v == "while" then
        return whilestat(t)
      elseif v == "do" then
        advance()
        scoped_block()
        expect_match("end", "do", t)
        return
      elseif v == "for" then
        return forstat(t)
      elseif v == "repeat" then
        return repeatstat(t)
      elseif v == "function" then
        return funcstat(t)
      elseif v == "local" then
        return localstat()
      elseif v == "break" then
        advance()
        if fs.loops == 0 then
          fail(("<break> at line %d not inside a loop"):format(t.line + 1), t)
        end
        return
      elseif v == "goto" then
        advance()
        scope.gotos[#scope.gotos + 1] = expect_name()
        return
      end
    end
    exprstat()
  end

  block = function(short_line)
    while true do
      local t = tok
      if t.type == "eof" or (short_line and t.line ~= short_line) then
        return
      end
      if t.type == "keyword" then
        if BLOCK_END[t.value] then
          return
        end
        if t.value == "return" then
          advance()
          local c = tok
          local empty = c.type == "eof"
            or (c.type == "keyword" and BLOCK_END[c.value])
            or (c.type == "op" and c.value == ";")
            or (short_line and c.line ~= short_line)
          if not empty then
            repeat
              expr()
            until not accept(",")
          end
          accept(";")
          return
        end
      end
      statement()
    end
  end

  local ok, err = pcall(function()
    fs = { vararg = true, loops = 0 }
    open_scope(true)
    block()
    if tok.type ~= "eof" then
      fail("'<eof>' expected near " .. near(tok))
    end
    close_scope()
  end)

  if not ok then
    if type(err) == "table" and err[ParseError] then
      local t = err.tok
      R.ok = false
      R.error = { msg = err.msg, line = t.line, col = t.col, eline = t.eline, ecol = math.max(t.ecol, t.col + 1) }
      if t.type == "eof" then
        R.error.ecol = t.col
      end
    else
      error(err, 0)
    end
  end

  return R
end

return M
