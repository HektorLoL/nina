# Age contest runbook

Last updated: 2026-09-29

Decreto 12.880/2026 art. 27 gives a person a way to contest the age a service
assigned them. In Nina the age is a band held on the server
(`private.account_age_status`), written by `record_age_signal` from Apple's
Declared Age Range, or declared by a guardian when they approve a minor. This
runbook is how the operator (Heitor) answers a contest. It runs in the Supabase
SQL editor of the production project, as `postgres`; no client role can call
any function below.

Nothing here ever stores a birth date, a range bound or a document. If a person
sends a document, do not keep it: answer, then delete the email's attachment.

## 1. Where a contest comes from

- **In the app**, "Minha idade está errada" (minor settings) offers "Compartilhar
  de novo" when Apple set the band, tells the person to talk to their guardian
  when a guardian set it, and always shows the privacy mailbox.
- **By email**, to the privacy mailbox (`PUBLIC_NINA_PRIVACY_CONTACT_EMAIL`,
  `privacidade@ninai.app` in the app). Reply within 15 days (LGPD art. 19 II);
  for a minor, the guardian exercises the right (art. 18 §3).

Ask for the email address of the Nina account (the one Apple shared, possibly a
private relay address) and nothing else. Find the account:

```sql
select id, email, created_at from auth.users where email = '<address>';
```

## 2. Read what Nina holds

```sql
select * from private.effective_age('<auth user id>');
```

`band_source` says who set the band: `apple` or `guardian`. `assurance` says how
(`confirmed`, `self_declared`, `guardian_declared`, `operator`, `none`).
`has_record = false` means Nina never received an answer from this iPhone and
treats the account as the youngest band.

## 3. Decide

Always choose the more protective reading when the evidence is unclear
(Decreto 12.880 art. 25 §4).

- **The person says they are older, and Apple set the band.** Ask them to share
  the range again from the app ("Compartilhar de novo"). If their Apple Account
  now says 18+ and Apple confirmed it, the app records it and the ratchet lets
  it through; a self-declared 18+ is refused for an account that was ever a
  minor. If Apple keeps answering the old band, the fix is in their Apple
  Account (the pt-BR Settings path is UNVERIFIED; do not quote one), not in
  Nina.
- **The person says they are older, and a guardian set the band.** The guardian
  who approved them can choose an older band only for an account-less profile.
  For an account, the contest goes to the guardian first; if the guardian
  agrees in writing from their own Nina account email, use step 4 below.
- **The person says they are younger.** Accept it at once: a younger band is
  always the protective direction. The app does this by itself when a new share
  says so; the operator does it with step 4.
- **Test and TestFlight accounts.** App Attest and Declared Age Range do not run
  on the Simulator, so testers are marked with step 4 and reason `testflight`.

## 4. Apply the decision

```sql
-- An adult Heitor has verified, or a tester (trusted: chats, buys, acts for minors).
select private.operator_set_age_status('<auth user id>', 'adult', null, true, 'age_contest');

-- An adult who is not verified beyond the person's word (runs a house only).
select private.operator_set_age_status('<auth user id>', 'adult', null, false, 'age_contest');

-- A minor, with the band: 'under_12', '12_15' or '16_17'.
select private.operator_set_age_status('<auth user id>', 'minor', '12_15', false, 'age_contest');
```

The reason is a stable lowercase code (`age_contest`, `testflight`,
`guardian_confirmed`), never free text about the person. The record's assurance
becomes `operator` for a trusted adult and `self_declared` for an untrusted one.

What each move does, with no further step:

- **To adult:** every guardianship over this account ends with
  `reached_majority`, its minor consents are withdrawn, its supervision settings
  are deleted and its `household_role` becomes `adult`. The app shows "Agora a
  conta é sua." once.
- **To minor or a younger band:** live AI consents are withdrawn (`age_status`),
  admin rights drop to member, the role becomes `child` or `teen`, pending Nina
  proposals are rejected, and optional profile fields are cleared. An account
  with no live guardian reads "Sua conta está pausada." until a guardian of the
  house declares with "Também sou responsável" / "Sou responsável".

**Remove the profile photo yourself after a move to minor.** The result reads
`"photo_cleanup_required": true`; the SQL editor cannot delete Storage objects.
In the dashboard, Storage → `profile-photos` → the folder named with the user id
→ delete every file. The next age signal from the device would also remove it,
but do not wait for one.

## 5. Answer and record

Reply to the person (or the guardian) with the result and the reason, and say a
person decided it, not an automated process. Keep the email thread as the
record; Nina's database keeps only the new band, its assurance and the time.

## 6. Watch the distribution

```sql
select * from private.age_assurance_distribution();
```

Operator-marked accounts appear as `operator`; leave them out when reading how
real users come back (`docs/production-launch-runbook.md` §3, "Measuring the age
distribution on TestFlight").
