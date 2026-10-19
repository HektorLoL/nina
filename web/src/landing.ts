import { type SupportQuestion, supportTopics } from "./support.ts";
import type { AppStoreListing } from "./appStore.ts";

export type TrayGlyph = "house" | "card" | "backpack" | "paw" | "seed";

export interface TourCast {
  owner: string;
  partner: string;
  child: string;
  pet: string;
}

export interface TrayRow {
  title: string;
  label: string;
  glyph: TrayGlyph;
  owner?: string;
  isLate?: boolean;
}

export interface ProposalFace {
  title: string;
  glyph: TrayGlyph;
  category: string;
  when: string;
  owner: string;
  isSeed: boolean;
}

export interface NinaStop {
  kind: "nina";
  id: string;
  title: string;
  line: string;
  extra: string;
  message: string;
  reply: string;
  proposal: ProposalFace;
}

export interface TodayStop {
  kind: "today";
  id: string;
  title: string;
  line: string;
  extra: string;
  rows: readonly TrayRow[];
}

export interface TasksStop {
  kind: "tasks";
  id: string;
  title: string;
  line: string;
  extra: string;
  group: { title: string; rows: readonly TrayRow[] };
  lists: readonly { title: string; count: number }[];
  seed: { title: string; label: string };
}

export interface HouseStop {
  kind: "house";
  id: string;
  title: string;
  line: string;
  extra: string;
  people: readonly { name: string; role: "adulto" | "criança" }[];
  pet: string;
  caption: string;
}

export type TabStop = NinaStop | TodayStop | TasksStop | HouseStop;

// The example house is the app's own tour cast, so the site never draws a real person.
export const tourCast: TourCast = {
  owner: "Dani",
  partner: "Cris",
  child: "Lia",
  pet: "Paçoca",
};

export const proposalCopy = {
  pending: "Ainda não existe",
  disclaimer: "A Nina pode ler errado. Nada entra sem você confirmar.",
  create: "Criar tarefa",
  correct: "Corrigir",
  decline: "Não",
  resolved: "Você confirmou.",
  composer: "Escreva pra Nina",
} as const;

export const heroExample = {
  message: "Autorização da escola até amanhã",
  reply: "Entendi. Fica como tarefa para amanhã?",
  proposal: {
    title: "Assinar a autorização",
    glyph: "backpack",
    category: "Escola",
    when: "Amanhã, 09:00",
    owner: "Sem dono",
    isSeed: false,
  } satisfies ProposalFace,
  confirmLabel: `${proposalCopy.create}: Assinar a autorização, de exemplo`,
  captionBefore: "Nada existe até você tocar em Criar tarefa.",
  captionAfter: "Foi só um exemplo. Nada do que você viu entrou na sua casa.",
  replay: "Ver de novo",
  description:
    "Uma conversa de exemplo na aba da Nina. Você escreve: autorização da escola até amanhã. A Nina responde: entendi, fica como tarefa para amanhã? E propõe algo que ainda não existe: assinar a autorização, escola, amanhã às 9 horas, sem dono. O botão abaixo cria essa tarefa de exemplo, que não sai desta página.",
} as const;

const seedProposal: ProposalFace = {
  title: "Pintar a sala",
  glyph: "house",
  category: "Casa",
  when: "Plante depois",
  owner: "Sem dono",
  isSeed: true,
};

export const ninaStop: NinaStop = {
  kind: "nina",
  id: "aba-nina",
  title: "Nina",
  line:
    "Na aba da Nina, você conta o que precisa ser feito, do jeito que vier. Ela lê e propõe o que fazer.",
  extra:
    "Ela sugere quem fica com cada coisa. Quando não tem data, ela não inventa uma.",
  message: "Um dia quero pintar a sala",
  reply: "Entendi. Sem data, pode ficar como semente.",
  proposal: seedProposal,
};

