-- Zapytania do pokazania w konsoli D1 i do porównania z odpowiedziami agenta.

-- 1. Ile zgłoszeń w każdym miesiącu, według tematu
SELECT * FROM v_submissions_by_month ORDER BY month, submissions DESC;

-- 2. Nowe zgłoszenia czekające na synchronizację z Attio
SELECT id, created_at, full_name, company_name, topic, budget_range, attachment_key
FROM form_submissions
WHERE status = 'new'
ORDER BY id;

-- 3. Zgłoszenia z załącznikiem — wiersz w D1 wskazuje plik w R2 kluczem
SELECT id, company_name, attachment_key
FROM form_submissions
WHERE attachment_key IS NOT NULL;

-- 4. Odsetek spamu
SELECT
  COUNT(*)                                                     AS all_submissions,
  SUM(CASE WHEN status = 'spam' OR ai_category = 'spam' THEN 1 ELSE 0 END) AS spam,
  ROUND(100.0 * SUM(CASE WHEN status = 'spam' OR ai_category = 'spam' THEN 1 ELSE 0 END) / COUNT(*), 1) AS spam_pct
FROM form_submissions;

-- 5. Test uprawnień: ten zapis wykonany tokenem "D1 Read" musi zostać odrzucony przez Cloudflare.
--    Tym samym tokenem SELECT z punktów 1–4 działa.
UPDATE form_submissions SET status = 'spam' WHERE id = 13;

-- 6. Ten sam zapis tokenem "D1 Edit" przechodzi. Cofnięcie zmiany po demo:
UPDATE form_submissions SET status = 'new' WHERE id = 13;
