# Child-safety runbook

Last updated: 2026-10-20

What the operator (Heitor) does with reports and child-safety holds. The law
behind it: ECA Digital (Lei 15.211/2025) arts. 27–30 and 33, Decreto
12.880/2026 arts. 36–39, Portaria MJSP 1.312/2026 (24 September, DOU
2026-09-28: the MJSP act the decree's art. 39 §§1–2 points to), and ECA art.
241-B §2 III, which allows a provider to possess such material only to report
it, and only until the authority receives it. Everything here runs in the
Supabase SQL editor of the production project as `postgres`; no API role can
read the tables below. This is not legal advice. Heitor decided the open
points himself, without counsel, on 2026-10-20 (§5); what is still UNVERIFIED
is in §5.

## 1. What reaches the operator

| Source | Where it lands | Target |
|---|---|---|
| A child-safety hold: input moderation flagged `sexual/minors` in a chat message | `private.child_safety_holds`, plus a block in `private.nina_ai_blocks` | read within 12 hours of `created_at` |
| "Denunciar resposta" on a Nina reply (adults) | `private.nina_reply_reports`; the reply is kept past retention for up to 90 days (`chat_messages.held_for_review_until`), and copied into the report if its house is deleted first | acknowledge within 48 hours |
| "Denunciar um problema" / "Escrever denúncia" (every age) | an identified email to the report mailbox, subject "Denúncia ECA Digital" | acknowledge within 48 hours |

The 48-hour acknowledgement of a report is Heitor's choice (the law sets none)
and is published on `https://ninai.app/denuncia/`. A report is never anonymous
(ECA Digital art. 29 §2): the email carries its author, and the in-app report
carries the reporter's account.

A hold has one target, whatever it turns out to hold: read it within 12 hours of
`created_at`. Portaria MJSP 1.312 art. 8 counts the reporting deadline from the
confirmed detection, and a detection by automated means counts (art. 8 §1), so
the clock starts at the moderation flag, and a human review may not postpone the
report (art. 8 §2). The deadline is 12 hours when a child may be at risk now, 72
hours for abuse material that is recent or not yet catalogued, and 7 days
otherwise; nobody knows which applies until someone reads the hold, so every
hold gets the shortest. A daily read (§6) cannot meet it: it needs an alert to
the operator when a hold lands, which does not exist yet (§5). Art. 8's
deadlines, art. 9's contents and art. 18's urgency flag bind only from the
Portaria's second stage (art. 35 II and §§3–4; the dates are in §5); removing
the content and preserving it (art. 23) bind now (art. 35 §5).

## 2. A child-safety hold

The system has already, with no person involved: sealed the message in
`private.child_safety_holds`, replaced it in the author's own thread with
"Mensagem não enviada.", answered with the generic refusal, blocked the
account's chat (`reason_code = 'child_safety_hold'`), and logged only
`child_safety_hold_created` and the run id. Moderation reads the pseudonymized
text, so a hold can come from an adult writing about a real child under a code.

**Open holds:**

```sql
select id, user_id, family_id, run_id, created_at, reported_at, authority_receipt_at
from private.child_safety_holds
where deleted_at is null
order by created_at;
```

**Read one** only when you are ready to decide, and never copy it anywhere but
the report itself:

```sql
select content from private.child_safety_holds where id = '<hold id>';
```

Then decide:

- **Apparent sexual abuse or exploitation material, or grooming** (Decreto
  12.880 art. 39 I; a kidnapping, or grooming toward serious harm or death, art.
  39 II and III, is reported the same way). Report it with the content, the time
  with its time zone, the account and house identifiers, whether a child may be
  at risk now, and nothing Nina does not hold. Portaria MJSP 1.312 art. 9 lists
  what a report carries; the kind of incident, the time with its zone and the
  sender's contact are required (art. 9 §1), and what Nina cannot obtain may be
  left out (art. 9 §2). Where it goes:

  - **Through NIDUS, once it takes reports.** The Portaria makes the Polícia
    Federal's Centro Nacional de Proteção à Criança e ao Adolescente (CNCA,
    the decree's "Centro Nacional de Triagem de Notificações", art. 1 §1) the
    receiver, through its NIDUS system, by API or an authenticated web portal
    (art. 6), once Nina is registered (art. 7). Mark the urgency field when a
    child may be at risk now (art. 18). NIDUS answers with a receipt and a
    protocol number, which is not a validation (art. 11 §1), and tells the
    sender the validation result later (art. 14 §4). It does not take
    Nina's reports yet (§5).
  - **Until then, the Ministério Público Federal (Heitor's decision of
    2026-10-20).** No regulation names an interim channel: Portaria art. 35
    stages only the sending, and art. 35 §5 keeps art. 23's removal and
    preservation binding now. Nina reports to one of the three receivers ECA
    art. 241-B §2 III names, the Ministério Público, through the MPF's online
    representação, which the MPF Serviços page now calls "Denúncias e
    pedidos de informação"
    (`https://www.mpf.mp.br/servicos/mpf-servicos-internas/denuncias`: tick
    "Li e aceito os termos acima descritos", then "Entrar com o GOV.BR"; read
    on 2026-10-20). It takes a company "por meio de seus representantes ou
    prepostos" at any hour. File it as the company's legal representative,
    signed in with Heitor's own gov.br account (level bronze or higher; the
    page says gov.br is for natural persons only, and the company's CNPJ goes
    into the manifestante's data after login). Receipt is
    immediate; a filing made out of hours is analysed the next working day.
    When a child may be at risk now, call 190 first, then file. A private
    chat is most likely a state matter (STF Tema 393 gives the federal courts
    material "acessível transnacionalmente"), so the MPF may pass the report
    to a state body; it has still reached a Ministério Público. Each filing:
    - names the incident, the time of the hold with its time zone, the
      account and house identifiers, the account's access records around
      that time (§7: read them with the hold id as the case reference), and
      that the message is sealed on Nina's server;
    - carries the held text, pasted straight from the SQL editor into the
      form, with no note, draft or file in between; clear the clipboard
      afterwards (Universal Clipboard copies it to Heitor's other Apple
      devices), and never download or print a receipt that repeats the text.
      If the MPF form turns out to e-mail or produce a PDF of what was
      written, describe the content instead and offer the sealed text on
      the MPF's request through a channel it names;
    - gives an e-mail address only Heitor reads, never the shared privacy
      mailbox;
    - asks whether the MPF wants the content kept longer (Portaria art. 23
      §3; ECA Digital art. 27 §3). Whatever it answers in writing is kept
      with the case.

    Keep the manifestation number and key: they are the receipt. Not used:
    the Polícia Civil's Delegacia Online (individuals only, and the competent
    station is the one where the facts happened, which Nina does not know);
    Comunica PF (federal attribution only; the Secom guide offers it only
    "quando houver repercussão internacional"); SaferNet (one public URL per
    report, no files); Disque 100 and the Conselho Tutelar (not receivers
    under art. 241-B §2 III, and Portaria art. 30 §4 lets them receive only a
    description); and NCMEC, a US nonprofit and none of the three receivers,
    so holding or sending the content for it is not sheltered, and not
    clearly the "autoridade internacional competente" whose receipt starts
    the deletion under Decreto 12.880 art. 39 §2 (art. 37 §§2–3 speak of
    reports a provider makes there "por força de lei").

    Holds are text only while attachments are off. Never download, view and
    save, or forward an image; attachments stay off until a hold can seal a
    file on the server and send it from there (§5).

  Record that you reported it:

  ```sql
  update private.child_safety_holds set reported_at = now() where id = '<hold id>';
  ```

  Then empty the content when the authority's answer lets it go:

  - **On the MPF (Heitor's decision of 2026-10-20):** delete the content once
    the MPF's receipt of the filing that carried it is in hand, unless the
    MPF asked in writing to keep it. That receipt is where ECA art. 241-B §2
    III's shelter ends ("até o recebimento do material"). No CNCA validation
    ever comes on this route, so Portaria art. 23's "até a validação" cannot
    be met here; Heitor accepts that departure (§5). A filing that only
    described the content has not delivered the material: keep the hold
    until the MPF asks for the text and receives it, or says it does not
    need it.
  - **Through NIDUS, once it takes reports:** the written rule is Portaria
    art. 23: keep the content until the CNCA validates the report, and
    delete it once NIDUS reports the validation (art. 23 §2, art. 14 §4).
    The receipt NIDUS gives at sending is not that moment (art. 11 §1), and
    the CNCA may ask for a correction before it validates (art. 12 I, art.
    14 §§2–3). Heitor decides this rule again when NIDUS opens (§5).

  On either route, a request from the police, an administrative authority or
  the Ministério Público to keep the content longer, naming the period and the
  purpose (Portaria art. 23 §3; ECA Digital art. 27 §3), keeps the hold only
  while the request is in force. Both provisions send it through Marco Civil
  art. 15 §2, which applies art. 13 §§3–4: keep the request itself secret, and
  ask the authority for the protocol of its court filing; the request lapses
  if no filing is shown within 60 days of it, or if the court refuses, and
  the content is then emptied at once, as on its own route. A court order
  keeps the hold for the period the order sets. Otherwise leave the hold as it
  is until the requested period ends. Then:

  ```sql
  update private.child_safety_holds
  set authority_receipt_at = now(), content = '', deleted_at = now()
  where id = '<hold id>';
  ```

  `authority_receipt_at` then holds the moment the authority's answer let the
  content go: the MPF's receipt now, the validation through NIDUS later, or
  the end of a longer keep an authority asked for in writing.

  Keep the account, its data and the hold's metadata for the period the
  authority asks (ECA Digital art. 27 §2); do not delete the account yourself
  unless the authority says to. The hold itself copies the account into the
  sealed `private.child_safety_preserved_accounts` the moment it is created
  (since 2026-10-20, migration `202610200001`), after the message is replaced
  by the marker, so the copy never repeats the sealed words: the Auth user id,
  the Apple `sub`, the email, the creation and last sign-in dates, the
  memberships, the chat and the memories. Without it, the daily retention
  deleted the account's chat after 30 days, and the person could clear their
  own thread and memories. If the person deletes the account from the app,
  the deletion still completes (Apple 5.1.1(v), LGPD art. 16 I), and
  `prepare_account_deletion` merges a fresh copy into the first one. Before
  the copy, the hold seals the same words wherever the account sent them
  again (a resend after a failed turn stores a new line). A failed copy never
  undoes the hold: it raises the warning `child_safety_copy_failed`, and the
  operator takes the copy again with
  `select private.preserve_child_safety_account('<auth user id>');`. When the house itself is deleted (the titular's
  `delete_family`, or an account deletion that leaves no adult, since
  2026-10-15), the same copy is taken first for every account the house held
  or that wrote in it (a person removed or gone from the house leaves their
  chat and memories there), so the house's chat and memories survive in it. Every later copy is merged
  into the first one, never dropped: when that account is deleted afterwards,
  the houses it joined and what it wrote since are added to what was kept.
  `preserved_at` stays the date of the first copy. The hold keeps its
  `user_id` and `family_id`, which carry no foreign key, and while the hold is
  open or reported, a new account signed in with the same Apple ID stays
  blocked from the chat. Retention keeps a preserved account until six months
  after `authority_receipt_at` (ECA Digital art. 27 §2 points to Marco Civil
  art. 15's six months; the Portaria sets no period of its own, art. 23 §§2–3;
  they run from `authority_receipt_at` by Heitor's decision of 2026-10-20,
  §5). The account's access records (§7) stay for the same period:

  ```sql
  select hold_id, user_id, apple_subject, email, preserved_at
  from private.child_safety_preserved_accounts
  order by preserved_at;
  ```

  Leave the chat block in place. The author has already seen the neutral
  marker and, on the next message, "A conversa está suspensa nesta conta.";
  follow the authority's guidance before telling them more.
- **A false positive** (a parent organizing a pediatric appointment, a school
  notice about sex education, a misread word). Empty the content at once and
  lift the block:

  ```sql
  update private.child_safety_holds
  set content = '', deleted_at = now()
  where id = '<hold id>';
  select private.operator_lift_ai_block('<auth user id>', 'false_positive');
  ```

  The person's chat works again on the next message. Their thread keeps "Mensagem
  não enviada." for that turn. If the account had already been deleted, the next
  daily retention run drops its preserved copy, because a hold emptied without a
  confirmed receipt is no longer preserved, and a new account with the same
  Apple ID is no longer blocked.

Retention purges a lifted block after one year. A hold with `deleted_at` set
keeps only its timestamps and identifiers.

## 3. A reported Nina reply

```sql
select
  reports.id,
  reports.reason,
  reports.created_at,
  coalesce(messages.text, reports.reply_text) as reply,
  coalesce(requests.text, reports.request_text) as request
from private.nina_reply_reports as reports
left join public.chat_messages as messages on messages.id = reports.message_id
left join public.nina_ai_runs as runs on runs.id = reports.run_id
left join public.chat_messages as requests on requests.id = runs.request_message_id
where reports.reviewed_at is null
order by reports.created_at;
```

When the house was deleted inside the review window (the titular's
`delete_family`, or an account deletion that leaves no adult, since
2026-10-15), the reply and the message that asked for it are gone from
`chat_messages`, so the report carries its own copy in `reply_text` and
`request_text`; `message_id`, `run_id` and `family_id` read null. Retention
clears both copies ninety days after the report, as it would the reply. Only
the reporter still erases a held reply early: while the house stands, by
clearing their own conversation or deleting their own account; once the house
is gone there is no conversation left to clear, so only the reporter's account
deletion (`prepare_account_deletion`) clears the copy. A report by the person
whose action deletes the house gets no copy, because the deletion takes their
conversation as clearing it would.

Read the reply in context only as far as the decision needs. Then record the
outcome, one of `no_action`, `prompt_changed`, `account_blocked`,
`reported_to_authority`:

```sql
update private.nina_reply_reports
set reviewed_at = now(), outcome = 'no_action'
where id = '<report id>';
```

- A reply that breaks the prompt's rules (sexual, violent, discriminatory,
  profane or drug content; medical, dietary or emotional guidance) is a product
  change: add the case to `supabase/functions/nina-chat/evals/pt-BR.json`, fix
  `_shared/nina-chat-policy.ts` with a source-text pin, and run the local eval.
