-- ============================================================
-- SmartFlow Observatory — Methodology Query 01
-- Endpoint Mortality Distribution by Status Code + Registry Source
-- ============================================================
-- Source DB: mapper.db
-- Atlas Reference: Finding 1, Atlas Part I — "Endpoint mortality cohort"
-- Drill-Down: drill-downs/01-endpoint-mortality/report.md
-- ============================================================
-- Observation window: 2026-04-12 → 2026-05-15 (33-day Q1 cohort)
-- Catalogue cumulative size at snapshot: 22,249 endpoints
-- Expected output (Atlas Mid-2026 baseline):
--   HTTP 200: 923 endpoints (4.15%)
--   HTTP 404: 6,471 endpoints (29.1%)
--   HTTP 0 (non-responsive): 13,327 endpoints (59.9%)
--   payment_required_valid=1 (strict compliance): 128 (0.58%)
-- ============================================================
-- Last verified: 2026-05-16 (Stage 3 Curator re-query)
-- ============================================================

-- ---- 1.1 — Status code distribution across the full catalogue ----
SELECT
  COALESCE(http_status_code, 0) AS status_code,
  COUNT(*) AS endpoint_count,
  ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM endpoints), 2) AS pct_of_total
FROM endpoints
GROUP BY status_code
ORDER BY endpoint_count DESC;

-- ---- 1.2 — Strict x402 compliance (payment_required_valid=1) ----
SELECT
  COUNT(*) AS strict_compliant_count,
  ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM endpoints), 4) AS pct_of_total
FROM endpoints
WHERE payment_required_valid = 1;

-- ---- 1.3 — Registry-source survival ratio ----
-- This is the load-bearing chart in drill-down #1.
-- Survival = (endpoints alive at snapshot) / (endpoints first-seen ≥14 days ago) per source.
SELECT
  registry_source,
  COUNT(*) AS total_in_cohort,
  SUM(CASE WHEN http_status_code = 200 THEN 1 ELSE 0 END) AS alive_count,
  ROUND(
    100.0 * SUM(CASE WHEN http_status_code = 200 THEN 1 ELSE 0 END) / COUNT(*),
    2
  ) AS survival_pct
FROM endpoints
WHERE first_seen_date <= date('now', '-14 days')
GROUP BY registry_source
ORDER BY survival_pct DESC;

-- ---- 1.4 — Top providers by catalogue contribution + survival ----
SELECT
  provider_inferred,
  COUNT(*) AS catalogue_count,
  SUM(CASE WHEN http_status_code = 200 THEN 1 ELSE 0 END) AS alive_count,
  ROUND(
    100.0 * SUM(CASE WHEN http_status_code = 200 THEN 1 ELSE 0 END) / COUNT(*),
    2
  ) AS survival_pct
FROM endpoints
GROUP BY provider_inferred
HAVING COUNT(*) >= 50
ORDER BY catalogue_count DESC
LIMIT 20;

-- ============================================================
-- Three ways this query could be wrong:
-- ============================================================
-- 1. http_status_code = 0 may conflate "never probed" with "probe error / network timeout".
--    The Atlas separates these into NULL (never probed) vs explicit 0 (probe attempt, failure).
--    If your mapper.db doesn't make this distinction, the 59.9% figure may overcount.
--
-- 2. first_seen_date depends on the crawler's discovery timeline. Endpoints discovered late
--    (e.g., last 7 days) are excluded from the 14-day survival cohort, but the catalogue total
--    still includes them. The 0.58% compliance figure uses the full catalogue; the 23.3% / 96.7%
--    registry survival splits use only endpoints first-seen ≥14 days ago.
--
-- 3. registry_source classifier is a hand-curated mapping from URL pattern to source tag.
--    Edge cases (e.g., an endpoint discovered via well-known but later imported into 402index)
--    are deduplicated to the first-discovered source. If your deduplication policy differs,
--    cohort sizes will shift.
-- ============================================================
