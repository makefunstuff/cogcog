# Baseline Notes

This file is no longer a changelog of completed fixes.
An older version of this document contained several stale claims that did not match the repository.

Use this file as a quick baseline note instead.

## Current reality

- `lua/cogcog/context.lua` previously contained duplicated helper definitions.
- Workbench state now persists to `.cogcog/workbench.md`.
- Legacy `.cogcog/session.md` is treated as a migration source, not the canonical path.
- There is still no `lua/cogcog/tests.lua` module.
- The repository test entrypoint is the root `tests.lua` file.

## Running the current tests

From inside Neovim with the plugin on `runtimepath`:

```vim
:luafile tests.lua
```

Or headlessly:

```bash
nvim --headless -u NONE \
  "+set rtp+=/path/to/cogcog" \
  "+cd /path/to/cogcog" \
  "+luafile tests.lua"
```

## Why this file exists

The goal is to avoid trusting stale internal notes over the actual codebase.
If behavior changes, update the code, vimdoc, README, and this note together.
