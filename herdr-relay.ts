// Forwards agent state reports from the workspace container to the host herdr server.
//
// The herdr socket can type into any pane and run commands on the host, so this relay
// accepts only state reports from a `sandbox:*` source for a known agent, and strips the
// fields that could run something on the host. Everything else is rejected before herdr.
//
// The agent keeps its real name (`omp`, `claude`) so herdr and Collie pick that agent's
// screen grammar. The `sandbox:*` source keeps herdr from treating the report as its own
// integration, so the session id is recorded for Collie but never drives a resume; the
// patched herdr in ~/Coding/Sasaya/herdr (dev-env branch) is what records it.

import net from "node:net";
import os from "node:os";
import path from "node:path";

const LISTEN_HOST = "127.0.0.1";
const LISTEN_PORT = Number(process.env.HERDR_RELAY_PORT ?? 47123);
const HERDR_SOCKET_PATH =
  process.env.HERDR_RELAY_SOCKET_PATH ?? path.join(os.homedir(), ".config/herdr/herdr.sock");
const SANDBOX_SOURCE_PREFIX = "sandbox:";
const ALLOWED_AGENTS: Record<string, true> = { omp: true, claude: true };
const MAX_LINE_BYTES = 16 * 1024;

const ALLOWED_METHODS: Record<string, true> = {
  "pane.report_agent": true,
  "pane.report_agent_session": true,
  "pane.release_agent": true,
};
// resume_argv would run on the host; a container session path names nothing on the host.
const STRIPPED_FIELDS = ["resume_argv", "agent_session_path"];

type RelayRequest = { id?: unknown; method?: unknown; params?: Record<string, unknown> };

function sanitize(line: string): string | undefined {
  let request: RelayRequest;
  try {
    request = JSON.parse(line);
  } catch {
    return undefined;
  }
  const params = request.params;
  if (typeof request.method !== "string" || !Object.hasOwn(ALLOWED_METHODS, request.method)) {
    return undefined;
  }
  if (!params || typeof params !== "object") return undefined;
  if (typeof params.source !== "string" || !params.source.startsWith(SANDBOX_SOURCE_PREFIX)) return undefined;
  if (typeof params.agent !== "string" || !Object.hasOwn(ALLOWED_AGENTS, params.agent)) return undefined;

  const allowedParams = { ...params };
  for (const field of STRIPPED_FIELDS) delete allowedParams[field];
  return JSON.stringify({ id: request.id, method: request.method, params: allowedParams });
}

function rejection(line: string): string {
  let id: unknown = null;
  try {
    id = JSON.parse(line)?.id ?? null;
  } catch {}
  return `${JSON.stringify({ id, error: { code: "relay_rejected", message: "only sandbox agent state reports are relayed" } })}\n`;
}

function forward(request: string, client: net.Socket): void {
  const upstream = net.connect(HERDR_SOCKET_PATH);
  upstream.on("connect", () => upstream.write(`${request}\n`));
  upstream.on("data", (chunk) => client.write(chunk));
  upstream.on("error", () => client.destroy());
  upstream.on("end", () => client.end());
}

net
  .createServer((client) => {
    let buffered = "";
    client.setEncoding("utf8");
    client.on("error", () => client.destroy());
    client.on("data", (chunk: string) => {
      buffered += chunk;
      if (buffered.length > MAX_LINE_BYTES) return client.destroy();
      const newline = buffered.indexOf("\n");
      if (newline === -1) return;

      const line = buffered.slice(0, newline);
      client.pause();
      const request = sanitize(line);
      if (!request) return client.end(rejection(line));
      forward(request, client);
    });
  })
  .listen(LISTEN_PORT, LISTEN_HOST, () => {
    console.log(`herdr-relay ${LISTEN_HOST}:${LISTEN_PORT} -> ${HERDR_SOCKET_PATH}`);
  });
