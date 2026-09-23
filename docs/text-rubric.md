# Nina: rubric for cutting on-screen text

Last updated: 2026-09-23

This rubric applies to every screen of the iOS app. A screen passes when it meets every rule in §1 and every rule in its surface section (§2), and when none of the text listed in §3 has been lost. The rules come from Mobbin research on about 90 iOS screens across six surfaces. The strongest references are cited inline.

---

## 0. How to audit a screen

1. **Render every state.** That means default, empty, error, loading and offline. It also means owner, admin and member; a free house and a covered house; and Dynamic Type at `accessibility3`.
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
5. **Run the layout checks** (G15–G16) and the engineering guardrails (§4).

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
- **G15. Composition.**
  - Free space sits above the actions, never below them.
  - A single block (an empty state, the brand block, a gate) is centered vertically in the space it has.
  - Screens scroll at `accessibility3`. Content uses `minHeight` equal to the viewport, never fixed heights.
- **G16. Glyphs replace words only where the glyph is standard**: chevron, ↗, +, bell, calendar, person, lock, (i).
  - Every icon-only control has an explicit `accessibilityLabel`.
  - A state word removed from the screen moves into `accessibilityValue`.
- **G17. Voice.**
  - Informal `você`. No exclamation marks, no emoji.
  - Nina is named as a person, never "IA" or "assistente".
  - No string claims Nina did something.
  - Short does not mean telegraphic: Nina's own lines stay whole sentences with a period.

### Word budgets

These count authored words only, as defined in §0 step 4.

| Surface | Budget |
|---|---|
| Welcome / login | ≤ 28 including button labels and legal; ≤ 16 without the legal line |
| Email or code step (sheet) | ≤ 15 |
| Settings root | ≤ 50, and 1 second line in total (the account row) |
| Settings sub-screen | ≤ 40, plus protected footers |
| Tutorial | ≤ 3 screens, ≤ 120 words in total, ≤ 45 per screen |
| Empty state | headline ≤ 6 + one line ≤ 10 + one action ≤ 3 |
| Filter or group empty | one line ≤ 4 |
| Chat, empty | ≤ 25 including chips and placeholder |
| Proposal card chrome | ≤ 10, not counting the proposal's own values or protected lines |
| Consent gate | ≤ 50 (changes need counsel sign-off, see §3) |
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
│         Sua amiga Nina         │  .ninaText(.display), centered
│    Conta pra ela o que pesa.   │  .ninaText(.label, muted), centered
│ (flexible spacer, min 32)      │
│ [    Continuar com a Apple   ] │  system button, black, 52pt
│ [      Entrar com email      ] │  outline, 52pt, 12pt gap
│        error line (if any)     │  .meta, ink, centered
│ Ao continuar, você aceita os   │  .meta muted, centered, 14pt below
│ Termos e a Política de Priv.   │  links tinted
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
            actionGroup                   // VStack(spacing: 12): Apple, email, error line
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
  - The login screen never explains how the product works. That is the tutorial's job.
  - Only 4 of 16 references add a second line, and none explains the product.
- **L4.** At most two buttons: Apple first (black, system label), email second (outline).
  - There is no cobalt fill on the welcome screen. The screen's single cobalt control lives in the email sheet.
