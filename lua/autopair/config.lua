local M = {}

---Current global config.
---
---@type APFullConfig
M.config = {
    enabled = true,
    filetypes_excluded = { 'TelescopePrompt' },
    buftypes_excluded = {},
    fastwrap = {
        enable = { i = false, c = false },
    },
    mapping = {
        cr = true,
        bs = { i = true, c = true },
        ch = { i = false, c = false },
        cu = { i = true, c = false },
        cw = { i = true, c = false },
        space = { i = true, c = false },
    },
    spec = {
        default_cmap = false,
        default_space = false,
        enable_default_conditions = true,
        enable_default_specs = true,
    },
    condition = {
        ignore_pair_if_before = [=[[%w%'%"]]=],
    },
}

---@param config APConfig
local function validate(config)
    vim.validate {
        enabled = { config.enabled, 'boolean', true },
        filetypes_excluded = { config.filetypes_excluded, 'table', true },
        buftypes_excluded = { config.buftypes_excluded, 'table', true },
        fastwrap = { config.fastwrap, 'table', true },
        mapping = { config.mapping, 'table', true },
        spec = { config.spec, 'table', true },
        condition = { config.condition, 'table', true },
    }

    if config.fastwrap then
        vim.validate {
            enable = { config.fastwrap.enable, { 'boolean', 'table' }, true },
        }
    end

    if config.mapping then
        vim.validate {
            bs = { config.mapping.bs, { 'boolean', 'table' }, true },
            ch = { config.mapping.ch, { 'boolean', 'table' }, true },
            cr = { config.mapping.cr, { 'boolean', 'table' }, true },
            cu = { config.mapping.cu, { 'boolean', 'table' }, true },
            cw = { config.mapping.cw, { 'boolean', 'table' }, true },
            space = { config.mapping.space, { 'boolean', 'table' }, true },
        }
    end

    if config.spec then
        vim.validate {
            default_cmap = { config.spec.default_cmap, 'boolean', true },
            default_space = { config.spec.default_space, 'boolean', true },
            enable_default_conditions = {
                config.spec.enable_default_conditions,
                'boolean',
                true,
            },
            enable_default_specs = {
                config.spec.enable_default_specs,
                'boolean',
                true,
            },
        }
    end

    if config.condition then
        vim.validate {
            ignore_pair_if_before = {
                config.condition.ignore_pair_if_before,
                'string',
                true,
            },
        }
    end
end

---@param opts? APMappingConfig
---@return APMappingFullConfig
local function get_full_mapping_conf(opts)
    if not opts then
        return {}
    end

    for name, value in pairs(opts) do
        if name ~= 'cr' then
            if type(value) == 'boolean' then
                opts[name] = { i = value, c = value }
            end
        end
    end
    ---@diagnostic disable-next-line: return-type-mismatch
    return opts
end

---@param opts? APConfig
function M.configure(opts)
    opts = opts or {}
    validate(opts)

    -- convert to full mapping config
    ---@type APMappingFullConfig
    opts.mapping = get_full_mapping_conf(opts.mapping)

    M.config = vim.tbl_deep_extend('force', M.config, opts)
end

return M
