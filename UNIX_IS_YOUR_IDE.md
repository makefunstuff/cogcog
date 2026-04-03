# Unix Is Your IDE

No frameworks. No SDKs. No MCP servers. Just the tools you already have.

## Why

The LLM is just another Unix filter. It reads text, processes it, writes text. Like `grep`, `sort`, `jq`, `awk` — except it understands natural language.

MCP is a protocol for doing what `|` already does. Tool calling is what `command | llm` already does. RAG is what `grep -rn` already does. Agent memory is what a markdown file already does.

The industry builds complex systems to replicate what Unix gives you for free. The LLM is the new thing. The rest has been solved since the 1970s.

## The cost of abstractions

Every layer between you and the answer adds latency, tokens, money, opacity, and fragility. The Unix approach has a pipe (zero latency), the text you chose (minimal tokens), your judgment (free), full visibility, and no dependencies.

An agent burns 15000 tokens reading 10 files, 80% irrelevant. You `grep -rn "authenticate" src/` and send 50 relevant lines. Better answer, 30x cheaper.

## Practical examples

Every example below works today, on any machine with a shell and an LLM CLI. Replace `llm` with whatever you use — `cogcog`, `claude -p`, `opencode run`, `ollama run`, or a `curl` one-liner.

## File operations

### Read a file
```bash
# agent framework
agent.tools.read_file("src/auth.ts")

# unix
cat src/auth.ts
```

### Read specific lines
```bash
# agent: read_file("src/auth.ts", start=40, end=60)
sed -n '40,60p' src/auth.ts
```

### Find where a function is defined
```bash
# agent: 5 tool calls, reads 3 files, concludes after 30 seconds
# unix:
grep -rn "function handleAuth" src/
```
0.01 seconds. Shows file, line number, content.

### Find all files matching a pattern
```bash
# agent: list_directory recursively, filter results
# unix:
find src/ -name "*.test.ts"
```

### Read only what matters from a large file
```bash
# agent reads the whole file (2000 tokens). you read 5 lines:
grep -n "TODO\|FIXME\|HACK" src/scheduler.ts
```

## Search

### Text search across a project
```bash
grep -rn "authenticate" src/ --include="*.ts"
```

### Semantic search (when regex isn't enough)
```bash
grep -rn "check.*permission\|verify.*access\|auth.*gate" src/
```

Still regex. Still instant. Covers 95% of "semantic" searches.

### Find dead code
```bash
# find all exported functions
grep -rn "^export function" src/ | awk -F: '{print $3}' | sed 's/export function //' | sed 's/(.*//' > /tmp/exports

# check which ones are never imported
while read fn; do
    count=$(grep -rn "$fn" src/ --include="*.ts" | grep -v "export function" | wc -l)
    [[ $count -eq 0 ]] && echo "unused: $fn"
done < /tmp/exports
```

7 lines of bash. An agent would use an expensive "analyze codebase" tool call.

### Find all API endpoints
```bash
grep -rn "app\.\(get\|post\|put\|delete\|patch\)" src/routes/
```

### Find all SQL queries
```bash
grep -rn "SELECT\|INSERT\|UPDATE\|DELETE\|CREATE" src/ --include="*.ts"
```

## Code review

### Review staged changes
```bash
git diff --staged | llm "review for bugs, security issues, and performance problems"
```

### Review a specific file's recent changes
```bash
git log -p --since="1 week" -- src/auth.ts | llm "any risky changes?"
```

### Review a pull request
```bash
gh pr diff 42 | llm "summarize changes, flag risks"
```

### Review only the security-relevant parts
```bash
gh pr diff 42 -- src/auth/ src/middleware/ | llm "security review"
```

### Compare two branches
```bash
git diff main..feature/auth | llm "is this ready to merge?"
```

## Testing

### Explain test failures
```bash
npm test 2>&1 | tail -30 | llm "why is this failing?"
```

### Generate a test from implementation
```bash
cat src/parser.ts | llm "write unit tests for this. use vitest."
```

### Find untested code paths
```bash
# run coverage, extract uncovered lines
npx c8 report --reporter=text 2>&1 | grep "Uncovered" | llm "which of these are most risky to leave untested?"
```

