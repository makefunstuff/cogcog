# Tutorial: First hour with cogcog

## Setup (2 minutes)

```bash
# minimal: just an API key
export ANTHROPIC_API_KEY="sk-ant-..."

# put cogcog on PATH
cp bin/cogcog ~/.local/bin/
chmod +x ~/.local/bin/cogcog

# test it
echo "hello" | cogcog
```

Add to your Neovim config (lazy.nvim):

```lua
{ dir = "/path/to/cogcog" }
```

Restart Neovim. All verbs work.

## Open a project

```bash
cd ~/Work/some-project
nvim
```

### 1. Map the project

```
<leader>cd
```

Wait 30-60 seconds. The LLM reads your project and writes a domain-organized reference to `.cogcog/discovery.md`. You see it streaming in.

When done, you have something like:

```markdown
## Domains

### Auth
- `src/auth/middleware.ts` — JWT validation, token refresh
- `src/auth/oauth.ts` — OAuth2 PKCE flow

### Database
- `src/db/pool.ts` — connection pooling
- `src/db/migrations/` — knex migrations
```

Put your cursor on any path. Press `gf`. You're in that file.

### 2. Understand code

You're in `src/auth/middleware.ts`. You see a function you don't understand:

```
gaf → "what does this do?"
```

A split opens on the right with the explanation. Read it. Press `q` to close.

Try another:

```
gaip → "why is this checking the expiry twice?"
```

These are stateless — each question is independent. Quick and disposable.

### 3. Go deeper with a conversation

Open the context panel:

```
<leader>co
```

Now `ga` becomes stateful — answers accumulate:

```
gaf → "how does token refresh work?"
gaf → "what happens if the refresh token is expired?"
gaf → "could this deadlock under high concurrency?"
```

Each answer builds on the previous. The panel shows the full conversation.

Close the panel to go back to stateless mode:

```
<leader>co
```

### 4. Pin code from multiple files

You want to ask about how two files interact. Navigate to file A:

```vim
" select the relevant function
visual <leader>cy
```

Navigate to file B:

```vim
" select another function
visual <leader>cy
```

Both are now in the context panel. Ask about them together:

```
<C-g> → "can these functions race? what if both are called simultaneously?"
```

The LLM sees both pinned selections and your question.

### 5. Plan a feature

```
<C-g> → "I need to add rate limiting to the API. What's the approach?"
```

The agent reads your codebase (it has tool access) and suggests an approach. Follow up:

```
<C-g> → "use token bucket, not sliding window"
<C-g> → "where exactly should the middleware go?"
```

The conversation accumulates in the context panel.

### 6. Generate code

From the planning conversation, generate the implementation:

```
gsaf → "implement the rate limiting middleware based on our discussion"
```

A code buffer opens below with the generated code. It has line numbers and the right filetype.

Save it:

```vim
:w src/middleware/ratelimit.ts
```

### 7. Verify the code

Select the generated code and check it with the strongest model:

```
<leader>gcaf
```

A review appears in a side split. Read the feedback. Press `q` to close.

### 8. Test and iterate

Run your tests:

```vim
:make
```

If tests fail, errors land in quickfix. Ask about them:

```
gaip → "why is this failing?"
```

Quickfix entries are auto-included — the LLM sees both your code and the errors.

Fix it:

```
gsaf → "fix the test failures"
```

Save, test again. Repeat until green.

### 9. Review before committing

From the shell:

```bash
git diff --staged | cogcog --raw "review for bugs, security issues"
```

Or from vim:

```vim
:read !git diff --staged
gaip → "anything wrong with these changes?"
```

### 10. Save your session

The context panel auto-saves when you quit. Next time you open this project, `<leader>co` restores the conversation.

Save a named session for later:

```vim
<leader>co
:w .cogcog/rate-limiting-session.md
```

Resume next week:

```vim
<leader>co
:read .cogcog/rate-limiting-session.md
<C-g> → "continuing from where we left off"
```

## Improve over time

When a response is bad:

```
<leader>cp → "it gave generic advice instead of analyzing my actual code"
```

This generates an instruction and appends it to `.cogcog/system.md`. Your prompts get better project-by-project.

## Add project-specific skills

Create `.cogcog/system.md` in your project:

```markdown
You are a senior TypeScript engineer working on a Node.js API.
This project uses Knex for database, JWT for auth, Redis for caching.
Be concise. Reference file paths. Show code, not prose.
```

This loads automatically into every context panel session.

Add reusable templates:

```markdown
<!-- .cogcog/review.md -->
Review for: bugs, security issues, performance problems, error handling.
Reference line numbers. No generic advice.
```

Load them with `:read .cogcog/review.md` in the context panel.

## Daily workflow cheatsheet

```
gaf             "what does this do?"        quick understanding
gsaf            "add error handling"         generate code
<leader>gcaf    verify with strongest model  before committing
<C-g>           plan a feature               agentic conversation
<leader>cy      pin code for cross-file questions
<leader>cd      map a new project
q               close any response split
<C-c>           cancel if it's taking too long
```
