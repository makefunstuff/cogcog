-- cogcog.lua — minimal async bridge to any stdin->stdout LLM
--
-- <leader>co  open scratch context buffer
-- <leader>cs  send buffer to LLM, response streams into split
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
