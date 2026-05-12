# セマンティック監査カタログ設計書

- 設計者: 軍師 (gunshi)
- 日付: 2026-05-03 (v2: 2026-05-04 再スキャン知見反映)
- 将軍指示: セマンティック監査結果を永続カタログ化+3接点注入

## §1 目的

grepで検出不能なバグ(エラー握りつぶし/状態遷移不整合/レースコンディション/暗黙前提崩壊)を
**永続カタログ**として蓄積し、全エージェントが検索・参照・活用できる仕組みを構築する。

初回監査(2026-05-03)で23件検出→12件修正CLEAR→再スキャン(2026-05-04)で~55件検出(全224本拡大+修正副作用カテゴリ追加)。修正12件中5件(42%)に副作用発見=**修正副作用スキャンは必須**。

## §2 カタログフォーマット

### 保存先
`logs/semantic_audit_catalog.yaml`

### エントリ構造
```yaml
entries:
  - id: SA-001
    category: silent_failure | state_transition | race_condition | implicit_assumption | side_effect
    severity: urgent | high | medium | low
    file: scripts/archive_completed.sh
    function: sync_chronicle_entry    # ★行番号ではなく関数名で特定(v2改善)
    context_pattern: "flock.*return 1.*chronicle"  # grepで再発見可能なコンテキスト文字列
    line_hint: 137                    # 参考値(陳腐化する前提。context_patternが正本)
    title: "サブシェルreturn偽装成功"
    description: "flock timeout→return 1→サブシェル内returnは親に伝播しない→後続echoが無条件実行"
    failure_scenario: "WSL2 NTFS flock timeout時にchronicle更新失敗が成功として記録される"
    detection_method: semantic  # semantic | grep | runtime | gate
    detected_at: "2026-05-03T22:50:00"
    detected_by: gunshi
    source_analysis: docs/research/gunshi_idle_semantic_infra_audit_20260503.md
    status: open | resolved | wont_fix | superseded
    resolved_by: null           # cmd_id (GATE CLEAR時に自動記録)
    resolved_at: null
    file_hash: null              # 変更検知用。diff時にfile_hash不一致→line_hint再計算
    grep_impossible_reason: "return 1は正しいbash構文。サブシェルセマンティクスの理解が必要"
```

### カテゴリ定義

| カテゴリ | 検出対象 | grep不可能な理由 |
|---------|---------|-----------------|
| `silent_failure` | エラー握りつぶし・戻り値無視・tmpfile消失 | `2>/dev/null`は見つかるが「空文字列がcase不一致」は見つからない |
| `state_transition` | 状態遷移の欠落・不整合・dead state | `status:`は見つかるが「遷移ロジックの不在」は見つからない |
| `race_condition` | TOCTOU・並行書込み・glob展開レース | `flock`の有無は見つかるが「flockスコープ外の書込み」は見つからない |
| `implicit_assumption` | スクリプト間の暗黙前提崩壊 | 各スクリプトは正常だが「呼ばれない関数の効果」は見つからない |
| `side_effect` | 修正が導入した新たなバグ | 修正コード自体は正しいが「波及先での副作用」は修正diffだけでは見つからない |

### side_effectカテゴリの根拠(再スキャン実証 2026-05-04)

修正12件中5件(42%)に副作用を検出。パターン:
1. **return 1伝播**: set -euo pipefail環境でreturn 1が想定外の箇所に波及(cmd_2533→archive全体exit)
2. **set +eスコープ過大**: エラー無視区間が意図より広い(cmd_2539)
3. **フィルタ偽陰性**: マルチワーカー配備の考慮漏れ(cmd_2530)
4. **上限値の除外漏れ**: gate待ち状態のreportがcap対象(cmd_2529)
5. **非atomic更新**: 2ステップのyaml_field_setで中間状態が見える(cmd_2531→report_field_set)

## §3 解消マーク仕組み

### 自動解消(GATE CLEAR連携)

cmd_complete_gate.shのGATE CLEAR時に、修正対象ファイルとカタログを突合:

