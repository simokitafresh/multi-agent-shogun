# cmd_save BLOCK根因パターン分析+自動成長設計案 v3

> v2→v3: 家老2往復目5件反映。一次データ集計スクリプト添付、既存機構差分表、SG-PRE25共通化、ms計測、D0分離。

## 背景
殿指示(2026-07-02): 品質+速度+自動成長の3軸同時改善。速度超速=トータル品質直結。

## 現状計測 (再現コマンド付き — 家老残穴1反映)

```bash
# 再現コマンド
python3 -c "
import yaml
from collections import Counter
with open('logs/cmd_design_quality.yaml') as f:
    data = yaml.safe_load(f)
blocks = [e for e in data.get('entries',[]) if e.get('gate_result') == 'BLOCK']
print(f'total={len(data[\"entries\"])} block_records={len(blocks)} unique_cmds={len(set(e[\"cmd_id\"] for e in blocks))}')
"
```

| 指標 | 値 | ソース |
|------|-----|--------|
| 総件数 | 209 | cmd_design_quality.yaml entries count |
| BLOCK記録 | 28 | gate_result==BLOCK |
| unique BLOCK cmd | 17 | cmd_idユニーク |
| **unique BLOCK率** | **8.1%** (17/209) | |
| preflight実測 | 2.08秒 | cmd_3636 (2026-07-02) |

## BLOCK根因パターン (一次データ: notes列分類)

| # | パターン | records | unique cmds | 対象cmd | 現状対策 |
|---|---------|---------|------------|---------|---------|
| 1 | bc_fail | 9 | 7 | cmd_3588/3620/3621/3622/3628/3634/training | gate_report_format.sh |
| 2 | mismatch | 4 | 3 | cmd_3586/3636/training_L4 | SG-PRE25(軍師precheck) |
| 3 | report_format | 4 | 3 | cmd_3621/3629/3634 | report_field_set.sh |
| 4 | prev_lesson_missing+other | 4 | 4 | cmd_3589/3591/3592/3598 | warn_missing_prev_cmd_lesson |
| 5 | already_delegated | 2 | 2 | cmd_3588/3590 | cmd_delegate.sh guard |
| 6 | other_draft | 2 | 1 | cmd_3598 | other_draft_exists check |
| 7 | warn_escalation | 2 | 1 | cmd_3631 | WARN累計昇格 |
| 8 | required_field | 1 | 1 | cmd_3590 | 必須項目check |

**最大パターン**: bc_fail(7 unique cmds)=忍者の報告品質。将軍起票の品質改善対象外。
**将軍起票品質の最大パターン**: mismatch(3 unique cmds)+warn_escalation(1)+other_draft(1)=5 cmds

## 既存cmd_save機構との差分表 — 家老残穴2反映

| 既存機構 | 場所 | 機能 | v3で追加する差分 |
|---------|------|------|----------------|
| BLOCK SUMMARY | L3334-3343 | 過去Attempt診断表示 | パターン別unique件数を追加表示 |
| build_unique_block_checks_str | L146 | BLOCK check名のユニーク化 | 変更なし(既存維持) |
| Session State | L2689付近 | WARN累計記録 | 変更なし |
| cmd_skeleton.sh | 別ファイル | 雛形生成 | 変更なし |
| **新規: L5パターン集計** | BLOCK SUMMARY内 | 直近10件BLOCKのパターン別集計 | **追加**(既存BLOCK SUMMARYに統合) |

## 改善3軸設計案

### 軸1: 品質(unique BLOCK率8.1%→4%以下)

**mismatch(3 unique cmds)**: SG-PRE25との共通化 — 家老残穴3反映

- **現状**: SG-PRE25(gate_gunshi_report_precheck.sh)にcommand欄ファイル抽出+files_modified照合ロジックが実装済み
- **設計**: SG-PRE25の抽出器を共通関数化(scripts/lib/extract_command_files.sh)。cmd_save.shはこの関数を呼び、抽出結果をINFO表示(Level 5)。SG-PRE25も同関数を使用
- **責務分離**: cmd_save = 起票時のINFO提示(files_modified未確定)。SG-PRE25 = 完了時のBLOCK(files_modified確定後)
- **reference_only標準化**: cmd_3636のBLOCK→CLEAR差分で実証後に判断(保留)

**FP(今セッションD0済み)**: → §D0実装済み節に分離

### 軸2: 速度(preflight 2.08秒→1.0秒以下)

**ms単位計測コマンド** — 家老残穴4反映
```bash
# ms単位プロファイル (date +%s%N使用)
PS4='+ $(date +%s%N) ' bash -x scripts/cmd_save.sh --preflight cmd_XXXX 2>&1 | \
  awk '/^\+ [0-9]+/{ns=$2; sub(/^\+ [0-9]+ /,""); if(prev_ns) printf "%6.1fms %s\n", (ns-prev_ns)/1e6, prev_line; prev_ns=ns; prev_line=$0}' | \
  sort -rn | head -20
```

**改善手順**:
1. 上記コマンドで上位3関数を特定
2. 品質gateを壊さない小粒高速化(CMD_BLOCK_CACHE活用/grep→awk統合等)
3. 既存bats全PASSを確認
4. 効果計測(before/after)

### 軸3: 自動成長(昇格制)

**昇格5段階**(家老指摘5反映: 自動check追加禁止、累計昇格FP増殖防止):

| Level | 動作 | 自動/手動 |
|-------|------|----------|
| L5 | BLOCK SUMMARY内にパターン別集計表示 | 自動(既存BLOCK SUMMARYに統合) |
| L4 | 同一パターン3件→「新check候補」INFO表示(WARN/BLOCKにしない) | 自動 |
| L3 | 候補を軍師/家老がレビュー+FP率計測 | 手動 |
| L2 | レビューPASS→check関数追加cmd起票 | 手動 |
| L1 | 有効化後のBLOCK率/FP率計測 | 自動 |

## D0実装済み (今セッション) — 家老残穴5反映: 別節分離

| 修正 | ファイル | commit | テスト |
|------|---------|--------|--------|
| is_gate_or_hook_addition_cmd project除外 | cmd_save.sh L356 | 未commit(CTX深) | bash -n PASS。cmd_3637 PASS実証 |
| is_gate_or_script_modification_cmd project除外 | cmd_save.sh L445 | 同上 | 同上 |
| check_dm_signal_bare_layer_reference ETL層除外 | cmd_save.sh L4127 | 同上 | 同上 |
| inject_growth_loop_defense project除外 | deploy_task.sh L4018 | 同上 | bash -n PASS |

**検証証跡**: cmd_3637(project=dm-signal)がFP修正後にcmd_save.sh PASSし家老配備済み。cmd_3636(7回BLOCK)の同一条件で通過。

## 検証計画

1. 集計スクリプト: 上記python3コマンドで再現可能
2. SG-PRE25現物: gate_gunshi_report_precheck.shのファイル抽出ロジックを読み、共通関数化の工数を見積もる
3. 速度プロファイル: ms単位コマンドで上位3関数特定
4. bats回帰: test_cmd_save*.bats全PASS
5. D0 commit後のBLOCK率/FP率計測

## 因果鎖
殿指示(品質+速度+自動成長) → 一次データ集計(unique 8.1%) → 正規化8パターン → 家老2往復10件+将軍3件反映 → 3軸設計(共通関数化/ms計測/昇格制) + D0実装済み4箇所分離
