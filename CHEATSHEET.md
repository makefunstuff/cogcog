# cogcog cheatsheet

## Verbs

```
gaip                explain (no prompt, instant)
1gaip               one sentence
3gaip               detailed with examples
Visual ga           ask with prompt
gsip / gss          generate → new buffer (agent)
<leader>grip        refactor in-place (u to undo)
<leader>gcip        check (strongest model)
```

Close response splits with `q`.

## Context from vim state

```
<leader>gj          ask about jump trail (investigation)
<leader>g.          review recent changes
<leader>gx          agent execute (sends current file + open buffers)
```

`ga` auto-includes visible windows + quickfix.

## Planning

```
<C-g>               plan — agentic, reads files
<C-g> (in panel)    send buffer as-is
<C-g> (in exec)     continue conversation
```

## Context management

```
<leader>cy          pin selection to context
<leader>co          toggle panel (open = ga stateful)
<leader>cc          clear context
<leader>cd          discover / update project map
<leader>cp          improve prompt from bad response
<C-c>               cancel job
```

## Native vim context

```vim
:read .cogcog/review.md     add skill
:read !git diff --staged    add diff
:read !grep -rn "auth" src/ add search
dap                         delete section
:w .cogcog/session.md       save manually
```

## Config

```
COGCOG_FAST_MODEL   ga: fast model
COGCOG_CMD          gs/<C-g>/<leader>gx: agent CLI
COGCOG_CHECKER      <leader>gc/<leader>cd: strongest model
```

## Combos

```
gaip                        instant explain
gd → gaip                   definition → explain
:make → gaip                errors → explain (quickfix auto)
<leader>gj                  where have I been → how do they connect
<leader>g.                  what I changed → any bugs
<leader>cy × N → <C-g>     pin from files → plan
gsip → <leader>gcip         generate → verify
<leader>gx → <C-g>         execute → continue
<leader>cd → <C-g>         discover → explore
```
