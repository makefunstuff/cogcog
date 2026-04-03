-- cogcog — LLM as a vim verb
-- ga{motion} / visual ga        stateless ask → response split
-- gs{motion} / visual gs        stateless generate → code buffer
-- <leader>gc{motion} / visual   check with cloud model
-- <C-g>                         stateful follow-up → context panel
-- <leader>cy                    pin selection to context
-- <leader>co                    toggle context panel
-- <leader>cc                    clear context
-- <C-c>                         cancel running job

local M = {}
local active_jobs = {}
local cogcog_dir = vim.fn.getcwd() .. "/.cogcog"
local session_file = cogcog_dir .. "/session.md"
local cogcog_bin = vim.fn.exepath("cogcog") ~= "" and vim.fn.exepath("cogcog") or "cogcog"

-- util
local function shell_escape(s) return vim.fn.shellescape(s) end
local function strip_ansi(s) return s:gsub("\27%[[%d;]*m", "") end
local function relative_name(path)
  if path == "" then return "scratch" end
  local cwd = vim.fn.getcwd() .. "/"
  return path:sub(1, #cwd) == cwd and path:sub(#cwd + 1) or path
end

local function with_input_system(input)
  local sys = cogcog_dir .. "/system.md"
  if vim.fn.filereadable(sys) == 1 then
    vim.list_extend(input, vim.fn.readfile(sys))
    table.insert(input, "")
  end
  return input
end

local function with_input_quickfix(input)
  local qf = vim.fn.getqflist()
  if #qf == 0 then return input end
  local out, seen = {}, {}
  for _, item in ipairs(qf) do
    if item.bufnr > 0 and item.lnum > 0 then
      local key = item.bufnr .. ":" .. item.lnum
      if not seen[key] then
        seen[key] = true
        local fname = relative_name(vim.api.nvim_buf_get_name(item.bufnr))
        table.insert(out, fname .. ":" .. item.lnum .. ": " .. vim.trim(item.text or ""))
      end
    end
  end
  if #out > 0 then
    table.insert(input, "--- quickfix ---")
    vim.list_extend(input, out)
    table.insert(input, "")
  end
  return input
end

local function with_input_selection(input, lines, source)
  if lines and #lines > 0 then
    table.insert(input, "--- " .. source .. " ---")
    table.insert(input, "")
    vim.list_extend(input, lines)
    table.insert(input, "")
  end
  return input
end

local function with_input_context(input)
  local ctx = M.get_or_create_ctx()
  local ctx_lines = vim.api.nvim_buf_get_lines(ctx, 0, -1, false)
  if vim.trim(table.concat(ctx_lines, "\n")) ~= "" then
    table.insert(input, "--- context ---")
    table.insert(input, "")
    vim.list_extend(input, ctx_lines)
    table.insert(input, "")
  end
  return input
end

-- streaming
local function stream_to_buf(lines, buf, opts)
  opts = opts or {}
  local tmp = vim.fn.tempname()
  vim.fn.writefile(lines, tmp)
  local flag = opts.raw and " --raw" or ""
  local cmd = (opts.cmd or cogcog_bin) .. flag .. " < " .. shell_escape(tmp)
  local first = true
  vim.notify("cogcog: thinking...", vim.log.levels.INFO)

  local job = vim.fn.jobstart({ "bash", "-c", cmd }, {
    stdout_buffered = false,
    on_stderr = function(_, data)
      if not data then return end
      local msg = vim.trim(table.concat(data, "\n"))
      msg = strip_ansi(msg)
      if msg == "" or msg:match("^> build") or msg:match("^%s*$") then return end
      vim.schedule(function()
        vim.notify("cogcog: " .. msg:sub(1, 200), vim.log.levels.ERROR)
      end)
    end,
    on_stdout = function(_, data)
      if not data then return end
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        if first then
          local lc = vim.api.nvim_buf_line_count(buf)
          local last = vim.api.nvim_buf_get_lines(buf, lc - 1, lc, false)[1] or ""
          if last ~= "" then vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "" }) end
          first = false
        end
        for i, chunk in ipairs(data) do
          chunk = strip_ansi(chunk)
          if chunk:match("^> build") then chunk = "" end
          local lc = vim.api.nvim_buf_line_count(buf)
          if i == 1 then
            local last = vim.api.nvim_buf_get_lines(buf, lc - 1, lc, false)[1] or ""
            vim.api.nvim_buf_set_lines(buf, lc - 1, lc, false, { last .. chunk })
          else
            vim.api.nvim_buf_set_lines(buf, lc, lc, false, { chunk })
          end
        end
        for _, w in ipairs(vim.api.nvim_list_wins()) do
          if vim.api.nvim_win_get_buf(w) == buf then
            pcall(vim.api.nvim_win_set_cursor, w, { vim.api.nvim_buf_line_count(buf), 0 })
          end
        end
      end)
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        vim.fn.delete(tmp)
        active_jobs[job] = nil
        if code ~= 0 then
          vim.notify("cogcog: exit " .. code, vim.log.levels.ERROR)
        else
          vim.notify("cogcog: done", vim.log.levels.INFO)
          if opts.on_done then opts.on_done() end
        end
      end)
    end,
  })
  if type(job) == "number" and job > 0 then active_jobs[job] = true end
  return job
