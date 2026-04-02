-- cogcog.lua — thin context-building bridge to any stdin→stdout LLM command
--
-- Commands:
--   :Cog              open/focus the context buffer
--   :CogAdd <file>    append file contents with header
--   :CogCmd <cmd>     append shell command output
--   :CogYank          yank visual selection into context buffer
--   :CogSend          send context to LLM, response in split
--   :CogClear         wipe the context buffer
--
-- The context buffer is a scratch markdown buffer you edit freely.
-- You decide what goes in. The LLM sees exactly what you curated.

local M = {}

M.cmd = os.getenv("COGCOG_CMD") or "cogcog"

local ctx_buf = nil

-- open or focus the context buffer
function M.open()
  if ctx_buf and vim.api.nvim_buf_is_valid(ctx_buf) then
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(w) == ctx_buf then
        vim.api.nvim_set_current_win(w)
        return
      end
    end
    vim.cmd("vsplit")
    vim.api.nvim_win_set_buf(0, ctx_buf)
    return
  end
  vim.cmd("vsplit")
  ctx_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, ctx_buf)
  vim.bo[ctx_buf].filetype = "markdown"
  vim.bo[ctx_buf].buftype = "nofile"
  vim.api.nvim_buf_set_name(ctx_buf, "[cogcog]")
end

-- append file contents with a header
function M.add_file(path)
  M.open()
  path = vim.fn.expand(path)
  if vim.fn.filereadable(path) == 0 then
    vim.notify("cogcog: file not found: " .. path, vim.log.levels.ERROR)
    return
  end
  local lines = vim.fn.readfile(path)
  local header = { "", "--- " .. path .. " ---", "" }
  vim.api.nvim_buf_set_lines(ctx_buf, -1, -1, false, header)
  vim.api.nvim_buf_set_lines(ctx_buf, -1, -1, false, lines)
end

-- append shell command output
function M.add_cmd(cmd)
  M.open()
  local output = vim.fn.systemlist(cmd)
  local header = { "", "--- $ " .. cmd .. " ---", "" }
  vim.api.nvim_buf_set_lines(ctx_buf, -1, -1, false, header)
  vim.api.nvim_buf_set_lines(ctx_buf, -1, -1, false, output)
end

-- append arbitrary lines (from visual selection, etc.)
function M.add_lines(lines, label)
  M.open()
  label = label or "selection"
  local header = { "", "--- " .. label .. " ---", "" }
  vim.api.nvim_buf_set_lines(ctx_buf, -1, -1, false, header)
  vim.api.nvim_buf_set_lines(ctx_buf, -1, -1, false, lines)
end

-- send context buffer to LLM, show response in a horizontal split
function M.send()
  if not ctx_buf or not vim.api.nvim_buf_is_valid(ctx_buf) then
    vim.notify("cogcog: no context buffer", vim.log.levels.WARN)
    return
  end
  local lines = vim.api.nvim_buf_get_lines(ctx_buf, 0, -1, false)
  local input = table.concat(lines, "\n")
  if vim.trim(input) == "" then
    vim.notify("cogcog: context buffer is empty", vim.log.levels.WARN)
    return
  end

  vim.notify("cogcog: sending " .. #lines .. " lines...", vim.log.levels.INFO)

  local chunks = {}

  local job_id = vim.fn.jobstart(M.cmd, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data then
        for _, line in ipairs(data) do
          table.insert(chunks, line)
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        local msg = table.concat(data, "\n")
        if vim.trim(msg) ~= "" then
          vim.schedule(function()
            vim.notify("cogcog: " .. msg, vim.log.levels.ERROR)
          end)
        end
      end
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        if code ~= 0 then
          vim.notify("cogcog: exited with code " .. code, vim.log.levels.ERROR)
          return
        end
        while #chunks > 0 and chunks[#chunks] == "" do
          table.remove(chunks)
        end
        if #chunks == 0 then
          vim.notify("cogcog: empty response", vim.log.levels.WARN)
          return
        end
        local resp_buf = vim.api.nvim_create_buf(false, true)
        vim.cmd("split")
        vim.api.nvim_win_set_buf(0, resp_buf)
        vim.bo[resp_buf].filetype = "markdown"
        vim.bo[resp_buf].buftype = "nofile"
        vim.api.nvim_buf_set_name(resp_buf, "[cogcog-response]")
        vim.api.nvim_buf_set_lines(resp_buf, 0, -1, false, chunks)
        vim.notify("cogcog: done", vim.log.levels.INFO)
      end)
    end,
  })

  if job_id <= 0 then
    vim.notify("cogcog: failed to start: " .. M.cmd, vim.log.levels.ERROR)
    return
  end

  vim.fn.chansend(job_id, input)
  vim.fn.chanclose(job_id, "stdin")
end

-- clear the context buffer
function M.clear()
  if ctx_buf and vim.api.nvim_buf_is_valid(ctx_buf) then
    vim.api.nvim_buf_set_lines(ctx_buf, 0, -1, false, {})
  end
end

-- user commands
vim.api.nvim_create_user_command("Cog", function() M.open() end, {})
vim.api.nvim_create_user_command("CogAdd", function(o) M.add_file(o.args) end, { nargs = 1, complete = "file" })
vim.api.nvim_create_user_command("CogCmd", function(o) M.add_cmd(o.args) end, { nargs = "+" })
vim.api.nvim_create_user_command("CogSend", function() M.send() end, {})
vim.api.nvim_create_user_command("CogClear", function() M.clear() end, {})
vim.api.nvim_create_user_command("CogYank", function(o)
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, o.line1 - 1, o.line2, false)
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then name = "buffer" end
  M.add_lines(lines, name .. ":" .. o.line1 .. "-" .. o.line2)
end, { range = true })

return M
