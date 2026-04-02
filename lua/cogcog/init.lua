-- cogcog — LLM as a vim verb
--
-- ga{motion} / visual ga   stateless ask → response split
-- gs{motion} / visual gs   stateless generate → code buffer
-- <C-g>                    stateful follow-up → context panel
-- <leader>cy               pin selection to context
-- <leader>co               toggle context panel
-- <leader>cc               clear context
--
-- context is just a buffer. use :read .cogcog/review.md to add skills.
-- use :read !git diff to add tools. use dap to remove sections.

local cogcog_dir = vim.fn.getcwd() .. "/.cogcog"
local session_file = cogcog_dir .. "/session.md"
local ns = vim.api.nvim_create_namespace("cogcog")

-- shared: pipe lines through cogcog, stream into a buffer

local function stream_to_buf(lines, buf, opts)
	opts = opts or {}
	local tmp = vim.fn.tempname()
	vim.fn.writefile(lines, tmp)

	local cogcog_bin = vim.fn.exepath("cogcog")
	if cogcog_bin == "" then cogcog_bin = "cogcog" end
	local flag = opts.raw and " --raw" or ""
	local first = true

	vim.notify("cogcog: thinking...", vim.log.levels.INFO)

	return vim.fn.jobstart({ "bash", "-c", cogcog_bin .. flag .. " < " .. vim.fn.shellescape(tmp) }, {
		stdout_buffered = false,
		on_stdout = function(_, data)
			if not data then return end
			vim.schedule(function()
				if not vim.api.nvim_buf_is_valid(buf) then return end
				if first then
					vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "" })
					first = false
				end
				for i, chunk in ipairs(data) do
					chunk = chunk:gsub("\27%[[%d;]*m", "") -- strip ansi
					local lc = vim.api.nvim_buf_line_count(buf)
					if i == 1 then
						local last = vim.api.nvim_buf_get_lines(buf, lc - 1, lc, false)[1] or ""
						vim.api.nvim_buf_set_lines(buf, lc - 1, lc, false, { last .. chunk })
					else
						vim.api.nvim_buf_set_lines(buf, lc, lc, false, { chunk })
					end
				end
				-- auto-scroll any window showing this buffer
				for _, w in ipairs(vim.api.nvim_list_wins()) do
					if vim.api.nvim_win_get_buf(w) == buf then
						pcall(vim.api.nvim_win_set_cursor, w, { vim.api.nvim_buf_line_count(buf), 0 })
					end
				end
			end)
		end,
		on_exit = function(_, code)
			vim.schedule(function()
				vim.fn.delete(tmp)
				if code ~= 0 then
					vim.notify("cogcog: exit " .. code, vim.log.levels.ERROR)
				else
					vim.notify("cogcog: done", vim.log.levels.INFO)
					if opts.on_done then opts.on_done() end
				end
			end)
		end,
	})
end

-- context panel (stateful, for <C-g> planning)

local function get_or_create_ctx()
	for _, b in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_get_name(b):match("%[cogcog%]$") then
			return b
		end
	end
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].filetype = "markdown"
	vim.bo[buf].buftype = "nofile"
	vim.api.nvim_buf_set_name(buf, "[cogcog]")
	local initial = vim.fn.filereadable(session_file) == 1
		and vim.fn.readfile(session_file)
		or (vim.fn.filereadable(cogcog_dir .. "/system.md") == 1
			and vim.fn.readfile(cogcog_dir .. "/system.md")
			or {})
	if #initial > 0 then vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial) end
	return buf
end

local function ctx_win()
	local buf = get_or_create_ctx()
	for _, w in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_get_buf(w) == buf then return w end
	end
end

local function show_panel()
	if ctx_win() then return end
	local buf = get_or_create_ctx()
	local width = math.floor(vim.o.columns * 0.4)
	vim.cmd("botright vsplit")
	vim.cmd("vertical resize " .. width)
	vim.api.nvim_win_set_buf(0, buf)
	for _, opt in ipairs({ "number", "relativenumber", "cursorline" }) do
		vim.api.nvim_set_option_value(opt, false, { win = 0 })
	end
	vim.api.nvim_set_option_value("signcolumn", "no", { win = 0 })
	vim.api.nvim_set_option_value("wrap", true, { win = 0 })
	vim.api.nvim_set_option_value("linebreak", true, { win = 0 })
	vim.api.nvim_set_option_value("winfixwidth", true, { win = 0 })
	vim.api.nvim_set_option_value("statusline", " cogcog", { win = 0 })
end

-- helpers

