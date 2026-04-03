-- cogcog — LLM as a vim verb
local config = require("cogcog.config")
local ctx = require("cogcog.context")
local stream = require("cogcog.stream")

-- ask (ga): stateless or stateful, no prompt by default

local ask_verbosity = {
  [0] = "Explain this code concisely.",
  [1] = "Explain in one sentence.",
  [2] = "Explain this code clearly.",
  [3] = "Explain in detail with examples.",
}

local function ask_stateless(code_lines, source, question)
  local input = {}
  ctx.with_system(input)
  ctx.with_quickfix(input)
  ctx.with_visible(input)
  ctx.with_selection(input, code_lines, source)
  table.insert(input, question)

  -- reuse existing ask buffer
  local buf, win
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_get_name(b):match("%[cogcog%-ask%]$") then
      buf = b
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(w) == buf then win = w end
      end
      break
    end
  end
  if not buf then
    buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = "markdown"
    vim.bo[buf].buftype = "nofile"
    vim.api.nvim_buf_set_name(buf, "[cogcog-ask]")
  end
  if not win then
    win = ctx.make_split(true, buf, " cogcog ask │ " .. question:sub(1, 40))
  else
    vim.api.nvim_set_option_value("statusline", " cogcog ask │ " .. question:sub(1, 40), { win = win })
  end
  stream.to_buf(input, buf, { raw = true })
end

local function ask_stateful(code_lines, source, question)
  local panel = ctx.get_or_create_panel()
  if code_lines and #code_lines > 0 then
    vim.api.nvim_buf_set_lines(panel, -1, -1, false, { "", "--- " .. source .. " ---", "" })
    vim.api.nvim_buf_set_lines(panel, -1, -1, false, code_lines)
  end
  vim.api.nvim_buf_set_lines(panel, -1, -1, false, { "", question, "" })
  stream.to_buf(vim.api.nvim_buf_get_lines(panel, 0, -1, false), panel, {
    raw = true,
    on_done = function()
      if vim.api.nvim_buf_is_valid(panel) then
        vim.api.nvim_buf_set_lines(panel, -1, -1, false, { "", "---", "", "" })
      end
    end,
  })
end

local function ask_send(code_lines, source, question)
  if ctx.panel_win() then
    ask_stateful(code_lines, source, question)
  else
    ask_stateless(code_lines, source, question)
  end
end

local saved_count = 0

local function ask(lines, source)
  local question = ask_verbosity[saved_count] or ask_verbosity[0]
  ask_send(lines, source, question)
end

local function ask_prompted(lines, source)
  vim.ui.input({ prompt = " ask: " }, function(q)
    if q and vim.trim(q) ~= "" then ask_send(lines, source, q) end
  end)
end

-- generate (gs): agent backend, new code buffer

