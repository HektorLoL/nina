# Age Rating (Classificação Indicativa) - Nina

Last updated: 2026-10-18

Nina aims for an all-ages rating: "Livre" in Brazil, AL on Apple's Brazil
self-rating. That is a target, not a guarantee: Apple computes the App Store
rating from the questionnaire, and the Ministério da Justiça e Segurança
Pública (MJSP) can assign its own, which then replaces Apple's pictogram.
Guideline 2.3.6 asks for honest answers, so every answer below carries its
rationale and the rating it risks if App Review reads the feature differently.

Heitor decided on 2026-09-29 (D1): aim for "Livre"; if Apple or the MJSP rate
Nina 10 or 12, accept it, keep the AI chat for adults, and change the one rating
constant (§8).

Heitor decided on 2026-10-14 (D3): an adult whose 18+ age Apple reports as
self-declared may chat and buy Premium, because Apple does not confirm adult
ages in Brazil (`docs/privacy/lgpd-launch-posture.md`, "Decision D3"). Acting
for a minor still needs an age Apple confirmed. This weakens the age gate in
front of the chat and the paywall, and §6 says what it may cost.

Answer the questionnaire only after the all-ages work is live end to end:
migrations, functions, the TestFlight build, the web pages and the production
preflight. Until then, today's build makes every approved joiner an adult with
AI access, and an AL answer would be false.

## 1. The one constant

| Surface | Line | File |
| --- | --- | --- |
| iOS | `static let currentCode = "L"` inside `enum NinaRating` | `Nina/NinaRating.swift` |
| Web | `export const ninaRatingCode: NinaRatingCode = "L";` | `web/src/rating.ts` |

The preflight check `repository.rating-constant-consistency` fails when the two
disagree. Everything else is derived from the code, identically on both
surfaces:

| Code | Name | Symbol | Accessibility label | Terms phrase | Colour |
| --- | --- | --- | --- | --- | --- |
| L | Livre | L | Classificação indicativa: livre | livre | #00A859 |
| 10 | Não recomendado para menores de 10 anos | 10 | Classificação indicativa: não recomendado para menores de 10 anos | não recomendada para menores de 10 anos | #0095DA |
| 12 | Não recomendado para menores de 12 anos | 12 | Classificação indicativa: não recomendado para menores de 12 anos | não recomendada para menores de 12 anos | #FDC300 |
| 14 | Não recomendado para menores de 14 anos | 14 | Classificação indicativa: não recomendado para menores de 14 anos | não recomendada para menores de 14 anos | #F58220 |
| 16 | Não recomendado para menores de 16 anos | 16 | Classificação indicativa: não recomendado para menores de 16 anos | não recomendada para menores de 16 anos | #E3001B |
| 18 | Não recomendado para menores de 18 anos | 18 | Classificação indicativa: não recomendado para menores de 18 anos | não recomendada para menores de 18 anos | #1D1D1B |

The colours and the drawn symbol are UNVERIFIED against the official artwork on
gov.br/mj. Confirm them before release; they are the one colour exception to the
azulejo palette on both surfaces.

Where the rating is shown (Portaria MJSP 1.048/2025 art. 50 asks for install,
login and startup; Decreto 12.880/2026 art. 12 §4 and Portaria art. 55 ask for
the Terms):

- the App Store listing (Apple);
- LoginView and the startup loading screen (`AppLoadingScreen`; not its
  app-switcher cover), both at 22pt in the same spot (build 11; the settings
  rows were removed, and `repository.rating-mark-placement` keeps it there);
- the footer of every page of `ninai.app`;
- Terms §4, through `ninaRating.termsPhrase`;
- `/familias/` §11.

## 2. Apple questionnaire answers

