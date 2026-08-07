-- =====================================================================
-- 01-catalog-gaps-census.sql
-- WI#7, sekcja "Three notes on the public catalog", punkt trzeci:
-- payTo widziane w publicznym katalogu, ktore settluja on-chain PO
-- ostatnim skanie, w ktorym katalog je pokazywal.
--
-- Autor przebiegu: re-JOIN 2026-08-07 (nightq-0803-fixes)
-- Zastepuje: brak reprodukowalnego zapytania pod liczbami 1,550/231/64/29/~84
--            z komentarza GitHub c-5007015702 (2026-07-17T20:00:20Z)
--
-- ---------------------------------------------------------------------
-- URUCHOMIENIE (read-only na obu bazach zrodlowych):
--
--   rm -f /tmp/wi7-census.db
--   sqlite3 "" < 01-catalog-gaps-census.sql
--
-- Zrodla sa ATTACHowane z ?mode=ro, wiec SQLite odrzuci kazdy zapis.
-- Jedyny zapis idzie do /tmp/wi7-census.db (tabele posrednie).
-- Czas przebiegu: ok. 15 min (3 pelne skany bazaar_snapshots + JOIN po
-- idx_to_wallet na 77M wierszy payments).
--
-- ---------------------------------------------------------------------
-- DLACZEGO bazaar_snapshots, A NIE bazaar_endpoints
--
-- bazaar_endpoints.last_seen i .last_pay_to sa MUTOWALNE: kazdy kolejny
-- skan je nadpisuje. Rekonstrukcja historyczna po nich (filtr first_seen
-- <= cutoff) dawala poprawny wynik w lipcu, a dzis daje inny, bo czesc
-- endpointow zmienila payTo po cutoffie. bazaar_snapshots to niemutowalny
-- log per-skan, wiec rekonstrukcja z niego jest stabilna w czasie.
--
-- Walidacja rekonstrukcji (2026-08-07): dla cutoffu "teraz" zbior payTo
-- i wartosci last_catalog zgadzaja sie z zywym bazaar_endpoints co do
-- jednego wiersza (2026 = 2026, 0 roznic w last_catalog).
--
-- ---------------------------------------------------------------------
-- DEFINICJE
--   last_catalog(payTo) = najpozniejszy snapshot_date (<= cutoff) sposrod
--       wszystkich resource_url, ktorych payTo w ich ostatnim snapshocie
--       (<= cutoff) rowna sie temu payTo, po LOWER(TRIM(.)).
--   settlement "po katalogu" = wiersz payments z to_wallet = payTo
--       i substr(timestamp,1,19) > last_catalog, w oknie <= cutoff.
--   gap_d = julianday(last_after) - julianday(last_catalog).
--   Sygnal glowny = gap_d >= 7. Kubelek gap_d < 1 to artefakt migawki
--       (payTo wciaz w najswiezszym skanie), NIE delisting.
--
-- KLUCZ JOINU: bazaar pay_to jest checksummed (mixed-case),
--   payments.to_wallet jest lowercase. Stad LOWER(TRIM(pay_to)).
--
-- CUTOFFY
--   A = 2026-07-16T21:14:00  replay censusu n1 z 16.07 (kontrola)
--   B = 2026-07-17T19:30:00  replay komentarza c-5007015702
--       (komentarz opublikowany 20:00:20Z; zapytanie chodzilo ok. 19:30,
--        patrz sweep w CENSUS-REJOIN-2026-08-07.md)
--   C = brak gornego ograniczenia, czyli stan baz w chwili przebiegu
--
-- =====================================================================
-- FROZEN OUTPUTS (przebieg 2026-08-07, VPS, sqlite3 3.45)
--   payments.db: 76 951 584 wierszy, max timestamp 2026-08-07T16:06:29
--   mapper.db bazaar_snapshots: 13 218 152 wierszy, 82 301 resource_url
--
--   metryka                     |   A 16.07 |   B 17.07 |   C 07.08
--   ----------------------------|-----------|-----------|----------
--   kohorta payTo (all-network) |     1 531 |     1 550 |     2 026
--   kohorta payTo (EVM only)    |     1 497 |     1 516 |     1 977
--   >=1 settlement po katalogu  |       141 |       231 |       198
--   gap_d >= 7                  |        63 |        64 |        92
--   gap_d >= 30                 |        28 |        29 |        38
--   max gap_d                   |   82.1261 |   84.4617 |  101.6697
--   gap_d < 1 (artefakt migawki)|        64 |       152 |        84
--   gap_d >= 7 AND tx_po >= 5   |        35 |        35 |        53
--   gap_d >= 7 AND usdc_po >= 1 |        18 |        18 |        28
--
--   Kontrola A: 1531 / 141 / 63 / 28 / 82,1 zgadza sie co do cyfry z
--   ~/queue-overnight-2026-07-17/output/n1-frozen-tracking-census.md
--   Kontrola B: 1550 / 231 / 64 / 29 / ~84 zgadza sie co do cyfry z
--   opublikowanym komentarzem c-5007015702.
--
--   UWAGA do max gap w B: rekord 84,4617 dnia to payTo
--   0x7e37015a806ff05d6ab3de50f6d0e8765d38c72d z JEDNA transakcja
--   na 0,0007 USDC. Odporny odpowiednik (tx_po >= 5) to 82,13 dnia.
--   W C rekord 101,6697 ma 48 tx / 0,20 USDC.
--
--   UWAGA do wariantu C: 2026-07-24T03:00:01 wolumen skanu katalogu
--   spada z ok. 24 900 do 14 199 resource_url i tam zostaje. 10 873
--   resource_url (379 payTo) ma last_seen w dobie 2026-07-23. Osiem
--   z 92 payTo w kubelku gap>=7 wariantu C to wlasnie ten prog.
--   Wariant B (17.07) jest sprzed tego zdarzenia, wiec nieskazony.
--   Przyczyna progu (czystka po stronie katalogu vs obciecie naszej
--   paginacji) NIE jest rozstrzygnieta z tych dwoch tabel.
-- =====================================================================

