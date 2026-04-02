# CogCog

CogCog is not a plugin. It's a workflow. Neovim is already a context engine — buffers, `:read !`, registers, pipes, splits. An LLM is just `stdin → stdout`. CogCog is the thin bridge between the two.

**You build context manually, so you read the code. You choose what matters. The LLM only sees what you curated. Building the context IS the understanding.**

I am not inventing, or pretending it's a revolution, I have a feeling that modern workflows with 'coding agents' 
feels like you trade fake impression of delivery 'speed' to building up enormous amount of hidden debt. And this modern paradigm "i ship code i don't read" will heavily can shoot you in the leg.

I am not rejecting usage of coding agents, I just want to control the context, delegate boring parts, manage the context, avoid tool calling bloat. And maybe (hope so), reduce costs on inference at some point. I don't like that all these tools are actually starting to accumulate a lot of "leaned helplessness", and dependency of inference api uptime, is not what I want to have.

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

# Use a different LLM command entirely (any stdin->stdout program works)
export COGCOG_CMD="my-local-llm"
```

## Structure

```
bin/cogcog       # shell script: stdin -> LLM -> stdout
lua/cogcog.lua   # two keymaps for async send
README.md
```
