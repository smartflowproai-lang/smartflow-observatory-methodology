# smartflow-observatory/methodology

**Open-source SQL methodology repository — the queries behind SmartFlow Observatory's published Atlas + Quarterly + Drill-Down series.**

---

## What this is

This repository publishes the SQL queries that generate the numerical claims in:

- **[The Agent Economy Atlas — Mid-2026](https://smartflowproai.com/atlas)** (flagship monograph, 22,815 słów)
- **[The State of x402 — Q1 2026](https://smartflowproai.com/atlas)** (inaugural quarterly)
- **6 standalone drill-down reports** (covering endpoint mortality, mega-bots, CDP facilitator-mediation, wash taxonomy, well-known adoption, weekly tx growth)

Every numerical claim in the published Atlas series is reproducible by running the queries in this repository against any equivalent x402 endpoint catalogue + Base-mainnet USDC payment record. The expected output ranges are documented in each query header.

---

## Why this exists

In late April 2026, SmartFlow Observatory retracted a numerical claim ("99.82% P2P") that had been cited for three weeks in our handoffs, partner emails, and a Base grant submission. The retraction was triggered when a downstream partner asked how CDP facilitator-mediated transactions appeared in our USDC `Transfer` log scrape — the answer was "they don't, because EIP-3009 mediation is structurally invisible at the Transfer-log layer." The methodology was wrong; the claim was wrong; the public-facing artifacts were corrected; and the institutional discipline that followed is codified in our `measurement-discipline.md` rule.

This repository is the operational consequence of that retraction. A research observatory whose value proposition is "we observe rails better than anyone else" cannot afford methodological opacity. Publishing the SQL is the cheapest, most reproducible form of "show your work" available to us.

If a number we publish is wrong, this repository is the fastest path for any third party to demonstrate that — by running the same query against their own data and pointing out the gap.

---

## Repository layout

```
methodology/
├── README.md (this file)
├── LICENSE (CC-BY-4.0 — attribution required, derivative work permitted)
├── queries/
│   ├── 01-endpoint-mortality.sql          (Finding 1 — Atlas Part I)
│   ├── 02-facilitator-mediation.sql       (Finding 3 — Atlas Part II)
│   ├── 03-wash-taxonomy.sql               (Finding 5 — Atlas Part II / Drill-down #4)
│   ├── 04-wellknown-adoption.sql          (Finding 4 — Atlas Part IV / Drill-down #5)
│   ├── 05-weekly-growth.sql               (Finding 6 — Atlas Part VI / Drill-down #6)
│   ├── 06-spec-validity-sweep.sql         (May 2026 schema re-validation — catalogue quality layer, 88% strict-v2 pass)
│   ├── 07-volume-backfill.sql             (May 2026 endpoint↔payment-tracker volume join — recipient-set coverage gap)
│   ├── 08-volume-distribution.sql         (May 2026 cohort segmentation by lifetime USDC volume — buyer-agent filter selectivity support)
│   ├── 09-facilitator-concentration.sql   (May 2026 facilitator landscape: top-N share, HHI, Gini — monopolistic vs competitive structure)
│   ├── 10-wash-drift-wow.sql              (May 2026 week-over-week clean-cohort drift accounting + rolling std-dev anomaly band — companion to Drill-down #6 narrative)
│   └── 11-cohort-projection.sql           (May 2026 catalogue inflation rate = catalog growth ÷ alive-cohort growth — Bazaar merge skew + heuristic interpretation bands)
├── schema/
│   ├── mapper-db-schema.sql               (mapper.db DDL)
│   └── payments-db-schema.sql             (payments.db DDL)
└── docs/
    ├── observation-windows.md             (cohort definitions: Q1 = 2026-04-12 → 2026-05-15, 33 days)
    ├── wash-flag-definitions.md           (R1 sub-cent / R2 burst / R3 dust / R4 loop)
    └── facilitator-classification.md      (tri-state mediation classifier rules)
```

---

## Weekly series

Beyond the Atlas queries above, this repository also publishes the queries behind the Weekly newsletter.

### Weekly #6 - "How much does the x402 market actually weigh" (2026-08-02)

Nine files under `queries/wi6/`, plus limits and correction documents. **Corrected August 2, 2026:** four facilitator-marker rows were reclassified as ERC-4337 bundlers and dropped; the corrected mature-week headline is 61,221 payments / $7,260.29 and the amount-vs-protocol gap widens from 63x to 240x. Details: `docs/wi6-correction.md`, query `08-corrected-headline.sql`.

| File | What it produces |
|---|---|
| `00-universe-and-filters.sql` | Shared preamble: the ledger universe, the clock, the wash definition, the facilitator marker, the catalogue, the protocol filter. Run first. |
| `01-amount-filter-baseline.sql` | The amount filtered baseline, i.e. the inflated figure in the piece's lead |
| `02-protocol-filter-weight.sql` | The protocol filtered weight and the three ratios against file 01 |
| `03-unmarked-share.sql` | The 94.5 percent unmarked share, plus the autopsy of a number withdrawn from an earlier draft |
| `04-recipient-bands.sql` | Recipient revenue bands and the concentration line |
| `05-payment-size-bands.sql` | Payment size distribution, calls versus value |
| `06-weekly-series.sql` | Eleven consecutive weeks under one filter, and the receiving-address jump |
| `07-cohort-retention.sql` | Cohort retention for recipients and payers |
| `08-corrected-headline.sql` | Corrected headline after dropping four ERC-4337 bundler senders (Aug 2 correction) |
| `docs/wi6-limitations.md` | The eight limits that cut across all of the above |
| `docs/wi6-correction.md` | The August 2 correction: evidence, corrected figures, method changes |

Two things about this set are worth flagging before you run anything.

**It is filtered on protocol role, not on amount.** Either the money landed on a payTo address published in a service catalogue, or the payment carries a facilitator marker. A bridge contract does not appear in a service catalogue and a liquidity pool does not settle through a facilitator, which is the whole point. The published piece argues that an amount band is a filter on size rather than on purpose, and files 01 and 02 are the same week measured both ways so the difference can be inspected rather than asserted.

**One of these files documents a mistake rather than a finding.** File 03 contains the autopsy of a figure that reached a draft of this piece and was withdrawn before publication: it was arithmetically exact and still wrong, because its population did not match the population it was being compared against. The predicate, the reproduction, and the rule we took from it are all in the file. If the point of publishing methodology is that errors become findable, the errors we found ourselves belong here too.

Expected outputs are documented in each file header, with the date and the exact instant of the ledger they came from. Two of the files report a live re-query rather than the frozen rerun; that split is deliberate and is explained in `docs/wi6-limitations.md`, item L8.

---

## How to reproduce

1. **Clone**: `git clone https://github.com/smartflowproai-lang/smartflow-observatory-methodology.git`
2. **Provision DBs**: SQLite or equivalent — schemas in `schema/` directory
3. **Populate**: either crawl your own (mapper.db crawler is similar to a generic x402 endpoint crawler) or use an existing snapshot
4. **Run queries**: each `queries/*.sql` file is self-contained, copy-paste into your SQL client
5. **Compare**: output should match the expected range documented in the file header (`-- Expected output: X transactions / $Y volume / [date range]`)

If your output differs materially from the expected range, the difference is informative. We welcome issues + pull requests against this repository when an observable third party derives different numbers.

---

## What this is NOT

- **NOT a data dump.** This repository contains queries, not data rows. The mapper.db and payments.db row-level data is the publisher's operational asset and is not redistributed under this license. Enterprise data partnership (raw query access) is a separate paid agreement.
- **NOT a replacement for the published Atlas.** The Atlas is the institutional read of what these queries mean. This repository is the queries' source code. They serve different audiences.
- **NOT a substitute for the Methodology Bible.** Appendix A of the Atlas (the Methodology Bible) contains the prose context, the limits-of-the-observation, and the "three ways this could be wrong" per query. This repository is the executable artifact; the Atlas is the textual artifact.

---

## Citation

When citing methodology from this repository in your own published research, please use:

> *"SmartFlow Observatory methodology, [query name] (May 2026). Available at github.com/smartflowproai-lang/smartflow-observatory-methodology."*

For numerical claim citation (which uses Atlas content rather than methodology directly), please use the citation format documented at [smartflowproai.com/atlas](https://smartflowproai.com/atlas) and consider the 12-month citation license available for institutional citing.

---

## License

CC-BY-4.0 — attribution required, derivative work permitted. See `LICENSE`.

The queries themselves are licensed under CC-BY-4.0; the schemas (database definitions) are licensed under CC0 (public domain dedication) to encourage interoperability.

---

## Maintainer

**Tom Smart** · SmartFlow Observatory
- Email: `info@smartflowproai.com`
- X / Twitter: `@TomSmart_ai`
- Web: `smartflowproai.com/atlas`

Issues, pull requests, and methodology corrections welcome. Disputes over a number should be filed as a GitHub issue with the alternative query and the expected output; the project will respond within 5 business days and either correct the methodology, push back with reasoning, or update the public-facing claim.

---

## Field guide

The failure modes this repository documents from the measurement side are packaged, from the builder side, as a repair guide: [Fix Your 402](https://smartflow6.gumroad.com/l/fix-your-402) (PDF + markdown, USD 39) covers 8 failure chapters built from real scans of live x402 endpoints, each with a symptom, a one-command confirmation, a before/after JSON fix, and a re-scan verification. All 22 JSON examples validate against the open-source x402-endpoint-validator. A [free sample chapter](https://smartflowproai.com/fix-your-402-sample.pdf) is available. It is an implementation guide, not a security audit.

---

## Versioning

| Version | Date | Changes |
|---|---|---|
| v1.0.0 | 2026-05-16 | Initial release. 5 queries covering Atlas Findings 1, 3, 4, 5, 6. Schemas for mapper.db + payments.db. |
| v1.1.0 | 2026-08-02 | Weekly series added. 8 queries + limits doc for Weekly #6 (protocol filter vs amount filter, concentration, size distribution, 11 week series, cohort retention). |
| v1.1.1 | 2026-08-02 | Weekly #6 correction: four facilitator-marker rows reclassified as ERC-4337 bundlers, corrected headline query + correction document added. |

---

*This repository is the public-facing methodology layer of the SmartFlow Observatory research program. The point estimates are the product. The methodology is the asset. Both are public.*
