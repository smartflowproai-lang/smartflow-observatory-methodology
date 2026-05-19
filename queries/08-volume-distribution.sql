-- ============================================================
-- SmartFlow Observatory — Methodology Query 08
-- On-Chain Volume Distribution — endpoint cohort by volume band
-- ============================================================
-- Source DBs: mapper.db (endpoints + on_chain_volume_usdc populated 2026-05-19)
-- Trigger: post-Query 07 backfill, mapper.db has accurate lifetime USDC
--          volume per endpoint. Query 08 segments this into bands for
--          buyer-agent decision support (which endpoints carry real
--          settlement signal vs catalogued-but-dormant).
-- Companion: mapper-mcp v0.3.0 `list_endpoints({volume_gt: X})` filter
-- ============================================================
-- Expected output (snapshot 2026-05-19):
--   total endpoints catalogued: 58,822
--   endpoints with on_chain_volume_usdc > 0: 11,365 (19.3% of catalogue)
--   endpoints with volume > $1: ~5,500 (estimated)
--   endpoints with volume > $10: ~800 (estimated)
--   endpoints with volume > $100: ~50 (estimated)
--   90th percentile volume: ~$4 USDC
--   99th percentile volume: ~$80 USDC
--   max single-endpoint volume: $160.02 USDC
-- ============================================================
-- Last verified: 2026-05-19 (Phase 2 backfill complete via Query 07)
-- ============================================================

-- ---- 8.1 — Volume band counts ----
-- Segments endpoints into bands so buyer agents can decide which
-- "minimum credible activity" floor to set on list_endpoints calls.

SELECT
  CASE
    WHEN on_chain_volume_usdc = 0 OR on_chain_volume_usdc IS NULL THEN '00. zero volume'
    WHEN on_chain_volume_usdc > 0    AND on_chain_volume_usdc <  1 THEN '01. > $0,    < $1'
    WHEN on_chain_volume_usdc >= 1   AND on_chain_volume_usdc <  10 THEN '02. $1-10'
    WHEN on_chain_volume_usdc >= 10  AND on_chain_volume_usdc <  100 THEN '03. $10-100'
    WHEN on_chain_volume_usdc >= 100 AND on_chain_volume_usdc <  1000 THEN '04. $100-1000'
    ELSE                                                                 '05. >= $1000'
  END AS volume_band,
  COUNT(*) AS endpoint_count,
  ROUND(SUM(on_chain_volume_usdc), 2) AS band_total_usdc,
  ROUND(AVG(on_chain_volume_usdc), 4) AS band_avg_usdc
FROM endpoints
GROUP BY volume_band
ORDER BY volume_band;

-- ---- 8.2 — Percentile cuts (selectivity discipline for filter callers) ----
-- The buyer-side question: "what volume floor leaves me with N quality
-- endpoints?" These percentile cuts let the buyer reason about the
-- selectivity / sample-size tradeoff before setting volume_gt.

WITH nonzero AS (
  SELECT on_chain_volume_usdc
  FROM endpoints
  WHERE on_chain_volume_usdc > 0
  ORDER BY on_chain_volume_usdc
)
SELECT
  COUNT(*) AS nonzero_count,
  -- Note: SQLite has no native PERCENTILE_CONT; this is approximate
  -- via row-position. For production-grade percentile use Python/pandas.
  (SELECT on_chain_volume_usdc FROM nonzero
    LIMIT 1 OFFSET CAST(COUNT(*) * 0.50 AS INTEGER) - 1) AS p50_volume,
  (SELECT on_chain_volume_usdc FROM nonzero
    LIMIT 1 OFFSET CAST(COUNT(*) * 0.75 AS INTEGER) - 1) AS p75_volume,
  (SELECT on_chain_volume_usdc FROM nonzero
    LIMIT 1 OFFSET CAST(COUNT(*) * 0.90 AS INTEGER) - 1) AS p90_volume,
  (SELECT on_chain_volume_usdc FROM nonzero
    LIMIT 1 OFFSET CAST(COUNT(*) * 0.99 AS INTEGER) - 1) AS p99_volume,
  MAX(on_chain_volume_usdc) AS p100_volume
FROM endpoints
WHERE on_chain_volume_usdc > 0;

-- ---- 8.3 — Volume Gini coefficient approximation ----
-- Measure of concentration: 0 = perfect equality (each endpoint same
-- volume), 1 = total inequality (one endpoint, rest zero). Useful
-- signal of catalogue health — if Gini > 0.95, one or two endpoints
-- dominate lifetime volume and the buyer-side filter floors should
-- be set conservatively.

WITH ranked AS (
  SELECT
    on_chain_volume_usdc,
    ROW_NUMBER() OVER (ORDER BY on_chain_volume_usdc) AS rn,
    COUNT(*) OVER () AS n
  FROM endpoints
  WHERE on_chain_volume_usdc > 0
)
SELECT
  -- Gini ~ (2 * sum(rank * volume) - (n+1) * sum(volume)) / (n * sum(volume))
  ROUND(
    (2.0 * SUM(rn * on_chain_volume_usdc) - (MIN(n) + 1) * SUM(on_chain_volume_usdc))
    / (MIN(n) * SUM(on_chain_volume_usdc)),
    4
  ) AS gini_approximation,
  MIN(n) AS sample_n
FROM ranked;

-- ---- 8.4 — Top 25 endpoints by volume (cohort head for buyer-side lookups) ----
SELECT
  url,
  chain,
  on_chain_volume_usdc AS lifetime_volume_usdc,
  status AS last_probe_status,
  spec_valid,
  last_seen
FROM endpoints
WHERE on_chain_volume_usdc > 0
ORDER BY on_chain_volume_usdc DESC
LIMIT 25;

-- ---- 8.5 — Limitations ----
--
-- 1. "Lifetime" volume horizon: payments.db ingestion start = 2026-04
--    (per pmt schema first_payment column). Volume figures are floor-
--    bounded by that start window; pre-April activity is invisible.
--
-- 2. Wallet-share artifacts: 9 endpoints share the max-volume wallet
--    0x44dc...7c2c (see Query 07 §7.2). Per-wallet aggregation is more
--    economically meaningful than per-endpoint for those endpoints,
--    because the volume settled to a shared operator address rather
--    than to nine independent operators.
--
-- 3. Bands are arbitrary log-scale cuts. They serve buyer-agent
--    decision support, not statistical inference. For inference,
--    use Query 07 § percentile cells + appropriate non-parametric
--    test (KS / Mann-Whitney depending on hypothesis).
--
-- 4. Gini coefficient on heavy-tailed economic data is informative
--    but not robust; if catalogue grows substantially, re-validate
--    against alternative concentration measure (HHI, top-10 share)
--    before citing in published reports.
--
-- ---- end of Query 08 ----
