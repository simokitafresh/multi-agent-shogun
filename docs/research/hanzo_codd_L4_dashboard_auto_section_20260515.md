# CoDD修行L4: dashboard_auto_section.sh 設計書品質検証

- 実施者: hanzo
- 対象: `scripts/dashboard_auto_section.sh`
- 実施日: 2026-05-15
- task_id: cmd_training_L4_codd_202605152312_hanzo
- CoDD version: 2.18.0

---

## AC1: codd spec相当の目的・制約・対象範囲

### 目的

`scripts/dashboard_auto_section.sh` は `dashboard.md` の機械的セクション（リアルタイム状況）を自動生成する。
`<!-- DASHBOARD_AUTO_START -->` ～ `<!-- DASHBOARD_AUTO_END -->` マーカー間のみを上書きし、マーカー外（家老記入セクション）は一切変更しない。

### 入力ソース（10種）

| 入力 | 種別 | 用途 |
|------|------|------|
| `queue/karo_snapshot.txt` | 直接読込 | 忍者配備状況・idle/done |
| `queue/shogun_to_karo.yaml` | 直接読込 | パイプライン active cmd一覧 |
| `logs/gate_metrics.log` | 直接読込 | 連勝数・CLEAR率・総cmd数 |
| `queue/tasks/*.yaml` | 直接読込 | 各忍者の現タスク詳細 |
| `config/settings.yaml` | 直接読込 | モデル名 |
| `config/cli_profiles.yaml` | 直接読込 | display_name解決 |
| `logs/gate_fire_log.yaml` | 直接読込 | 初回CLEAR率計算 |
| `logs/lesson_impact.tsv` | 直接読込 | 教訓注入・直近30cmd集計 |
| `queue/lesson_effectiveness_status.txt` | 直接読込 | 効果率閾値 |
| 外部スクリプト (5本) | subprocess | 知識・CI・スキル等の派生指標 |

### 出力セクション（10種）

1. 忍者配備（忍者名・モデル・状態・cmd・内容）
2. CI Status（GREEN/RED/check failed）
3. Unpushed Commits WARN（≥10件で表示）
4. パイプライン（active cmds）
5. 戦況メトリクス（CLEAR率・稼働数・連勝）
6. モデル別スコアボード
7. 知識サイクル健全度（PJ別・タスク種別・モデル別・教訓ランキング）
8. スキル健全度
9. Context鮮度警告
10. 戦果（直近5 CLEAR）

### 制約

- `--dry-run` 時はdashboard.md未変更
- マーカーなし時はexit 1
- 原子書込み: `.tmp` → `mv` による中途半端な書込み防止
- `set -euo pipefail` + `|| true` による graceful degradation

---

## AC2: elicit/lexicon観点での要件穴・coverage軸

### coverage軸マトリクス

| 軸 | 評価 | コメント |
|----|------|---------|
| 機能正確性 | ★★★★☆ | 各セクション生成ロジックは詳細に実装 |
| パフォーマンス | ★★★★★ | 多層キャッシュ・background subprocess・gawk最適化 |
| 並行安全性 | ★★☆☆☆ | flock未使用。競合書込みリスク |
| 外部契約 | ★★☆☆☆ | 5本外部スクリプトの出力形式が要件/設計書に未定義 |
| エラー可視性 | ★★☆☆☆ | `|| true` でサイレント失敗。運用デバッグ困難 |
| テスト容易性 | ★★☆☆☆ | 1278行が単一スクリプト。セクション単体テスト不可 |
| マーカー検証 | ★★★☆☆ | 存在チェックのみ。順序チェックなし |
| ntfy冪等性 | ★★★★☆ | CLEAR_COUNT dedup済みだがプロジェクト非スコープ |

### 要件穴 (Gaps)

**GAP-1: 並行書込み安全性（severity: HIGH）**

- 現状: `dashboard.md` の書込みに `flock` なし
- リスク: `dashboard-update` スキルと `ninja_monitor` が同時実行された場合、`.tmp` ファイルが競合し、出力が混在する可能性
- 現要件(SR-1)は「原子書込み」と規定するが並行インスタンスへの言及なし

**GAP-2: ntfy dedup のスコープ漏れ（severity: MEDIUM）**

- 現状: `/tmp/mas-dashboard-ntfy-last-clear.txt`（プロジェクトハッシュなし）
- 他のキャッシュファイル（CTX/CI/git-revlist）はすべて `_proj_hash` を含む
- 同一ホストに複数MASインスタンスがある場合、ntfy通知が抑制または重複する

**GAP-3: 外部スクリプト出力形式の無契約（severity: HIGH）**

- `knowledge_metrics.sh --json --by-project --by-model` → JSON形式の詳細スキーマ不明
- `ci_status_check.sh --status` → `GREEN` or `RED:<run_id>:<failed>` はdesignに記載されているが要件に未記載
- スクリプト変更時の破壊的変更検出ゲートがない

**GAP-4: マーカー順序の未検証（severity: LOW）**

- 現状: `grep -qF MARKER_START` と `grep -qF MARKER_END` の存在チェックのみ
- `MARKER_END` が `MARKER_START` より前に存在する場合、`awk` の置換が誤動作する

