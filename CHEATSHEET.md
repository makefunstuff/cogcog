# cogcog cheatsheet

## Verbs (all 0.3s via raw API)

```
gaip / gaa          explain (no prompt, instant)
1gaip               one sentence
3gaip               detailed
Visual ga           ask with prompt
gsip / gss          generate → code buffer
<leader>grip        refactor in-place (u to undo)
```

## Slow verbs (cloud models)

```
<leader>gcip        check (opus)
<leader>gx          agent execute (cloud, in panel)
<leader>cd          discover project (opus)
```

## Context from vim state

```
<leader>gj          jump trail
<leader>g.          recent changes
```

`ga` auto-includes visible windows + quickfix.

## Planning (fast, in panel)

```
<C-g>               plan (0.3s, raw API)
<C-g> (in panel)    send as-is
```

## Context

```
<leader>cy          pin selection
<leader>co          toggle panel (open = ga stateful)
<leader>cc          clear
<leader>cp          improve prompt from bad response
<C-c>               cancel
q                   close split
```

## Native vim

```vim
:read .cogcog/review.md     add skill
:read !git diff --staged    add diff
dap                         delete section
```

## Config

```
COGCOG_FAST_MODEL   ga/gs/<C-g>/<leader>gr: fast local model
COGCOG_AGENT_CMD    <leader>gx: cloud agent with tools
COGCOG_CHECKER      <leader>gc/<leader>cd: strongest model
```

## Combos

```
gaip                instant explain
gaa                 explain entire buffer
gd → gaip           definition → explain
:make → gaip        errors → explain
<leader>gj          investigate jump trail
<leader>g.          review changes
gsip → <leader>gcip generate → verify
<C-g> → <leader>gx  plan → execute
```
