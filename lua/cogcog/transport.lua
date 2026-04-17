-- cogcog/transport.lua — emit Neovim-side events for an attached harness
local config = require("cogcog.config")
local M = {}

math.randomseed(vim.uv.hrtime())

local WRITE_FIFO_PY = [[
import errno
import os
import sys

path = sys.argv[1]
data = sys.stdin.buffer.read()

try:
    fd = os.open(path, os.O_WRONLY | os.O_NONBLOCK)
except OSError as exc:
    if exc.errno in (errno.ENXIO, errno.ENOENT):
        sys.exit(3)
    raise

try:
    os.write(fd, data)
finally:
    os.close(fd)
]]

local function json_encode(value)
  if vim.json and vim.json.encode then return vim.json.encode(value) end
  return vim.fn.json_encode(value)
end

local function event_fifo()
  return config.event_fifo
end

local function ensure_fifo(path)
  vim.fn.mkdir(config.cogcog_dir, "p")
  vim.fn.system({
    "bash",
    "-lc",
    'if [ -e "$1" ] && [ ! -p "$1" ]; then rm -f "$1"; fi; [ -p "$1" ] || mkfifo "$1"',
    "_",
    path,
  })
end

local function send_to_fifo(path, data)
  if vim.fn.executable("python3") ~= 1 then return end
  vim.fn.system({ "python3", "-c", WRITE_FIFO_PY, path }, data)
end

local function event_id()
  return string.format("%x-%x", os.time(), math.random(0xffff))
end

function M.emit(kind, payload)
  local path = event_fifo()
  ensure_fifo(path)

  local event = {
    id = event_id(),
    type = kind,
    cwd = vim.fn.getcwd(),
    timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    payload = payload or {},
  }

  send_to_fifo(path, json_encode(event) .. "\n")

  vim.g.cogcog_last_event = event

  pcall(vim.api.nvim_exec_autocmds, "User", {
    pattern = "CogcogEvent",
    modeline = false,
    data = event,
  })

  vim.notify("cogcog: event → " .. kind, vim.log.levels.INFO)
  return event
end

function M.event_fifo()
  return event_fifo()
end

return M
