-- cogcog — LLM as a vim verb
local config = require("cogcog.config")
local ctx = require("cogcog.context")
local transport = require("cogcog.transport")

-- Auto-start Neovim server for pi extension integration.
local _cogcog_socket = vim.env.COGCOG_NVIM_SOCKET or "/tmp/cogcog.sock"
pcall(vim.fn.serverstart, _cogcog_socket)

local ask_verbosity = {
  [0] = "Explain this code concisely.",
  [1] = "Explain in one sentence.",
  [2] = "Explain this code clearly.",
  [3] = "Explain in detail with examples.",
}

local function emit_context_event(kind, input, extra)
  local payload = vim.tbl_extend("force", {
    context = input,
  }, extra or {})
  return transport.emit(kind, payload)
end

local function append_to_workbench(title, lines)
  local workbench = ctx.get_or_create_workbench()
  vim.api.nvim_buf_set_lines(workbench, -1, -1, false, { "", title, "" })
  if lines and #lines > 0 then
    vim.api.nvim_buf_set_lines(workbench, -1, -1, false, lines)
  end
  return workbench
end

-- ask (ga)

local function ask_stateless(code_lines, source, question)
  local input = {}
  ctx.with_system(input)
  ctx.with_scope_contract(input)
  table.insert(input, "For this request: explain in natural language. Do NOT output code unless specifically asked.")
  table.insert(input, "")
  ctx.with_selection(input, code_lines, source)
  ctx.with_quickfix(input)
  ctx.with_visible(input)
  table.insert(input, question)

  emit_context_event("ask", input, {
    mode = "stateless",
    source = source,
    question = question,
    selection = code_lines,
  })
end

local function ask_in_workbench(code_lines, source, question)
  if code_lines and #code_lines > 0 then
    append_to_workbench("--- " .. source .. " ---", code_lines)
  end
  append_to_workbench(question)

  local input = {}
  ctx.with_system(input)
  ctx.with_scope_contract(input)
  ctx.with_quickfix(input)
  ctx.with_workbench(input)
  ctx.with_visible(input)

  emit_context_event("ask", input, {
    mode = "workbench",
    source = source,
    question = question,
    selection = code_lines,
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

-- generate (gs)

local function gen_send(code_lines, source, instruction)
  local input = {}
  ctx.with_system(input)
  ctx.with_scope_contract(input)
  ctx.with_selection(input, code_lines, source)
  ctx.with_workbench(input)
  table.insert(input, instruction)
  table.insert(input, "")
  table.insert(input, "Output only the code. No explanations unless asked.")

  emit_context_event("generate", input, {
    source = source,
    instruction = instruction,
    selection = code_lines,
  })
end

local function gen(lines, source)
  vim.ui.input({ prompt = " gen: " }, function(q)
    if q and vim.trim(q) ~= "" then gen_send(lines, source, q) end
  end)
end

-- refactor (gr)

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

  emit_context_event("refactor", input, {
    source = source,
    instruction = instruction,
    selection = lines,
    target = {
      file = ctx.relative_name(vim.api.nvim_buf_get_name(target_buf)),
      start_line = l1,
      end_line = l2,
    },
  })
end

local function refactor(lines, source)
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

-- check (gc)

local function check_send(code_lines, source)
  local input = {}
  ctx.with_system(input)
  ctx.with_scope_contract(input)
  table.insert(input, "Review this code for correctness, edge cases, and bugs.")
  table.insert(input, "Be concise. Only flag real problems.")
  table.insert(input, "")
  ctx.with_selection(input, code_lines, source)

  emit_context_event("check", input, {
    source = source,
    selection = code_lines,
  })
end

-- plan (C-g)

local function plan_send(question)
  local from_workbench = ctx.is_workbench()
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

  emit_context_event("plan", input, {
    question = question,
    mode = from_workbench and "workbench" or "code",
  })
end

-- execute (<leader>gx)

local function exec_send(instruction)
  local from_workbench = ctx.is_workbench()
  local workbench = ctx.get_or_create_workbench()
  vim.api.nvim_buf_set_lines(workbench, -1, -1, false, {
    "",
    "--- exec ---",
    "",
    instruction,
    "",
  })

  local input = {}
  ctx.with_agent_instructions(input, "exec")
  ctx.with_scope_contract(input)
  ctx.with_quickfix(input)
  ctx.with_workbench(input)
  ctx.with_visible(input)

  ctx.show_workbench()

  emit_context_event("execute", input, {
    instruction = instruction,
    mode = from_workbench and "workbench" or "code",
  })
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
  saved_count = vim.v.count
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

vim.keymap.set("n", "<leader>gx", function()
  local cur_file = ctx.relative_name(vim.api.nvim_buf_get_name(0))
  local hint = cur_file ~= "scratch" and " (in " .. cur_file .. ")" or ""
  vim.ui.input({ prompt = " exec" .. hint .. ": " }, function(q)
    if not q or vim.trim(q) == "" then return end
    if cur_file ~= "scratch" then
      q = "[working in " .. cur_file .. "] " .. q
    end
    exec_send(q)
  end)
end, { desc = "cogcog: execute in pi" })

vim.keymap.set("v", "<leader>gy", function()
  ctx.visual_then(function(lines, source)
    append_to_workbench("--- " .. source .. " ---", lines)
    vim.notify("📌 pinned to workbench")
  end)
end, { desc = "cogcog: pin" })

vim.keymap.set("n", "<leader>co", function()
  if ctx.workbench_win() then
    vim.api.nvim_win_close(ctx.workbench_win(), false)
  else
    ctx.show_workbench()
  end
end, { desc = "cogcog: workbench" })

vim.keymap.set("n", "<leader>cc", function()
  local workbench = ctx.get_or_create_workbench()
  vim.api.nvim_buf_set_lines(workbench, 0, -1, false, {})
  vim.fn.delete(config.workbench_file)
  vim.fn.delete(config.legacy_session_file)
  vim.notify("🗑 workbench cleared")
end, { desc = "cogcog: clear workbench" })

vim.keymap.set({ "n", "i" }, "<C-c>", function()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-c>", true, false, true), "n", false)
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
