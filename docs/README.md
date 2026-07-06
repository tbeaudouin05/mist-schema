# Documentation

- `atlas-workflow.md`: Atlas commands and Turso/libSQL test validation setup
- `schema-policy.md`: schema ownership, drift, and merge policy

`mist-schema` validates schema changes against a dedicated Turso/libSQL test
database. Credentials are supplied by `TURSO_DB_URL` and `TURSO_TOKEN` from an
ignored local env file or CI secrets. The local env file must not be committed
or printed.

The Bitwarden note containing the test database credentials is named exactly
`mist-schema secret note`.

`db/schema.sql` remains the canonical desired schema.
