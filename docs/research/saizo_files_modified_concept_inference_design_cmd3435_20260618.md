# files_modified → Concept 因果辺 自動推論ロジック 設計書
<!-- cmd_3435 Phase1 AC2 | saizo | 2026-06-18 -->
<!-- origin: [[操作的オントロジーPhase1設計]] -> [[files_modified_concept_inference]] -->

## 背景・問題

AC1分析より: `semantic_index_update.sh` の `cmd_complete` イベント処理で
`files_modified` (ファイルパス配列) → 対応conceptの推論が**テキストマッチング主体**。
- 現状: `score_concept(concept, fields)` がcmd title/purposeとaliasの文字列一致で判定
- 問題: ファイルパス自体をconceptへ直接マッピングするロジックが存在しない
- 結果: `scripts/lesson_write.sh` を変更したcmdが `lesson_lifecycle` conceptに接続されない

---

## 設計目標

`files_modified` に含まれるファイルパスから、対応する宣言conceptを**高精度に推論**し、
`| causal |` エントリを自動生成して [[link]] の浮遊ノード問題を解消する。

---

## 入力 / 出力 / 接続点

### 入力

```json
{
  "id": "cmd_3435",
  "title": "因果辺DAG分析",
  "purpose": "オントロジー記事知見の三層記憶適用",
  "files": [
    "docs/research/saizo_causal_dag_analysis_cmd3435_20260618.md",
    "docs/semantic-index/index.md"
  ],
  "origin": "[[殿指示_オントロジー記事_20260618]] -> [[操作的オントロジーPhase1設計]]"
}
```

### 出力

```
| causal | `cmd_3435` files_modified: [[semantic_causal_automation]][[operational_ontology]] |
```

追加: `cmd_complete` イベント処理時に `| file |` エントリも自動追記

```
| file | `docs/research/saizo_causal_dag_analysis_cmd3435_20260618.md` |
```

### 接続点 (既存スクリプト)

| スクリプト | 接続方式 |
|-----------|---------|
| `scripts/semantic_index_update.sh` | Python埋込み内の`score_concept`関数を拡張 |
| `scripts/cmd_complete_gate.sh` | `--semantic-update`フラグ経由でpayload渡し |
| `scripts/deploy_task.sh` | `files_modified`フィールドをpayloadに含める |

---

## 推論アルゴリズム (4段階フォールバック)

### Stage 1: 直接ルックアップ (O(1), 精度=確実)

index.md解析時に `file → concept set` 逆引きマップを構築:

```python
file_concept_map = {}   # path → set[concept_id]

for concept in concepts:
    for line in concept["block"].splitlines():
        if line.startswith("| file |"):
            fp = extract_backtick_path(line)
            if fp:
                file_concept_map.setdefault(fp, set()).add(concept["id"])
        elif line.startswith("| cmd |"):
            # (file1, file2) 形式のfiles_modifiedも収集
            for fp in extract_parens_files(line):
                file_concept_map.setdefault(fp, set()).add(concept["id"])
```

ファイルパスが完全一致 → 対応conceptを**HIGH信頼度**で返す。

### Stage 2: ディレクトリプレフィックス推論 (精度=中)

AC1分析で判明した`| file |`パスの分布からディレクトリ→conceptパターンを定義:

```python
DIR_PREFIX_MAP = [
    # (正規表現パターン, concept_id, confidence)
    (r"^scripts/gates/",            "gate_quality_framework",      "MEDIUM"),
    (r"^scripts/hooks/",            "hook_automation_framework",   "MEDIUM"),
    (r"^scripts/lesson_",           "lesson_lifecycle",            "HIGH"),
    (r"^scripts/inbox_",            "inbox_processing_discipline", "HIGH"),
    (r"^scripts/inbox_watcher",     "inbox_watcher_process_model", "HIGH"),
    (r"^scripts/semantic_",         "semantic_causal_automation",  "HIGH"),
    (r"^scripts/memory_db_",        "local_memory_db",             "HIGH"),
    (r"^scripts/obsidian_",         "three_layer_memory_system",   "MEDIUM"),
    (r"^scripts/deploy_task\.sh",   "agent_formation_management",  "HIGH"),
    (r"^scripts/ninja_monitor",     "daemon_supervision",          "HIGH"),
    (r"^scripts/cmd_save",          "cmd_quality_logging",         "HIGH"),
    (r"^scripts/cmd_complete_gate", "gate_quality_framework",      "HIGH"),
    (r"^scripts/report_field_set",  "report_quality_protocol",     "HIGH"),
    (r"^context/dm-signal",         "dmsignal_operations",         "MEDIUM"),
    (r"^context/growth-loop",       "growth_loop",                 "HIGH"),
    (r"^context/infrastructure",    "infrastructure_ops",          "HIGH"),
    (r"^context/memory-db",         "local_memory_db",             "HIGH"),
    (r"^context/training-cycle",    "training_cycle_quality",      "MEDIUM"),
    (r"^context/semantic-map",      "semantic_causal_automation",  "HIGH"),
    (r"^docs/semantic-index/",      "semantic_causal_automation",  "HIGH"),
    (r"^docs/research/gunshi_",     "semantic_causal_automation",  "LOW"),
    (r"^docs/research/",            None,                          "LOW"),  # → Stage3へ
    (r"^tests/unit/test_semantic",  "semantic_causal_automation",  "MEDIUM"),
    (r"^tests/unit/test_cmd_",      "cmd_quality_logging",         "MEDIUM"),
    (r"^tests/unit/test_memory",    "local_memory_db",             "MEDIUM"),
    (r"^tests/unit/",               "test_quality_framework",      "LOW"),
    (r"^skills/",                   "skill_design_rules",          "MEDIUM"),
    (r"^instructions/",             "chain_principle",             "LOW"),
    (r"^projects/dm-signal",        "dmsignal_operations",         "MEDIUM"),
    (r"^config/",                   "agent_formation_management",  "LOW"),
    (r"^\.(claude|codex)/hooks/",   "hook_automation_framework",   "HIGH"),
    (r"^\.(claude|codex)/hooks/pre-bash", "destructive_operations","MEDIUM"),
]
```

