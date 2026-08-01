# hidden-infra汚染rollback設計書 — AsIs/ToBe 5W1H

- 版: v1.1 (2026-08-01 15:31 家老一次検証反映)
- 発端: 殿下知2026-08-01 15:15「汚染設計書に基づく作業が仕組みを破壊し尽くしている。作業開始前に一気に戻ることをおすすめする」
- レビュー: 家老RC反映済み(分類・競合手順を一次結果で修正)
- 実行状態: 未実行(設計書レビュー→殿裁可→実行の順)

## §0 結論(1行)

hidden-infra作業(07-31 19:05開始)が本番運用スクリプト3本+新設durable_state系へ入れた変更を、巻き添えゼロの分類に基づき「ファイル復元」と「commit逆適用」の2手で除去し、bats+実runtime整合で検証する。

## §1 AsIs(現状 — 全て一次データで確定済み)

### 1.1 汚染の起点と範囲
| 項目 | 値 | 一次データ |
|------|-----|-----------|
| 作業開始 | 2026-07-31 19:05:44 (c2e7ad06e Gate0 contract) | git log --date=iso |
| 健全な戻り点 | f3478e625235 (開始直前commit) | git rev-parse c2e7ad06e^ |
| 開始以降の総commit | 133 | git rev-list --count |
| うちhidden-infra系 | 46 | git log --grep 集計 |
| うち無関係(保持必須) | 87 | 同上(grep -v) |

### 1.2 中核コードへの侵入(ファイル別・全数検分済み)
| ファイル | hidden-infra変更 | 非hidden-infra変更(巻き添えリスク) | 分類 |
|---------|-----------------|----------------------------------|------|
| scripts/lib/durable_state.py | 8 commits(新設) | 0件 | A: 全削除可 |
| scripts/lib/durable_state.sh | 3 commits(新設) | a5f648ff0(orphan dispatcher wire 14:33。ただしguarded-yaml-set=hidden-infra派生機能の配線であり実質同系) | A': 全削除可(家老レビューで同系判定の確認要) |
| tests/unit/test_durable_state.bats | 9 commits(新設) | 0件 | A: 全削除可 |
| scripts/auto_deploy_next.sh | 4 commits | 0件 | B: f3478e625時点へファイル復元 |
| tests/unit/test_auto_deploy_next.bats | 5 commits | 0件 | B: 同上 |
| scripts/ninja_monitor.sh | R03 startup reconciliation | formal fail-close判定・dedupe・即clear修正は保持必須 | C: commit逆適用禁止。reconciliation hunkだけ除去 |
| scripts/deploy_task.sh | da8993f1d owner transaction + 4b2ebade6 continuation | gitignore分類・AC fingerprint・lesson matcher・context gate deferは保持 | C: 対象hunkだけ除去 |
| tests/unit/test_lock_path.bats | 新設 | 0件 | A: 全削除可(戻り点にファイルなし) |
| tests/unit/test_deploy_task.bats | 4b2ebade6の隔離stub | lesson matcherは保持 | C: 4b2ebade6の対象hunkだけ除去 |
| tests/unit/test_auto_deploy_next.bats | 新設 | 0件 | A: 全削除可(戻り点にファイルなし) |
| docs/research/hidden-infrastructure-*(設計書・manifest・receipt群) | 約50 commits | — | D: 触らない(履歴として無害。campaign停止済み・STOPPED_BY_LORD) |

### 1.3 因果(時系列一致)
R03 owner transaction(08-01 09:30/09:47/11:01)+R05 deploy selector(08-01 13:42)が運用スクリプトへ入った後、本日の運用障害が発生:
- 半蔵・飛猿のfail-close膠着/auto-clear不収束(14時台、家老が手動白紙化+コード修正で対処)
- report notification structured identity BLOCK(14:50 将軍実測)
- レビューWARN率50%エスカレーション(cmd_4204で別途是正済み)

### 1.4 既に完了している封じ込め
- 家老がcampaign停止(1d55a05c 14:49)、canonical manifest=STOPPED_BY_LORD、半蔵・飛猿白紙化、失敗worker即clear修正(ef717c4e7)
- 誤配線の残骸: なし(inbox未読0・稼働はhayate cmd_4205のみ)

