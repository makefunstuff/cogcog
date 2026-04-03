# CogCog

LLM as a vim verb.

**You build context manually, so you read the code. You choose what matters. The LLM only sees what you curated.**

## What you can do

```
gaf  → "what does this function do?"     instant answer, stay in your code
gsaf → "add error handling"              generates code in a new buffer
<leader>gcaf                             deep verification with strongest model
<C-g> → "let's design the auth flow"    agentic planning (reads files, uses tools)
<leader>cd                               maps entire project by domain
```

## Three verbs

| Verb | Role | How |
|------|------|-----|
| `ga` | ask / explain | you select code, LLM answers fast |
| `gs` | generate code | agent backend, can read files and use tools |
| `<leader>gc` | verify / review | deep analysis with strongest available model |

All compose with motions: `gaip`, `gsaf`, `<leader>gcaf`. All work in visual mode. Response splits close with `q`.

With just `ANTHROPIC_API_KEY`, all three work through the Anthropic API. Configure separate backends for cost optimization as needed.

> **Note:** `ga` overrides vim's built-in show-ASCII, `gs` overrides sleep, `<C-g>` overrides show-file-info. These are deliberate tradeoffs — the LLM verbs are used far more often.

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
Visual gs   → "add error handling"
```

Agent backend with tool calls and web search. Output auto-detects language, strips code fences. `:w filename` to save.

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
| `gs` | visual | generate from selection |
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
