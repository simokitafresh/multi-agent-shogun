# Precompute L5 Fingerprint Skip 設計書 v1.1

作成: 2026-07-11 軍師 | 源流: cmd_3835 Phase4 FAIL(66.64s, 目標30s未達) + 家老research_request
v1.1: 将軍R1-R5対応(endpoint単位fingerprint、signal EP除外、stale契約明記、telemetry追加)

---

## 0. 一言でいうと

fullrecalculate時のL5(precompute_raw)を**入力が変わっていないendpointはスキップ**して30秒以下にする。
現行66.64sのうちPF render=58.06s(87.1%)が支配的。

**v1.1重要変更(R1対応)**: signals EPは日次で新行が追加されるため**常に再計算(skip対象外)**。
他7EP(performance/monthly_returns/annual_returns/rolling_returns/drawdowns/monthly_trade/compare_returns_trailing)はmonthly_returns+config hashで安定→skip対象。
signals 1行/PFの計算コストは全体の7%(実測推定)で、7EP skip効果が支配的。

---

## 1. Baseline実測値(cmd_3835 Phase4)

| 指標 | 値 | 出典 |
|------|-----|------|
| L5全体(本番cold) | 66.64s | Render log rows=1533 |
| PF render合計 | 58.06s (87.1%) | PF別102 elapsed合計 |
| Fixed overhead | 8.58s | 66.64 - 58.06 |
| PF median | 0.45s | PF別elapsed |
| PF p95 | 1.80s | PF別elapsed |
| PF max | 2.18s | PF別elapsed |
| 行数/PF | 15行(8EP×パラメータ) | expected_key_set() |
| 総行数 | 1533 (102PF × 15) | DB実測 |
| L5目標 | ≤30s | 設計書v1.2 |
| ローカルwarm | 13.21s | cmd_3835 |
| 旧L5 | 1659.78s→66.64s (24.9倍改善) | cmd_3825→3835 |

### visibility PUTによるcache消失(証拠強度: 強い推定)

cmd_3837/3841期間(2026-07-10 20:45〜01:00)にviewer_tiers.pyのupdate_tier/global_visibility PUTがinvalidate_precomputed_rawを呼び、可視性非依存のraw cacheを含む全行を削除した。global PUTは全行削除(行407-426)。Phase4実行前のprecomputed_raw=0行はこのバグが直接原因(時刻ログ未捕捉のため強い推定)。hotfix 178add2aでinvalidateを両PUTから除去済み。

---

## 2. 必須決定9項目

### (1) Fingerprintに含む全入力

cmd_3840設計§7.1 manifestと共通化(二重SSOT禁止)。canonical SHA-256。

| カテゴリ | 入力 | hash方法 | 根拠行 |
|----------|------|----------|--------|
| PF config | config JSON (name/type含む) | SHA-256(canonical json.dumps sort_keys) | precompute_raw.py:459 portfolio_preload |
| monthly_returns | PF別monthly_return rows | SHA-256(date+value concat) | precompute_raw.py:287 monthly_return_cache |
| signals+ledger | PF別signal rows + ledger state | SHA-256(date+signal+holding_signal) | precompute_raw.py:351 signal_preload |
| trade/drawdown等 | 上記から派生(独立入力なし) | PF config+monthly_returns hashで十分 | 各calculator内部 |
| logical_date | 基準日付 | ISO文字列 | precompute_raw.py:529 |
| PRECOMPUTE_PARAMS | 全endpoint×params | SHA-256(json.dumps) | precompute_raw.py:83-102 |
| code identity | source file hash or git commit | cmd_3840 manifest方式(_COMMIT_HASH) | recalculate_fast.py:365 |

**composite fingerprint** = SHA-256(config_hash + mr_hash + signal_hash + logical_date + params_hash + code_hash)

### (2) PF単位 vs endpoint単位 + 計算量

**推奨: endpoint群単位(2グループ)** (v1.1 R1対応で変更)

| グループ | endpoint | skip判定 | 理由 |
|----------|----------|----------|------|
| stable群(7EP) | performance, monthly_returns, annual_returns, rolling_returns, drawdowns, monthly_trade, compare_returns_trailing | config+mr hashで判定 | 月次周期で安定。日次先端は月中変化なし |
| volatile群(1EP) | signals | **常に再計算** | 日次で新signal行が追加されhash変化。skip不可 |

- stable群は同一入力(config+monthly_returns)を共有→PF×stable群で1 fingerprint
- signals EPは1行/PFで計算コスト軽微(全体の7%推定)
- 計算量: 102 SHA-256(config+mr) + 102×signals再計算 = fixed + 102×0.03s ≈ 3.1s追加
- skip効果: stable群14行/PF × 102PF × median 0.42s/行 ≈ **43.5s節約**