- **L5.** Choosing email never re-flows the welcome screen. It opens a sheet (`.presentationDetents([.medium, .large])`, radius 28).
  - Precedents: [Luma](https://mobbin.com/screens/5b0e502b-47ea-45a2-975b-0a70be09c657), and the [Claude flow](https://mobbin.com/flows/34ee8283-6a62-4b6e-b6d2-970e86c495ee), where the brand block never moves.
  - Focus the field with `.task { await Task.yield(); focusedField = .email }`.
  - Opening the sheet keeps `Haptics.lightImpact()`.
- **L6. The code step says what happened, echoes the address, and offers a resend.**
  - Precedents: [Brick](https://mobbin.com/flows/3f721b3f-5cc4-427a-8635-36668bad5963) and [TikTok](https://mobbin.com/flows/ce10d6cb-7a46-4501-847a-44f487d76171). 7 of the 8 code screens reviewed echo the address.
  - The field has no caption above it, because its placeholder or content already says what it is.
- **L7. The legal footnote** is centered, 1–2 lines, in the `.meta` tier, 14pt under the last button. It appears on the welcome screen only, not again in the sheet.
- **L8.** The error line sits inside the action group, centered, in ink (never terracotta). One state gets one sentence.

**Target strings**

| Where | Current | Target |
|---|---|---|
| Welcome tagline | 20-word, two-sentence subtitle | "Conta pra ela o que pesa." |
| Invite variant | "Você foi convidado para uma casa." plus a subtitle | Title "Você tem um convite"; tagline "Quem convidou aprova sua entrada." The line is protected (§3). The new title is also gender-neutral. |
| Email button | "Usar meu email" | "Entrar com email". Email only signs in existing accounts (`shouldCreateUser: false`). |
| Email step | "Email" caption plus the field | Title "Entrar com email"; field placeholder "voce@exemplo.com" with no caption; button "Enviar código" |
| Code step | "Código" caption and "Confirmar código" | Title "Código enviado"; muted line "Para ‹email›"; a `.oneTimeCode` field; button "Confirmar"; one row of quiet links "Reenviar código" · "Trocar email" |
| Legal footnote | no comma after "Ao continuar" | "Ao continuar, você aceita os Termos e a Política de Privacidade." |
| Backend unavailable | "Configure o projeto Supabase…" plus the error line | Delete the footer sentence. `configurationMissing` becomes "Não dá para entrar agora. Tente mais tarde." |

### 2.2 Onboarding and tutorial

**Rules**

- **O1. At most 3 screens: capture, confirm, close.**
  - Cut any step that leaves nothing behind and rehearses no gesture the real app has. That removes the "subtract" step and the three question steps.
  - A question comes back only when something reads its answer, and it is asked where that answer takes effect.
  - Precedents: [Arc Search](https://mobbin.com/flows/4260d248-66f7-4b8a-952e-81446a19bbd6) teaches by doing; the [Things 3 welcome](https://mobbin.com/flows/084e799a-adc4-4949-9393-6065b518211f) uses about 14 words.
- **O2. Headlines are 7 words or fewer, with no body line by default.** Allow a body line only for a term the reader may not know, and then one sentence of 12 words or fewer. Precedents: the [Duolingo mascot questions](https://mobbin.com/flows/ac9d2f58-868d-4fd3-a79c-9655ce6b1522) and [Blue Apron](https://mobbin.com/screens/abae8f67-deed-43a5-b14b-12094e2fdac1).
- **O3. The rehearsal uses the live UI's exact strings**: the same pending tag, the same buttons and the same disclaimer line (§2.5). When a live string changes, the tutorial changes in the same commit.
- **O4. Use one progress indicator**, the segmented bar. No "Pergunta N de M" text.
- **O5. One skip per screen**: "Pular" at the top right ("Fechar" on replay).
- **O6. The closing screen** has a headline of 5 words or fewer, one line of 8 words or fewer, and one button. No recap of what the user just did.
- **O7. Option labels are 5 words or fewer.** No placeholder option ("É outra coisa") unless tapping it opens a field. Counter-example: [MacroFactor](https://mobbin.com/screens/d0e155ed-6da1-4e5f-a03a-675b24be45c9), with 12–15 words per option.

**Target strings**

- **Capture:** "O que está na sua cabeça agora?" with the eyebrow "Ou toque em uma", the example chips and the placeholder "Escreva do seu jeito". Delete "Do jeito que você pensou. Sem data, sem categoria, sem forma certa."
- **Confirm:**
  - Nina's bubble: "Li assim. Confere?"
  - Card and buttons: the live card and live buttons, with "Criar tarefa" or "Criar semente", "Corrigir", "Não".
  - Disclaimer: the live disclaimer line, word for word.
  - Delete "A Nina está esperando você." and the 20-word footer.
  - Replace the inert `NinaCheckbox` with the category glyph.
- **Close:** "Agora é com você." plus "Foi só um ensaio. Nada foi criado." plus the button "Começar".

### 2.3 Settings (`SettingsSheet` and the screens it pushes)

Evidence: 9 reference settings roots show about 77 rows, and none of them has a description line. Examples: [Things 3](https://mobbin.com/screens/fe872e1e-90a8-4409-a62f-8360b64d7080), [Todoist](https://mobbin.com/screens/f53e3dc7-132a-4915-af49-d0ba98e4136b), [Monzo](https://mobbin.com/flows/1fcc4f33-fb16-4296-b470-e04456be34ee), [BeReal](https://mobbin.com/screens/e49ad3ee-1913-46c7-8ae9-b22965472b05) and [Zesty](https://mobbin.com/screens/eb324653-f821-4ab3-8603-c4818ac0acd4). Nina's root today has 10 of 11 rows with a subtitle, about 140 words.

**Rules**

- **S1.** Every row follows G5. Only the account row (name and email) has a second line.
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

**Target root** (owner, free house; about 45 words)

- Account row: name and email.
- `Email de acesso ›` (or `Adicionar email ›` when no email is linked)
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
- **Ajuda group:** `Rever o tutorial` · `Falar com o suporte ↗` · `Termos de uso ↗`
- `Sair da conta`
- `Apagar conta` (in ink)
- Footer: `Nina 1.0 (4)`

The invite row's trailing "5 vagas" follows [Duolingo's "4 spots left"](https://mobbin.com/screens/fd3e8e2e-0b82-4e2f-8223-b410a3e325f9). `settingsSummary()` returns a single word. "Bloqueados" is ink or muted, never terracotta.

**Target sub-screens**

- **Privacidade**
  - Consent toggle: "Deixar a Nina ler", with the second line "Mensagens e fotos."
  - Footer under it: "Vale só para você. Cada adulto decide o seu."
  - Data rows: `Baixar meus dados ›` and `Apagar minha conversa`, with the footer "A conversa some sozinha depois de 30 dias."
  - The "Onde ficam os seus dados" card becomes one closing footer: "Seus dados ficam no Brasil. Para responder, o que você envia passa por um serviço fora do país." This needs counsel sign-off (§3).
  - "Apagar minha conversa" alert: title "Apagar sua conversa?", message "Tarefas e memórias confirmadas ficam."
- **Avisos**
  - Delete the intro sentence.
  - Show the status card only when iOS has denied notifications: "O iPhone bloqueou os avisos." with the button "Abrir Ajustes do iPhone".
  - Toggle "Avisos", with the footer "Tarefas urgentes ganham um segundo aviso uma hora depois."
  - "Silenciar à noite" loses its subtitle, because the Começa and Termina rows already show the hours. Its footer becomes "No silêncio, o aviso chega na hora, sem som." (protected).
- **Email de acesso**
  - Delete the intro sentence.
  - When an email is linked, show the value row "Email atual" with the address.
  - When none is linked, add the footer "Com um email, você entra por código, sem a Apple."
- **Apagar conta**
  - Eyebrow "Some para sempre": "Sua conversa com a Nina", "Suas memórias privadas", "Seu perfil e sua foto", "Seu acesso a ‹casa›".
  - Eyebrow "Fica na casa": "Tarefas que você criou, sem dono", "Compras", "Memórias compartilhadas".
  - Keep the typed gate and the ink "Apagar conta" button. Delete "Deixa pra lá".
  - Alert: title "Apagar sua conta?", message "Não dá para desfazer." Keep `Haptics.warning()` when arming it.

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
- **E10. Rows (`TaskRowView`) stay as they are.** They already match every reference.

**Target strings**

| Where | Target |
|---|---|
| Hoje, first day | "A casa começa vazia." + "Conta pra Nina o que está pesando." + quiet "Conversar com a Nina", with the + visible. Delete "Escrever sem a Nina". |
| Hoje, day cleared | "Acabou o dia da casa." + "Pode largar o celular." The next-up eyebrow changes from "Amanhã cedo" to "Próxima". |
| Filter empty | "Nada com você." · "Tudo tem dono." · "Nenhuma semente." · "Nada em aberto." |
| Overdue | Header "ATRASADAS · N", action "Remarcar". Alert: title "Remarcar para amanhã, 09:00?", message "Nada é apagado.", button "Remarcar". |
| Tarefas, first use | "Nada combinado ainda." + "Conta pra Nina. Ela propõe, você confirma." + one button. The + is visible. |
| Sementes, empty | "Semente é vontade sem data." + the example card + "Nova semente" |
| Sementes, populated | At most a dismissible "Semente não vira atraso." with "Entendi" |
| Compras | Empty: "Nada faltando." + "O que acabar em casa aparece aqui." Clear button: "Limpar comprados". Alert: "Limpar comprados?" / "Some da lista para todo mundo da casa." |
| Search, no results | "Nada com esse nome." + "Tenta outra palavra." + one chip, "Conversar com a Nina" |
| Memórias, empty | "A Nina propõe guardar. Memórias começam privadas." |

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
  - No permanent chip row.
  - Precedent: [Perplexity](https://mobbin.com/screens/7248785b-ef14-4bc8-86ac-6f657fa9e6db).
- **C5. Photo previews.**
  - A draft photo previews as a thumbnail with an X, with no filename or size. Only documents show a name and size.
  - The draft footer becomes the protected line "A foto não fica guardada em servidor nenhum."
- **C6. "Not yet confirmed" is said once per card, and the disclaimer once per screen.**
  - The card carries one pending tag of 3 words or fewer: "Ainda não existe" (a memory uses "Ainda não guardada").
  - The disclaimer is one faint line under the newest Nina reply that has a pending proposal: "A Nina pode ler errado. Nada entra sem você confirmar."
  - Delete `waitingLine` and the composer footer.
  - The research suggested the one-word tag "Proposta". It is not used here, because the pending statement is protected (§3) and the tutorial mirrors it.
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
  - "Sem conexão. Esta resposta veio do aparelho."
  - "Modo local. Nada sai deste aparelho."
  - "Ler foto e documento é do Premium." with the action "Ver o Premium"
  - "No Premium, 30 mensagens por hora." with the action "Ver o Premium"
  - The withheld-proposals notice becomes "Confirmação ainda fechada nesta versão. Nada entrou na casa."
- **C12. The typing indicator** is the mark in `.reading` presence, plus "Lendo" or no text at all.
- **C13. Date correction hints.**
  - Parsed: "Vai ficar: sex, 18:00."
  - Empty: "Vai ficar sem data."
  - Unparseable: "Não entendi a data. Tente "amanhã 18:00"."
- **C14. The gates** have a headline, at most 4 lines of 10 words or fewer, one button, one footnote and one link. No closing paragraph.
  - Adult-only gate: "A conversa é dos adultos da casa." + "Tarefas e compras continuam com você."
  - Consent gate: see §3. It needs counsel sign-off before any wording ships.

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
- **K5. A permission prompt inside a sheet is one chip at the end of the chip row.**
  - Not yet asked: "Ativar avisos", which requests permission.
  - Denied: "Avisos bloqueados", which opens iPhone Ajustes.
  - Both use the `bell.slash` glyph.
- **K6. Delete action.** The button reads "Apagar". Alert: title "Apagar esta tarefa?", message "Some para toda a casa. Não dá para desfazer."
- **K7. Invite sheet.**
  - The protected line appears once: "Quem abrir o link pede para entrar. Alguém da casa aprova."
  - The four fact rows collapse into one data line: "Vale até 30 de set. · 5 usos restantes".
  - "Renovar o link" becomes a quiet text button.
  - Precedent: [Life360 invite code](https://mobbin.com/screens/a3589921-f6d4-468d-a702-70c2ee835d44).

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

**Rules**

- **H1. Member rows** are an avatar, a name and one line of data: the role, "Criança" or "Pet". Never a sentence. Precedents: [Greenlight Family](https://mobbin.com/screens/5a8be526-2a1c-4402-9666-fec75183726b) and [Life360](https://mobbin.com/screens/4af1acb5-fbf9-4dd7-832f-d7795f1d5f14).
- **H2. Capacity is a count**: "2 de 8 pessoas". Delete the separate "casa cheia" sentence.
- **H3. Each invariant is stated once, on the surface where it matters, in 12 words or fewer.**
  - "Não ocupa vaga." appears on Nina's row only.
  - "Não usa o app" appears in the add-profile sheet only. "Adicionar criança ou pet" has no subtitle.
  - The invite approval line appears in the invite sheet only.
- **H4. Actions on the Casa screen are rows, not cards.**
  - "Convidar alguém ›" joins the member list. Precedent: [Splitwise group](https://mobbin.com/screens/f0e6077c-afdf-4cc9-9993-c38a65ef982d); its toggle-description block below is the counter-example.
  - A premium-gated item is one row: a lock glyph, the title, a "Premium" tag and a chevron. Example: "Resumo semanal".
  - In a covered house, before the first digest: "O primeiro chega em até 7 dias."
- **H5. The solo portrait** is the eyebrow "Sinal de sobrecarga", the title "Aparece quando o outro adulto entrar.", and the button "Convidar". Delete `aloneReassurance`.
- **H6. The portrait title never equals the eyebrow.**
  - The unbalanced headline "Sinal de sobrecarga" becomes "Pesando de um lado". Update `HouseholdWorkloadTests.swift:40` deliberately.
  - "A casa está parecida" and "Ainda sem retrato da casa" stay.
- **H7. `WorkloadView`.**
  - Structure: the headline, the bars, and one caption: "Só o que está aberto e tem dono. Para conversar, não para cobrar." The caption stays gated on `snapshot.isConclusive`.
  - Put "Sementes não entram. Não é histórico, é hoje." behind an (i). Precedent: [Splitwise stats](https://mobbin.com/screens/f77b2738-8716-4219-932f-3e9080cbbd2c).
  - Unbalanced message: "‹Nome› está com a parte mais pesada agora." A balanced house has no message.
  - Inconclusive message: "Preciso de \(minimumAssignedSample) tarefas com dono, entre \(minimumCarriers) pessoas." Keep the interpolated constants.
  - The shared row label becomes "Sem dono".

---

## 3. Text that must never be cut

These strings may be shortened to the minimum form shown. Every element listed must survive.

**Counsel-gated** means Brazilian counsel approves the new wording before it ships (CLAUDE.md §13). Until then, change only layout and spacing, not wording.

| # | Protected content | Surface | Minimum form | Gate |
|---|---|---|---|---|
| 1 | Subscription terms: plan name, period, billed price per option, auto-renewal, how to cancel, Restaurar compras, links to Termos and Privacidade | Paywall | Title + a price on each option + one terms line (P3) + link row | App Review 3.1.2. Drop no element. |
| 2 | The limit Premium does not lift | Paywall | "Teto da casa: 100 conversas por dia." | — |
| 3 | AI consent: content goes to a model outside Brazil; nothing is retained there or used for training; the conversation stays with the person; each adult decides; it can be switched off in Ajustes and stops immediately; declining keeps everything else working; privacy policy link | Chat consent gate | Headline + ≤4 lines of ≤10 words + button + footnote + link | Counsel-gated |
| 4 | Where data lives, plus the international transfer | Privacidade | One closing footer (§2.3) | Counsel-gated |
| 5 | Withdrawing consent applies only to you | Privacidade | "Vale só para você. Cada adulto decide o seu." | Counsel-gated |
| 6 | Account deletion: every item that disappears, every item that stays, irreversibility, the typed gate. Must be reachable from the Settings root | Apagar conta | Two noun lists + gate + "Não dá para desfazer." | App Store 5.1.1(v). No item removed. |
| 7 | What survives deleting the conversation; 30-day retention | Privacidade | Alert message (§2.3) + "A conversa some sozinha depois de 30 dias." | — |
| 8 | Who will read a shared memory, and that sharing is irreversible | Memory share alert | C10 | — |
| 9 | Memories start private | Memórias empty state, memory card | "Memórias começam privadas." and the two separate buttons | — |
| 10 | An invite link grants nothing; someone in the house approves | Invite sheet; login invite variant | One line each (§2.1, K7) | — |
| 11 | Pending state; date and owner on the card face; the "can read it wrong" disclaimer | Proposal card, tutorial | One tag + one disclaimer line per screen (C6) | — |
| 12 | Photos are not stored on a server | Composer, while a photo is attached | "A foto não fica guardada em servidor nenhum." | Privacy-sensitive path (CLAUDE.md §13) |
| 13 | The card cannot be used to pay a bill | "O que eu li" block on bills | "Para pagar, abra o boleto no banco." | — |
| 14 | Quiet hours silence a notification but never move it | Avisos | "No silêncio, o aviso chega na hora, sem som." | — |
| 15 | The workload portrait is not for blame; it is never drawn when inconclusive | Casa, `WorkloadView` | "Para conversar, não para cobrar." gated on `isConclusive` | — |
| 16 | Nina does not take a slot | Casa, Nina's row | "Não ocupa vaga." | — |
| 17 | Honesty states: offline or local reply, confirmation withheld, an action that failed | Chat notices, error lines | One line each (C11) | Never replaced by silence |
| 18 | Legal acceptance at sign-in | Welcome | L7 footnote | — |
| 19 | Why chat is unavailable, and what still works | Adult-only gate | C14 | — |
| 20 | Irreversibility on every irreversible action | Destructive alerts | "Não dá para desfazer." | — |
| 21 | Only the subscriber manages a shared plan | Premium management | "Só quem assina muda o plano." | — |

**Never write**

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
  - The seeded greeting (`AppStore.swift:2748`) and `MockNinaEngine` stay in one voice. If one changes, check the other.
- **Removed steps:** when a tutorial step is removed, remove its dead state and model code in the same change. Leave no unreachable view.