local function relative_name(path)
	if path == "" then return "scratch" end
	local cwd = vim.fn.getcwd() .. "/"
	if path:sub(1, #cwd) == cwd then return path:sub(#cwd + 1) end
	return path
end

local function get_visual_selection()
	local name = relative_name(vim.api.nvim_buf_get_name(0))
	local l1, l2 = vim.fn.line("'<"), vim.fn.line("'>")
	return vim.api.nvim_buf_get_lines(0, l1 - 1, l2, false), name, l1, l2
end

local function gather_quickfix()
	local qf = vim.fn.getqflist()
	if #qf == 0 then return {} end
	local out, seen = {}, {}
	for _, item in ipairs(qf) do
		if item.bufnr > 0 and item.lnum > 0 then
			local fname = relative_name(vim.api.nvim_buf_get_name(item.bufnr))
			local key = fname .. ":" .. item.lnum
			if not seen[key] then
				seen[key] = true
				table.insert(out, fname .. ":" .. item.lnum .. ": " .. vim.trim(item.text or ""))
			end
		end
	end
	return out
end

-- ga: stateless ask → response in a throwaway split

local function ask_send(code_lines, source, question)
	local input = {}

	-- system prompt
	local sys = cogcog_dir .. "/system.md"
	if vim.fn.filereadable(sys) == 1 then
		vim.list_extend(input, vim.fn.readfile(sys))
		table.insert(input, "")
	end

	-- quickfix
	local qf = gather_quickfix()
	if #qf > 0 then
		table.insert(input, "--- quickfix ---")
		vim.list_extend(input, qf)
		table.insert(input, "")
	end

	-- code
	if code_lines and #code_lines > 0 then
		table.insert(input, "--- " .. source .. " ---")
		table.insert(input, "")
		vim.list_extend(input, code_lines)
		table.insert(input, "")
	end

	table.insert(input, question)

	-- create throwaway response buffer
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].filetype = "markdown"
	vim.bo[buf].buftype = "nofile"

	-- open in a right split
	local width = math.floor(vim.o.columns * 0.4)
	vim.cmd("botright vsplit")
	vim.cmd("vertical resize " .. width)
	vim.api.nvim_win_set_buf(0, buf)
	vim.api.nvim_set_option_value("number", false, { win = 0 })
	vim.api.nvim_set_option_value("signcolumn", "no", { win = 0 })
	vim.api.nvim_set_option_value("wrap", true, { win = 0 })
	vim.api.nvim_set_option_value("linebreak", true, { win = 0 })
	vim.api.nvim_set_option_value("statusline", " cogcog ask │ " .. question:sub(1, 40), { win = 0 })

	-- go back to previous window so user stays in their code
	vim.cmd("wincmd p")

	stream_to_buf(input, buf, { raw = true })
end

local function ask(code_lines, source)
	vim.ui.input({ prompt = " ask: " }, function(q)
		if not q or vim.trim(q) == "" then return end
		ask_send(code_lines, source, q)
	end)
end

-- gs: stateless generate → code buffer