ATTACH DATABASE 'file:/home/ubuntu/x402-network-mapper/mapper.db?mode=ro'   AS m;
ATTACH DATABASE 'file:/home/ubuntu/x402-payment-tracker/payments.db?mode=ro' AS p;
ATTACH DATABASE 'file:/tmp/wi7-census.db?mode=rwc'                          AS w;

PRAGMA temp_store=FILE;

-- ---------------------------------------------------------------------
-- 0. Cutoffy w jednym miejscu.
--    ts_cat  = gorna granica skanow katalogu
--    ts_pay  = gorna granica plaatnosci
--    '9999-12-31T23:59:59' oznacza "bez ograniczenia" (cutoff C).
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS w.params;
CREATE TABLE w.params (variant TEXT PRIMARY KEY, ts_cat TEXT, ts_pay TEXT, label TEXT);
INSERT INTO w.params VALUES
  ('A','2026-07-16T21:14:00','2026-07-16T21:14:00','replay censusu n1 16.07'),
  ('B','2026-07-17T19:30:00','2026-07-17T19:30:00','replay komentarza c-5007015702'),
  ('C','9999-12-31T23:59:59','9999-12-31T23:59:59','stan w chwili przebiegu');

-- ---------------------------------------------------------------------
-- 1. Rekonstrukcja katalogu: dla kazdego resource_url ostatni snapshot
--    <= cutoff. Bare pay_to pochodzi z wiersza z MAX(), co SQLite
--    gwarantuje przy dokladnie jednym agregacie min()/max().
--    NOT INDEXED wymusza pelny skan zamiast 13M losowych lookupow
--    po idx_bazaar_snapshots_resource (60 s zamiast ponad 10 min).
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS w.url_a;
CREATE TABLE w.url_a AS
SELECT resource_url, MAX(substr(snapshot_date,1,19)) AS last_seen, pay_to
FROM m.bazaar_snapshots NOT INDEXED
WHERE substr(snapshot_date,1,19) <= (SELECT ts_cat FROM w.params WHERE variant='A')
GROUP BY resource_url;

DROP TABLE IF EXISTS w.url_b;
CREATE TABLE w.url_b AS
SELECT resource_url, MAX(substr(snapshot_date,1,19)) AS last_seen, pay_to
FROM m.bazaar_snapshots NOT INDEXED
WHERE substr(snapshot_date,1,19) <= (SELECT ts_cat FROM w.params WHERE variant='B')
GROUP BY resource_url;