| Item | Answer | Rationale | Risk if App Review disagrees |
| --- | --- | --- | --- |
| In-app Parental Controls | Yes | A live guardian sets alerts, quiet hours and a daily limit, sees 7 days of use, exports and deletes (ECA Digital arts. 17-18). | Stays AL on Apple's Brazil table. |
| In-app Age Assurance | Yes | Declared Age Range, recorded only through an App Attest-verified endpoint; server gates for every adult feature. An 18+ range, self-declared or confirmed, opens the chat and Premium; acting for a minor needs Apple's confirmation (D3). | Stays AL. |
| Unrestricted Web Access | No | No web view or browser. | None. |
| Advertising | No | No ads and no ad SDK. | None. |
| Social Media | No | No feed, no discovery, no public profile. Required question since September 2026. | None expected. |
| User-Generated Content | No | Content is visible only inside one household of at most 8 people an adult approved; minors author nothing. | A6. |
| Messaging and Chat | No | There are no messages between people. The chat is one adult with Nina. | A12 if shared tasks are read as group posting. |
| Profanity or crude humor; horror | None | The AI is reachable only by accounts Apple reports as 18+, self-declared or confirmed (D3), is bound by prompt rules and output moderation for every adult, and is tested in the local eval. A minor who declared 18+ to Apple reaches it under the same rules. | A10. |
| Mature or suggestive themes; sexual content; nudity; violence; weapons | None | Prompt rule against sexual, violent, discriminatory, profane and drug content; output moderation; eval cases. | A12 to A16. |
| Alcohol, tobacco, drugs | None | Nina's own content has none. Shopping lists are the family's own text, and minors never see the shopping list. How Apple treats private household text is UNVERIFIED. | A14. |
| Medical or Treatment Information | None, only once the deterministic medical refusal ships, passes the eval, and App Review confirms adult-only features count as described; otherwise Infrequent | Nina gives no diagnosis or guidance; people type their own reminders. | A12. |
| Health or Wellness Topics | No, under the same conditions, with attachments off and no prescription reading in the metadata or on the landing | The landing no longer mentions "a receita do pediatra". | A10. |
| Gambling, contests, loot boxes | No | None (ECA Digital art. 20). | None. |
| Made for Kids | No | It binds the Kids Category rules for good (Guideline 1.3), and Nina sends adult data to OpenAI. | None. |
| Override to a higher rating | None | The Terms set no minimum age; they name adult-only features. | See question 3 below. |
| Age Suitability URL | `https://ninai.app/familias/` | Public, no install needed (ECA Digital art. 16). | None. |

## 3. Questions for App Review, before submitting

Ask in writing, in the App Review notes of the submission (decided 2026-09-29;
`docs/production-launch-runbook.md` §6 has the reasons and the optional
appointment). Record each answer with its date here. If an answer moves the
rating, change the answers and `NinaRating.currentCode` together and resubmit.

1. Does content shared inside a closed household of up to 8 approved people
   count as User-Generated Content or as Messaging?
   Answer: pending.
2. Do features that the server gates to users the Declared Age Range API
   reports as 18+, self-declared or confirmed, count toward the questionnaire
   answers?
   Answer: pending.
3. Does "some features are only for adults" in the Terms count as a minimum age
   requirement that forces an override?
   Answer: pending.
4. Sign in with Apple is the only sign-in. The chat and the subscription open
   only for an account whose Declared Age Range answer is 18+, self-declared or
   confirmed, and decisions about children only for an adult Apple confirmed.
   How should the reviewer reach these features if the review device shares no
   age?
   Answer: pending.

## 4. Review note (English)

> Nina is a household organizer with no minimum age. Everything that raised the
> previous 18+ rating is unreachable for anyone the server has not recorded as
> an adult: the assistant chat, subscriptions, the full household view, and
> decisions about children. Age comes from the Declared Age Range API and is
> recorded server-side only through an App Attest-verified endpoint. Unknown age
> is treated as a child. A person under 18 holds an account only after a parent
> or legal guardian already in the household approves it in the app. That
> account shows only the person's own chores, with guardian controls for
> notifications, quiet hours and a daily time limit. The chat and
> subscriptions open for an adult whether Apple reports the age as
> self-declared or confirmed; decisions about children need Apple's
> confirmation. There is no user-to-user messaging, feed, web view or
> advertising. Test accounts: [trusted adult], [declared adult], [minor],
> [unknown].

Test accounts are marked with `private.operator_set_age_status`, because App
Attest and Declared Age Range do not run on the Simulator or on a reviewer's
device in the expected way. Sign in with Apple is the only sign-in, so there is
no password to hand the reviewer, and the "Test accounts" line above has no
working form yet: how the reviewer reaches the adult features is question 4 of
`docs/production-launch-runbook.md` §6, open until App Review answers it. The
notes also carry that section's Sign in with Apple paragraph, word for word
(build 12): Nina asks Apple for the name alone, keeps only the first name and
never asks for the email, so an adult sees a name field only when Apple shared
no first name (Guideline 4.0). A person under 18, or anyone whose age Apple
has not shared (Nina treats that account as a minor's until it does, and the
reviewer starts there), confirms a first name, filled in from Apple's when
shared, where they ask to join a household; the paragraph says so.