### Test a regex
```bash
echo 'test123
hello world
foo_bar_baz
123-456-7890' | grep -P '^\d{3}-\d{3}-\d{4}$'
```

No LLM needed. But if you can't figure out the regex:

```bash
echo "I need a regex that matches US phone numbers with dashes" | llm
```

## Debugging

### Explain an error
```bash
# copy error from terminal, pipe it
echo "TypeError: Cannot read properties of undefined (reading 'map')" | llm "explain and suggest fix"
```

### Analyze logs
```bash
journalctl -u myservice --since "1 hour ago" | grep -i error | llm "what's the root cause?"
```

### Kubernetes debugging
```bash
{
    echo "## pods"
    kubectl get pods -n prod
    echo "## events"  
    kubectl get events -n prod --sort-by='.lastTimestamp' | tail -20
    echo "## recent errors"
    kubectl logs deploy/api --since=10m 2>&1 | grep -i error | tail -30
} | llm "on-call summary: what needs attention?"
```

### Memory leak investigation
```bash
{
    echo "## pod stats"
    kubectl top pods -n prod --containers
    echo "## OOM events"
    kubectl get events -n prod | grep OOM
    echo "## restarts"
    kubectl get pods -n prod -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.containerStatuses[0].restartCount}{"\n"}{end}'
} | llm "is there a memory leak? which service?"
```

### Docker debugging
```bash
docker logs myapp --since 5m 2>&1 | tail -50 | llm "what's wrong?"
docker stats --no-stream | llm "any containers using too much memory?"
docker inspect myapp | llm "any misconfigurations?"
```

## Infrastructure

### Terraform review
```bash
terraform plan -no-color 2>&1 | llm "list every destructive change"
```

### Dockerfile audit
```bash
cat Dockerfile | llm "audit: layer caching, image size, security, running as root"
```

### Nginx config review
```bash
cat /etc/nginx/nginx.conf | llm "any security issues or misconfigurations?"
```

### Systemd unit review
```bash
cat /etc/systemd/system/myapp.service | llm "is this production-ready? any missing restart policies?"
```

### Firewall audit
```bash
iptables -L -n | llm "any rules that are too permissive?"
# or on opnsense:
ssh router "pfctl -sr" | llm "any firewall rules that should be tightened?"
```

## Database

### Explain a query plan
```bash
psql mydb -c "EXPLAIN ANALYZE SELECT * FROM orders WHERE user_id = 42" | llm "is this query efficient?"
```

### Schema review
```bash
pg_dump --schema-only mydb | llm "suggest missing indexes for common query patterns"
```

### Find N+1 queries
```bash
grep -rn "SELECT.*FROM" src/ --include="*.ts" | llm "any of these look like N+1 patterns?"
```

### Migration review
```bash
cat migrations/20260401_add_orders.sql | llm "will this migration lock the table? is it safe for zero-downtime deploy?"
```

## Dependency management

### Audit dependencies
```bash
npm audit --json 2>/dev/null | llm "which vulnerabilities are actually exploitable?"
cat go.sum | llm "any packages with known CVEs?"
```

### Find unused dependencies
```bash
# list deps
jq -r '.dependencies | keys[]' package.json > /tmp/deps
# check usage
while read dep; do
    count=$(grep -rn "from ['\"]$dep" src/ | wc -l)
    [[ $count -eq 0 ]] && echo "unused: $dep"
done < /tmp/deps
```

Pure bash. No `depcheck` package needed.

### License audit
```bash
cat node_modules/*/package.json | jq -r '.name + " " + (.license // "UNKNOWN")' | sort | llm "any copyleft licenses that would be a problem for a commercial product?"
```

## Documentation

### Generate docs from code
```bash
cat src/api/routes.ts | llm "generate API documentation in markdown"
```

### Generate a changelog
```bash
git log --oneline --since="2 weeks ago" | llm "write a user-facing changelog, group by feature/fix/chore"
```

### Generate commit messages
```bash
git diff --staged | llm "write a commit message. conventional commits format. just the message, nothing else."
```

