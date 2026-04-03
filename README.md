# CogCog

LLM as a vim verb.

**You build context manually, so you read the code. You choose what matters. The LLM only sees what you curated.**

## What you can do

```
gaf  → "what does this function do?"     instant answer, stay in your code
gsaf → "add error handling"              generates code in a new buffer
graf → "simplify this"                   refactors code in-place (undo with u)
<leader>gcaf                             deep verification with strongest model
<C-g> → "let's design the auth flow"    agentic planning (reads files, uses tools)
<leader>cd                               maps entire project by domain
```

## Four verbs

| Verb | Role | Output |
|------|------|--------|
| `ga` | ask / explain | answer in side split |
| `gs` / `gss` | generate code | new code buffer |
| `gr` | refactor in-place | replaces your code (undo with `u`) |
| `<leader>gc` | verify / review | review in side split |

All compose with motions: `gaip`, `gsaf`, `graf`, `<leader>gcaf`. All work in visual mode. Response splits close with `q`.

With just `ANTHROPIC_API_KEY`, all verbs work. Configure separate backends for cost optimization as needed.

> **Note:** `ga` overrides vim's show-ASCII, `gs` overrides sleep, `gr` overrides replace-char, `<C-g>` overrides show-file-info. These are deliberate tradeoffs.

## Workflows

### Ask (`ga`) — you curate, LLM answers

```
gaip        → "what does this do?"
gaf         → "any bugs here?"
Visual ga   → "explain the error"
```

**Panel closed** = one-shot, throwaway split. Quickfix auto-included.
**Panel open** = conversation. Questions and answers accumulate.

### Generate (`gs`) — agent writes code

```
gsip        → "rewrite in async/await"
gss         → "scaffold the entire module"       (whole buffer)
Visual gs   → "add error handling"
```

Agent backend with tool calls and web search. Output auto-detects language, strips code fences. `:w filename` to save.

### Refactor (`gr`) — in-place rewrite

```
graf        → "simplify this function"
grip        → "convert to async/await"
Visual gr   → "add type annotations"
```

Replaces the code directly. Undo with `u`.

### Check (`<leader>gc`) — deep verification

```
<leader>gcaf        strongest model reviews this function
Visual <leader>gc   reviews selection
```

### Plan (`<C-g>`) — agentic conversation

```
<C-g> → "let's design the auth flow"
<C-g> → "what about token refresh?"
gsaf  → "implement based on our plan"
```

Uses the agent backend — can read files, search the codebase, use tools. The LLM decides what's relevant, not you.

Pin specific code manually with `<leader>cy` when you know better.

### Discover (`<leader>cd`) — project map

One-time deep analysis. Strongest model maps your project by domain, outputs `gf`-navigable reference saved to `.cogcog/discovery.md`. Update incrementally as the project evolves.

### Improve (`<leader>cp`) — learn from bad responses

Got a bad response? `<leader>cp` → tell it what was wrong → appends a fix to `.cogcog/system.md`. Prompts improve incrementally.

## Install

```bash
cp bin/cogcog ~/.local/bin/
chmod +x ~/.local/bin/cogcog
```

Neovim (lazy.nvim):

```lua
{ dir = "/path/to/cogcog" }
```

Requires: `curl`, `jq`.

## Quickstart

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
echo "hello" | cogcog
```

That's it. All verbs work. Configure separate backends below for cost optimization.

## Configuration (optional)

Three independent paths — configure any or none:

```bash
# ask (ga): any OpenAI-compatible API — local Ollama, OpenRouter, Groq
export COGCOG_BACKEND=openai
export COGCOG_API_URL=http://localhost:8090/v1/chat/completions
export COGCOG_API_KEY=your-key
export COGCOG_FAST_MODEL="your-fast-model"

# generate/plan (gs, <C-g>): any stdin→stdout CLI with tool calling
export COGCOG_CMD="opencode run -m your/model"

# check/discover (<leader>gc, <leader>cd): strongest model
export COGCOG_CHECKER="pi -p --provider anthropic --model opus:xhigh"
```

Or use Anthropic for everything (default):

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
```

## Keymaps

| Key | Mode | What |
|-----|------|------|
| `ga{motion}` | normal | ask about text object |
| `ga` | visual | ask about selection |
| `gs{motion}` | normal | generate from text object |
| `gss` | normal | generate from entire buffer |
| `gs` | visual | generate from selection |
| `gr{motion}` | normal | refactor in-place |
| `gr` | visual | refactor selection in-place |
| `<leader>gc{motion}` | normal | check text object |
| `<leader>gc` | visual | check selection |
| `<C-g>` | normal | plan (agentic, has tools) |
| `<leader>cy` | visual | pin selection to context |
| `<leader>co` | normal | toggle context panel |
| `<leader>cd` | normal | discover / update project map |
| `<leader>cp` | normal | improve prompt from bad response |
| `<leader>cc` | normal | clear context |
| `<C-c>` | any | cancel running job |
| `q` | response | close response split |

## Context

Context is a buffer. Use Neovim:

```vim
:read .cogcog/review.md     " add a skill
:read !git diff             " add tool output
dap                         " delete a section
```

Session auto-saves on exit. System prompt loads from `.cogcog/system.md`.

## Shell

```bash
echo "explain CRDs" | cogcog
git diff --staged | cogcog --raw "review this"
```

See **[USAGE.md](USAGE.md)** for tricks. See **[UNIX_IS_YOUR_IDE.md](UNIX_IS_YOUR_IDE.md)** for why `|` is the only protocol you need. Run `:help cogcog` inside Neovim.

## Structure

```
bin/cogcog              # bash: stdin → LLM → stdout
lua/cogcog/init.lua     # neovim: ga/gs/gc/plan/discover
doc/cogcog.txt          # :help cogcog
.cogcog/                # project prompts and templates
```
