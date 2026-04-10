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

Tools: `read_file`, `list_files`, `grep`, `run_command`, plus anything in
`.cogcog/tools/`.

## Neovim is Neovim

CogCog uses what Neovim already has:

- **Motions** = scope (the verb acts on exactly what you select)
- **Visible windows** = soft context (what you see is what the model sees)
- **Quickfix** = hard batch boundary (`<leader>gR` rewrites only quickfix targets)
- **Buffers** = surfaces (workbench, review, code output — just buffers)
- **`:read !cmd`** = import anything into workbench
- **`u`** = undo

No panels. No sidebars. No chat windows. No special UI.

## Pi is pi

[Pi](https://github.com/badlogic/pi-mono) is a coding agent that runs in your
terminal. It has its own TUI, its own session management, its own tools. It
doesn't need to be embedded in anything.

CogCog includes a pi extension that gives pi eyes — and hands — into your Neovim:

```
Terminal 1: nvim                    editing, fast verbs, visual review
Terminal 2: pi                      agent loops, multi-file refactors
```

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

### Example: pi finds issues → you browse them in Neovim

You ask pi to review a module. Pi reads the code, finds issues, and pushes
them to your quickfix list:

```
You:  review terraform/utils/iam.ts for code smells

Pi:   I'll read the file and check for issues.
      [reads file via nvim_buffer]

      Found 3 issues. Sending to your quickfix list.
      [calls nvim_quickfix]

      Set 3 items in quickfix (pi: code review)
```

In your Neovim, the quickfix window opens:

```
terraform/utils/iam.ts|28 W| getUserOrgRoles: flatMap may produce duplicates
terraform/utils/iam.ts|97 W| getGoogleRolesForProject: .map() for side effects — use forEach
terraform/utils/iam.ts|42 I| nested ternary is hard to read — extract to helper
```

Now you navigate them with `:cnext` / `:cprev`, or open Telescope:

```vim
:Telescope quickfix
```

Pick one, jump to the line, fix it. This is Neovim's native quickfix workflow —
pi just filled it with intelligent findings instead of grep matches.

You can also hand the quickfix back to cogcog:

```
<leader>gR              batch rewrite all quickfix targets
<leader>gQ              review and prioritize the list
```

Pi finds. Neovim navigates. Cogcog rewrites. Each tool does what it's best at.

### Setup

```bash
# cogcog auto-starts the Neovim server socket on load — just symlink:
ln -s /path/to/cogcog/pi-extension ~/.pi/agent/extensions/cogcog
```

No bridge process. No wrapper scripts. Pi talks directly to Neovim's native
RPC socket via the `cogcog.bridge` Lua module.

**CLI tool** for scripts and agent skills:

```bash
nv status                   # check connection
nv context                  # buffer, cursor, windows, diagnostics
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

Quickfix is the boundary. Cogcog never roams beyond it.

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
<leader>ct → pick and run
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
| **Tool results** | data the model fetched | tool calls you approved |

## Install

```lua
{ "makefunstuff/cogcog", lazy = false, config = function() require("cogcog") end }
```

### Backend

```bash
# GitHub Copilot — no API key needed, 14ms overhead
export COGCOG_BACKEND=copilot

# or: OpenAI Codex, direct Anthropic, any OpenAI-compatible endpoint
```

`copilot` and `codex` read OAuth from pi's `~/.pi/agent/auth.json`.
Run `pi /login` once. Requires `bash`, `curl`, `jq`.

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

```
bin/cogcog               stdin → LLM → stdout
lua/cogcog/init.lua      verbs, keymaps, tools
lua/cogcog/stream.lua    streaming to buffers
lua/cogcog/context.lua   scope builders, workbench
lua/cogcog/config.lua    paths and config
lua/cogcog/bridge.lua    editor state for pi extension
pi-extension/            pi extension (TypeScript)
skills/nvim-bridge/      agent skill for nv CLI
doc/cogcog.txt           :help cogcog
```