- To stop an account's chat for misuse (Terms §12), block it; lift it later with
  `private.operator_lift_ai_block`:

  ```sql
  insert into private.nina_ai_blocks (user_id, reason_code)
  values ('<auth user id>', 'operator')
  on conflict (user_id) do update
  set reason_code = 'operator', created_at = now(), lifted_at = null, lift_reason_code = null;
  ```

Reviewed reports are purged after six months.

## 4. An email report

1. Acknowledge within 48 hours from the report mailbox.
2. Identify the account and house from what the reporter gives; ask for nothing
   more than the case needs, and never for a child's documents.
3. Decide, and tell the reporter what was done. Tell the author of the
   reported content the decision, the reasons, and whether a person or an
   automated process decided (ECA Digital art. 30; `/denuncia/` §3). Either may
   contest by replying to that email or writing to the report mailbox; a person
   reviews and answers with reasons, and an automated decision can always be
   reviewed by a person (LGPD art. 20). Until Nina has a second reviewer, the
   second look is Heitor's, done on fresh notes.
4. For apparent abuse material, follow §2's reporting path even though no hold
   exists; do not store the material in the mailbox longer than the report
   needs.
5. Misuse of the channel (false or abusive reports) may itself end in a block,
   as the Terms say.

## 5. Decided, UNVERIFIED and open

