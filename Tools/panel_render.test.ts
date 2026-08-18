import { assert, assertEquals, assertStringIncludes } from "@std/assert";
import {
  deltaLabel,
  escapeHTML,
  minimumRunsForTrend,
  type PanelFonts,
  renderPanel,
  sparkline,
} from "./panel_render.ts";
import type { HistoryRecord, PanelSnapshot } from "./panel.ts";

const fonts: PanelFonts = {
  frauncesBase64: "AA==",
  interRegularBase64: "AA==",
  interSemiBoldBase64: "AA==",
};

function snapshot(overrides: Partial<PanelSnapshot> = {}): PanelSnapshot {
  return {
    generatedAt: "2026-08-18T09:30:00.000Z",
    deep: false,
    premise: "A Brazilian-Portuguese iOS app.",
    yours: [
      {
        title: "Open the company",
        section: "Blocks launch completely",
        done: false,
      },
      {
        title: "Request the D-U-N-S",
        section: "Blocks launch completely",
        done: false,
        blockedBy: "Open the company",
      },
    ],
    gates: [
      {
        id: "repository.ci-preflight",
        status: "pass",
        message: "CI enforces invariants.",
      },
      {
        id: "repository.legal-values",
        status: "warning",
        message: "Legal values are external.",
      },
    ],
    next: [
      {
        rank: 1,
        area: "Task lifecycle",
        priority: "HIGH",
        title: "Overdue vanish",
        symptom: "A task due yesterday disappears.",
      },
    ],
    live: [{ name: "ninai.app", state: "ok", detail: "answering" }],
    ci: "success",
    ...overrides,
  };
}

function history(count: number): HistoryRecord[] {
  return Array.from({ length: count }, (_, index) => ({
    at: `2026-08-${String(index + 1).padStart(2, "0")}T00:00:00.000Z`,
    yoursOpen: 16,
    yoursActionable: 10 - index,
    gatesPass: 20,
    gatesWarning: 1,
    gatesFailure: 0,
    nextOpen: 91,
    nextClosed: 0,
    ci: "success",
    health: "ok",
  }));
}

Deno.test("a backlog symptom carrying quotes and angle brackets cannot break the page", () => {
  assertEquals(
    escapeHTML('A "boleto" & <script>alert(1)</script>'),
    "A &quot;boleto&quot; &amp; &lt;script&gt;alert(1)&lt;/script&gt;",
  );
});

Deno.test("the panel escapes content it did not author", () => {
  const html = renderPanel(
    snapshot({ premise: 'He said "no" & left <b>' }),
    [],
    fonts,
  );

  assertStringIncludes(html, "&quot;no&quot; &amp; left &lt;b&gt;");
  assert(!html.includes("left <b>"));
});

Deno.test("the trend refuses to draw below three runs and says so", () => {
  assertEquals(sparkline([5]), "");
  assertEquals(sparkline([5, 4]), "");
  assertEquals(minimumRunsForTrend, 3);

  const html = renderPanel(snapshot(), [], fonts);
  assertStringIncludes(html, "Not enough runs yet to show movement.");
  assert(!html.includes('<svg class="spark"'));
});

Deno.test("three runs are enough for the line to appear", () => {
  const html = renderPanel(snapshot(), history(2), fonts);

  assertStringIncludes(html, '<svg class="spark"');
  assert(!html.includes("Not enough runs yet"));
});

Deno.test("the sparkline plots every point and marks the latest", () => {
  const svg = sparkline([3, 1, 2]);

  assertStringIncludes(svg, "<polyline");
  assertStringIncludes(svg, "<circle");
  assertEquals((svg.match(/,/g) ?? []).length >= 3, true);
});

Deno.test("a flat series is drawn rather than dividing by a zero span", () => {
  const svg = sparkline([4, 4, 4]);

  assertStringIncludes(svg, "<polyline");
  assert(!svg.includes("NaN"));
});

Deno.test("the delta reads as a direction rather than a raw number", () => {
  assertEquals(deltaLabel([10, 8, 6]), "down 4 across 3 runs");
  assertEquals(deltaLabel([6, 8]), "up 2 across 2 runs");
  assertEquals(deltaLabel([5, 5, 5]), "no change across 3 runs");
  assertEquals(deltaLabel([5]), "");
});

Deno.test("the headline counts work that can start today, not everything open", () => {
  const html = renderPanel(snapshot(), [], fonts);

  // Two open blockers, but one waits on the other.
  assertStringIncludes(html, '<span class="figure">1</span>');
  assertStringIncludes(html, "things only you can clear, ready to start today");
});

Deno.test("blocked work is separated from work that can start", () => {
  const html = renderPanel(snapshot(), [], fonts);

  assertStringIncludes(html, "You can start these today");
  assertStringIncludes(html, "Waiting on something else");
  assertStringIncludes(html, "waits on Open the company");
});

Deno.test("nothing waiting means no waiting heading at all", () => {
  const html = renderPanel(
    snapshot({
      yours: [{ title: "Only thing", section: "Blocks launch", done: false }],
    }),
    [],
    fonts,
  );

  assert(!html.includes("Waiting on something else"));
});

Deno.test("a panel with no data yet states why rather than showing a zero", () => {
  const html = renderPanel(
    snapshot({
      live: [{
        name: "Revenue",
        state: "not-yet",
        detail: "blocked on the App Store record above",
      }],
    }),
    [],
    fonts,
  );

  assertStringIncludes(html, "blocked on the App Store record above");
  assert(!html.includes("R$ 0,00"));
});

Deno.test("failing gates sort above warnings and passes", () => {
  const html = renderPanel(
    snapshot({
      gates: [
        { id: "a.pass", status: "pass", message: "fine" },
        { id: "b.fail", status: "failure", message: "broken" },
        { id: "c.warn", status: "warning", message: "careful" },
      ],
    }),
    [],
    fonts,
  );

  const fail = html.indexOf("b.fail");
  const warn = html.indexOf("c.warn");
  const pass = html.indexOf("a.pass");
  assert(fail < warn && warn < pass, "expected failure, warning, then pass");
});

Deno.test("the page is self-contained so it survives being published as an artifact", () => {
  const html = renderPanel(snapshot(), history(3), fonts);

  assert(!html.includes("http://"));
  assert(!/src=["']https:/.test(html));
  assert(!/href=["']https:/.test(html));
  assertStringIncludes(html, "data:font/ttf;base64,");
});

Deno.test("the generation stamp is rendered so a stale panel is obvious", () => {
  const html = renderPanel(snapshot(), [], fonts);

  assertStringIncludes(html, "2026-08-18 09:30 UTC");
  assertStringIncludes(html, "fast run");
});

Deno.test("a deep run says so, because it means something different", () => {
  const html = renderPanel(snapshot({ deep: true }), [], fonts);

  assertStringIncludes(html, "deep run");
});
