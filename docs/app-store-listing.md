# App Store listing — draft for version 1.0

Last updated: 2026-10-19

The text to paste into App Store Connect for the first submission. It is a
draft: Heitor approves every line before it is pasted. The name was decided on
2026-10-05. Each claim below is true of the build and the
server as of this date; re-check the marked ones before submitting.

The App Store page is visible to every age, so it follows the voice rule for
surfaces a minor can see (CLAUDE.md §2): Nina is spoken of in the third person
and is never "amiga". It does not call her "um programa de computador"
(Heitor's call, 2026-10-05): the store page is not a conversation, and every
screen a minor sees in the app still says it once. No "para crianças" anywhere
in the metadata (runbook §6.3), and no block that markets the minor features:
Heitor cut the description's "CRIANÇAS E ADOLESCENTES" block and its kids-mode
line on 2026-10-15, and the website's "Crianças" section followed on
2026-10-19. The features are unchanged in the app, and `/familias/`, the Age
Suitability URL, still describes them.

## 1. App information

| Field | Value | Limit |
|---|---|---|
| Name | Nina: rotina da casa (20). Renamed in App Store Connect on 2026-10-05 | 30 |
| Subtitle | Tarefas, lembretes e compras (28) | 30 |
| Primary category | Produtividade | |
| Secondary category | Estilo de vida | |
| Support URL | https://ninai.app/suporte/ | |
| Marketing URL | https://ninai.app/ | |
| Privacy Policy URL | https://ninai.app/privacidade/ | |
| Age Suitability URL | https://ninai.app/familias/ | |
| Age rating, Brazil | 14 ("Não recomendado para menores de 14 anos"; ClassInd's reading of 2026-10-15, accepted 2026-10-18). "A14" in the rating document is its own notation, not an App Store Connect value; how App Store Connect sets it is UNVERIFIED (`docs/privacy/classificacao-indicativa.md` §2) | |
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
> A Nina propõe; as pessoas da casa decidem.
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
> PRIVACIDADE
> • Você entra com a sua conta Apple.
> • Os registros da casa ficam em servidores no Brasil.
> • A conversa com a Nina é para quem tem 18 anos ou mais na faixa de idade da Apple, e só depois de aceitar o aviso: o que você escreve vai para a OpenAI, nos Estados Unidos, que pode guardar por até 30 dias para evitar abuso. Nome de criança ou adolescente vai trocado por um código.
> • Sem anúncios e sem rastreamento.
>
> NINA PREMIUM
> Uma assinatura vale para a casa toda:
> • Até 50 mensagens por dia para cada adulto. Sem o Premium, são 10.
> • O resumo semanal da casa, quando dois adultos conversam com a Nina.
>
> O Compartilhamento Familiar da Apple não libera o Premium: a assinatura vale para a casa da Nina de quem assinou, com todo mundo que está nela.
>
> Nina Premium mensal: R$ 24,90 por mês. Nina Premium anual: R$ 249,90 por ano. A assinatura renova sozinha pelo App Store e pode ser cancelada a qualquer momento nos Ajustes do iPhone, até 24 horas antes da renovação. Apagar a conta da Nina não cancela a assinatura.
>
> Termos de uso: https://ninai.app/termos/
> Política de privacidade: https://ninai.app/privacidade/

Re-check before pasting:

- The quotas (50 per day with Premium, 10 per day without) are
  `begin_nina_chat_run` in `202610050004_premium_daily_chat_limit.sql`, which
  must be live in production before submission; the support FAQ says the
  same.
- The weekly summary needs at least two adults with a live AI consent and a
  week with some movement (`get_nina_weekly_candidates`), which the Premium
  line says; the in-app FAQ says the same.
- Photo and document reading are off at launch (`NINA_ATTACHMENTS_ENABLED =
  NO`), so the description never sells them.
- The chat line says 18+ on Apple's range, not a confirmed age, because of
  decision D3 (2026-10-14). It is true only while production's
  `private.age_policy.trusted_assurances` holds `self_declared`
  (`docs/production-launch-runbook.md`, "Measuring the age distribution on
  TestFlight (decision D3)").
- The prices are the App Store Connect prices for Brazil; Apple shows the
  current price on the page, and this text must match it.
- The description ends with the Terms link, which Guideline 3.1.2 asks of an
  auto-renewing subscription. Every `ninai.app` link ends in a slash: the site
  serves each page at its folder, so the slashless form answers with a
  redirect first.
- Family Sharing is on for both subscriptions in App Store Connect (since
  2026-09-03; Apple never lets it be turned off), so the store page may say a
  purchase can be shared. The Family Sharing line says what the app does: the
  server binds each receipt to the buyer's account and covers the buyer's
  house, and a family-shared transaction never reaches the server
  (`CLAUDE.md` §4, Monetization). The landing's FAQ says the same.

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

The one text to paste into App Review Information › Notes, as it stands on
2026-10-19. It replaces every earlier draft, the one that was in
`docs/privacy/classificacao-indicativa.md` §4 included. Paste what is inside the
fence, line breaks as they are: 3,877 characters, under Apple's 4,000.

```text
Nina is a household organizer for families in Brazil, in Brazilian Portuguese, for iPhone. A person tells Nina in a chat what the house needs; Nina proposes tasks, reminders and shopping items, and nothing is created until a person confirms it.

How to review
1. Tap "Continuar com a Apple" and sign in with your own Apple Account. There is no email, password or demo account.
2. Nina asks for your age range through Apple's Declared Age Range sheet ("Antes, sua faixa de idade."). Share it. An 18+ range, self-declared or confirmed, opens the chat and Premium; adding or approving a child needs an age Apple confirmed.
3. Tap "Criar uma casa", type any house name and continue. A short tour follows; "Pular" skips it.
4. Nina tab: before the first message Nina shows a notice saying that what you write goes to OpenAI in the United States, with a separate, unticked box for that transfer. Tick the box, then tap "Aceitar e conversar com a Nina".
5. Send, for example, "Me lembra de pagar a conta de luz dia 20". Nina answers with a proposal card; tap "Criar tarefa" to confirm. The task then appears in Hoje and Tarefas.
6. To report one of Nina's replies, touch and hold it and choose "Denunciar resposta".
7. Premium: Casa tab, gear icon (Ajustes), "Nina Premium". In-app purchases need a sandbox account set to Brazil, the only storefront where Nina is sold. The server verifies receipts in production first, then in the sandbox, so sandbox purchases work.
8. Account deletion: Ajustes, "Apagar conta".

If your device shares no age range, Nina treats the account as a minor's, which can only ask to join a household. Reply in this submission with the time (UTC) you signed in, and we will mark that account on our server as a self-declared adult within one business day: it reaches the chat and Premium, never decisions about a child. We remove the mark after the review.

Sign in with Apple is the only way in. Nina requests only the full-name scope and never the email scope, and keeps only the first (given) name Apple shares; it never stores the family name, and it never asks for an email address, so an account created with this version holds none. The first name is what the other members of the household see. An adult is asked to type a first name only when Apple shared none (the person chose not to share it, or the Apple ID had already signed in to Nina, since Apple shares the name only on the first sign-in), and only when creating or joining a household. A person under 18, or anyone whose age Apple has not shared (Nina treats that account as a minor's until it does), confirms a first name, filled in from Apple's when shared, only when asking a guardian to let them join a household.

Age rating: on 15 October 2026 Brazil's Ministry of Justice rating coordination (ClassInd) told us Nina tends to "not recommended for under 14" because of the in-app subscription and the generative AI chat. We accept that and set the Brazil age rating to 14. Nina sets no minimum age: a person under 18 joins a household only with a guardian's approval in the app and sees only their own tasks. Our questions:
1. Does content shared inside a closed household of up to 8 approved people count as User-Generated Content or as Messaging?
2. The AI chat and the subscription open only for accounts the Declared Age Range API reports as 18+, self-declared or confirmed. Do these adult-only features count toward the questionnaire answers, and could they lift Brazil's rating above 14?
3. Our Terms say some features are only for adults and set no minimum age. Does that count as a minimum age requirement?
4. If a review device shares no age range, is marking the review account as a self-declared adult on our server, as described above, the way you prefer to reach the adult features?

Age Suitability URL: https://ninai.app/familias/ — Support: https://ninai.app/suporte/
```

What each part rests on, and what to re-check before pasting:

- **The steps** follow the build as of 2026-10-19: "Continuar com a Apple" is
  the one door, the age step comes right after it, house setup opens on "Criar
  uma casa" or "Tenho um convite", the tour skips with "Pular", the consent card
  keeps "Aceitar e conversar com a Nina" off until the "Envio para fora do
  Brasil" box is ticked, a dated proposal confirms with "Criar tarefa", and
  "Denunciar resposta" is the context menu of a reply Nina sent. Re-read them
  against the build you submit.
- **The sandbox line.** Both subscriptions are sold in Brazil only, so a
  sandbox Apple Account in another storefront sees no product. The server
  verifies production first, then sandbox, and `NINA_APP_STORE_ENVIRONMENT`
  stays unset (`docs/production-launch-runbook.md` §2).
- **The reviewer's account** (Heitor's choice 3 of 2026-10-19): marked with
  `trusted = false`, which records a self-declared adult, so it chats and buys
  but never approves, adds or answers for a child. The mark and unmark
  statements, and how to find the account from the time the reviewer gives,
  are in `docs/production-launch-runbook.md` §6, "The reviewer's account".
- **The Sign in with Apple paragraph** is word for word the one in
  `docs/production-launch-runbook.md` §6.1 (Guideline 4.0; decided
  2026-10-05, build 12). Change both together or neither.
- **The four questions** are recorded with their answers in
  `docs/privacy/classificacao-indicativa.md` §3, in these words. They were
  reworded on 2026-10-19 for the rating of 14 and for D3: question 2 can still
  lift Apple's rating above 14, question 3 decides whether the Terms force an
  override Nina did not choose, question 1 decides whether "No" is the honest
  answer, and question 4 is how the reviewer reaches the adult features.
- **The age-rating sentence.** If the análise prévia has been filed or decided
  by the time of submission, say so. If App Store Connect could not set the
  Brazil rating to 14 directly, replace "set the Brazil age rating to 14" with
  what it allowed (UNVERIFIED until then;
  `docs/privacy/classificacao-indicativa.md` §2).
- **Count again after any edit**, with the text alone (no fence):

  ```sh
  python3 -c 'import sys; print(len(sys.stdin.read().rstrip("\n")))' < notes.txt
  ```

## 7. What this draft does not cover

- The privacy questionnaire: `docs/privacy/app-store-privacy-labels.md` is the
  source, Purchase History, Health and Photos or Videos rows included (added
  2026-10-19).
- Screenshots: plain 6.9-inch iPhone screenshots of the app, with made-up
  names, for the first submission (Heitor's choice 1 of 2026-10-19; designed
  images come later), plus one paywall screenshot per subscription.
- The App Store Connect settings themselves (availability, devices, age
  answers, URLs, categories, the subscription group, the release mode):
  `docs/production-launch-runbook.md` §6, "App Store Connect settings".
