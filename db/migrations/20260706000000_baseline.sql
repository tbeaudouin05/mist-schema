-- Baseline migration: initial schema.
-- Hand-authored from db/schema.sql because local Atlas trigger diff requires
-- atlas login (libsql/sqlite trigger support). Future migrations should be
-- Atlas-generated via `atlas migrate diff <name> --env turso_test`.

CREATE TABLE runtime_config (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    config_id      TEXT    NOT NULL,
    config_version INTEGER NOT NULL DEFAULT 1,
    created_at     INTEGER NOT NULL DEFAULT 0,
    updated_at     INTEGER NOT NULL DEFAULT 0,
    deleted_at     INTEGER,
    config_json    TEXT    NOT NULL
);
CREATE UNIQUE INDEX idx_runtime_config_config_id
    ON runtime_config(config_id) WHERE deleted_at IS NULL;

CREATE TABLE agent_state (
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

CREATE TABLE conversation_state (
    id                       INTEGER PRIMARY KEY AUTOINCREMENT,
    conversation_id          TEXT    NOT NULL,
    last_seen_config_version INTEGER,
    ai_enabled               INTEGER NOT NULL DEFAULT 1 CHECK(ai_enabled IN (0,1)),
    created_at               INTEGER NOT NULL DEFAULT 0,
    updated_at               INTEGER NOT NULL DEFAULT 0,
    deleted_at               INTEGER
);
CREATE UNIQUE INDEX idx_conversation_state_conversation_id
    ON conversation_state(conversation_id) WHERE deleted_at IS NULL;

CREATE TABLE school_settings (
    id         INTEGER PRIMARY KEY CHECK(id = 1),
    timezone   TEXT    NOT NULL
        CHECK(timezone <> '' AND timezone = TRIM(timezone)
          AND timezone NOT GLOB '*/*'
          AND timezone NOT GLOB '*[+ ]*'),
    currency   TEXT    NOT NULL
        CHECK(LENGTH(currency) = 3 AND currency = UPPER(currency)),
    created_at INTEGER NOT NULL DEFAULT 0,
    updated_at INTEGER NOT NULL DEFAULT 0,
    deleted_at INTEGER
);
CREATE TRIGGER trg_school_settings_currency_immutable
    BEFORE UPDATE OF currency ON school_settings
    WHEN OLD.currency <> NEW.currency
BEGIN
    SELECT RAISE(ABORT, 'school_settings currency is setup-once immutable');
END;

CREATE TABLE customers (
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
CREATE UNIQUE INDEX idx_customers_whatsapp_phone
    ON customers(whatsapp_phone) WHERE deleted_at IS NULL;

CREATE TABLE offering_templates (
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
CREATE UNIQUE INDEX idx_offering_templates_slot
    ON offering_templates(name, weekday, time_slot) WHERE deleted_at IS NULL;
CREATE INDEX idx_offering_templates_name
    ON offering_templates(name) WHERE deleted_at IS NULL;

CREATE TABLE sessions (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    offering_name       TEXT    NOT NULL
        CHECK(offering_name <> '' AND offering_name = TRIM(offering_name)),
    date                TEXT    NOT NULL CHECK(date <> '' AND date = TRIM(date)),
    time_slot           TEXT    NOT NULL
        CHECK(time_slot <> '' AND time_slot = TRIM(time_slot)),
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
CREATE INDEX idx_sessions_slot
    ON sessions(offering_name, date, time_slot, status);
CREATE INDEX idx_sessions_date
    ON sessions(date, status);
CREATE INDEX idx_sessions_starts_at
    ON sessions(starts_at_ms, status);

CREATE TABLE inquiries (
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
CREATE INDEX idx_inquiries_slot
    ON inquiries(offering_name, date, time_slot, status);
CREATE INDEX idx_inquiries_customer
    ON inquiries(customer_id, date, status);
CREATE INDEX idx_inquiries_customer_fk
    ON inquiries(customer_id);
CREATE INDEX idx_inquiries_session
    ON inquiries(session_id) WHERE session_id IS NOT NULL;
CREATE INDEX idx_inquiries_session_fk
    ON inquiries(session_id);

CREATE TABLE bookings (
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
CREATE INDEX idx_bookings_customer
    ON bookings(customer_id, status);
CREATE INDEX idx_bookings_customer_fk
    ON bookings(customer_id);
CREATE INDEX idx_bookings_session
    ON bookings(session_id) WHERE session_id IS NOT NULL;
CREATE INDEX idx_bookings_session_fk
    ON bookings(session_id);
CREATE TRIGGER trg_bookings_mark_confirmed_after_paid
    AFTER UPDATE OF payment_status ON bookings
    WHEN NEW.payment_status = 'paid' AND NEW.status = 'pending_payment'
BEGIN
    UPDATE bookings SET status = 'confirmed' WHERE id = NEW.id;
END;

CREATE TABLE reminder_dispatch (
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
CREATE UNIQUE INDEX idx_reminder_dispatch_lookup
    ON reminder_dispatch(booking_id, reminder_kind) WHERE deleted_at IS NULL;
CREATE INDEX idx_reminder_dispatch_booking_fk
    ON reminder_dispatch(booking_id);

CREATE TABLE schedule_change_notice (
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
CREATE INDEX idx_schedule_change_notice_lookup
    ON schedule_change_notice(status, booking_id, change_kind);
CREATE INDEX idx_schedule_change_notice_booking_fk
    ON schedule_change_notice(booking_id);
CREATE UNIQUE INDEX idx_schedule_change_notice_dedup
    ON schedule_change_notice(booking_id, change_kind) WHERE deleted_at IS NULL;
CREATE INDEX idx_schedule_change_notice_session
    ON schedule_change_notice(session_id) WHERE session_id IS NOT NULL;
CREATE INDEX idx_schedule_change_notice_session_fk
    ON schedule_change_notice(session_id);

CREATE TABLE reminder_rule (
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
CREATE UNIQUE INDEX idx_reminder_rule_key
    ON reminder_rule(rule_key) WHERE deleted_at IS NULL;
CREATE INDEX idx_reminder_rule_status
    ON reminder_rule(status) WHERE deleted_at IS NULL;

CREATE TABLE schedule_change_rule (
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
CREATE UNIQUE INDEX idx_schedule_change_rule_key
    ON schedule_change_rule(rule_key) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX idx_schedule_change_rule_kind
    ON schedule_change_rule(change_kind) WHERE deleted_at IS NULL;
CREATE INDEX idx_schedule_change_rule_status
    ON schedule_change_rule(status) WHERE deleted_at IS NULL;

CREATE TABLE reminder_failure (
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
CREATE UNIQUE INDEX idx_reminder_failure_lookup
    ON reminder_failure(booking_id, reminder_kind) WHERE deleted_at IS NULL;
CREATE INDEX idx_reminder_failure_booking_fk
    ON reminder_failure(booking_id);
CREATE INDEX idx_reminder_failure_active
    ON reminder_failure(next_retry_after) WHERE deleted_at IS NULL AND resolved_at IS NULL;

CREATE TABLE schedule_change_failure (
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
CREATE UNIQUE INDEX idx_schedule_change_failure_lookup
    ON schedule_change_failure(booking_id, change_kind) WHERE deleted_at IS NULL;
CREATE INDEX idx_schedule_change_failure_booking_fk
    ON schedule_change_failure(booking_id);
CREATE INDEX idx_schedule_change_failure_active
    ON schedule_change_failure(next_retry_after) WHERE deleted_at IS NULL AND resolved_at IS NULL;
