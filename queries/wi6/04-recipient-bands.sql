-- ============================================================
-- SmartFlow Observatory - Weekly #6 methodology
-- 04: Who is actually earning (recipient revenue bands)
-- ============================================================
-- Backs, from "How much does the x402 market actually weigh":
--   "Five receiving addresses took in $1,000 or more that week, collecting
--    $14,063.97 between them, 51 percent of everything. Another 19 took in
--    between $100 and $1,000, for $5,406.07. A further 133 took in between $10
--    and $100. That is 157 addresses holding 82 percent of the money. Everyone
--    else, 10,010 addresses, shared $4,914.54, 49 cents each for the week."
-- ============================================================
-- Universe: protocol filtered, clean, mature week (see files 00 and 02)
-- Cutoff:   window ['2026-06-29', '2026-07-06') on ingest clock
-- Number family: FROZEN rerun of 2026-07-27T18:25Z
-- ============================================================
-- Run 00-universe-and-filters.sql first.
-- ============================================================


-- ---- 4.1 - Bands, addresses, money, share ----
WITH recipient AS (
  SELECT
    to_wallet,
    COUNT(*)          AS calls,
    SUM(amount_usdc)  AS vol
  FROM payments
  WHERE timestamp >= '2026-06-29' AND timestamp < '2026-07-06'
    AND (wash_flag IS NULL OR wash_flag = '')
    AND (is_facilitator_mediated = 1 OR to_wallet IN (SELECT w FROM cat))
  GROUP BY to_wallet
),
total AS (SELECT SUM(vol) AS all_vol FROM recipient)
SELECT
  CASE
    WHEN vol >= 1000 THEN '1: >= $1,000'
    WHEN vol >= 100  THEN '2: $100 to $1,000'
    WHEN vol >= 10   THEN '3: $10 to $100'
    ELSE                  '4: < $10'
  END                                              AS band,
  COUNT(*)                                         AS addresses,
  ROUND(SUM(vol), 2)                               AS volume_usdc,
  ROUND(100.0 * SUM(vol) / (SELECT all_vol FROM total), 2) AS pct_of_volume,
  ROUND(SUM(vol) / COUNT(*), 2)                    AS mean_per_address
FROM recipient
GROUP BY band
ORDER BY band;
-- Published (rerun 2026-07-27), against a $27,570.90 total:
--   1: >= $1,000          5 addresses    $14,063.97    51.01%
--   2: $100 to $1,000    19 addresses     $5,406.07    19.61%
--   3: $10 to $100      133 addresses     $3,186.32    11.56%
--   4: < $10         10,010 addresses     $4,914.54    17.82%   ($0.49 each)
-- Bands 1 to 3: 157 addresses, $22,656.36, 82.18 percent.
-- Bands 1 to 2:  24 addresses, "the field at the top is 24 addresses wide".


-- ---- 4.2 - The concentration line on its own ----
-- The one number most likely to be quoted out of this piece, isolated so it can be
-- checked without reading the band table.
WITH recipient AS (
  SELECT to_wallet, SUM(amount_usdc) AS vol
  FROM payments
  WHERE timestamp >= '2026-06-29' AND timestamp < '2026-07-06'
    AND (wash_flag IS NULL OR wash_flag = '')
    AND (is_facilitator_mediated = 1 OR to_wallet IN (SELECT w FROM cat))
  GROUP BY to_wallet
)
SELECT
  SUM(CASE WHEN vol >= 10 THEN 1 ELSE 0 END)                       AS addresses_over_10,
  ROUND(100.0 * SUM(CASE WHEN vol >= 10 THEN vol ELSE 0 END)
              / SUM(vol), 2)                                        AS pct_of_volume,
  COUNT(*)                                                          AS all_recipients
FROM recipient;
-- Published: 157 | 82.18 | 10167


-- ============================================================
-- Three ways this query could be wrong:
-- ============================================================
-- 1. The bands are drawn on addresses, and the concentration claim is a claim
--    about addresses only. If the five top addresses belong to one operator, the
--    market is more concentrated than stated; if the 10,010 small addresses belong
--    to a handful of operators running wallet-per-user, it is less fragmented than
--    stated. We have confirmed at least one address fronting tens of thousands of
--    catalogue URLs, so both directions are live. Address is not entity.
--
-- 2. The revenue attributed to an address is revenue inside our amount band. A
--    service whose typical charge is above $5 shows up here as a small earner or
--    not at all. The bands describe micro-payment revenue, not service revenue.
--
-- 3. Because tx_hash is the primary key, a recipient settled through multi-leg
--    transactions is undercounted relative to one settled leg by leg, and the
--    ranking between them is not like for like. See docs/wi6-limitations.md, L1.
-- ============================================================
