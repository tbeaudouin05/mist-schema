-- Canonical Mist database schema.
--
-- mist-schema is now the authoritative owner of this schema. Atlas treats this
-- file as the desired schema state and derives migration history from it.
--
-- This schema was imported from mist-setup
-- (internal/runtimeopsqlc/schema.sql) as the Phase 2 source of truth. That file
-- was the prior canonical SQL DDL mirror of the runtime operational database,
-- kept in sync with internal/configschema/configschema.go. Ownership now lives
-- here; consumer repositories (mist-web, mist-stripe, mist-setup) sync pinned
-- copies of this file for sqlc generation rather than owning the schema.

-- runtime_config: authoritative per-instance runtime configuration rows.
CREATE TABLE IF NOT EXISTS runtime_config (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    config_id      TEXT    NOT NULL,
    config_version INTEGER NOT NULL DEFAULT 1,
    created_at     INTEGER NOT NULL DEFAULT 0,
    updated_at     INTEGER NOT NULL DEFAULT 0,
    deleted_at     INTEGER,
    config_json    TEXT    NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_runtime_config_config_id
    ON runtime_config(config_id) WHERE deleted_at IS NULL;

-- admin_auth_tokens: short-lived admin dashboard link tokens created by
-- mist-setup and validated by mist-web. Only an opaque digest of the bearer
-- token is stored; plaintext token material never belongs in the database.
-- purpose/scope provide bounded routing/authorization context for the link,
-- while optional subject/admin_label let setup annotate who or what the token
-- was created for without requiring a first-class admin user table.
-- expires_at, used_at, revoked_at, created_at, and updated_at are UTC Unix ms.
CREATE TABLE IF NOT EXISTS admin_auth_tokens (
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
CREATE UNIQUE INDEX IF NOT EXISTS idx_admin_auth_tokens_digest
    ON admin_auth_tokens(token_digest) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_admin_auth_tokens_active_expiry
    ON admin_auth_tokens(expires_at) WHERE deleted_at IS NULL AND used_at IS NULL AND revoked_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_admin_auth_tokens_purpose_scope
    ON admin_auth_tokens(purpose, scope, expires_at) WHERE deleted_at IS NULL;

-- agent_state: singleton row holding all global WhatsApp/runtime fields.
-- Enforces singleton with CHECK(id = 1).
CREATE TABLE IF NOT EXISTS agent_state (
    id                        INTEGER PRIMARY KEY CHECK(id = 1),
    whatsapp_status           TEXT,
    whatsapp_connected        INTEGER NOT NULL DEFAULT 0 CHECK(whatsapp_connected IN (0,1)),
    whatsapp_customer_live    INTEGER NOT NULL DEFAULT 0 CHECK(whatsapp_customer_live IN (0,1)),
    whatsapp_enabled_in_config INTEGER NOT NULL DEFAULT 0 CHECK(whatsapp_enabled_in_config IN (0,1)),
    whatsapp_connection_basis TEXT,
    session_store_exists      INTEGER NOT NULL DEFAULT 0 CHECK(session_store_exists IN (0,1)),
    service_active            INTEGER NOT NULL DEFAULT 0 CHECK(service_active IN (0,1)),
    qr_recent                 INTEGER NOT NULL DEFAULT 0 CHECK(qr_recent IN (0,1)),
    status_checked_at         INTEGER NOT NULL,
    updated_at                INTEGER NOT NULL DEFAULT 0,
    created_at                INTEGER NOT NULL DEFAULT 0,
    deleted_at                INTEGER
);

-- conversation_state: per-conversation tracking for the AI plane.
CREATE TABLE IF NOT EXISTS conversation_state (
    id                       INTEGER PRIMARY KEY AUTOINCREMENT,
    conversation_id          TEXT    NOT NULL,
    last_seen_config_version INTEGER,
    ai_enabled               INTEGER NOT NULL DEFAULT 1 CHECK(ai_enabled IN (0,1)),
    created_at               INTEGER NOT NULL DEFAULT 0,
    updated_at               INTEGER NOT NULL DEFAULT 0,
    deleted_at               INTEGER
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_conversation_state_conversation_id
    ON conversation_state(conversation_id) WHERE deleted_at IS NULL;

-- school_settings: singleton (CHECK(id = 1)) holding the school's required
-- operational IANA timezone and approved public-information summary. Not seeded;
-- the absence of the row means the timezone is unset and session creation is
-- gated. The timezone CHECK is a coarse shape guard only (non-empty, trimmed,
-- slash-free, no '+'/space). Go validates the runtime IANA value before
-- encoding '/' as '%2F' for persistence. All timestamps are UTC Unix ms.
CREATE TABLE IF NOT EXISTS school_settings (
    id                     INTEGER PRIMARY KEY CHECK(id = 1),
    timezone               TEXT    NOT NULL
        CHECK(timezone <> '' AND timezone = TRIM(timezone)
          AND timezone NOT GLOB '*/*'
          AND timezone NOT GLOB '*[+ ]*'),
    currency               TEXT    NOT NULL
        CHECK(LENGTH(currency) = 3 AND currency = UPPER(currency)),
    school_website_url     TEXT,
    school_info_summary    TEXT,
    school_info_updated_at INTEGER,
    created_at             INTEGER NOT NULL DEFAULT 0,
    updated_at             INTEGER NOT NULL DEFAULT 0,
    deleted_at             INTEGER
);
CREATE TRIGGER IF NOT EXISTS trg_school_settings_currency_immutable
    BEFORE UPDATE OF currency ON school_settings
    WHEN OLD.currency <> NEW.currency
BEGIN
    SELECT RAISE(ABORT, 'school_settings currency is setup-once immutable');
END;

-- school_information_versions: complete durable proposals/versions attached to
-- the singleton school scope. Each row owns the canonical URL, concise summary,
-- detailed information, sources, and lifecycle state. Existing rows predate the
-- proposal workflow and are backfilled as approved; approved_at = 0 is the
-- explicit legacy timestamp sentinel. New lifecycle timestamps are server-owned
-- UTC Unix ms. canonical_url/summary remain nullable only for legacy rows with
-- approved_at = 0; every pending proposal must own both fields and an expiry.
-- Newly approved versions are unique per active school, and approval can only
-- move on to superseded. Retention remains an application concern.
CREATE TABLE IF NOT EXISTS school_information_versions (
    id                 INTEGER PRIMARY KEY AUTOINCREMENT,
    school_settings_id INTEGER NOT NULL CHECK(school_settings_id = 1),
    status             TEXT    NOT NULL DEFAULT 'approved'
        CHECK(status IN ('pending','approved','superseded')),
    canonical_url      TEXT
        CHECK(canonical_url IS NULL OR (canonical_url <> ''
          AND canonical_url = TRIM(canonical_url)
          AND LENGTH(canonical_url) <= 2048)),
    summary            TEXT
        CHECK(summary IS NULL OR (summary <> ''
          AND summary = TRIM(summary)
          AND LENGTH(summary) <= 1000)),
    detailed_info      TEXT    NOT NULL
        CHECK(detailed_info <> ''
          AND detailed_info = TRIM(detailed_info)
          AND LENGTH(detailed_info) <= 100000),
    source_urls        TEXT    NOT NULL
        CHECK(source_urls <> ''
          AND source_urls = TRIM(source_urls)
          AND LENGTH(source_urls) <= 20000
          AND JSON_VALID(source_urls)
          AND JSON_TYPE(source_urls) = 'array'
          AND JSON_ARRAY_LENGTH(source_urls) > 0),
    created_at         INTEGER NOT NULL DEFAULT 0 CHECK(created_at >= 0),
    updated_at         INTEGER NOT NULL DEFAULT 0 CHECK(updated_at >= 0),
    approved_at        INTEGER NOT NULL DEFAULT 0 CHECK(approved_at >= 0),
    superseded_at      INTEGER,
    expires_at         INTEGER,
    deleted_at         INTEGER,
    CHECK(status <> 'pending' OR (canonical_url IS NOT NULL
      AND summary IS NOT NULL
      AND approved_at = 0
      AND superseded_at IS NULL
      AND expires_at IS NOT NULL)),
    CHECK(status <> 'approved' OR (approved_at >= 0 AND superseded_at IS NULL)),
    CHECK(status <> 'superseded' OR superseded_at IS NOT NULL),
    CHECK(approved_at = 0 OR approved_at >= created_at),
    CHECK(superseded_at IS NULL OR superseded_at >= created_at),
    CHECK(expires_at IS NULL OR expires_at > created_at),
    CHECK(deleted_at IS NULL OR deleted_at >= created_at),
    FOREIGN KEY(school_settings_id) REFERENCES school_settings(id)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_school_information_versions_one_approved
    ON school_information_versions(school_settings_id)
    WHERE deleted_at IS NULL AND status = 'approved' AND approved_at > 0;
CREATE INDEX IF NOT EXISTS idx_school_information_versions_pending_lookup
    ON school_information_versions(school_settings_id, status, created_at DESC, id DESC, expires_at)
    WHERE deleted_at IS NULL AND status = 'pending';
CREATE INDEX IF NOT EXISTS idx_school_information_versions_retention
    ON school_information_versions(school_settings_id, status, approved_at DESC, id DESC)
    WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_school_information_versions_school_settings_fk
    ON school_information_versions(school_settings_id);
CREATE TRIGGER IF NOT EXISTS trg_school_information_versions_no_new_legacy_approved
    BEFORE INSERT ON school_information_versions
    WHEN NEW.status = 'approved'
      AND (NEW.approved_at = 0 OR NEW.canonical_url IS NULL OR NEW.summary IS NULL)
BEGIN
    SELECT RAISE(ABORT, 'new approved school information must be complete and timestamped');
END;
CREATE TRIGGER IF NOT EXISTS trg_school_information_versions_status_transition
    BEFORE UPDATE OF status ON school_information_versions
    WHEN OLD.status <> NEW.status
      AND NOT (
        (OLD.status = 'pending' AND NEW.status IN ('approved', 'superseded'))
        OR (OLD.status = 'approved' AND NEW.status = 'superseded')
      )
BEGIN
    SELECT RAISE(ABORT, 'invalid school information status transition');
END;

-- customers: one row per known customer; whatsapp_phone is the primary identity.
-- Uniqueness enforced by partial index on active (non-deleted) rows.
CREATE TABLE IF NOT EXISTS customers (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    whatsapp_phone TEXT    NOT NULL
        CHECK(whatsapp_phone GLOB '[1-9]*'
          AND whatsapp_phone NOT GLOB '*[^0-9]*'
          AND LENGTH(whatsapp_phone) BETWEEN 8 AND 15),
    first_name     TEXT    NOT NULL
        CHECK(first_name <> '' AND first_name = TRIM(first_name)),
    display_name   TEXT
        CHECK(display_name <> '' AND display_name = TRIM(display_name)),
    email          TEXT
        CHECK(email GLOB '?*@?*'
          AND email NOT GLOB '*@*@*'
          AND email NOT GLOB '* *'
          AND email = LOWER(email)
          AND email = TRIM(email)),
    notes          TEXT,
    -- preferred_language: required BCP47-ish language tag, stored normalized
    -- lowercase (e.g. 'en', 'fr', 'pt-br'). NOT NULL so every customer carries an
    -- explicit language for student WhatsApp reminders. Every agent-facing
    -- customer-creation path supplies it explicitly and validates it as required:
    -- upsert_customer, and the create_booking/create_inquiry auto-create-by-phone
    -- path. DEFAULT 'en' is only a schema-level backstop for direct/auxiliary SQL
    -- inserts (e.g. trigger/constraint unit tests); no agent path relies on it. The
    -- reminder/notice dispatcher uses it to pick a localized message.
    preferred_language TEXT NOT NULL DEFAULT 'en'
        CHECK(preferred_language <> ''
          AND preferred_language = TRIM(preferred_language)
          AND preferred_language = LOWER(preferred_language)
          AND LENGTH(preferred_language) BETWEEN 2 AND 12
          AND preferred_language NOT GLOB '*[^a-z0-9-]*'),
    created_at     INTEGER NOT NULL DEFAULT 0,
    updated_at     INTEGER NOT NULL DEFAULT 0,
    deleted_at     INTEGER
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_customers_whatsapp_phone
    ON customers(whatsapp_phone) WHERE deleted_at IS NULL;

-- customer_questions: durable questions from customers that school staff need
-- to answer or follow up on. question_text is stored trimmed and bounded;
-- status is the complete lifecycle. follow_up_at is the UTC Unix ms instant at
-- which a question enters the staff follow-up queue, while resolved_at records
-- completion. Soft-deleted rows are excluded from active dashboard indexes.
CREATE TABLE IF NOT EXISTS customer_questions (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    customer_id   INTEGER NOT NULL,
    question_text TEXT   NOT NULL
        CHECK(question_text <> ''
          AND question_text = TRIM(question_text)
          AND LENGTH(question_text) <= 2000),
    status        TEXT    NOT NULL DEFAULT 'open'
        CHECK(status IN ('open','follow_up','resolved')),
    follow_up_at  INTEGER,
    resolved_at   INTEGER,
    created_at    INTEGER NOT NULL DEFAULT 0,
    updated_at    INTEGER NOT NULL DEFAULT 0,
    deleted_at    INTEGER,
    CHECK(status <> 'follow_up' OR follow_up_at IS NOT NULL),
    CHECK(follow_up_at IS NULL OR status IN ('follow_up','resolved')),
    CHECK((status = 'resolved') = (resolved_at IS NOT NULL)),
    CHECK(follow_up_at IS NULL OR follow_up_at >= created_at),
    CHECK(resolved_at IS NULL OR resolved_at >= created_at),
    FOREIGN KEY(customer_id) REFERENCES customers(id)
);
CREATE INDEX IF NOT EXISTS idx_customer_questions_customer_open
    ON customer_questions(customer_id, created_at)
    WHERE deleted_at IS NULL AND status = 'open';
CREATE INDEX IF NOT EXISTS idx_customer_questions_follow_up
    ON customer_questions(follow_up_at, customer_id)
    WHERE deleted_at IS NULL AND status = 'follow_up';
CREATE INDEX IF NOT EXISTS idx_customer_questions_customer_fk
    ON customer_questions(customer_id);

-- offering_templates: combined catalog and recurring weekly schedule.
-- Each row is a concrete template: name identifies the offering,
-- weekday+time_slot define the recurrence. Uniqueness of active
-- (name, weekday, time_slot) combinations enforced by partial unique index.
-- default_price_cents is required so every template can produce priced sessions.
CREATE TABLE IF NOT EXISTS offering_templates (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    name                TEXT    NOT NULL
        CHECK(name <> '' AND name = TRIM(name)),
    description         TEXT,
    weekday             INTEGER NOT NULL CHECK(weekday BETWEEN 0 AND 6),
    time_slot           TEXT    NOT NULL
        CHECK(time_slot <> '' AND time_slot = TRIM(time_slot)),
    capacity            INTEGER CHECK(capacity > 0),
    min_capacity        INTEGER CHECK(min_capacity > 0),
    default_price_cents INTEGER NOT NULL CHECK(default_price_cents >= 0),
    notes               TEXT,
    valid_from          TEXT CHECK(valid_from IS NULL OR valid_from = TRIM(valid_from)),
    valid_to            TEXT CHECK(valid_to IS NULL OR valid_to = TRIM(valid_to)),
    created_at          INTEGER NOT NULL DEFAULT 0,
    updated_at          INTEGER NOT NULL DEFAULT 0,
    deleted_at          INTEGER
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_offering_templates_slot
    ON offering_templates(name, weekday, time_slot) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_offering_templates_name
    ON offering_templates(name) WHERE deleted_at IS NULL;

-- surf_spots: admin-curated catalog of favorite surf spots. Each row is a named
-- location with WGS84 coordinates (latitude/longitude as REAL with range CHECKs)
-- plus optional Surfline-style guide fields (ideal swell/wind direction, surf
-- height, tide + tide height, best season, ability level) and a concise
-- admin-editable description/tips surface used to forecast optimal surfing
-- conditions. Active-name uniqueness enforced by a partial unique index.
-- Independent of sessions/offerings; no foreign keys.
CREATE TABLE IF NOT EXISTS surf_spots (
    id                    INTEGER PRIMARY KEY AUTOINCREMENT,
    name                  TEXT    NOT NULL
        CHECK(name <> '' AND name = TRIM(name)),
    latitude              REAL    NOT NULL CHECK(latitude BETWEEN -90 AND 90),
    longitude             REAL    NOT NULL CHECK(longitude BETWEEN -180 AND 180),
    description           TEXT,
    ideal_swell_direction TEXT,
    ideal_wind_direction  TEXT,
    ideal_surf_height     TEXT,
    ideal_tide            TEXT,
    ideal_tide_height     TEXT,
    best_season           TEXT,
    ability_level         TEXT
        CHECK(ability_level IS NULL OR ability_level IN ('beginner','intermediate','advanced')),
    tips                  TEXT,
    created_at            INTEGER NOT NULL DEFAULT 0,
    updated_at            INTEGER NOT NULL DEFAULT 0,
    deleted_at            INTEGER
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_surf_spots_name
    ON surf_spots(name) WHERE deleted_at IS NULL;

-- sessions: concrete future lesson times; independent snapshots with no FK to
-- offerings/templates so the catalog can change after sessions are created.
-- date and time_slot are calendar/clock strings. cancelled_at is UTC Unix ms.
-- capacity and min_capacity are both required (NOT NULL): every session has a
-- maximum and a minimum participant target, and min_capacity must be in
-- 1..capacity. booked_capacity is incremented/decremented transactionally on
-- booking create/cancel; the table CHECKs enforce it never exceeds capacity and
-- never sits in an active below-minimum state (it must be exactly 0 or at least
-- min_capacity). Empty sessions stay allowed.
CREATE TABLE IF NOT EXISTS sessions (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    offering_name       TEXT    NOT NULL
        CHECK(offering_name <> '' AND offering_name = TRIM(offering_name)),
    date                TEXT    NOT NULL CHECK(date <> '' AND date = TRIM(date)),
    time_slot           TEXT    NOT NULL
        CHECK(time_slot <> '' AND time_slot = TRIM(time_slot)),
    -- starts_at_ms: canonical UTC Unix ms instant for the session, derived from
    -- the school-local date/time using the required school_settings timezone.
    -- Clean-slate reset/init stores it as NOT NULL.
    starts_at_ms        INTEGER NOT NULL CHECK(starts_at_ms > 0),
    capacity            INTEGER NOT NULL CHECK(capacity > 0),
    min_capacity        INTEGER NOT NULL CHECK(min_capacity >= 1) CHECK(min_capacity <= capacity),
    booked_capacity     INTEGER NOT NULL DEFAULT 0 CHECK(booked_capacity >= 0),
    price_cents         INTEGER NOT NULL CHECK(price_cents >= 0),
    status              TEXT    NOT NULL CHECK(status IN ('scheduled','cancelled')),
    notes               TEXT,
    cancellation_reason TEXT,
    cancelled_at        INTEGER,
    created_at          INTEGER NOT NULL DEFAULT 0,
    updated_at          INTEGER NOT NULL DEFAULT 0,
    deleted_at          INTEGER,
    CHECK(booked_capacity <= capacity),
    CHECK(booked_capacity = 0 OR booked_capacity >= min_capacity)
);
CREATE INDEX IF NOT EXISTS idx_sessions_slot
    ON sessions(offering_name, date, time_slot, status);
CREATE INDEX IF NOT EXISTS idx_sessions_date
    ON sessions(date, status);
-- Reminder/time-range query path: select scheduled sessions by canonical UTC
-- instant.
CREATE INDEX IF NOT EXISTS idx_sessions_starts_at
    ON sessions(starts_at_ms, status);

-- inquiries: a customer's interest in a session before confirming.
-- session_id is NOT NULL: an inquiry must always reference a concrete sessions.id;
-- create_inquiry requires a positive session_id matching a scheduled session.
-- converted_at is UTC Unix ms.
CREATE TABLE IF NOT EXISTS inquiries (
    id                     INTEGER PRIMARY KEY AUTOINCREMENT,
    customer_id            INTEGER NOT NULL,
    status                 TEXT    NOT NULL
        CHECK(status IN ('open','combined','converted','closed')),
    offering_name          TEXT    NOT NULL
        CHECK(offering_name <> '' AND offering_name = TRIM(offering_name)),
    session_id             INTEGER NOT NULL,
    date                   TEXT    NOT NULL CHECK(date <> '' AND date = TRIM(date)),
    time_slot              TEXT    NOT NULL
        CHECK(time_slot <> '' AND time_slot = TRIM(time_slot)),
    participants           INTEGER NOT NULL CHECK(participants > 0),
    notes                  TEXT,
    source_channel         TEXT,
    source_conversation_id TEXT,
    converted_booking_id   INTEGER,
    converted_at           INTEGER,
    created_at             INTEGER NOT NULL DEFAULT 0,
    updated_at             INTEGER NOT NULL DEFAULT 0,
    deleted_at             INTEGER,
    FOREIGN KEY(customer_id) REFERENCES customers(id),
    FOREIGN KEY(session_id)  REFERENCES sessions(id)
);
CREATE INDEX IF NOT EXISTS idx_inquiries_slot
    ON inquiries(offering_name, date, time_slot, status);
CREATE INDEX IF NOT EXISTS idx_inquiries_customer
    ON inquiries(customer_id, date, status);
CREATE INDEX IF NOT EXISTS idx_inquiries_customer_fk
    ON inquiries(customer_id);
CREATE INDEX IF NOT EXISTS idx_inquiries_session
    ON inquiries(session_id) WHERE session_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_inquiries_session_fk
    ON inquiries(session_id);

-- bookings: customer reservation for a session. Stripe-enabled instances create
-- pending_payment/unpaid bookings until webhook confirmation; non-Stripe
-- instances create confirmed/not_required bookings directly.
-- session_id is NOT NULL: a booking must always reference a concrete sessions.id.
-- cancelled_at is UTC Unix ms.
-- A booking carries NO date/time_slot or price snapshot: the referenced session
-- is the single source of truth for schedule (sessions.date, sessions.time_slot,
-- sessions.starts_at_ms) and amount (sessions.price_cents). Read/query surfaces
-- join sessions for derived fields, so a session reschedule/reprice is reflected
-- without copying data back.
CREATE TABLE IF NOT EXISTS bookings (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    customer_id         INTEGER NOT NULL,
    status              TEXT    NOT NULL
        CHECK(status IN ('pending_payment','confirmed','cancelled','session_cancelled')),
    offering_name       TEXT    NOT NULL
        CHECK(offering_name <> '' AND offering_name = TRIM(offering_name)),
    session_id          INTEGER NOT NULL,
    participants        INTEGER NOT NULL CHECK(participants > 0),
    payment_status      TEXT    NOT NULL DEFAULT 'unpaid'
        CHECK(payment_status IN ('unpaid','paid','refunded','failed','not_required')),
    paid_at             INTEGER,
    stripe_checkout_session_id TEXT,
    stripe_payment_intent_id   TEXT,
    notes               TEXT,
    cancellation_reason TEXT,
    cancelled_at        INTEGER,
    created_at          INTEGER NOT NULL DEFAULT 0,
    updated_at          INTEGER NOT NULL DEFAULT 0,
    deleted_at          INTEGER,
    CHECK(status <> 'confirmed' OR payment_status IN ('paid','not_required')),
    CHECK(status <> 'pending_payment' OR payment_status IN ('unpaid','failed','paid')),
    FOREIGN KEY(customer_id) REFERENCES customers(id),
    FOREIGN KEY(session_id)  REFERENCES sessions(id)
);
CREATE INDEX IF NOT EXISTS idx_bookings_customer
    ON bookings(customer_id, status);
CREATE INDEX IF NOT EXISTS idx_bookings_customer_fk
    ON bookings(customer_id);
CREATE INDEX IF NOT EXISTS idx_bookings_session
    ON bookings(session_id) WHERE session_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_bookings_session_fk
    ON bookings(session_id);
CREATE TRIGGER IF NOT EXISTS trg_bookings_mark_confirmed_after_paid
    AFTER UPDATE OF payment_status ON bookings
    WHEN NEW.payment_status = 'paid' AND NEW.status = 'pending_payment'
BEGIN
    UPDATE bookings SET status = 'confirmed' WHERE id = NEW.id;
END;

-- reminder_dispatch: idempotency record of which reminder has been sent for
-- each booking. Partial unique index enforces one row per (booking, kind).
-- sent_at is UTC Unix ms. reminder_rule_key/reminder_rule_version are the
-- optional stable identity of the reminder_rule that produced this dispatch;
-- they are nullable so the prior reminder_kind-only record-sent contract still
-- works unchanged, while newer dispatches can stamp the rule revision they ran.
CREATE TABLE IF NOT EXISTS reminder_dispatch (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    booking_id    INTEGER NOT NULL,
    reminder_kind TEXT    NOT NULL
        CHECK(reminder_kind <> '' AND reminder_kind = TRIM(reminder_kind)),
    reminder_rule_key     TEXT
        CHECK(reminder_rule_key IS NULL OR (reminder_rule_key <> ''
          AND reminder_rule_key = TRIM(reminder_rule_key)
          AND reminder_rule_key = LOWER(reminder_rule_key))),
    reminder_rule_version INTEGER
        CHECK(reminder_rule_version IS NULL OR reminder_rule_version >= 1),
    channel       TEXT,
    detail        TEXT,
    sent_at       INTEGER NOT NULL,
    created_at    INTEGER NOT NULL DEFAULT 0,
    updated_at    INTEGER NOT NULL DEFAULT 0,
    deleted_at    INTEGER,
    FOREIGN KEY(booking_id) REFERENCES bookings(id)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_reminder_dispatch_lookup
    ON reminder_dispatch(booking_id, reminder_kind) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_reminder_dispatch_booking_fk
    ON reminder_dispatch(booking_id);

-- schedule_change_notice: enqueued notification per affected booking when a
-- session is cancelled. Partial unique index prevents duplicate enqueue.
-- session_id is NOT NULL: every notice is enqueued from a concrete session
-- cancellation, so it always references that session. enqueued_at and sent_at
-- are UTC Unix ms.
CREATE TABLE IF NOT EXISTS schedule_change_notice (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    booking_id  INTEGER NOT NULL,
    session_id  INTEGER NOT NULL,
    change_kind TEXT    NOT NULL
        CHECK(change_kind <> '' AND change_kind = TRIM(change_kind)),
    status      TEXT    NOT NULL DEFAULT 'pending'
        CHECK(status IN ('pending','sent')),
    channel     TEXT,
    detail      TEXT,
    enqueued_at INTEGER NOT NULL,
    sent_at     INTEGER,
    created_at  INTEGER NOT NULL DEFAULT 0,
    updated_at  INTEGER NOT NULL DEFAULT 0,
    deleted_at  INTEGER,
    FOREIGN KEY(booking_id) REFERENCES bookings(id),
    FOREIGN KEY(session_id) REFERENCES sessions(id)
);
CREATE INDEX IF NOT EXISTS idx_schedule_change_notice_lookup
    ON schedule_change_notice(status, booking_id, change_kind);
CREATE INDEX IF NOT EXISTS idx_schedule_change_notice_booking_fk
    ON schedule_change_notice(booking_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_schedule_change_notice_dedup
    ON schedule_change_notice(booking_id, change_kind) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_schedule_change_notice_session
    ON schedule_change_notice(session_id) WHERE session_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_schedule_change_notice_session_fk
    ON schedule_change_notice(session_id);

-- reminder_rule: durable, bounded set of booking-reminder rules. rule_key is the
-- stable identity (unique among active rows); version is a monotonic revision
-- counter bumped on each material change so reminder_dispatch rows can reference
-- the exact rule revision they ran. reminder_kind stays the dedup partition that
-- reminder_dispatch keys on. status enables/disables a rule without soft-delete;
-- deleted_at remains the soft-delete mechanism. offset_minutes is the lead time
-- (minutes before booking start) at which the reminder is due.
CREATE TABLE IF NOT EXISTS reminder_rule (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    rule_key       TEXT    NOT NULL
        CHECK(rule_key <> '' AND rule_key = TRIM(rule_key) AND rule_key = LOWER(rule_key)),
    version        INTEGER NOT NULL DEFAULT 1 CHECK(version >= 1),
    reminder_kind  TEXT    NOT NULL
        CHECK(reminder_kind <> '' AND reminder_kind = TRIM(reminder_kind)),
    offset_minutes INTEGER NOT NULL CHECK(offset_minutes >= 0),
    channel        TEXT
        CHECK(channel IS NULL OR (channel <> '' AND channel = TRIM(channel))),
    default_locale TEXT
        CHECK(default_locale IS NULL OR (default_locale <> ''
          AND default_locale = TRIM(default_locale)
          AND default_locale = LOWER(default_locale)
          AND LENGTH(default_locale) BETWEEN 2 AND 12
          AND default_locale NOT GLOB '*[^a-z0-9-]*')),
    description    TEXT,
    status         TEXT    NOT NULL DEFAULT 'active'
        CHECK(status IN ('active','disabled')),
    created_at     INTEGER NOT NULL DEFAULT 0,
    updated_at     INTEGER NOT NULL DEFAULT 0,
    deleted_at     INTEGER
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_reminder_rule_key
    ON reminder_rule(rule_key) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_reminder_rule_status
    ON reminder_rule(status) WHERE deleted_at IS NULL;

-- schedule_change_rule: durable enable/disable switches for proactive
-- schedule-change notices. The product-owned systemd timer is installed and
-- enabled by setup, but the dispatcher only sends notice kinds with an active
-- rule. This mirrors booking-reminder rules without lead-time windows.
CREATE TABLE IF NOT EXISTS schedule_change_rule (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    rule_key       TEXT    NOT NULL
        CHECK(rule_key <> '' AND rule_key = TRIM(rule_key) AND rule_key = LOWER(rule_key)),
    change_kind    TEXT    NOT NULL
        CHECK(change_kind <> '' AND change_kind = TRIM(change_kind)),
    channel        TEXT
        CHECK(channel IS NULL OR (channel <> '' AND channel = TRIM(channel))),
    default_locale TEXT
        CHECK(default_locale IS NULL OR (default_locale <> ''
          AND default_locale = TRIM(default_locale)
          AND default_locale = LOWER(default_locale)
          AND LENGTH(default_locale) BETWEEN 2 AND 12
          AND default_locale NOT GLOB '*[^a-z0-9-]*')),
    description    TEXT,
    status         TEXT    NOT NULL DEFAULT 'disabled'
        CHECK(status IN ('active','disabled')),
    created_at     INTEGER NOT NULL DEFAULT 0,
    updated_at     INTEGER NOT NULL DEFAULT 0,
    deleted_at     INTEGER
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_schedule_change_rule_key
    ON schedule_change_rule(rule_key) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_schedule_change_rule_kind
    ON schedule_change_rule(change_kind) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_schedule_change_rule_status
    ON schedule_change_rule(status) WHERE deleted_at IS NULL;

-- reminder_failure: durable retry/failure metadata for reminders the dispatcher
-- could not deliver on a pass (render/send/missing-contact/record-after-send).
-- One active row per (booking_id, reminder_kind) — the same dedup partition
-- reminder_dispatch keys on — enforced by the partial unique index. attempt_count
-- / last_attempt_at / next_retry_after drive the retry backoff; expires_at is the
-- hard cutoff after which the reminder is abandoned; resolved_at is stamped when a
-- later pass finally delivers it, dropping the row out of the active set.
-- error_category is bounded to the four retryable failure kinds. All timestamps
-- are UTC Unix ms. No reminder is marked sent without a successful WhatsApp send,
-- so a failure row never coexists with a reminder_dispatch row for the same key.
CREATE TABLE IF NOT EXISTS reminder_failure (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    booking_id       INTEGER NOT NULL,
    reminder_kind    TEXT    NOT NULL
        CHECK(reminder_kind <> '' AND reminder_kind = TRIM(reminder_kind)),
    error_category   TEXT    NOT NULL
        CHECK(error_category IN ('render','send','missing_contact','record')),
    error_message    TEXT,
    attempt_count    INTEGER NOT NULL DEFAULT 1 CHECK(attempt_count >= 1),
    last_attempt_at  INTEGER NOT NULL,
    next_retry_after INTEGER NOT NULL,
    expires_at       INTEGER NOT NULL,
    resolved_at      INTEGER,
    created_at       INTEGER NOT NULL DEFAULT 0,
    updated_at       INTEGER NOT NULL DEFAULT 0,
    deleted_at       INTEGER,
    FOREIGN KEY(booking_id) REFERENCES bookings(id)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_reminder_failure_lookup
    ON reminder_failure(booking_id, reminder_kind) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_reminder_failure_booking_fk
    ON reminder_failure(booking_id);
CREATE INDEX IF NOT EXISTS idx_reminder_failure_active
    ON reminder_failure(next_retry_after) WHERE deleted_at IS NULL AND resolved_at IS NULL;

-- schedule_change_failure: durable retry/failure metadata for schedule-change
-- notices the dispatcher could not deliver on a pass (render/send/missing-contact/
-- record-after-send). It mirrors reminder_failure exactly, keyed on the
-- schedule_change_notice dedup partition (booking_id, change_kind). One active row
-- per key (enforced by the partial unique index). attempt_count / last_attempt_at
-- / next_retry_after drive the retry backoff; expires_at is the hard cutoff after
-- which the notice is abandoned; resolved_at is stamped when a later pass finally
-- delivers it, dropping the row out of the active set. error_category is bounded to
-- the four retryable failure kinds. All timestamps are UTC Unix ms.
CREATE TABLE IF NOT EXISTS schedule_change_failure (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    booking_id       INTEGER NOT NULL,
    change_kind      TEXT    NOT NULL
        CHECK(change_kind <> '' AND change_kind = TRIM(change_kind)),
    error_category   TEXT    NOT NULL
        CHECK(error_category IN ('render','send','missing_contact','record')),
    error_message    TEXT,
    attempt_count    INTEGER NOT NULL DEFAULT 1 CHECK(attempt_count >= 1),
    last_attempt_at  INTEGER NOT NULL,
    next_retry_after INTEGER NOT NULL,
    expires_at       INTEGER NOT NULL,
    resolved_at      INTEGER,
    created_at       INTEGER NOT NULL DEFAULT 0,
    updated_at       INTEGER NOT NULL DEFAULT 0,
    deleted_at       INTEGER,
    FOREIGN KEY(booking_id) REFERENCES bookings(id)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_schedule_change_failure_lookup
    ON schedule_change_failure(booking_id, change_kind) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_schedule_change_failure_booking_fk
    ON schedule_change_failure(booking_id);
CREATE INDEX IF NOT EXISTS idx_schedule_change_failure_active
    ON schedule_change_failure(next_retry_after) WHERE deleted_at IS NULL AND resolved_at IS NULL;

-- session_surf_advice: the product-owned daily surf-advice dispatcher records
-- ONE overall advice per scheduled session for today and tomorrow — a single
-- forecast condition and a short justification that explains the ranking of the
-- advised favorite surf spots as a whole. forecast_condition is the recorded
-- enum (matching the surf-conditions vocabulary); justification is a short human
-- explanation; generated_at is the UTC ms instant the pass produced it. The
-- session's date already lives on sessions, so no forecast_date is duplicated
-- here. session_id is an integer FK to sessions. The daily pass replaces a
-- session's advice idempotently (soft-delete + reinsert), so the partial unique
-- index guaranteeing one active advice per session always holds. The ranked
-- spots for the advice live in the child session_surf_advice_spots table.
CREATE TABLE IF NOT EXISTS session_surf_advice (
    id                 INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id         INTEGER NOT NULL,
    forecast_condition TEXT    NOT NULL
        CHECK(forecast_condition IN ('ideal','ok','cancel_session')),
    justification      TEXT,
    generated_at       INTEGER NOT NULL,
    created_at         INTEGER NOT NULL DEFAULT 0,
    updated_at         INTEGER NOT NULL DEFAULT 0,
    deleted_at         INTEGER,
    FOREIGN KEY(session_id) REFERENCES sessions(id)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_session_surf_advice_session
    ON session_surf_advice(session_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_session_surf_advice_session_fk
    ON session_surf_advice(session_id);

-- session_surf_advice_spots: the ranked spot rows for one session_surf_advice —
-- the ordered list of advised favorite surf spots (advice_rank 1 is the top pick,
-- 2 the runner-up) the overall advice ranked. These rows carry only the ranking,
-- never a per-spot condition/justification: the forecast condition and
-- justification are session-level and live on the parent. session_surf_advice_id
-- and surf_spot_id are integer FKs to their parents' primary keys. The daily pass
-- replaces a session's ranking rows alongside the parent, so the partial unique
-- index on active (session_surf_advice_id, advice_rank) always holds.
CREATE TABLE IF NOT EXISTS session_surf_advice_spots (
    id                     INTEGER PRIMARY KEY AUTOINCREMENT,
    session_surf_advice_id INTEGER NOT NULL,
    surf_spot_id           INTEGER NOT NULL,
    advice_rank            INTEGER NOT NULL CHECK(advice_rank IN (1,2)),
    created_at             INTEGER NOT NULL DEFAULT 0,
    updated_at             INTEGER NOT NULL DEFAULT 0,
    deleted_at             INTEGER,
    FOREIGN KEY(session_surf_advice_id) REFERENCES session_surf_advice(id),
    FOREIGN KEY(surf_spot_id) REFERENCES surf_spots(id)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_session_surf_advice_spots_rank
    ON session_surf_advice_spots(session_surf_advice_id, advice_rank) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_session_surf_advice_spots_advice_fk
    ON session_surf_advice_spots(session_surf_advice_id);
CREATE INDEX IF NOT EXISTS idx_session_surf_advice_spots_spot_fk
    ON session_surf_advice_spots(surf_spot_id);
