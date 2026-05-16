-- ============================================================
-- SmartFlow Observatory — Methodology Query 05
-- Weekly Transaction Growth + Anthropic 15.06 Trigger Hypothesis Falsifiability
-- ============================================================
-- Source DB: payments.db
-- Atlas Reference: Finding 6, Atlas Part VI — "Weekly tx growth compounded ~29× then plateaued"
-- Drill-Down: drill-downs/06-weekly-growth-trigger/report.md
-- ============================================================
-- Expected output (Atlas Mid-2026 baseline, clean cohort):
--   Week 14 (2026-W14): 88,735 tx
--   Week 15 (2026-W15): ~342,000 tx
--   Week 16 (2026-W16): ~970,000 tx
--   Week 17 (2026-W17): ~1,860,000 tx
--   Week 18 (2026-W18): 3,041,346 tx (peak)
--   Week 19 (2026-W19): 2,585,726 tx (-15% from peak — plateau or fatigue?)
--   Linear regression slope: ~+12,000 clean tx / day (Q1 trend)
-- ============================================================
-- Anthropic 15.06 hypothesis: the 15 June 2026 Anthropic pricing change is a candidate
-- trigger for the week-18 spike. Falsifiability: if Q2 week-by-week growth diverges
-- materially from the Q1 linear-trend projection (slope ≈ +12K tx/day), the hypothesis
-- has explanatory power. If Q2 reverts to baseline trend, hypothesis is refuted.
-- ============================================================
-- Last verified: 2026-05-16 (Stage 3 Curator re-query)
-- ============================================================

-- ---- 5.1 — Weekly clean transaction counts ----
SELECT
  strftime('%Y-W%W', block_timestamp, 'unixepoch') AS year_week,
  MIN(date(block_timestamp, 'unixepoch')) AS week_start_date,
  COUNT(*) AS clean_tx_count,
  SUM(amount_usdc) AS clean_volume_usdc,
  COUNT(DISTINCT payer_wallet) AS distinct_payers,
  COUNT(DISTINCT recipient_wallet) AS distinct_recipients
FROM payments
WHERE wash_flag IS NULL
GROUP BY year_week
ORDER BY year_week;

-- ---- 5.2 — Daily clean transaction counts (May 2026 — the post-week-18 plateau window) ----
SELECT
  date(block_timestamp, 'unixepoch') AS observation_date,
  COUNT(*) AS daily_tx_count,
  SUM(amount_usdc) AS daily_volume_usdc
FROM payments
WHERE wash_flag IS NULL
  AND date(block_timestamp, 'unixepoch') >= '2026-04-30'
GROUP BY observation_date
ORDER BY observation_date;

-- ---- 5.3 — Linear regression slope (Q1 trend, May 2026 daily counts) ----
-- Compute mean(x), mean(y), slope = cov(x,y)/var(x)
-- This is a simple linear regression suitable for daily-count series
WITH daily_data AS (
  SELECT
    julianday(date(block_timestamp, 'unixepoch')) AS x,
    COUNT(*) AS y
  FROM payments
  WHERE wash_flag IS NULL
    AND date(block_timestamp, 'unixepoch') BETWEEN '2026-05-01' AND '2026-05-15'
  GROUP BY x
),
stats AS (
  SELECT
    AVG(x) AS mean_x,
    AVG(y) AS mean_y,
    COUNT(*) AS n
  FROM daily_data
)
SELECT
  SUM((d.x - s.mean_x) * (d.y - s.mean_y)) / SUM((d.x - s.mean_x) * (d.x - s.mean_x)) AS slope_tx_per_day,
  s.mean_y AS mean_daily_count,
  s.n AS days_observed
FROM daily_data d, stats s
GROUP BY s.mean_y, s.n;

-- ---- 5.4 — Pre-15-June baseline projection (for Q2 falsifiability test) ----
-- If slope = +12,000 tx/day, the projected daily count on 2026-06-15 is:
--   2026-05-15 baseline + (slope × days_elapsed)
-- Drill-down #6 §4 documents the exact falsifiability threshold.
SELECT
  (SELECT COUNT(*) FROM payments WHERE wash_flag IS NULL AND date(block_timestamp, 'unixepoch') = '2026-05-15') AS baseline_2026_05_15,
  julianday('2026-06-15') - julianday('2026-05-15') AS days_to_target,
  12000 * (julianday('2026-06-15') - julianday('2026-05-15')) AS projected_drift_at_slope_12k;

-- ============================================================
-- Three ways this query could be wrong:
-- ============================================================
-- 1. ISO-week boundaries differ between SQLite (%W = Sunday-first) and some other locales
--    (%V = Monday-first ISO 8601). Cross-check week boundary if comparing to externally
--    aggregated week-counts. The Atlas uses %W.
--
-- 2. Daily clean-count drift since 2026-05-16 wash-classifier update would shift the linear
--    regression slope. Re-running this query post-update will produce a different slope
--    than the Atlas baseline (~+12K tx/day). The drill-down (drill-downs/06-weekly-growth-trigger/)
--    documents the slope at the Atlas baseline snapshot; live drift is expected.
--
-- 3. The Anthropic 15.06 trigger hypothesis assumes a single calendar-aligned shock would
--    appear as a discrete spike in daily counts in a 0-3-day window around 2026-06-15.
--    Confounders include: (a) Base mainnet activity surges unrelated to x402,
--    (b) other agent-SDK pricing changes on the same date, (c) seasonal patterns.
--    The drill-down §4.3 enumerates the confounders.
-- ============================================================
