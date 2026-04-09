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
<leader>gx          pi RPC execute (in workbench)
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

## Planning (fast, in workbench)

```text
<C-g>               plan / synthesize (0.3s, raw API)
<C-g> (in workbench) send as-is
```

## Workbench

```text
<leader>gy          pin selection
<leader>co          toggle workbench
<leader>cc          clear workbench
<leader>cp          improve prompt from bad response
<C-c>               cancel
a                   apply review buffer
q                   close split
```

## Native vim

```vim
:read .cogcog/review.md     add skill
:read !git diff --staged    add diff
dap                         delete section
```

## Config

```text
COGCOG_FAST_MODEL   ga/gs/<C-g>/<leader>gr: fast model for bundled transport
COGCOG_PI_RPC_CMD   <leader>gx: override pi RPC command/provider/model
COGCOG_PI_SOCKET    optional companion harness socket (default: .cogcog/pi-bridge.sock)
COGCOG_CHECKER      <leader>gc/<leader>cd: optional stronger review/discovery command
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
<C-g> → <leader>gx  plan → pi RPC execute
bin/cogcog-harness  optional shared terminal harness
:CogcogHarness      open embedded harness terminal
:CogcogCompanionStop stop companion broker
:CogcogDetach       detach current local pi channel
```
