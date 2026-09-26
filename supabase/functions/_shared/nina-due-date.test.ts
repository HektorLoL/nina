import {
  assert,
  assertEquals,
  assertNotStrictEquals,
  assertStringIncludes,
} from "@std/assert";
import type { NinaProposalOutput } from "./nina-ai.ts";
import {
  fillMissingDueAt,
  ninaDefaultDueHour,
  ninaDueAt,
  ninaLocalNow,
  resolveDueInstant,
} from "./nina-due-date.ts";

const saturdayMorning = "2026-09-26T10:15:00-03:00";

const sharedDueTable: Array<[string, string, string | null]> = [
  ["Dia 20", "2026-09-26T10:15:00-03:00", "2026-10-20T09:00:00-03:00"],
  ["dia 26", "2026-09-26T10:15:00-03:00", "2026-10-26T09:00:00-03:00"],
  ["dia 26 às 18h", "2026-09-26T10:15:00-03:00", "2026-09-26T18:00:00-03:00"],
  ["dia 26", "2026-09-26T08:30:00-03:00", "2026-09-26T09:00:00-03:00"],
  ["dia 26 às 8h", "2026-09-26T10:15:00-03:00", "2026-10-26T08:00:00-03:00"],
  ["dia 31", "2026-09-26T10:15:00-03:00", "2026-10-31T09:00:00-03:00"],
  ["dia 31", "2026-10-31T10:00:00-03:00", "2026-12-31T09:00:00-03:00"],
  ["dia 31", "2026-12-31T10:00:00-03:00", "2027-01-31T09:00:00-03:00"],
  ["dia 30", "2027-01-31T10:00:00-03:00", "2027-03-30T09:00:00-03:00"],
  ["dia 5", "2026-12-20T10:00:00-03:00", "2027-01-05T09:00:00-03:00"],
  ["dia 20", "2026-09-20T23:59:00-03:00", "2026-10-20T09:00:00-03:00"],
  [
    "dia 20 do mês que vem",
    "2026-09-26T10:15:00-03:00",
    "2026-10-20T09:00:00-03:00",
  ],
  ["sexta às 14h", "2026-09-26T10:15:00-03:00", "2026-10-02T14:00:00-03:00"],
  ["Sexta, 14h", "2026-09-26T10:15:00-03:00", "2026-10-02T14:00:00-03:00"],
  ["sexta 14h30", "2026-09-26T10:15:00-03:00", "2026-10-02T14:30:00-03:00"],
  ["sexta-feira", "2026-09-26T10:15:00-03:00", "2026-10-02T09:00:00-03:00"],
  [
    "me lembre sexta as 18",
    "2026-09-26T10:15:00-03:00",
    "2026-10-02T18:00:00-03:00",
  ],
  [
    "Sexta, 02/10, 14h",
    "2026-09-26T10:15:00-03:00",
    "2026-10-02T14:00:00-03:00",
  ],
  ["sábado", "2026-09-26T10:15:00-03:00", "2026-10-03T09:00:00-03:00"],
  ["sábado às 18h", "2026-09-26T10:15:00-03:00", "2026-09-26T18:00:00-03:00"],
  ["sabado 8h", "2026-09-26T10:15:00-03:00", "2026-10-03T08:00:00-03:00"],
  [
    "sábado que vem às 18h",
    "2026-09-26T10:15:00-03:00",
    "2026-10-03T18:00:00-03:00",
  ],
  ["domingo", "2026-09-26T10:15:00-03:00", "2026-09-27T09:00:00-03:00"],
  ["na segunda", "2026-09-26T10:15:00-03:00", "2026-09-28T09:00:00-03:00"],
  ["deixa pra sexta", "2026-09-26T10:15:00-03:00", "2026-10-02T09:00:00-03:00"],
  [
    "a reunião de sexta",
    "2026-09-26T10:15:00-03:00",
    "2026-10-02T09:00:00-03:00",
  ],
  [
    "às 8 de segunda-feira",
    "2026-09-26T10:15:00-03:00",
    "2026-09-28T08:00:00-03:00",
  ],
  ["sexta", "2026-10-02T08:00:00-03:00", "2026-10-02T09:00:00-03:00"],
  ["próxima sexta", "2026-10-02T08:00:00-03:00", "2026-10-09T09:00:00-03:00"],
  [
    "quinta-feira que vem",
    "2026-10-01T08:00:00-03:00",
    "2026-10-08T09:00:00-03:00",
  ],
  ["amanhã", "2026-09-26T10:15:00-03:00", "2026-09-27T09:00:00-03:00"],
  ["amanhã 9h", "2026-09-26T10:15:00-03:00", "2026-09-27T09:00:00-03:00"],
  ["Amanhã, 07:30", "2026-09-26T10:15:00-03:00", "2026-09-27T07:30:00-03:00"],
  ["amanhã de manhã", "2026-09-26T10:15:00-03:00", "2026-09-27T09:00:00-03:00"],
  [
    "amanhã às 10 de manhã",
    "2026-09-26T10:15:00-03:00",
    "2026-09-27T10:00:00-03:00",
  ],
  ["às 10 amanhã", "2026-09-26T10:15:00-03:00", "2026-09-27T10:00:00-03:00"],
  [
    "amanhã às 8 da noite",
    "2026-09-26T10:15:00-03:00",
    "2026-09-27T20:00:00-03:00",
  ],
  ["amanhã", "2026-12-31T23:30:00-03:00", "2027-01-01T09:00:00-03:00"],
  [
    "depois de amanhã",
    "2026-09-26T10:15:00-03:00",
    "2026-09-28T09:00:00-03:00",
  ],
  ["hoje às 14h", "2026-09-26T10:15:00-03:00", "2026-09-26T14:00:00-03:00"],
  ["Hoje, 14:30", "2026-09-26T10:15:00-03:00", "2026-09-26T14:30:00-03:00"],
  ["hoje", "2026-09-26T08:00:00-03:00", "2026-09-26T09:00:00-03:00"],
  ["20/10", "2026-09-26T10:15:00-03:00", "2026-10-20T09:00:00-03:00"],
  ["20/10/2026", "2026-09-26T10:15:00-03:00", "2026-10-20T09:00:00-03:00"],
  ["20/10 às 14:30", "2026-09-26T10:15:00-03:00", "2026-10-20T14:30:00-03:00"],
  ["12/08, 09:00", "2026-09-26T10:15:00-03:00", "2027-08-12T09:00:00-03:00"],
  ["dia 1/2", "2026-09-26T10:15:00-03:00", "2027-02-01T09:00:00-03:00"],
  ["20 de outubro", "2026-09-26T10:15:00-03:00", "2026-10-20T09:00:00-03:00"],
  ["20 out., 09:00", "2026-09-26T10:15:00-03:00", "2026-10-20T09:00:00-03:00"],
  ["1º de novembro", "2026-09-26T10:15:00-03:00", "2026-11-01T09:00:00-03:00"],
  ["29 de fevereiro", "2026-09-26T10:15:00-03:00", "2028-02-29T09:00:00-03:00"],
  ["14h", "2026-09-26T10:15:00-03:00", "2026-09-26T14:00:00-03:00"],
  ["14hs", "2026-09-26T10:15:00-03:00", "2026-09-26T14:00:00-03:00"],
  ["14h30min", "2026-09-26T10:15:00-03:00", "2026-09-26T14:30:00-03:00"],
  ["9h", "2026-09-26T10:15:00-03:00", "2026-09-27T09:00:00-03:00"],
  ["14:30", "2026-09-26T10:15:00-03:00", "2026-09-26T14:30:00-03:00"],
  ["14h30", "2026-09-26T10:15:00-03:00", "2026-09-26T14:30:00-03:00"],
  ["meio-dia", "2026-09-26T10:15:00-03:00", "2026-09-26T12:00:00-03:00"],
  ["às 9", "2026-09-26T10:15:00-03:00", "2026-09-27T09:00:00-03:00"],
  [
    "as 9 no pediatra",
    "2026-09-26T10:15:00-03:00",
    "2026-09-27T09:00:00-03:00",
  ],
  ["às 14 horas", "2026-09-26T10:15:00-03:00", "2026-09-26T14:00:00-03:00"],
  ["2 da tarde", "2026-09-26T10:15:00-03:00", "2026-09-26T14:00:00-03:00"],
  ["dia 20 as 18", "2026-09-26T10:15:00-03:00", "2026-10-20T18:00:00-03:00"],
  ["daqui 3 dias", "2026-09-26T10:15:00-03:00", "2026-09-29T09:00:00-03:00"],
  ["daqui a 3 dias", "2026-09-26T10:15:00-03:00", "2026-09-29T09:00:00-03:00"],
  ["Daqui 8 dias", "2026-09-26T10:15:00-03:00", "2026-10-04T09:00:00-03:00"],
  [
    "Me lembre de pagar o boleto dia 20",
    "2026-09-26T10:15:00-03:00",
    "2026-10-20T09:00:00-03:00",
  ],
  [
    "Me lembre da consulta na sexta às 14h.",
    "2026-09-26T10:15:00-03:00",
    "2026-10-02T14:00:00-03:00",
  ],
  [
    "O comunicado da escola diz reunião dia 25 às 18h.",
    "2026-09-26T10:15:00-03:00",
    "2026-10-25T18:00:00-03:00",
  ],
  [
    "Crie uma tarefa para o Heitor separar os documentos amanhã às 9h.",
    "2026-09-26T10:15:00-03:00",
    "2026-09-27T09:00:00-03:00",
  ],
  ["dia 10 de manhã", "2026-09-26T10:15:00-03:00", "2026-10-10T09:00:00-03:00"],
  ["20/10 de manhã", "2026-09-26T10:15:00-03:00", "2026-10-20T09:00:00-03:00"],
  [
    "dia 10 às 8 da noite",
    "2026-09-26T10:15:00-03:00",
    "2026-10-10T20:00:00-03:00",
  ],
  ["8h30 da noite", "2026-09-26T10:15:00-03:00", "2026-09-26T20:30:00-03:00"],
  [
    "sexta 1h30 da tarde",
    "2026-09-26T10:15:00-03:00",
    "2026-10-02T13:30:00-03:00",
  ],
  ["às 5 da tarde", "2026-09-26T10:15:00-03:00", "2026-09-26T17:00:00-03:00"],
  ["meio-dia e meia", "2026-09-26T10:15:00-03:00", "2026-09-26T12:30:00-03:00"],
  ["6ª feira às 14h", "2026-09-26T10:15:00-03:00", "2026-10-02T14:00:00-03:00"],
  ["5ª, 19h", "2026-09-26T10:15:00-03:00", "2026-10-01T19:00:00-03:00"],
  [
    "reunião na escola 5ª às 19h",
    "2026-09-26T10:15:00-03:00",
    "2026-10-01T19:00:00-03:00",
  ],
  ["2ª-feira, 10h", "2026-09-26T10:15:00-03:00", "2026-09-28T10:00:00-03:00"],
  [
    "5ª feira que vem",
    "2026-10-01T08:00:00-03:00",
    "2026-10-08T09:00:00-03:00",
  ],
  [
    "2ª via do boleto, pagar amanhã",
    "2026-09-26T10:15:00-03:00",
    "2026-09-27T09:00:00-03:00",
  ],
  [
    "comprar 1 ou 2 pacotes amanhã",
    "2026-09-26T10:15:00-03:00",
    "2026-09-27T09:00:00-03:00",
  ],
  [
    "entre em contato com a escola amanhã",
    "2026-09-26T10:15:00-03:00",
    "2026-09-27T09:00:00-03:00",
  ],
  ["dia 31 do mês que vem", "2026-10-10T10:15:00-03:00", null],
  ["dia 32", "2026-09-26T10:15:00-03:00", null],
  ["dia 0", "2026-09-26T10:15:00-03:00", null],
  ["hoje às 8h", "2026-09-26T10:15:00-03:00", null],
  ["10/09/2026", "2026-09-26T10:15:00-03:00", null],
  ["31/02", "2026-09-26T10:15:00-03:00", null],
  ["tomar 1/2 comprimido", "2026-09-26T10:15:00-03:00", null],
  ["Reduza a dose para 1/2 comprimido", "2026-09-26T10:15:00-03:00", null],
  ["25h", "2026-09-26T10:15:00-03:00", null],
  ["hoje à noite", "2026-09-26T10:15:00-03:00", null],
  ["sexta à tarde", "2026-09-26T10:15:00-03:00", null],
  ["Sem data", "2026-09-26T10:15:00-03:00", null],
  ["Esta semana", "2026-09-26T10:15:00-03:00", null],
  ["Semana que vem", "2026-09-26T10:15:00-03:00", null],
  ["Semana que vem, 14h", "2026-09-26T10:15:00-03:00", null],
  ["mais para frente", "2026-09-26T10:15:00-03:00", null],
  ["quando der", "2026-09-26T10:15:00-03:00", null],
  ["sexta ou sábado", "2026-09-26T10:15:00-03:00", null],
  ["hoje e amanhã", "2026-09-26T10:15:00-03:00", null],
  ["14h ou 15h", "2026-09-26T10:15:00-03:00", null],
  ["de segunda a sexta às 7h", "2026-09-26T10:15:00-03:00", null],
  ["pegar a segunda via do boleto", "2026-09-26T10:15:00-03:00", null],
  [
    "Segunda via do boleto chegou, me lembre de pagar",
    "2026-09-26T10:15:00-03:00",
    null,
  ],
  ["reunião da sexta série", "2026-09-26T10:15:00-03:00", null],
  ["às 14h reunião sexta", "2026-09-26T10:15:00-03:00", null],
  ["pagar as 3 contas", "2026-09-26T10:15:00-03:00", null],
  ["levar as 2 crianças amanhã", "2026-09-26T10:15:00-03:00", null],
  ["Me lembra amanhã às 10 de pegar o bolo", "2026-09-26T10:15:00-03:00", null],
  ["Tomar o remédio a cada 8 horas", "2026-09-26T10:15:00-03:00", null],
  ["Tomar amoxicilina de 8/8h", "2026-09-26T10:15:00-03:00", null],
  ["de 8 em 8 horas", "2026-09-26T10:15:00-03:00", null],
  [
    "jejum de 8 horas antes do exame amanhã",
    "2026-09-26T10:15:00-03:00",
    null,
  ],
  ["Reunião de 2 horas amanhã", "2026-09-26T10:15:00-03:00", null],
  ["me lembre daqui 2 horas", "2026-09-26T10:15:00-03:00", null],
  ["ontem às 10h", "2026-09-26T10:15:00-03:00", null],
  ["Sex, 14h", "2026-09-26T10:15:00-03:00", null],
  [
    "Precisamos limpar a geladeira neste fim de semana.",
    "2026-09-26T10:15:00-03:00",
    null,
  ],
  [
    "A receita diz uma dose de manhã. Pode organizar um lembrete?",
    "2026-09-26T10:15:00-03:00",
    null,
  ],
  ["dia 20 de noite", "2026-09-26T10:15:00-03:00", null],
  ["dia 5 da tarde", "2026-09-26T10:15:00-03:00", null],
  ["2ª via do boleto", "2026-09-26T10:15:00-03:00", null],
  ["3ª dose da vacina", "2026-09-26T10:15:00-03:00", null],
  ["a 4ª reunião do condomínio", "2026-09-26T10:15:00-03:00", null],
  ["Buscar as crianças às 5", "2026-09-26T10:15:00-03:00", null],
  ["dia 5 ou 6", "2026-09-26T10:15:00-03:00", null],
  ["dia 20 e 21", "2026-09-26T10:15:00-03:00", null],
  ["entre 14 e 16h", "2026-09-26T10:15:00-03:00", null],
  ["das 10 às 12h", "2026-09-26T10:15:00-03:00", null],
  ["14h 30", "2026-09-26T10:15:00-03:00", null],
];

