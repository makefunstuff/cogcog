# CogCog

LLM as a vim verb.

**You build context manually, so you read the code. You choose what matters. The LLM only sees what you curated.**

## What you can do

```
gaip                                 instant explain, zero friction
Visual ga → "is this thread-safe?"   ask a specific question
gsaf → "add error handling"          generate code in a new buffer
<leader>graf → "simplify"            refactor in-place (u to undo)
<leader>gcaf                         deep verification
<C-g> → "design the auth flow"       agentic planning (reads files)
<leader>gx → "refactor auth module"  multi-file agent work
<leader>cd                           map entire project by domain
```

## Verbs

| Verb | What | Output |
|------|------|--------|
| `ga{motion}` | explain (no prompt) | side split |
| visual `ga` | ask (prompted) | side split |
| `gs{motion}` / `gss` | generate (agent) | code buffer |
| `<leader>gr{motion}` | refactor in-place | replaces code (`u` to undo) |
| `<leader>gc{motion}` | deep check | side split |

Count controls verbosity: `gaip` = concise, `1gaip` = one sentence, `3gaip` = detailed.

All response splits close with `q`.

## Context modes

| Mode | How | Backend |
|------|-----|---------|
| **Seamless** | `ga` auto-includes visible windows + quickfix | fast local |
| **Explicit** | `<leader>cy` to pin, `:read` to add | you curate |
| **Agentic** | `<C-g>`, `<leader>gx`, `gs` — LLM reads files | agent with tools |

Open the panel (`<leader>co`) → `ga` becomes stateful (conversation accumulates).

## Vim-native context

Your vim state IS context:

| Feature | Keymap | What it sends |
|---------|--------|---------------|
| Visible windows | `ga` | all code on screen |
| Quickfix | `ga` | LSP diagnostics, `:grep`, `:make` errors |
| Jump trail | `<leader>gj` | last 8 locations you navigated |
| Recent changes | `<leader>g.` | lines you just edited |
| Open buffers | `<leader>gx` | file list for agent |

## Planning & execution

```
<C-g> → "add rate limiting"          agent reads your codebase
<C-g> → "use token bucket"           conversation accumulates
gsaf → "implement the plan"          generate from context
<leader>gx → "refactor auth module"  agent works across files
```

`<C-g>` in an exec buffer continues the conversation.

## Discovery

```
<leader>cd                            map project (one-time, strongest model)
```

`gf`-navigable output saved to `.cogcog/discovery.md`. Update incrementally.

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
# ask (ga): any OpenAI-compatible API
export COGCOG_BACKEND=openai
export COGCOG_API_URL=http://localhost:8090/v1/chat/completions
export COGCOG_API_KEY=your-key
export COGCOG_FAST_MODEL="your-model"

# generate/plan (gs, <C-g>, <leader>gx): agent CLI with tools
export COGCOG_CMD="pi -p --provider ollama-cloud --model kimi-k2.5"

# check/discover (<leader>gc, <leader>cd): strongest model
export COGCOG_CHECKER="pi -p --provider anthropic --model opus:xhigh"
```

## All keymaps

| Key | Mode | What |
|-----|------|------|
| `ga{motion}` | n | explain (no prompt, count = verbosity) |
| `ga` | v | ask (prompted) |
| `gs{motion}` / `gss` | n | generate → code buffer |
| `gs` | v | generate from selection |
| `<leader>gr{motion}` | n | refactor in-place |
| `<leader>gr` | v | refactor selection |
| `<leader>gc{motion}` | n | check with strongest model |
| `<leader>gc` | v | check selection |
| `<C-g>` | n | plan / continue exec buffer |
| `<leader>cy` | v | pin to context |
| `<leader>co` | n | toggle context panel |
| `<leader>gx` | n | agent execute (multi-file) |
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

See **[TUTORIAL.md](TUTORIAL.md)** to get started. See **[USAGE.md](USAGE.md)** for tricks. See **[UNIX_IS_YOUR_IDE.md](UNIX_IS_YOUR_IDE.md)** for why `|` is the only protocol you need. Run `:help cogcog` inside Neovim.

## Structure

```
bin/cogcog                  # bash: stdin → LLM → stdout
lua/cogcog/init.lua         # verbs and keymaps
lua/cogcog/stream.lua       # shared streaming
lua/cogcog/context.lua      # input builders, panel, helpers
lua/cogcog/config.lua       # paths and config
doc/cogcog.txt              # :help cogcog
doc/cogcog-tutorial.txt     # :help cogcog-tutorial
.cogcog/                    # project prompts and templates
```

## Improvements (v2)

### Error Handling
- Added error callbacks to stream operations
- Better validation before buffer operations
- Notifications on failures instead of silent crashes

### Race Condition Fixes
- Selection captured INSIDE callbacks, not before
- Prevents selection changes during async operations

### Timeout Handling
- Configurable timeout via `COGCOG_TIMEOUT` (default: 60s)
- Automatic cleanup on timeout

### Tests
- Unit tests in `tests.lua`
- Test context builders and stream logic

### Documentation
- `doc/CODE_STYLE.md` - coding conventions
- `.gitignore` - ignore cogcog state files

## Running Tests

```bash
lua tests.lua
```

## Improvements Summary

| Issue | Fix |
|-------|-----|
| No error handling | Added error callbacks, validation |
| Race conditions | Capture selection in callbacks |
| No timeout | Configurable timeout mechanism |
| No tests | Unit tests for core logic |
| No docs | Added CODE_STYLE.md |
| Silent failures | User notifications |
