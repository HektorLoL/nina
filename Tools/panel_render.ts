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

// Below three runs the panel says so rather than drawing a line through two
// points, the same refusal HouseholdWorkload makes below six assigned tasks.
export const minimumRunsForTrend = 3;

export function sparkline(values: readonly number[]): string {
  if (values.length < minimumRunsForTrend) return "";

  const width = 240;
  const height = 44;
  const highest = Math.max(...values);
  const lowest = Math.min(...values);
  const span = highest - lowest || 1;
  const step = values.length > 1 ? width / (values.length - 1) : 0;

  const points = values.map((value, index) => {
    const x = (index * step).toFixed(1);
    const y = (height - ((value - lowest) / span) * height).toFixed(1);
    return `${x},${y}`;
  });

  const [lastX, lastY] = points[points.length - 1].split(",");

  return `<svg class="spark" viewBox="0 0 ${width} ${height}" role="img" ` +
    `aria-label="Trend across ${values.length} runs">` +
    `<polyline points="${points.join(" ")}" />` +
    `<circle cx="${lastX}" cy="${lastY}" r="3.5" /></svg>`;
}

export function deltaLabel(values: readonly number[]): string {
  if (values.length < 2) return "";
  const change = values[values.length - 1] - values[0];
  if (change === 0) return `no change across ${values.length} runs`;
  const direction = change < 0 ? "down" : "up";
  return `${direction} ${Math.abs(change)} across ${values.length} runs`;
}

function laneCount(label: string, value: number, tone: string): string {
  return `<span class="tally ${tone}"><b>${value}</b> ${
    escapeHTML(label)
  }</span>`;
}

function yoursSection(snapshot: PanelSnapshot): string {
  const open = snapshot.yours.filter((item) => !item.done);
  if (open.length === 0) {
    return `<p class="empty">Nothing is waiting on you. That has never been true before, so check the vault parsed.</p>`;
  }

  const actionable = open.filter((item) => isActionable(item, snapshot.yours));
  const waiting = open.filter((item) => !isActionable(item, snapshot.yours));

  const row = (item: typeof open[number]) => {
    const blocked = item.blockedBy
      ? `<span class="row-note blocked">waits on ${
        escapeHTML(item.blockedBy)
      }</span>`
      : "";
    const unlocks = item.unlocks
      ? `<span class="row-note">unlocks ${escapeHTML(item.unlocks)}</span>`
      : "";
    return `<li class="row"><span class="row-title">${
      escapeHTML(item.title)
    }</span><span class="row-meta">${
      escapeHTML(item.section)
    }</span>${blocked}${unlocks}</li>`;
  };

  const waitingBlock = waiting.length === 0
    ? ""
    : `<h3 class="sub">Waiting on something else</h3>
      <ul class="rows waiting">${waiting.map(row).join("")}</ul>`;

  return `<h3 class="sub">You can start these today</h3>
      <ul class="rows">${actionable.map(row).join("")}</ul>
      ${waitingBlock}`;
}

function gatesSection(snapshot: PanelSnapshot): string {
  const order = { failure: 0, warning: 1, pass: 2 } as const;
  const sorted = [...snapshot.gates].sort((a, b) =>
    order[a.status] - order[b.status]
  );

  const rows = sorted.map((gate) =>
    `<li class="gate ${gate.status}"><code>${escapeHTML(gate.id)}</code>` +
    `<span class="gate-msg">${escapeHTML(gate.message)}</span></li>`
  ).join("");

  return `<ul class="gates">${rows}</ul>`;
}

function nextSection(snapshot: PanelSnapshot): string {
  const open = snapshot.next.filter((item) => !item.closed);
  const rows = open.slice(0, 12).map((item) =>
    `<li class="next"><span class="rank">${item.rank}</span>` +
    `<span class="next-body"><span class="next-title">${
      escapeHTML(item.title)
    }</span>` +
    `<span class="next-symptom">${escapeHTML(item.symptom)}</span>` +
    `<span class="next-meta">${
      escapeHTML(item.area)
    } · ${item.priority}</span></span></li>`
  ).join("");

  const remaining = open.length - Math.min(open.length, 12);
  const more = remaining > 0
    ? `<p class="empty">${remaining} more in <code>docs/product-depth-backlog.md</code>, in rank order.</p>`
    : "";

  return `<ul class="rows">${rows}</ul>${more}`;
}

