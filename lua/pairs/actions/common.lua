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

---Find matching regex spec.
---
---@param atype PairAdjacentType
---@param ctx PairLineContext
---@return boolean
local function regex_adjacent_find_spec(atype, ctx)
    local specs = st.state.regex.adjacent
    ---@type PairFullSpec
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
                    break
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
                    break
                end
            end
        end
    end

    if not spec then
        return false
    end
    ---@cast ctx PairContext
    ctx.spec = setmetatable({}, { __index = spec })

    return true
end

---Find matching spec of fixed length.
---
---@param atype PairAdjacentType
---@param ctx PairLineContext
---@return boolean
local function fixed_adjacent_find_spec(atype, ctx)
    -- must check if is in the right context
    local lens = st.state.lengths[ctx.mode]
    ---@type PairFullSpec
    local spec
    for _, z in ipairs(lens) do
        local olen, clen = U.uncantor(z)
        local tstart = ctx.col - olen
        local tend = ctx.col + clen - 1
        if tstart >= 1 and tend <= #ctx.line then
            local text = ctx.line:sub(tstart, tend)
            local trigs = st.state.specs.adjacent
            spec = trigs[text]
            if spec then
                break
            end

            -- check space
            local space = ctx.line:sub(ctx.col - 1, ctx.col)
            if atype ~= ACTION.space and space == '  ' then
                local ltext = ctx.line:sub(ctx.col - 1 - olen, ctx.col - 2)
                local rtext = ctx.line:sub(ctx.col + 1, ctx.col + clen)
                spec = st.state.specs.adjacent[ltext .. rtext]
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

    return true
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

    local found = regex_adjacent_find_spec(atype, ctx)
    if not found then
        found = fixed_adjacent_find_spec(atype, ctx)
    end

    if not found then
        return false
    end

    ---@cast ctx PairContext
    if
        not (atype == ACTION.cr and { ctx.spec.cr.enable } or {
            ctx.spec[atype][ctx.mode].enable,
        })[1]
    then -- action not enabled
        return false
    end

    if ctx.spaced and not ctx.spec.space[ctx.mode].enable then
        -- spaced but space action not enabled
        return false
    end

    return U.ternary(check, M.check_conditions(atype, ctx), true)
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