end

function M.cancel_all()
  local count = 0
  for job in pairs(active_jobs) do
    vim.fn.jobstop(job)
    count = count + 1
  end
  active_jobs = {}
  if count > 0 then vim.notify("cogcog: cancelled", vim.log.levels.INFO) end
end

-- context panel
function M.get_or_create_ctx()
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_get_name(b):match("%[cogcog%]$") then
      return b
    end
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype, vim.bo[buf].buftype = "markdown", "nofile"
  vim.api.nvim_buf_set_name(buf, "[cogcog]")
  local initial = vim.fn.filereadable(session_file) == 1 and vim.fn.readfile(session_file)
      or (vim.fn.filereadable(cogcog_dir .. "/system.md") == 1 and vim.fn.readfile(cogcog_dir .. "/system.md") or {})
  if #initial > 0 then vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial) end
  return buf
end

local function ctx_win()
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(w) == M.get_or_create_ctx() then return w end
  end
end

function M.show_panel()
  if ctx_win() then return end
  local buf = M.get_or_create_ctx()
  local width = math.floor(vim.o.columns * 0.4)
  vim.cmd("botright vsplit | vertical resize " .. width)
  vim.api.nvim_win_set_buf(0, buf)
  for _, opt in ipairs({ "number", "relativenumber", "cursorline" }) do
    vim.api.nvim_set_option_value(opt, false, { win = 0 })
  end
  vim.api.nvim_set_option_value("signcolumn", "no", { win = 0 })
  vim.api.nvim_set_option_value("wrap", true, { win = 0 })
  vim.api.nvim_set_option_value("linebreak", true, { win = 0 })
  vim.api.nvim_set_option_value("winfixwidth", true, { win = 0 })
  vim.api.nvim_set_option_value("statusline", " cogcog", { win = 0 })
end

-- helpers
local function get_visual_selection()
  local name = relative_name(vim.api.nvim_buf_get_name(0))
  local l1, l2 = vim.fn.line("'<"), vim.fn.line("'>")
  return vim.api.nvim_buf_get_lines(0, l1 - 1, l2, false), name, l1, l2
end

local function make_split(vertical, buf, statusline)
  if vertical then
    local width = math.floor(vim.o.columns * 0.4)
    vim.cmd("botright vsplit | vertical resize " .. width)
  else
    vim.cmd("botright " .. math.max(10, math.floor(vim.o.lines * 0.4)) .. "split")
  end
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_set_option_value("number", false, { win = win })
  vim.api.nvim_set_option_value("signcolumn", "no", { win = win })
  vim.api.nvim_set_option_value("wrap", true, { win = win })
  vim.api.nvim_set_option_value("linebreak", true, { win = win })
  vim.api.nvim_set_option_value("statusline", statusline, { win = win })
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, desc = "close" })
  vim.cmd("wincmd p")
  return win
end

