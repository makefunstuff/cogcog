# CogCog

LLM as a vim verb.

**You build context manually, so you read the code. You choose what matters. The LLM only sees what you curated.**

## Three verbs

| Verb | What | Model | Cost |
|------|------|-------|------|
| `ga` | ask / explain | gemma4 E4B (local) | $0 |
| `gs` | generate code | kimi-k2.5 (opencode zen) | sub |
| `<leader>gc` | verify / check | opus xhigh (anthropic) | sub |

`ga` and `gs` compose with any vim motion: `gaip`, `gsaf`, `<leader>gcaf`.

## Workflows

### Ask (`ga`) — fast, local

```
gaip        → "what does this do?"
gaf         → "any bugs here?"
Visual ga   → "explain the error"
```

Panel closed = stateless (throwaway split). Panel open = stateful (conversation accumulates).

Quickfix entries (LSP diagnostics, `:grep`, `:make` errors) are auto-included.

### Generate (`gs`) — agentic, cloud

```
gsip        → "rewrite in async/await"
Visual gs   → "add error handling"
```

Uses an agent backend with tool calls and web search. Output auto-detects language, strips code fences, sets filetype. `:w filename` to save.

### Check (`<leader>gc`) — deep verification

```
<leader>gcaf    → opus reviews this function
Visual <leader>gc → opus reviews selection
```

Generate cheap, verify smart. Local model writes, cloud model catches bugs.

### Plan (`<C-g>`) — stateful conversation

```
<C-g>       → "let's design the auth flow"
<C-g>       → "what about token refresh?"
```

Build up context with `<leader>cy`, then `gs` to materialize code from the plan.

## Install

```bash
cp bin/cogcog ~/.local/bin/
chmod +x ~/.local/bin/cogcog
```

Neovim (lazy.nvim):

```lua
{ dir = "/path/to/cogcog" }
```

Requires: `curl`, `jq` for raw API path.

## Configuration

```bash
# ga: fast local model (any OpenAI-compatible endpoint)
export COGCOG_BACKEND=openai
export COGCOG_API_URL=http://192.168.1.138:8090/v1/chat/completions
export COGCOG_API_KEY=unused
export COGCOG_FAST_MODEL="gemma-4-E4B-it-Q4_K_M"

# gs: agent backend (any stdin→stdout CLI with tool calling)
export COGCOG_CMD="opencode run -m opencode/kimi-k2.5"

# gc: checker is configured in lua (default: pi -p --provider anthropic --model opus:xhigh)
```

The three paths can point anywhere — local Ollama, OpenRouter, Anthropic, any OpenAI-compatible API.

## Keymaps

| Key | Mode | What |
|-----|------|------|
| `ga{motion}` | normal | ask about text object |
| `ga` | visual | ask about selection |
| `gs{motion}` | normal | generate from text object |
| `gs` | visual | generate from selection |
| `<leader>gc{motion}` | normal | check text object |
| `<leader>gc` | visual | check selection |
| `<C-g>` | normal | plan (stateful follow-up) |
| `<leader>cy` | visual | pin selection to context |
| `<leader>co` | normal | toggle context panel |
| `<leader>cd` | normal | discover project |
| `<leader>cc` | normal | clear context |
| `<C-c>` | any | cancel running job |

## Context

Context is a buffer. Use Neovim to manage it:

```vim
:read .cogcog/review.md          " add a skill
:read !git diff                  " add tool output
dap                              " delete a section
```

Session auto-saves on exit. System prompt loads from `.cogcog/system.md`.

## Shell

```bash
echo "explain CRDs" | cogcog
git diff --staged | cogcog --raw "review this"
```

## Day 1 on a new codebase

`<leader>cd` — one keymap. Gathers project structure, entry points, package info, git history, README. Sends everything to the LLM and asks "explain this project."

```
<leader>cd                          " auto-discover: tree + entry points + deps + git log → LLM
<C-g> → "show me the request lifecycle"
<C-g> → "where's the auth logic?"
```

From there, follow the LLM's pointers with `gd` (go to definition), pin what you find with `<leader>cy`, keep asking. The panel accumulates your exploration.

The agent reads 50 files silently and gives you an answer. cogcog reads 5 files with you and gives you understanding.

## What you can do in 5 minutes

**Understand unfamiliar code:**
```
gaf → "what does this function do?"
gaf → "what happens if the input is nil?"
```

**Find and fix a bug:**
```vim
:make                                   " build errors → quickfix
gaip → "why is this failing?"           " LLM sees errors + code
gsaf → "fix it"                         " generates fixed version
:w                                      " save, re-run :make
```

**Review before committing:**
```bash
git diff --staged | cogcog --raw "review for bugs"
```

**Generate a function:**
```
gsip → "write a function that retries HTTP requests with exponential backoff"
:w src/retry.ts                         " save the generated code
<leader>gcaf                            " opus verifies it
```

**Explore a new codebase:**
```
<leader>cd                              " auto-gathers structure + entry points
<C-g> → "where's the database layer?"   " follow up
gd → gaf → "explain this"              " navigate and ask
```

**Plan then build:**
```
<leader>co                              " open panel
<C-g> → "I need to add rate limiting. What's the approach?"
<C-g> → "use token bucket, not sliding window"
gsaf → "implement based on our plan"    " generates from conversation
```

See **[USAGE.md](USAGE.md)** for more tricks and patterns. See **[UNIX_IS_YOUR_IDE.md](UNIX_IS_YOUR_IDE.md)** for why MCP is `curl` and every "agent feature" done with tools you already have.

## Structure

```
bin/cogcog              # bash: stdin → LLM → stdout
lua/cogcog/init.lua     # neovim: ga/gs/gc/plan
.cogcog/                # project skills and templates
```