### Stage 3: ファイル名ステム × Aliasスコアリング (精度=低〜中)

既存の `score_concept(concept, fields)` にファイルパスを追加入力として渡す:

```python
def infer_concepts_from_filepath(filepath, concepts):
    stem = Path(filepath).stem                  # e.g. "lesson_lifecycle"
    parts = filepath.replace('/', ' ').replace('_', ' ').replace('-', ' ')
    fields = [filepath, stem, parts]

    scored = []
    for concept in concepts:
        level, exact, partial = score_concept(concept, fields)
        if level != "NONE":
            scored.append((concept["id"], level, exact, partial))
    return scored
```

### Stage 4: 時間的近傍推論 (精度=補完)

同一ファイルを直近N件のcmd_completeで変更していた場合、そのcmdに紐付いたconceptを継承:

```python
def temporal_concept_inference(filepath, memory_db_path, lookback_days=30):
    """記憶DBのevent_conceptsから同ファイルの直近concept履歴を取得"""
    conn = sqlite3.connect(memory_db_path)
    rows = conn.execute("""
        SELECT DISTINCT ec.concept_name, COUNT(*) as freq
        FROM events e
        JOIN event_concepts ec ON e.id = ec.event_id
        WHERE e.content LIKE ?
          AND e.created_at > datetime('now', '-? days')
        GROUP BY ec.concept_name
        ORDER BY freq DESC LIMIT 5
    """, (f"%{filepath}%", lookback_days)).fetchall()
    return [(r[0], "LOW") for r in rows]
```

---

## 統合: `semantic_index_update.sh` への組込み方法

### 変更箇所

`semantic_index_update.sh` 内Pythonブロックの `cmd_complete` 処理部分:

```python
# === 既存の score_concept ループの前に追加 ===
def infer_concepts_from_files(files_modified, concepts):
    """4段階フォールバックでfiles_modified→concept推論"""
    file_concept_map = build_file_concept_map(concepts)  # Stage1
    results = {}  # concept_id → confidence_level

    for fp in (files_modified or []):
        # Stage 1: 直接ルックアップ
        if fp in file_concept_map:
            for cid in file_concept_map[fp]:
                results[cid] = max_confidence(results.get(cid), "HIGH")
            continue

        # Stage 2: ディレクトリプレフィックス
        matched_cid = match_dir_prefix(fp, DIR_PREFIX_MAP)
        if matched_cid:
            results[matched_cid] = max_confidence(results.get(matched_cid), "MEDIUM")
            continue

        # Stage 3: ファイル名ステムscoring
        for cid, level, _, _ in infer_concepts_from_filepath(fp, concepts):
            results[cid] = max_confidence(results.get(cid), "LOW")

        # Stage 4: NO_MATCHをキューに追加 (AC3連携)
        if fp not in results:
            queue_filepath_no_match(fp, payload)

    return results

# files_modifiedから得たconceptを既存スコアリング結果にマージ
file_inferred = infer_concepts_from_files(payload.get("files", []), concepts)
for cid, conf in file_inferred.items():
    # 既存のconcept選択ロジックに "HIGH file-inferred" として合流
    pre_scored_concepts[cid] = max_confidence(pre_scored_concepts.get(cid), conf)
```

### 自動追記するエントリ

1. **`| causal |`エントリ**: `cmd_id files_modified: [[concept_a]][[concept_b]]`
2. **`| file |`エントリ**: 新規ファイルのindex.md登録(Stage1キャッシュ更新)

---

## 出力検証方法

```bash
# files_modifiedにscripts/lesson_write.shを含むcmd_completeを流す
echo '{"id":"cmd_test","title":"test","files":["scripts/lesson_write.sh"]}' \
  | bash scripts/semantic_index_update.sh cmd_complete -

# → lesson_lifecycle conceptのblockに | causal | cmd_test files_modified: [[lesson_lifecycle]] | が追記されていること
grep "cmd_test" docs/semantic-index/index.md
```

---

## 既存防御との整合性

| 既存防御 | 整合状況 |
|---------|---------|
| `concept_terms` でのaliasスコアリング | Stage3で既存関数を**拡張入力**として活用。既存ロジック不変 |
| `queue_no_match_purpose_aliases` | Stage4 NO_MATCHがこの関数の**呼出しトリガーに統合** |
| flock排他ロック | 既存の`flock -w 10 200`内で全処理を完結。ロック不変 |
| `SEMANTIC_INDEX_LOCK` | 変更なし |

---

## 参照

- `scripts/semantic_index_update.sh` L860: `score_concept()` (Stage3の既存実装)
- `scripts/semantic_index_update.sh` L845: `queue_no_match_purpose_aliases()` (Stage4連携先)
- `docs/research/saizo_causal_dag_analysis_cmd3435_20260618.md` (背景分析)
- → AC3: `docs/research/saizo_provisional_concept_autogen_design_cmd3435_20260618.md`
