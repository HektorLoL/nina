import { assert, assertEquals, assertStringIncludes } from "@std/assert";
import {
  isActionable,
  parseBacklog,
  parseGates,
  parseHistory,
  parsePremise,
  parseYours,
  summarize,
  type YoursItem,
} from "./panel.ts";

const repoRoot = new URL("../", import.meta.url);
const vaultBlockers =
  "/Users/heitorsuper/developer/Notes vault/My notes/Nina/What claude needs from me.md";

async function repoFile(path: string): Promise<string> {
  return await Deno.readTextFile(new URL(path, repoRoot));
}

Deno.test("the premise comes from the operating manual rather than a copy", async () => {
  const premise = parsePremise(await repoFile("CLAUDE.md"));

  assertStringIncludes(premise, "Brazilian-Portuguese iOS app");
  assertStringIncludes(premise, "mental load");
  // Read as one line: the source wraps it across four.
  assert(!premise.includes("\n"));
});

Deno.test("a manual with no section 2 yields no premise instead of guessing", () => {
  assertEquals(parsePremise("# Title\n\n## 1. Something\n\n**Bold.**"), "");
});

Deno.test("every backlog gap is read, with its rank, priority and area", async () => {
  const items = parseBacklog(await repoFile("docs/product-depth-backlog.md"));

  assertEquals(items.length, 91);
  assertEquals(items[0].rank, 1);
  assertEquals(items.at(-1)?.rank, 91);
  assertEquals(items.filter((item) => item.priority === "HIGH").length, 51);
  assertEquals(items.filter((item) => item.priority === "MEDIUM").length, 36);
  assertEquals(items.filter((item) => item.priority === "LOW").length, 4);
  assert(items.every((item) => item.symptom.length > 0));
  assert(items.every((item) => item.area.length > 0));
});

Deno.test("a long area heading is shortened at its first parenthetical", () => {
  const items = parseBacklog([
    "## Shopping / groceries depth (aisles, quantities, history)",
    "",
    "#### [HIGH] Something is wrong",
    "",
    "- **Symptom:** It is wrong.",
  ].join("\n"));

  assertEquals(items[0].area, "Shopping / groceries depth");
});

Deno.test("a closed gap keeps its rank instead of vanishing from the count", () => {
  const items = parseBacklog([
    "## Area",
    "#### [HIGH] First",
    "- **Symptom:** One.",
    "- **Closed:** 2026-08-18 — shipped.",
    "#### [MEDIUM] Second",
    "- **Symptom:** Two.",
  ].join("\n"));

  assertEquals(items.length, 2);
  assertEquals(items[0].closed, "2026-08-18 — shipped.");
  assertEquals(items[1].rank, 2);
  assertEquals(items[1].closed, undefined);
});

Deno.test("only the first symptom of a gap is taken", () => {
  const items = parseBacklog([
    "## Area",
    "#### [LOW] Thing",
    "- **Symptom:** The real one.",
    "- **Sketch:** Mentions - **Symptom:** in prose.",
  ].join("\n"));

  assertEquals(items[0].symptom, "The real one.");
});

Deno.test("the blocker list is read from the vault, sections one through three", async () => {
  let source: string;
  try {
    source = await Deno.readTextFile(vaultBlockers);
  } catch {
    // The vault is a separate repository on one machine; CI has no copy, and
    // the panel is built to degrade rather than fail when it is absent.
    return;
  }
  const items = parseYours(source);

  // A living note, so this asserts shape rather than a count that would go red
  // every time a blocker is ticked off.
  assert(items.length >= 5, `parsed only ${items.length} blockers`);
  assert(items.every((item) => item.title.length > 0));
  assert(items.every((item) => item.section.length > 0));
  assert(
    items.some((item) => !item.done),
    "a note with nothing open would mean the launch is unblocked, which it is not",
  );
  assert(
    !items.some((item) => item.section.startsWith("What I")),
    "informational sections must not reach the work lane",
  );
});

Deno.test("a box ticked by hand with inner spaces still reads as done", () => {
  const items = parseYours([
    "## 1. Blocks launch",
    "### [ X ] Ticked by hand",
    "### [x] Ticked by machine",
    "### [ ] Still open",
    "## 4. What I installed",
    "### [ ] Not work",
  ].join("\n"));

  assertEquals(items.map((item) => [item.title, item.done]), [
    ["Ticked by hand", true],
    ["Ticked by machine", true],
    ["Still open", false],
  ]);
});

Deno.test("informational sections are not counted as work", () => {
  const items = parseYours([
    "## 1. Blocks launch completely",
    "### [ ] A real blocker",
    "## 4. What I installed on your Mac today (no action needed)",
    "### [ ] Not a blocker",
    "## 5. What I do *not* need from you",
    "### [ ] Also not a blocker",
  ].join("\n"));

  assertEquals(items.length, 1);
  assertEquals(items[0].title, "A real blocker");
});

