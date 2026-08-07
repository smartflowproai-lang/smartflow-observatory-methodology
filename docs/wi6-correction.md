# Weekly #6 correction: the facilitator marker (August 2, 2026)

A correction block was added to the published post on August 2, 2026, the same day the issue was found. This document is the reproducible side of that correction. The post: "How much does the x402 market actually weigh".

## What was wrong

The protocol filter counts a payment as protocol traffic if its `tx_sender` sits in the 76 row `facilitators` table, or if the recipient is a catalogued payTo address. Four rows of that table, added in April by a fan-out heuristic (`source='pattern_inference'`, one row from a sample of four transactions), turned out to be ERC-4337 bundler hot wallets, not x402 facilitators. Between them they carried 26,485 of 87,706 payments and $20,479.65 of $27,739.95 in the mature week, roughly three quarters of the dollar headline.

## How the classification was settled

Three independent evidence axes, two of them independent of our own catalogue:

1. **Catalogue test.** Against the widest payTo catalogue we can build (7,953 addresses, union of four mapper sources), the Coinbase facilitator addresses hit 81.5 to 83.5 percent. The four inferred rows hit 0.05 to 0.08 percent. A middle group of two Multicall3 batching addresses sits near 53 percent and needs its own review; it is not part of this correction.
2. **Called method.** An x402 `exact` settlement must call `transferWithAuthorization` on USDC (EIP-3009); 20,079 of 20,099 catalogued accepts declare scheme `exact`. In every sampled transaction the Coinbase facilitators call exactly that. The four rows call `handleOps` on the ERC-4337 EntryPoint instead, in 56 of 56 sampled transactions, including six drawn from inside the measured week. Bundlers are neutral account-abstraction infrastructure; they are not facilitators.
3. **Price discreteness.** Facilitator-settled traffic shows price points (top amount is about a third of all transfers, roughly 10 percent unique amounts). The four rows show a continuous distribution (about 64 percent unique amounts, top amount under 4 percent). Service payments have a price list; this traffic does not.

## Corrected figures (mature week 2026-06-29 to 2026-07-06, wash excluded)

Canonical corrected variant V3 drops all four bundler senders and keeps the canonical catalogue (575 payTo). The published correction reports the conservative end and names the wide-catalogue value.

| metric | published | corrected V3 | wide catalogue W3 |
|---|---:|---:|---:|
| payments | 86,895 | 61,221 | 64,412 |
| volume | $27,570.90 | $7,260.29 | $7,626.75 |
| paying addresses | 13,514 | 6,996 | 7,147 |
| receiving addresses | 10,167 | 7,680 | 7,710 |
| volume ratio vs amount filter | 63.3x | 240.4x | 228.8x |
| addresses holding the top share | 157 hold 82% | 44 hold 89.3% | not recomputed |
| field at the top (>= $100) | 24 | 6 | not recomputed |
| new recipients returning within 3 weeks | 4.1% | 1.51% | not recomputed |

The direction of the original finding strengthens: filtering by amount inflates the market 240 times, not 63. The recipient the marker ranked first ($5,967.30, 21.5 percent of the week) was a bridge contract reached only through the bundler rows; it leaves the ranking entirely.

## What changes in the method

1. Entry to the `facilitators` table now requires a mechanical test: presence of `transferWithAuthorization` calls on USDC, checked against decoded transaction input. A 40 percent hit rate on the wide catalogue is a secondary control, not the primary gate (the middle batching group shows why: it passes 40 percent without being facilitator settlement).
2. The four rows are excluded by a `status` column, not deleted; the exclusion date and reason are recorded. Labelled coverage in the quality canary drops by an expected 1.32 points at the cut date.
3. The marker remains a label, not a measurement. That line was already in this repository; the correction is what it looks like when it has teeth.

## Three ways this correction could still be wrong

1. **The mechanical test could be the wrong test.** `transferWithAuthorization` is the settlement call for the `exact` scheme, which covers 20,079 of 20,099 catalogued accepts. A facilitator settling a different scheme would fail this gate and be dropped from the marker even though it is doing protocol work. The gate is calibrated to the dominant scheme, not to the protocol.
2. **The remaining table is not re-gated.** The four rows were removed by the test; the rows already inside were not re-tested against it. Three `pattern_inference` rows from the same April heuristic are still active. Re-running the gate backwards would change the marker again, by under one percent of the mature week as measured on 2026-08-07.
3. **The denominator moves.** The wash classifier keeps labelling rows after they were first counted, so both the corrected headline and the amount-filtered comparison drift downward between runs. The frozen outputs are a reading at a timestamp, not a constant, and the ratio inherits that drift from both sides.

## Known limits of the corrected numbers

Carried over from the original run and still true: `tx_hash` is the primary key, so multi-leg settlements count once and bundler dollar totals are underestimated, which makes the contamination estimate conservative. Timestamps are ingest time, not block time. The catalogue grows, which pushes re-runs up, while the wash classifier keeps labelling rows after they were first counted, which pushes them down. In practice a re-run lands within a fraction of a percent of the frozen output, on either side of it. `tx_sender` is backfilled and mutable, so historical variant splits are not bit-reproducible from earlier seals.

Queries: `08-corrected-headline.sql` in `queries/wi6/`. Run order and frozen outputs are in the header of that file.

## Addendum, August 7, 2026

A later audit refined the classification of the four removed rows. Three call `handleOps` on the EntryPoint and are ERC-4337 bundler hot wallets. The fourth (`0xb42f812a...`) routes through a delegation contract and is a relayer, not a bundler; the sentence "56 of 56 sampled transactions" above does not hold for that row. The operative test is unchanged and is what all four fail: none of them calls `transferWithAuthorization`. The exclusion reason recorded against that row in the `facilitators` table was corrected on August 3, 2026.
