---
name: dream
argument-hint: ""
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

### 2d. 研究日誌鮮度チェック
MEMORY.mdの研究日誌索引行から最新Phase番号を抽出し、研究日誌本体の最終Phase番号と突合:
```bash
# MEMORY.md索引のPhase番号
grep -oP 'Phase \d+' memory/MEMORY.md | tail -1
# 研究日誌本体の最終Phase番号
grep -oP '## .*Phase \d+' memory/dialogue_preprocessing_research_20260331.md | tail -1
```
不一致 → `DREAM-STALE: 研究日誌Phase N だがMEMORY.md索引はPhase M` をinsightに登録。

### 2e. 到達パス検証（保存=受動的に届くか）
「保存=いつでも意識も準備もせずに利用できる知識」(殿定義)。調べないと使えないものは存在しないのと同じ。

**新規PI/知識の到達パス検証**:
config/projects.yamlのactive PJ一覧を取得し、各PJのprojects/{id}.yamlが以下の全復帰手順に到達パスがあるか検証:
- 将軍: CLAUDE.md Step 3.5
- 家老: CLAUDE.md karo Recovery Step 5
- 軍師: instructions/gunshi.md Recovery (4)
- 忍者: CLAUDE.md ninja Recovery Step 4

```bash
# active PJ一覧
grep -A1 'status: active' config/projects.yaml | grep 'id:' | awk '{print $NF}'
# 各復帰手順にprojects/{id}.yamlの参照があるか
grep -l 'projects/{id}.yaml\|projects/.*yaml' CLAUDE.md instructions/gunshi.md
```
穴 → `DREAM-REACHABILITY: {project} は {role} に届かない` をinsightに登録。

### 2f. Context健全度チェック（知識の網目密度）
context/*.md間の相互参照・孤立・陳腐化・対話到達性を検出する。
Karpathy Lint: 知識ベースの構造的健全性を定期チェック。

```bash
# 孤立context検出（他のcontextファイル・CLAUDE.mdから参照されていない）
for f in context/*.md; do
  bn=$(basename "$f")
  refs=$(grep -rl "$bn" context/*.md CLAUDE.md 2>/dev/null | grep -v "$f" | wc -l)
  if [ "$refs" -eq 0 ]; then echo "ORPHAN: $bn"; fi
done

# 陳腐化検出（最終git commit 14日以上前）
for f in context/*.md; do
  last=$(git log -1 --format="%at" -- "$f" 2>/dev/null)
  now=$(date +%s)
  if [ -n "$last" ] && [ $((now - last)) -gt 1209600 ]; then
    echo "STALE(14d+): $(basename $f) — last: $(git log -1 --format='%ai' -- "$f")"
  fi
done

# dialogue到達性（経験的知識がcontextから参照されていない）
for f in memory/dialogue_*.md memory/deepdive_*.md; do
  bn=$(basename "$f" .md)
  refs=$(grep -rl "$bn" context/*.md 2>/dev/null | wc -l)
  if [ "$refs" -eq 0 ]; then echo "UNREACHABLE-DIALOGUE: $(basename $f)"; fi
done
```

**重要**: dialogue/deepdiveは経験的知識（過程が本体）。圧縮・吸収禁止。contextには**ポインタのみ**追加。
孤立・陳腐化・対話未到達 → Phase 5 で insight に登録:
```bash
bash scripts/insight_write.sh "DREAM-CONTEXT: orphan=${N}, stale=${M}, unreachable_dialogue=${K}" dream
```

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

3. **教訓Prune（参照ファイル存在検証）**:
   各 `projects/*/lessons*.yaml` 内の教訓エントリに含まれる `target_path` / `source_file` / `enforcement` フィールドのファイル参照が実在するかを検証する。
   ```bash
   # lessons*.yaml からファイルパス参照を抽出して存在確認
   for f in projects/*/lessons*.yaml projects/infra/lessons_*.yaml; do
     [ -f "$f" ] || continue
     grep -oE '(target_path|source_file|enforcement):\s*\S+' "$f" | awk '{print $2}' | while read p; do
       p="${p//\"/}"  # クォート除去
       [ -z "$p" ] || [ "$p" = "null" ] && continue
       [ -f "$p" ] || echo "PRUNE-MISSING: $f → $p"
     done
   done
   ```
   見つかったMISSINGは `DREAM-PRUNE: {file} → {path} が存在しない` として insight に登録し、教訓エントリに `[ref_missing: YYYY-MM-DD]` を付記する（削除しない）。

4. **教訓矛盾検出**:
   同一 lesson ID が複数の lessons*.yaml に存在し、かつ `detail` または `title` が実質矛盾している（「禁止」vs「必須」、正反対の数値等）場合を検出する。
   ```bash
   # 全lessonsファイルからIDを抽出して重複確認
   grep -h "^  - id:" projects/*/lessons*.yaml projects/infra/lessons_*.yaml 2>/dev/null \
     | sort | uniq -d | awk '{print $NF}'
   ```
   重複IDが見つかれば両エントリを読み比べ、矛盾があれば `DREAM-CONTRADICTION: {id} が {fileA} と {fileB} で矛盾` として insight に登録。矛盾解消の優先順位はPhase 3cに従う。

5. **dream完了タイムスタンプ記録**:
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
  reachability: X/Y active PJs fully reachable (2e)
  journal_freshness: MEMORY.md Phase N = journal Phase M (2d)
  context_orphans: N (他contextから参照なし) (2f)
  context_stale: M (14日以上未更新) (2f)
  dialogue_unreachable: K (contextから参照なし) (2f)
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