DROP TABLE IF EXISTS w.url_c;
CREATE TABLE w.url_c AS
SELECT resource_url, MAX(substr(snapshot_date,1,19)) AS last_seen, pay_to
FROM m.bazaar_snapshots NOT INDEXED
WHERE substr(snapshot_date,1,19) <= (SELECT ts_cat FROM w.params WHERE variant='C')
GROUP BY resource_url;

-- ---------------------------------------------------------------------
-- 2. Kohorta payTo. is_evm wydzielone, zeby mianownik dalo sie podac
--    w obu wariantach (all-network vs EVM), bo tylko EVM moze w ogole
--    trafic w ledger na Base.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS w.cat_a;
CREATE TABLE w.cat_a AS
SELECT LOWER(TRIM(pay_to)) AS payto_lower, MAX(last_seen) AS last_catalog,
       COUNT(*) AS n_endpoints,
       (LENGTH(TRIM(pay_to))=42 AND LOWER(SUBSTR(TRIM(pay_to),1,2))='0x'
        AND LOWER(SUBSTR(TRIM(pay_to),3)) NOT GLOB '*[^0-9a-f]*') AS is_evm
FROM w.url_a WHERE pay_to IS NOT NULL AND TRIM(pay_to)<>'' GROUP BY LOWER(TRIM(pay_to));

DROP TABLE IF EXISTS w.cat_b;
CREATE TABLE w.cat_b AS
SELECT LOWER(TRIM(pay_to)) AS payto_lower, MAX(last_seen) AS last_catalog,
       COUNT(*) AS n_endpoints,
       (LENGTH(TRIM(pay_to))=42 AND LOWER(SUBSTR(TRIM(pay_to),1,2))='0x'
        AND LOWER(SUBSTR(TRIM(pay_to),3)) NOT GLOB '*[^0-9a-f]*') AS is_evm
FROM w.url_b WHERE pay_to IS NOT NULL AND TRIM(pay_to)<>'' GROUP BY LOWER(TRIM(pay_to));

DROP TABLE IF EXISTS w.cat_c;
CREATE TABLE w.cat_c AS
SELECT LOWER(TRIM(pay_to)) AS payto_lower, MAX(last_seen) AS last_catalog,
       COUNT(*) AS n_endpoints,
       (LENGTH(TRIM(pay_to))=42 AND LOWER(SUBSTR(TRIM(pay_to),1,2))='0x'
        AND LOWER(SUBSTR(TRIM(pay_to),3)) NOT GLOB '*[^0-9a-f]*') AS is_evm
FROM w.url_c WHERE pay_to IS NOT NULL AND TRIM(pay_to)<>'' GROUP BY LOWER(TRIM(pay_to));

-- ---------------------------------------------------------------------
-- 3. Settlement po ostatnim widzeniu w katalogu.
--    tx_backfilled liczy wiersze, ktore w oknie czasowym cutoffu byly,
--    ale zostaly zingestowane pozniej (detected_at > cutoff). To licznik
--    mutacji ledgera: jesli > 0, dawny przebieg ich nie widzial.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS w.after_a;
CREATE TABLE w.after_a AS
SELECT c.payto_lower, COUNT(*) AS tx_po, SUM(COALESCE(pm.amount_usdc,0)) AS usdc_po,
       COUNT(DISTINCT pm.from_wallet) AS payers_po,
       MIN(substr(pm.timestamp,1,19)) AS first_after,
       MAX(substr(pm.timestamp,1,19)) AS last_after,
       SUM(CASE WHEN pm.detected_at > (SELECT ts_pay FROM w.params WHERE variant='A') THEN 1 ELSE 0 END) AS tx_backfilled
FROM w.cat_a c JOIN p.payments pm ON pm.to_wallet = c.payto_lower
WHERE substr(pm.timestamp,1,19) > c.last_catalog
  AND substr(pm.timestamp,1,19) <= (SELECT ts_pay FROM w.params WHERE variant='A')
GROUP BY c.payto_lower;

