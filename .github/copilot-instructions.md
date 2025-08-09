# Copilot Instructions for LDoc (Garry's Mod Fork)

## Project Overview
- This is a maintained fork of LDoc, specialized for Garry's Mod Lua codebases.
- Adds first-class support for LuaLS annotations, Garry's Mod realms, and repo-specific conveniences.
- Remains compatible with classic LDoc syntax and templates.

## Architecture & Key Components
- Main entry: `ldoc.lua` (invoked via `lua ldoc.lua <path>`)
Core logic: `ldoc/` directory (parsing, rendering, config)
  - `parse.lua`: Handles doc comment parsing for both LuaLS and LDoc styles.
  - `html.lua`, `markdown.lua`, `markup.lua`: Output formatting and rendering.
  - `config.ld`: Project-specific configuration, controls file inclusion, module mapping, and parsing style.
Templates: `docs/templates/` and `ldoc/html/` for custom output.

## Developer Workflows
**Build:**
  - Remove upstream LDoc: `luarocks remove ldoc`
  - Build: `luarocks make`
**Generate Docs:**
  - `lua ldoc.lua .` (output to `docs/html` or as set in `config.ld`)
**Testing (Custom Workflow):**
  - Run the PowerShell script `.rebuildTestDocsLimited.ps1` to rebuild and generate documentation. This script handles LDoc reinstallation, cleans old output, generates new docs, and copies assets. You **MUST** do this step to re-build the docs for testing.
  - For browser-based validation, use PlayWright to navigate to `file://<workspace-root>/docs/html/index.html` (replace `<workspace-root>` with your workspace directory) and verify documentation output.
**Config:**
  - Edit `config.ld` to control included files, module mapping, and parsing style (see README for examples)

## Project-Specific Patterns & Conventions
- **Annotation Styles:**
  - Supports both LuaLS (`---@param name type # desc`) and LDoc (`@tparam type name desc`) styles.
  - Parsing style can be forced via `config.ld` (e.g., `only_luals = true`).
- **Realm Inference:**
  - Infers Garry's Mod realms from file prefixes (`cl_`, `sv_`, `sh_`) or `@realm` tag.
- **Custom Types & Sections:**
  - Use `new_type("hook", ...)`, `new_type("panel", ...)` in config to create custom doc sections.
- **Exclusions:**
  - Exclude files/folders in `config.ld` under `exclude`.
- **Module Mapping:**
  - Map modules to files in `config.ld` under `module_file`.

## Integration Points & External Dependencies
- Relies on Lua and LuaRocks (Penlight library required).
- Compatible with Garry's Mod Lua codebases and LuaLS annotation standards.

## Examples
- See `README.md` for quickstart, annotation examples, and config samples.
- See `cityrp_tests/` for sample annotated code.

## Troubleshooting
- If documentation output is incorrect, check parsing style settings in `config.ld` and annotation style in code comments.
- For regressions, compare with upstream LDoc and open an issue with a minimal repro.

---

For further details, see `README.md` and comments in `config.ld` and `ldoc/parse.lua`.
