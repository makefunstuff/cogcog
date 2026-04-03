# cogcog cheatsheet

## Verbs

```
ga{motion}          ask (fast, local)
gs{motion}          generate (agentic)
<leader>gc{motion}  check (deep, cloud)
```

All work in visual mode: select → `ga`, `gs`, `<leader>gc`.

## Context & planning

```
<leader>cy       pin selection to context
<leader>co       toggle context panel (open = ga becomes stateful)
<leader>cc       clear context
<leader>cd       discover project (saves .cogcog/discovery.md, gf-navigable)
<leader>cp       improve prompt from bad response
<C-g>            plan — auto-pins current file, prompts, sends
<C-g> (in panel) send buffer as-is
<C-c>            cancel running job
```

## Quick ask (panel closed = stateless)

```
gaip             "what does this do?"
gaf              "any bugs?"
Visual ga        "explain this error"
```

Quickfix auto-included. Throwaway split, cursor stays in your code.

## Deep ask (panel open = stateful)

```
<leader>co       open panel
gaip             appends to conversation
gaip             builds on previous answer
<leader>co       close → back to stateless
```

## Generate

```
gsip             "add error handling"
gsaf             "rewrite with async/await"
Visual gs        "convert to TypeScript"
```

Code buffer. `:w filename` to save. Auto-detects language.

## Check

```
<leader>gcaf             check this function
<leader>gcip             check this paragraph
Visual <leader>gc        check selection
```

## Plan → Build

```
<C-g>            "let's add rate limiting"
<C-g>            "use token bucket"
gsaf             "implement based on our plan"
<leader>gcaf     verify
```

## Discover

```
<leader>cd       opus maps the project by domain
                 gf on any path to open the file
                 yank domain sections into context
```

## Improve

```
<leader>cp       "response was too generic"
                 → appends fix to .cogcog/system.md
```

## Context management (native vim)

```vim
:read .cogcog/review.md     add a skill
:read !git diff --staged    add git diff
:read !grep -rn "auth" src/ add search results
dap                         delete a section
:w .cogcog/my-session.md    save session
```

## Shell

```bash
echo "explain" | cogcog          agent path
echo "quick" | cogcog --raw      fast API path
git diff | cogcog --raw "review"
```

## Config

```bash
COGCOG_FAST_MODEL   ga: fast model for ask
COGCOG_CMD          gs: agent CLI (stdin→stdout)
COGCOG_CHECKER      gc: checker CLI
COGCOG_BACKEND      openai or anthropic
COGCOG_API_URL      API endpoint
COGCOG_API_KEY      API key
```

## Combos

```
gd → gaf                    definition → ask about it
:make → gaip                 build errors → explain
:grep "TODO" → <C-g>        find TODOs → summarize
ggVG ga                      explain entire file
<leader>cy × N → <C-g>      pin from files → ask
gsip → <leader>gcip          generate → verify
<leader>cd → <C-g>           discover → explore
```