DROP TABLE IF EXISTS w.after_b;
CREATE TABLE w.after_b AS
SELECT c.payto_lower, COUNT(*) AS tx_po, SUM(COALESCE(pm.amount_usdc,0)) AS usdc_po,
       COUNT(DISTINCT pm.from_wallet) AS payers_po,
       MIN(substr(pm.timestamp,1,19)) AS first_after,
       MAX(substr(pm.timestamp,1,19)) AS last_after,
       SUM(CASE WHEN pm.detected_at > (SELECT ts_pay FROM w.params WHERE variant='B') THEN 1 ELSE 0 END) AS tx_backfilled
FROM w.cat_b c JOIN p.payments pm ON pm.to_wallet = c.payto_lower
WHERE substr(pm.timestamp,1,19) > c.last_catalog
  AND substr(pm.timestamp,1,19) <= (SELECT ts_pay FROM w.params WHERE variant='B')
GROUP BY c.payto_lower;

DROP TABLE IF EXISTS w.after_c;
CREATE TABLE w.after_c AS
SELECT c.payto_lower, COUNT(*) AS tx_po, SUM(COALESCE(pm.amount_usdc,0)) AS usdc_po,
       COUNT(DISTINCT pm.from_wallet) AS payers_po,
       MIN(substr(pm.timestamp,1,19)) AS first_after,
       MAX(substr(pm.timestamp,1,19)) AS last_after,
       0 AS tx_backfilled
FROM w.cat_c c JOIN p.payments pm ON pm.to_wallet = c.payto_lower
WHERE substr(pm.timestamp,1,19) > c.last_catalog
  AND substr(pm.timestamp,1,19) <= (SELECT ts_pay FROM w.params WHERE variant='C')
GROUP BY c.payto_lower;

-- ---------------------------------------------------------------------
-- 4. Raport
-- ---------------------------------------------------------------------
.mode column
.headers on

SELECT 'STAN ZRODEL' AS sekcja;
SELECT (SELECT COUNT(*) FROM p.payments)             AS payments_rows,
       (SELECT MAX(substr(timestamp,1,19)) FROM p.payments) AS payments_max_ts,
       (SELECT COUNT(*) FROM m.bazaar_snapshots)     AS snapshot_rows,
       (SELECT MAX(substr(snapshot_date,1,19)) FROM m.bazaar_snapshots) AS catalog_max_ts;

SELECT 'METRYKI' AS sekcja;
SELECT 'A' AS wariant,
  (SELECT COUNT(*) FROM w.cat_a)                AS kohorta_all,
  (SELECT COUNT(*) FROM w.cat_a WHERE is_evm=1) AS kohorta_evm,
  (SELECT COUNT(*) FROM w.after_a)              AS any_after,
  (SELECT COUNT(*) FROM w.after_a a JOIN w.cat_a c USING(payto_lower)
     WHERE julianday(a.last_after)-julianday(c.last_catalog)>=7)  AS gap_ge_7,
  (SELECT COUNT(*) FROM w.after_a a JOIN w.cat_a c USING(payto_lower)
     WHERE julianday(a.last_after)-julianday(c.last_catalog)>=30) AS gap_ge_30,
  (SELECT ROUND(MAX(julianday(a.last_after)-julianday(c.last_catalog)),4)
     FROM w.after_a a JOIN w.cat_a c USING(payto_lower))          AS max_gap_d,
  (SELECT COUNT(*) FROM w.after_a a JOIN w.cat_a c USING(payto_lower)
     WHERE julianday(a.last_after)-julianday(c.last_catalog)<1)   AS gap_lt_1,
  (SELECT COUNT(*) FROM w.after_a a JOIN w.cat_a c USING(payto_lower)
     WHERE julianday(a.last_after)-julianday(c.last_catalog)>=7 AND a.tx_po>=5)     AS gap7_tx5,
  (SELECT COUNT(*) FROM w.after_a a JOIN w.cat_a c USING(payto_lower)
     WHERE julianday(a.last_after)-julianday(c.last_catalog)>=7 AND a.usdc_po>=1)   AS gap7_usdc1,
  (SELECT COALESCE(SUM(tx_backfilled),0) FROM w.after_a)          AS tx_backfilled
