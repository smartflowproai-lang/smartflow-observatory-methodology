-- payments.db schema (DDL only, no data)
-- SmartFlow Observatory — Base USDC micro-payments ledger database
-- License: CC0 1.0 (public domain dedication), per repository README
-- Generated from the live database: 2026-09-11

CREATE TABLE payments (
            tx_hash TEXT PRIMARY KEY,
            chain TEXT,
            block_number INTEGER,
            from_wallet TEXT,
            to_wallet TEXT,
            amount_raw TEXT,
            amount_usdc REAL,
            timestamp TEXT,
            detected_at TEXT
        , wash_flag TEXT DEFAULT NULL, tx_sender TEXT, is_facilitator_mediated INTEGER DEFAULT NULL);
CREATE TABLE tracked_blocks (
            chain TEXT PRIMARY KEY,
            last_block INTEGER
        );
CREATE INDEX idx_from_wallet_ts ON payments(from_wallet, timestamp);
CREATE INDEX idx_to_wallet ON payments(to_wallet);
CREATE INDEX idx_timestamp ON payments(timestamp);
CREATE TABLE wallet_metadata (address TEXT PRIMARY KEY, is_contract INTEGER, checked_at INTEGER, activity_pattern TEXT DEFAULT NULL, active_days INTEGER DEFAULT NULL, active_hours INTEGER DEFAULT NULL, tx_per_day INTEGER DEFAULT NULL, classified_at INTEGER DEFAULT NULL);
CREATE TABLE facilitators(
  address TEXT,
  name TEXT,
  chain TEXT,
  source TEXT,
  is_contract INT,
  label_on_chain TEXT,
  first_seen TEXT,
  last_seen TEXT,
  total_tx INT,
  total_volume REAL,
  notes TEXT
, status TEXT, status_reason TEXT, status_set_at TEXT);
CREATE INDEX idx_tx_sender ON payments(tx_sender);
CREATE INDEX idx_is_facilitator_mediated ON payments(is_facilitator_mediated);
CREATE INDEX idx_to_wallet_fac ON payments(to_wallet, is_facilitator_mediated);
CREATE INDEX idx_fac_address ON facilitators(address);
CREATE INDEX idx_wash_flag ON payments(wash_flag);
CREATE TABLE backfill_sender_done(
                     block INTEGER PRIMARY KEY, filled INTEGER, at TEXT);
