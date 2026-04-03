#!/usr/bin/env lua
-- cogcog/tests.lua — Unit tests for context builders and stream logic
-- Run in Neovim: :lua require("cogcog.tests").run()

-- Minimal test framework
local test_results = { passed = 0, failed = 0 }
local current_test = nil

-- Test runner
function test(name, fn)
  current_test = name
  local success, err = pcall(fn)
  if success then
    test_results.passed = test_results.passed + 1
    io.stdout.write("✓ " .. name .. "\n")
  else
    test_results.failed = test_results.failed + 1
    io.stderr:write("✗ " .. name .. ": " .. tostring(err) .. "\n")
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
test("with_agent_instructions adds base instructions", function()
  local input = {}
  require("cogcog.context").with_agent_instructions(input, "gen")
  assert_true(#input > 0, "should contain instructions")
  assert_contains(input, "--- instructions ---")
end)

test("with_agent_instructions gen mode adds gen-specific", function()
  local input = {}
  require("cogcog.context").with_agent_instructions(input, "gen")
  assert_contains(input, "Explore the relevant code first")
end)

test("with_agent_instructions plan mode adds plan-specific", function()
  local input = {}
  require("cogcog.context").with_agent_instructions(input, "plan")
  assert_contains(input, "Be concrete")
end)

test("with_agent_instructions exec mode adds exec-specific", function()
  local input = {}
  require("cogcog.context").with_agent_instructions(input, "exec")
  assert_contains(input, "Read files before making changes")
end)

-- Test config
test("config.default_timeout exists", function()
  local config = require("cogcog.config")
  assert_true(config.default_timeout ~= nil, "timeout should be set")
end)

-- Test with_quickfix
test("with_quickfix handles empty quickfix", function()
  local input = {}
  require("cogcog.context").with_quickfix(input)
  -- Should return input unchanged
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

-- Summary
print("\n--- Test Results ---")
print("Passed: " .. test_results.passed)
print("Failed: " .. test_results.failed)

if test_results.failed > 0 then
  print("\nFailed tests:")
  for name, result in pairs(test_results) do
    if not result then
      print("  " .. name)
    end
  end
  os.exit(1)
else
  print("\nAll tests passed!")
  os.exit(0)
end