UNION ALL
SELECT 'B',
  (SELECT COUNT(*) FROM w.cat_b), (SELECT COUNT(*) FROM w.cat_b WHERE is_evm=1),
  (SELECT COUNT(*) FROM w.after_b),
  (SELECT COUNT(*) FROM w.after_b a JOIN w.cat_b c USING(payto_lower) WHERE julianday(a.last_after)-julianday(c.last_catalog)>=7),
  (SELECT COUNT(*) FROM w.after_b a JOIN w.cat_b c USING(payto_lower) WHERE julianday(a.last_after)-julianday(c.last_catalog)>=30),
  (SELECT ROUND(MAX(julianday(a.last_after)-julianday(c.last_catalog)),4) FROM w.after_b a JOIN w.cat_b c USING(payto_lower)),
  (SELECT COUNT(*) FROM w.after_b a JOIN w.cat_b c USING(payto_lower) WHERE julianday(a.last_after)-julianday(c.last_catalog)<1),
  (SELECT COUNT(*) FROM w.after_b a JOIN w.cat_b c USING(payto_lower) WHERE julianday(a.last_after)-julianday(c.last_catalog)>=7 AND a.tx_po>=5),
  (SELECT COUNT(*) FROM w.after_b a JOIN w.cat_b c USING(payto_lower) WHERE julianday(a.last_after)-julianday(c.last_catalog)>=7 AND a.usdc_po>=1),
  (SELECT COALESCE(SUM(tx_backfilled),0) FROM w.after_b)
UNION ALL
SELECT 'C',
  (SELECT COUNT(*) FROM w.cat_c), (SELECT COUNT(*) FROM w.cat_c WHERE is_evm=1),
  (SELECT COUNT(*) FROM w.after_c),
  (SELECT COUNT(*) FROM w.after_c a JOIN w.cat_c c USING(payto_lower) WHERE julianday(a.last_after)-julianday(c.last_catalog)>=7),
  (SELECT COUNT(*) FROM w.after_c a JOIN w.cat_c c USING(payto_lower) WHERE julianday(a.last_after)-julianday(c.last_catalog)>=30),
  (SELECT ROUND(MAX(julianday(a.last_after)-julianday(c.last_catalog)),4) FROM w.after_c a JOIN w.cat_c c USING(payto_lower)),
  (SELECT COUNT(*) FROM w.after_c a JOIN w.cat_c c USING(payto_lower) WHERE julianday(a.last_after)-julianday(c.last_catalog)<1),
  (SELECT COUNT(*) FROM w.after_c a JOIN w.cat_c c USING(payto_lower) WHERE julianday(a.last_after)-julianday(c.last_catalog)>=7 AND a.tx_po>=5),
  (SELECT COUNT(*) FROM w.after_c a JOIN w.cat_c c USING(payto_lower) WHERE julianday(a.last_after)-julianday(c.last_catalog)>=7 AND a.usdc_po>=1),
  0;

SELECT 'HISTOGRAM gap_d, wariant B' AS sekcja;
SELECT bucket, COUNT(*) AS payto FROM (
  SELECT CASE WHEN d<1 THEN '0: <1 day' WHEN d<3 THEN '1: 1-2 days' WHEN d<7 THEN '2: 3-6 days'
              WHEN d<14 THEN '3: 7-13 days' WHEN d<30 THEN '4: 14-29 days' ELSE '5: 30+ days' END AS bucket
  FROM (SELECT julianday(a.last_after)-julianday(c.last_catalog) AS d
        FROM w.after_b a JOIN w.cat_b c USING(payto_lower))
) GROUP BY bucket ORDER BY bucket;

SELECT 'HISTOGRAM gap_d, wariant C' AS sekcja;
SELECT bucket, COUNT(*) AS payto FROM (
  SELECT CASE WHEN d<1 THEN '0: <1 day' WHEN d<3 THEN '1: 1-2 days' WHEN d<7 THEN '2: 3-6 days'
              WHEN d<14 THEN '3: 7-13 days' WHEN d<30 THEN '4: 14-29 days' ELSE '5: 30+ days' END AS bucket
  FROM (SELECT julianday(a.last_after)-julianday(c.last_catalog) AS d
        FROM w.after_c a JOIN w.cat_c c USING(payto_lower))
) GROUP BY bucket ORDER BY bucket;