```bash
# cmd_complete_gate.sh GATE CLEARブロック(L4453前後)に追加
# files_modifiedからスクリプトファイルを抽出
# semantic_audit_catalog.yamlの該当file+status:openエントリをresolved化
resolve_semantic_audit() {
    local cmd_id="$1"
    local catalog="$SCRIPT_DIR/logs/semantic_audit_catalog.yaml"
    [ -f "$catalog" ] || return 0

    # 修正されたスクリプトファイル一覧を取得
    local modified_scripts
    modified_scripts=$(git log --grep="$cmd_id" --format="" --name-only | grep '^scripts/' | sort -u)
    [ -z "$modified_scripts" ] && return 0

    # 該当エントリをresolved化(Python inline)
    python3 - "$catalog" "$cmd_id" "$modified_scripts" <<'RESOLVE_PY'
import sys, yaml, os
from datetime import datetime

catalog_path, cmd_id = sys.argv[1], sys.argv[2]
modified = set(sys.argv[3].split())

with open(catalog_path, encoding='utf-8') as f:
    data = yaml.safe_load(f) or {}

entries = data.get('entries', [])
resolved_count = 0
for entry in entries:
    if entry.get('status') != 'open':
        continue
    entry_file = entry.get('file', '')
    if entry_file in modified:
        # context_patternで現存確認(行番号ではなくパターンマッチ)
        ctx = entry.get('context_pattern', '')
        if ctx:
            target = os.path.join(os.path.dirname(catalog_path), '..', entry_file)
            if os.path.exists(target):
                with open(target, encoding='utf-8', errors='replace') as tf:
                    if not any(
                        __import__('re').search(ctx, line)
                        for line in tf
                    ):
                        # パターン消失=修正済みと推定
                        entry['status'] = 'resolved'
                        entry['resolved_by'] = cmd_id
                        entry['resolved_at'] = datetime.now().isoformat()
                        resolved_count += 1
                        continue
        # パターンなし or パターン残存→手動確認必要
        entry['status'] = 'review_needed'
        entry['resolved_by'] = cmd_id

import tempfile
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(catalog_path), suffix='.tmp')
with os.fdopen(fd, 'w', encoding='utf-8') as f:
    yaml.dump(data, f, allow_unicode=True, default_flow_style=False, sort_keys=False)
os.replace(tmp, catalog_path)
print(f"resolved: {resolved_count}")
RESOLVE_PY
}
```

### 手動解消
`bash scripts/lib/semantic_audit.sh resolve SA-001 cmd_2529`

### 解消時の記録
```yaml
status: resolved
resolved_by: cmd_2529
resolved_at: "2026-05-03T23:00:00"
file_hash: "abc123"  # git hash-object scripts/archive_completed.sh
```

## §4 差分再スキャントリガー

### トリガー条件

| トリガー | タイミング | 対象 |
|---------|----------|------|
| **GATE CLEAR時** | cmd_complete_gate.sh L4453後 | files_modifiedに含まれるスクリプト |
| **★修正副作用スキャン** | バグ修正cmd GATE CLEAR後 | 修正されたスクリプト+呼出元+呼出先 |
| **idle自走** | 軍師のidle Step 7(新設) | git diffで前回監査以降に変更されたスクリプト |
| **定期フル** | 週1(/dream時) | 全224スクリプト |

### 修正副作用スキャン(再スキャン実証で追加)

バグ修正のGATE CLEAR後、修正が導入した新たなバグを検出する専用スキャン。
42%の検出率(12件中5件)を実証。**修正→CLEAR→安心は危険。修正→CLEAR→副作用スキャンが正しいフロー。**

検証観点:
1. 修正で追加した条件分岐にエッジケース漏れはないか
2. 修正が正常系の動作を変えていないか(特にset -e環境でのreturn伝播)
3. フォアグラウンド化やリトライによるパフォーマンス回帰
4. 新しいファイル操作が既存のflock/atomic writeと衝突しないか
5. フィルタ強化による偽陰性(正当なケースの除外)

### GATE CLEAR時の差分通知

```bash
# cmd_complete_gate.sh GATE CLEARブロックに追加
notify_semantic_audit_impact() {
    local cmd_id="$1"
    local catalog="$SCRIPT_DIR/logs/semantic_audit_catalog.yaml"
    [ -f "$catalog" ] || return 0

    local modified_scripts
    modified_scripts=$(git log --grep="$cmd_id" --format="" --name-only | grep '^scripts/' | sort -u)
    [ -z "$modified_scripts" ] && return 0

    # 修正されたスクリプトに関連するopen/resolvedエントリを抽出
    local hits=0
    for script in $modified_scripts; do
        local count
        count=$(grep -c "file: $script" "$catalog" 2>/dev/null || echo 0)
        hits=$((hits + count))
    done

    if [ "$hits" -gt 0 ]; then
        echo "[semantic_audit] $hits件のカタログエントリが${cmd_id}の変更対象ファイルに関連"
        echo "[semantic_audit] → 差分再スキャン推奨: 修正で新たなパターンが発生していないか確認"
    fi
}
```

### idle自走の差分再スキャン

```bash
# scripts/lib/semantic_audit.sh diff-scan
# 前回の監査タイムスタンプ以降にgit diffで変更されたスクリプトを特定
# 変更されたスクリプトのみを対象にエージェント探索を実行
# 結果をカタログに追加
```

