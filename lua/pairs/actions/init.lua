local C = require 'pairs.config'
local T = require 'pairs.types'
local U = require 'pairs.utils'
local adj = require 'pairs.actions.adjacent'
local ins = require 'pairs.actions.insert'
local st = require 'pairs.actions.state'

local M = {
    specs = st.specs,
    load_state = st.load_state,
    get_state = st.get_state,
    trigger_cr = adj.trigger_cr,
    trigger_del_char = adj.trigger_del_char,
    trigger_del_line = adj.trigger_del_line,
    trigger_del_word = adj.trigger_del_word,
    trigger_space = adj.trigger_space,
}

local ACTION = T.ACTION
local KEY = T.KEY

-- }}} Specs Setup {{{

---@param spec PairFullSpec
---@param mode PairModeType
---@param key string
---@param act PairInsertType
local function record_to(spec, mode, key, act)
    if spec.regex then
        table.insert(st.state.regex.insert[mode][act], spec)
        return
    end

    if not st.state.specs.insert[mode][key] then
        st.state.specs.insert[mode][key] = {}
    end
    if not st.state.specs.insert[mode][key][act] then
        st.state.specs.insert[mode][key][act] = {}
    end
    table.insert(st.state.specs.insert[mode][key][act], spec)
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
    if spec.regex then
        table.insert(st.state.regex.adjacent, spec)
    else
        local pair = spec.opener.text .. spec.closer.text
        local z = spec.regex and 0
            or U.cantor(#spec.opener.text, #spec.closer.text)

        st.state.specs.adjacent[pair] = spec
        for _, mode in ipairs { 'i', 'c' } do
            if
                not spec.regex
                and not vim.list_contains(st.state.lengths[mode], z)
                and ( -- exclude if all actions are disabled for `mode`
                    spec.del[mode].enable
                    or spec.space[mode].enable
                    or U.ternary(mode == 'i', spec.cr.enable, false)
                )
            then
                table.insert(st.state.lengths[mode], z)
            end
        end
    end
end

---@param buf integer
local function set_keymaps(buf)
    -- set mappings for auto-pairing/-closing triggers
    for mode, kspec in pairs(st.state.specs.insert) do
        for key in pairs(kspec) do
            vim.keymap.set(mode, key, function()
                return ins.trigger(key)
            end, {
                buffer = buf,
                expr = true,
                desc = 'Autopair for ' .. key,
            })
        end
    end

    -- set mappings for indentation, deletion, and spacing
    local opts = {
        cr = {
            lhs = KEY.cr,
            rhs = M.trigger_cr,
            desc = KEY.cr .. ' for auto-indenting',
        },
        bs = {
            lhs = KEY.bs,
            rhs = M.trigger_del_char,
            desc = KEY.bs .. ' for auto-deleting (char-wise)',
        },
        ch = {
            lhs = KEY.ch,
            rhs = M.trigger_del_char,
            desc = KEY.ch .. ' for auto-deleting (char-wise)',
        },
        cu = {
            lhs = KEY.cu,
            rhs = M.trigger_del_line,
            desc = KEY.cu .. ' for auto-deleting (line-wise)',
        },
        cw = {
            lhs = KEY.cw,
            rhs = M.trigger_del_word,
            desc = KEY.cw .. ' for auto-deleting (word-wise)',
        },
        space = {
            lhs = KEY.space,
            rhs = M.trigger_space,
            desc = KEY.space .. ' for auto-spacing',
        },
    }

    for key, mapopts in pairs(opts) do
        local conf = C.config.mapping[key]
        local mode = {}

        if
            (key == 'cr' and { conf } or { conf.i })[1]
            and not U.bufmap_exists(buf, 'i', mapopts.lhs)
        then
            table.insert(mode, 'i')
        end
        if
            key ~= 'cr'
            and conf.c
            and not U.bufmap_exists(buf, 'c', mapopts.lhs)
        then
            table.insert(mode, 'c')
        end

        if #mode > 0 then
            vim.keymap.set(
                mode,
                mapopts.lhs,
                mapopts.rhs,
                { buffer = buf, expr = true, desc = mapopts.desc }
            )
        end
    end
end

local function watch_insert_start()
    vim.api.nvim_create_autocmd('InsertEnter', {
        group = vim.api.nvim_create_augroup('pairs.nvim', { clear = true }),
        pattern = '*',
        callback = function()
            st.state.inspos = vim.api.nvim_win_get_cursor(0)
        end,
        desc = 'Get position where the last Insert mode started',
    })
end

local function watch_input()
    vim.api.nvim_create_autocmd('InsertCharPre', {
        group = vim.api.nvim_create_augroup(
            'pairs.nvim_input',
            { clear = true }
        ),
        pattern = '*',
        callback = function()
            ins.trigger(vim.v.char, true)
        end,
    })
end

---@param specs PairFullSpec[]
---@return boolean # `true` for a successful setup.
function M.setup_extend(specs)
    local buf = vim.api.nvim_get_current_buf()
    if not U.buffer_qualified(buf) then
        return false
    end

    if not st.state then
        st.state = st.new_state()
    end

    -- sort specs first by opener length
    table.sort(specs, function(a, b)
        return #a.opener.text > #b.opener.text
    end)

    -- record triggers for all qualified specs
    local ft = vim.api.nvim_get_option_value('filetype', { buf = buf })
    for _, s in ipairs(specs) do
        if U.filetype_qualified(s, ft) then -- spec enabled in current buffer
            record(s)
        end
    end

    set_keymaps(buf)

    return true
end

---@return boolean # `true` for a successful setup.
function M.setup()
    st.state = st.new_state()

    -- setup all specs
    local succ = M.setup_extend(M.specs)
    if not succ then
        return false
    end

    watch_insert_start()
    watch_input()

    return true
end

return M
