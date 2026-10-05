import {
  assert,
  assertEquals,
  assertFalse,
  assertStringIncludes,
} from "@std/assert";
import {
  familyAlias,
  foldText,
  isRosterEntry,
  Pseudonymizer,
  type RosterEntry,
} from "./nina-pseudonyms.ts";

const requesterID = "30000000-0000-4000-9000-000000000001";
const childID = "30000000-0000-4000-9000-000000000002";
const teenID = "30000000-0000-4000-9000-000000000003";
const quietAdultID = "30000000-0000-4000-9000-000000000004";
const petID = "30000000-0000-4000-9000-000000000005";
const unknownID = "30000000-0000-4000-9000-000000000006";

const roster: RosterEntry[] = [
  {
    member_id: requesterID,
    name: "Marina Castello",
    household_role: "adult",
    alias_kind: "none",
    nicknames: [],
    created_at: "2026-09-01T10:00:00Z",
  },
  {
    member_id: childID,
    name: "Ana Clara",
    household_role: "child",
    alias_kind: "child",
    nicknames: ["Aninha", "Cacá"],
    created_at: "2026-09-01T10:01:00Z",
  },
  {
    member_id: teenID,
    name: "Pedro",
    household_role: "teen",
    alias_kind: "teen",
    nicknames: [],
    created_at: "2026-09-01T10:02:00Z",
  },
  {
    member_id: quietAdultID,
    name: "Rafael Souza",
    household_role: "adult",
    alias_kind: "adult",
    nicknames: [],
    created_at: "2026-09-01T10:03:00Z",
  },
  {
    member_id: petID,
    name: "Thor",
    household_role: "pet",
    alias_kind: "none",
    nicknames: [],
    created_at: "2026-09-01T10:04:00Z",
  },
  {
    member_id: unknownID,
    name: "Joana",
    household_role: "adult",
    alias_kind: "person",
    nicknames: [],
    created_at: "2026-09-01T10:05:00Z",
  },
];

function pseudonymizer(entries = roster): Pseudonymizer {
  return new Pseudonymizer(entries, "Casa Castello");
}

Deno.test("no minor name survives in the model request, accent-folded", () => {
  const names = pseudonymizer();
  const request = {
    new_message:
      "A ANA CLARA e a ána precisam do Pedro às 7h; pédro leva a Ana.",
    members: [{ name: "Ana Clara" }, { name: "Pedro" }],
  };

  const sent = JSON.stringify(names.deep(request));
  const folded = foldText(sent);

  assertFalse(/\bana\b/.test(folded));
  assertFalse(/\bpedro\b/.test(folded));
  assertStringIncludes(sent, "Criança 1");
  assertStringIncludes(sent, "Adolescente 1");
  assertStringIncludes(sent, "às 7h");
});

Deno.test("a registered nickname is replaced", () => {
  const names = pseudonymizer();

  assertEquals(
    names.text("A Aninha tem natação e a cacá tem balé."),
    "A Criança 1 tem natação e a Criança 1 tem balé.",
  );
});

Deno.test("a minor sharing a first name with an adult is aliased everywhere and restored on return", () => {
  const shared: RosterEntry[] = [
    {
      member_id: requesterID,
      name: "Pedro Castello",
      household_role: "adult",
      alias_kind: "none",
      nicknames: [],
      created_at: "2026-09-01T10:00:00Z",
    },
    {
      member_id: teenID,
      name: "Pedro Lima",
      household_role: "teen",
      alias_kind: "teen",
      nicknames: [],
      created_at: "2026-09-01T10:01:00Z",
    },
  ];
  const names = new Pseudonymizer(shared, null);

  const sent = names.text("O Pedro leva o Pedro Lima ao treino.");
  assertEquals(sent, "O Adolescente 1 leva o Adolescente 1 ao treino.");
  assertFalse(foldText(sent).includes("pedro"));

  assertEquals(
    names.restoreText("Adolescente 1 tem treino amanhã."),
    "Pedro Lima tem treino amanhã.",
  );
});

Deno.test("a proposal owner alias maps back to the member", () => {
  const names = pseudonymizer();
  const proposal = {
    title: "Levar a Criança 1 na escola",
    payload: {
      owner: "Criança 1",
      title: "Levar a Criança 1 na escola",
      detail: "O Adulto 1 busca às 17h",
    },
  };

  const restored = names.restoreDeep(proposal);

  assertEquals(restored.payload.owner, "Ana Clara");
  assertEquals(restored.payload.title, "Levar a Ana Clara na escola");
  assertEquals(restored.payload.detail, "O Rafael Souza busca às 17h");
  assertEquals(names.memberIDForAlias("Criança 1"), childID);
  assertEquals(names.memberIDForAlias("criança 1"), childID);
  assertEquals(names.memberIDForAlias("Casa"), null);
});

