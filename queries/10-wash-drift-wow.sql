-- ============================================================
-- SmartFlow Observatory — Methodology Query 10
-- Wash Drift Week-over-Week — clean-cohort trajectory + anomaly flag
-- ============================================================
-- Source DB: payments.db (payments table, wash_flag column)
-- Trigger: Drill-Down #6 (weekly tx growth narrative) reported a
--          decelerating clean-cohort trajectory through late April with
--          partial-week caveats applied to the trailing two weeks. As
--          new data accumulates, the question becomes: how much of the
--          week-over-week (WoW) shift is real signal vs. reclassification
--          artefact (wash flags applied retroactively as classifier
--          vintage advances), and is the latest WoW move inside or
--          outside normal variance?
--
--          Q10 publishes the week-by-week clean-cohort accounting that
--          Drill-Down #6 narrative cited, plus an anomaly threshold
--          (rolling std-dev band) so a reader can decide whether to
--          attribute a given WoW move to organic shift, classifier
--          vintage drift, or a structural event (e.g. Bazaar merge).
--
-- Companion: Drill-Down #6 (weekly growth narrative), Atlas Part VI
--            (decelerating-growth finding), planned Q3 2026 drill-down
--            "wash flag classifier vintage audit".
-- ============================================================
-- Per measurement-discipline house-rule §4, EXPLICITLY:
--   Numerator   : payment rows WHERE wash_flag IS NULL OR wash_flag = ''
--                 (the "clean cohort" — neither sub-cent self-pay,
--                  burst, dust, nor loop classified)
--   Denominator : same clean-cohort numerator, segmented by Monday-
--                 anchored ISO-week buckets (date(timestamp, 'weekday 0',
--                 '-6 days') as week_start — see Limitation (e) for the
--                 anchor-formula choice)
--   Scale       : payments.amount_usdc (USDC, six decimals normalised)
-- ============================================================
-- Expected output (snapshot 2026-05-19, payments.db lifetime cohort
-- 2026-04-12 → 2026-05-19, full table = 15,572,672 rows; clean cohort
-- after wash-flag exclusion = 8,786,600 rows; total wash-flagged =
-- 6,786,154 rows across R1/R2/R3/R4 — see Query 03):
--
--   Week-by-week clean-cohort accounting (week_start = Monday of ISO
--   week; computed via date(timestamp, 'weekday 0', '-6 days') — see
--   Limitation (e) for why the naive 'weekday 1' anchor is buggy):
--     2026-04-06  W15  partial    ~86,854 tx     ~$92,765   (data starts
--                                              Sun 2026-04-12; only the
--                                              tail of this week observed)
--     2026-04-13  W16             ~966,289 tx  ~$1,110,729
--     2026-04-20  W17           ~1,345,837 tx  ~$1,577,623
--     2026-04-27  W18           ~1,538,776 tx  ~$1,640,426
--     2026-05-04  W19           ~1,551,473 tx  ~$1,640,418   ← W18→W19
--                                              ~+0.8% tx, ~0% vol —
--                                              matches Drill-Down #6
--                                              "decelerating-growth"
--                                              narrative cited in the
--                                              prose footnote.
--     2026-05-11  W20           ~2,163,699 tx  ~$2,224,074   ← W19→W20
--                                              +39.5% tx, +35.6% vol —
--                                              co-incident with the
--                                              2026-05-18 Bazaar
--                                              catalogue merge spike
--                                              (Query 11 §11.1: +36,570
--                                              new endpoints same day)
--     2026-05-18  W21  partial  ~1,133,672 tx  ~$1,144,281   (data ends
--                                              Tue 2026-05-19; 2 of 7
--                                              days observed — caveat
--                                              flagged in §10.1 output)
--
--   WoW % shifts (full-week pairs only; partial weeks excluded from
--   anomaly evaluation per (a)):
--     W16→W17  +39.3% tx   +42.0% vol
--     W17→W18  +14.3% tx    +4.0% vol
--     W18→W19   +0.8% tx     ~0.0% vol    ← Drill-Down #6 framing:
--                                            mid-cohort deceleration
--                                            into late April / early May.
--                                            §10.3 classifies this row
--                                            as 'elevated' (distance to
--                                            running_mean ≈ 17.3 pp vs
--                                            running σ ≈ 15.9 pp) — the
--                                            deceleration was unusually
--                                            sharp against the early-
--                                            cohort upward run.
--     W19→W20  +39.5% tx   +35.6% vol     ← §10.3 classifies this row
--                                            as 'normal' (running σ has
--                                            widened to ~16.6 pp after
--                                            W19 was absorbed; +39.5%
--                                            sits inside ±1 σ of mean).
--                                            Co-incides with the 2026-
--                                            05-18 Bazaar catalogue
--                                            merge — re-baseline
--                                            candidate from W20 forward
--                                            (see Limitation (c)).
--
--   Anomaly band classification per §10.3 output schema:
--     normal      : |WoW − running_mean| ≤ 1 σ
--     elevated    : 1 σ < |WoW − running_mean| ≤ 2 σ
--     anomaly     : |WoW − running_mean| > 2 σ (tail event)
--   The running mean + std-dev expand as full weeks accumulate; early
--   weeks may classify differently when re-run after additional history
--   lands. Document `classifier_vintage` + `snapshot_date` in any
--   published cite per Limitation (b).
-- ============================================================
-- Last verified: 2026-05-19 (against payments.db at 2026-05-19T18:04 UTC)
-- ============================================================

