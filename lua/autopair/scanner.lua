local F = require 'autopair.filetype'

local M = {}

---@class Scanner
local Scanner = {}

---@param source string
function Scanner.new(source)
    local instance = {
        source = source,
        pos = 1,
        eol = #source,
    }
    return setmetatable(instance, { __index = Scanner })
end

---@param char string
---@return boolean
function Scanner:eat(char)
    if not self:isover() and char == self:peek(#char) then
        self:step(#char)
        return true
    end

    return false
end

---@param length? integer
---@return string
function Scanner:peek(length)
    return self.source:sub(self.pos, self.pos + (length or 1) - 1)
end

---@param length? integer
function Scanner:step(length)
    self.pos = self.pos + (length or 1)
end

function Scanner:isover()
    return self.pos > self.eol
end

---@param scanner Scanner
---@param ctx ScannerContext
function M.isquote(scanner, ctx)
    if ctx.quote then
        if scanner:eat(ctx.quote) then
            ctx.quote = nil
            return true
        end

        return false
    end

    local quotes = F.quote[vim.bo.filetype] or {}
    table.insert(quotes, '"')
    table.insert(quotes, "'")

    for _, quote in ipairs(quotes) do
        if scanner:eat(quote) then
            ctx.quote = quote
            return true
        end
    end

    return false
end

M.Scanner = Scanner
return M
