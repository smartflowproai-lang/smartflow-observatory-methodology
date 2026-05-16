-- ============================================================
-- SmartFlow Observatory — Methodology Query 04
-- /.well-known/x402 Discovery Convention Adoption
-- ============================================================
-- Source DB: mapper.db
-- Atlas Reference: Finding 4, Atlas Part IV — "Discovery convention is healthy where used, barely used"
-- Drill-Down: drill-downs/05-wellknown-adoption/report.md
-- ============================================================
-- Expected output (Atlas Mid-2026 baseline):
--   /.well-known/x402 documents catalogued: 12
--   /.well-known/x402 documents HTTP 200: 11
--   /.well-known/x402 documents containing payment endpoints: 0
--   Apiosk-catalogued endpoints survival ratio: 100%
--   well-known-discovery cohort survival (excluding apinow.fun): 80.2%
-- ============================================================
-- Last verified: 2026-05-16 (Stage 3 Curator re-query)
-- ============================================================

-- ---- 4.1 — Discovery documents catalogued on canonical path ----
SELECT
  COUNT(*) AS wellknown_total_count,
  SUM(CASE WHEN http_status_code = 200 THEN 1 ELSE 0 END) AS wellknown_alive_count,
  SUM(CASE WHEN payment_required_valid = 1 THEN 1 ELSE 0 END) AS wellknown_with_payment_endpoint
FROM endpoints
WHERE url LIKE '%/.well-known/x402%';

-- ---- 4.2 — Host-level breakdown of /.well-known/x402 publishers ----
SELECT
  host,
  COUNT(*) AS endpoints_under_host,
  SUM(CASE WHEN url LIKE '%/.well-known/x402%' THEN 1 ELSE 0 END) AS has_wellknown_doc,
  SUM(CASE WHEN http_status_code = 200 THEN 1 ELSE 0 END) AS alive_count
FROM endpoints
WHERE host IN (
  SELECT DISTINCT host FROM endpoints WHERE url LIKE '%/.well-known/x402%'
)
GROUP BY host
ORDER BY endpoints_under_host DESC;

-- ---- 4.3 — Survival ratio by discovery source (the load-bearing chart in drill-down #5) ----
SELECT
  registry_source,
  COUNT(*) AS cohort_total,
  SUM(CASE WHEN http_status_code = 200 THEN 1 ELSE 0 END) AS alive_count,
  ROUND(
    100.0 * SUM(CASE WHEN http_status_code = 200 THEN 1 ELSE 0 END) / COUNT(*),
    2
  ) AS survival_pct
FROM endpoints
WHERE first_seen_date <= date('now', '-14 days')
  AND registry_source IN ('well-known-discovery', '402index', 'x402scan', 'apiosk')
GROUP BY registry_source
ORDER BY survival_pct DESC;

-- ---- 4.4 — apinow.fun deep dive (well-known concentration) ----
-- Strip apinow.fun out to see the "non-dominant-operator" survival of well-known
SELECT
  'apinow.fun-included' AS scope,
  COUNT(*) AS wellknown_endpoints,
  ROUND(
    100.0 * SUM(CASE WHEN http_status_code = 200 THEN 1 ELSE 0 END) / COUNT(*),
    2
  ) AS survival_pct
FROM endpoints
WHERE registry_source = 'well-known-discovery'
  AND first_seen_date <= date('now', '-14 days')

UNION ALL

SELECT
  'apinow.fun-excluded' AS scope,
  COUNT(*) AS wellknown_endpoints,
  ROUND(
    100.0 * SUM(CASE WHEN http_status_code = 200 THEN 1 ELSE 0 END) / COUNT(*),
    2
  ) AS survival_pct
FROM endpoints
WHERE registry_source = 'well-known-discovery'
  AND first_seen_date <= date('now', '-14 days')
  AND host != 'apinow.fun';

-- ============================================================
-- Three ways this query could be wrong:
-- ============================================================
-- 1. The `registry_source` tag is assigned at discovery time. An endpoint discovered via
--    /.well-known/x402 that is later also indexed in 402index would be tagged with the
--    first-discovered source. If the dedup policy differs in your mapper, the cohort sizes
--    will shift. The Atlas uses first-seen-first-source as the canonical dedup policy.
--
-- 2. /.well-known/x402 documents themselves are catalogued as endpoints, but they typically
--    contain pointer-style references to actual payment endpoints (the canonical pattern).
--    Whether the resource-pointed-to is counted as a "payment endpoint" or as a "well-known
--    discovery resource" depends on the classifier. The Atlas counts the well-known doc
--    itself; the resources it points to are separately counted in their own registry sources.
--
-- 3. The 12-document count is the catalogue snapshot at 2026-05-16. New well-known publishers
--    appearing daily would not be reflected. The drill-down #5 explicitly flags this as
--    "directional, given N=11 fragility" — small absolute numbers, large percentage swings.
-- ============================================================
