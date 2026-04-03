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

See **[USAGE.md](USAGE.md)** for tricks and patterns. See **[PHILOSOPHY.md](PHILOSOPHY.md)** for why MCP is `curl`. See **[UNIX_IS_YOUR_IDE.md](UNIX_IS_YOUR_IDE.md)** for practical examples — every "agent feature" done with tools you already have.

## Structure

```
bin/cogcog              # bash: stdin → LLM → stdout
lua/cogcog/init.lua     # neovim: ga/gs/gc/plan
.cogcog/                # project skills and templates
```
