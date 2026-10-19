import { assert, assertEquals } from "@std/assert";
import { resolveAppStoreListing } from "../src/appStore.ts";
import {
  availabilityLine,
  closingHeadline,
  exampleDescription,
  heroExample,
  houseStop,
  initial,
  landingFaq,
  ninaLines,
  ninaStop,
  proposalCopy,
  tabStops,
  tasksStop,
  todayStop,
  tourCast,
  workloadBands,
  workloadExample,
} from "../src/landing.ts";
import { supportTopics } from "../src/support.ts";

const read = (path: string) =>
  Deno.readTextFile(new URL(path, import.meta.url));

const landingPage = () => read("../src/pages/index.astro");
const landingModule = () => read("../src/landing.ts");

function collectStrings(value: unknown, into: string[] = []): string[] {
  if (typeof value === "string") into.push(value);
  else if (Array.isArray(value)) {
    value.forEach((item) => collectStrings(item, into));
  } else if (value && typeof value === "object") {
    Object.values(value).forEach((item) => collectStrings(item, into));
  }
  return into;
}

// The words a visitor reads in the page's markup, with expressions and tags taken out.
function markupText(page: string): string {
  let markup = page.split("---").slice(2).join("---");
  let previous = "";
  while (previous !== markup) {
    previous = markup;
    markup = markup.replace(/\{[^{}]*\}/g, " ");
  }
  return markup.replace(/<[^>]*>/g, " ").replace(/\s+/g, " ");
}

function frontmatterSentences(page: string): string[] {
  const frontmatter = page.split("---")[1] ?? "";
  return [...frontmatter.matchAll(/"((?:[^"\\]|\\.)*)"/g)]
    .map((match) => match[1])
    .filter((literal) => /\s/.test(literal));
}

Deno.test("the proposal card on the site quotes the app's own words", async () => {
  const components = await read("../../Nina/Components.swift");
  const chat = await read("../../Nina/NinaChatView.swift");

  assert(
    components.includes(`static let pending = "${proposalCopy.pending}"`),
  );
  assert(
    components.includes(
      `static let disclaimer = "${proposalCopy.disclaimer}"`,
    ),
  );
  assert(chat.includes(`default: "${proposalCopy.create}"`));
  assert(chat.includes(`"${proposalCopy.correct}",`));
  assert(chat.includes(`NinaButton(title: "${proposalCopy.decline}"`));
  assert(chat.includes(`"${proposalCopy.resolved}"`));
  assert(chat.includes(`TextField("${proposalCopy.composer}"`));
});

Deno.test("the hero's one real button is named by the words it shows", async () => {
  const page = await landingPage();

  assert(heroExample.confirmLabel.startsWith(proposalCopy.create));
  assert(page.includes("aria-label={heroExample.confirmLabel}"));
});

Deno.test("the site's examples come from the app's tour", async () => {
  const tour = await read("../../Nina/OnboardingTutorialView.swift");
  const mock = await read("../../Nina/MockNinaEngine.swift");
  const workload = await read("../../Nina/WorkloadView.swift");
  const bands = await read("../../Nina/HouseholdWorkload.swift");

  assert(
    tour.includes(
      `static let primaryCast = Cast(owner: "${tourCast.owner}", partner: "${tourCast.partner}", child: "${tourCast.child}", pet: "${tourCast.pet}")`,
    ),
  );
  assert(
    tour.includes(
      `static let proposalTitle = "${heroExample.proposal.title}"`,
    ),
  );
  for (
    const title of [
      tasksStop.seed.title,
      todayStop.rows[0].title,
      todayStop.rows[1].title,
      todayStop.rows[2].title,
      tasksStop.group.rows[0].title,
    ]
  ) {
    assert(tour.includes(`"${title}"`), title);
  }
  assert(tour.includes(`title: "Café", amount: "1 pacote"`));

  for (const line of [todayStop.line, tasksStop.line, houseStop.line]) {
    assert(tour.includes(`return "${line}"`), line);
  }
  assert(tour.includes(heroExample.captionAfter.split(". ")[1]));

  const message = tour.match(/static let message = "([^"]+)"/)?.[1];
  assertEquals(heroExample.message, message?.replace("sexta", "amanhã"));

  assert(mock.includes(`reply: "${ninaStop.reply}"`));
  for (
    const line of [
      workloadExample.headline,
      workloadExample.caption,
      workloadExample.method,
    ]
  ) {
    assert(workload.includes(`"${line}"`), line);
  }
  assertEquals(
    [...bands.matchAll(/case \.(?:light|similar|heavier): "([^"]+)"/g)].map((
      match,
    ) => match[1]),
    [...workloadBands],
  );
});

