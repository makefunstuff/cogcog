# cogcog cheatsheet

## Verbs (all 0.3s via bundled raw transport)

```text
gaip / gaa          explain (no prompt, instant)
1gaip               one sentence
3gaip               detailed
Visual ga           ask with prompt
gsip / gss          generate → code buffer
<leader>grip        refactor (small = inline, large = review buffer)
```

## Deeper / optional verbs

```text
<leader>gcip        check
<leader>cd          discover project
```

## Context from vim state

```text
<leader>gj          jump trail
<leader>g.          recent changes
<leader>gq          summarize quickfix
<leader>gQ          review quickfix
<leader>gR          review/apply quickfix rewrite
```

`ga` auto-includes visible windows + quickfix.

## Planning (workbench + tools)

```text
<C-g>               plan / synthesize (with tool calling)
<C-g> (in workbench) send as-is
```

## Workbench

```text
<leader>gy          pin selection
<leader>co          toggle workbench
<leader>cc          clear workbench
<leader>g!          exec command → workbench
<leader>ct          run project tool → workbench
<leader>cT          generate new tool → review → save
<leader>cp          improve prompt from bad response
<C-c>               cancel
a                   apply review buffer
q                   close split
```

## Pi integration (separate terminal)

```text
Terminal 1: nvim    fast verbs, editing
Terminal 2: pi      agent work, multi-file changes
```

Pi sees your Neovim state via the cogcog bridge extension.

```bash
ln -s /path/to/cogcog/pi-extension ~/.pi/agent/extensions/cogcog
```

CLI tool:

```bash
nv status                   check connection
nv context                  buffer, cursor, windows, diagnostics
nv buffer [path]            read buffer content
nv diagnostics [path]       LSP diagnostics
nv goto <path> [line]       navigate to file
```

## Config

```text
COGCOG_BACKEND      copilot (recommended), codex, anthropic, openai, pi
COGCOG_FAST_MODEL   fast model for bundled transport
COGCOG_CHECKER      optional stronger review/discovery command
COGCOG_KB           knowledge base path (for discovery KB insights)
COGCOG_NVIM_SOCKET  Neovim server socket (default: /tmp/cogcog.sock)
```

## Combos

```text
gaip                instant explain
gaa                 explain entire buffer
gd → gaip           definition → explain
:make → gaip        errors → explain
<leader>gj          investigate jump trail
<leader>g.          review changes
gsip → <leader>gcip generate → verify
<C-g>               plan in workbench (tools available)
<leader>cd → gf     discover → navigate
<leader>cT → <leader>ct  create tool → reuse it
```
