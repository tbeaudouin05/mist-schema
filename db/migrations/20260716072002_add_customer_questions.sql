-- Create "customer_questions" table
CREATE TABLE `customer_questions` (
  `id` integer NULL PRIMARY KEY AUTOINCREMENT,
  `customer_id` integer NOT NULL,
  `question_text` text NOT NULL,
  `status` text NOT NULL DEFAULT 'open',
  `follow_up_at` integer NULL,
  `resolved_at` integer NULL,
  `created_at` integer NOT NULL DEFAULT 0,
  `updated_at` integer NOT NULL DEFAULT 0,
  `deleted_at` integer NULL,
  CONSTRAINT `0` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`id`) ON UPDATE NO ACTION ON DELETE NO ACTION,
  CHECK (question_text <> ''
          AND question_text = TRIM(question_text)
          AND LENGTH(question_text) <= 2000),
  CHECK (status IN ('open','follow_up','resolved')),
  CHECK (status <> 'follow_up' OR follow_up_at IS NOT NULL),
  CHECK (follow_up_at IS NULL OR status IN ('follow_up','resolved')),
  CHECK ((status = 'resolved') = (resolved_at IS NOT NULL)),
  CHECK (follow_up_at IS NULL OR follow_up_at >= created_at),
  CHECK (resolved_at IS NULL OR resolved_at >= created_at)
);
-- Create index "idx_customer_questions_customer_open" to table: "customer_questions"
CREATE INDEX `idx_customer_questions_customer_open` ON `customer_questions` (`customer_id`, `created_at`) WHERE deleted_at IS NULL AND status = 'open';
-- Create index "idx_customer_questions_follow_up" to table: "customer_questions"
CREATE INDEX `idx_customer_questions_follow_up` ON `customer_questions` (`follow_up_at`, `customer_id`) WHERE deleted_at IS NULL AND status = 'follow_up';
-- Create index "idx_customer_questions_customer_fk" to table: "customer_questions"
CREATE INDEX `idx_customer_questions_customer_fk` ON `customer_questions` (`customer_id`);
