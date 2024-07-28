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
---@return ActionCondition
function M.notbefore(pattern)
    ---@param ctx PairLineContext
    ---@return boolean
    return function(ctx)
        if pattern ~= '' and ctx.after:match('^' .. pattern) then
            return false
        end
        return true
    end
end

---The cursor should not be preceeded by the pattern.
---
---@param pattern string
---@return ActionCondition
function M.notafter(pattern)
    ---@param ctx PairLineContext
    ---@return boolean
    return function(ctx)
        if pattern ~= '' and ctx.before:match(pattern .. '$') then
            return false
        end
        return true
    end
end

---The pair should not be followed by the pattern.
---
---@param pattern string
---@return ActionCondition
function M.pairnotbefore(pattern)
    ---@param ctx PairContext
    ---@return boolean
    return function(ctx)
        if
            pattern ~= ''
            and ctx.after:match(
                '^' .. U.lua_escape(ctx.spec.closer.text) .. pattern
            )
        then
            return false
        end
        return true
    end
end

---The pair should not be preceeded by the pattern.
---
---@param pattern string
---@return ActionCondition
function M.pairnotafter(pattern)
    ---@param ctx PairContext
    ---@return boolean
    return function(ctx)
        if
            pattern ~= ''
            and ctx.before:match(
                pattern .. U.lua_escape(ctx.spec.opener.text) .. '$'
            )
        then
            return false
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

---@type DefaultCondition
local conditions = {
    pair = {
        i = { only_before, nolessopener },
        c = { only_before, nolessopener },
    },
    close = {
        i = { nolesscloser },
        c = { nolesscloser },
    },
    del = {
        i = { M.isbalanced },
        c = { M.isbalanced },
    },
    cr = { M.isbalanced },
    space = {
        i = { M.isbalanced },
        c = { M.isbalanced },
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
