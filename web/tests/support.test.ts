import { assertEquals } from "@std/assert";
import {
  maxHousePeople,
  supportEmail,
  supportMailto,
  supportTopics,
} from "../src/support.ts";

const swiftSource = () =>
  Deno.readTextFile(new URL("../../Nina/SupportView.swift", import.meta.url));

function swiftTopics(source: string, people: number) {
  const topics = [];
  const topicPattern =
    /SupportTopic\(\s*title: "([^"]+)",\s*questions: \[(.*?)\]\s*\)/gs;
  const questionPattern =
    /SupportQuestion\(\s*question: "([^"]+)",\s*answer: "([^"]+)"\s*\)/gs;
  for (const topic of source.matchAll(topicPattern)) {
    const questions = [...topic[2].matchAll(questionPattern)].map((match) => ({
      question: match[1],
      answer: match[2].replaceAll(
        "\\(AppStore.maxFamilyPeople)",
        String(people),
      ),
    }));
    topics.push({ title: topic[1], questions });
  }
  return topics;
}

Deno.test("the site's support page answers exactly what the app's support screen answers", async () => {
  const parsed = swiftTopics(await swiftSource(), maxHousePeople);

  assertEquals(parsed.length > 0, true);
  assertEquals(parsed, supportTopics);
});

Deno.test("the site states the same people limit the app enforces", async () => {
  const appStore = await Deno.readTextFile(
    new URL("../../Nina/AppStore.swift", import.meta.url),
  );

  assertEquals(
    appStore.includes(`static let maxFamilyPeople = ${maxHousePeople}\n`),
    true,
  );
});

Deno.test("the site and the app write to the same support address", async () => {
  const models = await Deno.readTextFile(
    new URL("../../Nina/Models.swift", import.meta.url),
  );

  assertEquals(
    models.includes(
      `static let support = URL(string: "mailto:${supportEmail}")!`,
    ),
    true,
  );
  assertEquals(
    supportMailto(),
    "mailto:oi@ninai.app?subject=Ajuda%20com%20a%20Nina",
  );
});

Deno.test("no support answer shouts, uses emoji, or calls Nina an AI", () => {
  for (const topic of supportTopics) {
    for (const { question, answer } of topic.questions) {
      for (const text of [question, answer]) {
        assertEquals(text.includes("!"), false, text);
        assertEquals(/\p{Emoji_Presentation}/u.test(text), false, text);
        assertEquals(/\bIA\b|assistente/.test(text), false, text);
      }
    }
  }
});

Deno.test("the support page lists every topic from the shared list and links the mail", async () => {
  const page = await Deno.readTextFile(
    new URL("../src/pages/suporte.astro", import.meta.url),
  );
  const footer = await Deno.readTextFile(
    new URL("../src/components/SiteFooter.astro", import.meta.url),
  );

  assertEquals(page.includes("supportTopics.map("), true);
  assertEquals(page.includes("supportMailto()"), true);
  assertEquals(page.includes("<style"), false);
  assertEquals(page.includes("style="), false);
  assertEquals(footer.includes('href="/suporte/"'), true);
});
