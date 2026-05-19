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
│   └── 07-volume-backfill.sql             (May 2026 endpoint↔payment-tracker volume join — recipient-set coverage gap)
├── schema/
│   ├── mapper-db-schema.sql               (mapper.db DDL)
│   └── payments-db-schema.sql             (payments.db DDL)
└── docs/
    ├── observation-windows.md             (cohort definitions: Q1 = 2026-04-12 → 2026-05-15, 33 days)
    ├── wash-flag-definitions.md           (R1 sub-cent / R2 burst / R3 dust / R4 loop)
    └── facilitator-classification.md      (tri-state mediation classifier rules)
```

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

## Versioning

| Version | Date | Changes |
|---|---|---|
| v1.0.0 | 2026-05-16 | Initial release. 5 queries covering Atlas Findings 1, 3, 4, 5, 6. Schemas for mapper.db + payments.db. |

---

*This repository is the public-facing methodology layer of the SmartFlow Observatory research program. The point estimates are the product. The methodology is the asset. Both are public.*
