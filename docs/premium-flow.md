# Premium, end to end

Last updated: 2026-09-07

What happens between "Assinar o Premium" on a phone and "Premium ativo para a
casa inteira" on every phone in the house, where it broke on the first real
purchase, what was changed, and how each part is verified. Written after the
first sandbox purchase from TestFlight on 2026-09-06, which the server refused
every time.

## 1. The pieces

| Step | Where | What it does |
|---|---|---|
| Catalog | `PremiumSubscriptionStore.configure` | `Product.products(for:)` for the two ids in `NINA_PREMIUM_PRODUCT_IDS`. TestFlight reads App Store Connect's sandbox catalog; the simulator reads `Nina/Nina.storekit` through the scheme. |
| Purchase | `PremiumSubscriptionStore.purchase` | `product.purchase(options: [.appAccountToken(user.id)])`. The token is the only thing that binds Apple's receipt to a Nina account. |
| Local echo | `applyLocal` | The phone shows the receipt as active immediately, before the server has it. This is the only place a device-side receipt influences the UI. |
| Record | `recordOnServer` → `premium-subscription-sync` | POST the JWS with the user's session. Only a 2xx finishes the transaction; anything else marks the ledger `lastSyncFailed` and renders "Confirmando sua assinatura". |
| Verify | `_shared/app-store.ts` → `_shared/apple-jws.ts` | Certificate chain to an Apple root, Apple's marker OIDs, validity, ES256 signature; then bundle, environment, app id. |
| Bind | `premium-subscription-sync` | `appAccountTokenMatches(receipt token, auth.uid())`, case-insensitive. Mismatch is 403 and logged without the token. |
| Store | `premium_subscription_transactions`, `premium_subscriptions` | Upserts as `service_role`. A trigger resolves `family_id` from the buyer's active home and membership. |
| Household | `private.family_has_premium` → `get_current_home_context` | Any active row for the family covers everyone. The app reads this as `householdPremium`. |
| Renewals, cancellations | `app-store-server-notifications` | Apple posts signed notifications; the function verifies them the same way and updates the row. |
| Redelivery | `Transaction.updates` listener | An unfinished transaction is redelivered by StoreKit on every launch until the server records it. This is what rescued the first purchase once the server was fixed. |

## 2. What broke, and why nobody saw it

The first sandbox purchase (2026-09-06, TestFlight build 1) reached the server
three times and was refused three times with `400 transaction_verification_failed`
and an empty reason.

The verifier was Apple's own `@apple/app-store-server-library`. It builds on
`node:crypto`'s `X509Certificate`. The Supabase edge runtime
(`supabase-edge-runtime-1.74.3`, Deno 2.1.4 compatible) only stubs that class:
`toString()` and `raw` throw `Not implemented`. The library calls `toString()`
on the first line of its chain check, so every real receipt failed before any
verification happened, and the exception it wrapped carried no message.

Reproduced deterministically, not inferred: a throwaway function served with
`supabase functions serve` — the same runtime container production runs —
against Apple's published production chain returned the `Not implemented`
errors; the same code under Deno 2.9.5 on the Mac verified the chain, with and
without OCSP, in under half a second.

Two smaller findings from the same analysis:

- After a recorded purchase the app never reloaded the home context, and Casa
  reads premium from that context, not from the phone's receipt. A successful
  purchase would still have looked like nothing happened until the next
  foreground.
- The token comparison was case-sensitive. Apple's receipts happen to carry the
  token lowercase, so it was not the cause, but a case difference must never
  read as another account's receipt.

## 3. What changed

- `_shared/apple-jws.ts` reimplements the chain rules on WebCrypto with
  `@peculiar/x509`: a trusted root signs the intermediate; the intermediate is a
  CA and carries `1.2.840.113635.100.6.2.1`; the leaf carries
  `1.2.840.113635.100.6.11.1`; all three are within validity; the ES256
  signature verifies against the leaf key. Then the same bundle, environment,
  and app-id checks the library applied to transactions, renewal info, and
  notifications. Revocation is not consulted. `NINA_APP_STORE_ONLINE_CHECKS`
  now means "validity against the clock" rather than "against `signedDate`".
