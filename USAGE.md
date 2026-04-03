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

---

## Deep vim integration

### `:compiler` + `:make` → instant feedback loop

Neovim has built-in compiler definitions. Set one and the whole pipeline lights up:

```vim
:compiler cargo                     " sets makeprg + errorformat for Rust
:make                               " cargo build → errors in quickfix
gaip → "explain these errors"       " quickfix auto-included

:compiler pyunit                    " Python tests
:make                               " pytest → failures in quickfix
gaip → "why is this test failing?"
```

`:compiler tsc`, `:compiler go`, `:compiler gcc` — all work. The quickfix integration means `ga` always has the right errors for your language.

### Response chaining — output of one verb feeds another

`gs` generates code. Select it. `ga` explains it. `<leader>gc` verifies it. Each buffer is input to the next:

```
gsaf → "add connection pooling"
" in the gen buffer:
ggVG ga → "walk me through this implementation"
" in the explanation:
ggVG <leader>gc → "is the explanation accurate to the code?"
```

Three models, three perspectives, chained through buffers.

### `formatprg` — LLM as text formatter

```vim
:setlocal formatprg=cogcog\ --raw\ \"reformat\ to\ 80\ columns\"
gqip                                " formats paragraph through LLM
```

Now `gq` is an LLM operation. Works on comments, docs, commit messages. Synchronous — blocks until done. Use for short text.

### `:DiffOrig` — review your own changes

Before committing, see what you changed since opening the file:

```vim
:DiffOrig                           " split showing original vs current
```

Select your changes → `<leader>gc` → opus reviews your work.

Or the git version:

```vim
:Gdiffsplit HEAD                    " fugitive: diff with last commit
```

Select hunks → `ga` → "did I break anything?"

### `:redir` — capture vim state as context

Dump any ex command output into a buffer:

```vim
:redir @a | silent messages | redir END
"ap
gaip → "any errors in these messages?"
```

Or capture LSP info:

```vim
:redir @a | silent lua =vim.lsp.get_clients() | redir END
"ap
gaip → "which LSP servers are running and are they healthy?"
```

### Spell check → LLM prose editing

```vim
:set spell
]s                                  " jump to next misspelled word
gaip → "fix spelling and grammar in this paragraph"
```

Or use the filter:

```vim
:'<,'>!cogcog --raw "fix grammar, keep technical terms unchanged"
```

`u` to undo if you don't like the result.

### Tab pages as parallel sessions

```vim
:tabnew src/frontend/               " tab 1: frontend work
<leader>co                          " open panel — frontend context

:tabnew src/backend/                " tab 2: backend work
<leader>co                          " separate panel — backend context
```

Two independent cogcog sessions, each with their own context panel and conversation. Switch with `gt`.

### LSP navigate → pin → ask

Use LSP to find what matters, then pin it:

```vim
gd                                  " go to definition
visual <leader>cy                   " pin it

gr                                  " go to references
visual <leader>cy                   " pin a key reference

<C-g> → "is this implementation thread-safe given these call sites?"
```

LSP navigates. You curate. The LLM reasons about the connections.

### Model arbitrage

Start free, escalate when needed:

```
gaf → "any issues here?"            " gemma4 answers (free, fast)
```

Answer seems suspicious? Verify:

```
<leader>gcaf                         " opus double-checks (deep, paid)
```

90% of the time gemma4 is right and you pay nothing. For the 10% that matters, opus catches what gemma4 missed.

### Neovim as a data analysis tool

```vim
:read !psql mydb -c "SELECT * FROM orders LIMIT 20"
gaip → "find patterns in this data"

:read !curl -s https://api.example.com/metrics
gaip → "anything anomalous?"

:read !docker stats --no-stream
gaip → "which containers are using too much memory?"
```

Any command that produces text is a data source. The LLM is the analyst.

### Undo time travel

```vim
:earlier 10m                        " what did this file look like 10 min ago?
" copy relevant section
:later 10m                          " back to present
" paste old version, select both
ga → "what changed and why might it break?"
```

### The incremental understanding pattern

For a codebase you've never seen:

```vim
" 1. get the lay of the land
:read !tree -L 2
<C-g> → "what kind of project is this?"

" 2. look at the entry point
:read src/main.ts
<C-g> → "walk me through the startup"

" 3. follow the interesting thread
gd                                  " go to definition of something interesting
gaf → "what does this do?"

" 4. go deeper
<leader>cy                          " pin this function
gd                                  " follow next call
<leader>cy                          " pin that too
<C-g> → "how do these connect?"
```

