# Unix Is Your IDE

You don't need MCP. You don't need tool registries. You don't need agent frameworks. You don't need 47 npm packages to ask an LLM about your code.

The tools already exist. They've existed for decades.

## The LLM is just another filter

Unix has always worked this way: small programs that read stdin, process text, write stdout. `grep` filters lines. `sort` orders them. `jq` reshapes JSON. `awk` transforms columns.

An LLM does the same thing — it reads text and writes text. The only difference is it understands natural language.

```bash
# these are equivalent architectures
cat file | grep pattern | sort | uniq
cat file | cogcog "find the interesting parts" | cogcog "sort by importance"
```

The pipe is the protocol. Always has been.

## MCP is `curl`

MCP (Model Context Protocol) lets an LLM discover and call tools. Here's what that looks like:

```
MCP: agent connects to server → discovers tools → calls read_file(path) → gets result
You: cat src/auth.ts
```

```
MCP: agent connects to server → discovers tools → calls search(query) → gets results
You: grep -rn "handleAuth" src/
```

```
MCP: agent connects to server → discovers tools → calls run_command(cmd) → gets output
You: npm test 2>&1
```

MCP is a protocol for doing what your shell already does. The difference: MCP needs a server, a client, a transport layer, JSON-RPC, capability negotiation, and a dependency tree. Your shell needs nothing.

```bash
# "MCP server" for kubernetes
kubectl get pods -n prod

# "MCP server" for databases  
psql mydb -c "SELECT * FROM users LIMIT 5"

# "MCP server" for monitoring
curl -s http://prometheus:9090/api/v1/query?query=up

# "MCP server" for git
git log --oneline -20
```

Every CLI you have is an MCP server. The transport layer is `|`. The discovery protocol is `man`.

## Tool calling is `|`

Agent frameworks implement tool calling: the LLM decides what tool to run, formats a JSON request, the framework executes it, parses the response, and feeds it back.

```
Agent: LLM thinks → emits tool_call JSON → framework parses → executes → returns result → LLM thinks again
You:   command | cogcog "analyze"
```

The agent's tool call is a round-trip through JSON serialization, an HTTP request, response parsing, and another LLM inference. Your pipe is a file descriptor.

```bash
# agent does this in 5 tool calls over 30 seconds:
# 1. list_files(src/) → 2. read_file(src/auth.ts) → 3. read_file(src/middleware.ts) 
# 4. search("authenticate") → 5. analyze(results)

# you do this in 0.1 seconds:
grep -rn "authenticate" src/ | cogcog --raw "is there a path where auth is bypassed?"
```

Same answer. 300x faster. You read the grep output too, so you learned something.

## Context windows are expensive. Curation is free.

An agent reads your entire codebase into context. 15 files, 20000 tokens, 80% irrelevant. It has no idea what matters. It reads everything and hopes.

You know what matters. You've been staring at this code for three hours. You know the bug is somewhere in the auth middleware. So you give the LLM exactly that:

```bash
grep -n "token\|expire\|refresh" src/auth/*.ts | cogcog --raw "anything wrong with the token refresh logic?"
```

200 tokens. 100% relevant. Better answer because better context.

The agent's context gathering costs money and produces noise. Your context curation costs nothing and produces signal.

## Conversation memory is a file

Agents store conversation history in databases. They maintain "memory" through embeddings, vector stores, retrieval pipelines.

```bash
# save a conversation
:w .cogcog/auth-investigation.md

# resume next week
:read .cogcog/auth-investigation.md
```

Your memory is a markdown file. You can:
- `grep` it
- `git diff` it
- Edit it with vim
- Share it in a PR
- Read it at 3am without an API key

The agent's memory is a black box that requires the API to be up, the embeddings to be working, and the retrieval pipeline to not hallucinate.

## Parallel agents are tmux panes

Agent frameworks implement "sub-agents" and "parallel execution" with complex orchestration:

```
Orchestrator → spawns Agent A (search codebase)
             → spawns Agent B (analyze dependencies)
             → spawns Agent C (check security)
             → collects results → synthesizes
```

