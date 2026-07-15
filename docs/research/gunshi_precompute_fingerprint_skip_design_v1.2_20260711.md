# Precompute L5 高速化設計書 v1.2

作成: 2026-07-11 軍師 | 源流: cmd_3835 Phase4 FAIL + 家老12点差戻し + 将軍v1.1撤回→v1.2待ち
v1.0→v1.1→v1.2: PF単位fingerprint(v1.0)→endpoint群分離(v1.1)→**3案比較+cold path設計**(v1.2)

---

## 0. 問題の本質

日次fullrecalculate(対象workload)でL5=66.64s、目標≤30s。
fingerprint skipだけではcold path 30sを達成できない(v1.1で確定)。
**3案を比較し、cold/warm双方で30sを達成する組合せを選ぶ。**

---

## 1. Baseline実測値(cmd_3835 Phase4)

| 指標 | 値 |
|------|-----|
| L5全体(本番cold) | 66.64s |
| PF render合計 | 58.06s (87.1%) |
| Fixed overhead | 8.58s |
| PF median/p95/max | 0.45s / 1.80s / 2.18s |
| 行数/PF | 15行(8EP×パラメータ) |
| 総行数 | 1533 (102PF × 15) |
| ローカルwarm | 13.21s |
| 旧L5→現L5 | 1659.78s→66.64s (24.9倍改善) |

### visibility PUTによるcache消失(証拠強度: 強い推定)

viewer_tiers.pyのPUT経路がinvalidate_precomputed_rawを呼び全行削除。global PUTは全行対象。Phase4前のprecomputed_raw=0行はこのバグが主因。hotfix 178add2aで除去済み。cmd_3837/3841のoneshotスクリプトはAPI invalidation呼出しゼロ(grep確認)であり直接原因ではない。

---

## 2. logical_dateのendpoint別影響分析(一次コード確認済み)

| EP | logical_date使用 | 日次変化 | 月初変化 | skip可否 |
|---|---|---|---|---|
| monthly_returns | current_ym(月単位) | 同月内不変 | 変化 | ✓月中skip可 |
| annual_returns | YTD判定(年月) | 同月内不変 | 変化 | ✓月中skip可 |
| compare_returns | current_ym(月単位) | 同月内不変 | 変化 | ✓月中skip可 |
| rolling_returns | as_ofメタデータのみ | メタのみ | メタのみ | ✓メタ除外でskip可 |
| drawdowns | as_ofメタデータのみ | メタのみ | メタのみ | ✓メタ除外でskip可 |
| performance | cutoff=today-N×365 | **日次変動** | 変化 | △日次1日差は実質不変だがcutoff行が変わり得る |
| monthly_trade | as_of_date(月次取引) | 同月内不変 | 変化 | ✓月中skip可 |
| signals | signal_preload全行 | **日次新行追加** | 常に変化 | ✗常に再計算 |

**結論**: 月中の日次fullrecalcでは、signals(常時miss)+performance(日次cutoff微変動)以外の6EPは実質不変。

---

## 3. 3案比較表(cmd_3840 §4型式)

### 案A: 既存TTL活用+content-addressable skip

**原理**: precompute_raw_for_portfolios()内でUPSERT前にget_precomputed_raw()を呼び、TTL内(24h)の既存行のraw_json hashと新計算結果のhashを比較。一致→UPSERT skip。

| 項目 | 値 |
|------|-----|
| cold速度 | **66.64s(変わらない)**。全PF計算は必ず走る。skipはUPSERTのみ |
| warm速度 | 66.64s(計算自体をskipしないため効果なし) |
| リスク | 低(既存get_precomputed_rawの延長) |
| 回帰 | DB書込み量減少のみ。計算結果不変 |
| 30s達成 | **✗不可**。計算を省略しないため |
| 判定 | **不採用**。cold pathを改善しない |

### 案B: PF並列化(ThreadPoolExecutor)

**原理**: 102PFの計算を並列実行。現行は直列(1PFずつ15行計算→UPSERT→次PF)。

| 項目 | 値 |
|------|-----|
| cold速度 | 理論値: fixed 8.58 + max(PF elapsed) ≈ 8.58 + 2.18 = **10.76s** |
|  | 実際: DBセッション分離+並列overhead→**15-25s**(推定) |
| warm速度 | cold同等(計算skip機構なし) |
| リスク | 中。DBセッション分離(各threadに独立Session)、RSS増(並列数×50MB推定)、LockedTransaction競合 |
| 回帰 | 計算結果不変(各PF独立)。FoF依存順序は既存toposort維持 |
| 30s達成 | **✓可能性高い**(並列数8-16で) |
| 判定 | **採用順位1(cold path対策)** |

