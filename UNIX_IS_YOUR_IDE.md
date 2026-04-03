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

You store documents as embeddings (vectors). To search, convert your question to an embedding, find similar documents, feed them to the LLM.

### Qdrant

```bash
# 1. embed your question (using a local embedding model via Ollama)
VECTOR=$(curl -s http://localhost:11434/api/embeddings \
  -d '{"model":"nomic-embed-text","prompt":"how do we handle auth?"}' \
  | jq '.embedding')

# 2. search Qdrant for similar documents
DOCS=$(curl -s http://localhost:6333/collections/docs/points/search \
  -H "Content-Type: application/json" \
  -d "{\"vector\": $VECTOR, \"limit\": 5}" \
  | jq -r '.result[].payload.text')

# 3. ask the LLM using the retrieved docs as context
echo "$DOCS" | llm "based on these documents: how do we handle auth?"
```

### pgvector (PostgreSQL)

```bash
# same idea: embed → search → ask
VECTOR=$(curl -s http://localhost:11434/api/embeddings \
  -d '{"model":"nomic-embed-text","prompt":"deployment process"}' \
  | jq -c '.embedding')

psql mydb -c "
  SELECT content FROM documents
  ORDER BY embedding <=> '$VECTOR'
  LIMIT 5
" | llm "summarize our deployment process"
```

### One-liner with pipes

```bash
# embed + search + answer in one pipeline
curl -s http://localhost:11434/api/embeddings \
  -d '{"model":"nomic-embed-text","prompt":"retry policy"}' \
| jq -c '{vector: .embedding, limit: 5}' \
| curl -s http://localhost:6333/collections/docs/points/search \
    -H "Content-Type: application/json" -d @- \
| jq -r '.result[].payload.text' \
| llm "what's our retry policy?"
```

### Obsidian vault as knowledge base

Your notes are already on disk. No vector DB needed for most questions:

```bash
# search across all notes
grep -rn "kubernetes" ~/vault/ --include="*.md" | llm "summarize what I know about kubernetes"

# find notes about a topic and ask about them
find ~/vault/ -name "*.md" -exec grep -l "auth" {} \; \
| xargs cat \
| llm "based on my notes, what's my preferred auth approach?"

# daily notes as context
cat ~/vault/daily/2026-04-*.md | llm "summarize what I worked on this month"

# search by tag
grep -rl "#project/cogcog" ~/vault/ | xargs cat | llm "status update on cogcog"
```

For large vaults (10k+ notes), index into Qdrant:

```bash
# index all notes (one-time)
for f in ~/vault/**/*.md; do
  TEXT=$(cat "$f")
  VECTOR=$(curl -s http://localhost:11434/api/embeddings \
    -d "{\"model\":\"nomic-embed-text\",\"prompt\":$(jq -Rs . <<< "$TEXT")}" \
    | jq '.embedding')
  curl -s http://localhost:6333/collections/vault/points \
    -H "Content-Type: application/json" \
    -d "{\"points\":[{\"id\":$(md5sum <<< "$f" | cut -c1-8 | xargs printf '%d' 0x),\"vector\":$VECTOR,\"payload\":{\"file\":\"$f\",\"text\":$(jq -Rs . <<< "$TEXT")}}]}"
done

# then search semantically
curl -s http://localhost:11434/api/embeddings \
  -d '{"model":"nomic-embed-text","prompt":"what do I know about rate limiting?"}' \
| jq -c '{vector: .embedding, limit: 5}' \
| curl -s http://localhost:6333/collections/vault/points/search \
    -H "Content-Type: application/json" -d @- \
| jq -r '.result[].payload.text' \
| llm "based on my notes, what do I know about rate limiting?"
```

### Working in your vault with LLMs

Open your vault in Neovim. All cogcog verbs work on markdown:

```
" open a note
:e ~/vault/projects/cogcog.md

" explain something you wrote months ago
gaip                                "what was I thinking here?"

" expand a bullet into a paragraph
gsip → "expand this into a full explanation"

" refactor messy notes
<leader>grip → "clean up, keep the information, improve structure"

" generate a note from scratch
gss → "write a note about kubernetes networking based on what I've learned"
```

Link discovery across notes:

```
" find all notes that reference the current topic
:read !grep -rl "rate limiting" ~/vault/ --include="*.md"
gaip → "which of these notes are related and how?"
```

Morning review:

```bash
cat ~/vault/daily/$(date +%Y-%m-%d).md ~/vault/todo.md | llm "what should I focus on today?"
```

Weekly summary:

```bash
cat ~/vault/daily/2026-04-{01..07}.md 2>/dev/null | llm "summarize my week"
```

Generate links between notes:

```bash
# find notes that SHOULD link to each other but don't
find ~/vault/ -name "*.md" -exec grep -l "auth" {} \; \
| xargs head -5 \
| llm "which of these notes should reference each other? suggest [[wikilinks]]"
```

Extract actionable items:

```bash
cat ~/vault/meetings/2026-04-04.md | llm "extract action items as a checklist"
```

### Research workflow

Start with a question, build a note iteratively:

```bash
# 1. search the web
pi-tavily "eBPF vs iptables performance 2026" > /tmp/research.md

# 2. get an AI summary with citations
pi-ask "compare eBPF and iptables for packet filtering, with benchmarks" >> /tmp/research.md

# 3. open in vim, start refining
nvim /tmp/research.md
```

In Neovim:

```
" read more sources
:read !pi-tavily "eBPF XDP benchmarks real world"
:read !pi-ask "what are the downsides of eBPF?"

" ask about what you've gathered
gaip → "are these sources contradicting each other?"

" synthesize into a note
gss → "synthesize all of this into a structured note with sections"
:w ~/vault/research/ebpf-vs-iptables.md
```

Cross-reference with your existing knowledge:

```
:read !grep -rl "eBPF\|iptables\|firewall" ~/vault/ --include="*.md"
gaip → "what have I already written about this topic?"
```

Deep dive on a specific claim:

```
" select a claim in the research note
Visual ga → "find evidence for or against this. search the web if needed."
```

Build a literature review:

```bash
# collect multiple sources
for q in "eBPF performance" "XDP benchmarks" "eBPF security concerns"; do
    echo "## $q"
    pi-tavily "$q" 2>/dev/null | head -20
    echo ""
done > /tmp/literature.md

# synthesize
cat /tmp/literature.md | llm "write a literature review. cite sources. identify gaps."
```

Progressive refinement loop:

```
" draft
gss → "write a technical overview of eBPF for networking"

" critique your own draft
<leader>gcaf → opus reviews for accuracy

" refine based on critique
<leader>grip → "address the issues found in the review"

" save
:w ~/vault/research/ebpf-overview.md
```

### Or just grep your docs

```bash
grep -rn "retry" docs/ | llm "summarize our retry strategy"
```

RAG is for millions of documents. For a codebase or a personal vault, grep is faster and doesn't hallucinate.

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

## Incident response

Alert fires. Gather context from everywhere, diagnose:

```bash
{
    echo "## alert"
    curl -s http://grafana:3000/api/alerts | jq '.[] | select(.state=="alerting")'
    echo "## recent deploys"
    git log --oneline --since="2 hours ago"
    echo "## error logs"
    kubectl logs deploy/api --since=30m 2>&1 | grep -i "error\|panic\|fatal" | tail -30
    echo "## resource usage"
    kubectl top pods -n prod
} | llm "diagnose: what's causing the alert? what should I do first?"
```

After fixing, generate the post-mortem:

```bash
{
    echo "## timeline"
    kubectl get events -n prod --sort-by='.lastTimestamp' | tail -30
    echo "## fix"
    git log --oneline -3
    git diff HEAD~1
} | llm "write an incident post-mortem. timeline, root cause, fix, prevention."
```

## Automated standup

```bash
{
    echo "## yesterday"
    git log --author="$(git config user.name)" --oneline --since="yesterday"
    echo "## in progress"
    git branch --list | grep -v main
    echo "## blocked"
    grep -rn "TODO\|FIXME\|BLOCKED" src/ --include="*.go" | tail -10
} | llm "write a standup update: done, doing, blocked. 3 bullet points max."
```

## Architecture decision records

After a planning conversation in cogcog:

```vim
<leader>co
:w /tmp/discussion.md
```

```bash
cat /tmp/discussion.md | llm "extract an ADR from this discussion:
title, status (accepted), context, decision, consequences.
use the standard ADR format." > docs/adr/0042-rate-limiting.md
```

## Learning pipeline

Read docs, generate notes, quiz yourself:

```bash
# compress a long doc into your vault format
curl -s https://go.dev/doc/effective_go | llm "compress into concise notes with code examples" \
  > ~/vault/learning/effective-go.md

# generate flashcards
cat ~/vault/learning/effective-go.md \
  | llm "generate 10 flashcards as Q: / A: pairs" \
  > ~/vault/flashcards/go.md

# quiz yourself
cat ~/vault/flashcards/go.md | llm "pick 3 random questions, ask me one at a time"
```

In Neovim — read unfamiliar code as a learning exercise:

```
gaf → (explains the function)
3gaf → (detailed explanation with examples)
Visual ga → "what design pattern is this?"
Visual ga → "how would I write this differently in Rust?"
```

## Security audit pipeline

Systematically scan a codebase:

```bash
# find attack surface
grep -rn "http.Handle\|gin.GET\|app.post\|router\." src/ \
  | llm "list all API endpoints and their input parameters"

# check each for vulnerabilities
for file in src/routes/*.ts; do
    echo "=== $file ==="
    cat "$file" | llm "audit for: injection, auth bypass, SSRF, path traversal. be specific."
done > /tmp/security-audit.md

# prioritize
cat /tmp/security-audit.md | llm "rank findings by severity. top 3 to fix immediately."
```

In Neovim:

```
<leader>gcaf     opus reviews function for security
Visual ga → "can this input be exploited?"
```

## Cross-repo comparison

How do two projects solve the same problem?

```bash
{
    echo "## project A: auth"
    cat ~/Work/project-a/src/auth/*.ts
    echo "## project B: auth"
    cat ~/Work/project-b/src/auth/*.go
} | llm "compare these two auth implementations. which is more secure? which handles edge cases better?"
```

## Reverse engineering APIs

Capture traffic, understand the protocol:

```bash
# capture API calls
curl -sv https://api.example.com/users 2>&1 | llm "explain this HTTP exchange"

# compare two API versions
diff <(curl -s https://api.example.com/v1/users | jq 'keys') \
     <(curl -s https://api.example.com/v2/users | jq 'keys') \
| llm "what changed between v1 and v2? any breaking changes?"

# generate a client from observed responses
curl -s https://api.example.com/users | llm "generate a Go HTTP client struct and methods for this API"
```

## Config drift detection

Compare running state vs what's committed:

```bash
# kubernetes
diff <(kubectl get deploy api -o yaml) <(cat k8s/api-deployment.yaml) \
  | llm "what drifted? is the running config dangerous?"

# terraform
terraform plan -no-color 2>&1 | llm "is this drift intentional or did someone kubectl edit?"

# docker
diff <(docker inspect myapp | jq '.[0].Config') <(cat docker-compose.yml) \
  | llm "what's different between running container and compose file?"
```

## Knowledge distillation

Compress long content into your format:

```bash
# paper → notes
cat paper.pdf | pdftotext - - | llm "compress into: key findings, methodology, limitations. 1 page max." \
  > ~/vault/papers/paper-name.md

# video transcript → notes
yt-dlp --write-sub --skip-download "https://youtube.com/..." -o /tmp/vid
cat /tmp/vid.*.vtt | llm "compress this transcript into structured notes with timestamps" \
  > ~/vault/talks/talk-name.md

# book chapter → summary
cat chapter.txt | llm "summarize in my style: bullet points, code examples, actionable takeaways" \
  > ~/vault/books/book-chapter.md
```

## Personal context across projects

Build a cross-project knowledge graph:

```bash
# what have I been working on?
for dir in ~/Work/*/; do
    echo "## $(basename $dir)"
    git -C "$dir" log --author="$(git config user.name)" --oneline --since="1 month" 2>/dev/null | head -5
done | llm "summarize my work across all projects this month"

# find patterns across codebases
for dir in ~/Work/*/; do
    echo "## $(basename $dir)"
    grep -rn "func.*error" "$dir/src/" 2>/dev/null | head -5
done | llm "how do my different projects handle errors? any inconsistencies?"
```

## Why this works

The LLM is a Unix filter. It reads text, processes it, writes text. Every layer between you and the answer costs latency, tokens, money, opacity, and fragility.

An agent reads 15 files (15000 tokens, 80% irrelevant). You `grep` the 50 lines that matter. Better context, better answer, 30x cheaper.

Agents are great on day 1 of a new codebase when you don't know where to look. By day 30, `grep | llm` is faster than any agent. Most work happens on day 30.
