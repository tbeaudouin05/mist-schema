# Atlas Migrations

This directory stores Atlas-generated migration files for `mist-schema`.

Do not hand-maintain divergent schema state here. Edit `db/schema.sql`, generate
the migration with Atlas, review the generated SQL, and commit both files
together.

Expected migration workflow:

```sh
atlas migrate diff <change-name> --env local
atlas migrate validate --env local
```

If a generated migration needs adjustment, keep the final migration aligned with
`db/schema.sql` and re-run validation before merge.

## Migration history

**`20260706000000_baseline.sql`** — Hand-authored from `db/schema.sql`. Local
`atlas migrate diff` is blocked for schemas that contain triggers without an
Atlas login (libsql/sqlite trigger support requires the Atlas cloud login flow).
The baseline was therefore written by hand and hashed with `atlas migrate hash`.
Future schema changes should still follow the Atlas-generated workflow above
once the trigger-diff limitation is resolved or an Atlas login is available.
