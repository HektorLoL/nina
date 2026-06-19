# LGPD Launch Posture - Nina

Last updated: 2026-06-16

This is an engineering/privacy operations checklist for launch readiness. It is not a substitute for Brazilian legal review, but it documents the product controls now present in the app and the remaining launch ownership items.

Official references:

- ANPD data subject rights: https://www.gov.br/anpd/pt-br/assuntos/titular-de-dados-1/direito-dos-titulares
- ANPD data subject overview and DPO role: https://www.gov.br/anpd/pt-br/assuntos/titular-de-dados-1
- LGPD official law text: https://www.planalto.gov.br/ccivil_03/_ato2015-2018/2018/lei/l13709.htm
- OpenAI API data controls: https://developers.openai.com/api/docs/guides/your-data

## Data Inventory

Nina processes:

- Account data: Supabase Auth ID, Apple identity provider metadata, linked email, display name.
- Profile data: role, phone, birthday label, availability, communication preference, memory note, avatar/photo.
- Household data: family name, invite links, participants, roles, children/pets entered by adults, permissions.
- Routine data: tasks, reminders, shopping items, task categories, due labels/dates.
- Nina data: private adult chat threads, message attachments, proposals, confirmed private/shared memories, household insights.
- Operational data: rate limits, AI run cost/token/latency/status metadata, backend request diagnostics.

## Legal Bases to Validate

| Processing | Likely LGPD Basis | Product Control |
| --- | --- | --- |
| Account, login, sync, household management | Contract execution / preliminary procedures | Authenticated app account and home access. |
| AI chat and Nina memory | Consent | Consent gate before online Nina chat; revocation in Settings. |
| Security, abuse prevention, rate limits, backend diagnostics | Legitimate interest | Content-free logs where possible; no ad tracking. |
| Required retention or legal requests | Legal obligation | Policy reserves legally required retention. |
| Health/child data entered by adults | Consent or other applicable basis requiring legal review | Adult-only Nina chat; data minimization copy; no child chat access. |

## User Rights and Controls

Current product controls:

- Confirmation/access/export: `Ajustes -> Privacidade -> Exportar meus dados` generates JSON with the active home's locally synchronized data.
- Deletion: `Ajustes -> Conta -> Apagar conta` initiates account deletion in-app.
- Chat deletion: `Casa -> Memórias da Nina -> Apagar meu histórico com a Nina`.
- Memory deletion/editing: memory owners can edit/delete their confirmed memories.
- Consent revocation: `Ajustes -> Privacidade -> Consentimento de IA`.

Operational mailbox:

- Use `oi@ninai.app` until a dedicated privacy/DPO mailbox is configured.
- Before production launch, publish the legal entity and encarregado contact on `/privacidade`.

Recommended request handling:

- Acknowledge privacy requests promptly.
- For LGPD access/confirmation requests, support immediate simplified response when possible and a complete response within the statutory window when required.
- Verify identity before exporting or deleting data outside the in-app authenticated flows.
- Log request date, requester, verified account, action taken, completion date, and retained exceptions.

## Retention

Implemented backend retention:

- Private Nina chat messages: 30 days by `run_nina_retention`.
- Resolved Nina proposals: 30 days.
- AI operational run logs: 90 days and content-free by design.
- Household insights: 90 days.

User-triggered deletion:

- Private chat history can be deleted immediately.
- Confirmed memories owned by the user can be deleted immediately.
- Account deletion removes the Auth user and private Nina data. Shared household records can remain for other participants without the deleted user account linked.

## AI Processing

Current architecture:

- The iOS app never stores OpenAI API keys.
- The `nina-chat` Edge Function sends only the needed household context and attachments to OpenAI.
- OpenAI Responses calls use `store: false` in the backend.
- Confirmed memories are not auto-created; the user must accept a proposal.
- Personal memories start private; sharing is an explicit visibility choice.

## Launch Blockers Before Public Release

- Fill production legal entity and encarregado details on `/privacidade`.
- Confirm `oi@ninai.app` or a dedicated privacy mailbox is monitored and documented.
- Deploy the `delete-account` Edge Function with the Supabase service role key available only in function secrets.
- Apply all migrations and confirm `run_nina_retention` runs daily.
- Review App Store privacy labels against the production binary and SDK list.
- Run database tests for deletion, RLS, and Nina AI retention after the next migration batch.
- Have Brazilian counsel review child/health/sensitive-data wording and legal bases.