## 5. Metadata

No "para crianças" or similar in the name, subtitle, icon, screenshots or
description (Guidelines 2.3.8 and 5.1.4). Screenshots must suit every age: no
chat about medicine, no shopping list with alcohol, no boleto reading.

## 6. ClassInd self-classification (MJSP)

Apps with generative AI must be classified (Portaria MJSP 1.048/2025 art. 48 V).
Self-classify against the Portaria and the Guia Prático (5th ed., 2025). A
tendency raises the rating unless an attenuator applies, and attenuators count
only when they are on by default (Portaria art. 57).

| Tendency | What the Guia says | Nina | Attenuator |
| --- | --- | --- | --- |
| D.1.1 | A clear, permanent notice that supervision by a guardian is needed | A minor's home always shows "Responsável: {nome}"; the guardian's controls are on by default | E.1.10 |
| D.2.1 / D.3.1 | AI dialogue (6 and 10) | Accounts Nina knows are minors never reach the chat; adults only (18+ by Apple's range, self-declared or confirmed, D3), gated on the server | E.1.13; E.1.10 weak since D3 |
| D.4.1 | UNVERIFIED: read the Guia before filing | Map it when the Guia text is at hand | - |
| D.5.1 | Purchases with money in a utility app (14) | Only accounts Apple reports as 18+, self-declared or confirmed (D3), reach the paywall; the server refuses other buyers | E.1.10 (weak since D3), E.1.11 (not counted for D.5.1 until ClassInd answers; see below) |
| D.5.2 | Communication between users without parental consent or age assurance (14) | No messages between people; entry to a house needs an adult's approval, and a guardian's for a minor | E.1.10 |
| D.5.3 | AI in a secondary role does not fit the AI tendency | Nina's AI assists a household organizer; it proposes, a person confirms | - |
| D.6.1 | Processing that breaks the purpose principle (16) | Age data is single-purpose; the OpenAI transfer stays within the consented purpose; minors' data never goes | E.1.18 |
| D.6.5 | Nagging notifications (16) | One nudge per task for adults only; none for minors; forced quiet hours for minors | E.1.12 |
| D.7.1 | A generative tool that can produce sexual or violent text, or clinical or emotional guidance (18) | Prompt rules, output moderation, deterministic medical refusal; adults only | E.1.13 |

Attenuators on by default: E.1.10 access control and age assurance, E.1.11
consumption control, E.1.12 time control, E.1.13 content blocking, E.1.18 data
security.

**The rating risk D3 accepts.** Since D3 (2026-10-14), the chat and the
paywall open on an 18+ range the person declared to Apple. For E.1.10 the Guia
treats a self-declared gate as "facilmente burlável", so it may not attenuate
D.5.1, and purchases alone can lift the self-classification to 14. That is
outside D1, which accepted 10 or 12. Heitor took that risk knowingly. The plan:

- Ask the ClassInd coordination in writing whether Apple's own purchase
  controls count as the attenuator for D.5.1: Ask to Buy for a child in Family
  Sharing, and Screen Time's purchase restrictions. Record the answer and its
  date in §9.
- Keep the chat's refusal of sexual content and its output moderation on for
  every adult, as a legal line (Decreto 12.880 art. 16 §4) and as E.1.13. The
  chat's own tendencies (D.2.1, D.3.1, D.7.1) lean on those, not on the age
  gate.

**E.1.11 in Nina.** Consumption control here is what Nina itself does to
purchases, on by default: a household subscription, in its two plans, and
nothing else to buy (no consumable, no per-item purchase, no in-app currency),
sold only through Apple's own sheet, never offered to an account Nina knows is a
minor, and refused by the server to anyone `may_buy_premium` leaves out. Ask to
Buy and Screen Time are Apple's, set by a guardian, and not on by default for
every account. Whether the Guia's E.1.11 covers any of this for D.5.1 once the
gate before it is self-declared is UNVERIFIED, and it is the same question put
to ClassInd, so until ClassInd answers this document counts neither E.1.10 nor
E.1.11 as attenuating D.5.1.

**What Nina publishes meanwhile.** Terms §4 and `/familias/` §11 keep "Livre"
(`NinaRating.currentCode`) until ClassInd answers, on these grounds: it is the
target of D1; nothing is released and no self-classification has been filed with
the MJSP (the análise prévia below is not filed); and the reading that would
lift it past D1, D.5.1 behind a self-declared gate, is the open question.
Revisit it when ClassInd answers, and at the latest before the first App Store
submission, whose age questionnaire carries the answer. If ClassInd answers that
neither attenuates D.5.1, the honest self-classification is 14:
`NinaRating.currentCode`, `ninaRatingCode`, Terms §4, `/familias/` §11, the
marks, the App Store answers and this document change together, by §8's steps,
and because 14 is outside D1 the product question goes back to Heitor first.
Holding "Livre" past the submission without an answer is Heitor's call, recorded
in §9.

Also:

- File a voluntary análise prévia (Portaria art. 46) as soon as the build is
  feature-complete. The procedure, cost and required identity are UNVERIFIED; the
  company of decision D2 is likely needed.
- Register representative details with the ClassInd coordination (Portaria
  art. 56).
- Whether Apple's questionnaire counts as an authorized system (Portaria art.
  44 §3) is UNVERIFIED. The MJSP can open a process to assign a rating
  definitively (art. 45 §3).

