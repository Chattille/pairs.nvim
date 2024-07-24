local C = require 'autopair.config'

local M = {}

-- }}} Condition Components {{{

---Is cursor not followed by the pattern?
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

---Is cursor not preceeded by the pattern?
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

-- }}} Default Conditions {{{

---@type ActionCondition
local function only_before(ctx)
    return M.notbefore(C.config.condition.ignore_pair_if_before)(ctx)
end

---@type DefaultCondition
local conditions = {
    pair = {
        i = { only_before },
        c = { only_before },
    },
    close = {
        i = {},
        c = {},
    },
    del = {
        i = {},
        c = {},
    },
    cr = {},
    space = {
        i = {},
        c = {},
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
