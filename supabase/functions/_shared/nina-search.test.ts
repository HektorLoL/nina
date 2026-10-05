import { assert, assertEquals } from "@std/assert";
import {
  matchesSearch,
  normalizedSearch,
  searchCandidateLimit,
} from "./nina-search.ts";

Deno.test("nina's search folds accents and case like the app's search", () => {
  const medicine = { title: "Remédio do Pedro", subtitle: "" };
  const bill = { title: "Pagar a conta de luz", subtitle: "Vence na SEXTA" };

  assert(matchesSearch(medicine, "remedio", ["title", "subtitle"]));
  assert(matchesSearch(medicine, "REMÉDIO", ["title", "subtitle"]));
  assert(matchesSearch(bill, "sexta", ["title", "subtitle"]));
  assert(!matchesSearch(bill, "remedio", ["title", "subtitle"]));
});

Deno.test("an empty search matches everything and a long one is cut", () => {
  assert(matchesSearch({ title: "Lixo" }, "   ", ["title"]));
  assertEquals(normalizedSearch("  gás  "), "gás");
  assertEquals(normalizedSearch("x".repeat(300)).length, 120);
  assertEquals(normalizedSearch(42), "");
});

Deno.test("search tools read their candidates in order and beyond the old 50", async () => {
  const source = await Deno.readTextFile(
    new URL("../nina-chat/index.ts", import.meta.url),
  );
  const tools = source.slice(
    source.indexOf('case "search_tasks"'),
    source.indexOf('case "get_workload_summary"'),
  );

  assert(!tools.includes(".limit(50)"));
  assertEquals(tools.split(".limit(searchCandidateLimit)").length - 1, 3);
  assert(
    tools.includes('.order("due_at", { ascending: true, nullsFirst: false })'),
  );
  assert(searchCandidateLimit >= 500);
});
