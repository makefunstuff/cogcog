# Tutorial

## Setup

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
cp bin/cogcog ~/.local/bin/ && chmod +x ~/.local/bin/cogcog
```

Neovim: `{ dir = "/path/to/cogcog" }`

## 1. Explain code (instant, no prompt)

```text
gaip             explain this paragraph
gaf              explain this function
gaa              explain entire buffer
3gaip            detailed explanation
```

0.3s. Response in a side split. `q` to close.

## 2. Ask a question

```text
Visual select → ga → "is this thread-safe?"
```

## 3. Open the workbench when you need persistent context

```text
<leader>co       open workbench
gaip             ask with the workbench in play
<C-g>            continue from the workbench
<leader>co       close → back to stateless operator flow
```

## 4. Pin from multiple files

```vim
" file A: visual select → <leader>cy
" file B: visual select → <leader>cy
<C-g> → "can these race?"
```

## 5. Plan / synthesize

```text
<C-g> → "add rate limiting"      fast workbench synthesis
<C-g> → "use token bucket"
```

## 6. Generate code

```text
gsaf → "implement rate limiting"   fast (0.3s), code buffer
gss → "scaffold module"            entire buffer
:w src/ratelimit.ts
```

## 7. Refactor in-place

```text
<leader>graf → "simplify"         small rewrite = inline, large rewrite = review buffer
```

Press `a` to apply from the review buffer. `u` still undoes inline applies.

## 8. Quickfix batch work

```vim
:grep "TODO" src/**
<leader>gQ                        review the target set
<leader>gR                        prepare rewrites → review buffer → a to apply
```

## 9. Check

```text
<leader>gcaf                      review this function
```

By default this uses the bundled Cogcog transport.
Set `COGCOG_CHECKER` only if you want a different checker command.

## 10. Discover project

```text
<leader>cd                        write a navigable discovery note
```

## 11. Optional external execute

```text
<leader>gx → "refactor auth"     explicit external execute, anchored by workbench + visible state
```

This is disabled unless `COGCOG_AGENT_CMD` is set.

## 12. Investigate

```text
gd → gd → gd       navigate
<leader>gj         how do these connect?
<leader>g.         any bugs in my changes?
```

## 13. Iterate

```vim
:make               " errors → quickfix
gaip                " explain (quickfix auto-included)
gsaf → "fix it"
:make
<leader>gcaf        " verify
```

## 14. Improve prompts

```text
<leader>cp → "too generic"       appends fix to .cogcog/system.md
```
