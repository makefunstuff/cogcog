# Usage & Tricks

## The basics

```
gaip        ask about this paragraph
gsip        generate from this paragraph
gcip        check this paragraph
```

These are vim verbs. They compose with any motion or text object.

## Treesitter text objects

With nvim-treesitter-textobjects:

```
gaf         ask about this function
gsaf        rewrite this function
gcaf        check this function
gaic        ask about this class
gsac        generate from this class
```

`af` = around function, `ic` = inside class. Any treesitter text object works.

## The generate → check loop

Local model generates (free), cloud model reviews (smart):

```
gsip → "add input validation"
```

Read the output. Then check it:

```
gcip → (kimi-k2.5 reviews for bugs, edge cases)
```

Fix what the checker found. Repeat. Two models for the price of zero.

## Stateful exploration

Open the panel first, then `ga` becomes a conversation:

```
<leader>co                          " open panel
gaip → "what pattern is this?"      " appends to panel
gaip → "why not use X instead?"     " builds on previous answer
<leader>co                          " close panel, ga goes back to stateless
```

Good for learning a new codebase. Every question builds on the last.

## Pin from multiple files, then ask

```
" in file A
visual <leader>cy                   " pin the auth middleware

" in file B  
visual <leader>cy                   " pin the route handler

" now ask about both
<C-g> → "can these race?"
```

Context panel accumulates. The LLM sees both pieces together.

## Quickfix as context

Build errors go straight to the LLM:

```vim
:make                               " build fails, errors in quickfix
gaip → "why is this failing?"       " quickfix entries auto-included
```

Same with LSP diagnostics:

```vim
:lua vim.diagnostic.setqflist()     " push diagnostics to quickfix
gaip → "fix these"
```

Or grep results:

```vim
:grep "TODO" src/**/*.ts            " find all TODOs
<C-g> → "summarize what needs doing"
```

## Shell one-shots

cogcog works without neovim:

```bash
# review staged changes
git diff --staged | cogcog --raw "review this"

# explain a crash
kubectl logs deploy/api --tail=50 | cogcog --raw "what crashed?"

# generate a script
echo "bash script that watches a dir and runs make on changes" | cogcog > watch.sh
```

## Native vim as context management

No special commands needed. The context panel is just a buffer:

```vim
<leader>co                          " open panel
:read .cogcog/review.md             " add review skill
:read !git diff --staged            " add staged changes
:read !tree -L 2                    " add project structure
```

Type your question at the bottom, then `<C-g>` to send.

Delete context you don't need anymore:

```vim
dap                                 " delete around paragraph (a section)
ggdG                                " nuke everything
```

## Save and resume sessions

Sessions auto-save on exit. But you can also save manually:

```vim
<leader>co
:w .cogcog/debug-session.md         " save this investigation
```

Next week:

```vim
:e .cogcog/debug-session.md         " or just read it into panel
```

## Multiple gen buffers

Each `gs` creates a new buffer. Generate multiple variants:

```
gsip → "implement with callbacks"
gsip → "implement with async/await"
gsip → "implement with channels"
```

Three buffers open. Compare side by side with `:windo diffthis`.

## Refactor with context

Pin the tests, then refactor the implementation:

```
" pin the test file
visual <leader>cy                   " select test cases

" now refactor — the LLM knows what the tests expect
gsaf → "refactor, keep all tests passing"
```

## Commit messages

```bash
git diff --staged | cogcog --raw "write a commit message, just the message"
```

Or from vim:

```vim
:read !git diff --staged
<C-g> → "write a commit message for this"
```

## Explain an entire file

```
ggVG ga → "walk me through this file"
```

Or from shell:

```bash
cat src/scheduler.ts | cogcog --raw "explain the architecture"
```

## Chain tools

```bash
# find slow queries, explain them
pg_dump --schema-only mydb | cogcog --raw "find missing indexes"

# audit dependencies
cat package-lock.json | cogcog --raw "any known vulnerable packages?"

# review terraform plan
terraform plan -no-color | cogcog --raw "any destructive changes?"
```

## Use registers

Yank an LLM response into a register, paste it elsewhere:

```vim
" in the response split
"ay                                 " yank into register a

" in your code file
"ap                                 " paste
```

## Macros

Record a check-all-functions macro:

