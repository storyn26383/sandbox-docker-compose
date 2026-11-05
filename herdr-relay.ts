// Forwards agent state reports from the workspace container to the host herdr server.
//
// The herdr socket can type into any pane and run commands on the host, so this relay
// accepts only state reports from a `sandbox:*` source for a known agent, and strips the
// fields that could run something on the host. Everything else is rejected before herdr.
//
// The agent keeps its real name (`omp`) so herdr and Collie pick that agent's
// screen grammar. The `sandbox:*` source keeps herdr from treating the report as its own
// integration, so the session id is recorded for Collie but never drives a resume; the
// patched herdr in ~/Coding/Sasaya/herdr (dev-env branch) is what records it.
//
// herdr cannot see processes inside the container, so a sandbox agent stays reported until it
// releases itself. When the container stops (restart, crash, `make stop`), its agents die
// without releasing, so the relay remembers every agent it reported and releases them itself:
// on a docker `die` event, and at startup when the container started after the last report
// (it was restarted while the relay was down). The record survives relay restarts on disk.

import { mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";

const LISTEN_HOST = "127.0.0.1";
const LISTEN_PORT = Number(process.env.HERDR_RELAY_PORT ?? 47123);
const HERDR_SOCKET_PATH =
  process.env.HERDR_RELAY_SOCKET_PATH ?? path.join(os.homedir(), ".config/herdr/herdr.sock");
// the container whose agents are released when it stops; unset disables the cleanup
const CONTAINER = process.env.HERDR_RELAY_CONTAINER || undefined;
const STATE_PATH = process.env.HERDR_RELAY_STATE ?? path.join(import.meta.dir, ".data/herdr-relay-agents.json");
const SANDBOX_SOURCE_PREFIX = "sandbox:";
const ALLOWED_AGENTS: Record<string, true> = { omp: true };
const MAX_LINE_BYTES = 16 * 1024;
const EVENTS_RETRY_MS = 5_000;

const REPORT_AGENT = "pane.report_agent";
const REPORT_AGENT_SESSION = "pane.report_agent_session";
const RELEASE_AGENT = "pane.release_agent";
const ALLOWED_METHODS: Record<string, true> = {
  [REPORT_AGENT]: true,
  [REPORT_AGENT_SESSION]: true,
  [RELEASE_AGENT]: true,
};
// resume_argv would run on the host; a container session path names nothing on the host.
const STRIPPED_FIELDS = ["resume_argv", "agent_session_path"];

type RelayRequest = { id?: unknown; method?: string; params?: Record<string, unknown> };

// One agent the relay reported and has not seen released, keyed by pane.
type ReportedAgent = { source: string; agent: string; seq: number; reportedAt: number };
type ReportedAgents = Record<string, ReportedAgent>;

function sanitize(line: string): RelayRequest | undefined {
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
  return { id: request.id, method: request.method, params: allowedParams };
}

function rejection(line: string): string {
  let id: unknown = null;
  try {
    id = JSON.parse(line)?.id ?? null;
  } catch {}
  return `${JSON.stringify({ id, error: { code: "relay_rejected", message: "only sandbox agent state reports are relayed" } })}\n`;
}

// --- reported agents, persisted so a relay restart does not forget them ---

function loadReported(): ReportedAgents {
  try {
    return JSON.parse(readFileSync(STATE_PATH, "utf8")) as ReportedAgents;
  } catch {
    return {};
  }
}

const reported = loadReported();

function saveReported(): void {
  mkdirSync(path.dirname(STATE_PATH), { recursive: true });
  const temporary = `${STATE_PATH}.tmp`;
  writeFileSync(temporary, JSON.stringify(reported));
  renameSync(temporary, STATE_PATH);
}

// Called only after herdr accepted the request, so the record matches what herdr holds.
function track(request: RelayRequest): void {
  const params = request.params!;
  const paneId = params.pane_id;
  if (typeof paneId !== "string") return;
  if (request.method === RELEASE_AGENT) {
    if (!reported[paneId]) return;
    delete reported[paneId];
  } else {
    const seq = typeof params.seq === "number" ? params.seq : (reported[paneId]?.seq ?? 0);
    reported[paneId] = { source: String(params.source), agent: String(params.agent), seq, reportedAt: Date.now() };
  }
  saveReported();
}

// --- herdr ---

// Sends one request and resolves with herdr's response line.
function send(request: RelayRequest): Promise<string> {
  return new Promise((resolve, reject) => {
    const upstream = net.connect(HERDR_SOCKET_PATH);
    let buffer = "";
    upstream.setEncoding("utf8");
    upstream.on("connect", () => upstream.write(`${JSON.stringify(request)}\n`));
    upstream.on("data", (chunk: string) => {
      buffer += chunk;
      const newline = buffer.indexOf("\n");
      if (newline === -1) return;
      upstream.end();
      resolve(buffer.slice(0, newline + 1));
    });
    upstream.on("error", reject);
    upstream.on("close", () => reject(new Error("herdr closed the connection without a response")));
  });
}

function accepted(response: string): boolean {
  try {
    return !JSON.parse(response).error;
  } catch {
    return false;
  }
}

// herdr accepts a report only when its seq is above the last one for that source, so a release
// on the agent's behalf continues the agent's own sequence.
async function releaseAll(reason: string): Promise<void> {
  const panes = Object.keys(reported);
  if (panes.length === 0) return;
  console.log(`${reason}: releasing ${panes.length} agent(s)`);
  for (const paneId of panes) {
    const agent = reported[paneId]!;
    const request = {
      id: `relay:release:${paneId}`,
      method: RELEASE_AGENT,
      params: { pane_id: paneId, source: agent.source, agent: agent.agent, seq: agent.seq + 1 },
    };
    try {
      const response = await send(request);
      console.log(`  ${paneId} ${agent.source}: ${accepted(response) ? "released" : response.trim()}`);
    } catch (error) {
      console.log(`  ${paneId} ${agent.source}: ${(error as Error).message}`);
    }
    // forget it either way: the pane is gone, or herdr no longer holds this agent
    delete reported[paneId];
  }
  saveReported();
}

// --- container lifecycle ---

async function containerStartedAt(container: string): Promise<number | undefined> {
  const child = Bun.spawn(["docker", "inspect", "--format", "{{.State.StartedAt}}", container], {
    stdout: "pipe",
    stderr: "ignore",
  });
  const output = (await new Response(child.stdout).text()).trim();
  if ((await child.exited) !== 0) return undefined;
  const startedAt = Date.parse(output);
  return Number.isNaN(startedAt) ? undefined : startedAt;
}

// The container restarted while the relay was down if it started after the newest report.
async function releaseIfRestartedWhileDown(container: string): Promise<void> {
  const reports = Object.values(reported);
  if (reports.length === 0) return;
  const startedAt = await containerStartedAt(container);
  const newestReport = Math.max(...reports.map((agent) => agent.reportedAt));
  if (startedAt === undefined) await releaseAll(`${container} is not running`);
  else if (startedAt > newestReport) await releaseAll(`${container} restarted while the relay was down`);
}

function watchContainer(container: string): void {
  const child = Bun.spawn(
    ["docker", "events", "--filter", `container=${container}`, "--filter", "event=die", "--format", "{{.Action}}"],
    { stdout: "pipe", stderr: "ignore" },
  );
  void (async () => {
    const lines = child.stdout.pipeThrough(new TextDecoderStream());
    for await (const chunk of lines) {
      if (chunk.includes("die")) await releaseAll(`${container} stopped`);
    }
  })();
  // docker restarted or the stream ended: catch up on what was missed, then watch again
  void child.exited.then(async () => {
    await Bun.sleep(EVENTS_RETRY_MS);
    await releaseIfRestartedWhileDown(container);
    watchContainer(container);
  });
}

// --- relay server ---

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
      send(request)
        .then((response) => {
          if (accepted(response)) track(request);
          client.end(response);
        })
        .catch(() => client.destroy());
    });
  })
  .listen(LISTEN_PORT, LISTEN_HOST, () => {
    console.log(`herdr-relay ${LISTEN_HOST}:${LISTEN_PORT} -> ${HERDR_SOCKET_PATH}`);
  });

if (CONTAINER) {
  console.log(`releasing agents when ${CONTAINER} stops; state in ${STATE_PATH}`);
  await releaseIfRestartedWhileDown(CONTAINER);
  watchContainer(CONTAINER);
}