function liveSection(snapshot: PanelSnapshot): string {
  const rows = snapshot.live.map((system) =>
    `<li class="live ${system.state}"><span class="live-name">${
      escapeHTML(system.name)
    }</span><span class="live-detail">${escapeHTML(system.detail)}</span></li>`
  ).join("");
  return `<ul class="lives">${rows}</ul>`;
}

export function renderPanel(
  snapshot: PanelSnapshot,
  history: readonly HistoryRecord[],
  fonts: PanelFonts,
): string {
  const now = summarize(snapshot);
  const series = [...history, now].map((record) => record.yoursActionable);
  const headline = now.yoursActionable;
  const trend = sparkline(series);
  const delta = deltaLabel(series);

  const trendBlock = trend
    ? `${trend}<span class="delta">${escapeHTML(delta)}</span>`
    : `<span class="delta refused">Not enough runs yet to show movement.</span>`;

  const generated = new Date(snapshot.generatedAt);
  const stamp = generated.toISOString().replace("T", " ").slice(0, 16) + " UTC";

  return `<title>Nina Panel</title>
<style>
@font-face{font-family:"Fraunces";src:url(data:font/ttf;base64,${fonts.frauncesBase64}) format("truetype");font-weight:400;font-display:swap}
@font-face{font-family:"InterPanel";src:url(data:font/woff2;base64,${fonts.interRegularBase64}) format("woff2");font-weight:400;font-display:swap}
@font-face{font-family:"InterPanel";src:url(data:font/woff2;base64,${fonts.interSemiBoldBase64}) format("woff2");font-weight:600;font-display:swap}
:root{
--ground:#FBFCFD;--grout:#EDF0F4;--line:#DFE4EB;--ink:#131A24;--muted:#5C6675;
--cobalt:#1B4FD8;--cobalt-deep:#153CA6;--cobalt-wash:#E6EDFC;
--terracotta:#C2410C;--terracotta-wash:#FBEAE1;--moss:#3F6B4A;--moss-wash:#E7EFE9;
--display:"Fraunces",Georgia,serif;--face:"InterPanel",-apple-system,BlinkMacSystemFont,sans-serif;
}
*{box-sizing:border-box}
body{background:var(--ground);color:var(--ink);font-family:var(--face);font-size:15px;line-height:1.5;margin:0;-webkit-font-smoothing:antialiased}
.wrap{max-width:920px;margin:0 auto;padding:40px 20px 96px}
.eyebrow{font-size:11px;letter-spacing:.14em;text-transform:uppercase;font-weight:600;color:var(--muted);margin:0 0 14px;display:flex;gap:12px;flex-wrap:wrap}
.premise{font-family:var(--display);font-size:19px;line-height:1.45;margin:0 0 34px;color:var(--ink);max-width:62ch;text-wrap:balance}
.headline{display:flex;flex-wrap:wrap;align-items:flex-end;gap:10px 28px;padding:22px 24px;border:1px solid var(--line);border-radius:20px;background:#fff;margin:0 0 30px}
.figure{font-family:var(--display);font-size:60px;line-height:.95;letter-spacing:-.02em;color:var(--cobalt)}
.figure-label{font-size:13.5px;color:var(--muted);max-width:24ch;padding-bottom:6px}
.trend{margin-left:auto;display:flex;flex-direction:column;align-items:flex-end;gap:4px;padding-bottom:4px}
.spark{width:240px;height:44px;overflow:visible}
.spark polyline{fill:none;stroke:var(--cobalt);stroke-width:1.5;stroke-linejoin:round;stroke-linecap:round}
.spark circle{fill:var(--cobalt)}
.delta{font-size:12px;color:var(--muted);font-variant-numeric:tabular-nums}
.delta.refused{max-width:26ch;text-align:right}
section{margin:0 0 34px}
h2{font-family:var(--display);font-weight:400;font-size:23px;line-height:1.2;margin:0 0 4px;display:flex;align-items:baseline;gap:12px;flex-wrap:wrap}
.tally{font-family:var(--face);font-size:12px;letter-spacing:.02em;color:var(--muted);font-weight:400}
.tally b{font-variant-numeric:tabular-nums;font-weight:600;color:var(--ink)}
.tally.bad b{color:var(--terracotta)}
.tally.good b{color:var(--moss)}
h2+.hint{font-size:12.5px;color:var(--muted);margin:0 0 14px}
.sub{font-size:11px;letter-spacing:.12em;text-transform:uppercase;font-weight:600;color:var(--muted);margin:18px 0 8px}
.rows{list-style:none;margin:0;padding:0;border-top:1px solid var(--line)}
.row{display:flex;flex-wrap:wrap;align-items:baseline;gap:4px 12px;padding:11px 2px;border-bottom:1px solid var(--line)}
.row-title{font-weight:600;flex:1 1 62%;min-width:0}
.row-meta{font-size:11.5px;color:var(--muted);white-space:nowrap}
.row-note{font-size:11.5px;color:var(--muted);flex-basis:100%}
.row-note.blocked{color:var(--terracotta)}
.waiting .row-title{font-weight:400;color:var(--muted)}
.gates{list-style:none;margin:0;padding:0;display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:1px;background:var(--line);border:1px solid var(--line);border-radius:14px;overflow:hidden}
.gate{background:#fff;padding:9px 13px;display:flex;flex-direction:column;gap:2px;border-left:3px solid var(--moss)}
.gate code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:11.5px;color:var(--ink)}
.gate-msg{font-size:11.5px;color:var(--muted)}
.gate.warning{border-left-color:var(--cobalt);background:var(--cobalt-wash)}
.gate.failure{border-left-color:var(--terracotta);background:var(--terracotta-wash)}
.gate.pass .gate-msg{display:none}
.next{display:flex;gap:14px;padding:12px 2px;border-bottom:1px solid var(--line)}
.rank{font-variant-numeric:tabular-nums;font-size:12px;font-weight:600;color:var(--muted);min-width:22px;padding-top:2px}
.next-body{display:flex;flex-direction:column;gap:3px;min-width:0}
.next-title{font-weight:600}
.next-symptom{font-size:12.5px;color:var(--muted);display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
.next-meta{font-size:11px;letter-spacing:.06em;text-transform:uppercase;color:var(--muted)}
.lives{list-style:none;margin:0;padding:0;border-top:1px solid var(--line)}
.live{display:flex;flex-wrap:wrap;gap:4px 12px;padding:11px 2px;border-bottom:1px solid var(--line)}
.live-name{font-weight:600;min-width:180px}
.live-detail{color:var(--muted);font-size:13px;flex:1 1 50%}
.live.ok .live-name{color:var(--moss)}
.live.degraded .live-name,.live.unreachable .live-name{color:var(--terracotta)}
.live.not-yet .live-name{color:var(--muted)}
.empty{font-size:12.5px;color:var(--muted);margin:12px 0 0}
code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.9em}
@media (max-width:640px){
.wrap{padding:28px 16px 72px}
.figure{font-size:48px}
.trend{margin-left:0;align-items:flex-start;flex-basis:100%}
.delta.refused{text-align:left}
}
@media (prefers-reduced-motion:reduce){*{transition:none!important;animation:none!important}}
</style>
<div class="wrap">
<p class="eyebrow"><span>Nina · panel</span><span>${
    escapeHTML(stamp)
  }</span><span>${snapshot.deep ? "deep run" : "fast run"}</span></p>
<p class="premise">${escapeHTML(snapshot.premise)}</p>

<div class="headline">
  <span class="figure">${headline}</span>
  <span class="figure-label">things only you can clear, ready to start today</span>
  <span class="trend">${trendBlock}</span>
</div>

<section>
  <h2>Yours ${laneCount("open", now.yoursOpen, "bad")} ${
    laneCount("ready", now.yoursActionable, "")
  }</h2>
  <p class="hint">Read from the vault. No amount of engineering produces these.</p>
  ${yoursSection(snapshot)}
</section>

<section>
  <h2>Gates ${laneCount("passing", now.gatesPass, "good")} ${
    laneCount("warning", now.gatesWarning, "")
  } ${laneCount("failing", now.gatesFailure, "bad")}</h2>
  <p class="hint">Repository preflight and the last CI run — CI: ${
    escapeHTML(snapshot.ci)
  }.</p>
  ${gatesSection(snapshot)}
</section>

<section>
  <h2>Next ${laneCount("open", now.nextOpen, "")} ${
    laneCount("closed", now.nextClosed, "good")
  }</h2>
  <p class="hint">The ranked backlog, top twelve.</p>
  ${nextSection(snapshot)}
</section>

<section>
  <h2>Live systems</h2>
  <p class="hint">What is actually running, and what is not running yet.</p>
  ${liveSection(snapshot)}
</section>
</div>`;
}
