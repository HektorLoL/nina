# App Store listing — draft for version 1.0

Last updated: 2026-10-05

The text to paste into App Store Connect for the first submission. It is a
draft: Heitor approves every line before it is pasted. The name was decided on
2026-10-05. Each claim below is true of the build and the
server as of this date; re-check the marked ones before submitting.

The App Store page is visible to every age, so it follows the voice rule for
surfaces a minor can see (CLAUDE.md §2): Nina is spoken of in the third person,
is called "um programa de computador" once, and is never "amiga". No "para
crianças" anywhere in the metadata (runbook §6.3).

## 1. App information

| Field | Value | Limit |
|---|---|---|
| Name | Nina: rotina da casa (20). Decided 2026-10-05; App Store Connect still shows "Nina: sua amiga da casa" until Heitor renames it there | 30 |
| Subtitle | Tarefas, lembretes e compras (28) | 30 |
| Primary category | Produtividade | |
| Secondary category | Estilo de vida | |
| Support URL | https://ninai.app/suporte/ | |
| Marketing URL | https://ninai.app | |
| Privacy Policy URL | https://ninai.app/privacidade | |
| Age Suitability URL | https://ninai.app/familias/ | |
| Copyright | 2026 Heitor Castello Gomes França | |

Why this name: it drops "amiga", which the app no longer says anywhere
a child can see, and it repeats the login's own line, "A rotina da casa,
dividida." The subtitle then carries the three nouns people search for. Apple
indexes the name and subtitle, so the keywords below never repeat "rotina",
"casa", "tarefas", "lembretes" or "compras".

## 2. Promotional text (170)

> Conte para a Nina o que precisa ser feito em casa. Ela propõe tarefas, lembretes e compras, e nada entra na casa antes de você confirmar.

137 characters. It can change without a new version.

## 3. Description (4,000)

> A Nina organiza a rotina da casa a partir de uma conversa. Você escreve do seu jeito, como escreveria para alguém da família, e a Nina transforma isso em tarefas, lembretes, compras e sementes. Nada entra na casa antes de você confirmar.
>
> A Nina é um programa de computador. Ela propõe; as pessoas da casa decidem.
>
> PARA A CASA TODA
> • Até 8 pessoas na mesma casa, entre adultos, crianças e pets. A Nina não ocupa vaga.
> • Cada tarefa tem dono, data e categoria. Tarefa sem dono fica com a casa.
> • Lembretes na hora certa, e silêncio à noite quando você quiser. Do próprio aviso, marque como feita ou adie uma hora.
> • Lista de compras da casa: digite o item, aperte enter, e o próximo já pode vir.
> • Várias tarefas de uma vez: marque como feitas, passe para alguém ou apague.
> • Sementes: vontades sem data, que nunca viram atraso.
>
> UM RETRATO PARA CONVERSAR, NÃO PARA COBRAR
> • O Sinal de sobrecarga mostra como as tarefas abertas estão divididas entre os adultos da casa, em faixas, sem ranking.
> • Criança e adolescente nunca entram no retrato.
>
> CRIANÇAS E ADOLESCENTES
> • Quem tem menos de 18 anos entra numa casa só com a aprovação de um responsável, e vê só as próprias tarefas.
> • Tarefas grandes e coloridas para quem tem menos de 12 anos.
> • O dia de uma criança pode ser mostrado no celular de um adulto, impresso para a geladeira ou compartilhado como imagem ou PDF.
>
> PRIVACIDADE
> • Você entra com a sua conta Apple.
> • Os registros da casa ficam em servidores no Brasil.
> • A conversa com a Nina é para adultos com idade confirmada pela Apple, e só depois de aceitar o aviso: o que você escreve vai para a OpenAI, nos Estados Unidos, que pode guardar por até 30 dias para evitar abuso. Nome de criança ou adolescente vai trocado por um código.
> • Sem anúncios e sem rastreamento.
>
> NINA PREMIUM
> Uma assinatura vale para a casa toda:
> • Até 30 mensagens por hora para cada adulto. Sem o Premium, são 10 por dia.
> • O resumo semanal da casa, quando dois adultos conversam com a Nina.
>
> Nina Premium mensal: R$ 24,90 por mês. Nina Premium anual: R$ 249,90 por ano. A assinatura renova sozinha pelo App Store e pode ser cancelada a qualquer momento nos Ajustes do iPhone, até 24 horas antes da renovação. Apagar a conta da Nina não cancela a assinatura.
>
> Termos de uso: https://ninai.app/termos
> Política de privacidade: https://ninai.app/privacidade

