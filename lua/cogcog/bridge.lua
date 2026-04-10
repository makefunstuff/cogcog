-- cogcog/bridge.lua — Expose Neovim state to external tools (pi extension).
-- Called via: nvim --server /tmp/cogcog.sock --remote-expr "luaeval('...')"

local M = {}

local function rel(path)
  return vim.fn.fnamemodify(path, ":.")
end

--- Current editor state: buffer, cursor, visible windows, quickfix, diagnostics.
function M.get_context()
  local buf = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()
  local name = rel(vim.api.nvim_buf_get_name(buf))
  local cursor = vim.api.nvim_win_get_cursor(win)
  local row = cursor[1]

  -- lines around cursor (±10)
  local total = vim.api.nvim_buf_line_count(buf)
  local s = math.max(0, row - 11)
  local e = math.min(total, row + 10)
  local lines = vim.api.nvim_buf_get_lines(buf, s, e, false)

  -- visible windows
  local windows = {}
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(w).relative == "" then
      local b = vim.api.nvim_win_get_buf(w)
      local bname = rel(vim.api.nvim_buf_get_name(b))
      if bname ~= "" then
        table.insert(windows, {
          buffer = bname,
          cursor = vim.api.nvim_win_get_cursor(w),
          filetype = vim.bo[b].filetype,
          modified = vim.bo[b].modified,
        })
      end
    end
  end

  -- quickfix
  local qf = {}
  for _, item in ipairs(vim.fn.getqflist()) do
    if item.bufnr > 0 then
      table.insert(qf, {
        filename = rel(vim.api.nvim_buf_get_name(item.bufnr)),
        lnum = item.lnum,
        text = item.text,
      })
    end
  end

  -- diagnostics summary
  local diags = vim.diagnostic.get()
  local counts = { 0, 0, 0, 0 }
  for _, d in ipairs(diags) do counts[d.severity] = (counts[d.severity] or 0) + 1 end

  -- modified buffers
  local modified = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].modified then
      local bname = rel(vim.api.nvim_buf_get_name(b))
      if bname ~= "" then table.insert(modified, bname) end
    end
  end

  return vim.json.encode({
    cwd = vim.fn.getcwd(),
    buffer = name ~= "" and name or nil,
    cursor = cursor,
    filetype = vim.bo[buf].filetype,
    cursor_line = row,
    lines_start = s + 1,
    lines = lines,
    windows = windows,
    quickfix = #qf > 0 and qf or nil,
    diagnostics = { errors = counts[1], warnings = counts[2], info = counts[3], hints = counts[4] },
    modified_buffers = #modified > 0 and modified or nil,
  })
end

--- LSP diagnostics. Optional JSON arg: {"path":"file.ts"}
function M.get_diagnostics(args_json)
  local args = args_json and vim.json.decode(args_json) or {}
  local bufnr = nil
  if args.path and args.path ~= "" then
    bufnr = vim.fn.bufnr(args.path)
    if bufnr < 0 then
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if rel(vim.api.nvim_buf_get_name(b)) == args.path then bufnr = b; break end
      end
    end
    if not bufnr or bufnr < 0 then return vim.json.encode({}) end
  end

  local result = {}
  for _, d in ipairs(vim.diagnostic.get(bufnr)) do
    table.insert(result, {
      filename = rel(vim.api.nvim_buf_get_name(d.bufnr)),
      lnum = d.lnum + 1,
      col = d.col + 1,
      severity = ({ "error", "warning", "info", "hint" })[d.severity] or "?",
      message = d.message,
      source = d.source,
    })
  end
  return vim.json.encode(result)
end

--- Read buffer content. Optional JSON arg: {"path":"file.ts"}
function M.get_buffer(args_json)
  local args = args_json and vim.json.decode(args_json) or {}
  local bufnr
  if args.path and args.path ~= "" then
    bufnr = vim.fn.bufnr(args.path)
    if bufnr < 0 then
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if rel(vim.api.nvim_buf_get_name(b)) == args.path then bufnr = b; break end
      end
    end
    if not bufnr or bufnr < 0 then return vim.json.encode({ error = "buffer not found: " .. args.path }) end
  else
    bufnr = vim.api.nvim_get_current_buf()
  end

  return vim.json.encode({
    name = rel(vim.api.nvim_buf_get_name(bufnr)),
    filetype = vim.bo[bufnr].filetype,
    lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false),
    modified = vim.bo[bufnr].modified,
    line_count = vim.api.nvim_buf_line_count(bufnr),
  })
end

--- List all loaded file buffers.
function M.get_buffers()
  local result = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buftype == "" then
      local name = rel(vim.api.nvim_buf_get_name(b))
      if name ~= "" then
        table.insert(result, {
          name = name,
          filetype = vim.bo[b].filetype,
          modified = vim.bo[b].modified,
          line_count = vim.api.nvim_buf_line_count(b),
        })
      end
    end
  end
  return vim.json.encode(result)
end

--- Open file at line in the user's editor. JSON arg: {"path":"file.ts","line":42}
function M.goto_file(args_json)
  local args = vim.json.decode(args_json)
  vim.schedule(function()
    vim.cmd("edit " .. vim.fn.fnameescape(args.path))
    if args.line and args.line > 0 then
      pcall(vim.api.nvim_win_set_cursor, 0, { args.line, 0 })
      vim.cmd("normal! zz")
    end
  end)
  return vim.json.encode({ ok = true, path = args.path, line = args.line })
end

--- Set quickfix list. JSON arg: {"items":[{"filename":"f","lnum":1,"text":"msg"},...], "title":"..."}
--- Items can also have "col" and "type" ("E","W","I","H").
function M.set_quickfix(args_json)
  local args = vim.json.decode(args_json)
  local items = args.items or {}
  vim.schedule(function()
    local qf = {}
    for _, item in ipairs(items) do
      table.insert(qf, {
        filename = item.filename,
        lnum = item.lnum or 1,
        col = item.col or 0,
        text = item.text or "",
        type = item.type or "",
      })
    end
    vim.fn.setqflist({}, " ", {
      title = args.title or "pi",
      items = qf,
    })
    if #qf > 0 then vim.cmd("copen") end
  end)
  return vim.json.encode({ ok = true, count = #items })
end

--- Run a vim command. JSON arg: {"cmd":"make","silent":true}
function M.exec(args_json)
  local args = vim.json.decode(args_json)
  local output = ""
  vim.schedule(function()
    local ok, err = pcall(function()
      output = vim.api.nvim_exec2(args.cmd, { output = true }).output or ""
    end)
    if not ok then
      vim.notify("cogcog bridge exec error: " .. tostring(err), vim.log.levels.ERROR)
    end
  end)
  return vim.json.encode({ ok = true, cmd = args.cmd })
end

--- Send a notification. JSON arg: {"msg":"done","level":"info"}
function M.notify(args_json)
  local args = vim.json.decode(args_json)
  local levels = { error = vim.log.levels.ERROR, warn = vim.log.levels.WARN, info = vim.log.levels.INFO }
  vim.schedule(function()
    vim.notify(args.msg or "", levels[args.level] or vim.log.levels.INFO)
  end)
  return vim.json.encode({ ok = true })
end

return M
