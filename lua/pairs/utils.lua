local C = require 'pairs.config'
local scn = require 'pairs.scanner'

local LUAP_SUB_VREG = vim.regex [[\v\%@<!%(\%\%)*\zs\%\d]]

local M = {}

---Ternary operator.
---
---@generic T
---@param cond any
---@param t T
---@param f T
---@return T
function M.ternary(cond, t, f)
    if cond then
        return t
    else
        return f
    end
end

---Cantor pairing function
---
---@param x integer
---@param y integer
---@return integer z
function M.cantor(x, y)
    return math.floor((x + y) * (x + y + 1) / 2) + y
end

---Inverse of Cantor pairing function.
---Reference [StackExchange](https://math.stackexchange.com/a/222835).
---
---@param z integer
---@return integer x
---@return integer y
function M.uncantor(z)
    local n = math.floor((math.sqrt(8 * z + 1) - 1) / 2)
    local y = z - math.floor(n * (n + 1) / 2)
    local x = n - y
    return x, y
end

---@param str string
function M.lua_escape(str)
    local escaped = str:gsub('([-*+?()%[%]%%.^$])', '%%%1')
    return escaped
end

---@param keys string Raw input string.
function M.feed(keys)
    vim.api.nvim_feedkeys(
        vim.api.nvim_replace_termcodes(keys, true, false, true),
        'n',
        false
    )
end

---@param buf integer
---@param mode PairModeType
---@param lhs string
function M.bufmap_exists(buf, mode, lhs)
    local bufmaps = vim.api.nvim_buf_get_keymap(buf, mode)
    for _, bufmap in ipairs(bufmaps) do
        ---@diagnostic disable-next-line: undefined-field
        if bufmap.lhs == lhs then
            return true
        end
    end
    return false
end

---Check cmdtype.
local function cmdtype_enabled()
    local cmdtype = vim.fn.getcmdtype()
    if cmdtype == '' or C.config.spec.enabled_cmdtype:find('%' .. cmdtype) then
        return true
    end
    return false
end

function M.get_mode()
    return vim.api.nvim_get_mode().mode:sub(1, 1)
end

---Get cursor and line info.
---
---@param mode PairModeType
---@return string # Current line.
---@return string # Text before cursor.
---@return string # Text after cursor.
---@return integer # 1-based cursor column.
---@return integer # 1-based cursor row.
local function get_curln(mode)
    local line
    local col
    local row
    if mode == 'i' then
        local cur = vim.api.nvim_win_get_cursor(0)
        row = cur[1]
        col = cur[2] + 1
        line = vim.api.nvim_get_current_line()
    else
        row = 1
        col = vim.fn.getcmdpos()
        line = vim.fn.getcmdline()
    end

    local before = line:sub(1, col - 1)
    local after = line:sub(col)
    return line, before, after, col, row
end

---@param mode PairModeType
---@param spec? PairFullSpec
---@param key? string
---@return PairContext|PairLineContext
function M.get_context(mode, spec, key)
    local line, before, after, col, row = get_curln(mode)
    local ctx = {
        col = col,
        row = row,
        mode = mode,
        line = line,
        after = after,
        before = before,
    }
    if spec then
        ctx.spec = setmetatable({}, { __index = spec })
    end
    if key then
        ctx.key = key
    end
    return ctx
end

---@param mode string
---@return boolean
function M.mode_qualified(mode)
    if mode ~= 'i' and mode ~= 'c' then
        return false
    end
    if mode == 'c' and not cmdtype_enabled() then
        return false
    end
    return true
end

---@param buf integer
---@return boolean
function M.buffer_qualified(buf)
    -- filetype check
    local ft = vim.api.nvim_get_option_value('filetype', { buf = buf })
    if vim.list_contains(C.config.filetypes_excluded, ft) then
        return false
    end

    -- buftype check
    local bt = vim.api.nvim_get_option_value('buftype', { buf = buf })
    if vim.list_contains(C.config.buftypes_excluded, bt) then
        return false
    end

    -- float window check
    if ft == '' and vim.api.nvim_win_get_config(0).relative ~= '' then
        return false
    end

    if bt == 'help' and ft == '' then -- skip initialising help buffer
        return false
    end

    return true
end

---Is the `spec` qualified in the `ft`?
---
---@param spec PairFullSpec
---@param ft string
---@return boolean
function M.filetype_qualified(spec, ft)
    if #spec.filetype == 0 then -- implies all filetypes
        return true
    end

    local has_enabled_list = false
    for _, f in ipairs(spec.filetype) do
        if f:sub(1, 1) == '-' and not has_enabled_list then
            if f:sub(2) == ft then -- is in disabled list
                return false
            end
        else
            has_enabled_list = true -- spec has an enabled list
            if f == ft then -- is in enabled list
                return true
            end
        end
    end

    if has_enabled_list then
        return false -- not included in the enabled list
    else
        return true -- not included in the disabled list
    end
end

---Get a list of capture group patterns ordered by their group index
---in the pattern. For example, it will return `{ '(=*(%s*))', '(%s*)' }`
---for Lua pattern `^(=*(%s*))$`.
---
---@param pat string
---@return string[]
function M.get_luap_groups(pat)
    local scanner = scn.Scanner.new(pat)
    local caps = {} -- list of group text
    local level = 0 -- group level
    local count = 0 -- group index
    local escaped = false
    local counts = {} -- group index stack
    local positions = {} -- stack of group start pos

    while not scanner:isover() do
        if escaped then
            escaped = false
            scanner:step()
        elseif scanner:eat '%' then
            escaped = true
        elseif scanner:eat '(' then
            level = level + 1
            count = count + 1

            table.insert(counts, count)
            table.insert(positions, scanner.pos - 1)
        elseif scanner:eat ')' then
            -- pop start pos
            local start = positions[#positions]
            if not start then
                error(
                    ('Invalid pattern "%s": Capture not opened for pos %d'):format(
                        pat,
                        scanner.pos - 1
                    )
                )
            end

            positions[#positions] = nil
            local capstr = pat:sub(start, scanner.pos - 1)

            -- pop group index
            local index = counts[#counts]
            -- record index-th group
            caps[index] = capstr
            counts[#counts] = nil
            level = level - 1
        else
            scanner:step()
        end
    end

    if #positions > 0 then
        error(
            ('Invalid pattern "%s": Capture unfinished for pos %d'):format(
                pat,
                positions[#positions]
            )
        )
    end

    return caps
end

---Replace '%1', '%2', etc. in `sub` with corresponding parts in `pat`
---
---@param pat string Lua pattern with capture groups.
---@param sub string Substitute pattern.
---@return string # Substitute pattern with '%1', etc. replaced.
function M.get_replaced_sub(pat, sub)
    local caps = M.get_luap_groups(pat)
    while true do
        local ms, me = LUAP_SUB_VREG:match_str(sub)
        if not ms or not me then
            break
        end

        local index = sub:sub(me, me)
        local repl = caps[tonumber(index)]
        if not repl then
            error(
                ('Invaild substitute "%s": no capture %d'):format(sub, index)
            )
        end

        sub = sub:sub(ms == 0 and 0 or 1, ms) .. repl .. sub:sub(me + 1)
    end

    return sub
end

return M