Deno.test("tasks owned by minors never reach the model", () => {
  const names = pseudonymizer();
  const tasks = [
    { title: "Pagar a luz", owner_member_id: requesterID },
    { title: "Mochila", owner_member_id: childID },
    { title: "Treino", owner_member_id: teenID },
    { title: "Consulta", owner_member_id: unknownID },
    { title: "Vacina", owner_member_id: petID },
    { title: "Lixo", owner_member_id: null },
    { title: "Condomínio", owner_member_id: quietAdultID },
  ];

  assertEquals(
    names.withoutMinorWork(tasks).map((task) => task.title),
    ["Pagar a luz", "Vacina", "Lixo", "Condomínio"],
  );
});

Deno.test("the family name never reaches the model", () => {
  const names = pseudonymizer();
  const sent = names.deep({
    family: {
      id: "70000000-0000-4000-9000-000000000001",
      name: "Casa Castello",
    },
    new_message: "Na casa castello a semana foi puxada.",
  });

  assertEquals(sent.family.name, familyAlias);
  assertFalse(foldText(JSON.stringify(sent)).includes("castello"));
});

Deno.test("a pet reaches the model with its species and breed, and a person never carries them", () => {
  const names = pseudonymizer();
  const context = names.memberContext([
    {
      id: "99999999-0000-4000-8000-000000000001",
      name: "Thor",
      relationship: "Cachorro",
      household_role: "pet",
      pet_species: "Cachorro",
      pet_breed: "Vira-lata",
    },
    {
      id: requesterID,
      name: "Marina Castello",
      relationship: "Mãe",
      household_role: "adult",
      memory_note: "Cuida da agenda.",
      pet_species: "",
      pet_breed: "",
    },
  ]);

  assertEquals(context[0].pet_species, "Cachorro");
  assertEquals(context[0].pet_breed, "Vira-lata");
  assertFalse("pet_species" in context[1]);
  assertFalse("pet_breed" in context[1]);
});

Deno.test("an adult without live consent is aliased", () => {
  const names = pseudonymizer();
  const context = names.memberContext([
    {
      id: requesterID,
      name: "Marina Castello",
      relationship: "Mãe",
      household_role: "adult",
      memory_note: "Cuida da agenda.",
    },
    {
      id: quietAdultID,
      name: "Rafael Souza",
      relationship: "Pai",
      household_role: "adult",
      memory_note: "Trabalha à noite.",
    },
    {
      id: childID,
      name: "Ana Clara",
      relationship: "Filha",
      household_role: "child",
      memory_note: "Estuda de manhã.",
    },
  ]);

  assertEquals(context[1], { name: "Adulto 1", household_role: "adult" });
  assertEquals(context[2], { name: "Criança 1", household_role: "child" });
  assertEquals(
    names.text("O Rafael pediu ajuda."),
    "O Adulto 1 pediu ajuda.",
  );
  assertFalse(JSON.stringify(context).includes("Trabalha à noite"));
  assertFalse(JSON.stringify(context).includes("Estuda de manhã"));
  assertEquals(context[0].memory_note, "Cuida da agenda.");
});

Deno.test("an unregistered nickname passes and is a known limitation", () => {
  const names = pseudonymizer();

  assertEquals(
    names.text("O Pepê chegou tarde."),
    "O Pepê chegou tarde.",
  );
});

Deno.test("pets and the requester keep their names, and names inside words stay untouched", () => {
  const names = pseudonymizer();

  assertEquals(
    names.text("Marina leva o Thor; a banana e a Anapolina ficam."),
    "Marina leva o Thor; a banana e a Anapolina ficam.",
  );
  assertEquals(names.text("A Joana chega às 9h."), "A Pessoa 1 chega às 9h.");
});

Deno.test("object keys are aliased so a workload bucket cannot carry a name", () => {
  const names = pseudonymizer();
  const summary = names.deep({
    "Rafael Souza": { open: 2 },
    "Marina Castello": { open: 1 },
  });

  assertEquals(Object.keys(summary).sort(), ["Adulto 1", "Marina Castello"]);
});

Deno.test("the roster validator refuses rows that could smuggle an unaliased minor", () => {
  assert(isRosterEntry(roster[1]));
  assertFalse(isRosterEntry({ ...roster[1], alias_kind: "friend" }));
  assertFalse(isRosterEntry({ ...roster[1], nicknames: [1] }));
  assertFalse(isRosterEntry(null));
});

const mirnaAdultID = "30000000-0000-4000-9000-000000000011";
const mirnaTeenID = "30000000-0000-4000-9000-000000000012";

function sharedFirstNameRoster(adultKind: "none" | "adult"): RosterEntry[] {
  return [
    {
      member_id: requesterID,
      name: "Heitor",
      household_role: "adult",
      alias_kind: "none",
      nicknames: [],
      created_at: "2026-09-01T10:00:00Z",
    },
    {
      member_id: mirnaAdultID,
      name: "Mirna",
      household_role: "adult",
      alias_kind: adultKind,
      nicknames: [],
      created_at: "2026-09-01T10:01:00Z",
    },
    {
      member_id: mirnaTeenID,
      name: "Mirna Clara",
      household_role: "teen",
      alias_kind: "teen",
      nicknames: [],
      created_at: "2026-09-01T10:02:00Z",
    },
  ];
}

