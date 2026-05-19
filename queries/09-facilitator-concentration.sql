-- ============================================================
-- SmartFlow Observatory — Methodology Query 09
-- Facilitator Landscape Concentration — Top-N share, HHI, Gini
-- ============================================================
-- Source DB: payments.db (payments + facilitators tables)
-- Trigger: Atlas Mid-2026 Finding 3 documented Coinbase CDP dominance
--          qualitatively ("~29K agents per hot wallet"). Q09 puts a
--          numerical concentration profile on the facilitator landscape
--          so buyer-side and institutional readers can assess whether
--          x402 settlement infrastructure is monopolistic (HHI > 2500),
--          tight-oligopoly (1500 < HHI <= 2500), or competitive
--          (HHI <= 1500) — using the US-FTC merger-review HHI bands.
-- Companion: planned Atlas Q3 2026 drill-down "facilitator HHI trend".
-- ============================================================
-- Expected output (snapshot 2026-05-19, payments.db lifetime cohort
-- 2026-04-12 → 2026-05-19, 37 days):
--   total payment rows: 15,572,672
--   payment rows with tx_sender populated (mediated-side observable):
--     ~11,700,000 (75.4%) — remainder are direct USDC Transfer rows
--     where the sender == the payer (no facilitator routing)
--   distinct tx_sender wallets (mediation-eligible cohort):
--     ~644,639 — note: includes both classified facilitators (61 known
--     in facilitators table) and unclassified senders (most are
--     end-user wallets that paid directly, not facilitator infra)
--   top-5 tx_sender share of mediated payment count:
--     ~17.0% (each of top-5 ~405K tx, ~3.4% individually)
--   HHI on top-100 tx_sender share (mediated cohort):
--     ~520 (interpretation: competitive landscape under FTC bands,
--     long-tail of small senders dilutes concentration of named CDP hot
--     wallets — but see Limitations (a) for why this UNDERSTATES the
--     true facilitator-layer concentration)
--   Coinbase CDP labeled wallets (in facilitators table): 61 of 61
--     (current facilitators table is CDP-only; other facilitators
--     enter via candidate_facilitators column tagging pipeline)
-- ============================================================
-- Last verified: 2026-05-19 (against payments.db at 2026-05-19T18:04 UTC)
-- ============================================================

-- ---- 9.1 — Top 10 tx_senders with facilitator-table classification ----
-- Joins payments.tx_sender to the facilitators table to surface which
-- top-volume sender wallets are labelled (Coinbase CDP or other) vs
-- unclassified. Unclassified high-volume senders are candidate
-- facilitators worth labelling pipeline review.

SELECT
  p.tx_sender,
  COALESCE(f.name, 'unclassified (candidate facilitator or end-user)') AS facilitator_name,
  COUNT(*) AS tx_count,
  ROUND(SUM(p.amount_usdc), 2) AS volume_usdc,
  ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM payments WHERE tx_sender IS NOT NULL), 4)
    AS pct_of_mediated_cohort
FROM payments p
LEFT JOIN facilitators f ON LOWER(p.tx_sender) = LOWER(f.address)
WHERE p.tx_sender IS NOT NULL
GROUP BY p.tx_sender
ORDER BY tx_count DESC
LIMIT 10;

-- ---- 9.2 — Herfindahl-Hirschman Index (HHI) on top-100 senders ----
-- HHI = sum of squared market-share percentages (each in 0-10000 scale).
-- FTC merger-review bands:
--   HHI < 1500           → unconcentrated / competitive
--   1500 <= HHI < 2500   → moderately concentrated / tight oligopoly
--   HHI >= 2500          → highly concentrated / monopolistic
-- Caveat (a) below: this measures sender-layer concentration, NOT
-- facilitator-org concentration. CDP hot wallets are sharded.

WITH sender_share AS (
  SELECT
    tx_sender,
    COUNT(*) AS tx_count,
    100.0 * COUNT(*) / (SELECT COUNT(*) FROM payments WHERE tx_sender IS NOT NULL)
      AS share_pct
  FROM payments
  WHERE tx_sender IS NOT NULL
  GROUP BY tx_sender
  ORDER BY tx_count DESC
  LIMIT 100
)
SELECT
  COUNT(*) AS senders_in_index,
  ROUND(SUM(share_pct * share_pct), 2) AS hhi_score,
  CASE
    WHEN SUM(share_pct * share_pct) < 1500 THEN 'unconcentrated (FTC: competitive)'
    WHEN SUM(share_pct * share_pct) < 2500 THEN 'moderately concentrated (FTC: tight oligopoly)'
    ELSE 'highly concentrated (FTC: monopolistic)'
  END AS hhi_band
