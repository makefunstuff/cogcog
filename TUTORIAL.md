# Tutorial

## Setup

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
cp bin/cogcog ~/.local/bin/ && chmod +x ~/.local/bin/cogcog
```

Neovim: `{ dir = "/path/to/cogcog" }`

## 1. Explain code (instant, no prompt)

```
gaip             explain this paragraph
gaf              explain this function
gaa              explain entire buffer
3gaip            detailed explanation
```

0.3s. Response in a side split. `q` to close.

## 2. Ask a question

```
Visual select → ga → "is this thread-safe?"
```

## 3. Stateful exploration

```
<leader>co       open panel — ga becomes stateful
gaip             first question
gaip             builds on previous
<leader>co       close → back to stateless
```

## 4. Pin from multiple files

```vim
" file A: visual select → <leader>cy
" file B: visual select → <leader>cy
<C-g> → "can these race?"
```

## 5. Plan

```
<C-g> → "add rate limiting"      fast conversation in panel
<C-g> → "use token bucket"
```

## 6. Generate code

```
gsaf → "implement rate limiting"   fast (0.3s), code buffer
gss → "scaffold module"           entire buffer
:w src/ratelimit.ts
```

## 7. Refactor in-place

```
<leader>graf → "simplify"         replaces code, u to undo
```

## 8. Check

```
<leader>gcaf                      opus reviews (10-90s)
```

## 9. Agent execute

```
<leader>gx → "refactor auth"     cloud agent, in context panel
```

Has tools (read/write/edit/bash). Activity shows inline.

## 10. Discover project

```
<leader>cd                        opus maps project, gf-navigable
```

## 11. Investigate

```
gd → gd → gd       navigate
<leader>gj          how do these connect?
<leader>g.          any bugs in my changes?
```

## 12. Iterate

```vim
:make               errors → quickfix
gaip                explain (quickfix auto-included)
gsaf → "fix it"
:make
<leader>gcaf        verify
```

## 13. Improve prompts

```
<leader>cp → "too generic"       appends fix to .cogcog/system.md
```