Re-check before pasting:

- The quotas (30 per hour, 10 per day) are `begin_nina_chat_run` in
  `202609290006_ai_gates.sql`; the support FAQ says the same.
- The weekly summary needs at least two adults with a live AI consent and a
  week with some movement (`get_nina_weekly_candidates`), which the Premium
  line says; the in-app FAQ says the same.
- Photo and document reading are off at launch (`NINA_ATTACHMENTS_ENABLED =
  NO`), so the description never sells them.
- The prices are the App Store Connect prices for Brazil; Apple shows the
  current price on the page, and this text must match it.
- The description ends with the Terms link, which Guideline 3.1.2 asks of an
  auto-renewing subscription.

## 4. Keywords (100 bytes)

```
família,divisão,lista,mercado,filhos,organizar,agenda,doméstica,afazeres,boleto,carga mental,pet
```

99 bytes in UTF-8 (each accented letter is two). "boleto" stays even with
photo reading off: people ask Nina to remind them of one by text.

## 5. Subscriptions

| Field | Value | Limit |
|---|---|---|
| Group display name | Nina Premium | |
| `com.heitor.nina.premium.monthly` display name | Nina Premium mensal | 35 |
| Monthly description | A Nina Premium para a casa toda, mês a mês. | 55 |
| `com.heitor.nina.premium.yearly` display name | Nina Premium anual | 35 |
| Yearly description | Um ano de Nina Premium com 16% de economia. | 55 |

These equal `Nina/Nina.storekit`; 16% is R$ 249,90 against 12 × R$ 24,90.
Each subscription also needs its own review screenshot of the paywall.

## 6. App Review notes (English)

> Nina is a Brazilian household organizer in Portuguese. People sign in with Sign in with Apple only; there is no email or password, so there is no demo account. Please sign in with your own Apple Account.
>
> Nina proposes tasks from a chat and nothing is created until a person confirms it. The chat with Nina and the Premium subscription are available only to an adult whose age Apple's Declared Age Range confirms. If your review device does not share a confirmed adult age, the chat shows "A conversa pede idade confirmada." and the paywall is not offered. In that case, reply in this submission with the time you signed in and we will mark the review account as an adult on our server within one business day, or tell us how you prefer to reach those features.
>
> Subscriptions are verified with Apple in production first, then in the sandbox, so purchases made by App Review in the sandbox work.
>
> Questions about the age rating (we answered "Livre"):
> 1. Does content shared inside a closed household of up to 8 approved people count as User-Generated Content or as Messaging?
> 2. Do features that the server gates to users the Declared Age Range API confirms as 18+ count toward the questionnaire answers?
> 3. Does "some features are only for adults" in the Terms count as a minimum age requirement?
> 4. Sign in with Apple is the only sign-in, and the chat and the subscription open only for an adult whose age Apple confirmed. How should the reviewer reach those features?
>
> Age Suitability URL: https://ninai.app/familias/ — Support: https://ninai.app/suporte/

The four questions are word for word the ones in
`docs/production-launch-runbook.md` §6. Marking the reviewer's account uses
`private.operator_set_age_status(…, 'adult', null, true, 'app_review')` in the
SQL editor, the same operator path testers use.

## 7. What this draft does not cover

- The privacy questionnaire: `docs/privacy/app-store-privacy-labels.md` is the
  source; its "Purchases" row is still to settle in App Store Connect.
- Screenshots: 6.9-inch iPhone with made-up names, plus one paywall screenshot
  per subscription (open item 5).
