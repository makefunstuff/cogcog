-- cogcog/stream.lua — shared streaming to buffer
local config = require("cogcog.config")
local M = {}

M.active_jobs = {}

local function strip_ansi(s) return s:gsub("\27%[[%d;]*m", "") end

-- Stream command output into a buffer
-- opts:
--   raw (bool)          — pass --raw flag
--   cmd (string)        — override command (default: cogcog binary)
--   on_done (fn)        — callback on success
--   on_error (fn)       — callback on failure
--   stderr_to_buf (bool) — show stderr in the buffer (for exec mode)
function M.to_buf(lines, buf, opts)
  opts = opts or {}
  local cogcog_bin = config.cogcog_bin

  local tmp = vim.fn.tempname()
  vim.fn.writefile(lines, tmp)

  local flag = opts.raw and " --raw" or ""
  local shell_cmd = (opts.cmd or cogcog_bin) .. flag .. " < " .. vim.fn.shellescape(tmp)
  local first = true

  -- show placeholder (only one, replace existing if present)
  if vim.api.nvim_buf_is_valid(buf) then
    local lc = vim.api.nvim_buf_line_count(buf)
    local last = vim.api.nvim_buf_get_lines(buf, lc - 1, lc, false)[1] or ""
    if last:match("^⏳") then
      -- already has a placeholder, don't add another
    elseif last == "" then
      vim.api.nvim_buf_set_lines(buf, lc - 1, lc, false, { "⏳ thinking..." })
    else
      vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "⏳ thinking..." })
    end
  end

  local job = vim.fn.jobstart({ "bash", "-c", shell_cmd }, {
    stdout_buffered = false,
    on_stderr = function(_, data)
      if not data then return end
      local msg = vim.trim(table.concat(data, "\n"))
      msg = strip_ansi(msg)
      if msg == "" or msg:match("^%s*$") then return end

      if opts.stderr_to_buf and vim.api.nvim_buf_is_valid(buf) then
        -- show in buffer as indented lines (exec mode)
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then return end
          local lc = vim.api.nvim_buf_line_count(buf)
          local slines = vim.split(msg, "\n")
          for j, line in ipairs(slines) do slines[j] = "  " .. line end
          vim.api.nvim_buf_set_lines(buf, lc, lc, false, slines)
          M._scroll_buf(buf)
        end)
      else
        -- classify: progress messages vs real errors
        vim.schedule(function()
          local progress_patterns = {
            "^> build", "^⚙", "^✓", "^✗",
            "reading", "writing", "running", "searching",
            "[Tt]ool", "[Ee]dit", "[Bb]ash", "[Rr]ead", "[Ww]rite", "[Ss]earch",
            "tokens", "model", "session",
          }
          for _, pat in ipairs(progress_patterns) do
            if msg:match(pat) then
              vim.notify("⚙ " .. msg:sub(1, 120), vim.log.levels.INFO)
              return
            end
          end
          vim.notify("cogcog: " .. msg:sub(1, 200), vim.log.levels.ERROR)
        end)
      end
    end,
    on_stdout = function(_, data)
      if not data then return end
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        if first then
          -- clear the "..." placeholder
          local lc = vim.api.nvim_buf_line_count(buf)
          local last = vim.api.nvim_buf_get_lines(buf, lc - 1, lc, false)[1] or ""
          if last:match("^⏳") then
            vim.api.nvim_buf_set_lines(buf, lc - 1, lc, false, { "" })
          elseif last ~= "" then
            vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "" })
          end
          first = false
        end
        for i, chunk in ipairs(data) do
          chunk = strip_ansi(chunk)
          if chunk:match("^> build") then chunk = "" end
          local lc = vim.api.nvim_buf_line_count(buf)
          if i == 1 then
            local last = vim.api.nvim_buf_get_lines(buf, lc - 1, lc, false)[1] or ""
            vim.api.nvim_buf_set_lines(buf, lc - 1, lc, false, { last .. chunk })
          else
            vim.api.nvim_buf_set_lines(buf, lc, lc, false, { chunk })
          end
        end
        M._scroll_buf(buf)
      end)
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        vim.fn.delete(tmp)
        if job then M.active_jobs[job] = nil end
        if code ~= 0 then
          vim.notify("✗ cogcog exit " .. code, vim.log.levels.ERROR)
          if opts.on_error then opts.on_error(code) end
        else
          vim.notify("✓ cogcog done", vim.log.levels.INFO)
          if opts.on_done then opts.on_done() end
        end
      end)
    end,
  })

  if type(job) == "number" and job > 0 then M.active_jobs[job] = true end
  return job
end

function M._scroll_buf(buf)
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(w) == buf then
      pcall(vim.api.nvim_win_set_cursor, w, { vim.api.nvim_buf_line_count(buf), 0 })
    end
  end
end

function M.cancel_all()
  local count = 0
  for j in pairs(M.active_jobs) do
    pcall(vim.fn.jobstop, j)
    count = count + 1
  end
  M.active_jobs = {}
  if count > 0 then vim.notify("cogcog: cancelled", vim.log.levels.INFO) end
end

return M
