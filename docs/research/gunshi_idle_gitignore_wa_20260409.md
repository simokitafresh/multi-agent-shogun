# Gitignore Workaround Pattern Analysis
# Date: 2026-04-09
# Source: karo_workarounds.yaml 直近5件中2件

## 発見パターン

| cmd | category | 根因 |
|-----|----------|------|
| cmd_ga017_gs_knowledge | gitignore_untracked | gitignore対象ファイルにcommit必須AC設計 |
| cmd_root_dashboard_auto | verdict_override | gitignore対象ファイルにcommit必須AC設計 |

## 因果鎖

gitignore対象ファイルをcmd ACの変更対象に含める
→ 忍者がローカル編集完了
→ commitしようとするとUNTRACKED(gitignore)
→ verdict FAIL
→ 家老がverdict override
→ workaround発生

根因: cmd設計時にAC対象ファイルのgitignore状態を検証していない

## 自動化ターゲット

ac_physical_verify.sh (draft review Step 0.5) にgitignore検出を追加。

実装:
- 検証済みパスに対して `git check-ignore` を実行
- gitignore対象 + ACテキストに"commit"が含まれる場合 → WARN出力
- 軍師がdraft review時に自動検出し、REQUEST_CHANGESで指摘可能

防御階層: Level 5(事前コンテキスト提供) のままで、検出範囲を拡張

## 複利の問い

gitignore未検出×10回 = 10回workaround(負の複利)
gitignore検出追加×1回 = 全未来のgitignore workaround防止(正の複利)
