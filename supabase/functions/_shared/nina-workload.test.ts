import { assert, assertEquals, assertFalse, assertStringIncludes } from "@std/assert";
import {
  houseWorkloadKey,
  summarizeWorkload,
  workloadDisplayNames,
} from "./nina-workload.ts";

const marinaMotherID = "30000000-0000-4000-9000-000000000001";
const marinaCousinID = "30000000-0000-4000-9000-000000000002";
const ninaID = "30000000-0000-4000-9000-000000000003";

const marinaMother = {
  id: marinaMotherID,
  name: "Marina",
  relationship: "Mãe",
  household_role: "adult",
};
const marinaCousin = {
  id: marinaCousinID,
  name: "Marina",
  relationship: "Prima",
  household_role: "adult",
};
const nina = {
  id: ninaID,
  name: "Nina",
  relationship: "IA da casa",
  household_role: "assistant",
};

async function chatSource(): Promise<string> {
  return await Deno.readTextFile(
    new URL("../nina-chat/index.ts", import.meta.url),
  );
}

function workloadTool(source: string): string {
  const start = source.indexOf("case \"get_workload_summary\": {");
  const end = source.indexOf("default:", start);
  assert(start > 0);
  assert(end > start);
  return source.slice(start, end);
}

Deno.test("workload counts are grouped by member id, not by the display label", () => {
  const summary = summarizeWorkload(
    [
      { owner_member_id: marinaMotherID, owner_label: "Marina", is_done: false },
      {
        owner_member_id: marinaMotherID,
        owner_label: "Marina Castello",
        is_done: false,
      },
    ],
    [{ ...marinaMother, name: "Marina Castello" }],
  );

  assertEquals(summary, {
    "Marina Castello": { open: 2, completed: 0, urgent: 0 },
  });
  assertFalse("Marina" in summary);
});

Deno.test("two members sharing a name keep separate buckets", () => {
  const summary = summarizeWorkload(
    [
      { owner_member_id: marinaMotherID, owner_label: "Marina", is_done: false },
      { owner_member_id: marinaMotherID, owner_label: "Marina", is_done: true },
      { owner_member_id: marinaCousinID, owner_label: "Marina", is_done: false },
    ],
    [marinaMother, marinaCousin],
  );

  assertEquals(summary["Marina · Mãe"], { open: 1, completed: 1, urgent: 0 });
  assertEquals(summary["Marina · Prima"], { open: 1, completed: 0, urgent: 0 });
  assertFalse("Marina" in summary);
});

Deno.test("a member with no relationship is separated by a stable ordinal", () => {
  const displayNames = workloadDisplayNames([
    { ...marinaMother, relationship: "" },
    { ...marinaCousin, relationship: "" },
  ]);

  assertEquals(displayNames.get(marinaMotherID), "Marina · 1");
  assertEquals(displayNames.get(marinaCousinID), "Marina · 2");
});

Deno.test("Casa stays its own bucket and is never attributed to a person", () => {
  const summary = summarizeWorkload(
    [
      { owner_member_id: null, owner_label: "Casa", is_done: false },
      { owner_member_id: null, owner_label: "   ", is_done: false },
      { owner_member_id: null, is_done: false },
      { owner_member_id: marinaMotherID, owner_label: "Marina", is_done: false },
    ],
    [marinaMother],
  );

  assertEquals(summary[houseWorkloadKey], { open: 3, completed: 0, urgent: 0 });
  assertEquals(summary["Marina"], { open: 1, completed: 0, urgent: 0 });
});

Deno.test("a member named Casa is qualified away from the house bucket", () => {
  const casaID = "30000000-0000-4000-9000-000000000004";
  const summary = summarizeWorkload(
    [
      { owner_member_id: null, owner_label: "Casa", is_done: false },
      { owner_member_id: casaID, owner_label: "casa", is_done: false },
    ],
    [{
      id: casaID,
      name: "casa",
      relationship: "Filha",
      household_role: "child",
    }],
  );

  assertEquals(summary[houseWorkloadKey], { open: 1, completed: 0, urgent: 0 });
  assertEquals(summary["casa · Filha"], { open: 1, completed: 0, urgent: 0 });
});

Deno.test("work whose owner no longer resolves keeps its label instead of naming a person", () => {
  const summary = summarizeWorkload(
    [
      { owner_member_id: null, owner_label: "Marina", is_done: false },
      { owner_member_id: marinaMotherID, owner_label: "Marina", is_done: false },
      { owner_member_id: marinaCousinID, owner_label: "Marina", is_done: false },
    ],
    [marinaMother, marinaCousin],
  );

  assertEquals(summary["Marina"], { open: 1, completed: 0, urgent: 0 });
  assertEquals(summary["Marina · Mãe"], { open: 1, completed: 0, urgent: 0 });
  assertEquals(summary["Marina · Prima"], { open: 1, completed: 0, urgent: 0 });
  assertEquals(summary[houseWorkloadKey], undefined);
});

Deno.test("urgent counts only open work and completed work never counts as open", () => {
  const summary = summarizeWorkload(
    [
      {
        owner_member_id: marinaMotherID,
        owner_label: "Marina",
        is_done: false,
        priority: "urgent",
      },
      {
        owner_member_id: marinaMotherID,
        owner_label: "Marina",
        is_done: true,
        priority: "urgent",
      },
      {
        owner_member_id: marinaMotherID,
        owner_label: "Marina",
        is_done: false,
        priority: "normal",
      },
    ],
    [marinaMother],
  );

  assertEquals(summary["Marina"], { open: 2, completed: 1, urgent: 1 });
});

Deno.test("the assistant never receives a workload bucket", () => {
  const displayNames = workloadDisplayNames([marinaMother, nina]);

  assertEquals(displayNames.get(ninaID), undefined);
  assertEquals(displayNames.get(marinaMotherID), "Marina");
});

Deno.test("the chat tool reads the owner pointer and resolves names from the household", async () => {
  const tool = workloadTool(await chatSource());

  assertStringIncludes(
    tool,
    "select(\"owner_member_id,owner_label,is_done,priority\")",
  );
  assertStringIncludes(
    tool,
    "select(\"id,name,relationship,household_role\")",
  );
  assertStringIncludes(tool, "summarizeWorkload(");
  assertFalse(tool.includes("task.owner_label || \"Casa\""));
});

Deno.test("the chat tool scopes every workload read to the caller's own family", async () => {
  const tool = workloadTool(await chatSource());
  const scopes = [...tool.matchAll(/\.from\("(\w+)"\)/g)].map((match) =>
    match[1]
  );

  assertEquals(scopes, ["tasks", "family_members"]);
  assertEquals(
    [...tool.matchAll(/\.eq\("family_id", familyID\)/g)].length,
    scopes.length,
  );
});

Deno.test("the chat tool names the house bucket in its result and its description", async () => {
  const source = await chatSource();

  assertStringIncludes(workloadTool(source), "house_owner_label: houseWorkloadKey");
  assertStringIncludes(source, "The key Casa is work the house carries and is never a person.");
});

Deno.test("the weekly insight consumer still reads owner buckets as a string-keyed count map", async () => {
  const source = await Deno.readTextFile(
    new URL("../nina-maintenance/index.ts", import.meta.url),
  );

  assertStringIncludes(source, "open_tasks_by_owner: Record<string, number>;");
  assertFalse(source.includes("owner_label"));
});
