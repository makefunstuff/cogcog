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

By default this uses the bundled Cogcog transport.
Set `COGCOG_CHECKER` only if you explicitly want a different command for deeper review.

### Optional external execute

```text
<leader>gx → "refactor auth across all files"
<leader>gx → "add tests for the parser module"
```

`<leader>gx` is disabled unless `COGCOG_AGENT_CMD` is set.
When configured, activity shows in the workbench. Prompt anchors come from visible windows, quickfix, and the workbench.

### Discover project

```text
<leader>cd
```

Discovery writes a project note you can navigate with `gf`.
By default it uses the bundled Cogcog transport. Set `COGCOG_CHECKER` if you want a different review/discovery command.

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
```

```vim
:lua vim.diagnostic.setqflist()     " LSP diagnostics
gaip                                " explain
```

```vim
:grep "TODO" src/**
<leader>gq                          " summarize what is in quickfix
<leader>gQ                          " review and prioritize quickfix items
```

## Scope model

Cogcog distinguishes between three kinds of context:

- **hard scope** — the explicit operand or target set
- **explicit imports** — workbench contents, pinned snippets, command output you added
- **soft context** — visible windows for grounding

This keeps the common path bounded and predictable.

## Workbench flow

Open the workbench when you want a persistent editable scratchpad:

```text
<leader>co                open workbench
gaip                      explain with the workbench in play
<C-g>                     continue using the current workbench
<leader>co                close → back to stateless operator flow
```

Save a note manually if you want:

```vim
:w .cogcog/investigation.md
```

Pinned snippets, pasted docs, command output, and model responses can all live in the same workbench.

## Pin from multiple files

```vim
" file A: visual select → <leader>gy
" file B: visual select → <leader>gy
<C-g> → "can these race?"
```

## Generate → check loop

```text
gsaf → "implement retry with backoff"      generate (0.3s)
:w src/retry.ts                             save
:make                                       test
gaip                                        explain errors
gsaf → "fix it"                            iterate
<leader>gcaf                                verify with check
```

## Quickfix rewrite flow

Build a deliberate target set first, then prepare rewrites only for those targets:

```vim
:grep "TODO" src/**
<leader>gR
```

Cogcog prepares merged quickfix target snippets in descending order per file, opens a review buffer with diffs, and applies only when you press `a`.
The active quickfix list remains your navigation surface.

## Multi-file agent work

```text
<leader>gx → "add input validation to all handlers"
```

Agent reads files, makes changes, and streams progress in the workbench:

```text
  → Read src/routes/users.ts
  → Edit src/routes/users.ts
  → Read src/routes/orders.ts
  → Edit src/routes/orders.ts
Done. 2 files modified.
```

Follow up:

```text
<C-g> → "also add to the admin routes"
```

## Improve prompts over time

Bad response:

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
:read !grep -rn "auth" src/         " search results
dap                                 " delete a section
:w .cogcog/workbench.md             " save manually if you want
```

## Shell

```bash
# with copilot backend (opus 4.6 smart, sonnet 4.6 fast — no API key needed)
export COGCOG_BACKEND=copilot
echo "explain CRDs" | cogcog --raw          # fast: sonnet 4.6
git diff --staged | cogcog "review this"    # smart: opus 4.6

# or with direct API keys
echo "explain CRDs" | cogcog --raw
cat src/main.ts | cogcog --raw "any bugs?"
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
<C-g> → <leader>gx          plan → execute
<leader>cd → gf → gaip      discover → navigate → understand
```

## Discovery workflow

```text
<leader>cd                          map the project
```

Output:

```markdown
### Auth
- `src/auth/middleware.ts` — JWT validation
- `src/auth/oauth.ts` — OAuth2 flow

### Database
- `src/db/pool.ts` — connection pooling
```

Navigate: cursor on path → `gf` → you're in the file.

Pin a domain into the workbench:

```text
/### Auth                           jump to auth section
V/### Database                      select the auth domain
<leader>gy                          pin to workbench
<C-g> → "simplify the token refresh"
```

## Per-project system prompts

`.cogcog/system.md`:

```text
You are a senior engineer.
Be concise. Show code when relevant, explain when asked.
This project uses Go, PostgreSQL, Redis.
```

Loaded automatically. Improved incrementally via `<leader>cp`.