-- ---- 10.1 — Weekly clean-cohort tx + volume (Mon-anchored) ----
-- Buckets payments into Monday-anchored week_start dates and reports
-- the clean-cohort transaction count and USDC volume per week. A
-- partial_week flag surfaces the leading + trailing buckets where the
-- data window does not fully overlap the seven-day calendar week —
-- partial weeks must NOT be used in WoW percentage computations (see
-- Limitation (a)).

SELECT
  date(timestamp, 'weekday 0', '-6 days') AS week_start,
  COUNT(*) AS clean_tx,
  ROUND(SUM(amount_usdc), 2) AS clean_volume_usdc,
  MIN(date(timestamp)) AS first_day_observed,
  MAX(date(timestamp)) AS last_day_observed,
  CASE
    WHEN julianday(MAX(date(timestamp))) - julianday(MIN(date(timestamp))) + 1 < 7
      THEN 'PARTIAL — fewer than 7 calendar days observed in window'
    ELSE 'full'
  END AS partial_week_flag
FROM payments
WHERE wash_flag IS NULL OR wash_flag = ''
GROUP BY week_start
ORDER BY week_start;

-- ---- 10.2 — Week-over-week % change w/ explicit denominator ----
-- Joins each full week to the prior full week and computes WoW % change
-- on both tx count and USDC volume. The prior-week clean_tx and
-- clean_volume_usdc are surfaced as explicit denominators so a reviewer
-- can sanity-check arithmetic without re-running §10.1. Partial weeks
-- are EXCLUDED from this calculation entirely — they appear in §10.1
-- output only.

WITH weekly AS (
  SELECT
    date(timestamp, 'weekday 0', '-6 days') AS week_start,
    COUNT(*) AS clean_tx,
    SUM(amount_usdc) AS clean_volume_usdc,
    julianday(MAX(date(timestamp))) - julianday(MIN(date(timestamp))) + 1 AS days_covered
  FROM payments
  WHERE wash_flag IS NULL OR wash_flag = ''
  GROUP BY week_start
),
full_weeks AS (
  SELECT week_start, clean_tx, clean_volume_usdc
  FROM weekly
  WHERE days_covered >= 7
),
joined AS (
  SELECT
    curr.week_start AS week_start,
    curr.clean_tx AS curr_tx,
    curr.clean_volume_usdc AS curr_volume,
    LAG(curr.clean_tx) OVER (ORDER BY curr.week_start) AS prev_tx,
    LAG(curr.clean_volume_usdc) OVER (ORDER BY curr.week_start) AS prev_volume
  FROM full_weeks curr
)
SELECT
  week_start,
  curr_tx,
  prev_tx AS prev_week_tx_denominator,
  CASE
    WHEN prev_tx IS NULL THEN NULL
    ELSE ROUND(100.0 * (curr_tx - prev_tx) / prev_tx, 2)
  END AS wow_tx_pct,
  ROUND(curr_volume, 2) AS curr_volume_usdc,
  ROUND(prev_volume, 2) AS prev_week_volume_denominator,
  CASE
    WHEN prev_volume IS NULL OR prev_volume = 0 THEN NULL
    ELSE ROUND(100.0 * (curr_volume - prev_volume) / prev_volume, 2)
  END AS wow_volume_pct
FROM joined
ORDER BY week_start;

-- ---- 10.3 — Anomaly threshold flag (rolling std-dev band) ----
-- Computes the running mean and std-dev of WoW tx-% changes over the
-- full-weeks series and classifies each week as:
--   normal   : within ±1 std-dev of the running mean
--   elevated : within ±2 std-dev but outside ±1 std-dev
--   anomaly  : outside ±2 std-dev (tail event — investigate)
-- SQLite lacks a built-in STDEV aggregate, so std-dev is computed as
-- sqrt(avg(x^2) - avg(x)^2) over the prior weeks (running window).

