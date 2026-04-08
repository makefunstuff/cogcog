# Cogcog Tutorial

A hands-on walkthrough of every concept in Cogcog.
Work through this in order — each section builds on the previous one.

## Prerequisites

```bash
# Verify your setup
echo $COGCOG_BACKEND       # → copilot
echo $COGCOG_CMD            # → (should be empty)
echo $COGCOG_CHECKER        # → (should be empty)
```

Open Neovim. Confirm cogcog loads:

```vim
:echo has_key(plugs, 'cogcog')   " or just try gaip on any file
```

---

## Part 1: The core idea

Cogcog treats the LLM as **a vim verb**, not a chat partner.
You operate on text the same way you use `d`, `y`, `c` — with a motion or selection.

The model sees what you point it at. No hidden context accumulation.
No background indexing. No session history unless you explicitly open the workbench.

There are three context tiers:

| Tier | What | Example |
|------|------|---------|
| **Hard scope** | The explicit operand you're acting on | `gaip` → this paragraph |
| **Explicit imports** | Text you deliberately brought in | workbench contents, pinned snippets |
| **Soft context** | Nearby signals for grounding | visible windows, quickfix list |

You always know what the model probably saw.

---

## Part 2: Explain — your most common verb

Open any source file. Put your cursor inside a function.

### 2a. Explain a paragraph (no prompt, instant)

```
gaip
```

A `[cogcog-ask]` split opens on the right with a concise explanation.
Press `q` to close it.

**What happened**: `ga` = ask verb. `ip` = inner paragraph (vim motion).
The model saw that paragraph + your visible windows + quickfix (if any).
No prompt was needed — the default is "explain this code concisely."

### 2b. Control verbosity with count

```
1gaip          → one sentence
gaip           → concise (default)
2gaip          → clear explanation
3gaip          → detailed with examples
```

Try each one on the same paragraph. The response length changes.

### 2c. Explain a function

```
gaf            → explain this function (uses vim's function text object)
```

### 2d. Explain the entire buffer

```
gaa            → explain the whole file
```

### 2e. Ask a specific question

Visual-select some code, then:

```
ga
```

A prompt appears. Type your question:

```
is this thread-safe?
```

The answer appears in the same `[cogcog-ask]` split.
Subsequent `ga` calls reuse the same split — no window proliferation.

**Key concept**: `ga` without visual = explain (no prompt needed).
`ga` with visual = ask (prompt required).

---

## Part 3: Soft context — your screen is the context

This is one of Cogcog's most important ideas.

### 3a. Setup: split two related files

```vim
:edit src/auth/middleware.ts
:vsplit src/auth/oauth.ts
```

Now put your cursor in `middleware.ts` on a function that calls something from `oauth.ts`.

```
gaip
```

**The model saw both files** because both are visible. It can explain how they connect.
You didn't have to "add context" or "reference" anything — visible windows are soft context.

### 3b. Close one window

```vim
:only           " close all splits except current
gaip            " now it only sees the one file
```

**You control context by controlling your screen.**
This is the Cogcog alternative to "@file" mentions and context panels.

---

## Part 4: Generate code

### 4a. Generate from a motion

Put your cursor on a TODO comment or function signature:

```
gsip → "implement this with error handling"
```

A new code buffer opens with generated code. It has the correct filetype.
Save it: `:w src/newfile.ts`

### 4b. Generate from selection

Visual-select a type definition or interface:

```
gs → "implement this interface"
```

### 4c. Generate for the whole buffer

```
gss → "scaffold the module"
```

**Speed**: Generate uses `--raw` (sonnet 4.6). Should feel instant.

---

## Part 5: Refactor — in-place rewriting

### 5a. Small refactor (inline apply)

Put cursor on a short function:

```
<leader>grip → "simplify"
```

The code is replaced **in-place**. Press `u` to undo. That's it.

### 5b. Large refactor (review buffer)

Select a larger block (20+ lines):

```
Visual → <leader>gr → "convert callbacks to async/await"
```

When the rewrite is large, Cogcog opens a `[cogcog-review]` buffer with a unified diff.

- Press `a` to apply the changes
- Press `q` to reject and close

**The rule**: small rewrites go inline (fast, undoable). Large rewrites get a review gate.
You always see what changed before it lands.

---

## Part 6: Check — structured review

### 6a. Check a function

```
<leader>gcaf          review this function
```

Opens a `[cogcog-check]` split with the model's assessment: bugs, edge cases, suggestions.

### 6b. Check a selection

```
Visual → <leader>gc
```

### 6c. Check a paragraph

```
<leader>gcip
```

