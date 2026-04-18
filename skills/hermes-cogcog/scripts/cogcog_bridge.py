#!/usr/bin/env python3
"""CogCog bridge — Hermes skill that exposes Neovim tools via pynvim.

Connects to Neovim's RPC socket and calls require("cogcog.bridge") functions
directly. No Node.js, no MCP, no build step. Just Python + pynvim.

Usage by Hermes skill:
  python3 scripts/cogcog_bridge.py <tool> [args_json]
  
  python3 scripts/cogcog_bridge.py get_context
  python3 scripts/cogcog_bridge.py get_buffer '{"path": "main.py"}'
  python3 scripts/cogcog_bridge.py get_buffers
  python3 scripts/cogcog_bridge.py get_diagnostics '{"path": "main.py"}'
  python3 scripts/cogcog_bridge.py goto_file '{"path": "main.py", "line": 42}'
  python3 scripts/cogcog_bridge.py set_quickfix '{"items": [...], "title": "hermes"}'
  python3 scripts/cogcog_bridge.py exec '{"cmd": "write"}'
  python3 scripts/cogcog_bridge.py notify '{"msg": "done", "level": "info"}'
  python3 scripts/cogcog_bridge.py status
  
Env vars:
  COGCOG_NVIM_SOCKET — socket path (default: /tmp/cogcog.sock)
"""

import json
import os
import sys

SOCKET = os.environ.get("COGCOG_NVIM_SOCKET", "/tmp/cogcog.sock")


def connect():
    """Attach to Neovim via RPC socket."""
    if not os.path.exists(SOCKET):
        print(json.dumps({"error": f"Socket not found: {SOCKET}. Is Neovim running with --listen {SOCKET}?"}), file=sys.stderr)
        sys.exit(1)
    try:
        import pynvim
        nvim = pynvim.attach("socket", path=SOCKET)
        return nvim
    except Exception as e:
        print(json.dumps({"error": f"Failed to connect to Neovim: {e}"}), file=sys.stderr)
        sys.exit(1)


def call_bridge(nvim, method, args=None):
    """Call require("cogcog.bridge").method(args) in Neovim."""
    if args:
        return nvim.exec_lua(f'return require("cogcog.bridge").{method}(...)', args)
    else:
        return nvim.exec_lua(f'return require("cogcog.bridge").{method}()')


def main():
    if len(sys.argv) < 2:
        print("Usage: cogcog_bridge.py <tool> [args_json]", file=sys.stderr)
        print("Tools: status, get_context, get_buffer, get_buffers, get_diagnostics,", file=sys.stderr)
        print("       goto_file, set_quickfix, exec, notify", file=sys.stderr)
        sys.exit(1)

    tool = sys.argv[1]
    args = None
    if len(sys.argv) > 2:
        try:
            args = json.loads(sys.argv[2])
        except json.JSONDecodeError as e:
            print(json.dumps({"error": f"Invalid JSON args: {e}"}))
            sys.exit(1)

    # status doesn't need Neovim
    if tool == "status":
        connected = os.path.exists(SOCKET)
        result = {"connected": connected, "socket": SOCKET}
        if connected:
            try:
                nvim = connect()
                result["connected"] = True
                result["nvim_version"] = nvim.command_output("version").split("\n")[0]
                nvim.close()
            except Exception as e:
                result["connected"] = False
                result["error"] = str(e)
        print(json.dumps(result, indent=2))
        return

    # All other tools need Neovim
    nvim = connect()
    try:
        # Map Hermes tool names to bridge.lua function names
        tool_map = {
            "get_context": "get_context",
            "context": "get_context",
            "get_buffer": "get_buffer",
            "buffer": "get_buffer",
            "get_buffers": "get_buffers",
            "buffers": "get_buffers",
            "get_diagnostics": "get_diagnostics",
            "diagnostics": "get_diagnostics",
            "goto_file": "goto_file",
            "goto": "goto_file",
            "set_quickfix": "set_quickfix",
            "quickfix": "set_quickfix",
            "exec": "exec",
            "notify": "notify",
        }

        method = tool_map.get(tool)
        if not method:
            print(json.dumps({"error": f"Unknown tool: {tool}. Available: {', '.join(tool_map.keys())}"}))
            sys.exit(1)

        result = call_bridge(nvim, method, args)
        
        # Pretty-print buffers (show file content nicely)
        if tool in ("get_buffer", "buffer") and isinstance(result, dict) and "lines" in result:
            header = f"{result['name']} ({result['filetype']}{', modified' if result.get('modified') else ''}, {result.get('line_count', '?')} lines)\n"
            print(header + "\n".join(result["lines"]))
            return

        # Pretty-print buffers list
        if tool in ("get_buffers", "buffers") and isinstance(result, list):
            for b in result:
                print(f"{b['name']} ({b['filetype']}, {b['line_count']}L{', modified' if b.get('modified') else ''})")
            return

        # Default: JSON output
        print(json.dumps(result, indent=2))

    finally:
        nvim.close()


if __name__ == "__main__":
    main()