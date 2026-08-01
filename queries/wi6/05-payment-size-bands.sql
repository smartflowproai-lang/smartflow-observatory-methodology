-- ============================================================
-- SmartFlow Observatory - Weekly #6 methodology
-- 05: Payment size distribution (calls versus value)
-- ============================================================
-- Backs, from "How much does the x402 market actually weigh":
--   "Payments under 5 cents are 69.1 percent of all calls and 1.8 percent of all
--    value. Payments at or above $1 are 12.1 percent of calls and 83.8 percent of
--    value. Together the two smallest bands carry 87.9 percent of the calls and
--    16.2 percent of the money."
-- ============================================================
-- Universe: protocol filtered, clean, mature week (see files 00 and 02)
-- Cutoff:   window ['2026-06-29', '2026-07-06') on ingest clock
-- Number family: FROZEN rerun of 2026-07-27T18:25Z
-- ============================================================
-- Run 00-universe-and-filters.sql first.
-- ============================================================


-- ---- 5.1 - Three size bands over the protocol population ----
SELECT
  CASE
    WHEN amount_usdc <  0.05 THEN '1: < $0.05'
    WHEN amount_usdc <  1.00 THEN '2: $0.05 to $1'
    ELSE                          '3: >= $1'
  END                                        AS size_band,
  COUNT(*)                                   AS calls,
  ROUND(SUM(amount_usdc), 2)                 AS volume_usdc,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)              AS pct_of_calls,
  ROUND(100.0 * SUM(amount_usdc) / SUM(SUM(amount_usdc)) OVER (), 1) AS pct_of_value
FROM payments
WHERE timestamp >= '2026-06-29' AND timestamp < '2026-07-06'
  AND (wash_flag IS NULL OR wash_flag = '')
  AND (is_facilitator_mediated = 1 OR to_wallet IN (SELECT w FROM cat))
GROUP BY size_band
ORDER BY size_band;
-- Published (rerun 2026-07-27), against 86,895 calls and $27,570.90:
--   1: < $0.05        60,071 calls    $496.83      69.1% of calls    1.8% of value
--   2: $0.05 to $1    16,338 calls  $3,965.24      18.8% of calls   14.4% of value
--   3: >= $1          10,486 calls $23,108.83      12.1% of calls   83.8% of value
-- Bands 1 and 2 together: 76,409 calls (87.9%) and $4,462.07 (16.2%).
--
-- Note on the SQL: the window function form (SUM(...) OVER ()) needs SQLite 3.25
-- or later. On an older engine, compute the two totals separately and divide.


-- ---- 5.2 - The same split without window functions ----
-- Same output, portable, and easier to paste into a client that chokes on OVER ().
SELECT
  SUM(CASE WHEN amount_usdc <  0.05 THEN 1 ELSE 0 END)            AS calls_under_5c,
  SUM(CASE WHEN amount_usdc >= 1.00 THEN 1 ELSE 0 END)            AS calls_over_1,
  COUNT(*)                                                         AS calls_total,
  ROUND(SUM(CASE WHEN amount_usdc <  0.05 THEN amount_usdc ELSE 0 END), 2) AS vol_under_5c,
  ROUND(SUM(CASE WHEN amount_usdc >= 1.00 THEN amount_usdc ELSE 0 END), 2) AS vol_over_1,
  ROUND(SUM(amount_usdc), 2)                                       AS vol_total
FROM payments
WHERE timestamp >= '2026-06-29' AND timestamp < '2026-07-06'
  AND (wash_flag IS NULL OR wash_flag = '')
  AND (is_facilitator_mediated = 1 OR to_wallet IN (SELECT w FROM cat));
-- Published: 60071 | 10486 | 86895 | 496.83 | 23108.83 | 27570.90


-- ============================================================
-- Three ways this query could be wrong:
-- ============================================================
-- 1. The top band is capped by the ingest band at $5, so "payments at or above $1"
--    means "between $1 and $5". The real tail above $5 is invisible here, and it is
--    exactly where a serious paid API would sit. The 83.8 percent of value is
--    83.8 percent of a truncated distribution.
--
-- 2. The bands are cut at round numbers chosen after seeing the data. They are
--    descriptive, not tested against an alternative cut. A reader who cuts at
--    1 cent and 50 cents will get a different, equally true, story. The claim that
--    survives any cut is the barbell shape, not the specific percentages.
--
-- 3. Multi-leg transactions are stored as one row carrying one leg's amount, so a
--    payment split across legs is binned by a fragment of its true size. That pushes
--    mass toward the small bands. Direction of the bias is known, magnitude is not.
-- ============================================================
