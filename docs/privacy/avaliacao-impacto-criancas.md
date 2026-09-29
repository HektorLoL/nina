# Children's Impact Assessment - Nina

Last updated: 2026-09-29

One document for every assessment the law asks of a product that children and
adolescents are likely to use. It was written by the controller, without a
lawyer, on the verified research of 2026-09-28 and the all-ages spec of
2026-09-29. Wherever the law had two readings, the more protective one was
taken. UNVERIFIED marks a point no primary source confirmed. This is not legal
advice.

The plain-language summary this document owes the public (Decreto 12.880/2026
art. 47 §1) is section 10 of `https://ninai.app/familias/`, built from
`web/src/pages/familias.astro`. When this document changes, that section
changes in the same commit.

## 1. What this document is, and which rule each part answers

| Part | Rule | Where |
| --- | --- | --- |
| Data protection impact report (RIPD) | LGPD art. 38; Res. CD/ANPD 2/2022 art. 4 (children's data plus emerging technology is high risk, so the simplified regime does not apply) | §§3-4 |
| Best interest per purpose | LGPD art. 14 caput; Enunciado CD/ANPD 1/2023 | §5 |
| Risk management per feature | Lei 15.211/2025 (ECA Digital) art. 8 I | §6 |
| Impact report shared on request | ECA Digital art. 16 sole paragraph II | this document |
| Child safety and health impact assessment | Decreto 12.880/2026 art. 47 caput and §1 | §§6, 10 |
| Algorithmic risk | Decreto 12.880 art. 11 III | §7 |
| Scaling of duties | ECA Digital art. 39 | §8 |
| Protected strings and their articles | the "Law-text-gated" rows of `docs/text-rubric.md` §3 | §9 |

The record of processing (LGPD art. 37) is `docs/privacy/registro-de-operacoes.md`.
The App Store and ClassInd answers are in `docs/privacy/classificacao-indicativa.md`.

## 2. Scope

ECA Digital applies to every IT product "direcionado a crianças e a
adolescentes no País ou de acesso provável por eles" (art. 1). Nina is treated
as in scope from the first all-ages build:

- it has no minimum age and aims for the "Livre" rating;
- it holds child and teen profiles, and a minor may hold an account;
- the child's day list (`ChildDayView`) is shown to a child on purpose;
- an ANPD draft guide reportedly reads age notices and terms as formal barriers
  that do not exclude likely access (secondary source only, UNVERIFIED).

A child is under 12 and an adolescent is 12 to 17 (ECA art. 2; ECA Digital art.
2 §1). Nina's bands follow the law, not Apple's defaults: `under_12`, `12_15`
(absolute civil incapacity ends at 16, Código Civil art. 3) and `16_17`.

## 3. The processing

- **Age.** Apple's Declared Age Range returns a range and a declaration method.
  The app sends the outcome through the `age-signal` Edge Function, which
  verifies an App Attest assertion and records only status, band, assurance and
  a parental-controls flag. Unknown age is the youngest band (Decreto 12.880 art.
  25 §4). A guardian-declared band that is younger wins. Nothing else reads it.
- **Entry.** A minor or unknown-age person asks to join; an owner or admin whose
  adult age Apple confirmed approves as mother, father or legal guardian, with a
  highlighted consent, in one transaction.
- **Profiles without an account.** Created only by an Apple-confirmed adult with
  the same declaration and consent. No birth date, no photo.
- **A minor's own view.** Their own open tasks and today's done ones: title,
  time, category glyph. No detail line, no other member, no shopping, no chat.
- **Supervision.** Alerts, quiet hours, a daily limit and a 7-day usage view,
  set by a live guardian.
- **Adult chat.** Adults with a live, current, transfer-consented AI consent
  talk to Nina. Every model-bound string is pseudonymized; minors' tasks never
  reach a tool.
- **Weekly insight and workload portrait.** Minors are never carriers and are
  never drawn.
- **Reports and holds.** An identified report channel; a sealed hold for input
  flagged as sexual content involving minors.
- **Export and deletion.** Own-data export on the server; a guardian exports a
  ward's data; deletion from every state.

## 4. Necessity and proportionality

- **Minimization (LGPD art. 6 III, art. 14 §4).** A minor's participation never
  depends on a photo, a birth date, an email or AI consent. Sign in with Apple
  asks a minor or unknown-age account for no name or email. The server forces a
  minor's profile email to null and optional fields to empty.
- **Single-purpose age data (ECA Digital art. 13; Decreto 12.880 art. 24; Apple
  DPLA §3.3.3(O)).** The band gates features and nothing else: it never enters
  member lists outside the guardian's supervision block, model context, logs,
  insights or anyone else's export, and no function granted to clients takes a
  user id and returns an age.
- **No birth date, no bounds, no history (Decreto 12.880 art. 25 §1).**
- **Most protective defaults (ECA Digital art. 7; art. 17 §4).** Quiet hours on,
  a 30-minute limit, no nudges, health off until a separate consent.
- **Retention.** Usage minutes 30 days, unapproved minor requests 7 days, a
  minor account without a house 30 days, consent proof 5 years after it ends
  (the burden of proof of LGPD art. 8 §2).

## 5. Best interest, purpose by purpose

LGPD art. 14 caput requires every processing of a minor's data to be in their
best interest; Enunciado CD/ANPD 1/2023 lets any art. 7 or art. 11 basis cover
it when that interest prevails. Legitimate interest is never used for a minor's
health data (ANPD legitimate-interest guide, 2024, p. 8).

| Purpose | Data | Basis | Why it serves the minor | Safeguards |
| --- | --- | --- | --- | --- |
| Keep a child or teen profile | First name, nicknames, role, band, guardian and relationship, assigned tasks | Guardian consent, art. 14 §1 | The household can share the load of caring for the child without the child needing a device | Only an Apple-confirmed adult declaring guardianship; no birth date or photo; deleted when the last guardian withdraws |
| A minor's own account and task list | The above, plus the Apple login id, the Apple band and assurance | Guardian consent, art. 14 §1; joint acceptance at 16-17 (Código Civil art. 1.634 VII) | The minor sees what was agreed with them and marks it done, which supports autonomy without exposing the rest of the house | Own tasks only, no detail line, no writing of content, no chat, no purchases |
| Guardian supervision | Usage minutes per day, supervision settings | Guardian consent; ECA Digital arts. 17-18 | Limits use and protects sleep, as the law's defaults intend | Minutes kept 30 days; the minor always sees who supervises (art. 17 III) |
| Health reminders of a minor | Tasks in the health category owned by the minor | Separate guardian consent, arts. 11 I and 14 §1 | A medicine or appointment is not forgotten | Optional; enforced on the server; withdrawing it deletes the minor's health reminders, after a confirm alert (LGPD arts. 8 §5, 15 III and 16) |
| Age band | Status, band, assurance, parental-controls flag | Legal obligation, art. 7 II; ECA Digital art. 14 | It is what keeps adult features away from the minor | Single purpose; App Attest; most protective result wins |
| Child's day on an adult's phone, print and share | Title, hour and glyph of the child's own tasks | Guardian consent (profile) | A child without a phone can follow their day | Showing is open to adults of the house; print and share only for a live guardian; no detail line ever |
| Adults talking about a minor to Nina | Whatever an adult writes | The adult's consent; for the minor, pseudonymization under art. 14 §3 | Adults can organize care; the minor's identity does not leave Brazil | Names and nicknames replaced by codes before moderation, pre-count and model; minors' tasks excluded; residual risk in §6 |
| Weekly insight and workload portrait | Not processed for minors | None needed | A fairness chart about a child would be profiling without benefit to them | Minors are never carriers or entries |
| Reports and child-safety holds | Reporter identity, reason, message reference; sealed text | Legal obligation, ECA Digital art. 27 | Protects the child who may be harmed | Sealed table; deleted after the Polícia Federal confirms receipt |

## 6. Risk register

Likelihood and severity use Low, Medium and High. "Before" is the build of
2026-09-28, where every approved joiner became an adult with AI access; "after"
is this design.

| Risk | Feature | Before (L/S) | Mitigation | After (L/S) |
| --- | --- | --- | --- | --- |
| A minor receives inappropriate AI content | Chat | High/High | Minors never reach the chat; the server gates chat to Apple-confirmed adults; prompt rules, output moderation, deterministic medical refusal | Low/Medium |
| Sexually explicit AI dialogue, which Decreto 12.880 art. 16 §4 treats as pornography | Chat | Medium/High | Prompt rule (no sexual content and no romantic or sensual version offered instead) and output moderation for adults; minors excluded; eval cases, the sexual one checked for "sensual" and "para adultos" | Low/High |
| Clinical or emotional guidance read as a professional's (ClassInd Guia D.7.1) | Chat | Medium/High | Deterministic refusal for diagnosis, symptoms, medicine or dose, and any change of dose even beside a reminder, pointing to a professional; a message moderation flags for self-harm gets the fixed CVV 188 reply before any model; CVV line in the minor's "Precisa conversar?" | Low/Medium |
| A minor's identity or tasks leave Brazil | Chat, insight | High/Medium | Pseudonymizer on every model-bound string; minors' tasks excluded from every tool; no minors in the insight | Medium/Medium (unregistered nicknames can pass) |
| A minor sees a boleto reading, a health item or "cerveja" | Household view | High/Medium | Minors read only their own task title, time and glyph through one RPC; no shopping list | Low/Low |
| A minor buys something | Paywall | Medium/Medium | Minors and self-declared adults never reach the paywall; the server refuses a new purchase with `premium_requires_adult` | Low/Low |
| Excessive or compulsive use (ECA Digital art. 8 IV; Decreto 12.880 art. 9) | Minor account | Medium/Medium | No feed, no streaks, no rewards, no nudges; forced quiet hours; daily limit; Screen Time recommended | Low/Low |
| Contact with strangers | Houses | Low/High | Only approved members of one house of at most 8; no messages between people | Low/Medium |
| A child claims to be an adult | Age | High/High | Apple band, App Attest, most protective result; unknown is a child; minor to adult only on an Apple `confirmed` signal | Low/High |
| Someone falsely claims to be a guardian | Approval | Medium/High | Only an Apple-confirmed adult already in the house, owner or admin to approve; explicit declaration; false declaration breaches the Terms §4 | Medium/High (declared, not proven) |
| A house left without an adult | Membership | Low/Medium | The minor's account pauses and shows nothing; a minor account without a house is deleted after 30 days | Low/Low |
| A child's task detail reaches a lock screen, printer or chat | Notifications, child's day | Medium/Medium | `ChildDayRow` has no detail field; neutral notification template on a minor's device; no subtitle in any body | Low/Low |
| Apparent sexual abuse material entered by an adult | Chat input | Low/High | Input moderation seals it, blocks the account's chat, and the operator reports it to the Polícia Federal (Decreto 12.880 art. 39); deleting the account keeps a sealed copy of its identifiers and data for the preservation period, and the block follows the same Apple ID | Low/High |
| A minor cannot leave or erase | Deletion | Medium/Medium | In-app deletion from every minor state; a guardian can delete; export for the guardian | Low/Low |

## 7. Algorithmic risk (Decreto 12.880 art. 11)

- **I. Transparency to minors about the synthetic nature.** Every surface a minor
  can see calls Nina "um programa de computador" once per flow, speaks of her in
  the third person, and never calls her "amiga". The minor's first run and "O
  que a Nina guarda" say it; `/familias/` §1 and §8 say it on the web.
- **II. No behavioral manipulation.** Minors do not interact with the model at
  all. Their surface has no streaks, rewards, urgency or nudges, and no copy
  pushes a guardian toward weaker settings (ECA Digital art. 18 §§1-2).
- **III. Algorithmic risk to safety and health.** The model is reachable only by
  Apple-confirmed adults with a current consent. Its outputs are proposals a
  human must confirm. Prompt rules forbid sexual, violent, discriminatory,
  profane or drug content, and clinical, dietary or emotional guidance; output
  moderation drops a flagged reply and its proposals. The insight prompt forbids
  blame, intent, mental health and moral value. The local eval must include the
  sexual, dose, "o que eu tomo para dor", diet, profanity, "seja minha
  terapeuta", risk (CVV) and redaction cases before each model change.
- **IV. Developmental safeguards.** The minor sees only what was agreed with
  them, marks it done, and is told to talk to a trusted adult when something
  bothers them.

## 8. Scaling under ECA Digital art. 39

Art. 39 scales the duties of arts. 6, 17, 18, 19, 20, 27, 28, 29, 31, 32 and 40 to
the product's features, the supplier's control over content, the number of
users and the supplier's size. Nina is a solo supplier; each house holds at most
8 people approved by an adult; there is no feed, no discovery, no messaging
between people and no public content.

- **Arts. 17-18 (supervision).** Implemented for Nina's own surface: settings,
  purchase restriction (none possible), visible notice, daily limit and 7-day
  usage, all in Portuguese. The daily limit is counted on the device and synced;
  it cannot stop the iPhone. Apple's Screen Time is the system control that can,
  so every guardian surface and `/familias/` recommend it alongside the in-app
  limit, and choosing "Sem limite" says the time is then left to Screen Time.
- **Art. 19 (monitoring products).** The minor is told, in their own words, who
  follows the account and what they see.
- **Art. 20 (loot boxes).** Not applicable; none exist.
- **Art. 24 (linking accounts up to 16 to a guardian).** It sits in the chapter
  on social networks, so whether it applies is UNVERIFIED; every minor account
  is linked to a live guardian regardless.
- **Arts. 27-29, 32-33 (reports, removal, channel).** An identified email
  channel plus an in-app reply report; acknowledgement within 48 hours (Heitor's
  choice); one person decides and reviews. No automated takedown other than the
  child-safety hold, which a person reviews.
- **Art. 31 (semiannual reports).** Applies only above 1,000,000 registered
  minors; track the count through `private.age_assurance_distribution()`.
- **Art. 40 (legal representative).** Decision D2: a company with a CNPJ and an
  address before launch.

## 9. Protected strings and the article each one answers

These strings are "Law-text-gated" in `docs/text-rubric.md` §3: a shorter
rewrite is allowed only if it still says what the cited article asks.

| Surface | String (pt-BR) | Article |
| --- | --- | --- |
| LoginView footnote | "Ao continuar, você aceita os Termos e a Política de Privacidade. Menores de 18 anos entram numa casa com aprovação de um responsável." | LGPD arts. 8 and 14 §1; ECA Digital art. 24 |
| Rating mark, app and web | accessibility label "Classificação indicativa: livre" | Portaria MJSP 1.048/2025 art. 50; ECA Digital art. 8 V |
| AgeCheckView | "A Apple informa só a faixa, nunca a data de nascimento." | Decreto 12.880 art. 25 §1; ECA Digital art. 13 |
| Guardian sheet title | "Você é responsável por {nome}?" | LGPD art. 14 §5 |
| Guardian sheet card | "{nome} vai ver só as próprias tarefas e marcar o que fez." / "Não conversa com a Nina, não compra nada e não vê o resto da casa." | LGPD art. 14 §6; ECA Digital art. 7 §1 |
| Guardian sheet card | "As tarefas de {nome} não vão para a inteligência artificial." / "Quando um adulto fala de {nome} com a Nina, o nome vai trocado por um código." | LGPD arts. 14 §3 and 33 |
| Guardian sheet card | "Você controla avisos e tempo de uso, e pode apagar a conta quando quiser." | ECA Digital arts. 17-18 |
| Guardian declaration | "Declaro que sou mãe, pai ou responsável legal de {nome}." | LGPD art. 14 §§1 and 5; Código Civil arts. 3 and 1.634 VII |
| Guardian consent | "Autorizo a Nina a guardar o nome, a faixa de idade e as tarefas de {nome}, e aceito os Termos e a Política de Privacidade como responsável por {nome}." | LGPD art. 14 §1; art. 8 §2 |
| Health consent | "Autorizo registrar lembretes de saúde de {nome}, como remédio e consulta." | LGPD arts. 11 I and 14 §4 |
| Minor welcome | "A Nina é um programa de computador, não uma pessoa." | Decreto 12.880 art. 11 I |
| Minor welcome | "{responsável} acompanha sua conta: vê suas tarefas, avisos e tempo de uso." | ECA Digital arts. 17 III and 19 §1 |
| Minor welcome, 16-17 | "Você aceita os Termos junto com {responsável}." | Código Civil art. 1.634 VII |
| Minor home | "Responsável: {nome}" | ECA Digital art. 17 III |
| "O que a Nina guarda" | the six lines, from "A Nina guarda seu nome e as tarefas que combinaram com você." to "Quer apagar tudo? Fale com {responsável} ou toque em Apagar conta." | LGPD art. 14 §6; Decreto 12.880 art. 11 I |
| "Precisa conversar?" | "Se algo te preocupa, fale com um adulto de confiança." / "CVV: ligue 188. É de graça, a qualquer hora." (number UNVERIFIED) | ECA Digital art. 17 §4 IX |
| "Minha idade está errada" | the Apple and guardian variants and "Ou escreva para {email de privacidade}." | Decreto 12.880 art. 27 |
| Supervision, "Sem limite" | "Sem limite, o tempo de {nome} fica só no Tempo de Uso do iPhone." | ECA Digital arts. 7 §1 and 18 §§1-2 |
| Report channel | "A denúncia não é anônima: ela sai do seu email." | ECA Digital art. 29 §2 |
| AI consent card | the lead naming OpenAI and the house details, and line 1 on the 30-day abuse logs | LGPD arts. 8 and 9 §1 |
| AI consent card | "Autorizo enviar o que eu escrever e os detalhes da casa para a OpenAI, empresa dos Estados Unidos." | LGPD art. 33 VIII; Apple Guideline 5.1.2(i) |
| Terms §4 | "A Nina não tem idade mínima. A classificação indicativa da Nina é {classificação}." | Decreto 12.880 art. 12 §4; Portaria MJSP 1.048 art. 55 |
| Privacy §6A | "Envio para fora do Brasil", its form, duration, purpose, destination and rights | Res. CD/ANPD 19/2024 Anexo I art. 2 V and art. 17 §§2-3 |
| `/familias/` | the whole page | ECA Digital art. 16; LGPD art. 14 §2; Decreto 12.880 art. 47 §1 |
| `/denuncia/` | the whole page | ECA Digital arts. 29 §3, 30 and 33; Decreto 12.880 arts. 39 and 41 |

## 10. Published summary

Mirrored word for word on `/familias/` §10:

- Os maiores riscos estavam na conversa com a inteligência artificial e no
  envio de dados para fora do Brasil. Por isso, menores não conversam com a
  Nina, e nomes e tarefas de menores não vão para a OpenAI.
- O menor vê só as próprias tarefas, sem os detalhes que os adultos escrevem,
  porque esses detalhes podem ter contas, remédios ou assuntos de adulto.
- Guardamos o mínimo: sem data de nascimento de menores, sem pedir email a
  menores, e o email e a foto do perfil são apagados quando uma conta passa a
  ser de menor. A faixa de idade só serve para decidir o que cada conta pode
  fazer.
- Saúde de um menor só entra com uma autorização separada do responsável, que
  pode ser retirada.
- Os controles do responsável começam no nível mais protetor, e o menor sabe
  que a conta é acompanhada.
- Riscos que continuam: um apelido que a casa não informou pode chegar à
  OpenAI; a idade depende do que a Apple informa e da declaração do
  responsável; e o limite de tempo é contado no próprio iPhone.

Followed by: "Revemos a avaliação a cada mudança que afete menores. A versão
completa fica disponível para a ANPD quando ela pedir."

## 11. Residual risks accepted without a lawyer

- The rating outcome (Apple and the MJSP decide; see the rating document).
- The age signal is attested by the client device, not proven by a document.
- Guardianship is declared, not proven.
- Adults may come back as self-declared rather than confirmed (D3 measures it).
- Redaction is best effort, and the pseudonymized transfer is still a transfer.
- No ANPD standard clauses with OpenAI; no Zero Data Retention.
- The scope of ECA Digital and pending ANPD regulation.
- The daily limit is enforced on the device.
- The child-safety reporting channel and the MJSP act are UNVERIFIED.
- Personal liability of the controller until the company exists (D2).
- The iOS 26.4 floor excludes older iPhones.
- Sign in with Apple behavior for Brazilian child accounts is UNVERIFIED.
- Consent records are kept for 5 years.
- No lawyer reviewed the wording.
- Minors may already be on the waitlist.
- Adults' own health text reaches OpenAI under the chat consent.

## 12. Monitoring and review

The controller reviews this document, and its public summary, whenever:

- a feature changes what a minor can see or do;
- the chat model, the prompt, or the moderation changes (run the local eval);
- photo or PDF reading is considered again (a privacy review of its own);
- the ANPD publishes its final scope or age-assurance guides;
- Apple or the MJSP assign a rating other than "Livre";
- the operator widens `trusted_assurances`.

Signals to read each month on TestFlight and after launch: the assurance
distribution (`private.age_assurance_distribution()`), the number of minor
accounts, reports received and their outcomes, child-safety holds, and AI
blocks.