**並列数見込み**:
- workers=8: 102PF÷8=13ラウンド × max(0.45〜2.18) ≈ 13×0.6 = 7.8s + fixed 8.58 = **16.4s** ✓
- workers=16: 102÷16=7ラウンド × 0.6 ≈ 4.2 + 8.58 = **12.8s** ✓
- RSS: 16 workers × 50MB ≈ 800MB。本番Render 1936MB中余裕あり

**FoF依存順序**: 既存のtoposort(standard→fof→nested fof)を維持し、各層内で並列化。層間は直列。

### 案C: Endpoint差分skip(fingerprint, v1.1改良)

**原理**: endpoint別にfingerprint(入力hash)を計算し、前回値と一致→計算skip。

| 項目 | 値 |
|------|-----|
| cold速度 | 初回は全計算(66.64s)。2回目以降=§2の分析に基づきskip |
| warm速度(同日) | signals常時+performance常時+6EP skip: fixed 8.58 + 102×(signals 0.03 + perf 0.15) + fingerprint 1.02 ≈ **28.0s** |
| warm速度(月中日次) | 上記同等(月中は6EP入力不変) |
| warm速度(月初) | 全EP miss = cold ≈ 66.64s |
| リスク | 中。fingerprint計算の正確性(入力漏れ→stale返却) |
| 回帰 | skip hit時の出力=前回計算結果。入力不変なら正しい |
| 30s達成 | **warm: ✓(月中)、cold: ✗** |
| 判定 | **採用順位2(warm path対策、案Bと組合せ)** |

### 組合せ: B+C(推奨)

| workload | 案B効果 | 案C効果 | 組合せ |
|----------|--------|--------|--------|
| cold(初回/月初) | 66.64→**16.4s** | 効果なし | **16.4s** ✓ |
| warm(同日再実行) | 66.64→16.4s | 16.4→skip hit分さらに短縮 | **8-12s** ✓ |
| warm(月中日次) | 66.4→16.4s | signals+perf以外skip→計算量↓ | **10-14s** ✓ |
| 月初(config変更) | 66.64→16.4s | 全miss→案B頼み | **16.4s** ✓ |

**全workloadで≤30s達成。案B単独でも達成するが、案Cを加えることで月中日次のDB書込み量とCPU消費を抑制。**

---

## 4. 家老12点への回答

### (1) 致命: cold path設計

**対策**: 案B(PF並列化)でcold path 16.4s。fingerprint skipは案Cとしてwarm補助。日次fullrecalculateが対象workloadと明記。

### (2) input漏れ: PrecomputeRawContext全14入力のendpoint対応

| 入力 | performance | monthly_returns | annual_returns | rolling | drawdowns | monthly_trade | compare_returns | signals |
|------|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| monthly_return_cache | ✓ | ✓ | ✓(via monthly) | - | ✓ | ✓ | ✓ | - |
| portfolio_preload | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | - | ✓ |
| signal_preload | - | ✓ | ✓ | - | - | ✓ | - | ✓ |
| perf_price_cache | ✓ | - | - | - | - | ✓ | - | - |
| benchmark_cum_cache | - | - | - | - | - | - | - | - |
| shared_business_days | - | - | - | - | - | ✓ | - | - |
| dtb3_cache | - | - | - | - | - | - | - | - |
| rf_map_cache | - | - | - | - | - | - | - | - |
| logical_date | ✓(cutoff) | ✓(current_ym) | ✓(YTD) | ✓(meta) | ✓(meta) | ✓(as_of) | ✓(current_ym) | - |
| rolling_summary_preload | - | - | - | ✓ | - | - | - | - |
| rolling_chart_preload | - | - | - | ✓ | - | - | - | - |
| drawdown_preload | - | - | - | - | ✓ | - | - | - |
| ledger_preload | - | - | - | - | - | ✓ | - | - |
| ledger_oldest_date | - | - | - | - | - | ✓ | - | - |

FoF子PF依存: FoF calculatorはcomponent_portfolios config → 子PF monthly_returnsを内部参照。fingerprint計算時に子PF monthly_return_cacheも含める。