local function gen_send(code_lines, source, instruction)
  local input = {}
  ctx.with_selection(input, code_lines, source)
  ctx.with_panel(input)
  table.insert(input, instruction)
  table.insert(input, "")
  table.insert(input, "Output only the code. No explanations unless asked.")

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].filetype = "markdown"
  local win = ctx.make_split(false, buf, " cogcog gen │ " .. instruction:sub(1, 40))
  vim.api.nvim_set_option_value("number", true, { win = win })

  stream.to_buf(input, buf, {
    raw = false,
    on_done = function()
      if not vim.api.nvim_buf_is_valid(buf) then return end
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      lines = ctx.strip_code_fences(lines)
      if #lines > 0 then
        local lang = lines[1]:match("^```(%w+)")
        if lang then -- still has fences after strip, shouldn't happen but guard
          table.remove(lines, 1)
          if lines[#lines] and lines[#lines]:match("^```") then table.remove(lines) end
        end
      end
      -- detect lang from first non-empty stripped fence
      local all_text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
      local detected = all_text:match("^```(%w+)")
      if detected then
        lines = ctx.strip_code_fences(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        local ft_map = { js="javascript", ts="typescript", py="python", rb="ruby", rs="rust", sh="bash", yml="yaml" }
        vim.bo[buf].filetype = ft_map[detected] or detected
      end
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_set_option_value("statusline", " cogcog gen │ done │ :w to save", { win = win })
      end
    end,
  })
end

local function gen(lines, source)
  vim.ui.input({ prompt = " gen: " }, function(q)
    if q and vim.trim(q) ~= "" then gen_send(lines, source, q) end
  end)
end

-- refactor (gr): in-place replacement

local function refactor_do(lines, source, instruction, l1, l2, target_buf)
  local input = {}
  ctx.with_system(input)
  table.insert(input, "--- " .. source .. " ---")
  table.insert(input, "")
  vim.list_extend(input, lines)
  table.insert(input, "")
  table.insert(input, instruction)
  table.insert(input, "")
  table.insert(input, "Rewrite the text above according to the instruction.")
  table.insert(input, "Output ONLY the rewritten content. No explanations, no markdown fences.")
  table.insert(input, "Do NOT refuse. Just rewrite it.")

  local tmp = vim.fn.tempname()
  vim.fn.writefile(input, tmp)
  vim.notify("cogcog: refactoring...", vim.log.levels.INFO)

  vim.fn.jobstart({ "bash", "-c", config.cogcog_bin .. " --raw < " .. vim.fn.shellescape(tmp) }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if not data then return end
      vim.schedule(function()
        local result = ctx.strip_code_fences(data)
        if #result == 0 then
          vim.notify("cogcog: empty result", vim.log.levels.WARN)
          return
        end
        local text = table.concat(result, " ")
        if #result <= 2 and (text:match("I do not") or text:match("I cannot") or text:match("I can't")) then
          vim.notify("cogcog: model refused, original preserved", vim.log.levels.WARN)
          return
        end
        if vim.api.nvim_buf_is_valid(target_buf) then
          vim.api.nvim_buf_set_lines(target_buf, l1 - 1, l2, false, result)
          vim.notify("cogcog: refactored " .. (l2 - l1 + 1) .. " → " .. #result .. " lines (u to undo)")
        end
      end)
    end,
    on_exit = function() vim.schedule(function() vim.fn.delete(tmp) end) end,
  })
end

local function refactor(lines, source)
  -- capture buffer + marks BEFORE the async input prompt
  local target_buf = vim.api.nvim_get_current_buf()
  local l1, l2 = vim.fn.line("'["), vim.fn.line("']")
  if l1 == 0 then l1 = vim.fn.line("'<") end
  if l2 == 0 then l2 = vim.fn.line("'>") end

  vim.ui.input({ prompt = " refactor: " }, function(instruction)
    if instruction and vim.trim(instruction) ~= "" then
      refactor_do(lines, source, instruction, l1, l2, target_buf)
    end
  end)
end

-- check (gc): deep review

local function check_send(code_lines, source)
  local input = {
    "Review this code for correctness, edge cases, and bugs.",
    "Be concise. Only flag real problems.",
    "", "--- " .. source .. " ---", "",
  }
  vim.list_extend(input, code_lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].buftype = "nofile"
  ctx.make_split(true, buf, " cogcog check │ " .. source:sub(1, 30))
  stream.to_buf(input, buf, { cmd = config.checker_cmd() })
end

-- plan (C-g): agentic conversation

local function plan_send(question)
  local panel = ctx.get_or_create_panel()
  if question then
    vim.api.nvim_buf_set_lines(panel, -1, -1, false, { "", question, "" })
  end
  ctx.show_panel()
  stream.to_buf(vim.api.nvim_buf_get_lines(panel, 0, -1, false), panel, {
    raw = false,
    on_done = function()
      if vim.api.nvim_buf_is_valid(panel) then
        vim.api.nvim_buf_set_lines(panel, -1, -1, false, { "", "---", "", "" })
      end
    end,
  })
end

-- exec (gx): agent multi-file work

local function exec_send(instruction, buf, win)
  local input = {}
  ctx.with_current_file(input)
  ctx.with_open_buffers(input)
  ctx.with_panel(input)
  table.insert(input, "--- instruction ---")
  table.insert(input, instruction)

  local tmp = vim.fn.tempname()
  vim.fn.writefile(input, tmp)

  local cmd = vim.env.COGCOG_CMD
  if not cmd or cmd == "" then cmd = config.cogcog_bin end

  stream.to_buf(input, buf, {
    cmd = cmd,
    stderr_to_buf = true,
    on_done = function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_set_option_value("statusline",
          " cogcog exec │ done │ :Git diff to review", { win = win })
      end
    end,
  })
end

-- discover

local function do_discover(discovery_file, update)
  vim.fn.mkdir(config.cogcog_dir, "p")
  local gather = {
    { "structure", "tree -L 3 --noreport -I 'node_modules|.git|__pycache__|target|dist|build|zig-cache|zig-out|vendor|.next' 2>/dev/null || find . -maxdepth 3 -not -path '*/.git/*' | head -80" },
    { "project", "cat package.json 2>/dev/null || cat Cargo.toml 2>/dev/null || cat go.mod 2>/dev/null || cat pyproject.toml 2>/dev/null || cat Makefile 2>/dev/null || echo 'none'" },
    { "entry points", [[head -50 $(find . -maxdepth 2 -type f \( -name 'main.*' -o -name 'index.*' -o -name 'app.*' \) -not -path '*node_modules*' -not -path '*/.git/*' 2>/dev/null | head -5) 2>/dev/null || echo 'none']] },
    { "git log", "git log --oneline -20 2>/dev/null || echo 'not a git repo'" },
    { "README", "head -60 README.md 2>/dev/null || head -60 README 2>/dev/null || echo 'none'" },
  }
  local input = {}
  for _, sec in ipairs(gather) do
    local output = vim.fn.systemlist(sec[2])
    if #output > 0 then
      table.insert(input, "--- " .. sec[1] .. " ---")
      table.insert(input, "")
      vim.list_extend(input, output)
      table.insert(input, "")
    end
  end
  if update and vim.fn.filereadable(discovery_file) == 1 then
    table.insert(input, "--- previous discovery ---")
    table.insert(input, "")
    vim.list_extend(input, vim.fn.readfile(discovery_file))
    table.insert(input, "")
    table.insert(input, "UPDATE this discovery. Add new files, remove deleted ones, update descriptions.")
  else
    table.insert(input, "Analyze this project. Output a structured reference organized by DOMAIN.")
    table.insert(input, "Format: `path/to/file.ext` for vim gf navigation. Group by domain. Be concise.")
  end
  table.insert(input, "You may READ files. Do NOT write or create files. Output only the document.")

  vim.fn.writefile({ "# Discovering project..." }, discovery_file)
  vim.cmd("edit " .. vim.fn.fnameescape(discovery_file))
  local buf = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_set_option_value("statusline", " cogcog discover │ analyzing...", { win = win })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})

  vim.schedule(function()
    stream.to_buf(input, buf, {
      cmd = config.checker_cmd(),
      on_done = function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        vim.fn.writefile(vim.api.nvim_buf_get_lines(buf, 0, -1, false), discovery_file)
        vim.cmd("edit!")
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_set_option_value("statusline", " cogcog discover │ done │ gf to navigate", { win = win })
        end
      end,
    })
  end)