Deno.test("each example glyph is the app's own category symbol", async () => {
  const models = await read("../../Nina/Models.swift");
  const categories: Record<string, { title: string; symbol: string }> = {
    house: { title: "Casa", symbol: "house" },
    card: { title: "Contas", symbol: "creditcard" },
    backpack: { title: "Escola", symbol: "backpack" },
    paw: { title: "Pet", symbol: "pawprint" },
  };

  for (const { title, symbol } of Object.values(categories)) {
    assert(
      models.includes(`title: "${title}", symbolName: "${symbol}"`),
      title,
    );
  }
  assertEquals(categories[heroExample.proposal.glyph].title, "Escola");
  assertEquals(heroExample.proposal.category, "Escola");
  assertEquals(categories[todayStop.rows[0].glyph].title, "Contas");
  assertEquals(categories[tasksStop.group.rows[0].glyph].title, "Pet");
  assertEquals(categories[ninaStop.proposal.glyph].title, "Casa");
});

Deno.test("Nina speaks of herself in the third person on the site", async () => {
  for (const line of ninaLines()) {
    assertEquals(/\b(eu|minha|comigo|me)\b/i.test(line), false, line);
  }
  for (const source of [await landingPage(), await landingModule()]) {
    assertEquals(source.includes("o que pesa"), false);
    assertEquals(/\bamiga\b/i.test(source), false);
  }
});

Deno.test("no landing string shouts, uses emoji, or calls Nina an AI", async () => {
  const page = await landingPage();
  const texts = [
    ...collectStrings([
      heroExample,
      tabStops,
      workloadExample,
      landingFaq,
      proposalCopy,
      tabStops.map(exampleDescription),
    ]),
    ...frontmatterSentences(page),
    markupText(page),
  ];

  for (const text of texts) {
    assertEquals(text.includes("!"), false, text);
    assertEquals(/\p{Emoji_Presentation}/u.test(text), false, text);
    assertEquals(
      /\bIA\b|assistente|inteligência artificial/i.test(text),
      false,
      text,
    );
  }
});

Deno.test("no example screen carries a calendar date that can go stale", async () => {
  const months =
    "janeiro|fevereiro|março|abril|maio|junho|julho|agosto|setembro|outubro|novembro|dezembro";
  const weekdays = "segunda|terça|quarta|quinta|sexta|sábado|domingo";
  for (const source of [await landingPage(), await landingModule()]) {
    assertEquals(
      new RegExp(`\\b\\d{1,2} de (${months})\\b`, "i").test(source),
      false,
    );
    assertEquals(/\b\d{1,2} [a-zç]{3}\./i.test(source), false);
    assertEquals(
      new RegExp(`(${weekdays})[^.\\n]{0,12}\\d{1,2}`, "i").test(source),
      false,
    );
  }

  const labels = [
    heroExample.proposal.when,
    ...todayStop.rows.map((row) => row.label),
    ...tasksStop.group.rows.map((row) => row.label),
  ];
  for (const label of labels) {
    assert(/^(Hoje|Amanhã), \d{2}:\d{2}$/.test(label), label);
  }
  assertEquals(ninaStop.proposal.when, "Plante depois");
  assertEquals(tasksStop.seed.label, "Plante depois");
});

Deno.test("the hero never prints the confirmed line before anyone confirms", async () => {
  const page = await landingPage();
  const css = await read("../src/styles/global.css");

  assertEquals(page.includes("phone-waiting"), false);
  assert(
    /<p class="proposal-resolved"[^>]*>\s*<Glyph name="check" size=\{12\} \/>\{proposalCopy\.resolved\}/
      .test(page),
  );

  const rules = [
    ...css.replace(/\/\*[\s\S]*?\*\//g, "").matchAll(
      /([^{}]+)\{([^{}]*)\}/g,
    ),
  ]
    .map((match) => ({ selector: match[1].trim(), body: match[2] }))
    .filter((rule) =>
      rule.selector.includes("proposal-resolved") &&
      /\bdisplay\s*:/.test(rule.body)
    );
  assert(rules.length >= 2);
  for (const rule of rules) {
    const shows = !/\bdisplay\s*:\s*none\b/.test(rule.body);
    if (shows) assert(rule.selector.includes(".is-confirmed"), rule.selector);
  }
  assert(
    rules.some((rule) =>
      rule.selector === ".proposal-resolved" &&
      /\bdisplay\s*:\s*none\b/.test(rule.body)
    ),
  );
});

