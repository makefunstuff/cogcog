# CogCog

LLM as a vim verb.

**You build context manually, so you read the code. You choose what matters. The LLM only sees what you curated.**

## Workflows

### Ask (`ga`) — stateless, fast

Select code, ask a question, get an answer in a throwaway split. Direct API call, no agent. Cursor stays in your code.

```
gaip        → "what does this do?"
gaf         → "any bugs here?"
Visual ga   → "explain the error"
```

Quickfix entries (LSP diagnostics, `:grep`, `:make` errors) are auto-included.

### Generate (`gs`) — agentic

Select code or start from scratch, generate into a fresh code buffer. Uses agent backend with tool calls.

```
gsip        → "rewrite in async/await"
Visual gs   → "add error handling"
```

Output auto-detects language from code fences, strips them, sets filetype. `:w filename` to save.

### Plan (`<C-g>`) — stateful conversation

Multi-turn planning in a context panel. Build up context, discuss, iterate. When ready, `gs` to generate code.

```
<C-g>       → "let's design the auth flow"
<C-g>       → "what about token refresh?"
```

## Install

```bash
cp bin/cogcog ~/.local/bin/
chmod +x ~/.local/bin/cogcog
```

Neovim (lazy.nvim):

```lua
{ dir = "/path/to/cogcog" }
```

## Configuration

```bash
# fast path (ga): direct API via any OpenAI-compatible provider
export COGCOG_BACKEND=openai
export COGCOG_API_URL=https://openrouter.ai/api/v1/chat/completions
export COGCOG_API_KEY="sk-or-..."
export COGCOG_FAST_MODEL="google/gemini-2.5-flash"   # fast model for ask
export COGCOG_MODEL="moonshotai/kimi-k2.5"           # default model

# agent path (gs): any stdin→stdout CLI
export COGCOG_CMD="opencode run -m opencode/kimi-k2.5"

# or use Anthropic directly (default when no COGCOG_BACKEND is set)
export ANTHROPIC_API_KEY="sk-ant-..."
```

## Keymaps

| Key | Mode | What |
|-----|------|------|
| `ga{motion}` | normal | ask about text object |
| `ga` | visual | ask about selection |
| `gs{motion}` | normal | generate from text object |
| `gs` | visual | generate from selection |
| `<C-g>` | normal | plan (stateful follow-up) |
| `<leader>cy` | visual | pin selection to context |
| `<leader>co` | normal | toggle context panel |
| `<leader>cc` | normal | clear context |

## Context

Context is a buffer. Use Neovim to manage it:

```vim
:read .cogcog/review.md          " add a skill
:read !git diff                  " add tool output
:read !tree -L 3                 " add project tree
dap                              " delete a section
:w .cogcog/session.md            " save manually
```

Session auto-saves on exit and restores on open. System prompt loads from `.cogcog/system.md`.

## Shell

```bash
echo "explain CRDs" | cogcog
git diff --staged | cogcog "review this"
echo "quick question" | cogcog --raw    # bypass agent, hit API directly
```

See **[USAGE.md](USAGE.md)** for tricks, patterns, and how vim primitives replace agent features.

## Structure

```
bin/cogcog              # bash: stdin → LLM → stdout
lua/cogcog/init.lua     # neovim: ga/gs/gc/plan
.cogcog/                # project skills and templates
```
