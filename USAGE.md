# Usage & Tricks

## Fast verbs (0.3s, raw API)

### Instant explain

```text
gaip             what does this paragraph do?
gaf              what does this function do?
gaa              walk me through this entire file
1gaip            one sentence
3gaip            detailed with examples
```

No prompt. Includes visible windows + quickfix automatically.

### Ask with a question

```text
Visual select → ga → "is this thread-safe?"
Visual select → ga → "what happens on nil input?"
```

### Generate code

```text
gsaf → "add error handling"
gsip → "implement this TODO"
gss → "scaffold the module"
```

0.3s. Output in a code buffer with correct filetype. `:w filename` to save.

### Refactor in-place

```text
<leader>graf → "simplify"
<leader>grip → "convert to async/await"
Visual <leader>gr → "add type annotations"
```

Small rewrites apply directly. `u` to undo.
Larger rewrites open a review buffer with a unified diff. Press `a` to apply or `q` to close.

### Plan / synthesize in the workbench

```text
<C-g> → "add rate limiting to the API"
<C-g> → "use token bucket, not sliding window"
```

Fast workbench synthesis. Shows current filename in the prompt when invoked from code.

## Deeper / optional verbs

### Check

```text
<leader>gcaf        review this function
<leader>gcip        review this paragraph
```

Uses the bundled Cogcog transport.
Set `COGCOG_CHECKER` only if you explicitly want a different command.

### Discover project

```text
<leader>cd
```

Discovery writes a project dashboard you can navigate with `gf`.

## Context from vim state

### Your screen is context

`ga` auto-includes code from visible windows. Split `auth.ts` and `middleware.ts` side by side → `gaip` in `auth.ts` sees both files.

### Jump trail

Navigate around with `gd`, `gr`, `<C-o>`:

```text
<leader>gj          how do these locations connect?
```

### Recent changes

Edit some code, then:

```text
<leader>g.          any bugs in my changes?
```

### Quickfix

```vim
:make               " errors → quickfix
gaip                " explain failure (quickfix auto-included)

:lua vim.diagnostic.setqflist()     " LSP diagnostics
gaip                                " explain

:grep "TODO" src/**
<leader>gq                          " summarize what is in quickfix
<leader>gQ                          " review and prioritize quickfix items
```

## Scope model

Cogcog distinguishes between three kinds of context:

- **hard scope** — the explicit operand or target set
- **explicit imports** — workbench contents, pinned snippets, command output you added
- **soft context** — visible windows for grounding

## Workbench flow

```text
<leader>co                open workbench
gaip                      explain with the workbench in play
<C-g>                     continue using the current workbench
<leader>co                close → back to stateless operator flow
```

## Pin from multiple files

```vim
" file A: visual select → <leader>gy
" file B: visual select → <leader>gy
<C-g> → "can these race?"
```

## Pi integration (separate terminal)

CogCog + pi = two terminals, one workflow.

```text
Terminal 1: nvim              fast verbs, editing, visual review
Terminal 2: pi                agent work, multi-file changes
```

CogCog auto-starts `vim.fn.serverstart("/tmp/cogcog.sock")`.
Pi connects via the cogcog extension and gets:

- **Auto-injected context**: every prompt includes your buffer, cursor, visible windows, quickfix, and diagnostics
- **8 tools**: `nvim_context`, `nvim_buffer`, `nvim_buffers`, `nvim_diagnostics`, `nvim_goto`, `nvim_quickfix`, `nvim_exec`, `nvim_notify`
- When pi edits files, Neovim autoread picks up changes

Install:

```bash
ln -s /path/to/cogcog/pi-extension ~/.pi/agent/extensions/cogcog
```

Optional `nv` helper for scripts and agent skills:

```bash
nv status                   check connection
nv context                  full editor state
nv buffer [path]            read buffer content
nv buffers                  list loaded buffers
nv diagnostics [path]       LSP diagnostics
nv goto <path> [line]       open file in Neovim
nv eval <lua-expr>          arbitrary Lua
```

## Quickfix rewrite flow

Build a deliberate target set first:

```vim
:grep "TODO" src/**
<leader>gR
```

Prepares merged quickfix targets, opens review buffer with diffs.
Press `a` to apply, `q` to reject.

## Generate → check loop

```text
gsaf → "implement retry with backoff"      generate (0.3s)
:w src/retry.ts                             save
:make                                       test
gaip                                        explain errors
gsaf → "fix it"                            iterate
<leader>gcaf                                verify with check
```

## Improve prompts over time

```text
<leader>cp → "it gave generic advice instead of reading the code"
```

Appends to `.cogcog/system.md`. Prompts improve per-project.

## Context management (native vim)

```vim
<leader>co                          " open workbench
:read .cogcog/review.md             " add review skill
:read !git diff --staged            " add staged changes
:read !tree -L 3                    " project structure
dap                                 " delete a section
```

## Shell

```bash
export COGCOG_BACKEND=copilot
echo "explain CRDs" | cogcog --raw          # fast: sonnet 4.6
git diff --staged | cogcog "review this"    # smart: opus 4.6
```

## Combos

```text
gaip                        instant explain
gaa                         explain entire file
gd → gaip                   definition → explain
:make → gaip                errors → explain
<leader>gj                  jump trail → how connected
<leader>g.                  changes → any bugs
gsip → <leader>gcip         generate → verify
<C-g>                       plan in workbench
<leader>cd → gf → gaip      discover → navigate → understand
```
