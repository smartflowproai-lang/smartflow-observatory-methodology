-- ============================================================
-- SmartFlow Observatory — Methodology Query 07
-- On-Chain Volume Backfill — Endpoint ↔ Payment Tracker Join
-- ============================================================
-- Source DBs: mapper.db (endpoints + on_chain_wallet)
--             payments.db (payments table, ATTACHED)
-- Trigger: mapper.db.endpoints.on_chain_volume_usdc was stored as 0.0
--          on every row. The 2026-05-19 backfill populated lifetime
--          USDC volume per endpoint by joining mapper.on_chain_wallet
--          to payments.to_wallet (case-insensitive).
-- Companion script: src/sweep_validate_and_backfill.py (Phase 2)
-- ============================================================
-- Expected output (post 2026-05-19 backfill):
--   distinct on_chain_wallet values in mapper.db: 101
--   endpoint rows with on_chain_volume_usdc > 0: 11,365
--   total cumulative volume (lifetime): $7,190.62 USDC
--   median volume per endpoint: $0.63
--   max single-endpoint volume: $160.02
--                              (0x44dc...7c2c, 9 endpoints share)
-- ============================================================
-- Last verified: 2026-05-19 11:18:18 UTC (Phase 2 backfill complete)
-- ============================================================

-- ---- 7.1 — Backfill query (volume per distinct recipient wallet) ----
-- This is the JOIN that the Phase 2 backfill executes once per wallet.
-- Run it standalone to validate the volume figures against current
-- payments.db state.
ATTACH DATABASE '/root/x402-payment-tracker/payments.db' AS pmt;

SELECT
  m.on_chain_wallet,
  COUNT(DISTINCT m.id) AS endpoints_under_wallet,
  ROUND(COALESCE(SUM(p.amount_usdc), 0.0), 2) AS lifetime_volume_usdc,
  COUNT(p.tx_hash) AS payment_event_count,
  MIN(p.timestamp) AS first_payment,
  MAX(p.timestamp) AS last_payment
FROM endpoints m
LEFT JOIN pmt.payments p ON LOWER(m.on_chain_wallet) = LOWER(p.to_wallet)
WHERE m.on_chain_wallet IS NOT NULL
  AND m.on_chain_wallet != ''
GROUP BY m.on_chain_wallet
ORDER BY lifetime_volume_usdc DESC
LIMIT 25;

-- ---- 7.2 — Aggregate volume snapshot ----
SELECT
  COUNT(*) AS endpoints_with_volume,
  ROUND(SUM(on_chain_volume_usdc), 2) AS total_lifetime_volume_usdc,
  ROUND(AVG(on_chain_volume_usdc), 4) AS avg_volume_per_endpoint,
  ROUND(MAX(on_chain_volume_usdc), 2) AS max_single_endpoint_volume
FROM endpoints
WHERE on_chain_volume_usdc > 0;

-- ---- 7.3 — Coverage ratio: mapper recipient set vs payment-tracker recipient set ----
-- Mapper.db catches recipient wallets that endpoints declare in their
-- /.well-known/x402 manifest. payments.db catches all on-chain
-- USDC recipients (including facilitator-mediated routing).
-- The two recipient sets are NOT substitutes — different layers.
SELECT
  (SELECT COUNT(DISTINCT on_chain_wallet) FROM endpoints
   WHERE on_chain_wallet IS NOT NULL AND on_chain_wallet != '') AS mapper_recipient_wallet_count,
  (SELECT COUNT(DISTINCT to_wallet) FROM pmt.payments) AS payment_tracker_recipient_wallet_count_lifetime,
  (SELECT COUNT(DISTINCT to_wallet) FROM pmt.payments
   WHERE timestamp >= datetime('now', '-30 days')) AS payment_tracker_recipient_wallet_count_30d,
  (SELECT COUNT(DISTINCT to_wallet) FROM pmt.payments
   WHERE timestamp >= datetime('now', '-7 days')) AS payment_tracker_recipient_wallet_count_7d;

-- ---- 7.4 — Coverage gap interpretation ----
-- Expected ratio (2026-05-19 snapshot):
--   mapper recipient wallets: 101
--   payment-tracker lifetime distinct recipients: 1,172,763
--   mapper coverage of payment-tracker recipient set: 0.009%
--
-- The gap is structural, not a bug. Most x402 economic activity flows
-- through facilitator-mediated routing (Coinbase CDP pool fronts ~29K
-- agents per hot wallet — see Query 02). Endpoint-level recipient
-- wallets are a thin slice of the overall recipient pool.
--
-- For Atlas-style settlement-flow analysis, prefer payments.db direct
-- queries (Query 02) over mapper.on_chain_volume_usdc aggregates.

DETACH DATABASE pmt;

-- ---- Limitations ----
-- (a) Volume is lifetime, not windowed. on_chain_volume_usdc column
--     stores cumulative since payment tracker indexer start (2026-04-12).
--     For 30d / 7d windows, query payments.db directly.
-- (b) Volume reflects payment-tracker observed events only; payments
--     routed through facilitator EIP-3009 paths that the tracker does
--     not see (see 2026-04-23 99.82% retraction lineage) are not
--     attributed to the endpoint's recipient wallet.
-- (c) Wallet-to-endpoint mapping is many-to-one: a single wallet may
--     serve multiple endpoints (operator infrastructure pattern).
--     Volume is duplicated across all endpoints sharing a wallet —
--     SUM over rows over-counts at the endpoint level. To get true
--     per-wallet lifetime, query DISTINCT on_chain_wallet directly.
