-- ============================================================
-- SmartFlow Observatory - Weekly #6 methodology
-- 01: The amount filtered baseline (the inflated figure in the lead)
-- ============================================================
-- Backs, from "How much does the x402 market actually weigh":
--   "1,593,614 payments, $1,745,058 moved, 217,786 receiving addresses"
--   "The average payment in the unfiltered pile is $1.10"
-- ============================================================
-- Universe: payments.db, ingest-banded 0.0005 to 5.0 USDC (see file 00, section 0.2)
-- Cutoff:   window ['2026-06-29', '2026-07-06') on ingest clock, UTC midnight aligned
-- Filters:  clean only. NO protocol filter. NO further amount filter.
-- ============================================================
-- Run 00-universe-and-filters.sql first.
-- ============================================================
-- Number family: this is the FROZEN rerun of 2026-07-27T18:25Z.
-- A live re-query on 2026-07-28 returned 1,593,355 | 1,744,616.29 | 217,741.
-- The two families are never mixed inside one sentence of the published text.
-- The drift is wash flagging applied retroactively. See file 03 and L3.
-- ============================================================


-- ---- 1.1 - The headline triple ----
SELECT
  COUNT(*)                          AS payments,
  ROUND(SUM(amount_usdc), 2)        AS volume_usdc,
  COUNT(DISTINCT to_wallet)         AS receiving_addresses,
  COUNT(DISTINCT from_wallet)       AS paying_addresses
FROM payments
WHERE timestamp >= '2026-06-29' AND timestamp < '2026-07-06'
  AND (wash_flag IS NULL OR wash_flag = '');
-- Published (rerun 2026-07-27): 1593614 | 1745058.64 | 217786 | (not published)
-- Live     (2026-07-28):        1593355 | 1744616.29 | 217741 | 211596


-- ---- 1.2 - Average payment in the unfiltered pile ----
SELECT ROUND(SUM(amount_usdc) / COUNT(*), 4) AS mean_payment_usdc
FROM payments
WHERE timestamp >= '2026-06-29' AND timestamp < '2026-07-06'
  AND (wash_flag IS NULL OR wash_flag = '');
-- Published: 1.10   (1745058.64 / 1593614)


-- ---- 1.3 - Column identity check (why "receiving addresses" and not "payers") ----
-- Draft v2 of this piece labelled 217,786 as paying addresses. It is not.
-- The two counts are ~6,000 apart, which is far outside a one-day drift, so the
-- assignment is decidable rather than assumed. Kept here as an audit step, since
-- a mislabelled unit is the cheapest way to break the ratios in file 02.
SELECT
  COUNT(DISTINCT to_wallet)   AS distinct_recipients,
  COUNT(DISTINCT from_wallet) AS distinct_payers
FROM payments
WHERE timestamp >= '2026-06-29' AND timestamp < '2026-07-06'
  AND (wash_flag IS NULL OR wash_flag = '');
-- Live 2026-07-28: 217741 | 211596
-- 217,786 in the frozen rerun matches the recipient column, not the payer column.


-- ============================================================
-- Three ways this query could be wrong:
-- ============================================================
-- 1. It is not actually an amount filter written by us. The band lives in the
--    indexer, so this file reproduces "somebody filtered a ledger by amount" only
--    for readers whose ledger carries the same band. Against a complete USDC log
--    the equivalent baseline needs an explicit
--        AND amount_usdc BETWEEN 0.0005 AND 5.0
--    and will still differ, because our band was applied at ingest and never
--    revisited after later reclassification.
--
-- 2. Wash exclusion is applied here. That is a choice in our favour: it makes the
--    inflated figure smaller and therefore makes the ratio in file 02 smaller than
--    a critic could have made it. Without the exclusion the same window holds
--    4,800,294 rows. If you want the maximally unflattering comparison, drop the
--    wash clause from this file and keep it in file 02, and say that you did.
--
-- 3. COUNT(DISTINCT to_wallet) counts addresses, not businesses. One operator can
--    hold thousands of addresses and one address can front many services. Nothing
--    in this file distinguishes a wallet from a customer, which is exactly the
--    failure mode the published piece accuses other market sizings of.
-- ============================================================
