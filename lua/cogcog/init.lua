-- cogcog — LLM as a vim verb
local config = require("cogcog.config")
local ctx = require("cogcog.context")
local stream = require("cogcog.stream")

-- ask (ga): stateless or workbench-aware, no prompt by default

local ask_verbosity = {
  [0] = "Explain this code concisely.",
  [1] = "Explain in one sentence.",
  [2] = "Explain this code clearly.",
  [3] = "Explain in detail with examples.",
}

local function ask_stateless(code_lines, source, question)
  local input = {}
  ctx.with_system(input)
  ctx.with_scope_contract(input)
  -- override system prompt's "output only code" for ask mode
  table.insert(input, "For this request: explain in natural language. Do NOT output code unless specifically asked.")
  table.insert(input, "")
  ctx.with_selection(input, code_lines, source)
  ctx.with_quickfix(input)
  ctx.with_visible(input)
  table.insert(input, question)

  local buf = ctx.reuse_or_split("[cogcog-ask]", " 🔍 ask │ " .. question:sub(1, 40))
  stream.to_buf(input, buf, { raw = true })
end

local function ask_in_workbench(code_lines, source, question)
  local workbench = ctx.get_or_create_workbench()
  if code_lines and #code_lines > 0 then
    vim.api.nvim_buf_set_lines(workbench, -1, -1, false, { "", "--- " .. source .. " ---", "" })
    vim.api.nvim_buf_set_lines(workbench, -1, -1, false, code_lines)
  end
  vim.api.nvim_buf_set_lines(workbench, -1, -1, false, { "", question, "" })

  local input = {}
  ctx.with_system(input)
  ctx.with_scope_contract(input)
  ctx.with_quickfix(input)
  ctx.with_workbench(input)
  ctx.with_visible(input)

  stream.to_buf(input, workbench, {
    raw = true,
    on_done = function()
      if vim.api.nvim_buf_is_valid(workbench) then
        vim.api.nvim_buf_set_lines(workbench, -1, -1, false, { "", "---", "", "" })
      end
    end,
  })
end

