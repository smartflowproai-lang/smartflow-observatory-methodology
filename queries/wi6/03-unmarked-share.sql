-- ============================================================
-- SmartFlow Observatory - Weekly #6 methodology
-- 03: The unmarked share (the blind spot), and the autopsy of a withdrawn number
-- ============================================================
-- Backs, from "How much does the x402 market actually weigh":
--   "1,506,472 of the week's 1,593,355 unfiltered transfers, 94.5 percent,
--    carried no facilitator marker at all"
-- ============================================================
-- Universe: payments.db, ingest-banded
-- Cutoff:   window ['2026-06-29', '2026-07-06') on ingest clock
-- Filters:  clean, no protocol filter
-- Number family: BOTH numbers here are the live re-query of 2026-07-28. They are
--   internally consistent with each other and are never mixed with the frozen
--   2026-07-27 rerun inside one sentence.
-- ============================================================


-- ---- 3.1 - The published blind spot: 94.5 percent ----
SELECT
  SUM(CASE WHEN is_facilitator_mediated IS NULL
             OR is_facilitator_mediated = 0 THEN 1 ELSE 0 END) AS no_marker,
  COUNT(*)                                                     AS clean_rows,
  ROUND(100.0 * SUM(CASE WHEN is_facilitator_mediated IS NULL
                           OR is_facilitator_mediated = 0 THEN 1 ELSE 0 END)
              / COUNT(*), 1)                                   AS pct_no_marker
FROM payments
WHERE timestamp >= '2026-06-29' AND timestamp < '2026-07-06'
  AND (wash_flag IS NULL OR wash_flag = '');
-- Live 2026-07-28: 1506472 | 1593355 | 94.5


-- ---- 3.2 - Splitting the blind spot into its two halves ----
-- "No marker" is not one thing. = 0 means we resolved the sender and it was the
-- payer themselves. NULL means we could not resolve it, or the sender is a third
-- party absent from our 76 row table. Only the NULL half is genuinely unknown.
SELECT
  is_facilitator_mediated,
  COUNT(*) AS rows_
FROM payments
WHERE timestamp >= '2026-06-29' AND timestamp < '2026-07-06'
  AND (wash_flag IS NULL OR wash_flag = '')
GROUP BY is_facilitator_mediated;
-- Reported for the same window on 2026-07-28 without the wash filter:
--   marker = 0 only:            682,520
--   marker = 0 or NULL:       2,798,055
-- so NULL dominates the bucket by roughly three to one.


-- ============================================================
-- AUTOPSY: how 2,798,055 got into a draft, and why it is not in the published text
-- ============================================================
-- Draft v2 of this piece carried "2,798,055 of the transfers in that same window
-- carried no facilitator marker". The sentence was literally true and the number
-- reproduced to the unit. It was still wrong to publish, and the reason is worth
-- more than the number.
--
-- The lead figure (file 01) counts CLEAN rows: 1,593,614. The 2,798,055 counted
-- ALL rows in the same calendar window, wash included: a 4,800,294 row population.
-- "In that same window" was true of the window and false of the population, so the
-- draft was on course to report a subset as larger than its superset.

-- Q2a - the exact reproduction of the withdrawn figure (wash INCLUDED):
SELECT COUNT(*) AS withdrawn_2798055
FROM payments
WHERE timestamp >= '2026-06-29' AND timestamp < '2026-07-06'
  AND (is_facilitator_mediated IS NULL OR is_facilitator_mediated = 0);
-- 2026-07-28: 2798055 (unit-exact)

-- Q2c - the same predicate restricted to marker = 0, no NULL:
SELECT COUNT(*) AS marker_zero_only
FROM payments
WHERE timestamp >= '2026-06-29' AND timestamp < '2026-07-06'
  AND is_facilitator_mediated = 0;
-- 2026-07-28: 682520

-- The published replacement is 3.1: same predicate, same window, population
-- matched to the lead. 1,506,472 of 1,593,355, or 94.5 percent.
--
-- Side benefit of the autopsy: because this predicate does not depend on wash_flag
-- it does not drift, which is what pinned the rerun's window to the ingest clock
-- interval ['2026-06-29', '2026-07-06') in the first place.
--
-- The general rule we took from it, and now apply to every ratio we publish:
-- a numerator and a denominator must be filtered by the SAME criteria, and the
-- unit on both sides of a ratio must be the same unit (addresses vs addresses,
-- legs vs legs). A percentage whose two halves were built by different filters is
-- not a weak finding, it is not a finding.


-- ============================================================
-- Three ways this query could be wrong:
-- ============================================================
-- 1. The NULL half is unresolvable by construction, so 94.5 percent is a ceiling
--    on our ignorance and not a measurement of non-facilitator settlement. Some of
--    those rows are ordinary infrastructure traffic that was never an x402 payment
--    at all. We cannot tell you the split, which is the honest answer.
--
-- 2. tx_sender is written by a backfill that has had silent per-block RPC failures.
--    Rows whose sender was never resolved stay NULL forever unless rescanned, so
--    the NULL bucket carries an operational defect as well as a genuine unknown.
--    Estimated facilitator-mediated traffic missed for this reason is in the mid
--    teens as a percentage; it is not precisely known.
--
-- 3. The denominator is the clean banded universe, so the percentage moves when
--    the wash classifier revisits old rows. Reruns of this file on a later date
--    will not reproduce 94.5 exactly. Cite it with the date attached or not at all.
-- ============================================================
