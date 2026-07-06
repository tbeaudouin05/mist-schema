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

## Atlas vs sqlc role split

### Atlas owns

Use Atlas for:

- canonical schema definition
- migration generation and review
- migration application
- drift inspection and validation

Atlas is the schema authority.

### sqlc owns

Use `sqlc` for:

- service-specific query generation inside `mist-web`
- service-specific query generation inside `mist-stripe`
- query generation inside `mist-setup` only if it directly queries operational data

`sqlc` is not the schema authority.

`sqlc` is a consumer of the schema, not the owner.

## Source of truth shape

A single SQL schema file shared by Atlas and `sqlc` is acceptable early on.

Recommended near-term source of truth:

- canonical `db/schema.sql` in `mist-schema`
- Atlas migration directory derived from and validated against that canonical schema
- service repos vendor or sync the exact pinned `schema.sql` copy locally for `sqlc` generation

Each app repo can have:

- `third_party/mist-schema/schema.sql` or local `db/schema.sql` synced from canonical
- local `db/queries/*.sql`
- local `sqlc.yaml`

This keeps one real schema owner without forcing `sqlc` to reach across repos.

## Propagation model

Do not make propagation implicit or magical at first.

Prefer explicit pinned consumption:

- `mist-schema` gets a release tag
- each consumer repo bumps to that schema release explicitly
- CI verifies local synced schema matches the pinned canonical release

This is safer than auto-propagation because automatic fanout can silently break all repos at once.

### Safer workflow

1. schema change PR in `mist-schema`
2. merge and tag a schema release
3. bump schema version in `mist-web`
4. bump schema version in `mist-stripe`
5. bump schema version and rollout logic in `mist-setup`
6. run migrations across managed instances

Bump PR creation can be automated later, but merge decisions should remain explicit.

## CI guardrails

### In `mist-schema`

- validate Atlas config
- validate migrations apply cleanly to an empty DB
- validate resulting DB matches canonical schema
- drift check from migrations to schema
- optionally lint destructive changes with policy gates

### In `mist-web` and `mist-stripe`

- verify pinned schema copy matches declared schema release
- run `sqlc generate`
- fail if generated code is stale
- run integration tests against an ephemeral DB built from canonical schema
- optionally assert the app binary reports the expected schema release

### In `mist-setup`

- verify it provisions a DB directly to latest schema
- verify the migration runner upgrades older fixture DBs to latest
- verify post-migration schema matches canonical
- verify rollout status logic detects lagging instances

## Local developer workflow

### Schema changes

Work in `mist-schema`:

- edit `db/schema.sql`
- generate and review the Atlas migration
- validate
- merge and tag a release

### App query changes

Work in `mist-web` or `mist-stripe`:

- sync the latest pinned schema release
- edit service queries
- run `sqlc generate`
- run tests

### Setup and ops changes

Work in `mist-setup`:

- consume the latest schema release
- update provisioning or migration orchestration
- test migration rollout logic

This is cleaner than editing schema in `mist-setup` and propagating outward later.

## Rollout strategy for many instance DBs

Because there is no production yet, keep rollout aggressive.

### Provisioning

- all new instances start at the latest schema immediately

### Existing instance upgrades

- `mist-setup` always migrates instances toward one target version: latest
- do not support multiple long-lived schema tracks

## What to avoid

### 1. Canonical schema inside `mist-setup`

Too much coupling.

### 2. Duplicated schema in all three repos with sync-as-ownership

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

Phase 1 scaffold:

- `atlas.hcl` defines the local Atlas environment.
- `db/schema.sql` is the canonical desired schema.
- `db/migrations/` stores Atlas-generated migration history.
- `docs/schema-policy.md` records ownership, drift, and merge policy.
- `docs/atlas-workflow.md` records local Atlas commands.

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
- status and reporting for schema convergence

### Phase 4

Tighten enforcement.

Add:
- CI checks for generated code freshness
- schema release coordination automation
- rollout dashboards or alerts if needed

## Merge discipline rule

No service PR that depends on a schema change should merge until:

1. the corresponding schema release exists, and
2. the consumer repo is pinned to that release.

This keeps ownership and rollout disciplined early.
