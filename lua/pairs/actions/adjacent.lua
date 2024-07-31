local T = require 'pairs.types'
local U = require 'pairs.utils'
local cm = require 'pairs.actions.common'
local st = require 'pairs.actions.state'

local ACTION = T.ACTION
local DELETION = T.DELETION
local KEY = T.KEY
local LWORD_VREG =
    vim.regex [=[\v%(\k+\s*$|[^[:keyword:][:space:]]+\s*$|\s+$|^$)]=]

local M = {}

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

    for _, z in ipairs(st.state.lengths.cr) do
        local olen, clen = U.uncantor(z)
        local ltext = vim.trim(prev_line):sub(-olen)
        local rtext = vim.trim(next_line):sub(1, clen)

        if st.state.specs.cr[ltext .. rtext] then
            return true
        end
    end

    return false
end

---@return string
function M.trigger_cr()
    local mode = U.get_mode()
    if mode ~= 'i' or vim.bo.buftype == 'prompt' then
        -- disable in other modes and prompt buftype
        return KEY.abbr .. KEY.cr
    end

    local ctx = U.get_context 'i'
    if cm.adjacent_should(ACTION.cr, ctx) then
        return KEY.abbr .. KEY.undo .. KEY.cr .. KEY.up .. KEY.eol .. KEY.cr
    else
        return KEY.abbr .. KEY.cr
    end
end

---@return string
function M.trigger_del_char()
    local mode = U.get_mode()
    if not U.mode_qualified(mode) then
        return KEY.bs
    end

    local ctx = U.get_context(mode)
    if cm.adjacent_should(ACTION.del, ctx) then
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
    local mode = U.get_mode()
    local keys = (mode == 'i' and KEY.undo or '')
        .. (deltype == DELETION.word and KEY.cw or KEY.cu)
    if not U.mode_qualified(mode) then
        return keys
    end

    local ctx = U.get_context(mode)
    if inverse_cr_triggered(ctx) then
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
    local irow, icol = unpack(st.state.inspos)
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
            cm.adjacent_should(ACTION.del, ctx)
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
            cm.del_dryrun(ctx, left, right)
            del_count = del_count + right
            i = i - left
        else -- no auto-deleting triggered; delete normally
            cm.del_dryrun(ctx, 1, 0) -- simulate deletion
            i = i - 1
        end
    end

    return keys .. KEY.del:rep(del_count)
end

---@return string
function M.trigger_del_line()
    return trigger_del_chars(DELETION.line)
end

---@return string
function M.trigger_del_word()
    return trigger_del_chars(DELETION.word)
end

---@return string
function M.trigger_space()
    local mode = U.get_mode()
    if not U.mode_qualified(mode) then
        return KEY.abbr .. KEY.space
    end

    local ctx = U.get_context(mode)
    if cm.adjacent_should(ACTION.space, ctx) then
        local left = mode == 'i' and KEY.nundo .. KEY.left or KEY.left
        return KEY.abbr .. KEY.space .. left .. KEY.space
    else
        return KEY.abbr .. KEY.space
    end
end

return M
