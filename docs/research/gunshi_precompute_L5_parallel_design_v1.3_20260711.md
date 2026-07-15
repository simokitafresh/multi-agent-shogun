# Precompute L5 並列化設計書 v1.3.1

作成: 2026-07-11 軍師 | v1.3の家老A-G指摘を全修正。未決断ゼロ
旧版: v1.3(家老R1-R8+将軍S1-S4統合) → v1.3.1(家老A-G統合)

---

## 0. 骨格(家老確定方針・変更なし)

```
親transaction:
  1. global 3行(compare_returns_bulk+metrics_summary_bulk×2)をDB直接計算+commit(現行通り)
  2. 全14入力+PF ORMをimmutable DTOへmaterialize
  3. workerを起動(pure render: DB read=0, write=0)
  4. 全worker完了
  5. failed=0 → 単一savepoint+bulk UPSERT(all-or-nothing、PF 1530行)
  6. failed>0 → 旧1530行全保持、L5 error記録、再試行対象記録
```

**変更点(v1.3→v1.3.1)**: global 3行はPFループと独立した先行計算(現行precompute_raw.py L451-480の構造維持)。PF行のall-or-nothingスコープは1530行(102PF×15endpoint)。

---

## 1. Baseline(変更なし)

| 指標 | 値 |
|------|-----|
| L5本番cold | 66.64s |
| PF render | 58.06s (87.1%) |
| Fixed | 8.58s |
| PF median/p95/max | 0.45/1.80/2.18s |
| 行数 | 1533 = 1530(PF) + 3(global) |
| Render RSS本番 | 1936.1MB |

---

## 2. 並列アーキテクチャ(R1+F対応)

### 2.1 現行production contextの入力欠落(一次確認済み)

recalculate_fast.py L3091-3101でPrecomputeRawContext生成時に**5入力が未注入**:
- rolling_summary_preload (未注入)
- rolling_chart_preload (未注入)
- drawdown_preload (未注入)
- ledger_preload (未注入)
- ledger_oldest_effective_start_date (未注入)

→ _builders()内の対応calculator(rolling L256, drawdowns L264, monthly_trade L270-276)はこれらがNone→**DB Sessionから直接クエリで取得している**。

### 2.2 immutable DTO materialize

並列化の前提として、**全14入力を親transactionでmaterialize**する必要がある。
context欠落5入力の事前取得を追加:

```python
# 親transactionで全14入力materialize
rolling_summary_preload = _build_rolling_summary_preload(db, portfolios)
rolling_chart_preload = _build_rolling_chart_preload(db, portfolios)
drawdown_preload = _build_drawdown_preload(db, portfolios)
ledger_preload = _build_ledger_preload(db, portfolios)
ledger_oldest = _compute_ledger_oldest(ledger_preload)

context = PrecomputeRawContext(
    # ...既存9入力...
    rolling_summary_preload=rolling_summary_preload,
    rolling_chart_preload=rolling_chart_preload,
    drawdown_preload=drawdown_preload,
    ledger_preload=ledger_preload,
    ledger_oldest_effective_start_date=ledger_oldest,
    logical_date=calc_end_date,
)
```

### 2.3 worker設計

```
worker(pf_id, context_dto) -> list[dict]:
    # DB read=0, DB write=0
    # context_dtoからPF固有入力を抽出
    # _builders()相当のpure計算
    # 15行のraw結果dictを返す
```

- worker-local state: 各workerにcalculator/cacheインスタンスを独立生成
- shared mutable state禁止: profile dict, WARN collector, ORM objectは親→worker転送時にcopy/freeze
- DataFrame mutation: calculator内部で作成→worker内で完結。worker間共有なし

### 2.4 結果収集+UPSERT

```python
all_results = []  # worker結果を収集
failed_pfs = []

for future in futures:
    try:
        rows = future.result()
        all_results.extend(rows)
    except Exception as e:
        failed_pfs.append((pf_id, str(e)))

if not failed_pfs:
    with db.begin_nested():  # 単一savepoint
        _upsert_raw_rows(db, all_results)  # bulk UPSERT 1530行
    db.commit()
else:
    # all-or-nothing: 旧1530行全保持(UPSERT実行しない)
    logger.error("L5 partial failure: %s", failed_pfs)
    # L5_ERROR記録、再試行対象=failed_pfs
```

### 2.5 global 3行の扱い(F対応)

