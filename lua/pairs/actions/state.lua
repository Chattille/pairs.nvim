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
    M.state = cache
end

function M.get_state()
    return M.state
end

return M
