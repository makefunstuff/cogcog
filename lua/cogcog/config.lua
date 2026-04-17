-- cogcog/config.lua — shared state and config
local M = {}

local function module_source_path()
  local source = debug.getinfo(1, "S").source or ""
  return source:sub(1, 1) == "@" and source:sub(2) or source
end

local function repo_root()
  return vim.fn.fnamemodify(module_source_path(), ":h:h:h")
end

local function bundled_bin(name)
  local path = repo_root() .. "/bin/" .. name
  if vim.fn.executable(path) == 1 then return path end
end

local function bundled_cogcog_bin()
  return bundled_bin("cogcog")
end

M.cogcog_dir = vim.fn.getcwd() .. "/.cogcog"
M.workbench_file = M.cogcog_dir .. "/workbench.md"
M.legacy_session_file = M.cogcog_dir .. "/session.md"
M.session_file = M.workbench_file -- backward-compatible alias
M.discovery_file = M.cogcog_dir .. "/discovery.md"
M.event_fifo = M.cogcog_dir .. "/events.fifo"
M.cogcog_bin = bundled_cogcog_bin() or (vim.fn.exepath("cogcog") ~= "" and vim.fn.exepath("cogcog")) or "cogcog"

function M.readable_workbench_file()
  if vim.fn.filereadable(M.workbench_file) == 1 then return M.workbench_file end
  if vim.fn.filereadable(M.legacy_session_file) == 1 then return M.legacy_session_file end
end

function M.checker_cmd()
  if vim.env.COGCOG_CHECKER and vim.trim(vim.env.COGCOG_CHECKER) ~= "" then
    return vim.env.COGCOG_CHECKER
  end
  return M.cogcog_bin .. " --raw"
end

function M.agent_cmd()
  if vim.env.COGCOG_AGENT_CMD and vim.trim(vim.env.COGCOG_AGENT_CMD) ~= "" then
    return vim.env.COGCOG_AGENT_CMD
  end
end

function M.kb_path()
  if vim.env.COGCOG_KB and vim.trim(vim.env.COGCOG_KB) ~= "" then
    local p = vim.env.COGCOG_KB
    if vim.fn.isdirectory(p) == 1 then return p end
  end
end

return M