現行コード(precompute_raw.py L451-480)の構造:
```python
# global行: PFループの前に先行計算+先行commit
bulk_raw = build_compare_returns_bulk_raw(db)           # DB直接: PortfolioDB, PrecomputedMtd, Price
metrics_rows = [build_metrics_summary_bulk_raw(db, years=y) for y in [0, 10]]  # DB直接: PortfolioMetrics等
_upsert_raw_rows(db, [bulk_row, *metrics_rows])  # 3行UPSERT
db.commit()  # 先行commit

# PF行: global行の後に実行
_precompute_raw_portfolio_rows(db, portfolios, context=context)
```

**global 3行はPF並列化のスコープ外。** 理由:
1. `build_compare_returns_bulk_raw(db)`は全PFの横断集計(DB Session直接利用必須)
2. `build_metrics_summary_bulk_raw(db)`は全PF metricsの集約(同上)
3. 現行の先行commit構造はPF行のall-or-nothing(失敗時旧PF行保持)と独立しており変更不要

global入力(compare_returns_bulk用):
- PortfolioDB(全active PF)
- PrecomputedMtd(全PF MTD)
- Price(benchmark ticker最新日)
- 各PFのtrailing return(build_compare_returns_trailing_raw→DB直接)

global入力(metrics_summary_bulk用):
- PortfolioMetrics(全PF、years=0/10)
- DB Session直接利用

---

## 3. P0 gate(A/B/C対応): 3PFで正確性+安全性検証

### 3.1 P0の目的再定義(A対応)

**3PFでのspeedup閾値>1.8xは数学的に不可能。**

実測値: fast=0.29s, median=0.45s, slow=2.18s → serial合計=2.92s
- workers=2 ideal: span=max(2.18, 0.29+0.45)=2.18s → speedup=1.34x
- workers=3 ideal: span=2.18s → speedup=1.34x (slow PF支配)

3PFは**スケーリング評価には不適**。3PFの目的は正確性+安全性の検証に限定する。

### 3.2 P0 gate項目(修正版)

| 項目 | 条件 | PASS基準 |
|------|------|----------|
| exact parity | parallel 3PF結果 vs serial 3PF結果 | 45/45完全一致 |
| SELECT count | worker内 | 0件 |
| 決定性 | 同一入力10反復 | payload hash一致10/10 |
| peak RSS | P0実行中 | plan上限×0.85未満 |
| work/span efficiency | observed_speedup / ideal_speedup(LPT) | ≥ 0.7 (GILオーバーヘッド≤30%) |

### 3.3 speedup評価は102PF P2で実施

102PF LPT simulation(実測elapsedプロファイル使用):

| workers | makespan(理想) | speedup(理想) |
|---------|---------------|--------------|
| 2 | 30.6s | 2.0x |
| 3 | 20.5s | 3.0x |
| 4 | 15.4s | 4.0x |
| 6 | 10.3s | 5.9x |
| 8 | 7.8s | 7.8x |

本番目標: PF render ≤ 30s(固定8.58s含めて≤38.6s → 66.64sから42%削減以上)
→ workers=2のLPT理想30.6s+固定8.58s=39.2s、安全margin込みで**workers=3以上が必要**

### 3.4 FAIL条件と次行動(B対応: 灰色帯の一意化)

| P0結果 | 次行動 |
|--------|--------|
| exact<45/45 or SELECT>0 | **STOP**。thread safety契約違反。ProcessPool/設計見直し |
| 決定性<10/10 | **STOP**。mutation race。§4 thread safety監査を再実行 |
| work/span efficiency < 0.5 | **SWITCH**。GIL支配確定。ProcessPool比較設計書を提出(pickle/RSS込み)。即切替禁止 |
| work/span efficiency 0.5-0.7 | **INVESTIGATE**。profiling(cProfile)でGIL競合箇所を特定。報告後判断 |
| work/span efficiency ≥ 0.7 | **PASS**。P1へ進行 |
| peak RSS > plan上限×0.85 | **STOP**。workers数削減またはメモリ最適化 |

### 3.5 P0の循環解消(C対応)

P0は**production entry未接続のexperimental harness**として実装:
```python
# P0 experimental harness (本番パスに接続しない)
def p0_parallel_gate(db, pf_ids_3):
    """P0 gate: serial vs parallel比較。本番呼出元なし。"""
    context = _materialize_full_context(db, pf_ids_3)  # §2.2と同一ロジック
    serial_results = [_render_pf(pf_id, context) for pf_id in pf_ids_3]
    parallel_results = _run_parallel(pf_ids_3, context, workers=3)
    # exact比較、SELECT count、RSS計測
```