## 7. Expected rating

- **Apple, Brazil:** AL if App Review accepts the three readings in §3.
  Otherwise, honestly, A6, A10 or A12, and A14 in the worst case (alcohol in
  household text).
- **ClassInd:** "Livre" is the target but uncertain. The Guia rates even
  controlled AI dialogue at 6 or 10, and purchases at 14; only effective,
  on-by-default safeguards lower that. A realistic fallback is 10 to 14. Since
  D3, 14 is the honest worst case: a self-declared gate may not attenuate the
  purchases, unless ClassInd counts Apple's purchase controls (§6).

## 8. Fallback (D1)

If Apple or the MJSP assign 10 or 12:

1. Change `NinaRating.currentCode` and `ninaRatingCode` in the same commit. Run
   `deno task preflight:repo`; `repository.rating-constant-consistency` must
   pass.

   ```sh
   deno task preflight:repo
   ```

2. Rebuild and deploy the site. Terms §4, the footer mark and `/familias/` §11
   follow the constant; bump the Terms `updatedAt`.
3. Ship a build: the login, loading and settings marks follow the constant.
4. Keep the AI chat for adults. Nothing else in the product changes.
5. Update App Store Connect, this document and the review note.

A rating of 14 or above is outside D1: it means App Review or the MJSP read a
feature as adult content, and the product question goes back to Heitor. A 14
that comes only from purchases behind a self-declared gate (D.5.1, §6) is the
risk D3 accepted; it goes back to Heitor too, with ClassInd's written answer.

## 9. Records to keep here

- App Review's answers to §3, with dates.
- ClassInd's written answer on whether Ask to Buy and Screen Time count as the
  attenuator for purchases (D.5.1), with its date.
- If the first submission goes out before that answer, Heitor's decision on
  the published rating meanwhile (§6, "What Nina publishes meanwhile"), with
  its date.
- The análise prévia protocol number and outcome.
- The ClassInd registration of representative details.
- The rating Apple shows after submission, and any MJSP assignment.

Written so far:

- 2026-10-14: the written question to ClassInd is drafted (three questions:
  purchases under D.5.1, a self-declared adult age under E.1.10, and whether
  the análise prévia or Apple's questionnaire is the route; it also gives the
  art. 56 representative details). The channel is
  classificacaoindicativa@mj.gov.br, listed on the ClassInd page, the gov.br
  service page and the Guia's "Contatos úteis" (p. 134). The letter names the
  company and its CNPJ, so it lives outside this public repository, in
  Heitor's notes.
- 2026-10-14: Heitor sent it by email to classificacaoindicativa@mj.gov.br.
  No protocol number came back with the email.
- 2026-10-15: ClassInd answered by email (an analyst of the
  Coordenação-Geral de Política de Classificação Indicativa, copying the
  coordination's mailbox; Heitor read it on 2026-10-18). Its reading of the
  description: Nina presents tendency D.5.1 (purchases) and also D.5.3
  (generative AI of broad content), so it "tende" to "Não recomendado para
  menores de 14 anos", and no attenuator applies to interactive elements.
  The route is the voluntary análise prévia through the Sistema ClassInd,
  because the App Store is outside IARC; the filing needs a video showing
  every feature open to classification, plus an access link, login and
  password when they are needed for full access. It did not say whether an
  Inova Simples company files through its titular. This closes §6's open
  question: neither Apple's purchase controls nor the age gate attenuate
  D.5.1, and §6's D.5.3 reading ("AI in a secondary role") is not ClassInd's.
  14 is outside D1, so the product question is Heitor's (§8).