**Note**: Check uses the same bundled transport as other verbs by default.
Set `COGCOG_CHECKER` only if you want a separate, heavier command for deeper review.

---

## Part 7: Quickfix — batch work with explicit scope

This is the main contract for multi-location work.

### 7a. Build a target set

```vim
:grep "TODO" src/**
:copen                    " see what's in the quickfix list
```

Or from LSP:

```vim
:lua vim.diagnostic.setqflist()
```

Or from make:

```vim
:make
```

### 7b. Ask with quickfix context

Now with quickfix populated, any `ga` call auto-includes quickfix entries:

```
gaip          " explain this code — quickfix entries included as context
```

### 7c. Summarize the quickfix set

```
<leader>gq          summarize what's in quickfix
```

### 7d. Review the quickfix set

```
<leader>gQ          review and prioritize quickfix items
```

### 7e. Batch rewrite (prepare → review → apply)

This is the most powerful batch operation:

```
<leader>gR
```

What happens:
1. Cogcog reads all quickfix targets, grouped by file
2. Prepares rewrites for each target
3. Opens a review buffer with unified diffs
4. You press `a` to apply, or `q` to reject

**Targets that changed between prepare and apply are skipped** — no stale overwrites.

### 7f. The typical quickfix loop

```vim
:grep "TODO" src/**       " 1. build target set
<leader>gQ                " 2. review what you're about to change
<leader>gR                " 3. prepare → review → apply
```

**Key concept**: Quickfix is the batch boundary. Cogcog never roams beyond what you put in quickfix.

---

## Part 8: The workbench — persistent editable scratchpad

Everything above is **stateless**. Each verb call is independent.
The workbench is where you go when you need persistence.

### 8a. Open the workbench

```
<leader>co
```

A side panel opens. It's a plain markdown buffer you can edit freely.

### 8b. Plan / synthesize (fast)

From any code file:

```
<C-g> → "add rate limiting to this API"
```

The model's response streams into the workbench. Follow up:

```
<C-g> → "use token bucket instead of sliding window"
```

Each `<C-g>` continues in the workbench. The workbench accumulates your conversation.

### 8c. Pin snippets from multiple files

Navigate to file A, visual select a relevant function:

```
<leader>gy          pin to workbench
```

Navigate to file B, visual select another function:

```
<leader>gy          pin again
```

Now ask about both:

```
<C-g> → "can these two functions race?"
```

The model sees both pinned snippets because they're in the workbench.

### 8d. Import external context

Inside the workbench:

```vim
:read !git diff --staged         " staged changes
:read !tree -L 3                 " project structure
:read !grep -rn "auth" src/      " search results
:read .cogcog/review.md          " a skill file
```

This is native vim. No special import system.

### 8e. Edit the workbench

Delete a section: `dap`
Rearrange: `ddp`
Add your own notes: just type

**The workbench is a buffer.** All vim operations work.

### 8f. Close the workbench

```
<leader>co          toggle closed
```

When the workbench is closed, `ga` and other verbs go back to fully stateless mode.
The workbench auto-saves to `.cogcog/workbench.md` on exit.

### 8g. Clear the workbench

```
<leader>cc
```

---

## Part 9: Discovery — scouting unfamiliar code

### 9a. Map the project

```
<leader>cd
```

Options appear: Open / Update / Re-discover.
Choose Re-discover on a new project.

Output is a navigable map saved to `.cogcog/discovery.md`:

```markdown
### Auth
- `src/auth/middleware.ts` — JWT validation
- `src/auth/oauth.ts` — OAuth2 flow

### Database
- `src/db/pool.ts` — connection pooling
```

### 9b. Navigate the discovery note

Put cursor on a file path and press:

```
gf                  jump to that file
```

Then:

```
gaip                explain what you landed on
```

### 9c. Pin a domain into the workbench

In the discovery note:

```
/### Auth                       jump to auth section
V/### Database                  select the auth domain
<leader>gy                      pin to workbench
<C-g> → "simplify token refresh"
```

---

## Part 10: Jump trail and recent changes

### 10a. Investigate your navigation path

Navigate around a codebase normally: `gd`, `gr`, `<C-o>`, etc.

Then:

```
<leader>gj          how do these locations connect?
```

Cogcog reads your last 8 jump positions and asks the model to explain the relationships.

### 10b. Review your recent edits

Make some changes across a file, then:

```
<leader>g.          any bugs in my changes?
```

Cogcog extracts your recently edited lines and asks for a review.

---

## Part 11: Per-project system prompts

### 11a. Create a system prompt

