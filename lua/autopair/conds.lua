local M = {}

-- }}} Condition Components {{{

-- TODO: default conditions

-- }}} Helpers {{{

---@type table<PairActionType, table<PairModeType, ActionCondition[]>>
local conditions = {
    pair = {
        i = {},
        c = {},
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
    for _, cond in ipairs(conds) do
        if not cond(ctx) then
            return false
        end
    end
    return true
end

return M
