---
name: hermes-cogcog
description: Neovim integration via CogCog — exposes nvim_* tools using a tiny Python bridge (pynvim). No Node.js, no MCP, no build step.
version: 0.3.0
author: Hermes Agent
license: MIT
platforms: [linux, macos]
metadata:
  hermes:
    tags: [neovim, cogcog, editor]
prerequisites:
  commands: [python3]
  python_packages: [pynvim]
  environment:
    COGCOG_NVIM_SOCKET: "/tmp/cogcog.sock"
---

# CogCog Skill for Hermes

Connects Hermes to your active Neovim session via the CogCog bridge module.
Calls `require("cogcog.bridge")` Lua functions directly over the Neovim RPC socket.
Works alongside the pi extension — no modifications to CogCog or pi needed.

## Prerequisites

1. **Neovim** running with CogCog plugin loaded
2. **RPC socket** at `/tmp/cogcog.sock` (start Neovim with `--listen /tmp/cogcog.sock` or set `g:cogcog_socket`)
3. **pynvim** Python package: `pip install pynvim`

## Tools

All tools call the corresponding function in `lua/cogcog/bridge.lua`. Run via:

```
python3 scripts/cogcog_bridge.py <tool> [json_args]
```

| Tool | Bridge function | Args | Description |
|------|----------------|------|-------------|
| `status` | — | `{}` | Check Neovim connection (doesn't need a running session) |
| `get_context` / `context` | `get_context()` | `{}` | Full editor state: cwd, buffer, cursor, windows, quickfix, diagnostics |
| `get_buffer` / `buffer` | `get_buffer(path)` | `{path?}` | Read buffer contents. Omit path for current buffer |
| `get_buffers` / `buffers` | `get_buffers()` | `{}` | List all loaded file buffers |
| `get_diagnostics` / `diagnostics` | `get_diagnostics(path?)` | `{path?}` | LSP diagnostics. All buffers if path omitted |
| `goto_file` / `goto` | `goto_file(path, line?)` | `{path, line?}` | Open file and jump to line in Neovim |
| `set_quickfix` / `quickfix` | `set_quickfix(items, title?)` | `{items, title?}` | Set quickfix list in Neovim |
| `exec` | `exec(cmd)` | `{cmd}` | Run a Vim command (e.g. `write`, `make`) |
| `notify` | `notify(msg, level?)` | `{msg, level?}` | Show vim.notify popup (levels: error, warn, info) |

## Example Usage

```
# Get current editor context
python3 scripts/cogcog_bridge.py context

# Read a specific buffer
python3 scripts/cogcog_bridge.py buffer '{"path": "src/main.py"}'

# Get diagnostics for all files
python3 scripts/cogcog_bridge.py diagnostics

# Jump to a file at line 42
python3 scripts/cogcog_bridge.py goto '{"path": "src/main.py", "line": 42}'

# Set quickfix list
python3 scripts/cogcog_bridge.py quickfix '{"items": [{"filename": "main.py", "lnum": 10, "text": "todo"}, {"filename": "main.py", "lnum": 20, "text": "fix"}], "title": "hermes"}'

# Run a vim command
python3 scripts/cogcog_bridge.py exec '{"cmd": "write"}'

# Check connection status
python3 scripts/cogcog_bridge.py status
```

## How It Works

```
Neovim (cogcog plugin + bridge.lua)
    |
    |-- RPC socket /tmp/cogcog.sock
    |
    +--> pi extension (claims channel, receives events)
    |
    +--> cogcog_bridge.py (calls bridge.lua functions, no claim needed)
         ^
         |
    Hermes (via terminal tool)
```

The Python script attaches to Neovim via `pynvim.attach("socket")`, calls `require("cogcog.bridge").<function>(...)` using `exec_lua`, and prints results as JSON. It detaches after each call — no persistent process needed.

Pi continues to receive CogCog events via its claimed RPC channel. Hermes just calls bridge functions ad-hoc.

## Troubleshooting

**"Socket not found"**
- Start Neovim with: `nvim --listen /tmp/cogcog.sock`
- Or add to your init.lua: `vim.g.cogcog_socket = "/tmp/cogcog.sock"`
- Verify: `ls -la /tmp/cogcog.sock`

**"Failed to connect"**
- Ensure Neovim is running and the socket exists
- Check the socket path matches (env var `COGCOG_NVIM_SOCKET`)

**"module 'cogcog.bridge' not found"**
- Make sure CogCog plugin is loaded in Neovim
- Run `:lua print(require("cogcog.bridge").get_context())` in Neovim to test

## Environment

| Variable | Default | Purpose |
|----------|---------|---------|
| `COGCOG_NVIM_SOCKET` | `/tmp/cogcog.sock` | Neovim RPC socket path |