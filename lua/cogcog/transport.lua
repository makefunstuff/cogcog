-- cogcog/transport.lua — emit Neovim-side events for an attached harness
local config = require("cogcog.config")
local M = {}

math.randomseed(vim.uv.hrtime())

local MAX_EVENT_FILE_BYTES = 1024 * 1024
local KEEP_ROTATED_LINES = 100

local function json_encode(value)
  if vim.json and vim.json.encode then return vim.json.encode(value) end
  return vim.fn.json_encode(value)
end

local function event_file()
  return config.cogcog_dir .. "/events.jsonl"
end

local function rotate_if_needed(path)
  local size = vim.fn.getfsize(path)
  if size < 0 or size <= MAX_EVENT_FILE_BYTES then return end

  local lines = vim.fn.readfile(path)
  local keep_from = math.max(1, #lines - KEEP_ROTATED_LINES + 1)
  local kept = {}
  for i = keep_from, #lines do
    table.insert(kept, lines[i])
  end
  vim.fn.writefile(kept, path)
end

local function event_id()
  return string.format("%x-%x", os.time(), math.random(0xffff))
end

function M.emit(kind, payload)
  vim.fn.mkdir(config.cogcog_dir, "p")

  local event = {
    id = event_id(),
    type = kind,
    cwd = vim.fn.getcwd(),
    timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    payload = payload or {},
  }

  local path = event_file()
  rotate_if_needed(path)
  vim.fn.writefile({ json_encode(event) }, path, "a")

  vim.g.cogcog_last_event = event

  pcall(vim.api.nvim_exec_autocmds, "User", {
    pattern = "CogcogEvent",
    modeline = false,
    data = event,
  })

  vim.notify("cogcog: event → " .. kind, vim.log.levels.INFO)
  return event
end

function M.event_file()
  return event_file()
end

return M
