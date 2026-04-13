# スクリプトバグ・リファクタリング監査 2026-04-13

> 作成: 軍師 2026-04-13T21:10
> 対象: gate_report_autofix_main.py, gate_report_format.sh, deploy_task.sh
> トリガー: 殿指示「スクリプトのバグはないか？リファクタリングについて確認せよ」

## §1 最優先修正（cmd起票推奨）

### P1: autofix_main.py yaml.dump_all → 安全な書込み
- **行**: L443-444
- **重要度**: CRITICAL
- **問題**: `DumpAll([data], f, ...)` で運用YAML(報告)を丸ごと上書き。CLAUDE.md禁則(yaml.dump禁止)違反
- **リスク**: マルチライン文字列破壊→データ消失(cmd_1399事故と同型)
- **修正方針**: フィールド個別書込み(yaml_field_set.sh)、またはdiff-based patch方式に変更
- **工数**: 中（autofix全体のwrite方式を再設計）

### P2: autofix_main.py silent failure (except→pass)
- **行**: L49-50, L230-231
- **重要度**: HIGH
- **問題**: YAML parse失敗を`except Exception: pass`で握り潰し。PI-018(silent fallback)該当
- **修正方針**: `except yaml.YAMLError as e: log(f"WARN: {e}")` に変更。最低限ログ出力
- **工数**: 小

### P3: deploy_task.sh normalize_check_text AWK完全重複
- **行**: L1110, L1219
- **重要度**: MEDIUM
- **問題**: 同一AWK関数が2箇所に定義。GP-183/184で追加された直近コード
- **修正方針**: 共通AWKファイル(lib/awk_normalize_check.awk)に切り出し、両箇所から参照
- **工数**: 小〜中

## §2 中優先（補足cmd or 次回バッチ）

| 重要度 | ファイル | 行 | 問題 | 修正方針 |
|--------|---------|-----|------|---------|
| MEDIUM | autofix_main.py | L48 | isinstance判定の論理反転 | 条件式修正 |
| MEDIUM | autofix_main.py | L114-118 | 辞書キーマッチの矛盾 | ANY→ALL条件統一 |
| MEDIUM | gate_report_format.sh | L482 | sed -i cache race condition | tmpファイル+rename方式に変更 |
| MEDIUM | gate_report_format.sh | L35 | autofix subprocess失敗を`|| true`で握り潰し | exit code記録 |
| MEDIUM | gate_report_format.sh | L135-137 | assigned_acs parsing脆弱性 | gsub(/, /, " ")前処理追加 |
| MEDIUM | deploy_task.sh | L225-233 | reset_stale_fields race condition | fsync+検証追加 |
| MEDIUM | deploy_task.sh | L1118 | AWK exit条件の不完全regex | 拡張パターン修正 |
| MEDIUM | deploy_task.sh | L2967 | scout_exemptマッチ不完全 | ネスト対応regex |
| MEDIUM | deploy_task.sh | L2987-2993 | コメント行の誤マッチ | コメント除外フィルタ |

## §3 低優先（DRY / cosmetic）

- autofix_main.py: pass_vals/fail_vals定数化(L259,L424)、worker_task重複lookupヘルパー化
- gate_report_format.sh: assigned_acsフィルタ5箇所DRY化、hint dedup簡素化
- deploy_task.sh: quote-stripping 4箇所共通化、git check-ignoreバッチ化(L1193-1198)

## §4 CS checklist
- CS1: 3ファイル全量読了(Explore agent) ✓
- CS2: 現コードで問題を実確認(grep/sed -n) ✓
- CS3: CLAUDE.md yaml.dump禁則と照合 ✓
- CS4: 設計書永続化+家老cmd提案送信 → 本文書+下記inbox
- CS5: P1のyaml.dump代替方式は複数あり。詳細設計が必要
- CS6: 因果鎖: yaml.dump→マルチライン破壊→報告データ消失→家老WA。silent failure→エラー不可視→本番障害の根因不明。AWK重複→片方修正忘れ→挙動乖離

## §5 cmd分割案（推奨3cmd）

| cmd | 内容 | 依存 | 忍者工数 |
|-----|------|------|---------|
| A | P2: autofix silent failure修正(except→log) | なし | 小(30min) |
| B | P3: deploy_task AWK DRY化 | なし | 小〜中(1h) |
| C | P1: autofix yaml.dump撤去+安全書込み | A完了後推奨 | 中(2-3h) |

AとBは並列可能。Cは設計が必要なためA完了後に偵察→実装の2段階。

## §6 消火パターン監査 — 実行済み修正（2026-04-13 軍師直接実行）

殿指示「消火になっているゲートやフックはないか」に基づき7件修正。

| # | ファイル | 修正内容 | テスト |
|---|---------|---------|--------|
| 1 | gate_artifact_map.sh L72 | WARN exit 0→BLOCK exit 1 | 実行確認OK |
| 2 | gate_dc_duplicate.sh L144 | partial match exit 0→exit 1 | 実行確認OK |
| 3 | gate_gunshi_observations.sh L14 | ログ不在 exit 0→ALERT exit 1 | 不在テストOK |
| 4 | gate_gunshi_cs_checklist.sh L112 | warn=0上書きバグ修正+ログ不在exit 1 | 実行確認OK |
| 5 | stop-lint-gate.sh L99-113 | auto-approve→block+escalate | shellcheck OK |
| 6 | gate_context_freshness.sh L69/75 | ALERT 30日→14日、WARN 14日→7日 | 実行確認OK |
| 7 | gate_lesson_health.sh L25 | ALERT_THRESHOLD 10→5 | 実行確認OK |

## §7 消火パターン監査 — 残りcmd起票必要

| 優先 | 対象 | 消火パターン | cmd必要理由 |
|------|------|-------------|-------------|
| HIGH | autofix_main.py L85-105 | worker_id/parent_cmd推定 | gate_report_format.sh BLOCK条件追加が必要 |
| HIGH | autofix_main.py L278-282 | result正規化(PASS→yes) | 忍者教育+BLOCK条件追加 |
| HIGH | autofix_main.py L443 | yaml.dump_all | 書込み方式の再設計が必要 |
| MEDIUM | gate_report_format.sh L35 | autofix事前実行 | 個別消火撤去完了後に削除(最終ステップ) |

cmd_1888(lessons_useful MISSING撤去)が第一弾。上記を順次cmd化。
