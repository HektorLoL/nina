# Age Rating (Classificação Indicativa) - Nina

Last updated: 2026-09-29

Nina aims for an all-ages rating: "Livre" in Brazil, AL on Apple's Brazil
self-rating. That is a target, not a guarantee: Apple computes the App Store
rating from the questionnaire, and the Ministério da Justiça e Segurança
Pública (MJSP) can assign its own, which then replaces Apple's pictogram.
Guideline 2.3.6 asks for honest answers, so every answer below carries its
rationale and the rating it risks if App Review reads the feature differently.

Heitor decided on 2026-09-29 (D1): aim for "Livre"; if Apple or the MJSP rate
Nina 10 or 12, accept it, keep the AI chat for adults, and change the one rating
constant (§8).

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
- LoginView and the loading screen (`AppLoadingScreen`);
- the minor's settings row "Classificação indicativa";
- the footer of every page of `ninai.app`;
- Terms §4, through `ninaRating.termsPhrase`;
- `/familias/` §11.

## 2. Apple questionnaire answers

| Item | Answer | Rationale | Risk if App Review disagrees |
| --- | --- | --- | --- |
| In-app Parental Controls | Yes | A live guardian sets alerts, quiet hours and a daily limit, sees 7 days of use, exports and deletes (ECA Digital arts. 17-18). | Stays AL on Apple's Brazil table. |
| In-app Age Assurance | Yes | Declared Age Range, recorded only through an App Attest-verified endpoint; server gates for every adult feature. | Stays AL. |
| Unrestricted Web Access | No | No web view or browser. | None. |
| Advertising | No | No ads and no ad SDK. | None. |
| Social Media | No | No feed, no discovery, no public profile. Required question since September 2026. | None expected. |
| User-Generated Content | No | Content is visible only inside one household of at most 8 people an adult approved; minors author nothing. | A6. |
| Messaging and Chat | No | There are no messages between people. The chat is one adult with Nina. | A12 if shared tasks are read as group posting. |
| Profanity or crude humor; horror | None | The AI is reachable only by Apple-confirmed adults, is bound by prompt rules and output moderation, and is tested in the local eval. | A10. |
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
2. Do features the server gates to users the Declared Age Range API confirms as
   18 or older count toward the questionnaire answers?
   Answer: pending.
3. Does "some features are only for adults" in the Terms count as a minimum age
   requirement that forces an override?
   Answer: pending.
4. Sign in with Apple is the only sign-in, and the chat and the subscription
   open only for an adult whose age Apple confirmed. How should the reviewer
   reach those features?
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
> notifications, quiet hours and a daily time limit. There is no user-to-user
> messaging, feed, web view or advertising. Test accounts: [trusted adult],
> [declared adult], [minor], [unknown].

Test accounts are marked with `private.operator_set_age_status`, because App
Attest and Declared Age Range do not run on the Simulator or on a reviewer's
device in the expected way. Sign in with Apple is the only sign-in, so there is
no password to hand the reviewer, and the "Test accounts" line above has no
working form yet: how the reviewer reaches the adult features is question 4 of
`docs/production-launch-runbook.md` §6, open until App Review answers it.

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
| D.2.1 / D.3.1 | AI dialogue (6 and 10) | Minors never reach the chat; adults only, gated on the server | E.1.10, E.1.13 |
| D.4.1 | UNVERIFIED: read the Guia before filing | Map it when the Guia text is at hand | - |
| D.5.1 | Purchases with money in a utility app (14) | Only Apple-confirmed adults reach the paywall; the server refuses other buyers | E.1.10, E.1.11 |
| D.5.2 | Communication between users without parental consent or age assurance (14) | No messages between people; entry to a house needs an adult's approval, and a guardian's for a minor | E.1.10 |
| D.5.3 | AI in a secondary role does not fit the AI tendency | Nina's AI assists a household organizer; it proposes, a person confirms | - |
| D.6.1 | Processing that breaks the purpose principle (16) | Age data is single-purpose; the OpenAI transfer stays within the consented purpose; minors' data never goes | E.1.18 |
| D.6.5 | Nagging notifications (16) | One nudge per task for adults only; none for minors; forced quiet hours for minors | E.1.12 |
| D.7.1 | A generative tool that can produce sexual or violent text, or clinical or emotional guidance (18) | Prompt rules, output moderation, deterministic medical refusal; adults only | E.1.13 |

Attenuators on by default: E.1.10 access control and age assurance, E.1.11
consumption control, E.1.12 time control, E.1.13 content blocking, E.1.18 data
security.

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
  on-by-default safeguards lower that. A realistic fallback is 10 to 14.

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
feature as adult content, and the product question goes back to Heitor.

## 9. Records to keep here

- App Review's answers to §3, with dates.
- The análise prévia protocol number and outcome.
- The ClassInd registration of representative details.
- The rating Apple shows after submission, and any MJSP assignment.
