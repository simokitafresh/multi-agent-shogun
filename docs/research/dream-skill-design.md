# Dream-skill設計書 — Auto-dreamを超える5 Phase Memory Consolidation

<!-- cmd_origin: cmd_1414 | author: shogun | created: 2026-03-27 -->

## §1 設計根拠

### 殿の原理（38億年の射程）
- **タイムスタンプ=外部記憶**: LLMに時系列概念なし→因果推論不能→タイムスタンプで補う（dialogue_statistical_wheels Phase 4）
- **粒度**: 日付では不十分。秒精度+TZ。同日の複数イベントの因果順序を判別するため（殿ヒント 2026-03-27）
- **自動化×強制**: 理解だけでは行動は変わらない→環境に埋め込む（deepdive Phase 4）
- **免疫系**: 失敗→なぜなぜ→gate/hook→永続防御（deepdive Phase 5）
- **無知の知**: 自分を信じるな。車輪を確認してから磨け（殿 2026-03-27）

### Auto-dreamとの比較
| 観点 | Auto-dream | 我々のDream-skill |
|------|-----------|-----------------|
| 対象 | memory/のみ | 6層知識基盤を横断スキャン |
| タイムスタンプ | 日付(YYYY-MM-DD) | **秒精度+TZ (ISO 8601)** |
| 時間モデル | 単一(記録時刻のみ) | **二重(事実時刻+記録時刻)** |
| 目的 | メンテナンス(劣化防止) | **進化(免疫系強化)** |
| 出力 | 綺麗なメモリ | 綺麗なメモリ **+ 自動化ターゲット提案** |
| Phase数 | 4 | **5 (Phase 5: Immunize)** |

### 取り込んだ車輪（12システム調査結果）
| 車輪 | 出典 | 取込方法 |
|------|------|---------|
| 二重タイムスタンプ | Zep/Graphiti (2025) | 事実時刻(tau_s)+記録時刻(tau_m) |
| 矛盾テーブル | Audrey (2026) | [superseded]マーク+理由記録 |
| 信頼度の概念 | Audrey source_reliability | 殿直接>忍者報告>推論の3段階 |
| 200行索引制限 | Auto-dream/Claude Code | MEMORY.md行数制限 |
| タイムスタンプ粒度=秒 | Mnemosyne (2025) | Unix秒ベース計算。ISO 8601表記 |
| 陳腐化=削除でなくマーク | Audrey soft-forget | [stale]/[superseded]で不可視化。復元可能 |

### 意図的に取り込まないもの
| 不採用 | 理由 |
|--------|------|
| エビングハウス減衰公式 | 我々の知識は会話型ではなく運用型。半減期の設定根拠がない。Phase 5で陳腐化は検出できる |
| RL学習メモリ価値 | 計算コスト大。353 obsに対してRL学習は過剰 |
| グラフDB | MCP Memory=string[]。構造変更不可。プレフィックスマーカーで代替 |

---

## §2 SKILL.md全文

以下をそのまま `~/.claude/skills/dream/SKILL.md` として配置する。

