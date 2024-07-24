local conds = require 'autopair.conds'

---@param ctx PairContext
local function quote_not_after(ctx)
    return conds.notafter '%w'(ctx)
end

---@type PairSpec[]
return {
    {
        opener = '(',
        closer = ')',
        nestable = true,
        pair = true,
        close = true,
        del = true,
        space = true,
    },
    {
        opener = '[',
        closer = ']',
        filetype = '-markdown',
        nestable = true,
        pair = true,
        close = true,
        del = true,
        space = true,
    },
    {
        opener = '[',
        closer = ']',
        filetype = 'markdown',
        nestable = true,
        pair = true,
        close = true,
        del = true,
        cr = false,
        space = { i = false, c = true },
    },
    {
        opener = '{',
        closer = '}',
        nestable = true,
        pair = true,
        close = true,
        del = true,
        space = true,
    },
    {
        opener = '<',
        closer = '>',
        filetype = { 'html', 'markdown', 'svg', 'xml' },
        nestable = true,
    },
    {
        opener = '<!--',
        closer = '-->',
        filetype = { 'html', 'markdown' },
        cr = false,
        space = { i = true, c = false },
    },
    -- TODO regex pairs
    {
        opener = '>[%w%s]*$',
        closer = '^%s*</',
        regex = true,
        filetype = {
            'astro',
            'blade',
            'html',
            'htmldjango',
            'javascript',
            'javascriptreact',
            'php',
            'rescript',
            'svelte',
            'typescript',
            'typescriptreact',
            'vue',
            'xml',
        },
        pair = false,
        close = false,
        del = false,
    },

    {
        opener = "'",
        closer = "'",
        pair = quote_not_after,
        close = true,
        del = true,
        cr = false,
    },
    {
        opener = '"',
        closer = '"',
        pair = quote_not_after,
        close = true,
        del = true,
        cr = false,
    },
    {
        opener = '`',
        closer = '`',
        filetype = {
            'javascript',
            'javascriptreact',
            'markdown',
            'typescript',
            'typescriptreact',
            'svelte',
            'vue',
        },
        pair = { i = quote_not_after },
        cr = false,
    },
}
