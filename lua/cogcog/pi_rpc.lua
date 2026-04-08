local config = require("cogcog.config")
local stream = require("cogcog.stream")
local ui = require("cogcog.pi_rpc_ui")

local M = { job = nil, buf = nil, busy = false, partial = "", seq = 0, changed = {}, ui = {} }

local function running()
  return type(M.job) == "number" and M.job > 0 and vim.fn.jobwait({ M.job }, 0)[1] == -1
end

local function notify(msg, level)
  vim.schedule(function() vim.notify(msg, level or vim.log.levels.INFO) end)
end

local function append_lines(lines)
  vim.schedule(function()
    if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then return end
    vim.api.nvim_buf_set_lines(M.buf, -1, -1, false, lines)
    stream._scroll_buf(M.buf)
  end)
end

local function append_text(text)
  vim.schedule(function()
    if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then return end
    if vim.api.nvim_buf_line_count(M.buf) == 0 then vim.api.nvim_buf_set_lines(M.buf, 0, 0, false, { "" }) end
    local parts = vim.split(text or "", "\n", { plain = true, trimempty = false })
    local lc = vim.api.nvim_buf_line_count(M.buf)
    local last = vim.api.nvim_buf_get_lines(M.buf, lc - 1, lc, false)[1] or ""
    vim.api.nvim_buf_set_lines(M.buf, lc - 1, lc, false, { last .. (parts[1] or "") })
    if #parts > 1 then vim.api.nvim_buf_set_lines(M.buf, lc, lc, false, { unpack(parts, 2) }) end
    stream._scroll_buf(M.buf)
  end)
end

local function send(obj)
  if not running() then return notify("cogcog: pi rpc is not running", vim.log.levels.ERROR) end
  M.seq = M.seq + 1
  obj.id = obj.id or ("cogcog-rpc-" .. M.seq)
  vim.fn.chansend(M.job, vim.json.encode(obj) .. "\n")
  return true
end

local function refresh_changed()
  local names = {}
  for path in pairs(M.changed) do
    local abs, buf = vim.fn.fnamemodify(path, ":p"), vim.fn.bufnr(vim.fn.fnamemodify(path, ":p"))
    if buf > 0 then
      if vim.bo[buf].modified then
        notify("cogcog: changed on disk but buffer is modified: " .. vim.fn.fnamemodify(abs, ":."), vim.log.levels.WARN)
      else
        vim.cmd("silent! checktime " .. buf)
      end
    end
    names[#names + 1] = vim.fn.fnamemodify(path, ":.")
  end
  table.sort(names)
  M.changed = {}
  append_lines(#names > 0 and { "", "✓ changed: " .. table.concat(names, ", "), "", "---", "", "" } or { "", "---", "", "" })
end

local function tool_target(args)
  local value = type(args) == "table" and (args.path or args.command or args.dir or args.pattern) or nil
  if not value or value == "" then return "" end
  if #value > 80 then value = value:sub(1, 77) .. "..." end
  return " " .. value
end

local function handle_ui(req)
  ui.handle(req, send, notify, append_lines, M.ui)
end

local function handle(line)
  local ok, obj = pcall(vim.json.decode, line)
  if not ok or type(obj) ~= "table" then return notify("cogcog: bad pi rpc message", vim.log.levels.WARN) end
  if obj.type == "response" then
    if obj.success == false then M.busy = false; notify("cogcog: pi rpc " .. (obj.error or obj.command or "error"), vim.log.levels.ERROR) end
  elseif obj.type == "agent_start" then
    M.busy = true
  elseif obj.type == "agent_end" then
    M.busy = false; refresh_changed()
  elseif obj.type == "message_update" then
    local ev = obj.assistantMessageEvent or {}
    if ev.type == "text_delta" then append_text(ev.delta or "") end
  elseif obj.type == "tool_execution_start" then
    append_lines({ "", "🔧 " .. tostring(obj.toolName or "tool") .. tool_target(obj.args), "" })
  elseif obj.type == "tool_execution_end" then
    local args, name = obj.args or {}, tostring(obj.toolName or "")
    if (name == "edit" or name == "write") and type(args.path) == "string" then M.changed[args.path] = true end
    if obj.isError then append_lines({ "", "✗ " .. name, "" }) end
  elseif obj.type == "extension_ui_request" then
    handle_ui(obj)
  end
end

function M.ensure_started(buf, cmd)
  M.buf = buf
  if running() then return true end
  M.busy, M.partial, M.changed, M.ui = false, "", {}, {}
  local job = vim.fn.jobstart({ "bash", "-c", cmd or config.pi_rpc_cmd() }, {
    stdout_buffered = false,
    on_stdout = function(_, data)
      local text = table.concat(data or {}, "\n")
      if text == "" then return end
      M.partial = M.partial .. text
      while true do
        local nl = M.partial:find("\n", 1, true)
        if not nl then break end
        local line = M.partial:sub(1, nl - 1):gsub("\r$", "")
        M.partial = M.partial:sub(nl + 1)
        if line ~= "" then handle(line) end
      end
    end,
    on_stderr = function(_, data)
      local msg = vim.trim(table.concat(data or {}, "\n"))
      if msg ~= "" then notify("pi rpc: " .. msg:sub(1, 200), vim.log.levels.WARN) end
    end,
    on_exit = function(_, code)
      M.job, M.busy, M.partial, M.changed, M.ui = nil, false, "", {}, {}
      if code ~= 0 then notify("cogcog: pi rpc exited " .. code, vim.log.levels.ERROR) end
    end,
  })
  if type(job) ~= "number" or job <= 0 then return notify("cogcog: failed to start pi rpc", vim.log.levels.ERROR) end
  M.job = job
  return true
end

function M.is_busy() return M.busy end
function M.prompt(message) if send({ type = "prompt", message = message }) then M.busy = true end end
function M.steer(message) send({ type = "steer", message = message }) end
function M.abort() if M.busy then send({ type = "abort" }) end end

return M