Deno.test("an adult sharing a minor's first name keeps her own workload bucket", () => {
  for (const kind of ["none", "adult"] as const) {
    const names = new Pseudonymizer(sharedFirstNameRoster(kind), null);
    const summary = names.deep({
      [names.structuredName(requesterID, "Heitor")]: { open: 1 },
      [names.structuredName(mirnaAdultID, "Mirna")]: { open: 2 },
    });

    assertEquals(Object.keys(summary).sort(), ["Adulto 1", "Heitor"]);
    assertEquals(summary["Adulto 1"], { open: 2 });
    assertFalse(foldText(JSON.stringify(summary)).includes("mirna"));
    assertEquals(
      names.restoreText("Adulto 1 tem 2 tarefas."),
      "Mirna tem 2 tarefas.",
    );
  }
});

Deno.test("a proposal for that adult restores to the adult, not the minor", () => {
  const names = new Pseudonymizer(sharedFirstNameRoster("none"), null);
  const context = names.memberContext([
    {
      id: mirnaAdultID,
      name: "Mirna",
      relationship: "Tia",
      household_role: "adult",
    },
    {
      id: mirnaTeenID,
      name: "Mirna Clara",
      relationship: "Filha",
      household_role: "teen",
    },
  ]);

  assertEquals(context[0], {
    relationship: "Tia",
    memory_note: "",
    name: "Adulto 1",
    household_role: "adult",
  });
  assertEquals(context[1], { name: "Adolescente 1", household_role: "teen" });
  assertEquals(names.memberIDForAlias("Adulto 1"), mirnaAdultID);

  const [restored] = names.restoreProposals([
    { payload: { owner: "Adulto 1", title: "Adulto 1 compra pão" } },
  ]);
  assertEquals(restored.payload, { owner: "Mirna", title: "Mirna compra pão" });
});

Deno.test("a first name shared with an adult never becomes the minor's full name on the way back", () => {
  const names = new Pseudonymizer(sharedFirstNameRoster("adult"), null);

  const sent = names.text("A Mirna está com muito mais tarefas.");
  assertEquals(sent, "A Adolescente 1 está com muito mais tarefas.");

  assertEquals(
    names.restoreText("Adolescente 1 tem muitas tarefas."),
    "Mirna tem muitas tarefas.",
  );
  const [restored] = names.restoreProposals([
    {
      payload: {
        owner: "Adolescente 1",
        title: "Rever as tarefas da Adolescente 1",
      },
    },
  ]);
  assertEquals(restored.payload.owner, "Casa");
  assertEquals(restored.payload.title, "Rever as tarefas da Mirna");
  assertFalse(JSON.stringify(restored).includes("Mirna Clara"));
});

Deno.test("a minor named in full is still restored to the minor", () => {
  const names = new Pseudonymizer(sharedFirstNameRoster("adult"), null);

  assertEquals(
    names.text("Crie uma tarefa para a Mirna Clara estudar."),
    "Crie uma tarefa para a Adolescente 1 estudar.",
  );
  const [restored] = names.restoreProposals([
    { payload: { owner: "Adolescente 1", title: "Adolescente 1 estuda" } },
  ]);
  assertEquals(restored.payload, {
    owner: "Mirna Clara",
    title: "Mirna Clara estuda",
  });
  assertEquals(names.memberIDForAlias("Adolescente 1"), mirnaTeenID);
});

Deno.test("a minor whose profile name differs from the name the house registered is aliased under both", () => {
  const names = new Pseudonymizer([
    {
      member_id: teenID,
      name: "Duda",
      names: ["Duda", "Maria Eduarda"],
      household_role: "teen",
      alias_kind: "teen",
      nicknames: [],
      created_at: "2026-09-01T10:02:00Z",
    },
  ], null);

  assertEquals(
    names.text("A Maria Eduarda e a Duda saem às 7h."),
    "A Adolescente 1 e a Adolescente 1 saem às 7h.",
  );
  assertEquals(names.restoreText("Adolescente 1"), "Duda");
  assert(isRosterEntry({
    member_id: teenID,
    name: "Duda",
    names: ["Duda"],
    household_role: "teen",
    alias_kind: "teen",
    nicknames: [],
  }));
  assertFalse(isRosterEntry({
    member_id: teenID,
    name: "Duda",
    names: [1],
    household_role: "teen",
    alias_kind: "teen",
    nicknames: [],
  }));
});

Deno.test("a weekly metric keyed by a colliding carrier is named by code", () => {
  const names = new Pseudonymizer(sharedFirstNameRoster("none"), null);

  assertEquals(
    names.deep(names.structuredKeys({ Mirna: 2, Heitor: 1, Casa: 3 })),
    { "Adulto 1": 2, Heitor: 1, Casa: 3 },
  );
});
