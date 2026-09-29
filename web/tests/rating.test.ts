import { assertEquals } from "@std/assert";
import {
  ninaRating,
  type NinaRatingCode,
  ninaRatingCode,
  ratingFor,
} from "../src/rating.ts";

Deno.test("the livre rating reads as livre everywhere it is spoken", () => {
  assertEquals(ratingFor("L"), {
    code: "L",
    name: "Livre",
    symbolText: "L",
    accessibilityLabel: "Classificação indicativa: livre",
    termsPhrase: "livre",
    colorHex: "#00A859",
  });
});

Deno.test("every age rating derives its name, symbol, label, terms phrase and colour from its code", () => {
  const expectedColors: Record<Exclude<NinaRatingCode, "L">, string> = {
    "10": "#0095DA",
    "12": "#FDC300",
    "14": "#F58220",
    "16": "#E3001B",
    "18": "#1D1D1B",
  };

  for (const [code, colorHex] of Object.entries(expectedColors)) {
    const rating = ratingFor(code as NinaRatingCode);
    assertEquals(rating, {
      code: code as NinaRatingCode,
      name: `Não recomendado para menores de ${code} anos`,
      symbolText: code,
      accessibilityLabel:
        `Classificação indicativa: não recomendado para menores de ${code} anos`,
      termsPhrase: `não recomendada para menores de ${code} anos`,
      colorHex,
    });
  }
});

Deno.test("the published rating is the one the single constant names", () => {
  assertEquals(ninaRating, ratingFor(ninaRatingCode));
});

Deno.test("the rating constant keeps the exact line the preflight compares with the app", async () => {
  const source = await Deno.readTextFile(
    new URL("../src/rating.ts", import.meta.url),
  );

  assertEquals(
    source.split("\n").filter((line) =>
      line.startsWith("export const ninaRatingCode")
    ),
    [`export const ninaRatingCode: NinaRatingCode = "${ninaRatingCode}";`],
  );
});

Deno.test("the terms state the rating through the constant and never set an age floor", async () => {
  const terms = await Deno.readTextFile(
    new URL("../src/pages/termos.astro", import.meta.url),
  );

  assertEquals(terms.includes("ninaRating.termsPhrase"), true);
  assertEquals(terms.includes("18 anos ou mais"), false);
});

Deno.test("the rating mark is labelled with the rating's own accessibility label", async () => {
  const mark = await Deno.readTextFile(
    new URL("../src/components/RatingMark.astro", import.meta.url),
  );

  assertEquals(mark.includes("aria-label={rating.accessibilityLabel}"), true);
  assertEquals(mark.includes("style="), false);
  assertEquals(mark.includes("<style"), false);
});
