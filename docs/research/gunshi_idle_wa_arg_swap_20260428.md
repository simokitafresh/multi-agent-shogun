# karo_workaround_log.sh 引数順序逆転バグ分析

発見日: 2026-04-28
発見者: gunshi (idle自走 Step 1: karo_workarounds直近10件分析)

## 症状

直近4件(cmd_2351-2354)のworkaround記録でcmd_idとninjaフィールドが入れ替わっている:
- `cmd_id: saizo, ninja: cmd_2351` (正: `cmd_id: cmd_2351, ninja: saizo`)
- `cmd_id: hayate, ninja: cmd_2352` (正: `cmd_id: cmd_2352, ninja: hayate`)
- `cmd_id: saizo, ninja: cmd_2353`
- `cmd_id: hayate, ninja: cmd_2354`

## 根因

家老が `karo_workaround_log.sh --clean <ninja_name> <cmd_id>` と引数を逆順で渡した。
スクリプトのUsageは `--clean <cmd_id> <ninja_name>` だが、`validate_ninja_id`はWARNのみでBLOCKしない。

## 修正 (D0直接実装)

`validate_ninja_id`の後に引数順序チェックを追加:
- cmd_idが`cmd_`パターン不一致 AND ninjaが`cmd_`パターン一致 → 自動スワップ+WARN出力
- commit: 29efd36f

## 因果鎖

家老が引数逆順で呼出し → validate_ninja_idがWARNだがBLOCK不能 → cmd_id/ninja入替わりで記録 → workaround統計の忍者別集計が歪む可能性 → 自動スワップで再発防止

## LG014実践

「忍者/家老ミスに見える問題はインフラ真因を疑え」のパターン。
表面: 家老の引数ミス。真因: バリデーションがWARN止まりで防御不足。
