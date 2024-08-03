local T = require 'pairs.types'
local U = require 'pairs.utils'
local cm = require 'pairs.actions.common'
local st = require 'pairs.actions.state'

local ACTION = T.ACTION
local KEY = T.KEY

local M = {}

---@param ctx PairContext
---@return boolean
local function regex_pair_triggered(ctx)
    if
        ctx.spec.opener.key ~= ''
        and not ctx.key:match('^' .. ctx.spec.opener.key .. '$')
    then -- key not triggering auto-pairing
        return false
    end

    -- get actual opener
    local line = ctx.before .. ctx.key
    local ms, me = line:find(ctx.spec.opener.text .. '$')
    if ms and me then
        ctx.opener = line:sub(ms, me)
    end

    if
        ctx.opener
        and (
            ctx.spec.opener.key ~= ''
            or ctx.key == ctx.opener:sub(#ctx.opener)
        )
    then -- compute actual closer
        ctx.closer = line:sub(-#ctx.opener)
            :gsub(ctx.spec.opener.text .. '$', ctx.spec.closer.text)
        return true
    end

    return false
end

---@param ctx PairContext
---@return boolean
local function insert_pair_triggered(ctx)
    ctx.opener = ctx.spec.opener.text
    ctx.closer = ctx.spec.closer.text
    local length = #ctx.opener

    if (ctx.before .. ctx.key):sub(-length) == ctx.opener then
        return true
    else
        return false
    end
end

---Check if auto-pairing is triggered.
---
---@param ctx PairContext
---@return boolean
local function pair_triggered(ctx)
    if ctx.spec.regex then
        return regex_pair_triggered(ctx)
    else
        return insert_pair_triggered(ctx)
    end
end

---@param ctx PairContext
---@return boolean
local function regex_close_triggered(ctx)
    if
        ctx.spec.closer.key ~= ''
        and not ctx.key:match('^' .. ctx.spec.closer.key .. '$')
    then -- key not triggering auto-closing
        return false
    end

    -- get actual closer first
    local repl_closer =
        U.get_replaced_sub(ctx.spec.opener.text, ctx.spec.closer.text)
    local ms, me = ctx.after:find('^' .. repl_closer)
    if ms and me then
        ctx.closer = ctx.after:sub(ms, me)
    elseif ctx.spec.space[ctx.mode].enable then
        -- check space
        local sms, sme = ctx.after:find('^ ' .. repl_closer)
        if sms and sme then
            ctx.closer = ctx.after:sub(sms + 1, sme)
            ctx.spaced = true
        end
    end

    if
        ctx.closer
        and (
            ctx.spec.closer.key ~= ''
            -- use the last char if key is unspecified
            or ctx.key == ctx.closer:sub(#ctx.closer)
        )
    then
        ctx.opener = '' -- cannot decide
        return true
    end

    return false
end

---@param ctx PairContext
---@return boolean
local function insert_close_triggered(ctx)
    ctx.opener = ctx.spec.opener.text
    ctx.closer = ctx.spec.closer.text
    local length = #ctx.closer

    if ctx.after:sub(1, length) == ctx.closer then
        return true
    elseif
        ctx.spec.space[ctx.mode].enable
        and ctx.after:sub(1, length + 1) == ' ' .. ctx.closer
    then
        ctx.spaced = true
        return true
    else
        return false
    end
end

---Check if auto-closing is triggered.
---
---@param ctx PairContext
---@return boolean
local function close_triggered(ctx)
    if ctx.spec.regex then
        return regex_close_triggered(ctx)
    else
        return insert_close_triggered(ctx)
    end
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
    local max = #ctx.opener - 1

    if i <= max then
        local dry_ctx = vim.deepcopy(ctx)
        -- limit to text to be deleted
        dry_ctx.before = dry_ctx.before:sub(-max)
        dry_ctx.line = dry_ctx.before .. dry_ctx.after
        dry_ctx.col = max + 1
        while i <= max do
            if cm.adjacent_should(ACTION.del, dry_ctx, false) then
                -- simulate deletion
                local left = dry_ctx.spaced and 1 or #dry_ctx.opener
                local right = dry_ctx.spaced and 1 or #dry_ctx.closer
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

---@param mode PairModeType
---@param key string
---@param specs PairFullSpec[]
---@return string[]?
local function trigger_pair(mode, key, specs)
    for _, spec in ipairs(specs) do
        local ctx = U.get_context(mode, spec, key)
        ---@cast ctx PairContext
        if insert_should(ACTION.pair, ctx) then
            -- remove inserted pair before pairing
            local clears = KEY.del:rep(count_del(ctx))
            -- make dot-repeat work correctly in Insert mode
            local left = mode == 'i' and KEY.nundo .. KEY.left or KEY.left
            -- return as a list for caller to choose which parts to ignore
            return {
                KEY.abbr,
                clears,
                ctx.closer,
                left:rep(#ctx.closer),
                key,
            }
        end
    end
end

---@param mode PairModeType
---@param key string
---@param specs PairFullSpec[]
---@return string?
local function trigger_close(mode, key, specs)
    for _, spec in ipairs(specs) do
        local ctx = U.get_context(mode, spec, key)
        ---@cast ctx PairContext
        if insert_should(ACTION.close, ctx) then
            local length = #ctx.closer + (ctx.spaced and 1 or 0)
            -- make dot-repeat work correctly in Insert mode
            local right = mode == 'i' and KEY.nundo .. KEY.right or KEY.right
            return right:rep(length)
        end
    end
end

---Trgger auto-pairing or -closing for `key`.
---
---@param mode PairModeType
---@param key string
---@return string
local function trigger_insert(mode, key)
    local aspecs = st.state.specs.insert[mode][key]
    if aspecs.close then -- trigger closing first
        local close = trigger_close(mode, key, aspecs.close)
        if close then
            return close
        end
    end

    if aspecs.pair then
        local keys = trigger_pair(mode, key, aspecs.pair)
        if keys then
            -- insert closer first to avoid flickering
            return table.concat(keys)
        end
    end

    return key
end

---Check regex pairs.
---
---@param mode PairModeType
---@param key string
---@param fromevent? boolean
---@return boolean
local function trigger_regex(mode, key, fromevent)
    local aspecs = st.state.regex.insert[mode]
    if aspecs.close then
        local close = trigger_close(mode, key, aspecs.close)
        if close then
            vim.v.char = ''
            U.feed(close)
            return true
        end
    end

    if aspecs.pair then
        local keys = trigger_pair(mode, key, aspecs.pair)
        if keys then
            if fromevent then
                -- pass text to v:char to prevent re-evaluating fed keys
                vim.v.char = keys[5] .. keys[3]
                U.feed(keys[2] .. keys[4])
            else
                U.feed(table.concat(keys))
            end

            return true
        end
    end

    return false
end

---@param key string
---@param fromevent? boolean key from InsertCharPre (true) or fed from keymaps.
---@return string?
function M.trigger(key, fromevent)
    local mode = U.get_mode()
    if not U.mode_qualified(mode) then
        return key
    end

    if fromevent and st.state.specs.insert[mode][key] then
        -- avoid re-evaluating keys fed from insert keymaps
        return
    end

    local succ = trigger_regex(mode, key, fromevent)
    if not fromevent and not succ then
        return trigger_insert(mode, key)
    end

    return ''
end

return M
