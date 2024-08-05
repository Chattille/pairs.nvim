local M = {}

---Record all transformed PairSpecs.
---
---@type PairFullSpec[]
M.specs = {}

---@type State
M.state = nil

function M.new_state()
    ---@type State
    return {
        lengths = { i = {}, c = {} },
        regex = {
            insert = {
                i = { close = {}, pair = {} },
                c = { close = {}, pair = {} },
            },
            adjacent = {},
        },
        specs = {
            insert = { i = {}, c = {} },
            adjacent = {},
        },
        inspos = { 1, 0 },
    }
end

---@param cache State
function M.load_state(cache)
    M.state = cache
end

function M.get_state()
    return M.state
end

return M