end

-- improve prompt

local function improve_prompt()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local content = table.concat(lines, "\n")
  if vim.trim(content) == "" then
    vim.notify("cogcog: nothing to improve from", vim.log.levels.WARN)
    return
  end
  vim.ui.input({ prompt = " what was wrong: " }, function(feedback)
    if not feedback or vim.trim(feedback) == "" then return end
    local sys_file = config.cogcog_dir .. "/system.md"
    local input = {
      "You are a prompt engineer. Bad response below. User feedback follows.",
      "", "Current system prompt:", vim.fn.filereadable(sys_file) == 1 and table.concat(vim.fn.readfile(sys_file), "\n") or "",
      "", "Bad response:", content,
      "", "Feedback:", feedback,
      "", "Write ONE instruction to add to the system prompt. Output ONLY the instruction.",
    }
    local tmp = vim.fn.tempname()
    vim.fn.writefile(input, tmp)
    vim.fn.jobstart({ "bash", "-c", config.cogcog_bin .. " --raw < " .. vim.fn.shellescape(tmp) }, {
      stdout_buffered = true,
      on_stdout = function(_, data)
        if not data then return end
        vim.schedule(function()
          local improvement = vim.trim(table.concat(data, "\n"))
          if improvement == "" then return end
          vim.fn.mkdir(config.cogcog_dir, "p")
          local existing = vim.fn.filereadable(sys_file) == 1 and vim.fn.readfile(sys_file) or {}
          table.insert(existing, improvement)
          vim.fn.writefile(existing, sys_file)
          vim.notify("cogcog: +" .. improvement:sub(1, 60), vim.log.levels.INFO)
        end)
      end,
      on_exit = function() vim.schedule(function() vim.fn.delete(tmp) end) end,
    })
  end)