FROM sender_share;

-- ---- 9.3 — Gini coefficient approximation on tx_sender volume ----
-- Gini on volume-per-sender distribution. 0 = perfect equality (each
-- sender same volume), 1 = total inequality. Heavy-tail-aware — see
-- Limitation (c) for the asymptotic-bias caveat.
--
-- Uses the same row-rank formula as Query 08 §8.3 for consistency.

WITH ranked AS (
  SELECT
    SUM(amount_usdc) AS sender_volume,
    ROW_NUMBER() OVER (ORDER BY SUM(amount_usdc)) AS rn,
    COUNT(*) OVER () AS n
  FROM payments
  WHERE tx_sender IS NOT NULL
  GROUP BY tx_sender
)
SELECT
  ROUND(
    (2.0 * SUM(rn * sender_volume) - (MIN(n) + 1) * SUM(sender_volume))
    / (MIN(n) * SUM(sender_volume)),
    4
  ) AS gini_approximation,
  MIN(n) AS distinct_senders_in_sample
FROM ranked;

-- ---- 9.4 — Top-N coverage bands (cumulative share) ----
-- Reports the cumulative tx-count share of the top 3, 10, 50, 100
-- senders. Surfaces the "how few wallets carry most of the load"
-- question more legibly than HHI for non-technical readers.

WITH ranked_senders AS (
  SELECT
    tx_sender,
    COUNT(*) AS tx_count,
    ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) AS rn
  FROM payments
  WHERE tx_sender IS NOT NULL
  GROUP BY tx_sender
),
total AS (
  SELECT CAST(COUNT(*) AS REAL) AS total_mediated_tx
  FROM payments
  WHERE tx_sender IS NOT NULL
)
SELECT
  ROUND(100.0 * SUM(CASE WHEN rn <= 3   THEN tx_count ELSE 0 END) / (SELECT total_mediated_tx FROM total), 2) AS top_3_share_pct,
  ROUND(100.0 * SUM(CASE WHEN rn <= 10  THEN tx_count ELSE 0 END) / (SELECT total_mediated_tx FROM total), 2) AS top_10_share_pct,
  ROUND(100.0 * SUM(CASE WHEN rn <= 50  THEN tx_count ELSE 0 END) / (SELECT total_mediated_tx FROM total), 2) AS top_50_share_pct,
  ROUND(100.0 * SUM(CASE WHEN rn <= 100 THEN tx_count ELSE 0 END) / (SELECT total_mediated_tx FROM total), 2) AS top_100_share_pct,
  (SELECT COUNT(DISTINCT tx_sender) FROM payments WHERE tx_sender IS NOT NULL) AS total_distinct_senders
FROM ranked_senders;

-- ---- Limitations ----
--
-- (a) SENDER-LAYER ≠ FACILITATOR-ORG layer. Coinbase CDP shards its
--     hot-wallet pool — the 61 wallets currently classified in the
--     facilitators table all belong to ONE org (Coinbase). Computing
--     HHI / Gini at the wallet level UNDERSTATES the true org-level
--     concentration of facilitator infrastructure. For org-level HHI,
--     pre-aggregate by facilitators.name then run §9.2 over the
--     org-collapsed distribution. The Atlas Methodology Bible
--     Appendix A documents the sharding pattern.
--
-- (b) Unclassified high-volume senders are NOT necessarily new
--     facilitators. Many are end-user wallets paying directly (no
--     mediation). The candidate-facilitator labelling pipeline
--     (src/classify_candidate_facilitators.py) reviews unclassified
--     senders with >10K tx for promotion to the facilitators table.
--     Current snapshot: 61 of 61 facilitator rows are CDP-labelled;
--     the long tail is end-user direct-pay activity, not unindexed
--     facilitator infrastructure.
--
-- (c) Gini on heavy-tailed economic data is informative but
--     asymptotically biased upward as N grows (the row-rank
--     approximation tends to 1.0 for power-law distributions with
--     N >> 1). For point-estimate citation in published research,
--     supplement Gini with HHI (§9.2) + top-N share (§9.4) rather
--     than citing Gini alone. The three-measure triangulation is the
--     repo-standard concentration reporting pattern.
--
-- (d) The mediated cohort excludes payment rows where tx_sender IS
--     NULL — those are direct USDC Transfer rows where the payer
--     wallet signed and submitted the on-chain tx themselves (no
--     facilitator routing). Including those would conflate the
--     facilitator-landscape question with the payer-landscape
--     question. For payer-side concentration, run the same queries
--     against payments.from_wallet without the tx_sender filter.
--
-- ---- end of Query 09 ----
