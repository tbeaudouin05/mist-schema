-- Add column "updated_at" to table: "school_information_versions"
ALTER TABLE `school_information_versions` ADD COLUMN `updated_at` integer NOT NULL DEFAULT 0;