Deno.test("after a confirm the focus moves to the replay and back again", async () => {
  const script = await read("../public/scripts/home.js");
  const confirm = script.slice(
    script.indexOf('confirmButton?.addEventListener("click"'),
    script.indexOf('replayButton?.addEventListener("click"'),
  );
  const replay = script.slice(
    script.indexOf('replayButton?.addEventListener("click"'),
  );

  assert(confirm.includes('ritual.classList.add("is-confirmed")'));
  assert(
    confirm.indexOf("replayButton?.focus()") >
      confirm.indexOf('ritual.classList.add("is-confirmed")'),
  );
  assert(replay.includes("confirmButton?.focus()"));
});

Deno.test("the hero headline keeps a space between its two sentences once compressed", async () => {
  const page = await landingPage();
  const lines = [
    ...page.matchAll(/<span class="hero-line">[^<]*<\/span>(\{" "\})?/g),
  ];

  assertEquals(lines.length, 2);
  lines.slice(0, -1).forEach((line) => assert(line[1], line[0]));
});

Deno.test("the drawn screen's paragraph reset never outranks your bubble or the disclaimer", async () => {
  const css = (await read("../src/styles/global.css")).replace(
    /\/\*[\s\S]*?\*\//g,
    "",
  );
  const body = (selector: string) =>
    [...css.matchAll(/([^{}]+)\{([^{}]*)\}/g)].find((match) =>
      match[1].trim() === selector
    )?.[2] ?? "";

  assertEquals(/\.phone-screen p\s*\{/.test(css), false);
  assert(/\bmargin\s*:\s*0\b/.test(body(":where(.phone-screen) p")));
  assert(/\bmargin-left\s*:\s*auto\b/.test(body(".bubble-you")));
  assert(/\bmargin-left\s*:/.test(body(".proposal-disclaimer")));
});

Deno.test("the drawn card's two honesty lines keep a readable floor", async () => {
  const css = (await read("../src/styles/global.css")).replace(
    /\/\*[\s\S]*?\*\//g,
    "",
  );
  const fontSize = (selector: string) =>
    [...css.matchAll(/([^{}]+)\{([^{}]*)\}/g)]
      .find((match) => match[1].trim() === selector)?.[2]
      .match(/\bfont-size\s*:\s*([^;]+);/)?.[1].trim();

  assertEquals(fontSize(".proposal-tag"), "max(10px, 0.647em)");
  assertEquals(fontSize(".proposal-disclaimer"), "max(11px, 0.765em)");
});

Deno.test("every landing answer borrowed from support exists there word for word", () => {
  const support = new Map(
    supportTopics.flatMap((topic) => topic.questions).map((item) => [
      item.question,
      item.answer,
    ]),
  );
  const borrowed = landingFaq.filter((item) => support.has(item.question));

  assertEquals(borrowed.map((item) => item.question), [
    "Quem pode conversar com a Nina?",
    "Quem lê minha conversa com a Nina?",
    "Como cancelo o Premium?",
  ]);
  for (const item of borrowed) {
    assertEquals(item.answer, support.get(item.question));
  }
});

Deno.test("the landing states the house ceiling the app enforces", async () => {
  const sheets = await read("../../Nina/Sheets.swift");
  const line = "Teto da casa: 100 mensagens por dia.";

  assert((await landingPage()).includes(line));
  assert(sheets.includes(`Text("${line}")`));
});

Deno.test("the landing's prices are the App Store's", async () => {
  const page = await landingPage();
  const storekit = await read("../../Nina/Nina.storekit");
  const terms = await read("../src/pages/termos.astro");

  for (
    const [price, display] of [["R$ 24,90", "24.90"], ["R$ 249,90", "249.90"]]
  ) {
    assert(page.includes(price), price);
    assert(terms.includes(price), price);
    assert(storekit.includes(`"displayPrice" : "${display}"`), display);
  }
  assert(page.includes("até 24 horas antes da renovação"));
  assert(page.includes('href="/termos/"'));
});

Deno.test("the availability line says the app is not in the App Store until the identifier is real", async () => {
  const unpublished = resolveAppStoreListing({});
  const published = resolveAppStoreListing({
    PUBLIC_NINA_APP_STORE_ID: "6470000000",
  });
  const project = await read("../../Nina.xcodeproj/project.pbxproj");

  assertEquals(
    availabilityLine(unpublished),
    "Para iPhone, com iOS 26.4 ou mais novo. Ainda em teste, fora da App Store.",
  );
  assertEquals(
    availabilityLine(published),
    "Para iPhone, com iOS 26.4 ou mais novo.",
  );
  assertEquals(closingHeadline(unpublished).includes("App Store"), false);
  assert(closingHeadline(published).includes("App Store"));
  assert(project.includes("IPHONEOS_DEPLOYMENT_TARGET = 26.4;"));
  assertEquals(
    /IPHONEOS_DEPLOYMENT_TARGET = (?!26\.4;)/.test(project),
    false,
  );
});

Deno.test("every landing link lands on a section that exists, and the waitlist hash still opens", async () => {
  const page = await landingPage();
  const script = await read("../public/scripts/home.js");
  const join = await read("../src/pages/join/index.astro");

  for (
    const id of ["como-funciona", "preco", "privacidade", "duvidas"]
  ) {
    assert(page.includes(`href: "#${id}"`), id);
    assert(page.includes(`id="${id}"`), id);
  }
  assert(script.includes('window.location.hash === "#lista"'));
  assert(join.includes('href="/#lista"'));
});

Deno.test("the landing markets nothing for children, and /familias/ still describes what the app does for them", async () => {
  const page = await landingPage();
  const families = await read("../src/pages/familias.astro");

  assertEquals(page.includes("criancas"), false);
  assertEquals(
    /Crianças e adolescentes|Modo criança|coloridas/.test(page),
    false,
  );
  assert(families.includes("O Modo criança liga sozinho"));
  assert(families.includes("aprovação"));
});

Deno.test("/join/ calls Nina a computer program exactly once and never asks a 'responsável' to approve", async () => {
  const page = await read("../src/pages/join/index.astro");
  const script = await read("../public/scripts/invite.js");
  const both = `${page}\n${script}`;

  assertEquals(both.split("programa de computador").length - 1, 1);
  assertEquals(both.includes("responsável"), false);
  assertEquals(/\bamiga\b/i.test(both), false);
  assert(script.includes('"(prefers-reduced-motion: reduce)"'));
  assert(script.includes('? "auto" : "smooth"'));
});

Deno.test("the landing and the invite page carry no inline script, style block or style attribute", async () => {
  const files = [
    "../src/pages/index.astro",
    "../src/pages/join/index.astro",
    "../src/layouts/BaseLayout.astro",
    "../src/components/SiteFooter.astro",
    "../src/components/StoreAction.astro",
    "../src/components/TourRow.astro",
  ];
  for (const file of files) {
    const source = await read(file);
    for (const tag of source.match(/<script\b[^>]*>/g) ?? []) {
      assert(/\ssrc=/.test(tag), `${file}: ${tag}`);
    }
    assertEquals(source.includes("<style"), false, file);
    assertEquals(source.includes("style="), false, file);
  }
});

Deno.test("every page previews with a 1200×630 picture and alt text", async () => {
  const layout = await read("../src/layouts/BaseLayout.astro");
  const join = await read("../src/pages/join/index.astro");

  for (const name of ["nina.png", "nina-convite.png"]) {
    const bytes = await Deno.readFile(
      new URL(`../public/images/og/${name}`, import.meta.url),
    );
    const view = new DataView(bytes.buffer, bytes.byteOffset);
    assertEquals(
      new TextDecoder().decode(bytes.slice(12, 16)),
      "IHDR",
      name,
    );
    assertEquals(view.getUint32(16), 1200, name);
    assertEquals(view.getUint32(20), 630, name);
    assert(bytes.byteLength <= 300 * 1024, name);
  }
  assert(layout.includes('image = "/images/og/nina.png"'));
  assert(layout.includes('property="og:image:alt"'));
  assert(layout.includes('name="twitter:image:alt"'));
  assert(join.includes('image="/images/og/nina-convite.png"'));
});

Deno.test("an example person is named by one initial, as the app draws a one-word name", () => {
  assertEquals(initial(tourCast.owner), "D");
  assertEquals(initial("  paçoca"), "P");
  assertEquals(initial(""), "");
});
