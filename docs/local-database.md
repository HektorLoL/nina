# Running the Database Locally

Last updated: 2026-08-10

The database is the one layer whose gate used to live only in CI. Every
migration, RPC, policy, and grant was verified by pushing to `main` and reading
the workflow log, which made a one-character SQL mistake cost a full CI
round-trip. This document sets up the same gate on the machine, where the whole
loop is about thirty seconds.

The local stack is a Postgres container. Containers need a Linux kernel, which
macOS does not have, so a small virtual machine supplies one. That machine is
what `colima` starts, and `docker` is the client that talks to it.

## 1. One-time setup

```sh
brew install colima docker
```

This installs the container runtime and its client. Both are Homebrew formulae,
not casks, so nothing asks for an administrator password and nothing installs a
background service that survives a reboot. Docker Desktop and OrbStack would
work too — the repository tasks in section 3 talk to whatever Docker is
configured — but they need administrator rights to install a privileged helper,
and Docker Desktop carries a commercial licence question that colima does not.

Nothing about this setup is tracked in the repository, because a virtual machine
is machine state. What is tracked is every command that reproduces it.

## 2. Start the virtual machine

```sh
deno task db:runtime
```

Starts a machine named `nina` with 4 CPUs, 6 GB of memory, and a 60 GB disk,
using Apple's Virtualization framework and virtiofs — the fast path on Apple
silicon. The sizing is chosen for the full Supabase stack, which is roughly a
dozen containers; less memory makes Postgres and the analytics container fight.

The task is idempotent. Run against an already-running machine it prints
`already running, ignoring` and exits 0, so it is safe as the first line of any
sequence. The machine does not survive a reboot; run this once per session.

A failure here is an environment problem, never a repository problem. Check
`colima status --profile nina`.

## 3. Start the stack and run the gate

```sh
deno task db:up && deno task db:test
```

`db:up` creates a fresh database, applies every migration in
`supabase/migrations/` in filename order, and prints the local endpoints.
`db:test` runs the schema linter and then the pgTAP suite — the same two
commands, at the same pinned CLI version, that the `database` job in
`.github/workflows/ci.yml` runs.

Passing means the same thing here as in CI: every migration applied cleanly in
order onto an empty database, the linter found no schema errors, and every
pgTAP assertion held. A failure is a real signal. Read the first `ERROR:` line
in the output and ignore everything after it, since a pgTAP file aborts on its
first error and reports the collapse as a plan mismatch rather than as failed
assertions.

The credentials `db:up` prints are the Supabase demo values, identical on every
machine in the world, and they reach only 127.0.0.1. They are not secrets and
they are not related to any Nina project. Never paste one into
`config/production.env`, an xcconfig, or a Cloudflare variable.

## 4. The loop while changing the schema

```sh
deno task db:reset && deno task db:test
```

`db:test` runs against the database as it currently stands; it does not apply
migrations. So editing a migration file and re-running only `db:test` tests the
old schema and passes for the wrong reason. `db:reset` drops the database and
replays every migration from scratch, which is also what proves a migration is
re-runnable from empty — the property CI checks and the reason migrations here
are written with `drop constraint if exists` / `add constraint`.

Editing only a pgTAP file under `supabase/tests/database/` needs no reset.

## 5. Stopping

```sh
deno task db:down && colima stop --profile nina
```

`db:down` removes the stack's containers and their volumes; `colima stop` frees
the memory. To reclaim the disk image as well, `colima delete --profile nina`,
after which section 2 rebuilds it from nothing.

## 6. Why the version is pinned

Both CI and `db:test` pin the same Supabase CLI version, and
`repository.database-gate-parity` in `Tools/production_preflight.ts` fails if
they drift or if either side stops running the linter or pgTAP. A local gate
that runs a different CLI than CI is worse than no local gate, because it
produces confident green runs that CI then contradicts. The CLI itself will
periodically suggest upgrading; when taking that suggestion, change both places
in the same commit.
