-- cogcog.lua — minimal async bridge to any stdin->stdout LLM
--
-- <leader>co  open scratch context buffer
-- <leader>cs  send buffer to LLM, response in split
--
-- build context with native vim:
--   :read src/main.ts          add a file
--   :read !git log -10         add command output
--   :'<,'>y then paste         add a selection

local cmd = os.getenv("COGCOG_CMD") or "cogcog"

vim.keymap.set("n", "<leader>co", function()
	vim.cmd("enew | setlocal buftype=nofile ft=markdown")
end, { desc = "cogcog: open context" })

vim.keymap.set("n", "<leader>cs", function()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local input = table.concat(lines, "\n")
	if vim.trim(input) == "" then
		vim.notify("cogcog: empty", vim.log.levels.WARN)
		return
	end

	vim.notify("cogcog: sending " .. #lines .. " lines...")
	local chunks = {}

	local id = vim.fn.jobstart(cmd, {
		stdout_buffered = true,
		on_stdout = function(_, data)
			if data then
				vim.list_extend(chunks, data)
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
				if code ~= 0 then
					vim.notify("cogcog: exit " .. code, vim.log.levels.ERROR)
					return
				end
				while #chunks > 0 and chunks[#chunks] == "" do
					table.remove(chunks)
				end
				if #chunks == 0 then
					vim.notify("cogcog: empty response", vim.log.levels.WARN)
					return
				end
				local buf = vim.api.nvim_create_buf(false, true)
				vim.cmd("split")
				vim.api.nvim_win_set_buf(0, buf)
				vim.bo[buf].filetype = "markdown"
				vim.bo[buf].buftype = "nofile"
				vim.api.nvim_buf_set_lines(buf, 0, -1, false, chunks)
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
