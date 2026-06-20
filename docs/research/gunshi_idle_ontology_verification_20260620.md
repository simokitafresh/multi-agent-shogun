# オントロジー12パターン検証
<!-- generated: 2026-06-20T12:52:00+09:00 by gunshi idle analysis -->
<!-- 殿指示: 穴はないか？オントロジーを様々なパターンで検証しよう -->

## PASS (8パターン)

| # | 検証 | 結果 | 根拠 |
|---|------|------|------|
| 1 | repoパス消費者残存 | 0件 | rg '/mnt/c/tools/multi-agent-shogun' scripts/ .claude/ --type sh --type py |
| 2 | homeパス消費者残存 | 0件 | rg '/home/simokitafresh' 同上 |
| 3 | 忍者名ハードコード残存 | 0件 | rg 'hayate.*kagemaru.*hanzo' Guard外スクリプト |
| 4 | Guard16 batsテスト | 10/10 PASS | テスト#23-32(忍者名/repo/home各BLOCK+許可+混在) |
| 5 | gate_no_hardcoded_ninja_list | OK | ontology intact |
| 6 | pre-push ontology check | 動作確認 | .git/hooks/pre-push内にontology integrity check |
| 7a | 忍者名追加自動追従 | PASS | get_ninja_names()がsettings.yamlから動的取得 |
| 7b | repoパス変更自動追従 | PASS | git rev-parse --show-toplevel |

## 穴 (4パターン)

### 穴1: PJパス直書き19ファイル34箇所 (最大)

project_path.shヘルパー作成済み(cmd_3463 AC3)だが消費者書換え+Guard16テーブル追加が未実施。

| ファイル | 件数 | パターン |
|---------|------|---------|
| scripts/gates/gate_gunshi_report_precheck.sh | 5 | 変数代入3+インライン2 |
| scripts/cdp/cdp_measure.sh | 5 | 変数代入1 |
| scripts/hooks/test_hooks.sh | 4 | インライン4(テスト) |
| scripts/oneshot/wf_profile.py | 3 | インライン3 |
| scripts/sync_lessons.sh | 2 | インライン2 |
| scripts/gates/gate_p_average_freshness.sh | 2 | インライン1 |
| 他13ファイル | 各1 | 変数代入型/デフォルト値型 |

分類:
- **変数代入型**(8ファイル): `DM_SIGNAL_PATH="/mnt/c/..."` → `get_project_path dm-signal`に置換容易
- **インライン型**(11ファイル): 文字列中に直書き → 文脈依存で個別対応
- **auto-ops参照**(3ファイル): projects.yaml未登録 → 先にPJ登録が必要

### 穴2-4: Guard17/9bテーブル非統合、yaml_atomic.py除外は本日追加

## 推薦行動

1. cmd起票: PJパス19ファイル書換え+Guard16テーブルにPJパス概念追加
2. auto-opsのprojects.yaml登録要否は将軍判断

## 追加検証 (パターン13-30) — 殿指示「もう十分と思ったら洗脳の証拠」

### 新発見の穴(重要度順)

| # | 穴 | 影響 | 推薦対策 |
|---|---|------|---------|
| 30 | **SSOT正本(projects.yaml/cli_profiles.yaml)が保護されていない** | 正本破壊→全ヘルパー誤値→オントロジー全崩壊 | Guard17拡張でconfig/*.yaml手動Edit BLOCK |
| 15 | .yaml/.md内のハードコードはGuard16対象外 | instructions/generated/等のパス直書きが素通り | Guard16の拡張子対象拡大(yaml/md) |
| 19 | エージェント名2件は閾値以下で通過 | 2名直書きでのハードコードが漏れる | 意図的設計。閾値変更はFPリスク |

### 追加PASS確認

| # | 検証 | 結果 |
|---|------|------|
| 13 | Guard16偽陰性(ALLOWED広すぎ?) | なし。ALLOWED有でもcnt>=minならBLOCK(混在BLOCK) |
| 14 | .pyファイル対象 | ✓ L554: .sh\|.py |
| 17 | SSOT変更→全階層自動追従 | ✓ settings.yaml変更→get_ninja_names()→Guard16→消費者 |
| 18 | 消費者だけ変更→BLOCK | ✓ Guard16/17が逆方向も止める |
| 20 | 新規.sh作成時にGuard16発火 | ✓ Write tool対象 |
| 21 | dashファイル検出 | ✓ grep -cF(文字列マッチ)+git rev-parseがALLOWED |
| 22 | Guard間相互作用 | 独立にexit 2。先発火BLOCK |
| 23 | 3層防御(Write→commit→push) | ✓ 全層動作確認 |
| 24 | Codex CLI経由 | ✓ hooks.jsonでGuard16参照1件 |
| 25 | テーブル駆動スケーラビリティ | 概念追加=約10行(旧方式の5倍効率) |
| 26 | 概念間衝突 | なし(文字列が異なる) |
| 28 | CLAUDE.md内ハードコード | なし(CLAUDE.mdにパス直書き0件) |

## 因果リンク

- origin: [[殿指示_オントロジー検証]] -> [[PJパス直書き19ファイル]] -> [[Guard16テーブル未追加]]
- → [[cmd_3463_AC5]] repoパス書換えと同構造
- → [[operational_ontology]] 操作的オントロジー
