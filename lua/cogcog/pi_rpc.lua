local config = require("cogcog.config")
local stream = require("cogcog.stream")
local ui = require("cogcog.pi_rpc_ui")

local uv = vim.uv or vim.loop
local M = { chan = nil, kind = nil, buf = nil, busy = false, partial = "", seq = 0, changed = {}, ui = {}, current_text = false, stopping = false }

local function running()
  if type(M.chan) ~= "number" or M.chan <= 0 then return false end
  if M.kind == "job" then return vim.fn.jobwait({ M.chan }, 0)[1] == -1 end
  return pcall(vim.api.nvim_get_chan_info, M.chan)
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

local function reset_state()
  M.busy, M.partial, M.changed, M.ui, M.current_text, M.stopping = false, "", {}, {}, false, false
end

local function close_local()
  local chan, kind = M.chan, M.kind
  M.chan, M.kind = nil, nil
  reset_state()
  if type(chan) ~= "number" or chan <= 0 then return end
  if kind == "job" then
    M.stopping = true
    pcall(vim.fn.jobstop, chan)
  else
    pcall(vim.fn.chanclose, chan)
  end
end

local function send(obj)
  if not running() then return notify("cogcog: pi rpc is not running", vim.log.levels.ERROR) end
  M.seq = M.seq + 1
  obj.id = obj.id or ("cogcog-rpc-" .. M.seq)
  vim.fn.chansend(M.chan, vim.json.encode(obj) .. "\n")
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

local function message_text(msg)
  local out = {}
  for _, part in ipairs((msg or {}).content or {}) do
    if part.type == "text" and part.text and part.text ~= "" then out[#out + 1] = part.text end
  end
  return #out > 0 and table.concat(out, "\n") or nil
end

local function handle(line)
  local ok, obj = pcall(vim.json.decode, line)
  if not ok or type(obj) ~= "table" then return notify("cogcog: bad pi rpc message", vim.log.levels.WARN) end
  if obj.type == "response" then
    if obj.success == false then M.busy = false; notify("cogcog: pi rpc " .. (obj.error or obj.command or "error"), vim.log.levels.ERROR) end
  elseif obj.type == "agent_start" then
    M.busy, M.current_text = true, false
  elseif obj.type == "agent_end" then
    M.busy = false
    refresh_changed()
  elseif obj.type == "message_start" then
    if (obj.message or {}).role == "assistant" then M.current_text = false end
  elseif obj.type == "message_update" then
    local ev = obj.assistantMessageEvent or {}
    if ev.type == "text_delta" then M.current_text = true; append_text(ev.delta or "") end
  elseif obj.type == "message_end" then
    local msg = obj.message or {}
    if msg.role == "assistant" and msg.stopReason == "error" and msg.errorMessage then
      append_lines({ "", "✗ " .. msg.errorMessage, "" })
    elseif msg.role == "assistant" and not M.current_text then
      local text = message_text(msg)
      if text then append_text(text) end
    end
  elseif obj.type == "tool_execution_start" then
    append_lines({ "", "🔧 " .. tostring(obj.toolName or "tool") .. tool_target(obj.args), "" })
  elseif obj.type == "tool_execution_end" then
    local args, name = obj.args or {}, tostring(obj.toolName or "")
    if (name == "edit" or name == "write") and type(args.path) == "string" then M.changed[args.path] = true end
    if obj.isError then append_lines({ "", "✗ " .. name, "" }) end
  elseif obj.type == "extension_ui_request" then
    ui.handle(obj, send, notify, append_lines, M.ui)
  end
end

local function feed(data)
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
end

local function connect_socket(path)
  local chan = vim.fn.sockconnect("pipe", path, { on_data = function(_, data) feed(data) end, data_buffered = false })
  if type(chan) ~= "number" or chan <= 0 then return false end
  M.chan, M.kind = chan, "socket"
  send({ type = "broker_hello", client = "nvim", ui = true })
  notify("cogcog: attached to companion harness")
  return true
end

local function send_socket(path, obj)
  local chan = vim.fn.sockconnect("pipe", path, { on_data = function() end, data_buffered = false })
  if type(chan) ~= "number" or chan <= 0 then return false end
  vim.fn.chansend(chan, vim.json.encode(obj) .. "\n")
  vim.defer_fn(function() pcall(vim.fn.chanclose, chan) end, 50)
  return true
end

local function spawn_pi(cmd)
  local chan = vim.fn.jobstart({ "bash", "-c", cmd or config.pi_rpc_cmd() }, {
    stdout_buffered = false,
    on_stdout = function(_, data) feed(data) end,
    on_stderr = function(_, data)
      local msg = vim.trim(table.concat(data or {}, "\n"))
      if msg ~= "" then notify("pi rpc: " .. msg:sub(1, 200), vim.log.levels.WARN) end
    end,
    on_exit = function(_, code)
      local stopping = M.stopping
      M.chan, M.kind = nil, nil
      reset_state()
      if code ~= 0 and not stopping then notify("cogcog: pi rpc exited " .. code, vim.log.levels.ERROR) end
    end,
  })
  if type(chan) ~= "number" or chan <= 0 then return notify("cogcog: failed to start pi rpc", vim.log.levels.ERROR) end
  M.chan, M.kind = chan, "job"
  return true
end

function M.ensure_started(buf, cmd)
  M.buf = buf
  if running() then return true end
  reset_state()
  local socket = config.pi_socket_path()
  if socket ~= "" and uv and uv.fs_stat(socket) and connect_socket(socket) then return true end
  return spawn_pi(cmd)
end

function M.started() return running() end
function M.using_socket() return M.kind == "socket" and running() end
function M.is_busy() return M.busy end
function M.detach()
  if not running() then return false end
  close_local()
  return true
end
function M.stop_companion()
  local socket = config.pi_socket_path()
  local had_socket = socket ~= "" and uv and uv.fs_stat(socket) ~= nil
  if had_socket then send_socket(socket, { type = "broker_shutdown" }) end
  if M.kind == "socket" then close_local() end
  return had_socket
end
function M.prompt(message) if send({ type = "prompt", message = message }) then M.busy = true end end
function M.steer(message) send({ type = "steer", message = message }) end
function M.follow_up(message) send({ type = "follow_up", message = message }) end
function M.abort() if M.busy then send({ type = "abort" }) end end

return M
