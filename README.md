# CogCog

LLM as a vim verb.

CogCog is a Neovim-side operator layer for [pi](https://github.com/badlogic/pi-mono).
It turns motions, selections, quickfix, and a scratch workbench into structured events,
then hands those events to a claimed pi session over Neovim RPC.

Two terminals, one loop:

```text
Terminal 1: nvim   scope, edits, quickfix, workbench
Terminal 2: pi     agent turns, tools, multi-file work
```

No chat panel inside Neovim. No hidden browser. No wrapper daemon.
Just native vim state plus a pi bridge.

## What works today

With the bundled pi extension, these Neovim verbs are forwarded into pi:

| Key | What it sends |
|-----|---------------|
| `ga{motion}` / `gaa` / visual `ga` | ask / explain event |
| `gs{motion}` / `gss` / visual `gs` | generate event |
| `<leader>gr{motion}` / visual `<leader>gr` | refactor event with exact target file + line range |
| `<leader>gc{motion}` / visual `<leader>gc` | check / review event |
| `<C-g>` | plan / continue-from-workbench event |
| `<leader>gx` | execute / do-work event from Neovim |
| `<leader>gy` | pin selection into the workbench |
| `<leader>co` / `<leader>cc` | open / clear workbench |

Each forwarded turn reaches pi together with live editor context:

- current buffer + cursor
- visible windows
- quickfix entries
- diagnostics summary
- nearby lines around the cursor
- Neovim tools: `nvim_context`, `nvim_buffer`, `nvim_buffers`, `nvim_diagnostics`, `nvim_goto`, `nvim_quickfix`, `nvim_exec`, `nvim_notify`

So the basic contract is:

1. **Neovim defines scope** with motions, selections, quickfix, and the current screen.
2. **CogCog emits an event** for the claimed pi session.
3. **pi does the heavy lifting** with its own tools and edits.
4. **You stay in vim** for navigation, review, and undo.

## Quick start

### 1. Install the Neovim plugin

```lua
{ "makefunstuff/cogcog", lazy = false, config = function() require("cogcog") end }
```

CogCog auto-starts a Neovim server socket on load:

```text
/tmp/cogcog.sock
```

Override it with `COGCOG_NVIM_SOCKET` if you want a different path.

### 2. Install the pi extension

```bash
cd /path/to/cogcog/pi-extension
npm install
ln -s /path/to/cogcog/pi-extension ~/.pi/agent/extensions/cogcog
```

Then start or reload pi.

### 3. Claim the session that should receive CogCog events

Inside pi:

```text
/reload
/cogcog-claim
/cogcog-status
```

Only the claimed pi session receives live CogCog events.

### 4. Try the loop

In Neovim, put the cursor on some code and run:

```vim
gaip
```

If pi is claimed, you should see a follow-up event in pi with your selection and
current editor state.

If pi is **not** claimed, Neovim will warn:

```text
cogcog: no pi listener for ask
```

## Core ideas

### 1. Vim motions are the scope

CogCog does not invent a new selection model.

```vim
gaip          ask about inner paragraph
gaf           ask about function
gss           generate from whole buffer
<leader>grip  refactor inner paragraph
<leader>gcaf  review current function
```

The motion is the contract.

### 2. Your editor state is context

pi sees the active buffer, cursor, visible windows, quickfix, and diagnostics
before each event-driven turn.

That means your usual vim workflow already shapes the prompt:

- split related files if you want pi to notice them
- populate quickfix if you want a concrete target set visible
- keep the right buffer active before triggering a verb

### 3. The workbench is just a buffer

CogCog keeps a persistent scratch buffer at `[cogcog-workbench]`.
Use it to collect snippets, write plans, and stage context.

```text
<leader>co          open / close workbench
<leader>gy          pin visual selection into workbench
<C-g>               send a plan / continue event
<leader>cc          clear workbench
```

Workbench contents persist to:

```text
.cogcog/workbench.md
```

## Stable keymaps with the bundled pi bridge

### Ask / explain

```text
ga{motion}          explain / ask about scoped text
gaa                 explain whole buffer
Visual ga           prompted question about selection
1gaip               shorter ask instruction
3gaip               more detailed ask instruction
```

### Generate

```text
gs{motion}          generate from scoped text
gss                 generate from whole buffer
Visual gs           generate from selection
```

### Refactor

```text
<leader>gr{motion}  refactor scoped text
Visual <leader>gr   refactor selection
```

The emitted event includes the exact target file and line range, so pi can edit
precisely instead of guessing.

### Check

```text
<leader>gc{motion}  review / check scoped text
Visual <leader>gc   review selection
```

### Plan

```text
<C-g>               ask pi to continue from current file / workbench context
```

From a normal code buffer, `<C-g>` prompts for a short plan request.
From the workbench, `<C-g>` means “continue from here”.

### Execute

```text
<leader>gx          prompt in Neovim, then push the instruction to pi
```

Use this when you want to tell pi to actually do something from Neovim:
implement, fix, rename, move, clean up, investigate, and so on.

## pi bridge

The bundled extension gives pi two things:

1. **automatic editor-state injection** before each CogCog-triggered turn
2. **Neovim tools** so pi can inspect or manipulate your editor deliberately

### Commands

Inside pi:

```text
/cogcog-claim      receive CogCog events in this session
/cogcog-release    stop receiving them here
/cogcog-status     show socket / channel / owner state
```

### Tools registered by the extension

| Tool | What pi can do |
|------|----------------|
| `nvim_context` | inspect cwd, buffer, cursor, visible windows, quickfix, diagnostics |
| `nvim_buffer` | read a loaded buffer |
| `nvim_buffers` | list loaded buffers |
| `nvim_diagnostics` | read LSP diagnostics |
| `nvim_goto` | jump your editor to a file/line |
| `nvim_quickfix` | push findings into quickfix |
| `nvim_exec` | run a Vim command |
| `nvim_notify` | send a notification back to Neovim |

## Internal event surface

Every forwarded action still goes through `transport.emit()`, and every emit is
also exposed inside Neovim via:

- `User CogcogEvent` autocmd
- `vim.g.cogcog_last_event`

That gives you an escape hatch for custom listeners later, but the bundled
workflow is intentionally small: **ask / generate / refactor / check / plan / execute**.

## Shell filter: `bin/cogcog`

This repo also ships a plain stdin → LLM → stdout helper:

```bash
echo "explain this diff" | cogcog
cat src/auth.ts | cogcog --raw
```

This is separate from the Neovim keymaps.
Use it anywhere you want a Unix-style filter.

### Shell env vars

| Var | Purpose |
|-----|---------|
| `COGCOG_CMD` | delegate to another CLI instead of using HTTP |
| `COGCOG_API_URL` | default API endpoint |
| `COGCOG_FAST_API_URL` | endpoint for `--raw` when you want a different fast path |
| `COGCOG_API_KEY` | API key |
| `OPENAI_API_KEY` | fallback API key |
| `COGCOG_MODEL` | default model |
| `COGCOG_FAST_MODEL` | model for `--raw` |
| `COGCOG_MAX_TOKENS` | max tokens |
| `COGCOG_SYSTEM` | optional system prompt |

Example:

```bash
export COGCOG_API_URL=http://localhost:8091/v1/chat/completions
export COGCOG_MODEL=gemma4:26b
export OPENAI_API_KEY=dummy

echo "explain CRDs" | cogcog
```

Optional fast path:

```bash
export COGCOG_FAST_API_URL=http://localhost:1234/v1/chat/completions
export COGCOG_FAST_MODEL=gemma-4-e4b

cat src/main.ts | cogcog --raw
```

## Neovim-side config

| Var | Purpose |
|-----|---------|
| `COGCOG_NVIM_SOCKET` | Neovim RPC socket path for the pi bridge |
| `COGCOG_KB` | optional knowledge-base root for local KB lookup helpers |
| `COGCOG_CHECKER` | optional command used by local KB-search fallback helpers |

`COGCOG_KB` and `COGCOG_CHECKER` matter mostly for custom listeners and
Neovim-side helper flows. The bundled pi extension does **not** depend on them.

## Repo layout

```text
bin/cogcog                  # stdin -> LLM -> stdout helper
lua/cogcog/init.lua         # keymaps, event emission, workbench
lua/cogcog/context.lua      # scope builders, workbench helpers
lua/cogcog/transport.lua    # User autocommands + pi event emission
lua/cogcog/bridge.lua       # Neovim RPC surface for the pi extension
pi-extension/               # pi extension (TypeScript)
skills/nvim-bridge/         # helper notes for bridge usage
.cogcog/                    # workbench + project-local state
```

## Status

CogCog is currently best thought of as:

- a **precise Neovim event source**
- a **workbench buffer**
- a **pi bridge**
- plus a small **Unix filter** in `bin/cogcog`

It is not a self-contained chat UI inside Neovim.
The bundled bridge intentionally keeps the editor simple and lets pi handle the agent loop.

See also: [CHEATSHEET.md](CHEATSHEET.md) · [TUTORIAL.md](TUTORIAL.md) · [USAGE.md](USAGE.md) · [UNIX_IS_YOUR_IDE.md](UNIX_IS_YOUR_IDE.md)
