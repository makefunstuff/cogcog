# Usage & Tricks

## The basics

```
gaip            ask about this paragraph
gsip            generate from this paragraph
<leader>gcip    check this paragraph with opus
```

These are vim verbs. They compose with any motion or text object.

With treesitter-textobjects: `gaf` (ask about function), `gsaf` (rewrite function), `<leader>gcaf` (check function).

## The generate → check loop

Local model generates (free), Opus verifies (smart):

```
gsaf → "add input validation"           " gemma4 generates
<leader>gcaf                             " opus reviews for bugs
```

Fix what the checker found. Repeat. Generate cheap, verify smart.

## Stateful exploration

Open the panel first, then `ga` becomes a conversation:

```
<leader>co                          " open panel — ga is now stateful
gaf → "what pattern is this?"       " appends to panel
gaf → "why not use X instead?"      " builds on previous answer
<leader>co                          " close panel — ga goes back to stateless
```

Good for learning a new codebase. Every question builds on the last. Save the session: `:w .cogcog/learning-go-session.md`

## Pin from multiple files, then ask

```vim
" in file A: visual select → <leader>cy
" in file B: visual select → <leader>cy
" now ask about both
<C-g> → "can these race?"
```

## Quickfix as context

```vim
:make                               " errors → quickfix
gaip → "why is this failing?"       " quickfix auto-included

:lua vim.diagnostic.setqflist()     " LSP diagnostics → quickfix
gaip → "fix these"

:grep "TODO" src/**/*.ts            " grep results → quickfix
<C-g> → "summarize what needs doing"
```

## The Ralph loop

Generate code, test it, verify, iterate. You are the loop.

```vim
gsaf → "implement retry with exponential backoff"     " generate
:w src/retry.ts                                        " save
:make                                                  " test (errors → quickfix)
gsaf → "fix the failing tests"                         " iterate (quickfix auto-included)
:w src/retry.ts
:make                                                  " passes
<leader>gcaf                                           " verify with opus
```

Three cycles, every line reviewed. The [Ralph loop](https://awesomeclaude.ai/ralph-wiggum) pattern without the black box.

## TDD backwards

Write tests by hand. Pin them. Generate the implementation:

```vim
" pin test file
visual <leader>cy

" in implementation file
gsip → "implement to pass these tests, nothing more"
<leader>gcip
```

## Native vim as context management

The context panel is just a buffer:

```vim
<leader>co                          " open panel
:read .cogcog/review.md             " add a skill
:read !git diff --staged            " add staged changes
:read !tree -L 2                    " add project tree
:read !git blame -L 40,60 src/auth.ts   " add blame context
dap                                 " delete a section
```

Type your question at the bottom, `<C-g>` to send.

## Multiple gen buffers

Each `gs` creates a new buffer. Generate multiple variants:

```
gsip → "implement with callbacks"
gsip → "implement with async/await"
gsip → "implement with channels"
```

Three buffers. Compare with `:windo diffthis`. Ask which is better:

Select the diff → `ga` → "which handles backpressure better?"

## Shell one-shots

```bash
git diff --staged | cogcog --raw "review this"
kubectl logs deploy/api --tail=50 | cogcog --raw "what crashed?"
terraform plan -no-color | cogcog --raw "any destructive changes?"
cat go.sum | cogcog --raw "any packages with known CVEs?"
gh pr diff 42 | cogcog --raw "summarize changes, flag risks"
```

## The escape hatch

```vim
:%!cogcog --raw                     " filter entire buffer through LLM
:'<,'>!cogcog --raw "explain"       " filter selection (replaced in-place, undo with u)
```

## Registers

Yank a response into a register, paste elsewhere:

```vim
" in response split: "ay (yank to register a)
" in code file: "ap (paste)
```

## Cancel

`<C-c>` cancels any running job — ask, generate, or check.

---

## Advanced patterns

### The `:g/` filter — extract what matters

```vim
:enew | setlocal buftype=nofile
:read !grep -n "catch\|error\|throw" src/api.ts
gaip → "are any of these swallowing errors?"
```

Or extract function signatures:

```vim
:g/^function\|^const.*=>/t$
```

Select them → `ga` → "which have inconsistent naming?"

### Git archaeology

```vim
<leader>co
:read !git blame -L 40,60 src/auth.ts
:read !git log --oneline -10 -- src/auth.ts
:read !git diff HEAD~5 -- src/auth.ts
<C-g> → "why was the token refresh logic rewritten?"
```

### The review chain

```
gsaf → "refactor for readability"        " gemma4 writes
<leader>gcaf                              " opus reviews
```

Disagree? Pin both and ask:

```
<leader>cy                               " pin generated code
<leader>cy                               " pin review
<C-g> → "the reviewer says X. is the code fine?"
```

### Terminal buffer as context

```vim
:terminal npm test
```

When it finishes, select the error output → `ga` → "explain this failure"

Terminal is a buffer. Everything is a buffer.

### Marks as context bookmarks

```vim
" set marks in different files
mA                                  " mark in file A
mB                                  " mark in file B

" later: quickly pin both
'A → visual select → <leader>cy
'B → visual select → <leader>cy
<C-g> → "how do these interact?"
```

### Clipboard paste

Copy an error from your browser. In vim:

```vim
"+p                                 " paste from system clipboard
gaip → "what went wrong?"
```

### Man pages and docs

```vim
:read !man 2 epoll | head -50
gaip → "explain like I know Python but not C"
```

### Cross-language rewrite

```
gsaf → "rewrite this Python function in Zig, idiomatic style"
```

Gen buffer auto-detects language from code fences and sets filetype.

### Pipe chains

```bash
cat data.csv | cogcog --raw "convert to JSON" | cogcog --raw "find anomalies"
xxd firmware.bin | head -20 | cogcog --raw "what architecture is this?"
```

### Parallel work in tmux

```bash
# pane 1
cat src/api/*.ts | cogcog --raw "find N+1 query patterns"

# pane 2
cat src/middleware/*.ts | cogcog --raw "audit auth for bypasses"

# pane 3
git log --oneline --since=7d | cogcog --raw "what shipped?"
```

---

## Replacing agent features with vim

| Agent feature | Vim equivalent |
|--------------|----------------|
| Codebase search | `:grep "pattern" src/**` → quickfix |
| Read file | `:read src/file.ts` |
| Multi-file edit | `:args src/**/*.ts` → `:argdo %s/old/new/g` |
| Run tests | `:make` → quickfix → `ga` |
| Project structure | `:read !tree -L 3` |
| Code review | `git diff \| cogcog --raw "review"` |
| Web search | `:read !pi-search "query"` |
| Conversation memory | `:w .cogcog/session.md` |
| Parallel agents | tmux panes |
| Auto-fix lint | `:cdo s/var/const/` |

Every agent feature is a shell command + a vim primitive + `ga`/`gs`/`<leader>gc`. The agent wraps these in abstraction and hides what's happening. Cogcog gives you full visibility in tools you already know.

### The point

An agent burns 15000 tokens reading 10 files, 80% irrelevant.

```vim
:read !grep -n "authenticate" src/**/*.ts
gaip → "is there a path where auth is bypassed?"
```

500 tokens, 100% relevant. Better answer, 30x cheaper.
