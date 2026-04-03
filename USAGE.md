# Usage & Tricks

## Fast verbs (0.3s, raw API)

### Instant explain

```
gaip             what does this paragraph do?
gaf              what does this function do?
gaa              walk me through this entire file
1gaip            one sentence
3gaip            detailed with examples
```

No prompt. Includes visible windows + quickfix automatically.

### Ask with a question

```
Visual select → ga → "is this thread-safe?"
Visual select → ga → "what happens on nil input?"
```

### Generate code

```
gsaf → "add error handling"
gsip → "implement this TODO"
gss → "scaffold the module"
```

0.3s. Output in a code buffer with correct filetype. `:w filename` to save.

### Refactor in-place

```
<leader>graf → "simplify"
<leader>grip → "convert to async/await"
Visual <leader>gr → "add type annotations"
```

Replaces code directly. `u` to undo.

### Plan

```
<C-g> → "add rate limiting to the API"
<C-g> → "use token bucket, not sliding window"
```

Fast conversation in the context panel. Shows current filename in prompt.

## Cloud verbs (10-90s)

### Deep check

```
<leader>gcaf        opus reviews this function
<leader>gcip        opus reviews this paragraph
```

### Agent execute

```
<leader>gx → "refactor auth across all files"
<leader>gx → "add tests for the parser module"
```

Cloud agent with tools (read/write/edit/bash). Activity shows in the context panel. Follow up with `<C-g>`.

### Discover project

```
<leader>cd
```

Opus maps your project by domain. `gf` on paths to navigate.

## Context from vim state

### Your screen is context

`ga` auto-includes code from ALL visible windows. Split auth.ts and middleware.ts side by side → `gaip` in auth.ts sees both files.

### Jump trail

Navigate around with `gd`, `gr`, `<C-o>`:

```
<leader>gj          how do these locations connect?
```

### Recent changes

Edit some code, then:

```
<leader>g.          any bugs in my changes?
```

### Quickfix

```vim
:make               errors → quickfix
gaip                explain failure (quickfix auto-included)
```

```vim
:lua vim.diagnostic.setqflist()     LSP diagnostics
gaip                                explain
```

```vim
:grep "TODO" src/**
<C-g> → "summarize what needs doing"
```

## Stateful exploration

Open the panel → `ga` becomes a conversation:

```
<leader>co                open panel
gaip                      first question
gaip                      builds on previous answer
<leader>co                close → back to stateless
```

Save a session: `:w .cogcog/investigation.md`

## Pin from multiple files

```vim
" file A: visual select → <leader>cy
" file B: visual select → <leader>cy
<C-g> → "can these race?"
```

## Generate → check loop

```
gsaf → "implement retry with backoff"      generate (0.3s)
:w src/retry.ts                             save
:make                                       test
gaip                                        explain errors
gsaf → "fix it"                             iterate
<leader>gcaf                                verify with opus
```

## Multi-file agent work

```
<leader>gx → "add input validation to all handlers"
```

Agent reads files, makes changes. Activity streams in the panel:

```
  → Read src/routes/users.ts
  → Edit src/routes/users.ts
  → Read src/routes/orders.ts
  → Edit src/routes/orders.ts
Done. 2 files modified.
```

Follow up:

```
<C-g> → "also add to the admin routes"
```

## Improve prompts over time

Bad response:

```
<leader>cp → "it gave generic advice instead of reading the code"
```

Appends to `.cogcog/system.md`. Prompts improve per-project.

## Context management (native vim)

```vim
<leader>co                          open panel
:read .cogcog/review.md             add review skill
:read !git diff --staged            add staged changes
:read !tree -L 3                    project structure
:read !grep -rn "auth" src/         search results
dap                                 delete a section
:w .cogcog/session.md               save manually
```

## Shell

```bash
echo "explain CRDs" | cogcog --raw
git diff --staged | cogcog --raw "review this"
cat src/main.ts | cogcog --raw "any bugs?"
```

## Combos

```
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

```
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

Pin a domain into context:

```
/### Auth                           jump to auth section
V/### Database                      select the auth domain
<leader>cy                          pin to context
<C-g> → "simplify the token refresh"
```

## Per-project system prompts

`.cogcog/system.md`:

```
You are a senior engineer.
Be concise. Show code when relevant, explain when asked.
This project uses Go, PostgreSQL, Redis.
```

Loaded automatically. Improved incrementally via `<leader>cp`.
