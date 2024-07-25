local C = require 'autopair.config'
local D = require 'autopair.conds'
local S = require 'autopair.specs'
local T = require 'autopair.types'
local U = require 'autopair.utils'

local M = {}

local ACTION = T.ACTION
local DELETION = T.DELETION
local KEY = T.KEY
local LWORD_VREG =
    vim.regex [=[\v%(\k+\s*$|[^[:keyword:][:space:]]+\s*$|\s+$|^$)]=]

-- }}} Specs {{{

---@type State
local state = nil

local function new_state()
    return {
        lengths = {
            del = { i = {}, c = {} },
            cr = {},
            space = { i = {}, c = {} },
        },
        specs = {
            insert = { i = {}, c = {} },
            del = { i = {}, c = {} },
            cr = {},
            space = { i = {}, c = {} },
        },
        inspos = { 1, 0 },
    }
end

---@param cache State
function M.load_state(cache)
    state = cache
end

function M.get_state()
    return state
end

--- }}} Predicates {{{

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

---Check if inverse of auto-indenting is triggered.
---
---@param ctx PairLineContext
---@return boolean
local function inverse_cr_triggered(ctx)
    if
        ctx.mode == 'c'
        or ctx.col ~= 1
        or ctx.row == 1
        or ctx.row == vim.fn.line '$'
        or ctx.line ~= ''
    then
        return false
    end

    local prev_line =
        vim.api.nvim_buf_get_lines(0, ctx.row - 2, ctx.row - 1, true)[1]
    local next_line =
        vim.api.nvim_buf_get_lines(0, ctx.row, ctx.row + 1, true)[1]

    for z in pairs(state.lengths.cr) do
        local olen, clen = U.uncantor(z)
        local ltext = vim.trim(prev_line):sub(-olen)
        local rtext = vim.trim(next_line):sub(1, clen)

        if state.specs.cr[ltext .. rtext] then
            return true
        end
    end

    return false
end

---@param atype PairActionType
---@param ctx PairContext
local function check_conditions(atype, ctx)
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

---@param atype PairInsertType
---@param ctx PairContext
local function insert_should(atype, ctx)
    -- must check if is in the right context
    if not insert_triggered(atype, ctx) then
        return false
    end
    return check_conditions(atype, ctx)
end

---Check if text adjacent to the cursor matches one of the specs.
---
---@param atype PairAdjacentType
---@param ctx PairLineContext
---@return boolean
local function adjacent_should(atype, ctx)
    -- must check if is in the right context
    local spec
    local lens = atype == ACTION.cr and state.lengths.cr
        or state.lengths[atype][ctx.mode]
    for z in pairs(lens) do
        local olen, clen = U.uncantor(z)
        local text = ctx.line:sub(ctx.col - olen, ctx.col + clen - 1)
        local trigs = atype == ACTION.cr and state.specs.cr
            or state.specs[atype][ctx.mode]
        spec = trigs[text]
        if spec then
            break
        end

        -- check space
        local space = ctx.line:sub(ctx.col - 1, ctx.col)
        if atype ~= ACTION.space and space == '  ' then
            local ltext = ctx.line:sub(ctx.col - 1 - olen, ctx.col - 2)
            local rtext = ctx.line:sub(ctx.col + 1, ctx.col + clen)
            spec = state.specs.space[ctx.mode][ltext .. rtext]
            if spec then
                ctx.spaced = true
                break
            end
        end
    end

    if not spec then -- not triggered
        return false
    end
    ---@cast ctx PairContext
    ctx.spec = setmetatable({}, { __index = spec })

    return check_conditions(atype, ctx)
end

-- }}} Actions {{{

---Delete by modifying context.
---
---@param ctx PairLineContext
---@param left integer
---@param right integer
---@return PairLineContext
local function del_dryrun(ctx, left, right)
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
local function count_del(ctx)
    local del_count = 0
    local i = 1
    local max = #ctx.spec.opener.text - 1

    if i <= max then
        local dry_ctx = vim.deepcopy(ctx)
        while i <= max do
            if adjacent_should(ACTION.del, dry_ctx) then
                -- simulate deletion
                local left = dry_ctx.spaced and 1 or #dry_ctx.spec.opener.text
                local right = dry_ctx.spaced and 1 or #dry_ctx.spec.closer.text
                del_dryrun(dry_ctx, left, right)

                del_count = del_count + right
                i = i + left
            else
                del_dryrun(dry_ctx, 1, 0)
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
local function trigger(key)
    local mode = vim.api.nvim_get_mode().mode
    local aspecs = state.specs.insert[mode][key]

    if mode == 'c' and not U.cmdtype_enabled() then
        return key
    end

    if aspecs.close then -- trigger closing first
        for _, spec in ipairs(aspecs.close) do
            local ctx = U.get_context(mode, spec, key)
            ---@cast ctx PairContext
            if insert_should(ACTION.close, ctx) then
                local length = #ctx.spec.closer.text + (ctx.spaced and 1 or 0)
                return KEY.right:rep(length)
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
                -- insert closer first to avoid <C-w> not recognising word
                return KEY.abbr
                    .. clears
                    .. ctx.spec.closer.text
                    .. KEY.left:rep(#ctx.spec.closer.text)
                    .. key
            end
        end
    end

    return key
end

---@return string
local function trigger_cr()
    local ctx = U.get_context 'i'
    if adjacent_should(ACTION.cr, ctx) then
        return KEY.undo .. KEY.abbr .. KEY.cr .. KEY.up .. KEY.eol .. KEY.cr
    else
        return KEY.abbr .. KEY.cr
    end
end

---@return string
local function trigger_del_char()
    local mode = vim.api.nvim_get_mode().mode
    local ctx = U.get_context(mode)

    if mode == 'c' and not U.cmdtype_enabled() then
        return KEY.bs
    elseif adjacent_should(ACTION.del, ctx) then
        return KEY.bs:rep(ctx.spaced and 1 or #ctx.spec.opener.text)
            .. KEY.del:rep(ctx.spaced and 1 or #ctx.spec.closer.text)
    elseif inverse_cr_triggered(ctx) then
        -- inverse of auto-indenting
        local next_line =
            vim.api.nvim_buf_get_lines(0, ctx.row, ctx.row + 1, true)[1]
        local del_count = #next_line:match '^%s*'
        return KEY.undo .. KEY.bs .. KEY.del:rep(del_count + 1)
    else
        return KEY.bs
    end
end

---@param deltype deletion
---@return string
local function trigger_del_chars(deltype)
    local mode = vim.api.nvim_get_mode().mode
    local ctx = U.get_context(mode)
    local keys = (mode == 'i' and KEY.undo or '')
        .. (deltype == DELETION.word and KEY.cw or KEY.cu)

    if mode == 'c' and not U.cmdtype_enabled() then
        return keys
    elseif inverse_cr_triggered(ctx) then
        -- inverse of auto-indenting
        local next_line =
            vim.api.nvim_buf_get_lines(0, ctx.row, ctx.row + 1, true)[1]
        local del_count = #next_line:match '^%s*'
        return keys .. KEY.del:rep(del_count + 1)
    end

    -- set start and end position of the deletion
    local ds = deltype == DELETION.word and LWORD_VREG:match_str(ctx.before)
        or 0
    local de = ctx.col - 1
    local irow, icol = unpack(state.inspos)
    if ctx.row == irow and ctx.col > icol + 1 then
        -- get the start position of the newly entered characters
        ---@cast ds integer
        ds = math.max(ds, icol)
    end

    -- calculate how many KEY.del should be inserted
    local del_count = 0
    local i = de
    while i >= ds + 1 do
        -- NOTE: It is difficult to find out whether or not whitespaces after
        -- the cursor is deleted by i_ctrl-u, so in Insert mode the space
        -- adjacent to the closer within the pair is ignored.

        if
            adjacent_should(ACTION.del, ctx)
            and not (mode == 'i' and deltype == DELETION.line and ctx.spaced)
        then
            local left = ctx.spaced and 1 or #ctx.spec.opener.text
            local right = ctx.spaced and 1 or #ctx.spec.closer.text

            if i - left < ds then
                -- opener to be deleted exceeds the leftmost limit of deletion
                -- e.g. <C-w> in <o--|--o>
                break
            end

            -- simulate auto-deleting
            del_dryrun(ctx, left, right)
            del_count = del_count + right
            i = i - left
        else -- no auto-deleting triggered; delete normally
            del_dryrun(ctx, 1, 0) -- simulate deletion
            i = i - 1
        end
    end

    return keys .. KEY.del:rep(del_count)
end

---@return string
local function trigger_del_line()
    return trigger_del_chars(DELETION.line)
end

---@return string
local function trigger_del_word()
    return trigger_del_chars(DELETION.word)
end

---@return string
local function trigger_space()
    local mode = vim.api.nvim_get_mode().mode
    local ctx = U.get_context(mode)

    if mode == 'c' and not U.cmdtype_enabled() then
        return KEY.abbr .. KEY.space
    elseif adjacent_should(ACTION.space, ctx) then
        return KEY.abbr .. KEY.space .. KEY.left .. KEY.space
    else
        return KEY.abbr .. KEY.space
    end
end

-- }}} Specs Setup {{{

---@param spec PairFullSpec
---@param mode PairModeType
---@param key string
---@param act PairInsertType
local function record_to(spec, mode, key, act)
    if not state.specs.insert[mode][key] then
        state.specs.insert[mode][key] = {}
    end
    if not state.specs.insert[mode][key][act] then
        state.specs.insert[mode][key][act] = {}
    end
    table.insert(state.specs.insert[mode][key][act], spec)
end

---Record triggering key for each pair action of `spec`.
---
---@param spec PairFullSpec
local function record(spec)
    -- insertion pairs
    for _, action in ipairs { ACTION.pair, ACTION.close } do
        for _, mode in ipairs { 'i', 'c' } do
            if spec[action][mode].enable then
                local key = action == ACTION.pair and spec.opener.key
                    or spec.closer.key
                record_to(spec, mode, key, action)
            end
        end
    end

    -- adjacent pairs
    local pair = spec.opener.text .. spec.closer.text
    local z = U.cantor(#spec.opener.text, #spec.closer.text)

    for _, action in ipairs { ACTION.del, ACTION.space } do
        for _, mode in ipairs { 'i', 'c' } do
            if spec[action][mode].enable then
                state.specs[action][mode][pair] = spec
                state.lengths[action][mode][z] = true
            end
        end
    end

    if spec.cr.enable then
        state.specs.cr[pair] = spec
        state.lengths.cr[z] = true
    end
end

---@param buf integer
local function set_keymaps(buf)
    -- set mappings for auto-pairing/-closing triggers
    for mode, kspec in pairs(state.specs.insert) do
        for key in pairs(kspec) do
            U.exprmap {
                mode = { mode },
                lhs = key,
                rhs = function()
                    return trigger(key)
                end,
                desc = 'Autopair for ' .. key,
                buf = buf,
            }
        end
    end

    -- set mappings for indentation, deletion, and spacing
    local opts = {
        cr = {
            lhs = KEY.cr,
            rhs = trigger_cr,
            desc = KEY.cr .. ' for auto-indenting',
        },
        bs = {
            lhs = KEY.bs,
            rhs = trigger_del_char,
            desc = KEY.bs .. ' for auto-deleting (char-wise)',
        },
        ch = {
            lhs = KEY.ch,
            rhs = trigger_del_char,
            desc = KEY.ch .. ' for auto-deleting (char-wise)',
        },
        cu = {
            lhs = KEY.cu,
            rhs = trigger_del_line,
            desc = KEY.cu .. ' for auto-deleting (line-wise)',
        },
        cw = {
            lhs = KEY.cw,
            rhs = trigger_del_word,
            desc = KEY.cw .. ' for auto-deleting (word-wise)',
        },
        space = {
            lhs = KEY.space,
            rhs = trigger_space,
            desc = KEY.space .. ' for auto-spacing',
        },
    }

    for key, mapopts in pairs(opts) do
        local conf = C.config.mapping[key]
        local mode = {}

        if key == 'cr' and conf or conf.i then
            table.insert(mode, 'i')
        end
        if key ~= 'cr' and conf.c then
            table.insert(mode, 'c')
        end

        if #mode > 0 then
            mapopts.mode = mode
            mapopts.buf = buf
            U.exprmap(mapopts)
        end
    end
end

local function watch_insert_start()
    vim.api.nvim_create_autocmd('InsertEnter', {
        group = vim.api.nvim_create_augroup('autopair.nvim', { clear = true }),
        pattern = '*',
        callback = function()
            state.inspos = vim.api.nvim_win_get_cursor(0)
        end,
        desc = 'Get position where the last Insert mode started',
    })
end

---@param buf integer
function M.setup(buf)
    state = new_state()

    -- record triggers for all qualified specs
    local ft = vim.api.nvim_get_option_value('filetype', { buf = buf })
    for _, s in ipairs(S.specs) do
        if U.filetype_qualified(s, ft) then -- spec enabled in current buffer
            record(s)
        end
    end

    set_keymaps(buf)

    watch_insert_start()
end

return M