### Explain a codebase to a new team member
```bash
{
    echo "## structure"
    tree -L 2 --noreport -I node_modules
    echo "## package.json scripts"
    jq '.scripts' package.json
    echo "## README"
    head -50 README.md
} | llm "explain this project to a new developer joining the team"
```

## Data processing

### CSV analysis
```bash
cat sales.csv | llm "find patterns, anomalies, and trends"
```

### JSON transformation
```bash
curl -s https://api.example.com/users | jq '.[] | {name, email}' | llm "any duplicate emails?"
```

### Log analysis
```bash
cat access.log | awk '{print $1}' | sort | uniq -c | sort -rn | head -20 | llm "any suspicious IP patterns?"
```

### API response debugging
```bash
curl -sv https://api.example.com/health 2>&1 | llm "explain the HTTP exchange, any issues?"
```

## Monitoring

### Health check
```bash
{
    echo "## disk"
    df -h
    echo "## memory"
    free -h
    echo "## load"
    uptime
    echo "## top processes"
    ps aux --sort=-%mem | head -10
} | llm "anything concerning?"
```

### SSL certificate check
```bash
echo | openssl s_client -connect example.com:443 2>/dev/null | openssl x509 -text | llm "when does this cert expire? any issues?"
```

### DNS debugging
```bash
dig example.com ANY | llm "explain these DNS records, anything misconfigured?"
```

## Composition patterns

### The investigator — progressive depth
```bash
# 1. surface scan
grep -rn "error\|panic\|fatal" src/ | llm "any patterns?"

# 2. deep dive on what it found
cat src/auth/token.ts | llm "the error pattern analysis found issues here. what's wrong?"

# 3. generate fix
cat src/auth/token.ts | llm "fix the token refresh race condition, output only the code"
```

### The auditor — multi-dimensional review
```bash
# security
cat src/auth/*.ts | llm "security audit" > /tmp/security.md

# performance
cat src/db/*.ts | llm "find slow queries and missing indexes" > /tmp/perf.md

# reliability
cat src/middleware/*.ts | llm "what happens when downstream services are down?" > /tmp/reliability.md

# read all three
cat /tmp/security.md /tmp/perf.md /tmp/reliability.md | llm "prioritize: what should we fix first?"
```

### The translator — cross-language migration
```bash
# function by function
for f in src/*.py; do
    echo "=== $f ===" 
    cat "$f" | llm "rewrite in Go, idiomatic style"
done > go_migration.md
```

### The monitor — continuous checking
```bash
# check every 5 minutes
watch -n 300 'kubectl get pods -n prod | llm "any pods crashing or pending?"'
```

### The diff explainer — understand what changed
```bash
# what changed today
git diff HEAD~5 | llm "summarize what changed and why it might break something"

# what changed in a dependency update
diff <(git show HEAD~1:package-lock.json | jq '.packages | keys[]' | sort) \
     <(jq '.packages | keys[]' package-lock.json | sort) | llm "what dependencies changed?"
```

## The pattern

Every example above follows the same pattern:

```
command that produces text | llm "question about that text"
```

That's it. The command can be `cat`, `grep`, `git`, `kubectl`, `psql`, `curl`, `docker`, `terraform`, `openssl`, `dig`, `ps`, `df`, or any of the thousands of CLIs that produce text output.

The LLM is the last filter in the pipeline. Everything before it is standard Unix. Everything after it is text you can pipe somewhere else.

No server. No framework. No protocol. No SDK. No API key management library. No agent orchestration. No vector database. No embedding pipeline.

Just `|`.

## The buzzword translation table

| Buzzword | Unix equivalent |
|----------|----------------|
| MCP | `curl`, `grep`, `psql`, any CLI |
| Tool calling | `command \| llm` |
| RAG | `grep -rn` |
| Agent memory | A markdown file |
| Sub-agents | tmux panes |
| Context window management | Reading the code yourself and sending what matters |
| Agentic loop | A while loop (or you closing the loop manually) |
| Orchestration | A bash script |
| Structured output | `llm \| jq` |
| Prompt engineering | Writing clearly |
| Fine-tuning | A system prompt file |
