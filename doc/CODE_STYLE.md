# cogcog Code Style & Best Practices

## Architecture

### Single Responsibility
Each module handles one responsibility:
- **init.lua**: Vim keymaps and command verbs
- **context.lua**: Context gathering and input building
- **stream.lua**: Streaming output to buffers
- **config.lua**: Configuration and shared state

### Vim-Native Design
- Uses `vim.api.*` for buffer/window management
- Leverages existing vim state (quickfix, jumplist, changes)
- No external dependencies beyond neovim

### Async Patterns
- Background jobs for LLM communication
- `vim.schedule()` for cross-thread operations
- `vim.fn.jobstart()` for asynchronous processing

## Conventions

### Function Naming
- `verb_do()`: Main action (e.g., `refactor_do`)
- `verb_send()`: Send to backend (e.g., `ask_send`)
- `verb()`: User-facing wrapper (e.g., `ask()`)

### Error Handling
```lua
-- Check validity before operations
if vim.api.nvim_buf_is_valid(buf) then ... end

-- Use pcall for risky operations
local success, result = pcall(vim.fn.readfile, path)

-- Notify on errors
vim.notify("error message", vim.log.levels.ERROR)
```

### Magic Numbers
Document all magic numbers:
```lua
-- 5 = number of jump locations to show
M.with_jumps(input, max_jumps or 5)

-- 60s = default timeout for background jobs
local timeout = opts.timeout or config.default_timeout
```

### Buffer Types
- **Temporary**: `[cogcog-ask]`, `[cogcog-gen]`
- **Context**: `[cogcog]` (persistent)
- **Exec**: `[cogcog-exec-123456]` (timestamped)

## Testing

Run tests with:
```bash
lua tests.lua
```

Test categories:
- **strip_code_fences**: Code fence removal
- **relative_name**: Path conversion
- **with_***: Context builder functions
- **to_buf**: Streaming logic (mocked)

## Configuration

Environment variables:
```bash
export COGCOG_TIMEOUT=60      # Default: 60s
export COGCOG_CHECKER="..."   # Strongest model for check/discover
export COGCOG_CMD="..."       # Backend for gen/plan/exec
export COGCOG_BACKEND="..."   # Backend for ask (ga)
```

## Session Management

- Session saved to `.cogcog/session.md`
- Auto-saved on `VimLeavePre`
- Cleared with `<leader>cc`

## Key Principles

1. **Vim state IS context** - Don't duplicate what vim already knows
2. **Least code** - Prefer simple solutions over frameworks
3. **Error awareness** - Check validity before operations
4. **User feedback** - Notify on errors and long operations
5. **Clean up** - Remove temp files on exit
