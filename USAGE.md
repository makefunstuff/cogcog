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

---

## Replacing agent features with vim

Every feature of a coding agent is a vim primitive you already have.

### "Codebase search" — agents grep for you. You can grep.

An agent spends 10 seconds and 5 tool calls finding where `handleAuth` is defined.

```vim
:grep "handleAuth" src/**/*.ts
:copen                              " quickfix list with every match
```

0.1 seconds. Now ask about what you found:

```
gaip → "which of these is the main implementation vs tests?"
```

### "Read file" — agents read files for you. You have `:read`.

An agent calls `read_file("src/config.ts")` and burns 500 tokens on tool call overhead.

```vim
:read src/config.ts                 " instant, zero tokens wasted
```

Or read just the part you care about:

```vim
:read !sed -n '40,60p' src/config.ts
```

### "Multi-file edit" — agents edit files for you. You have arglist.

An agent iterates over files with tool calls. You have `:argdo`:

```vim
:args src/**/*.ts
:argdo %s/oldFunc/newFunc/g | update
```

Need the LLM to decide what to change? Generate a sed script:

```
<C-g> → "write a sed command that renames oldFunc to newFunc 
         but only in function calls, not the definition"
```

Copy the command, run it. You verified the regex. The agent wouldn't.

### "Run tests" — agents run tests for you. You have `:make`.

```vim
:set makeprg=npm\ test
:make                               " runs tests, errors → quickfix
:cnext                              " jump to first failure
gaip → "why is this failing?"       " quickfix auto-included
```

`:make` + quickfix + `ga` = the entire "run tests, read errors, explain failure" agent loop. Built into vim since 1991.

### "Project structure" — agents call `tree`. You have `:read !`.

```vim
:read !tree -L 3 --noreport -I node_modules
<C-g> → "where should I add the new middleware?"
```

### "Code review" — agents diff for you. You have fugitive.

```vim
:Git diff main                      " fugitive shows the diff
```

Select the hunks you want reviewed → `ga` → "any issues?"

Or the whole thing:

```bash
git diff main | cogcog --raw "review for bugs, security, performance"
```

### "Web search" — agents search for you. You have a terminal.

```vim
:read !curl -s "https://api.duckduckgo.com/?q=golang+mutex+best+practices&format=json" | jq '.AbstractText'
```

Or just:

```vim
:read !pi-search "golang mutex patterns" 2>/dev/null | head -20
<C-g> → "based on these results, should I use sync.Mutex or sync.RWMutex here?"
```

### "Context gathering" — agents read 15 files. You read what matters.

The agent's approach:

```
1. Read src/auth.ts (2000 tokens)
2. Read src/middleware.ts (1500 tokens)  
3. Read src/types.ts (800 tokens)
4. Read src/config.ts (600 tokens)
5. Read src/utils.ts (1200 tokens)
... 10 more files
Total: 15000 tokens of context, 80% irrelevant
```

Your approach:

```vim
:read !grep -n "authenticate\|authorize" src/**/*.ts
```

50 lines. The relevant lines only. Then:

```
gaip → "is there a path where auth is bypassed?"
```

500 tokens of context, 100% relevant. Better answer, 30x cheaper.

### "Plan and execute" — agents plan in JSON. You plan in text.

Agent creates a structured plan, then executes steps silently.

You:

```
<leader>co
<C-g> → "I need to add OAuth2. What files need to change and in what order?"
```

Read the plan. Disagree? Say so:

```
<C-g> → "skip the migration for now, just the middleware"
```

Now execute yourself, step by step:

```
gsaf → "add OAuth2 middleware based on our plan"
:w src/middleware/oauth.ts
:make
gcaf
```

You understood every step. The agent understood none.

### "Conversation memory" — agents store history. You have buffers.

Agents maintain conversation state in a database. You:

```vim
:w .cogcog/oauth-investigation.md   " save the session
```

Next week:

```vim
<leader>co
:read .cogcog/oauth-investigation.md
<C-g> → "continuing from last time — did we decide on PKCE?"
```

Your "memory" is a file. You can grep it, edit it, version it with git. An agent's memory is a black box you can't inspect.

### "Parallel agents" — agents spawn subagents. You have tmux.

In tmux pane 1:

```bash
cat src/api/*.ts | cogcog --raw "find all N+1 query patterns"
```

In tmux pane 2:

```bash
cat src/middleware/*.ts | cogcog --raw "audit auth middleware for bypasses"
```

In tmux pane 3:

```bash
git log --oneline --since=7d | cogcog --raw "what shipped this week?"
```

Three "agents" running in parallel. You read all three results. An orchestrator agent would have summarized away the details.

### "Auto-fix lint errors" — agents fix for you. You have `:cdo`.

```vim
:make                               " lint errors → quickfix
:cdo s/var /const /                 " fix all var→const automatically
```

Need smarter fixes? Generate a script:

```
<C-g> → "write a vim command that fixes each quickfix entry"
```

Or per-error:

```vim
:cfirst
gaip → "fix this lint error"        " quickfix context auto-included
:cnext
gaip → "fix this one too"
```

### "Summarize PR" — agents read diffs. You pipe them.

```bash
gh pr diff 42 | cogcog --raw "summarize changes, flag risks"
```

Or review specific files:

```bash
gh pr diff 42 -- src/auth/ | cogcog --raw "security review"
```

### "Dependency audit" — agents read lockfiles. You pipe them too.

```bash
cat go.sum | cogcog --raw "any packages with known CVEs?"
npm audit --json 2>/dev/null | cogcog --raw "which of these are actually exploitable in our context?"
```

### The point

Every "agent feature" is:
1. A shell command that already exists (grep, git, curl, make)
2. A vim primitive that already exists (:read, :make, :grep, :cdo, quickfix)
3. Plus `ga`/`gs`/`gc` to add LLM intelligence on top

The agent wraps these in 15 layers of abstraction, burns 10x the tokens, and hides what's happening. Cogcog gives you the same power with full visibility, in tools you already know.

### Rubber duck debugging

Open the panel. Explain your bug to the LLM:

```
<C-g> → "I have a race condition. Process A writes to the queue, process B reads. 
         Sometimes B reads stale data. I think the issue is..."
```

Half the time you solve it while typing. The other half, the LLM catches what you missed.
