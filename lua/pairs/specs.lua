local A = require 'pairs.actions'
local C = require 'pairs.config'
local T = require 'pairs.types'
local U = require 'pairs.utils'

local ACTION = T.ACTION

local M = {}

--- }}} Helpers {{{

---@param spec PairSpec
local function validate(spec)
    vim.validate {
        opener = { spec.opener, { 'string', 'table' } },
        closer = { spec.closer, { 'string', 'table' } },
        regex = { spec.regex, 'boolean', true },
        filetype = { spec.filetype, { 'string', 'table' }, true },
        nestable = { spec.nestable, { 'boolean', 'table' }, true },
        pair = { spec.pair, { 'boolean', 'function', 'table' }, true },
        close = { spec.close, { 'boolean', 'function', 'table' }, true },
        del = { spec.del, { 'boolean', 'function', 'table' }, true },
        cr = { spec.cr, { 'boolean', 'function', 'table' }, true },
        space = { spec.space, { 'boolean', 'function', 'table' }, true },
    }

    if type(spec.opener) == 'table' then
        vim.validate {
            text = { spec.opener.text, 'string' },
            key = { spec.opener.key, 'string', true },
        }
    end

    if type(spec.closer) == 'table' then
        vim.validate {
            text = { spec.closer.text, 'string' },
            key = { spec.closer.key, 'string', true },
        }
    end

    if type(spec.nestable) == 'table' then
        vim.validate {
            i = { spec.nestable.i, 'boolean', true },
            c = { spec.nestable.c, 'boolean', true },
        }
    end
end

---@param delim PairDelimiterSpec
---@param regex boolean
---@return PairDelimiterFullSpec
local function get_full_delim_spec(delim, regex)
    if type(delim) == 'string' then
        if regex then
            return { text = delim, key = '' }
        else
            return { text = delim, key = delim:sub(#delim) }
        end
    elseif not delim.key then
        if regex then
            return { text = delim.text, key = '' }
        else
            return { text = delim.text, key = delim.text:sub(#delim.text) }
        end
    else
        return { text = delim.text, key = delim.key }
    end
end

---@param cond PairCond
---@param mode PairModeType
---@param atype PairActionType
---@return PairFullCond
local function get_mode_spec(cond, mode, atype)
    local cf = C.config.spec
    local use_default = cf.enable_default_conditions
    local enable
    if mode == 'i' then
        enable = U.ternary(atype == ACTION.space, cf.default_space, true)
    else
        enable = U.ternary(
            atype == ACTION.space,
            cf.default_space and cf.default_cmap,
            cf.default_cmap
        )
    end

    if cond == nil then
        return { enable = enable, default = use_default }
    elseif type(cond) == 'boolean' then
        return { enable = cond, default = use_default }
    elseif type(cond) == 'function' then
        return { cond, enable = true, default = use_default }
    else -- table
        if cond.enable == nil then
            cond.enable = U.ternary(#cond == 0, enable, true)
        end
        if cond.default == nil then
            cond.default = use_default
        end
        return cond
    end
end

---@param action PairActionSpec
---@param atype PairActionType
---@return PairActionFullSpec|PairFullCond
local function get_full_action_spec(action, atype)
    if atype == ACTION.cr then
        ---@cast action PairCond
        return get_mode_spec(action, 'i', atype)
    end

    -- pair, close, and del
    if type(action) ~= 'table' or (action.i == nil and action.c == nil) then
        -- terminal types or action spec for both modes
        return {
            ---@diagnostic disable-next-line: param-type-mismatch
            i = get_mode_spec(action, 'i', atype),
            ---@diagnostic disable-next-line: param-type-mismatch
            c = get_mode_spec(action, 'c', atype),
        }
    else -- action spec for separate modes
        return {
            i = get_mode_spec(action.i, 'i', atype),
            c = get_mode_spec(action.c, 'c', atype),
        }
    end
end

---@param ftspec? string|string[]
---@return string[]
local function get_full_filetype_spec(ftspec)
    if type(ftspec) == 'string' then
        return { ftspec }
    end
    return ftspec or {}
end

---@param sspec? boolean|table<PairModeType, boolean?>
---@return table<PairModeType, boolean>
local function get_full_switch_spec(sspec)
    if sspec == nil then
        return { i = false, c = false }
    elseif type(sspec) == 'boolean' then
        return { i = sspec, c = sspec }
    else -- table
        if sspec.i == nil then
            sspec.i = false
        end
        if sspec.c == nil then
            sspec.c = false
        end
        ---@diagnostic disable-next-line: return-type-mismatch
        return sspec
    end
end

---@param spec PairSpec
---@return PairFullSpec
local function get_full_spec(spec)
    -- full regex
    if spec.regex == nil then
        spec.regex = false
    end

    -- full delims
    spec.opener = get_full_delim_spec(spec.opener, spec.regex)
    spec.closer = get_full_delim_spec(spec.closer, spec.regex)

    -- full filetype
    spec.filetype = get_full_filetype_spec(spec.filetype)

    -- full switch
    if spec.regex == nil then
        spec.regex = false
    end
    spec.nestable = get_full_switch_spec(spec.nestable)

    -- full actions
    for _, action in pairs(ACTION) do
        spec[action] = get_full_action_spec(spec[action], action)
    end

    ---@diagnostic disable-next-line: return-type-mismatch
    return spec
end

---Add pair specs.
---
---@param spec PairSpec|PairSpec[] A spec or a list of specs.
function M.add(spec)
    if not vim.islist(spec) then
        spec = { spec }
    end

    ---@type PairFullSpec[]
    local fullspecs = {}
    for _, s in ipairs(spec) do
        validate(s)
        -- convert to full spec
        local fullspec = get_full_spec(s)
        table.insert(A.specs, fullspec)
        table.insert(fullspecs, fullspec)
    end

    A.setup_extend(fullspecs)
end

return M