Heitor chose on 2026-10-19 to decide these points himself from Claude's
researched draft instead of asking counsel, and answered on 2026-10-20 ("1A
2A 3A"). Each decision below carries the risk he accepted.

- **The NIDUS stages.** The MJSP act is Portaria MJSP 1.312/2026 (24
  September, DOU 2026-09-28, Seção 1 Extra C, edição 183-C, in force on
  publication; read on 2026-10-19 at bibliotecadigital.mj.gov.br and the
  DOU). Its sending duties start in two stages, each opened by an act of the
  Polícia Federal's Director-General (art. 35): first, registration in NIDUS
  (that act within 30 days of the Portaria's publication, then 60 days to
  register); second, reports through NIDUS on art. 8's deadlines (that act up
  to 90 days after registration closes, then up to 120 days to comply). A DOU
  full-text search for "NIDUS" on 2026-10-19 found only the Portaria, so the
  first act is not out. Its last day is 2026-10-28 by the strict count (the
  MJSP's own news says 29 October). If each act comes on its last allowed
  day, registration closes on 2026-12-27 and reporting binds from
  2027-07-25; every later date counts from the earlier act's actual
  publication, so a late act moves them all. Watch the DOU and gov.br/pf
  until the act appears, then register at once. Registration (art. 7) takes
  the company's identification; the products, services, domains or apps it
  covers in Brazil (the iOS app `com.heitor.nina` and `ninai.app`); a legal
  representative; a technical contact; and a law-enforcement contact "para
  comunicações ordinárias e de emergência", a phone and e-mail answered at
  any hour. One person may hold every role (art. 7 §2). All of it goes into
  NIDUS and never into this repository.
- **The interim channel is the Ministério Público Federal (decided
  2026-10-20).** §2 says how. The choice was between the two receivers ECA
  art. 241-B §2 III names that a company can reach: the MPF's online
  representação (always open, national, immediate receipt) and the Polícia
  Civil in person (office hours, and the competent station is where the
  facts happened, which Nina does not know). Its cost: a private chat is
  most likely a state matter, so the MPF may pass the report on, which is
  slower. Not read: the Comunica PF form (HTTP 403 on 2026-10-19), and
  whether the MPF form e-mails or prints back what was written, which
  Heitor checks once without sending anything. Heitor also asks the Polícia
  Federal in writing, with no content and no user data, whether the CNCA
  admits an exceptional means before NIDUS opens (Portaria art. 6 §1 III);
  a route it offers replaces the MPF. The channel ends when NIDUS takes
  Nina's reports.
- **On the MPF, the content goes at the MPF's receipt (decided
  2026-10-20).** This follows ECA art. 241-B §2 III, a law, whose shelter
  ends "até o recebimento do material", and departs from Portaria art. 23,
  which binds now (art. 35 §5) and keeps the content "até a validação" by
  the CNCA, which never comes on this route. Every filing asks the MPF
  whether to keep it longer, so a written request overrides the default.
  Deleting at either moment also departs from a literal reading of ECA
  Digital art. 27 §2 I, which keeps for six months the content "gerado,
  carregado ou compartilhado" by a user named in a report; Decreto 12.880
  art. 39 §2 orders that same content deleted on confirmed receipt, and no
  text resolves the clash between the two laws. The rule rests on art.
  241-B, which is also a law, not on the decree ranking higher.