local function ask_send(code_lines, source, question)
  if ctx.workbench_win() then
    ask_in_workbench(code_lines, source, question)
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
  ctx.with_system(input)
  ctx.with_scope_contract(input)
  ctx.with_selection(input, code_lines, source)
  ctx.with_workbench(input)
  table.insert(input, instruction)
  table.insert(input, "")
  table.insert(input, "Output only the code. No explanations unless asked.")

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].filetype = "markdown"
  local win = ctx.make_split(false, buf, " 🔨 gen │ " .. instruction:sub(1, 40))
  vim.api.nvim_set_option_value("number", true, { win = win })

  stream.to_buf(input, buf, {
    raw = true, -- fast: code already selected, no tools needed
    on_done = function()
      if not vim.api.nvim_buf_is_valid(buf) then return end
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      -- strip leading/trailing blanks
      while #lines > 0 and vim.trim(lines[1]) == "" do table.remove(lines, 1) end
      while #lines > 0 and vim.trim(lines[#lines]) == "" do table.remove(lines) end
      -- detect and strip code fences
      if #lines >= 2 then
        local lang = lines[1]:match("^```(%w+)")
        if lang and lines[#lines]:match("^```%s*$") then
          table.remove(lines, 1)
          table.remove(lines)
          vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
          local ft_map = { js="javascript", ts="typescript", py="python", rb="ruby", rs="rust", sh="bash", yml="yaml" }
          vim.bo[buf].filetype = ft_map[lang] or lang
        end
      end
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_set_option_value("statusline", " 🔨 gen │ done │ :w to save", { win = win })
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

local REFACTOR_REVIEW_LINE_THRESHOLD = 8

local function apply_refactor_result(target_buf, l1, l2, result)
  if not vim.api.nvim_buf_is_valid(target_buf) then
    vim.notify("cogcog: target buffer closed", vim.log.levels.WARN)
    return false
  end
  vim.api.nvim_buf_set_lines(target_buf, l1 - 1, l2, false, result)
  vim.notify("✓ refactored " .. (l2 - l1 + 1) .. " → " .. #result .. " lines (u to undo)")
  return true
end

local function refactor_needs_review(original, result)
  return math.max(#original, #result) > REFACTOR_REVIEW_LINE_THRESHOLD or math.abs(#original - #result) > 2
end

local function open_refactor_review(source, instruction, target_buf, l1, l2, original, result)
  local review_buf, review_win = ctx.reuse_or_split("[cogcog-review]", " 👀 review │ a apply │ q close")
  local lines = {
    "# Refactor review",
    "",
    "Source: " .. source,
    "Instruction: " .. instruction,
    "",
    "Press `a` to apply, `q` to close.",
    "",
    "## Diff",
    "",
  }
  vim.list_extend(lines, ctx.unified_diff(original, result))
  table.insert(lines, "")
  table.insert(lines, "## Rewritten")
  table.insert(lines, "")
  vim.list_extend(lines, result)

  vim.bo[review_buf].readonly = false
  vim.bo[review_buf].modifiable = true
  vim.api.nvim_buf_set_lines(review_buf, 0, -1, false, lines)

  vim.keymap.set("n", "a", function()
    if apply_refactor_result(target_buf, l1, l2, result) then
      for _, win in ipairs(vim.fn.win_findbuf(review_buf)) do
        if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, false) end
      end
    end
  end, { buffer = review_buf, desc = "cogcog: apply review" })

  if vim.api.nvim_win_is_valid(review_win) then
    vim.api.nvim_set_option_value("wrap", false, { win = review_win })
    vim.api.nvim_set_option_value("statusline", " 👀 review │ a apply │ q close", { win = review_win })
    vim.api.nvim_set_current_win(review_win)
  end
end

local function refactor_do(lines, source, instruction, l1, l2, target_buf)
  local input = {}
  ctx.with_system(input)
  ctx.with_scope_contract(input)
  ctx.with_selection(input, lines, source)
  table.insert(input, instruction)
  table.insert(input, "")
  table.insert(input, "Rewrite the text above according to the instruction.")
  table.insert(input, "Output ONLY the rewritten content. No explanations, no markdown fences.")
  table.insert(input, "Do NOT refuse. Just rewrite it.")

  -- use a hidden scratch buffer to collect the response, then apply or review
  local tmp_buf = vim.api.nvim_create_buf(false, true)
  vim.notify("🔄 refactoring...", vim.log.levels.INFO)

  stream.to_buf(input, tmp_buf, {
    raw = true,
    on_done = function()
      if not vim.api.nvim_buf_is_valid(tmp_buf) then return end
      local result = vim.api.nvim_buf_get_lines(tmp_buf, 0, -1, false)
      vim.api.nvim_buf_delete(tmp_buf, { force = true })

      result = ctx.strip_code_fences(result)
      while #result > 0 and vim.trim(result[1]) == "" do table.remove(result, 1) end
      while #result > 0 and vim.trim(result[#result]) == "" do table.remove(result) end

      if #result == 0 then
        vim.notify("cogcog: empty result", vim.log.levels.WARN)
        return
      end
      local text = table.concat(result, " ")
      if #result <= 2 and (text:match("I do not") or text:match("I cannot") or text:match("I can't")) then
        vim.notify("cogcog: model refused, original preserved", vim.log.levels.WARN)
        return
      end
      if ctx.same_lines(lines, result) then
        vim.notify("cogcog: no changes suggested", vim.log.levels.INFO)
        return
      end
      if refactor_needs_review(lines, result) then
        open_refactor_review(source, instruction, target_buf, l1, l2, lines, result)
      else
        apply_refactor_result(target_buf, l1, l2, result)
      end
    end,
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
  local input = {}
  ctx.with_system(input)
  ctx.with_scope_contract(input)
  table.insert(input, "Review this code for correctness, edge cases, and bugs.")
  table.insert(input, "Be concise. Only flag real problems.")
  table.insert(input, "")
  ctx.with_selection(input, code_lines, source)
  local title = " 🛡 check │ " .. source:sub(1, 30)
  local buf, win = ctx.reuse_or_split("[cogcog-check]", title)
  stream.to_buf(input, buf, {
    cmd = config.checker_cmd(),
    on_done = function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_set_option_value("statusline", title .. " │ done", { win = win })
      end
    end,
  })
end

-- plan (C-g): workbench-driven synthesis

local function plan_send(question)
  local workbench = ctx.get_or_create_workbench()
  if question then
    vim.api.nvim_buf_set_lines(workbench, -1, -1, false, { "", question, "" })
  end
  ctx.show_workbench()

  local input = {}
  ctx.with_system(input)
  ctx.with_scope_contract(input)
  ctx.with_quickfix(input)
  ctx.with_workbench(input)
  ctx.with_visible(input)

  stream.to_buf(input, workbench, {
    raw = true,
    on_done = function()
      if vim.api.nvim_buf_is_valid(workbench) then
        vim.api.nvim_buf_set_lines(workbench, -1, -1, false, { "", "---", "", "" })
      end
    end,
  })
end

-- exec (gx): cloud agent, anchored by workbench + visible state

local function exec_send(instruction)
  local cmd = config.agent_cmd()
  if not cmd then
    vim.notify("cogcog: set COGCOG_AGENT_CMD to enable <leader>gx", vim.log.levels.WARN)
    return
  end

  local workbench = ctx.get_or_create_workbench()

  vim.api.nvim_buf_set_lines(workbench, -1, -1, false, { "", "--- exec: " .. instruction:sub(1, 50) .. " ---", "" })

  local input = {}
  ctx.with_agent_instructions(input, "exec")
  ctx.with_scope_contract(input)
  ctx.with_quickfix(input)
  ctx.with_workbench(input)
  ctx.with_visible(input)

  ctx.show_workbench()

  stream.to_buf(input, workbench, {
    cmd = cmd,
    stderr_to_buf = true,
    on_done = function()
      if vim.api.nvim_buf_is_valid(workbench) then
        vim.api.nvim_buf_set_lines(workbench, -1, -1, false, { "", "---", "", "" })
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
  vim.api.nvim_set_option_value("statusline", " 🗺 discover │ analyzing...", { win = win })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})

  vim.schedule(function()
    stream.to_buf(input, buf, {
      cmd = config.checker_cmd(),
      on_done = function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        vim.fn.writefile(vim.api.nvim_buf_get_lines(buf, 0, -1, false), discovery_file)
        vim.cmd("edit!")
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_set_option_value("statusline", " 🗺 discover │ done │ gf to navigate", { win = win })
        end
      end,
    })
  end)
end

-- improve prompt

local function improve_prompt()
  local buf_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  if #buf_lines == 0 or (#buf_lines == 1 and buf_lines[1] == "") then
    vim.notify("cogcog: nothing to improve from", vim.log.levels.WARN)
    return
  end
  vim.ui.input({ prompt = " what was wrong: " }, function(feedback)
    if not feedback or vim.trim(feedback) == "" then return end
    local sys_file = config.cogcog_dir .. "/system.md"
    local input = {
      "You are a prompt engineer. Bad response below. User feedback follows.",
      "", "Current system prompt:", vim.fn.filereadable(sys_file) == 1 and table.concat(vim.fn.readfile(sys_file), "\n") or "",
      "", "Bad response:", table.concat(buf_lines, "\n"),
      "", "Feedback:", feedback,
      "", "Write ONE instruction to add to the system prompt. Output ONLY the instruction.",
    }
    local tmp_buf = vim.api.nvim_create_buf(false, true)
    stream.to_buf(input, tmp_buf, {
      raw = true,
      on_done = function()
        if not vim.api.nvim_buf_is_valid(tmp_buf) then return end
        local result = vim.api.nvim_buf_get_lines(tmp_buf, 0, -1, false)
        vim.api.nvim_buf_delete(tmp_buf, { force = true })
        local improvement = vim.trim(table.concat(result, "\n"))
        if improvement == "" then return end
        vim.fn.mkdir(config.cogcog_dir, "p")
        local existing = vim.fn.filereadable(sys_file) == 1 and vim.fn.readfile(sys_file) or {}
        table.insert(existing, improvement)
        vim.fn.writefile(existing, sys_file)
        vim.notify("cogcog: +" .. improvement:sub(1, 60), vim.log.levels.INFO)
      end,
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
vim.keymap.set("n", "gaa", function()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  if #lines > 0 then ask(lines, ctx.relative_name(vim.api.nvim_buf_get_name(0))) end
end, { desc = "cogcog: ask about buffer" })

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
  if ctx.is_workbench() then
    -- in workbench: send the current workbench as-is
    plan_send(nil)
  else
    local cur_file = ctx.relative_name(vim.api.nvim_buf_get_name(0))
    local hint = cur_file ~= "scratch" and " (in " .. cur_file .. ")" or ""
    vim.ui.input({ prompt = " plan" .. hint .. ": " }, function(q)
      if not q or vim.trim(q) == "" then return end
      if cur_file ~= "scratch" then
        q = "[working in " .. cur_file .. "] " .. q
      end
      plan_send(q)
    end)
  end
end, { desc = "cogcog: plan / continue" })

vim.keymap.set("v", "<leader>cy", function()
  ctx.visual_then(function(lines, source)
    local workbench = ctx.get_or_create_workbench()
    vim.api.nvim_buf_set_lines(workbench, -1, -1, false, { "", "--- " .. source .. " ---", "" })
    vim.api.nvim_buf_set_lines(workbench, -1, -1, false, lines)
    vim.notify("📌 pinned to workbench")
  end)
end, { desc = "cogcog: pin" })

vim.keymap.set("n", "<leader>co", function()
  if ctx.workbench_win() then vim.api.nvim_win_close(ctx.workbench_win(), false) else ctx.show_workbench() end
end, { desc = "cogcog: workbench" })

vim.keymap.set("n", "<leader>gj", function()
  local input = {}
  ctx.with_system(input)
  ctx.with_jumps(input, 8)
  table.insert(input, "How do these code locations connect? What's the flow?")
  local buf = ctx.reuse_or_split("[cogcog-ask]", " 🔗 jumps │ investigation trail")
  stream.to_buf(input, buf, { raw = true })
end, { desc = "cogcog: jump trail" })

vim.keymap.set("n", "<leader>g.", function()
  local input = {}
  ctx.with_system(input)
  ctx.with_changes(input)
  table.insert(input, "I made these changes. Any bugs or issues?")
  local buf = ctx.reuse_or_split("[cogcog-ask]", " 📝 changes │ review edits")
  stream.to_buf(input, buf, { raw = true })
end, { desc = "cogcog: review changes" })

local function quickfix_flow(prompt, title)
  local qf = vim.fn.getqflist()
  if #qf == 0 then
    vim.notify("cogcog: quickfix is empty", vim.log.levels.WARN)
    return
  end
  local input = {}
  ctx.with_system(input)
  ctx.with_scope_contract(input)
  ctx.with_quickfix(input)
  ctx.with_visible(input)
  table.insert(input, prompt)
  local buf = ctx.reuse_or_split("[cogcog-quickfix]", title)
  stream.to_buf(input, buf, { raw = true })
end

local function quickfix_target_label(target)
  return target.file .. ":" .. target.start .. "-" .. target.stop
end

local function append_report(buf, lines)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, lines)
  end
end

local function build_quickfix_rewrite_input(target, instruction)
  local snippet = vim.api.nvim_buf_get_lines(target.bufnr, target.start - 1, target.stop, false)
  local input = {}
  ctx.with_system(input)
  ctx.with_scope_contract(input)
  ctx.with_workbench(input)
  table.insert(input, "This is one explicit snippet from the active quickfix target set.")
  table.insert(input, "Only rewrite the snippet below for this target.")
  table.insert(input, "")
  if target.hints and #target.hints > 0 then
    table.insert(input, "--- quickfix hints ---")
    for _, hint in ipairs(target.hints) do
      table.insert(input, target.file .. ":" .. hint.lnum .. ": " .. hint.text)
    end
    table.insert(input, "")
  end
  ctx.with_selection(input, snippet, quickfix_target_label(target))
  table.insert(input, instruction)
  table.insert(input, "")
  table.insert(input, "Rewrite ONLY the snippet above for this quickfix target.")
  table.insert(input, "Output ONLY the rewritten content. No explanations, no markdown fences.")
  return input, snippet
end

local function normalize_rewrite_result(result)
  result = ctx.strip_code_fences(result)
  while #result > 0 and vim.trim(result[1]) == "" do table.remove(result, 1) end
  while #result > 0 and vim.trim(result[#result]) == "" do table.remove(result) end
  if #result == 0 then return nil, "empty result" end

  local text = table.concat(result, " ")
  if #result <= 2 and (text:match("I do not") or text:match("I cannot") or text:match("I can't")) then
    return nil, "model refused"
  end
  return result
end

local function render_quickfix_rewrite_review(review_buf, instruction, changes, skipped, failures)
  local lines = {
    "# Quickfix rewrite review",
    "",
    "Instruction: " .. instruction,
    "Ready changes: " .. tostring(#changes),
    "Skipped: " .. tostring(skipped),
    "Failed: " .. tostring(#failures),
    "",
  }

  if #changes > 0 then
    table.insert(lines, "Press `a` to apply all prepared rewrites, `q` to close.")
  else
    table.insert(lines, "Nothing to apply. Press `q` to close.")
  end
  table.insert(lines, "")

  if #failures > 0 then
    table.insert(lines, "## Failures")
    table.insert(lines, "")
    vim.list_extend(lines, failures)
    table.insert(lines, "")
  end

  for _, change in ipairs(changes) do
    table.insert(lines, "## " .. quickfix_target_label(change.target))
    table.insert(lines, "")
    if change.target.hints and #change.target.hints > 0 then
      table.insert(lines, "Hints:")
      for _, hint in ipairs(change.target.hints) do
        table.insert(lines, "- " .. change.target.file .. ":" .. hint.lnum .. ": " .. hint.text)
      end
      table.insert(lines, "")
    end
    vim.list_extend(lines, ctx.unified_diff(change.original, change.result))
    table.insert(lines, "")
  end

  vim.api.nvim_buf_set_lines(review_buf, 0, -1, false, lines)
end

local function apply_quickfix_rewrite_changes(changes, review_buf, review_win)
  local applied, failed = 0, 0
  local failures = {}

  for _, change in ipairs(changes) do
    local target = change.target
    if not vim.api.nvim_buf_is_valid(target.bufnr) then
      failed = failed + 1
      table.insert(failures, "- " .. quickfix_target_label(target) .. " failed: buffer is no longer valid")
    else
      local current = vim.api.nvim_buf_get_lines(target.bufnr, target.start - 1, target.stop, false)
      if not ctx.same_lines(current, change.original) then
        failed = failed + 1
        table.insert(failures, "- " .. quickfix_target_label(target) .. " failed: target changed since review")
      else
        vim.api.nvim_buf_set_lines(target.bufnr, target.start - 1, target.stop, false, change.result)
        applied = applied + 1
      end
    end
  end

  append_report(review_buf, {
    "## Apply result",
    "",
    "Applied: " .. applied,
    "Failed: " .. failed,
    "",
  })
  if #failures > 0 then
    append_report(review_buf, failures)
    append_report(review_buf, { "" })
  end

  pcall(vim.keymap.del, "n", "a", { buffer = review_buf })
  if vim.api.nvim_win_is_valid(review_win) then
    vim.api.nvim_set_option_value("statusline", " ✍ quickfix review │ applied │ q close", { win = review_win })
  end
  vim.notify("cogcog: quickfix rewrite applied (" .. applied .. " applied, " .. failed .. " failed)")
end

local function quickfix_rewrite(instruction)
  local targets = ctx.get_quickfix_targets(2)
  if #targets == 0 then
    vim.notify("cogcog: quickfix is empty", vim.log.levels.WARN)
    return
  end

  local review_buf, review_win = ctx.reuse_or_split("[cogcog-quickfix-review]", " 👀 quickfix │ preparing review")
  vim.api.nvim_buf_set_lines(review_buf, 0, -1, false, {
    "# Quickfix rewrite review",
    "",
    "Instruction: " .. instruction,
    "Targets: " .. tostring(#targets),
    "",
    "Preparing review...",
  })
  if vim.api.nvim_win_is_valid(review_win) then
    vim.api.nvim_set_option_value("wrap", false, { win = review_win })
    vim.api.nvim_set_option_value("statusline", " 👀 quickfix │ preparing review", { win = review_win })
    vim.api.nvim_set_current_win(review_win)
  end

  local changes, failures = {}, {}
  local skipped = 0

  local function finish()
    render_quickfix_rewrite_review(review_buf, instruction, changes, skipped, failures)
    if #changes > 0 then
      vim.keymap.set("n", "a", function()
        apply_quickfix_rewrite_changes(changes, review_buf, review_win)
      end, { buffer = review_buf, desc = "cogcog: apply quickfix review" })
      if vim.api.nvim_win_is_valid(review_win) then
        vim.api.nvim_set_option_value("statusline", " 👀 quickfix review │ a apply │ q close", { win = review_win })
      end
    else
      pcall(vim.keymap.del, "n", "a", { buffer = review_buf })
      if vim.api.nvim_win_is_valid(review_win) then
        vim.api.nvim_set_option_value("statusline", " 👀 quickfix review │ q close", { win = review_win })
      end
    end
    vim.notify("cogcog: quickfix review ready (" .. #changes .. " changes, " .. skipped .. " skipped, " .. #failures .. " failed)")
  end

  local function process(index)
    if index > #targets then
      finish()
      return
    end

    local target = targets[index]
    if not vim.api.nvim_buf_is_valid(target.bufnr) then
      table.insert(failures, "- " .. quickfix_target_label(target) .. " failed: buffer is no longer valid")
      append_report(review_buf, { "- " .. quickfix_target_label(target) .. " failed: buffer is no longer valid", "" })
      process(index + 1)
      return
    end

    local input, original = build_quickfix_rewrite_input(target, instruction)
    local tmp_buf = vim.api.nvim_create_buf(false, true)
    append_report(review_buf, { "- preparing " .. quickfix_target_label(target) })

    stream.to_buf(input, tmp_buf, {
      raw = true,
      on_done = function()
        if not vim.api.nvim_buf_is_valid(tmp_buf) then
          table.insert(failures, "- " .. quickfix_target_label(target) .. " failed: temporary result buffer vanished")
          append_report(review_buf, { "  failed: temporary result buffer vanished", "" })
          process(index + 1)
          return
        end

        local result = vim.api.nvim_buf_get_lines(tmp_buf, 0, -1, false)
        vim.api.nvim_buf_delete(tmp_buf, { force = true })
        local err
        result, err = normalize_rewrite_result(result)

        if not result then
          table.insert(failures, "- " .. quickfix_target_label(target) .. " failed: " .. err)
          append_report(review_buf, { "  failed: " .. err, "" })
          process(index + 1)
          return
        end

        if ctx.same_lines(original, result) then
          skipped = skipped + 1
          append_report(review_buf, { "  - no change for " .. quickfix_target_label(target), "" })
          process(index + 1)
          return
        end

        table.insert(changes, { target = target, original = original, result = result })
        append_report(review_buf, {
          "  ✓ prepared " .. quickfix_target_label(target) .. " (" .. #original .. " lines → " .. #result .. ")",
          "",
        })
        process(index + 1)
      end,
      on_error = function(code)
        if vim.api.nvim_buf_is_valid(tmp_buf) then
          vim.api.nvim_buf_delete(tmp_buf, { force = true })
        end
        table.insert(failures, "- " .. quickfix_target_label(target) .. " failed: backend exit " .. tostring(code))
        append_report(review_buf, { "  failed: backend exit " .. tostring(code), "" })
        process(index + 1)
      end,
    })
  end

  process(1)
end

vim.keymap.set("n", "<leader>gq", function()
  quickfix_flow(
    "Summarize the current quickfix target set. Group related entries and explain the likely work.",
    " 📋 quickfix │ summarize target set"
  )
end, { desc = "cogcog: summarize quickfix" })

vim.keymap.set("n", "<leader>gQ", function()
  quickfix_flow(
    "Review the current quickfix target set. Highlight the most important issues and likely fixes.",
    " 🧭 quickfix │ review target set"
  )
end, { desc = "cogcog: review quickfix" })

vim.keymap.set("n", "<leader>gR", function()
  local targets = ctx.get_quickfix_targets(2)
  if #targets == 0 then
    vim.notify("cogcog: quickfix is empty", vim.log.levels.WARN)
    return
  end
  vim.ui.input({ prompt = " quickfix rewrite (" .. #targets .. " targets): " }, function(instruction)
    if not instruction or vim.trim(instruction) == "" then return end
    vim.ui.select({ "Apply", "Cancel" }, { prompt = "Apply rewrite to current quickfix targets?" }, function(choice)
      if choice == "Apply" then
        quickfix_rewrite(instruction)
      end
    end)
  end)
end, { desc = "cogcog: rewrite quickfix" })

vim.keymap.set("n", "<leader>gx", function()
  local cur_file = ctx.relative_name(vim.api.nvim_buf_get_name(0))
  local hint = cur_file ~= "scratch" and " (in " .. cur_file .. ")" or ""
  vim.ui.input({ prompt = " do" .. hint .. ": " }, function(instruction)
    if not instruction or vim.trim(instruction) == "" then return end
    if cur_file ~= "scratch" then
      instruction = "[working in " .. cur_file .. "] " .. instruction
    end
    exec_send(instruction)
  end)
end, { desc = "cogcog: execute" })

vim.keymap.set("n", "<leader>cd", function()
  local f = config.discovery_file
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
  local workbench = ctx.get_or_create_workbench()
  vim.api.nvim_buf_set_lines(workbench, 0, -1, false, {})
  vim.fn.delete(config.workbench_file)
  vim.fn.delete(config.legacy_session_file)
  vim.notify("🗑 workbench cleared")
end, { desc = "cogcog: clear workbench" })

vim.keymap.set({ "n", "i" }, "<C-c>", function()
  if next(stream.active_jobs) then
    stream.cancel_all()
  else
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-c>", true, false, true), "n", false)
  end
end, { desc = "cogcog: cancel" })

-- workbench restore notification
if config.readable_workbench_file() then
  vim.schedule(function()
    vim.notify("cogcog: workbench found (<leader>co to restore)", vim.log.levels.INFO)
  end)
end

-- workbench persistence
vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if ctx.is_workbench(buf) then
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        if #lines > 1 or (#lines == 1 and lines[1] ~= "") then
          vim.fn.mkdir(vim.fn.fnamemodify(config.workbench_file, ":h"), "p")
          vim.fn.writefile(lines, config.workbench_file)
          vim.fn.delete(config.legacy_session_file)
        else
          vim.fn.delete(config.workbench_file)
          vim.fn.delete(config.legacy_session_file)
        end
        return
      end
    end
  end,
})
