-- ============================================================
-- SmartFlow Observatory - Weekly #6 methodology
-- 00: Universe, filters, and the shared preamble
-- ============================================================
-- Companion to: "How much does the x402 market actually weigh"
--   (Weekly #6, published 2026-08-02)
-- Every other file in queries/wi6/ assumes this preamble has been run first.
-- ============================================================
-- Source DBs (both opened read-only):
--   payments.db  - Base-mainnet USDC transfer ledger, own indexer
--   mapper.db    - x402 service catalogue, own crawler
-- ============================================================
-- Last verified: 2026-07-31 (schema + filter definitions re-checked against live DBs)
-- ============================================================


-- ---- 0.1 - Open both databases read-only ----
-- Adjust the paths. mode=ro is deliberate: nothing in this repo writes.
-- .open 'file:payments.db?mode=ro'
ATTACH 'file:mapper.db?mode=ro' AS m;


-- ---- 0.2 - The ledger universe (READ THIS BEFORE COMPARING NUMBERS) ----
-- payments.db is NOT a full USDC transfer log. The indexer applies ONE filter at
-- ingest time and it is an amount filter:
--
--     0.0005 <= amount_usdc <= 5.0        (tracker.py, ingest guard)
--
-- Consequence: the "amount filtered" baseline in file 01 does not carry a WHERE
-- clause on amount, because the band is already baked into what got stored. If you
-- rebuild this from a complete Transfer log you must add the band yourself, or your
-- baseline will be larger than ours and the ratio in file 02 will not reproduce.
--
-- Ledger coverage at time of writing: 2026-04-12 through 2026-07-31 (ingest clock).


-- ---- 0.3 - The clock (NOT block time) ----
-- payments.timestamp is the INGEST timestamp, i.e. when our indexer wrote the row,
-- not the block timestamp. It runs roughly one hour behind block time and it is
-- batchy. Every window in this series is therefore an ingest window aligned to UTC
-- midnight, and no calendar date is claimed in the published text.
--
-- If you need block time on Base, derive it instead of trusting this column:
--     unix_seconds = 1784838545 + (block_number - 49024599) * 2
-- (2 second block cadence; anchor pair verified on our own ledger.)
--
-- Mature window used throughout Weekly #6 (7 days, ending 3 weeks back):
--     timestamp >= '2026-06-29' AND timestamp < '2026-07-06'
-- The maturity rule exists because wash flagging lags ingest; a fresh week looks
-- artificially clean. See docs/wi6-limitations.md, item L3.


-- ---- 0.4 - "Clean" (wash exclusion) ----
-- The wash classifier writes one of four labels, or leaves the column untouched:
--     R1_self   sender equals recipient
--     R2_burst  high frequency repetition inside a short window
--     R3_dust   dust-sized repetition
--     R4_loop   circular routing
-- Clean therefore means: no label. Both forms are treated as clean because the
-- column has been written by more than one generation of the classifier:
--
--     (wash_flag IS NULL OR wash_flag = '')
--
-- This exclusion applies to EVERY figure in Weekly #6, including the inflated one
-- in the lead. The one deliberate exception is documented in file 03.


-- ---- 0.5 - The facilitator marker (a lookup, not a detection) ----
-- is_facilitator_mediated is not inferred from the transaction. It is assigned:
--     = 1     tx_sender is present in the `facilitators` table
--     = 0     tx_sender equals from_wallet (the payer submitted their own transfer)
--     = NULL  everything else
--
-- `facilitators` is a 76 row table (verified 2026-07-31), built from 4 sources:
--     hardcoded 5, observed 49, observed-pool2 15, pattern_inference 7
--
-- NULL therefore means one of two very different things, and we cannot tell them
-- apart row by row:
--     (a) tx_sender was never resolved (RPC gaps during backfill), or
--     (b) tx_sender is a third party that is not in our 76 row table.
--
-- This is why the published text calls the marker a lower bound and not a census.
-- The size of that blind spot is measured in file 03.
SELECT COUNT(*) AS facilitator_rows, COUNT(DISTINCT source) AS sources
FROM facilitators;
-- Expected: 76 | 4


-- ---- 0.6 - The catalogue side of the protocol filter ----
-- A payTo address is an on-chain wallet published in a service catalogue as the
-- destination for a paid endpoint. Addresses in payments.db are lowercase, so the
-- catalogue side is lowercased on the way in.
CREATE TEMP TABLE cat AS
SELECT DISTINCT LOWER(on_chain_wallet) AS w
FROM m.endpoints
WHERE on_chain_wallet IS NOT NULL
  AND on_chain_wallet != '';

SELECT COUNT(*) AS catalogue_paytos FROM cat;
-- The catalogue grows daily. Any rerun of these queries on a later date will
-- recover slightly more protocol payments than the published figures. See
-- docs/wi6-limitations.md, item L4.


-- ---- 0.7 - The protocol filter itself ----
-- Either the money landed on a published payTo address, or a recognised settlement
-- service moved it. Both are statements about protocol role, not about amount:
--
--     (is_facilitator_mediated = 1 OR to_wallet IN (SELECT w FROM cat))
--
-- Written out in full, the standard predicate used by files 02, 04, 05, 06, 07:
--
--     WHERE timestamp >= '2026-06-29' AND timestamp < '2026-07-06'
--       AND (wash_flag IS NULL OR wash_flag = '')
--       AND (is_facilitator_mediated = 1 OR to_wallet IN (SELECT w FROM cat))


-- ============================================================
-- Three ways this preamble could be wrong:
-- ============================================================
-- 1. The amount band at ingest (0.0005 to 5.0 USDC) silently truncates the market
--    at both ends. A protocol payment of $12 is invisible to every query in this
--    directory. We report the protocol total as a total over the banded universe,
--    never as a total over x402.
--
-- 2. payments.tx_hash is the PRIMARY KEY, so a transaction carrying several USDC
--    transfer legs is stored once. Counts here are transactions, not payment legs,
--    and volume is understated wherever multi-leg settlement is used. Magnitude is
--    unmeasured in the general case; on one inspected operator the understatement
--    was large. See docs/wi6-limitations.md, item L1.
--
-- 3. The catalogue is our own crawl. Any paid endpoint we never found contributes
--    zero payTo addresses, so its revenue falls into the unmarked bucket rather
--    than into the protocol figure. The catalogue bounds the payTo side from below.
-- ============================================================