### (3) 順序: REPEATABLE READ snapshot

案B: 各workerがREPEATABLE READ snapshotを取得。全workerが同一snapshot時点のデータで計算。
案C: fingerprint計算はsnapshot後のmaterialized preload値から。TOCTOU禁止。
cmd_3840 manifestと共通: run開始時に1回snapshot→manifest記録→以後はpreload値のみ使用。

### (4) schema

案Bは**schema変更不要**。案Cのfingerprintは既存computed_at列の隣にnullableで追加。
invalidate→NULL化のstale問題(家老指摘): **案Bではinvalidateは現行の行削除を維持**(案Bは計算自体が高速なので再計算コスト小)。案Cのfingerprint列はskip判定のみに使用し、invalidateは行削除のまま(stale返却の仕様退行を回避)。
→ 現行のget_precomputed_raw()のTTL+オンデマンドfallback挙動を完全維持。

### (5) PF skip条件

案C適用時: 同一fingerprintの15キー完全集合(expected_key_set()で検証)かつ全15行のcomputed_atがTTL内。1行でも欠落/expired→全15行再計算。

### (6) global 3行(bulk endpoints)

compare_returns_bulk(1行) + metrics_summary_bulk(2行)はportfolio_id=NULL。
別global fingerprint: 全PFの個別行完了後にbulk再計算。並列化の対象外(全PF完了が前提)。固定費8.58s内に含まれる。

### (7) 部分failure

案B: 各workerの例外は個別catch。失敗PFのみrows未UPSERT、他PFは正常UPSERT。deferred_rows(現行のcontext有時all-or-nothing)は**案Bでは使用しない**(各worker独立commit)。テスト: 1PF injection error→そのPFのみ0行+他101正常を確認。

### (8) 本番P5: 2回実行の回避

案B: schema変更なし→migration不要→現1533行をbaselineに、修正後コードで1回だけfullrecalculate→1533行と比較。2回不要。
同一入力証明: manifest hash(cmd_3840)が前回runと一致していればdata不変を保証。

### (9) fingerprint 0.01s/PF・hit率: 未実測→実測計画

案C: P1実装後に3PF→102PFで以下を実測:
- fingerprint計算コスト/PF
- 昨日→今日のstable群fingerprint一致率(§2の分析を実データで検証)
- skip効果(elapsed差分)

案B: 並列化の実測はP1で直接計測(3PF→10→25→50→102の段階gate)。

### (10) code identity

**git commit hash(production 40hex)を採用**。cmd_3840契約のmanifest方式と一致。
dependency-closure hashは複雑で効果薄(pip freeze hash変更は稀でhit影響なし)。
code変更時は全PF再計算(commit hash変更→fingerprint miss)。

### (11) cmd_3837/3841 script原因説: 撤回

v1.0の記述を撤回。両oneshotスクリプトはDB直接操作でAPI invalidation呼出し0件(grep確認済み)。直接原因にはなれない。手動/FE PUTは強い推定に留める。hotfix後cacheは1533/1533 common・missing0・extra0・mismatch0実測PASS。

### (12) telemetry

| 計測 | 方法 | 通知 |
|------|------|------|
| PF/global hit/miss/reason | precompute完了時にJSON行ログ | logs/precompute_telemetry.yaml |
| fingerprint invalid数 | startup gateでNULL件数表示 | ntfy(>10%時) |
| elapsed(total/per-PF/per-EP) | TIMING SUMMARY(既存拡張) | dashboard_auto_section.sh |
| drift検知 | manifest不一致時 | ntfy+dashboard(cmd_3840 M5統合) |

---

## 5. 実装順序

| Phase | 内容 | 30s貢献 | 依存 |
|-------|------|---------|------|
| P1 | **PF並列化**(案B): ThreadPoolExecutor + 独立Session + toposort層別並列 | cold 66.64→16.4s | なし |
| P1a | git hash定数化(cmd_3840 hotfix): L2343/L2621→_COMMIT_HASH参照 | Stage A 35→3.9s | なし(P1と並列可) |
| P2 | 段階gate (3→10→25→50→102) + 全PF exact parity確認 | 検証 | P1 |
| P3 | **fingerprint skip**(案C): 月中stable群skip + signals常時再計算 | warm 16→10-14s | P2 |
| P4 | telemetry + manifest統合(cmd_3840連携) | 監視 | P3 |
| P5 | 本番1回実行 + baseline比較 | deploy | P4 |

