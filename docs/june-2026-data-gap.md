# June 2026 data gap — price-history marked non-citable

**Status: June 2026 price-history figures are non-citable.** Do not quote month-over-month
comparisons touching June 2026 from the price-history dataset, including ours.

## What happened

After a server migration on 2026-05-24 the crontab was restored selectively; the
`price_snapshot` job was not among the restored entries. Snapshot collection stopped
2026-06-01 ~14:30 UTC and resumed 2026-06-14 ~15:24 UTC when the entry was re-added.

## Extent (verified against the live database, read-only, 2026-08-28)

Daily row counts in `price_snapshots`:

| day | rows |
|---|---:|
| 2026-05-30 | 291,024 |
| 2026-05-31 | 278,898 |
| 2026-06-01 | 169,764 (partial — collection stopped mid-day) |
| 2026-06-02 … 2026-06-13 | **0 (12 full days, dates absent from the table entirely)** |
| 2026-06-14 | 121,928 (partial — collection resumed mid-day) |
| 2026-06-15 | 292,608 |

## Consequences

- A naive May→June activity comparison lands in the −40% range. That is an ingestion
  artifact, not market signal; the monitored source did not decline over the window.
- Only 16 of 30 June days are citable, and no June aggregate should be published without
  this caveat.
- The first price *change* recorded in the dataset can only be dated to within ±13 days:
  across the gap, change detection cannot distinguish "no change" from "no observation".

## How to refute this

1. Re-run the daily count:
   `SELECT substr(snapshot_timestamp,1,10) d, COUNT(*) FROM price_snapshots WHERE snapshot_timestamp >= '2026-06-01' AND snapshot_timestamp < '2026-06-16' GROUP BY d ORDER BY d;`
   If rows exist for June 2–13, this note is wrong.
2. Check the host's scheduler logs for the gap window: they show dozens of *other* cron
   jobs executing daily throughout, which rules out "the server was down" and supports the
   selective-restore diagnosis. A downed host would refute it.
3. Compare any independent observer of the same ecosystem for the same window: a genuine
   12-day drop to zero would be visible outside our dataset. It isn't.

## Lesson

A freshness check must assert "today's data exists", not "some recent data exists" — the
gap produced no errors, only silence. Filed alongside our monitoring-tolerance fixes.

*Published 2026-08-28.*
