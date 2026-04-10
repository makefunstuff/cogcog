// cogcog pi extension — gives pi eyes into your running Neovim.
// Install: ln -s /path/to/cogcog/pi-extension ~/.pi/agent/extensions/cogcog
//
// Start Neovim with: nvim --listen /tmp/cogcog.sock
// Or set COGCOG_NVIM_SOCKET to your socket path.
// Then run pi in another terminal — it auto-detects the connection.

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { Type } from "@sinclair/typebox";

export default function (pi: ExtensionAPI) {
  const socketPath =
    process.env.COGCOG_NVIM_SOCKET || "/tmp/cogcog.sock";

  // ── helpers ───────────────────────────────────────────────────

  async function isConnected(): Promise<boolean> {
    try {
      const fs = await import("node:fs");
      if (!fs.existsSync(socketPath)) return false;
      const r = await pi.exec("nvim", ["--server", socketPath, "--remote-expr", "1"], { timeout: 2000 });
      return r.code === 0;
    } catch {
      return false;
    }
  }

  /** Call a cogcog.bridge Lua method via --remote-expr. */
  async function nvimCall(method: string, args?: Record<string, any>): Promise<any> {
    let luaExpr: string;
    if (args) {
      // use [=[...]=] to avoid ]] issues in JSON
      const json = JSON.stringify(args);
      luaExpr = `require('cogcog.bridge').${method}([=[${json}]=])`;
    } else {
      luaExpr = `require('cogcog.bridge').${method}()`;
    }

    const result = await pi.exec(
      "nvim",
      ["--server", socketPath, "--remote-expr", `luaeval('${luaExpr}')`],
      { timeout: 5000 }
    );

    if (result.code !== 0) return null;
    const out = result.stdout.trim();
    if (!out) return null;
    try {
      return JSON.parse(out);
    } catch {
      return out;
    }
  }

  // ── context injection ─────────────────────────────────────────

  pi.on("before_agent_start", async (_event, _ctx) => {
    if (!(await isConnected())) return;
    const context = await nvimCall("get_context");
    if (!context) return;

    const lines: string[] = [];
    lines.push("## Neovim Editor State");
    lines.push(`CWD: ${context.cwd}`);
    if (context.buffer) {
      lines.push(
        `Buffer: \`${context.buffer}\` (${context.filetype || "?"}) — cursor line ${context.cursor?.[0]}`
      );
    }
    if (context.windows && context.windows.length > 1) {
      lines.push(
        `Visible: ${context.windows.map((w: any) => `\`${w.buffer}\``).join(", ")}`
      );
    }
    if (context.quickfix) {
      lines.push(`Quickfix (${context.quickfix.length}):`);
      for (const item of context.quickfix.slice(0, 10)) {
        lines.push(`  ${item.filename}:${item.lnum} ${item.text}`);
      }
    }
    const d = context.diagnostics;
    if (d && d.errors + d.warnings > 0) {
      lines.push(`Diagnostics: ${d.errors}E ${d.warnings}W ${d.info}I`);
    }
    if (context.modified_buffers) {
      lines.push(`Unsaved: ${context.modified_buffers.join(", ")}`);
    }
    if (context.lines && context.lines.length > 0) {
      lines.push("");
      const start = context.lines_start;
      lines.push(
        `\`\`\` ${context.buffer}:${start}-${start + context.lines.length - 1}`
      );
      for (let i = 0; i < context.lines.length; i++) {
        const num = start + i;
        const marker = num === context.cursor_line ? ">" : " ";
        lines.push(`${marker}${num}: ${context.lines[i]}`);
      }
      lines.push("```");
    }

    return {
      message: {
        customType: "cogcog-nvim-context",
        content: lines.join("\n"),
        display: false,
      },
    };
  });

  // ── tools ─────────────────────────────────────────────────────

  pi.registerTool({
    name: "nvim_context",
    label: "Neovim Context",
    description:
      "Get the user's current Neovim editor state: active buffer, cursor position, visible windows, quickfix list, diagnostics summary, and lines around the cursor.",
    parameters: Type.Object({}),
    async execute() {
      const ctx = await nvimCall("get_context");
      if (!ctx) throw new Error(`Neovim not reachable at ${socketPath}`);
      return {
        content: [{ type: "text" as const, text: JSON.stringify(ctx, null, 2) }],
        details: {},
      };
    },
  });

  pi.registerTool({
    name: "nvim_diagnostics",
    label: "Neovim Diagnostics",
    description:
      "Get LSP diagnostics from the user's Neovim. Shows errors, warnings, and info with file:line locations. Optionally filter by file path.",
    parameters: Type.Object({
      path: Type.Optional(
        Type.String({ description: "File path to filter (all buffers if omitted)" })
      ),
    }),
    async execute(_id, params) {
      const diags = await nvimCall("get_diagnostics", { path: params.path || "" });
      if (!diags) throw new Error(`Neovim not reachable at ${socketPath}`);
      if (!Array.isArray(diags) || diags.length === 0) {
        return { content: [{ type: "text" as const, text: "No diagnostics" }], details: {} };
      }
      const text = diags
        .map(
          (d: any) =>
            `${d.severity} ${d.filename}:${d.lnum}:${d.col} ${d.message}${d.source ? ` [${d.source}]` : ""}`
        )
        .join("\n");
      return { content: [{ type: "text" as const, text }], details: {} };
    },
  });

  pi.registerTool({
    name: "nvim_buffer",
    label: "Neovim Buffer",
    description:
      "Read the full contents of a buffer currently open in the user's Neovim. Returns text, filetype, and modified status. Reads the current buffer if no path given.",
    parameters: Type.Object({
      path: Type.Optional(
        Type.String({ description: "Buffer path (current buffer if omitted)" })
      ),
    }),
    async execute(_id, params) {
      const buf = await nvimCall("get_buffer", { path: params.path || "" });
      if (!buf) throw new Error(`Neovim not reachable at ${socketPath}`);
      if (buf.error) throw new Error(buf.error);
      const header = `${buf.name} (${buf.filetype}${buf.modified ? ", modified" : ""}, ${buf.line_count} lines)`;
      const text = header + "\n" + (buf.lines || []).join("\n");
      return { content: [{ type: "text" as const, text }], details: {} };
    },
  });

  pi.registerTool({
    name: "nvim_buffers",
    label: "Neovim Buffers",
    description:
      "List all loaded file buffers in the user's Neovim with filetypes, line counts, and modified status.",
    parameters: Type.Object({}),
    async execute() {
      const buffers = await nvimCall("get_buffers");
      if (!buffers) throw new Error(`Neovim not reachable at ${socketPath}`);
      if (!Array.isArray(buffers) || buffers.length === 0) {
        return { content: [{ type: "text" as const, text: "No buffers" }], details: {} };
      }
      const text = buffers
        .map(
          (b: any) =>
            `${b.name} (${b.filetype}, ${b.line_count}L${b.modified ? ", modified" : ""})`
        )
        .join("\n");
      return { content: [{ type: "text" as const, text }], details: {} };
    },
  });

  pi.registerTool({
    name: "nvim_goto",
    label: "Neovim Goto",
    description:
      "Open a file at a specific line in the user's Neovim editor. The editor window will jump to the file and line.",
    parameters: Type.Object({
      path: Type.String({ description: "File path to open" }),
      line: Type.Optional(Type.Number({ description: "Line number to jump to" })),
    }),
    async execute(_id, params) {
      const result = await nvimCall("goto_file", {
        path: params.path,
        line: params.line || 0,
      });
      if (!result) throw new Error(`Neovim not reachable at ${socketPath}`);
      const loc = params.line ? `${params.path}:${params.line}` : params.path;
      return {
        content: [{ type: "text" as const, text: `Opened ${loc} in Neovim` }],
        details: {},
      };
    },
  });

  // ── status on load ────────────────────────────────────────────

  pi.on("session_start", async (_event, ctx) => {
    if (await isConnected()) {
      ctx.ui.notify(`cogcog: Neovim connected (${socketPath})`, "info");
    } else {
      ctx.ui.setStatus("cogcog", "nvim: disconnected");
    }
  });
}
