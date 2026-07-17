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
  CHECK (status <> 'approved' OR (canonical_url IS NOT NULL
      AND summary IS NOT NULL
      AND approved_at > 0
      AND superseded_at IS NULL)),
  CHECK (status <> 'superseded' OR superseded_at IS NOT NULL),
  CHECK (approved_at = 0 OR approved_at >= created_at),
  CHECK (superseded_at IS NULL OR superseded_at >= created_at),
  CHECK (expires_at IS NULL OR expires_at > created_at),
  CHECK (deleted_at IS NULL OR deleted_at >= created_at)
);
-- Copy rows from old table "school_information_versions" to new temporary table "new_school_information_versions".
-- v0.2.4 represented pre-lifecycle rows as approved_at = 0. Preserve the
-- previously current row (latest active by created_at/id) only when the legacy
-- singleton has complete, constraint-valid public fields. All other legacy rows
-- remain durable, non-current history.
INSERT INTO `new_school_information_versions` (`id`, `school_settings_id`, `status`, `canonical_url`, `summary`, `detailed_info`, `source_urls`, `created_at`, `updated_at`, `approved_at`, `superseded_at`, `expires_at`, `deleted_at`)
SELECT
  `v`.`id`,
  `v`.`school_settings_id`,
  CASE
    WHEN `v`.`status` = 'approved' AND `v`.`approved_at` = 0 THEN
      CASE WHEN `v`.`deleted_at` IS NULL
        AND `v`.`id` = (
          SELECT `candidate`.`id`
          FROM `school_information_versions` AS `candidate`
          WHERE `candidate`.`school_settings_id` = `v`.`school_settings_id`
            AND `candidate`.`deleted_at` IS NULL
            AND `candidate`.`status` = 'approved'
            AND `candidate`.`approved_at` = 0
            AND NOT EXISTS (
              SELECT 1 FROM `school_information_versions` AS `current`
              WHERE `current`.`school_settings_id` = `candidate`.`school_settings_id`
                AND `current`.`deleted_at` IS NULL
                AND `current`.`status` = 'approved'
                AND `current`.`approved_at` > 0
            )
          ORDER BY `candidate`.`created_at` DESC, `candidate`.`id` DESC
          LIMIT 1
        )
        AND EXISTS (
          SELECT 1
          FROM `school_settings` AS `settings`
          WHERE `settings`.`id` = `v`.`school_settings_id`
            AND `settings`.`deleted_at` IS NULL
            AND `settings`.`school_website_url` IS NOT NULL
            AND `settings`.`school_website_url` <> ''
            AND `settings`.`school_website_url` = TRIM(`settings`.`school_website_url`)
            AND LENGTH(`settings`.`school_website_url`) <= 2048
            AND `settings`.`school_info_summary` IS NOT NULL
            AND `settings`.`school_info_summary` <> ''
            AND `settings`.`school_info_summary` = TRIM(`settings`.`school_info_summary`)
            AND LENGTH(`settings`.`school_info_summary`) <= 1000
        )
      THEN 'approved' ELSE 'superseded' END
    ELSE `v`.`status`
  END,
  CASE
    WHEN `v`.`status` = 'approved' AND `v`.`approved_at` = 0
      AND `v`.`deleted_at` IS NULL
      AND `v`.`id` = (
        SELECT `candidate`.`id`
        FROM `school_information_versions` AS `candidate`
        WHERE `candidate`.`school_settings_id` = `v`.`school_settings_id`
          AND `candidate`.`deleted_at` IS NULL
          AND `candidate`.`status` = 'approved'
          AND `candidate`.`approved_at` = 0
          AND NOT EXISTS (
            SELECT 1 FROM `school_information_versions` AS `current`
            WHERE `current`.`school_settings_id` = `candidate`.`school_settings_id`
              AND `current`.`deleted_at` IS NULL
              AND `current`.`status` = 'approved'
              AND `current`.`approved_at` > 0
          )
        ORDER BY `candidate`.`created_at` DESC, `candidate`.`id` DESC
        LIMIT 1
      )
      AND EXISTS (
        SELECT 1 FROM `school_settings` AS `settings`
        WHERE `settings`.`id` = `v`.`school_settings_id`
          AND `settings`.`deleted_at` IS NULL
          AND `settings`.`school_website_url` IS NOT NULL
          AND `settings`.`school_website_url` <> ''
          AND `settings`.`school_website_url` = TRIM(`settings`.`school_website_url`)
          AND LENGTH(`settings`.`school_website_url`) <= 2048
          AND `settings`.`school_info_summary` IS NOT NULL
          AND `settings`.`school_info_summary` <> ''
          AND `settings`.`school_info_summary` = TRIM(`settings`.`school_info_summary`)
          AND LENGTH(`settings`.`school_info_summary`) <= 1000
      )
    THEN (SELECT `settings`.`school_website_url` FROM `school_settings` AS `settings` WHERE `settings`.`id` = `v`.`school_settings_id`)
    ELSE `v`.`canonical_url`
  END,
  CASE
    WHEN `v`.`status` = 'approved' AND `v`.`approved_at` = 0
      AND `v`.`deleted_at` IS NULL
      AND `v`.`id` = (
        SELECT `candidate`.`id`
        FROM `school_information_versions` AS `candidate`
        WHERE `candidate`.`school_settings_id` = `v`.`school_settings_id`
          AND `candidate`.`deleted_at` IS NULL
          AND `candidate`.`status` = 'approved'
          AND `candidate`.`approved_at` = 0
          AND NOT EXISTS (
            SELECT 1 FROM `school_information_versions` AS `current`
            WHERE `current`.`school_settings_id` = `candidate`.`school_settings_id`
              AND `current`.`deleted_at` IS NULL
              AND `current`.`status` = 'approved'
              AND `current`.`approved_at` > 0
          )
        ORDER BY `candidate`.`created_at` DESC, `candidate`.`id` DESC
        LIMIT 1
      )
      AND EXISTS (
        SELECT 1 FROM `school_settings` AS `settings`
        WHERE `settings`.`id` = `v`.`school_settings_id`
          AND `settings`.`deleted_at` IS NULL
          AND `settings`.`school_website_url` IS NOT NULL
          AND `settings`.`school_website_url` <> ''
          AND `settings`.`school_website_url` = TRIM(`settings`.`school_website_url`)
          AND LENGTH(`settings`.`school_website_url`) <= 2048
          AND `settings`.`school_info_summary` IS NOT NULL
          AND `settings`.`school_info_summary` <> ''
          AND `settings`.`school_info_summary` = TRIM(`settings`.`school_info_summary`)
          AND LENGTH(`settings`.`school_info_summary`) <= 1000
      )
    THEN (SELECT `settings`.`school_info_summary` FROM `school_settings` AS `settings` WHERE `settings`.`id` = `v`.`school_settings_id`)
    ELSE `v`.`summary`
  END,
  `v`.`detailed_info`,
  `v`.`source_urls`,
  `v`.`created_at`,
  `v`.`updated_at`,
  CASE
    WHEN `v`.`status` = 'approved' AND `v`.`approved_at` = 0
      AND `v`.`deleted_at` IS NULL
      AND `v`.`id` = (
        SELECT `candidate`.`id`
        FROM `school_information_versions` AS `candidate`
        WHERE `candidate`.`school_settings_id` = `v`.`school_settings_id`
          AND `candidate`.`deleted_at` IS NULL
          AND `candidate`.`status` = 'approved'
          AND `candidate`.`approved_at` = 0
          AND NOT EXISTS (
            SELECT 1 FROM `school_information_versions` AS `current`
            WHERE `current`.`school_settings_id` = `candidate`.`school_settings_id`
              AND `current`.`deleted_at` IS NULL
              AND `current`.`status` = 'approved'
              AND `current`.`approved_at` > 0
          )
        ORDER BY `candidate`.`created_at` DESC, `candidate`.`id` DESC
        LIMIT 1
      )
      AND EXISTS (
        SELECT 1 FROM `school_settings` AS `settings`
        WHERE `settings`.`id` = `v`.`school_settings_id`
          AND `settings`.`deleted_at` IS NULL
          AND `settings`.`school_website_url` IS NOT NULL
          AND `settings`.`school_website_url` <> ''
          AND `settings`.`school_website_url` = TRIM(`settings`.`school_website_url`)
          AND LENGTH(`settings`.`school_website_url`) <= 2048
          AND `settings`.`school_info_summary` IS NOT NULL
          AND `settings`.`school_info_summary` <> ''
          AND `settings`.`school_info_summary` = TRIM(`settings`.`school_info_summary`)
          AND LENGTH(`settings`.`school_info_summary`) <= 1000
      )
    THEN MAX(1, `v`.`created_at`, COALESCE((
      SELECT `settings`.`school_info_updated_at`
      FROM `school_settings` AS `settings`
      WHERE `settings`.`id` = `v`.`school_settings_id`
    ), 0))
    ELSE `v`.`approved_at`
  END,
  CASE
    WHEN `v`.`status` = 'approved' AND `v`.`approved_at` = 0 THEN
      CASE WHEN `v`.`deleted_at` IS NULL
        AND `v`.`id` = (
          SELECT `candidate`.`id`
          FROM `school_information_versions` AS `candidate`
          WHERE `candidate`.`school_settings_id` = `v`.`school_settings_id`
            AND `candidate`.`deleted_at` IS NULL
            AND `candidate`.`status` = 'approved'
            AND `candidate`.`approved_at` = 0
            AND NOT EXISTS (
              SELECT 1 FROM `school_information_versions` AS `current`
              WHERE `current`.`school_settings_id` = `candidate`.`school_settings_id`
                AND `current`.`deleted_at` IS NULL
                AND `current`.`status` = 'approved'
                AND `current`.`approved_at` > 0
            )
          ORDER BY `candidate`.`created_at` DESC, `candidate`.`id` DESC
          LIMIT 1
        )
        AND EXISTS (
          SELECT 1
          FROM `school_settings` AS `settings`
          WHERE `settings`.`id` = `v`.`school_settings_id`
            AND `settings`.`deleted_at` IS NULL
            AND `settings`.`school_website_url` IS NOT NULL
            AND `settings`.`school_website_url` <> ''
            AND `settings`.`school_website_url` = TRIM(`settings`.`school_website_url`)
            AND LENGTH(`settings`.`school_website_url`) <= 2048
            AND `settings`.`school_info_summary` IS NOT NULL
            AND `settings`.`school_info_summary` <> ''
            AND `settings`.`school_info_summary` = TRIM(`settings`.`school_info_summary`)
            AND LENGTH(`settings`.`school_info_summary`) <= 1000
        )
      THEN `v`.`superseded_at`
      ELSE MAX(1, `v`.`created_at`, `v`.`updated_at`) END
    ELSE `v`.`superseded_at`
  END,
  `v`.`expires_at`,
  `v`.`deleted_at`
FROM `school_information_versions` AS `v`;
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
-- Enable back the enforcement of foreign-keys constraints
PRAGMA foreign_keys = on;