```bash
# tmux pane 1
cat src/api/*.ts | cogcog --raw "find N+1 queries"

# tmux pane 2
cat package.json | cogcog --raw "any vulnerable deps?"

# tmux pane 3
git diff HEAD~10 | cogcog --raw "anything risky in recent changes?"
```

Three parallel agents. You read all three results. No orchestrator, no synthesis step that hides details.

## RAG is grep

Retrieval-Augmented Generation: embed your documents, store in a vector database, query with cosine similarity, retrieve top-k chunks, inject into prompt.

Or:

```bash
grep -rn "retry" docs/ | cogcog --raw "summarize our retry strategy"
```

RAG is for when you have millions of documents and can't grep. For a codebase — which is exactly what coding agents work on — grep is faster, more precise, and doesn't hallucinate retrieval results.

## The real cost of abstractions

Every abstraction between you and the answer is:
- Latency (MCP handshake, tool call round-trip, JSON parsing)
- Tokens (tool call overhead, system prompts for tool descriptions)
- Money (every token costs)
- Opacity (you can't see what the agent sent to the LLM)
- Fragility (server down, API changed, rate limited, context window exceeded)

The Unix approach has:
- A pipe (zero latency)
- The text you chose (minimal tokens)
- Your judgment (free)
- Full visibility (it's right there in your terminal)
- No dependencies (works offline, works on any machine, works forever)

## "But agents are faster for complex tasks"

Are they?

An agent takes 2 minutes to:
1. Read 15 files (30 seconds)
2. Make 8 tool calls (60 seconds)  
3. Generate a plan (15 seconds)
4. Write code you need to review anyway (15 seconds)

You take 3 minutes to:
1. `grep` to find the relevant code (2 seconds)
2. Read it yourself (60 seconds)
3. Ask the LLM about the tricky part (10 seconds)
4. Write the code with `gs` (30 seconds)
5. Verify with `<leader>gc` (30 seconds)
6. Run tests (10 seconds)

The agent was 1 minute faster. But you understood every step. You can explain the change in a PR review. You can debug it at 3am. You can modify it next week without asking the agent "what did you do?"

The agent's speed is borrowed from your future self. You'll pay it back with interest the first time something breaks and you don't understand why.

## "But I need tool calling for X"

You probably don't. But if you do:

```bash
# this is tool calling
echo "read src/auth.ts and tell me if it's thread-safe" | opencode run -m kimi-k2.5
```

opencode has tools. claude has tools. pi has tools. They read files, run commands, browse the web. Set one as `COGCOG_CMD` and `gs` becomes agentic.

The point isn't that tool calling is bad. The point is that you don't need a framework to do it, and you should reach for it deliberately — not as the default for every interaction.

Quick question about code you're looking at? `ga`. Direct API, 0.3 seconds, zero overhead.

Need the LLM to read files and iterate? `gs`. Agentic backend, tool calls, the works.

Choose the right tool for the task. Not the most powerful tool for every task.

## What you actually need

1. A way to send text to an LLM: `curl` or any CLI
2. A way to stream the response: SSE parsing (30 lines of bash)
3. A way to choose what to send: your brain + `grep` + `:read`
4. A way to use the response: `|`, registers, yanking, `:w`

That's cogcog. A thin bridge between vim and any LLM. Everything else is vim being vim and unix being unix.

## The buzzword translation table

| Buzzword | Unix equivalent |
|----------|----------------|
| MCP | `curl`, `grep`, `psql`, any CLI |
| Tool calling | `command \| cogcog` |
| RAG | `grep -rn` |
| Agent memory | A markdown file |
| Sub-agents | tmux panes |
| Context window management | Reading the code yourself and sending what matters |
| Agentic loop | A while loop (or the Ralph loop with your hands on the wheel) |
| Orchestration | A bash script |
| Multi-modal input | `base64 image.png \| cogcog` |
| Structured output | `cogcog \| jq` |
| Prompt engineering | Writing clearly |
| Fine-tuning | `.cogcog/system.md` |

The industry builds complex systems to replicate what Unix gives you for free. The LLM is the new thing. The rest has been solved since the 1970s.
