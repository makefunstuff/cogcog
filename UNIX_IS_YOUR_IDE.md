# Unix Is Your IDE

Every example works today. Replace `llm` with `cogcog --raw`, `claude -p`, `pi -p`, or any stdin→stdout CLI.

```
command that produces text | llm "question about that text"
```

## File operations

```bash
cat src/auth.ts                                     # read file
sed -n '40,60p' src/auth.ts                         # read specific lines
grep -rn "function handleAuth" src/                 # find definition (0.01s)
find src/ -name "*.test.ts"                         # find files
grep -n "TODO\|FIXME\|HACK" src/scheduler.ts       # find annotations
```

## Code review

```bash
git diff --staged | llm "review for bugs, security, performance"
git diff main..feature | llm "is this ready to merge?"
gh pr diff 42 | llm "summarize changes, flag risks"
gh pr diff 42 -- src/auth/ | llm "security review"
```

## Testing & debugging

```bash
npm test 2>&1 | tail -30 | llm "why is this failing?"
cat src/parser.ts | llm "write unit tests for this"
```

## Log analysis

```bash
journalctl -u myservice --since "1 hour ago" | grep -i error | llm "root cause?"
kubectl logs deploy/api --since=5m | grep -v healthcheck | tail -50 | llm "what's failing?"
docker logs myapp --since 5m 2>&1 | tail -50 | llm "what's wrong?"
```

## Infrastructure

```bash
terraform plan -no-color 2>&1 | llm "list destructive changes"
cat Dockerfile | llm "audit: layer caching, image size, security"
cat /etc/nginx/nginx.conf | llm "any misconfigurations?"
iptables -L -n | llm "any rules too permissive?"
```

## Kubernetes

```bash
{
    echo "## pods"
    kubectl get pods -n prod
    echo "## events"
    kubectl get events -n prod --sort-by='.lastTimestamp' | tail -20
    echo "## errors"
    kubectl logs deploy/api --since=10m 2>&1 | grep -i error | tail -30
} | llm "on-call summary: what needs attention?"
```

## Database

```bash
psql mydb -c "EXPLAIN ANALYZE SELECT * FROM orders WHERE user_id = 42" | llm "is this efficient?"
pg_dump --schema-only mydb | llm "suggest missing indexes"
```

## RAG with self-hosted vector databases

### Qdrant

```bash
# search your knowledge base
curl -s http://localhost:6333/collections/docs/points/search \
  -H "Content-Type: application/json" \
  -d '{"vector": [0.1, 0.2, ...], "limit": 5}' \
| jq '.result[].payload.text' \
| llm "answer based on these documents: what's our retry policy?"
```

### pgvector (PostgreSQL)

```bash
psql mydb -c "
  SELECT content, 1 - (embedding <=> '[0.1, 0.2, ...]') AS similarity
  FROM documents
  ORDER BY embedding <=> '[0.1, 0.2, ...]'
  LIMIT 5
" | llm "based on these results, summarize our deployment process"
```

### Embeddings pipeline

```bash
# generate embedding for a query
echo "how do we handle auth?" \
| llm "output ONLY a JSON array of 384 floats representing this text as an embedding" \
| curl -s http://localhost:6333/collections/docs/points/search \
    -H "Content-Type: application/json" \
    -d @- \
| jq '.result[].payload.text' \
| llm "answer the question based on these documents"
```

### Or just grep your docs

```bash
grep -rn "retry" docs/ | llm "summarize our retry strategy"
```

RAG is for millions of documents. For a codebase, grep is faster and doesn't hallucinate.

## Web search

### Tavily

```bash
pi-tavily "kubernetes memory limits best practices" | llm "summarize the key recommendations"
```

### Perplexity

```bash
pi-ask "what changed in Go 1.24 error handling?"
```

### SearXNG (self-hosted)

```bash
curl -s "http://localhost:8888/search?q=golang+mutex+patterns&format=json" \
| jq '.results[:5] | .[].content' \
| llm "summarize these search results"
```

