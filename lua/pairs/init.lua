local A = require 'pairs.actions'
local C = require 'pairs.config'
local S = require 'pairs.specs'
local recipe = require 'pairs.recipe'

local M = {
    add = S.add,
}

---@type table<integer, State>
local cache = {}

local function on_attach()
    local buf = vim.api.nvim_get_current_buf()
    if cache[buf] then -- already attached
        A.load_state(cache[buf])
        return
    end

    -- filetype check
    local ft = vim.api.nvim_get_option_value('filetype', { buf = buf })
    if vim.list_contains(C.config.filetypes_excluded, ft) then
        return
    end

    -- buftype check
    local bt = vim.api.nvim_get_option_value('buftype', { buf = buf })
    if vim.list_contains(C.config.buftypes_excluded, bt) then
        return
    end

    -- float window check
    if ft == '' and vim.api.nvim_win_get_config(0).relative ~= '' then
        return
    end

    if bt == 'help' and ft == '' then -- skip initialising help buffer
        return
    end

    -- setup keymaps and state
    A.setup(buf)

    cache[buf] = A.get_state()
end

local function on_detach(data)
    if cache[data.buf] then
        cache[data.buf] = nil
    end
end

---@param opts? APConfig
function M.setup(opts)
    C.configure(opts)
    if not C.config.enabled then
        return
    end

    -- initialise
    if C.config.spec.enable_default_specs then -- add default specs
        S.add(recipe)
    end
    on_attach() -- attach to the current buffer

    local group =
        vim.api.nvim_create_augroup('pairs_nvim_buf', { clear = true })
    vim.api.nvim_create_autocmd('BufEnter', {
        group = group,
        pattern = '*',
        callback = on_attach,
    })
    vim.api.nvim_create_autocmd('BufDelete', {
        group = group,
        pattern = '*',
        callback = on_detach,
    })
end

return M
