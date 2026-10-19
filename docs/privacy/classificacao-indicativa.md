# Age Rating (Classificação Indicativa) - Nina

Last updated: 2026-10-19

Nina's rating is 14, "Não recomendado para menores de 14 anos", since
2026-10-18. That is the ClassInd coordination's reading of 2026-10-15 (§9):
Nina presents tendencies D.5.1 (purchases) and D.5.3 (generative AI of broad
content), and no attenuator applies to interactive elements. Heitor accepted it
on 2026-10-18 rather than publish "Livre" against it. It is still a
self-classification: the voluntary análise prévia through the Sistema ClassInd
(§6) is the next step and is not filed yet, and the Ministério da Justiça e
Segurança Pública (MJSP) can assign its own rating, which then replaces Apple's
pictogram. If the Ministry rates Nina lower, the constant goes back down (§8).
Apple computes the App Store rating from the questionnaire, and Guideline 2.3.6
asks for honest answers, so every answer below carries its rationale and the
rating it risks if App Review reads the feature differently.

Heitor decided on 2026-09-29 (D1): aim for "Livre"; if Apple or the MJSP rate
Nina 10 or 12, accept it, keep the AI chat for adults, and change the one rating
constant (§8). A 14 or above went back to Heitor, and on 2026-10-18 it did.

Heitor decided on 2026-10-14 (D3): an adult whose 18+ age Apple reports as
self-declared may chat and buy Premium, because Apple does not confirm adult
ages in Brazil (`docs/privacy/lgpd-launch-posture.md`, "Decision D3"). Acting
for a minor still needs an age Apple confirmed. This weakened the age gate in
front of the chat and the paywall, and §6 says what it was expected to cost.

Heitor decided on 2026-10-18 (option A): accept 14 now. The rating changes to
14 in the app, on the site and in the Terms; the AI chat and Premium stay
exactly as they are, for adults only; the análise prévia gets filed (not yet,
§6); and if the Ministry later rates Nina lower, the constant changes back (§8,
§9).

Heitor decided on 2026-10-19 (choice 4): the version is submitted with
"Manually release this version", and Release is pressed only after the
análise prévia's result or a written yes from ClassInd (§9;
`docs/production-launch-runbook.md` §8).

Answer the questionnaire only with the all-ages work live end to end:
migrations, functions, the build, the web pages and the production preflight
(live since 2026-09-29; `CLAUDE.md` §13). A build without the age step makes
every approved joiner an adult with AI access, and the answers below would be
false.

## 1. The one constant

| Surface | Line | File |
| --- | --- | --- |
| iOS | `static let currentCode = "14"` inside `enum NinaRating` | `Nina/NinaRating.swift` |
| Web | `export const ninaRatingCode: NinaRatingCode = "14";` | `web/src/rating.ts` |

Both lines read `"L"` until 2026-10-18. The preflight check
`repository.rating-constant-consistency` fails when the two disagree.
Everything else is derived from the code, identically on both surfaces; the 14
row is the one in use:

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

