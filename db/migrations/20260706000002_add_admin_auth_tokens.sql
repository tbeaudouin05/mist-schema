-- Add admin_auth_tokens for short-lived admin dashboard auth links.

CREATE TABLE admin_auth_tokens (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    token_digest TEXT    NOT NULL
        CHECK(token_digest <> '' AND token_digest = TRIM(token_digest)),
    purpose      TEXT    NOT NULL DEFAULT 'admin_dashboard'
        CHECK(purpose <> ''
          AND purpose = TRIM(purpose)
          AND purpose = LOWER(purpose)
          AND purpose NOT GLOB '*[^a-z0-9_-]*'),
    scope        TEXT    NOT NULL DEFAULT 'admin'
        CHECK(scope <> ''
          AND scope = TRIM(scope)
          AND scope = LOWER(scope)
          AND scope NOT GLOB '*[^a-z0-9_:-]*'),
    subject      TEXT
        CHECK(subject IS NULL OR (subject <> '' AND subject = TRIM(subject))),
    admin_label  TEXT
        CHECK(admin_label IS NULL OR (admin_label <> '' AND admin_label = TRIM(admin_label))),
    expires_at   INTEGER NOT NULL CHECK(expires_at > 0),
    used_at      INTEGER,
    revoked_at   INTEGER,
    created_at   INTEGER NOT NULL DEFAULT 0 CHECK(created_at >= 0),
    updated_at   INTEGER NOT NULL DEFAULT 0 CHECK(updated_at >= 0),
    deleted_at   INTEGER,
    CHECK(expires_at > created_at),
    CHECK(used_at IS NULL OR used_at >= created_at),
    CHECK(revoked_at IS NULL OR revoked_at >= created_at),
    CHECK(deleted_at IS NULL OR deleted_at >= created_at)
);
CREATE UNIQUE INDEX idx_admin_auth_tokens_digest
    ON admin_auth_tokens(token_digest) WHERE deleted_at IS NULL;
CREATE INDEX idx_admin_auth_tokens_active_expiry
    ON admin_auth_tokens(expires_at) WHERE deleted_at IS NULL AND used_at IS NULL AND revoked_at IS NULL;
CREATE INDEX idx_admin_auth_tokens_purpose_scope
    ON admin_auth_tokens(purpose, scope, expires_at) WHERE deleted_at IS NULL;
