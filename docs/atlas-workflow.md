# Atlas Workflow

This repository uses Atlas to manage the schema lifecycle.

## Files

- `atlas.hcl`: Turso/libSQL test validation environment configuration
- `db/schema.sql`: canonical desired schema
- `db/migrations/`: Atlas migration history

## Local Commands

Load local test database credentials from an ignored env file before running
commands that connect to Turso:

```sh
set -a
. ./.env.local
set +a
```

The env file must define `TURSO_DB_URL` and `TURSO_TOKEN`. Do not commit it,
print its contents, or use credentials for production systems.

Generate a migration after editing `db/schema.sql`:

```sh
atlas migrate diff <change-name> --env turso_test
```

Validate migration files:

```sh
atlas migrate validate --env turso_test
```

Validate the canonical desired schema against the dedicated Turso/libSQL test
database:

```sh
atlas schema apply --env turso_test --dry-run
```

Validate an empty Phase 1 migration directory without starting a dev database:

```sh
atlas migrate validate --dir file://db/migrations
```

## Notes

The `turso_test` Atlas environment uses a SQLite-compatible in-memory dev
database for migration planning and a dedicated Turso/libSQL test database for
schema validation. It must not point at production, staging, or any long-lived
database.

Keep credentials out of this repository. Local credentials belong in an ignored
env file such as `.env.local`; CI credentials belong in CI secrets. The
Bitwarden note containing the test database URL and token is named exactly
`mist-schema secret note`.
