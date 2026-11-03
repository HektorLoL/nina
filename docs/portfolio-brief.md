# Nina — portfolio brief

Last updated: 2026-11-03

A short, self-contained description of Nina for a reader who has never seen
the code: what the product is, why it exists, how it is built, and what was
hard. The full operating manual is `CLAUDE.md`; this file leaves out its
internal detail on purpose.

## In one sentence

Nina is a Brazilian-Portuguese iPhone app where a family tells a character
named Nina what is weighing on the household, and she turns it into shared
tasks, reminders, groceries and undated "seeds", while quietly showing who is
carrying more of the house.

## The problem

Task apps already exist. What they do not remove is the **cost of
negotiating** the tasks: asking a partner to take something on is an
interpersonal act, and in many two-adult homes one person ends up as the
household's project manager without anyone deciding it.

Nina routes that coordination through a neutral third party. You say "the
boleto is due on the 20th and someone needs to buy diapers", and Nina proposes
the reminder and the shopping item. Assigning work stops being a request from
one person to another.

The emotional goal is **relief, not productivity**. The design north star is a
board called "conversa → alívio" (conversation → relief).

## Who it is for

- Brazilian families, up to 8 people plus pets, iPhone first.
- Built for the primary domestic manager in a two-adult home.
- Children and pets are profiles managed by adults; a teenager can hold a
  guardian-approved account that shows only their own tasks.
- Brazil only: pt-BR copy, prices in reais, servers in São Paulo, and the
  Brazilian privacy and child-protection laws (LGPD, ECA Digital) as the
  compliance regime.

## Product ideas worth noticing

1. **Nina proposes; humans confirm.** Every AI output is a proposal card the
   person accepts, edits or dismisses. Nina never changes household data by
   herself. This is the whole trust proposition, and it is a tested rule: the
   AI evaluation fails if a single change happens without a human
   confirmation.
2. **Seeds ("sementes").** An intention you are allowed to have *without* a
   date ("one day we should paint the hall"). Most task apps punish undated
   items; Nina names them and refuses to invent a date.
3. **Nina is a household member who doesn't take a slot.** She appears in the
   member list as part of the house ("Não ocupa vaga."), not as a tool.
4. **Overload signal ("Sinal de sobrecarga").** A portrait of who holds which
   open tasks, subtitled "Um retrato para conversar, não para cobrar" (a
   picture to talk about, not to blame). It only draws when the data is
   conclusive, counts adults only, and the weekly AI summary is forbidden from
   assigning blame, intent or moral value.
5. **A voice, not an assistant.** Short, warm sentences, no exclamation marks,
   no emoji. On any screen a child can see, Nina is described in the third
   person as a computer program, never as a friend.

## How it is built

Four surfaces, one product:

| Surface | Stack |
|---|---|
| iOS app | SwiftUI (iOS 26.4+), one central `@Observable` store, about 38,000 lines of Swift |
| Database | Supabase Postgres with row-level security on every table and privileged actions only through audited database functions (57 migrations, about 22,000 lines of SQL) |
| Server logic | 6 Deno edge functions (AI chat, daily maintenance, account deletion, age signal, two App Store functions), about 15,000 lines of TypeScript |
| Website | Astro static site on a Cloudflare Worker at `ninai.app`, strict content security policy |

Other choices:

- **One sign-in door:** Sign in with Apple only. No passwords, no email codes.
- **One third-party iOS dependency** (the Supabase client). No analytics, no
  crash reporter, no ads, so the App Store label "Data Used to Track You: No"
  is true by construction.
- **The AI** runs on an OpenAI model through the Responses API with a strict
  JSON schema, read-only tools, input and output moderation, and a
  pseudonymizer that replaces children's and other people's names before
  anything leaves the server.
- **Design system "azulejo"**, built from 47 design boards: light only, one
  brand blue per screen, colour reserved for meaning (terracotta for
  lateness, red for errors, green only for things a human confirmed).
- **Premium subscription** (R$ 24,90/month) through StoreKit, verified
  server-side and shared by the whole house.

## What was hard

- **Trust under a hostile client.** The app ships only a public key. Every
  table is protected by row-level security and every privileged operation is
  a server function, so a modified app gains nothing. An early bug let a
  member promote themselves to owner; the fix removed the client's write
  access to those tables entirely.
- **Children and age.** Brazil's 2026 child-protection rules shaped the
  architecture: a server-held age band written only after an Apple App Attest
  check, a ratchet that can always move an account toward more protection but
  never less without proof, guardian approval as one atomic step, and no
  child's name or tasks ever reaching the AI provider.
- **Dates in spoken Portuguese.** "Dia 20", "sexta às 14h", "depois de
  amanhã de manhã": a reminder with a label but no real date never fires.
  The fix reads dates by one shared rule on three layers (the AI prompt, a
  server fallback and the phone), and the reader refuses to guess rather than
  book the wrong day.
- **Money limits on AI.** The monthly AI budget is a database constraint, not
  application logic, with a per-house share so one heavy household cannot
  pause everyone else.
- **Edge runtime surprises.** Apple's own receipt-verification library and
  part of WebCrypto do not work in the Supabase edge runtime, which made
  every real purchase and every real iPhone fail while all tests passed. Both
  were replaced with verification code that runs there, and tested against
  real Apple data.

## How it was made

- Solo project by a product-side founder, built with AI coding agents (Claude
  Code) doing most of the implementation under a detailed operating manual
  (`CLAUDE.md`) that records every product rule and every lesson learned.
- Started 2026-06-18; about 230 commits on a trunk-based `main` with CI on
  every push.
- Tested in four layers: about 640 XCTest cases for the app, about 880
  pgTAP assertions for the database and its permissions, about 400 Deno
  tests for the server and website, and a release preflight tool that scans
  the source and the final iOS archive for secrets, debug code and broken
  invariants.
- An AI evaluation suite (38 cases, run locally, never on real data) gates
  model and prompt changes: task type, correct dates, safety replies, and
  zero private-data leaks.
- Status in November 2026: on TestFlight (build 20 is the release candidate),
  backend live in production, App Store listing prepared, waiting on the
  official Brazilian age rating before release.
