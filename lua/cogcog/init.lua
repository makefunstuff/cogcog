-- cogcog — LLM as a vim verb
--
-- ga{motion}  ask about text object (e.g. gaip = ask about paragraph)
-- ga         (visual) ask about selection
-- <C-g>      ask / follow-up from anywhere (no selection needed)
-- <leader>cy (visual) pin selection to context (no send)
-- <leader>cl toggle skills/tools
-- <leader>co toggle context panel visibility
-- <leader>cc clear context + start fresh

local job_id = nil
local cogcog_dir = vim.fn.getcwd() .. "/.cogcog"
local session_file = cogcog_dir .. "/session.md"

-- spinner
local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local spinner_timer = nil
local spinner_idx = 0

-- skills and tools

local builtin_tools = {
	tree =
	"tree -I 'node_modules|.git|__pycache__|.next|dist|build|target' --noreport -L 4 2>/dev/null || find . -maxdepth 4 -not -path '*/.git/*' | head -80",
	diff = "git diff 2>/dev/null",
	staged = "git diff --staged 2>/dev/null",
	log = "git log --oneline -20 2>/dev/null",
}

local function load_system_prompt()
	local f = cogcog_dir .. "/system.md"
	if vim.fn.filereadable(f) == 1 then return vim.fn.readfile(f) end
	return {}
end

local function list_skills()
	local skills = {}
	local dirs = { cogcog_dir .. "/skills", cogcog_dir }
	for _, dir in ipairs(dirs) do
		for _, f in ipairs(vim.fn.glob(dir .. "/*.md", false, true)) do
			local name = vim.fn.fnamemodify(f, ":t"):gsub("%.md$", "")
			if name ~= "system" and name ~= "session" then
				skills[name] = skills[name] or f
			end
		end
	end
	local result = {}
	for name, path in pairs(skills) do
		table.insert(result, { name = name, path = path })
	end
	table.sort(result, function(a, b) return a.name < b.name end)
	return result
end

-- context buffer

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
		or load_system_prompt()
	if #initial > 0 then vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial) end

	return buf
end

local function ctx_win()
	local buf = get_or_create_ctx()
	for _, w in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_get_buf(w) == buf then return w end
	end
	return nil
end

local function setup_win(w)
	vim.api.nvim_set_option_value("number", false, { win = w })
	vim.api.nvim_set_option_value("relativenumber", false, { win = w })
	vim.api.nvim_set_option_value("signcolumn", "no", { win = w })
	vim.api.nvim_set_option_value("wrap", true, { win = w })
	vim.api.nvim_set_option_value("linebreak", true, { win = w })
	vim.api.nvim_set_option_value("cursorline", false, { win = w })
	vim.api.nvim_set_option_value("statusline", " cogcog", { win = w })
	vim.api.nvim_set_option_value("winfixwidth", true, { win = w })
end

local function show_panel()
	local w = ctx_win()
	if w then return w end
	local buf = get_or_create_ctx()
	-- open on the right, 40% width
	local width = math.floor(vim.o.columns * 0.4)
	vim.cmd("botright vsplit")
	vim.cmd("vertical resize " .. width)
	w = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(w, buf)
	setup_win(w)
	return w
end

local function hide_panel()
	local w = ctx_win()
	if w then vim.api.nvim_win_close(w, false) end
end

local function toggle_panel()
	if ctx_win() then hide_panel() else show_panel() end
end

local function ensure_panel()
	if not ctx_win() then show_panel() end
end

local function append(lines)
	local buf = get_or_create_ctx()
	vim.api.nvim_buf_set_lines(buf, -1, -1, false, lines)
end

local function scroll_bottom()
	local w = ctx_win()
	if not w then return end
	local buf = get_or_create_ctx()
	local lc = vim.api.nvim_buf_line_count(buf)
	vim.api.nvim_win_set_cursor(w, { lc, 0 })
end

