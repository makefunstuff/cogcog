# CogCog

LLM as a vim verb.

Neovim is Neovim. [Pi](https://github.com/badlogic/pi-mono) is pi. Both are awesome.

CogCog makes them work together without either pretending to be the other.

## Fast verbs (0.3s)

```
gaip           explain this paragraph
gaf            explain this function
V → ga         "is this thread-safe?"
gsip           "implement this TODO"
<leader>grip   "simplify"
<leader>gcaf   review this function
```

Motions, text objects, visual selections. No prompt needed for explain.
Small refactors apply inline (`u` to undo). Large ones open a review buffer
(`a` to apply, `q` to reject).

## Workbench

Where stateless verbs end and iterative work begins.

```
<C-g> → "refactor auth to use token buckets"
```

The model can request tools. Every call visible, every call approved:

```
🔧 read_file("src/auth.ts")
🔧 grep("RateLimiter", "src/")
```

Built-ins: `read_file`, `list_files`, `grep`, `run_command`, `diagnostics`,
`lsp_symbols`, `buffers`, `kb_search`, plus anything in `.cogcog/tools/`.

Approvals are controlled by `vim.g.cogcog_tool_mode`:
`"ask"` (default), `"read"` (auto-approve read-only tools), `"trust"`.

## Neovim is Neovim

CogCog uses what Neovim already has:

- **Motions** = scope (the verb acts on exactly what you select)
- **Visible windows** = soft context (what you see is what the model sees)
- **Quickfix** = hard batch boundary (`<leader>gR` rewrites only quickfix targets)
- **Buffers** = surfaces (workbench, review, code output — just buffers)
- **`:read !cmd`** = import anything into workbench
- **`u`** = undo

No panels. No sidebars. No chat windows. No special UI.

## Pi bridge

Pi runs in your terminal. CogCog gives it eyes and hands into your Neovim
via a shared socket (`/tmp/cogcog.sock`).

```
Terminal 1: nvim                    editing, fast verbs, visual review
Terminal 2: pi                      agent loops, multi-file refactors
```

The same Neovim RPC socket handles both directions:

- **Pi → Neovim** for editor context and editor actions
- **Neovim → Pi** for live CogCog verb events (`ask`, `generate`, `refactor`, `plan`, ...)

Pi sees what you see — automatically, every prompt:

```markdown
## Neovim Editor State
Buffer: `src/auth.ts` (typescript) — cursor line 42
Visible: `src/auth.ts`, `src/middleware.ts`
Diagnostics: 2E 1W 0I
```

And it can reach back into your editor:

| Tool | What pi can do |
|------|----------------|
| `nvim_context` | see your buffer, cursor, windows, quickfix, diagnostics |
| `nvim_buffer` | read any open buffer |
| `nvim_buffers` | list loaded buffers |
| `nvim_diagnostics` | get LSP errors and warnings |
| `nvim_goto` | open a file at a line in your Neovim |
| `nvim_quickfix` | push items into the quickfix list |
| `nvim_exec` | run a vim command (`:make`, `:grep`, `:write`) |
| `nvim_notify` | send a notification to your editor |

### Setup

```bash
cd /path/to/cogcog/pi-extension && npm install
ln -s /path/to/cogcog/pi-extension ~/.pi/agent/extensions/cogcog
```

Then `/reload` in pi.

If you run multiple pi instances, explicitly choose the event consumer:

```text
/cogcog-claim      receive CogCog verb events in this pi session
/cogcog-release    stop receiving them here
/cogcog-status     show socket/channel/owner state
```

Only the claimed pi session receives live CogCog events.

No bridge process. No wrapper scripts. Pi talks directly to Neovim's native
msgpack-RPC socket via the `cogcog.bridge` Lua module, and CogCog verbs push
live events back over that same connection.

## Backend

CogCog uses any OpenAI-compatible endpoint. Point it at a local llama-server,
Ollama, or any API:

```bash
export COGCOG_API_URL=http://192.168.1.138:8091/v1/chat/completions
export COGCOG_MODEL=gemma4:26b
export OPENAI_API_KEY=dummy   # required by protocol, any value works for local
```

Optional fast model for inline operations:

```bash
export COGCOG_FAST_API_URL=http://localhost:1234/v1/chat/completions
export COGCOG_FAST_MODEL=gemma-4-e4b
```

That's it. No OAuth, no token refresh, no cloud auth management.

## Batch (quickfix)

```vim
:grep "TODO" src/**                 build target set
<leader>gQ                          review the set
<leader>gR                          prepare rewrite → review → apply
```

Quickfix is the boundary. Cogcog never roams beyond it.

## Discover

```
<leader>cd                          project dashboard
```

Pre-computes real stats (files, LOC, git, treesitter, LSP, diagnostics),
then asks the model to synthesize architecture and module tables.

## Project tools

Scripts in `.cogcog/tools/` are project-local and model-available:

```
<leader>cT → "tool that finds unused exports" → review → save
<leader>ct → pick and run
```

## Context model

| Tier | What | You control it by |
|------|------|-------------------|
| **Hard scope** | the text you act on, or the current quickfix target set | motion, selection, buffer, quickfix |
| **Explicit imports** | text you brought in | workbench, `<leader>gy`, `<leader>g!` |
| **Soft context** | nearby signals | visible windows |
| **Tool results** | data the model fetched | tool calls you approved |

## Install

```lua
{ "makefunstuff/cogcog", lazy = false, config = function() require("cogcog") end }
```

## All keymaps

| Key | What |
|-----|------|
| `ga{motion}` / `gaa` / `ga` (v) | explain |
| `gs{motion}` / `gss` / `gs` (v) | generate |
| `<leader>gr{motion}` / `<leader>gr` (v) | refactor |
| `<leader>gc{motion}` / `<leader>gc` (v) | check |
| `<C-g>` | workbench synthesis (with tools) |
| `<leader>gy` (v) | pin to workbench |
| `<leader>co` | toggle workbench |
| `<leader>cc` | clear workbench |
| `<leader>g!` | exec command → workbench |
| `<leader>ct` | run project tool |
| `<leader>cT` | generate new tool |
| `<leader>gj` | jump trail |
| `<leader>g.` | review recent changes |
| `<leader>gq` / `<leader>gQ` | quickfix summarize / review |
| `<leader>gR` | batch rewrite quickfix |
| `<leader>cd` | discover project |
| `<leader>cp` | improve prompt |
| `<C-c>` | cancel |

## Philosophy

Inspired by Mario Zechner's [*Thoughts on slowing the fuck down*](https://mariozechner.at/posts/2026-03-25-thoughts-on-slowing-the-fuck-down/).

You should always know what the model saw, what it changed, and how to undo it.

See [TUTORIAL.md](TUTORIAL.md) · [USAGE.md](USAGE.md) · [CHEATSHEET.md](CHEATSHEET.md) · [UNIX_IS_YOUR_IDE.md](UNIX_IS_YOUR_IDE.md)

## Structure

```text
bin/cogcog                  # stdin → LLM → stdout (OpenAI-compatible)
lua/cogcog/init.lua         # verbs and keymaps
lua/cogcog/transport.lua    # emits live RPC events to pi
lua/cogcog/context.lua      # scope builders, workbench
lua/cogcog/config.lua       # paths and config
lua/cogcog/bridge.lua       # Neovim RPC bridge for pi extension
pi-extension/               # pi extension (TypeScript + Neovim client)
skills/nvim-bridge/         # agent skill for nv CLI
doc/cogcog.txt              # :help cogcog
.cogcog/                    # prompts, templates, workbench state
```
