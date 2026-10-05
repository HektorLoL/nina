export interface SupportQuestion {
  question: string;
  answer: string;
}

export interface SupportTopic {
  title: string;
  questions: readonly SupportQuestion[];
}

export const supportEmail = "oi@ninai.app";

// The people limit is the one `AppStore.maxFamilyPeople` and the database enforce.
export const maxHousePeople = 8;

// These answers equal `SupportContent.topics` in `Nina/SupportView.swift`; web/tests/support.test.ts fails when the two drift.
export const supportTopics: readonly SupportTopic[] = [
  {
    title: "Usar a Nina",
    questions: [
      {
        question: "Como a Nina cria uma tarefa?",
        answer:
          "Você conta do seu jeito. A Nina propõe uma tarefa, um lembrete ou uma compra. Nada entra na casa antes de você confirmar.",
      },
      {
        question: "O que é uma semente?",
        answer:
          "Uma vontade sem data, como pintar a sala um dia. Ela fica guardada e nunca vira atraso. Quando chegar a hora, você planta e ela ganha uma data.",
      },
      {
        question: "Por que um aviso não chegou?",
        answer:
          "Confira Avisos nos Ajustes da Nina e nos Ajustes do iPhone. Uma tarefa sem data não tem aviso. No silêncio da noite, o aviso chega na hora, sem som.",
      },
      {
        question: "Por que a conversa pede idade confirmada?",
        answer:
          "Conversar com a Nina, assinar o Premium e incluir uma criança pedem idade confirmada pela Apple. Tarefas, lembretes e compras funcionam sem isso.",
      },
    ],
  },
  {
    title: "A casa",
    questions: [
      {
        question: "Como chamo alguém para a casa?",
        answer:
          "Em Casa, use Convidar alguém e mande o link. Quem abrir pede para entrar, e alguém da casa aprova.",
      },
      {
        question: "Quantos cabem numa casa?",
        answer:
          `Até ${maxHousePeople}, entre pessoas e pets. A Nina não ocupa vaga.`,
      },
      {
        question: "Crianças podem usar a Nina?",
        answer:
          "Uma criança ou um adolescente entra numa casa só com a aprovação de um responsável, e vê só as próprias tarefas.",
      },
      {
        question: "O que o Premium inclui?",
        answer:
          "Vale para a casa toda: cada adulto manda até 50 mensagens por dia para a Nina. Sem o Premium, são 10 mensagens por dia. Quando dois adultos aceitaram conversar com a Nina, a casa também recebe o resumo semanal nas semanas com movimento.",
      },
      {
        question: "Como cancelo o Premium?",
        answer:
          "Nos Ajustes do iPhone, em Assinaturas. Apagar a conta não cancela a cobrança.",
      },
    ],
  },
  {
    title: "Privacidade e conta",
    questions: [
      {
        question: "Quem lê minha conversa com a Nina?",
        answer:
          "Na casa, só você. Cada adulto tem a própria conversa. Uma memória começa privada, e só vai para a casa se você compartilhar.",
      },
      {
        question: "Para onde vai o que eu escrevo?",
        answer:
          "Os seus registros ficam em servidores no Brasil. O que você escreve para a Nina vai para a OpenAI, nos Estados Unidos, que pode guardar por até 30 dias para evitar abuso. Nome de criança ou adolescente vai trocado por um código.",
      },
      {
        question: "Como apago minha conta?",
        answer:
          "Em Ajustes, no fim da lista, em Apagar conta. As tarefas que eram suas voltam para a casa, sem dono. Se a casa é sua e nenhum outro adulto fica nela, ela é apagada junto.",
      },
    ],
  },
];

export function supportMailto(subject = "Ajuda com a Nina"): string {
  return `mailto:${supportEmail}?subject=${encodeURIComponent(subject)}`;
}