end

-- operator factory

local function make_op(fn)
  return function()
    local s, e = vim.api.nvim_buf_get_mark(0, "["), vim.api.nvim_buf_get_mark(0, "]")
    local lines = vim.api.nvim_buf_get_lines(0, s[1] - 1, e[1], false)
    if #lines == 0 then return end
    fn(lines, ctx.relative_name(vim.api.nvim_buf_get_name(0)) .. ":" .. s[1] .. "-" .. e[1])
  end
end

_G._cogcog_ask_op = make_op(ask)
_G._cogcog_gen_op = make_op(gen)
_G._cogcog_check_op = make_op(check_send)
_G._cogcog_refactor_op = make_op(refactor)

-- keymaps

vim.keymap.set("n", "ga", function()
  saved_count = vim.v.count -- capture BEFORE g@
  vim.o.operatorfunc = "v:lua._cogcog_ask_op"
  return "g@"
end, { expr = true, desc = "cogcog: ask" })
vim.keymap.set("v", "ga", function() ctx.visual_then(ask_prompted) end, { desc = "cogcog: ask" })

vim.keymap.set("n", "gs", function()
  vim.o.operatorfunc = "v:lua._cogcog_gen_op"
  return "g@"
end, { expr = true, desc = "cogcog: generate" })
vim.keymap.set("v", "gs", function() ctx.visual_then(gen) end, { desc = "cogcog: generate" })
vim.keymap.set("n", "gss", function()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  if #lines > 0 then gen(lines, ctx.relative_name(vim.api.nvim_buf_get_name(0))) end
end, { desc = "cogcog: generate from buffer" })

vim.keymap.set("n", "<leader>gr", function()
  vim.o.operatorfunc = "v:lua._cogcog_refactor_op"
  return "g@"
end, { expr = true, desc = "cogcog: refactor" })
vim.keymap.set("v", "<leader>gr", function()
  ctx.visual_then(function(lines, source)
    local target_buf = vim.api.nvim_get_current_buf()
    local l1, l2 = vim.fn.line("'<"), vim.fn.line("'>")
    vim.ui.input({ prompt = " refactor: " }, function(instruction)
      if instruction and vim.trim(instruction) ~= "" then
        refactor_do(lines, source, instruction, l1, l2, target_buf)
      end
    end)
  end)
end, { desc = "cogcog: refactor" })

vim.keymap.set("n", "<leader>gc", function()
  vim.o.operatorfunc = "v:lua._cogcog_check_op"
  return "g@"
end, { expr = true, desc = "cogcog: check" })
vim.keymap.set("v", "<leader>gc", function() ctx.visual_then(check_send) end, { desc = "cogcog: check" })

vim.keymap.set("n", "<C-g>", function()
  local bufname = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
  if bufname:match("%[cogcog%]$") then
    plan_send(nil)
  elseif bufname:match("%[cogcog%-exec") then
    -- continue in exec buffer
    local buf = vim.api.nvim_get_current_buf()
    local win = vim.api.nvim_get_current_win()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    if vim.trim(table.concat(lines, "\n")) == "" then return end
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "", "---", "" })
    vim.api.nvim_set_option_value("statusline", " cogcog exec │ continuing...", { win = win })
    local cmd = vim.env.COGCOG_CMD or config.cogcog_bin
    stream.to_buf(lines, buf, {
      cmd = cmd,
      stderr_to_buf = true,
      on_done = function()
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_set_option_value("statusline", " cogcog exec │ done", { win = win })
        end
      end,
    })
  else
    vim.ui.input({ prompt = " plan: " }, function(q)
      if q and vim.trim(q) ~= "" then plan_send(q) end
    end)
  end
