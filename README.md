# CogCog

CogCog is not a plugin. It's a workflow. Neovim is already a context engine — buffers, `:read !`, registers, pipes, splits. An LLM is just `stdin → stdout`. CogCog is the thin bridge between the two.

**You build context manually, so you read the code. You choose what matters. The LLM only sees what you curated. Building the context IS the understanding.**

I am not inventing, or pretending it's a revolution, I have a feeling that modern workflows with 'coding agents' 
feels like you trade fake impression of delivery 'speed' to building up enormous amount of hidden debt. And this modern paradigm "i ship code i don't read" will heavily can shoot you in the leg.

I am not rejecting usage of coding agents, I just want to control the context, delegate boring parts, manage the context, avoid tool calling bloat. And maybe (hope so), reduce costs on inference at some point. Waiting 30 seconds for an LLM to grep your codebase, read 15 files, and conclude where a function is defined — when `grep -rn "funcName" src/` takes 0.1 seconds — is not productivity, it's theater. I don't like that all these tools are actually starting to accumulate a lot of "learned helplessness", and dependency of inference api uptime, is not what I want to have.

No bullshit, these scripts were also generated, but my take that I want to introduce the middle ground between generating and actual understading what you are doing.

## Install

```bash
# put the shell script on your PATH
cp bin/cogcog ~/.local/bin/
chmod +x ~/.local/bin/cogcog

# set your API key — or use claude/opencode as backend instead (see Configuration)
export ANTHROPIC_API_KEY="sk-..."
```

Requires: `curl`, `jq`. Or set `COGCOG_CMD="claude -p"` to use any CLI you already have.

**Optional:** Neovim keymaps (async send + streaming response in a split).

```lua
-- lazy.nvim
{ dir = "/path/to/cogcog" }

-- or in init.lua
vim.opt.rtp:prepend("/path/to/cogcog")
require("cogcog")
```

## How it works

A scratch buffer is your context. You `:read` files and command output into it, type your question, send.

### Shell

```bash
echo "explain kubernetes CRDs in 3 sentences" | cogcog
cat src/main.ts src/db.ts | cogcog "review this"
{ cat .cogcog/review.md; git diff --staged; } | cogcog
```

### Neovim

```vim
<leader>co                         " open scratch buffer
:read .cogcog/review.md            " load a context template
:read src/auth/middleware.ts       " add code
:read !git diff HEAD~1             " add command output
                                   " type your question at the bottom
<leader>cs                         " send — response streams into a split
```

Without the plugin, same thing with native vim:

```vim
:enew | setlocal buftype=nofile ft=markdown
:read src/main.ts
:%!cogcog
```

| Keymap | Mode | What it does |
|--------|------|-------------|
| `<leader>co` | normal | Open scratch context buffer |
| `<leader>ci` | normal | Inspect sections, jump to one |
| `<leader>cd` | normal | Delete section under cursor |
| `<leader>ct` | normal | Add project tree to context |
| `<leader>cb` | normal | Add all open buffers to context |
| `<leader>cs` | normal | Send buffer to LLM, response in split |
| `<leader>cs` | visual | Send selection to LLM, response to clipboard |
| `<leader>cy` | visual | Yank selection into context buffer |

## Context templates

Keep a `.cogcog/` directory in your project with reusable templates. The buffer is a workspace, not a chat — curate it per-question, not per-session.

```
.cogcog/
  system.md        # "you are a senior engineer. be concise."
  review.md        # "review for bugs, security, performance..."
  explain.md       # "explain step by step, focus on the why"
  refactor.md      # "refactor for clarity, keep behavior identical"
  debug.md         # "here's code + error output, what's wrong?"
  arch.md          # your system architecture notes
  conventions.md   # project coding style, patterns
```

Starter templates are included in this repo's `.cogcog/` directory. Copy them to your project and customize.

```vim
" compose context from templates + code
:read .cogcog/system.md
:read .cogcog/review.md
:read src/api/routes.ts
:read !git diff HEAD~1 -- src/api/

" if the session was valuable, save it
:w .cogcog/oom-debug-session.md
```

No conversation history, no accumulated state. Each send is self-contained. If the LLM's previous answer matters, paste the relevant part back in — otherwise you're burning tokens on context the model doesn't need.

## Examples

### Code review

```vim
:read .cogcog/review.md
:read !git diff main
```

### Debug a failing test

```vim
:read .cogcog/debug.md
:read !npm test 2>&1 | tail -30
:read src/parser.ts
" type: why is this test failing?
```

### Understand unfamiliar code

```vim
:read src/scheduler.ts
:read src/queue.ts
" type: how does the retry logic work?
```

### Shell one-shots

```bash
git diff --staged | cogcog "review this diff"
kubectl get events -n prod | cogcog "anything alarming here?"
terraform plan -no-color 2>&1 | cogcog "any destructive changes?"
```

### Vibe mode

Nothing stops you from going full slopgen.

```bash
# generate and pipe straight to a file
echo "write a Go CLI that watches a directory for changes and runs make" | cogcog > cmd/watcher/main.go

# generate, then review your own slop
echo "write a python script that converts CSV to JSON" | cogcog | tee convert.py | cogcog "review this for bugs"

# scaffold an entire frontend
echo "react app with tailwind: login page, dashboard with sidebar,
settings page, dark mode toggle, mock auth flow. include routing.
output each file with its path as a header." | cogcog > frontend.md

# full feature — go nuts
echo "express.js REST API:
- sqlite with knex migrations
- user auth (JWT, bcrypt)
- CRUD for posts with pagination
- rate limiting middleware
- error handling
- seed script with fake data
output as separate files with paths: src/db.ts, src/routes/, src/middleware/, etc" | cogcog > feature.md
```

