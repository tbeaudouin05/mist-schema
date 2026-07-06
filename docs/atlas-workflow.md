# Atlas Workflow

This repository uses Atlas to manage the schema lifecycle.

## Files

- `atlas.hcl`: local Atlas environment configuration
- `db/schema.sql`: canonical desired schema
- `db/migrations/`: Atlas migration history

## Local Commands

Generate a migration after editing `db/schema.sql`:

```sh
atlas migrate diff <change-name> --env local
```

Validate migration files:

```sh
atlas migrate validate --env local
```

Validate an empty Phase 1 migration directory without starting a dev database:

```sh
atlas migrate validate --dir file://db/migrations
```

## Notes

The `local` Atlas environment uses a disposable PostgreSQL dev database through
Docker for migration generation and semantic validation. It must not point at
production, staging, or any long-lived database.

Keep credentials out of this repository. Runtime database URLs belong in the
systems that apply migrations, not in `mist-schema`.