**殿裁定チェックポイント**: P2完了後(並列化の実測値が30s以下であることを確認してから案C着手)。

### 将軍ガイド対応

- (1) 3案比較表: §3に速度+リスク+回帰+採用順位を記載
- (2) fingerprint skipのsame-day warm適用範囲: §3案Cに明記。全捨てではなくwarm補助として残存

---

## 5.5 将軍S1-S4追記(v1.2a)

### S1: 接続数上限

本番Render PostgreSQL接続上限: 97(Starter plan)。
既存消費: uvicorn workers=2 × pool(5+10) = 最大30接続 + cron/ETL(1-2並列) = 最大34接続。
案B workers=8の場合: 各workerは**DBを読まずpreload値のみで計算**し、UPSERT時のみ1接続使用(直列化可)。
→ 追加接続=UPSERT並列数(最大8) + 既存34 = **42接続**。上限97に対して余裕55。
workers上限の根拠: **workers≤16**(16+34=50 < 97の60%安全マージン)。

### S2: GIL/スケールfallback

PF計算はPython支配(pandas/numpy含む)だがI/O wait(DB UPSERT)も含む。
ThreadPoolExecutor: GIL下でもI/O wait中に他threadが進行→混合workloadではスケール可能。
P2実測でスケール不足(workers=8で elapsed > 25s)が確認された場合: **ProcessPoolExecutor(fork=copy-on-write, preloadをpickle不要のshared memory経由で渡す)に切替**。

### S3: snapshot同一性

**workerはDBを読まずrun開始時にmaterialize済みのpreload値のみで計算する**。
precompute_raw_for_portfolios()のcontext引数に全14入力がpreload済み(§4(2)マトリクス参照)。
各workerはcontext内の値だけで計算→DB snapshot差異の問題は発生しない。
UPSERT時のみDBアクセスするが、これは書込みのみでreadしない。

### S4: 部分失敗と完了判定

| 状態 | L5完了判定 | recalc status | 再試行 |
|------|-----------|---------------|--------|
| 全PF成功 | L5_DONE | completed | なし |
| 1+PF失敗 | **L5_PARTIAL** | completed(計算自体は完了) | 失敗PFはfallback cron(02:00)で再試行。etl_trigger経由で個別portfolio_idsを指定 |
| 全PF失敗 | L5_FAIL | failed | 次回fullrecalculate |

L5 fallback cronとの整合: fallback cronはportfolio_ids=Noneで全PF対象。L5_PARTIAL後にfallback cronが走ると失敗PFも再計算される。二重実行は冪等(UPSERT)で安全。

---

## 6. 因果

`[[cmd_3835_Phase4_FAIL_66.64s]] -> [[cold_path設計不在(v1.1)]] -> [[案B並列化+案C fingerprint組合せ]]`

---

## 7. 自己検査(14点全解決確認)

- [x] 家老(1) cold path: 案B並列化で16.4s
- [x] 家老(2) 全14入力endpoint対応: §4(2)マトリクス
- [x] 家老(3) REPEATABLE READ: §4(3)
- [x] 家老(4) schema: 案B=変更なし、案C=nullable追加
- [x] 家老(5) 15キー完全集合: §4(5)
- [x] 家老(6) global 3行: §4(6)
- [x] 家老(7) 部分failure: §4(7) worker独立catch
- [x] 家老(8) 2回回避: §4(8) manifest証明
- [x] 家老(9) 実測計画: §4(9)
- [x] 家老(10) code identity: git commit 40hex
- [x] 家老(11) script原因説撤回: §4(11)
- [x] 家老(12) telemetry: §4(12)
- [x] 将軍(1) 3案比較表: §3
- [x] 将軍(2) fingerprint warm適用範囲: §3案C
- [x] 将軍S1 接続数: §5.5 workers≤16、42/97接続
- [x] 将軍S2 GIL fallback: §5.5 ProcessPool切替1行明記
- [x] 将軍S3 snapshot同一性: §5.5 preload値のみ計算、DB read不要
- [x] 将軍S4 部分失敗: §5.5 L5_PARTIAL+fallback cron整合

帰属整理: P1a(git hash定数化)はcmd_3840系cmdで実施。本設計から除外済み。
