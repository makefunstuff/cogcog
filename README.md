# CogCog

LLM as a vim verb.

## How it works

```
 you see code ──→ you act on it ──→ you review the result
     │                 │                    │
  screen is         ga  gs  gr  gc       split / inline / review buffer
  your context      motion or visual       q to close, u to undo, a to apply
```

Fast verbs are stateless. No chat, no hidden context, no session history.
The workbench is where longer work happens — with tools the model can use.

## The workflow

### 1. Understand

```
gaip           explain this paragraph
gaf            explain this function
gaa            explain entire file
V → ga         ask "is this thread-safe?"
```

No prompt needed for explain. Count controls depth: `1gaip` one sentence, `3gaip` detailed.

### 2. Generate

```
gsip → "implement this TODO"
gsaf → "add error handling"
gss  → "scaffold the module"
```

Output lands in a code buffer. `:w filename` to save.

### 3. Refactor

```
<leader>grip → "simplify"
<leader>graf → "convert to async"
V → <leader>gr → "add types"
```

Small rewrites go inline (`u` to undo). Large rewrites open a review buffer (`a` to apply, `q` to reject).

### 4. Check

```
<leader>gcaf        review this function
<leader>gcip        review this paragraph
```

### 5. Plan (workbench + tools)

The workbench is where stateless verbs end and iterative work begins.

```
<C-g> → "refactor auth to use token buckets"
```

The model responds — and can request tools to gather context:

```
I need to see the current auth implementation.

🔧 read_file("src/middleware/auth.ts")

  --- tool: read_file ---
  import { verify } from './jwt';
  export function authMiddleware(req, res, next) { ... }
  --- end ---

Here's the refactored version using token buckets:
  [code in workbench]
```

Every tool call is visible in the workbench. You approve each one.
The model gets up to 5 tool turns per question, then stops.

**Available tools:**

| Tool | What | Source |
|------|------|--------|
| `read_file(path)` | read a project file | shell |
| `list_files(dir)` | list directory contents | shell |
| `grep(pattern, path)` | search for patterns | shell |
| `run_command(cmd)` | execute a shell command | shell |
| `.cogcog/tools/*.sh` | your bash scripts | shell |
| `.cogcog/tools/*.lua` | your neovim-native scripts | neovim |

**Approval modes** (`vim.g.cogcog_tool_mode`):

| Mode | Behavior |
|------|----------|
| `"ask"` (default) | approve every tool call |
| `"read"` | auto-approve read-only, ask for commands |
| `"trust"` | auto-approve all for this turn |

### 6. Execute and import

```
<leader>g! → "make test"           run command → output in workbench
<leader>gy                          pin selection to workbench
<leader>ct                          pick a project tool → output in workbench
<C-g> → "what failed?"             ask about the output
```

### 7. Pi integration (separate terminal)

CogCog gives [pi](https://github.com/badlogic/pi-mono) eyes into your Neovim via a bridge module.

```
Terminal 1: nvim                    (cogcog fast verbs, editing)
Terminal 2: pi                      (agent work, multi-file changes)
                │
                ├─ sees your buffer, cursor, windows, quickfix, diagnostics
                ├─ tools: nvim_context, nvim_buffer, nvim_diagnostics, nvim_goto
                └─ file edits → Neovim autoread picks up changes
```

CogCog auto-starts `vim.fn.serverstart("/tmp/cogcog.sock")` on load.
Install the pi extension:

```bash
ln -s /path/to/cogcog/pi-extension ~/.pi/agent/extensions/cogcog
```

Pi auto-injects your Neovim state into every prompt and registers tools the LLM
can call to read buffers, check diagnostics, or navigate you to a file.

No wrappers. No bridge process. Just pi + a TypeScript extension talking to
Neovim's native RPC socket.

CLI tool for scripts and agent skills:

```bash
nv status                           # check connection
nv context                          # buffer, cursor, windows, quickfix, diagnostics
nv buffer [path]                    # read buffer content
nv diagnostics [path]               # LSP errors/warnings
nv goto <path> [line]               # open file in Neovim
```

### 8. Batch (quickfix)

```vim
:grep "TODO" src/**                 build target set
<leader>gQ                          review the set
<leader>gR                          prepare rewrite → review → apply
```

Quickfix is the hard boundary. Cogcog never roams beyond it.

### 9. Discover (unfamiliar code)

```
<leader>cd                          project dashboard
```

Pre-computes real stats (files, LOC, git, treesitter, LSP, diagnostics),
then asks the model to synthesize architecture + module tables.
Dense dashboard, not a README summary.

### 10. Project tools (`.cogcog/tools/`)

Scripts in `.cogcog/tools/` are project-local tools.

```
<leader>cT → "tool that finds unused exports" → review → save
<leader>ct → pick and run a saved tool
```

The self-evolution loop:

```
encounter friction ──→ <leader>cT "tool that checks X" ──→ review ──→ save
       ↑                                                                 │
       └──── next time: <leader>ct or model uses it via <C-g> ──────────┘
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

### Backend setup

```bash
# recommended: GitHub Copilot (no API key needed, 14ms overhead)
export COGCOG_BACKEND=copilot
# smart: claude-opus-4.6, fast: claude-sonnet-4.6

# or: OpenAI Codex (no API key needed, 18ms overhead)
export COGCOG_BACKEND=codex

# or: direct Anthropic
export ANTHROPIC_API_KEY="sk-ant-..."

# or: any OpenAI-compatible endpoint
export COGCOG_BACKEND=openai
export COGCOG_API_URL=http://localhost:11434/v1/chat/completions
export COGCOG_API_KEY=your-key
```

Both `copilot` and `codex` read OAuth tokens from [pi](https://github.com/badlogic/pi-mono)'s `~/.pi/agent/auth.json`. Run `pi /login` once to authenticate.

Requires: `bash`, `curl`, `jq`.

### Knowledge base (optional)

```bash
export COGCOG_KB=~/path/to/your/knowledge-base
```

When set, discovery dashboards include relevant KB pages, and the
`kb_search` tool becomes available during workbench synthesis.

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
| `<C-g>` | n | synthesize in workbench (with tools) |
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
| `<leader>gx` | n | reminder: use pi in the other terminal |
| `<C-c>` | n/i | cancel |
| `q` | split | close |
| `a` | review | apply |
| `u` | after refactor | undo |

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
lua/cogcog/bridge.lua    editor state exposed to external tools (pi extension)
pi-extension/index.ts    pi extension — gives pi eyes into Neovim
skills/nvim-bridge/      skill for querying Neovim from agents
doc/cogcog.txt           :help cogcog
.cogcog/                 per-project prompts, tools, and state
```
