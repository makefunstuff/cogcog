-- cogcog/context.lua — input builders and context panel
local config = require("cogcog.config")
local M = {}

-- Input builders: each takes an input table and returns it with added context
-- Usage: ctx.with_system(input) where input = {}

-- Add system prompt if exists
function M.with_system(input)
  local sys = config.cogcog_dir .. "/system.md"
  if vim.fn.filereadable(sys) == 1 then
    local sys_lines = vim.fn.readfile(sys)
    if #sys_lines > 0 then
      vim.list_extend(input, sys_lines)
      table.insert(input, "")
    else
      vim.notify("cogcog: system.md is empty", vim.log.levels.WARN)
    end
  end
  return input
end

-- Add quickfix list (LSP diagnostics, grep, make errors)
function M.with_quickfix(input)
  local qf = vim.fn.getqflist()
  if #qf == 0 then return input end
  local out, seen = {}, {}
  for _, item in ipairs(qf) do
    if item.bufnr > 0 and item.lnum > 0 then
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
  else
    vim.notify("cogcog: no quickfix items found", vim.log.levels.INFO)
  end
  return input
end

-- Add selection (lines, source identifier)
function M.with_selection(input, lines, source)
  if lines and #lines > 0 then
    table.insert(input, "--- " .. source .. " ---")
    table.insert(input, "")
    vim.list_extend(input, lines)
    table.insert(input, "")
  end
  return input
end

-- Add context panel if populated
function M.with_panel(input)
  local ctx = M.get_or_create_panel()
  local lines = vim.api.nvim_buf_get_lines(ctx, 0, -1, false)
  local content = table.concat(lines, "\n")
  if vim.trim(content) ~= "" then
    table.insert(input, "--- context ---")
    table.insert(input, "")
    vim.list_extend(input, lines)
    table.insert(input, "")
  end
  return input
end

-- Add all visible windows (excluding cogcog buffers)
function M.with_visible(input)
  local seen = {}
  -- skip cogcog buffers
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_get_name(b):match("%[cogcog") then
      seen[b] = true
    end
  end
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    local b = vim.api.nvim_win_get_buf(w)
    if not seen[b] and vim.api.nvim_buf_is_valid(b) and vim.bo[b].buftype == "" then
      seen[b] = true
      local name = vim.api.nvim_buf_get_name(b)
      if name ~= "" then
        local info = vim.fn.getwininfo(w)[1]
        if info then
          local first = info.topline or 1
          local last = info.botline or vim.api.nvim_buf_line_count(b)
          local vis = vim.api.nvim_buf_get_lines(b, first - 1, last, false)
          if #vis > 0 then
            table.insert(input, "--- " .. M.relative_name(name) .. ":" .. first .. "-" .. last .. " (visible) ---")
            table.insert(input, "")
            vim.list_extend(input, vis)
            table.insert(input, "")
          end
        end
      end
    end
  end
  return input
end

-- Add jump trail (last N locations visited via gv or <C-o>/<C-i>)
-- max_jumps = 5 (default, controls how many jump locations to include)
function M.with_jumps(input, max_jumps)
  max_jumps = max_jumps or 5
  local jumps = vim.fn.getjumplist()[1]
  if not jumps or #jumps == 0 then return input end
  local seen, count = {}, 0
  for i = #jumps, 1, -1 do
    if count >= max_jumps then break end
    local j = jumps[i]
    if j.bufnr and vim.api.nvim_buf_is_valid(j.bufnr) and vim.bo[j.bufnr].buftype == "" then
      local name = vim.api.nvim_buf_get_name(j.bufnr)
      local key = name .. ":" .. j.lnum
      if name ~= "" and not seen[key] then
        seen[key] = true
        local start = math.max(0, j.lnum - 3)
        local stop = math.min(vim.api.nvim_buf_line_count(j.bufnr), j.lnum + 3)
        local snippet = vim.api.nvim_buf_get_lines(j.bufnr, start, stop, false)
        if #snippet > 0 then
          table.insert(input, "--- " .. M.relative_name(name) .. ":" .. (start+1) .. "-" .. stop .. " (jump) ---")
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

