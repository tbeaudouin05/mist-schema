-- Add column "school_website_url" to table: "school_settings"
ALTER TABLE `school_settings` ADD COLUMN `school_website_url` text NULL;
-- Add column "school_info_summary" to table: "school_settings"
ALTER TABLE `school_settings` ADD COLUMN `school_info_summary` text NULL;
-- Add column "school_info_updated_at" to table: "school_settings"
ALTER TABLE `school_settings` ADD COLUMN `school_info_updated_at` integer NULL;
-- Create "school_information_versions" table
CREATE TABLE `school_information_versions` (
  `id` integer NULL PRIMARY KEY AUTOINCREMENT,
  `school_settings_id` integer NOT NULL,
  `detailed_info` text NOT NULL,
  `source_urls` text NOT NULL,
  `created_at` integer NOT NULL DEFAULT 0,
  `deleted_at` integer NULL,
  CONSTRAINT `0` FOREIGN KEY (`school_settings_id`) REFERENCES `school_settings` (`id`) ON UPDATE NO ACTION ON DELETE NO ACTION,
  CHECK (school_settings_id = 1),
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
  CHECK (deleted_at IS NULL OR deleted_at >= created_at)
);
-- Create index "idx_school_information_versions_latest_active" to table: "school_information_versions"
CREATE INDEX `idx_school_information_versions_latest_active` ON `school_information_versions` (`school_settings_id`, `created_at` DESC, `id` DESC) WHERE deleted_at IS NULL;
-- Create index "idx_school_information_versions_school_settings_fk" to table: "school_information_versions"
CREATE INDEX `idx_school_information_versions_school_settings_fk` ON `school_information_versions` (`school_settings_id`);
