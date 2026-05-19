-- ============================================================
-- SmartFlow Observatory — Methodology Query 06
-- Strict x402 v2 Schema Validity — Catalogue Quality Layer
-- ============================================================
-- Source DB: mapper.db
-- Trigger: 2026-05-19 schema re-validation sweep flagged stale
--          payment_required_valid flag in 12,980 of 13,064 status=402
--          rows. sweep_all.py probe updates status but does not re-parse
--          /.well-known/x402 body for v2 schema compliance.
-- Companion script: src/sweep_validate_and_backfill.py (Phase 1)
-- Atlas Reference: planned Drill-Down (WI#7 candidate)
-- ============================================================
-- Expected output (post 2026-05-19 sweep):
--   total endpoints status=402: 13,064
--   payment_required_valid=1 (strict v2 compliant body): 11,505 (88.06%)
--   payment_required_valid=0 (HTTP 402 but non-compliant body): 1,522 (11.65%)
--   network errors at re-validation: 37 (0.28%)
--   distinct on_chain_wallet within valid cohort: 78
-- ============================================================
-- Last verified: 2026-05-19 11:18:18 UTC (Phase 1 sweep complete)
-- ============================================================

-- ---- 6.1 — Spec-validity distribution within paid (status=402) cohort ----
SELECT
  CASE
    WHEN payment_required_valid = 1 THEN 'spec-valid (v2 compliant body)'
    WHEN payment_required_valid = 0 THEN 'invalid402 (HTTP 402 but body non-compliant)'
    ELSE 'unknown / pending re-validation'
  END AS cohort,
  COUNT(*) AS endpoint_count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_402_cohort
FROM endpoints
WHERE status = 402
GROUP BY cohort
ORDER BY endpoint_count DESC;

-- ---- 6.2 — Spec-validity by registry source ----
-- Where do the 1,522 invalid-402 endpoints concentrate?
SELECT
  registry_source,
  COUNT(*) AS endpoints_status_402,
  SUM(CASE WHEN payment_required_valid = 1 THEN 1 ELSE 0 END) AS spec_valid_count,
  SUM(CASE WHEN payment_required_valid = 0 OR payment_required_valid IS NULL THEN 1 ELSE 0 END) AS invalid_count,
  ROUND(100.0 * SUM(CASE WHEN payment_required_valid = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_valid
FROM endpoints
WHERE status = 402
GROUP BY registry_source
ORDER BY endpoints_status_402 DESC
LIMIT 20;

-- ---- 6.3 — Recent first-seen valid-cohort additions ----
-- Surface endpoints that became spec-valid within the past 7 days.
SELECT
  url,
  registry_source,
  payment_required_amount,
  payment_required_token,
  first_seen,
  last_seen,
  on_chain_wallet
FROM endpoints
WHERE status = 402
  AND payment_required_valid = 1
  AND first_seen >= datetime('now', '-7 days')
ORDER BY first_seen DESC
LIMIT 25;

-- ---- 6.4 — Concentration of valid endpoints by recipient wallet ----
-- Operator-shape signal. Few wallets controlling many spec-valid endpoints
-- = aggregator / facilitator-style infrastructure deployment.
SELECT
  on_chain_wallet,
  COUNT(*) AS spec_valid_endpoints_under_wallet,
  ROUND(SUM(on_chain_volume_usdc), 2) AS lifetime_volume_usdc,
  COUNT(DISTINCT registry_source) AS distinct_registry_sources
FROM endpoints
WHERE status = 402
  AND payment_required_valid = 1
  AND on_chain_wallet IS NOT NULL
  AND on_chain_wallet != ''
GROUP BY on_chain_wallet
ORDER BY spec_valid_endpoints_under_wallet DESC
LIMIT 15;

-- ---- 6.5 — Schema validity refresh process (companion script) ----
-- The strict v2 validity flag is updated by:
--   src/sweep_validate_and_backfill.py (Phase 1)
-- The script re-fetches /.well-known/x402 (with fallback probe paths),
-- parses the JSON body, and asserts:
--   - body is a dict
--   - accepts[] is a non-empty array
--   - each accept item has: scheme, network, payTo, maxAmountRequired
-- Optional: x402Version field (does not affect validity, only loose-vs-strict tag).
-- Stale flag protection: sweep_all.py probe updates status only;
-- this script must run separately to refresh body validity.

-- ---- Limitations ----
-- (a) The validity check is body-shape only; it does not verify wallet
--     reachability or payment-tracker registration. An endpoint can be
--     spec-valid yet idle (zero on-chain payments tracked).
-- (b) Schema definition follows current public x402 specification draft
--     v2. Future spec revisions may broaden the required-fields set.
-- (c) Network errors at re-validation (37 in the 2026-05-19 sweep) leave
--     payment_required_valid unchanged, not forced to 0 — to avoid
--     misclassifying transient outage as permanent invalidity.
