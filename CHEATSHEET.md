# cogcog cheatsheet

## Verbs

```
ga{motion}       ask (fast, local)
gs{motion}       generate (agentic, cloud)
<leader>gc{motion}  check (opus, deep)
```

All work in visual mode too: select → `ga`, `gs`, `<leader>gc`.

## Context

```
<leader>cy       pin selection to context
<leader>co       toggle context panel
<leader>cc       clear context
<leader>cd       discover project (opus, saves .cogcog/discovery.md)
<C-g>            plan — prompt from anywhere, or send buffer if in panel
<C-c>            cancel running job
```

## Quick ask (stateless)

```
gaip             "what does this do?"
gaf              "any bugs?"
Visual ga        "explain this error"
```

Panel closed = throwaway split. Quickfix auto-included.

## Deep ask (stateful)

```
<leader>co       open panel first
gaip             now appends to panel (conversation)
gaip             builds on previous answer
<leader>co       close panel → back to stateless
```

## Generate

```
gsip             "add error handling"
gsaf             "rewrite with async/await"
Visual gs        "convert to TypeScript"
```

Output in a code buffer. `:w filename` to save. Auto-detects language.

## Check

```
<leader>gcaf     opus reviews this function
<leader>gcip     opus reviews this paragraph
Visual <leader>gc  opus reviews selection
```

## Plan → Build

```
<C-g>            "let's add rate limiting"
<C-g>            "use token bucket"
gsaf             "implement based on our plan"
<leader>gcaf     verify with opus
```

## Discover

```
<leader>cd       one-time project analysis (opus)
                 saves to .cogcog/discovery.md
                 gf on any path to open the file
```

## Context management (native vim)

```vim
:read .cogcog/review.md          add a skill
:read !git diff --staged         add git diff
:read !tree -L 3                 add project tree
:read !grep -rn "auth" src/      add search results
dap                              delete a section
ggdG                             clear everything
:w .cogcog/my-session.md         save session
```

## Shell

```bash
echo "explain" | cogcog          default backend
echo "quick" | cogcog --raw      fast path (skips agent)
git diff | cogcog --raw "review"
```

## Models

```
ga  → COGCOG_FAST_MODEL  (local gemma4, 0.3s)
gs  → COGCOG_CMD          (opencode kimi-k2.5, agentic)
gc  → COGCOG_CHECKER      (pi opus:xhigh)
```

## Ralph loop

```
gsaf → "implement retry"     generate
:w src/retry.ts               save
:make                          test (errors → quickfix)
gsaf → "fix the errors"       iterate (quickfix auto-included)
:make                          test again
<leader>gcaf                   verify with opus
```

## Combos

```
gd → gaf                    go to definition → ask about it
:make → gaip                 build errors → explain failure
:grep "TODO" → <C-g>        find TODOs → summarize
ggVG ga                      explain entire file
<leader>cy × N → <C-g>      pin from multiple files → ask
gsip → <leader>gcip          generate → verify
```
