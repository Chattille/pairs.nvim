local D = require 'pairs.conds'
local T = require 'pairs.types'
local U = require 'pairs.utils'
local st = require 'pairs.actions.state'

local ACTION = T.ACTION

local M = {}

---@param atype PairActionType
---@param ctx PairContext
function M.check_conditions(atype, ctx)
    -- check default conditions
    if
        atype == ACTION.cr and ctx.spec.cr.default
        or ctx.spec[atype][ctx.mode].default
    then
        local default_pass = D.check_default_conditions(atype, ctx)
        if not default_pass then
            return false
        end
    end

    -- check conditions added in specs
    local conds = atype == ACTION.cr and ctx.spec.cr
        or ctx.spec[atype][ctx.mode]
    for _, cond in ipairs(conds) do
        if not cond(ctx) then
            return false
        end
    end

    return true
end

---Check if text adjacent to the cursor matches one of the specs.
---
---@param atype PairAdjacentType
---@param ctx PairLineContext
---@return boolean
function M.adjacent_should(atype, ctx)
    -- must check if is in the right context
    local spec
    local lens = atype == ACTION.cr and st.state.lengths.cr
        or st.state.lengths[atype][ctx.mode]
    for _, z in ipairs(lens) do
        local olen, clen = U.uncantor(z)
        local tstart = ctx.col - olen
        local tend = ctx.col + clen - 1
        if tstart >= 1 and tend <= #ctx.line then
            local text = ctx.line:sub(tstart, tend)
            local trigs = atype == ACTION.cr and st.state.specs.cr
                or st.state.specs[atype][ctx.mode]
            spec = trigs[text]
            if spec then
                break
            end

            -- check space
            local space = ctx.line:sub(ctx.col - 1, ctx.col)
            if atype ~= ACTION.space and space == '  ' then
                local ltext = ctx.line:sub(ctx.col - 1 - olen, ctx.col - 2)
                local rtext = ctx.line:sub(ctx.col + 1, ctx.col + clen)
                spec = st.state.specs.space[ctx.mode][ltext .. rtext]
                if spec then
                    ctx.spaced = true
                    break
                end
            end
        end
    end

    if not spec then -- not triggered
        return false
    end
    ---@cast ctx PairContext
    ctx.spec = setmetatable({}, { __index = spec })

    return M.check_conditions(atype, ctx)
end

---Delete by modifying context.
---
---@param ctx PairLineContext
---@param left integer
---@param right integer
---@return PairLineContext
function M.del_dryrun(ctx, left, right)
    ctx.before = ctx.before:sub(1, #ctx.before - left)
    ctx.after = ctx.after:sub(right + 1)
    ctx.line = ctx.before .. ctx.after
    ctx.col = ctx.col - left
    if ctx.spaced then
        ctx.spaced = nil
    end

    return ctx
end

---Do a dry run of backspace deletion, find closers that should be deleted,
---and return the amount of KEY.del to be inserted.
---
---@param ctx PairContext
---@return integer
function M.count_del(ctx)
    if ctx.col == #ctx.line + 1 then -- cursor at end of line
        return 0
    end

    local del_count = 0
    local i = 1
    local max = #ctx.opener - 1

    if i <= max then
        local dry_ctx = vim.deepcopy(ctx)
        while i <= max do
            if M.adjacent_should(ACTION.del, dry_ctx) then
                -- simulate deletion
                local left = dry_ctx.spaced and 1 or #dry_ctx.spec.opener.text
                local right = dry_ctx.spaced and 1 or #dry_ctx.spec.closer.text
                M.del_dryrun(dry_ctx, left, right)

                del_count = del_count + right
                i = i + left
            else
                M.del_dryrun(dry_ctx, 1, 0)
                i = i + 1
            end
        end
    end

    return del_count
end

return M