local function relative_name(path)
	if path == "" then return "scratch" end
	local cwd = vim.fn.getcwd() .. "/"
	if path:sub(1, #cwd) == cwd then return path:sub(#cwd + 1) end
	return path
end

-- section management

local function find_section(tag)
	local buf = get_or_create_ctx()
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	for i, line in ipairs(lines) do
		if line == "--- " .. tag .. " ---" then return i end
	end
	return nil
end

local function remove_section(tag)
	local buf = get_or_create_ctx()
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local start = nil
	for i, line in ipairs(lines) do
		if line == "--- " .. tag .. " ---" then
			start = i; break
		end
	end
	if not start then return false end
	local s = start
	if s > 1 and vim.trim(lines[s - 1]) == "" then s = s - 1 end
	local stop = #lines
	for i = start + 1, #lines do
		if lines[i]:match("^%-%-%- .+ %-%-%-$") then
			stop = i - 1
			if stop >= s and vim.trim(lines[stop]) == "" then stop = stop - 1 end
			break
		end
	end
	vim.api.nvim_buf_set_lines(buf, s - 1, stop, false, {})
	return true
end

local function add_skill(name, path)
	if find_section("skill:" .. name) then return end
	append({ "", "--- skill:" .. name .. " ---", "" })
	append(vim.fn.readfile(path))
end

local function add_tool(name)
	local tag = "tool:" .. name
	if find_section(tag) then return end
	local cmd = builtin_tools[name]
	if not cmd then return end
	local output = vim.fn.systemlist(cmd)
	if #output > 0 and vim.trim(table.concat(output, "")) ~= "" then
		append({ "", "--- " .. tag .. " ---", "" })
		append(output)
	end
end

-- save/restore

local function save_session()
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
end

vim.api.nvim_create_autocmd("VimLeavePre", { callback = save_session })

-- spinner

local function start_spinner(buf)
	spinner_idx = 0
	if spinner_timer then spinner_timer:stop() end
	spinner_timer = vim.uv.new_timer()
	spinner_timer:start(0, 80, vim.schedule_wrap(function()
		if not vim.api.nvim_buf_is_valid(buf) or not job_id then
			if spinner_timer then
				spinner_timer:stop(); spinner_timer = nil
			end
			return
		end
		spinner_idx = (spinner_idx + 1) % #spinner_frames
		local lc = vim.api.nvim_buf_line_count(buf)
		local last = vim.api.nvim_buf_get_lines(buf, lc - 1, lc, false)[1] or ""
		if last:match("^[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]") then
			vim.api.nvim_buf_set_lines(buf, lc - 1, lc, false,
				{ spinner_frames[spinner_idx + 1] .. " thinking..." })
		end
	end))
end

local function stop_spinner(buf)
	if spinner_timer then
		spinner_timer:stop(); spinner_timer = nil
	end
	if not vim.api.nvim_buf_is_valid(buf) then return end
	local lc = vim.api.nvim_buf_line_count(buf)
	local last = vim.api.nvim_buf_get_lines(buf, lc - 1, lc, false)[1] or ""
	if last:match("^[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]") then
		vim.api.nvim_buf_set_lines(buf, lc - 1, lc, false, { "" })
	end
end

-- send

local function send()
	if job_id then
		vim.notify("cogcog: running...", vim.log.levels.WARN)
		return
	end

	local ctx = get_or_create_ctx()
	local lines = vim.api.nvim_buf_get_lines(ctx, 0, -1, false)
	local input = table.concat(lines, "\n")
	if vim.trim(input) == "" then
		vim.notify("cogcog: empty", vim.log.levels.WARN)
		return
	end

	ensure_panel()
	local tmp = vim.fn.tempname()
	vim.fn.writefile(lines, tmp)

	append({ "", "---", "", spinner_frames[1] .. " thinking..." })
	scroll_bottom()
	start_spinner(ctx)

	local shell_cmd = "cogcog < " .. vim.fn.shellescape(tmp)
	local first_output = true

	job_id = vim.fn.jobstart({ "bash", "-lc", shell_cmd }, {
		stdout_buffered = false,
		on_stdout = function(_, data)
			if not data then return end
			vim.schedule(function()
				if not vim.api.nvim_buf_is_valid(ctx) then return end
				if first_output then
					stop_spinner(ctx)
					first_output = false
				end
				for i, chunk in ipairs(data) do
					local lc = vim.api.nvim_buf_line_count(ctx)
					if i == 1 then
						local last = vim.api.nvim_buf_get_lines(ctx, lc - 1, lc, false)[1] or ""
						vim.api.nvim_buf_set_lines(ctx, lc - 1, lc, false, { last .. chunk })
					else
						vim.api.nvim_buf_set_lines(ctx, lc, lc, false, { chunk })
					end
				end
				scroll_bottom()
			end)
		end,
		on_stderr = function(_, data)
			if not data then return end
			local msg = vim.trim(table.concat(data, "\n"))
			if msg ~= "" then
				vim.schedule(function()
					vim.notify("cogcog: " .. msg, vim.log.levels.ERROR)
				end)
			end
		end,
		on_exit = function(_, code)
			vim.schedule(function()
				stop_spinner(ctx)
				vim.fn.delete(tmp)
				job_id = nil
				if code == 0 then
					if vim.api.nvim_buf_is_valid(ctx) then
						append({ "", "" })
						scroll_bottom()
					end
				else
					vim.notify("cogcog: exit " .. code, vim.log.levels.ERROR)
				end
			end)
		end,
	})

	if not job_id or job_id <= 0 then
		stop_spinner(ctx)
		vim.fn.delete(tmp)
		job_id = nil
		vim.notify("cogcog: failed to start", vim.log.levels.ERROR)
	end
end

-- pin code to context (visual)

local function pin_selection()
	local name = relative_name(vim.api.nvim_buf_get_name(0))
	local l1, l2 = vim.fn.line("'<"), vim.fn.line("'>")
	local lines = vim.api.nvim_buf_get_lines(0, l1 - 1, l2, false)
	append({ "", "--- " .. name .. ":" .. l1 .. "-" .. l2 .. " ---", "" })
	append(lines)
end

-- ask: prompt for question, optionally with selection, then send

local function ask(with_selection)
	local sel_lines, sel_name, sel_range
	if with_selection then
		sel_name = relative_name(vim.api.nvim_buf_get_name(0))
		local l1, l2 = vim.fn.line("'<"), vim.fn.line("'>")
		sel_lines = vim.api.nvim_buf_get_lines(0, l1 - 1, l2, false)
		sel_range = l1 .. "-" .. l2
	end

	vim.ui.input({ prompt = " ask: " }, function(question)
		if not question or vim.trim(question) == "" then return end
		if sel_lines then
			append({ "", "--- " .. sel_name .. ":" .. sel_range .. " ---", "" })
			append(sel_lines)
		end
		append({ "", question })
		send()
	end)
end

-- operator function for ga{motion}

function _G._cogcog_operatorfunc(type)
	local start_pos = vim.api.nvim_buf_get_mark(0, "[")
	local end_pos = vim.api.nvim_buf_get_mark(0, "]")
	local lines = vim.api.nvim_buf_get_lines(0, start_pos[1] - 1, end_pos[1], false)
	if #lines == 0 then return end

	local name = relative_name(vim.api.nvim_buf_get_name(0))
	local range = start_pos[1] .. "-" .. end_pos[1]

	vim.ui.input({ prompt = " ask: " }, function(question)
		if not question or vim.trim(question) == "" then return end
		append({ "", "--- " .. name .. ":" .. range .. " ---", "" })
		append(lines)
		append({ "", question })
		send()
	end)
end

-- keymaps

-- ga as operator: gaip (paragraph), gaf (function), ga3j (3 lines down)
vim.keymap.set("n", "ga", function()
	vim.o.operatorfunc = "v:lua._cogcog_operatorfunc"
	return "g@"
end, { expr = true, desc = "cogcog: ask about {motion}" })

-- ga in visual: select then ask
vim.keymap.set("v", "ga", function()
	-- exit visual mode to set '< and '> marks
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
	vim.schedule(function() ask(true) end)
end, { desc = "cogcog: ask about selection" })

-- ctrl-g: ask/follow-up from anywhere (no selection)
vim.keymap.set("n", "<C-g>", function() ask(false) end, { desc = "cogcog: ask" })

-- pin selection to context without sending
vim.keymap.set("v", "<leader>cy", function()
	-- exit visual to set marks
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
	vim.schedule(function()
		pin_selection()
		ensure_panel()
		scroll_bottom()
		vim.notify("cogcog: pinned")
	end)
end, { desc = "cogcog: pin to context" })

-- toggle panel
vim.keymap.set("n", "<leader>co", toggle_panel, { desc = "cogcog: toggle panel" })

-- toggle skills/tools
vim.keymap.set("n", "<leader>cl", function()
	local items = {}
	for _, s in ipairs(list_skills()) do
		local tag = "skill:" .. s.name
		local active = find_section(tag) ~= nil
		table.insert(items, {
			label = (active and "● " or "  ") .. s.name,
			tag = tag,
			active = active,
			kind = "skill",
			name = s.name,
			path = s.path,
		})
	end
	for name, _ in pairs(builtin_tools) do
		local tag = "tool:" .. name
		local active = find_section(tag) ~= nil
		table.insert(items, {
			label = (active and "● " or "  ") .. name .. " ⚡",
			tag = tag,
			active = active,
			kind = "tool",
			name = name,
		})
	end
	if #items == 0 then
		vim.notify("cogcog: no skills/tools", vim.log.levels.WARN)
		return
	end
	table.sort(items, function(a, b)
		if a.active ~= b.active then return a.active end
		return a.name < b.name
	end)
	vim.ui.select(items, {
		prompt = "toggle:",
		format_item = function(item) return item.label end,
	}, function(choice)
		if not choice then return end
		if choice.active then
			remove_section(choice.tag)
			vim.notify("cogcog: -" .. choice.name)
		else
			if choice.kind == "skill" then
				add_skill(choice.name, choice.path)
			else
				add_tool(choice.name)
			end
			vim.notify("cogcog: +" .. choice.name)
		end
		ensure_panel()
		scroll_bottom()
	end)
end, { desc = "cogcog: skills/tools" })

-- clear
vim.keymap.set("n", "<leader>cc", function()
	local buf = get_or_create_ctx()
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
	vim.fn.delete(session_file)
	local sys = load_system_prompt()
	if #sys > 0 then vim.api.nvim_buf_set_lines(buf, 0, -1, false, sys) end
	vim.notify("cogcog: cleared")
end, { desc = "cogcog: clear" })
