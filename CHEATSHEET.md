# cogcog cheatsheet

## Stable with the bundled pi extension

```text
ga{motion} / gaa   ask / explain
Visual ga          ask a specific question about selection

gs{motion} / gss   generate from scoped text
Visual gs          generate from selection

<leader>gr{motion} refactor scoped text
Visual <leader>gr  refactor selection

<leader>gc{motion} check / review scoped text
Visual <leader>gc  check selection

<C-g>              plan / continue
<leader>gx         execute prompt from Neovim -> pi
<leader>gy         pin selection to workbench
<leader>co         toggle workbench
<leader>cc         clear workbench
```

## Typical loop

```text
Terminal 1: nvim
Terminal 2: pi
/reload
/cogcog-claim

In nvim:
  gaip
  gsip
  <leader>grip
  <leader>gcaf
  <C-g>
  <leader>gx
```

If nothing reaches pi, check:

```text
/cogcog-status
```

## What pi gets

Each CogCog-triggered turn comes with live Neovim context:

```text
- current buffer + cursor
- visible windows
- quickfix entries
- diagnostics summary
- nearby lines around cursor
```

And pi can use:

```text
nvim_context
nvim_buffer
nvim_buffers
nvim_diagnostics
nvim_goto
nvim_quickfix
nvim_exec
nvim_notify
```

## Workbench

```text
<leader>co         open / close [cogcog-workbench]
<leader>gy         append selection to workbench
<C-g>              continue from current file / workbench
<leader>cc         wipe workbench + .cogcog/workbench.md
```

## pi bridge commands

```text
/cogcog-claim      this pi session receives events
/cogcog-release    release event ownership
/cogcog-status     socket / channel / owner / claimed state
```

## Internal event hook

Every forwarded action also emits a local Neovim event:

```text
User CogcogEvent
vim.g.cogcog_last_event
```

## Shell helper

```bash
echo "explain this" | cogcog
cat src/main.ts | cogcog --raw
```

See `README.md` for env vars and setup.
