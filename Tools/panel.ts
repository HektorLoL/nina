import { renderPanel } from "./panel_render.ts";

export type LaneStatus = "pass" | "warning" | "failure";

export interface YoursItem {
  title: string;
  section: string;
  done: boolean;
  blockedBy?: string;
  unlocks?: string;
}

export interface GateItem {
  id: string;
  status: LaneStatus;
  message: string;
}

export interface NextItem {
  rank: number;
  area: string;
  priority: "HIGH" | "MEDIUM" | "LOW";
  title: string;
  symptom: string;
  closed?: string;
}

export interface LiveSystem {
  name: string;
  state: "ok" | "degraded" | "unreachable" | "not-yet";
  detail: string;
}

export interface PanelSnapshot {
  generatedAt: string;
  deep: boolean;
  premise: string;
  yours: YoursItem[];
  gates: GateItem[];
  next: NextItem[];
  live: LiveSystem[];
  ci: string;
}

export interface HistoryRecord {
  at: string;
  yoursOpen: number;
  yoursActionable: number;
  gatesPass: number;
  gatesWarning: number;
  gatesFailure: number;
  nextOpen: number;
  nextClosed: number;
  ci: string;
  health: string;
}

// The premise is read rather than copied so the one sentence at the top of the
// panel can never drift from the one sentence that governs the repository.
export function parsePremise(source: string): string {
  const start = source.indexOf("## 2. What Nina is");
  if (start < 0) return "";
  const bold = source.slice(start).match(/\*\*([\s\S]+?)\*\*/);
  return bold ? bold[1].replace(/\s+/g, " ").trim() : "";
}

