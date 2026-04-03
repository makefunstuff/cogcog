# CogCog

LLM as a vim verb.

**You build context manually, so you read the code. You choose what matters. The LLM only sees what you curated.**

## What you can do

```
gaip                                 instant explain (0.3s, no prompt)
gaa                                  explain entire buffer
Visual ga → "is this thread-safe?"   ask a specific question
gsaf → "add error handling"          generate code (0.3s, raw API)
gss → "scaffold the module"          generate from entire buffer
<leader>graf → "simplify"            refactor in-place (u to undo)
<leader>gcaf                         deep check (opus)
<C-g> → "design the auth flow"       plan in context panel
<leader>gx → "refactor auth module"  agent execute (cloud, has tools)
<leader>cd                           map project by domain
```

## Verbs

| Verb | What | Speed | Output |
|------|------|-------|--------|
| `ga{motion}` / `gaa` | explain | 0.3s | side split (reused) |
| visual `ga` | ask (prompted) | 0.3s | side split (reused) |
| `gs{motion}` / `gss` | generate | 0.3s | code buffer |
| `<leader>gr{motion}` | refactor in-place | 0.3s | replaces code |
| `<leader>gc{motion}` | deep check | 10-90s | side split (reused) |

Count controls verbosity: `gaip` concise, `1gaip` one sentence, `3gaip` detailed.

All splits close with `q` and reuse the same window.

## Context modes

| Mode | How | Backend |
|------|-----|---------|
| **Seamless** | `ga` includes visible windows + quickfix | raw API (fast) |
| **Explicit** | `<leader>cy` to pin, `:read` to add | you curate |
| **Planning** | `<C-g>` conversation in panel | raw API (fast) |
| **Agentic** | `<leader>gx` execute with tools | cloud agent |

Open the panel (`<leader>co`) → `ga` becomes stateful.

## Vim-native context

| Keymap | Context source |
|--------|---------------|
| `ga` | visible windows + quickfix |
| `<leader>gj` | last 8 jump locations |
| `<leader>g.` | recently edited lines |
| `<leader>gx` | current file + open buffers |

## Planning & execution

```
<C-g> → "add rate limiting"          fast conversation (raw API)
<C-g> → "use token bucket"           continues in panel
<leader>gx → "implement it"          cloud agent executes (also in panel)
gsaf → "implement this function"     fast code generation (raw API)
```

Both `<C-g>` and `<leader>gx` work in the same context panel. Plan fast, execute with agent when you need tools.

## Discovery

```
<leader>cd                            map project (strongest model)
```

`gf`-navigable output saved to `.cogcog/discovery.md`. Options: Open / Update / Re-discover.

## Install

```bash
cp bin/cogcog ~/.local/bin/ && chmod +x ~/.local/bin/cogcog
```

Neovim (lazy.nvim):

```lua
{ dir = "/path/to/cogcog" }
```

## Quickstart

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
echo "hello" | cogcog
```

All verbs work. Configure separate backends below for cost optimization.

## Configuration

```bash
# fast path (ga, gs, <C-g>, <leader>gr): any OpenAI-compatible API
export COGCOG_BACKEND=openai
export COGCOG_API_URL=http://localhost:8090/v1/chat/completions
export COGCOG_API_KEY=your-key
export COGCOG_FAST_MODEL="your-model"

# agent execute (<leader>gx): cloud agent with tools
export COGCOG_AGENT_CMD="pi -p --provider ollama-cloud --model kimi-k2.5"

# check/discover (<leader>gc, <leader>cd): strongest model
export COGCOG_CHECKER="pi -p --provider anthropic --model opus:xhigh"

# optional
export COGCOG_MODEL="model-name"        # default when FAST_MODEL not set
export COGCOG_MAX_TOKENS=8192
export COGCOG_SYSTEM="be concise"       # shell system prompt
```

## All keymaps

| Key | Mode | What |
|-----|------|------|
| `ga{motion}` | n | explain (no prompt, count = verbosity) |
| `gaa` | n | explain entire buffer |
| `ga` | v | ask (prompted) |
| `gs{motion}` / `gss` | n | generate → code buffer |
| `gs` | v | generate from selection |
| `<leader>gr{motion}` | n | refactor in-place |
| `<leader>gr` | v | refactor selection |
| `<leader>gc{motion}` | n | check with strongest model |
| `<leader>gc` | v | check selection |
| `<C-g>` | n | plan (fast, in panel) |
| `<leader>cy` | v | pin to context |
| `<leader>co` | n | toggle context panel |
| `<leader>gx` | n | agent execute (cloud, in panel) |
| `<leader>gj` | n | ask about jump trail |
| `<leader>g.` | n | review recent changes |
| `<leader>cd` | n | discover / update project |
| `<leader>cp` | n | improve prompt |
| `<leader>cc` | n | clear context |
| `<C-c>` | n/i | cancel running job |
| `q` | response | close split |

## Context management (native vim)

```vim
:read .cogcog/review.md     " add a skill
:read !git diff             " add tool output
dap                         " delete a section
```

Session auto-saves on exit. System prompt from `.cogcog/system.md`.

## Shell

```bash
echo "explain CRDs" | cogcog
git diff --staged | cogcog --raw "review this"
```

See **[TUTORIAL.md](TUTORIAL.md)**, **[USAGE.md](USAGE.md)**, **[UNIX_IS_YOUR_IDE.md](UNIX_IS_YOUR_IDE.md)**. Run `:help cogcog` in Neovim.

## Structure

```
bin/cogcog                  # bash: stdin → LLM → stdout
lua/cogcog/init.lua         # verbs and keymaps
lua/cogcog/stream.lua       # shared streaming
lua/cogcog/context.lua      # input builders, panel, helpers
lua/cogcog/config.lua       # paths and config
doc/cogcog.txt              # :help cogcog
.cogcog/                    # project prompts and templates
```
