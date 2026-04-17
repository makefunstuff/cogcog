-- cogcog/transport.lua — emit Neovim-side events to the attached pi channel
local M = {}

math.randomseed(vim.uv.hrtime())

local function event_id()
  return string.format("%x-%x", os.time(), math.random(0xffff))
end

local function target_channel()
  local channel = vim.g.cogcog_pi_owner_channel
  if type(channel) == "number" then return channel end
  if type(channel) == "string" then return tonumber(channel) end
end

function M.emit(kind, payload)
  local event = {
    id = event_id(),
    type = kind,
    cwd = vim.fn.getcwd(),
    timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    payload = payload or {},
  }

  local channel = target_channel()
  local ok, reason
  if channel then
    ok, reason = pcall(vim.rpcnotify, channel, "cogcog_notify", event)
    if not ok then vim.g.cogcog_pi_owner_channel = nil end
  else
    ok, reason = false, "no-listener"
  end

  vim.g.cogcog_last_event = event

  pcall(vim.api.nvim_exec_autocmds, "User", {
    pattern = "CogcogEvent",
    modeline = false,
    data = event,
  })

  if ok then
    vim.notify("cogcog: event → " .. kind, vim.log.levels.INFO)
  elseif reason == "no-listener" then
    vim.notify("cogcog: no pi listener for " .. kind, vim.log.levels.WARN)
  else
    vim.notify("cogcog: failed to emit " .. kind .. " (" .. tostring(reason) .. ")", vim.log.levels.ERROR)
  end
  return event
end

function M.target_channel()
  return target_channel()
end

return M