前回監査タイムスタンプ: カタログファイルの`last_full_scan:`フィールド

## §5 3接点注入設計

### 接点1: 偵察AC自動注入

deploy_task.shのtask_type=reconまたはscout時:
```yaml
# task YAMLに自動追加
semantic_audit_context:
  related_entries:
    - SA-003: "deploy_task.sh L688 mktemp未検証"  # target_pathがdeploy_task.shの場合
  instruction: "偵察対象にセマンティック監査の既知バグがある。波及分析に含めよ"
```

**実装**: deploy_task.shのrelated_lessons注入ロジック(L2535-2585)と同様に、
target_pathとカタログのfileフィールドを突合し、一致するエントリをtask YAMLに注入。

### 接点2: SGプロトコル(軍師レビュー)

draft review Step 4(事前検死)に追加:
```
Step 4.5: Semantic Audit Check
  cmd_complete_gate.sh/deploy_task.sh/archive_completed.sh等の
  高リスクファイルが変更対象の場合、カタログの該当エントリを確認。
  既知バグが修正されていない+影響する変更が含まれる場合→REQUEST_CHANGES
```

**実装**: `bash scripts/lib/semantic_audit.sh check-files <files_modified>`
→ 該当エントリ一覧を返す。0件ならスキップ。

### 接点3: idle自走メニュー

instructions/gunshi.md §idle自走プロトコルに Step 7追加:
```
Step 7: セマンティック監査差分再スキャン
  - git diff --name-only $(カタログlast_scan)..HEAD | grep '^scripts/'
  - 変更スクリプトに対してカテゴリ別の意味的探索を実行
  - 新規検出→カタログ追加→掲示板投稿
  - 完了→last_scan更新
```

## §6 初期データ投入

初回23件+再スキャン~55件(重複排除)を初期エントリとして投入。
SA-001〜023は初回、SA-024〜は再スキャンで追加。resolved/superseded管理で鮮度維持。

| ID | カテゴリ | severity | ファイル | 行 | タイトル |
|----|---------|----------|---------|-----|---------|
| SA-001 | silent_failure | urgent | archive_completed.sh | 137 | サブシェルreturn偽装成功 |
| SA-002 | silent_failure | urgent | cmd_complete_gate.sh | 81 | flock timeout→case空文字沈黙 |
| SA-003 | silent_failure | high | deploy_task.sh | 688 | mktemp未検証 |
| SA-004 | silent_failure | high | deploy_task.sh | 983 | mktemp+||true二重握りつぶし |
| SA-005 | silent_failure | medium | archive_completed.sh | 397 | 二重flock timeout→pending_decisions無視 |
| SA-006 | silent_failure | medium | inbox_write.sh | 255 | mv失敗時メッセージ消失 |
| SA-007 | silent_failure | medium | ninja_monitor.sh | 173 | inbox_write戻り値無視(bg) |
| SA-008 | state_transition | urgent | report_field_set.sh | 3316 | status:pending永久残存 |
| SA-009 | state_transition | ~~high~~ **wont_fix** | deploy_task.sh | 5051 | ~~task in_progress→idle自動遷移なし~~ **棄却: M6再精査でGATE CLEAR時idle遷移(L432-458)実装済みと確認** |
| SA-010 | state_transition | high→low | archive_completed.sh | 599 | delegated→done遷移の非決定性 (U1修正でgate_metrics fallback追加→大幅緩和) |
| SA-011 | state_transition | ~~medium~~ **wont_fix** | - | - | ~~completed status dead code~~ **棄却: M6再精査でL1239にcompleted含む確認済み** |
| SA-012 | race_condition | high | cmd_complete_gate.sh | 2817 | glob展開後ファイル増減 |
| SA-013 | race_condition | medium | archive_completed.sh | 1169 | archive.doneチェックTOCTOU |
| SA-014 | race_condition | medium | yaml_field_set.sh | 18 | 複数フィールド更新の非atomic |
| SA-015 | race_condition | ~~medium~~ **wont_fix** | cmd_complete_gate.sh | 1977 | ~~symlink+原本重複カウント~~ **棄却: M8再精査でcmd_2530 fallbackフィルタ+GP-230 symlink cleanup済み** |
| SA-016 | implicit_assumption | urgent | archive_completed.sh | 1101 | gate_metricsローテーション後fallback崩壊 |
| SA-017 | implicit_assumption | urgent | archive_completed.sh | 1112 | placeholder上書き漏れ |
| SA-018 | implicit_assumption | ~~high~~ **superseded→SA-H2** | deploy_task.sh | 5009 | ~~karo_directでreset_stale_fields未呼出~~ **訂正: reset_stale_fieldsは呼ばれる。真因=L5009のtask_id設定漏れ(cmd_2538で修正CLEAR)** |
| SA-019 | implicit_assumption | medium | ninja_monitor.sh | 2263 | inbox_watcher kill→ゾンビ残存 |
| SA-020 | implicit_assumption | medium | bulletin_write.sh | 205 | watcher未起動時通知喪失 |
| SA-021 | implicit_assumption | resolved | archive_completed.sh | 1084 | 3パターンSKIP | → cmd_2529で修正中
| SA-022 | implicit_assumption | resolved | cmd_complete_gate.sh | 1975 | fallback glob交差汚染 | → cmd_2530で修正中
| SA-023 | implicit_assumption | resolved | cmd_complete_gate.sh | 4453 | gate_metrics CLEAR保証 | → cmd_2530で修正中

