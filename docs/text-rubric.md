# Nina: rubric for cutting on-screen text

Last updated: 2026-10-18

This rubric applies to every screen of the iOS app. A screen passes when it meets every rule in §1 and every rule in its surface section (§2), and when none of the text listed in §3 has been lost. The rules come from Mobbin research on about 90 iOS screens across six surfaces. The strongest references are cited inline.

---

## 0. How to audit a screen

1. **Render every state.** That means default, empty, error, loading and offline. It also means owner, admin and member; a free house and a covered house; a trusted adult, a declared adult, a minor and an unknown age; and Dynamic Type at `accessibility3`.
2. **List every visible string and tag it.**
   - **T**: title
   - **D**: live data (a date, count, name, price or status value)
   - **A**: an action label
   - **P**: protected text (§3)
   - **X**: an explanation of how something works
   - **R**: reassurance
   - **I**: an instruction about a control (for example "Toque para…")
   - **=**: text that repeats something already on screen
3. **Delete every X, R, I and = string**, unless the surface section explicitly allows it or it is also P. A P string may be shortened to the minimum form given in §3. It is never removed.
4. **Count the words against the budget** in the table at the end of §1.
   - Count every word the app writes: buttons, eyebrows, placeholders, footers and legal text.
   - A number, price, time or date counts as one word.
   - Do not count household content: task titles, people's names, the house name, message text, or Nina's generated replies.
5. **Run the layout checks** (G15, G16, G19) and the engineering guardrails (§4).

---

## 1. Global rules