### (3) 保存先schema/migration/unique key

PrecomputedRawに**fingerprint列を追加**:

```sql
ALTER TABLE precomputed_raw ADD COLUMN input_fingerprint VARCHAR(64);
CREATE INDEX idx_precomp_raw_fingerprint ON precomputed_raw (portfolio_id, input_fingerprint);
```

- unique keyは既存(endpoint, portfolio_id, params_hash)を維持
- fingerprintはPF単位で全15行に同一値を格納(冗長だが1 JOIN不要で高速)
- migration: nullable追加→backfill→NOT NULL化の2段階

### (4) recalc内snapshot整合とcmd_3840 manifest統合

**manifest = fingerprint SSOT**。二重SSOT禁止。

- run開始時にmanifest(cmd_3840設計)を1回計算
- manifestのPF別hashをそのままfingerprint値として使用
- precompute_raw_for_portfolios()のcontext引数にmanifest_hashesを追加:
  ```python
  context = PrecomputeRawContext(
      ...,
      manifest_hashes: dict[str, str] | None = None,  # {portfolio_id: fingerprint}
  )
  ```
- snapshot整合: manifest計算後にDB snapshot取得(既存のpreload経路)→以降は全てpreload値を使用→並行更新はmanifest不一致で検知

### (5) Cache hit/miss/failure時のatomicity・stale保持

| 状態 | 動作 | 根拠 |
|------|------|------|
| hit (fingerprint一致) | skip計算、既存raw_json保持 | 入力不変=出力不変 |
| miss (fingerprint不一致) | 全15行再計算→UPSERT+fingerprint更新 | 入力変更=再計算必須 |
| failure (計算エラー) | **stale保持**(旧raw_json残存、fingerprint更新なし) | fail-closed: 古い正しいデータ > エラー後の空 |
| miss (fingerprint NULL=初回) | 全計算→UPSERT+fingerprint設定 | migration直後 |

atomicity: 既存のdeferred_rows+savepoint(行640-665)を維持。fingerprint更新はraw_json UPSERTと同一transaction。

### (6) 既存invalidate全callerの新契約

| caller | 現行動作 | 新契約 |
|--------|---------|--------|
| folders.py:28 | signals/compare_returns/bulk削除 | **削除→fingerprint NULL化**に変更(再計算を強制するがstale row保持) |
| metrics.py:158 | metrics_summary_bulk削除 | 同上 |
| portfolios.py:336 | 変更PF+bulk削除 | 同上 |
| precompute_raw.py:466 | bulk削除 | 同上 |
| portfolio_metrics.py:73 | metrics_summary_bulk削除 | 同上 |
| ~~viewer_tiers.py~~ | ~~全行削除~~ | **178add2aで除去済み** |

**原則**: invalidateは行削除ではなくfingerprint NULL化。これにより:
- stale data保持(API応答可)
- 次回precompute時に全PF再計算(fingerprint=NULL→miss)
- visibility PUTバグ(全行消失)の再発防止

### (7) cold/warm双方の段階gate

| ステージ | PF数 | warm目標 | cold制約 |
|----------|------|----------|----------|
| 3PF | 3 | fingerprint込み≤1s | N/A |
| 10PF | 10 | ≤3s | N/A |
| 25PF | 25 | ≤8s | N/A |
| 50PF | 50 | ≤15s | N/A |
| 102PF(全量) | 102 | **≤30s** | 66.64sを悪化させない |

warm 30s達成見込み:
- skip hit率90%(月次でconfig/signal変更は〜10PF): fixed 8.58 + 10PF×0.45 + fingerprint計算102×0.01 ≈ **14.1s** ✓
- skip hit率70%: fixed 8.58 + 30PF×0.45 + 1.02 ≈ **23.1s** ✓
- skip hit率50%: fixed 8.58 + 51PF×0.45 + 1.02 ≈ **32.6s** ✗(ギリギリ)
- skip hit率0%(cold): 8.58 + 102×0.45 + 1.02 ≈ **55.5s**(66.64より改善、cold制約OK)

### (8) Exact tests

| テスト | 内容 | 判定 |
|--------|------|------|
| changed_1pf | 1PFのconfig変更→そのPFのみ再計算、残101 skip | exact parity |
| all_pf_miss | fingerprint全NULL→102PF全計算 | exact parity(cold相当) |
| input_same | 2回連続実行→2回目は102 skip | exact parity + skip=102 |
| code_change | _COMMIT_HASH変更→全PF再計算 | exact parity |
| logical_date_change | logical_date変更→全PF再計算 | exact parity |
| partial_failure | 1PF計算エラー→そのPFのfingerprint未更新、他101正常 | stale保持 |

### (9) Production一発前の凍結比較方法