```
qq          " start recording
]m          " jump to next function
gcaf        " check it
q           " stop recording
10@q        " check next 10 functions
```

## Per-project system prompts

Each project gets its own `.cogcog/system.md`:

```
# for a Go project
.cogcog/system.md: "You are a Go expert. Prefer stdlib. No external dependencies unless asked."

# for a frontend project  
.cogcog/system.md: "You are a React/TypeScript expert. Use hooks, no class components."
```

The system prompt auto-loads into the context panel on start.

## The escape hatch

Everything is just stdin/stdout. If cogcog doesn't do what you want:

```vim
:%!cogcog --raw                     " filter entire buffer through LLM
:'<,'>!cogcog --raw "explain"       " filter selection
```

This is vim's native `!` filter. Works with any command. No plugin needed.

---

## Advanced patterns

### TDD backwards — tests first, implement from context

Write your tests. Pin them. Generate the implementation:

```
" write tests by hand
visual <leader>cy                   " pin the test file

" in the implementation file
gsip → "implement to pass these tests, nothing more"
gcip → (verify it actually passes)
```

The LLM sees your tests as the spec. It generates exactly what's needed.

### Git blame archaeology

```vim
:read !git blame -L 40,60 src/auth.ts
:read !git log --oneline -10 -- src/auth.ts
:read !git diff HEAD~5 -- src/auth.ts
```

Then ask:

```
<C-g> → "why was the token refresh logic rewritten? was the old version buggy?"
```

Git history as LLM context. Understand decisions, not just code.

### The `:g/` filter — extract what matters

```vim
" grab only error handling code from a large file
:enew | setlocal buftype=nofile
:read !grep -n "catch\|error\|throw\|reject" src/api.ts
```

Now `gaip` → "are any of these swallowing errors?"

Or use `:g/` inside a buffer:

```vim
" copy all function signatures to a new buffer
:g/^function\|^const.*=.*=>/t$ 
```

Select them all → `ga` → "which of these have inconsistent naming?"

### Visual block mode — columnar operations

Select a column of variable names with `<C-v>`:

```
const userData = ...
const userEmail = ...  
const userName = ...
```

Visual block select the names → `ga` → "are these following a consistent naming convention?"

### Diff two approaches

Generate two variants, then compare:

```vim
gsip → "implement with promises"
" save to file A
:w /tmp/approach-a.ts

gsip → "implement with async generators"  
:w /tmp/approach-b.ts

:vert diffsplit /tmp/approach-a.ts
```

Now select the diff → `ga` → "which approach handles backpressure better?"

### Log forensics

```bash
# grab recent errors
journalctl -u myservice --since "1 hour ago" | grep -i error > /tmp/errors.log
```

```vim
:read /tmp/errors.log
gaip → "what's the root cause? is there a pattern?"
```

Or kubernetes:

```vim
:read !kubectl logs deploy/api --since=5m | grep -v healthcheck | tail -50
:read !kubectl describe pod api-xyz | grep -A5 "State\|Restart\|Events"
<C-g> → "what's causing the restarts?"
```

### Database schema exploration

```vim
:read !psql mydb -c "\dt"                              " list tables
:read !psql mydb -c "\d+ users"                        " schema
:read !psql mydb -c "SELECT * FROM users LIMIT 3"      " sample data
<C-g> → "suggest indexes for common query patterns"
```

### The recursive self-improvement

Generate code, check it, feed the check back to generate again:

```
gsaf → "add caching"                " generates v1
gcaf → (finds: "no cache invalidation")
gsaf → "add caching with TTL-based invalidation"   " generates v2, informed by check
```

Each cycle improves. Local model generates, cloud model finds holes, you decide.

### Regex and one-liner generation

```vim
:enew
i need a regex that matches ISO dates but not timestamps
```

`gsip` → you get the regex. Test it immediately:

```vim
:read !grep -P '<paste regex>' src/**/*.ts
```

### Explain error output in-place

Your build fails. The error is in the terminal. Select it:

```
:'<,'>!cogcog --raw "explain this error and suggest a fix"
```

The error text is **replaced** with the explanation. Undo with `u` to get the error back.

### The review chain — author → reviewer → arbiter

```
gsaf → "refactor this for readability"     " qwen3.5 writes
gcaf → (kimi checks)                       " kimi reviews
```

