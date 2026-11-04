-- Cloudflare D1 (SQLite) — zgłoszenia z formularza kontaktowego na stronie WWW
-- Uruchomienie:
--   npx wrangler d1 execute website-leads --remote --file=d1/schema.sql

DROP VIEW IF EXISTS v_submissions_by_month;
DROP TABLE IF EXISTS form_submissions;

CREATE TABLE form_submissions (
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  created_at        TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  full_name         TEXT    NOT NULL,
  email             TEXT    NOT NULL,
  phone             TEXT,
  company_name      TEXT,
  nip               TEXT    CHECK (nip IS NULL OR length(nip) = 10),
  topic             TEXT    NOT NULL CHECK (topic IN ('ai_agent', 'process_automation', 'system_integration', 'training', 'other')),
  budget_range      TEXT    NOT NULL DEFAULT 'unknown' CHECK (budget_range IN ('<20k', '20-50k', '50-150k', '>150k', 'unknown')),
  message           TEXT    NOT NULL,
  attachment_key    TEXT,                 -- klucz pliku w R2, np. contact-form/2026/10/27/studio-kadr-brief.pdf
  marketing_consent INTEGER NOT NULL DEFAULT 0 CHECK (marketing_consent IN (0, 1)),
  source_page       TEXT,
  status            TEXT    NOT NULL DEFAULT 'new' CHECK (status IN ('new', 'synced', 'spam', 'error', 'archived')),
  ai_category       TEXT,                 -- qualified | not_a_fit | spam (wynik klasyfikacji LLM)
  attio_person_id   TEXT,
  synced_at         TEXT,
  sync_error        TEXT
);

CREATE INDEX idx_form_submissions_status     ON form_submissions (status);
CREATE INDEX idx_form_submissions_created_at ON form_submissions (created_at);

CREATE VIEW v_submissions_by_month AS
SELECT
  substr(created_at, 1, 7)                          AS month,
  topic,
  COUNT(*)                                          AS submissions,
  SUM(CASE WHEN status = 'spam' THEN 1 ELSE 0 END)  AS spam
FROM form_submissions
GROUP BY 1, 2;
