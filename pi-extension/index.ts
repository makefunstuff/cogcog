// cogcog pi extension — gives pi eyes into your running Neovim.
// Install: ln -s /path/to/cogcog/pi-extension ~/.pi/agent/extensions/cogcog
// Then run `npm install` in this directory once for the Neovim RPC client.
//
// Start Neovim with: nvim --listen /tmp/cogcog.sock
// Or set COGCOG_NVIM_SOCKET to your socket path.
// Then run pi in another terminal — it auto-detects the connection.

import * as fs from "node:fs";
import { attach, type NeovimClient } from "neovim";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { Type } from "@sinclair/typebox";

type RpcNeovim = NeovimClient & {
  on(event: "notification", listener: (method: string, args: any[]) => void): RpcNeovim;
  on(event: "disconnect", listener: () => void): RpcNeovim;
  removeAllListeners(event?: string): RpcNeovim;
  transport: { close(): Promise<void> };
};

export default function (pi: ExtensionAPI) {
  const socketPath = process.env.COGCOG_NVIM_SOCKET || "/tmp/cogcog.sock";

  const actionableEventTypes = new Set([
    "ask",
    "generate",
    "refactor",
    "check",
    "plan",
    "execute",
  ]);

  const rpcLogger = {
    level: "silent",
    info() {},
    warn() {},
    error() {},
    debug() {},
  };

  let nvim: RpcNeovim | null = null;
  let connectPromise: Promise<RpcNeovim | null> | null = null;
  let attachedChannel: number | null = null;
  let sessionCtx: any = null;

  // ── helpers ───────────────────────────────────────────────────

  function uiNotify(msg: string, level: "info" | "warning" | "error" = "info") {
    if (sessionCtx?.hasUI) sessionCtx.ui.notify(msg, level);
  }

  function setCogcogStatus(text: string) {
    if (sessionCtx) sessionCtx.ui.setStatus("cogcog", text);
  }

  function schema<T>(value: T): any {
    return value;
  }

  async function currentChannel(): Promise<number | null> {
    const client = await ensureNvim();
    if (!client) return null;
    if (attachedChannel != null) return attachedChannel;
    attachedChannel = await client.channelId;
    return attachedChannel;
  }

  async function bridgeStatus() {
    const channel = await currentChannel();
    const owner = (await nvimCall("get_pi_status"))?.owner ?? null;
    return {
      channel,
      owner,
      claimed: channel != null && owner === channel,
    };
  }

  async function refreshStatus() {
    if (!(await isConnected())) {
      setCogcogStatus("nvim: disconnected");
      return;
    }

    const status = await bridgeStatus();
    if (status.claimed) {
      setCogcogStatus(`nvim: connected · claimed (${status.channel})`);
    } else if (status.owner != null) {
      setCogcogStatus(`nvim: connected · owner ${status.owner}`);
    } else {
      setCogcogStatus("nvim: connected · unclaimed");
    }
  }

  async function claimBridge() {
    const channel = await currentChannel();
    if (channel == null) return null;
    return await nvimCall("claim_pi", { channel });
  }

  async function releaseBridge() {
    const channel = await currentChannel();
    if (channel == null) return null;
    return await nvimCall("release_pi", { channel });
  }

  function handleNotification(method: string, args: any[]) {
    if (method !== "cogcog_notify") return;
    try {
      const event = Array.isArray(args) ? args[0] : undefined;
      const message = formatEventMessage(event);
      if (!message) return;
      deliverEventMessage(message);
    } catch (error) {
      uiNotify(`cogcog: failed to process event (${String(error)})`, "warning");
    }
  }

  async function closeNvim(detachBridge = true) {
    const client = nvim;
    const channel = attachedChannel;

    nvim = null;
    attachedChannel = null;
    connectPromise = null;

    if (!client) {
      setCogcogStatus("nvim: disconnected");
      return;
    }

    client.removeAllListeners("notification");
    client.removeAllListeners("disconnect");

    if (detachBridge && channel != null) {
      try {
        await client.executeLua('return require("cogcog.bridge").detach_pi(...)', [{ channel }]);
      } catch {
        // Best effort only.
      }
    }

    try {
      await client.transport.close();
    } catch {
      // Ignore already-closed sockets.
    }

    setCogcogStatus("nvim: disconnected");
  }

  async function ensureNvim(): Promise<RpcNeovim | null> {
    if (nvim) return nvim;
    if (connectPromise) return connectPromise;
    if (!fs.existsSync(socketPath)) return null;

    const promise = (async () => {
      const client = attach({ socket: socketPath, options: { logger: rpcLogger as any } }) as RpcNeovim;
      client.on("notification", handleNotification);
      client.on("disconnect", () => {
        if (nvim === client) {
          nvim = null;
          attachedChannel = null;
          connectPromise = null;
          setCogcogStatus("nvim: disconnected");
        }
      });

      try {
        const channel = await client.channelId;
        await client.executeLua('return require("cogcog.bridge").attach_pi(...)', [{ channel }]);
        nvim = client;
        attachedChannel = channel;
        await refreshStatus();
        return client;
      } catch (error) {
        client.removeAllListeners();
        try {
          await client.transport.close();
        } catch {
          // Ignore.
        }
        uiNotify(`cogcog: failed to attach to Neovim (${String(error)})`, "error");
        return null;
      }
    })();

    connectPromise = promise;
    try {
      return await promise;
    } finally {
      if (connectPromise === promise) connectPromise = null;
    }
  }

  async function isConnected(): Promise<boolean> {
    return (await ensureNvim()) != null;
  }

  /** Call a cogcog.bridge Lua method over the persistent Neovim RPC socket. */
  async function nvimCall(method: string, args?: Record<string, any>): Promise<any> {
    const client = await ensureNvim();
    if (!client) return null;

    try {
      const lua = args
        ? `return require("cogcog.bridge").${method}(...)`
        : `return require("cogcog.bridge").${method}()`;
      return await client.executeLua(lua, args ? [args] : []);
    } catch (error) {
      uiNotify(`cogcog: nvimCall ${method} failed (${String(error)})`, "warning");
      return null;
    }
  }

  function formatSnippet(title: string, lines: unknown, maxLines = 40): string[] {
    if (!Array.isArray(lines) || lines.length === 0) return [];
    const textLines = lines.slice(0, maxLines).map((line) => String(line));
    const out = ["", `${title}:`, "```"];
    out.push(...textLines);
    if (lines.length > maxLines) out.push(`… (${lines.length - maxLines} more lines)`);
    out.push("```");
    return out;
  }

  function formatEventMessage(event: any): string | null {
    if (!event || !actionableEventTypes.has(event.type)) return null;

    const payload = event.payload || {};
    const lines: string[] = [];
    lines.push(`Cogcog event: ${event.type}`);
    if (event.cwd) lines.push(`CWD: ${event.cwd}`);

    switch (event.type) {
      case "ask":
        if (payload.source) lines.push(`Source: ${payload.source}`);
        if (payload.question) lines.push(`Question: ${payload.question}`);
        lines.push(...formatSnippet("Selection", payload.selection));
        break;
      case "generate":
        if (payload.source) lines.push(`Source: ${payload.source}`);
        if (payload.instruction) lines.push(`Instruction: ${payload.instruction}`);
        lines.push(...formatSnippet("Selection", payload.selection));
        break;
      case "refactor":
        if (payload.source) lines.push(`Source: ${payload.source}`);
        if (payload.instruction) lines.push(`Instruction: ${payload.instruction}`);
        if (payload.target?.file) {
          lines.push(
            `Target: ${payload.target.file}:${payload.target.start_line}-${payload.target.end_line}`
          );
        }
        lines.push(...formatSnippet("Selection", payload.selection));
        break;
      case "check":
        if (payload.source) lines.push(`Source: ${payload.source}`);
        lines.push("Review this code for correctness, edge cases, and bugs.");
        lines.push(...formatSnippet("Selection", payload.selection));
        break;
      case "plan":
        lines.push(payload.question || "Continue from the current Cogcog workbench context in Neovim.");
        break;
      case "execute":
        if (payload.instruction) lines.push(`Instruction: ${payload.instruction}`);
        else lines.push("Execute the requested work from Cogcog.");
        break;
      default:
        return null;
    }

    lines.push("");
    lines.push("Use Neovim tools if you need more editor context.");
    return lines.join("\n");
  }

  function deliverEventMessage(message: string) {
    try {
      const result = pi.sendUserMessage(message);
      Promise.resolve(result).catch(() => {
        Promise.resolve(pi.sendUserMessage(message, { deliverAs: "followUp" })).catch(() => {
          uiNotify("cogcog: failed to queue follow-up event", "error");
        });
      });
    } catch {
      try {
        Promise.resolve(pi.sendUserMessage(message, { deliverAs: "followUp" })).catch(() => {
          uiNotify("cogcog: failed to queue follow-up event", "error");
        });
      } catch {
        uiNotify("cogcog: failed to send event", "error");
      }
    }
  }

  // ── context injection ─────────────────────────────────────────

  pi.on("before_agent_start", async (_event, _ctx) => {
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
    parameters: schema(Type.Object({})),
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
    parameters: schema(Type.Object({
      path: Type.Optional(
        Type.String({ description: "File path to filter (all buffers if omitted)" })
      ),
    })),
    async execute(_id: string, params: any) {
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
    parameters: schema(Type.Object({
      path: Type.Optional(
        Type.String({ description: "Buffer path (current buffer if omitted)" })
      ),
    })),
    async execute(_id: string, params: any) {
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
    parameters: schema(Type.Object({})),
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
    parameters: schema(Type.Object({
      path: Type.String({ description: "File path to open" }),
      line: Type.Optional(Type.Number({ description: "Line number to jump to" })),
    })),
    async execute(_id: string, params: any) {
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

  pi.registerTool({
    name: "nvim_quickfix",
    label: "Neovim Quickfix",
    description:
      "Set the quickfix list in the user's Neovim. Items appear in the quickfix window and can be navigated with :cnext/:cprev or Telescope. Use this to send findings (TODOs, issues, locations) to the editor.",
    parameters: schema(Type.Object({
      title: Type.Optional(Type.String({ description: "Quickfix list title" })),
      items: Type.Array(
        Type.Object({
          filename: Type.String({ description: "File path (relative to cwd)" }),
          lnum: Type.Number({ description: "Line number" }),
          text: Type.String({ description: "Description" }),
          col: Type.Optional(Type.Number({ description: "Column number" })),
          type: Type.Optional(
            Type.String({ description: "Type: E(rror), W(arning), I(nfo), H(int)" })
          ),
        }),
        { description: "Quickfix items" }
      ),
    })),
    async execute(_id: string, params: any) {
      const result = await nvimCall("set_quickfix", {
        title: params.title || "pi",
        items: params.items,
      });
      if (!result) throw new Error(`Neovim not reachable at ${socketPath}`);
      return {
        content: [
          {
            type: "text" as const,
            text: `Set ${params.items.length} items in quickfix${params.title ? ` (${params.title})` : ""}`,
          },
        ],
        details: {},
      };
    },
  });

  pi.registerTool({
    name: "nvim_exec",
    label: "Neovim Command",
    description:
      "Run a vim command in the user's Neovim (e.g. :make, :write, :grep). Use for triggering builds, saves, or other editor actions.",
    parameters: schema(Type.Object({
      cmd: Type.String({ description: "Vim command to execute (without leading :)" }),
    })),
    async execute(_id: string, params: any) {
      const result = await nvimCall("exec", { cmd: params.cmd });
      if (!result) throw new Error(`Neovim not reachable at ${socketPath}`);
      return {
        content: [{ type: "text" as const, text: `Executed :${params.cmd}` }],
        details: {},
      };
    },
  });

  pi.registerTool({
    name: "nvim_notify",
    label: "Neovim Notify",
    description:
      "Send a notification to the user's Neovim editor.",
    parameters: schema(Type.Object({
      msg: Type.String({ description: "Notification message" }),
      level: Type.Optional(
        Type.String({ description: "Level: error, warn, info (default: info)" })
      ),
    })),
    async execute(_id: string, params: any) {
      await nvimCall("notify", { msg: params.msg, level: params.level || "info" });
      return {
        content: [{ type: "text" as const, text: `Notified: ${params.msg}` }],
        details: {},
      };
    },
  });

  pi.registerCommand("cogcog-claim", {
    description: "Claim Cogcog event delivery for this pi session",
    handler: async (_args, ctx) => {
      const result = await claimBridge();
      if (!result) {
        ctx.ui.notify(`cogcog: Neovim not reachable at ${socketPath}`, "warning");
        return;
      }
      await refreshStatus();
      ctx.ui.notify(`cogcog: claimed events for channel ${result.owner}`, "info");
    },
  });

  pi.registerCommand("cogcog-release", {
    description: "Release Cogcog event delivery from this pi session",
    handler: async (_args, ctx) => {
      const result = await releaseBridge();
      if (!result) {
        ctx.ui.notify(`cogcog: Neovim not reachable at ${socketPath}`, "warning");
        return;
      }
      await refreshStatus();
      ctx.ui.notify(
        result.released ? "cogcog: released event claim" : `cogcog: another session owns events (${result.owner ?? "-"})`,
        result.released ? "info" : "warning"
      );
    },
  });

  pi.registerCommand("cogcog-status", {
    description: "Show Cogcog bridge status",
    handler: async (_args, ctx) => {
      const connected = await isConnected();
      const status = connected ? await bridgeStatus() : { channel: null, owner: null, claimed: false };
      ctx.ui.notify(
        `cogcog: nvim=${connected ? "connected" : "disconnected"} socket=${socketPath} channel=${status.channel ?? "-"} owner=${status.owner ?? "-"} claimed=${status.claimed ? "yes" : "no"}`,
        "info"
      );
    },
  });

  // ── status on load ────────────────────────────────────────────

  pi.on("session_start", async (_event, ctx) => {
    sessionCtx = ctx;
    await refreshStatus();
  });

  pi.on("session_shutdown", async () => {
    await closeNvim();
    sessionCtx = null;
  });
}