- the App Store listing (Apple; §2 says how far it can be made to read 14);
- not in the app, since build 19 (2026-10-19, Heitor's decision; §9). From
  build 11 to build 18 the mark sat on LoginView and the startup loading
  screen at 22pt, and build 18 drew 14; `repository.rating-mark-placement`
  now fails if `Nina/` draws it anywhere. This departs from the "login e
  inicialização ou carregamento" line of art. 50;
- the footer of every page of `ninai.app`;
- Terms §4, through `ninaRating.termsPhrase`;
- `/familias/` §11.

## 2. Apple questionnaire answers

The answers stay what is true of the product; the 2026-10-18 decision changed
the target, not the facts. Answered honestly, the questionnaire is expected to
compute AL to A12, and A14 at worst, on Apple's Brazil table (§7), none above
the 14 Nina now publishes, so below A14 the listing has to be raised to match:
A14, in this document's notation for Apple's Brazil table. How Apple shows a
ClassInd rating for Brazil is UNVERIFIED: whether App Store Connect takes a
Brazil rating of 14 directly, only through "Override to a higher rating" (and
which global tier lands on 14 in Brazil), or only once the MJSP assigns one. Read it in App Store
Connect before answering, and record what it offered in §9. A risk at or
below A14 in the last column no longer changes the Brazil listing; a reading
of A16 or above would, and goes back to Heitor (§8).

| Item | Answer | Rationale | Risk if App Review disagrees |
| --- | --- | --- | --- |
| In-app Parental Controls | Yes | A live guardian sets alerts, quiet hours and a daily limit, sees 7 days of use, exports and deletes (ECA Digital arts. 17-18). | None for the listing. |
| In-app Age Assurance | Yes | Declared Age Range, recorded only through an App Attest-verified endpoint; server gates for every adult feature. An 18+ range, self-declared or confirmed, opens the chat and Premium; acting for a minor needs Apple's confirmation (D3). | None for the listing. |
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
| Override to a higher rating | Whatever makes the Brazil listing read 14 (UNVERIFIED, see above); never for a minimum age | The 14 is ClassInd's reading, accepted 2026-10-18. The Terms still set no minimum age; they name adult-only features. | See question 3 below. |
| Age Suitability URL | `https://ninai.app/familias/` | Public, no install needed (ECA Digital art. 16). | None. |

## 3. Questions for App Review, before submitting

Ask in writing, in the App Review notes of the submission (decided 2026-09-29;
`docs/production-launch-runbook.md` §6 has the reasons and the optional
appointment). Record each answer with its date here. If an answer moves the
rating above 14, change the answers and `NinaRating.currentCode` together and
resubmit, after Heitor decides (§8).

The four questions were reworded on 2026-10-19 for the rating of 14 and for
D3; these are the words in the final review notes
(`docs/app-store-listing.md` §6). All four stay useful, for different reasons.
Question 2 can still lift Apple's rating above 14 (mature themes risk A16).
Question 3 decides whether the Terms force an override Nina did not choose.
Question 1's worst reading, A12, no longer changes the Brazil listing, but the
answer still decides whether "No" is the honest answer, and a wrong one costs a
rejection round (Guideline 2.3.6). Question 4 is how the reviewer reaches the
adult features, whatever the rating.

1. Does content shared inside a closed household of up to 8 approved people
   count as User-Generated Content or as Messaging?
   Answer: pending.
2. The AI chat and the subscription open only for accounts the Declared Age
   Range API reports as 18+, self-declared or confirmed. Do these adult-only
   features count toward the questionnaire answers, and could they lift
   Brazil's rating above 14?
   Answer: pending.
3. Our Terms say some features are only for adults and set no minimum age.
   Does that count as a minimum age requirement?
   Answer: pending.
4. If a review device shares no age range, is marking the review account as a
   self-declared adult on our server, as described above, the way you prefer
   to reach the adult features?
   Answer: pending.

## 4. Review note (English)

The one review note is in `docs/app-store-listing.md` §6, final as of
2026-10-19, with its character count. The earlier draft that stood here
(written before D3 and the rating of 14, with a "Test accounts" line that had
no working form) was deleted that day so that only one text exists. The note
names the rating of 14, asks §3's questions, carries the Sign in with Apple
paragraph of `docs/production-launch-runbook.md` §6.1 word for word, and says
how the reviewer reaches the adult features: if the review device shares no
age, the operator marks the reviewer's account with `trusted = false`, a
self-declared adult that chats and buys Premium but never acts for a child
(Heitor's choice 3 of 2026-10-19; the statements are in the runbook's §6, "The
reviewer's account").

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
| D.5.1 | Purchases with money in a utility app (14) | Only accounts Apple reports as 18+, self-declared or confirmed (D3), reach the paywall; the server refuses other buyers. ClassInd read this tendency into Nina on 2026-10-15 | None, on ClassInd's reading (no attenuator applies to interactive elements); E.1.10 and E.1.11 stay on but do not lower it |
| D.5.2 | Communication between users without parental consent or age assurance (14) | No messages between people; entry to a house needs an adult's approval, and a guardian's for a minor | E.1.10 |
| D.5.3 | Generative AI of broad content (14), on ClassInd's reading of 2026-10-15. This document first read the Guia as saying AI in a secondary role does not fit the AI tendency; ClassInd did not read it that way | Nina's AI assists a household organizer; it proposes, a person confirms; adults only. ClassInd read this tendency into Nina | None, on ClassInd's reading (no attenuator applies to interactive elements) |
| D.6.1 | Processing that breaks the purpose principle (16) | Age data is single-purpose; the OpenAI transfer stays within the consented purpose; minors' data never goes | E.1.18 |
| D.6.5 | Nagging notifications (16) | One nudge per task for adults only; none for minors; forced quiet hours for minors | E.1.12 |
| D.7.1 | A generative tool that can produce sexual or violent text, or clinical or emotional guidance (18) | Prompt rules, output moderation, deterministic medical refusal; adults only | E.1.13 |

Attenuators on by default: E.1.10 access control and age assurance, E.1.11
consumption control, E.1.12 time control, E.1.13 content blocking, E.1.18 data
security.

ClassInd's reading of 2026-10-15 named only D.5.1 and D.5.3 in Nina and counted
no attenuator for interactive elements. The other rows, and every other entry
in the Attenuator column, are this document's own reading from before that
answer. If that rule holds for every row, an attenuator lowers none of them, so
the análise prévia has to show that D.5.2 (14), D.6.1 and D.6.5 (16) and D.7.1
(18) are absent from Nina, not attenuated. D.6.1, D.6.5 or D.7.1 read into Nina
would put the rating above 14, and that goes back to Heitor (§8); D.5.2 would
not raise it, but would keep it at 14 even if D.5.1 and D.5.3 were later read
out of Nina. Whether "no attenuator applies to interactive elements" covers
every D tendency or only D.5.x is UNVERIFIED; ask in the filing.

**The rating risk D3 accepted, and how it came out.** Since D3 (2026-10-14),
the chat and the paywall open on an 18+ range the person declared to Apple.
For E.1.10 the Guia treats a self-declared gate as "facilmente burlável", so
it may not attenuate D.5.1, and purchases alone could lift the
self-classification to 14. That was outside D1, which accepted 10 or 12.
Heitor took that risk knowingly. The plan was:

- Ask the ClassInd coordination in writing whether Apple's own purchase
  controls count as the attenuator for D.5.1: Ask to Buy for a child in Family
  Sharing, and Screen Time's purchase restrictions. Asked on 2026-10-14,
  answered on 2026-10-15 (§9).
- Keep the chat's refusal of sexual content and its output moderation on for
  every adult, as a legal line (Decreto 12.880 art. 16 §4) and as E.1.13. The
  chat's own tendencies (D.2.1, D.3.1, D.7.1) lean on those, not on the age
  gate. This still holds.

The answer went further than the question. ClassInd counted no attenuator for
interactive elements at all and read D.5.3 as well as D.5.1, each at 14, so
the 14 does not rest on D3's self-declared gate alone. Heitor accepted 14 on
2026-10-18 and kept D3 as it is (§9).

**E.1.11 in Nina.** Consumption control here is what Nina itself does to
purchases, on by default: a household subscription, in its two plans, and
nothing else to buy (no consumable, no per-item purchase, no in-app currency),
sold only through Apple's own sheet, never offered to an account Nina knows is a
minor, and refused by the server to anyone `may_buy_premium` leaves out. Ask to
Buy and Screen Time are Apple's, set by a guardian, and not on by default for
every account. ClassInd answered on 2026-10-15 that no attenuator applies to
interactive elements, so this document counts neither E.1.10 nor E.1.11 as
attenuating D.5.1 or D.5.3. Both stay on by default because they are what the
product promises, not because they move the rating.

**What Nina publishes (decided 2026-10-18).** From 2026-10-14 to 2026-10-18,
Terms §4 and `/familias/` §11 kept "Livre" while the question to ClassInd was
open. Once ClassInd read 14, Heitor accepted it (option A):
`NinaRating.currentCode` and `ninaRatingCode` read `"14"`, so Terms §4 ("não
recomendada para menores de 14 anos"), `/familias/` §11, the footer mark on
every page and the welcome and startup marks (build 18) all say 14, and the
Terms page reads "Atualizados em 18 de outubro de 2026". Following Heitor's
rule of 2026-10-15 (the recorded Terms version follows the page date), once
that page was live the operator moved `private.age_policy.current_terms_version`
to `'2026-10-18'` (`docs/production-launch-runbook.md` §3, "The rating of 14,
and the Terms of 18 October"), on 2026-10-18. Every adult now meets "Os Termos
mudaram." once and every minor acknowledges the Terms again. The AI chat and
Premium are unchanged: adults only, by Apple's 18+ range, declared or confirmed
(D3), and acting for a minor still needs a confirmed age. The App Store answers
and the review note carry 14 (§2, §4). If the análise prévia or the MJSP rate
Nina lower, the constant goes back down by §8's steps.

Also:

- File the voluntary análise prévia (Portaria art. 46) through the Sistema
  ClassInd, the route ClassInd named on 2026-10-15 because the App Store is
  not part of IARC. Not filed yet. The
  filing needs a video demonstrating every feature open to classification,
  plus an access link, login and password when they are needed for full
  access. This document's reading of what the video must show, UNVERIFIED
  against the Sistema's own form: the welcome, the age step,
  house setup and an invite, Hoje, Tarefas and Casa, a proposal from the chat
  and its confirmation, the paywall and its Apple sheet, the guardian's
  approval and supervision, a minor's home, kids mode, the child's day list,
  and the medical and sexual-content refusals. Sign in with Apple is the only
  sign-in, so there is no login and password to hand over; how the analyst
  reaches the adult features (the video alone, or an Apple Account the
  operator marks with `private.operator_set_age_status`) is an open question
  for the filing. ClassInd did not answer whether an Inova Simples company
  files through its titular, and the cost is UNVERIFIED. The company's name
  and CNPJ go into the filing, never into this repository.
- Register representative details with the ClassInd coordination (Portaria
  art. 56).
- Whether Apple's questionnaire counts as an authorized system (Portaria art.
  44 §3) is UNVERIFIED; ClassInd's answer that the App Store is not part of
  IARC, and that the route is the análise prévia, suggests it does not. The
  MJSP can open a process to assign a rating definitively (art. 45 §3).

## 7. Expected rating

- **Apple, Brazil:** the questionnaire computes AL if App Review accepts the
  three readings in §3; otherwise, honestly, A6, A10 or A12, and A14 in the
  worst case (alcohol in household text). The listing is to read A14 either
  way, to match the 14 Nina publishes; how App Store Connect gets there is
  UNVERIFIED (§2). Only a reading of A16 or above would move it.
- **ClassInd:** 14. That is ClassInd's reading of 2026-10-15 (D.5.1 and D.5.3,
  no attenuator for interactive elements), which Heitor accepted on
  2026-10-18. The análise prévia decides it formally. A lower outcome moves
  the constant down (§8); a higher one goes back to Heitor.

## 8. Changing the rating

The same steps moved the rating from "L" to 14 on 2026-10-18, and move it
again if the análise prévia or the MJSP assign another, or App Review reads
Nina above 14:

1. Change `NinaRating.currentCode` and `ninaRatingCode` in the same commit. Run
   `deno task preflight:repo`; `repository.rating-constant-consistency` must
   pass.

   ```sh
   deno task preflight:repo
   ```

2. Rebuild and deploy the site. Terms §4, the footer mark and `/familias/` §11
   follow the constant; bump the Terms `updatedAt`, and re-read any sentence
   on those pages that explains why Nina has this particular rating. The
   reason clause (`ratingReason` in `termos.astro` and `familias.astro`) shows
   only while the code is `"14"`, so another code publishes no reason until
   each page gets its own sentence.
3. Once the Terms page is live, move `private.age_policy.current_terms_version`
   to the date it shows (Heitor's rule of 2026-10-15; an operator statement,
   `docs/production-launch-runbook.md` §3).
4. Ship a build: the welcome and startup marks follow the constant.
5. Keep the AI chat and Premium for adults. Nothing else in the product
   changes.
6. Update App Store Connect, this document and the review note.

Heitor decided on 2026-10-18 that if the Ministry (the análise prévia or an
MJSP assignment) rates Nina lower than 14, the constant goes back down by these
steps. Apple computing a lower rating does not, because the 14 is the
Ministry's coordination's reading. A rating above 14 means App Review or the
MJSP read a feature as adult content, and the product question goes back to
Heitor first.

D1 (2026-09-29) accepted 10 or 12 by these steps and sent 14 or above back to
Heitor. The 14 that came back was ClassInd's (§9), and Heitor accepted it.

## 9. Records to keep here

- App Review's answers to §3, with dates.
- ClassInd's written answer on whether Ask to Buy and Screen Time count as the
  attenuator for purchases (D.5.1), with its date (written below, 2026-10-15).
- Heitor's decision on the published rating (written below, 2026-10-18).
- What App Store Connect offered for a Brazil rating of 14 (§2).
- The análise prévia protocol number and outcome, which Release waits for
  (choice 4, below).
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
- 2026-10-19: Heitor removed the rating mark from the app (build 19), after
  testing build 18 and asking for examples of apps that show their own
  rating on screen. A search (web, news, the government's FAQ, Mobbin) found
  none: stores show the rating on the listing (Instagram's "16" on Google
  Play), and streaming apps show it per title. The rule still reads, in
  Portaria MJSP 1.048/2025 art. 50 sole paragraph, "A exibição das indicações
  etárias e dos descritores de conteúdo nos aplicativos e navegadores deverá
  ocorrer nas páginas de instalação, login e inicialização ou carregamento",
  in force since 2026-03-17 (art. 95 I) for the providers of art. 48 I to V,
  where V (AI that generates content) plausibly covers Nina; Lei 15.211 art.
  8 V asks a service minors may reach to state the rating "no momento do
  acesso"; the Guia (5th ed., p. 20 and O.3) asks for more (descriptors, a
  centred box at every access, settings). The risk accepted: an ECA
  administrative infraction (Portaria art. 13), no enforcement found, and an
  análise prévia whose analyst opens the app without a mark. The search also
  found that a self-classified work should show the provisional symbol (A14)
  until the rating is published in the DOU (art. 14 §2, art. 18; Guia H.1),
  and that the repo's L, 12, 16 and 18 hexes differ slightly from the Guia's
  (p. 125); neither matters while the app draws no mark. Restoring it is one
  `ClassIndMark()` call on each of the two screens plus the preflight check.
- 2026-10-19: Heitor decided (choice 4) that the App Store version waits for
  the Ministry: it goes to App Review with "Manually release this version",
  and Release is pressed only after the análise prévia's result or a written
  yes from ClassInd, so the public listing never runs ahead of the rating the
  Ministry reads. App Review can approve meanwhile; the approved version waits
  in "Pending Developer Release". The launch-day steps start there
  (`docs/production-launch-runbook.md` §8). Not filed yet, so not released.
- 2026-10-18: Heitor decided (option A) to accept 14 now.
  `NinaRating.currentCode` and `ninaRatingCode` move from `"L"` to `"14"`
  together, so Terms §4, `/familias/` §11, the footer mark on every page and
  the welcome and startup marks say 14; build 18 is the first build that
  draws it. The Terms page
  reads "Atualizados em 18 de outubro de 2026", and once it was live the
  operator moved `current_terms_version` to `'2026-10-18'`
  (`docs/production-launch-runbook.md` §3), the same day. The AI chat and
  Premium stay exactly as they are, for adults only (D3 unchanged; acting for
  a minor still needs a confirmed age). Next: file the análise prévia through
  the Sistema ClassInd (§6); not filed yet. If the Ministry later rates Nina
  lower, the constant changes back by §8's steps.
