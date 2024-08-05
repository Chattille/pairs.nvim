local C = require 'pairs.config'
local U = require 'pairs.utils'
local scn = require 'pairs.scanner'

local M = {}

-- }}} Condition Components {{{

---Check if the opener and closer have the same amount.
---This will skip backslash-escaped chars and chars inside quoted strings
---(filetype-specific).
---
---@param ctx PairContext
---@return integer # Positive if more openers and negative if more closers.
function M.check_balance(ctx)
    if
        not ctx.spec.nestable[ctx.mode]
        or not C.config.condition.check_inline_balance
        or ctx.spec.opener.text == ctx.spec.closer.text
    then
        return 0
    end

    ---@type Scanner
    local scanner = scn.Scanner.new(ctx.line)
    ---@type ScannerContext
    local sctx = { quote = nil }
    local escaped = false
    local balance = 0

    while not scanner:isover() do
        if scn.isquote(scanner, sctx) then
            goto continue
        elseif sctx.quote then
            scanner:step()
            goto continue
        elseif escaped then
            escaped = false
            scanner:step()
            goto continue
        end

        if scanner:eat [[\]] then
            escaped = true
        elseif scanner:eat(ctx.spec.opener.text) then
            balance = balance + 1
        elseif scanner:eat(ctx.spec.closer.text) then
            balance = balance - 1
        else
            scanner:step()
        end

        ::continue::
    end

    return balance
end

---Brackets are balanced on the current line.
---
---@param ctx PairContext
function M.isbalanced(ctx)
    return M.check_balance(ctx) == 0
end

---The cursor should not be followed by the pattern.
---
---@param pattern string
---@param type? 'lua'|'vim' Type of pattern. Default `'lua'`.
---@return ActionCondition
function M.notbefore(pattern, type)
    type = type or 'lua'

    ---@param text string
    local function match(text)
        if type == 'lua' then
            return text:match('^' .. pattern)
        else
            return vim.regex([[\v^\m]] .. pattern):match_str(text)
        end
    end

    ---@param ctx PairContext
    ---@return boolean
    return function(ctx)
        return U.ternary(pattern ~= '' and match(ctx.after), false, true)
    end
end

---The cursor should not be preceeded by the pattern.
---
---@param pattern string
---@param type? 'lua'|'vim' Type of pattern. Default `'lua'`.
---@return ActionCondition
function M.notafter(pattern, type)
    type = type or 'lua'

    ---@param text string
    local function match(text)
        if type == 'lua' then
            return text:match(pattern .. '$')
        else
            return vim.regex([[\m]] .. pattern .. [[\v$]]):match_str(text)
        end
    end

    ---@param ctx PairContext
    ---@return boolean
    return function(ctx)
        return U.ternary(pattern ~= '' and match(ctx.before), false, true)
    end
end

---The pair should not be followed by the pattern.
---
---@param pattern string
---@param type? 'lua'|'vim' Type of pattern. Default `'lua'`.
---@return ActionCondition
function M.pairnotbefore(pattern, type)
    type = type or 'lua'

    ---@param text string
    ---@param pair string
    local function match(text, pair)
        if type == 'lua' then
            return text:match('^' .. U.lua_escape(pair) .. pattern)
        else
            return vim.regex([[\v^\V]] .. pair .. [[\m]] .. pattern)
                :match_str(text)
        end
    end

    ---@param ctx PairContext
    ---@return boolean
    return function(ctx)
        if
            pattern ~= ''
            and ctx.closer ~= ''
            and match(ctx.after, ctx.closer)
        then
            return false
        end
        return true
    end
end

---The pair should not be preceeded by the pattern.
---
---@param pattern string
---@param type? 'lua'|'vim' Type of pattern. Default `'lua'`.
---@return ActionCondition
function M.pairnotafter(pattern, type)
    type = type or 'lua'

    ---@param text string
    ---@param pair string
    local function match(text, pair)
        if type == 'lua' then
            return text:match(pattern .. U.lua_escape(pair) .. '$')
        else
            return vim.regex([[\m]] .. pattern .. [[\V]] .. pair .. [[\v$]])
                :match_str(text)
        end
    end

    ---@param ctx PairContext
    ---@return boolean
    return function(ctx)
        if pattern ~= '' and ctx.opener ~= '' then
            local tail = ctx.before:sub(-#ctx.opener) == ctx.opener and ''
                or (ctx.key or '')
            if match(ctx.before .. tail, ctx.opener) then
                return false
            end
        end
        return true
    end
end

-- }}} Default Conditions {{{

---@type ActionCondition
local function only_before(ctx)
    return M.notbefore(C.config.condition.ignore_pair_if_before)(ctx)
end

---@type ActionCondition
local function nolessopener(ctx)
    return M.check_balance(ctx) >= 0
end

---@type ActionCondition
local function nolesscloser(ctx)
    return M.check_balance(ctx) <= 0
end

---@type ActionCondition
local function nobackslash(ctx)
    return M.notafter([[\\\@<!\%(\\\{2}\)*\\]], 'vim')(ctx)
end

---@type ActionCondition
local function pairnobackslash(ctx)
    return M.pairnotafter([[\\\@<!\%(\\\{2}\)*\\]], 'vim')(ctx)
end

---@type DefaultCondition
local conditions = {
    pair = {
        i = { only_before, nobackslash, pairnobackslash, nolessopener },
        c = { only_before, nobackslash, pairnobackslash, nolessopener },
    },
    close = {
        i = { nobackslash, pairnobackslash, nolesscloser },
        c = { nobackslash, pairnobackslash, nolesscloser },
    },
    del = {
        i = { pairnobackslash, nolesscloser },
        c = { pairnobackslash, nolesscloser },
    },
    cr = { pairnobackslash, M.isbalanced },
    space = {
        i = { pairnobackslash, M.isbalanced },
        c = { pairnobackslash, M.isbalanced },
    },
}

---@param atype PairActionType
---@param ctx PairContext
function M.check_default_conditions(atype, ctx)
    local conds = atype == 'cr' and conditions.cr
        or conditions[atype][ctx.mode]
    ---@cast conds ActionCondition[]
    for _, cond in ipairs(conds) do
        if not cond(ctx) then
            return false
        end
    end
    return true
end

return M
