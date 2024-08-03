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

---Check regex pairs.
---
---@param atype PairAdjacentType
---@param ctx PairLineContext
---@param check boolean `true` to check conditions.
---@return boolean
local function regex_adjacent_should(atype, ctx, check)
    local specs = atype == ACTION.cr and st.state.regex.cr
        or st.state.regex[atype][ctx.mode]
    local spec
    for _, regspec in ipairs(specs) do
        local opener
        local space

        -- check opener
        local os, oe = ctx.before:find(regspec.opener.text .. '$')
        if os and oe then
            opener = ctx.before:sub(os, oe)
        elseif atype ~= ACTION.space then
            local sos, soe = ctx.before:find(regspec.opener.text .. ' $')
            if sos and soe then
                opener = ctx.before:sub(sos, soe - 1)
                space = true
            end
        end

        if opener then -- then check closer
            ---@cast ctx PairContext
            if U.has_sub(regspec.closer.text) then -- has capture groups
                local closer =
                    opener:gsub(regspec.opener.text, regspec.closer.text)
                if
                    ctx.after:sub(
                        space and 2 or 1,
                        #closer + (space and 1 or 0)
                    ) == closer
                then
                    ctx.opener = opener
                    ctx.closer = closer
                    ctx.spaced = space
                    spec = regspec
                end
            else -- no capture groups
                local es, ee = ctx.after:find(
                    (space and '^ ' or '^') .. regspec.closer.text
                )
                if es and ee then
                    ctx.opener = opener
                    ctx.closer = ctx.after:sub(space and es + 1 or es, ee)
                    ctx.spaced = space
                    spec = regspec
                end
            end
        end
    end

    if not spec then
        return false
    end
    ---@cast ctx PairContext
    ctx.spec = setmetatable({}, { __index = spec })

    return U.ternary(check, M.check_conditions(atype, ctx), true)
end

---Check pairs of fixed length.
---
---@param atype PairAdjacentType
---@param ctx PairLineContext
---@param check boolean `true` to check conditions.
---@return boolean
local function fixed_adjacent_should(atype, ctx, check)
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
    ctx.opener = spec.opener.text
    ctx.closer = spec.closer.text
    ctx.spec = setmetatable({}, { __index = spec })

    return U.ternary(check, M.check_conditions(atype, ctx), true)
end

---Check if text adjacent to the cursor matches one of the specs.
---
---@param atype PairAdjacentType
---@param ctx PairLineContext
---@param check? boolean `true` to check conditions. Default `true`.
---@return boolean
function M.adjacent_should(atype, ctx, check)
    ---@cast check -?
    check = check == nil and true or check
    return regex_adjacent_should(atype, ctx, check)
        or fixed_adjacent_should(atype, ctx, check)
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

return M
