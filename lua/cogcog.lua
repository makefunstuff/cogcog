-- cogcog.lua — minimal async bridge to any stdin->stdout LLM
--
-- <leader>co  open scratch context buffer
-- <leader>ci  inspect sections, jump to one
-- <leader>cd  delete section under cursor
-- <leader>ct  dump project tree into context
-- <leader>cb  dump all open buffers into context
-- <leader>cs  send buffer to LLM, response streams into split
-- visual <leader>cs  send selection to LLM, response to clipboard
-- visual <leader>cy  yank selection into context buffer

local cmd = os.getenv("COGCOG_CMD") or "cogcog"

local function get_or_create_ctx()
	-- find existing [cogcog] buffer
	for _, b in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_get_name(b):match("%[cogcog%]$") then
			return b
		end
	end
	-- create new one
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].filetype = "markdown"
	vim.bo[buf].buftype = "nofile"
	vim.api.nvim_buf_set_name(buf, "[cogcog]")
	return buf
end

local function focus_ctx()
	local buf = get_or_create_ctx()
	-- check if already visible in a window
	for _, w in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_get_buf(w) == buf then
			vim.api.nvim_set_current_win(w)
			return buf
		end
	end
	vim.cmd("vsplit")
	vim.api.nvim_win_set_buf(0, buf)
	return buf
end

vim.keymap.set("n", "<leader>co", function()
	focus_ctx()
end, { desc = "cogcog: open context" })

-- inspect: list all --- sections, jump to selected
vim.keymap.set("n", "<leader>ci", function()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local sections = {}
	for i, line in ipairs(lines) do
		if line:match("^%-%-%- .+ %-%-%-$") then
			table.insert(sections, { lnum = i, text = line })
		end
	end
	if #sections == 0 then
		vim.notify("cogcog: no sections found", vim.log.levels.WARN)
		return
	end
	vim.ui.select(sections, {
		prompt = "Jump to section:",
		format_item = function(item)
			return string.format("L%-4d %s", item.lnum, item.text)
		end,
	}, function(choice)
		if choice then
			vim.api.nvim_win_set_cursor(0, { choice.lnum, 0 })
			vim.cmd("normal! zt")
		end
	end)
end, { desc = "cogcog: inspect sections" })

-- delete section under cursor (from --- header to next --- header or end)
vim.keymap.set("n", "<leader>cd", function()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local cur = vim.api.nvim_win_get_cursor(0)[1]

	-- find section start: search backwards for --- header
	local start = nil
	for i = cur, 1, -1 do
		if lines[i]:match("^%-%-%- .+ %-%-%-$") then
			start = i
			break
		end
	end
	if not start then
		vim.notify("cogcog: not in a section", vim.log.levels.WARN)
		return
	end

	-- include blank line before header if present
	if start > 1 and vim.trim(lines[start - 1]) == "" then
		start = start - 1
	end

	-- find section end: next --- header or end of buffer
	local stop = #lines
	for i = start + 2, #lines do
		if lines[i]:match("^%-%-%- .+ %-%-%-$") then
			stop = i - 1
			-- trim trailing blank line
			if stop >= start and vim.trim(lines[stop]) == "" then
				stop = stop - 1
			end
			break
		end
	end

	vim.api.nvim_buf_set_lines(0, start - 1, stop, false, {})
	vim.notify("cogcog: deleted " .. (stop - start + 1) .. " lines")
end, { desc = "cogcog: delete section" })

-- dump all open file buffers into the current buffer
vim.keymap.set("n", "<leader>cb", function()
	local current = vim.api.nvim_get_current_buf()
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if buf ~= current and vim.api.nvim_buf_is_loaded(buf) then
			local name = vim.api.nvim_buf_get_name(buf)
			if name ~= "" and vim.bo[buf].buftype == "" then
				local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
				local header = { "", "--- " .. name .. " ---", "" }
				vim.api.nvim_buf_set_lines(current, -1, -1, false, header)
				vim.api.nvim_buf_set_lines(current, -1, -1, false, lines)
			end
		end
	end
	vim.notify("cogcog: added open buffers")
end, { desc = "cogcog: add open buffers" })

-- dump project tree into the current buffer
vim.keymap.set("n", "<leader>ct", function()
	local output = vim.fn.systemlist("tree -I 'node_modules|.git|__pycache__|.next|dist|build' --noreport -L 4 2>/dev/null || find . -maxdepth 4 -not -path '*/.git/*' -not -path '*/node_modules/*' | head -80")
	local header = { "", "--- project tree ---", "" }
	local current = vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_set_lines(current, -1, -1, false, header)
	vim.api.nvim_buf_set_lines(current, -1, -1, false, output)
	vim.notify("cogcog: added tree")
end, { desc = "cogcog: add project tree" })

