-- cogcog/config.lua — shared state and config
local M = {}

M.cogcog_dir = vim.fn.getcwd() .. "/.cogcog"
M.session_file = M.cogcog_dir .. "/session.md"
M.cogcog_bin = vim.fn.exepath("cogcog") ~= "" and vim.fn.exepath("cogcog") or "cogcog"

function M.checker_cmd()
  if vim.env.COGCOG_CHECKER then return vim.env.COGCOG_CHECKER end
  if vim.fn.executable("pi") == 1 then return "pi -p --provider anthropic --model opus:xhigh" end
  return M.cogcog_bin .. " --raw"
end

return M