end, { desc = "cogcog: plan / continue" })

vim.keymap.set("v", "<leader>cy", function()
  ctx.visual_then(function(lines, source)
    local panel = ctx.get_or_create_panel()
    vim.api.nvim_buf_set_lines(panel, -1, -1, false, { "", "--- " .. source .. " ---", "" })
    vim.api.nvim_buf_set_lines(panel, -1, -1, false, lines)
    vim.notify("cogcog: pinned")
  end)
end, { desc = "cogcog: pin" })

vim.keymap.set("n", "<leader>co", function()
  if ctx.panel_win() then vim.api.nvim_win_close(ctx.panel_win(), false) else ctx.show_panel() end
end, { desc = "cogcog: panel" })

vim.keymap.set("n", "<leader>gj", function()
  local input = {}
  ctx.with_system(input)
  ctx.with_jumps(input, 8)
  table.insert(input, "How do these code locations connect? What's the flow?")
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].buftype = "nofile"
  ctx.make_split(true, buf, " cogcog jumps")
  stream.to_buf(input, buf, { raw = true })
end, { desc = "cogcog: jump trail" })

vim.keymap.set("n", "<leader>g.", function()
  local input = {}
  ctx.with_system(input)
  ctx.with_changes(input)
  table.insert(input, "I made these changes. Any bugs or issues?")
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].buftype = "nofile"
  ctx.make_split(true, buf, " cogcog changes")
  stream.to_buf(input, buf, { raw = true })
end, { desc = "cogcog: review changes" })

vim.keymap.set("n", "<leader>gx", function()
  -- capture current buffer BEFORE creating exec buffer
  local cur_buf = vim.api.nvim_get_current_buf()
  vim.ui.input({ prompt = " do: " }, function(instruction)
    if not instruction or vim.trim(instruction) == "" then return end
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = "markdown"
    vim.bo[buf].buftype = "nofile"
    vim.api.nvim_buf_set_name(buf, "[cogcog-exec-" .. os.time() .. "]")
    local win = ctx.make_split(true, buf, " cogcog exec │ " .. instruction:sub(1, 40))
    exec_send(instruction, buf, win)
  end)
end, { desc = "cogcog: execute" })

vim.keymap.set("n", "<leader>cd", function()
  local f = config.cogcog_dir .. "/discovery.md"
  if vim.fn.filereadable(f) == 1 then
    vim.ui.select({ "Open", "Update", "Re-discover" }, { prompt = "discovery.md:" }, function(c)
      if c == "Open" then vim.cmd("edit " .. vim.fn.fnameescape(f))
      elseif c == "Update" then do_discover(f, true)
      elseif c == "Re-discover" then do_discover(f, false) end
    end)
  else
    do_discover(f, false)
  end
end, { desc = "cogcog: discover" })

vim.keymap.set("n", "<leader>cp", improve_prompt, { desc = "cogcog: improve prompt" })

vim.keymap.set("n", "<leader>cc", function()
  local panel = ctx.get_or_create_panel()
  vim.api.nvim_buf_set_lines(panel, 0, -1, false, {})
  vim.fn.delete(config.session_file)
  local sys = config.cogcog_dir .. "/system.md"
  if vim.fn.filereadable(sys) == 1 then
    vim.api.nvim_buf_set_lines(panel, 0, -1, false, vim.fn.readfile(sys))
  end
  vim.notify("cogcog: cleared")
end, { desc = "cogcog: clear" })

vim.keymap.set({ "n", "i" }, "<C-c>", function()
  if next(stream.active_jobs) then
    stream.cancel_all()
  else
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-c>", true, false, true), "n", false)
  end
end, { desc = "cogcog: cancel" })

-- session persistence
vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_get_name(b):match("%[cogcog%]$") then
        local lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
        if #lines > 1 or (#lines == 1 and lines[1] ~= "") then
          vim.fn.mkdir(vim.fn.fnamemodify(config.session_file, ":h"), "p")
          vim.fn.writefile(lines, config.session_file)
        else
          vim.fn.delete(config.session_file)
        end
        return
      end
    end
  end,
})
