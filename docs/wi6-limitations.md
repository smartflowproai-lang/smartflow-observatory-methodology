# Weekly #6 - what these queries cannot tell you

Companion to `queries/wi6/`. The published piece promised the weak points would be written next to the queries rather than buried. This is that list.

Each query file also carries its own "three ways this could be wrong" block. This document holds the limits that cut across all of them.

---

## L1. Counts are transactions, not payment legs

`payments.tx_hash` is the table's PRIMARY KEY. A transaction that moves USDC in several legs is stored once, carrying one leg's amount.

Consequences:

- `COUNT(*)` counts transactions. It undercounts payment legs by an unknown factor.
- `SUM(amount_usdc)` understates volume wherever multi-leg settlement is used.
- The bias is not uniform across recipients, so rankings between a multi-leg settler and a single-leg settler are not like for like.

On one operator we inspected, the understatement was roughly a factor of 28 for that operator's volume. That figure is specific to that operator and must not be read as a global correction factor. We do not know the market-wide magnitude and we do not apply a correction anywhere in Weekly #6.

Direction: every volume and count figure in Weekly #6 is a floor.

## L2. The ledger is amount-banded at ingest

The indexer stores a USDC transfer only if `0.0005 <= amount_usdc <= 5.0`.

This band is not in any `WHERE` clause in this directory. It is in the data.

Consequences:

- Nothing above $5 exists in any figure here. A serious paid API charging $20 a call is invisible.
- The "amount filtered baseline" in file 01 reproduces someone else's amount filter only for readers whose ledger carries the same band.
- The 63.3x ratio in file 02 is a ratio inside the band. Outside it, we have no measurement at all.

Direction: unknown. The band truncates both tails, and we cannot see what it removed.

## L3. `timestamp` is ingest time and wash flags arrive late

`payments.timestamp` is when our indexer wrote the row, not when the block was produced. It lags block time by roughly an hour and it arrives in batches.

Separately, the wash classifier revisits old rows. A row that was clean yesterday can be flagged today.

Consequences:

- Every window in this directory is an ingest window. Do not read calendar dates into them.
- The same query run on two consecutive days returns different numbers for the same historical window. Observed drift over 26 hours on the file 01 baseline: 259 rows and $442.
- Fresh weeks look artificially clean, which is why Weekly #6 only reports windows ending three weeks back.
- Recent weeks are systematically flattered relative to old ones in the file 06 series.

For block-derived time on Base, do not trust this column. Derive it:

```
unix_seconds = 1784838545 + (block_number - 49024599) * 2
```

Direction: recent periods are biased optimistic relative to older ones.

## L4. The catalogue is our own crawl, and it grows

The payTo side of the protocol filter is `mapper.db`, our crawler's endpoint catalogue.

Consequences:

- An endpoint we never found contributes no payTo address, and its revenue falls into the unmarked bucket instead of the protocol figure.
- The catalogue is rebuilt live on every run, so reruns against a fixed historical window recover MORE protocol payments over time. Between 27 and 28 July this added 913 rows to the mature week.
- Anyone reproducing file 02 later should expect to beat our published number rather than match it.

Direction: the protocol figure is a lower bound that gets less wrong with time.

## L5. The facilitator marker is a 76 row lookup, not a detection

`is_facilitator_mediated` is assigned by membership test, not by parsing the transaction:

| Value | Meaning |
|---|---|
| 1 | `tx_sender` appears in the `facilitators` table (76 rows, 4 sources) |
| 0 | `tx_sender` equals `from_wallet`, the payer submitted their own transfer |
| NULL | everything else |

NULL therefore conflates two different things that we cannot separate row by row: a sender we never resolved (RPC gaps during backfill), and a third-party sender absent from our table.

Consequences:

- A settlement service we have not catalogued contributes nothing, and its traffic is counted as unmarked.
- The 94.5 percent unmarked share in file 03 is a ceiling on our ignorance, not a measurement of non-facilitator settlement.
- A hand-maintained list is exactly the kind of definition that silently goes stale. We have been caught by this class of error before, on a different list, and it reversed the sign of a published trend.

Direction: facilitator-mediated traffic is understated.

## L6. Addresses are not entities

Nothing in this directory maps an address to a business.

- One operator can hold thousands of receiving addresses (wallet-per-user, claim flows, gasless onboarding).
- One address can front thousands of unrelated endpoints. We have confirmed a single proxy wallet serving tens of thousands of catalogue URLs.

Consequences: the concentration claim in file 04 is a claim about addresses. The retention claim in file 07 is address persistence, not customer retention. Both directions of error are live and we do not know which dominates.

This limit is why Weekly #6 stops at "those addresses are not evidence of a widening market" and does not name a cause for the address jump. Reading intent from an address pattern is where measurement stops and storytelling starts.

## L7. Sponsored transactions can be misread as direct

Where a third party sponsors gas or submits on the payer's behalf, the identity of the true payer may sit in a receipt field we do not currently read. Such a payment can be classified as direct rather than mediated.

Direction: contributes to L5, in the same direction.

## L8. Two number families, never mixed

Weekly #6 carries figures from two instants of the ledger:

| Family | When | Which figures |
|---|---|---|
| Frozen rerun | 2026-07-27T18:25Z | lead baseline, protocol weight, recipient bands, size bands, weekly series |
| Live re-query | 2026-07-28, to 20:13Z | 94.5 percent unmarked share, all retention figures |

Each family is internally consistent. Across families the same quantity differs, because of L3 and L4. The published text separates them with the phrases "re-run" and "re-queried on the live ledger", and no sentence divides a number from one family by a number from the other.

If you extend this analysis, keep the discipline: a ratio whose numerator and denominator come from different instants, different filters, or different units is not a weak finding. It is not a finding.

---

## How to tell us we are wrong

Run the queries against your own data. If your output differs materially from the documented expectation, open an issue with your query and your output. A disagreement about method is a disagreement that can be settled; a disagreement about a headline number cannot.

## L9. The tx_sender column is backfilled retroactively

`tx_sender` (the transaction-level sender behind the facilitator marker) is not
present on every row at ingest. A background job fills it in retroactively and
runs every 30 minutes; as of 2026-08-01 it has filled 4,540,990 rows after their
initial ingest. Three consequences. First, the facilitator marker can flip a
historical row from unattributed to attributed days after ingest, so any figure
built on `is_facilitator_mediated` drifts upward on re-runs independently of
catalogue growth. Second, L4 is incomplete as written: catalogue growth is one
channel of file 02 drift, and marker backfill is the second and larger one.
Third, reproducing a published figure requires knowing the query date, because
the backfill state at that date is part of the input. This is why the frozen
rerun exists and why every file in this directory names its query date.
