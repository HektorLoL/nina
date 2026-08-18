import {
  type HistoryRecord,
  isActionable,
  type PanelSnapshot,
  summarize,
} from "./panel.ts";

export interface PanelFonts {
  frauncesBase64: string;
  interRegularBase64: string;
  interSemiBoldBase64: string;
}

export function escapeHTML(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

// Below three runs the wall shows no line at all, the same refusal
// HouseholdWorkload makes below six assigned tasks.
export const minimumRunsForTrend = 3;

export function sparkline(values: readonly number[]): string {
  if (values.length < minimumRunsForTrend) return "";

  const width = 100;
  const height = 26;
  const highest = Math.max(...values);
  const lowest = Math.min(...values);
  const span = highest - lowest || 1;
  const step = width / (values.length - 1);

  const points = values.map((value, index) => {
    const x = (index * step).toFixed(2);
    const y = (height - ((value - lowest) / span) * height).toFixed(2);
    return `${x},${y}`;
  });

  const [lastX, lastY] = points[points.length - 1].split(",");

  return `<svg class="spark" viewBox="0 0 ${width} ${height}" preserveAspectRatio="none" ` +
    `role="img" aria-label="Across ${values.length} runs">` +
    `<polyline points="${points.join(" ")}" />` +
    `<circle cx="${lastX}" cy="${lastY}" r="2" vector-effect="non-scaling-stroke" />` +
    `</svg>`;
}

// Column count follows the pane's own proportion, so a cluster tiles its space
// instead of forming a column in a wide box or a strip in a tall one.
export function deltaLabel(values: readonly number[]): string {
  if (values.length < minimumRunsForTrend) {
    return "too few runs to show movement";
  }
  const change = values[values.length - 1] - values[0];
  if (change === 0) return `steady across ${values.length} runs`;
  return `${change < 0 ? "down" : "up"} ${
    Math.abs(change)
  } across ${values.length} runs`;
}

export function columnsFor(count: number, aspect = 1): number {
  if (count <= 1) return 1;
  return Math.max(1, Math.ceil(Math.sqrt(count * aspect)));
}

function tile(tone: string, label: string, detail: string): string {
  return `<i class="t ${tone}" tabindex="0"><s class="tip"><b>${
    escapeHTML(label)
  }</b>${detail ? `<em>${escapeHTML(detail)}</em>` : ""}</s></i>`;
}

function yoursField(snapshot: PanelSnapshot): string {
  return snapshot.yours.map((item) => {
    const tone = item.done
      ? "done"
      : isActionable(item, snapshot.yours)
      ? "ready"
      : "waiting";
    const detail = item.done
      ? item.section
      : isActionable(item, snapshot.yours)
      ? `${item.section} · you can start this today`
      : `waits on ${item.blockedBy ?? "something else"}`;
    return tile(tone, item.title, detail);
  }).join("");
}

function gatesField(snapshot: PanelSnapshot): string {
  const order = { failure: 0, warning: 1, pass: 2 } as const;
  return [...snapshot.gates]
    .sort((a, b) => order[a.status] - order[b.status])
    .map((gate) => tile(gate.status, gate.id, gate.message))
    .join("");
}

function nextField(snapshot: PanelSnapshot): string {
  return snapshot.next.map((item) => {
    const tone = item.closed ? "done" : item.priority.toLowerCase();
    const detail = item.closed
      ? `closed ${item.closed}`
      : `${item.area} · ${item.priority}`;
    return tile(tone, `${item.rank}. ${item.title}`, detail);
  }).join("");
}

function systemsField(snapshot: PanelSnapshot): string {
  return snapshot.live.map((system) =>
    tile(system.state, system.name, system.detail)
  ).join("");
}

function cluster(
  title: string,
  count: string,
  columns: number,
  maxTile: string,
  tiles: string,
): string {
  return `<section class="cl"><header><h2>${escapeHTML(title)}</h2><b>${
    escapeHTML(count)
  }</b></header><div class="field" style="--cols:${columns};--max:${maxTile}">${tiles}</div></section>`;
}

export function renderPanel(
  snapshot: PanelSnapshot,
  history: readonly HistoryRecord[],
  fonts: PanelFonts,
): string {
  const now = summarize(snapshot);
  const series = [...history, now].map((record) => record.yoursActionable);
  const trend = sparkline(series);
  const changeLabel = deltaLabel(series);

  const stamp = new Date(snapshot.generatedAt).toISOString()
    .replace("T", " ").slice(0, 16);

  const ciTone = snapshot.ci === "success"
    ? "pass"
    : snapshot.ci === "failure"
    ? "failure"
    : "warning";

  return `<title>Nina Panel</title>
<style>
@font-face{font-family:"Fraunces";src:url(data:font/ttf;base64,${fonts.frauncesBase64}) format("truetype");font-weight:400;font-display:block}
@font-face{font-family:"InterPanel";src:url(data:font/woff2;base64,${fonts.interRegularBase64}) format("woff2");font-weight:400;font-display:block}
@font-face{font-family:"InterPanel";src:url(data:font/woff2;base64,${fonts.interSemiBoldBase64}) format("woff2");font-weight:600;font-display:block}
:root{
--ground:#FBFCFD;--grout:#EDF0F4;--line:#DFE4EB;--ink:#131A24;--muted:#5C6675;
--cobalt:#1B4FD8;--cobalt-wash:#E6EDFC;--terracotta:#C2410C;--terracotta-wash:#FBEAE1;
--moss:#3F6B4A;--moss-wash:#E7EFE9;
--display:"Fraunces",Georgia,serif;--face:"InterPanel",-apple-system,BlinkMacSystemFont,sans-serif;
--gap:clamp(2px,.42vmin,5px);
}
*{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%;overflow:hidden}
body{
  background:var(--grout);color:var(--ink);font-family:var(--face);
  -webkit-font-smoothing:antialiased;
  display:grid;grid-template-rows:auto 1fr auto;
  gap:clamp(8px,1.4vmin,18px);
  padding:clamp(10px,1.8vmin,24px);
}
.rail{display:flex;align-items:center;gap:clamp(8px,1.6vmin,20px);font-size:clamp(8px,1.08vmin,11px);letter-spacing:.16em;text-transform:uppercase;color:var(--muted);font-weight:600}
.rail .mark{width:.85em;height:.85em;border-radius:50%;border:2px solid var(--cobalt);border-bottom-color:transparent;transform:rotate(-45deg)}
.rail .ci{margin-left:auto;display:flex;align-items:center;gap:.5em}
.dot{width:.6em;height:.6em;border-radius:50%;background:var(--moss)}
.dot.warning{background:var(--cobalt)}.dot.failure{background:var(--terracotta)}

.wall{display:grid;grid-template-columns:minmax(0,7fr) minmax(0,13fr);grid-template-rows:minmax(0,11fr) minmax(0,9fr);gap:clamp(8px,1.4vmin,18px);min-height:0}
.pane{background:var(--ground);border-radius:clamp(6px,1vmin,14px);padding:clamp(9px,1.5vmin,20px);min-width:0;min-height:0;display:flex;flex-direction:column;box-shadow:0 1px 0 rgba(19,26,36,.05)}
.pane.split{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:clamp(9px,1.6vmin,22px);align-content:stretch}

.figure{font-family:var(--display);font-size:min(26vh,15vw);line-height:.82;letter-spacing:-.03em;color:var(--cobalt);font-variant-numeric:tabular-nums}
.figure-note{font-size:clamp(9px,1.22vmin,13px);line-height:1.35;color:var(--muted);max-width:20ch;margin-top:.5em}
.spark{width:100%;height:clamp(20px,4.2vmin,44px);margin-top:auto;overflow:visible}
.spark polyline{fill:none;stroke:var(--cobalt);stroke-width:1.4;vector-effect:non-scaling-stroke;stroke-linejoin:round;stroke-linecap:round}
.spark circle{fill:var(--cobalt)}
.change{font-size:clamp(8px,1.06vmin,11px);letter-spacing:.1em;text-transform:uppercase;color:var(--muted);margin-top:.55em;font-weight:600}

.cl{display:flex;flex-direction:column;min-width:0;min-height:0;flex:1}
.cl header{display:flex;align-items:baseline;gap:.6em;margin-bottom:clamp(5px,.9vmin,11px)}
.cl h2{font-family:var(--display);font-weight:400;font-size:clamp(12px,1.9vmin,21px);line-height:1;letter-spacing:-.01em}
.cl header b{font-size:clamp(8px,1.06vmin,11px);letter-spacing:.1em;text-transform:uppercase;color:var(--muted);font-weight:600;font-variant-numeric:tabular-nums}
.field{flex:1;min-height:0;min-width:0;display:grid;grid-template-columns:repeat(var(--cols),minmax(0,min(100%,var(--max))));grid-auto-rows:auto;gap:var(--gap);place-content:center;overflow:hidden}

/* Every tile is glazed ceramic: a lit top edge, a shaded foot, and grout between. */
.t{
  aspect-ratio:1;position:relative;border-radius:clamp(1.5px,.34vmin,4px);background:var(--grout);
  box-shadow:inset 0 1px 0 rgba(255,255,255,.7),inset 0 -1px 0 rgba(19,26,36,.07),inset 0 0 0 1px rgba(19,26,36,.035);
  outline:none;transition:box-shadow .12s ease;
}
.t::after{content:"";position:absolute;inset:0;border-radius:inherit;background:linear-gradient(150deg,rgba(255,255,255,.34),rgba(255,255,255,0) 42%);pointer-events:none}

.t.ready{background:var(--cobalt)}
.t.waiting{background:var(--terracotta)}
.t.done{background:var(--moss)}
.t.pass{background:var(--moss-wash);box-shadow:inset 0 0 0 1px rgba(63,107,74,.28)}
.t.warning{background:var(--cobalt-wash)}
.t.failure{background:var(--terracotta)}
.t.high{background:#C9D4EC}
.t.medium{background:#DEE4EF}
.t.low{background:var(--grout)}
.t.ok{background:var(--moss)}
.t.degraded,.t.unreachable{background:var(--terracotta)}
.t\\.not-yet,.t.not-yet{background:#fff;box-shadow:inset 0 0 0 1px var(--line)}

.t:hover,.t:focus-visible{box-shadow:0 0 0 2px var(--ground),0 0 0 4px var(--cobalt);z-index:5}

/* One fixed readout: only the hovered tile's slip is visible, so 126 tiles
   share a single line of text instead of 126 tooltips. */
.tip{position:fixed;left:clamp(10px,1.8vmin,24px);right:clamp(10px,1.8vmin,24px);bottom:clamp(10px,1.8vmin,24px);
  display:flex;align-items:baseline;gap:.8em;opacity:0;pointer-events:none;
  font-style:normal;font-size:clamp(10px,1.3vmin,14px);line-height:1.3;z-index:9}
.tip b{font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:62%}
.tip em{font-style:normal;color:var(--muted);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.t:hover .tip,.t:focus-visible .tip{opacity:1}

.readout{height:clamp(18px,2.5vmin,26px);display:flex;align-items:center;font-size:clamp(9px,1.18vmin,12px);color:var(--muted);letter-spacing:.02em}
.readout .hint{opacity:.75;transition:opacity .12s ease}
/* The slip and the hint share one line, so the hint yields to it. */
body:has(.t:hover) .readout .hint,body:has(.t:focus-visible) .readout .hint{opacity:0}

@media (max-width:760px){
  .wall{grid-template-columns:minmax(0,1fr);grid-template-rows:auto minmax(0,1fr) auto}
  .pane.split{grid-template-columns:minmax(0,1fr) minmax(0,1fr)}
  .figure{font-size:min(15vh,26vw)}
  .figure-note{max-width:none}
}
@media (prefers-reduced-motion:reduce){.t{transition:none}}
</style>
<div class="rail">
  <span class="mark" aria-hidden="true"></span>
  <span>Nina</span><span>${escapeHTML(stamp)} UTC</span>
  <span>${snapshot.deep ? "deep" : "fast"}</span>
  <span class="ci"><span class="dot ${ciTone}"></span>CI ${
    escapeHTML(snapshot.ci)
  }</span>
</div>

<main class="wall">
  <div class="pane">
    <div class="figure">${now.yoursActionable}</div>
    <p class="figure-note">${escapeHTML(snapshot.premise)}</p>
    ${trend}
    <div class="change">${escapeHTML(changeLabel)}</div>
  </div>

  <div class="pane">
    ${
    cluster(
      "Next",
      `${now.nextOpen} open · ${now.nextClosed} closed`,
      columnsFor(snapshot.next.length, 2),
      "clamp(12px,4.6vmin,48px)",
      nextField(snapshot),
    )
  }
  </div>

  <div class="pane split">
    ${
    cluster(
      "Yours",
      `${now.yoursActionable} of ${now.yoursOpen} ready`,
      columnsFor(snapshot.yours.length),
      "clamp(18px,6.4vmin,70px)",
      yoursField(snapshot),
    )
  }
    ${
    cluster(
      "Systems",
      `${snapshot.live.filter((s) => s.state === "ok").length} live`,
      columnsFor(snapshot.live.length),
      "clamp(26px,9vmin,104px)",
      systemsField(snapshot),
    )
  }
  </div>

  <div class="pane">
    ${
    cluster(
      "Gates",
      `${now.gatesFailure} failing · ${now.gatesWarning} warning`,
      columnsFor(snapshot.gates.length, 2),
      "clamp(14px,4.6vmin,46px)",
      gatesField(snapshot),
    )
  }
  </div>
</main>

<div class="readout"><span class="hint">Hover or tab a tile to read it.</span></div>`;
}
