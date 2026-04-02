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

**Optional:** Load the Lua plugin for `:Cog*` commands.

```lua
-- lazy.nvim
{ dir = "/path/to/cogcog" }

-- or manually in init.lua
vim.opt.rtp:prepend("/path/to/cogcog")
require("cogcog")
```

## Bash

The script reads stdin, sends it to Claude, writes the response to stdout. That's it.

```bash
echo "explain kubernetes CRDs in 3 sentences" | cogcog
cat src/main.ts src/db.ts | cogcog
```

In vim, everything is native commands:

```vim
" start a scratch buffer
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

## Lua (not)

Adds `:Cog*` commands so you don't retype `:read` paths. Still no auto-discovery, no tool calls, no autonomous anything.

```vim
:Cog                          " open the context buffer (vsplit)
:CogAdd src/main.ts           " append a file with header
:CogAdd src/db.ts
:CogCmd grep -rn 'TODO' src/  " append command output
                               " edit the buffer, trim noise, type your question
:CogSend                      " send to LLM → response in horizontal split

" from any buffer, yank a selection into context:
:'<,'>CogYank

:CogClear                     " wipe and start fresh
```

### Commands

| Command | What it does |
|---------|-------------|
| `:Cog` | Open/focus the context buffer |
| `:CogAdd <file>` | Append file contents with path header |
| `:CogCmd <cmd>` | Append shell command output |
| `:CogYank` | Yank visual selection into context (with source label) |
| `:CogSend` | Send context to LLM, response in new split |
| `:CogClear` | Wipe the context buffer |

## Configuration

```bash
# Change the model (default: claude-sonnet-4-20250514)
export COGCOG_MODEL="claude-haiku-3-20250514"

# Change max tokens (default: 8192)
export COGCOG_MAX_TOKENS=16384

# Lua plugin only: use a different LLM command (any stdin→stdout program works)
export COGCOG_CMD="my-local-llm"
```

## The constraint

No automatic file discovery. No tool calls. No autonomous exploration. The human builds the context. That's not a limitation — that's the product.

## Structure

```
bin/cogcog       # shell script: stdin → LLM → stdout
lua/cogcog.lua   # optional neovim plugin
README.md
```
