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

For Phase 1, this directory may contain only this README. Use checksum
validation until the first generated migration exists:

```sh
atlas migrate validate --dir file://db/migrations
```