Disagree with the review? Pin both and ask a third:

```
<leader>cy  " pin the generated code
<leader>cy  " pin the review
<C-g> → "the reviewer says X. is the reviewer right or is the code fine?"
```

Three models, three perspectives.

### Infrastructure as code review

```bash
terraform plan -no-color 2>&1 | cogcog --raw "list every destructive change"
```

Or in vim before applying:

```vim
:read !terraform plan -no-color
gcip → (cloud model checks for dangerous changes)
```

### Documentation from implementation

```
gsaf → "write a docstring for this function. include params, return type, and one example."
```

The gen buffer has just the docstring. Yank it back:

```vim
" in gen buffer
ggVGy

" in source file, above the function
P
```

### The typing teacher — learn a new language

Open a Go file you don't know:

```vim
<leader>co                          " open panel for stateful exploration
gaf → "explain this function, I know Python but not Go"
gaf → "what's the defer keyword doing here?"
gaf → "how would I write this in Python?"
```

The panel accumulates your learning session. Save it:

```vim
:w .cogcog/learning-go-session.md
```

### Macro: check every function in a file

```vim
qq]mgcafq                           " record: next function → check it
100@q                               " replay across the file
```

You get a review split for every function. Read through them.

### Pipe chain — transform data through LLM

```bash
# CSV → JSON → analyzed
cat data.csv | cogcog --raw "convert to JSON" | cogcog --raw "find anomalies"

# API response → summary
curl -s https://api.example.com/status | cogcog --raw "is anything degraded?"

# binary → explained
xxd firmware.bin | head -20 | cogcog --raw "what architecture is this? any magic bytes?"
```

### The scratch debugger

Reproduce a bug in a scratch buffer:

```vim
:enew
:read !curl -s http://localhost:3000/api/users      " the broken response
:read !cat src/routes/users.ts                       " the handler
:read !cat src/db/queries.ts                         " the query
<C-g> → "the API returns empty array even though the DB has data. why?"
```

All context in one buffer. No framework, no debug protocol, just text.

### Cross-language rewrite

```
gsaf → "rewrite this Python function in Zig, idiomatic style"
```

The gen buffer sets filetype automatically from the code fences. You get syntax-highlighted Zig.

### The Ralph loop — generate, test, verify, iterate

The [Ralph loop](https://awesomeclaude.ai/ralph-wiggum) is a pattern where an AI agent generates code, tests it, verifies the result, and iterates until done. Agents like Claude Code do this automatically in 30 silent tool calls. With cogcog, YOU are the loop — and you see everything.

**Step 1: Generate**

```
gsaf → "add rate limiting middleware"
```

**Step 2: Test**

Save the gen buffer, run tests:

```vim
:w src/middleware/ratelimit.ts
:make                                " or :!npm test
```

**Step 3: Verify**

Build errors land in quickfix. Check what went wrong:

```
gcaf → (cloud model reviews the generated code against the errors)
```

Or if tests pass, check anyway:

```vim
:read !npm test 2>&1 | tail -20
gaip → "do these tests actually cover edge cases?"
```

**Step 4: Iterate**

If the checker found problems, feed them back:

```
gsaf → "fix: rate limiter doesn't reset after window expires (see quickfix)"
```

Quickfix context is auto-included. The LLM sees the errors and the code together.

**The full cycle in practice:**

```vim
gsaf → "implement retry with exponential backoff"     " generate
:w src/retry.ts                                        " save
:!go test ./... 2>&1 | head -20                        " test
" tests fail — errors in quickfix
gsaf → "fix the failing tests"                         " iterate (quickfix auto-included)
:w src/retry.ts                                        " save
:!go test ./...                                        " test again
" tests pass
gcaf                                                   " verify with cloud model
```

You closed the loop 3 times in under a minute. You read every line. You ran the tests yourself. You verified with a second model. No silent tool calls, no black box.

The difference from automated Ralph: you learn what retry logic looks like, you see why the first attempt failed, you understand what the checker caught. The agent version ships faster but teaches nothing.

### Rubber duck debugging

Open the panel. Explain your bug to the LLM:

```
<C-g> → "I have a race condition. Process A writes to the queue, process B reads. 
         Sometimes B reads stale data. I think the issue is..."
```

Half the time you solve it while typing. The other half, the LLM catches what you missed.
