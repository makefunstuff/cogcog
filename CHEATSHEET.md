# cogcog cheatsheet

## Verbs

```
gaip / gaa          explain (no prompt, instant)
1gaip               one sentence
3gaip               detailed with examples
Visual ga           ask with prompt
gsip / gss          generate → new buffer (agent)
<leader>grip        refactor in-place (u to undo)
<leader>gcip        check (strongest model)
```

All response splits reuse the same window. Close with `q`.

## Context from vim state

```
<leader>gj          jump trail (investigation)
<leader>g.          recent changes
<leader>gx          agent execute (cloud, sends current file + buffers)
```

`ga` auto-includes visible windows + quickfix.

## Planning

```
<C-g>               plan — local agent, reads files
<C-g> (in panel)    send buffer as-is
<C-g> (in exec)     continue conversation
```

## Context management

```
<leader>cy          pin selection
<leader>co          toggle panel (open = ga stateful)
<leader>cc          clear context
<leader>cd          discover / update project map
<leader>cp          improve prompt from bad response
<C-c>               cancel job
```

## Native vim

```vim
:read .cogcog/review.md     add skill
:read !git diff --staged    add diff
dap                         delete section
:w .cogcog/session.md       save manually
```

## Config

```
COGCOG_FAST_MODEL   ga/<leader>gr: fast local model
COGCOG_CMD          gs/<C-g>: local agent with tools
COGCOG_AGENT_CMD    <leader>gx: cloud agent (heavy work)
COGCOG_CHECKER      <leader>gc/<leader>cd: strongest model
```

## Combos

```
gaip                        instant explain
gaa                         explain entire buffer
gd → gaip                   definition → explain
:make → gaip                errors → explain (quickfix auto)
<leader>gj                  where have I been → how connected
<leader>g.                  what I changed → any bugs
<leader>cy × N → <C-g>     pin from files → plan
gsip → <leader>gcip         generate → verify
<leader>gx → <C-g>         execute → continue
```
