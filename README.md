# CogCog

LLM as a vim verb.

**You build context manually, so you read the code. You choose what matters. The LLM only sees what you curated.**

## What you can do

```
gaf  → "what does this function do?"     instant answer, stay in your code
gsaf → "add error handling"              generates code in a new buffer
<leader>gcaf                             opus verifies the code
<C-g> → "let's design the auth flow"    stateful planning conversation
<leader>cd                               opus maps the entire project
```

## Three verbs

| Verb | Role | Speed |
|------|------|-------|
| `ga` | ask / explain | fast (local model) |
| `gs` | generate code | agentic (tool calls, web search) |
| `<leader>gc` | verify / review | deep (strongest model) |

All compose with motions: `gaip`, `gsaf`, `<leader>gcaf`. All work in visual mode.

## Workflows

### Ask (`ga`) — stateless or stateful

```
gaip        → "what does this do?"
gaf         → "any bugs here?"
Visual ga   → "explain the error"
```

**Panel closed** = one-shot answer in a throwaway split. Quickfix auto-included.
**Panel open** = conversation. Questions and answers accumulate.

### Generate (`gs`) — agentic

```
gsip        → "rewrite in async/await"
Visual gs   → "add error handling"
```

Agent backend with tool calls. Output auto-detects language, strips code fences. `:w filename` to save.

### Check (`<leader>gc`) — deep verification

```
<leader>gcaf        opus reviews this function
Visual <leader>gc   opus reviews selection
```

### Plan (`<C-g>`) — stateful conversation

```
<C-g> → "let's design the auth flow"
<C-g> → "what about token refresh?"
gsaf  → "implement based on our plan"
```

Auto-pins the current file to context when asked from a code buffer.

### Discover (`<leader>cd`) — project map

One-time deep analysis. Opus maps your project by domain, outputs `gf`-navigable reference saved to `.cogcog/discovery.md`.

### Improve (`<leader>cp`) — learn from bad responses

Got a bad response? `<leader>cp` → tell it what was wrong → generates a system prompt fix and appends to `.cogcog/system.md`. Your prompts improve incrementally.

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

Simplest setup — just Anthropic:

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
echo "hello" | cogcog
```

## Configuration

Three independent paths. Configure what you need:

```bash
# ask (ga): any OpenAI-compatible API — local Ollama, OpenRouter, Groq, etc.
export COGCOG_BACKEND=openai
export COGCOG_API_URL=http://localhost:8090/v1/chat/completions
export COGCOG_API_KEY=your-key
export COGCOG_FAST_MODEL="your-fast-model"

# generate (gs): any stdin→stdout CLI with tool calling
export COGCOG_CMD="opencode run -m your/model"

# check (gc): configurable via env var
export COGCOG_CHECKER="pi -p --provider anthropic --model opus:xhigh"
```

Or use Anthropic for everything (default, no extra config):

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
| `<C-g>` | normal | plan (auto-pins current file) |
| `<leader>cy` | visual | pin selection to context |
| `<leader>co` | normal | toggle context panel |
| `<leader>cd` | normal | discover project |
| `<leader>cp` | normal | improve prompt from bad response |
| `<leader>cc` | normal | clear context |
| `<C-c>` | any | cancel running job |

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