P0 PASS後に同一`_render_pf`/`_run_parallel`コードをP1で`precompute_raw_for_portfolios`に統合。

---

## 4. Thread Safety契約(R3対応・変更なし+E追加)

### 4.1 14入力のcopy/share/read-only契約(E対応)

| 入力 | 型 | worker間 | 契約 | mutation test |
|------|------|---------|------|--------------|
| monthly_return_cache | dict[str, list] | **share** | read-only(dictのlist要素はMonthlyReturn ORM→DTO化) | worker内で.append等mutation→AssertionError |
| portfolio_preload | list[PortfolioDTO] | **share** | read-only(ORM→namedtuple/dataclass DTO) | 属性set→frozen dataclass |
| signal_preload | dict[str, list] | **share** | read-only(LazySignalArtifactCacheのDTB3 ref含む) | worker内mutation→AssertionError |
| perf_price_cache | PerfPriceCache | **copy** | worker-local copy(内部にmutable dict) | 元objectと別instance確認 |
| benchmark_cum_cache | dict[str, Series] | **share** | read-only(Seriesはimmutable view化) | .iloc[]= →raises |
| shared_business_days | set[date] | **share** | read-only(frozenset化) | .add()→AttributeError |
| dtb3_cache | DataFrame | **share** | read-only(.flags.writeable=False) | .iloc[0]=→raises |
| rf_map_cache | dict[str, float] | **share** | read-only(MappingProxyType wrap) | __setitem__→TypeError |
| logical_date | date | **share** | immutable(date is immutable) | N/A |
| rolling_summary | dict | **share** | read-only(MappingProxyType) | __setitem__→TypeError |
| rolling_chart | dict | **share** | read-only(MappingProxyType) | __setitem__→TypeError |
| drawdown_preload | dict | **share** | read-only(MappingProxyType) | __setitem__→TypeError |
| ledger_preload | dict | **share** | read-only(MappingProxyType) | __setitem__→TypeError |
| ledger_oldest | date|None | **share** | immutable | N/A |

**share=メモリ共有(GIL下ThreadPoolで安全)。copy=worker-local deepcopy。**

share対象のDataFrame: `.flags.writeable=False`でnumpy配列をread-only化。
share対象のdict: `types.MappingProxyType`でread-only view化。
share対象のORM object: DTO化(namedtuple/frozen dataclass)。lazyload禁止。

### 4.2 mutable state監査(v1.3と同一)

| 対象 | mutable? | 対策 |
|------|----------|------|
| _builders()内calculator | ✓(内部cache dict) | worker-localで独立生成 |
| monthly_family_cache等 | ✓ | worker-localで独立生成 |
| setup_profile dict | ✓ | 親で初期化→workerには渡さない(プロファイルは親で計測) |
| matched_weight_warn_collector | ✓ | worker-local list→完了後に親でmerge(決定的sort順: pf_id→endpoint→params_hash) |
| ORM Portfolio object | ✓(lazyload) | DTO化(id/config/type/name) |
| DataFrame | ✓ | §4.1の契約に従う |

### 4.3 決定性contract

同一3PF、同一detached入力で10反復parallel実行→payload SHA-256が10/10一致。

---

## 5. RSS(R4+D対応)

### 5.1 Render plan上限の確定(D対応)

**P0実行前にRender API一次情報で確定する。**
```bash
# Render API: GET /services/{service_id}
curl -s -H "Authorization: Bearer $RENDER_API_KEY" \
  "https://api.render.com/v1/services/$SERVICE_ID" | jq '.plan, .memoryLimit'
```

確定するまで仮定値を使わない。実plan/memory_limitをworkers式に代入する。

### 5.2 workers上限式

```
workers_max = floor((plan_memory_mb × 0.85 - baseline_rss_mb) / per_worker_rss_mb)
```

| 変数 | 値 | ソース |
|------|-----|--------|
| plan_memory_mb | **P0前にRender APIで確定** | 一次情報 |
| baseline_rss_mb | 1936.1 | cmd_3835本番計測 |
| per_worker_rss_mb | P0で実測 | P0 3PF実行中のRSS増分/workers数 |

例(plan=4096MBの場合): floor((4096×0.85 - 1936) / 50) = floor((3481.6-1936)/50) = floor(30.9) = 30 → **実用上は8-16で十分**