local function visual_then(fn)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
  vim.schedule(function()
    local lines, name, l1, l2 = get_visual_selection()
    fn(lines, name .. ":" .. l1 .. "-" .. l2)
  end)
end

-- ask
local function ask_prepare_input(code_lines, source)
  local input = {}
  with_input_system(input)
  with_input_quickfix(input)
  with_input_selection(input, code_lines, source)
  return input
end

local function ask_stateless(code_lines, source, question)
  local input = ask_prepare_input(code_lines, source)
  table.insert(input, question)

  local buf, win
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_get_name(b):match("%[cogcog%-ask%]$") then
      buf, win = b, nil
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(w) == buf then win = w end
      end
      break
    end
  end
  if not buf then
    buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype, vim.bo[buf].buftype = "markdown", "nofile"
    vim.api.nvim_buf_set_name(buf, "[cogcog-ask]")
  end
  if not win then
    win = make_split(true, buf, " cogcog ask │ " .. question:sub(1, 40))
  else
    vim.api.nvim_set_option_value("statusline", " cogcog ask │ " .. question:sub(1, 40), { win = win })
  end
  stream_to_buf(input, buf, { raw = true })
end

local function ask_stateful(code_lines, source, question)
  local ctx = M.get_or_create_ctx()
  if code_lines and #code_lines > 0 then
    vim.api.nvim_buf_set_lines(ctx, -1, -1, false, { "", "--- " .. source .. " ---", "" })
    vim.api.nvim_buf_set_lines(ctx, -1, -1, false, code_lines)
  end
  vim.api.nvim_buf_set_lines(ctx, -1, -1, false, { "", question, "" })
  stream_to_buf(vim.api.nvim_buf_get_lines(ctx, 0, -1, false), ctx, {
    raw = true,
    on_done = function()
      if vim.api.nvim_buf_is_valid(ctx) then
        vim.api.nvim_buf_set_lines(ctx, -1, -1, false, { "", "---", "", "" })
      end
    end,
  })
end

local function ask_send(code_lines, source, question)
  if ctx_win() then
    ask_stateful(code_lines, source, question)
  else
    ask_stateless(code_lines, source, question)
  end
end

local function ask(lines, source)
  vim.ui.input({ prompt = " ask: " }, function(q)
    if q and vim.trim(q) ~= "" then ask_send(lines, source, q) end
  end)
end

-- generate
local function gen_prepare_input(code_lines, source, instruction)
  local input = {}
  with_input_selection(input, code_lines, source)
  with_input_context(input)
  table.insert(input, instruction)
  table.insert(input, "")
  table.insert(input, "Output only the code. No explanations unless asked.")
  return input
end

