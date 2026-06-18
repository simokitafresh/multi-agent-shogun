# NO_MATCH → 仮Concept 自動生成 設計書
<!-- cmd_3435 Phase1 AC3 | saizo | 2026-06-18 -->
<!-- origin: [[操作的オントロジーPhase1設計]] -> [[provisional_concept_autogen]] -->

## 背景・問題

AC1分析より:
- gitトラッキングファイルの72.5%(874/1205)がconcept未登録
- `[[link]]`参照の99.9%(668/669)が宣言conceptに未到達
- 現在の `queue_no_match_purpose_aliases()` はaliasの**昇格候補**をキューに積むだけ
  → 「仮concept」を生成してグラフに接続する仕組みが存在しない

---

## 設計目標

NO_MATCH発生時に**仮concept(provisional)**を自動生成してindex.mdに挿入し、
- 浮遊[[link]]の一時的な「停留所」として機能させる
- 将来の人間レビューまたは自動昇格条件で正式conceptに昇格させる

---

## トリガー条件

以下の**全条件**を満たした場合に仮concept生成を発動:

| 条件 | 判定方法 |
|------|---------|
| T1: Stage1〜3の全フォールバックで対応concept未発見 | `infer_concepts_from_files()`が空を返す |
| T2: 同じファイルが直近N件のNO_MATCHに累積出現 | `no_match_cumulative_count(fp) >= THRESHOLD` (デフォルトN=3) |
| T3: ファイルパスが意味のあるステムを持つ | ステム長>=4 かつ pure数字ではない |
| T4: 同名の仮conceptが未存在 | `provisional_{stem}`がindex.mdに未登録 |

T2の意図: 単発NO_MATCHでは生成しない。繰り返し参照されるファイルのみ仮concept化。

---

## 仮Concept スキーマ

```markdown
## provisional_{stem} — 仮: {derived_label}

| 属性 | 値 |
|------|---|
| id | provisional_{stem} |
| label | 仮: {derived_label} |
| aliases | {file_stem}, {filepath_normalized}, provisional_{stem} |
| status | provisional |
| auto_generated | true |
| source_cmd | {triggering_cmd_id} |
| source_files | {comma_separated_files} |
| no_match_count | {cumulative_count} |
| created_at | {ISO8601} |
| promotion_threshold | {PROMOTION_THRESHOLD} |
| related_concepts | |

| 種別 | パス/参照 |
|------|----------|
| file | `{filepath}` |
| causal | [[{triggering_cmd_id}]] -> [[provisional_{stem}]] (auto_generated) |
```

### フィールド生成ルール

| フィールド | 生成方法 |
|-----------|---------|
| `stem` | `Path(filepath).stem.lower()` でsnake_case変換 |
| `derived_label` | stemのアンダースコア→スペース変換 + 先頭大文字 |
| `aliases` | stem, filepath正規化形(スラッシュ→スペース), original filepath |
| `source_cmd` | `payload["id"]` (トリガーとなったcmd_id) |
| `no_match_count` | 累積NO_MATCH回数 |

---

## 昇格条件 (provisional → 正式concept)

### 自動昇格 (Auto-Promotion)

以下の**いずれか**を満たした場合、`provisional_{stem}` を正式conceptとして昇格:

| 条件 | 判定 |
|------|------|
| A1: 参照cmds >= 5件 | `source_cmds_count >= 5` |
| A2: related_concepts経由で宣言conceptから到達可能 | グラフトラバーサル深さ<=2 |
| A3: 既存の宣言conceptとaliasが高スコアマッチ | `alias_similarity_score >= 70.0` |

A3の場合は昇格ではなく**既存conceptへのaliasとして吸収**:
```
provisional_{stem} → 既存concept.aliases に stem追加 → provisional削除
```

### 手動昇格 (Manual-Promotion)

家老/軍師が以下を実行:
```bash
bash scripts/semantic_index_update.sh absorb_pending '{}'
# → queue/insights.yaml の provisional候補を処理
```

---

## 既存NO_MATCH計測との統合

### 現状の NO_MATCH 計測

`scripts/semantic_index_update.sh` L817-858:
```python
def recent_no_match_purpose_aliases(path):
    # deploy_task.logから "inject_semantic_concepts: NO_MATCH" を抽出
    # → purpose文字列からaliasを生成してqueueに積む
```

### 統合設計

