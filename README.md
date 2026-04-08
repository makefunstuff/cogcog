# CogCog

LLM as a vim verb.

## How it works

```
 you see code ──→ you act on it ──→ you review the result
     │                 │                    │
  screen is         ga  gs  gr  gc       split / inline / review buffer
  your context      motion or visual       q to close, u to undo, a to apply
```

There is no chat. No hidden context. No session history.
Each verb is a stateless call on the text you pointed it at.
Your visible windows are the context. Quickfix is the batch boundary.

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

### 5. Plan (workbench)

```
<leader>co                          open workbench
<C-g> → "design the auth flow"     synthesize
<C-g> → "use token bucket"         continue
<leader>co                          close — back to stateless
```

The workbench is a plain markdown buffer. Pin code with `<leader>cy`, import context with `:read !git diff`, edit freely with normal vim.

### 6. Batch (quickfix)

```vim
:grep "TODO" src/**                 build target set
<leader>gQ                          review the set
<leader>gR                          prepare rewrite → review → apply
```

Quickfix is the hard boundary. Cogcog never roams beyond it.

### 7. Discover (unfamiliar code)

```
<leader>cd                          scout the project
```

Produces a two-part discovery note:
- **Project Map** — every file organized by domain, `gf`-navigable
- **Candidate Files** — the 5–15 files to read first

Then: `gf` into a file → `gaip` to understand → `<leader>cy` to pin → `<C-g>` to synthesize.

### 8. Investigate

```
gd → gd → gd                       navigate normally
<leader>gj                          how do these locations connect?
<leader>g.                          any bugs in my changes?
```

## The loop

Most real work follows one of these paths:

```
understand          gaip → read → gaip → read
                    ↓
generate            gsaf → :w → :make → fix
                    ↓
refactor            <leader>graf → review → iterate
                    ↓
verify              <leader>gcaf → done or back to refactor
```

```
orient              <leader>cd → gf → gaip → <leader>cy
                    ↓
plan                <leader>co → <C-g> → <C-g>
                    ↓
batch               :grep → <leader>gR → :make
```

## Context model

| Tier | What | You control it by |
|------|------|-------------------|
| **Hard scope** | the text you act on | motion, selection, buffer |
| **Explicit imports** | text you brought in | workbench, `<leader>cy`, `:read` |
| **Soft context** | nearby signals | visible windows |

Your screen is your context. Split two files side by side → `gaip` sees both.
Close one → it sees one. No `@file` mentions needed.

Quickfix is the batch scope. When populated, it's included automatically.

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
| `<C-g>` | n | synthesize in workbench |
| `<leader>cy` | v | pin to workbench |
| `<leader>co` | n | toggle workbench |
| `<leader>cc` | n | clear workbench |
| `<leader>gj` | n | jump trail |
| `<leader>g.` | n | review recent changes |
| `<leader>gq` | n | summarize quickfix |
| `<leader>gQ` | n | review quickfix |
| `<leader>gR` | n | batch rewrite quickfix |
| `<leader>cd` | n | discover project |
| `<leader>cp` | n | improve prompt |
| `<leader>gx` | n | external execute (opt-in) |
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
.cogcog/                 per-project prompts and state
```