### DuckDuckGo

```bash
curl -s "https://api.duckduckgo.com/?q=epoll+vs+io_uring&format=json" \
| jq '.AbstractText' \
| llm "explain the tradeoffs"
```

## Dependency audit

```bash
npm audit --json 2>/dev/null | llm "which vulnerabilities are actually exploitable?"
cat go.sum | llm "any packages with known CVEs?"
```

## Documentation

```bash
git log --oneline --since="2 weeks ago" | llm "write a user-facing changelog"
git diff --staged | llm "write a commit message. conventional commits. just the message."
cat src/api/routes.ts | llm "generate API docs in markdown"
```

## Data processing

```bash
cat sales.csv | llm "find patterns and anomalies"
curl -s https://api.example.com/users | jq '.[] | {name, email}' | llm "any duplicates?"
cat access.log | awk '{print $1}' | sort | uniq -c | sort -rn | head -20 | llm "suspicious IPs?"
```

## Monitoring

```bash
{
    echo "## disk"; df -h
    echo "## memory"; free -h
    echo "## load"; uptime
    echo "## top processes"; ps aux --sort=-%mem | head -10
} | llm "anything concerning?"

echo | openssl s_client -connect example.com:443 2>/dev/null \
| openssl x509 -text | llm "when does this cert expire?"
```

## Composition patterns

### Progressive investigation

```bash
# surface scan
grep -rn "error\|panic\|fatal" src/ | llm "any patterns?"

# deep dive
cat src/auth/token.ts | llm "the scan found issues here. what's wrong?"

# fix
cat src/auth/token.ts | llm "fix the token refresh race condition"
```

### Multi-dimensional audit

```bash
cat src/auth/*.ts | llm "security audit" > /tmp/security.md
cat src/db/*.ts | llm "find slow queries" > /tmp/perf.md
cat /tmp/security.md /tmp/perf.md | llm "prioritize: what first?"
```

### Parallel agents (tmux)

```bash
# pane 1
cat src/api/*.ts | llm "find N+1 queries"

# pane 2
cat src/middleware/*.ts | llm "audit auth for bypasses"

# pane 3
git log --oneline --since=7d | llm "what shipped this week?"
```

### Continuous monitoring

```bash
watch -n 300 'kubectl get pods -n prod | llm "any pods crashing?"'
```

### Git hooks

```bash
# .git/hooks/pre-commit
#!/bin/bash
issues=$(git diff --staged | cogcog --raw "ONLY list critical bugs, one per line. say NONE if clean")
if [[ "$issues" != *"NONE"* ]]; then
    echo "$issues"
    read -rp "commit anyway? (y/n) " answer
    [[ "$answer" == "y" ]] || exit 1
fi
```

## The buzzword translation table

| Buzzword | Unix |
|----------|------|
| MCP | `curl`, `grep`, `psql`, any CLI |
| Tool calling | `command \| llm` |
| RAG | `grep -rn` or Qdrant/pgvector + `curl` + `jq` |
| Vector search | `curl http://qdrant:6333/... \| jq \| llm` |
| Web search | `pi-tavily`, `pi-ask`, `curl searxng` |
| Agent memory | a markdown file |
| Sub-agents | tmux panes |
| Context window | reading the code yourself and sending what matters |
| Agentic loop | a while loop |
| Orchestration | a bash script |
| Structured output | `llm \| jq` |
| Prompt engineering | writing clearly |
| Fine-tuning | `.cogcog/system.md` |

## Why this works

The LLM is a Unix filter. It reads text, processes it, writes text. Every layer between you and the answer costs latency, tokens, money, opacity, and fragility.

An agent reads 15 files (15000 tokens, 80% irrelevant). You `grep` the 50 lines that matter. Better context, better answer, 30x cheaper.

Agents are great on day 1 of a new codebase when you don't know where to look. By day 30, `grep | llm` is faster than any agent. Most work happens on day 30.
