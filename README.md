# Pairs.nvim

Another simple autopair plugin for NeoVim.

Heavily inspired by [nvim-autopairs][nvim_autopairs] and [auto-pairs][auto_pairs].

## Default Config

```lua
require('pairs').setup {
    -- Enable the plugin. Default `true`.
    enabled = true,
    -- List of filetypes to disable the plugin.
    filetypes_excluded = { 'TelescopePrompt' },
    -- List of buftypes to disable the plugin.
    buftypes_excluded = {},
    mapping = {
        -- Enable keymap for <CR>.
        cr = true,
        -- Enable keymap for <BS>. Default `true` for both imap and cmap.
        bs = { i = true, c = true },
        -- Enable keymap for <C-h>.
        ch = { i = false, c = false },
        -- Enable keymap for <C-u>.
        cu = { i = true, c = false },
        -- Enable keymap for <C-w>.
        cw = { i = true, c = false },
        -- Enable keymap for <Space>.
        space = { i = true, c = false },
        -- Any config above will be ignored if there is already a buffer keymap.
    },
    -- Config for every pair spec.
    spec = {
        -- Enable cmap by default for added pairs if the pair action
        -- is not configured.
        default_cmap = false,
        -- Command-line types to enable the pair. See `:help getcmdtype()`.
        -- The default includes all cmdline types but forward and backward
        -- search command (i.e. `/` and `?`).
        enabled_cmdtype = ':>@-=',
        -- Enable space action when it is omitted.
        default_space = false,
        -- Enable default condition functions from `pairs.conds`.
        enable_default_conditions = true,
        -- Include default specs from `pairs.recipe`.
        enable_default_specs = true,
    },
    -- Config for default conditions.
    condition = {
        -- Disable auto-pairing when the cursor is placed before the pattern.
        ignore_pair_if_before = [=[[%w%'%"]]=],
        -- Check bracket balance on the current line for nestable pairs.
        check_inline_balance = true,
    },
}
```

### `<C-w>` and `<C-u>`

Pairs.nvim can create keymaps for `<C-w>` and `<C-u>`. They will try to delete pairs properly within their deletion range.

```
before              insert   after
=================   ======   ============
hello world{{|}}    <C-w>    hello world|
-----------------   ------   ------------
print({ | })        <C-w>    print|
-----------------   ------   ------------
world{{|}a}         <C-w>    world|a}
```

`<C-u>`'s behaviour may be slightly different from one's expectation. As it is difficult to detect whether or not whitespaces right after the cursor are deleted by `<C-u>`, the keymap to `<C-u>` will ignore `space` action.

```
before   insert    after
======   ======    ======
{  |}    <C-u>     |
------   ------    ------
{ | }    <C-u>     | }
                or |}     in some files
```

## Custom Pairs

```lua
-- Add a single pair spec or a list of specs.
require('pairs').add {
    -- Specify opener and closer for the pair.
    opener = '<!--',
    closer = { text = '-->', key = '>' },

    -- Specify filetype or a list of filetypes to enable the pair.
    -- Prefix the filetype with a `-` to disable it.
    filetype = { 'markdown', 'html' },

    -- Specify whether the pair can be nested.
    -- Used to check inline balance.
    nestable = false,

    -- Configure five pair actions.
    pair = true,
    close = true,
    del = true,
    cr = false,
    space = true,
}
```

### `opener` and `closer`

Pair delimiters are specified via `opener` and `closer`, which can be:

1. a string that specifies the content;
2. or `{ text: string, key?: string }`, where `text` is the content and `key` is used to create keymaps for auto-pairing (`opener`) or -closing (`closer`). If `key` is omitted, the last character of `text` will be used.
   
   ```lua
   {
       -- press `-` to insert the opener and closer
       opener = '<!--',
       -- press `,` to move out of the pair
       closer = { text = '-->', key = ',' },
   }
   ```

### `filetype`

Specify `filetype` to enable the pair in given filetypes. This can be:

1. a string;
   
   ```lua
   filetype = '-markdown',
   ```

2. or a list of strings.
   
   ```lua
   filetype = { 'markdown', 'html', 'xml' },
   ```

Each filetype can be prefixed by a `-` to disable the pair in the given filetype. This is inspired by [nvim-autopairs][nvim_autopairs].

### `nestable`

`nestable` specifies whether the pair can be nested. It can be:

1. a boolean;
2. or `{ i?: boolean, c?: boolean }`;

If enabled, Pairs.nvim will check whether brackets are balanced for the current line excluding those in quotes or after a backslash. If omitted, `nestable` will be `false` for both modes.

### Pair Actions

I love how [nvim-autopairs][nvim_autopairs] gives me granular control over the completion, deletion, and indentation of a pair, so I have implemented it in a similar way.