### 5.3 段階gate

P0(3PF)→P2(10→25→50→102)の各段階でpeak RSS実測。
headroom(plan上限×0.85 - peak RSS)が0以下になったら即STOP+workers数削減。

uvicorn 2 workers + API/cron併存のベースライン考慮:
- P0実行時のRSS = uvicorn master RSS + precompute process RSS
- 他uvicorn workerのRSSはps auxで実測しベースラインに含める

---

## 6. 案Cの位置づけ(R5対応・変更なし)

**v1.3.1でも案C(fingerprint skip)の速度主張(10-14s)は撤回維持。**
案CはP2完了後に実測で設計確定:
- 昨日→今日のendpoint別raw_json完全一致率
- as_ofメタデータ除外でのexact parity成立条件
- skip時のmeta patch契約(旧raw_jsonのas_ofを新値に更新して完全一致とする)

P3設計はP2実測データに基づく。P2前の案C速度予測は全て仮説扱い。

---

## 7. 入力依存matrix(R6+F対応)

### 7.1 PF個別行(15 endpoint × 102 PF = 1530行)の入力matrix

| 入力 | perf | mr | ar | roll | dd | mt | comp | sig |
|------|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| monthly_return_cache | ✓ | ✓ | ✓ | - | ✓ | ✓ | ✓ | - |
| portfolio_preload | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | - | ✓ |
| signal_preload | - | ✓ | ✓ | - | - | ✓ | - | ✓ |
| perf_price_cache | ✓ | - | - | - | - | ✓ | - | - |
| benchmark_cum_cache | - | - | - | - | - | - | - | - |
| shared_business_days | - | - | - | - | - | ✓ | - | - |
| dtb3_cache | - | - | - | - | - | - | - | - |
| rf_map_cache | - | - | - | - | - | - | - | - |
| logical_date | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | - |
| rolling_summary | - | - | - | ✓ | - | - | - | - |
| rolling_chart | - | - | - | ✓ | - | - | - | - |
| drawdown_preload | - | - | - | - | ✓ | - | - | - |
| ledger_preload | - | - | - | - | - | ✓ | - | - |
| ledger_oldest | - | - | - | - | - | ✓ | - | - |
| FoF子PF closure | - | ✓ | ✓ | - | - | - | - | - |

### 7.2 global 3行(compare_returns_bulk×1 + metrics_summary_bulk×2)の入力

| 入力 | compare_returns_bulk | metrics_summary_bulk |
|------|:---:|:---:|
| PortfolioDB(全active) | ✓ | - |
| PrecomputedMtd(全PF) | ✓ | - |
| Price(benchmark最新日) | ✓ | - |
| 各PFのtrailing return(DB) | ✓ | - |
| 各PFのMTD data(DB or cache) | ✓ | - |
| PortfolioMetrics(全PF) | - | ✓ |
| benchmark ticker monthly rows | - | ✓ |

**global 3行はDB Session直接利用が必須**。PF並列化スコープ外。
現行の先行計算+先行commit構造(precompute_raw.py L451-480)を維持。

### 7.3 v1.3のmatrix誤り訂正(F対応)

v1.3の§7でcomp_bulk/met_bulk列をPF個別行matrixに混在させていたのは誤り。
- `compare_returns_bulk`と`metrics_summary_bulk`はPF個別endpoint(`performance`等)とは別の計算パス
- 入力もDB Session直接クエリであり、14入力materializeの対象外
- v1.3.1では§7.1(PF行)と§7.2(global行)を分離

---

## 8. P5同一入力証明(R7+G対応)

現1533行にmanifestは存在しない。したがって「前回manifest一致で保証」は使えない。

**正本証明方法**:
1. P2で**frozen production fixture**(本番DB snapshotの全14入力をJSON退避)を作成
2. 同一fixtureでserial reference(現行コード直列)→1530行(PF)+3行(global)=**1533行**
3. 同一fixtureでparallel candidate(修正後コード並列)→1530行(PF)+3行(global)=**1533行**
4. **全1533行のraw_json exact一致**を証明(PF 1530行 + global 3行)
5. global 3行: 並列化前後でコードパス変更なし→exact一致は自明だが、回帰防止として検証に含める

P5本番では: parallel実行→新1533行のendpoint/portfolio_id/params_hash完全集合を検証。
「前回値との一致」は保証不能(logical_dateが異なるため)。

---

## 9. 実装順序(R8対応)