function shortArea(heading: string): string {
  return heading.split(/\s+[—(]/)[0].trim();
}

export function parseBacklog(source: string): NextItem[] {
  const items: NextItem[] = [];
  let area = "";
  let current: NextItem | undefined;
  let rank = 0;

  for (const line of source.split("\n")) {
    const areaHeading = line.match(/^## (.+)$/);
    if (areaHeading) {
      area = shortArea(areaHeading[1]);
      current = undefined;
      continue;
    }

    const gap = line.match(/^#### \[(HIGH|MEDIUM|LOW)\] (.+)$/);
    if (gap) {
      rank += 1;
      current = {
        rank,
        area,
        priority: gap[1] as NextItem["priority"],
        title: gap[2].trim(),
        symptom: "",
      };
      items.push(current);
      continue;
    }

    if (!current) continue;

    const symptom = line.match(/^- \*\*Symptom:\*\* (.+)$/);
    if (symptom && !current.symptom) {
      current.symptom = symptom[1].trim();
      continue;
    }

    const closed = line.match(/^- \*\*Closed:\*\* (.+)$/);
    if (closed) current.closed = closed[1].trim();
  }

  return items;
}

// Only the first three sections carry work; 4 and 5 are informational, and
// counting them would inflate the one number the panel exists to report.
export function parseYours(source: string): YoursItem[] {
  const items: YoursItem[] = [];
  let section = "";
  let inScope = false;
  let current: YoursItem | undefined;

  for (const line of source.split("\n")) {
    const heading = line.match(/^## (\d+)\.\s*(.+)$/);
    if (heading) {
      inScope = ["1", "2", "3"].includes(heading[1]);
      section = heading[2].trim();
      current = undefined;
      continue;
    }

    // Heitor ticks by hand as "[ X ]", so the box tolerates inner spaces.
    const item = line.match(/^### \[\s*([xX]?)\s*\]\s*(.+)$/);
    if (item) {
      if (!inScope) {
        current = undefined;
        continue;
      }
      current = {
        title: item[2].trim(),
        section,
        done: item[1].toLowerCase() === "x",
      };
      items.push(current);
      continue;
    }

    if (!current) continue;

    const blockedBy = line.match(/^\*\*Blocked by:\*\*\s*(.+?)\.?\s*$/);
    if (blockedBy) current.blockedBy = blockedBy[1].trim();

    const unlocks = line.match(/^\*\*Unlocks:\*\*\s*(.+?)\.?\s*$/);
    if (unlocks) current.unlocks = unlocks[1].trim();
  }

  return items;
}

// An item waiting on something unfinished is not work you can pick up today,
// which is the difference between a list of twelve and a list of three.
export function isActionable(
  item: YoursItem,
  all: readonly YoursItem[],
): boolean {
  if (item.done) return false;
  if (!item.blockedBy) return true;
  const blocker = all.find((candidate) => candidate.title === item.blockedBy);
  return blocker ? blocker.done : true;
}

export function parseGates(output: string): GateItem[] {
  const items: GateItem[] = [];
  for (const line of output.split("\n")) {
    const match = line.match(/^(PASS|WARN|FAIL) ([A-Za-z0-9.\-_]+): (.+)$/);
    if (!match) continue;
    items.push({
      id: match[2],
      status: match[1] === "PASS"
        ? "pass"
        : match[1] === "WARN"
        ? "warning"
        : "failure",
      message: match[3].trim(),
    });
  }
  return items;
}

export function summarize(snapshot: PanelSnapshot): HistoryRecord {
  const health = snapshot.live.find((system) => system.name === "ninai.app");
  return {
    at: snapshot.generatedAt,
    yoursOpen: snapshot.yours.filter((item) => !item.done).length,
    yoursActionable:
      snapshot.yours.filter((item) => isActionable(item, snapshot.yours))
        .length,
    gatesPass: snapshot.gates.filter((gate) => gate.status === "pass").length,
    gatesWarning:
      snapshot.gates.filter((gate) => gate.status === "warning").length,
    gatesFailure:
      snapshot.gates.filter((gate) => gate.status === "failure").length,
    nextOpen: snapshot.next.filter((item) => !item.closed).length,
    nextClosed: snapshot.next.filter((item) => item.closed).length,
    ci: snapshot.ci,
    health: health?.state ?? "unreachable",
  };
}

export function parseHistory(source: string): HistoryRecord[] {
  const records: HistoryRecord[] = [];
  for (const line of source.split("\n")) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    try {
      records.push(JSON.parse(trimmed) as HistoryRecord);
    } catch {
      continue;
    }
  }
  return records;
}

const vaultBlockerPath =
  "/Users/heitorsuper/developer/Notes vault/My notes/Nina/What claude needs from me.md";

// Encoded here rather than via @std/encoding: deno.lock is frozen, and one new
// import fails the edge-functions job before a single test runs.
function encodeBase64(bytes: Uint8Array): string {
  let binary = "";
  const chunk = 0x8000;
  for (let index = 0; index < bytes.length; index += chunk) {
    binary += String.fromCharCode(...bytes.subarray(index, index + chunk));
  }
  return btoa(binary);
}

async function run(command: string, args: string[]): Promise<string> {
  try {
    const process = new Deno.Command(command, {
      args,
      stdout: "piped",
      stderr: "null",
    });
    const { stdout } = await process.output();
    return new TextDecoder().decode(stdout);
  } catch {
    return "";
  }
}

async function readIfPresent(path: string | URL): Promise<string> {
  try {
    return await Deno.readTextFile(path);
  } catch {
    return "";
  }
}

async function collectLive(root: URL): Promise<LiveSystem[]> {
  const systems: LiveSystem[] = [];

  try {
    const response = await fetch("https://ninai.app/api/health", {
      signal: AbortSignal.timeout(8_000),
    });
    const body = await response.json() as {
      status?: string;
      checks?: Record<string, boolean>;
    };
    const failing = Object.entries(body.checks ?? {})
      .filter(([, value]) => !value)
      .map(([key]) => key);
    systems.push({
      name: "ninai.app",
      state: body.status === "ok" ? "ok" : "degraded",
      detail: failing.length === 0
        ? "invite lookup and waitlist both answering"
        : `degraded: ${failing.join(", ")}`,
    });
  } catch {
    systems.push({
      name: "ninai.app",
      state: "unreachable",
      detail: "no answer from /api/health",
    });
  }

  // Stating why a panel is empty beats printing a zero for a shop that does not
  // exist yet, the same choice /privacidade makes about a missing controller.
  const productionEnv = await readIfPresent(
    new URL("config/production.env", root),
  );
  const hasAppleID = /^NINA_APP_APPLE_ID=(?!replace_with)\S+/m.test(
    productionEnv,
  );

  systems.push({
    name: "App Store",
    state: hasAppleID ? "ok" : "not-yet",
    detail: hasAppleID
      ? "app record configured"
      : "no app in App Store Connect — nothing can be sold yet",
  });
  systems.push({
    name: "Revenue",
    state: "not-yet",
    detail: hasAppleID
      ? "awaiting the first transaction"
      : "blocked on the App Store record above",
  });
  systems.push({
    name: "AI spend",
    state: "not-yet",
    detail:
      "US$20/mo chat + US$5/mo insights, capped in the database; no run recorded yet",
  });

  return systems;
}

async function collectCI(): Promise<string> {
  const output = await run("gh", [
    "run",
    "list",
    "--branch",
    "main",
    "--limit",
    "1",
    "--json",
    "conclusion,status",
  ]);
  try {
    const runs = JSON.parse(output) as Array<
      { conclusion?: string; status?: string }
    >;
    const latest = runs[0];
    if (!latest) return "no runs found";
    return latest.conclusion || latest.status || "unknown";
  } catch {
    return "unavailable";
  }
}

async function main(): Promise<void> {
  const deep = Deno.args.includes("--deep");
  const root = new URL("../", import.meta.url);
  const rootPath = decodeURIComponent(root.pathname);

  const preflightArgs = [
    "run",
    "--allow-read",
    "--allow-run=git",
    "Tools/production_preflight.ts",
    "repository",
  ];
  const [claudeMd, backlog, vault, preflight, ci, live] = await Promise.all([
    readIfPresent(new URL("CLAUDE.md", root)),
    readIfPresent(new URL("docs/product-depth-backlog.md", root)),
    readIfPresent(vaultBlockerPath),
    run("deno", preflightArgs),
    collectCI(),
    collectLive(root),
  ]);

  const gates = parseGates(preflight);
  if (deep) {
    gates.push(...parseGates(await run("deno", ["task", "db:test"])));
  }

  const yours = parseYours(vault);
  if (vault === "") {
    live.push({
      name: "Vault",
      state: "unreachable",
      detail:
        `not found at ${vaultBlockerPath} — the Yours lane is empty for that reason, not because the work is done`,
    });
  }

  const snapshot: PanelSnapshot = {
    generatedAt: new Date().toISOString(),
    deep,
    premise: parsePremise(claudeMd),
    yours,
    gates,
    next: parseBacklog(backlog),
    live,
    ci,
  };

  const historyPath = new URL("panel/history.jsonl", root);
  const history = parseHistory(await readIfPresent(historyPath));

  const fontFor = async (path: string) =>
    encodeBase64(await Deno.readFile(new URL(path, root)));

  const html = renderPanel(snapshot, history, {
    frauncesBase64: await fontFor("web/public/fonts/Fraunces-Regular.ttf"),
    interRegularBase64: await fontFor(
      "web/node_modules/@fontsource/inter/files/inter-latin-400-normal.woff2",
    ),
    interSemiBoldBase64: await fontFor(
      "web/node_modules/@fontsource/inter/files/inter-latin-600-normal.woff2",
    ),
  });

  await Deno.mkdir(new URL("panel/", root), { recursive: true });
  await Deno.writeTextFile(new URL("panel/index.html", root), html);
  await Deno.writeTextFile(
    historyPath,
    `${JSON.stringify(summarize(snapshot))}\n`,
    { append: true },
  );

  const now = summarize(snapshot);
  console.log(
    `Panel written to ${rootPath}panel/index.html — ` +
      `${now.yoursActionable} ready of ${now.yoursOpen} yours, ` +
      `${now.gatesFailure} gate failure(s), ${now.nextOpen} backlog items open.`,
  );
}

if (import.meta.main) {
  try {
    await main();
  } catch (error) {
    console.error(
      `Panel failed: ${
        error instanceof Error ? error.message : "unexpected failure"
      }`,
    );
    Deno.exit(1);
  }
}
