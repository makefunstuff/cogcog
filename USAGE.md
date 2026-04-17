# Usage & Tricks

This file is the practical cookbook for Cogcog as it exists today:

- Neovim defines scope
- Cogcog emits an event
- pi receives it in another terminal
- pi uses `nvim_*` tools when it needs more context

For setup, see `README.md`.

## Minimal loop

```text
Terminal 1: nvim
Terminal 2: pi
/reload
/cogcog-claim
```

Then in Neovim:

```text
gaip
<leader>gcaf
gsip
<leader>grip
<C-g>
<leader>gx
```

## Ask / explain

```text
gaip             ask about inner paragraph
gaf              ask about current function
gaa              ask about whole file
1gaip            shorter ask wording
3gaip            more detailed ask wording
Visual ga        ask a specific question about selection
```

Good prompts after visual `ga`:

```text
is this thread-safe?
what edge cases are missing?
what is the actual control flow here?
```

## Generate

```text
gsip             generate from scoped text
gsaf             generate from current function
gss              generate from whole file
Visual gs        generate from selection
```

Useful instructions:

```text
implement this TODO
add validation and clear errors
write the happy path first, keep it small
```

## Refactor

```text
<leader>grip     refactor inner paragraph
<leader>graf     refactor current function
Visual <leader>gr
```

Useful instructions:

```text
simplify the control flow
convert this to async/await
reduce branching, keep behavior the same
```

The refactor event includes the exact target file + line range, so pi can edit precisely.

## Check / review

```text
<leader>gcip     review current paragraph
<leader>gcaf     review current function
Visual <leader>gc
```

Useful review prompts:

```text
review this for correctness
look for race conditions
check null / empty / retry edge cases
```

## Execute from Neovim

```text
<leader>gx       prompt in Neovim, then push the instruction to pi
```

Use this when you want a direct do-work turn from the editor:

```text
fix this test failure
rename this module to auth-client
implement the TODO below
investigate why this code loops forever
```

Cogcog records the instruction in the workbench, emits an `execute` event, and
pi can take it from there.

## Workbench

```text
<leader>co       open / close workbench
<leader>gy       pin selection into workbench
<C-g>            continue from current file / workbench
<leader>cc       clear workbench
```

Use the workbench when the task stops being “one scoped question” and starts becoming:

- a plan
- a comparison between multiple snippets
- a running scratchpad
- a place to collect notes for pi

### Example: compare two functions

```vim
" file A: visual select -> <leader>gy
" file B: visual select -> <leader>gy
<C-g>            " ask pi to continue from the workbench thread
```

### Example: stage context manually

Open the workbench and use normal vim commands:

```vim
:read !git diff --staged
:read !rg -n "RateLimiter" src/
```

The workbench is just a buffer.

## Use your screen as context

Before each Cogcog-triggered turn, the bundled pi extension injects:

- current buffer
- cursor position
- visible windows
- quickfix entries
- diagnostics summary
- nearby lines around the cursor

That means splits are meaningful.

### Example

```vim
:edit src/auth.ts
:vsplit src/session.ts
gaip
```

pi can see both visible buffers and decide whether to inspect one of them further.

## pi bridge commands

Inside pi:

```text
/cogcog-claim
/cogcog-release
/cogcog-status
```

If `gaip` seems to do nothing, `cogcog-status` is the first place to look.

## Neovim tools pi can use

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

Practical uses:

- `nvim_context` to understand where you are
- `nvim_buffer` to read a loaded buffer in full
- `nvim_goto` to jump you to a file/line
- `nvim_quickfix` to send review findings into quickfix
- `nvim_notify` to tell you when a task is done

## Internal event hook

Every forwarded action also fires a local Neovim event:

```text
User CogcogEvent
vim.g.cogcog_last_event
```

You probably do not need this day to day, but it is there if you want to build
a custom listener later.

## Shell mode

Cogcog also ships a plain shell helper:

```bash
echo "explain CRDs" | cogcog
cat src/main.ts | cogcog --raw
git diff --staged | cogcog "review this"
```

Example config:

```bash
export COGCOG_API_URL=http://localhost:8091/v1/chat/completions
export COGCOG_MODEL=gemma4:26b
export OPENAI_API_KEY=dummy
```

Optional fast path:

```bash
export COGCOG_FAST_API_URL=http://localhost:1234/v1/chat/completions
export COGCOG_FAST_MODEL=gemma-4-e4b
```

Or delegate to another CLI:

```bash
export COGCOG_CMD='claude -p'
```

## Combos

```text
gaip                     quick explain / ask
gaf                      ask about function
Visual ga                ask a precise question

gsip -> <leader>gcaf     generate, then review
<leader>grip -> gaip     refactor, then ask what changed

<leader>gy x2 -> <C-g>   pin multiple snippets, then continue in workbench
<leader>gx               push a do-work instruction from Neovim

/cogcog-status           debug event delivery
```

## Mental model

- Use **motions** when scope is obvious
- Use **visual selections** when you need exactness
- Use **splits** when you want nearby context visible
- Use **workbench** when the task becomes iterative
- Use **pi** for the actual agent turn
- Use **vim** for review, navigation, and undo
