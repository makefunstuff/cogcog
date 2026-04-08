local ctx = require("cogcog.context")

local M = {}

local function respond(send, id, payload)
  payload.type, payload.id = "extension_ui_response", id
  send(payload)
end

local function split_lines(text)
  local lines = vim.split(text or "", "\n", { plain = true, trimempty = false })
  return #lines > 0 and lines or { "" }
end

local function set_editor_text(state, text)
  if not state.editor or not vim.api.nvim_buf_is_valid(state.editor) then return false end
  vim.api.nvim_buf_set_lines(state.editor, 0, -1, false, split_lines(text))
  return true
end

local function open_editor(req, send, state)
  local buf, done = vim.api.nvim_create_buf(false, true), false
  local prefill = req.prefill or state.editor_text or ""
  state.editor = buf
  vim.bo[buf].buftype, vim.bo[buf].bufhidden, vim.bo[buf].swapfile, vim.bo[buf].filetype = "nofile", "wipe", false, "markdown"
  vim.api.nvim_buf_set_name(buf, "[cogcog-pi-editor]")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, split_lines(prefill))
  local function finish(payload)
    if done then return end
    done, state.editor = true, nil
    respond(send, req.id, payload)
    if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
  end
  vim.api.nvim_create_autocmd("BufWipeout", { buffer = buf, once = true, callback = function() if not done then finish({ cancelled = true }) end end })
  vim.keymap.set({ "n", "i" }, "<C-s>", function() finish({ value = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n") }) end, { buffer = buf })
  vim.keymap.set("n", "ZZ", function() finish({ value = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n") }) end, { buffer = buf })
  vim.keymap.set("n", "q", function() finish({ cancelled = true }) end, { buffer = buf })
  vim.keymap.set("n", "ZQ", function() finish({ cancelled = true }) end, { buffer = buf })
  local win = ctx.make_split(false, buf, " ✍ pi editor │ <C-s>/ZZ submit │ q cancel ")
  vim.api.nvim_set_current_win(win)
end

function M.handle(req, send, notify, append, state)
  local prompt = req.title or req.method
  if req.message then prompt = prompt .. ": " .. req.message end
  if req.method == "notify" then
    return notify(req.message or "", ({ error = vim.log.levels.ERROR, warning = vim.log.levels.WARN })[req.notifyType] or vim.log.levels.INFO)
  elseif req.method == "setStatus" then
    return req.statusText and append({ "", "ℹ status[" .. (req.statusKey or "pi") .. "]: " .. req.statusText, "" })
  elseif req.method == "setWidget" then
    if req.widgetLines and #req.widgetLines > 0 then append(vim.list_extend({ "", "ℹ widget[" .. (req.widgetKey or "pi") .. "]", "" }, req.widgetLines)) end
    return
  elseif req.method == "setTitle" then
    return
  elseif req.method == "set_editor_text" then
    state.editor_text = req.text or ""
    if not set_editor_text(state, state.editor_text) then notify("cogcog: no active pi editor", vim.log.levels.WARN) end
    return
  end
  vim.schedule(function()
    if req.method == "select" then
      vim.ui.select(req.options or {}, { prompt = prompt }, function(value) respond(send, req.id, value ~= nil and { value = value } or { cancelled = true }) end)
    elseif req.method == "confirm" then
      vim.ui.select({ "Yes", "No" }, { prompt = prompt }, function(value) respond(send, req.id, value ~= nil and { confirmed = value == "Yes" } or { cancelled = true }) end)
    elseif req.method == "input" then
      vim.ui.input({ prompt = prompt .. ((req.placeholder and req.placeholder ~= "") and " (" .. req.placeholder .. ")" or "") .. ": " }, function(value) respond(send, req.id, value ~= nil and { value = value } or { cancelled = true }) end)
    elseif req.method == "editor" then
      open_editor(req, send, state)
    else
      respond(send, req.id, { cancelled = true })
      notify("cogcog: pi requested unsupported UI: " .. tostring(req.method), vim.log.levels.WARN)
    end
  end)
end

return M
