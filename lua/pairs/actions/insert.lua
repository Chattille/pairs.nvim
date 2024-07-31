local T = require 'pairs.types'
local U = require 'pairs.utils'
local cm = require 'pairs.actions.common'
local st = require 'pairs.actions.state'

local ACTION = T.ACTION
local KEY = T.KEY

local M = {}

---Check if auto-paring is triggered.
---
---@param ctx PairContext
---@return boolean
local function pair_triggered(ctx)
    if ctx.spec.regex and ctx.before:match(ctx.spec.opener.text) then
        return true
    end

    local escaped_opener = U.lua_escape(ctx.spec.opener.text)
    if ctx.spec.opener.text:sub(#ctx.spec.opener.text) == ctx.key then
        if (ctx.before .. ctx.key):match(escaped_opener .. '$') then
            return true
        end
    elseif ctx.before:match(escaped_opener .. '$') then
        return true
    end

    return false
end

---Check if auto-closing is triggered.
---
---@param ctx PairContext
---@return boolean
local function close_triggered(ctx)
    local escaped_closer = ctx.spec.regex and ctx.spec.closer.text
        or U.lua_escape(ctx.spec.closer.text)

    if ctx.spec.regex then
        if ctx.after:match(escaped_closer) then
            return true
        end
    elseif ctx.after:match('^' .. escaped_closer) then
        return true
    end

    if -- check space
        ctx.spec.space[ctx.mode].enable
        and ctx.after:match('^ ' .. escaped_closer)
    then
        ctx.spaced = true
        return true
    end

    return false
end

---@param atype PairInsertType
---@param ctx PairContext
local function insert_triggered(atype, ctx)
    if atype == ACTION.pair then
        return pair_triggered(ctx)
    else
        return close_triggered(ctx)
    end
end

---@param atype PairInsertType
---@param ctx PairContext
local function insert_should(atype, ctx)
    -- must check if is in the right context
    if not insert_triggered(atype, ctx) then
        return false
    end
    return cm.check_conditions(atype, ctx)
end

---Do a dry run of backspace deletion, find closers that should be deleted,
---and return the amount of KEY.del to be inserted.
---
---@param ctx PairContext
---@return integer
local function count_del(ctx)
    if ctx.col == #ctx.line + 1 then -- cursor at end of line
        return 0
    end

    local del_count = 0
    local i = 1
    local max = #ctx.spec.opener.text - 1

    if i <= max then
        local dry_ctx = vim.deepcopy(ctx)
        while i <= max do
            if cm.adjacent_should(ACTION.del, dry_ctx) then
                -- simulate deletion
                local left = dry_ctx.spaced and 1 or #dry_ctx.spec.opener.text
                local right = dry_ctx.spaced and 1 or #dry_ctx.spec.closer.text
                cm.del_dryrun(dry_ctx, left, right)

                del_count = del_count + right
                i = i + left
            else
                cm.del_dryrun(dry_ctx, 1, 0)
                i = i + 1
            end
        end
    end

    return del_count
end

---Trgger auto-pairing or -closing for `key`.
---
---@param key string
---@return string
function M.trigger(key)
    local mode = U.get_mode()
    if not U.mode_qualified(mode) then
        return key
    end

    local aspecs = st.state.specs.insert[mode][key]
    if aspecs.close then -- trigger closing first
        for _, spec in ipairs(aspecs.close) do
            local ctx = U.get_context(mode, spec, key)
            ---@cast ctx PairContext
            if insert_should(ACTION.close, ctx) then
                local length = #ctx.spec.closer.text + (ctx.spaced and 1 or 0)
                -- make dot-repeat work correctly in Insert mode
                local right = mode == 'i' and KEY.nundo .. KEY.right
                    or KEY.right
                return right:rep(length)
            end
        end
    end

    if aspecs.pair then
        for _, spec in ipairs(aspecs.pair) do
            local ctx = U.get_context(mode, spec, key)
            ---@cast ctx PairContext
            if insert_should(ACTION.pair, ctx) then
                -- remove inserted pair before pairing
                local clears = KEY.del:rep(count_del(ctx))
                -- make dot-repeat work correctly in Insert mode
                local left = mode == 'i' and KEY.nundo .. KEY.left or KEY.left
                -- insert closer first to avoid flickering
                return KEY.abbr
                    .. clears
                    .. ctx.spec.closer.text
                    .. left:rep(#ctx.spec.closer.text)
                    .. key
            end
        end
    end

    return key
end

return M