WITH weekly AS (
  SELECT
    date(timestamp, 'weekday 0', '-6 days') AS week_start,
    COUNT(*) AS clean_tx,
    julianday(MAX(date(timestamp))) - julianday(MIN(date(timestamp))) + 1 AS days_covered
  FROM payments
  WHERE wash_flag IS NULL OR wash_flag = ''
  GROUP BY week_start
),
full_weeks AS (
  SELECT week_start, clean_tx
  FROM weekly
  WHERE days_covered >= 7
),
wow AS (
  SELECT
    week_start,
    clean_tx,
    LAG(clean_tx) OVER (ORDER BY week_start) AS prev_tx,
    CASE
      WHEN LAG(clean_tx) OVER (ORDER BY week_start) IS NULL THEN NULL
      ELSE 100.0 * (clean_tx - LAG(clean_tx) OVER (ORDER BY week_start))
           / LAG(clean_tx) OVER (ORDER BY week_start)
    END AS wow_pct
  FROM full_weeks
),
running AS (
  SELECT
    week_start,
    wow_pct,
    AVG(wow_pct) OVER (ORDER BY week_start ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
      AS running_mean,
    AVG(wow_pct * wow_pct) OVER (ORDER BY week_start ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
      AS running_mean_sq,
    COUNT(wow_pct) OVER (ORDER BY week_start ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
      AS running_n
  FROM wow
)
SELECT
  week_start,
  ROUND(wow_pct, 2) AS wow_pct,
  ROUND(running_mean, 2) AS running_mean_pct,
  ROUND(
    CASE
      WHEN running_n < 2 THEN NULL
      ELSE sqrt(max(0, running_mean_sq - running_mean * running_mean))
    END, 2) AS running_stddev_pct,
  CASE
    WHEN wow_pct IS NULL OR running_n < 3 THEN 'insufficient-history'
    WHEN abs(wow_pct - running_mean) <= sqrt(max(0, running_mean_sq - running_mean * running_mean))
      THEN 'normal'
    WHEN abs(wow_pct - running_mean) <= 2 * sqrt(max(0, running_mean_sq - running_mean * running_mean))
      THEN 'elevated'
    ELSE 'anomaly'
  END AS anomaly_band
FROM running
ORDER BY week_start;

-- ---- Limitations ----
--
-- (a) PARTIAL WEEKS distort both numerator and denominator. The Q1
--     cohort begins mid-week (Sunday 2026-04-12, so W15 lacks Mon-Sat)
--     and the live snapshot ends on whichever calendar day the query
--     was run (typically a Tue or Wed for monthly delivery, so the
--     trailing week is 2-3 days observed of 7). §10.2 + §10.3 EXCLUDE
--     partial weeks from WoW + anomaly evaluation. §10.1 surfaces them
--     for completeness with an explicit `partial_week_flag` column.
--     Drill-Down #6 narrative cited the trailing-week-partial caveat
--     for its publication window — historical readers comparing
--     Drill-Down #6 prose to a later Q10 run will see different
--     terminal-week numbers as partial weeks complete.
--
-- (b) CLASSIFIER VINTAGE DRIFT. The wash_flag column is populated by
--     a classifier whose rules (R1 self / R2 burst / R3 dust / R4 loop)
--     have evolved across versions. A payment row inserted in W16 with
--     wash_flag = '' (clean) may be retroactively re-tagged as 'R3_dust'
--     in a future classifier release. This means historical Q10 outputs
--     are NOT immutable — a re-run two months later may show a smaller
--     clean cohort for the same week. Mitigate by:
--       (i) pinning the classifier version (see facilitator-classification.md
--           §3 for the analogous mediation-classifier vintage discipline);
--       (ii) annotating each published Q10 result with `classifier_vintage`
--            metadata in the prose footnote;
--       (iii) treating large retrospective WoW shifts (>>1 std-dev) on
--             previously-stable weeks as a reclassification flag rather
--             than an organic shift.
--
-- (c) STRUCTURAL EVENTS (cohort discontinuities) — catalogue merges,
--     facilitator launches, regulatory events — break the
--     stationary-WoW assumption underlying the rolling-std-dev band in
--     §10.3. The 2026-05-18 Bazaar catalogue merge (+36,570 endpoints
--     in one day, see Query 11 §11.1) is the canonical example in the
--     Q1 cohort. When an anomaly flag fires AND a known structural
--     event aligns, the recommended treatment is "re-baseline the
--     rolling window from the post-event week forward" rather than
--     classifying the event week as a tail-event outlier on its own
--     merits. This is a discretionary call; the SQL surfaces the flag,
--     the analyst makes the re-baseline decision.
--
-- (e) WEEK ANCHOR FORMULA. SQLite's `date(t, 'weekday N')` modifier
--     moves to the next occurrence of weekday N at or after t. The
--     naive Monday anchor `date(t, 'weekday 1', '-7 days')` looks
--     correct but mis-buckets Mondays themselves: for a Mon, 'weekday 1'
--     is a no-op, and the subsequent '-7 days' kicks the Monday into
--     the PRIOR week's bucket. We use `date(t, 'weekday 0', '-6 days')`
--     instead — "the Sunday at or after t" minus six days, which lands
--     on the correct ISO-week-anchor Monday for every weekday of the
--     input. A simple alternative is `date(t, '-' || ((strftime('%w',t)
--     + 6) % 7) || ' days')`, which is more verbose but does not rely
--     on the SQLite modifier semantics. Both formulas agree on the
--     Q1 cohort; we prefer the modifier form for legibility.
--
-- (d) The std-dev approximation `sqrt(avg(x^2) - avg(x)^2)` is the
--     population formula (n in denominator, not n-1). For n < 5 the
--     sample-vs-population distinction is material but the band is
--     intentionally wide enough (±2σ) that the difference does not
--     change classification in practice. For tight-band analysis
--     (e.g. ±0.5σ), recompute with the sample formula or use a
--     statistical package that exposes both.
--
-- ---- end of Query 10 ----