export const todayStop: TodayStop = {
  kind: "today",
  id: "aba-hoje",
  title: "Hoje",
  line: "Em Hoje fica o dia da casa. O que atrasou vem primeiro, sem bronca.",
  extra: "Do próprio aviso, dá para marcar como feita ou adiar uma hora.",
  rows: [
    {
      title: "Pagar a luz",
      label: "Hoje, 08:00",
      glyph: "card",
      owner: tourCast.owner,
      isLate: true,
    },
    {
      title: "Levar o lixo",
      label: "Hoje, 20:00",
      glyph: "house",
      owner: tourCast.partner,
    },
    {
      title: "Lavar a louça",
      label: "Hoje, 21:00",
      glyph: "house",
      owner: tourCast.owner,
    },
  ],
};

export const tasksStop: TasksStop = {
  kind: "tasks",
  id: "aba-tarefas",
  title: "Tarefas",
  line:
    "Em Tarefas fica tudo por categoria, e as compras também. Semente é vontade sem data e nunca atrasa.",
  extra: "Várias de uma vez: marque como feitas, passe para alguém ou apague.",
  group: {
    title: "Pet",
    rows: [
      {
        title: "Vacina",
        label: "Amanhã, 09:00",
        glyph: "paw",
        owner: tourCast.owner,
      },
    ],
  },
  lists: [
    { title: "Sementes", count: 1 },
    { title: "Compras", count: 1 },
  ],
  seed: { title: "Pintar a sala", label: "Plante depois" },
};

export const houseStop: HouseStop = {
  kind: "house",
  id: "aba-casa",
  title: "Casa",
  line:
    "Em Casa ficam as pessoas, os pets e um retrato de quem carrega mais. É para conversar, não para cobrar.",
  extra: "Até 8 na casa, entre pessoas e pets. A Nina não ocupa vaga.",
  people: [
    { name: tourCast.owner, role: "adulto" },
    { name: tourCast.partner, role: "adulto" },
    { name: tourCast.child, role: "criança" },
  ],
  pet: tourCast.pet,
  caption:
    `${tourCast.owner}, ${tourCast.partner}, ${tourCast.child}, ${tourCast.pet} e a Nina`,
};

export const tabStops: readonly TabStop[] = [
  ninaStop,
  todayStop,
  tasksStop,
  houseStop,
];

export type WorkloadBandName = "leve" | "parecido" | "mais pesado";

export const workloadBands: readonly WorkloadBandName[] = [
  "leve",
  "parecido",
  "mais pesado",
];

// Five, one and one open tasks put the average at three, which is what makes these bands reachable in the app.
export const workloadExample = {
  eyebrow: "Sinal de sobrecarga",
  headline: "A casa está pesando mais de um lado.",
  caption: "Só o que está aberto e tem dono. Para conversar, não para cobrar.",
  method: "Sementes não entram. Não é histórico, é hoje.",
  rows: [
    { name: tourCast.owner, band: "mais pesado", isShared: false },
    { name: tourCast.partner, band: "leve", isShared: false },
    { name: "Sem dono", band: "leve", isShared: true },
  ] as const satisfies readonly {
    name: string;
    band: WorkloadBandName;
    isShared: boolean;
  }[],
};

export function workloadDescription(): string {
  const rows = workloadExample.rows.map((row) => `${row.name}, ${row.band}.`)
    .join(" ");
  return `Exemplo do sinal de sobrecarga, em três faixas: leve, parecido e mais pesado. ${rows} Não há número nenhum.`;
}

export function initial(name: string): string {
  return Array.from(name.trim())[0]?.toLocaleUpperCase("pt-BR") ?? "";
}

function spokenRow(row: TrayRow): string {
  const lateness = row.isLate ? "atrasada, " : "";
  return `${row.title}, ${lateness}${row.label}, ${row.owner ?? "sem dono"}.`;
}

function lowerFirst(text: string): string {
  return text.charAt(0).toLocaleLowerCase("pt-BR") + text.slice(1);
}