-- Add recent changes (last 10 lines modified, showing ±2 context)
-- Shows what the user recently edited so LLM understands changes
function M.with_changes(input)
  local changes = vim.fn.getchangelist()[1]
  if not changes or #changes == 0 then return input end
  local buf = vim.api.nvim_get_current_buf()
  local name = M.relative_name(vim.api.nvim_buf_get_name(buf))
  local seen, snippets = {}, {}
  for i = #changes, math.max(1, #changes - 10), -1 do
    local c = changes[i]
    if c.lnum and c.lnum > 0 and not seen[c.lnum] then
      seen[c.lnum] = true
      local start = math.max(0, c.lnum - 2)
      local stop = math.min(vim.api.nvim_buf_line_count(buf), c.lnum + 2)
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

-- Add current file contents
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

-- Add list of open buffers
function M.with_open_buffers(input)
  local cur_name = vim.api.nvim_buf_get_name(0)
  local names = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buftype == "" then
      local name = vim.api.nvim_buf_get_name(b)
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

-- Get or create the context panel buffer
function M.get_or_create_panel()
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_get_name(b):match("%[cogcog%]$") then
      return b
    end
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].buftype = "nofile"
  vim.api.nvim_buf_set_name(buf, "[cogcog]")
  local initial = vim.fn.filereadable(config.session_file) == 1
    and vim.fn.readfile(config.session_file)
    or (vim.fn.filereadable(config.cogcog_dir .. "/system.md") == 1
      and vim.fn.readfile(config.cogcog_dir .. "/system.md") or {})
  if #initial > 0 then vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial) end
  return buf
end

-- Get the panel window if it exists
function M.panel_win()
  local buf = M.get_or_create_panel()
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(w) == buf then return w end
  end
end

-- Show/create context panel and split
function M.show_panel()
  if M.panel_win() then return end
  local buf = M.get_or_create_panel()
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

-- Helpers

-- Convert absolute path to relative (or return "scratch" for unnamed)
function M.relative_name(path)
  if path == "" then return "scratch" end
  local cwd = vim.fn.getcwd() .. "/"
  return path:sub(1, #cwd) == cwd and path:sub(#cwd + 1) or path
end

-- Create vertical or horizontal split with options
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

-- Get visual selection as lines, name, and line range
function M.get_visual_selection()
  local name = M.relative_name(vim.api.nvim_buf_get_name(0))
  local l1, l2 = vim.fn.line("'<"), vim.fn.line("'>")
  return vim.api.nvim_buf_get_lines(0, l1 - 1, l2, false), name, l1, l2
end

-- Escape visual mode, get selection, call callback
function M.visual_then(fn)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
  vim.schedule(function()
    local lines, name, l1, l2 = M.get_visual_selection()
    fn(lines, name .. ":" .. l1 .. "-" .. l2)
  end)
end

-- Add agent-specific instructions based on mode
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
      "Read files before making changes.",
      "Prefer editing existing code over creating new files.",
      "Run tests after changes if possible.",
    })
  end
  -- load project system prompt if exists
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

-- Strip markdown code fences from output
function M.strip_code_fences(result)
  while #result > 0 and result[#result] == "" do table.remove(result) end
  if #result >= 2 then
    if result[1]:match("^```") then table.remove(result, 1) end
    if #result > 0 and result[#result]:match("^```") then table.remove(result) end
  end
  return result
end

return M

function M.get_or_create_panel()
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_get_name(b):match("%[cogcog%]$") then
      return b
    end
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].buftype = "nofile"
  vim.api.nvim_buf_set_name(buf, "[cogcog]")
  local initial = vim.fn.filereadable(config.session_file) == 1
    and vim.fn.readfile(config.session_file)
    or (vim.fn.filereadable(config.cogcog_dir .. "/system.md") == 1
      and vim.fn.readfile(config.cogcog_dir .. "/system.md") or {})
  if #initial > 0 then vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial) end
  return buf
end

function M.panel_win()
  local buf = M.get_or_create_panel()
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(w) == buf then return w end
  end
end

function M.show_panel()
  if M.panel_win() then return end
  local buf = M.get_or_create_panel()
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

function M.relative_name(path)
  if path == "" then return "scratch" end
  local cwd = vim.fn.getcwd() .. "/"
  return path:sub(1, #cwd) == cwd and path:sub(#cwd + 1) or path
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
      "Read files before making changes.",
      "Prefer editing existing code over creating new files.",
      "Run tests after changes if possible.",
    })
  end
  -- load project system prompt if exists
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

function M.strip_code_fences(result)
  while #result > 0 and result[#result] == "" do table.remove(result) end
  if #result >= 2 then
    if result[1]:match("^```") then table.remove(result, 1) end
    if #result > 0 and result[#result]:match("^```") then table.remove(result) end
  end
  return result
end

return M