### 1.5 関連するが本設計書のスコープ外
- [MEM:]引用強制hookの二重出力バグ(07-15導入 d8ed01688)は汚染設計書由来ではない別系統。別途扱う
- 未push 66+ commits(CI GREEN確認済み・rollback完了後にpush判断)

## §2 ToBe(あるべき状態)

1. 運用中核(deploy_task.sh / ninja_monitor.sh / auto_deploy_next.sh)からhidden-infra由来の変更が0行(git diffで機械検証可能)
2. 新設汚染ファイル5本(durable_state系3本+auto_deploy/lock test 2本)がツリーから消滅し、参照元0件(rg検証)
3. 本日の正当修正87 commits分の成果は全て無傷で保持
4. 全unit bats FAIL=0・SKIP=0、かつ実runtime(deploy→report→GATEの1周)が正常
5. docs(設計書・manifest)は履歴として残置、STOPPED_BY_LORDのまま

## §3 5W1H

- **WHY**: hidden-infra実装が運用スクリプトへ持ち込んだowner transaction/selector変更が、本日の配備・終端・clear機構の膠着群と時系列一致。殿裁定「現形の継続禁止」+15:15下知「作業開始前に戻る」。選別revertはLLMの選別ミスリスク(LS099)があるため、分類A/B(ファイル復元)を主とし、巻き添えが実在するC群のみ最小のcommit逆適用にする
- **WHAT**: §1.2の分類どおり — A/A': 新設5ファイルを削除、B: scripts/auto_deploy_next.shだけをf3478e625時点へ復元、C: ninja_monitor.sh/deploy_task.sh/test_deploy_task.batsから汚染hunkだけを除去し、正当な後続修正を保持
- **WHEN**: 家老レビューCLEAR→殿裁可の直後、hayateのcmd_4205完了を待たずに実行可(対象ファイルとhayate作業スコープの重複はcmd_4205=cmd_save/skeleton系で重複なし。実行直前にtask YAMLのplanned_pathsで再確認)
- **WHERE**: multi-agent-shogun repo main、ローカルtree(push前)。本番DM-signalには一切触れない
- **WHO**: 実行=家老差配(忍者1名で直列。破壊的操作のためTier2手順=対象リスト提示→将軍検分→実行)。検証=軍師レビュー+将軍がgit diff f3478e625 -- <対象>で0差分を一次検分
- **HOW**: (1)A群: 戻り点に存在しない新設5ファイルだけを削除 (2)B群: scripts/auto_deploy_next.shだけをf3478e625時点へ復元 (3)C群: commit丸ごとのrevertは禁止し、上記3ファイルの対象hunkだけを除去 (4)検証: bash scripts/run_tests.sh(対象影響suite選択実行)FAIL=0 SKIP=0→deploy→report 1周の実機smoke (5)commit(scope明示)→報告

## §4 採用二値AC(実行cmd/家老直接配備の契約)

- AC1: 対象9ファイルについて`git diff f3478e625..HEAD -- <path>`のhidden-infra由来差分が0行(C群は非hidden-infra 7commit分の差分のみ残存)か(yes/no)
- AC2: durable_state参照が運用コードから0件(`rg -l durable_state scripts/ --glob '!lib/durable_state*'`→0)か(yes/no)
- AC3: 影響suite選択実行でFAIL=0・SKIP=0、かつdeploy→report終端1周のsmokeが正常か(yes/no)

## §5 リスクと未解決

- R1(実測済み): `git apply --reverse --check`はdeploy_taskのda8993f1d、deploy_task/testの4b2ebade6、ninja_monitorの0f4a9c887でPASSし、ninja_monitorのda8993f1dだけFAIL。da8993f1dには保持必須のformal-close判定が混在するため、ninja_monitorはstartup reconciliation hunkだけ除去する
- R2: durable_state削除でa5f648ff0のdispatcher配線が孤児参照になる→AC2のrg検証で捕捉
- R3(解決): active_context_gate_transient(7a4748678/fd4741d34/da05eab82/f6fba29d6)はdurable_state参照0で、active owner中のcontext gate誤報を止める独立hotfix。hidden-infra rollback対象へ加えず保持する

## 因果リンク
origin: [[殿下知_汚染設計書破壊確認_20260801]] -> [[hidden-infra運用スクリプト侵入7ファイル]] -> [[分類別rollback設計]]