````markdown
---
name: dream
description: |
  【将軍専用】メモリ統合・整理（5 Phase REM型）。
  MEMORY.md + memory/*.mdの健全度スキャン、タイムスタンプ統一(ISO 8601秒精度+TZ)、
  矛盾解消、重複排除、陳腐化検出、免疫系提案(自動化ターゲット発見)を行う。
  Auto-dreamの4 Phaseを超える5 Phase設計: Orient/Gather/Consolidate/Prune/Immunize。
  TRIGGER: /dream、メモリ整理、知識統合、記憶の清掃、夢
  DO NOT TRIGGER: 知識棚卸し(→shogun-teire)、教訓登録(→lesson-sort)、
  PD反映(→shogun-pd-sync)、/clear前準備(→shogun-clear-prep)、Memory MCP単発操作
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Edit
  - Write
  - mcp__memory__read_graph
  - mcp__memory__open_nodes
  - mcp__memory__search_nodes
  - mcp__memory__add_observations
  - mcp__memory__delete_observations
---

# /dream — Memory Consolidation (5 Phase)

メモリの統合・整理を行う。REM睡眠に倣い、知識基盤を強化する。

**核心原理**: メモリ整理は目的ではなく手段。真の目的は**因果推論能力の維持**と**免疫系(gate/hook)候補の発見**。タイムスタンプは「後で読めるように」ではなく「**因果推論を可能にするため**」に付与する。

**二大原則**:
1. 殿の時系列原則: 「LLMには時系列概念がない。タイムスタンプという外部記憶で因果推論を可能にする」
2. 殿の免疫系原則: 「失敗→なぜなぜ→gate/hook→永続防御。メモリ整理で終わるな、防御層候補を出力せよ」

---

## 事前チェック

```bash
# dream実行条件チェック（24h経過 AND 前回dreamから変更あり）
bash scripts/should_dream.sh
```
PASSなら続行。FAILなら「前回dreamから24h未経過」と報告して終了。
殿が明示的に `/dream` を指示した場合はチェックをスキップして続行。

---

## Phase 1 — Orient (状態把握)

1. memory ディレクトリを `ls` してファイル一覧を取得
2. MEMORY.md を読む — 現在の行数、200行制限との差分を記録
3. 各 memory/*.md をスキャンし以下を記録:
   - ファイル名、行数、最終更新日
   - タイムスタンプなしのエントリ数
   - 日付のみ(時刻なし)のエントリ数
   - 相対日付("yesterday", "先週"等)のエントリ数
4. `bash scripts/gates/gate_shogun_memory.sh` を実行 — memory健全度確認
5. Phase 1サマリを記録:
   ```
   P1: files=N, total_lines=M, ts_coverage=X%, stale_candidates=K
   ```

---

## Phase 2 — Gather Signal (信号収集)

3つのソースから、メモリに反映すべき新情報を収集する。

### 2a. 構造化YAML（一次ソース — 最優先）
```bash
# karo_workarounds: 直近20件の傾向
tail -80 logs/karo_workarounds.yaml

# gate_fire_log: 直近50 FAIL
grep "result: FAIL" logs/gate_fire_log.yaml | tail -50

# lesson effectiveness
bash scripts/gates/gate_lesson_health.sh
```
- workaround のカテゴリ別頻度変化を検出
- gate FAIL の新パターンを検出
- lesson effectiveness rate の変化を検出

### 2b. セッションJSONL（二次ソース — grepで絞る）
```bash
TRANSCRIPTS_DIR="$HOME/.claude/projects/$(basename $(pwd))/"

# 殿の教えパターン（直近7日のセッションファイル）
find "$TRANSCRIPTS_DIR" -name "*.jsonl" -mtime -7 -exec \
  grep -l '"role":"human"' {} \; | while read f; do
    grep '"role":"human"' "$f" | grep -iE '覚えて|忘れるな|重要だ|原則|禁止|教訓' | tail -5
done

# CLAUDE.md/instructions変更
find "$TRANSCRIPTS_DIR" -name "*.jsonl" -mtime -7 -exec \
  grep -l 'CLAUDE.md\|instructions/' {} \; | head -5
```
**注意**: JSONLを全文読むな。grepで絞ってからtailで制限。

### 2c. ドリフト検出（三次ソース — 現状との突合）
各memory topic fileの事実主張をランダムに2-3件検証:
- ファイルパス参照 → `[ -f path ]` で存在確認
- 関数名参照 → `grep -r "function_name"` で存在確認
- 数値主張 → 可能なら現在値と比較
ドリフト検出時は Phase 3 で修正対象としてフラグ。

---

## Phase 3 — Consolidate (統合)

Phase 2 の発見事項をメモリに反映する。

### 3a. タイムスタンプ正規化 ★最重要

**全エントリに ISO 8601 秒精度+TZ を付与する。**

形式: `[2026-03-27T01:30:00+09:00]`

| 現状 | 変換ルール |
|------|-----------|
| タイムスタンプなし | `[recorded: YYYY-MM-DDTHH:MM:SS+09:00]` を付与（現在時刻） |
| 日付のみ `2026-03-25` | `[2026-03-25T00:00:00+09:00]` （時刻不明はmidnight） |
| 相対日付 "yesterday" | セッションファイルのmtimeから絶対日付を算出 |
| 秒精度あり | そのまま維持。TZ未記載なら `+09:00` を追加 |

**二重タイムスタンプ**（可能な場合）:
- `event:` — 事実がいつ起きたか（例: cmd_1082事故は2026-03-15）
- `recorded:` — いつ学んだか（例: 教訓登録は2026-03-16）
- 両方わかる場合のみ付与。不明なら `recorded:` のみ。

### 3b. 重複排除
- 新エントリ追加前に既存topic fileを検索
- 同一内容 → 既存エントリを更新（新規作成しない）
- 類似内容 → マージして1エントリに統合
- ソース帰属を保持: `(source: cmd_1413, 2026-03-27T01:30:00+09:00)`

### 3c. 矛盾解消
優先順位（信頼度順）:
1. **殿の直接発言** — 最高信頼度
2. **現物確認済み事実**（コード読み、本番データ） — 高信頼度
3. **忍者の報告** — 中信頼度
4. **推論・想像** — 低信頼度

矛盾解消時: 旧エントリに `[superseded: YYYY-MM-DDTHH:MM:SS+09:00, by: 新エントリの要約, reason: 理由]` を付記。削除はしない。

### 3d. 層間整合チェック
- MEMORY.md索引 ↔ memory/*.md実体 — 孤立ポインタを検出
- memory observations ↔ lessons.yaml — 矛盾があれば lessons を正とする（lessonsは家老がレビュー済み）
- memory内のファイル参照 ↔ 実ファイル — ドリフトを修正

---

## Phase 4 — Prune & Index (刈込)

1. **MEMORY.md更新**:
   - 200行以内、~25KB以内を維持
   - 1エントリ=1行、150文字以内: `- [Title](file.md) — one-line hook`
   - MEMORY.mdにメモリ内容を直接書くな — 索引のみ
   - 存在しないファイルへのポインタを削除
   - 冗長なエントリ → 詳細をtopic fileに移動し、索引行を短縮

2. **陳腐化マーク**（削除ではなくマーク）:
   - 30日以上参照されていないエントリ: `[stale: YYYY-MM-DD, last_referenced: YYYY-MM-DD]`
   - 矛盾解消で上書きされたエントリ: `[superseded]` マーク済み（Phase 3c）
   - **削除はしない**。マークのみ。復元可能性を維持。

3. **dream完了タイムスタンプ記録**:
   ```bash
   date -Iseconds > ~/.claude/skills/dream/.last-dream
   ```

---

## Phase 5 — Immunize (免疫提案) ★Auto-dreamに存在しないフェーズ

Phase 2 の収集データを分析し、**自動化ターゲット**(gate/hook/lesson候補)を提案する。
メモリ整理で終わるな。防御層候補を出力せよ。

### 5a. Gate候補
karo_workaroundsの再発パターン（同カテゴリ3回以上）:
```
GATE CANDIDATE: {category} — {N}回発生。
  直近: {latest_cmd}。
  提案: gate_{name}.sh で自動防止。
```

### 5b. Lesson候補
gate_fire_logの未カバーFAIL理由（lessons.yamlに対応教訓なし）:
```
LESSON CANDIDATE: {fail_reason} — {N}回FAIL。
  lessons.yamlに未登録。lesson_write.sh で登録推奨。
```

### 5c. メモリ品質メトリクス
```
DREAM METRICS:
  timestamp_coverage: X% (秒精度+TZ)
  staleness_rate: X% (30日以上未参照)
  contradiction_count: N (未解決矛盾)
  drift_count: N (現状と乖離)
  memory_lines: L/200 (MEMORY.md)
```

### 5d. 提案の永続化
```bash
# 各候補をinsightキューに登録
bash scripts/insight_write.sh "DREAM-GATE: {suggestion}" dream
bash scripts/insight_write.sh "DREAM-LESSON: {suggestion}" dream
```

---

## 出力サマリ

```
Dream completed [ISO 8601 timestamp]
- Phase 1: N files, M lines, X% timestamp coverage
- Phase 2: N signals (YAML: A, JSONL: B, drift: C)
- Phase 3: N updated, M timestamps normalized, K contradictions resolved
- Phase 4: MEMORY.md L/200 lines, N stale marked
- Phase 5: N gate candidates, M lesson candidates → insights queue
Next dream eligible: [timestamp + 24h]
```

---

## 制約
- memory/ 以外のプロジェクトコードは**読み取り専用**
- 書き込み対象: memory/, MEMORY.md, ~/.claude/skills/dream/.last-dream, insights(スクリプト経由)
- メモリエントリを**削除しない** — [stale]/[superseded]マークのみ
- CLAUDE.md, instructions/, projects/, lessons.yaml は**変更禁止**（別パイプラインが管理）
- MCP Memory操作: read/open/searchは自由。add/deleteは確認済み修正のみ
````

---

## §3 should_dream.sh仕様

```bash
#!/usr/bin/env bash
# should_dream.sh — dream実行条件チェック
# 条件: 前回dreamから24h以上経過
# Exit 0 = ready, Exit 1 = not ready
set -euo pipefail

LAST_DREAM_FILE="$HOME/.claude/skills/dream/.last-dream"
THRESHOLD=$((24 * 60 * 60))  # 24 hours in seconds

if [[ ! -f "$LAST_DREAM_FILE" ]]; then
    echo "DREAM: 初回実行。Ready."
    exit 0
fi

LAST_TS=$(cat "$LAST_DREAM_FILE")
LAST_EPOCH=$(date -d "$LAST_TS" +%s 2>/dev/null || echo 0)
NOW_EPOCH=$(date +%s)
ELAPSED=$(( NOW_EPOCH - LAST_EPOCH ))

if [[ $ELAPSED -ge $THRESHOLD ]]; then
    HOURS=$(( ELAPSED / 3600 ))
    echo "DREAM: 前回から${HOURS}h経過 (>24h)。Ready."
    exit 0
else
    REMAINING_H=$(( (THRESHOLD - ELAPSED) / 3600 ))
    REMAINING_M=$(( ((THRESHOLD - ELAPSED) % 3600) / 60 ))
    echo "DREAM: 次回まで${REMAINING_H}h${REMAINING_M}m。Not ready."
    exit 1
fi
```

---

## §4 テスト計画

| テスト | 期待結果 | 検証方法 |
|--------|---------|---------|
| `/dream` でスキル発火 | SKILL.md内容が実行される | 手動実行 |
| Phase 1 完了 | memory状態レポート出力 | サマリにfiles/lines/ts_coverage表示 |
| Phase 3 タイムスタンプ正規化 | 相対日付→絶対日付変換 | 変換前後のdiff確認 |
| Phase 4 MEMORY.md行数 | 200行以内 | `wc -l MEMORY.md` |
| Phase 5 免疫提案 | insights.yamlにDREAM-*エントリ | `grep DREAM insights.yaml` |
| should_dream.sh 初回 | exit 0 + "初回実行" | .last-dream不在で実行 |
| should_dream.sh 24h未満 | exit 1 + 残り時間表示 | .last-dream書込み直後に実行 |
