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

local tool_mode = vim.g.cogcog_tool_mode or "ask"  -- "ask" | "read" | "trust"

local builtin_tools = {
  read_file = function(args)
    local path = args:match('^"(.-)"') or args:match("^'(.-)'") or args
    if not path or path == "" then return "error: no path given" end
    local lines = vim.fn.readfile(path, "", 500)
    if #lines == 0 and vim.fn.filereadable(path) == 0 then return "error: file not found: " .. path end
    return table.concat(lines, "\n")
  end,
  list_files = function(args)
    local dir = args:match('^"(.-)"') or args:match("^'(.-)'") or args
    if not dir or dir == "" then dir = "." end
    local out = vim.fn.systemlist("find " .. vim.fn.shellescape(dir) .. " -maxdepth 2 -not -path '*/.*' -type f 2>/dev/null | head -100 | sort")
    return #out > 0 and table.concat(out, "\n") or "error: empty or not found: " .. dir
  end,
  grep = function(args)
    local pattern, path = args:match('^"(.-)",%s*"(.-)"')
    if not pattern then pattern = args:match('^"(.-)"') or args; path = "." end
    if not path or path == "" then path = "." end
    local out = vim.fn.systemlist("grep -rn " .. vim.fn.shellescape(pattern) .. " " .. vim.fn.shellescape(path) .. " 2>/dev/null | head -50")
    return #out > 0 and table.concat(out, "\n") or "no matches"
  end,
  run_command = function(args)
    local cmd = args:match('^"(.-)"') or args:match("^'(.-)'") or args
    if not cmd or cmd == "" then return "error: no command given" end
    local out = vim.fn.systemlist(cmd)
    local code = vim.v.shell_error
    local result = table.concat(out, "\n")
    if code ~= 0 then result = result .. "\n(exit " .. code .. ")" end
    return result
  end,
  diagnostics = function()
    local diags = vim.diagnostic.get()
    if #diags == 0 then return "no diagnostics" end
    local out = {}
    for _, d in ipairs(diags) do
      local fname = vim.api.nvim_buf_is_valid(d.bufnr) and vim.fn.fnamemodify(vim.api.nvim_buf_get_name(d.bufnr), ":.") or "?"
      local sev = ({ "ERROR", "WARN", "INFO", "HINT" })[d.severity] or "?"
      table.insert(out, fname .. ":" .. (d.lnum + 1) .. " [" .. sev .. "] " .. d.message)
    end
    return table.concat(out, "\n")
  end,
  lsp_symbols = function(args)
    local path = args:match('^"(.-)"') or args:match("^'(.-)'") or args
    local bufnr
    if path and path ~= "" then
      bufnr = vim.fn.bufadd(path)
      vim.fn.bufload(bufnr)
    else
      bufnr = vim.api.nvim_get_current_buf()
    end
    local params = { textDocument = vim.lsp.util.make_text_document_params(bufnr) }
    local results = vim.lsp.buf_request_sync(bufnr, "textDocument/documentSymbol", params, 3000)
    if not results then return "no LSP response" end
    local out = {}
    local function collect(symbols, indent)
      for _, s in ipairs(symbols) do
        local kind = vim.lsp.protocol.SymbolKind[s.kind] or "?"
        table.insert(out, string.rep("  ", indent) .. kind .. " " .. s.name .. " :" .. (s.range.start.line + 1))
        if s.children then collect(s.children, indent + 1) end
      end
    end
    for _, r in pairs(results) do
      if r.result then collect(r.result, 0) end
    end
    return #out > 0 and table.concat(out, "\n") or "no symbols found"
  end,
  buffers = function()
    local out = {}
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(b) then
        local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ":.")
        if name ~= "" then
          local mod = vim.bo[b].modified and " [+]" or ""
          table.insert(out, name .. mod)
        end
      end
    end
    return #out > 0 and table.concat(out, "\n") or "no named buffers"
  end,
  kb_search = function(args)
    local query = args:match('^"(.-)"') or args:match("^'(.-)'") or args
    if not query or query == "" then return "error: no query given" end
    local results = ctx.kb_search(query, 5)
    if not results then return "no knowledge base configured (set COGCOG_KB)" end
    if #results == 0 then return "no results for: " .. query end
    local out = {}
    for _, r in ipairs(results) do
      table.insert(out, "## " .. r.title)
      table.insert(out, r.path)
      table.insert(out, r.snippet)
      table.insert(out, "")
    end
    return table.concat(out, "\n")
  end,
}