| Phase | 内容 | 依存 |
|-------|------|------|
| **P0** | experimental harness: serial vs workers2/3、exact45/45、SELECT0、10反復決定性、peak RSS、work/span efficiency | Render API plan確認 |
| **P1** | PF並列化: immutable DTO materialize+worker pure render+親bulk UPSERT | P0 PASS |
| **P2** | 段階gate: 10→25→50→102 + frozen fixture exact parity(**1533/1533**) | P1 |
| **P3** | fingerprint skip(設計はP2実測後に確定) | P2 |
| **P4** | telemetry+manifest統合 | P3 |
| **P5** | 本番1回実行+集合完全性検証 | P4 |

殿裁定CP: P2後の構成確定時(並列化の実測speedupとRSSが許容範囲であることを確認後)。
P1a(git hash定数化): 本設計から削除。cmd_3840系cmdで実施。

---

## 10. 部分失敗(R1/S4統合・PFスコープ明確化)

| 状態 | L5判定 | PF 1530行 | global 3行 | recalc status | 再試行 |
|------|--------|---------|-----------|---------------|--------|
| 全PF成功 | L5_DONE | 新1530行でUPSERT | 先行commit済み(変更なし) | completed | なし |
| 1+PF失敗 | **L5_ERROR** | **旧1530行全保持** | 先行commit済み(影響なし) | completed | failed PFを記録→fallback cron or 手動etl_trigger |
| global失敗 | L5_ERROR | PFループ実行しない | 旧3行保持 | completed | 次回fullrecalculate |

all-or-nothingスコープ = PF 1530行。global 3行は独立transaction(現行構造維持)。

---

## 11. Telemetry(変更なし)

| 計測 | 方法 | 通知 |
|------|------|------|
| PF/global hit/miss/reason | JSON行ログ | logs/precompute_telemetry.yaml |
| elapsed(total/per-PF/serial-vs-parallel) | TIMING SUMMARY | dashboard |
| peak RSS | P0/P2各stageで記録 | ntfy(plan上限80%超時) |
| failed PFs | L5_ERROR時 | ntfy+dashboard |

---

## 12. 因果

`[[cmd_3835_Phase4_FAIL_66.64s]] -> [[v1.2欠陥(context5入力欠落/RSS算術/GIL未証明)]] -> [[v1.3 pure_render並列+P0実測gate]] -> [[v1.3.1 P0数学的修正+immutable契約+global分離]]`

---

## 13. 自己検査

### v1.3家老A-G全解決:
- [x] A: P0 speedup>1.8x撤回。3PF=正確性+安全性。speedupは102PF P2で評価。work/span efficiencyで3PFのGILオーバーヘッドを計測
- [x] B: FAIL/INVESTIGATE/SWITCH/PASSの4状態+次行動を一意化。灰色帯なし
- [x] C: P0=experimental harness(production entry未接続)。PASS後P1で統合
- [x] D: Render API一次情報でplan確定を明記。仮定値使用禁止
- [x] E: 14入力のcopy/share/read-only契約表+mutation test定義
- [x] F: global 3行をPF matrixから分離。compare_returns_bulk/metrics_summary_bulkの入力を別表で明記。現行先行commit構造維持
- [x] G: P2 exactは1533/1533(PF 1530 + global 3)を明記

### v1.3由来(家老R1-R8+将軍S1-S4): 全維持
- [x] R1-R8: v1.3の解決を全維持
- [x] S1-S4: v1.3の解決を全維持

### セルフレビュー3点:
1. **数値検算**: 3PF speedup理想値=1.34x(Python計算で実測検証済み)。102PF LPT simulation(workers=2:2.0x, 3:3.0x, 4:4.0x, 6:5.9x, 8:7.8x)もPython計算で実測。1533=1530+3はprecompute_raw.py L460-467で一次確認
2. **前提検証**: global行の構造をprecompute_raw.py L451-480で一次確認(build_compare_returns_bulk_raw+build_metrics_summary_bulk_raw+先行commit)。14入力の型はPrecomputeRawContext dataclass定義で確認
3. **事前検死**: 忍者詰まりポイント=(a)Render API確認の認証(→.env RENDER_API_KEY使用、手順明記) (b)immutable化の具体実装(→§4.1で型別手段明記) (c)P0 experimental harnessの配置(→tests/またはscripts/benchmarks/に配置、importパス明記が必要→P0実装cmd側で指定)

### 未決断: **ゼロ**
