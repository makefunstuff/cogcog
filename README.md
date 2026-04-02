# CogCog

CogCog is not a plugin. It's a workflow. Neovim is already a context engine — buffers, `:read !`, registers, pipes, splits. An LLM is just `stdin → stdout`. CogCog is the thin bridge between the two.

**You build context manually, so you read the code. You choose what matters. The LLM only sees what you curated. Building the context IS the understanding.**

I am not inventing, or pretending it's a revolution, I have a feeling that modern workflows with 'coding agents' 
feels like you trade fake impression of delivery 'speed' to building up enormous amount of hidden debt. And this modern paradigm "i ship code i don't read" will heavily can shoot you in the leg.

I am not rejecting usage of coding agents, I just want to control the context, delegate boring parts, manage the context, avoid tool calling bloat. And maybe (hope so), reduce costs on inference at some point. Waiting 30 seconds for an LLM to grep your codebase, read 15 files, and conclude where a function is defined — when `grep -rn "funcName" src/` takes 0.1 seconds — is not productivity, it's theater. I don't like that all these tools are actually starting to accumulate a lot of "learned helplessness", and dependency of inference api uptime, is not what I want to have.

No bullshit, these scripts were also generated, but my take that I want to introduce the middle ground between generating and actual understading what you are doing.


## Install

```bash
# 1. Put the shell script on your PATH
cp bin/cogcog ~/bin/
chmod +x ~/bin/cogcog

# 2. Set your API key
export ANTHROPIC_API_KEY="sk-..."
```

Requires: `curl`, `jq`

**Optional:** Load the Lua keymaps in your Neovim config.

```lua
-- lazy.nvim
{ dir = "/path/to/cogcog" }

-- or manually in init.lua
vim.opt.rtp:prepend("/path/to/cogcog")
require("cogcog")
```

## Usage

### Shell

The script reads stdin, sends it to Claude, writes the response to stdout. That's it.

```bash
echo "explain kubernetes CRDs in 3 sentences" | cogcog
cat src/main.ts src/db.ts | cogcog
```

### Neovim — zero plugins

Everything is native vim. A scratch buffer is your context.

```vim
" open a scratch buffer — this is your context
:enew | setlocal buftype=nofile ft=markdown

" append files — you read them, you choose them
:read src/main.ts
:read src/db.ts

" append command output
:read !grep -rn 'TODO' src/
:read !git log --oneline -10

" type your question at the bottom, then:
:%!cogcog              " send whole buffer
:'<,'>!cogcog          " send just a selection
```

Your context is a buffer you can edit, reorder, and trim. The LLM sees exactly what you see.

### Neovim — with keymaps

The optional Lua file adds two keymaps. The only thing it does that raw vim can't: async send (non-blocking) with response in a separate split (context stays intact).

| Keymap | What it does |
|--------|-------------|
| `<leader>co` | Open a scratch context buffer |
| `<leader>cs` | Send buffer to LLM, response in split |

Build context with native vim:

```vim
:read src/main.ts              " add a file
:read !git log --oneline -10   " add command output
:'<,'>y                        " yank a selection, paste into context
```

## Workflow: context templates

Keep a directory of reusable context snippets — system prompts, review checklists, architecture notes, style guides. Load what you need.

```
~/.cogcog/
  review.md        # "review this code for bugs, security, readability"
  explain.md       # "explain this code step by step"
  refactor.md      # "refactor for clarity, keep behavior identical"
  style.md         # project conventions, naming rules
  arch.md          # system architecture overview
```

Then in Neovim:

```vim
" load a template + the code you care about
:read ~/.cogcog/review.md
:read src/auth/middleware.ts

" or compose multiple contexts
:read ~/.cogcog/style.md
:read ~/.cogcog/arch.md
:read src/api/routes.ts
:read !git diff HEAD~1 -- src/api/

" edit the buffer, trim what's irrelevant, send
```

You build a library of contexts over time. Each one is a plain text file you can version, share, and edit.

### Examples

```vim
" code review: template + diff
:read ~/.cogcog/review.md
:read !git diff main

" debug a failing test: error output + source
:read !npm test 2>&1 | tail -30
:read src/parser.ts
" type: why is this test failing?

" understand unfamiliar code: just the files you're staring at
:read src/scheduler.ts
:read src/queue.ts
" type: how does the retry logic work?

" quick one-shot from shell
git diff --staged | cogcog "review this diff"
kubectl get events -n prod | cogcog "anything alarming here?"
```

