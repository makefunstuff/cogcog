# CogCog

LLM as a vim verb.

Cogcog is a Neovim plugin for **bounded AI work**:

- operand-local explain / ask / generate / rewrite / check
- quickfix-scoped batch review and rewrite
- a plain editable **workbench** buffer for planning and imports
- a lightweight **discovery note** for unfamiliar code

It is inspired in part by Mario Zechner’s essay
[*Thoughts on slowing the fuck down*](https://mariozechner.at/posts/2026-03-25-thoughts-on-slowing-the-fuck-down/):
**the goal is not blind throughput, but visible scope, review, and judgment.**

If you want a chat harness with hidden context accumulation and autonomy theater, this is not that.
If you want Neovim-native leverage on work you can still inspect and steer, that is the point.

## What you can do

```text
gaip                                 instant explain (0.3s, no prompt)
Visual ga → "is this thread-safe?"   ask a specific question
gsaf → "add error handling"          generate code (0.3s, raw API)
<leader>graf → "simplify"            refactor (small = inline, large = review)
:grep "TODO" src/**                  build a deliberate target set
<leader>gQ                           review the current quickfix set
<leader>gR                           prepare batch rewrite → review → apply
<C-g> → "design the auth flow"       synthesize in workbench
<leader>cd                           map project by domain
<leader>gx → "implement it"          optional external execute
```

## Core surfaces

| Surface | What it is for |
|---------|-----------------|
| **Operand** | `ga` / `gs` / `gr` / `gc` on a motion, selection, or buffer |
| **Quickfix** | deliberate multi-location target sets for summarize / review / rewrite |
| **Workbench** | planning, synthesis, imports, and longer visible text work |
| **Discovery note** | scout-style project map and candidate files |

`<leader>gx` still exists for explicit external execute, but it should stay secondary to the **operand → quickfix → workbench** loop.

## Scope model

Cogcog currently treats context in three buckets:

- **hard scope** — the explicit operand or target set
  - selection / motion target
  - whole buffer
  - quickfix entries for batch work
- **explicit imports** — text you deliberately bring in
  - workbench contents
  - pinned snippets
  - `:read !cmd` output
- **soft context** — supporting nearby signals
  - visible windows

Quickfix is the batch boundary when present.
Visible windows help with grounding, but they are not a license to roam the whole repo.

## Verbs

| Verb | What | Speed | Output |
|------|------|-------|--------|
| `ga{motion}` / `gaa` | explain | 0.3s | side split (reused) |
| visual `ga` | ask (prompted) | 0.3s | side split (reused) |
| `gs{motion}` / `gss` | generate | 0.3s | code buffer |
| `<leader>gr{motion}` | refactor in-place | 0.3s | inline for small rewrites, review buffer for larger ones |
| `<leader>gc{motion}` | check | 0.3s by default, overrideable | side split (reused) |

Count controls verbosity: `gaip` concise, `1gaip` one sentence, `3gaip` detailed.

Small refactors still apply directly and stay undoable with `u`.
Larger refactors open a review buffer with a unified diff. Press `a` to apply, `q` to close.

All splits close with `q` and reuse the same window.

## Quickfix-first batch work

| Keymap | Context source |
|--------|----------------|
| `ga` | visible windows + quickfix |
| `<leader>gj` | last 8 jump locations |
| `<leader>g.` | recently edited lines |
| `<leader>gq` / `<leader>gQ` | summarize / review current quickfix set |
| `<leader>gR` | prepare, review, and apply current quickfix target set |
| `<leader>gx` | visible windows + quickfix + workbench |

Typical loop:

```vim
:grep "TODO" src/**
<leader>gQ
<leader>gR
```

`<leader>gR` prepares rewrites for merged quickfix targets, opens a review buffer with diffs, and only applies when you press `a`.
Targets that changed since review are skipped.

## Workbench

The workbench is a plain editable markdown buffer.
Use it for:

- pinned snippets from multiple files
- `:read !git diff` / logs / grep output
- planning notes
- imported docs or research snippets
- longer back-and-forth when a simple operator call is not enough

```text
<C-g> → "add rate limiting"          fast workbench synthesis (raw API)
<C-g> → "use token bucket"           continues in workbench
<leader>gx → "implement it"          optional external execute in workbench
```

Open it with `<leader>co`.
Workbench contents auto-save on exit to `.cogcog/workbench.md`.
Legacy `.cogcog/session.md` is treated as a migration source.

## Discovery

```text
<leader>cd                            map project
```

`gf`-navigable output is saved to `.cogcog/discovery.md`.
Options: Open / Update / Re-discover.
By default it uses the bundled Cogcog transport.
Set `COGCOG_CHECKER` only if you explicitly want a different command for review/discovery.

## Install with lazy.nvim

```lua
{
  "makefunstuff/cogcog",
  config = function()
    require("cogcog")
  end,
}
```

No separate `cogcog` binary install is required for the plugin path above.
When installed from git, Cogcog uses the bundled `bin/cogcog` automatically.

## Requirements

For the bundled transport you need:

- `bash`
- `curl` and `jq` (for anthropic/openai backends)
- one model provider configured

### Quickest setup: copilot backend (recommended)

If you have [pi](https://github.com/badlogic/pi-mono) installed and authenticated
with GitHub Copilot:

```bash
export COGCOG_BACKEND=copilot
```

That's it. Reads pi's OAuth token directly, calls the Copilot API with plain `curl`.
**14ms overhead**, auto-refreshes expired tokens.

- Smart model (default): **claude-opus-4.6**
- Fast model (`--raw`): **claude-sonnet-4.6**

```bash
# optionally override
export COGCOG_MODEL=claude-sonnet-4.5   # smart override
export COGCOG_FAST_MODEL=claude-haiku-4.5  # fast override
```

### Alternative: codex backend

For ChatGPT Plus/Pro Codex subscription:

```bash
export COGCOG_BACKEND=codex
# default model: gpt-5.4
```

Same 18ms overhead, same auto-refresh from pi's `auth.json`.

### Direct API backends

```bash
# Anthropic (default backend)
export ANTHROPIC_API_KEY="sk-ant-..."

# or any OpenAI-compatible endpoint
export COGCOG_BACKEND=openai
export COGCOG_API_URL=http://localhost:8090/v1/chat/completions
export COGCOG_API_KEY=your-key
export COGCOG_FAST_MODEL="your-model"
```

### Slow but universal: pi backend

If you need a provider that isn't anthropic/openai/codex/copilot:

```bash
export COGCOG_BACKEND=pi
export COGCOG_PI_PROVIDER=google     # any pi provider
```

This delegates to `pi -p` (~0.7s startup overhead). Fine for `<leader>gc` / `<leader>gx`,
not ideal for fast verbs.

## Configuration

### Default core path

By default, core Cogcog behavior uses the bundled `bin/cogcog` transport:

- `ga`, `gs`, `gr`, `<C-g>`
- `gc`
- `cd`

This means the core loop does **not** assume `pi`, `opencode`, Claude Code, or any other external harness.

### Optional overrides

```bash
# optional: stronger separate command for check/discover
export COGCOG_CHECKER="your-review-command"

# optional: explicit external execute command for <leader>gx
export COGCOG_AGENT_CMD="your-execute-command"

# bundled cogcog transport
export COGCOG_MODEL="model-name"        # default model when FAST_MODEL not set
export COGCOG_MAX_TOKENS=8192
export COGCOG_SYSTEM="be concise"
```

`<leader>gx` is intentionally **disabled unless `COGCOG_AGENT_CMD` is set**.

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
| `<leader>gc{motion}` | n | check |
| `<leader>gc` | v | check selection |
| `<C-g>` | n | plan / synthesize (fast, in workbench) |
| `<leader>cy` | v | pin to workbench |
| `<leader>co` | n | toggle workbench |
| `<leader>gx` | n | optional external execute (in workbench) |
| `<leader>gj` | n | ask about jump trail |
| `<leader>g.` | n | review recent changes |
| `<leader>gq` | n | summarize current quickfix set |
| `<leader>gQ` | n | review current quickfix set |
| `<leader>gR` | n | prepare, review, and apply current quickfix target set |
| `<leader>cd` | n | discover / update project |
| `<leader>cp` | n | improve prompt |
| `<leader>cc` | n | clear workbench |
| `<C-c>` | n/i | cancel running job |
| `a` | review | apply prepared review buffer |
| `q` | response/review | close split |

## Context management (native vim)

```vim
:read .cogcog/review.md     " add a skill
:read !git diff             " add tool output
dap                         " delete a section
```

System prompt comes from `.cogcog/system.md`.

## Optional shell use

The bundled transport is also a small CLI:

```bash
echo "explain CRDs" | bin/cogcog
git diff --staged | bin/cogcog --raw "review this"
```

That shell path is optional. The main product is the Neovim plugin.

See **[TUTORIAL.md](TUTORIAL.md)**, **[USAGE.md](USAGE.md)**, **[UNIX_IS_YOUR_IDE.md](UNIX_IS_YOUR_IDE.md)**.
Run `:help cogcog` in Neovim.

## Structure

```text
bin/cogcog                  # bundled transport used by the plugin
lua/cogcog/init.lua         # verbs and keymaps
lua/cogcog/stream.lua       # shared streaming
lua/cogcog/context.lua      # input builders, workbench, helpers
lua/cogcog/config.lua       # paths and config
doc/cogcog.txt              # :help cogcog
.cogcog/                    # project prompts and templates
```
