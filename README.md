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

I also need the rate limiter.

🔧 grep("RateLimiter", "src/")

  --- tool: grep ---
  src/limiter.ts:3:export class RateLimiter {
  src/middleware/rate-limit.ts:1:import { RateLimiter } from './limiter';
  --- end ---

Here's the refactored version using token buckets:
  [code in workbench]
```

Every tool call is visible in the workbench. You approve each one.
The model gets up to 5 tool turns per question, then stops.

**Available tools:**

| Tool | What | Native |
|------|------|--------|
| `read_file(path)` | read a project file | shell |
| `list_files(dir)` | list directory contents | shell |
| `grep(pattern, path)` | search for patterns | shell |
| `run_command(cmd)` | execute a shell command | shell |
| `diagnostics()` | LSP diagnostics across open buffers | neovim |
| `lsp_symbols(path)` | document symbols via LSP | neovim |
| `buffers()` | list loaded buffers | neovim |
| `kb_search(query)` | search knowledge base | neovim |
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

Optional companion harness:

```bash
bin/cogcog-harness
```

This keeps the current editor-native flow intact, but adds a second terminal UI
that can share the same live pi RPC session with Neovim through
`.cogcog/pi-bridge.sock`.

Useful commands inside Neovim:

```vim
:CogcogHarness          " open an embedded harness terminal
:CogcogCompanionStatus  " show socket/attach state
:CogcogCompanionStop    " stop the broker
:CogcogDetach           " detach Neovim from the current pi channel
```

### 7. Batch (quickfix)

```vim
:grep "TODO" src/**                 build target set
<leader>gQ                          review the set
<leader>gR                          prepare rewrite → review → apply
```

Quickfix is the hard boundary. Cogcog never roams beyond it.

### 8. Discover (unfamiliar code)

```
<leader>cd                          project dashboard
```

Discovery pre-computes real stats in Lua, then asks the model to fill in the
intelligent parts. The result is a markdown dashboard, not a README summary:

```markdown
# 📋 cogcog

| | |
|---|---|
| 🔀 Branch | `master` |
| 📁 Files | 24 |
| 📏 Source LOC | 1,890 |
| 📝 Commits | 47 |
| 🕐 Last commit | f19104e rewrite discovery (2 hours ago) |
| 🩺 Health | ❌0 ⚠️2 ℹ️0 💡3 |

## 🏗 Architecture
    init.lua ──→ context.lua ──→ stream.lua ──→ bin/cogcog

## 📦 Modules
### Core
| File | LOC | Role |
|------|-----|------|
| `lua/cogcog/init.lua` | ~890 | keymaps, verbs, tools |
| `lua/cogcog/context.lua` | ~210 | scope builders, KB |
...
```

Data sources:

| Pre-computed (Lua) | Model fills in |
|--------------------|----------------|
| File count, LOC, git stats | Architecture paragraph + diagram |
| File type breakdown | Module groupings + tables |
| Treesitter declarations | Entry points + call flow |
| LSP symbols | Stack + patterns |
| Diagnostics counts | Issues (if any) |
| KB search results | Team knowledge (if KB set) |

KB search is **LLM-powered**: sends the full page index to the model, gets
back the relevant paths. Not grep — the model understands what's related.

### 9. Project tools (`.cogcog/tools/`)

Scripts in `.cogcog/tools/` are project-local tools. Bash (`.sh`) for shell work,
Lua (`.lua`) for Neovim-native work. The model can use them during workbench
synthesis, and you can run them directly.

```bash
# bash tool — shell work
cat > .cogcog/tools/test-changed.sh << 'EOF'
#!/bin/bash
# Run tests for files changed since last commit
git diff --name-only HEAD | grep -E '\.ts$' | xargs npx jest --findRelatedTests
EOF
chmod +x .cogcog/tools/test-changed.sh
```

```lua
-- lua tool — neovim-native (.cogcog/tools/unused-imports.lua)
-- Find files with LSP diagnostics about unused imports
local diags = vim.diagnostic.get()
local out = {}
for _, d in ipairs(diags) do
  if d.message:match("[Uu]nused") then
    local f = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(d.bufnr), ":.")
    table.insert(out, f .. ":" .. (d.lnum + 1) .. " " .. d.message)
  end
end
return table.concat(out, "\n")
```

Generate new tools with the LLM — choose bash or lua:

```
<leader>cT → "tool that finds unused exports" → [bash / lua] → review → save
```

The self-evolution loop:

```
encounter friction ──→ <leader>cT "tool that checks X" ──→ review ──→ save
       ↑                                                                 │
       └──── next time: <leader>ct or model uses it via <C-g> ──────────┘
```

## The loops

```
stateless           gaip → read → gaip → read          (0.3s per call)
                    gsaf → :w → :make → fix
                    <leader>graf → review → iterate
                    <leader>gcaf → done
```

```
workbench           <C-g> "question"                    (model uses tools)
                      → 🔧 read_file → y               (you approve)
                      → 🔧 grep → y                    (you approve)
                      → model responds with full context
                    <C-g> "now implement it"             (continues)
                      → model uses tools again if needed
```

```
orient + plan       <leader>cd → gf → gaip → <leader>gy → <C-g>
batch               :grep → <leader>gR → :make
evolve              <leader>cT → tool saved → <leader>ct or <C-g> reuses it
```

## Context model

| Tier | What | You control it by |
|------|------|-------------------|
| **Hard scope** | the text you act on | motion, selection, buffer |
| **Explicit imports** | text you brought in | workbench, `<leader>gy`, `<leader>g!` |
| **Soft context** | nearby signals | visible windows |
| **Tool results** | data the model fetched | tool calls you approved in workbench |

Your screen is your context for fast verbs.
The workbench accumulates context for longer work — including tool results.
Quickfix is the batch scope.

## Install

```lua
-- lazy.nvim
{ "makefunstuff/cogcog", config = function() require("cogcog") end }
```

### Backend setup

```bash
# recommended: GitHub Copilot (no API key needed, 14ms overhead)
export COGCOG_BACKEND=copilot
# smart: claude-opus-4.6, fast: claude-sonnet-4.6

# or: OpenAI Codex (no API key needed, 18ms overhead)
export COGCOG_BACKEND=codex
# default: gpt-5.4

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
The KB should have a `wiki/` directory with markdown files.

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
| `<leader>gx` | n | pi RPC execute |
| `<C-c>` | n/i | cancel |
| `q` | split | close |
| `a` | review | apply |
| `u` | after refactor | undo |

## Per-project prompts

`.cogcog/system.md` is loaded automatically. Improve it incrementally:

```
<leader>cp → "too generic, read the actual code"
```

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
doc/cogcog.txt           :help cogcog
.cogcog/                 per-project prompts, tools, and state
```