local function gen_send(code_lines, source, instruction)
	local input = {}

	if code_lines and #code_lines > 0 then
		table.insert(input, "--- " .. source .. " ---")
		table.insert(input, "")
		vim.list_extend(input, code_lines)
		table.insert(input, "")
	end

	-- include planning context if non-empty
	local ctx = get_or_create_ctx()
	local ctx_lines = vim.api.nvim_buf_get_lines(ctx, 0, -1, false)
	if vim.trim(table.concat(ctx_lines, "\n")) ~= "" then
		table.insert(input, "--- context ---")
		table.insert(input, "")
		vim.list_extend(input, ctx_lines)
		table.insert(input, "")
	end

	table.insert(input, instruction)
	table.insert(input, "")
	table.insert(input, "Output only the code. No explanations unless asked.")

	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].filetype = "markdown"

	local height = math.max(10, math.floor(vim.o.lines * 0.4))
	vim.cmd("botright " .. height .. "split")
	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win, buf)
	vim.api.nvim_set_option_value("number", true, { win = win })
	vim.api.nvim_set_option_value("signcolumn", "no", { win = win })
	vim.api.nvim_set_option_value("statusline",
		" cogcog gen │ " .. instruction:sub(1, 40), { win = win })
	vim.cmd("wincmd p")

	stream_to_buf(input, buf, {
		raw = false,
		on_done = function()
			if not vim.api.nvim_buf_is_valid(buf) then return end
			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			while #lines > 0 and vim.trim(lines[1]) == "" do table.remove(lines, 1) end
			while #lines > 0 and vim.trim(lines[#lines]) == "" do table.remove(lines) end
			if #lines >= 2 then
				local lang = lines[1]:match("^```(%w+)")
				if lang and lines[#lines]:match("^```%s*$") then
					table.remove(lines, 1)
					table.remove(lines)
					vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
					local ft = ({ js = "javascript", ts = "typescript", py = "python",
						rb = "ruby", rs = "rust", sh = "bash", yml = "yaml" })[lang] or lang
					vim.bo[buf].filetype = ft
				end
			end
			if vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_set_option_value("statusline",
					" cogcog gen │ done │ :w to save", { win = win })
			end
		end,
	})
end

local function gen(code_lines, source)
	vim.ui.input({ prompt = " gen: " }, function(q)
		if not q or vim.trim(q) == "" then return end
		gen_send(code_lines, source, q)
	end)
end

-- <C-g>: stateful planning → context panel

local plan_job = nil

local function plan_send(question)
	if plan_job then
		vim.notify("cogcog: running...", vim.log.levels.WARN)
		return
	end

	local ctx = get_or_create_ctx()
	if question then
		vim.api.nvim_buf_set_lines(ctx, -1, -1, false, { "", question, "", "---", "" })
	end

	show_panel()
	local lines = vim.api.nvim_buf_get_lines(ctx, 0, -1, false)

	plan_job = stream_to_buf(lines, ctx, {
		raw = true,
		on_done = function()
			plan_job = nil
			if vim.api.nvim_buf_is_valid(ctx) then
				vim.api.nvim_buf_set_lines(ctx, -1, -1, false, { "", "" })
			end
		end,
	})
end

-- session persistence

vim.api.nvim_create_autocmd("VimLeavePre", {
	callback = function()
		for _, b in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_get_name(b):match("%[cogcog%]$") then
				local lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
				if #lines > 0 and vim.trim(table.concat(lines, "")) ~= "" then
					vim.fn.mkdir(vim.fn.fnamemodify(session_file, ":h"), "p")
					vim.fn.writefile(lines, session_file)
				else
					vim.fn.delete(session_file)
				end
				return
			end
		end
	end,
})

-- operator functions

function _G._cogcog_ask_op(type)
	local s, e = vim.api.nvim_buf_get_mark(0, "["), vim.api.nvim_buf_get_mark(0, "]")
	local lines = vim.api.nvim_buf_get_lines(0, s[1] - 1, e[1], false)
	if #lines == 0 then return end
	ask(lines, relative_name(vim.api.nvim_buf_get_name(0)) .. ":" .. s[1] .. "-" .. e[1])
end

function _G._cogcog_gen_op(type)
	local s, e = vim.api.nvim_buf_get_mark(0, "["), vim.api.nvim_buf_get_mark(0, "]")
	local lines = vim.api.nvim_buf_get_lines(0, s[1] - 1, e[1], false)
	if #lines == 0 then return end
	gen(lines, relative_name(vim.api.nvim_buf_get_name(0)) .. ":" .. s[1] .. "-" .. e[1])
end

local function visual_then(fn)
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
	vim.schedule(function()
		local lines, name, l1, l2 = get_visual_selection()
		fn(lines, name .. ":" .. l1 .. "-" .. l2)
	end)
end

-- keymaps

vim.keymap.set("n", "ga", function()
	vim.o.operatorfunc = "v:lua._cogcog_ask_op"
	return "g@"
end, { expr = true, desc = "cogcog: ask about {motion}" })

vim.keymap.set("v", "ga", function() visual_then(ask) end, { desc = "cogcog: ask" })

vim.keymap.set("n", "gs", function()
	vim.o.operatorfunc = "v:lua._cogcog_gen_op"
	return "g@"
end, { expr = true, desc = "cogcog: generate from {motion}" })

vim.keymap.set("v", "gs", function() visual_then(gen) end, { desc = "cogcog: generate" })

vim.keymap.set("n", "<C-g>", function()
	vim.ui.input({ prompt = " plan: " }, function(q)
		if not q or vim.trim(q) == "" then return end
		plan_send(q)
	end)
end, { desc = "cogcog: plan" })

vim.keymap.set("v", "<leader>cy", function()
	visual_then(function(lines, source)
		local ctx = get_or_create_ctx()
		vim.api.nvim_buf_set_lines(ctx, -1, -1, false,
			{ "", "--- " .. source .. " ---", "" })
		vim.api.nvim_buf_set_lines(ctx, -1, -1, false, lines)
		vim.notify("cogcog: pinned")
	end)
end, { desc = "cogcog: pin to context" })

vim.keymap.set("n", "<leader>co", function()
	if ctx_win() then vim.api.nvim_win_close(ctx_win(), false)
	else show_panel() end
end, { desc = "cogcog: toggle panel" })

vim.keymap.set("n", "<leader>cc", function()
	local buf = get_or_create_ctx()
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
	vim.fn.delete(session_file)
	local sys = cogcog_dir .. "/system.md"
	if vim.fn.filereadable(sys) == 1 then
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.fn.readfile(sys))
	end
	vim.notify("cogcog: cleared")
end, { desc = "cogcog: clear" })