### Vibe mode

Nothing stops you from going full slopgen. Open a buffer, type what you want, send it.

```vim
" yolo a whole component
:enew | setlocal buftype=nofile ft=markdown
" type: write me a react dashboard with charts and dark mode
" <leader>cs → paste the output into your project

" generate from shell, pipe straight to a file
echo "write a Go CLI that watches a directory for changes and runs make" | cogcog > cmd/watcher/main.go

" chain it — generate, then immediately review your own slop
echo "write a python script that converts CSV to JSON" | cogcog | tee convert.py | cogcog "review this for bugs"

" scaffold fast
echo "terraform module for an RDS postgres with read replica" | cogcog > modules/rds/main.tf
echo "dockerfile for a bun app with multi-stage build" | cogcog > Dockerfile

" generate an entire frontend — dump it, split it, ship it
echo "react app with tailwind: login page, dashboard with sidebar,
settings page, dark mode toggle, mock auth flow. include routing.
output each file with its path as a header." | cogcog > frontend.md

" full feature — go nuts
echo "express.js REST API:
- sqlite with knex migrations
- user auth (JWT, bcrypt)
- CRUD for posts with pagination
- rate limiting middleware
- error handling
- seed script with fake data
output as separate files with paths: src/db.ts, src/routes/, src/middleware/, etc" | cogcog > feature.md
```

## Configuration

```bash
# Change the model (default: claude-sonnet-4-20250514)
export COGCOG_MODEL="claude-haiku-3-20250514"

# Change max tokens (default: 8192)
export COGCOG_MAX_TOKENS=16384

# System prompt — persistent instructions without cluttering your context
export COGCOG_SYSTEM="you are a senior engineer. be concise. no yapping."

# Use a different LLM command entirely (any stdin->stdout program works)
export COGCOG_CMD="my-local-llm"
```

### Tool calling

You don't need MCP when Unix is your IDE already. MCP gives an LLM a protocol to discover and call tools. But `curl`, `jq`, `grep`, `kubectl`, `git` - these are already tools. They already have a protocol: stdin, stdout, exit codes. Your shell already composes them. `:read !kubectl get pods` is an MCP server with zero dependencies. `git diff | cogcog` is tool use without a tool registry. The plumbing has been there for 50 years — the LLM is just another filter in the pipeline.

```bash
# database tool
pg_dump --schema-only mydb | cogcog "find potential performance issues"

# kubernetes tool
kubectl get events -n prod --sort-by='.lastTimestamp' | cogcog "anything alarming?"

# observability tool
curl -s 'http://prometheus:9090/api/v1/query?query=rate(http_requests_total[5m])' | cogcog "explain these metrics"

# git tool
git log --oneline --since=yesterday | cogcog "summarize what the team shipped"

# infrastructure tool
terraform plan -no-color 2>&1 | cogcog "any destructive changes here?"

# incident response tool
kubectl logs deploy/api --since=5m | grep -i error | cogcog "what's failing and why?"

# security tool
trivy image myapp:latest --format json | cogcog "critical vulnerabilities?"

# compose them — no SDK, no server, no protocol negotiation
{ echo "## pods"; kubectl get pods -n prod; echo "## events"; kubectl get events -n prod --sort-by='.lastTimestamp' | tail -20; echo "## recent errors"; kubectl logs deploy/api --since=10m | grep -i error | tail -30; } | cogcog "on-call summary: what needs attention?"
```

Every CLI you already use is a tool. `|` is your tool calling protocol.

### "But the LLM can't iterate without tool calling"

It can. You just close the loop yourself.

```bash
# 1. you don't know where to start — ask
echo "I have a memory leak in a Go service running in k8s. pods get OOMKilled after ~2h.
what commands should I run to diagnose this?" | cogcog

# LLM says: check memory limits, get pod describe, look at Go pprof, check restart count...

# 2. you run what it suggested, pipe results back
{ echo "## pod describe"; kubectl describe pod api-7f8b9-x2k4n -n prod; \
  echo "## memory over time"; kubectl top pods -n prod --containers; \
  echo "## recent OOMKills"; kubectl get events -n prod | grep OOM; } \
| cogcog "here's what you asked for. what's the issue?"

# LLM narrows it down: "container has no memory limit, Go runtime defaults to GOMEMLIMIT=off..."

# 3. you go deeper
{ echo "## go pprof heap"; curl -s http://localhost:6060/debug/pprof/heap?debug=1 | head -50; \
  echo "## goroutine count"; curl -s http://localhost:6060/debug/pprof/goroutine?debug=1 | head -30; } \
| cogcog "found the pprof endpoints. what's leaking?"
```