The pair spec can specify five kinds of pair actions:

- `pair` specifies conditions for auto-completing the pair.
  
  ```
  before   insert   after
  ======   ======   =====
  |        (        (|)
  ```

- `close` specifies conditions for auto-moving out of the pair.
  
  ```
  before     insert   after
  ========   ======   =====
  <!--|-->   >        <!---->|
  ```

- `del` specifies conditions for auto-deleting the pair.
  
  ```
  before    insert   after
  =======   ======   =====
  '''|'''   <BS>     |
  ```

- `cr` specifies conditions for auto-indenting.
  
  ```
  before    insert   after
  =======   ======   =====
  {|}       <CR>     {
                         |
                     }
  -------   ------   -----
  {         <BS>     {|}   * also works for <C-w> and <C-u> if they are enabled
  |
  }
  ```

- `space` specifies conditions for adding spaces within the pair.
  
  ```
  before    insert    after
  =======   =======   =====
  <|>       <Space>   < | >
  -------   -------   -----
  < | >     <BS>      <|>
  -------   -------   -----
  < | >     >         <  >|
  ```

Each of them can be:

1. a boolean that enable/disable the pair in Insert and Cmdline mode;
   
   ```lua
   pair = true, -- enable auto-pairing for both modes
   del = false, -- disable auto-deleting for both modes
   ```

2. a function that checks whether the action should be triggered (will be used for both `i` and `c` modes);
   
   ```lua
   filetype = 'lua',
   pair = function(ctx)
       if vim.fn.mode() == 'i' and ctx.before:match '%-%-.*$' then
           -- disable auto-pairing in lua comments
           return false
       elseif vim.fn.getcmdtype() == ':' and ctx.before:match '^help' then
           -- disable auto-pairing in `:help` cmdline
           return false
       end
       return true
   end,
   ```

3. a list of condition functions (both modes);
   
   ```lua
   space = { -- check conditions for adding spaces
       function(ctx)
           -- ...
       end,
       function(ctx)
           -- ...
       end,
   },
   ```

4. or a table that specifies Insert and Cmdline mode separately (except `cr`, which only works in Insert mode). The value of each mode can be omitted or any of the value described in 1-3.
   
   ```lua
   pair = { i = true, c = false }, -- enable in Insert and disable in Cmdline
   space = { -- specify different conditions for Insert and Cmdline modes
       i = function(ctx)
           -- ...
       end,
       c = { --[[ ... ]] },
   },
   ```

If omitted, the pair action will be enabled for Insert mode by default and Cmdline mode will be determined by `spec.default_cmap`.

For reference, a condition function is a function that receives `ctx` and returns a boolean. If all condition functions return `true`, the pair action will be performed, otherwise the action will not be triggered. `ctx` is a table that contains:

```lua
---@class PairContext
---@field key    string  Character that triggers the pair action.
---@field mode   string  'i' (Insert) or 'c' (Cmdline).
---@field row    integer 1-based cursor row.
---@field col    integer 1-based cursor column.
---@field line   string  Current line content.
---@field before string  Text before the cursor.
---@field after  string  Text after the cursor.
---@field spaced boolean `space` action is active. Useful for deletion.
---@field spec   table   Pair spec as described above.
```

Default condition functions can be accessed via `require('pairs.conds')`.

## Disclaimer

This plugin is more like a hobby project or a practice project. As I am not a professional programmer, the repo will probably not be maintained actively. If you meet any problems when using the plugin or see some bad codes (you definitely will), feel free to share your thoughts, fork this repo, or use the following more professional, well-designed, and probably more feature-packed plugins:

- [Ultimate-autopair.nvim][ultimate_autopair]: autopair plugin for Insert and Cmdline modes with multiline and Tree-sitter support;
- [nvim-autopairs][nvim_autopairs]: the most popular autopair plugin for Insert mode with Tree-sitter support;
- [autoclose.nvim][autoclose_nvim]: minimalist autopair plugin for Insert and Cmdline modes;
- [auto-pairs][auto_pairs]: not for NeoVim and not maintained for a very long time, but still a great plugin and gives Pairs.nvim much inspiration;

## TODO

- [ ] regex pairs;
- [ ] Unicode pairs;
- [ ] Tree-sitter support;
- [ ] fastwrap support;
- [ ] help file;

[nvim_autopairs]: https://github.com/windwp/nvim-autopairs
[auto_pairs]: https://github.com/jiangmiao/auto-pairs
[ultimate_autopair]: https://github.com/altermo/ultimate-autopair.nvim
[autoclose_nvim]: https://github.com/m4xshen/autoclose.nvim
[mini_pairs]: https://github.com/echasnovski/mini.nvim/blob/main/readmes/mini-pairs.md