1. 本番でfullrecalculate実行(修正前コード)→precomputed_raw全1533行をJSON退避
2. 修正後コードでfullrecalculate実行→precomputed_raw全1533行を取得
3. raw_json値の完全一致を全行で確認(JSONable_encoderの正規化込み)
4. fingerprint列が全PFに設定されていることを確認
5. skip count = 0(初回は全計算)を確認

---

## 3. 実装順序

| Phase | 内容 | 依存 |
|-------|------|------|
| P0 | migration: input_fingerprint列追加(nullable) | なし |
| P1 | fingerprint計算+skip判定をprecompute_raw_for_portfoliosに実装 | P0 |
| P2 | invalidateをfingerprint NULL化に変更(5箇所) | P1 |
| P3 | exact tests 6件 | P1+P2 |
| P4 | 段階gate (3→10→25→50→102) | P3 |
| P5 | 本番凍結比較+deploy | P4 |

**殿裁定チェックポイント**: P2完了後(invalidate契約変更)に殿へ設計判断を確認。

---

## 4. 因果

`[[cmd_3835_Phase4_FAIL_66.64s]] -> [[PF_render_87.1%が支配的]] -> [[入力不変PF_skip_fingerprint設計]]`

---

## 5. 自己検査(家老追加条件)

- [x] cmd_3840 manifest共通化: §2(4)でmanifest=fingerprint SSOTと明記。二重SSOT禁止
- [x] 178add2a後のcache消失説明: §1末尾に証拠強度付き1文
- [x] baseline記録: §1に旧1659.78→66.64(24.9倍)、PF render58.06、fixed8.58、median/p95/max
- [x] skip hit率別<=30達成見込み: §2(7)に90%=14.1s/70%=23.1s/50%=32.6s算出

---

## 6. 将軍R1-R5対応(v1.1)

### R1(重大・hit率前提崩壊): RESOLVED

signals EPは日次で新行追加→全行hashでは毎日miss。**対策: signals EPをskip対象外とし常に再計算**。
他7EPはmonthly_returns+config依存で月次周期安定。§2(2)をendpoint群単位に変更。

v1.1 hit率再試算(stable群7EP × 14行/PFのみ対象):
- stable群skip率90%(月次config変更〜10PF): fixed 8.58 + signals全PF 3.1 + 10PF×14行×0.03 + fingerprint 1.02 ≈ **17.0s** ✓
- stable群skip率50%: 8.58 + 3.1 + 51×14×0.03 + 1.02 ≈ **34.1s** ✗(50%以上必要)
- 前提確定のための実測: P1実装前に3PFで「昨日→今日のstable群fingerprint一致率」を実測。1行スクリプトで確認可能

### R2(スコープ分離): RESOLVED

P0のALTER TABLE(precomputed_raw.input_fingerprint追加)はcmd_3840 AC7(recalculate系schema migration 0)と別スコープ。
- cmd_3840: recalculate_fast.pyの計算ロジック変更でschema変更を伴わない
- 本設計: precomputed_rawキャッシュ層への列追加。計算ロジック不変
両設計書に「precomputed_raw列追加はL5キャッシュ層の変更であり、recalculate計算schema migration 0の対象外」と明記

### R3(stale契約): RESOLVED

| 状態 | API挙動(現行) | NULL化後のAPI挙動 | 契約 |
|------|-------------|-----------------|------|
| 行あり+fresh | cached raw_json返却 | 同左 | 変更なし |
| 行なし(削除後) | **get_precomputed_raw()→None→オンデマンドfallback計算** | N/A(行は削除しない) | 行削除を廃止 |
| 行あり+fingerprint NULL | N/A(現行なし) | **cached raw_json返却(stale)**+次回precompute時に再計算 | stale許容: 値は前回計算時の正しい結果。次回fullrecalculate(最大24h以内)で更新 |

stale許容条件: fullrecalculateが日次cron(02:00 JST)+L3成功後enqueueで最大24h以内に再計算される。admin設定変更→即時反映が必要な場合はinvalidate後にprecompute_raw_for_portfolios()を明示呼出し(etl_trigger経由)。

### R4(NOT NULL化不要): ACCEPTED

NULL=missで動作するためNOT NULL制約は追加しない。migration 1段階のみ。

### R5(telemetry): RESOLVED

| 計測 | 方法 | 通知先 |
|------|------|--------|
| skip率 | precompute完了時にskip/total/elapsed_msをlogs/precompute_telemetry.yamlに記録 | dashboard_auto_section.sh |
| fingerprint状態 | PF別fingerprint NULL件数をstartup gateで表示 | ntfy(NULL>10%時) |
| drift検知(M5統合) | manifest不一致時にntfy+dashboard | cmd_3840設計§5.5と共通経路 |
