import { assert, assertEquals, assertStringIncludes } from "@std/assert";
import {
  columnsFor,
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
        symptom: "Gone.",
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

function tileCount(html: string): number {
  return (html.match(/<i class="t /g) ?? []).length;
}

Deno.test("a title carrying quotes and angle brackets cannot break the page", () => {
  assertEquals(
    escapeHTML('A "boleto" & <script>alert(1)</script>'),
    "A &quot;boleto&quot; &amp; &lt;script&gt;alert(1)&lt;/script&gt;",
  );
});

Deno.test("the wall escapes content it did not author", () => {
  const html = renderPanel(
    snapshot({ premise: 'He said "no" & left <b>' }),
    [],
    fonts,
  );

  assertStringIncludes(html, "&quot;no&quot; &amp; left &lt;b&gt;");
  assert(!html.includes("left <b>"));
});

Deno.test("every item in every lane becomes exactly one tile", () => {
  const html = renderPanel(snapshot(), [], fonts);

  // 2 yours + 2 gates + 1 next + 1 system.
  assertEquals(tileCount(html), 6);
});

Deno.test("a closed backlog item keeps its tile so the wall does not shrink", () => {
  const open = renderPanel(snapshot(), [], fonts);
  const closed = renderPanel(
    snapshot({
      next: [{
        rank: 1,
        area: "Task lifecycle",
        priority: "HIGH",
        title: "Overdue vanish",
        symptom: "Gone.",
        closed: "2026-08-18 — shipped",
      }],
    }),
    [],
    fonts,
  );

  assertEquals(tileCount(open), tileCount(closed));
  assertStringIncludes(closed, "closed 2026-08-18 — shipped");
});

Deno.test("a blocked item is glazed apart from one that can start today", () => {
  const html = renderPanel(snapshot(), [], fonts);

  assertStringIncludes(html, 'class="t ready"');
  assertStringIncludes(html, 'class="t waiting"');
  assertStringIncludes(html, "waits on Open the company");
});

Deno.test("the headline counts work that can start today, not everything open", () => {
  const html = renderPanel(snapshot(), [], fonts);

  assertStringIncludes(html, '<div class="figure">1</div>');
});

Deno.test("the page holds no scrollbar in either axis", () => {
  const html = renderPanel(snapshot(), history(3), fonts);

  assertStringIncludes(html, "html,body{height:100%;overflow:hidden}");
});

Deno.test("nothing that would trap the fixed readout inside a tile survives", () => {
  const html = renderPanel(snapshot(), history(3), fonts);
  const styles = html.slice(html.indexOf("<style>"), html.indexOf("</style>"));
  const hover = styles.slice(styles.indexOf(".t:hover"));

  // transform and filter both make a tile a containing block for position:fixed,
  // which silently re-anchors the readout slip to the tile.
  assert(!hover.includes("transform:"), "hover must not transform a tile");
  assert(!hover.includes("filter:"), "hover must not filter a tile");
  assertStringIncludes(styles, ".tip{position:fixed");
});

Deno.test("every tile is reachable without a mouse", () => {
  const html = renderPanel(snapshot(), [], fonts);
  const tiles = tileCount(html);

  assertEquals((html.match(/tabindex="0"/g) ?? []).length, tiles);
  assertStringIncludes(html, ".t:focus-visible .tip");
});

Deno.test("the trend refuses to draw below three runs and says so", () => {
  assertEquals(sparkline([5]), "");
  assertEquals(sparkline([5, 4]), "");
  assertEquals(minimumRunsForTrend, 3);

  const html = renderPanel(snapshot(), [], fonts);
  assertStringIncludes(html, "too few runs to show movement");
  assert(!html.includes('<svg class="spark"'));
});

Deno.test("three runs are enough for the line to appear", () => {
  const html = renderPanel(snapshot(), history(2), fonts);

  assertStringIncludes(html, '<svg class="spark"');
  assert(!html.includes("too few runs"));
});

Deno.test("a flat series is drawn rather than dividing by a zero span", () => {
  const svg = sparkline([4, 4, 4]);

  assertStringIncludes(svg, "<polyline");
  assert(!svg.includes("NaN"));
});

Deno.test("the delta reads as a direction rather than a raw number", () => {
  assertEquals(deltaLabel([10, 8, 6]), "down 4 across 3 runs");
  assertEquals(deltaLabel([5, 5, 5]), "steady across 3 runs");
  assertEquals(deltaLabel([5]), "too few runs to show movement");
});

Deno.test("a cluster tiles its pane rather than forming a column or a strip", () => {
  assertEquals(columnsFor(4), 2);
  assertEquals(columnsFor(16), 4);
  assertEquals(columnsFor(91, 2), 14);
  assertEquals(columnsFor(1), 1);
  assertEquals(columnsFor(0), 1);
});

Deno.test("a lane with nothing in it still renders its cluster rather than collapsing", () => {
  const html = renderPanel(
    snapshot({ next: [], yours: [], gates: [], live: [] }),
    [],
    fonts,
  );

  assertEquals(tileCount(html), 0);
  assertStringIncludes(html, ">Next</h2>");
  assertStringIncludes(html, ">Yours</h2>");
});

Deno.test("a system with no data yet states why rather than showing a zero", () => {
  const html = renderPanel(
    snapshot({
      live: [{
        name: "Revenue",
        state: "not-yet",
        detail: "blocked on the App Store record",
      }],
    }),
    [],
    fonts,
  );

  assertStringIncludes(html, "blocked on the App Store record");
  assert(!html.includes("R$ 0,00"));
});

Deno.test("the page is self-contained so it survives being published as an artifact", () => {
  const html = renderPanel(snapshot(), history(3), fonts);

  assert(!html.includes("http://"));
  assert(!/src=["']https:/.test(html));
  assertStringIncludes(html, "data:font/ttf;base64,");
});

Deno.test("the generation stamp is rendered so a stale wall is obvious", () => {
  const html = renderPanel(snapshot(), [], fonts);

  assertStringIncludes(html, "2026-08-18 09:30 UTC");
  assertStringIncludes(html, ">fast<");
});
