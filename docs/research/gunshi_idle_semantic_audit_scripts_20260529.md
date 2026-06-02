# セマンティック監査: 直近変更スクリプト (2026-05-29)

## 対象
- scripts/cmd_save.sh (cmd_3103-3105変更)
- scripts/cmd_complete_gate.sh (cmd_3104変更)
- scripts/gates/gate_test_health.sh (cmd_3103新規)
- scripts/causal_backlink_counts.sh (cmd_3104新規)

## カテゴリ: silent_failure

| ファイル | 行 | パターン | 判定 | 理由 |
|---------|-----|---------|------|------|
| cmd_complete_gate.sh | 1980-1981 | `$?`がsubshell不反映(エージェント主張) | **P0棄却(偽陽性)** | bashでは`var=$(cmd)`後の`$?`はcmdの終了コードを返す。エージェントのbash知識誤り |
| cmd_save.sh | 2826-2828 | `\|\| true`でrg/grep失敗握りつぶし | P1(低リスク) | Q11研究ドキュメント検出のWARN段階。致命的判定ロジックに影響しない |
| cmd_complete_gate.sh | 1064 | awk `2>/dev/null`で空文字→SKIP | P1(設計意図通り) | BLOCKカテゴリなし=SKIPは正しい動作 |
| gate_test_health.sh | 52 | bats出力`/dev/null`破棄 | P1(設計意図通り) | 目的は速度計測。失敗理由はexit codeで十分 |
| gate_test_health.sh | 154 | grep失敗→テスト0件 | P1(低影響) | サマリ表示のみ。判定ロジック不使用 |
| causal_backlink_counts.sh | 88 | rg不在→空結果 | P1(環境不在) | rg 14.1.1インストール済み。発火条件なし |

## カテゴリ: implicit_assumption

| ファイル | 行 | 前提 | 判定 | 理由 |
|---------|-----|------|------|------|
| cmd_save.sh↔causal_backlink_counts.sh | 2747/69-71 | `docs/research`パス共有 | P1(将来リスク) | 現時点整合。ディレクトリ構造変更時のみ発火 |
| gate_test_health.sh | 21-23 | `tests/unit/*.bats`パス | P1(安定) | 現パス構造と一致。変更予定なし |
| gate_test_health.sh | 52 | batsインストール済み | P1(安定) | bats使用はCI/pre-pushの前提 |
| cmd_complete_gate.sh | 38-42 | gate_metrics.logのTSV形式 | P1(安定) | 形式変更予定なし |

## 総合判定

**即時修正が必要な真正バグ: 0件**

P0報告1件は偽陽性(bashの`$?`挙動に対するエージェントの誤解)。
P1は全て設計意図通りまたは環境条件で発火しない。
新規gate/hook追加は不要。

## メタ観察

エージェント(Explore型)のbash知識に`$?`の挙動に関する誤解があり、P0偽陽性を生成した。
セマンティック監査でエージェント結果を鵜呑みにせず現物検証(Read tool)で棄却できた。
これは「想像するな確認せよ」原則の監査結果版への適用。