Each step builds understanding. The panel accumulates your investigation. Save it: `:w .cogcog/codebase-notes.md`

### Generate vim commands, then execute them

Ask the LLM to write vim ex commands. Review. Execute:

```
<C-g> → "write a vim substitute command that converts all snake_case variables to camelCase in this file"
```

Copy the command from the response. Run it:

```vim
:%s/\v_(\l)/\U\1/g
```

Or generate a more complex script:

```
gsip → "write a vim script that reorders all imports alphabetically"
:source %                           " execute the gen buffer
```

The LLM writes the automation. You verify and execute.

### Git conflict resolution

In a merge conflict, select the conflict markers:

```
<<<<<<< HEAD
const timeout = 5000;
=======
const timeout = 10000;
>>>>>>> feature
```

`ga` → "which version is correct? the feature branch increased timeout — why might that matter?"

Or `gs` → "resolve this conflict, keep the higher timeout but add a comment explaining why"

### Documentation-driven development

Write the README first:

```vim
<leader>co
" type or paste the API docs you want
<C-g> → "based on this README, what functions do I need to implement?"
```

Then generate from the plan:

```
gsip → "implement the parse function described in the README"
```

The spec IS the context. The code follows the spec.

### SQL from description

```
<C-g> → "I have tables: users(id, email, created_at), orders(id, user_id, amount, status)"
<C-g> → "write a query: monthly revenue per user who signed up in 2025, only users with >3 orders"
```

Then verify it won't do something terrible:

```
<leader>gcip → "will this query be slow on 10M rows? any missing indexes?"
```

### Regex debugging

Paste a regex you don't understand:

```
gaip → "what does ^(?:(?:25[0-5]|2[0-4]\d|[01]?\d{1,2})\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d{1,2})$ match?
         give 3 examples that match and 3 that don't"
```

Or the reverse — describe what you want:

```
gsip → "write a regex that matches ISO 8601 dates with optional timezone"
```

### Reading obfuscated code

Paste minified/obfuscated JS:

```
gsip → "deobfuscate: rename variables to meaningful names, add whitespace, add comments"
```

The gen buffer gives you readable code with the same logic.

### Dockerfile review

```
<leader>gcip → "audit: layer caching, image size, security, running as root?"
```

### Environment debugging

```vim
:read !env | sort | grep -i "node\|npm\|path"
gaip → "anything misconfigured for a Node.js project?"
```

### `entr` — auto-review on file change

```bash
ls src/*.ts | entr -c sh -c 'cat src/main.ts | cogcog --raw "any new bugs since last check?"'
```

Every time you save, the LLM reviews. Lightweight continuous review.

### Git hooks — pre-commit review

```bash
# .git/hooks/pre-commit
#!/bin/bash
issues=$(git diff --staged | cogcog --raw "list ONLY critical bugs or security issues, one per line. if none, say NONE")
if [[ "$issues" != *"NONE"* ]]; then
    echo "cogcog found issues:"
    echo "$issues"
    echo "commit anyway? (y/n)"
    read -r answer
    [[ "$answer" == "y" ]] || exit 1
fi
```

Every commit gets a free review from your local model.

### Adversarial testing

Generate code, then try to break it:

```
gsaf → "implement a rate limiter"
ga (select output) → "write 5 inputs that would break this rate limiter"
```

Then fix what you found:

```
gsaf → "fix: handle these edge cases: [paste the attacks]"
```

### The consensus pattern

Ask the same question to two models. Compare:

```
gaip → "is this thread-safe?"                  " gemma4 answers
<leader>gcip                                    " opus answers separately
```

If they agree, you're probably fine. If they disagree, that's where the bug is.

### Changelog from git

```bash
git log --oneline --since="2 weeks ago" | cogcog --raw "write a user-facing changelog, group by feature/fix/chore"
```

### Live REPL → ask

```vim
:terminal python3
```

Run some code in the REPL. Copy the output. `ga` → "why did this return None?"

Terminal is a buffer. Copy from it like any buffer.

### API client from curl

Copy a working curl command:

```
curl -X POST https://api.example.com/users \
  -H "Content-Type: application/json" \
  -d '{"name": "test"}'
```

```
gsip → "generate a Go HTTP client for this API endpoint with proper error handling"
```

### Migration from schema diff

Pin the old schema and new schema:

```vim
<leader>cy                          " pin: old CREATE TABLE
<leader>cy                          " pin: new CREATE TABLE
gsip → "write the SQL migration (ALTER TABLE statements)"
<leader>gcip                        " verify it won't lose data
```

### `equalprg` — LLM as indentation fixer