```bash
mkdir -p .cogcog
cat > .cogcog/system.md << 'EOF'
You are a senior engineer.
Be concise. Show code when relevant, explain when asked.
This project uses TypeScript, PostgreSQL, Redis.
EOF
```

Cogcog loads this automatically on every call.

### 11b. Improve prompts from bad responses

Got a vague or generic response? While looking at it:

```
<leader>cp → "too generic, read the actual code structure"
```

This appends your feedback to `.cogcog/system.md`. Prompts improve per-project over time.

---

## Part 12: Optional external execute

This is **disabled by default** and intentionally so.

### 12a. Enable it

```bash
export COGCOG_AGENT_CMD="pi -p --no-session"    # or any agentic command
```

### 12b. Use it

```
<leader>gx → "refactor auth across all files"
```

Agent activity streams into the workbench. The prompt is anchored by visible windows, quickfix, and workbench contents.

### 12c. Why it's separate

`<leader>gx` is the only verb that gives the model write access beyond the current operand.
Everything else is bounded. This one is explicitly opted-in.

---

## Part 13: Cancellation

At any point during a running job:

```
<C-c>               cancel all running cogcog jobs
```

Works in both normal and insert mode.

---

## Part 14: The shell transport

The bundled `bin/cogcog` is also usable from the command line:

```bash
# fast (sonnet 4.6)
echo "explain CRDs" | cogcog --raw

# smart (opus 4.6)
git diff --staged | cogcog "review this"

# pipe anything
cat src/main.ts | cogcog --raw "any bugs?"
kubectl logs deploy/api | cogcog --raw "what happened?"
```

From inside Neovim:

```vim
:%!cogcog --raw           send entire buffer, replace with response
:'<,'>!cogcog --raw       send selection, replace with response
```

This is standard Unix pipelining. The transport is `stdin → LLM → stdout`.

---

## Part 15: The complete workflow

Here's how the pieces compose in a real session:

### Arriving at unfamiliar code

```
<leader>cd              discover the project
gf                      navigate to an interesting file
gaip                    explain what you're looking at
gaf                     explain the function
<leader>gj              how does my navigation path connect?
```

### Working on a feature

```
<C-g> → "design the auth flow"         plan in workbench
gsaf → "implement token validation"     generate code
:w src/auth/validate.ts                 save
<leader>gcaf                            check the implementation
<leader>graf → "handle token expiry"    refine
```

### Fixing a batch of issues

```vim
:make                                   " errors → quickfix
gaip                                    " understand the first error
<leader>gQ                              " review all errors
<leader>gR                              " batch fix → review → apply
:make                                   " verify
```

### Investigating a bug across files

```vim
:edit src/auth.ts                       " open suspect file
:vsplit src/session.ts                  " open related file
gaip                                    " explain with both visible
<leader>gy                              " pin auth code to workbench
:edit src/middleware.ts
<leader>gy                              " pin middleware too
<C-g> → "can these race on session refresh?"
```

---

## Part 16: What Cogcog is NOT

- **Not a chat harness.** No hidden session, no context accumulation unless you open the workbench.
- **Not an autonomous agent.** `<leader>gx` is explicitly opt-in and disabled by default.
- **Not a RAG system.** No background indexing, no embedding store.
- **Not a persistent memory.** Each verb call is stateless. The workbench is opt-in persistence.
- **Not fighting vim.** Motions, text objects, splits, quickfix, `gf`, `:read` — all work as vim intended.

---

## Quick reference

| Key | What | Speed |
|-----|------|-------|
| `gaip` / `gaf` / `gaa` | explain (no prompt) | fast |
| `1gaip` / `3gaip` | one-sentence / detailed | fast |
| visual `ga` | ask with prompt | fast |
| `gsip` / `gss` | generate code | fast |
| visual `gs` | generate from selection | fast |
| `<leader>grip` | refactor in-place | fast |
| `<leader>gcaf` | check / review | fast |
| `<C-g>` | plan / synthesize (workbench) | fast |
| `<leader>gy` | pin to workbench | instant |
| `<leader>co` | toggle workbench | instant |
| `<leader>cc` | clear workbench | instant |
| `<leader>gj` | jump trail context | fast |
| `<leader>g.` | recent changes review | fast |
| `<leader>gq` | summarize quickfix | fast |
| `<leader>gQ` | review quickfix | fast |
| `<leader>gR` | batch rewrite quickfix | fast |
| `<leader>cd` | discover project | fast |
| `<leader>cp` | improve prompt | instant |
| `<leader>gx` | external execute | slow (opt-in) |
| `<C-c>` | cancel | instant |
| `q` | close split | instant |
| `a` | apply review buffer | instant |
| `u` | undo inline refactor | instant |
