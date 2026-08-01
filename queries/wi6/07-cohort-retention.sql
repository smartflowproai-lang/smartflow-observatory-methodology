-- ============================================================
-- SmartFlow Observatory - Weekly #6 methodology
-- 07: Cohort retention (do the new addresses come back)
-- ============================================================
-- Backs, from "How much does the x402 market actually weigh":
--   "the week holds 10,190 receiving addresses ... Of those, 8,747 had never
--    received a protocol payment before. In the three weeks that followed, 361 of
--    them, 4.1 percent, received another one; 95.9 percent have not appeared
--    again. Payers behave differently even like for like: of the 8,307 payers new
--    to the protocol that week, 1,282, 15.4 percent, paid again in the following
--    three weeks, nearly four times the recipient rate. Count the whole payer
--    cohort, returning regulars included, and 5,456 of 14,220, 38 percent, show
--    up again." (payer figures: 2026-08-01 live re-query; see 7.4 and 7.5)"
-- ============================================================
-- Universe: protocol filtered, clean (see files 00 and 02)
-- Cohort window:    ['2026-06-29', '2026-07-06')
-- "Before":         all ledger history prior to 2026-06-29
-- "Return window":  ['2026-07-06', '2026-07-27')  exactly three weeks
-- Number family: LIVE re-query of 2026-07-28, NOT the frozen rerun. This is why
--   the cohort is 10,190 here and 10,167 in files 02 and 04.
-- ============================================================
-- Run 00-universe-and-filters.sql first.
-- ============================================================


-- ---- 7.1 - Cohort of recipients ----
CREATE TEMP TABLE coh_to AS
SELECT DISTINCT to_wallet AS a
FROM payments
WHERE timestamp >= '2026-06-29' AND timestamp < '2026-07-06'
  AND (wash_flag IS NULL OR wash_flag = '')
  AND (is_facilitator_mediated = 1 OR to_wallet IN (SELECT w FROM cat));
SELECT COUNT(*) AS cohort_recipients FROM coh_to;   -- 10190


-- ---- 7.2 - Recipients seen before the window, and the new ones ----
CREATE TEMP TABLE seen_to AS
SELECT DISTINCT p.to_wallet AS a
FROM payments p
JOIN coh_to c ON c.a = p.to_wallet
WHERE p.timestamp < '2026-06-29'
  AND (p.wash_flag IS NULL OR p.wash_flag = '')
  AND (p.is_facilitator_mediated = 1 OR p.to_wallet IN (SELECT w FROM cat));
SELECT COUNT(*) AS recipients_seen_before FROM seen_to;   -- 1443

CREATE TEMP TABLE new_to AS
SELECT a FROM coh_to WHERE a NOT IN (SELECT a FROM seen_to);
SELECT COUNT(*) AS new_recipients FROM new_to;            -- 8747


-- ---- 7.3 - Who came back in the following three weeks ----
SELECT COUNT(DISTINCT n.a) AS new_recipients_returning
FROM new_to n
JOIN payments p ON p.to_wallet = n.a
WHERE p.timestamp >= '2026-07-06' AND p.timestamp < '2026-07-27'
  AND (p.wash_flag IS NULL OR p.wash_flag = '')
  AND (p.is_facilitator_mediated = 1 OR p.to_wallet IN (SELECT w FROM cat));
-- 361, i.e. 4.13 percent of 8,747. 95.9 percent did not appear again.

SELECT COUNT(DISTINCT s.a) AS returning_recipients_seen_before
FROM seen_to s
JOIN payments p ON p.to_wallet = s.a
WHERE p.timestamp >= '2026-07-06' AND p.timestamp < '2026-07-27'
  AND (p.wash_flag IS NULL OR p.wash_flag = '')
  AND (p.is_facilitator_mediated = 1 OR p.to_wallet IN (SELECT w FROM cat));
-- 1383 of 1443 at the 2026-07-28 live re-query. This figure matures DOWNWARD as
-- wash flagging catches up: a 2026-07-31 re-run gives 1,021 of 1,441 (70.9%).
-- Read it as "established addresses persist far more than new ones", not as a
-- stable constant; see limitation L3 (maturity) and L9 (tx_sender backfill).


-- ---- 7.4 - The payer side, same construction on from_wallet ----
CREATE TEMP TABLE coh_from AS
SELECT DISTINCT from_wallet AS a
FROM payments
WHERE timestamp >= '2026-06-29' AND timestamp < '2026-07-06'
  AND (wash_flag IS NULL OR wash_flag = '')
  AND (is_facilitator_mediated = 1 OR to_wallet IN (SELECT w FROM cat));
