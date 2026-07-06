# Schema Policy

`mist-schema` is the canonical schema authority for Mist. It owns:

- canonical schema definition in `db/schema.sql`
- Atlas migration history in `db/migrations/`
- schema release points
- drift policy and validation expectations

## Supported State

Mist supports one target schema: latest.

Schema drift is an operational bug. Detect it, repair it, and avoid encoding
drift as a supported operating mode.

## Change Rules

- Make schema changes in this repository first.
- Update `db/schema.sql` as the desired end state.
- Generate Atlas migrations from that desired state.
- Review generated SQL before merge.
- Commit schema and migration changes together.
- Tag releases after merge so consumer repositories can pin exact schema
  versions.

## Consumer Rules

Consumer repositories should treat schema as pinned input:

- `mist-web` and `mist-stripe` use the pinned schema for local `sqlc`
  generation.
- `mist-setup` uses the pinned schema release for provisioning and migration
  orchestration.
- No consumer repository should become the schema authority.

## Merge Discipline

No service change that depends on a schema change should merge until:

1. the corresponding `mist-schema` release exists
2. the consumer repository is explicitly pinned to that release
3. consumer validation passes against the pinned schema