## You don't need MCP

You don't need MCP when Unix is your IDE already. MCP gives an LLM a protocol to discover and call tools. But `curl`, `jq`, `grep`, `kubectl`, `git` — these are already tools. They already have a protocol: stdin, stdout, exit codes. Your shell already composes them. `:read !kubectl get pods` is an MCP server with zero dependencies. `git diff | cogcog` is tool use without a tool registry. The plumbing has been there for 50 years — the LLM is just another filter in the pipeline.

```bash
# "tool calling" — unix edition
pg_dump --schema-only mydb | cogcog "find potential performance issues"
kubectl logs deploy/api --since=5m | grep -i error | cogcog "what's failing?"
curl -s 'http://prometheus:9090/api/v1/query?query=rate(http_requests_total[5m])' | cogcog "explain these metrics"
git log --oneline --since=yesterday | cogcog "summarize what the team shipped"
trivy image myapp:latest --format json | cogcog "critical vulnerabilities?"

# compose them — no SDK, no server, no protocol negotiation
{ echo "## pods"; kubectl get pods -n prod; \
  echo "## events"; kubectl get events -n prod --sort-by='.lastTimestamp' | tail -20; \
  echo "## recent errors"; kubectl logs deploy/api --since=10m | grep -i error | tail -30; \
} | cogcog "on-call summary: what needs attention?"
```

Every CLI you already use is a tool. `|` is your tool calling protocol.

### "But the LLM can't iterate without tool calling"

It can. You close the loop.

```bash
# 1. you don't know where to start — ask
echo "memory leak in a Go service on k8s, pods OOMKilled after ~2h.
what should I run to diagnose?" | cogcog

# 2. run what it suggested, pipe results back
{ echo "## pod describe"; kubectl describe pod api-7f8b9-x2k4n -n prod; \
  echo "## memory"; kubectl top pods -n prod --containers; \
  echo "## OOMKills"; kubectl get events -n prod | grep OOM; } \
| cogcog "here's what you asked for. what's the issue?"

# 3. go deeper
{ echo "## pprof heap"; curl -s http://localhost:6060/debug/pprof/heap?debug=1 | head -50; \
  echo "## goroutines"; curl -s http://localhost:6060/debug/pprof/goroutine?debug=1 | head -30; } \
| cogcog "what's leaking?"
```

Each step, you read the output too — you learn what these commands mean, what normal vs broken looks like. An agent would have done this in 30 silent tool calls and handed you an answer you can't verify.

### "But coding agents can do web search, write tools dynamically..."

So can you.

```bash
# want a web search tool? ask cogcog to write you one
echo "write a bash script called websearch that takes a query,
hits the DuckDuckGo HTML API, extracts top 5 URLs and snippets,
outputs clean text to stdout" | cogcog > ~/bin/websearch
chmod +x ~/bin/websearch

# now you have it. forever. zero dependencies.
websearch "kubernetes memory limits best practice" | cogcog "summarize"

# want RAG? it's an HTTP call
curl -s http://localhost:6333/collections/docs/points/search \
  -d '{"vector": [...], "limit": 5}' \
| jq '.result[].payload.text' \
| cogcog "what's our retry policy?"

# or just grep your own docs
grep -rn "retry" docs/ | cogcog "summarize our retry strategy"

# "dynamic tool writing" — the LLM generates a script, you read it, you run it
echo "bash script that collects pod resource usage, OOMKills,
pprof top allocators, goroutine count. output as markdown." \
| cogcog > diagnose.sh
chmod +x diagnose.sh
./diagnose.sh | cogcog "analyze this"
```

Every "feature" of a coding agent is a shell script you can write in 5 minutes — and then you own it, you can read it, and it works when the API is down.

### You don't even need cogcog

Any `stdin → stdout` LLM CLI works. The workflow is the point, not the tool.

```bash
git diff --staged | claude -p "review this diff"
kubectl get events -n prod | claude -p "anything alarming?"
terraform plan -no-color | opencode run "any destructive changes?"
git log --oneline -20 | pi -p "summarize recent changes"

# they all work in vim too
:%!claude -p "refactor this"
:'<,'>!opencode run "explain"
```

The pattern is always: `your context | any-llm "your question"`. Cogcog is just a thin wrapper around the Anthropic API. If you already have a CLI that reads stdin and writes stdout, use that.

## Configuration

```bash
# model (default: claude-sonnet-4-20250514)
export COGCOG_MODEL="claude-haiku-3-20250514"

# max tokens (default: 8192)
export COGCOG_MAX_TOKENS=16384

# system prompt
export COGCOG_SYSTEM="you are a senior engineer. be concise. no yapping."

# use a different backend (any stdin->stdout CLI)
export COGCOG_CMD="claude -p"
```

## Structure

```
bin/cogcog         # shell script: stdin -> LLM -> stdout
lua/cogcog.lua     # two keymaps for async send
.cogcog/           # starter context templates
  system.md        #   default system prompt
  review.md        #   code review template
  explain.md       #   explain code template
  refactor.md      #   refactor template
  debug.md         #   debugging template
README.md
```

--- project tree ---

.
./lua
./lua/cogcog.lua
./bin
./bin/cogcog
./.git
./.cogcog
./.cogcog/system.md
./.cogcog/review.md
./.cogcog/explain.md
./.cogcog/refactor.md
./.cogcog/debug.md
./README.md