function resolved(text: string, now: string): string | null {
  const instant = resolveDueInstant(text, new Date(now));
  return instant ? ninaDueAt(instant) : null;
}

function proposal(
  kind: NinaProposalOutput["kind"],
  dueLabel: string,
  dueAt: string | null,
): NinaProposalOutput {
  return {
    id: "40000000-0000-4000-8000-000000000001",
    kind,
    title: "Anotei o boleto",
    detail: "Chegou pela mensagem",
    action_title: "Confirmar",
    payload: {
      title: "Pagar o boleto",
      detail: "Conta de luz",
      owner: "Casa",
      due_label: dueLabel,
      due_at: dueAt,
      category: "bills",
      symbol_name: "doc.text",
      amount: "",
      extracted: [{ label: "Vencimento", value: "20/10/2026" }],
      rationale: "Pedido na mensagem",
      source: "mensagem",
      visibility: null,
      confidence: 0.8,
      deduplication_key: "boleto-luz",
    },
  };
}

Deno.test("every row of the shared due table resolves to its São Paulo instant", () => {
  for (const [text, now, expected] of sharedDueTable) {
    assertEquals(resolved(text, now), expected, `${text} at ${now}`);
  }
});

Deno.test("the phone's label reader is tested against exactly the same table", async () => {
  const swift = await Deno.readTextFile(
    new URL("../../../NinaTests/TaskAgendaTests.swift", import.meta.url),
  );
  const phoneRows = [
    ...swift.matchAll(/\("([^"]*)", "([^"]+)", (nil|"[^"]+")\)/g),
  ].map((match) =>
    JSON.stringify([
      match[1],
      match[2],
      match[3] === "nil" ? null : match[3].slice(1, -1),
    ])
  );
  const serverRows = sharedDueTable.map((row) => JSON.stringify(row));

  assertEquals(phoneRows.length, serverRows.length);
  assertEquals([...new Set(phoneRows)].sort(), [...new Set(serverRows)].sort());
});

Deno.test("the phone books a day without a time at the server's default hour", async () => {
  const appStore = await Deno.readTextFile(
    new URL("../../../Nina/AppStore.swift", import.meta.url),
  );

  assertStringIncludes(
    appStore,
    `static let defaultDueHour = ${ninaDefaultDueHour}`,
  );
});

Deno.test("said on the 20th, dia 20 is today only while its hour is still ahead", () => {
  assertEquals(
    resolved("dia 20", "2026-09-20T08:00:00-03:00"),
    "2026-09-20T09:00:00-03:00",
  );
  assertEquals(
    resolved("dia 20", "2026-09-20T10:00:00-03:00"),
    "2026-10-20T09:00:00-03:00",
  );
  assertEquals(
    resolved("dia 20 às 18h", "2026-09-20T10:00:00-03:00"),
    "2026-09-20T18:00:00-03:00",
  );
  assertEquals(
    resolved("dia 20 às 18h", "2026-09-20T19:00:00-03:00"),
    "2026-10-20T18:00:00-03:00",
  );
});

Deno.test("dia 31 skips every month without a 31st, across the turn of the year", () => {
  assertEquals(
    resolved("dia 31", "2026-10-31T10:00:00-03:00"),
    "2026-12-31T09:00:00-03:00",
  );
  assertEquals(
    resolved("dia 31", "2026-12-31T10:00:00-03:00"),
    "2027-01-31T09:00:00-03:00",
  );
  assertEquals(
    resolved("dia 31", "2027-01-31T10:00:00-03:00"),
    "2027-03-31T09:00:00-03:00",
  );
  assertEquals(
    resolved("dia 31 do mês que vem", "2026-10-10T10:15:00-03:00"),
    null,
  );
});

Deno.test("a weekday is today only while its hour is still ahead, and que vem never is", () => {
  assertEquals(
    resolved("sábado às 18h", saturdayMorning),
    "2026-09-26T18:00:00-03:00",
  );
  assertEquals(
    resolved("sábado às 8h", saturdayMorning),
    "2026-10-03T08:00:00-03:00",
  );
  assertEquals(
    resolved("sábado que vem às 18h", saturdayMorning),
    "2026-10-03T18:00:00-03:00",
  );
  assertEquals(
    resolved("sexta", "2026-10-02T08:00:00-03:00"),
    "2026-10-02T09:00:00-03:00",
  );
  assertEquals(
    resolved("sexta", "2026-10-02T10:00:00-03:00"),
    "2026-10-09T09:00:00-03:00",
  );
  assertEquals(
    resolved("próxima sexta", "2026-10-02T08:00:00-03:00"),
    "2026-10-09T09:00:00-03:00",
  );
});

Deno.test("the server leaves today without a time to the confirmation once nine has passed", () => {
  assertEquals(resolved("hoje", saturdayMorning), null);
  assertEquals(resolved("26/09", saturdayMorning), null);
  assertEquals(
    resolved("hoje", "2026-09-26T08:00:00-03:00"),
    "2026-09-26T09:00:00-03:00",
  );
});

Deno.test("an ordinal, a fraction or an article is never read as a date", () => {
  for (
    const text of [
      "pegar a segunda via do boleto",
      "Segunda via do boleto chegou, me lembre de pagar",
      "reunião da sexta série",
      "tomar 1/2 comprimido",
      "Reduza a dose para 1/2 comprimido",
      "pagar as 3 contas",
      "levar as 2 crianças amanhã",
    ]
  ) {
    assertEquals(resolved(text, saturdayMorning), null, text);
  }
  assertEquals(
    resolved("dia 1/2", saturdayMorning),
    "2027-02-01T09:00:00-03:00",
  );
  assertEquals(
    resolved("na segunda", saturdayMorning),
    "2026-09-28T09:00:00-03:00",
  );
});

Deno.test("two dates, two times or a part of the day without a clock time resolve to nothing", () => {
  for (
    const text of [
      "sexta ou sábado",
      "hoje e amanhã",
      "14h ou 15h",
      "de segunda a sexta às 7h",
      "hoje à noite",
      "sexta à tarde",
      "amanhã de madrugada",
    ]
  ) {
    assertEquals(resolved(text, saturdayMorning), null, text);
  }
});

Deno.test("a duration, an interval or a dose schedule is never read as a clock time", () => {
  for (
    const text of [
      "A cada 8 horas",
      "Tomar o remédio a cada 8 horas",
      "Tomar amoxicilina de 8/8h",
      "de 8 em 8 horas",
      "jejum de 8 horas antes do exame amanhã",
      "me lembre daqui 2 horas",
      "Reunião de 2 horas amanhã",
    ]
  ) {
    assertEquals(resolved(text, saturdayMorning), null, text);
  }
});

Deno.test("a date or time word the reader cannot place refuses instead of falling back to today", () => {
  for (
    const text of [
      "Me lembra amanhã às 10 de pegar o bolo",
      "às 14h reunião sexta",
      "Semana que vem, 14h",
      "ontem às 10h",
      "Sex, 14h",
    ]
  ) {
    assertEquals(resolved(text, saturdayMorning), null, text);
  }
});

Deno.test("a part of the day after a named date keeps the date and never becomes its hour", () => {
  assertEquals(
    resolved("dia 10 de manhã", saturdayMorning),
    "2026-10-10T09:00:00-03:00",
  );
  assertEquals(
    resolved("20/10 de manhã", saturdayMorning),
    "2026-10-20T09:00:00-03:00",
  );
  assertEquals(
    resolved("8h30 da noite", saturdayMorning),
    "2026-09-26T20:30:00-03:00",
  );
  assertEquals(resolved("dia 20 de noite", saturdayMorning), null);
  assertEquals(resolved("dia 5 da tarde", saturdayMorning), null);
});

Deno.test("an ordinal weekday reads as that weekday, and an ordinal noun never does", () => {
  assertEquals(
    resolved("6ª feira às 14h", saturdayMorning),
    "2026-10-02T14:00:00-03:00",
  );
  assertEquals(
    resolved("5ª, 19h", saturdayMorning),
    "2026-10-01T19:00:00-03:00",
  );
  assertEquals(
    resolved("2ª-feira, 10h", saturdayMorning),
    "2026-09-28T10:00:00-03:00",
  );
  for (
    const text of [
      "2ª via do boleto",
      "3ª dose da vacina",
      "a 4ª reunião do condomínio",
    ]
  ) {
    assertEquals(resolved(text, saturdayMorning), null, text);
  }
});

Deno.test("a range, an alternative or a bare hour from one to seven resolves to nothing", () => {
  for (
    const text of [
      "dia 5 ou 6",
      "dia 20 e 21",
      "entre 14 e 16h",
      "das 10 às 12h",
      "14h 30",
      "Buscar as crianças às 5",
    ]
  ) {
    assertEquals(resolved(text, saturdayMorning), null, text);
  }
  assertEquals(
    resolved("às 5 da tarde", saturdayMorning),
    "2026-09-26T17:00:00-03:00",
  );
  assertEquals(
    resolved("meio-dia e meia", saturdayMorning),
    "2026-09-26T12:30:00-03:00",
  );
  assertEquals(
    resolved("comprar 1 ou 2 pacotes amanhã", saturdayMorning),
    "2026-09-27T09:00:00-03:00",
  );
});

Deno.test("two spellings of the same day read as that one day", () => {
  assertEquals(
    resolved("Sexta, 02/10, 14h", saturdayMorning),
    "2026-10-02T14:00:00-03:00",
  );
  assertEquals(resolved("Sexta, 03/10, 14h", saturdayMorning), null);
});

Deno.test("local_now carries São Paulo's date, weekday, time and offset", () => {
  assertEquals(ninaLocalNow(new Date("2026-09-26T13:15:00Z")), {
    date: "2026-09-26",
    weekday: "sábado",
    time: "10:15",
    utc_offset: "-03:00",
    time_zone: "America/Sao_Paulo",
  });
});

Deno.test("local_now turns the day over at midnight in São Paulo, not in UTC", () => {
  const lateSaturday = ninaLocalNow(new Date("2026-09-27T02:30:00Z"));

  assertEquals(lateSaturday.date, "2026-09-26");
  assertEquals(lateSaturday.weekday, "sábado");
  assertEquals(lateSaturday.time, "23:30");
});

Deno.test("the production boleto reminder is booked for the twentieth of next month", () => {
  const filled = fillMissingDueAt(
    [proposal("reminder", "Dia 20", null)],
    "Me lembre de pagar o boleto dia 20",
    new Date(saturdayMorning),
  );

  assertEquals(filled.filled, 1);
  assertEquals(filled.proposals[0].payload.due_at, "2026-10-20T09:00:00-03:00");
  assertEquals(filled.proposals[0].payload.due_label, "Dia 20");
});

Deno.test("a date Nina gave keeps its instant and only gains the spelling the phone reads", () => {
  const filled = fillMissingDueAt(
    [
      proposal("reminder", "Dia 20", "2026-10-20T12:00:00Z"),
      proposal("task", "Dia 20", "2026-10-22T09:00-03:00"),
      proposal("task", "Dia 20", "2026-09-01T09:00:00.000-03:00"),
    ],
    "Me lembre de pagar o boleto dia 20",
    new Date(saturdayMorning),
  );

  assertEquals(filled.filled, 0);
  assertEquals(
    filled.proposals.map((item) => item.payload.due_at),
    [
      "2026-10-20T09:00:00-03:00",
      "2026-10-22T09:00:00-03:00",
      "2026-09-01T09:00:00-03:00",
    ],
  );
});

Deno.test("an impossible date is never re-spelled into another day", () => {
  const now = new Date(saturdayMorning);
  const undated = fillMissingDueAt(
    [
      proposal("task", "Sem data", "2026-02-30T09:00:00-03:00"),
      proposal("task", "Sem data", "2026-10-20T24:00:00-03:00"),
    ],
    "Organize o boleto",
    now,
  );
  const fromLabel = fillMissingDueAt(
    [proposal("task", "Dia 20", "2026-02-30T09:00:00-03:00")],
    "Organize o boleto",
    now,
  );

  assertEquals(undated.proposals.map((item) => item.payload.due_at), [
    null,
    null,
  ]);
  assertEquals(
    fromLabel.proposals[0].payload.due_at,
    "2026-10-20T09:00:00-03:00",
  );
});

Deno.test("a seed, a purchase and a memory never gain a date", () => {
  const filled = fillMissingDueAt(
    [
      proposal("seed", "Dia 20", null),
      proposal("shopping", "Dia 20", null),
      proposal("memory", "Dia 20", null),
    ],
    "Me lembre de pagar o boleto dia 20",
    new Date(saturdayMorning),
  );

  assertEquals(filled.filled, 0);
  assertEquals(filled.proposals.map((item) => item.payload.due_at), [
    null,
    null,
    null,
  ]);
});

Deno.test("a message's date fills only the one dated proposal it could have meant", () => {
  const now = new Date(saturdayMorning);
  const message = "Me lembre da consulta na sexta às 14h";
  const single = fillMissingDueAt(
    [proposal("reminder", "Sem data", null), proposal("shopping", "", null)],
    message,
    now,
  );
  const pair = fillMissingDueAt(
    [proposal("task", "Sem data", null), proposal("task", "Sem data", null)],
    message,
    now,
  );

  assertEquals(single.filled, 1);
  assertEquals(single.proposals[0].payload.due_at, "2026-10-02T14:00:00-03:00");
  assertEquals(single.proposals[0].payload.due_label, "02/10, 14:00");
  assertEquals(single.proposals[1].payload.due_at, null);
  assertEquals(pair.filled, 0);
  assertEquals(pair.proposals.map((item) => item.payload), [
    proposal("task", "Sem data", null).payload,
    proposal("task", "Sem data", null).payload,
  ]);
});

Deno.test("a due_at without a zone keeps Nina's São Paulo hour, and an unreadable one is re-read from its label or dropped", () => {
  const filled = fillMissingDueAt(
    [
      proposal("reminder", "Amanhã, 07:30", "amanhã"),
      proposal("task", "Dia 20", "2026-10-20T14:00:00"),
      proposal("task", "Logo mais", "2026-10-20T14:00"),
      proposal("task", "Sem data", "logo mais"),
    ],
    "Organize a semana",
    new Date(saturdayMorning),
  );

  assertEquals(filled.filled, 1);
  assertEquals(filled.proposals.map((item) => item.payload.due_at), [
    "2026-09-27T07:30:00-03:00",
    "2026-10-20T14:00:00-03:00",
    "2026-10-20T14:00:00-03:00",
    null,
  ]);
});

Deno.test("filling a date changes nothing else and never mutates what the model returned", () => {
  const returned = [
    proposal("reminder", "Dia 20", null),
    proposal("task", "Sem data", "2026-10-20T12:00:00Z"),
    proposal("seed", "Dia 20", null),
  ];
  const untouched = structuredClone(returned);

  const filled = fillMissingDueAt(
    returned,
    "Me lembre de pagar o boleto dia 20",
    new Date(saturdayMorning),
  );

  assertEquals(returned, untouched);
  assertEquals(filled.proposals.length, returned.length);
  filled.proposals.forEach((item, index) => {
    assertNotStrictEquals(item, returned[index]);
    assertNotStrictEquals(item.payload, returned[index].payload);
    assertEquals(
      { ...item, payload: { ...item.payload, due_at: null } },
      {
        ...returned[index],
        payload: { ...returned[index].payload, due_at: null },
      },
    );
  });
  assert(
    filled.proposals.every((item, index) => item.kind === returned[index].kind),
  );
});