The LLM tells you what to look at. You run it. You pipe it back. Each step, you read the output too — so you learn what these commands mean, what the metrics look like, what normal vs broken is. An agent would have done this in 30 silent tool calls and handed you an answer you can't verify.

The iteration loop isn't missing. The agent just isn't the one driving it — you are.

### "But coding agents can do web search, write tools dynamically..."

So can you. Faster, and without burning tokens on tool discovery.

```bash
# web search — you already have it
curl -s "https://html.duckduckgo.com/html/?q=go+GOMEMLIMIT+best+practice" \
| sed -n 's/.*<a rel="nofollow" class="result__a" href="\([^"]*\)".*/\1/p' | head -5 \
| cogcog "summarize the top results for GOMEMLIMIT configuration"

# or just use your browser, copy the relevant part, paste into the context buffer
# you already filtered the noise — the LLM gets signal, not 10 pages of SEO slop

# "dynamic tool writing" - the LLM writes a script, you run it
echo "write a bash one-liner that finds the top 10 Go allocations from pprof heap output" | cogcog
# LLM outputs: curl -s localhost:6060/debug/pprof/heap?debug=1 | grep -E '^\s+[0-9]' | sort -rn | head -10

# you read it, it makes sense, you run it
# an agent would have executed it blindly

# or chain it - ask the LLM to generate the diagnostic script, then run it
echo "write a bash script that collects: pod resource usage, recent OOMKills,
go pprof top allocators, and goroutine count. output as markdown sections." \
| cogcog > diagnose.sh
chmod +x diagnose.sh
./diagnose.sh | cogcog "analyze this diagnostic output"
```

The LLM that "writes tools dynamically" is just generating shell commands. You don't need a framework for that — you need `echo "write me a script" | cogcog > script.sh`. The difference is you read the script before running it.

Want a web search tool? Ask cogcog to write you one.

```bash
echo "write a bash script called websearch that takes a query as argument,
hits the DuckDuckGo HTML API, extracts top 5 result URLs and snippets,
outputs clean text to stdout" | cogcog > ~/bin/websearch
chmod +x ~/bin/websearch

# now you have a web search tool. forever. zero dependencies.
websearch "kubernetes memory limits best practice" | cogcog "summarize"
```

Want RAG? It's an HTTP call.

```bash
# your vector DB already has an API
curl -s http://localhost:6333/collections/docs/points/search \
  -d '{"vector": [...], "limit": 5}' \
| jq '.result[].payload.text' \
| cogcog "answer based on these docs: what's our retry policy?"

# or just grep your own docs — sometimes that's all the RAG you need
grep -rn "retry" docs/ | cogcog "summarize our retry strategy"
```

Every "feature" of a coding agent is a shell script you can write in 5 minutes — and then you own it, you can read it, and it works when the API is down.

### You don't even need cogcog

Any `stdin → stdout` LLM CLI works the same way. The workflow is the point, not the tool.

```bash
# claude code
git diff --staged | claude -p "review this diff"
kubectl get events -n prod | claude -p "anything alarming?"
cat src/main.ts | claude -p "find bugs"

# opencode
terraform plan -no-color | opencode run "any destructive changes?"
cat docker-compose.yml | opencode run "security issues?"

# pi
git log --oneline -20 | pi -p "summarize recent changes"

# they all work in vim too
:%!claude -p "refactor this"
:'<,'>!opencode run "explain"
```

The pattern is always the same: `your context | any-llm "your question"`. Cogcog is just a thin wrapper around the Anthropic API. If you already have a CLI that reads stdin and writes stdout, use that. The workflow is what matters.

## Structure

```
bin/cogcog       # shell script: stdin -> LLM -> stdout
lua/cogcog.lua   # two keymaps for async send
README.md
```
