-- Disable the enforcement of foreign-keys constraints
PRAGMA foreign_keys = off;
-- Create "new_school_information_versions" table
CREATE TABLE `new_school_information_versions` (
  `id` integer NULL PRIMARY KEY AUTOINCREMENT,
  `school_settings_id` integer NOT NULL,
  `status` text NOT NULL DEFAULT 'approved',
  `canonical_url` text NULL,
  `summary` text NULL,
  `detailed_info` text NOT NULL,
  `source_urls` text NOT NULL,
  `created_at` integer NOT NULL DEFAULT 0,
  `updated_at` integer NOT NULL DEFAULT 0,
  `approved_at` integer NOT NULL DEFAULT 0,
  `superseded_at` integer NULL,
  `expires_at` integer NULL,
  `deleted_at` integer NULL,
  CONSTRAINT `0` FOREIGN KEY (`school_settings_id`) REFERENCES `school_settings` (`id`) ON UPDATE NO ACTION ON DELETE NO ACTION,
  CHECK (school_settings_id = 1),
  CHECK (status IN ('pending','approved','superseded')),
  CHECK (canonical_url IS NULL OR (canonical_url <> ''
          AND canonical_url = TRIM(canonical_url)
          AND LENGTH(canonical_url) <= 2048)),
  CHECK (summary IS NULL OR (summary <> ''
          AND summary = TRIM(summary)
          AND LENGTH(summary) <= 1000)),
  CHECK (detailed_info <> ''
          AND detailed_info = TRIM(detailed_info)
          AND LENGTH(detailed_info) <= 100000),
  CHECK (source_urls <> ''
          AND source_urls = TRIM(source_urls)
          AND LENGTH(source_urls) <= 20000
          AND JSON_VALID(source_urls)
          AND JSON_TYPE(source_urls) = 'array'
          AND JSON_ARRAY_LENGTH(source_urls) > 0),
  CHECK (created_at >= 0),
  CHECK (updated_at >= 0),
  CHECK (approved_at >= 0),
  CHECK (status <> 'pending' OR (canonical_url IS NOT NULL
      AND summary IS NOT NULL
      AND approved_at = 0
      AND superseded_at IS NULL
      AND expires_at IS NOT NULL)),
  CHECK (status <> 'approved' OR (approved_at >= 0 AND superseded_at IS NULL)),
  CHECK (status <> 'superseded' OR superseded_at IS NOT NULL),
  CHECK (approved_at = 0 OR approved_at >= created_at),
  CHECK (superseded_at IS NULL OR superseded_at >= created_at),
  CHECK (expires_at IS NULL OR expires_at > created_at),
  CHECK (deleted_at IS NULL OR deleted_at >= created_at)
);
-- Copy rows from old table "school_information_versions" to new temporary table "new_school_information_versions"
INSERT INTO `new_school_information_versions` (`id`, `school_settings_id`, `detailed_info`, `source_urls`, `created_at`, `updated_at`, `deleted_at`) SELECT `id`, `school_settings_id`, `detailed_info`, `source_urls`, `created_at`, `updated_at`, `deleted_at` FROM `school_information_versions`;
-- Drop "school_information_versions" table after copying rows
DROP TABLE `school_information_versions`;
-- Rename temporary table "new_school_information_versions" to "school_information_versions"
ALTER TABLE `new_school_information_versions` RENAME TO `school_information_versions`;
-- Create index "idx_school_information_versions_one_approved" to table: "school_information_versions"
CREATE UNIQUE INDEX `idx_school_information_versions_one_approved` ON `school_information_versions` (`school_settings_id`) WHERE deleted_at IS NULL AND status = 'approved' AND approved_at > 0;
-- Create index "idx_school_information_versions_pending_lookup" to table: "school_information_versions"
CREATE INDEX `idx_school_information_versions_pending_lookup` ON `school_information_versions` (`school_settings_id`, `status`, `created_at` DESC, `id` DESC, `expires_at`) WHERE deleted_at IS NULL AND status = 'pending';
-- Create index "idx_school_information_versions_retention" to table: "school_information_versions"
CREATE INDEX `idx_school_information_versions_retention` ON `school_information_versions` (`school_settings_id`, `status`, `approved_at` DESC, `id` DESC) WHERE deleted_at IS NULL;
-- Create index "idx_school_information_versions_school_settings_fk" to table: "school_information_versions"
CREATE INDEX `idx_school_information_versions_school_settings_fk` ON `school_information_versions` (`school_settings_id`);
-- Create trigger "trg_school_information_versions_no_new_legacy_approved"
CREATE TRIGGER `trg_school_information_versions_no_new_legacy_approved` BEFORE INSERT ON `school_information_versions` FOR EACH ROW WHEN NEW.status = 'approved'
      AND (NEW.approved_at = 0 OR NEW.canonical_url IS NULL OR NEW.summary IS NULL) BEGIN
    SELECT RAISE(ABORT, 'new approved school information must be complete and timestamped');
END;
-- Create trigger "trg_school_information_versions_status_transition"
CREATE TRIGGER `trg_school_information_versions_status_transition` BEFORE UPDATE OF `status` ON `school_information_versions` FOR EACH ROW WHEN OLD.status <> NEW.status
      AND NOT (
        (OLD.status = 'pending' AND NEW.status IN ('approved', 'superseded'))
        OR (OLD.status = 'approved' AND NEW.status = 'superseded')
      ) BEGIN
    SELECT RAISE(ABORT, 'invalid school information status transition');
END;
-- Enable back the enforcement of foreign-keys constraints
PRAGMA foreign_keys = on;
