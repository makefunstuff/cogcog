# cogcog cheatsheet

## Verbs (you curate context)

```
ga{motion}          ask (fast, local, you provide code)
gs{motion}          generate (agent, has tools)
<leader>gc{motion}  check (deep, strongest model)
```

Visual mode: select → `ga`, `gs`, `<leader>gc`. Close response with `q`.

## Planning & context (LLM curates context)

```
<C-g>            plan — agentic, reads files, uses tools
<leader>cy       pin selection to context (manual override)
<leader>co       toggle context panel (open = ga becomes stateful)
<leader>cd       discover / update project map
<leader>cp       improve prompt from bad response
<leader>cc       clear context
<C-c>            cancel running job
```

## Quick ask (panel closed = stateless)

```
gaip             "what does this do?"
gaf              "any bugs?"
Visual ga        "explain this error"
```

Quickfix auto-included. Reuses same response split.

## Deep ask (panel open = stateful)

```
<leader>co       open panel
gaip             appends to conversation
gaip             builds on previous
<leader>co       close → back to stateless
```

## Generate

```
gsip             "add error handling"
gsaf             "rewrite with async/await"
Visual gs        "convert to TypeScript"
```

Code buffer with line numbers. `:w filename` to save. Auto-detects language.

## Check

```
<leader>gcaf             check this function
<leader>gcip             check this paragraph
Visual <leader>gc        check selection
```

## Plan → Build

```
<C-g>            "let's add rate limiting"     (agent reads relevant files)
<C-g>            "use token bucket"
gsaf             "implement based on our plan"
<leader>gcaf     verify
```

## Discover

```
<leader>cd       maps project by domain (strongest model)
                 gf on any path to open file
                 Update option for incremental maintenance
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

```
COGCOG_FAST_MODEL   ga: fast model (local)
COGCOG_CMD          gs/<C-g>: agent CLI with tools
COGCOG_CHECKER      gc/<leader>cd: strongest model
COGCOG_BACKEND      openai or anthropic
COGCOG_API_URL      API endpoint
COGCOG_API_KEY      API key
```

## Combos

```
gd → gaf                    definition → ask about it
:make → gaip                 build errors → explain
ggVG ga                      explain entire file
<leader>cy × N → <C-g>      pin from files → plan with context
gsip → <leader>gcip          generate → verify
<leader>cd → <C-g>           discover → explore
<leader>cp                   bad response → improve prompt
```
