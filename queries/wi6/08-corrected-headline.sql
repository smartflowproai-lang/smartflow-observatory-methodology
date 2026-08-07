-- 08-corrected-headline.sql
-- Weekly #6 correction (2026-08-02): drop four ERC-4337 bundler senders from the
-- facilitator marker and recompute the protocol-filter headline.
-- See docs/wi6-correction.md for the evidence and the published correction block.
--
-- FROZEN OUTPUTS (run 2026-08-02 14:43Z..14:50Z, payments.db mtime 14:32Z, mode=ro):
--   V1 (control, uncorrected) : 87,706 payments | $27,739.95 | 14,219 payers | 10,183 recipients
--   V3 (corrected, canonical) : 61,221 payments | $ 7,260.29 |  6,996 payers |  7,680 recipients
--   W3 (corrected, wide cat.) : 64,412 payments | $ 7,626.75 |  7,147 payers |  7,710 recipients
--   Removed senders combined  : 26,485 payments | $20,479.65 | catalogue legs: 0 (narrow cat)
--
-- The four excluded senders (facilitators.source='pattern_inference', April entries).
-- Three are ERC-4337 bundler hot wallets: they call handleOps on the EntryPoint.
-- The fourth (0xb42f812a...) routes through a delegation contract and is a relayer.
-- The test all four fail, and the one that governs the table, is transferWithAuthorization
-- on USDC; see docs/wi6-correction.md and its addendum of 2026-08-07:
--   0x1278c1e48e3c9548a5d9f2b16dc27ed311b0697c
--   0x54e2acab04c89a3fe02852bf8dd69ee8f526bc75
--   0xb42f812a44c22cc6b861478900401ee759ebead6
--   0xaf2bfb6b69dfe6efd257fe8cd694175156a23812
--
-- NULL trap: `tx_sender NOT IN (...)` silently drops rows where tx_sender IS NULL.
-- Every variant below keeps the explicit `tx_sender IS NULL OR` guard.

-- 0. Canonical catalogue (attach mapper.db read-only as m):
--    CREATE TEMP TABLE cat(w TEXT PRIMARY KEY);
--    INSERT OR IGNORE INTO cat
--      SELECT DISTINCT LOWER(on_chain_wallet) FROM m.endpoints
--      WHERE on_chain_wallet IS NOT NULL AND on_chain_wallet != '';   -- 575 rows

-- 1. Corrected headline, canonical variant V3:
SELECT COUNT(*)                        AS payments,
       ROUND(SUM(amount_usdc),2)      AS volume_usdc,
       COUNT(DISTINCT from_wallet)    AS paying_addresses,
       COUNT(DISTINCT to_wallet)      AS receiving_addresses,
       ROUND(SUM(amount_usdc)/COUNT(*),4) AS mean_payment_usdc
FROM payments
WHERE timestamp >= '2026-06-29' AND timestamp < '2026-07-06'
  AND (wash_flag IS NULL OR wash_flag = '')
  AND (is_facilitator_mediated = 1 OR to_wallet IN (SELECT w FROM cat))
  AND (tx_sender IS NULL OR tx_sender NOT IN
       ('0x1278c1e48e3c9548a5d9f2b16dc27ed311b0697c',
        '0x54e2acab04c89a3fe02852bf8dd69ee8f526bc75',
        '0xb42f812a44c22cc6b861478900401ee759ebead6',
        '0xaf2bfb6b69dfe6efd257fe8cd694175156a23812'));

-- 2. Falsification check: the removed rows carry zero catalogue evidence.
--    Expected (narrow catalogue): legs_also_in_catalogue = 0 for every sender,
--    so the subtraction is exact and removes no catalogued payment.
SELECT tx_sender, COUNT(*) AS tx, ROUND(SUM(amount_usdc),2) AS usd,
       SUM(CASE WHEN to_wallet IN (SELECT w FROM cat) THEN 1 ELSE 0 END) AS legs_also_in_catalogue
FROM payments
WHERE timestamp >= '2026-06-29' AND timestamp < '2026-07-06'
  AND (wash_flag IS NULL OR wash_flag = '')
  AND (is_facilitator_mediated = 1 OR to_wallet IN (SELECT w FROM cat))
  AND tx_sender IN ('0x1278c1e48e3c9548a5d9f2b16dc27ed311b0697c',
                    '0x54e2acab04c89a3fe02852bf8dd69ee8f526bc75',
                    '0xb42f812a44c22cc6b861478900401ee759ebead6',
                    '0xaf2bfb6b69dfe6efd257fe8cd694175156a23812')
GROUP BY tx_sender ORDER BY tx DESC;

-- 3. Wide catalogue (union of four mapper sources, 7,927 valid payTo addresses;
--    add facilitator-observed pool to reach the 7,953 used for the marker test):
--    guard json_valid() + json_type()='array' or the query fails on malformed raw_accepts.
--    CREATE TEMP TABLE catw (w TEXT PRIMARY KEY);
--    INSERT OR IGNORE INTO catw SELECT DISTINCT LOWER(on_chain_wallet) FROM m.endpoints
--      WHERE on_chain_wallet IS NOT NULL AND on_chain_wallet != '';
--    INSERT OR IGNORE INTO catw SELECT DISTINCT LOWER(last_pay_to) FROM m.bazaar_endpoints
--      WHERE last_pay_to IS NOT NULL AND last_pay_to != '';
--    INSERT OR IGNORE INTO catw SELECT DISTINCT LOWER(wallet) FROM m.on_chain_wallets
--      WHERE wallet IS NOT NULL AND wallet != '';
--    INSERT OR IGNORE INTO catw
--      SELECT DISTINCT LOWER(json_extract(je.value,'$.payTo'))
--      FROM m.endpoints e, json_each(e.raw_accepts,'$.accepts') je
--      WHERE e.raw_accepts IS NOT NULL AND json_valid(e.raw_accepts)
--        AND json_type(e.raw_accepts,'$.accepts')='array'
--        AND json_extract(je.value,'$.payTo') IS NOT NULL;
--    DELETE FROM catw WHERE w NOT LIKE '0x%' OR LENGTH(w) != 42;
--    Rerun query 1 with cat -> catw to obtain W3 (64,412 | $7,626.75).

-- Limits: tx_hash is PK (multi-leg settlements count once, so bundler dollar totals
-- are underestimates and the correction is conservative); timestamp is ingest time;
-- the catalogue grows over time; tx_sender is backfilled and mutable, so historical
-- variant splits are not bit-reproducible from earlier seals.
