# Tutorial: First hour with cogcog

## Setup

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
cp bin/cogcog ~/.local/bin/ && chmod +x ~/.local/bin/cogcog
echo "hello" | cogcog
```

Neovim (lazy.nvim):

```lua
{ dir = "/path/to/cogcog" }
```

## 1. Map the project

```
<leader>cd
```

Wait 30-60 seconds. Output is a `gf`-navigable reference saved to `.cogcog/discovery.md`. Cursor on a path → `gf` → you're in the file.

## 2. Understand code

Navigate to a function:

```
gaip             instant explain (no prompt)
3gaip            detailed explanation
```

`ga` auto-includes visible windows and quickfix. Press `q` to close the response.

## 3. Ask specific questions

Visual select code:

```
Visual ga → "is this thread-safe?"
Visual ga → "what happens on timeout?"
```

## 4. Deep exploration (stateful)

```
<leader>co                 open panel — ga is now stateful
gaip                       first question
gaip                       builds on previous answer
<leader>co                 close panel — back to stateless
```

## 5. Pin from multiple files

```vim
" in file A: visual select → <leader>cy
" in file B: visual select → <leader>cy
<C-g> → "can these race?"
```

## 6. Plan a feature

```
<C-g> → "I need to add rate limiting"
<C-g> → "use token bucket, store in redis"
```

Agent reads your codebase and discusses the approach.

## 7. Generate code

```
gsaf → "implement rate limiting based on our plan"
:w src/middleware/ratelimit.ts
```

Code buffer auto-detects language and sets filetype.

## 8. Refactor in-place

```
<leader>graf → "simplify this function"
```

Code replaced directly. `u` to undo if you don't like it.

## 9. Verify

```
<leader>gcaf
```

Strongest model reviews for bugs. `q` to close.

## 10. Multi-file agent work

```
<leader>gx → "refactor auth module to use JWT everywhere"
```

Agent activity streams live. `<C-g>` in the exec buffer to continue.

## 11. Test and iterate

```vim
:make                               " errors → quickfix
gaip                                " explain failure (quickfix auto-included)
gsaf → "fix it"
:make
<leader>gcaf                        " verify
```

## 12. Use your vim state

After navigating around with `gd`, `gr`, `<C-o>`:

```
<leader>gj                          " how do these locations connect?
```

After editing code:

```
<leader>g.                          " any bugs in my changes?
```

## 13. Improve prompts over time

Bad response? Fix it permanently:

```
<leader>cp → "it gave generic advice"
```

Appends instruction to `.cogcog/system.md`.

## 14. Save sessions

Auto-saves on quit. Save manually:

```vim
<leader>co
:w .cogcog/auth-investigation.md
```

Resume next week:

```vim
:read .cogcog/auth-investigation.md
<C-g> → "continuing from where we left off"
```

## Daily workflow

```
gaip             quick understanding
gsaf             generate code
<leader>graf     refactor in-place
<leader>gcaf     verify before commit
<C-g>            plan a feature
<leader>gx       multi-file agent work
<leader>gj       investigate navigation trail
<leader>g.       review your changes
q                close response
<C-c>            cancel if slow
```