**GAP-5: サイレント失敗の不透明性（severity: MEDIUM）**

- `|| true` が多数箇所に存在
- データソース障害時に `—` を表示するが、stderr/logへのエラー記録がない
- 本番運用で「なぜ値が `—` なのか」の診断ができない

---

## AC3: codd validate/measure による品質採点・改善点

### Before → After (measure)

| 指標 | Before (私の変更前) | After |
|------|---------------------|-------|
| `health_score` | 92 | 93 |
| `total_nodes` | 12 | 16 |
| `total_edges` | 7 | 10 |
| `validation_errors` | 0 | 0 (私の文書は clean) |
| `validation_warnings` | 1 | 1 (既存inbox_write警告のみ) |
| `documents_checked` | 12 | 16 |

### validate結果

- my documents: validation_errors=0, validation_warnings=0
- 既存警告(pre-existing): `inbox_write_requirements.md` の depended_by 相互参照欠如
- 既存エラー(pre-existing, 新規検出): `restart_watchers_requirements.md` が参照する `design:script:restart-watchers` が未定義

### 設計書品質スコア（手動採点）

| 観点 | スコア | 根拠 |
|------|--------|------|
| Purpose明確性 | 9/10 | ヘッダーコメントが明確 |
| Input/Output定義 | 8/10 | 入力は詳細だが外部スクリプト契約が欠如 |
| エラーハンドリング | 5/10 | `|| true` による隠蔽が多い |
| キャッシュ設計 | 9/10 | 多層キャッシュが整合的に設計されている |
| 並行安全性 | 4/10 | flock未使用、heavy cache競合リスク |
| 保守性 | 5/10 | 1278行単一ファイル、セクション分離なし |
| **総合** | **7/10** | パフォーマンス最適化は優秀、安全性・保守性に課題 |

### 改善点（3つ以上）

**改善1: `flock` による並行書込み保護 (GAP-1対応)**
```bash
# dashboard.md更新前にflockで排他制御
exec 200>"${PROJECT_DIR}/.dashboard_update.lock"
flock -w 5 200 || { echo "ERROR: dashboard update lock timeout" >&2; exit 1; }
# ... 既存の書込みロジック ...
flock -u 200
```
- 効果: `dashboard-update`スキルと`ninja_monitor`の同時実行時の競合排除
- リスク: lock取得失敗時の適切なエラー処理が必要

**改善2: ntfy dedup ファイルのプロジェクトスコープ化 (GAP-2対応)**
```bash
# 変更前:
_ntfy_last_file="/tmp/mas-dashboard-ntfy-last-clear.txt"
# 変更後:
_ntfy_last_file="/tmp/mas-dashboard-ntfy-last-clear-${_proj_hash}.txt"
```
- 効果: 複数MASインスタンスのntfy通知干渉を排除
- コスト: 1行修正のみ

**改善3: 外部スクリプト出力契約をrequirementsに追記 (GAP-3対応)**

`dashboard_auto_section_requirements.md` に以下を追記すべき:
- FR-X: `ci_status_check.sh --status` は `GREEN`、`RED:<run_id>:<failed_tests>`、またはエラー文字列を返すこと
- FR-X: `knowledge_metrics.sh --json --by-project --by-model` は `inject_rate`/`ref_rate`/`lesson_effectiveness`/`by_project[]`/`by_model[]`/`top_helpful[]`/`bottom_lessons[]` を含むJSONを返すこと
- FR-X: `model_analysis.sh --summary` は `model_row=<slug>\t<label>\t<clear>\t<impl>\t<trend>\t<n>` 形式の行を返すこと

**改善4: マーカー順序バリデーション追加 (GAP-4対応)**
```bash
# 存在チェックの後に追加:
_start_line=$(grep -n "$MARKER_START" "$DASHBOARD" | head -1 | cut -d: -f1)
_end_line=$(grep -n "$MARKER_END" "$DASHBOARD" | head -1 | cut -d: -f1)
if [[ "${_start_line:-0}" -ge "${_end_line:-0}" ]]; then
    echo "ERROR: MARKER_START must precede MARKER_END in dashboard.md" >&2
    exit 1
fi
```
- 効果: 手動編集でマーカーが入れ替わった場合の誤動作を防止

**改善5: データソース障害の可視化 (GAP-5対応)**
```bash
# heavy cache MISS + 計算失敗時にstderrに記録
FIRST_FIRE_RATE=$(compute_first_fire_rate) || {
    echo "WARN: compute_first_fire_rate failed, using —" >&2
    FIRST_FIRE_RATE="—"
}
```
- 効果: 本番で `—` が表示された原因をログから特定できる

---

## 作成物一覧

| 種別 | パス |
|------|------|
| Requirements | `codd/requirements/dashboard_auto_section_requirements.md` |
| Design | `codd/design/dashboard_auto_section_design.md` |
| Research | `docs/research/hanzo_codd_L4_dashboard_auto_section_20260515.md` (本文書) |

## codd dag verify

```
codd scan --path . → Documents: 15, Graph: 16 nodes, 10 edges
codd validate --path . → validation_errors=0 (my docs), pre-existing: 2 (inbox_write warning + restart_watchers error)
codd measure --path . --json → health_score: 92 → 93
```
