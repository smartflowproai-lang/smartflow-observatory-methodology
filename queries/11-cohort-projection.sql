-- ============================================================
-- SmartFlow Observatory — Methodology Query 11
-- Catalogue Inflation Rate — catalog growth ÷ alive-cohort growth
-- ============================================================
-- Source DB: mapper.db (endpoints.first_seen + endpoints.last_seen)
-- Trigger: Through Q1 2026 the mapper catalogue and the alive-endpoint
--          cohort grew together (each new endpoint observed by the
--          crawler typically responded with a 402 within days, so
--          catalog_growth ≈ alive_growth and the catalogue tracked
--          operational substance). The 2026-05-18 Bazaar catalogue
--          merge broke that alignment: +36,570 new `first_seen` rows
--          landed in one day, but only a fraction responded as live
--          402 endpoints in the trailing scan windows — the catalogue
--          inflated faster than the alive cohort.
--
--          Q11 publishes the rolling-window arithmetic for the
--          inflation ratio (catalog growth ÷ alive growth) so a reader
--          can distinguish "catalogue size grew because we discovered
--          more live infrastructure" from "catalogue size grew because
--          we imported a stale registry dump". Values close to 1.0 =
--          discovery in step with operational reality. Values >> 1.0 =
--          catalogue inflating faster than substance — treat catalogue-
--          count statistics with caution in that window.
--
-- Companion: Drill-Down #7 (well-known adoption — same Bazaar merge
--            context), Atlas Mid-2026 Finding 1 (endpoint mortality —
--            inflation ratio is the upstream framing of mortality), and
--            Query 10 §10.3 (the W19→W20 elevated-band anomaly that
--            traces to the same 2026-05-18 event observed here).
-- ============================================================
-- Per measurement-discipline house-rule §4, EXPLICITLY:
--   Numerator (catalog growth)  : count of endpoint rows whose
--                                 first_seen falls inside the rolling
--                                 7-day window ending at cutoff D
--   Numerator (alive growth)    : count of endpoint rows that became
--                                 alive INSIDE the rolling 7-day window
--                                 — operationalised here as endpoints
--                                 first_seen on or before D AND last_seen
--                                 >= D − 7 days. This captures both
--                                 newly-discovered endpoints that are
--                                 still responding and previously-quiet
--                                 endpoints that came back alive.
--   Denominator                 : the rolling window itself (7 days);
--                                 outputs are NOT normalised to per-day
--                                 rates — they are 7-day totals so the
--                                 ratio is dimensionless.
--   Scale                       : endpoint rows (one row = one URL)
-- ============================================================
-- Expected output (snapshot 2026-05-19, mapper.db lifetime cohort
-- 2026-04-10 → 2026-05-19; full endpoints table = 58,822 rows; pre-
-- merge alive cohort ≈ 22,000 endpoints; post-merge alive cohort
-- ≈ 58,800 endpoints):
--
--   §11.1 — 7-day rolling new endpoints by first_seen (cutoff series),
--           selected points:
--     2026-04-12  →  ~21,637  (initial mapper crawler bootstrap window —
--                              the first 7-day bucket captures the bulk
--                              ingestion of the existing x402 universe)
--     2026-04-26  →  ~82      (post-bootstrap organic discovery rate)
--     2026-05-10  →  ~22      (decelerating organic discovery; matches
--                              Drill-Down #1 mortality narrative)
--     2026-05-17  →  ~149     (pre-merge baseline, week before Bazaar)
--     2026-05-18  →  ~36,713  (Bazaar catalogue merge event +36,570
--                              new first_seen rows in a single day —
--                              cumulative with the prior 7 days)
--     2026-05-19  →  ~36,581  (rolling window dominated by 2026-05-18
--                              spike; will decay back over the next
--                              7 days as the spike rolls out)
--
--   §11.2 — 7-day rolling alive cohort size, selected points:
--     2026-04-12  →  ~21,637  (initial alive cohort = entire bootstrap)
--     2026-04-26  →  ~21,983  (pre-merge organic alive ≈ 22K)
--     2026-05-17  →  ~22,202  (alive cohort essentially flat for ~3 wks
--                              before merge — operationally mature x402
--                              universe stabilises around 22K endpoints)
--     2026-05-18  →  ~58,772  (post-merge — alive jumps to nearly the
--                              entire catalogue because the merged rows
--                              were ingested with fresh last_seen
--                              timestamps and have not yet failed a
--                              crawl pass — caveat (b))
--     2026-05-19  →  ~58,773
--
--   §11.3 — Inflation ratio (catalog growth ÷ alive growth):
--     Late-April transition window (W17 / W18, 2026-04-19 → 2026-04-25):
--                          ratios 1.14 → 1.93 — "mild inflation":
--                          catalogue gained 14-93% more endpoints than
--                          the alive cohort, attributable to a thin
--                          mortality wave thinning the alive count while
--                          new discoveries continued.
--     2026-04-26 → 2026-05-17 (organic-discovery regime, no mortality
--                          wave): ratios cluster at 1.0 because new
--                          first_seen rows count as alive in the same
--                          7-day window — see Limitation (d) for why
--                          the ratio is dual-count-saturated in steady-
--                          state and a Q12 follow-up is needed to
--                          separate "new + alive" from "newly-alive".
--     2026-05-18 → present (Bazaar merge regime): ratio also lands at
--                          ~1.0 SHORT TERM, but for the OPPOSITE reason:
--                          merged endpoints inflate BOTH numerator and
--                          denominator equally for the first 7 days
--                          after the merge. This is the stabilisation
--                          window caveat (b) — re-run §11.3 after the
--                          crawler has had 48-72h to attempt the merged
--                          URLs before citing a post-merge inflation
--                          ratio as stable.
-- ============================================================
-- Last verified: 2026-05-19 (against mapper.db at 2026-05-19T18:00 UTC)
-- ============================================================

-- ---- 11.1 — 7-day rolling new endpoints per cutoff day ----
-- For each cutoff day in the observation window, counts endpoints
-- whose first_seen falls in [cutoff − 6 days, cutoff]. This is a
-- rolling-7-day total, not a per-day rate.
--
-- Cutoff series is generated as date arithmetic over the cohort
-- window: 2026-04-12 (Q1 cohort start) through 2026-05-19 (snapshot).
-- Each cutoff row reports the 7-day total ending that day so the
-- reader can plot inflation vs alive-growth side-by-side.

WITH RECURSIVE cutoffs(cutoff_day) AS (
  SELECT date('2026-04-12')
  UNION ALL
  SELECT date(cutoff_day, '+1 day')
  FROM cutoffs
  WHERE cutoff_day < date('2026-05-19')
)
SELECT
  c.cutoff_day,
  (
    SELECT COUNT(*)
    FROM endpoints e
    WHERE date(e.first_seen) >= date(c.cutoff_day, '-6 days')
      AND date(e.first_seen) <= c.cutoff_day
  ) AS new_endpoints_7d_total
FROM cutoffs c
ORDER BY c.cutoff_day;

-- ---- 11.2 — 7-day rolling alive cohort size per cutoff day ----
-- For each cutoff day, counts endpoints satisfying BOTH:
--   (i)  first_seen on or before cutoff (the endpoint was known to the
--        catalogue by that day);
--   (ii) last_seen on or after cutoff − 6 days (the endpoint was
--        observed responding inside the 7-day window).
-- This is the "alive cohort" — endpoints whose operational presence
-- the crawler confirmed in the window.

WITH RECURSIVE cutoffs(cutoff_day) AS (
  SELECT date('2026-04-12')
  UNION ALL
  SELECT date(cutoff_day, '+1 day')
  FROM cutoffs
  WHERE cutoff_day < date('2026-05-19')
)
SELECT
  c.cutoff_day,
  (
    SELECT COUNT(*)
    FROM endpoints e
    WHERE date(e.first_seen) <= c.cutoff_day
      AND date(e.last_seen)  >= date(c.cutoff_day, '-6 days')
  ) AS alive_endpoints_7d_window
FROM cutoffs c
ORDER BY c.cutoff_day;

-- ---- 11.3 — Inflation ratio (catalog growth / alive growth) ----
-- For each cutoff day, computes:
--   catalog_growth_7d  = endpoints newly first_seen in the window (§11.1)
--   alive_growth_7d    = change in alive_endpoints_7d_window vs the
--                        same metric at cutoff − 7 days
--   inflation_ratio    = catalog_growth_7d / alive_growth_7d
-- Interpretation bands (heuristic, NOT statistically derived):
--   ratio in [0.8, 1.25]   →  catalogue tracking operational substance
--   ratio in (1.25, 3.0]   →  catalogue inflating faster than alive
--                              cohort (mild — backlog of slow-to-respond
--                              new listings)
--   ratio > 3.0            →  catalogue inflation spike — likely
--                              registry merge, stale-dump import, or
--                              upstream registry-event artefact
--   ratio negative         →  alive cohort SHRINKING while catalogue
--                              grows (mortality > discovery — investigate)
-- See Limitation (c) for why these bands are heuristic, not derived
-- from a stationarity assumption.

WITH RECURSIVE cutoffs(cutoff_day) AS (
  SELECT date('2026-04-19')
  UNION ALL
  SELECT date(cutoff_day, '+1 day')
  FROM cutoffs
  WHERE cutoff_day < date('2026-05-19')
),
windowed AS (
  SELECT
    c.cutoff_day,
    (
      SELECT COUNT(*)
      FROM endpoints e
      WHERE date(e.first_seen) >= date(c.cutoff_day, '-6 days')
        AND date(e.first_seen) <= c.cutoff_day
    ) AS catalog_growth_7d,
    (
      SELECT COUNT(*)
      FROM endpoints e
      WHERE date(e.first_seen) <= c.cutoff_day
        AND date(e.last_seen)  >= date(c.cutoff_day, '-6 days')
    ) AS alive_now,
    (
      SELECT COUNT(*)
      FROM endpoints e
      WHERE date(e.first_seen) <= date(c.cutoff_day, '-7 days')
        AND date(e.last_seen)  >= date(c.cutoff_day, '-13 days')
    ) AS alive_prior
  FROM cutoffs c
)
SELECT
  cutoff_day,
  catalog_growth_7d,
  alive_now,
  alive_prior,
  (alive_now - alive_prior) AS alive_growth_7d,
  CASE
    WHEN (alive_now - alive_prior) = 0 THEN NULL
    ELSE ROUND(1.0 * catalog_growth_7d / (alive_now - alive_prior), 3)
  END AS inflation_ratio,
  CASE
    WHEN (alive_now - alive_prior) = 0 THEN 'alive-flat (denominator zero)'
    WHEN (alive_now - alive_prior) < 0 THEN 'alive-shrinking (catalogue grows, cohort dies)'
    WHEN 1.0 * catalog_growth_7d / (alive_now - alive_prior) BETWEEN 0.8 AND 1.25
      THEN 'tracking (substance ≈ catalogue)'
    WHEN 1.0 * catalog_growth_7d / (alive_now - alive_prior) BETWEEN 1.25 AND 3.0
      THEN 'mild inflation (response-lag backlog)'
    WHEN 1.0 * catalog_growth_7d / (alive_now - alive_prior) > 3.0
      THEN 'spike (registry merge / stale-dump import suspected)'
    ELSE 'sub-tracking (alive growing faster than catalogue — re-crawl validation candidate)'
  END AS interpretation_band
FROM windowed
ORDER BY cutoff_day;

-- ---- Limitations ----
--
-- (a) ROLLING-WINDOW BOUNDS. The 7-day rolling window is the smallest
--     bucket that smooths over weekly seasonality (crawler cadence is
--     daily; user-side discovery has weekly cycles). Shorter windows
--     (1-3 days) over-attribute one-day spikes to "inflation" when
--     they are just crawler-pass artefacts. Longer windows (28-day)
--     hide structural events behind backward-averaging. The 7-day
--     bucket is a defensible default; readers wanting a sharper trend
--     view should re-parameterise the `'-6 days'` literal in §11.1
--     and §11.2 (and the `'-13 days'` in §11.3's alive_prior column,
--     which must move in lockstep).
--
-- (b) BAZAAR ONE-TIME MERGE SKEW. The 2026-05-18 Bazaar catalogue
--     merge ingested 36,570 endpoint rows in a single day. These rows
--     were inserted with a fresh `last_seen` value equal to the merge
--     timestamp (the crawler had not yet attempted to fetch them on
--     a real crawl pass). For the first 7-day window post-merge, the
--     alive-cohort denominator therefore INCLUDES all 36,570 rows even
--     though some fraction of them will not respond on the first real
--     crawl attempt. The inflation_ratio for the merge window will
--     therefore UNDER-state true inflation (ratio looks closer to 1.0
--     than the eventual stabilised value will be). The fix is to wait
--     one full crawl-cycle after the merge (typically 48-72h) before
--     citing the merge-week inflation_ratio as a stable metric. The
--     Atlas Q3 2026 drill-down will publish the post-stabilisation
--     ratio against the same merge cohort for direct comparison.
--
-- (c) HEURISTIC BANDS, NOT STATIONARY. The interpretation bands in
--     §11.3 (1.25 / 3.0 thresholds) are operational heuristics, not
--     statistically-derived confidence intervals. They were chosen to
--     match the Drill-Down #1 mortality-survival report's
--     "growth-vs-mortality" pairing: a ratio of 1.25 means catalogue
--     is growing 25% faster than alive cohort, which empirically
--     coincides with the response-lag-backlog regime in the Q1 cohort.
--     A future quarterly may recalibrate thresholds against accumulated
--     post-merge data; do not cite the band thresholds as authoritative
--     before that recalibration.
--
-- (d) DUAL-COUNTING IN ALIVE COHORT. An endpoint counted as "alive"
--     in the §11.2 window may also be counted as "new" in the §11.1
--     window (if its first_seen also falls inside the trailing 7
--     days). This is intentional — the inflation ratio measures
--     catalogue arrivals against operational footprint at the same
--     instant. Readers wanting "newly-alive endpoints" specifically
--     (catalogue arrivals MINUS pre-existing inventory) can filter
--     §11.1 results by `WHERE first_seen > (cutoff_day - 6 days)` and
--     join to a per-endpoint first-response timestamp from
--     endpoint_history — that join is left to a future Q12.
--
-- ---- end of Query 11 ----
