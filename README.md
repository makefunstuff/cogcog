# CogCog

LLM as a vim verb. Fast, stateless, visible.

## The idea

```
 you see code ──→ you act on it ──→ you review the result
     │                 │                    │
  screen is         ga  gs  gr  gc       split / inline / review buffer
  your context      motion or visual       q to close, u to undo, a to apply
```

Fast verbs are stateless. No chat, no hidden context, no session history.
The workbench is where longer work happens — with tools the model can use.

For heavier agent work, [pi](https://github.com/badlogic/pi-mono) runs in a
separate terminal with full awareness of your Neovim state.

## Fast verbs (0.3s)

### Understand

```
gaip           explain this paragraph
gaf            explain this function
gaa            explain entire file
V → ga         ask "is this thread-safe?"
```

No prompt needed. Count controls depth: `1gaip` one sentence, `3gaip` detailed.

### Generate

```
gsip → "implement this TODO"
gsaf → "add error handling"
gss  → "scaffold the module"
```

Output lands in a code buffer. `:w filename` to save.

### Refactor

```
<leader>grip → "simplify"
<leader>graf → "convert to async"
V → <leader>gr → "add types"
```

Small rewrites go inline (`u` to undo). Large rewrites open a review buffer
(`a` to apply, `q` to reject).

### Check

```
<leader>gcaf        review this function
<leader>gcip        review this paragraph
```

## Workbench + tools

The workbench is where stateless verbs end and iterative work begins.

```
<C-g> → "refactor auth to use token buckets"
```

The model can request tools — every call visible, every call approved:

```
🔧 read_file("src/middleware/auth.ts")

  --- tool: read_file ---
  import { verify } from './jwt';
  export function authMiddleware(req, res, next) { ... }
  --- end ---

Here's the refactored version:
  [code in workbench]
```

**Available tools:**

| Tool | What |
|------|------|
| `read_file(path)` | read a project file |
| `list_files(dir)` | list directory contents |
| `grep(pattern, path)` | search for patterns |
| `run_command(cmd)` | execute a shell command |
| `.cogcog/tools/*` | your project scripts |

**Approval modes** (`vim.g.cogcog_tool_mode`):
`"ask"` (default) · `"read"` (auto-approve reads) · `"trust"` (auto-approve all)

## Pi as companion

CogCog and [pi](https://github.com/badlogic/pi-mono) share the same design
values: visible context, no hidden state, you stay in control. They complement
each other — CogCog handles fast Neovim verbs, pi handles agent work that
spans files.

```
Terminal 1: nvim                    fast verbs, editing, visual review
Terminal 2: pi                      agent loops, multi-file changes, tools
                │
                └─ cogcog extension gives pi live Neovim awareness
```

A bundled pi extension connects to your running Neovim and injects editor
state into every pi prompt automatically:

```markdown
## Neovim Editor State
CWD: /home/you/project
Buffer: `src/auth.ts` (typescript) — cursor line 42

``` src/auth.ts:32-52
 32: export function validateToken(token: string) {
...
>42:     if (expired) throw new AuthError('token expired');
...
```

Pi sees what you see. It knows your buffer, cursor, visible windows, quickfix
list, and LSP diagnostics. When pi edits files, Neovim picks up the changes
via autoread.

**Pi tools registered by the extension:**

| Tool | What pi can do |
|------|----------------|
| `nvim_context` | read your buffer, cursor, windows, quickfix, diagnostics |
| `nvim_buffer` | read full content of any open buffer |
| `nvim_buffers` | list all loaded buffers |
| `nvim_diagnostics` | get LSP errors and warnings |
| `nvim_goto` | open a file at a specific line in your editor |

**Install:**

```bash
# cogcog auto-starts the Neovim server socket on load
# just symlink the extension for pi:
ln -s /path/to/cogcog/pi-extension ~/.pi/agent/extensions/cogcog
```

No bridge process. No wrapper scripts. Pi talks directly to Neovim's native
RPC socket via the `cogcog.bridge` Lua module.

**CLI tool** for scripts and agent skills:

```bash
nv status                   # connected: /tmp/cogcog.sock
nv context                  # full editor state as JSON
nv buffer [path]            # read buffer content
nv diagnostics [path]       # LSP diagnostics
nv goto <path> [line]       # navigate editor to file
```

## Batch (quickfix)

```vim
:grep "TODO" src/**                 build target set
<leader>gQ                          review the set
<leader>gR                          prepare rewrite → review → apply
```

Quickfix is the hard boundary. Cogcog never roams beyond it.

## Discover

```
<leader>cd                          project dashboard
```

Pre-computes real stats (files, LOC, git, treesitter, LSP, diagnostics),
then asks the model to synthesize architecture and module tables.
Dense dashboard, not a README summary.

## Project tools

Scripts in `.cogcog/tools/` are project-local and model-available:

```
<leader>cT → "tool that finds unused exports" → review → save
<leader>ct → pick and run a saved tool
```

The self-evolution loop:

```
encounter friction ──→ <leader>cT generate tool ──→ review ──→ save
       ↑                                                        │
       └──── <leader>ct or model uses it via <C-g> ────────────┘
```

## Context model

| Tier | What | You control it by |
|------|------|-------------------|
| **Hard scope** | the text you act on | motion, selection, buffer |
| **Explicit imports** | text you brought in | workbench, `<leader>gy`, `<leader>g!` |
| **Soft context** | nearby signals | visible windows |
| **Tool results** | data the model fetched | tool calls you approved in workbench |

## Install

```lua
-- lazy.nvim
{ "makefunstuff/cogcog", lazy = false, config = function() require("cogcog") end }
```

### Backend

```bash
# recommended: GitHub Copilot (no API key needed, 14ms overhead)
export COGCOG_BACKEND=copilot
# smart: claude-opus-4.6, fast: claude-sonnet-4.6

# or: OpenAI Codex (18ms overhead)
export COGCOG_BACKEND=codex

# or: direct API key
export ANTHROPIC_API_KEY="sk-ant-..."

# or: any OpenAI-compatible endpoint
export COGCOG_BACKEND=openai
export COGCOG_API_URL=http://localhost:11434/v1/chat/completions
```

`copilot` and `codex` read OAuth tokens from pi's `~/.pi/agent/auth.json`.
Run `pi /login` once to authenticate. Requires: `bash`, `curl`, `jq`.

### Knowledge base (optional)

```bash
export COGCOG_KB=~/path/to/knowledge-base
```

Discovery dashboards include relevant KB pages when set.

## All keymaps

| Key | Mode | What |
|-----|------|------|
| `ga{motion}` | n | explain (count = verbosity) |
| `gaa` | n | explain entire buffer |
| `ga` | v | ask with prompt |
| `gs{motion}` / `gss` | n | generate → code buffer |
| `gs` | v | generate from selection |
| `<leader>gr{motion}` | n | refactor in-place |
| `<leader>gr` | v | refactor selection |
| `<leader>gc{motion}` | n | check |
| `<leader>gc` | v | check selection |
| `<C-g>` | n | workbench synthesis (with tools) |
| `<leader>gy` | v | pin to workbench |
| `<leader>co` | n | toggle workbench |
| `<leader>cc` | n | clear workbench |
| `<leader>g!` | n | exec command → workbench |
| `<leader>ct` | n | run project tool → workbench |
| `<leader>cT` | n | generate new tool → review → save |
| `<leader>gj` | n | jump trail |
| `<leader>g.` | n | review recent changes |
| `<leader>gq` | n | summarize quickfix |
| `<leader>gQ` | n | review quickfix |
| `<leader>gR` | n | batch rewrite quickfix |
| `<leader>cd` | n | discover project |
| `<leader>cp` | n | improve prompt |
| `<C-c>` | n/i | cancel |

## Philosophy

Inspired by Mario Zechner's [*Thoughts on slowing the fuck down*](https://mariozechner.at/posts/2026-03-25-thoughts-on-slowing-the-fuck-down/).

The goal is not blind throughput. It's visible scope, review, and judgment.
You should always know what the model saw, what it changed, and how to undo it.

See [TUTORIAL.md](TUTORIAL.md), [USAGE.md](USAGE.md), [UNIX_IS_YOUR_IDE.md](UNIX_IS_YOUR_IDE.md).

## Structure

```
bin/cogcog               stdin → LLM → stdout (bundled transport)
lua/cogcog/init.lua      verbs and keymaps
lua/cogcog/stream.lua    streaming to buffers
lua/cogcog/context.lua   scope builders, workbench, helpers
lua/cogcog/config.lua    paths and config
lua/cogcog/bridge.lua    editor state for external tools (pi extension)
pi-extension/index.ts    pi extension — gives pi eyes into Neovim
skills/nvim-bridge/      agent skill for the nv CLI tool
doc/cogcog.txt           :help cogcog
.cogcog/                 per-project prompts, tools, and state
```