```vim
:setlocal equalprg=cogcog\ --raw\ \"fix\ indentation\"
=ip                                 " fix indentation of this paragraph via LLM
gg=G                                " fix entire file
```

`=` is a vim verb. Now it runs through the LLM. Works on broken YAML, mangled JSON, inconsistent code style.

### Expression register — compute and insert

`"=` evaluates an expression and inserts the result:

```vim
"=system('echo "one-liner to parse ISO date in Go" | cogcog --raw')
p                                   " paste the generated one-liner
```

No split, no buffer. Just inline insert from LLM. Good for quick one-liners while typing.

### `:cexpr` — LLM output as quickfix

Have the LLM produce a list of issues in compiler-error format, load as quickfix:

```bash
cat src/*.ts | cogcog --raw "list bugs as filename:line: message format" > /tmp/issues
```

```vim
:cexpr readfile('/tmp/issues')      " load as quickfix
:copen                              " browse issues
:cnext                              " jump to each one
```

Now you navigate LLM-found bugs with standard quickfix motions.

### `:filter` — narrow before asking

`:filter` restricts command output by pattern:

```vim
:filter /Error/ messages            " only error messages
```

Combine with `:redir` to capture filtered output, then ask:

```vim
:redir @a | filter /warn\|error/ messages | redir END
"ap
gaip → "what's going wrong?"
```

### `grepprg` — semantic search

Set grep to use LLM for semantic search:

```bash
# ~/bin/llm-grep
#!/bin/bash
cat "$2" | cogcog --raw "find lines related to: $1. output as filename:line:text" 2>/dev/null
```

```vim
:set grepprg=llm-grep
:grep "authentication logic" src/
:copen                              " results in quickfix
```

`:grep` becomes semantic. "Find authentication logic" instead of a regex.

### `TextYankPost` — explain what you copy

```lua
vim.api.nvim_create_autocmd("TextYankPost", {
    callback = function()
        if vim.v.event.operator == "y" and vim.v.event.regname == "+" then
            -- when yanking to system clipboard, auto-explain
            vim.schedule(function()
                -- triggers ga on the yanked text
            end)
        end
    end,
})
```

Every time you copy code to clipboard (for a PR, chat, docs), get an auto-explanation. Opt-in by yanking to `+` register.

### `:cbuffer` — buffer as error list

Write issues by hand (or have LLM write them), then load as quickfix:

```vim
<leader>co
<C-g> → "review src/auth.ts for bugs. format each as: src/auth.ts:LINE: ISSUE"
```

Copy the response to a scratch buffer:

```vim
:enew
"+p
:cbuffer                            " parse as quickfix
:copen                              " navigate with :cnext
```

LLM-generated issues, navigable with standard quickfix.

### `completefunc` — LLM-powered completion

```lua
vim.bo.completefunc = function(findstart, base)
    if findstart == 1 then
        return vim.fn.col('.') - 1
    end
    local result = vim.fn.system('echo "' .. base .. '" | cogcog --raw "complete this code, one line"')
    return { { word = vim.trim(result), menu = "[cogcog]" } }
end
```

Now `<C-x><C-u>` triggers LLM completion. Inline, no split. Experimental — slow for real-time, but works for deliberate completion.

### `BufReadCmd` — LLM as a file reader

```lua
vim.api.nvim_create_autocmd("BufReadCmd", {
    pattern = "cogcog://*",
    callback = function(ev)
        local query = ev.file:gsub("^cogcog://", "")
        local result = vim.fn.systemlist('echo "' .. query .. '" | cogcog --raw')
        vim.api.nvim_buf_set_lines(ev.buf, 0, -1, false, result)
        vim.bo[ev.buf].filetype = "markdown"
    end,
})
```

Now `:edit cogcog://explain mutex in Go` opens a buffer with the LLM response. Treat prompts as files.

### `vim.diagnostic` → targeted ask

```lua
-- ask about the diagnostic under cursor
vim.keymap.set("n", "<leader>gd", function()
    local diag = vim.diagnostic.get(0, { lnum = vim.fn.line(".") - 1 })
    if #diag == 0 then return end
    local msg = diag[1].message
    local line = vim.fn.getline(".")
    vim.fn.system('echo "error: ' .. msg .. '\ncode: ' .. line .. '" | cogcog --raw "explain and fix"')
end)
```

One keymap: cursor on a red squiggly → LLM explains the diagnostic and suggests a fix.

### Treesitter queries — surgical context extraction

Instead of selecting lines manually, extract specific AST nodes:

```lua
-- extract all function signatures from current file
local query = vim.treesitter.query.parse("typescript", "(function_declaration name: (identifier) @name)")
local tree = vim.treesitter.get_parser():parse()[1]
local sigs = {}
for _, node in query:iter_captures(tree:root(), 0) do
    table.insert(sigs, vim.treesitter.get_node_text(node, 0))
end
```

Pipe those signatures to `<C-g>` → "which of these functions could be combined?"

Or extract all error handlers:

```vim
:lua local q = vim.treesitter.query.parse("go", "(call_expression function: (selector_expression field: (field_identifier) @fn (#eq? @fn \"Error\")))") -- ...
```

Feed ONLY the error handling code to `ga` → "are any of these swallowing errors?" — zero noise, 100% signal.

### Diff mode with gen buffer — hunk-by-hunk apply

Generate a rewrite, then diff it against the original:

```vim
gsaf → "rewrite with proper error handling"
```

In the gen buffer:

```vim
:diffthis
```

Switch to your original file:

```vim
:diffthis
```

Now you see the diff. Use `do` (diff obtain) to pull specific hunks from the gen buffer. `]c` / `[c` to jump between changes. Cherry-pick what you want, skip what you don't.

Better than accepting/rejecting the whole thing.

### Multiple quickfix stacks

Neovim keeps a stack of quickfix lists. `:colder` and `:cnewer` switch between them:

```vim
:make                               " build errors → qf list 1
:grep "TODO" src/**                 " TODOs → qf list 2
:lua vim.diagnostic.setqflist()     " LSP diagnostics → qf list 3
```

Now navigate between them:

```vim
:colder                             " back to build errors
gaip → "fix this build error"       " quickfix auto-included
:cnewer                             " forward to TODOs
gaip → "is this TODO still relevant?"
```

Three parallel context streams, all in quickfix. No plugin needed.

### Ghost text — LLM suggestions in insert mode

```lua
local ghost_ns = vim.api.nvim_create_namespace("cogcog_ghost")
local timer = nil

vim.api.nvim_create_autocmd("CursorHoldI", {
    callback = function()
        local line = vim.api.nvim_get_current_line()
        if #line < 10 then return end
        -- fire cogcog in background, show result as virtual text
        vim.fn.jobstart({ "bash", "-c", "echo '" .. line .. "' | cogcog --raw 'complete this line, output ONLY the completion'" }, {
            on_exit = function(_, code, _)
                -- show as ghost text via extmark
            end,
        })
    end,
})
```

Cursor pauses in insert mode → LLM suggests completion as dim virtual text. Accept with `<Tab>`, dismiss by continuing to type. Like Copilot, but through your local model.

### Buffer-local keymaps in gen buffer

The gen buffer is just code. Add keymaps that make sense there:

```lua
-- in the gen buffer after gs:
vim.keymap.set("n", "<CR>", function()
    vim.ui.input({ prompt = "save to: " }, function(path)
        if path then vim.cmd("write " .. path) end
    end)
end, { buffer = buf, desc = "save generated code" })

vim.keymap.set("n", "q", function()
    vim.cmd("bdelete!")
end, { buffer = buf, desc = "discard" })
```

`<CR>` to save, `q` to discard. No `:w` path gymnastics.

### `:cdo` + LLM — batch fix

Fix every quickfix entry with a single LLM call pattern:

```vim
:make                               " 12 lint errors
:cdo execute 'normal V' | execute "'<,'>!cogcog --raw \"fix this lint error\""
```

Every error line gets replaced with the LLM's fix. Review with `u` / `:cnext` / `:cprev`.

Nuclear option. Use on a branch.

### `BufWritePre` — auto-review before save

```lua
vim.api.nvim_create_autocmd("BufWritePre", {
    pattern = "*.go",
    callback = function()
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        local issues = vim.fn.system("cogcog --raw 'list ONLY critical bugs, one per line. say NONE if clean'", table.concat(lines, "\n"))
        if not issues:match("NONE") then
            vim.notify("cogcog: " .. vim.trim(issues), vim.log.levels.WARN)
        end
    end,
})
```

Every `:w` on a Go file triggers a quick review. Only warns on critical issues. Uses local model — fast and free.

### `:lua=` as inline context dump

Neovim's `:lua=` prints the return value. Combine with `:redir`:

```vim
:redir @a
:lua =vim.lsp.get_clients()[1].server_capabilities
:redir END
"ap
gaip → "which LSP features am I missing out on?"
```

Or dump treesitter node info:

```vim
:lua =vim.treesitter.get_node():type()
```

Use the AST node type to decide what kind of question to ask.
