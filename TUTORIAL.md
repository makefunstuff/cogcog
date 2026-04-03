# Tutorial: First hour with cogcog

## Setup

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
cp bin/cogcog ~/.local/bin/ && chmod +x ~/.local/bin/cogcog
echo "hello" | cogcog
```

Neovim (lazy.nvim): `{ dir = "/path/to/cogcog" }`

## 1. Map the project

```
<leader>cd
```

Strongest model analyzes your project. Output saved to `.cogcog/discovery.md`. Press `gf` on any path to open the file.

## 2. Quick explain (no prompt)

```
gaip             instant explain of this paragraph
gaf              explain this function
gaa              explain entire buffer
3gaip            detailed explanation with examples
```

Response reuses the same side split. `q` to close.

`ga` auto-includes visible windows and quickfix entries.

## 3. Ask a specific question

```
Visual select → ga → "is this thread-safe?"
```

## 4. Stateful exploration

```
<leader>co                 open panel — ga becomes stateful
gaip                       first question
gaip                       builds on previous
<leader>co                 close → back to stateless
```

## 5. Pin from multiple files

```vim
" file A: visual select → <leader>cy
" file B: visual select → <leader>cy
<C-g> → "can these race?"
```

## 6. Plan (agent reads files)

```
<C-g> → "add rate limiting"
<C-g> → "use token bucket"
```

Local agent reads your codebase with tools.

## 7. Generate code

```
gsaf → "implement rate limiting"
gss → "scaffold the module"
:w src/ratelimit.ts
```

Auto-detects language, strips code fences.

## 8. Refactor in-place

```
<leader>graf → "simplify"
```

Replaces code directly. `u` to undo.

## 9. Deep check

```
<leader>gcaf
```

Strongest model reviews. Response reuses split. `q` to close.

## 10. Multi-file agent work (cloud)

```
<leader>gx → "refactor auth across all files"
```

Cloud agent with live activity. `<C-g>` in the exec buffer to continue.

## 11. Investigate with vim state

```
gd → gd → gd               navigate around
<leader>gj                  "how do these locations connect?"
```

```
" edit some code
<leader>g.                  "any bugs in my changes?"
```

## 12. Test and iterate

```vim
:make                       errors → quickfix
gaip                        explain failure (quickfix auto-included)
gsaf → "fix it"
:make
<leader>gcaf                verify
```

## 13. Improve prompts

```
<leader>cp → "too generic"
```

Appends fix to `.cogcog/system.md`. Prompts improve over time.

## 14. Cancel

```
<C-c>                       cancel any running job
```

## Daily workflow

```
gaip / gaa       quick understanding
gsaf / gss       generate code
<leader>graf     refactor in-place
<leader>gcaf     verify before commit
<C-g>            plan with local agent
<leader>gx       heavy multi-file work (cloud)
<leader>gj       investigate jump trail
<leader>g.       review your changes
q                close response
<C-c>            cancel
```
