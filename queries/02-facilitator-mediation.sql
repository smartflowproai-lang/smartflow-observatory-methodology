-- ============================================================
-- SmartFlow Observatory — Methodology Query 02
-- Facilitator-Mediation Tri-State Classifier + Volume vs Count Barbell
-- ============================================================
-- Source DB: payments.db
-- Atlas Reference: Finding 3, Atlas Part II — "Facilitator landscape"
-- Drill-Down: drill-downs/03-cdp-barbell/report.md
-- ============================================================
-- Observation window: 2026-04-12 → 2026-05-15 (33-day Q1 cohort)
-- Expected output (Atlas Mid-2026 baseline, pre wash-classifier-update of 2026-05-16):
--   CDP facilitator-mediated by count: 1,554,140 (45.4% of classified)
--   CDP facilitator-mediated by volume: $230,857 (2.35% of classified-clean volume)
--   Direct (non-mediated) by count: 1,862,886 (54.6%)
--   Unclassified (NULL): 2,186,436 (drill-down explains the impact of resolving this bucket)
-- ============================================================
-- Drift note: A wash-classifier update on 2026-05-16 reclassed ~32% of formerly clean
-- transactions as wash. Post-update mediation share is 11.9% by count / 4.8% by volume
-- against the all-classified denominator. See drill-down #3 §6 for full reconciliation.
-- ============================================================
-- Last verified: 2026-05-16 (Stage 3 Curator re-query, post wash-classifier-update)
-- ============================================================

-- ---- 2.1 — Tri-state mediation classifier counts ----
-- States: 1 = facilitator-mediated (EIP-3009), 0 = direct transfer, NULL = unclassified
SELECT
  is_facilitator_mediated,
  COUNT(*) AS tx_count,
  SUM(amount_usdc) AS volume_usdc,
  ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM payments WHERE wash_flag IS NULL), 2) AS pct_of_clean_count,
  ROUND(100.0 * SUM(amount_usdc) / (SELECT SUM(amount_usdc) FROM payments WHERE wash_flag IS NULL), 4) AS pct_of_clean_volume
FROM payments
WHERE wash_flag IS NULL
GROUP BY is_facilitator_mediated;

-- ---- 2.2 — CDP-only facilitator-mediation share (excluding 7 non-CDP clusters) ----
-- CDP identity: facilitator wallet IN (SELECT wallet FROM facilitators WHERE cluster = 'CDP')
SELECT
  COUNT(*) AS cdp_tx_count,
  SUM(amount_usdc) AS cdp_volume_usdc,
  ROUND(100.0 * COUNT(*) / (
    SELECT COUNT(*) FROM payments
    WHERE wash_flag IS NULL AND is_facilitator_mediated IS NOT NULL
  ), 2) AS cdp_pct_of_classified_count,
  ROUND(100.0 * SUM(amount_usdc) / (
    SELECT SUM(amount_usdc) FROM payments
    WHERE wash_flag IS NULL AND is_facilitator_mediated IS NOT NULL
  ), 4) AS cdp_pct_of_classified_volume
FROM payments
WHERE wash_flag IS NULL
  AND submitter_wallet IN (SELECT wallet FROM facilitators WHERE cluster = 'CDP');

-- ---- 2.3 — Amount distribution: facilitator-mediated vs direct (the barbell visualization) ----
-- Bin into log-bucket amount ranges to see the bimodal distribution
SELECT
  CASE
    WHEN amount_usdc < 0.01 THEN 'sub-cent'
    WHEN amount_usdc < 0.10 THEN '$0.01-$0.10'
    WHEN amount_usdc < 1.00 THEN '$0.10-$1'
    WHEN amount_usdc < 10.00 THEN '$1-$10'
    WHEN amount_usdc < 100.00 THEN '$10-$100'
    WHEN amount_usdc < 1000.00 THEN '$100-$1,000'
    ELSE '$1,000+'
  END AS amount_bucket,
  SUM(CASE WHEN is_facilitator_mediated = 1 THEN 1 ELSE 0 END) AS mediated_count,
  SUM(CASE WHEN is_facilitator_mediated = 0 THEN 1 ELSE 0 END) AS direct_count,
  SUM(CASE WHEN is_facilitator_mediated = 1 THEN amount_usdc ELSE 0 END) AS mediated_volume,
  SUM(CASE WHEN is_facilitator_mediated = 0 THEN amount_usdc ELSE 0 END) AS direct_volume
FROM payments
WHERE wash_flag IS NULL
GROUP BY amount_bucket
ORDER BY MIN(amount_usdc);

-- ---- 2.4 — Distinct CDP facilitator wallet count ----
SELECT COUNT(DISTINCT wallet) AS distinct_cdp_wallets
FROM facilitators
WHERE cluster = 'CDP';
-- Expected: 1,621 (Atlas Mid-2026 baseline)

-- ============================================================
-- Three ways this query could be wrong:
-- ============================================================
-- 1. The `facilitators` table is hand-curated + automated by wallet-fingerprint classifier.
--    A new CDP facilitator wallet that has not yet been added to the table would be
--    classified as is_facilitator_mediated = NULL (unclassified) rather than = 1 (CDP).
--    Coverage gap is estimated 2-5% per the Methodology Bible.
--
-- 2. is_facilitator_mediated relies on EIP-3009 signature parsing. If a CDP transaction
--    is submitted by an alternative submitter (e.g., a delegated submitter wallet) but
--    still carries the canonical EIP-3009 mediation pattern, it should be flagged as 1.
--    Edge cases where the classifier returns false-negative are documented in
--    schema/facilitator-classification.md.
--
-- 3. amount_usdc is parsed from transaction value × 1e-6 (USDC has 6 decimals). Edge cases
--    where the value field is malformed (e.g., reverted transactions, gas-only transactions)
--    may not appear in payments.db at all — the Indexer filters these out at ingestion.
-- ============================================================
