-- ============================================================
-- SmartFlow Observatory - Weekly #6 methodology
-- 06: Eleven weeks under one filter (the series, and the address jump)
-- ============================================================
-- Backs, from "How much does the x402 market actually weigh":
--   "The peak came nine weeks before the most recent mature week: 147,051
--    payments and $64,231.31. The eight weeks that followed sat between $26,102
--    and $43,983 with no direction. The most recent mature week came in at
--    $27,570.90 ... The eleven weeks total $369,572, an average of about $33,600."
--   "Receiving addresses jumped from 3,848 to 10,167, up 6,319 in a single week.
--    Volume rose $1,353.75, or 5.2 percent."
--   "Volume per receiving address fell from $6.81 to $2.71."
-- ============================================================
-- Universe: protocol filtered, clean (see files 00 and 02)
-- Cutoff:   eleven consecutive 7 day ingest windows,
--           ['2026-04-20', '2026-04-27') through ['2026-06-29', '2026-07-06')
-- Number family: FROZEN rerun of 2026-07-27T18:25Z
-- ============================================================
-- Run 00-universe-and-filters.sql first.
-- ============================================================
-- On the window labels: the source rerun tagged these rows with ISO week numbers
-- (W16 to W26). Those tags are names, not definitions. The definition is the
-- 7 day ingest interval anchored on the mature window, and that is what this file
-- reproduces. Do not read a calendar week into them.
-- ============================================================


-- ---- 6.1 - The series ----
WITH RECURSIVE win(n, start_ts, end_ts) AS (
  SELECT 1, '2026-04-20', '2026-04-27'
  UNION ALL
  SELECT n + 1, date(start_ts, '+7 day'), date(end_ts, '+7 day')
  FROM win WHERE n < 11
)
SELECT
  win.n                                   AS week_index,
  win.start_ts                            AS window_start,
  COUNT(p.tx_hash)                        AS payments,
  ROUND(SUM(p.amount_usdc), 2)            AS volume_usdc,
  COUNT(DISTINCT p.to_wallet)             AS receiving_addresses,
  ROUND(SUM(p.amount_usdc) / COUNT(DISTINCT p.to_wallet), 2) AS volume_per_recipient
FROM win
LEFT JOIN payments p
  ON p.timestamp >= win.start_ts
 AND p.timestamp <  win.end_ts
 AND (p.wash_flag IS NULL OR p.wash_flag = '')
 AND (p.is_facilitator_mediated = 1 OR p.to_wallet IN (SELECT w FROM cat))
GROUP BY win.n, win.start_ts
ORDER BY win.n;
-- Published anchors (rerun 2026-07-27):
--   week 2  (peak):     147,051 payments   $64,231.31
--   weeks 3 to 10:      volume band $26,102 to $43,983, no direction
--   week 10:            $26,217.15   3,848 recipients   $6.81 per recipient
--   week 11 (mature):    86,895 payments   $27,570.90   10,167 recipients   $2.71
--   all 11 weeks:       $369,572.29 total, $33,597.48 mean


-- ---- 6.2 - The two claims about the last step ----
-- Volume up 5.2 percent, recipients up 164 percent. Stated as arithmetic on the
-- series above so the reader can see there is no third number hiding in it.
SELECT
  10167 - 3848                                   AS new_recipients,          -- 6319
  ROUND(27570.90 - 26217.15, 2)                  AS volume_delta_usdc,       -- 1353.75
  ROUND(100.0 * (27570.90 - 26217.15) / 26217.15, 2) AS volume_delta_pct,    -- 5.16
  ROUND((27570.90 - 26217.15) / (10167 - 3848), 2)   AS delta_per_new_addr,  -- 0.21
  ROUND(26217.15 / 3848, 2)                      AS vol_per_recip_before,    -- 6.81
  ROUND(27570.90 / 10167, 2)                     AS vol_per_recip_after;     -- 2.71
-- Crediting the entire volume increase to the new addresses gives each of them
-- about 21 cents. That is the arithmetic behind refusing to call this growth.


-- ---- 6.3 - Peak to trough, stated as the piece states it ----
SELECT
  ROUND(100.0 * (27570.90 - 64231.31) / 64231.31, 2) AS volume_vs_peak_pct,  -- -57.08
  ROUND(100.0 * (86895.0 - 147051.0) / 147051.0, 2)  AS count_vs_peak_pct;   -- -40.91


-- ============================================================
-- Three ways this query could be wrong:
-- ============================================================
-- 1. The protocol filter is applied with TODAY's catalogue to ALL eleven windows,
--    including windows that predate most of the catalogue's growth. Older weeks are
--    therefore measured with a better instrument than they were lived with, which
--    biases the series UPWARD at the old end and makes the flat reading, if
--    anything, generous to the growth story. A time-aware catalogue (payTo known as
--    of the window) would be the stricter test and we have not run it.
--
-- 2. Every window is an ingest window. Ingest is batchy and lags block time by
--    roughly an hour, so a payment near a boundary can land in the neighbouring
--    week. At weekly resolution this is noise; do not reuse this construction at
--    daily resolution without switching to block-derived time (file 00, 0.3).
--
-- 3. The wash classifier has had more time to work on old weeks than on recent
--    ones. Late flagging removes rows, so recent weeks are systematically flattered
--    relative to old ones. The maturity rule (3 weeks) reduces this but does not
--    remove it, and it means a flat series is more likely to be a declining one
--    than a rising one. We state the direction of the bias rather than correct it.
-- ============================================================