Deno.test("a ticked blocker reads as done", () => {
  const items = parseYours([
    "## 2. Decisions only you can make",
    "### [x] Settled",
    "### [ ] Open",
  ].join("\n"));

  assertEquals(items[0].done, true);
  assertEquals(items[1].done, false);
});

Deno.test("blocked-by and unlocks are read when present", () => {
  const items = parseYours([
    "## 1. Blocks launch completely",
    "### [ ] Request the D-U-N-S",
    "**Blocked by:** Open the company.",
    "**Unlocks:** The Apple Organization account.",
  ].join("\n"));

  assertEquals(items[0].blockedBy, "Open the company");
  assertEquals(items[0].unlocks, "The Apple Organization account");
});

Deno.test("work waiting on something unfinished is not actionable today", () => {
  const all: YoursItem[] = [
    { title: "Open the company", section: "1", done: false },
    {
      title: "Request the D-U-N-S",
      section: "1",
      done: false,
      blockedBy: "Open the company",
    },
  ];

  assertEquals(isActionable(all[0], all), true);
  assertEquals(isActionable(all[1], all), false);
});

Deno.test("clearing a blocker makes what waited on it actionable", () => {
  const all: YoursItem[] = [
    { title: "Open the company", section: "1", done: true },
    {
      title: "Request the D-U-N-S",
      section: "1",
      done: false,
      blockedBy: "Open the company",
    },
  ];

  assertEquals(isActionable(all[1], all), true);
});

Deno.test("a blocked-by naming nothing real stays actionable rather than hiding", () => {
  const all: YoursItem[] = [
    { title: "Thing", section: "1", done: false, blockedBy: "A typo" },
  ];

  assertEquals(isActionable(all[0], all), true);
});

Deno.test("done work is never actionable", () => {
  const all: YoursItem[] = [{ title: "Thing", section: "1", done: true }];

  assertEquals(isActionable(all[0], all), false);
});

Deno.test("preflight output is read back as check results", () => {
  const gates = parseGates([
    "PASS repository.ci-preflight: CI enforces repository production invariants.",
    "WARN repository.legal-values: Legal values are intentionally external.",
    "FAIL environment.legal-identity: Fill the production controller name.",
    "",
    "Preflight: 1 failure(s), 1 warning(s).",
  ].join("\n"));

  assertEquals(gates.length, 3);
  assertEquals(gates[0].status, "pass");
  assertEquals(gates[1].status, "warning");
  assertEquals(gates[2].status, "failure");
  assertEquals(gates[2].id, "environment.legal-identity");
  assertEquals(gates[2].message, "Fill the production controller name.");
});

Deno.test("the preflight still prints the shape this parser reads back", async () => {
  const source = await repoFile("Tools/production_preflight.ts");

  // The gates lane is coupled to printResults by text, not by a type, so a
  // reworded log line would empty the lane rather than fail anywhere else.
  assertStringIncludes(source, "`${label} ${result.id}: ${result.message}`");
  assertStringIncludes(source, '? "PASS"');
  assertStringIncludes(source, '? "WARN"');
  assertStringIncludes(source, ': "FAIL"');
});

Deno.test("a summary counts each lane separately", () => {
  const record = summarize({
    generatedAt: "2026-08-18T00:00:00.000Z",
    deep: false,
    premise: "",
    yours: [
      { title: "A", section: "1", done: false },
      { title: "B", section: "1", done: true },
      { title: "C", section: "1", done: false, blockedBy: "A" },
    ],
    gates: [
      { id: "a.b", status: "pass", message: "" },
      { id: "c.d", status: "warning", message: "" },
    ],
    next: [
      { rank: 1, area: "x", priority: "HIGH", title: "t", symptom: "s" },
      {
        rank: 2,
        area: "x",
        priority: "LOW",
        title: "t",
        symptom: "s",
        closed: "done",
      },
    ],
    live: [{ name: "ninai.app", state: "ok", detail: "" }],
    ci: "success",
  });

  assertEquals(record.yoursOpen, 2);
  assertEquals(record.yoursActionable, 1);
  assertEquals(record.gatesPass, 1);
  assertEquals(record.gatesWarning, 1);
  assertEquals(record.gatesFailure, 0);
  assertEquals(record.nextOpen, 1);
  assertEquals(record.nextClosed, 1);
  assertEquals(record.health, "ok");
});

Deno.test("a truncated history line is skipped rather than failing the run", () => {
  const records = parseHistory([
    '{"at":"2026-08-18T00:00:00.000Z","yoursOpen":16}',
    '{"at":"2026-08-19T00:00:00.000Z","yoursOpen"',
    "",
  ].join("\n"));

  assertEquals(records.length, 1);
  assertEquals(records[0].yoursOpen, 16);
});
