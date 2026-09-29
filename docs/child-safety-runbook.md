# Child-safety runbook

Last updated: 2026-09-29

What the operator (Heitor) does with reports and child-safety holds. The law
behind it: ECA Digital (Lei 15.211/2025) arts. 27–30 and 33, Decreto
12.880/2026 art. 39 §§1–2, and ECA art. 241-B §2 III, which allows possessing
such material only to report it. Everything here runs in the Supabase SQL
editor of the production project as `postgres`; no API role can read the tables
below. This is not legal advice, and three points are UNVERIFIED (§5).

## 1. What reaches the operator

| Source | Where it lands | Target to acknowledge |
|---|---|---|
| A child-safety hold: input moderation flagged `sexual/minors` in a chat message | `private.child_safety_holds`, plus a block in `private.nina_ai_blocks` | review within 48 hours, sooner when you can |
| "Denunciar resposta" on a Nina reply (adults) | `private.nina_reply_reports`; the reply is kept past retention for up to 90 days (`chat_messages.held_for_review_until`) | 48 hours |
| "Denunciar um problema" / "Escrever denúncia" (every age) | an identified email to the report mailbox, subject "Denúncia ECA Digital" | 48 hours |

The 48-hour acknowledgement is Heitor's choice (the law sets none) and is
published on `https://ninai.app/denuncia/`. A report is never anonymous (ECA
Digital art. 29 §2): the email carries its author, and the in-app report carries
the reporter's account.

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

- **Apparent sexual abuse or exploitation material, or grooming.** Report it to
  the Polícia Federal (the intake channel is UNVERIFIED, §5) with the content,
  the time and the account and house identifiers, and nothing Nina does not
  hold. Record that you reported it:

  ```sql
  update private.child_safety_holds set reported_at = now() where id = '<hold id>';
  ```

  When the authority confirms receipt, record it and empty the content — Nina
  keeps no copy past receipt (Decreto 12.880 art. 39 §2):

  ```sql
  update private.child_safety_holds
  set authority_receipt_at = now(), content = '', deleted_at = now()
  where id = '<hold id>';
  ```

  Keep the account, its data and the hold's metadata for the period the
  authority asks (ECA Digital art. 27 §2); do not delete the account yourself
  unless the authority says to. If the person deletes it from the app, the
  deletion still completes (Apple 5.1.1(v), LGPD art. 16 I), but first
  `prepare_account_deletion` copies the account into the sealed
  `private.child_safety_preserved_accounts`: the Auth user id, the Apple `sub`,
  the email, the creation and last sign-in dates, the memberships, the chat and
  the memories. The hold keeps its `user_id` and `family_id`, which carry no
  foreign key, and while the hold is open or reported, a new account signed in
  with the same Apple ID stays blocked from the chat. Retention keeps a
  preserved account until six months after the authority confirmed receipt
  (Marco Civil art. 15, the period art. 27 §2 points to; UNVERIFIED until the
  MJSP act, §5):

  ```sql
  select hold_id, user_id, apple_subject, email, preserved_at
  from private.child_safety_preserved_accounts
  order by preserved_at;
  ```
 Leave the chat block in place. The author has
  already seen the neutral marker and, on the next message, "A conversa está
  suspensa nesta conta."; follow the authority's guidance before telling them
  more.
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
select reports.id, reports.reason, reports.created_at, messages.text
from private.nina_reply_reports as reports
left join public.chat_messages as messages on messages.id = reports.message_id
where reports.reviewed_at is null
order by reports.created_at;
```

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

## 5. UNVERIFIED — launch blockers

- **The Polícia Federal intake** for apparent child sexual abuse material (the
  spec names the "Centro Nacional de Triagem") and the MJSP act that governs it
  were not confirmed from a primary source. Confirm the channel and how to
  submit before launch, and write it into §2.
- **The retention period after reporting** (ECA Digital art. 27 §2) depends on
  that act. The code keeps a preserved account six months after receipt
  (`private.child_safety_hold_is_preserved`); change that one function if the
  act says otherwise.
- **CVV 188**, shown to minors and in the prompt, must be confirmed on
  cvv.org.br. The 190 and Disque 100 numbers on `/denuncia/` likewise.

## 6. Signals to read monthly

```sql
select count(*) filter (where deleted_at is null) as open_holds,
       count(*) filter (where reported_at is not null) as reported
from private.child_safety_holds;
select reason, outcome, count(*) from private.nina_reply_reports group by 1, 2 order by 1, 2;
select reason_code, count(*) filter (where lifted_at is null) as active from private.nina_ai_blocks group by 1;
```

These feed the review cycle in `docs/privacy/avaliacao-impacto-criancas.md` §12.