SELECT 'NAJDLUZSZE LUKI, wariant B (uwaga na tx_po)' AS sekcja;
SELECT a.payto_lower, c.last_catalog, a.last_after,
       ROUND(julianday(a.last_after)-julianday(c.last_catalog),4) AS gap_d,
       a.tx_po, ROUND(a.usdc_po,4) AS usdc_po
FROM w.after_b a JOIN w.cat_b c USING(payto_lower) ORDER BY gap_d DESC LIMIT 5;

SELECT 'NAJDLUZSZE LUKI, wariant C (uwaga na tx_po)' AS sekcja;
SELECT a.payto_lower, c.last_catalog, a.last_after,
       ROUND(julianday(a.last_after)-julianday(c.last_catalog),4) AS gap_d,
       a.tx_po, ROUND(a.usdc_po,4) AS usdc_po
FROM w.after_c a JOIN w.cat_c c USING(payto_lower) ORDER BY gap_d DESC LIMIT 5;

SELECT 'ROZNICA KOHORT A vs B (wyjasnienie 1531 -> 1550)' AS sekcja;
SELECT (SELECT COUNT(*) FROM w.cat_b b LEFT JOIN w.cat_a a USING(payto_lower) WHERE a.payto_lower IS NULL) AS weszlo,
       (SELECT COUNT(*) FROM w.cat_a a LEFT JOIN w.cat_b b USING(payto_lower) WHERE b.payto_lower IS NULL) AS wyszlo,
       (SELECT COUNT(*) FROM w.cat_b) - (SELECT COUNT(*) FROM w.cat_a) AS netto;

SELECT 'payTo, ktore weszlo do gap>=7 miedzy A i B' AS sekcja;
SELECT a.payto_lower, c.last_catalog, a.last_after,
       ROUND(julianday(a.last_after)-julianday(c.last_catalog),4) AS gap_d, a.tx_po, ROUND(a.usdc_po,4) AS usdc_po
FROM w.after_b a JOIN w.cat_b c USING(payto_lower)
WHERE julianday(a.last_after)-julianday(c.last_catalog)>=7
  AND a.payto_lower NOT IN (
    SELECT x.payto_lower FROM w.after_a x JOIN w.cat_a y USING(payto_lower)
    WHERE julianday(x.last_after)-julianday(y.last_catalog)>=7);

-- ---------------------------------------------------------------------
-- 5. Kontrola stabilnosci rekonstrukcji: dla cutoffu C zbior payTo i
--    last_catalog musza byc identyczne z zywym bazaar_endpoints.
--    Oczekiwane: 0, 0, 0.
-- ---------------------------------------------------------------------
SELECT 'KONTROLA rekonstrukcja vs zywy bazaar_endpoints (oczekiwane 0/0/0)' AS sekcja;
WITH live AS (
  SELECT LOWER(TRIM(last_pay_to)) AS payto_lower, MAX(substr(last_seen,1,19)) AS last_catalog
  FROM m.bazaar_endpoints WHERE last_pay_to IS NOT NULL AND TRIM(last_pay_to)<>''
  GROUP BY LOWER(TRIM(last_pay_to)))
SELECT (SELECT COUNT(*) FROM live l LEFT JOIN w.cat_c c USING(payto_lower) WHERE c.payto_lower IS NULL)  AS tylko_w_zywym,
       (SELECT COUNT(*) FROM w.cat_c c LEFT JOIN live l USING(payto_lower) WHERE l.payto_lower IS NULL)  AS tylko_w_rekonstrukcji,
       (SELECT COUNT(*) FROM live l JOIN w.cat_c c USING(payto_lower) WHERE l.last_catalog<>c.last_catalog) AS rozne_last_catalog;

-- =====================================================================
-- HIGIENA: obie bazy zrodlowe otwarte wylacznie ?mode=ro. Zaden wiersz
-- w mapper.db ani payments.db nie jest tworzony, zmieniany ani usuwany.
-- Zapis idzie tylko do /tmp/wi7-census.db. Zero VACUUM (payments.db ma
-- pieczec anchor, patrz project-anchor-seal-txsender-mutable).
-- =====================================================================
