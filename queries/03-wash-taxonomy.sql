-- ============================================================
-- SmartFlow Observatory — Methodology Query 03
-- Wash Activity Taxonomy R1-R4 — Cohort Sizes + Volume Impact
-- ============================================================
-- Source DB: payments.db
-- Atlas Reference: Finding 5, Atlas Part II — "Wash activity is structural, not anomalous"
-- Drill-Down: drill-downs/04-wash-taxonomy/report.md
-- ============================================================
-- Wash classifier definitions (see docs/wash-flag-definitions.md):
--   R1 — sub-cent microbilling (amount < $0.001)
--   R2 — burst (≥10 tx from same payer to same recipient within 1 second)
--   R3 — dust (amount > sub-cent but < $0.01 AND high-frequency)
--   R4 — loop (circular flow A → B → A within 60-second window)
-- ============================================================
-- Expected output (Atlas Mid-2026 baseline):
--   R3 (dust): 14.5% of total tx count / 0.03% of volume
--   R2 (burst): 6.7% of count / 5.7% of volume
--   R4 (loop): 6.7% of count / 12.2% of volume
--   Combined wash flag total: ~24% of raw tx count
--   ~22% volume overcount risk if model uses raw aggregates without filtering
-- ============================================================
-- Drift note: 2026-05-16 wash-classifier update reclassed ~32% of formerly clean tx as wash.
-- Cohort percentages may have drifted; absolute count + volume verified live at last update.
-- ============================================================
-- Last verified: 2026-05-16 (Stage 3 Curator re-query)
-- ============================================================

-- ---- 3.1 — Wash flag distribution: count + volume per rule ----
SELECT
  COALESCE(wash_flag, 'CLEAN') AS classification,
  COUNT(*) AS tx_count,
  ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM payments), 2) AS pct_of_raw_count,
  SUM(amount_usdc) AS volume_usdc,
  ROUND(100.0 * SUM(amount_usdc) / (SELECT SUM(amount_usdc) FROM payments), 4) AS pct_of_raw_volume
FROM payments
GROUP BY classification
ORDER BY tx_count DESC;

-- ---- 3.2 — R3 (dust) cohort sample — worked example ----
-- Show 10 random R3-flagged tx — for documentation of "what dust looks like"
SELECT
  block_number,
  tx_hash,
  payer_wallet,
  recipient_wallet,
  amount_usdc,
  block_timestamp
FROM payments
WHERE wash_flag = 'R3'
ORDER BY RANDOM()
LIMIT 10;

-- ---- 3.3 — R4 (loop) cohort — circular flow detection ----
-- Identify A→B→A patterns within 60-second window
SELECT
  COUNT(*) AS r4_tx_count,
  COUNT(DISTINCT payer_wallet) AS distinct_payers_in_loops,
  AVG(amount_usdc) AS avg_amount_usdc,
  MAX(amount_usdc) AS max_amount_usdc
FROM payments
WHERE wash_flag = 'R4';

-- ---- 3.4 — Clean cohort total (the wash-filtered baseline for all subsequent queries) ----
SELECT
  COUNT(*) AS clean_tx_count,
  SUM(amount_usdc) AS clean_volume_usdc,
  MIN(block_timestamp) AS earliest_clean_tx,
  MAX(block_timestamp) AS latest_clean_tx
FROM payments
WHERE wash_flag IS NULL;

-- ---- 3.5 — Volume overcount risk: raw vs clean ----
SELECT
  (SELECT SUM(amount_usdc) FROM payments) AS raw_total_volume,
  (SELECT SUM(amount_usdc) FROM payments WHERE wash_flag IS NULL) AS clean_total_volume,
  ROUND(
    100.0 * (
      (SELECT SUM(amount_usdc) FROM payments) -
      (SELECT SUM(amount_usdc) FROM payments WHERE wash_flag IS NULL)
    ) / (SELECT SUM(amount_usdc) FROM payments),
    2
  ) AS pct_overcount_if_no_filter;

-- ============================================================
-- Three ways this query could be wrong:
-- ============================================================
-- 1. R1-R4 thresholds are path-dependent. The Atlas uses $0.001 for R1, 1-second window
--    for R2, 60-second window for R4. Different thresholds would relocate transactions
--    between cohorts. The drill-down (drill-downs/04-wash-taxonomy/) documents the
--    sensitivity analysis; queries here use the canonical thresholds.
--
-- 2. R3 (dust) classification requires high-frequency component — the threshold is "10+
--    transactions from same payer-recipient pair within a 5-minute rolling window." If
--    your indexer does not maintain rolling-window counters per payer-recipient pair,
--    you cannot reproduce R3 directly. The Atlas Methodology Bible §A.6 documents the
--    rolling-window aggregation approach.
--
-- 3. The Atlas estimated >95% precision and <85% recall on the wash side as calibration
--    targets. These were NOT empirically validated against labelled ground truth (no
--    labelled ground truth exists for x402 wash classification at the population level).
--    The classifier is a working measurement instrument, not a settled science result.
-- ============================================================