- **Through NIDUS, the written default is art. 23's validation**, not the
  receipt, until Heitor decides again when NIDUS opens. A literal reading of
  art. 241-B §2 III puts the days between the NIDUS receipt and the
  validation outside its shelter; art. 23's express "até a validação" and
  the CNCA's power to ask for a correction first (art. 12 I) argue for it.
  The same reading applies to grooming or kidnapping content: Decreto art.
  39 §2 and Portaria art. 23 §2 name only exploitation and abuse material,
  and art. 241-B §2 only arts. 240, 241, 241-A and 241-C, so Nina handles
  the rest the same way. Whether a text message is a "registro" under art.
  241-B is open.
- **The six months run from `authority_receipt_at` (decided 2026-10-20).**
  No text says when they start: ECA Digital art. 27 §2 borrows Marco Civil
  art. 15's six months, and Portaria art. 23 §2 keeps account data, records
  and metadata after the validation for as long as those laws require.
  `authority_receipt_at` is the latest moment Nina can document (the MPF's
  receipt now, the validation later, or the end of a longer keep), so the
  six months never end early, and LGPD art. 16 I covers the extra days.
  `private.child_safety_hold_is_preserved` already counts this way.
- **What the six months hold.** Since migration `202610200001` (2026-10-20)
  the hold copies the account the moment it is created (§2), and the
  account's access records stay while the hold is preserved (§7).
