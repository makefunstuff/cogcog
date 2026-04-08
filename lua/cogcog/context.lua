-- cogcog/context.lua — input builders and workbench helpers
local config = require("cogcog.config")
local M = {}

local WORKBENCH_NAME = "[cogcog-workbench]"

local function read_lines(path)
  if path and vim.fn.filereadable(path) == 1 then return vim.fn.readfile(path) end
  return {}
end

local function is_cogcog_buf(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return false end
  return vim.api.nvim_buf_get_name(buf):match("%[cogcog") ~= nil
end

local function workbench_initial_lines()
  return read_lines(config.readable_workbench_file())
end

-- Input builders -----------------------------------------------------------
--
-- Context model used by the current Cogcog pass:
--   - hard scope: explicit operand / quickfix target set
--   - explicit imports: workbench contents
--   - soft context: visible windows

function M.with_system(input)
  local sys = config.cogcog_dir .. "/system.md"
  local sys_lines = read_lines(sys)
  if #sys_lines > 0 then
    vim.list_extend(input, sys_lines)
    table.insert(input, "")
  end
  return input
end

function M.with_scope_contract(input)
  table.insert(input, "Primary target: the explicit operand or quickfix target set.")
  table.insert(input, "Quickfix, when present, is the hard boundary for batch work.")
  table.insert(input, "Workbench content is explicitly imported context. Visible windows are soft context only.")
  table.insert(input, "")
  return input
end

-- Hard scope for batch work.
function M.with_quickfix(input)
  local qf = vim.fn.getqflist()
  if #qf == 0 then return input end

  local out, seen = {}, {}
  for _, item in ipairs(qf) do
    if item.bufnr > 0 and item.lnum > 0 and vim.api.nvim_buf_is_valid(item.bufnr) then
      local key = item.bufnr .. ":" .. item.lnum
      if not seen[key] then
        seen[key] = true
        local fname = M.relative_name(vim.api.nvim_buf_get_name(item.bufnr))
        local text = item.text and vim.trim(item.text) or "(no message)"
        table.insert(out, fname .. ":" .. item.lnum .. ": " .. text)
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

function M.get_quickfix_targets(context_radius)
  context_radius = context_radius or 2
  local qf = vim.fn.getqflist()
  local per_buf = {}

  for _, item in ipairs(qf) do
    if item.bufnr > 0 and item.lnum > 0 and vim.api.nvim_buf_is_valid(item.bufnr) and vim.bo[item.bufnr].buftype == "" then
      local line_count = vim.api.nvim_buf_line_count(item.bufnr)
      local file = M.relative_name(vim.api.nvim_buf_get_name(item.bufnr))
      per_buf[item.bufnr] = per_buf[item.bufnr] or {}
      table.insert(per_buf[item.bufnr], {
        bufnr = item.bufnr,
        file = file,
        lnum = item.lnum,
        text = item.text and vim.trim(item.text) or "(no message)",
        start = math.max(1, item.lnum - context_radius),
        stop = math.min(line_count, item.lnum + context_radius),
      })
    end
  end

  local targets = {}
  for bufnr, entries in pairs(per_buf) do
    table.sort(entries, function(a, b)
      if a.start == b.start then return a.stop < b.stop end
      return a.start < b.start
    end)

    local current = nil
    for _, entry in ipairs(entries) do
      if not current then
        current = {
          bufnr = bufnr,
          file = entry.file,
          start = entry.start,
          stop = entry.stop,
          hints = { { lnum = entry.lnum, text = entry.text } },
        }
      elseif entry.start <= current.stop + 1 then
        current.stop = math.max(current.stop, entry.stop)
        table.insert(current.hints, { lnum = entry.lnum, text = entry.text })
      else
        table.insert(targets, current)
        current = {
          bufnr = bufnr,
          file = entry.file,
          start = entry.start,
          stop = entry.stop,
          hints = { { lnum = entry.lnum, text = entry.text } },
        }
      end
    end
    if current then table.insert(targets, current) end
  end

  table.sort(targets, function(a, b)
    if a.file == b.file then return a.start > b.start end
    return a.file < b.file
  end)

  return targets
end

-- Hard scope for the current operand.
function M.with_selection(input, lines, source)
  if lines and #lines > 0 then
    table.insert(input, "--- " .. source .. " ---")
    table.insert(input, "")
    vim.list_extend(input, lines)
    table.insert(input, "")
  end
  return input
end

-- Explicit imports and longer-form working material.
function M.with_workbench(input)
  local buf = M.get_or_create_workbench()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  if vim.trim(table.concat(lines, "\n")) ~= "" then
    table.insert(input, "--- workbench ---")
    table.insert(input, "")
    vim.list_extend(input, lines)
    table.insert(input, "")
  end
  return input
end

-- Backward-compatible alias while the rest of the plugin migrates.
M.with_panel = M.with_workbench

-- Build a compact index of all wiki pages in the KB.
local function kb_build_index(wiki_dir)
  local files = vim.fn.systemlist("find " .. vim.fn.shellescape(wiki_dir) .. " -name '*.md' -type f 2>/dev/null | sort")
  if #files == 0 then return nil end
  local index = {}
  for _, f in ipairs(files) do
    local rel = f:gsub("^" .. vim.pesc(wiki_dir) .. "/?", "")
    local lines = vim.fn.readfile(f, "", 20)
    local title = ""
    local desc = ""
    local in_frontmatter = false
    for _, line in ipairs(lines) do
      if line == "---" then
        in_frontmatter = not in_frontmatter
      elseif in_frontmatter then
        -- parse YAML frontmatter
        local t = line:match('^title:%s*"?(.-)"?%s*$')
        if t and t ~= "" then title = t end
      elseif line:match("^#") and title == "" then
        title = line:gsub("^#+%s*", "")
      elseif line ~= "" and desc == "" and not line:match("^[-#]") and not in_frontmatter then
        desc = line:sub(1, 120)
      end
    end
    if title == "" then title = rel:gsub("%.md$", ""):gsub("/", " > ") end
    table.insert(index, { path = f, rel = rel, title = title, desc = desc })
  end
  return index
end

-- Try Obsidian CLI search (requires running Obsidian app).
local function kb_obsidian_search(vault_name, query, max_results)
  if vim.fn.executable("obsidian") ~= 1 then return nil end
  local cmd = "obsidian search" ..
    " query=" .. vim.fn.shellescape(query) ..
    " vault=" .. vim.fn.shellescape(vault_name) ..
    " limit=" .. max_results ..
    " format=json 2>/dev/null"
  local raw = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 or raw == "" or raw:match("^%s*$") then return nil end
  local ok, parsed = pcall(vim.json.decode, raw)
  if not ok or type(parsed) ~= "table" or #parsed == 0 then return nil end
  return parsed
end

-- LLM-powered KB search: try Obsidian CLI first, fall back to LLM index search.
function M.kb_search(query, max_results)
  local kb = config.kb_path()
  if not kb then return nil end
  max_results = max_results or 8
  local wiki_dir = kb .. "/wiki"
  if vim.fn.isdirectory(wiki_dir) == 0 then return nil end

  -- derive vault name from kb path
  local vault_name = vim.fn.fnamemodify(kb, ":t")

  -- ── try Obsidian CLI first (instant, uses built-in search index) ──
  local obs_results = kb_obsidian_search(vault_name, query, max_results)
  if obs_results then
    local results = {}
    for _, hit in ipairs(obs_results) do
      local path = hit.path or hit.file or hit
      if type(path) == "string" then
        local full = kb .. "/" .. path
        if vim.fn.filereadable(full) == 0 then full = path end
        local flines = vim.fn.filereadable(full) == 1 and vim.fn.readfile(full, "", 20) or {}
        local title = ""
        local snippet = {}
        local in_fm = false
        for i, line in ipairs(flines) do
          if line == "---" then in_fm = not in_fm
          elseif in_fm then
            local t = line:match('^title:%s*"?(.-)"?%s*$')
            if t and t ~= "" then title = t end
          elseif line:match("^#") and title == "" then
            title = line:gsub("^#+%s*", "")
          elseif line ~= "" and not in_fm and i > 1 then
            table.insert(snippet, line)
          end
        end
        if title == "" then title = path:gsub("%.md$", ""):gsub("/", " > ") end
        table.insert(results, {
          path = path,
          full_path = full,
          title = title,
          snippet = table.concat(snippet, "\n", 1, math.min(#snippet, 8)),
        })
      end
      if #results >= max_results then break end
    end
    if #results > 0 then
      vim.notify("📚 KB: " .. #results .. " pages via Obsidian", vim.log.levels.INFO)
      return results
    end
  end

  -- ── fallback: LLM-powered search ─────────────────────────────
  local index = kb_build_index(wiki_dir)
  if not index or #index == 0 then return nil end

  vim.notify("📚 KB: searching " .. #index .. " pages via LLM...", vim.log.levels.INFO)

  local prompt_lines = {
    "You are a knowledge base search engine.",
    "Given a query and a page index, return the most relevant page paths.",
    "",
    "Query: " .. query,
    "",
    "Pages:",
  }
  for _, entry in ipairs(index) do
    local line = entry.rel
    if entry.title ~= "" then line = line .. " — " .. entry.title end
    if entry.desc ~= "" then line = line .. " | " .. entry.desc end
    table.insert(prompt_lines, line)
  end
  table.insert(prompt_lines, "")
  table.insert(prompt_lines, "Return up to " .. max_results .. " most relevant page paths, one per line.")
  table.insert(prompt_lines, "Output ONLY the paths, nothing else. No numbering, no explanation.")

  local tmp = vim.fn.tempname()
  vim.fn.writefile(prompt_lines, tmp)
  local cmd = config.checker_cmd() .. " < " .. vim.fn.shellescape(tmp)
  local raw_output = vim.fn.systemlist("bash -c " .. vim.fn.shellescape(cmd))
  vim.fn.delete(tmp)

  if vim.v.shell_error ~= 0 then return nil end

  -- build a lookup from relative path → full path
  local lookup = {}
  for _, entry in ipairs(index) do
    lookup[entry.rel] = entry
    local basename = entry.rel:match("[^/]+$") or entry.rel
    if not lookup[basename] then lookup[basename] = entry end
  end

  -- parse model output into results
  local results = {}
  local seen = {}
  for _, line in ipairs(raw_output) do
    line = vim.trim(line)
    line = line:gsub("^%d+[%.%)%s]+", "")
    line = line:gsub("^`(.-)`.*", "%1")
    line = line:gsub("^%-+%s*", "")
    line = vim.trim(line)
    if line == "" then goto continue end

    local entry = lookup[line]
    if not entry then
      for _, e in ipairs(index) do
        if e.rel:find(line, 1, true) or e.path:find(line, 1, true) then
          entry = e
          break
        end
      end
    end
    if entry and not seen[entry.path] then
      seen[entry.path] = true
      local flines = vim.fn.readfile(entry.path, "", 20)
      local snippet = {}
      for i = 2, math.min(#flines, 12) do
        if flines[i] ~= "" then table.insert(snippet, flines[i]) end
      end
      table.insert(results, {
        path = entry.rel,
        full_path = entry.path,
        title = entry.title,
        snippet = table.concat(snippet, "\n"),
      })
    end
    if #results >= max_results then break end
    ::continue::
  end

  if #results > 0 then
    vim.notify("📚 KB: " .. #results .. " pages via LLM", vim.log.levels.INFO)
  end
  return results
end

-- Include KB context in input if relevant.
function M.with_kb(input, query)
  local results = M.kb_search(query)
  if not results or #results == 0 then return input end
  table.insert(input, "--- knowledge base context ---")
  table.insert(input, "")
  for _, r in ipairs(results) do
    table.insert(input, "### " .. r.title)
    table.insert(input, "`" .. r.path .. "`")
    table.insert(input, r.snippet)
    table.insert(input, "")
  end
  return input
end

-- Tool definitions for workbench synthesis.
function M.with_tools(input)
  local tools = {
    "read_file(path) — read a project file and return its contents",
    "list_files(dir) — list files in a directory (default: .)",
    "grep(pattern, path) — search for a regex pattern (default path: .)",
    "run_command(cmd) — execute a shell command and return stdout+stderr",
    "diagnostics() — get LSP diagnostics across all open buffers (neovim-native)",
    "lsp_symbols(path) — get document symbols via LSP (neovim-native)",
    "buffers() — list currently loaded buffers (neovim-native)",
    "kb_search(query) — search the knowledge base for relevant pages (if configured)",
  }

  -- discover .cogcog/tools/ scripts
  local tools_dir = config.cogcog_dir .. "/tools"
  if vim.fn.isdirectory(tools_dir) == 1 then
    local files = vim.fn.globpath(tools_dir, "*", false, true)
    for _, f in ipairs(files) do
      local name = vim.fn.fnamemodify(f, ":t")
      if not name:match("^%.") and not name:match("~$") then
        local first_lines = vim.fn.readfile(f, "", 5)
        local desc = ""
        for _, line in ipairs(first_lines) do
          if line:match("^#[^!]") then
            desc = " — " .. line:gsub("^#%s*", "")
            break
          end
        end
        table.insert(tools, "tool:" .. name .. desc)
      end
    end
  end

  table.insert(input, "## Available tools")
  table.insert(input, "")
  table.insert(input, "To use a tool, output EXACTLY this format on its own line:")
  table.insert(input, "<<<TOOL: tool_name(args)>>>")
  table.insert(input, "")
  table.insert(input, "Examples:")
  table.insert(input, '<<<TOOL: read_file("src/auth.ts")>>>')
  table.insert(input, '<<<TOOL: grep("TODO", "src/")>>>')
  table.insert(input, '<<<TOOL: list_files("src/middleware")>>>')
  table.insert(input, '<<<TOOL: run_command("make test")>>>')
  table.insert(input, '<<<TOOL: tool:check-types.sh()>>>')
  table.insert(input, "")
  table.insert(input, "Rules:")
  table.insert(input, "- Output at most ONE tool call per response")
  table.insert(input, "- Place it at the END of your response, after any explanation")
  table.insert(input, "- I will execute it (with approval) and call you again with the result")
  table.insert(input, "- If you don't need a tool, just respond normally without any tool call")
  table.insert(input, "")
  for _, t in ipairs(tools) do
    table.insert(input, "- " .. t)
  end
  table.insert(input, "")
  return input
end

-- Soft context from what is visibly on screen right now.
function M.with_visible(input)
  local seen = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if not seen[buf] and vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "" and not is_cogcog_buf(buf) then
      seen[buf] = true
      local name = vim.api.nvim_buf_get_name(buf)
      if name ~= "" then
        local info = vim.fn.getwininfo(win)[1]
        if info then
          local first = info.topline or 1
          local last = info.botline or vim.api.nvim_buf_line_count(buf)
          local lines = vim.api.nvim_buf_get_lines(buf, first - 1, last, false)
          if #lines > 0 then
            table.insert(input, "--- " .. M.relative_name(name) .. ":" .. first .. "-" .. last .. " (visible) ---")
            table.insert(input, "")
            vim.list_extend(input, lines)
            table.insert(input, "")
          end
        end
      end
    end
  end
  return input
end

function M.with_jumps(input, max_jumps)
  max_jumps = max_jumps or 5
  local jumps = vim.fn.getjumplist()[1]
  if not jumps or #jumps == 0 then return input end

  local seen, count = {}, 0
  for i = #jumps, 1, -1 do
    if count >= max_jumps then break end
    local jump = jumps[i]
    if jump.bufnr and vim.api.nvim_buf_is_valid(jump.bufnr) and vim.bo[jump.bufnr].buftype == "" then
      local name = vim.api.nvim_buf_get_name(jump.bufnr)
      local key = name .. ":" .. jump.lnum
      if name ~= "" and not seen[key] then
        seen[key] = true
        local start = math.max(0, jump.lnum - 3)
        local stop = math.min(vim.api.nvim_buf_line_count(jump.bufnr), jump.lnum + 3)
        local snippet = vim.api.nvim_buf_get_lines(jump.bufnr, start, stop, false)
        if #snippet > 0 then
          table.insert(input, "--- " .. M.relative_name(name) .. ":" .. (start + 1) .. "-" .. stop .. " (jump) ---")
          table.insert(input, "")
          vim.list_extend(input, snippet)
          table.insert(input, "")
          count = count + 1
        end
      end
    end
  end
  return input
end

function M.with_changes(input)
  local changes = vim.fn.getchangelist()[1]
  if not changes or #changes == 0 then return input end

  local buf = vim.api.nvim_get_current_buf()
  local name = M.relative_name(vim.api.nvim_buf_get_name(buf))
  local seen, snippets = {}, {}
  for i = #changes, math.max(1, #changes - 10), -1 do
    local change = changes[i]
    if change.lnum and change.lnum > 0 and not seen[change.lnum] then
      seen[change.lnum] = true
      local start = math.max(0, change.lnum - 2)
      local stop = math.min(vim.api.nvim_buf_line_count(buf), change.lnum + 2)
      vim.list_extend(snippets, vim.api.nvim_buf_get_lines(buf, start, stop, false))
      table.insert(snippets, "")
    end
  end

  if #snippets > 0 then
    table.insert(input, "--- recent changes in " .. name .. " ---")
    table.insert(input, "")
    vim.list_extend(input, snippets)
    table.insert(input, "")
  end
  return input
end

function M.with_current_file(input)
  local buf = vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(buf)
  if name ~= "" and vim.bo[buf].buftype == "" then
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    if #lines > 0 then
      table.insert(input, "--- current file: " .. M.relative_name(name) .. " ---")
      table.insert(input, "")
      vim.list_extend(input, lines)
      table.insert(input, "")
    end
  end
  return input
end

-- Optional helper only. Do not use as a default context source.
function M.with_open_buffers(input)
  local cur_name = vim.api.nvim_buf_get_name(0)
  local names = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == "" then
      local name = vim.api.nvim_buf_get_name(buf)
      if name ~= "" and name ~= cur_name then
        table.insert(names, M.relative_name(name))
      end
    end
  end
  if #names > 0 then
    table.insert(input, "--- open buffers ---")
    vim.list_extend(input, names)
    table.insert(input, "")
  end
  return input
end

-- Workbench ---------------------------------------------------------------

local function buf_name_ends_with(buf, suffix)
  return vim.api.nvim_buf_is_valid(buf)
    and vim.api.nvim_buf_get_name(buf):match(vim.pesc(suffix) .. "$") ~= nil
end

function M.get_or_create_workbench()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if buf_name_ends_with(buf, WORKBENCH_NAME) then
      return buf
    end
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].buftype = "nofile"
  vim.api.nvim_buf_set_name(buf, WORKBENCH_NAME)

  local initial = workbench_initial_lines()
  if #initial > 0 then vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial) end
  return buf
end

function M.is_workbench(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  return buf_name_ends_with(buf, WORKBENCH_NAME)
end

function M.workbench_win()
  local buf = M.get_or_create_workbench()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buf then return win end
  end
end

function M.show_workbench()
  if M.workbench_win() then return end
  local buf = M.get_or_create_workbench()
  local width = math.floor(vim.o.columns * 0.4)
  vim.cmd("botright vsplit | vertical resize " .. width)
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  for _, opt in ipairs({ "number", "relativenumber", "cursorline" }) do
    vim.api.nvim_set_option_value(opt, false, { win = win })
  end
  vim.api.nvim_set_option_value("signcolumn", "no", { win = win })
  vim.api.nvim_set_option_value("wrap", true, { win = win })
  vim.api.nvim_set_option_value("linebreak", true, { win = win })
  vim.api.nvim_set_option_value("winfixwidth", true, { win = win })
  vim.api.nvim_set_option_value("statusline", " 🧠 workbench", { win = win })
  return win
end

-- Backward-compatible aliases while the rest of the plugin migrates.
M.get_or_create_panel = M.get_or_create_workbench
M.panel_win = M.workbench_win
M.show_panel = M.show_workbench

-- Helpers -----------------------------------------------------------------

function M.relative_name(path)
  if path == "" then return "scratch" end
  local cwd = vim.fn.getcwd() .. "/"
  return path:sub(1, #cwd) == cwd and path:sub(#cwd + 1) or path
end

function M.same_lines(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do
    if a[i] ~= b[i] then return false end
  end
  return true
end

function M.unified_diff(a, b)
  if M.same_lines(a, b) then return { "(no changes)" } end

  local left = table.concat(a, "\n")
  local right = table.concat(b, "\n")
  if left ~= "" then left = left .. "\n" end
  if right ~= "" then right = right .. "\n" end

  local diff_fn = (vim.text and vim.text.diff) or vim.diff
  if type(diff_fn) == "function" then
    local ok, diff = pcall(diff_fn, left, right, { result_type = "unified" })
    if ok and type(diff) == "string" and diff ~= "" then
      diff = diff:gsub("\n+$", "")
      return vim.split(diff, "\n", { plain = true })
    end
  end

  local out = { "--- original ---", "" }
  vim.list_extend(out, a)
  table.insert(out, "")
  table.insert(out, "--- rewritten ---")
  table.insert(out, "")
  vim.list_extend(out, b)
  return out
end

function M.make_split(vertical, buf, statusline)
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
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf })
  vim.cmd("wincmd p")
  return win
end

function M.get_visual_selection()
  local name = M.relative_name(vim.api.nvim_buf_get_name(0))
  local l1, l2 = vim.fn.line("'<"), vim.fn.line("'>")
  return vim.api.nvim_buf_get_lines(0, l1 - 1, l2, false), name, l1, l2
end

function M.visual_then(fn)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
  vim.schedule(function()
    local lines, name, l1, l2 = M.get_visual_selection()
    fn(lines, name .. ":" .. l1 .. "-" .. l2)
  end)
end

function M.with_agent_instructions(input, mode)
  local instructions = {
    "Read before you write. Understand existing code before changing it.",
    "Match the project's style, naming, and conventions.",
  }

  if mode == "gen" then
    vim.list_extend(instructions, {
      "Explore the relevant code first, then generate.",
      "Output the final code to stdout.",
    })
  elseif mode == "plan" then
    vim.list_extend(instructions, {
      "Explore the codebase before answering.",
      "Reference specific file paths and line numbers.",
      "Be concrete — suggest exact changes, not vague advice.",
    })
  elseif mode == "exec" then
    vim.list_extend(instructions, {
      "Default to analysis and a concrete plan before editing.",
      "Only edit when the user explicitly asks to implement, fix, change, or write code.",
      "Read files before making changes.",
      "Prefer editing existing code over creating new files.",
      "Run tests after changes if possible.",
    })
  end

  local sys = config.cogcog_dir .. "/system.md"
  if vim.fn.filereadable(sys) == 1 then
    vim.list_extend(instructions, vim.fn.readfile(sys))
  end

  table.insert(input, "--- instructions ---")
  table.insert(input, "")
  vim.list_extend(input, instructions)
  table.insert(input, "")
  return input
end

function M.reuse_or_split(name, statusline)
  local buf
  for _, existing in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(existing) and vim.api.nvim_buf_get_name(existing):match(vim.pesc(name) .. "$") then
      buf = existing
      break
    end
  end

  if not buf then
    buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = "markdown"
    vim.bo[buf].buftype = "nofile"
    vim.api.nvim_buf_set_name(buf, name)
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})

  local win
  for _, existing in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(existing) == buf then win = existing end
  end
  if not win then
    win = M.make_split(true, buf, statusline)
  else
    vim.api.nvim_set_option_value("statusline", statusline, { win = win })
  end
  return buf, win
end

function M.strip_code_fences(result)
  while #result > 0 and vim.trim(result[1]) == "" do table.remove(result, 1) end
  while #result > 0 and vim.trim(result[#result]) == "" do table.remove(result) end
  if #result >= 2 then
    if result[1]:match("^```") then table.remove(result, 1) end
    if #result > 0 and result[#result]:match("^```") then table.remove(result) end
  end
  return result
end

return M