export function exampleDescription(stop: TabStop): string {
  const opening = `Exemplo da aba ${stop.title}:`;
  switch (stop.kind) {
    case "nina": {
      const face = stop.proposal;
      const reply = stop.reply.split(". ").map(lowerFirst).join(", ");
      return `${opening} você escreve ${
        lowerFirst(stop.message)
      }. A Nina responde: ${reply} E propõe ${face.title}, ${face.category}, ${
        lowerFirst(face.when)
      }, ${lowerFirst(face.owner)}. ${proposalCopy.pending}.`;
    }
    case "today": {
      const late = stop.rows.filter((row) => row.isLate).length;
      return `${opening} atrasadas, ${late}. ${
        stop.rows.map(spokenRow).join(" ")
      }`;
    }
    case "tasks": {
      const group =
        `categoria ${stop.group.title}, ${stop.group.rows.length}. ${
          stop.group.rows.map(spokenRow).join(" ")
        }`;
      const [first, second] = stop.lists;
      const lists =
        `Listas ${first.title}, ${first.count}, e ${second.title}, ${second.count}.`;
      return `${opening} ${group} ${lists} ${stop.seed.title}, ${
        lowerFirst(stop.seed.label)
      }.`;
    }
    case "house": {
      const adults = stop.people.filter((person) => person.role === "adulto")
        .map((person) => person.name);
      const children = stop.people.filter((person) => person.role === "criança")
        .map((person) => person.name);
      return `${opening} ${adults.join(" e ")}, adultos; ${
        children.join(" e ")
      }, criança; ${stop.pet}, pet; e a Nina.`;
    }
  }
}

export function availabilityLine(listing: AppStoreListing): string {
  const device = "Para iPhone, com iOS 26.4 ou mais novo.";
  return listing.isPublished
    ? device
    : `${device} Ainda em teste, fora da App Store.`;
}

export const closingLine = "Quer uma casa mais leve?";

export function closingHeadline(listing: AppStoreListing): string {
  return listing.isPublished
    ? "A Nina está na App Store."
    : "A Nina está quase pronta para a sua casa.";
}

// A borrowed answer is read from the support list by its question, so the two can never say different things.
export function fromSupport(question: string): SupportQuestion {
  for (const topic of supportTopics) {
    const found = topic.questions.find((item) => item.question === question);
    if (found) return found;
  }
  throw new Error(`The support list has no question "${question}".`);
}

export const landingFaq: readonly SupportQuestion[] = [
  {
    question: "Como eu entro na Nina?",
    answer:
      "Com a sua conta Apple, em Continuar com a Apple. A Nina não pede senha nem email. Depois de entrar, você compartilha a sua faixa de idade pela Apple, e a Nina recebe só a faixa, nunca a data de nascimento.",
  },
  fromSupport("Quem pode conversar com a Nina?"),
  fromSupport("Quem lê minha conversa com a Nina?"),
  {
    question: "A Nina funciona sem internet?",
    answer:
      "Não. Ao abrir, a Nina confere se você ainda faz parte da casa, e isso pede internet. Os lembretes já marcados no iPhone continuam chegando.",
  },
  {
    question: "Posso usar se moro sozinho?",
    answer:
      "Pode. O retrato da casa fica dormindo, porque com um adulto só não tem o que comparar, mas as tarefas, as compras, os lembretes e as sementes funcionam igual.",
  },
  {
    question: "Funciona no Android ou no iPad?",
    answer: "Ainda não. A Nina é só para iPhone, com iOS 26.4 ou mais novo.",
  },
  fromSupport("Como cancelo o Premium?"),
  {
    question: "O Premium vale para o Compartilhamento Familiar da Apple?",
    answer:
      "Não. Uma assinatura cobre a casa da Nina de quem assinou, com todo mundo que está nela. O Compartilhamento Familiar da Apple não libera o Premium.",
  },
];

// Every sentence Nina herself says on the site; she speaks of herself in the third person on a page every age can read.
export function ninaLines(): string[] {
  return [
    heroExample.reply,
    ninaStop.reply,
    proposalCopy.disclaimer,
    closingLine,
  ];
}

export type AvatarTone = "ink" | "slate" | "mist";

// The same neutral ink tints the app's MemberTone gives the tour cast: never a hue per person.
export function avatarTone(name: string): AvatarTone {
  if (name === tourCast.partner) return "slate";
  if (name === tourCast.child) return "mist";
  return "ink";
}
