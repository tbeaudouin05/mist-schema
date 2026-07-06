-- Add surf_spots, session_surf_advice, and session_surf_advice_spots tables.

CREATE TABLE surf_spots (
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
CREATE UNIQUE INDEX idx_surf_spots_name
    ON surf_spots(name) WHERE deleted_at IS NULL;

CREATE TABLE session_surf_advice (
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
CREATE UNIQUE INDEX idx_session_surf_advice_session
    ON session_surf_advice(session_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_session_surf_advice_session_fk
    ON session_surf_advice(session_id);

CREATE TABLE session_surf_advice_spots (
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
CREATE UNIQUE INDEX idx_session_surf_advice_spots_rank
    ON session_surf_advice_spots(session_surf_advice_id, advice_rank) WHERE deleted_at IS NULL;
CREATE INDEX idx_session_surf_advice_spots_advice_fk
    ON session_surf_advice_spots(session_surf_advice_id);
CREATE INDEX idx_session_surf_advice_spots_spot_fk
    ON session_surf_advice_spots(surf_spot_id);
