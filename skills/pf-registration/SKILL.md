---
name: pf-registration
argument-hint: "[pf_type] [pf_id]"
description: |
  本番PF登録の全ステップを構造的に実行し、各ステップ後にパリティ検証を強制するスキル。
  忍者がステップ順序を飛ばせず、パリティFAIL時は即停止する。
  チェックリスト(checklist-shin-v2-registration.md / checklist-alm-registration.md)に基づく。
  TRIGGER: /pf-registration、本番登録、PF登録、シン四神登録、忍法登録、ALM登録
  DO NOT TRIGGER: GS実行（→run_077直接実行）、偵察（→偵察cmd）、fullrecalculate（→API直接実行）
quality_metric: "当該スキル使用タスクのWA不発生率（logs/karo_workarounds.yamlにPF登録順序・パリティ確認起因のworkaroundが記録されない割合）"
---

# /pf-registration — 本番PF登録スキル

本番PF登録をステップ順に実行し、各ステップ後にパリティ検証を強制する。
「fullrecalcの後でまとめて確認」は禁止。各ステップ直後に即パリティ。

## 根本原則

> **本番を変更したら即パリティ。** 想像するな確認せよ、の本番操作版。
> DB登録後に「あとで確認」は禁止(cmd_1770三重事故: DB登録→パリティ未確認→コード未デプロイ+偽signal+ユーザー丸見え)。

---

## 事前準備

### Step 0: チェックリスト特定

タスクYAMLのproject/purposeから登録タイプを判定し、対応するチェックリストを読む。

```
シン四神/シン忍法 → context/checklist-shin-v2-registration.md
ALM四神/ALM忍法  → context/checklist-alm-registration.md
秘奥義/奥義      → checklist-shin-v2-registration.md §Step 8-9を参照
```

チェックリストを全文読んでからStep 1に進め。途中から始めるな。

---

## 実行フロー

### Phase 1: 清掃(Step 0)

汚染データがあれば削除する。

1. 対象PFの現在状態をDB確認: `SELECT id, name, type FROM portfolios WHERE name LIKE '%対象%'`
2. 汚染PF(パリティFAIL状態)があれば削除(FoF先→standard後の順序制約)
3. 削除後のDB確認: 対象が0体であること

**検証**: `SELECT COUNT(*) FROM portfolios WHERE name LIKE '%対象%'` = 0
**FAIL時**: 停止。削除失敗の原因を報告

---

### Phase 2: パリティ土台(Step 1-2)

#### Step 1: Standard PFパリティ
GSの計算結果が本番DBと完全一致するか検証。

```bash
# パリティ検証ツールで自動突合(PF名 or UUID指定)
bash scripts/parity_check.sh <PF名 or UUID>
# 全PF一括の場合:
bash scripts/parity_check.sh --all
```

**検証基準**: holding_signal完全一致 AND monthly_return完全一致
**FAIL時**: 即停止。不一致の月・フィールドを報告。修正なしに先に進むな

#### Step 2: 既存FoFパリティ(Phase A→G)
忍法スクリプトを既存FoFと同じ設定で実行し、出力が本番と完全一致するか検証。
Phase A(EqualWeight)から順にPhase G(ネステッド)まで、1 Phaseずつ進む。

**各Phase後の必須アクション**:
1. 結果をチェックリストに記録(PASS/FAIL + 月数 + 一致数)
2. FAILなら即停止。知見を抽出し報告
3. PASSなら次のPhaseへ

---

### Phase 3: 登録(Step 3-6)

#### Step 3: GS探索→チャンピオン選定
チェックリスト記載のGSコマンドを実行。

#### Step 4: チャンピオン登録(DB INSERT)
```bash
# 登録後に即パリティ(★最重要)
# SELECT で登録確認 → holding_signal + monthly_return 突合
```

**即パリティ**: 登録直後にholding_signal + monthly_returnを本番DBと突合。
「fullrecalculateの後でまとめて」は禁止。

#### Step 5: fullrecalculate実行
```bash
curl -X POST https://dm-signal-backend.onrender.com/admin/recalculate-sync \
  -u "$ADMIN_USER:$ADMIN_PASS"
```
完了確認: recalculation_status DB行で二重確認(L690)

#### Step 6: fullrecalculate後パリティ
全登録PFのholding_signal + monthly_returnを再突合。
fullrecalculate前後で値が変わっていないことを確認。

---

### Phase 4: FoF構築(Step 7-8)

#### Step 7: 忍法スクリプト実行→FoF登録
忍法スクリプト(run_077_*.py)でFoFを構築し、DB登録。

**各忍法登録後に即パリティ**:
- holding_signal完全一致
- monthly_return完全一致
- component_weights存在確認(fof_component_weightsテーブル)

#### Step 8: 秘奥義/奥義登録(該当する場合)
L2/L3のFoF登録。Step 7と同じ即パリティ手順。

---

### Phase 5: 最終検証(Step 9)

#### Step 9: 3レイヤー貫通確認
1. **DB**: 全登録PFのsignal/monthly_return/component_weights存在
2. **API**: `GET /api/signals/{portfolio_id}` で応答確認
3. **FE**: Dashboard/Monthly Tradeで表示確認(可能な場合)

---

## パリティ検証の実行方法

```python
# 共通パリティチェックパターン
# 1. holding_signal突合
SELECT date, holding_signal FROM signals WHERE portfolio_id = '{pf_id}' ORDER BY date

# 2. monthly_return突合
SELECT date, return_value FROM monthly_returns WHERE portfolio_id = '{pf_id}' ORDER BY date

# 3. 比較: GS出力 vs DB値 → 完全一致(許容誤差ゼロ)
```

NULL行は比較対象から除外する(L699)。
FoFのholding_signal同一判定は展開後ticker×weightで行う(L703)。

---

## FAIL時の手順

1. **即停止** — 次のステップに進むな
2. **不一致の詳細記録** — どの月、どのフィールド、どの値が異なるか
3. **報告** — task YAMLのprogressに記録し、家老に報告
4. **修正** — 修正は別cmdで対応。修正後にFAILしたステップからやり直し

---

## 制約

- チェックリスト(context/checklist-*.md)が正本。このスキルは実行手順のみ
- パリティ検証の許容誤差はゼロ(IEEE 754ノイズ=1e-12のみ許容: L392)
- FoF削除順序: FoF先→standard後(FK制約)
- Portfolio直下top_nを構成数に使うな(L696)。pipeline_config内側のみ
- DB操作は直列(並列タイムアウト実証済み)