- **G1. A screen header is the title only.** A second line is allowed only when it is live data: a date, a count, or a greeting of 3 words or fewer that uses the person's name. No sentence may explain what the screen or a filter is. All 10 list screens reviewed follow this, for example [Things 3 Today](https://mobbin.com/flows/2183d71f-aab0-40ba-a87a-96eb62a16b0c) and [Todoist Today](https://mobbin.com/flows/209b02ae-6b81-4249-812f-0847d36572c1).
- **G2. Each fact appears once per screen.** This covers counts, prices, renewal terms, reassurances and invariants. If count tiles carry the numbers, the chips do not (see [Reminders](https://mobbin.com/flows/d3ee4640-b9c8-48a6-bc02-5460d835de85), where the tiles are the filter).
- **G3. State is a value, never a sentence.** Show it as a trailing muted value of 1–2 words: "Ligados", "Bloqueados", "5 vagas", "Ativo", "Participante". Precedents: [Telegram Privacy](https://mobbin.com/screens/c6c93be9-2128-4a89-b2a4-8ddd62b91af9) and [Duolingo Reminders](https://mobbin.com/screens/ec850b9f-5407-470f-8d3c-548f4ac5c2df).
- **G4. Never write "Toque para…"**, and never describe what a chevron, toggle or ↗ does. None of the 15 settings references does.
- **G5. A row is an optional glyph, a title of 3 words or fewer, and exactly one trailing element**: a chevron, ↗, a toggle, or a value.
  - A second line is allowed only for data that changes (an email, a role, a date, a count).
  - It is never a description.
  - Only the account row gets a second line by default (§2.3).
- **G6. Helper text under a control is allowed only when it prevents an error with a real consequence**: money, data loss, sharing with another person, privacy, a lockout, or a notification that will not fire. It must be one sentence of 12 words or fewer.
- **G7. Footers.**
  - At most one footer per group.
  - One sentence of 15 words or fewer.
  - Only when the setting's effect cannot be guessed from its title.
  - It never repeats a row or a picker.
- **G8. Explanations of how a feature works belong in three places only**: the tutorial, the sheet the action opens, or behind an (i) control. They never sit on the list that links to the feature.
  - On a populated screen, teaching copy may appear only once, as a card the viewer can dismiss. Remember the dismissal per viewer.
  - Precedent: the [Superlist tip card](https://mobbin.com/flows/caf436ab-dcf0-42ed-ab27-15a0b3437619).
- **G9. Each reassurance appears once per flow**, not once per screen.
- **G10. Buttons are a verb of 1–2 words, with a hard maximum of 3.**
  - Add the noun only when the screen does not already name the object. A proposal card uses "Criar tarefa"; a sheet already titled "Nova tarefa" uses "Criar".
  - The system Apple button label is exempt.
- **G11. One word per act.** A verb used for one action is never reused for another. "Plantar" means giving a semente a date; creating a semente is "Nova semente".
- **G12. Empty and blocked states.**
  - At most one mark, a headline of 6 words or fewer, at most one line of 10 words or fewer, and at most one action.
  - A filter or group that comes up empty shows one line of 4 words or fewer, with no mark, body or action.
  - Precedents: [Attio "No Tasks / Create your first task." with the + button](https://mobbin.com/screens/be0471bf-0192-4057-b23f-ba463960aa30) and [Genie](https://mobbin.com/flows/e83357bc-8fe8-4092-91cf-1caecef82973).
- **G13. Alerts.**
  - The title is a question that names the action, in 7 words or fewer.
  - The message is 10 words or fewer, or absent. It states only a consequence, and never repeats the title or the button.
  - The destructive button is the verb alone.
  - Precedent: [Vocabulary account deletion](https://mobbin.com/flows/979ec144-9635-428a-b171-3d0223fa30c6).
- **G14. No vendor names, configuration instructions or error codes.** "Supabase", "configure o projeto" and similar never appear. Technical nouns are allowed only inside a protected privacy line from §3. "Apple" and "App Store" are allowed where the system or the purchase requires them.
- **G15. Composition** (rewritten 2026-10-14; its old first bullet, "free space sits above the actions, never below them", pinned every form's commit to the foot of the screen and opened the gaps Heitor rejected).
  - No glaze sits between a control and what it acts on.
  - A sheet is as tall as its content (`FittedSheetLayout`), and a form's commit follows its last field, with that field focused on arrival. Precedents: Things 3 new to-do, Todoist and TickTick quick add, Toggl "Edit Project", WHOOP "Join team", Quizlet "Join with code"; counter-examples: Faire "Edit board" and Discord "Join an existing server", whose commit floats at the foot under empty glaze.
  - A single centered block (an empty state, the brand block, a gate) keeps a spacer above and below it and its exits at the foot. The old "free space above the actions" survives only here.
  - A short page ends at its last control, and the leftover glaze falls below it, the way a short list ends. Screens scroll at `accessibility3`; a `minHeight` equal to the viewport is only for a centered block, never fixed heights.
- **G16. Glyphs replace words only where the glyph is standard**: chevron, ↗, +, bell, calendar, person, lock, (i).
  - Every icon-only control has an explicit `accessibilityLabel`.
  - A state word removed from the screen moves into `accessibilityValue`.
- **G17. Voice.**
  - Informal `você`. No exclamation marks, no emoji.
  - Nina is named as a person, never "IA" or "assistente".
  - No string claims Nina did something.
  - Short does not mean telegraphic: Nina's own lines stay whole sentences with a period.
  - **Exception, surfaces a minor can see** (§2.9 and the login): Nina is spoken of in the third person and never says "eu", she is "um programa de computador" once per flow (Decreto 12.880 art. 11 I), and she is never "amiga". The guardian sheet and "O que a Nina guarda" may say "inteligência artificial", because the legal line has to name what the data does not reach.
- **G18. No string claims that nothing sent to the model is kept.** OpenAI may keep abuse logs up to 30 days. "fica guardado lá", "servidor nenhum", "usado só para responder" and "não guarde o que recebe" fail `repository.retention-claims`.
- **G19. A control's label never wraps beside another control** (2026-10-14).
  - `NinaChip` holds one line. A chip row that does not scroll horizontally is a `ViewThatFits(in: .horizontal)`: the row first, then a stacked fallback.
  - If a row cannot fit at default size on a 375 pt phone, a control moves into the edit state before any label is shortened, and a protected label (§3) is never shortened.
  - At accessibility sizes a chip alone in its column, or a lone full-width button, may wrap. Nothing is truncated or clipped.
  - Two labelled buttons side by side ("Feitas" / "Passar", "Aprovar" / "Recusar", "Aceitar" / "Recusar", "Corrigir" / "Não") share the row only while each label fits its share of it; otherwise they stack, full width, and the selection bar drops its glyphs before it stacks. A quiet control beside a commit ("Apagar", "Adicionar e continuar") takes its own line above the commit before either wraps. A text control beside a header's title ("Cancelar", "Sair da conta") drops below the title or into the header's menu before either wraps.
  - Precedents: Apple News Saved Stories, Places and Abode, which keep Edit and Delete out of the card, and Nina's own Hoje header (the date beside the Premium badge in a `ViewThatFits`).
- **G20. A failure line opens one way: "Não deu para ‹ação› agora. Tente de novo."** (2026-10-15).
  - It reaches the screen through `NinaErrorNote` or the sync toast, never as plain ink text.
  - A consequence the person must know may sit between the two ("Não deu para confirmar agora. Nada entrou na casa. Tente de novo."; "… Ele continua ativo nesta casa. Tente de novo.").
  - Where a retry cannot help, the close changes, never the opening: "Não deu para ler esse arquivo. Escolha outro."; a build with no server reads "Não deu para ‹ação› agora. Tente mais tarde."
  - When a "Tentar de novo" control sits beside it, the line drops its own "Tente de novo." (G2).
  - Not covered: a refusal that names its reason ("Este convite é inválido, expirou ou a casa está sem vagas."), a field to fix ("Cada anexo pode ter até 5 MB."), the account-deletion lines (§2.3) and the sign-in line "Não foi possível entrar agora. Tente de novo.", which CLAUDE.md §12 and the launch runbook quote as the sign of a production Auth setting.
  - A closed door is not a failure: "Foto e documento são do Premium." after a house loses Premium stays grout and ink.

### Word budgets

These count authored words only, as defined in §0 step 4.

| Surface | Budget |
|---|---|
| Welcome / login | ≤ 28 including button labels and legal; ≤ 16 without the legal line. The protected age line makes it 30; the legal text wins |
| Settings root | ≤ 50, and 1 second line in total (the account row) |
| Settings sub-screen | ≤ 40, plus protected footers |
| Tour | 6 steps, ≤ 120 authored words in total (Nina's lines, the header, the skip, the buttons, the "Exemplo" legend), ≤ 24 per line; example values and protected lines inside the tray are not counted |
| Empty state | headline ≤ 6 + one line ≤ 10 + one action ≤ 3 |
| Filter or group empty | one line ≤ 4 |
| Chat, empty | ≤ 25 including chips and placeholder |
| Proposal card chrome | ≤ 10, not counting the proposal's own values or protected lines |
| Consent gate | no budget: every line is Law-text-gated (§3 row 3) |
| Age check, minor states | the empty-state budget; protected lines are not counted |
| Guardian sheet chrome | ≤ 20, not counting the protected card, declaration and consents |
| Alert | title ≤ 7, message ≤ 10, buttons 1–2 words |
| Capture sheet chrome | ≤ 15 |
| Paywall | ≤ 55 including the terms line and the link row |
| Premium management | ≤ 45 |
| Casa | ≤ 40, not counting names |
| Workload portrait | ≤ 45 |

---

## 2. Rules per surface

### 2.1 Login (`LoginView`)

**Recommended layout: brand block in the middle, actions at the bottom.**

- In 16 of the 17 references, the button group and the legal line are pinned to the bottom safe area. Examples: [Duolingo](https://mobbin.com/screens/fb4eda98-538d-4bc0-9ef6-bf06ed401c12), [Pi](https://mobbin.com/screens/fa1be339-90a6-4871-ad50-a054b2c71107), [Alan](https://mobbin.com/screens/21080b03-a1f7-4113-8a57-b7dee60054d2), [Todoist](https://mobbin.com/screens/74ce39aa-af90-4223-9f23-879cda9e13e4), [ChatGPT](https://mobbin.com/screens/e3e09d6b-6600-4cc6-8242-8bb2574c8deb) and [Stardust](https://mobbin.com/screens/217034f9-33d8-4435-9444-f67f72bd447d).
- None of the 17 leaves empty space below the buttons.
- Duolingo, Pi and Alan are the closest analogues to Nina: a character mark or mascot, a name, one short line, and the actions under the thumb.
- The only reference that stacks everything from the top is an [older Notion capture](https://mobbin.com/screens/ef91694f-7bfa-4f3c-bba6-664654d59a7a). Its bottom ~40% is empty, and it reads as unfinished. Nina has exactly this problem today.

```
┌────────────────────────────────┐
│ (flexible spacer, min 32)      │
│            [cup 64]            │  NinaMark(size: 64)
│              Nina              │  .ninaText(.display), centered
│   A rotina da casa, dividida.  │  .ninaText(.label, muted), centered
│ (flexible spacer, min 32)      │
│ [    Continuar com a Apple   ] │  the system button, black, 52pt, [.fullName]
│        error line (if any)     │  .meta, ink, centered, 12pt gap
│ Ao continuar, você aceita os   │  .meta muted, centered, 14pt below
│ Termos e a Política de Priv.   │  links tinted
│ Menores de 18 anos entram…     │  protected age line
│             [ 14 ]             │  ClassIndMark() (22pt)
│ 16pt bottom inset              │
└────────────────────────────────┘
```

```swift
GeometryReader { proxy in
    ScrollView {
        VStack(spacing: 0) {
            Spacer(minLength: 32)
            brandBlock                    // VStack(spacing: 14), .multilineTextAlignment(.center)
            Spacer(minLength: 32)
            actionGroup                   // VStack(spacing: 12): Apple, error line
            legalFootnote.padding(.top, 14)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .frame(minHeight: proxy.size.height)
    }
    .scrollBounceBehavior(.basedOnSize)
}
.ninaScreenBackground()
```

The two equal spacers center the brand block in the space above the actions. On a 6.1-inch iPhone that puts it at about 38–40% of the safe-area height, slightly above the geometric center, which is where Duolingo and Alan sit. Drop `.padding(.top, 46)` and `.frame(maxWidth: 520)`: the app is iPhone-only.

**Rules**

- **L1.** Nothing sits below the legal line except the 16pt bottom inset.
- **L2.** The mark, title and tagline share one horizontal center.
  - If the text is ever left-aligned instead, it must sit directly on top of the buttons, as in [Brink](https://mobbin.com/screens/8dbbaa4b-6f0a-4631-9e58-5dd5aeec61b7). It never floats at the top.
- **L3.** The tagline is one line of 6 words or fewer.
  - The login screen never explains how the product works. That is the tour's job.
  - Only 4 of 16 references add a second line, and none explains the product.
- **L4.** One door, one button (build 11, 2026-10-04): the black system "Continuar com a Apple" (52pt), which asks Apple for the name alone and never the email (build 12, 2026-10-05; build 11 asked for neither), so Apple's own sheet carries the name row and the welcome adds no word about it; the age range is read after sign-in by the age step (M2). There is no cobalt control on the welcome. No other door; email, code and Google sign-in were removed on 2026-09-26.
  - Word count: Apple's system label is not counted, because the system draws it (§0 step 4 counts what the app writes). The welcome is 6 authored words without the legal line and 29 with it.
  - A Debug build adds one quiet row, "Teste 1 · Teste 2", under the Apple button for the local test accounts. It is compiled out of Release, so no budget here counts it.
- **L5.** Retired 2026-09-26: there is no email sheet.
- **L6.** Retired 2026-09-26: there is no code step.
- **L7. The legal footnote** is centered, in the `.meta` tier, 14pt under the last button, followed by the ClassInd mark at its 22pt default (Portaria MJSP 1.048 art. 50: the rating shows at login; the startup screen draws it in the same spot, and no other screen draws it). It appears on the welcome screen only. It carries the protected age line (§3 row 18), so it runs to 3–4 lines.
- **L8.** The error line sits inside the action group, centered, in alert red with its glyph (`NinaErrorNote`, since 2026-10-04), never terracotta. One state gets one sentence.

**Target strings**

| Where | Current | Target |
|---|---|---|
| Welcome title and tagline | "Sua amiga Nina" / "Conta pra ela o que pesa." (until 2026-09-29) | "Nina" / "A rotina da casa, dividida." Every age sees this screen, and the old tagline invited emotional unloading. |
| Invite variant | "Você foi convidado para uma casa." plus a subtitle | Title "Você tem um convite"; tagline "Quem convidou aprova sua entrada." The line is protected (§3). The new title is also gender-neutral. |
| Email and Google buttons | "Entrar com email", "Continuar com o Google" | None. Apple is the only door (2026-09-26). |
| Legal footnote | "Ao continuar, você aceita os Termos e a Política de Privacidade." | the same, plus "Menores de 18 anos entram numa casa com aprovação de um responsável." (§3 row 18) |
| Backend unavailable | "Configure o projeto Supabase…" plus the error line | Delete the footer sentence. `configurationMissing` becomes "Não deu para entrar agora. Tente mais tarde." (G20, 2026-10-15; it was "Não dá para…") |

### 2.2 Onboarding and the tour

**Rules**

- **O1. Six steps on one screen**: a greeting, the four tabs in the bar's order, then a close. The tour runs after the house exists and writes nothing. There is no paging swipe and no tap-anywhere advance.
- **O2. Nina speaks every line in the first person**: at most 2 sentences and 24 words, the name not counted, ending with a period.
- **O3. Every example sits on a grout tray under "Exemplo", answers no tap, and uses the live strings** ("Ainda não existe" and the disclaimer through `NinaProposalCopy`, "Lendo", "Sem dono", "Plante depois", the band titles, the category and the "Sementes" and "Compras" chip titles with their counts). Dates come from the live reader and formatter. When a live string or the live proposal card changes, the tour changes in the same commit.
- **O4. One progress indicator**: the tab-bar map under the button. No "N de M" on screen; VoiceOver hears "Etapa N de 6".
- **O5. One skip**, "Pular" at the top right ("Fechar" on replay), hidden on the close.
- **O6. The close is Nina's line plus one button**, "Começar" ("Fechar" on replay). No recap.
- **O7. "Demonstração" names the screen and "Exemplo" names each picture.** They are two facts (G2).
- **O8. An adult Apple gave no first name types it where the house first needs it** (build 11; a fallback since build 12): "Seu primeiro nome" with the placeholder "Como a casa chama você" (the minor path's words), under "Nome da casa" when creating, under "Link ou código" when joining, and above "Pedir para entrar" on the invite. No helper line, no separate screen. The create or join button stays disabled until it holds a name; a failed save reads "Não deu para salvar seu nome. Tente de novo." Since build 12 Sign in with Apple asks for the name, and an adult who shared a given name never sees the field (App Review 4.0 refuses asking for a name Apple could have shared); it shows only when Apple gave none, since the server's placeholder "Família" would otherwise become the member's name.
- **O9. House setup opens on a choice** (2026-10-15). "Primeiro, a casa." + "Se alguém da casa já usa a Nina, peça o convite." as one centred block, with two outline buttons of equal weight at the foot: "Criar uma casa" and "Tenho um convite". Neither is cobalt, and no keyboard opens until a path is chosen; then the path's field takes focus (§2.2's earlier rule still holds there). Each path keeps the other as its quiet alternate ("Tenho um convite" / "Criar uma casa"). A partner whose invite link was lost on the way to the App Store otherwise opened a second house, which its owner could leave only by handing it over or, since 2026-10-15, by deleting it. The house-name placeholder is "Nossa casa", never a real family's name.

**Target strings**

- **Header and controls:** "Demonstração"; "Pular" ("Fechar" on replay, spoken "Pular a demonstração" / "Fechar a demonstração"); "Continuar"; "Começar" ("Fechar" on replay); the tray legend "Exemplo".
- **Greeting:** "Oi, ‹nome›, eu sou a Nina. Vou mostrar as quatro abas em um minuto, só com exemplos." Without a name: "Oi, eu sou a Nina. Vou mostrar as quatro abas em um minuto, só com exemplos." On replay: "Oi de novo, ‹nome›. Vou mostrar as quatro abas em um minuto, só com exemplos." or "Oi de novo. Vou mostrar as quatro abas em um minuto, só com exemplos."
- **Nina**, by what the chat tab will show the person:
  - open: "Na minha aba, você me conta o que pesa, do jeito que vier. Eu leio e proponho o que fazer."
  - consent still to decide: "Na minha aba, você decide se eu posso ler. Depois me conta o que pesa e eu proponho o que fazer."
  - age not yet confirmed: "Na minha aba, quando a Apple confirmar sua idade, você me conta o que pesa e eu proponho o que fazer."
  - closed (blocked, parental controls, or no chat for this account): "Na minha aba, a conversa comigo não abre nesta conta. Tarefas, compras e a casa continuam com você." (the live gates' "continuam com você"). No example proposal is drawn, and the line sits centred on the screen.
- **Hoje:** "Em Hoje fica o dia da casa. O que atrasou vem primeiro, sem bronca."
- **Tarefas:** "Em Tarefas fica tudo por categoria, e as compras também. Semente é vontade sem data e nunca atrasa."
- **Casa:** "Em Casa ficam as pessoas, os pets e um retrato de quem carrega mais. É para conversar, não para cobrar." (three lines on a 402 pt phone, so the protected "não para cobrar" is never split)
- **Close:** "Pronto, agora é com você. Nada do que você viu entrou na sua casa."
- Every line is drawn through `OnboardingTour.drawnLine`: its last two words are joined by a no-break space, and so is every one-letter word and every "um", "na", "no", "de", "da", "do" and "eu" to the word after it, so no bubble ends on one word and no line ends on "O", "e", "é", "na" or a sentence's opening "Eu"; the greeting and the close also break between their sentences. "em" stays free, because binding it pushes the greeting's second sentence to three lines. VoiceOver reads the line as written.
- **Map hint** (VoiceOver): "Mostra esta aba na demonstração." It holds for the Nina item even when the chat is closed and no example is drawn. On the close a tap on the map opens that tab in the app, and the hint is "Abre esta aba."
- **"Começar" hint** (VoiceOver, first run only): "Abre a aba Nina." or "Abre a aba Hoje.", the tab the map's pill shows. A replay's "Fechar" has none.

### 2.3 Settings (`SettingsSheet` and the screens it pushes)

Evidence: 9 reference settings roots show about 77 rows, and none of them has a description line. Examples: [Things 3](https://mobbin.com/screens/fe872e1e-90a8-4409-a62f-8360b64d7080), [Todoist](https://mobbin.com/screens/f53e3dc7-132a-4915-af49-d0ba98e4136b), [Monzo](https://mobbin.com/flows/1fcc4f33-fb16-4296-b470-e04456be34ee), [BeReal](https://mobbin.com/screens/e49ad3ee-1913-46c7-8ae9-b22965472b05) and [Zesty](https://mobbin.com/screens/eb324653-f821-4ab3-8603-c4818ac0acd4). Nina's root today has 10 of 11 rows with a subtitle, about 140 words.

**Rules**

- **S1.** Every row follows G5. Only the account row has a second line: the email, when the account carries one (a build-11 account has none, and then the row is the name alone).
- **S2.** No intro sentence under any settings title.
- **S3.** A toggle may carry a second line of 6 words or fewer only when it grants consent over personal data. At most one per screen; in Nina that is the consent toggle only. Precedent: the [Monzo Privacy](https://mobbin.com/flows/78851f14-67db-4e4c-b282-cdbc14c926b0) consent toggle.
- **S4.** A row that cannot be tapped and has no value is not a row. Delete it, or turn it into a footer (this removes "O que some com o tempo").
- **S5.** "Sair da conta" and then "Apagar conta" are the last two items of the root. Deletion is never inside Privacy. Precedents: [Monzo](https://mobbin.com/flows/1fcc4f33-fb16-4296-b470-e04456be34ee) and [Rodeo](https://mobbin.com/flows/edf330b1-a6c0-4165-87ca-68df4b2ba46b).
- **S6.** The app version is a muted, centered footer under the exits ("Nina 1.0 (4)"), not a row.
- **S7.** Premium on the root is one row, as in [Telegram](https://mobbin.com/screens/d1dbed8c-9d7f-410e-943f-91d0268bb2de):
  - Free house: "Nina Premium" with a trailing price and a chevron.
  - Covered house: "Nina Premium" with a trailing "Ativo" and a chevron.
  - Benefits and renewal details live only on the Premium sheet.
- **S8.** A status card appears only when the person has to act (notifications denied by iOS). A healthy state shows nothing.
- **S9.** A destructive screen has noun lists of 3–5 words per item, one friction gate and one confirm button. No lead paragraph, and no second cancel button when a back control already exists.

**Target root** (owner, free house; about 42 words)

- Account row: name, and the email when the account carries one.
- `Nina Premium   R$ 24,90/mês ›`
- **Nina group**
  - `Avisos   Ligados|Desligados|Bloqueados ›`
  - `Resumo semanal [toggle]`. A member sees the value "Ligado" or "Desligado" instead; an uncovered house shows `Premium ›`.
  - `Privacidade e dados ›`
  - `Política de privacidade ↗`
- **Casa group**
  - `Nome da casa   ‹name› ›`
  - `Convidar alguém   5 vagas ›` (when full: "Casa cheia", disabled and dimmed)
  - A member instead sees `Seu acesso   Participante`.
  - An adult who is not the owner also sees `Sair da casa` (no chevron) at the end of the group. Alert: "Sair desta casa?" / "Suas tarefas ficam com a casa." / "Sair". `Haptics.warning()` arms it. A failure reads "Não deu para sair da casa agora. Tente de novo."
  - The owner (Titular) sees the same row; `Haptics.selection()` opens an alert that never strands them (2026-10-15). With another adult who has an account: "Antes, passe a casa." with "Em Casa, toque na pessoa, depois em Editar e em Passar a casa. Quando ela aceitar, você pode sair." (or "Esperando ‹nome› aceitar a casa. Depois disso, você pode sair." while an offer waits), and the buttons "Apagar a casa" and "Entendi". With nobody to receive the house: "Para sair, apague a casa." / "Só outro adulto com conta recebe a casa. Para passar, convide alguém primeiro." / "Apagar a casa" / "Cancelar". "Apagar a casa" opens the gate below; it deletes nothing by itself.
  - The titular alone also sees `Apagar a casa ›` (trash glyph, ink) as the last row of the group; `Haptics.lightImpact()` opens it. An admin never sees it: deleting erases every member's shared data, so it is the titular's alone (2026-10-15).
- **Ajuda group:** `Rever a demonstração` · `Dúvidas e suporte ›` · `Novidades ›` · `Termos de uso ↗` · `Denunciar um problema ›`
  - "Dúvidas e suporte" (2026-10-04) pushes a FAQ grouped under three eyebrows, each answer behind its question (G8: the screen the action opens), and ends with one card: "Ainda com dúvida?", the address, and the cobalt "Escrever para o suporte" (mail with the app and iOS versions, nothing from the house). The website's `/suporte/` shows the same answers (`web/src/support.ts`, held equal by `web/tests/support.test.ts`).
  - "Novidades" (2026-10-04) shows `NinaAnnouncementBoard.current`: the mark, the title "Novidades da Nina", then the eyebrows "Novo" and "Em breve", each item a 48pt glyph tile (cobalt on the wash for Novo, ink on grout for Em breve), a title of 5 words or fewer and one line of 10 words or fewer. The same board opens by itself once per board id as a sheet over the tabs, with one cobalt "Entendi", never over another sheet and never right after the tour. "Em breve" names only work that is planned; an item moves to "Novo" in the build that ships it, under a new board id. The 1.0 board (id `1.0`, 2026-10-15) holds only "Feito pelo aviso" and "Busca sem acento": no tester changelog entry, and no "Em breve", since photo reading is off at launch and App Review reads a promise as unfinished.
- `Sair da conta`. Alert: "Sair da conta?" / "Para entrar de novo, use sua conta Apple." / "Sair". `Haptics.warning()` arms it (2026-10-15): signing out takes the household off this phone. Every other "Sair da conta" (the age check, the majority and Terms gates, house setup, the pending, decision and unavailable screens) has no alert and answers with `Haptics.selection()`. A failed sign-out reads "Não deu para sair da conta agora. Tente de novo." above it.
- `Apagar conta` (in ink)
- Footer: `Nina 1.0 (4)`
- A failed "Nome da casa" or "Sair da casa" reads as an error note at the end of the Casa group, because the sync toast sits under the sheet.

The invite row's trailing "5 vagas" follows [Duolingo's "4 spots left"](https://mobbin.com/screens/fd3e8e2e-0b82-4e2f-8223-b410a3e325f9). `settingsSummary()` returns a single word. "Bloqueados" is ink or muted, never terracotta.

**Target sub-screens**

- **Privacidade**
  - Consent toggle: "Deixar a Nina ler", with the second line "Mensagens e fotos."
  - Footer under it: "Vale só para você. Cada adulto decide o seu."
  - Data rows: `Baixar meus dados ›` and `Apagar minha conversa`, with the footer "A conversa some sozinha depois de 30 dias."
  - The "Onde ficam os seus dados" card becomes one closing footer. Since 2026-09-29 it names the provider and the retention (§3 row 4): "Em São Paulo. Os seus registros ficam em servidores no Brasil. Se você aceitou conversar com a Nina, o que você escreve vai para a OpenAI, empresa dos Estados Unidos, que pode guardar por até 30 dias para evitar abuso. Quando outro adulto conversa com a Nina, suas tarefas podem ir junto, com seu nome trocado por um código."
  - The row "Denunciar um problema" (every age) opens the report page: "Algo na Nina fere uma criança ou um adolescente? Conte para nós.", the protected "A denúncia não é anônima: ela sai do seu email.", the button "Escrever denúncia" (mail, subject "Denúncia ECA Digital", no household data) and the link "Como tratamos denúncias".
  - "Apagar minha conversa" alert: title "Apagar sua conversa?", message "Tarefas e memórias confirmadas ficam."
- **Apagar a casa** (2026-10-15; the titular only, an adult today)
  - Title "Apagar a casa". Eyebrow "Some para todos": "Tarefas, sementes e compras", "Memórias, compartilhadas e privadas", "Conversas com a Nina", "Perfis de crianças e pets", "O convite e os pedidos", "O acesso de todos".
  - Eyebrow "Fica" (grout card): "Sua conta", "A conta de cada adulto", and, when the house holds a child's or teen's account, "Contas de menores, por 30 dias".
  - The titular's own active subscription adds the account-deletion card with "Apagar a casa" in place of "Apagar a conta": "Sua assinatura continua." / "Apagar a casa não cancela a cobrança. A Apple segue cobrando até você cancelar." / quiet "Gerenciar assinatura". A house covered by someone else's subscription reads "A assinatura continua." / "Apagar a casa não cancela a cobrança de quem assina." with no button (§3 row 21: only the subscriber manages it).
  - The typed gate is the house's name: "Escreva ‹nome da casa› para confirmar". Case and accents never decide; every letter does. The ink "Apagar a casa" button arms with `Haptics.warning()` and opens "Apagar a casa?" / "Some para todos da casa. Não dá para desfazer." / "Apagar". No haptic on the confirm.
  - A failure is one error note above the ink button: "Só quem é titular apaga a casa.", "O nome da casa mudou. Confira e escreva de novo." (the house was renamed meanwhile; the phone reloads it first), "A resposta não chegou. Tente de novo." (a dropped connection or a gateway 5xx, which may come after the house was deleted; the next read of the house (the retry, a pull, a return to the app) then finds it gone and lands on "Casa apagada.", never on "Você não faz mais parte desta casa.") or "Não deu para apagar a casa agora. Tente de novo." (only for an answer that arrived, or a request never sent). Like account deletion, nothing here claims the house is intact unless an answer proves it.
  - Afterwards the titular lands on house setup ("Primeiro, a casa.") with the moss "Casa apagada." under the two buttons. Everyone else meets the decision screen on their next load (§2.8).
- **Avisos**
  - Delete the intro sentence.
  - Show the status card only when iOS has denied notifications: "O iPhone bloqueou os avisos." with the button "Abrir Ajustes do iPhone".
  - Toggle "Avisos", with the footer "Tarefas urgentes ganham um segundo aviso uma hora depois."
  - "Silenciar à noite" loses its subtitle, because the Começa and Termina rows already show the hours. Its footer becomes "No silêncio, o aviso chega na hora, sem som." (protected).
- **Apagar conta**
  - Eyebrow "Some para sempre": "Sua conversa com a Nina", "Suas memórias privadas", "Seu perfil e sua foto", "Seu acesso a ‹casa›".
  - Eyebrow "Fica na casa": "Tarefas que você criou, sem dono", "Compras", "Memórias compartilhadas".
  - Keep the typed gate and the ink "Apagar conta" button. Delete "Deixa pra lá".
  - An active subscriber first sees one grout card: "Sua assinatura continua." / "Apagar a conta não cancela a cobrança. A Apple segue cobrando até você cancelar." / quiet "Gerenciar assinatura" (§3 row 6; build-10 fix b).
  - The same screen is reachable with no house: from house setup, the pending and decision screens, the unavailable screen and every minor state.
  - Alert: title "Apagar sua conta?", message "Não dá para desfazer." Keep `Haptics.warning()` when arming it.
  - A failure is one card above the ink button, one line each (build 11); since 2026-10-04 the card is the alert wash with the red glyph and red line, except "A Apple não confirmou." (the person cancelled Apple's sheet), which stays grout and ink: "A Apple não confirmou. Nada foi apagado." (Apple sheet cancelled, nothing sent), "Sem internet. Nada foi apagado." (the phone had no network path before sending), "A resposta não chegou. Tente de novo." (a dropped connection or a gateway 5xx, which may come after the deletion ran), "Não deu para apagar agora. Tente em alguns minutos.", "Sua sessão terminou. Saia e entre de novo para apagar.", "A conta pode já ter sido apagada." (a signed-out reply right after an answer that never arrived; it never points to sign-in, which would open a new account), "Você não é mais responsável por esta conta." (a guardian whose link ended) and "Não deu para apagar por aqui. Nada foi apagado." (a refusal). "Nada foi apagado" appears only where it is provable: nothing was sent, or a refusal came before any stage ran. A refusal, an ended session, or the second failure in a row (a cancelled Apple sheet counts) adds the muted "Para apagar mesmo assim, escreva para ‹email de privacidade›." ("Para confirmar, escreva para ‹email de privacidade›." after "A conta pode já ter sido apagada.", with a quiet "Sair") and a quiet "Escrever" (mail with the subject "Apagar minha conta" and "Referência: ‹id›", or "Apagar a conta de um menor" with the ward's reference and the guardian's own "Responsável: ‹id›"). VoiceOver hears the line and the mail line together. Never terracotta.

### 2.4 Lists and empty states (Hoje, Tarefas, Sementes, Compras, Memórias)

**Rules**

- **E1. Headers** follow G1. Hoje keeps its date or greeting line. Tarefas drops the subtitle on every filter.
- **E2. Empty states** follow G12.
  - When the screen has a persistent + button, it stays visible in the empty state too, and it is the manual path.
  - Never stack a second "sem a Nina" button.
  - Any button inside the empty state is quiet or outline, so the + stays the screen's one cobalt control.
  - Precedent: [Attio](https://mobbin.com/screens/be0471bf-0192-4057-b23f-ba463960aa30).
- **E3. A celebration** is one headline plus one line.
- **E4. Section headers** are `LABEL · N` plus a chevron.
  - Never print the collapsed state as a word ("recolhida").
  - Never repeat the tab's own name as a header ("HOJE · N" inside Hoje).
  - Precedent: [Attio groups](https://mobbin.com/flows/4f835cbe-869a-45c1-9efe-9fb588b59081).
- **E5. Each number appears once.** Either the stat tiles or the chips carry the counts, not both. If the tiles stay, they become the filter.
- **E6. An action next to a counted header is one verb.** The count stays in the header. Precedent: [Todoist "Overdue 4 · Reschedule"](https://mobbin.com/flows/0a060d26-a86f-4c9c-9216-05518cd1f207).
- **E7. No permanent explanatory card under a populated list** (G8).
- **E8. A no-results state** has a headline of 4 words or fewer, a hint of 3 words or fewer, and one exit the screen does not already have.
- **E9. A footnote that describes behavior must be true.** Delete the "últimos 30 dias" note under "CONCLUÍDAS HOJE": that group only ever holds today's completions.
- **E10. Rows (`TaskRowView`) stay as they are.** They already match every reference. One refinement (2026-10-04): a title that does not fit on one line beside its date takes the full width, up to three lines, and the date, glyph and owner drop under it, the layout accessibility sizes already used, so a title is never cut to "esc…".

**Target strings**

| Where | Target |
|---|---|
| Hoje, first day | "A casa começa vazia." + "Conta pra Nina o que está pesando." + quiet "Conversar com a Nina", with the + visible. Delete "Escrever sem a Nina". |
| Hoje, day cleared | "Acabou o dia da casa." + "Pode largar o celular." The next-up eyebrow changes from "Amanhã cedo" to "Próxima". |
| Hoje, tomorrow (2026-10-05) | Under today's list, a folded group "AMANHÃ · N" with a chevron, closed by default, listing tomorrow's open tasks in `TaskListOrder`. It never shows when the day is cleared, where "Próxima" already points ahead. |
| Filter empty | "Nada com você." · "Tudo tem dono." · "Nenhuma semente." · "Nada em aberto." |
| Overdue | Header "ATRASADAS · N", action "Remarcar". Alert: title "Remarcar para amanhã, 09:00?", message "Nada é apagado.", button "Remarcar". |
| Tarefas, first use | "Nada combinado ainda." + "Conta pra Nina. Ela propõe, você confirma." + one button. The + is visible. |
| Sementes, empty | "Semente é vontade sem data." + the example card + "Nova semente" |
| Sementes, populated | At most a dismissible "Semente não vira atraso." with "Entendi" |
| Compras | Empty: "Nada faltando." + "O que acabar em casa aparece aqui." The inline field "Adicionar item" sits above the list (since 2026-10-04): return adds the item to the top and keeps the keyboard up; its trailing control opens the full sheet for quantity and owner ("Adicionar com quantidade e dono"). Clear button: "Limpar comprados". Alert: "Limpar comprados?" / "Some da lista para todo mundo da casa." |
| Search, no results | "Nada com esse nome." + "Tenta outra palavra." + one chip, "Conversar com a Nina" |
| Memórias, empty | "A Nina propõe guardar. Memórias começam privadas." |
| Memórias, a card (2026-10-14) | The reading row is "Editar" and, for a private memory, "Compartilhar com a casa" (protected, §3 row 9, never shortened). Deleting a memory lives in the edit row: "Salvar", "Cancelar", then the trash glyph ("Apagar memória"). Both rows stack rather than wrap (G19). |

### 2.5 Chat and proposal cards (`NinaChatView`)

**Rules**

- **C1. The empty chat has one intro.**
  - A headline of 6 words or fewer and a subline of 5 words or fewer, centered vertically between the header and the composer.
  - The seeded greeting bubble is never shown while the capture prompt is.
  - Precedents: [Claude](https://mobbin.com/screens/2f4b2424-da04-4326-8bc4-a01e30724ebb) and [Perplexity](https://mobbin.com/screens/f1fbcc17-9ce6-48bb-b9f4-a8a7db2f27c3).
  - Counter-example: [Lloyds](https://mobbin.com/screens/8c352ab6-c8a5-4f48-9d20-cc6f5ff0a618), whose first bubble runs about 45 words.
- **C2. Example chips.**
  - At most 3 chips, of 5 words or fewer each.
  - One horizontal row, directly above the composer, hidden after the first message.
  - Never name a person or pet who is not in the house (this drops "Téo").
  - Precedent: [Cash App](https://mobbin.com/screens/56ff5f1d-e0ad-4657-90e3-ab6ba37081e2).
- **C3. The composer placeholder** is 4 words or fewer ("Escreva pra Nina" passes).
- **C4. Attaching uses one unlabeled + icon.**
  - Its accessibility label is "Anexar foto ou documento". It opens a menu with "Foto" and "Documento".
  - In a free house, it opens the gate instead: "Foto e documento são do Premium." with the button "Ver o Premium".
  - A failed or refused attachment ("Não deu para carregar uma das fotos agora. Tente de novo.", "Você pode enviar até 3 anexos por mensagem.") is an error note above the composer. Attachments dropped because the house lost Premium leave the grout line "Foto e documento são do Premium." (G20).
  - No permanent chip row.
  - Precedent: [Perplexity](https://mobbin.com/screens/7248785b-ef14-4bc8-86ac-6f657fa9e6db).
- **C5. Photo previews.**
  - A draft photo previews as a thumbnail with an X, with no filename or size. Only documents show a name and size.
  - The draft footer is the protected line "A Nina não guarda a foto. A OpenAI pode guardar por até 30 dias para evitar abuso." (§3 row 12; the old "A foto não fica guardada em servidor nenhum." was untrue).
- **C6. "Not yet confirmed" is said once per card, and the disclaimer once per screen.**
  - The card carries one pending tag of 3 words or fewer: "Ainda não existe" (a memory uses "Ainda não guardada").
  - The disclaimer is one faint line under the newest Nina reply that has a pending proposal: "A Nina pode ler errado. Nada entra sem você confirmar."
  - Delete `waitingLine` and the composer footer.
  - The research suggested the one-word tag "Proposta". It is not used here, because the pending statement is protected (§3) and the tour mirrors it.
  - Precedent: [Claude's single disclaimer](https://mobbin.com/screens/ed3e4d7f-e3e5-44e8-a0ad-649a958ce5fa).
- **C7. Card anatomy: the tag, the title, then one meta line of glyph + value pairs** (date · owner · quantity).
  - No label column ("Quando" / "Repete" / "Dono").
  - The date and owner stay on the card face.
  - Show recurrence only when the proposal actually repeats; never print "Não repete".
  - Undated shows "Sem data". A semente shows "Plante depois".
  - Precedents: [Structured](https://mobbin.com/flows/a7568c34-288d-4384-8165-530ec3e2e766) and [Me+](https://mobbin.com/flows/9dfe5bb4-1d31-44ed-bc03-e9414180b8df).
- **C8. Buttons.**
  - At most 3 actions per card, each of 1–2 words: "Criar tarefa", "Corrigir", "Não".
  - The memory card is the one exception, because the two separate taps are a product invariant: "Guardar para mim", "Compartilhar com a casa", "Corrigir", "Não".
- **C9. At most one secondary line under the title**, either the detail or the rationale.
  - In the "O que eu li" block, delete "Corrija se eu tiver lido errado."
  - The bill note becomes the protected line "Para pagar, abra o boleto no banco."
- **C10. An irreversible-action warning appears once, in the confirm alert only.**
  - Memory share alert: title "Compartilhar com a casa?", message "‹Nome› vai poder ler. Não dá para desfazer."
  - Variants: "Quem entrar vai poder ler. Não dá para desfazer." and "Os outros adultos vão poder ler. Não dá para desfazer."
- **C11. Notices are one line attached to the top of the composer**, 8 words or fewer, with at most one action. They are not cards in the thread. Precedent: [Claude's limit strip](https://mobbin.com/screens/e4c51fae-e8b6-4e42-8a4c-23d1ec12b06a).
  - A turn Nina never answered is a failure, not a notice (2026-10-15): no Nina reply, the person's words back in the composer, and an error note above it (G20): "Sem conexão. Tente de novo." only when the request found no network, otherwise "Não deu para a Nina responder agora. Tente de novo.". "Sem conexão. Esta resposta veio do aparelho." is gone with the on-device engine that wrote it.
  - "Modo local. Nada sai deste aparelho."
  - A refusal the server stored nothing of never reads as Nina's line (2026-10-15): the thread gets no line for the refused turn, the person's words and attachments go back to the composer, and the notice stays through any refresh until a turn is answered. No refusal adds a line in Nina's name, refused content included: its line becomes "Mensagem não enviada.", the words never come back, and the error note reads "A Nina não pode ajudar com esse conteúdo. Se houver risco imediato para alguém, procure uma pessoa de confiança ou o serviço de emergência." (third person, a refusal that names its reason under G20, with the server's safety pointer kept whole); it also ends any held notice, because moderation runs only after every ceiling let the turn through.
  - "Ler foto e documento é do Premium." with the action "Ver o Premium", for an account that may buy in a house that is not covered; otherwise "Foto e documento são do Premium." with no action.
  - "Limite de mensagens. No Premium, 50 por dia." with the action "Ver o Premium", on the same condition; otherwise (a covered house at its limit, or an account that may not buy) "Limite de mensagens. Anote pelo + em Hoje." with no action. Either ends when the house becomes covered.
  - "Conversa pausada. Anote pelo + em Hoje." after the shared budget pauses the chat, with no action: no purchase lifts it.
  - A message too large is a failure, not a notice: the error note "Essa mensagem ou anexo é grande demais para a Nina." (third person, like "A Nina ainda está lendo essa mensagem. Espere um instante.").
  - The withheld-proposals notice becomes "Confirmação ainda fechada nesta versão. Nada entrou na casa."
- **C12. The typing indicator** is the mark in `.reading` presence, plus "Lendo" or no text at all.
- **C13. Date correction hints.**
  - Parsed: "Vai ficar: sex, 18:00."
  - Empty: "Vai ficar sem data."
  - Unparseable: "Não entendi a data. Tente "amanhã 18:00"."
- **C14. The gates** have a headline, at most 4 lines of 10 words or fewer, one button, one footnote and one link. No closing paragraph.
  - Every gate draws the chat header (wordmark and gear), so the Nina tab always reaches Ajustes (2026-10-15).
  - Adult-only gate: "A conversa é dos adultos da casa." + "Tarefas e compras continuam com você."
  - Declared adult the age policy keeps from the AI: "A conversa pede idade confirmada." + "A Apple ainda não confirmou sua idade. O resto funciona." + "Tentar de novo". Since D3 (2026-10-14) production admits self-declared adults, so this gate shows only while `trusted_assurances` leaves out `self_declared` (before the operator statement, or after a revert).
  - Adult with active parental controls: "A conversa não abre nesta conta." + "Esta conta tem controles parentais ativos. O resto funciona." + "Tentar de novo" (a share after the controls are lifted opens the chat), with no line about Apple's confirmation. Its Premium sheet reads "O Premium não abre nesta conta." + the same line. Build 12 still shows them the declared-adult gate and "Isso pede idade confirmada pela Apple.", which is untrue for them, until the next build ships.
  - Blocked account: "A conversa está suspensa nesta conta." + "Se for engano, escreva para ‹email de privacidade›."
  - Consent gate: see §3 row 3. It is exempt from the line limits, because every line is Law-text-gated.
- **C15. "Denunciar resposta"** is a context-menu item on every Nina reply. The sheet has four chips ("Conteúdo impróprio", "Risco para alguém", "Saúde ou remédio", "Outro") and "Enviar"; the confirmation is "Recebido. Vamos olhar."

- **C17. A card that repeats something still open says so** (2026-10-05): a grout capsule with `doc.on.doc` and "Já existe na casa." when an open task, reminder or semente (or, for a shopping card, an unbought item) has the same title, accents and case folded. It flags and never blocks: confirming a second one stays the person's call.
- **C16. Cards waiting in older turns are counted above the thread** (2026-10-05). A floating capsule at the top of the conversation, an up arrow and "N propostas esperando" ("1 proposta esperando"), jumps to the oldest turn that still has a pending card. The newest turn never counts, because its cards are already on screen; resolved cards never count. It is the one way back to a proposal left behind, short of an Inbox.

**Target empty chat:** "Jogue uma lembrança aqui." + "Eu proponho. Você confirma." Chips: "Acabou o café" · "Autorização da escola até sexta" · "Um dia, pintar a sala".

### 2.6 Cards, sheets and alerts (capture sheet, task detail, invite sheet, permission prompts)

**Rules**

- **K1. Capture sheets have no explanatory sentence.**
  - No helper line under the Tarefa/Semente switch. The "Sem data" chip already carries what a semente is.
  - Delete the plant-mode hint.
  - Precedents: [Todoist quick add](https://mobbin.com/screens/2fef17d9-49dd-4cb7-974b-594bb7b736e6), [Reminders](https://mobbin.com/screens/38267c18-dcc0-4510-93be-36b7060dcbd6) and [Superlist](https://mobbin.com/screens/63f4bc4a-8939-4d48-ab69-6aa499dab4fc).
- **K2. Every chip leads with a glyph.**
  - Attributes left at their default are glyph-only, with accessibility labels "Repetição", "Aviso" and "Prioridade". Once set, they gain 1–2 words ("Semanal", "1 hora antes", "Alta").
  - The owner chip always shows words ("Sem dono" or the person's name).
  - This removes "Ninguém ainda", "Não repete", "Na hora", "Prioridade normal" and the "Mais" chip.
- **K3. Captions and commit button.**
  - The note placeholder is one word: "Nota".
  - The date panel loses its "Quando" label.
  - Commit is one verb, because the header already names the object: "Criar", "Salvar" or "Plantar".
- **K4. Keep the capture-sheet structure.** The title field comes first and is focused on appear (with `Task.yield()`). Classification comes after the title.
  - The sheet fits its content (2026-10-14). The chips and the commit sit directly under the fields and ride the keyboard, the Todoist, TickTick, Things 3 and Toggl shape; nothing opens a gap between the last field and the chips.
  - The date and category panels open at the end of the fields, directly above the chips, and the card grows by them.
  - A sheet holding typed input does not close on a swipe or a tap above the card; the close button discards it. Nothing is added to say so.
- **K5. A permission prompt inside a sheet is one chip at the end of the chip row.**
  - Not yet asked: "Ativar avisos", which requests permission.
  - Denied: "Avisos bloqueados", which opens iPhone Ajustes.
  - The same chip (`NotificationPermissionChip`) sits under a dated proposal card's meta line (2026-10-15). Under Hoje's header only "Ativar avisos" shows, while iOS has not been asked, "Avisos" is on and the house has open dated tasks: a refusal is never a standing chip on the main screen.
  - iOS's own prompt comes right after the first dated task or reminder this phone confirms, and on a minor's first visit to their tasks, with no line before it (§0 step 3); never at launch.
  - Both use the `bell.slash` glyph.
- **K6. Delete action.** The button reads "Apagar". Alert: title "Apagar esta tarefa?", message "Some para toda a casa. Não dá para desfazer."
  - In an editor, the quiet "Apagar" sits in the commit row opposite the commit, in edit mode only (never while adding or planting). VoiceOver reads the commit first.
  - At accessibility sizes it ends the field column instead, so it never squeezes the commit.
- **K7. Invite sheet.**
  - The protected line appears once: "Quem abrir o link pede para entrar. Alguém da casa aprova."
  - The four fact rows collapse into one data line: "Vale até 30 de set. · 5 usos restantes".
  - "Renovar o link" becomes a quiet text button. A failed renewal buzzes once, from the store (2026-10-15; Casa's row used to buzz a second time).
  - The shared message names the house after a colon, with no article before it, and keeps the request honest: "‹Nome› quer dividir a casa com você na Nina: ‹casa›. Tocar no link só pede entrada. Alguém da casa ainda precisa aprovar." ("a ‹casa›" broke on names like "Lar dos Prado".)
  - Precedent: [Life360 invite code](https://mobbin.com/screens/a3589921-f6d4-468d-a702-70c2ee835d44).
- **K8. The invite screen** (`InviteAcceptanceView`, 2026-10-15). Under "Pedir para entrar", the second outline button is "Criar uma casa" for someone with no house, and it opens house setup on the create path; for someone already in a house, or waiting on one, it is "Agora não", which only sets the invite aside. A failure is an error note above the buttons.

### 2.7 Paywall and premium management (`PremiumBenefitsSheet`)

**Rules**

- **P1. The paywall contains:**
  - the title
  - comparison rows of 4 words or fewer
  - the billed price printed on each plan option
  - one line of renewal and cancellation terms
  - one CTA
  - one link row: "Restaurar · Termos · Privacidade"
  - Nothing else: no subtitle, no trust card, no second disclosure. Precedents: [Structured](https://mobbin.com/screens/164379e9-258f-4b6c-9f91-7a02a3f4c277), [Liven](https://mobbin.com/screens/a612cffd-939d-471f-9b89-bf734058ab1a), [Givingli](https://mobbin.com/screens/39d7f4f0-e7e9-4777-b85c-cd3358b438b1) and [Duolingo](https://mobbin.com/flows/c71bfa5f-5cc4-427a-8635-36668bad5963).
  - Counter-example: [Jomo](https://mobbin.com/screens/355c903b-4580-4f82-bd8f-0c46195fa434), with trust paragraphs above the CTA.
- **P2. The billed amount is the prominent price on each option**: "Mensal · R$ 24,90/mês", "Anual · R$ 249,90/ano". A monthly equivalent or "-16%" may appear, but smaller. Apple reviews for this.
- **P3. One terms line, matching the selected plan**: "R$ 249,90 por ano. Renova sozinho. Cancele quando quiser na App Store." Precedent: [Lifesum's one-line terms](https://mobbin.com/screens/8b62f92e-5ada-4dc4-89f1-70a82820887e).
- **P4. Delete** "Três limites reais somem. É só isso.", the "O que o Premium não muda" card (in both states), and the separate big price above the button.
  - The ceiling note becomes "Teto da casa: 100 conversas por dia." (protected).
  - The CTA becomes "Assinar". "Premium" appears on screen at most twice.
  - Show the "Fotos de documentos" row only when `NinaAttachmentGate` is on.
  - "Resumo semanal" carries one `.meta` line under its title, "Quando 2 adultos aceitarem conversar com a Nina." (CDC art. 31: the condition is stated where the benefit is sold, as a condition and never as a fact already met).
  - Plans that do not load read "Não deu para carregar os planos agora." as an error note with a quiet "Tentar de novo" under it (2026-10-15; it was a grout card saying "Tente mais tarde." with no way to retry, and sandbox loads fail often during review).
- **P5. The management state has a title, the plan, price and renewal rows, and one "Gerenciar na App Store" button.**
  - Show a "Situação" row only when the status differs from what the title says (grace period, expired, revoked).
  - No purchase disclosure, because nothing is being sold.
  - Precedent: [Duolingo "Current plan"](https://mobbin.com/flows/8127cf41-d878-4028-bd38-ed7621a4873b).

**Target covered state:**

- Title "Premium ativo na casa" + "Vale para a casa toda." + the Plano, Preço and Renovação rows + "Gerenciar na App Store".
- When another adult subscribed, the footer reads "Só quem assina muda o plano."
- The value while the purchase is being recorded reads "Registrando na casa".
- The moss activation moment and its single "Pronto" button stay.

### 2.8 Casa (`HouseView`, member screens, `WorkloadView`)

Since 2026-09-29 a claimed minor's row reads "Acesso limitado" and an account-less child or teen without a guardian's consent reads "Sem autorização" (G3 values; never the band). The member editor's role chips are "Adulto · Adolescente · Criança · Pet"; "Adulto" shows "Adultos entram por convite." and "Convidar", and a viewer who is not a trusted adult sees the two minor chips disabled with the helper "Só um responsável com idade confirmada pela Apple cadastra." (G6: it prevents an error with a legal consequence). A self-declared adult without parental controls also reads "Confirmada é a idade que a Apple verificou, não só a declarada." and a quiet "Tentar de novo" (M2's inline share), there, on a legacy child's card and on a minor's join request under "Isso pede idade confirmada pela Apple." (2026-10-15).

A house that was deleted (2026-10-15) is told on the decision screen as "Essa casa foi apagada." with "Tudo o que estava nela foi junto, memórias privadas também." for someone who lived there (each adult's private memories go with the house, and a list that left them out read as if they survived), or "Seu pedido de entrada não vale mais." for someone still waiting; never "As tarefas e as listas ficam com a casa.", which is the removal line and would be false. The titular's acceptance card reads "Como titular, você cuida de convites, permissões e ajustes. Para sair depois, passe a casa ou apague a casa." Casa, Hoje and Tarefas reload on a pull, through the same verified load a return to the app takes.

**Rules**

- **H1. Member rows** are an avatar, a name and one line of data: the role, "Criança" or "Pet". Never a sentence. Precedents: [Greenlight Family](https://mobbin.com/screens/5a8be526-2a1c-4402-9666-fec75183726b) and [Life360](https://mobbin.com/screens/4af1acb5-fbf9-4dd7-832f-d7795f1d5f14).
- **H2. Capacity is a count**: "2 de 8 pessoas e pets" (2026-10-15: a pet takes a slot, Nina does not; the limit lines say "8 pessoas e pets" too). Delete the separate "casa cheia" sentence.
- **H3. Each invariant is stated once, on the surface where it matters, in 12 words or fewer.**
  - "Não ocupa vaga." appears on Nina's row only.
  - "Não usa o app" appears in the add-profile sheet only. "Adicionar criança ou pet" has no subtitle.
  - The invite approval line appears in the invite sheet only.
- **H4. Actions on the Casa screen are rows, not cards.**
  - "Convidar alguém ›" joins the member list. Precedent: [Splitwise group](https://mobbin.com/screens/f0e6077c-afdf-4cc9-9993-c38a65ef982d); its toggle-description block below is the counter-example.
  - A premium-gated item is one row: a lock glyph, the title, a "Premium" tag and a chevron. Example: "Resumo semanal". The tag never breaks mid-word: at accessibility sizes it becomes the row's second line, as Perfil's "Memórias" count does, the chevron stays for a person who may buy, and the row keeps 14 pt above and below (2026-10-15).
  - In a covered house the row carries "Chega quando 2 adultos aceitarem conversar com a Nina." (2026-10-15; the server writes no digest for a house with fewer than two adults who accepted, so the row names the condition the summary waits on, never a date).
- **H5. The solo portrait** is the eyebrow "Sinal de sobrecarga", the title "Aparece quando outro adulto entrar na casa." (no article: a single parent has no "o outro adulto"), and the button "Convidar". Delete `aloneReassurance`. It shows while the house has one adult, however many children or pets live there: only adults carry load in the portrait (2026-10-15).
- **H6. The portrait title never equals the eyebrow.**
  - The unbalanced headline "Sinal de sobrecarga" becomes "Pesando de um lado". Update `HouseholdWorkloadTests.swift:40` deliberately.
  - "A casa está parecida" and "Ainda sem retrato da casa" stay.
- **H7. `WorkloadView`.**
  - Structure: the headline, the bars, and one caption: "Só o que está aberto e tem dono. Para conversar, não para cobrar." The caption stays gated on `snapshot.isConclusive`.
  - Put "Sementes não entram. Não é histórico, é hoje." behind an (i). Precedent: [Splitwise stats](https://mobbin.com/screens/f77b2738-8716-4219-932f-3e9080cbbd2c).
  - Unbalanced message: "‹Nome› está com a parte mais pesada agora." A balanced house has no message.
  - Inconclusive message: "Preciso de \(minimumAssignedSample) tarefas com dono, entre \(minimumCarriers) adultos." Keep the interpolated constants.
  - The shared row label becomes "Sem dono".
- **H8. The child's day** (`ChildTodaySection` on a child's member screen, `ChildDayView`, the printed page and the shared picture and PDF).
  - A child's surface never shows lateness: no terracotta, no "atrasada", no date. An hour shows only for something that happens today.
  - Never an article before the child's name: a child's gender is unknown, so write "Mostrar para Ana", never "a Ana".
  - The child's name is the first word of the profile name, unless another person in the house has a name that starts the same way (Maria Clara and Maria Eduarda, or a father João and a son João Pedro). Then it is the shortest run of leading words nobody else's name starts with ("Maria Clara", "João Pedro"), so two printouts or two WhatsApp lists never carry the same name. Nina's own row does not count.
  - Member screen: the eyebrow "Hoje · N" (rendered "HOJE · 3"), or "Hoje" alone when empty; the group-empty line "Nada para hoje." (G12); the buttons "Mostrar para ‹Nome›", "Imprimir" and "Compartilhar"; on a failed print, "Não deu para imprimir agora."
  - Child's screen: the date eyebrow ("sexta-feira, 25 de setembro", rendered uppercase), then the child's name as the title, by the namesake rule above (G1: both are live data). "Segure para sair" is an allowed instruction, an exception to G4, because a non-standard gesture needs its label; its accessibility label is "Sair". A done card's accessibility value is "Feita".
  - The celebration follows E3: "Tudo feito por hoje." + "Pode devolver o celular.", below the cards, mirroring Hoje's "Nada mais para hoje." / "Pode largar o celular." VoiceOver announces "Tudo feito por hoje." An empty list reads "Nada para hoje." + "Pode devolver o celular."
  - Print: the date line uppercased, the child's name, and the pager "1 de 2" in `muted` only when there is more than one page. The print job is named "‹Nome› · ‹data›".
  - Share (since 2026-10-04, replacing the plain-text share): "Compartilhar" opens a menu with "Imagem" and "PDF". The picture is `ChildDayShareCard`: a band of azulejo tiles, the date line uppercased, the child's name in Fraunces, one stroked card per task (an empty circle to tick, the title, the hour only when today, the category glyph in cobalt) and the mark, 1170 px wide, at least 4:5, taller as the list grows. The PDF is the printed A4 page. Both files are named "‹Nome› · ‹data›". No owner, no category word, no emoji, no detail line.
- **H9. "O que a Nina lembra" on a child's or pet's member screen** is read-only and built on the phone. The add and edit sheets ask no note for a child or pet; an adult's screen keeps the typed note.
  - Structure: the eyebrow, then up to 3 memory lines (each memory's title, newest first, never its body), then up to 3 routine lines, "‹título› · ‹ritmo›".
  - Rhythm values (D): "todos os dias, 07:00" · "toda terça, 18:00" · "todo sábado, 09:30" · "todo mês, dia 5" · "todo ano, 12 de março". Without a date, the recurrence title in lowercase: "toda semana", and so on.
  - A memory only this adult can read ends in a lock glyph, with the accessibility value "Só você vê" (G16).
  - Empty: one muted line, "A Nina aprende sobre ‹Nome› nas conversas." It is an allowed X string, an exception to G12's 4-word group line, because an empty card would otherwise read as a field to fill. It has no mark and no action.
  - Names: the name follows H8's namesake rule, except that Nina's own row counts. There is never an article before the name, and never a task's detail line.

### 2.9 Age, minors and guardians (`AgeCheckView`, `MinorViews`, `GuardianViews`)

Every screen here can be seen by someone under 18, so G17's minor exception applies, and most lines are Law-text-gated (§3). Nothing on a minor's surface shows lateness, a task's detail line, another person's work, a price or a chat.

**Rules**

- **M1. Each blocked state is one G12 block.** No house: "Peça o convite da sua casa." / "Quem cuida de você aprova sua entrada." Unknown age: "Falta sua faixa de idade." / "Sem ela, só um responsável aprova sua entrada." / "Compartilhar faixa". Sent: "Pedido enviado." / "Um responsável seu na casa precisa aprovar." Limit: "Por hoje é só." / "Seus avisos continuam chegando." ("Volte amanhã." when the guardian turned alerts off or iOS does not allow them, since the other line would be false) No guardian: "Sua conta está pausada." / "Falta um responsável na casa." Removed: "Você saiu da casa." / "Sua conta é apagada em 30 dias." / "Apagar agora". A deleted house (2026-10-15) keeps the removed lines under the headline "A casa foi apagada.".
- **M2. The age check** is "Antes, sua faixa de idade." + the protected Apple line + "Continuar", with the quiet "Sair da conta" and "Apagar conta" at the foot (since build 11 it is the first screen after sign-in, so it leaves a way out, §3 row 6). Its declined, Apple-error and App Attest states each have one headline, one line, a retry and a quiet "Continuar assim", over the same two exits. Never name the Settings path until the pt-BR labels are read on a device. A share started from a button inside the app ("Tentar de novo", "Compartilhar faixa", "Compartilhar de novo") never replaces the screen: the button shows pending, then one line under it, "Faixa atualizada.", "A faixa não foi compartilhada.", "A Apple não respondeu agora. Tente de novo em instantes.", "Não deu para confirmar este iPhone." or "Não deu para atualizar sua idade."
- **M2a. The majority and changed-Terms gates** are one title, one line, "Aceitar", then the quiet "Ler os Termos", "Sair da conta" and "Apagar conta" (a gate always leaves a way out, §3 row 6). Majority: "Agora a conta é sua." / "A Apple informou que você tem 18 anos ou mais." / "‹responsável› não acompanha mais sua conta." Changed Terms, for a restored session that never saw the current version: "Os Termos mudaram." / "Para continuar, leia e aceite a nova versão." When this phone's welcome footnote was accepted but the server never recorded it (the recording failed), the gate never claims a change: "Antes, os Termos." / "Para continuar, leia e aceite os Termos."
- **M3. The minor home** is "Suas tarefas" with the protected second line "Responsável: ‹nome›", sections "Hoje" and "Próximos dias", rows shaped like H8's child's day, and the empty line "Nada para hoje." / "Quando combinarem uma tarefa, ela aparece aqui."
- **M3a. Kids mode** (2026-10-04, `KidsMode.swift`) replaces M3's list for a minor whose band is `under_12`, or for any minor who turns on "Modo criança" in Ajustes (the switch also turns it off for an under-12). Header: "Oi, ‹nome›" (or "Oi"), then one star per task of today and the value "N de M feitas". One big card per task: a category tile in the kids palette (`NinaTheme.Kids`, the only place category gets a colour), the title in the `.kids` tier, the hour in a sun pill, and a round check that pops with a short shape confetti when it closes. All done: "Tudo feito por hoje." / "Muito bem." on the sun wash. "Próximos dias" keeps small tiled rows. No emoji in any string: the colour, the tiles and the shapes are the "emoji". The shapes are flat circles, stars and squares, never a face or a character. Reduce Motion removes the confetti, the pop and the drifting shapes. The account-less child's list on an adult's phone (`ChildDayView`) uses the same card for a profile whose role is `child`, and closes with the same sun card, "Tudo feito por hoje." / "Pode devolver o celular."
- **M4. Minor settings** are rows only (S1): "Modo criança" (switch), "Responsável", "Tempo hoje" ("4 de 30 min"), "Avisos" ("Ligados" only when the guardian keeps alerts on and iOS allows them, "Bloqueados" when iOS refused, otherwise "Desligados"), "O que a Nina guarda", "Precisa conversar?", "Minha idade está errada", "Denunciar um problema", "Termos de uso" ↗, "Política de privacidade" ↗, then "Sair" and "Apagar conta". Alerts: "Apagar sua conta?" / "Suas tarefas voltam para a casa. Não dá para desfazer." and "Sair deste iPhone?" / "Para entrar de novo, use sua conta Apple."
- **M5. The guardian sheet** keeps its protected card, declaration and consents whole; its chrome follows the capture sheet (K1–K4) with the title "Você é responsável por ‹nome›?", the eyebrows "Quem você é" and "Idade de ‹nome›", the optional "Apelidos" field (helper "Só para a Nina esconder o nome."), "Aprovar" (or "Cadastrar"), quiet "Agora não", the link "Ler sobre famílias" and the footnote "Se você não é responsável, feche e peça a quem é."
- **M6. Supervision** is the eyebrow "Supervisão" and value rows (G3); the footer "‹nome› não conversa com a Nina e não compra nada."; the quiet destructive actions last. Choosing "Sem limite" shows only the neutral "Sem limite, o tempo de ‹nome› fica só no Tempo de Uso do iPhone." No copy may push a guardian toward a weaker setting (ECA Digital art. 18 §§1–2).
- **M7. A minor's notification** is "‹título› · ‹hora›": no Nina voice, no nudge.

---

## 3. Text that must never be cut

These strings may be shortened to the minimum form shown. Every element listed must survive.

**Law-text-gated** (since 2026-09-29; it replaces "Counsel-gated", because no lawyer reviews Nina's wording) means the string answers a legal article, cited in `docs/privacy/avaliacao-impacto-criancas.md` §9. A shorter rewrite is allowed only if it still says everything the article asks; where the legal text is longer than a word budget, the legal text wins. Changing one means changing that document's row in the same commit.

| # | Protected content | Surface | Minimum form | Gate |
|---|---|---|---|---|
| 1 | Subscription terms: plan name, period, billed price per option, auto-renewal, how to cancel, Restaurar compras, links to Termos and Privacidade | Paywall | Title + a price on each option + one terms line (P3) + link row | App Review 3.1.2. Drop no element. |
| 2 | The limit Premium does not lift | Paywall | "Teto da casa: 100 conversas por dia." | — |
| 3 | AI consent v2: the text and the house details go to OpenAI, a US company; OpenAI may keep them up to 30 days against abuse, or longer if the law requires, and trains nothing on them; the conversation is the person's own; children's and teens' names go as codes and their tasks never go; another adult's name goes only if that adult accepted; it can be switched off in Ajustes · Privacidade e dados and stops at once; the separate, unchecked transfer box "Autorizo enviar o que eu escrever e os detalhes da casa para a OpenAI, empresa dos Estados Unidos."; "Este aviso mudou." when an older consent was withdrawn; declining keeps everything else working; privacy policy link | Chat consent gate | Headline + lead + the five lines + the transfer block + button + footnote + link | Law-text-gated (LGPD arts. 8, 9 §1 and 33 VIII; Apple 5.1.2(i)) |
| 4 | Where data lives, plus the international transfer and its 30-day abuse logs, and that an adult who did not accept still has tasks sent, under a code, when another adult chats | Privacidade | One closing footer (§2.3) | Law-text-gated (LGPD art. 33 VIII) |
| 5 | Withdrawing consent applies only to you | Privacidade | "Vale só para você. Cada adulto decide o seu." | Law-text-gated |
| 6 | Account deletion: every item that disappears, every item that stays, irreversibility, the typed gate; for a subscriber, that deleting does not cancel Apple's billing, with a way to manage the subscription. Must be reachable from the Settings root, from every no-house screen, from the age check and from the majority and Terms gates. A refusal, or the second failure in a row, always leaves a way out by mail | Apagar conta | Two noun lists + gate + "Não dá para desfazer." + the subscriber card + "Para apagar mesmo assim, escreva para ‹email de privacidade›." with "Escrever" | App Store 5.1.1(v) and 3.1.2. No item removed. |
| 7 | What survives deleting the conversation; 30-day retention | Privacidade | Alert message (§2.3) + "A conversa some sozinha depois de 30 dias." | — |
| 8 | Who will read a shared memory, and that sharing is irreversible | Memory share alert | C10 | — |
| 9 | Memories start private | Memórias empty state, memory card | "Memórias começam privadas." and the two separate buttons | — |
| 10 | An invite link grants nothing; someone in the house approves | Invite sheet; login invite variant | One line each (§2.1, K7) | — |
| 11 | Pending state; date and owner on the card face; the "can read it wrong" disclaimer | Proposal card, tour (Nina step example) | One tag + one disclaimer line per screen (C6) | — |
| 12 | Nina keeps no photo, and what OpenAI may keep | Composer, while a photo is attached | "A Nina não guarda a foto. A OpenAI pode guardar por até 30 dias para evitar abuso." | Law-text-gated; privacy-sensitive path (CLAUDE.md §13) |
| 13 | The card cannot be used to pay a bill | "O que eu li" block on bills | "Para pagar, abra o boleto no banco." | — |
| 14 | Quiet hours silence a notification but never move it | Avisos | "No silêncio, o aviso chega na hora, sem som." | — |
| 15 | The workload portrait is not for blame; it is never drawn when inconclusive | Casa, `WorkloadView` | "Para conversar, não para cobrar." gated on `isConclusive` | — |
| 16 | Nina does not take a slot | Casa, Nina's row | "Não ocupa vaga." | — |
| 17 | Honesty states: offline or local reply, confirmation withheld, an action that failed | Chat notices, error lines | One line each (C11) | Never replaced by silence |
| 18 | Legal acceptance at sign-in, and that a minor enters only with a guardian's approval | Welcome | "Ao continuar, você aceita os Termos e a Política de Privacidade. Menores de 18 anos entram numa casa com aprovação de um responsável." | Law-text-gated (LGPD arts. 8 and 14 §1; ECA Digital art. 24) |
| 19 | Why chat is unavailable, and what still works: adult-only, age not confirmed by Apple, suspended | Adult-only, declared-adult and blocked gates | C14 | — |
| 20 | Irreversibility on every irreversible action | Destructive alerts | "Não dá para desfazer." | — |
| 21 | Only the subscriber manages a shared plan | Premium management | "Só quem assina muda o plano." | — |
| 22 | The rating | Welcome, startup loading screen, web footer | The ClassInd mark from `NinaRating.current`, accessibility label "Classificação indicativa: não recomendado para menores de 14 anos" (14 since 2026-10-18, build 18; "livre" before) | Law-text-gated (Portaria MJSP 1.048 art. 50) |
| 23 | Apple gives only a range, never a birth date | `AgeCheckView` | "A Apple informa só a faixa, nunca a data de nascimento." | Law-text-gated (ECA Digital art. 13; Decreto 12.880 art. 25 §1) |
| 24 | What a minor sees and does not; that their tasks do not go to the AI and their name goes as a code; the guardian's controls | Guardian sheet card | The five card lines | Law-text-gated (LGPD art. 14 §§3, 6; ECA Digital arts. 7 and 17–18) |
| 25 | The guardian's declaration, the account consent with Terms acceptance on the minor's behalf, and the separate optional health consent | Guardian sheet | The two required checkboxes and the optional one, whole | Law-text-gated (LGPD arts. 8 §2, 11 I, 14 §§1, 4, 5; Código Civil arts. 3 and 1.634 VII) |
| 26 | Nina is a program, who supervises the account, never to share access | Minor welcome | The five lines; "Entendi" under 16, "Aceitar" with "Você aceita os Termos junto com ‹responsável›." at 16–17 | Law-text-gated (Decreto 12.880 art. 11 I; ECA Digital art. 17) |
| 27 | Who supervises | Minor home | "Responsável: ‹nome›" | Law-text-gated (ECA Digital art. 17 III) |
| 28 | What Nina keeps about a minor, where, who sees it, that Nina is a program, the codes, how to delete | "O que a Nina guarda" | The six lines + "Mais para os responsáveis" | Law-text-gated (LGPD art. 14 §6) |
| 29 | Where to talk | "Precisa conversar?" | "Se algo te preocupa, fale com um adulto de confiança." + "CVV: ligue 188. É de graça, a qualquer hora." (number UNVERIFIED) | Law-text-gated (ECA Digital art. 17 §4 IX) |
| 30 | How to contest the age | "Minha idade está errada" | The Apple or guardian variant + "Ou escreva para ‹email de privacidade›." (the mail carries "Referência: ‹id›", so the operator can find an account with no email) | Law-text-gated (Decreto 12.880 art. 27) |
| 31 | A report is never anonymous | "Denunciar um problema" | "A denúncia não é anônima: ela sai do seu email." | Law-text-gated (ECA Digital art. 29 §2) |
| 32 | No setting is pushed weaker | Supervision, "Sem limite" | "Sem limite, o tempo de ‹nome› fica só no Tempo de Uso do iPhone." | Law-text-gated (ECA Digital art. 18 §§1–2) |
| 33 | Someone who writes about hurting themselves meets the CVV line before any model | Chat reply (`ninaSupportReply`) | "Sinto muito que esteja tão pesado. Você não precisa passar por isso sem apoio: ligue 188, o CVV, de graça, a qualquer hora. Se houver perigo agora, procure um serviço de emergência." (number UNVERIFIED) | Law-text-gated (ECA Digital art. 17 §4 IX) |
| 34 | Withdrawing a minor's health consent deletes the health reminders | Health consent sheet, confirm alert armed with `warning()` | "Retirar a autorização de saúde?" / "Os lembretes de saúde de ‹nome› são apagados." / "Retirar" | Law-text-gated (LGPD arts. 8 §5, 15 III and 16) |
| 35 | Deleting the account needs Apple's confirmation, and a cancelled confirmation deletes nothing | Apagar conta | "A Apple pede para confirmar com sua conta." above the ink button; "A Apple não confirmou. Nada foi apagado." when the Apple sheet is cancelled | Apple 5.1.1(v) |
| 36 | House deletion: everything that disappears for everyone, what stays, irreversibility, the typed house-name gate; for a subscriber, that deleting the house does not cancel Apple's billing, with a way to manage it; for a house someone else pays for, that their billing continues | Apagar a casa | Two noun lists + gate + "Some para todos da casa. Não dá para desfazer." + the subscription card (§2.3) | App Store 3.1.2 (the billing line). No item removed. |

**Never write**

- Copy claiming that nothing sent to the model provider is kept (G18).
- "amiga", "eu" in Nina's voice, or a scripted Nina conversation on a surface a minor can see (G17).
- A minor's age band anywhere but their own guardian's supervision block.
- Copy claiming that task titles are hidden from the lock screen. They are not.
- Any string saying Nina created, changed or deleted something.
- "IA" or "assistente" as Nina's name.
- Vendor or configuration language (G14).

---

## 4. Engineering guardrails (so the cuts stay compatible with CLAUDE.md)

- **Strings:** pt-BR literals stay inline in the view. No `Localizable`. Every string goes through `.ninaText`:
  - headlines use `.screen`, `.title` or `.zero`
  - lines use `.label` in muted
  - footers and legal text use `.meta`
  - eyebrows use `.eyebrow`
- **Before deleting or rewording a string,** run `grep -rn "<string>" NinaTests Tools supabase/functions/_shared web/tests`. Update any assertion deliberately; never delete one. The known hit is `HouseholdWorkloadTests.swift:40`.
- **Color:** "Bloqueados", "Casa cheia" and "Apagar conta" are ink or muted, never terracotta. Moss is only for something a human confirmed. There is one cobalt control per screen, so an empty-state button goes quiet whenever the + is visible.
- **Accessibility:** rows keep a minimum height of 44pt. When a state moves into a chevron or trailing value, set `accessibilityValue`. Icon-only controls get an `accessibilityLabel`. Disabled controls use both `.disabled` and `.opacity`.
- **Haptics are unchanged:**
  - `lightImpact` when a sheet opens
  - `warning` when a destructive action is armed
  - `success` and `selection` asymmetry for completing and un-completing
- **Out of scope:**
  - Nina's generated replies. `nina-chat-policy.ts` is a product change, not a copy pass.
  - Notification bodies, which are governed by `NotificationTargetingTests`.
  - The web invite page's "Verificação pendente" state.
- **Records:**
  - Log every copy change that departs from the Paper boards in `docs/rebrand-implementation.md`.
  - The seeded greeting (`DemoHouse.messages`) and `MockNinaEngine` stay in one voice. If one changes, check the other. Both are DEBUG-only since 2026-10-15.
- **Removed steps:** when a tutorial step is removed, remove its dead state and model code in the same change. Leave no unreachable view.