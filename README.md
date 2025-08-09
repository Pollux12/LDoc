# LDoc (Garry's Mod fork)

This is a maintained fork of LDoc tailored for Garry’s Mod codebases. It adds some experimental (but mostly working!) support for LuaLS annotations, Garry’s Mod realms, and repo-specific conveniences while remaining compatible with classic LDoc syntax and templates.

Highlights:
- Dual-style parsing: supports both LuaLS (---@param name type # desc) and LDoc (@tparam type name desc) via mapping and hacky workarounds
- Garry’s Mod realm integration: infer client/server/shared from file prefixes (cl_, sv_, sh_) or via @realm
- Customization preserved: aliases, new types, and custom tags from config.ld work across both styles, or at least they should

## Quick start

1) Add a `config.ld` (see doc/doc.md for full options). Example minimal:

```lua
dir = "docs/html"
project = "My GMod Project"
format = "markdown"
-- Auto-detect both styles by default
-- only_luals = true    -- force only LuaLS
-- only_ldoc  = true    -- force only LDoc
```

2) Annotate code (either style works):

```lua
--- Check if the given entity is a player
--- @param ent Entity # The entity to check
--- @return boolean # Whether the entity is a player
function IsPlayer(ent)
    return ent and ent:IsValid() and ent:IsPlayer()
end
```

3) Generate docs:

```sh
lua ldoc.lua .
```

Output is written to `dir` (default `doc/`).

## LuaLS parsing controls

- Auto (default): both styles are parsed based on the comment content
- Force only LuaLS: `only_luals = true`
- Force only LDoc: `only_ldoc = true`
- Prefer LuaLS with fallback: `luals = true, ldoc_compat = true`
- Pure LuaLS: `luals = true` (no LDoc tag parsing in doc comments)
- Disable realm inference: `auto_realm = false`

See “LuaLS Annotation Support” in doc/doc.md for syntax and examples.

## Garry’s Mod specifics

- Realm badges: use `@realm client|server|shared|menu|global|clmenu` or rely on filename prefixes
- Custom types: `new_type`, `alias`, `tparam_alias` remain available and apply to both styles
- Custom hooks/panels: define with `new_type("hook", ...)`, `new_type("panel", ...)` and they’ll render in their own sections

## Compatibility and upstream

This fork is based on lunarmodules/LDoc and aims to remain compatible with common LDoc features while adding LuaLS and GMod-specific ergonomics. If you hit regressions, please open an issue with a small repro.

License remains as in upstream LDoc; see COPYRIGHT.

## Testing and running

I prefer just being able to quickly build the docs vs weird automated tests for this. Run these in terminal which has Lua in path:

`luarocks remove ldoc` - Remove LDoc if it already exists
`luarocks make` - Build LDoc
`ldoc.lua <path>` - Run LDoc against path