local function is_read_only_tool(name)
  return name == "read_file" or name == "list_files" or name == "grep"
    or name == "diagnostics" or name == "lsp_symbols" or name == "buffers"
    or name == "kb_search"
end

local function execute_tool(name, args)
  -- check builtins first
  if builtin_tools[name] then return builtin_tools[name](args) end
  -- check .cogcog/tools/
  if name:match("^tool:") then
    local script_name = name:gsub("^tool:", "")
    local script_path = config.cogcog_dir .. "/tools/" .. script_name
    if vim.fn.filereadable(script_path) == 1 then
      if script_name:match("%.lua$") then
        local ok, result = pcall(dofile, script_path)
        if not ok then return "error: " .. tostring(result) end
        if type(result) == "function" then
          ok, result = pcall(result)
          if not ok then return "error: " .. tostring(result) end
        end
        return tostring(result or "")
      else
        local out = vim.fn.systemlist({ "bash", script_path })
        local code = vim.v.shell_error
        local result = table.concat(out, "\n")
        if code ~= 0 then result = result .. "\n(exit " .. code .. ")" end
        return result
      end
    end
    return "error: tool not found: " .. script_name
  end
  return "error: unknown tool: " .. name
end

local function parse_tool_call(lines)
  for i = #lines, 1, -1 do
    local name, args = lines[i]:match("^<<<TOOL:%s*([%w_:%.%-]+)%((.*)%)>>>$")
    if name then
      return name, args, i
    end
  end
  return nil
end

local function build_plan_message()
  local input = {}
  ctx.with_agent_instructions(input, "plan")
  ctx.with_scope_contract(input)
  ctx.with_quickfix(input)
  ctx.with_workbench(input)
  ctx.with_visible(input)
  return table.concat(input, "\n")
end

local function plan_send(question)
  local workbench = ctx.get_or_create_workbench()
  if question then
    vim.api.nvim_buf_set_lines(workbench, -1, -1, false, { "", question, "" })
  end
  ctx.show_workbench()

  local rpc = require("cogcog.pi_rpc")
  if not rpc.ensure_started(workbench, config.pi_rpc_cmd()) then return end
  local message = build_plan_message()
  if rpc.is_busy() then rpc.steer(message) else rpc.prompt(message) end
end

-- exec (gx): cloud agent, anchored by workbench + visible state

local function exec_send(instruction)
  local workbench = ctx.get_or_create_workbench()

  vim.api.nvim_buf_set_lines(workbench, -1, -1, false, { "", "--- exec: " .. instruction:sub(1, 50) .. " ---", "" })

  local input = {}
  ctx.with_agent_instructions(input, "exec")
  ctx.with_scope_contract(input)
  ctx.with_quickfix(input)
  ctx.with_workbench(input)
  ctx.with_visible(input)

  ctx.show_workbench()

  local rpc = require("cogcog.pi_rpc")
  if not rpc.ensure_started(workbench, config.pi_rpc_cmd()) then return end
  local message = table.concat(input, "\n")
  if rpc.is_busy() then rpc.steer(message) else rpc.prompt(message) end
end

-- discover

