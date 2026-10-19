# Child-safety runbook

Last updated: 2026-10-19

What the operator (Heitor) does with reports and child-safety holds. The law
behind it: ECA Digital (Lei 15.211/2025) arts. 27–30 and 33, Decreto
12.880/2026 arts. 36–39, Portaria MJSP 1.312/2026 (24 September, DOU
2026-09-28: the MJSP act the decree's art. 39 §§1–2 points to), and ECA art.
241-B §2 III, which allows a provider to possess such material only to report
it, and only until the authority receives it. Everything here runs in the
Supabase SQL editor of the production project as `postgres`; no API role can
read the tables below. This is not legal advice; what is still UNVERIFIED or
waits on counsel is in §5.

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
  - **Until then, the interim channel. UNVERIFIED: no regulation names one, and
    the operator or counsel decides which one Nina uses (§5).** The options on
    record: the decree also accepts a report to a foreign triage centre whose
    reports the Polícia Federal can reach, the "autoridade internacional
    competente" (art. 39 §§1–2, art. 37 §§2–3; Portaria art. 6 §2), though art.
    37 §2 speaks of reports a provider makes there "por força de lei". The
    federal government's guide (Secom, "Como denunciar conteúdos criminosos
    online", gov.br/secom) offers the Polícia Federal's Comunica PF form for
    online child sexual abuse only "quando houver repercussão internacional",
    and the PF's own page for it sends any crime outside its federal attribution
    to the Polícia Civil. The form itself was never read (it answered 403 on
    2026-10-19). The same guide names the nearest Polícia Civil station, the
    Ministério Público, Disque 100, the Conselho Tutelar and SaferNet, and 190
    for danger now. ECA art. 241-B §2 III shelters a provider's possession only
    for a report to the police, the Ministério Público or the Judiciary.

  Record that you reported it:

  ```sql
  update private.child_safety_holds set reported_at = now() where id = '<hold id>';
  ```

  Then empty the content by one of two rules, which counsel signs off before
  launch (§5):

  - **Through NIDUS:** keep the content until the CNCA validates the report
    (Portaria art. 23), and delete it once NIDUS reports the validation (art.
    23 §2, art. 14 §4). The receipt NIDUS gives at sending is not that moment.
  - **On the interim channel:** no validation ever comes, so delete it once
    the authority confirms receipt (Decreto 12.880 art. 39 §2; ECA art. 241-B
    §2 III shelters possession only until then).

  On either route, when the authority asks Nina to keep it longer, naming the
  period and the purpose (Portaria art. 23 §3; ECA Digital art. 27 §3), leave
  the hold as it is until that period ends. Then:

  ```sql
  update private.child_safety_holds
  set authority_receipt_at = now(), content = '', deleted_at = now()
  where id = '<hold id>';
  ```

  `authority_receipt_at` then holds the moment the authority's answer let the
  content go: the validation through NIDUS, the receipt on the interim channel.

  Keep the account, its data and the hold's metadata for the period the
  authority asks (ECA Digital art. 27 §2); do not delete the account yourself
  unless the authority says to. If the person deletes it from the app, the
  deletion still completes (Apple 5.1.1(v), LGPD art. 16 I), but first
  `prepare_account_deletion` copies the account into the sealed
  `private.child_safety_preserved_accounts`: the Auth user id, the Apple `sub`,
  the email, the creation and last sign-in dates, the memberships, the chat and
  the memories. When the house itself is deleted (the titular's
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
  when the six months start is UNVERIFIED, §5):

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

## 5. UNVERIFIED and open — launch blockers

- **The NIDUS stages.** The MJSP act is Portaria MJSP 1.312/2026 (24
  September, DOU 2026-09-28, Seção 1 Extra C, in force on publication; read
  on 2026-10-19 at bibliotecadigital.mj.gov.br). Its sending duties start in
  two stages, each opened by an act of the Polícia Federal's Director-General
  (art. 35): first, registration in NIDUS (that act within 30 days of the
  Portaria, then 60 days to register); second, reports through NIDUS on art.
  8's deadlines (that act up to 90 days after registration closes, then up to
  120 days to comply). If each act comes on its last allowed day, registration
  closes on 2026-12-27 and reporting binds from 2027-07-25; an earlier act
  brings them forward. Whether the first act is out is UNVERIFIED: watch
  the Polícia Federal's site and the DOU, and register as soon as it is.
  Registration takes the company's identification, a legal representative, a
  technical contact and a law-enforcement contact (art. 7), which go into
  NIDUS and never into this repository.
- **The interim channel** (§2) is UNVERIFIED: no regulation names one, the
  Comunica PF form was never read and the government's guide limits it to cases
  "com repercussão internacional", and a foreign centre counts only on the
  decree's terms. The operator or counsel decides it before launch and writes it
  into §2.
- **Counsel signs off the two deletion rules** in §2, and the window under
  NIDUS between the receipt, where ECA art. 241-B §2 III's shelter ends, and
  the validation, until which Portaria art. 23 keeps the content.
- **When the six months start.** The Portaria sets no retention period of its
  own: art. 23 §2 keeps account data and metadata as long as Marco Civil and
  ECA Digital require, and §3 lets the authority ask for longer. ECA Digital
  art. 27 §2 points to Marco Civil art. 15's six months without saying
  whether they run from the report, the receipt or the validation. The code
  counts them from `authority_receipt_at`
  (`private.child_safety_hold_is_preserved`); change that one function if
  counsel reads otherwise.
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
