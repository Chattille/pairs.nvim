local C = require 'autopair.config'
local ACTION = require('autopair.types').ACTION

local M = {}

---Record all transformed PairSpecs.
---
---@type PairFullSpec[]
M.specs = {}

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
---@param only_cmap? boolean Specified exclusively for cmap.
---@return PairFullCond
local function get_full_mode_cond(cond, mode, atype, only_cmap)
    ---@type boolean
    local use_default = C.config.spec.enable_default_conditions

    if mode == 'i' then
        local enable
        if atype == ACTION.space then
            enable = C.config.spec.default_space
        else
            enable = true
        end

        if cond == nil then
            return { enable = enable, default = use_default }
        elseif type(cond) == 'boolean' then
            return { enable = cond, default = use_default }
        elseif type(cond) == 'function' then
            return { cond, enable = true, default = use_default }
        else -- list
            if cond.enable == nil then
                if #cond == 0 then
                    ---@cast enable -?
                    cond.enable = enable
                else
                    cond.enable = true
                end
            end

            if cond.default == nil then
                cond.default = use_default
            end

            return cond
        end
    else -- cmdline
        ---@type boolean
        local use_cmap = C.config.spec.default_cmap
        local enable
        if atype == ACTION.space then
            enable = C.config.spec.default_space and use_cmap
        else
            enable = use_cmap
        end

        if cond == nil then
            return { enable = enable, default = use_default }
        elseif type(cond) == 'boolean' then
            return { enable = cond, default = use_default }
        elseif type(cond) == 'function' then
            if only_cmap or use_cmap then
                return { cond, enable = true, default = use_default }
            else
                return { enable = false, default = use_default }
            end
        else -- list
            if not only_cmap and not use_cmap then
                return { enable = false, default = use_default }
            end

            if cond.enable == nil then
                if #cond == 0 then
                    ---@cast enable -?
                    cond.enable = enable
                else -- one or more conditions present for cmdline imply true
                    cond.enable = true
                end
            end

            if cond.default == nil then
                cond.default = use_default
            end

            return cond
        end
    end
end

---@param action PairActionSpec
---@param atype PairActionType
---@return PairActionFullSpec|PairFullCond
local function get_full_action_spec(action, atype)
    if atype == ACTION.cr then
        ---@cast action PairCond
        return get_full_mode_cond(action, 'i', atype)
    end

    -- pair, close, and del
    if type(action) ~= 'table' then
        return {
            i = get_full_mode_cond(action, 'i', atype),
            c = get_full_mode_cond(action, 'c', atype),
        }
    else -- list
        if action.i == nil and action.c == nil then
            -- action spec for both modes
            return {
                ---@diagnostic disable-next-line: param-type-mismatch
                i = get_full_mode_cond(action, 'i', atype),
                ---@diagnostic disable-next-line: param-type-mismatch
                c = get_full_mode_cond(action, 'c', atype),
            }
        else -- action spec for separate modes
            return {
                i = get_full_mode_cond(action.i, 'i', atype),
                c = get_full_mode_cond(action.c, 'c', atype, true),
            }
        end
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
    if type(spec) ~= 'table' then
        spec = { spec }
    end

    for _, s in ipairs(spec) do
        validate(s)
        -- convert to full spec
        table.insert(M.specs, get_full_spec(s))
    end
end

return M