local function do_discover(discovery_file, update)
  vim.fn.mkdir(config.cogcog_dir, "p")

  -- extension → treesitter language (bufload doesn't trigger filetype detection)
  local ext_to_lang = {
    lua = "lua", ts = "typescript", tsx = "tsx", js = "javascript", jsx = "javascript",
    py = "python", go = "go", rs = "rust", zig = "zig", rb = "ruby",
    java = "java", c = "c", cpp = "cpp", h = "c",
  }

  -- ── pre-compute stats ─────────────────────────────────────────
  local project_name = vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
  local git_branch = vim.fn.systemlist("git branch --show-current 2>/dev/null")[1] or ""
  local git_commit_count = vim.fn.systemlist("git rev-list --count HEAD 2>/dev/null")[1] or "?"
  local git_last_commit = vim.fn.systemlist("git log -1 --format='%h %s (%cr)' 2>/dev/null")[1] or ""
  local git_contributors = vim.fn.systemlist("git shortlog -sn --no-merges HEAD 2>/dev/null | wc -l")[1] or "?"
  local total_files = vim.trim(vim.fn.systemlist([[find . -maxdepth 4 -type f -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/vendor/*' -not -path '*/target/*' -not -path '*/dist/*' -not -path '*/build/*' -not -path '*/__pycache__/*' 2>/dev/null | wc -l]])[1] or "?")
  local loc_raw = vim.fn.systemlist([[find . -maxdepth 4 -type f \( -name '*.lua' -o -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' -o -name '*.py' -o -name '*.go' -o -name '*.rs' -o -name '*.zig' -o -name '*.rb' -o -name '*.java' -o -name '*.c' -o -name '*.cpp' -o -name '*.h' \) -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/vendor/*' 2>/dev/null | xargs wc -l 2>/dev/null | tail -1]])[1] or ""
  local total_loc = loc_raw:match("^%s*(%d+)") or "?"

  local file_counts_raw = vim.fn.systemlist([[find . -maxdepth 4 -type f -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/vendor/*' -not -path '*/target/*' -not -path '*/dist/*' -not -path '*/build/*' -not -path '*/__pycache__/*' 2>/dev/null | sed 's/.*\.//' | sort | uniq -c | sort -rn | head -10]])

  local manifest_name = vim.fn.glob("package.json") ~= "" and "package.json"
    or vim.fn.glob("Cargo.toml") ~= "" and "Cargo.toml"
    or vim.fn.glob("go.mod") ~= "" and "go.mod"
    or vim.fn.glob("pyproject.toml") ~= "" and "pyproject.toml"
    or nil
  local manifest_content = manifest_name and vim.fn.readfile(manifest_name, "", 30) or {}

  local diags = vim.diagnostic.get()
  local diag_counts = { 0, 0, 0, 0 }
  for _, d in ipairs(diags) do diag_counts[d.severity] = (diag_counts[d.severity] or 0) + 1 end

  -- ── stats block (rendered in Lua, model keeps verbatim) ───────
  local header = { "# 📋 " .. project_name, "" }
  table.insert(header, "```")
  if git_branch ~= "" then table.insert(header, "🔀 " .. git_branch) end
  table.insert(header, "📁 " .. total_files .. " files   📏 " .. total_loc .. " LOC")
  local git_line = {}
  if git_commit_count ~= "?" then table.insert(git_line, "📝 " .. vim.trim(git_commit_count) .. " commits") end
  if vim.trim(git_contributors or "") ~= "" and vim.trim(git_contributors) ~= "0" then
    table.insert(git_line, "👥 " .. vim.trim(git_contributors))
  end
  if #git_line > 0 then table.insert(header, table.concat(git_line, "   ")) end
  if git_last_commit ~= "" then table.insert(header, "🕐 " .. git_last_commit) end
  if #diags > 0 then
    table.insert(header, "🩺 ❌" .. diag_counts[1] .. " ⚠️" .. diag_counts[2] .. " ℹ️" .. diag_counts[3] .. " 💡" .. diag_counts[4])
  end
  -- file type breakdown
  local types = {}
  for _, line in ipairs(file_counts_raw) do
    local count, ext = line:match("^%s*(%d+)%s+(%S+)")
    if count and ext then table.insert(types, ext .. ":" .. count) end
  end
  if #types > 0 then table.insert(header, "📊 " .. table.concat(types, "  ")) end
  table.insert(header, "```")
  table.insert(header, "")

  -- ── raw data for model ────────────────────────────────────────
  local input = {}
  vim.list_extend(input, header)

  -- tree
  local tree = vim.fn.systemlist("tree -L 3 --noreport --dirsfirst -I 'node_modules|.git|__pycache__|target|dist|build|zig-cache|zig-out|vendor|.next' 2>/dev/null || find . -maxdepth 3 -not -path '*/.git/*' | head -80")
  if #tree > 0 then
    table.insert(input, "--- raw: file tree ---")
    vim.list_extend(input, tree)
    table.insert(input, "")
  end

  if #manifest_content > 0 then
    table.insert(input, "--- raw: " .. manifest_name .. " ---")
    vim.list_extend(input, manifest_content)
    table.insert(input, "")
  end

  local entries = vim.fn.systemlist([[head -50 $(find . -maxdepth 2 -type f \( -name 'main.*' -o -name 'index.*' -o -name 'app.*' \) -not -path '*node_modules*' -not -path '*/.git/*' 2>/dev/null | head -5) 2>/dev/null]])
  if #entries > 0 then
    table.insert(input, "--- raw: entry points ---")
    vim.list_extend(input, entries)
    table.insert(input, "")
  end

  local gitlog = vim.fn.systemlist("git log --oneline -20 2>/dev/null")
  if #gitlog > 0 then
    table.insert(input, "--- raw: git log ---")
    vim.list_extend(input, gitlog)
    table.insert(input, "")
  end

  local readme = vim.fn.systemlist("head -60 README.md 2>/dev/null || head -60 README 2>/dev/null")
  if #readme > 0 then
    table.insert(input, "--- raw: README ---")
    vim.list_extend(input, readme)
    table.insert(input, "")
  end

  -- ── treesitter declarations ───────────────────────────────────
  local ts_lines = {}
  local ts_file_count = 0
  local src_files = vim.fn.systemlist("find . -maxdepth 3 -type f \\( -name '*.lua' -o -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' -o -name '*.py' -o -name '*.go' -o -name '*.rs' -o -name '*.zig' \\) -not -path '*node_modules*' -not -path '*/.git/*' -not -path '*/vendor/*' -not -path '*/dist/*' -not -path '*/build/*' 2>/dev/null | head -40")
  for _, file in ipairs(src_files) do
    local ext = file:match("%.(%w+)$")
    local lang = ext and ext_to_lang[ext]
    if lang and pcall(vim.treesitter.language.inspect, lang) then
      local bufnr = vim.fn.bufadd(file)
      vim.fn.bufload(bufnr)
      local ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
      if ok and parser then
        local trees = parser:parse()
        if trees and trees[1] then
          local root = trees[1]:root()
          local decls = {}
          for child in root:iter_children() do
            local ntype = child:type()
            if ntype:match("function") or ntype:match("class") or ntype:match("struct")
              or ntype:match("impl") or ntype:match("interface") or ntype:match("type_alias")
              or ntype:match("method") or ntype:match("enum")
              or ntype:match("export") or ntype:match("variable_declaration")
              or ntype:match("lexical_declaration") then
              local row = child:start()
              local line = (vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""):gsub("{%s*$", ""):gsub("%s+$", "")
              if #line > 100 then line = line:sub(1, 97) .. "..." end
              if line ~= "" then table.insert(decls, "  :" .. (row + 1) .. "  " .. line) end
            end
          end
          if #decls > 0 then
            ts_file_count = ts_file_count + 1
            table.insert(ts_lines, file .. ":")
            vim.list_extend(ts_lines, decls)
          end
        end
      end
    end
  end
  if #ts_lines > 0 then
    table.insert(input, "--- raw: treesitter (" .. ts_file_count .. " files parsed) ---")
    vim.list_extend(input, ts_lines)
    table.insert(input, "")
  end

  -- ── LSP symbols (only from already-open buffers with LSP) ─────
  local lsp_lines = {}
  local lsp_buf_count = 0
  if #vim.lsp.get_clients() > 0 then
    local seen = {}
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buftype == "" then
        local bname = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ":.")
        if bname ~= "" and not seen[bname] then
          seen[bname] = true
          local params = { textDocument = vim.lsp.util.make_text_document_params(b) }
          local results = vim.lsp.buf_request_sync(b, "textDocument/documentSymbol", params, 2000)
          if results then
            local syms = {}
            local function collect_s(symbols, indent)
              for _, s in ipairs(symbols) do
                local kind = vim.lsp.protocol.SymbolKind[s.kind] or "?"
                table.insert(syms, string.rep("  ", indent + 1) .. kind .. " " .. s.name)
                if s.children and indent < 1 then collect_s(s.children, indent + 1) end
              end
            end
            for _, r in pairs(results) do
              if r.result and #r.result > 0 then collect_s(r.result, 0) end
            end
            if #syms > 0 then
              lsp_buf_count = lsp_buf_count + 1
              table.insert(lsp_lines, bname .. ":")
              vim.list_extend(lsp_lines, syms)
            end
          end
        end
      end
    end
  end
  if #lsp_lines > 0 then
    table.insert(input, "--- raw: LSP symbols (" .. lsp_buf_count .. " buffers) ---")
    vim.list_extend(input, lsp_lines)
    table.insert(input, "")
  end

  -- ── knowledge base (Obsidian CLI → grep fallback, no LLM) ────
  local kb = config.kb_path()
  local kb_pages = {}
  if kb and vim.fn.isdirectory(kb .. "/wiki") == 1 then
    -- build search terms from project context
    local terms = { project_name }
    if manifest_name then
      for _, line in ipairs(manifest_content) do
        local n = line:match('"name"%s*:%s*"(.-)"') or line:match('^name%s*=%s*"(.-)"') or line:match('^module%s+(%S+)')
        if n then
          local clean = n:gsub(".*/", "")
          table.insert(terms, clean)
          break
        end
      end
    end
    for _, line in ipairs(readme or {}) do
      for w in line:gmatch("%w+") do
        if #w > 4 then table.insert(terms, w) end
      end
      if #terms > 15 then break end
    end
    local query = table.concat(terms, " ")

    -- try Obsidian CLI first (requires running Obsidian app)
    local vault_name = vim.fn.fnamemodify(kb, ":t")
    local obs_raw = ""
    if vim.fn.executable("obsidian") == 1 then
      obs_raw = vim.fn.system("obsidian search query=" .. vim.fn.shellescape(query)
        .. " vault=" .. vim.fn.shellescape(vault_name)
        .. " path=wiki limit=8 format=json 2>/dev/null")
    end
    local obs_paths = {}
    if obs_raw ~= "" then
      local ok, parsed = pcall(vim.json.decode, obs_raw)
      if ok and type(parsed) == "table" then
        for _, hit in ipairs(parsed) do
          local p = type(hit) == "table" and (hit.path or hit.file) or hit
          if type(p) == "string" then table.insert(obs_paths, p) end
        end
      end
    end

    -- fallback: grep wiki for each term
    if #obs_paths == 0 then
      local seen = {}
      for _, term in ipairs(terms) do
        local hits = vim.fn.systemlist("grep -rli " .. vim.fn.shellescape(term)
          .. " " .. vim.fn.shellescape(kb .. "/wiki") .. " 2>/dev/null | head -4")
        for _, h in ipairs(hits) do
          if not seen[h] then
            seen[h] = true
            table.insert(obs_paths, h)
          end
        end
        if #obs_paths >= 8 then break end
      end
    end

    -- read actual content of found pages (not just snippets)
    for _, p in ipairs(obs_paths) do
      local full = p
      if vim.fn.filereadable(full) == 0 then full = kb .. "/" .. p end
      if vim.fn.filereadable(full) == 0 then full = kb .. "/wiki/" .. p end
      if vim.fn.filereadable(full) == 1 then
        local lines = vim.fn.readfile(full, "", 40)
        local title = ""
        local content = {}
        local in_fm = false
        for _, line in ipairs(lines) do
          if line == "---" then
            in_fm = not in_fm
          elseif in_fm then
            local t = line:match('^title:%s*"?(.-)"?%s*$')
            if t and t ~= "" and title == "" then title = t end
          else
            table.insert(content, line)
          end
        end
        local rel = full:gsub("^" .. vim.pesc(kb) .. "/?", "")
        if title == "" then title = rel:gsub("%.md$", ""):gsub("/", " > ") end
        table.insert(kb_pages, {
          path = rel,
          title = title,
          content = table.concat(content, "\n"),
        })
      end
      if #kb_pages >= 8 then break end
    end

    if #kb_pages > 0 then
      table.insert(input, "--- raw: knowledge base (" .. #kb_pages .. " pages) ---")
      for _, page in ipairs(kb_pages) do
        table.insert(input, "📚 " .. page.title .. " (" .. page.path .. ")")
        if page.content ~= "" then table.insert(input, page.content) end
        table.insert(input, "")
      end
      vim.notify("📚 KB: " .. #kb_pages .. " pages" .. (#obs_paths > 0 and vim.fn.executable("obsidian") == 1 and " (obsidian)" or " (grep)"), vim.log.levels.INFO)
    end
  end

  -- ── sources summary ───────────────────────────────────────────
  local sources = { "tree", "git" }
  if #manifest_content > 0 then table.insert(sources, manifest_name) end
  if #ts_lines > 0 then table.insert(sources, "treesitter(" .. ts_file_count .. ")") end
  if #lsp_lines > 0 then table.insert(sources, "lsp(" .. lsp_buf_count .. ")") end
  if #kb_pages > 0 then table.insert(sources, "kb(" .. #kb_pages .. ")") end
  if #diags > 0 then table.insert(sources, "diagnostics") end

  -- ── prompt ────────────────────────────────────────────────────
  if update and vim.fn.filereadable(discovery_file) == 1 then
    table.insert(input, "--- previous discovery ---")
    vim.list_extend(input, vim.fn.readfile(discovery_file))
    table.insert(input, "")
    table.insert(input, "UPDATE this dashboard. Keep the ``` stats block verbatim. Rewrite all sections below using the raw data above.")
    table.insert(input, "For the Team Knowledge section: extract SPECIFIC insights from KB page content — not just page titles in a table.")
    table.insert(input, "Output ONLY the dashboard. No preamble.")
  else
    table.insert(input, "")
    table.insert(input, "The ``` stats block above is pre-computed. Keep it EXACTLY as-is at the top.")
    table.insert(input, "Below it, write these sections. Use ONLY data from the raw sections above.")
    table.insert(input, "")
    table.insert(input, "## 🏗 Architecture")
    table.insert(input, "2-3 sentences. Then an ASCII flow diagram in a ``` block.")
    table.insert(input, "")
    table.insert(input, "## 📦 Modules")
    table.insert(input, "### SubsystemName")
    table.insert(input, "| File | Role |")
    table.insert(input, "|------|------|")
    table.insert(input, "| `path/file` | what it does |")
    table.insert(input, "Key declarations (from treesitter if available):")
    table.insert(input, "- `FunctionOrType` — purpose")
    table.insert(input, "(repeat ### for each subsystem)")
    table.insert(input, "")
    table.insert(input, "## 🚀 Entry Points")
    table.insert(input, "1. `path:line` — what starts here")
    table.insert(input, "")
    table.insert(input, "## 🔗 Stack")
    table.insert(input, "| Dep | Purpose |")
    table.insert(input, "|-----|---------|")
    table.insert(input, "")
    if #kb_pages > 0 then
      table.insert(input, "## 📚 Team Knowledge")
      table.insert(input, "You have FULL CONTENT of " .. #kb_pages .. " KB pages in 'raw: knowledge base' above.")
      table.insert(input, "Read them carefully. Extract SPECIFIC insights that matter for this project:")
      table.insert(input, "- Deployment gotchas, architectural decisions, known pitfalls")
      table.insert(input, "- How this project connects to other systems")
      table.insert(input, "- Operational patterns, runbook warnings, config quirks")
      table.insert(input, "- Past incidents or decisions that affect how you work here")
      table.insert(input, "Format: bullet list. Each bullet = one concrete insight with source page.")
      table.insert(input, "- **Insight here** — detail from the KB content (`page-path.md`)")
      table.insert(input, "Do NOT just list page titles. Extract the actual knowledge.")
      table.insert(input, "")
    end
    table.insert(input, "## 🗺 Start Here")
    table.insert(input, "1. `path` — what you learn")
    table.insert(input, "")
    table.insert(input, "---")
    table.insert(input, "*Sources: " .. table.concat(sources, ", ") .. "*")
    table.insert(input, "")
    table.insert(input, "RULES:")
    table.insert(input, "- Keep ``` stats block VERBATIM at top")
    table.insert(input, "- Use TABLES for Modules and Stack — never prose paragraphs")
    table.insert(input, "- All paths: real relative paths from tree, gf-navigable in vim")
    table.insert(input, "- Include treesitter declarations when available — name real functions/types")
    table.insert(input, "- No HTML. No <details>. Plain markdown only.")
    table.insert(input, "- This is a dense working dashboard, not documentation")
  end
  table.insert(input, "Output ONLY the dashboard. No preamble, no commentary, no tool calls.")
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

vim.keymap.set("v", "<leader>gy", function()
  ctx.visual_then(function(lines, source)
    local workbench = ctx.get_or_create_workbench()
    vim.api.nvim_buf_set_lines(workbench, -1, -1, false, { "", "--- " .. source .. " ---", "" })
    vim.api.nvim_buf_set_lines(workbench, -1, -1, false, lines)
    vim.notify("📌 pinned to workbench")
  end)
end, { desc = "cogcog: pin" })

vim.keymap.set("n", "<leader>g!", function()
  vim.ui.input({ prompt = "$ " }, function(cmd)
    if not cmd or cmd == "" then return end
    local workbench = ctx.get_or_create_workbench()
    ctx.show_workbench()
    vim.api.nvim_buf_set_lines(workbench, -1, -1, false, { "", "--- $ " .. cmd .. " ---", "" })
    local job = vim.fn.jobstart({ "bash", "-c", cmd }, {
      stdout_buffered = false,
      on_stdout = function(_, data)
        if not data then return end
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(workbench) then return end
          for _, line in ipairs(data) do
            if line ~= "" then
              vim.api.nvim_buf_set_lines(workbench, -1, -1, false, { line })
            end
          end
          stream._scroll_buf(workbench)
        end)
      end,
      on_stderr = function(_, data)
        if not data then return end
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(workbench) then return end
          for _, line in ipairs(data) do
            if line ~= "" then
              vim.api.nvim_buf_set_lines(workbench, -1, -1, false, { line })
            end
          end
          stream._scroll_buf(workbench)
        end)
      end,
      on_exit = function(_, code)
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(workbench) then return end
          vim.api.nvim_buf_set_lines(workbench, -1, -1, false, { "", "--- exit " .. code .. " ---", "" })
          stream._scroll_buf(workbench)
          vim.notify(code == 0 and "✓ command done" or ("✗ exit " .. code), code == 0 and vim.log.levels.INFO or vim.log.levels.WARN)
        end)
      end,
    })
    if type(job) == "number" and job > 0 then stream.active_jobs[job] = true end
  end)
end, { desc = "cogcog: exec → workbench" })

local function run_tool_to_workbench(tool_path)
  local workbench = ctx.get_or_create_workbench()
  ctx.show_workbench()
  local name = vim.fn.fnamemodify(tool_path, ":t")
  vim.api.nvim_buf_set_lines(workbench, -1, -1, false, { "", "--- tool: " .. name .. " ---", "" })

  if tool_path:match("%.lua$") then
    -- lua tools run inside neovim
    local ok, result = pcall(dofile, tool_path)
    if not ok then
      result = "error: " .. tostring(result)
    elseif type(result) == "function" then
      ok, result = pcall(result)
      if not ok then result = "error: " .. tostring(result) end
    end
    local out = vim.split(tostring(result or ""), "\n")
    vim.api.nvim_buf_set_lines(workbench, -1, -1, false, out)
    vim.api.nvim_buf_set_lines(workbench, -1, -1, false, { "", "--- end ---", "" })
    stream._scroll_buf(workbench)
    vim.notify("✓ " .. name .. " done")
    return
  end

  -- bash tools run as jobs
  local job = vim.fn.jobstart({ "bash", tool_path }, {
    stdout_buffered = false,
    on_stdout = function(_, data)
      if not data then return end
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(workbench) then return end
        for _, line in ipairs(data) do
          if line ~= "" then
            vim.api.nvim_buf_set_lines(workbench, -1, -1, false, { line })
          end
        end
        stream._scroll_buf(workbench)
      end)
    end,
    on_stderr = function(_, data)
      if not data then return end
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(workbench) then return end
        for _, line in ipairs(data) do
          if line ~= "" then
            vim.api.nvim_buf_set_lines(workbench, -1, -1, false, { line })
          end
        end
        stream._scroll_buf(workbench)
      end)
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(workbench) then return end
        vim.api.nvim_buf_set_lines(workbench, -1, -1, false, { "", "--- exit " .. code .. " ---", "" })
        stream._scroll_buf(workbench)
        vim.notify(code == 0 and ("✓ " .. name .. " done") or ("✗ " .. name .. " exit " .. code),
          code == 0 and vim.log.levels.INFO or vim.log.levels.WARN)
      end)
    end,
  })
  if type(job) == "number" and job > 0 then stream.active_jobs[job] = true end
end

vim.keymap.set("n", "<leader>ct", function()
  local tools_dir = config.cogcog_dir .. "/tools"
  if vim.fn.isdirectory(tools_dir) == 0 then
    vim.notify("cogcog: no tools yet — create scripts in .cogcog/tools/", vim.log.levels.INFO)
    return
  end
  local files = vim.fn.globpath(tools_dir, "*", false, true)
  -- filter to executable scripts
  local tools = {}
  for _, f in ipairs(files) do
    local name = vim.fn.fnamemodify(f, ":t")
    if not name:match("^%.") and not name:match("~$") then
      table.insert(tools, { name = name, path = f })
    end
  end
  if #tools == 0 then
    vim.notify("cogcog: .cogcog/tools/ is empty", vim.log.levels.INFO)
    return
  end
  local labels = {}
  for _, t in ipairs(tools) do table.insert(labels, t.name) end
  vim.ui.select(labels, { prompt = "tool:" }, function(choice)
    if not choice then return end
    for _, t in ipairs(tools) do
      if t.name == choice then
        run_tool_to_workbench(t.path)
        return
      end
    end
  end)
end, { desc = "cogcog: run tool → workbench" })

vim.keymap.set("n", "<leader>cT", function()
  vim.ui.input({ prompt = "tool idea: " }, function(desc)
    if not desc or desc == "" then return end
    vim.ui.select({ "bash", "lua (neovim-native)" }, { prompt = "language:" }, function(lang)
      if not lang then return end
      local is_lua = lang:match("^lua")

      local input = {}
      ctx.with_system(input)
      ctx.with_workbench(input)

      if is_lua then
        table.insert(input, "Generate a Neovim-native Lua tool for this job:")
        table.insert(input, desc)
        table.insert(input, "")
        table.insert(input, "Rules:")
        table.insert(input, "- Output ONLY the Lua code, no explanation before or after")
        table.insert(input, "- The file must return a string (the tool output)")
        table.insert(input, "- You can return a function that returns a string instead")
        table.insert(input, "- You have full access to the Neovim Lua API: vim.api, vim.fn, vim.diagnostic, vim.lsp, vim.treesitter")
        table.insert(input, "- Use vim.fn.systemlist() for shell commands if needed")
        table.insert(input, "- Keep it short and single-purpose")
        table.insert(input, "- Example:")
        table.insert(input, '  local diags = vim.diagnostic.get()')
        table.insert(input, '  local out = {}')
        table.insert(input, '  for _, d in ipairs(diags) do')
        table.insert(input, '    local fname = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(d.bufnr), ":.")')
        table.insert(input, '    table.insert(out, fname .. ":" .. d.lnum .. ": " .. d.message)')
        table.insert(input, '  end')
        table.insert(input, '  return table.concat(out, "\\n")')
      else
        table.insert(input, "Generate a small project-local tool script (bash) for this job:")
        table.insert(input, desc)
        table.insert(input, "")
        table.insert(input, "Rules:")
        table.insert(input, "- Output ONLY the script content, no explanation before or after")
        table.insert(input, "- Start with #!/bin/bash and set -euo pipefail")
        table.insert(input, "- Keep it short and single-purpose")
        table.insert(input, "- Print human-readable output to stdout")
        table.insert(input, "- Use relative paths (assume CWD is the project root)")
      end

      local ext = is_lua and ".lua" or ".sh"
      local review_buf = ctx.reuse_or_split("[cogcog-tool-review]", " 🔧 tool review │ a save │ q close")
    stream.to_buf(input, review_buf, {
      raw = true,
      on_done = function()
        if not vim.api.nvim_buf_is_valid(review_buf) then return end
        local all = vim.api.nvim_buf_get_lines(review_buf, 0, -1, false)
        -- extract script lines (strip fences if model wrapped in ```)
        local script = {}
        local in_fence = false
        for _, line in ipairs(all) do
          if line:match("^```") then
            in_fence = not in_fence
          elseif in_fence or line ~= "" or #script > 0 then
            table.insert(script, line)
          end
        end
        -- trim trailing empty lines
        while #script > 0 and script[#script] == "" do table.remove(script) end
        if #script == 0 then return end

        -- rewrite buffer with clean script + instructions
        local display = { "# Tool review", "", "Description: " .. desc, "", "Press `a` to save to .cogcog/tools/, `q` to discard.", "", "---", "" }
        vim.list_extend(display, script)
        vim.bo[review_buf].modifiable = true
        vim.api.nvim_buf_set_lines(review_buf, 0, -1, false, display)

        vim.keymap.set("n", "a", function()
          -- prompt for filename
          vim.ui.input({ prompt = "tool name: ", default = desc:gsub("%s+", "-"):gsub("[^%w%-_]", ""):sub(1, 40) .. ext }, function(name)
            if not name or name == "" then return end
            local tools_dir = config.cogcog_dir .. "/tools"
            vim.fn.mkdir(tools_dir, "p")
            local path = tools_dir .. "/" .. name
            vim.fn.writefile(script, path)
            vim.fn.setfperm(path, "rwxr-xr-x")
            vim.notify("🔧 saved → .cogcog/tools/" .. name)
            for _, win in ipairs(vim.fn.win_findbuf(review_buf)) do
              if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, false) end
            end
          end)
        end, { buffer = review_buf, desc = "cogcog: save tool" })
      end,
    })
    end)
  end)
end, { desc = "cogcog: generate tool" })

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
  local rpc = require("cogcog.pi_rpc")
  if rpc.is_busy() then
    rpc.abort()
  elseif next(stream.active_jobs) then
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