- **Attachments stay off** (`NINA_ATTACHMENTS_ENABLED` in the app and in
  `nina-chat`) until a hold can seal a file on the server and send it from
  there: `hold_nina_chat_run_for_child_safety` keeps only the message text,
  and any route that took a file today would push it through Heitor's own
  computer. Both decisions above are taken again before attachments go on.
- **An alert to the operator when a hold lands** does not exist. The 12-hour
  target in §1 needs one, and from the second stage art. 8 makes 12 hours the
  legal deadline whenever a child may be at risk now.

Read from their official sources on 2026-10-19, and right: CVV 188 (cvv.org.br:
free, 24 hours a day), and the 190 and Disque 100 numbers on `/denuncia/` (the
Secom guide above names 190 for the Polícia Militar and Disque 100 for the
Ouvidoria Nacional de Direitos Humanos).

## 6. Signals to read every day

Nothing alerts the operator yet: a hold, a reported reply and an email report
land silently, and the 48-hour acknowledgement in §1 is kept only if someone
looks. A daily read cannot keep a hold's 12-hour target (§1); only an alert
can (§5). So, until an alert exists (an email or a push to the operator when a
row lands), read these every day, launch day included
(`docs/production-launch-runbook.md` §8). This replaced a monthly read on
2026-10-19.

