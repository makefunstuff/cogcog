# Cogcog Tutorial

A hands-on walkthrough of Cogcog as it works **today**.

The important mental model:

- **Neovim defines scope** with motions, selections, quickfix, and your current screen
- **Cogcog emits a structured event**
- **pi receives that event** in another terminal
- **pi uses Neovim tools** to inspect, navigate, and help you edit

This tutorial follows the bundled setup in this repo: Neovim plugin + pi extension.

---

## Part 0: Setup

### 0a. Install the plugin

```lua
{ "makefunstuff/cogcog", lazy = false, config = function() require("cogcog") end }
```

Cogcog starts a Neovim RPC socket automatically when it loads.
Default:

```text
/tmp/cogcog.sock
```

Override with `COGCOG_NVIM_SOCKET` if you want.

### 0b. Install the pi extension

```bash
cd /path/to/cogcog/pi-extension
npm install
ln -s /path/to/cogcog/pi-extension ~/.pi/agent/extensions/cogcog
```

### 0c. Run both sides

```text
Terminal 1: nvim
Terminal 2: pi
```

Inside pi:

```text
/reload
/cogcog-claim
/cogcog-status
```

Only the **claimed** pi session receives Cogcog events.

### 0d. First sanity check

Open any source file in Neovim, put your cursor on some code, and run:

```vim
gaip
```

Expected result:

- Neovim emits an `ask` event
- pi receives a follow-up message with the selection and editor context
- pi can now answer using its normal agent loop and `nvim_*` tools

If pi is not connected or not claimed, Neovim warns:

```text
cogcog: no pi listener for ask
```

---

## Part 1: The core idea

Cogcog treats the LLM as a **vim-triggered agent turn**, not as an embedded chat panel.

A motion or selection defines the hard scope:

```vim
gaip          ask about inner paragraph
gaf           ask about current function
gss           generate from the whole buffer
<leader>grip  refactor the current paragraph
<leader>gcaf  review the current function
```

The plugin does not invent a second selection model.
You keep using vim.

---

## Part 2: Ask / explain

### 2a. Explain scoped text

Put your cursor inside a function or code paragraph:

```vim
gaip
```

What happens:

1. Cogcog captures the selected text (`ip`)
2. It emits an `ask` event
3. pi receives the event together with current Neovim state
4. pi can answer directly, or inspect more using `nvim_context`, `nvim_buffer`, etc.

### 2b. Adjust the built-in ask wording with counts

```vim
1gaip          shorter ask instruction
gaip           normal ask instruction
3gaip          more detailed ask instruction
```

These counts change the ask prompt Cogcog emits.
The exact final answer still depends on what pi does with the event.

### 2c. Ask a specific question

Visual-select some code and run:

```vim
ga
```

Type something like:

```text
is this thread-safe?
```

This sends the selection plus your explicit question into pi.

### 2d. Ask about the whole file

```vim
gaa
```

Useful when you want pi to explain an entire module in one turn.

---

## Part 3: Your editor state already matters

Before each Cogcog-triggered turn, the bundled pi extension injects current
editor state into pi.

That includes:

- current buffer
- cursor position
- visible windows
- quickfix entries
- diagnostics summary
- lines around the cursor

### 3a. Use splits deliberately

Open two related files side by side:

```vim
:edit src/auth.ts
:vsplit src/session.ts
```

Now run:

```vim
gaip
```

pi can see that both buffers are visible and can use Neovim tools to inspect them.

### 3b. Keep the right buffer active

Cogcog turns are anchored in whatever you are currently looking at.
If you want pi to reason from a specific place, make that place current first.

---

## Part 4: Generate

Generation is just another structured event.

### 4a. Generate from a motion

Put your cursor on a TODO or stub:

```vim
gsip
```

Then type an instruction like:

```text
implement this with validation and error handling
```

Cogcog emits a `generate` event containing:

- the selected text
- where it came from
- your instruction

pi can then respond with code, open files, or edit directly depending on the workflow you want.

### 4b. Generate from a selection

```vim
Visual gs
```

This is good for turning an interface, type, or skeleton into a concrete implementation.

### 4c. Generate from the whole buffer

```vim
gss
```

Use this when the entire file is the prompt.

---

## Part 5: Refactor

Refactor is where Cogcog becomes especially precise.

### 5a. Refactor scoped text

```vim
<leader>grip
```

Then enter something like:

```text
simplify the control flow and keep the same behavior
```

Cogcog emits a `refactor` event with:

- the selected text
- your instruction
- the exact target file
- start line
- end line

That means pi does not have to guess where the rewrite belongs.

### 5b. Refactor a visual selection

```vim
Visual <leader>gr
```

This is the most direct way to say:

> rewrite exactly this region

The actual edit is still performed by pi or by you afterward.
Cogcog's job is to define the scope and carry the target location precisely.

---

## Part 6: Check / review

### 6a. Review a function

```vim
<leader>gcaf
```

