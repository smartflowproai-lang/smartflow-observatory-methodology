-- mapper.db schema (DDL only, no data)
-- SmartFlow Observatory — x402 endpoint catalogue database
-- License: CC0 1.0 (public domain dedication), per repository README
-- Generated from the live database: 2026-09-11

CREATE TABLE endpoints (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        url TEXT UNIQUE,
        network TEXT,
        registry_source TEXT,
        first_seen TEXT,
        last_seen TEXT,
        status INTEGER,
        response_time_ms INTEGER,
        payment_required_amount TEXT,
        payment_required_token TEXT,
        raw_accepts TEXT,
        notes TEXT
    , chain TEXT, asset TEXT, content_type TEXT, provider_inferred TEXT, response_shape_hash TEXT, payment_required_valid INTEGER DEFAULT 0, consecutive_fails INTEGER DEFAULT 0, http_status_code INTEGER, tls_issuer TEXT, response_size_bytes INTEGER, auth_required INTEGER DEFAULT 0, endpoint_category TEXT, on_chain_wallet TEXT, on_chain_payments INTEGER DEFAULT 0, on_chain_payments_30d INTEGER DEFAULT 0, on_chain_payments_7d INTEGER DEFAULT 0, on_chain_volume_usdc REAL DEFAULT 0, on_chain_first_payment TEXT, on_chain_last_payment TEXT, on_chain_status TEXT, on_chain_last_sync TEXT, is_external_directory_listed INTEGER DEFAULT 0, last_scanned_at TEXT, probe_methods_tried TEXT, challenge_method TEXT);
CREATE TABLE sqlite_sequence(name,seq);
CREATE TABLE endpoint_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    endpoint_url TEXT NOT NULL,
    scanned_at TEXT NOT NULL,
    status INTEGER,
    http_status_code INTEGER,
    response_time_ms INTEGER,
    payment_required_valid INTEGER,
    payment_required_amount TEXT,
    payment_required_token TEXT,
    response_shape_hash TEXT,
    content_type TEXT,
    response_size_bytes INTEGER,
    notes TEXT,
    scan_run_id TEXT
);
CREATE INDEX idx_history_url ON endpoint_history(endpoint_url);
CREATE INDEX idx_history_scanned_at ON endpoint_history(scanned_at);
CREATE INDEX idx_history_url_scanned ON endpoint_history(endpoint_url, scanned_at);
CREATE TABLE scan_runs (
    run_id TEXT PRIMARY KEY,
    started_at TEXT NOT NULL,
    completed_at TEXT,
    total_endpoints INTEGER,
    new_endpoints INTEGER,
    live_402 INTEGER,
    dead INTEGER,
    sources_used TEXT,
    notes TEXT
);
CREATE TABLE on_chain_wallets (
            wallet TEXT PRIMARY KEY,
            total_payments INTEGER DEFAULT 0,
            payments_30d INTEGER DEFAULT 0,
            payments_7d INTEGER DEFAULT 0,
            first_payment TEXT,
            last_payment TEXT,
            on_chain_status TEXT,
            facilitator_count INTEGER DEFAULT 0,
            bazaar_urls TEXT,
            matched_endpoint_ids TEXT,
            last_dune_sync TEXT,
            last_bazaar_sync TEXT
        );
CREATE TABLE bazaar_snapshots (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            snapshot_date   TEXT NOT NULL,          -- ISO date of this run
            resource_url    TEXT NOT NULL,
            pay_to          TEXT,                   -- first accepts[].payTo
            network         TEXT,                   -- first accepts[].network
            amount          TEXT,                   -- first accepts[].maxAmountRequired (raw units)
            asset           TEXT,                   -- first accepts[].asset (contract addr)
            scheme          TEXT,                   -- first accepts[].scheme
            last_updated    TEXT,                   -- item.lastUpdated from API
            resource_type   TEXT,                   -- item.type
            x402_version    TEXT,                   -- item.x402Version
            accepts_count   INTEGER,                -- len(item.accepts)
            raw_json        TEXT NOT NULL           -- full item as JSON string
        );
CREATE INDEX idx_bazaar_snapshots_date
            ON bazaar_snapshots (snapshot_date)
    ;
CREATE INDEX idx_bazaar_snapshots_resource
            ON bazaar_snapshots (resource_url)
    ;
CREATE TABLE bazaar_endpoints (
            resource_url    TEXT PRIMARY KEY,
            first_seen      TEXT NOT NULL,
            last_seen       TEXT NOT NULL,
            times_seen      INTEGER NOT NULL DEFAULT 1,
            last_pay_to     TEXT,
            last_network    TEXT,
            last_amount     TEXT,
            last_asset      TEXT,
            last_scheme     TEXT,
            last_type       TEXT
        );
CREATE TABLE scan_log (
  url TEXT NOT NULL,
  ts INTEGER NOT NULL,
  status_code INTEGER,
  response_time_ms INTEGER,
  strict_v2_valid INTEGER,
  raw_accepts TEXT,
  PRIMARY KEY (url, ts)
);
CREATE INDEX idx_scan_log_url_ts ON scan_log(url, ts);
CREATE INDEX idx_endpoints_last_scanned ON endpoints(last_scanned_at, id);