```sql
select id, created_at from private.child_safety_holds
where deleted_at is null and reported_at is null
order by created_at;

select id, reason, created_at from private.nina_reply_reports
where reviewed_at is null
order by created_at;
```

Each row is work for §2 or §3 today; read the mailbox for §4 at the same
time. Then, for the review cycle in
`docs/privacy/avaliacao-impacto-criancas.md` §12, the totals:

```sql
select count(*) filter (where deleted_at is null) as open_holds,
       count(*) filter (where reported_at is not null) as reported
from private.child_safety_holds;
select reason, outcome, count(*) from private.nina_reply_reports group by 1, 2 order by 1, 2;
select reason_code, count(*) filter (where lifted_at is null) as active from private.nina_ai_blocks group by 1;
```

When an alert exists, record here what it watches, and the daily read can go
back to a weekly one.

## 7. Access records (Marco Civil art. 15)

Since migration `202610200001` (2026-10-20, Heitor's choice 3A), Nina keeps
the access records Marco Civil art. 15 asks of an application provider: the
date and time, with time zone, of each use of the app and the IP address it
came from, per account, for six months, under seal (art. 15 caput: "sob
sigilo, em ambiente controlado e de segurança"). They live in
`private.app_access_records`, which no API role can read. `ensure_current_profile`
writes them through `private.record_app_access`; it runs on every app load,
pull and realtime refresh, and in every RPC that returns the home context. The
app writes tasks, shopping items, sections and categories straight to their
tables, so such a write is covered only by the load or refresh around it, and
a record's `last_seen_at` can be earlier than the person's last write. A use
from the same address within thirty minutes extends the last row instead of
adding one, and one account adds at most 500 new address rows a day (past
that, the warning `app_access_record_cap_reached`). No Edge Function
reaches `ensure_current_profile`, so every address is the phone's, never the
server's. A failure there never stops the app from loading; it raises the
warning `app_access_record_failed` with the SQLSTATE alone.

The address is Cloudflare's `cf-connecting-ip` and nothing else
(`private.request_client_address`). On 2026-10-20 a request to production
that carried its own `CF-Connecting-IP` was refused by Cloudflare with "error
code: 1000" before it reached Supabase, while a forged `X-Forwarded-For`
passed through, so only the first is trusted. `cf-connecting-ipv6` is read
only when `cf-connecting-ip` holds a Class E pseudo address (Cloudflare's
Pseudo IPv4 mode), never beside a real one. Two gaps stay open:

- **The source port.** Decreto 8.771 art. 15-A (added by Decreto 12.975/2026,
  in force since 2026-07-20) extends the duty to the "porta lógica de origem"
  whenever it is needed to identify the terminal, as the STJ had read
  Marco Civil art. 5 VIII for IPv4 since REsp 1.784.156/SP (2019). No header
  behind Supabase's gateway carries the client's port, so `source_port` stays
  null. An IPv6 address usually identifies the line alone; an IPv4 address
  behind a carrier's shared NAT does not. Getting the port would mean routing
  the app's API traffic through a Cloudflare zone Nina controls, which needs
  a build; until then the records hold the IP and the time only, and a court
  is told so. The decree is challenged (ADI 7981 at the STF, no injunction
  on the docket on 2026-10-20; PDLs 398, 460, 467 and 470/2026 in the Senate
  and 454/2026 in the Câmara), and its art. 15-A stays in force meanwhile.
- **The chat turn itself.** A message to Nina goes to the `nina-chat` Edge
  Function, which never reaches `ensure_current_profile`, so nothing records
  the address of the turn. The record of the app use around it (the load or
  refresh before it, and any after it) is what shows where the person was;
  its `last_seen_at` may end before the hold's `created_at`.

The records carry no foreign key, so they outlive the account: a deletion from
the app leaves them for their six months (LGPD art. 16 I), as the privacy page
says (§8). Retention deletes a row six months after its `last_seen_at`, except
while `kept_until` is in the future or a hold on that account is preserved
(§2).

**Hand them over only on a court order** (art. 10 §1, art. 15 §3, art. 22),
never to a private requester, the police or the Ministério Público without one.
The one exception is the child-safety report the law requires (ECA Digital
art. 27; Portaria art. 9 X lists the IP addresses with their times): a report
under §2 carries the held account's records around the hold. Read them
only through the operator function, never with a plain `select`: Decreto
8.771 art. 13 III asks for an inventory of every access to the records, and
the function writes one line per read into `private.app_access_record_reads`
(when it started and finished, who read and the database role, the case
reference, the account or address, the period and how many rows came back;
kept five years). `postgres`, the SQL editor's role, owns the table, so a plain
`select` would read it unlogged; nothing in the database stops that role, so
the rule is this procedure. Name yourself, the case, the account, the address
or both, and the period the order covers:

```sql
select * from private.operator_read_access_records(
  'Heitor',
  '<case reference, e.g. the court case number or the hold id>',
  '<auth user id>'::uuid,
  null,
  '<from>'::timestamptz,
  '<to>'::timestamptz
);

select * from private.operator_read_access_records(
  'Heitor',
  '<case reference>',
  null,
  '<ip address>'::inet,
  '<from>'::timestamptz,
  '<to>'::timestamptz
);
```

Each row is a stretch of use from one address, from `first_seen_at` to
`last_seen_at`.

Times are `timestamptz`; give them to the authority in
`America/Sao_Paulo` with the offset written out. When the police, the
administrative authority or the Ministério Público asks Nina to keep records
longer (art. 15 §2, a "requerimento cautelar"), keep the asked rows and hand
over nothing yet: the authority has 60 days from its request to file for the
court order (art. 13 §3, which art. 15 §2 applies), Nina keeps the request
itself secret (art. 13 §4), and the request lapses if the court refuses or
nothing is filed in those 60 days. Set `kept_until` to the end of what the
request asks, or to 60 days from it when it names no date, and move it when
a court order arrives:

```sql
update private.app_access_records
set kept_until = '<date>'
where user_id = '<auth user id>';
```