Cogcog emits a `check` event telling pi to review the scoped code for:

- correctness
- edge cases
- bugs

### 6b. Review a selection

```vim
Visual <leader>gc
```

This is the fastest way to aim pi at a specific risky block.

---

## Part 7: Execute and workbench

### 7a. Execute from Neovim

Use this when you want to push a direct do-work instruction into pi from the editor:

```vim
<leader>gx
```

Then type something like:

```text
fix the failing test near the cursor
rename this helper to authClient
implement the TODO in this file
investigate why this retry loop never stops
```

Cogcog records the instruction in the workbench and emits an `execute` event.

### 7b. The workbench buffer

The workbench is a plain markdown scratch buffer:

```text
[cogcog-workbench]
```

It is useful for collecting snippets and keeping a working thread visible.

Open it with:

```vim
<leader>co
```

### 7c. Pin code into it

Visual-select something relevant, then:

```vim
<leader>gy
```

Do this from multiple files if needed.

### 7d. Continue from it

```vim
<C-g>
```

Behavior:

- from a normal file: Cogcog prompts for a plan request
- from the workbench: Cogcog emits “continue from here”

### 7e. Persistence

Workbench contents are saved to:

```text
.cogcog/workbench.md
```

So you can treat it as a durable scratchpad, not a throwaway popup.

### 7f. Clear it

```vim
<leader>cc
```

---

## Part 8: pi bridge commands and tools

### 8a. Session ownership

Inside pi:

```text
/cogcog-claim
/cogcog-release
/cogcog-status
```

If multiple pi sessions are open, only the claimed one receives events.

### 8b. Neovim tools available to pi

The extension registers these tools:

- `nvim_context`
- `nvim_buffer`
- `nvim_buffers`
- `nvim_diagnostics`
- `nvim_goto`
- `nvim_quickfix`
- `nvim_exec`
- `nvim_notify`

That gives pi enough editor awareness to:

- inspect the active file
- read any loaded buffer
- jump you to a file and line
- publish findings into quickfix
- notify you inside Neovim

### 8c. A practical loop

1. In Neovim, run `gaip` or `<leader>gcaf`
2. pi receives the event
3. pi asks for more context via `nvim_context` or `nvim_buffer`
4. pi replies or edits
5. if useful, pi pushes findings into quickfix via `nvim_quickfix`
6. you navigate with normal vim commands

---

## Part 9: Internal event hook

Every forwarded action is also exposed inside Neovim via:

- `User CogcogEvent`
- `vim.g.cogcog_last_event`

You do not need this for the normal bundled workflow, but it is useful if you
want to build your own listener later.

### 9a. Inspect emitted events

For example, in Neovim:

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "CogcogEvent",
  callback = function(ev)
    print(vim.inspect(ev.data))
  end,
})
```

Now every Cogcog event becomes observable inside Neovim.

---

## Part 10: Shell mode

This repo also ships a plain shell helper:

```bash
echo "explain CRDs" | cogcog
cat src/main.ts | cogcog --raw
```

This is separate from the Neovim/pi event flow.
It is just a Unix filter.

### 10a. Basic config

```bash
export COGCOG_API_URL=http://localhost:8091/v1/chat/completions
export COGCOG_MODEL=gemma4:26b
export OPENAI_API_KEY=dummy
```

Optional fast path for `--raw`:

```bash
export COGCOG_FAST_API_URL=http://localhost:1234/v1/chat/completions
export COGCOG_FAST_MODEL=gemma-4-e4b
```

### 10b. Delegate to another CLI

```bash
export COGCOG_CMD='claude -p'
```

Then:

```bash
git diff --staged | cogcog "review this"
```

---

## Part 11: What Cogcog is and is not

### Cogcog is

- a Neovim operator layer
- a workbench buffer
- a structured event emitter
- a pi bridge
- a small stdin → stdout shell helper

### Cogcog is not

- a built-in chat window inside Neovim
- a hidden background agent loop
- a guarantee that every keymap is handled by the bundled pi extension
- a replacement for normal vim navigation, quickfix, undo, and editing

---

## Quick reference

| Key | What happens today |
|-----|--------------------|
| `ga{motion}` / `gaa` / visual `ga` | emits ask / explain event |
| `gs{motion}` / `gss` / visual `gs` | emits generate event |
| `<leader>gr{motion}` / visual `<leader>gr` | emits refactor event with exact target range |
| `<leader>gc{motion}` / visual `<leader>gc` | emits check event |
| `<C-g>` | emits plan / continue event |
| `<leader>gx` | emits execute event from a Neovim prompt |
| `<leader>gy` | appends selection to workbench |
| `<leader>co` | toggles workbench |
| `<leader>cc` | clears workbench |
| `/cogcog-claim` | claim event delivery in pi |
| `/cogcog-status` | inspect bridge status |

If you remember only one thing, remember this:

> Cogcog gives pi precise scope from Neovim.
> pi gives Cogcog actual agent behavior.
