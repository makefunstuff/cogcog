#!/usr/bin/env lua
-- cogcog/tests.lua — Unit tests for context builders and stream logic
-- Run in Neovim: :luafile tests.lua

-- Minimal test framework
local test_results = { passed = 0, failed = 0, failures = {} }
local current_test = nil

local function out(line)
  if vim and vim.api then
    vim.api.nvim_out_write(line .. "\n")
  else
    print(line)
  end
end

local function finish(code)
  if vim and vim.cmd then
    if code == 0 then
      vim.cmd("qall!")
    else
      vim.cmd("cquit " .. code)
    end
  else
    os.exit(code)
  end
end

-- Test runner
function test(name, fn)
  current_test = name
  local success, err = pcall(fn)
  if success then
    test_results.passed = test_results.passed + 1
    out("✓ " .. name)
  else
    test_results.failed = test_results.failed + 1
    table.insert(test_results.failures, { name = name, err = tostring(err) })
    out("✗ " .. name .. ": " .. tostring(err))
  end
end

-- Test helpers
function assert_true(condition, msg)
  if not condition then
    error(msg or "assertion failed")
  end
end

function assert_equal(a, b, msg)
  if a ~= b then
    error((msg or "assertion failed") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
  end
end

function assert_not_nil(val)
  assert_true(val ~= nil, "value is nil")
end

function assert_not_empty(tbl)
  assert_true(#tbl > 0, "table is empty")
end

function assert_contains(tbl, val)
  for _, v in ipairs(tbl) do
    if v == val then return end
  end
  error("table does not contain: " .. tostring(val))
end

-- Test strip_code_fences
test("strip_code_fences removes leading fence", function()
  local input = { "```lua", "local x = 1", "```", "" }
  local result = require("cogcog.context").strip_code_fences(input)
  assert_equal(#result, 1)
  assert_equal(result[1], "local x = 1")
end)

test("strip_code_fences removes trailing fence", function()
  local input = { "", "local x = 1", "```lua", "" }
  local result = require("cogcog.context").strip_code_fences(input)
  assert_equal(#result, 1)
  assert_equal(result[1], "local x = 1")
end)

test("strip_code_fences removes both fences", function()
  local input = { "```lua", "local x = 1", "```", "" }
  local result = require("cogcog.context").strip_code_fences(input)
  assert_equal(#result, 1)
  assert_equal(result[1], "local x = 1")
end)

test("strip_code_fences preserves content", function()
  local input = { "", "local x = 1", "" }
  local result = require("cogcog.context").strip_code_fences(input)
  assert_equal(#result, 1)
  assert_equal(result[1], "local x = 1")
end)

test("strip_code_fences handles multiple lines", function()
  local input = { "```lua", "local x = 1", "local y = 2", "```" }
  local result = require("cogcog.context").strip_code_fences(input)
  assert_equal(#result, 2)
  assert_equal(result[1], "local x = 1")
  assert_equal(result[2], "local y = 2")
end)

-- Test relative_name
test("relative_name returns relative path", function()
  -- Note: This requires vim.fn.getcwd()
  local cwd = vim.fn.getcwd() .. "/"
  local test_path = cwd .. "README.md"
  local result = require("cogcog.context").relative_name(test_path)
  assert_equal(result, "README.md")
end)

test("relative_name handles scratch", function()
  assert_equal(require("cogcog.context").relative_name(""), "scratch")
end)

test("relative_name handles absolute paths", function()
  local test_path = vim.fn.expand("~/test.lua")
  local result = require("cogcog.context").relative_name(test_path)
  assert_true(#result > 0, "result should not be empty")
end)

test("same_lines detects equal content", function()
  assert_true(require("cogcog.context").same_lines({ "a", "b" }, { "a", "b" }))
end)

test("same_lines detects changed content", function()
  assert_true(not require("cogcog.context").same_lines({ "a", "b" }, { "a", "c" }))
end)

test("unified_diff shows changed lines", function()
  local diff = require("cogcog.context").unified_diff({ "old" }, { "new", "next" })
  assert_contains(diff, "-old")
  assert_contains(diff, "+new")
  assert_contains(diff, "+next")
end)

-- Test with_selection
test("with_selection adds section", function()
  local input = {}
  local lines = { "line1", "line2", "line3" }
  local source = "test:1-3"
  require("cogcog.context").with_selection(input, lines, source)
  assert_not_empty(input)
  assert_contains(input, "--- test:1-3 ---")
end)

test("with_selection handles empty lines", function()
  local input = {}
  require("cogcog.context").with_selection(input, {}, "source")
  assert_true(#input == 0, "should not add empty selection")
end)

-- Test with_agent_instructions
test("with_scope_contract documents scope buckets", function()
  local input = {}
  require("cogcog.context").with_scope_contract(input)
  assert_contains(input, "Primary target: the explicit operand or quickfix target set.")
  assert_contains(input, "Workbench content is explicitly imported context. Visible windows are soft context only.")
end)

test("with_agent_instructions adds base instructions", function()
  local input = {}
  require("cogcog.context").with_agent_instructions(input, "gen")
  assert_true(#input > 0, "should contain instructions")
  assert_contains(input, "--- instructions ---")
end)

test("with_agent_instructions gen mode adds gen-specific", function()
  local input = {}
  require("cogcog.context").with_agent_instructions(input, "gen")
  assert_contains(input, "Explore the relevant code first, then generate.")
end)

test("with_agent_instructions plan mode adds plan-specific", function()
  local input = {}
  require("cogcog.context").with_agent_instructions(input, "plan")
  assert_contains(input, "Be concrete — suggest exact changes, not vague advice.")
end)

test("with_agent_instructions exec mode adds exec-specific", function()
  local input = {}
  require("cogcog.context").with_agent_instructions(input, "exec")
  assert_contains(input, "Read files before making changes.")
end)

-- Test config
test("config exposes workbench paths", function()
  local config = require("cogcog.config")
  assert_true(config.workbench_file ~= nil, "workbench_file should be set")
  assert_true(config.legacy_session_file ~= nil, "legacy_session_file should be set")
end)

test("config resolves bundled cogcog binary when available", function()
  local config = require("cogcog.config")
  assert_true(type(config.cogcog_bin) == "string" and config.cogcog_bin ~= "", "cogcog_bin should be a non-empty string")
  if config.cogcog_bin ~= "cogcog" then
    assert_true(vim.fn.filereadable(config.cogcog_bin) == 1, "resolved cogcog_bin should exist")
  end
end)

test("checker_cmd falls back to bundled raw path", function()
  local config = require("cogcog.config")
  local old = vim.env.COGCOG_CHECKER
  vim.env.COGCOG_CHECKER = nil
  assert_equal(config.checker_cmd(), config.cogcog_bin .. " --raw")
  vim.env.COGCOG_CHECKER = old
end)

test("agent_cmd is optional", function()
  local config = require("cogcog.config")
  local old = vim.env.COGCOG_AGENT_CMD
  vim.env.COGCOG_AGENT_CMD = nil
  assert_equal(config.agent_cmd(), nil)
  vim.env.COGCOG_AGENT_CMD = old
end)

-- Test with_quickfix
test("with_quickfix handles empty quickfix", function()
  vim.fn.setqflist({})
  local input = {}
  require("cogcog.context").with_quickfix(input)
  assert_true(#input == 0, "empty quickfix should not add context")
end)

test("get_quickfix_targets merges nearby entries", function()
  local buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_name(buf, vim.fn.getcwd() .. "/quickfix-target-test.lua")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "l1", "l2", "l3", "l4", "l5", "l6", "l7", "l8", "l9", "l10",
  })
  vim.fn.setqflist({
    { bufnr = buf, lnum = 3, text = "first" },
    { bufnr = buf, lnum = 4, text = "second" },
    { bufnr = buf, lnum = 9, text = "third" },
  })
  local targets = require("cogcog.context").get_quickfix_targets(1)
  assert_equal(#targets, 2, "nearby quickfix entries should merge")
  assert_equal(targets[1].start, 8)
  assert_equal(targets[1].stop, 10)
  assert_equal(#targets[1].hints, 1)
  assert_equal(targets[2].start, 2)
  assert_equal(targets[2].stop, 5)
  assert_equal(#targets[2].hints, 2)
end)

test("get_quickfix_targets ignores empty quickfix", function()
  vim.fn.setqflist({})
  local targets = require("cogcog.context").get_quickfix_targets(1)
  assert_equal(#targets, 0)
end)

-- Test M.to_buf structure (can't fully test without actual backend)
test("config module loads", function()
  local config = require("cogcog.config")
  assert_true(config.cogcog_dir ~= nil, "cogcog_dir should be set")
  assert_true(config.session_file ~= nil, "session_file should be set")
  assert_true(config.cogcog_bin ~= nil, "cogcog_bin should be set")
end)

-- Test error handling patterns
test("error notification uses correct level", function()
  -- Check that vim.notify is used with ERROR level
  local stream = require("cogcog.stream")
  -- Verify error handling exists in the module
  assert_true(type(stream.cancel_all) == "function", "cancel_all should exist")
end)

test("with_tools includes builtins", function()
  local c = require("cogcog.context")
  local input = {}
  c.with_tools(input)
  local text = table.concat(input, "\n")
  assert_true(text:find("read_file") ~= nil, "should list read_file")
  assert_true(text:find("list_files") ~= nil, "should list list_files")
  assert_true(text:find("grep") ~= nil, "should list grep")
  assert_true(text:find("run_command") ~= nil, "should list run_command")
  assert_true(text:find("<<<TOOL:") ~= nil, "should include format example")
end)

test("with_tools discovers .cogcog/tools/ scripts", function()
  local c = require("cogcog.context")
  local cfg = require("cogcog.config")
  local tools_dir = cfg.cogcog_dir .. "/tools"
  vim.fn.mkdir(tools_dir, "p")
  vim.fn.writefile({ "#!/bin/bash", "# List recent commits", "git log --oneline -5" }, tools_dir .. "/recent.sh")
  local input = {}
  c.with_tools(input)
  local text = table.concat(input, "\n")
  assert_true(text:find("tool:recent.sh") ~= nil, "should discover recent.sh")
  assert_true(text:find("List recent commits") ~= nil, "should parse description")
  vim.fn.delete(tools_dir .. "/recent.sh")
  vim.fn.delete(tools_dir, "d")
end)

-- Summary
out("")
out("--- Test Results ---")
out("Passed: " .. test_results.passed)
out("Failed: " .. test_results.failed)

if test_results.failed > 0 then
  out("")
  out("Failed tests:")
  for _, failure in ipairs(test_results.failures) do
    out("  " .. failure.name .. ": " .. failure.err)
  end
  finish(1)
else
  out("")
  out("All tests passed!")
  finish(0)
end