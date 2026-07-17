test "migrate" "v024_legacy_current_is_preserved" {
  migrate {
    to = "20260716211920"
  }
  exec {
    sql = <<-SQL
      INSERT INTO school_settings
        (id, timezone, currency, school_website_url, school_info_summary,
         school_info_updated_at, created_at, updated_at)
      VALUES
        (1, 'Etc%2FUTC', 'USD', 'https://school.example', 'Original summary',
         250, 10, 250);
      INSERT INTO school_information_versions
        (id, school_settings_id, detailed_info, source_urls, created_at, updated_at, deleted_at)
      VALUES
        (1, 1, 'Older details', '["https://source.example/old"]', 100, 110, NULL),
        (2, 1, 'Current details', '["https://source.example/current"]', 200, 210, NULL),
        (3, 1, 'Deleted details', '["https://source.example/deleted"]', 300, 305, 310);
    SQL
  }
  migrate {
    to = "20260717140630"
  }
  assert {
    sql = <<-SQL
      SELECT COUNT(*) = 1
        AND MAX(id) = 2
        AND MAX(canonical_url) = 'https://school.example'
        AND MAX(summary) = 'Original summary'
        AND MAX(approved_at) = 250
      FROM school_information_versions
      WHERE deleted_at IS NULL AND status = 'approved' AND approved_at > 0;
    SQL
  }
  assert {
    sql = <<-SQL
      SELECT COUNT(*) = 2
        AND SUM(CASE WHEN id = 1 AND approved_at = 0 AND superseded_at = 110 THEN 1 ELSE 0 END) = 1
        AND SUM(CASE WHEN id = 3 AND approved_at = 0 AND superseded_at = 305 AND deleted_at = 310 THEN 1 ELSE 0 END) = 1
      FROM school_information_versions
      WHERE status = 'superseded';
    SQL
  }
  assert {
    sql = "SELECT COUNT(*) = 3 FROM school_information_versions;"
  }
}

test "migrate" "v024_missing_singleton_fact_stays_noncurrent" {
  migrate {
    to = "20260716211920"
  }
  exec {
    sql = <<-SQL
      INSERT INTO school_settings
        (id, timezone, currency, school_website_url, school_info_summary,
         school_info_updated_at, created_at, updated_at)
      VALUES (1, 'Etc%2FUTC', 'USD', 'https://school.example', NULL, 250, 10, 250);
      INSERT INTO school_information_versions
        (id, school_settings_id, detailed_info, source_urls, created_at, updated_at)
      VALUES
        (1, 1, 'Older details', '["https://source.example/old"]', 100, 110),
        (2, 1, 'Latest details', '["https://source.example/latest"]', 200, 210);
    SQL
  }
  migrate {
    to = "20260717140630"
  }
  assert {
    sql = "SELECT COUNT(*) = 0 FROM school_information_versions WHERE deleted_at IS NULL AND status = 'approved';"
  }
  assert {
    sql = <<-SQL
      SELECT COUNT(*) = 2
        AND SUM(CASE WHEN approved_at = 0 AND canonical_url IS NULL
          AND summary IS NULL AND superseded_at > 0 THEN 1 ELSE 0 END) = 2
      FROM school_information_versions
      WHERE status = 'superseded';
    SQL
  }
}

test "migrate" "v024_existing_current_wins_over_legacy" {
  migrate {
    to = "20260716211920"
  }
  exec {
    sql = <<-SQL
      INSERT INTO school_settings
        (id, timezone, currency, school_website_url, school_info_summary,
         school_info_updated_at, created_at, updated_at)
      VALUES
        (1, 'Etc%2FUTC', 'USD', 'https://new.example', 'New summary', 500, 10, 500);
      INSERT INTO school_information_versions
        (id, school_settings_id, detailed_info, source_urls, created_at, updated_at)
      VALUES
        (1, 1, 'Legacy details', '["https://source.example/legacy"]', 100, 110);
    SQL
  }
  migrate {
    to = "20260717134538"
  }
  exec {
    sql = <<-SQL
      INSERT INTO school_information_versions
        (id, school_settings_id, status, canonical_url, summary, detailed_info,
         source_urls, created_at, updated_at, approved_at)
      VALUES
        (2, 1, 'approved', 'https://new.example', 'New summary', 'New details',
         '["https://source.example/new"]', 400, 500, 500);
    SQL
  }
  migrate {
    to = "20260717140630"
  }
  assert {
    sql = <<-SQL
      SELECT COUNT(*) = 1 AND MAX(id) = 2 AND MAX(approved_at) = 500
      FROM school_information_versions
      WHERE deleted_at IS NULL AND status = 'approved';
    SQL
  }
  assert {
    sql = <<-SQL
      SELECT status = 'superseded' AND approved_at = 0
        AND canonical_url IS NULL AND summary IS NULL AND superseded_at = 110
      FROM school_information_versions WHERE id = 1;
    SQL
  }
}