```python
def handle_no_match_filepath(fp, payload, concepts):
    """
    AC2のStage4から呼ばれる。
    1. no_match_count更新 (logs/no_match_filepaths.yaml)
    2. count >= THRESHOLD → 仮concept生成
    3. 既存queue_no_match_purpose_aliases()も並行実行
    """
    count = increment_no_match_count(fp)  # logs/no_match_filepaths.yaml 更新

    if should_generate_provisional(fp, count, concepts):
        # 仮concept生成
        provisional_id = generate_provisional_concept(fp, payload, concepts)
        print(f"PROVISIONAL_CONCEPT_GENERATED: {provisional_id} for {fp}")

        # insights.yaml に昇格候補として登録
        queue_provisional_insight(provisional_id, fp, payload)

    # 既存の purpose alias候補キューも維持
    queue_no_match_purpose_aliases(concepts)
```

### 新規ファイル: `logs/no_match_filepaths.yaml`

```yaml
# NO_MATCH累積カウンタ。仮concept生成のトリガー閾値管理
no_match_files:
  scripts/some_new_script.sh:
    count: 2
    first_seen: 2026-06-18T19:00:00
    last_seen: 2026-06-18T20:00:00
    source_cmds: [cmd_3435, cmd_3436]
    provisional_generated: false
  context/new_context.md:
    count: 4
    first_seen: 2026-06-17T10:00:00
    last_seen: 2026-06-18T19:00:00
    source_cmds: [cmd_3400, cmd_3410, cmd_3420, cmd_3435]
    provisional_generated: true
    provisional_id: provisional_new_context
```

---

## 仮Concept の index.md 挿入位置

仮conceptは `## semantic_causal_automation` セクションの**直後**に挿入:
- 理由: セマンティックインフラの責務範囲内で管理
- 将来: 正式昇格時に適切なカテゴリセクションに移動

```markdown
## semantic_causal_automation — セマンティック因果自動化
...（既存）

<!-- PROVISIONAL CONCEPTS - auto-generated, pending human review -->
## provisional_new_context — 仮: New Context
...
```

---

## 既存NO_MATCH メトリクスとの対応

| 既存メトリクス | 場所 | 仮concept生成後の変化 |
|-------------|------|---------------------|
| `no_match_pct` | `logs/cmd_design_quality.yaml` | 仮concept生成後に**再計算してpct低下**を記録 |
| `inject_semantic_concepts: NO_MATCH` ログ | `logs/deploy_task.log` | 仮concept生成後は `PROVISIONAL_MATCH` に変更 |
| `queue/insights.yaml` | semantic insights queue | 仮concept昇格候補を追加エントリとして格納 |

---

## フロー全体図

```
cmd_complete イベント
    │
    ▼
AC2: 4段階ファイルパス推論
    │
    ├─ HIGH/MEDIUM match → 宣言concept にカウント
    │
    └─ NO_MATCH → handle_no_match_filepath()
                      │
                      ├─ count < THRESHOLD (3) → カウンタ更新のみ
                      │                          (既存alias候補queue維持)
                      │
                      └─ count >= THRESHOLD
                              │
                              ├─ alias_similarity >= 70 → 既存conceptへ吸収
                              │
                              └─ 仮concept生成 → index.md挿入
                                                    │
                                                    └─ 昇格監視
                                                        ├─ A1: cmds>=5 → 正式concept化
                                                        ├─ A2: 到達可能 → 正式concept化
                                                        └─ A3: 高類似 → 既存吸収
```

---

## 検証方法

```bash
# 新規ファイルでNO_MATCHをシミュレート(3回)
for i in 1 2 3; do
  echo "{\"id\":\"cmd_test_$i\",\"title\":\"test\",\"files\":[\"context/new_unknown_file.md\"]}" \
    | bash scripts/semantic_index_update.sh cmd_complete -
done

# 仮conceptが生成されたか確認
grep "provisional_new_unknown_file" docs/semantic-index/index.md

# NO_MATCHカウンタ確認
cat logs/no_match_filepaths.yaml | grep new_unknown_file
```

---

## 参照

- `scripts/semantic_index_update.sh` L817-858: `queue_no_match_purpose_aliases()` (既存実装)
- `docs/research/saizo_causal_dag_analysis_cmd3435_20260618.md` (背景分析)
- `docs/research/saizo_files_modified_concept_inference_design_cmd3435_20260618.md` (AC2設計)
- `queue/insights.yaml` (昇格候補queue)