-- visual: send selection directly to LLM
vim.keymap.set("v", "<leader>cs", function()
	local l1 = vim.fn.line("'<")
	local l2 = vim.fn.line("'>")
	local lines = vim.api.nvim_buf_get_lines(0, l1 - 1, l2, false)
	local input = table.concat(lines, "\n")
	if vim.trim(input) == "" then return end
	vim.fn.setreg("+", vim.fn.system(cmd, input))
	vim.notify("cogcog: response in clipboard")
end, { desc = "cogcog: send selection" })

-- visual: yank selection into context buffer
vim.keymap.set("v", "<leader>cy", function()
	local buf = vim.api.nvim_get_current_buf()
	local name = vim.api.nvim_buf_get_name(buf)
	if name == "" then name = "buffer" end
	local l1 = vim.fn.line("'<")
	local l2 = vim.fn.line("'>")
	local lines = vim.api.nvim_buf_get_lines(buf, l1 - 1, l2, false)
	local ctx = get_or_create_ctx()

	local header = { "", "--- " .. name .. ":" .. l1 .. "-" .. l2 .. " ---", "" }
	vim.api.nvim_buf_set_lines(ctx, -1, -1, false, header)
	vim.api.nvim_buf_set_lines(ctx, -1, -1, false, lines)
	vim.notify("cogcog: yanked " .. (l2 - l1 + 1) .. " lines to context")
end, { desc = "cogcog: yank to context" })

vim.keymap.set("n", "<leader>cs", function()
	local ctx = get_or_create_ctx()
	local lines = vim.api.nvim_buf_get_lines(ctx, 0, -1, false)
	local input = table.concat(lines, "\n")
	if vim.trim(input) == "" then
		vim.notify("cogcog: context buffer is empty — use <leader>cy to yank code into it", vim.log.levels.WARN)
		return
	end

	-- create response buffer immediately so you see streaming output
	local resp_buf = vim.api.nvim_create_buf(false, true)
	vim.cmd("split")
	vim.api.nvim_win_set_buf(0, resp_buf)
	vim.bo[resp_buf].filetype = "markdown"
	vim.bo[resp_buf].buftype = "nofile"
	vim.api.nvim_buf_set_name(resp_buf, "[cogcog-response]")
	vim.api.nvim_buf_set_lines(resp_buf, 0, -1, false, { "cogcog: waiting..." })

	local partial = ""

	local id = vim.fn.jobstart(cmd, {
		on_stdout = function(_, data)
			if not data then return end
			for i, chunk in ipairs(data) do
				if i == 1 then
					partial = partial .. chunk
				else
					vim.schedule(function()
						if not vim.api.nvim_buf_is_valid(resp_buf) then return end
						local lc = vim.api.nvim_buf_line_count(resp_buf)
						-- first chunk replaces the "waiting..." line
						if lc == 1 and vim.api.nvim_buf_get_lines(resp_buf, 0, 1, false)[1] == "cogcog: waiting..." then
							vim.api.nvim_buf_set_lines(resp_buf, 0, 1, false, { partial })
						else
							vim.api.nvim_buf_set_lines(resp_buf, lc - 1, lc, false, { partial })
						end
					end)
					partial = chunk
				end
			end
		end,
		on_stderr = function(_, data)
			if data then
				local msg = vim.trim(table.concat(data, "\n"))
				if msg ~= "" then
					vim.schedule(function()
						vim.notify("cogcog: " .. msg, vim.log.levels.ERROR)
					end)
				end
			end
		end,
		on_exit = function(_, code)
			vim.schedule(function()
				if not vim.api.nvim_buf_is_valid(resp_buf) then return end
				if code ~= 0 then
					vim.notify("cogcog: exit " .. code, vim.log.levels.ERROR)
					return
				end
				-- flush remaining partial line
				if partial ~= "" then
					local lc = vim.api.nvim_buf_line_count(resp_buf)
					if lc == 1 and vim.api.nvim_buf_get_lines(resp_buf, 0, 1, false)[1] == "cogcog: waiting..." then
						vim.api.nvim_buf_set_lines(resp_buf, 0, 1, false, { partial })
					else
						vim.api.nvim_buf_set_lines(resp_buf, lc - 1, lc, false, { partial })
					end
				end
				vim.notify("cogcog: done")
			end)
		end,
	})

	if id <= 0 then
		vim.notify("cogcog: failed to start", vim.log.levels.ERROR)
		return
	end
	vim.fn.chansend(id, input)
	vim.fn.chanclose(id, "stdin")
end, { desc = "cogcog: send" })
