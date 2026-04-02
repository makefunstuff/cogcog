# CogCog

LLM as a vim verb. Three workflows, zero bloat.

**You build context manually, so you read the code. You choose what matters. The LLM only sees what you curated. Building the context IS the understanding.**

Modern "coding agents" trade fake speed for hidden debt. The paradigm of "ship code I don't read" will shoot you in the leg. CogCog is the middle ground: control the context, delegate boring parts, stay model-agnostic, avoid tool calling bloat.

## Three Workflows

### Ask (`ga`) — fast, one-shot

Select code, ask a question, get an answer. Direct API call, no agent overhead.

```
gaip        → "what does this do?"     → answer streams in side panel
gaf         → "any bugs here?"         → answer with function context
Visual ga   → "explain the error"      → answer about selection
```

Quickfix context is auto-included — LSP diagnostics, `:grep` results, `:make` errors come along for free.

### Generate (`gs`) — agentic slopgen

Select code or start from scratch, generate into a fresh buffer. Uses an agent backend (tool calls, file access).

```
gsip        → "rewrite in async/await" → new code buffer
Visual gs   → "add error handling"     → new code buffer
gs (panel)  → "implement the plan"     → code from planning context
```

Output goes to `[cogcog-gen]` — yank what you need, `:w filename`, or discard.

### Plan (`<C-g>`) — interactive conversation

Build context, discuss architecture, iterate. When ready, trigger `gs` to materialize.

```
<C-g>       → "let's design the auth flow"
<leader>cy  → pin code to context
<leader>cl  → toggle skills/tools
<C-g>       → "what about token refresh?"
gs          → "generate the implementation"  → code buffer
```

## Install

```bash
# put the shell script on your PATH
cp bin/cogcog ~/.local/bin/
chmod +x ~/.local/bin/cogcog
```

**Neovim plugin** (lazy.nvim):

```lua
{ dir = "/path/to/cogcog" }
```

## Configuration

Two layers: fast API for ask, agent CLI for generation.

```bash
# fast path (ga): direct API, any OpenAI-compatible provider
export COGCOG_BACKEND=openai
export COGCOG_API_URL=https://openrouter.ai/api/v1/chat/completions
export COGCOG_API_KEY="sk-or-..."
export COGCOG_MODEL="moonshotai/kimi-k2.5"

# agent path (gs): any stdin→stdout CLI with tool calling
export COGCOG_CMD="opencode run -m opencode/kimi-k2.5"

# or use Anthropic directly (default when no COGCOG_BACKEND is set)
export ANTHROPIC_API_KEY="sk-ant-..."

# optional
export COGCOG_MAX_TOKENS=8192
export COGCOG_SYSTEM="you are a senior engineer. be concise."
```

### Supported backends (fast path)

Any OpenAI-compatible API works:

```bash
# OpenRouter (access to 100+ models)
COGCOG_API_URL=https://openrouter.ai/api/v1/chat/completions

# Ollama (local)
COGCOG_API_URL=http://localhost:11434/v1/chat/completions

# Ollama Cloud
COGCOG_API_URL=https://ollama.com/v1/chat/completions

# Groq
COGCOG_API_URL=https://api.groq.com/openai/v1/chat/completions
```

### Supported agents (slopgen path)

Any CLI that reads stdin and writes stdout:

```bash
COGCOG_CMD="opencode run -m opencode/kimi-k2.5"
COGCOG_CMD="claude -p --model sonnet"
COGCOG_CMD="aider --message"
```

## Keymaps

| Key | Mode | Workflow | What |
|-----|------|---------|------|
| `ga{motion}` | normal | ask | ask about text object |
| `ga` | visual | ask | ask about selection |
| `<C-g>` | normal | plan | ask / follow-up (no selection) |
| `gs{motion}` | normal | generate | generate from text object |
| `gs` | visual | generate | generate from selection |
| `<leader>cy` | visual | context | pin selection to context |
| `<leader>co` | normal | context | toggle context panel |
| `<leader>cl` | normal | context | toggle skills/tools |
| `<leader>cc` | normal | context | clear context |

## Skills and Tools

Skills are prompt templates in `.cogcog/` or `.cogcog/skills/`. Tools inject dynamic content. Toggle with `<leader>cl`.

```
.cogcog/
  system.md          # auto-loaded as base prompt
  review.md          # "review for bugs, security, performance..."
  explain.md         # "explain step by step"
  refactor.md        # "refactor for clarity"
  debug.md           # "what's wrong?"
```

Built-in tools: `tree`, `diff`, `staged`, `log`.

## Context

Context is a buffer, not a database. You see exactly what the LLM sees.

- **Quickfix auto-context**: LSP diagnostics, grep results, build errors are auto-included when you `ga`
- **Session persistence**: context saves to `.cogcog/session.md` on exit, restores on open
- **Skills are invisible layers**: prepended when sending, shown in statusline, don't clutter the buffer

## Shell

The Neovim plugin is optional. The CLI works standalone:

```bash
echo "explain kubernetes CRDs" | cogcog
git diff --staged | cogcog "review this"
cat src/main.ts | cogcog "any bugs?"
kubectl get events -n prod | cogcog "what needs attention?"
```

Pass `--raw` to force the direct API path (bypasses `COGCOG_CMD`):

```bash
echo "quick question" | cogcog --raw
```

## Structure

```
bin/cogcog              # bash: stdin → LLM → stdout (API + agent delegation)
lua/cogcog/init.lua     # neovim: ga/gs/plan workflows
.cogcog/                # project-level skills and templates
```