SELECT COUNT(*) AS cohort_payers FROM coh_from;   -- 14223

SELECT COUNT(DISTINCT c.a) AS payers_seen_before
FROM coh_from c
JOIN payments p ON p.from_wallet = c.a
WHERE p.timestamp < '2026-06-29'
  AND (p.wash_flag IS NULL OR p.wash_flag = '')
  AND (p.is_facilitator_mediated = 1 OR p.to_wallet IN (SELECT w FROM cat));
-- 5917

SELECT COUNT(DISTINCT c.a) AS payers_returning
FROM coh_from c
JOIN payments p ON p.from_wallet = c.a
WHERE p.timestamp >= '2026-07-06' AND p.timestamp < '2026-07-27'
  AND (p.wash_flag IS NULL OR p.wash_flag = '')
  AND (p.is_facilitator_mediated = 1 OR p.to_wallet IN (SELECT w FROM cat));
-- 5459 of 14,223 at the 2026-07-28 re-query; 5,456 of 14,220 on 2026-08-01.


-- ---- 7.5 - Like-for-like: retention of NEW payers only ----
-- 7.3 measures NEW recipients; 7.4 measures the WHOLE payer cohort, returning
-- regulars included. Comparing those two across sides mixes populations, which
-- is the numerator/denominator trap file 03 performs a post-mortem on. The
-- published sentence uses THIS construction for the cross-side comparison:
-- new payers only, same window, same filters as 7.2/7.3.
CREATE TEMP TABLE seen_from AS
SELECT DISTINCT c.a
FROM coh_from c
JOIN payments p ON p.from_wallet = c.a
WHERE p.timestamp < '2026-06-29'
  AND (p.wash_flag IS NULL OR p.wash_flag = '')
  AND (p.is_facilitator_mediated = 1 OR p.to_wallet IN (SELECT w FROM cat));
SELECT COUNT(*) AS payers_seen_before FROM seen_from;   -- 5,913 (2026-08-01)

CREATE TEMP TABLE new_from AS
SELECT a FROM coh_from WHERE a NOT IN (SELECT a FROM seen_from);
SELECT COUNT(*) AS new_payers FROM new_from;            -- 8,307 (2026-08-01)

SELECT COUNT(DISTINCT n.a) AS new_payers_returning
FROM new_from n
JOIN payments p ON p.from_wallet = n.a
WHERE p.timestamp >= '2026-07-06' AND p.timestamp < '2026-07-27'
  AND (p.wash_flag IS NULL OR p.wash_flag = '')
  AND (p.is_facilitator_mediated = 1 OR p.to_wallet IN (SELECT w FROM cat));
-- 1,282 of 8,307, i.e. 15.4 percent (2026-08-01). Like-for-like against the
-- recipients' 4.1 percent this is a 3.7x gap, not the 9.4x a whole-cohort
-- comparison would suggest.

DROP TABLE IF EXISTS seen_from;
DROP TABLE IF EXISTS new_from;

DROP TABLE IF EXISTS coh_to;
DROP TABLE IF EXISTS seen_to;
DROP TABLE IF EXISTS new_to;
DROP TABLE IF EXISTS coh_from;


-- ============================================================
-- Three ways this query could be wrong:
-- ============================================================
-- 1. The return window is younger than our own maturity rule allows. Late wash
--    flagging can only remove rows from it, so it can only reduce the 361. The
--    4.1 percent is therefore a ceiling, and we say so in the published text. If
--    you rerun this file after the window matures, expect a lower number, and that
--    lower number is the better one.
--
-- 2. "Came back" means the same ADDRESS received another protocol payment. A
--    service that rotates its receiving address per period looks like churn here
--    even if the same business is being paid every week. The measurement is address
--    persistence; it is not customer retention, and it is a weaker claim.
--
-- 3. (population match) 7.3 and 7.5 compare NEW-to-NEW; quoting 7.3 against
--    7.4 compares a new-only numerator population with a whole-cohort one. Any
--    reuse of these figures must keep the populations aligned, or it recreates
--    the exact error documented in file 03.
--
-- 4. The payer side is defined by protocol payments only, so a wallet that keeps
--    paying but stops paying catalogued or facilitator-settled endpoints counts as
--    churned. Both retention numbers inherit every coverage gap of the protocol
--    filter, and the gaps do not have to be symmetric between the two sides.
-- ============================================================