local function gen_send(code_lines, source, instruction)
  local input = gen_prepare_input(code_lines, source, instruction)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype, vim.bo[buf].filetype = "nofile", "markdown"
  local win = make_split(false, buf, " cogcog gen │ " .. instruction:sub(1, 40))
  vim.api.nvim_set_option_value("number", true, { win = win })

  stream_to_buf(input, buf, {
    raw = false,
    on_done = function()
      if not vim.api.nvim_buf_is_valid(buf) then return end
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      while #lines > 0 and vim.trim(lines[1]) == "" do table.remove(lines, 1) end
      while #lines > 0 and vim.trim(lines[#lines]) == "" do table.remove(lines) end
      if #lines >= 2 then
        local lang = lines[1]:match("^```(%w+)")
        if lang and lines[#lines]:match("^```%s*$") then
          table.remove(lines, 1)
          table.remove(lines)
          vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
          local ft_map = { js = "javascript", ts = "typescript", py = "python", rb = "ruby", rs = "rust", sh = "bash", yml =
          "yaml" }
          vim.bo[buf].filetype = ft_map[lang] or lang
        end
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

-- check
local function resolve_checker()
  if vim.env.COGCOG_CHECKER then return vim.env.COGCOG_CHECKER end
  if vim.fn.executable("pi") == 1 then return "pi -p --provider anthropic --model opus:xhigh" end
  return cogcog_bin .. " --raw"
end
local checker_cmd = resolve_checker()

local function check_send(code_lines, source)
  local input = {
    "Review this code for correctness, edge cases, and bugs.",
    "Be concise. Only flag real problems.",
    "",
    "--- " .. source .. " ---",
    "",
  }
  vim.list_extend(input, code_lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype, vim.bo[buf].buftype = "markdown", "nofile"
  make_split(true, buf, " cogcog check │ " .. source:sub(1, 30))
  stream_to_buf(input, buf, { cmd = checker_cmd })
end

-- plan
local function plan_send(question)
  local ctx = M.get_or_create_ctx()
  if question then vim.api.nvim_buf_set_lines(ctx, -1, -1, false, { "", question, "" }) end
  M.show_panel()
  stream_to_buf(vim.api.nvim_buf_get_lines(ctx, 0, -1, false), ctx, {
    raw = false,
    on_done = function()
      if vim.api.nvim_buf_is_valid(ctx) then
        vim.api.nvim_buf_set_lines(ctx, -1, -1, false, { "", "---", "", "" })
      end
    end,
  })
end

-- refactor
local function strip_code_fences(result)
  while #result > 0 and result[#result] == "" do table.remove(result) end
  if #result >= 2 then
    if result[1]:match("^```") then table.remove(result, 1) end
    if result[#result]:match("^```") then table.remove(result) end
  end
  return result
end

local function refactor_prepare_input(lines, source, instruction)
  local input = {}
  with_input_system(input)
  table.insert(input, "--- " .. source .. " ---")
  table.insert(input, "")
  vim.list_extend(input, lines)
  table.insert(input, "")
  table.insert(input, instruction)
  table.insert(input, "")
  table.insert(input, "Output ONLY the refactored code. No explanations, no markdown fences, no backticks.")
  return input
end

local function refactor_do(lines, source, instruction, l1, l2)
  local input = refactor_prepare_input(lines, source, instruction)
  local tmp = vim.fn.tempname()
  vim.fn.writefile(input, tmp)
  vim.notify("cogcog: refactoring...", vim.log.levels.INFO)

  vim.fn.jobstart({ "bash", "-c", cogcog_bin .. " --raw < " .. shell_escape(tmp) }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if not data then return end
      vim.schedule(function()
        local result = strip_code_fences(data)
        if #result == 0 then
          vim.notify("cogcog: empty result", vim.log.levels.WARN)
          return
        end
        vim.api.nvim_buf_set_lines(0, l1 - 1, l2, false, result)
        vim.notify("cogcog: refactored " .. (l2 - l1 + 1) .. " → " .. #result .. " lines")
      end)
    end,
    on_exit = function() vim.schedule(function() vim.fn.delete(tmp) end) end,
  })
end

local function refactor(lines, source)
  vim.ui.input({ prompt = " refactor: " }, function(instruction)
    if not instruction or vim.trim(instruction) == "" then return end
    local l1, l2 = vim.fn.line("'["), vim.fn.line("']")
    if l1 == 0 then l1 = vim.fn.line("'<") end
    if l2 == 0 then l2 = vim.fn.line("'>") end
    refactor_do(lines, source, instruction, l1, l2)
  end)
end

-- discover
local function do_discover(discovery_file, update)
  vim.fn.mkdir(cogcog_dir, "p")
  local gather = {
    { "structure",    "tree -L 3 --noreport -I 'node_modules|.git|__pycache__|target|dist|build|zig-cache|zig-out|vendor|.next' 2>/dev/null || find . -maxdepth 3 -not -path '*/.git/*' | head -80" },
    { "project",      "cat package.json 2>/dev/null || cat Cargo.toml 2>/dev/null || cat go.mod 2>/dev/null || cat pyproject.toml 2>/dev/null || cat Makefile 2>/dev/null || echo 'none'" },
    { "entry points", [[head -50 $(find . -maxdepth 2 -type f \( -name 'main.*' -o -name 'index.*' -o -name 'app.*' -o -name 'mod.*' -o -name 'lib.*' \) -not -path '*node_modules*' -not -path '*/.git/*' 2>/dev/null | head -5) 2>/dev/null || echo 'none']] },
    { "git log",      "git log --oneline -20 2>/dev/null || echo 'not a git repo'" },
    { "README",       "head -60 README.md 2>/dev/null || head -60 README 2>/dev/null || echo 'none'" },
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
    table.insert(input, "UPDATE the discovery document above based on the current project state.")
  else
    table.insert(input, "Analyze this project. Output a structured reference document organized by DOMAIN.")
  end
  table.insert(input, "Format rules: real paths only, group by functional domain, concise.")
  vim.fn.writefile({ "# Discovering project...", "", "Please wait — Opus is analyzing." }, discovery_file)
  vim.cmd("edit " .. vim.fn.fnameescape(discovery_file))
  local buf = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_set_option_value("wrap", true, { win = win })
  vim.api.nvim_set_option_value("linebreak", true, { win = win })
  vim.api.nvim_set_option_value("statusline", " cogcog discover │ gathering...", { win = win })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
  vim.schedule(function()
    vim.api.nvim_set_option_value("statusline", " cogcog discover │ analyzing...", { win = win })
    stream_to_buf(input, buf, {
      cmd = checker_cmd,
      on_done = function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        vim.fn.writefile(vim.api.nvim_buf_get_lines(buf, 0, -1, false), discovery_file)
        vim.cmd("edit!")
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_set_option_value("statusline", " cogcog discover │ done │ gf to navigate", { win = win })
        end
        vim.notify("cogcog: saved " .. discovery_file, vim.log.levels.INFO)
      end,
    })
  end)
end

-- improve prompt
local function improve_prompt()
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local content = table.concat(lines, "\n")
  if vim.trim(content) == "" then
    vim.notify("cogcog: nothing to improve from", vim.log.levels.WARN)
    return
  end
  vim.ui.input({ prompt = " what was wrong: " }, function(feedback)
    if not feedback or vim.trim(feedback) == "" then return end
    local sys_file = cogcog_dir .. "/system.md"
    local current_prompt = vim.fn.filereadable(sys_file) == 1 and table.concat(vim.fn.readfile(sys_file), "\n") or ""
    local input = {
      "You are a prompt engineer. A user asked an LLM a question and got a bad response.",
      "",
      "Current system prompt:",
      current_prompt,
      "",
      "The conversation/response that was bad:",
      content,
      "",
      "User feedback on what was wrong:",
      feedback,
      "",
      "Write ONE concise instruction to add to the system prompt that would prevent this problem.",
      "Output ONLY the instruction line, nothing else.",
    }
    local tmp = vim.fn.tempname()
    vim.fn.writefile(input, tmp)
    vim.notify("cogcog: improving prompt...", vim.log.levels.INFO)
    vim.fn.jobstart({ "bash", "-c", cogcog_bin .. " --raw < " .. shell_escape(tmp) }, {
      stdout_buffered = true,
      on_stdout = function(_, data)
        if not data then return end
        vim.schedule(function()
          local improvement = vim.trim(table.concat(data, "\n"))
          if improvement == "" then return end
          vim.fn.mkdir(cogcog_dir, "p")
          local existing = vim.fn.filereadable(sys_file) == 1 and vim.fn.readfile(sys_file) or {}
          table.insert(existing, improvement)
          vim.fn.writefile(existing, sys_file)
          vim.notify("cogcog: added to system.md: " .. improvement:sub(1, 60), vim.log.levels.INFO)
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
    fn(lines, relative_name(vim.api.nvim_buf_get_name(0)) .. ":" .. s[1] .. "-" .. e[1])
  end
end

-- keymaps
_G._cogcog_ask_op = make_op(ask)
_G._cogcog_gen_op = make_op(gen)
_G._cogcog_check_op = make_op(check_send)
_G._cogcog_refactor_op = make_op(refactor)

vim.keymap.set("n", "ga", function()
  vim.o.operatorfunc = "v:lua._cogcog_ask_op"
  return "g@"
end, { expr = true, desc = "cogcog: ask about {motion}" })
vim.keymap.set("v", "ga", function() visual_then(ask) end, { desc = "cogcog: ask" })

vim.keymap.set("n", "gs", function()
  vim.o.operatorfunc = "v:lua._cogcog_gen_op"
  return "g@"
end, { expr = true, desc = "cogcog: generate from {motion}" })
vim.keymap.set("v", "gs", function() visual_then(gen) end, { desc = "cogcog: generate" })

vim.keymap.set("n", "gss", function()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  if #lines > 0 then gen(lines, relative_name(vim.api.nvim_buf_get_name(0))) end
end, { desc = "cogcog: generate from buffer" })

vim.keymap.set("n", "gr", function()
  vim.o.operatorfunc = "v:lua._cogcog_refactor_op"
  return "g@"
end, { expr = true, desc = "cogcog: refactor {motion}" })
vim.keymap.set("v", "gr", function()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
  vim.schedule(function()
    local lines, name, l1, l2 = get_visual_selection()
    vim.ui.input({ prompt = " refactor: " }, function(instruction)
      if instruction and vim.trim(instruction) ~= "" then
        refactor_do(lines, name .. ":" .. l1 .. "-" .. l2, instruction, l1, l2)
      end
    end)
  end)
end, { desc = "cogcog: refactor selection" })

vim.keymap.set("n", "<leader>gc", function()
  vim.o.operatorfunc = "v:lua._cogcog_check_op"
  return "g@"
end, { expr = true, desc = "cogcog: check {motion}" })
vim.keymap.set("v", "<leader>gc", function() visual_then(check_send) end, { desc = "cogcog: check selection" })

vim.keymap.set("n", "<C-g>", function()
  if vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf()):match("%[cogcog%]$") then
    plan_send(nil)
    return
  end
  vim.ui.input({ prompt = " plan: " }, function(q)
    if q and vim.trim(q) ~= "" then plan_send(q) end
  end)
end, { desc = "cogcog: plan" })

vim.keymap.set("v", "<leader>cy", function()
  visual_then(function(lines, source)
    local ctx = M.get_or_create_ctx()
    vim.api.nvim_buf_set_lines(ctx, -1, -1, false, { "", "--- " .. source .. " ---", "" })
    vim.api.nvim_buf_set_lines(ctx, -1, -1, false, lines)
    vim.notify("cogcog: pinned")
  end)
end, { desc = "cogcog: pin to context" })

vim.keymap.set("n", "<leader>co", function()
  if ctx_win() then vim.api.nvim_win_close(ctx_win(), false) else M.show_panel() end
end, { desc = "cogcog: toggle panel" })

vim.keymap.set("n", "<leader>cd", function()
  local discovery_file = cogcog_dir .. "/discovery.md"
  if vim.fn.filereadable(discovery_file) == 1 then
    vim.ui.select({ "Open", "Update", "Re-discover from scratch" }, { prompt = "discovery.md exists:" }, function(choice)
      if not choice then return end
      if choice == "Open" then
        vim.cmd("edit " .. vim.fn.fnameescape(discovery_file))
      elseif choice == "Update" then
        do_discover(discovery_file, true)
      else
        do_discover(discovery_file, false)
      end
    end)
    return
  end
  do_discover(discovery_file, false)
end, { desc = "cogcog: discover project" })

vim.keymap.set("n", "<leader>cp", improve_prompt, { desc = "cogcog: improve prompt" })

vim.keymap.set("n", "<leader>cc", function()
  vim.api.nvim_buf_set_lines(M.get_or_create_ctx(), 0, -1, false, {})
  vim.fn.delete(session_file)
  local sys = cogcog_dir .. "/system.md"
  if vim.fn.filereadable(sys) == 1 then
    vim.api.nvim_buf_set_lines(M.get_or_create_ctx(), 0, -1, false, vim.fn.readfile(sys))
  end
  vim.notify("cogcog: cleared")
end, { desc = "cogcog: clear" })

vim.keymap.set({ "n", "i" }, "<C-c>", function()
  if next(active_jobs) then
    M.cancel_all()
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
        if #lines > 0 and vim.trim(table.concat(lines, "")) ~= "" then
          vim.fn.mkdir(vim.fn.fnamemodify(session_file, ":h"), "p")
          vim.fn.writefile(lines, session_file)
        else
          vim.fn.delete(session_file)
        end
        return
      end
    end
  end,
})

return M
