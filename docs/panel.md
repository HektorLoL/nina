# Nina panel

Last updated: 2026-08-18

A private, locally generated readiness cockpit. It answers one question — *what
is blocking launch, and am I moving* — and it is deliberately not an ops
console, because there is no production traffic to observe yet.

```sh
deno task panel
```

Writes `panel/index.html` and appends one record to `panel/history.jsonl`. Open
the HTML from disk. The page is self-contained, so it can also be published as a
private artifact when you want it on a phone.

```sh
deno task panel --deep
```

The same, plus the database gate. Slow, and it needs the container runtime from
`docs/local-database.md` to be up.

## What it reads

Nothing is fetched with a credential, and the page never contains one.

| Lane | Source |
| --- | --- |
| Premise | `CLAUDE.md` §2, so the sentence cannot drift from the manual |
| Yours | the vault note, by absolute path |
| Gates | `Tools/production_preflight.ts` output, plus `gh run list` |
| Next | `docs/product-depth-backlog.md` |
| Live systems | `https://ninai.app/api/health`, unauthenticated |

## Things that will silently go wrong

**The gates lane is coupled to `printResults` by text, not by a type.** Rewording
that log line empties the lane rather than failing anywhere else.
`Tools/panel.test.ts` pins the exact template string for that reason.

**The vault lives in a different repository, on one machine.** `parseYours` reads
an absolute path; when it is missing the panel still builds, the Yours lane is
empty, and Live systems says why. CI has no vault, so the test that reads it
returns early rather than failing.

**Only sections 1 to 3 of the vault note are work.** Sections 4 and 5 are
informational, and counting them would inflate the one number the panel exists
to report.

**Closing a backlog item means adding a field, not moving the item.** Write
`- **Closed:** YYYY-MM-DD — one line on what changed` in place. The item keeps
its rank, so the panel can count what is done without diffing git.

**The trend refuses to draw below three runs.** This is the same refusal
`HouseholdWorkload` makes below six assigned tasks: a line through two points is
decoration pretending to be information.

**`panel/index.html` is ignored; `panel/history.jsonl` is committed.** The page is
regenerated output and would make a 150 KB diff on every run. The history is the
part worth keeping.
