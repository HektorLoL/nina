import {
  assert,
  assertEquals,
  assertFalse,
  assertStringIncludes,
} from "@std/assert";
import {
  type HouseholdMemberRow,
  minimizeMembersForModel,
} from "./nina-member-context.ts";

const adult: HouseholdMemberRow = {
  name: "Marina Castello",
  relationship: "mãe",
  household_role: "adult",
  memory_note: "Centraliza escola, saúde e lembretes da casa.",
};

const child: HouseholdMemberRow = {
  name: "Ana Clara Castello",
  relationship: "filha",
  household_role: "child",
  memory_note: "Tem rotina de escola, mochila e atividades da semana.",
};

Deno.test("a child's memory note never reaches the model context", () => {
  const [minimized] = minimizeMembersForModel([child]);

  assertFalse("memory_note" in minimized);
  assertFalse(JSON.stringify(minimized).includes("mochila"));
});

Deno.test("a child keeps the name and relationship a task has to name", () => {
  const [minimized] = minimizeMembersForModel([child]);

  assertEquals(minimized.name, "Ana Clara Castello");
  assertEquals(minimized.relationship, "filha");
  assertEquals(minimized.household_role, "child");
});

Deno.test("an adult's memory note is the consented grant and survives", () => {
  const [minimized] = minimizeMembersForModel([adult]);

  assertEquals(minimized.memory_note, adult.memory_note);
});

Deno.test("pets and the assistant row pass through untouched", () => {
  const rows: HouseholdMemberRow[] = [
    { name: "Fumaça", household_role: "pet", memory_note: "Ração e vacina." },
    { name: "Nina", household_role: "assistant", memory_note: "IA da casa." },
  ];

  assertEquals(minimizeMembersForModel(rows), rows);
});

Deno.test("a row with no household role is left alone rather than guessed at", () => {
  const rows: HouseholdMemberRow[] = [{ name: "?", memory_note: "kept" }];

  assertEquals(minimizeMembersForModel(rows)[0].memory_note, "kept");
});

Deno.test("minimizing copies rather than mutating the rows it was given", () => {
  const rows = [{ ...child }];
  minimizeMembersForModel(rows);

  assertEquals(rows[0].memory_note, child.memory_note);
});

Deno.test("the chat turn minimizes members instead of forwarding the query rows", async () => {
  const source = await Deno.readTextFile(
    new URL("../nina-chat/index.ts", import.meta.url),
  );

  assertStringIncludes(
    source,
    "minimizeMembersForModel(membersResult.data ?? [])",
  );
  assert(!source.includes("members: membersResult.data"));
});
