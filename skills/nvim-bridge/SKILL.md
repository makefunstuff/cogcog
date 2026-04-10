---
name: nvim-bridge
description: Query and control a running Neovim editor via the cogcog bridge. Use when you need the user's current editor state — buffer content, cursor position, visible windows, quickfix list, LSP diagnostics — or to navigate them to a file. Requires cogcog plugin loaded in Neovim.
argument-hint: <what to check or do in neovim>
allowed-tools: [Bash, Read]
version: 1.0.0
---

# Neovim Bridge

Interact with the user's running Neovim editor via `~/Work/tools/nv`.

## Request
$ARGUMENTS

## Tool

```bash
~/Work/tools/nv <subcommand> [args...]
```

### Subcommands

| Command | What it does |
|---------|-------------|
| `nv status` | Check if Neovim is reachable, show cwd and current buffer |
| `nv context` | Full editor state: buffer, cursor, ±10 lines, visible windows, quickfix, diagnostics |
| `nv buffer [path]` | Read buffer content (current buffer if path omitted) |
| `nv buffers` | List all loaded file buffers with filetypes and line counts |
| `nv diagnostics [path]` | LSP diagnostics — all buffers or filtered by path |
| `nv goto <path> [line]` | Open file at line in the user's Neovim |
| `nv eval <lua-expr>` | Evaluate arbitrary Lua expression in Neovim (use `[[...]]` for strings) |

### Environment

| Var | Default | Purpose |
|-----|---------|---------|
| `COGCOG_NVIM_SOCKET` | `/tmp/cogcog.sock` | Neovim server socket path |

### Prerequisites

1. Neovim must be running with the cogcog plugin loaded (`lazy = false` in plugin spec)
2. Plugin auto-starts `vim.fn.serverstart("/tmp/cogcog.sock")` on load
3. The `nv` tool uses `nvim --server --remote-expr` to call `cogcog.bridge` Lua module

## Steps

### 1. Check connection
```bash
~/Work/tools/nv status
```
If disconnected, tell the user to restart Neovim or check their socket path.

### 2. Get context (most common)
```bash
~/Work/tools/nv context
```
Returns JSON with: `cwd`, `buffer`, `cursor`, `filetype`, `lines` (±10 around cursor), `windows`, `quickfix`, `diagnostics`, `modified_buffers`.

### 3. Read specific buffer
```bash
~/Work/tools/nv buffer                           # current buffer
~/Work/tools/nv buffer terraform/utils/iam.ts    # specific file (must be loaded)
```
Returns: `name`, `filetype`, `lines` (full content), `modified`, `line_count`.

### 4. Check diagnostics
```bash
~/Work/tools/nv diagnostics                      # all buffers
~/Work/tools/nv diagnostics terraform/utils/iam.ts  # one file
```
Returns array of: `filename`, `lnum`, `col`, `severity`, `message`, `source`.

### 5. Navigate user to a file
```bash
~/Work/tools/nv goto terraform/utils/iam.ts 42
```
Opens the file at line 42 in the user's Neovim. Path is relative to Neovim's cwd.

### 6. Advanced: eval arbitrary Lua
```bash
~/Work/tools/nv eval "vim.fn.getcwd()"
~/Work/tools/nv eval "vim.api.nvim_buf_line_count(0)"
```
Use for one-off queries not covered by the bridge methods.

## Output format

All commands return JSON (piped through `python3 -m json.tool`). Parse fields directly.

## Notes

- Buffer paths are relative to Neovim's cwd (shown in `nv context` → `cwd`)
- `nv buffer` only reads **loaded** buffers — if a file isn't open in Neovim, use `read` tool instead
- `nv goto` is async — the file opens in Neovim after the command returns
- Diagnostics require LSP to be running in Neovim for that filetype
- The socket is a Unix domain socket — only works on the same machine