## §7 セルフレビュー3点

### 数値検算
- スクリプト総数: 224本(実測)
- 初回エントリ: 23件(4探索の重複排除後)。修正12件CLEAR
- 再スキャンエントリ: ~55件(5探索・全224本+副作用カテゴリ)。P0: 2件, P1: 6件, P2: 8件, P3: 20+件
- カテゴリ分布(再スキャン): silent_failure 42件, side_effect 5件, state_transition 1件, race_condition 4件, implicit_assumption 8件

### 前提検証
- カタログ保存先`logs/semantic_audit_catalog.yaml`は既存ログディレクトリ内。gitignore対象外
- yaml_field_set.shはflock付き(L18-30)。カタログ書込みもflock経由で安全
- gate_metricsローテーション(rotate_gate_metrics.sh)はMAX_LINES=1000。差分再スキャンの前回タイムスタンプが1000行以上前に遡ることはない

### 事前検死
- 忍者がカタログを直接編集するリスク: なし(resolved化はcmd_complete_gate.sh自動or軍師手動)
- カタログ肥大化: 年間~100件。1エントリ~10行=~1000行/年。管理可能
- 偽陽性の蓄積: wont_fixステータスで除外。定期/dream時に棚卸し

## §8 実装ロードマップ

| Phase | 内容 | 実装者 | 依存 |
|-------|------|--------|------|
| 0 | カタログYAML作成+初期23件投入 | 軍師(D0) | なし |
| 1 | `scripts/lib/semantic_audit.sh`(check-files/resolve/diff-scan) | 忍者cmd | Phase 0 |
| 2 | cmd_complete_gate.sh GATE CLEAR時の自動resolved化+差分通知 | 忍者cmd | Phase 1 |
| 3 | deploy_task.shの偵察AC自動注入 | 忍者cmd | Phase 1 |
| 4 | gunshi.md SGプロトコル+idle自走にStep追加 | 軍師(D0) | Phase 1 |

Phase 0は軍師D0で即実行可能。Phase 1-3は忍者cmd。Phase 4は軍師D0。

## §9 再スキャン知見(2026-05-04追加)

### 範囲拡大の効果
| 指標 | 初回(5本) | 再スキャン(224本) | 倍率 |
|------|----------|-----------------|------|
| silent_failure | 7件 | 42件 | 6x |
| 合計 | 23件 | ~55件 | 2.4x |

### 修正副作用の定量
- 修正12件中5件(42%)に副作用
- P0(即時修正): 2件(cmd_2533 archive全体exit, cmd_2539 set+eスコープ)
- P1(高優先): 3件(cmd_2530 フィルタ偽陰性, cmd_2529 cap除外漏れ, verdict非atomic)
- 副作用なし: 7件(cmd_2531/2532/2534/2535/2536/2537/2538)

### 修正副作用のパターン分類
| パターン | 件数 | 対策 |
|---------|------|------|
| set -e環境でのreturn 1波及 | 1件 | 呼出元に`\|\| true`追加 |
| set +eスコープ過大 | 1件 | スコープ最小化 |
| フィルタ強化の偽陰性 | 1件 | primary/secondaryフィルタ分離 |
| 上限値の状態除外漏れ | 1件 | pending状態を明示除外 |
| 非atomic 2ステップ更新 | 1件 | yaml_field_set_batch化 |

### 設計への反映
1. **side_effectカテゴリ追加** → §2カテゴリ定義に追加済み
2. **修正副作用スキャントリガー** → §4トリガー条件に追加済み
3. **初期データ拡大** → §6を23件→~55件+に更新済み
4. **再スキャンは修正完了後に必須** → 「修正→CLEAR→副作用スキャン」がフロー

→ 再スキャン詳細: `docs/research/gunshi_semantic_rescan_20260504.md`

generated: 2026-05-04T01:00:00+09:00
