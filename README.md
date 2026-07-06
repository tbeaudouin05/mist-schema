# mist-schema

Canonical schema authority for Mist.

## Purpose

`mist-schema` is the single source of truth for the shared database schema used by:

- `mist-web`
- `mist-stripe`
- `mist-setup`

This repo owns schema definition, migration history, release points, and drift policy.

## Core policy

- One canonical latest schema.
- Fast convergence to latest.
- No intentional long-term multi-version support.
- Drift is an operational bug, not a supported state.

If a schema change is risky, test it hard before merge rather than supporting old versions longer.

## Drift posture

Treat any drift as an operational bug, not a supported state.

Meaning:
- detect it
- repair it
- do not normalize it into policy

## What to avoid

### 1. Canonical schema inside `mist-setup`

Too much coupling.

### 2. Duplicated schema in all three repos with sync

This creates:
- multiple PRs
- easy drift
- ambiguous ownership
- confusion about which repo is truth

### 3. sqlc-only with no Atlas

Too weak for the intended operations goal.

`sqlc` is excellent for typed queries, but it is not the schema lifecycle authority.

## Final recommendation

- Use Atlas.
- Do not make `mist-setup` the canonical schema owner.
- Create and use this dedicated `mist-schema` repo now.
- Let `mist-setup` own migration execution and convergence across instance DBs.
- Keep one supported schema target: latest.
- Use explicit pinned schema release propagation to `mist-web`, `mist-stripe`, and `mist-setup`.
- Use `sqlc` only as a per-service consumer of the canonical schema.

## Rollout plan

### Phase 1 — now

Create `mist-schema` and move schema authority here.

Include:
- `db/schema.sql`
- Atlas config
- `db/migrations/`
- docs for schema policy

### Phase 2

Make `mist-web`, `mist-stripe`, and `mist-setup` consume pinned schema releases.

Each repo should:
- sync a local schema copy
- add a CI guard for stale schema sync

### Phase 3

Make `mist-setup` the migration operator.

Add:
- provisioning of latest schema
- migration of existing DBs to latest
- status/reporting for schema convergence

### Phase 4

Tighten enforcement.

Add:
- CI checks for generated code freshness
- schema release coordination automation
- rollout dashboards/alerts if needed

## Merge discipline rule

No service PR that depends on a schema change should merge until:

1. the corresponding schema release exists, and
2. the consumer repo is pinned to that release.

This keeps ownership and rollout disciplined early.
