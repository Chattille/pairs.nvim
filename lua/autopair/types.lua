---@meta autopair.types

local M = {}

---@enum action
M.ACTION = {
    close = 'close',
    cr = 'cr',
    del = 'del',
    pair = 'pair',
    space = 'space',
}

---@enum deletion
M.DELETION = {
    line = 0,
    word = 1,
}

---@enum key
M.KEY = {
    abbr = '<C-]>',
    bs = '<BS>',
    ch = '<C-h>',
    cr = '<CR>',
    cu = '<C-u>',
    cw = '<C-w>',
    del = '<Del>',
    down = '<Down>',
    eol = '<End>',
    esc = '<Esc>',
    left = '<Left>',
    right = '<Right>',
    space = '<Space>',
    undo = '<C-g>u',
    up = '<Up>',
}

return M

---@alias PairModeType 'c'|'i'
---@alias PairInsertType 'close'|'pair'
---@alias PairAdjacentType 'cr'|'del'|'space'
---@alias PairActionType PairInsertType|PairAdjacentType
---@alias ActionCondition fun(ctx: PairContext): boolean
---@alias PairCond boolean|ActionCondition|PairFullCond
---@alias PairActionSpec PairCond|table<PairModeType, PairCond>
---@alias PairDelimiterSpec string|{ text: string, key: string? }
---@alias KeymapConfig boolean|table<PairModeType, boolean?>
---@alias KeymapFullConfig table<PairModeType, boolean>
---@alias PairActionFullSpec table<PairModeType, PairFullCond>
---@alias PairFullCond { enable: boolean, default: boolean, [integer]: ActionCondition }
---@alias PairDelimiterFullSpec { text: string, key: string }
---@alias LengthSet table<integer, boolean>
---@alias SpecSet table<string, PairFullSpec>

---@class ExprOpts
---@field mode string[]
---@field lhs key
---@field rhs function
---@field desc string
---@field buf integer

---Specs to be triggered in different modes.
---Auto-pairing and -closing are stored in triggers.insert as sub-categories of
---the same key, because the same character may be used both for auto-pairing
---and -closing the same pair or different pairs.
---
---@class SpecRecord
---@field insert table<PairModeType, table<string, table<PairInsertType, PairFullSpec[]>>>
---@field del table<PairModeType, SpecSet>
---@field cr SpecSet
---@field space table<PairModeType, SpecSet>

---Record length of opener and/or closer.
---
---@class LengthRecord
---@field del table<PairModeType, LengthSet>
---@field cr LengthSet
---@field space table<PairModeType, LengthSet>

---@class DefaultCondition
---@field pair table<PairModeType, ActionCondition[]>
---@field close table<PairModeType, ActionCondition[]>
---@field cr ActionCondition[]
---@field del table<PairModeType, ActionCondition[]>
---@field space table<PairModeType, ActionCondition[]>

---@class State
---@field specs SpecRecord
---@field lengths LengthRecord
---(1, 0)-based position where the latest Insert mode started.
---@field inspos [number, number]

---@class APConfig
---@field enabled? boolean Enable the plugin. Default `true`.
---@field filetypes_excluded? string[] List of filetypes to disable the plugin.
---@field buftypes_excluded? string[] List of buftypes to disable the plugin.
---@field fastwrap? APFastWrapConfig Config for fast wrap.
---@field mapping? APMappingConfig Enable or disable keymaps.
---@field spec? APSpecConfig Config for default spec behaviours.
---@field condition? APConditionConfig Config for default conditions.

---@class APFastWrapConfig
---Enable keymap for fast wrap. Default `false` for both imap and cmap.
---@field enable? KeymapConfig

---@class APMappingConfig
---Enable keymap for <BS>. Default `true` for both imap and cmap.
---@field bs? KeymapConfig
---Enable keymap for <C-h>. Default `false` for both imap and cmap.
---@field ch? KeymapConfig
---Enable keymap for <CR>. Default `true`.
---@field cr? boolean
---Enable keymap for <C-u>. Default `true` for imap and `false` for cmap.
---@field cu? KeymapConfig
---Enable keymap for <C-w>. Default `true` for imap and `false` for cmap.
---@field cw? KeymapConfig
---Enable keymap for <Space>. Default `true` for imap and `false` for cmap.
---@field space? KeymapConfig

---@class APSpecConfig
---Enable cmap by default for added pairs if the action is not configured.
---Default `false`.
---@field default_cmap? boolean
---Enable space action when not specified. Default `false`.
---@field default_space? boolean
---Enable default conditions. Default `true`.
---@field enable_default_conditions? boolean
---Enable default specs. Default `true`.
---@field enable_default_specs? boolean

---@class APConditionConfig
---Disable auto-pairing when the cursor is placed before the pattern.
---@field ignore_pair_if_before? string

---@class (exact) APFullConfig
---@field enabled boolean
---@field filetypes_excluded string[]
---@field buftypes_excluded string[]
---@field fastwrap APFastWrapFullConfig
---@field mapping APMappingFullConfig
---@field spec APSpecFullConfig
---@field condition APConditionFullConfig

---@class (exact) APFastWrapFullConfig
---@field enable KeymapFullConfig

---@class (exact) APMappingFullConfig
---@field bs KeymapFullConfig
---@field ch KeymapFullConfig
---@field cr boolean
---@field cu KeymapFullConfig
---@field cw KeymapFullConfig
---@field space KeymapFullConfig

---@class (exact) APSpecFullConfig
---@field default_cmap boolean
---@field default_space boolean
---@field enable_default_conditions boolean
---@field enable_default_specs boolean

---@class (exact) APConditionFullConfig
---@field ignore_pair_if_before string

---Specifications to create auto pairs.
---
---@class PairSpec
---@field opener PairDelimiterSpec
---@field closer PairDelimiterSpec
---@field regex? boolean Pair is regex. Default `false`.
---@field filetype? string|string[] Filetype(s) for the pair to be applied.
---@field nestable? boolean|table<PairModeType, boolean?> Pair can be nested.
---@field pair? PairActionSpec Conditions for auto-pairing pairs.
---@field close? PairActionSpec Conditions for auto-closing out of pairs.
---@field del? PairActionSpec Conditions for auto-deleting pairs.
---@field cr? PairCond Conditions for auto-indenting pairs.
---@field space? PairActionSpec Conditions for auto-spacing pairs.

---@class (exact) PairFullSpec
---@field opener PairDelimiterFullSpec
---@field closer PairDelimiterFullSpec
---@field regex boolean
---@field filetype string[]
---@field nestable table<PairModeType, boolean>
---@field pair PairActionFullSpec
---@field close PairActionFullSpec
---@field del PairActionFullSpec
---@field cr PairFullCond
---@field space PairActionFullSpec

---@class PairLineContext
---@field col integer
---@field row integer
---@field mode PairModeType
---@field line string
---@field after string
---@field before string
---@field spaced? boolean

---@class PairContext : PairLineContext
---@field key? string
---@field spec PairFullSpec