- Refusals log the status code and a bounded cause, never a receipt or a token.
- The paywall reloads the home after a recorded purchase or restore, shows a
  moss activation moment when the house becomes covered while the sheet is
  open, and otherwise becomes a management screen: plan, price, renewal,
  status, what is unlocked, one cobalt "Gerenciar na App Store", and restore.
  Casa and Hoje carry a `PremiumBadge` while the house is covered.

## 4. How each part is verified

| Claim | Evidence |
|---|---|
| Chain rules and signature | `_shared/apple-jws.test.ts`: a generated three-tier authority with Apple's markers; tampered payload, foreign key, wrong algorithm, short chain, unparsable certificate, missing markers, non-CA intermediate, expired leaf, wrong bundle, wrong environment, notification bodies (`data`, `summary`, production app id). Plus Apple's real production chain against the chain rules at a fixed date. |
| The runtime can run it | The WebCrypto probe inside the local edge-runtime container passed every check before the code was written; the deployed function answers an empty-chain receipt with `invalid_chain_length` in its log. |
| Token binding | `_shared/app-store.test.ts`: `appAccountTokenMatches` accepts either case, refuses a different UUID or a non-UUID. |
| Row shape | `supabase/tests/database/premium.test.sql` (84 assertions): grants, RLS, status mapping, household resolution. |
| Family sharing | `PremiumSubscriptionTests.testAFamilySharedTransactionIsNeverSentToTheServerAndNeverReadsAsPremium`. |
| End to end, real Apple sandbox | 2026-09-07 01:16 UTC: the pending receipt from build 1 was redelivered on launch, recorded as `source = entitlement_repair`, one row in `premium_subscriptions` (`Sandbox`, `active`, `family_id` set), and the phone showed "Premium ativo para a casa inteira. Acesso até 7 de set. de 2026." |

## 5. Still open

- **Apple's server notifications arrive and are applied.** Confirmed 2026-09-09: both URL fields in App Store Connect hold the function's address, and `app_store_server_notifications` holds a `DID_CHANGE_RENEWAL_STATUS` (`AUTO_RENEW_DISABLED`, 2026-09-07 01:37 UTC) and an `EXPIRED` (`VOLUNTARY`, 2026-09-07 20:24 UTC), both processed; the subscription row carries `latest_notification_type = EXPIRED`, `status = expired`, `is_active = false`. A cancellation therefore reaches Nina from Apple, not only from the phone's next sync.
- **Sandbox timing** is not production timing: a monthly plan renews every few minutes and expires within the hour, so "Restaurar compras" hours later finds nothing usable on the device and sends nothing. That is sandbox behaviour, not a defect.
- **Before submission** set `NINA_APP_STORE_ENVIRONMENT=production` again (unset during TestFlight so sandbox receipts verify) and paste the OpenAI key into `config/production.env` so the release gate goes fully green.
- **Denials are still plain chat lines**: a free household that hits a ceiling gets a sentence from Nina, not a button to the paywall. Recorded in `CLAUDE.md` §13.

## App-side proof, 2026-09-09

Run in the iOS simulator (iPhone 17 Pro, signed Debug build) against
production, signed in by email with a throwaway user whose house was marked
premium through a fixture row in `premium_subscriptions` (the membership
trigger attached `family_id` the moment the house was created). Observed, in
order: the Casa header carried the PREMIUM badge; Ajustes showed the block
"Premium ativo para a casa inteira" with the renewal date and the button
"Ver a assinatura"; that button opened the management screen — plan, price,
renewal, status, what is unlocked, one cobalt "Gerenciar na App Store", and
"Restaurar compras". The fixture row, the house, and the user were deleted
afterwards.

Two things the same run exposed that were not premium's fault: an unsigned
simulator build cannot persist the session (Keychain `-34018`), and three
production auth settings had email login broken (provider off, dead SMTP key,
2 emails/hour). Both are recorded in `CLAUDE.md` §12.
