-- ============================================================
-- SmartFlow Observatory - Weekly #6 methodology
-- 02: The protocol filtered weight, and the ratios against file 01
-- ============================================================
-- Backs, from "How much does the x402 market actually weigh":
--   "86,895 payments, $27,570.90, from 13,514 paying addresses to 10,167
--    receiving addresses"
--   "the volume is 63.3 times smaller, the payment count 18.3 times smaller,
--    the receiving addresses 21.4 times smaller"
--   "The average protocol payment is 32 cents"
-- ============================================================
-- Universe: payments.db (ingest-banded) joined to mapper.db catalogue
-- Cutoff:   window ['2026-06-29', '2026-07-06') on ingest clock
-- Filters:  clean AND protocol role (catalogue payTo OR facilitator marker)
-- ============================================================
-- Run 00-universe-and-filters.sql first (it creates TEMP TABLE cat).
-- ============================================================
-- Number family: published figures are the FROZEN rerun of 2026-07-27T18:25Z.
-- Live re-query 2026-07-28 returned 87,808 | 27,833.59 | 10,190 recipients |
-- 14,223 payers. The +913 rows are catalogue growth plus late wash flagging.
-- ============================================================


-- ---- 2.1 - The protocol weight ----
SELECT
  COUNT(*)                       AS payments,
  ROUND(SUM(amount_usdc), 2)     AS volume_usdc,
  COUNT(DISTINCT to_wallet)      AS receiving_addresses,
  COUNT(DISTINCT from_wallet)    AS paying_addresses,
  ROUND(SUM(amount_usdc) / COUNT(*), 4) AS mean_payment_usdc
FROM payments
WHERE timestamp >= '2026-06-29' AND timestamp < '2026-07-06'
  AND (wash_flag IS NULL OR wash_flag = '')
  AND (is_facilitator_mediated = 1 OR to_wallet IN (SELECT w FROM cat));
-- Published (rerun 2026-07-27): 86895 | 27570.90 | 10167 | 13514 | 0.3173
-- Live     (2026-07-28):        87808 | 27833.59 | 10190 | 14223


-- ---- 2.2 - Which side of the filter recovers what ----
-- Not published, but it is the first question a reader should ask: is the protocol
-- figure carried by the catalogue or by the marker? Run it before you cite 2.1.
SELECT
  SUM(CASE WHEN is_facilitator_mediated = 1
            AND to_wallet IN (SELECT w FROM cat) THEN 1 ELSE 0 END) AS both,
  SUM(CASE WHEN is_facilitator_mediated = 1
            AND to_wallet NOT IN (SELECT w FROM cat) THEN 1 ELSE 0 END) AS marker_only,
  SUM(CASE WHEN (is_facilitator_mediated IS NULL OR is_facilitator_mediated = 0)
            AND to_wallet IN (SELECT w FROM cat) THEN 1 ELSE 0 END) AS catalogue_only
FROM payments
WHERE timestamp >= '2026-06-29' AND timestamp < '2026-07-06'
  AND (wash_flag IS NULL OR wash_flag = '')
  AND (is_facilitator_mediated = 1 OR to_wallet IN (SELECT w FROM cat));
-- If one side dominates, the protocol figure inherits that side's blind spot.
-- Expected (2026-07-31 re-run): both = 39,507 | marker_only = 47,322 |
-- catalogue_only = 925 (of 87,754). One side DOES dominate: the facilitator
-- marker carries 98.9 percent of the protocol figure and the catalogue leg adds
-- about one percent on top of it. "Protocol weight" therefore inherits the
-- marker's blind spot almost entirely: it is, in practice, traffic attributable
-- to the known facilitator sender set, plus a thin catalogue margin. The
-- published text says this in one clause; this query is where the number lives.


-- ---- 2.3 - The three ratios (same unit on both sides) ----
-- Recomputed from the frozen rerun rather than re-queried, so that the numerator
-- and the denominator come from the same instant of the ledger.
SELECT
  ROUND(1745058.64 / 27570.90, 1) AS volume_ratio,      -- 63.3
  ROUND(1593614.0  / 86895.0,  1) AS count_ratio,       -- 18.3
  ROUND(217786.0   / 10167.0,  1) AS recipient_ratio;   -- 21.4
-- The recipient ratio divides recipients by recipients. Dividing the file 01
-- recipient count by the file 02 payer count would produce 16.1 and would be
-- comparing two different units. That mistake is the reason file 01 carries an
-- explicit column identity check.


-- ============================================================
-- Three ways this query could be wrong:
-- ============================================================
-- 1. The catalogue side is a moving target. `cat` is rebuilt from a live crawl on
--    every run, so this query returns MORE protocol payments as the catalogue
--    grows, against a fixed historical window. The published figure is therefore a
--    lower bound that gets less wrong over time, which is an unusual direction of
--    error and worth stating out loud. Anyone reproducing this on a later date
--    should expect to beat our number, not match it.
--
-- 2. The marker side is a 76 row lookup on tx_sender (file 00, section 0.5). A
--    settlement service we have not catalogued contributes nothing here, and its
--    traffic lands in the unmarked bucket measured in file 03. The filter is
--    therefore conservative in one direction only.
--
-- 3. to_wallet IN (SELECT w FROM cat) matches an address, not an operator. One
--    address serving thousands of unrelated endpoints will pull all of its traffic
--    into the protocol figure. We have hit exactly this: a single proxy wallet
--    fronting tens of thousands of catalogue URLs. Address is not entity, and no
--    query in this directory pretends otherwise.
-- ============================================================
