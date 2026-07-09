# cmd_3807 gate_gunshi_report_precheck.sh git履歴走査統合

Date: 2026-07-10
Worker: saizo
Target: `scripts/gates/gate_gunshi_report_precheck.sh`
Purpose: 軍師実測13.4秒/将軍再現10.9秒(2026-07-10 00:26-00:32)。毎レビュー実行されるgateがgit全履歴走査を
多重実行しており軍師レビューのスループットを恒常的に阻害している。将軍のPS4行別プロファイルでホットスポット
4箇所を特定済み: L627(per-file git log 2回3.8s)+L563(git log --grep全履歴numstat 2回1.2s)+L347(因果リンク解決
timeout 3s)+L176(0.85s)。走査を1回に統合し出力等価のまま高速化する。

## Before (現物確認: git stashで原本を再現し計測)

原本コードは以下3箇所で同一REPO_ROOT(またはPROJECT_DIR)に対し`git log --grep="${PARENT_CMD}"`の全履歴走査を
独立に実行していた:

| 箇所 | 行番号(原本) | 出力形式 | 用途 |
|---|---|---|---|
| SG-PRE3 (Batch git data) | L120 | `--name-only` | commit検証(ファイル存在照合) |
| SG-PRE13 | L351 | `--numstat` | hook/gate系ファイルの大規模削減検出 |
| SG-PRE19 (no-hash分岐) | L567(REPO_ROOT) + L574(DM_SIGNAL_PATH) | `--numstat` | changed_lines合計 |

PROJECT_DIR==REPO_ROOT(DM-Signal以外の報告。実運用最頻出)の場合、L120/L351/L567は**同一リポジトリへの
実質的に同一の全履歴grep走査を3回**実行しており、DM-Signal報告(IS_DM_SIGNAL=1)の場合は最大4回
(PROJECT_DIR用1回+REPO_ROOT用1回×PRE13/PRE19-2回)実行していた。

### PS4行別プロファイル実測(cmd_3804報告, no-hash分岐, PROJECT_DIR==REPO_ROOT)

Method: `PS4='+ [${EPOCHREALTIME}] ${BASH_SOURCE}:${LINENO}: '; bash -x scripts/gates/gate_gunshi_report_precheck.sh <report>` の
トレースログを行単位でdelta集計。

| rank | 行 | 内容 | 所要時間 |
|---|---|---|---:|
| 1 | L351 (SG-PRE13) | `git log --grep=cmd_3804 --numstat`(REPO_ROOT) | 1.234s |
| 2 | L120 (SG-PRE3) | `git log --grep=cmd_3804 --name-only`(REPO_ROOT) | 1.213s |
| 3 | L563/567 (SG-PRE19) | `git log --grep=cmd_3804 --no-merges --fixed-strings --numstat`(REPO_ROOT) | 1.177s |
| 4 | L973 (SG-PRE31) | N×M意味検算(範囲外) | 0.530s |
| 5 | L667 (SG-PRE22) | semantic_search呼出(範囲外) | 0.457s |

上位3件(3.624s / 全体6.234sの58%)がすべて**同一REPO_ROOTへの重複全履歴--grep走査**であることを実測で確認。
これが軍師報告のPS4プロファイルで指摘された「L627/L563/L347/L176」のホットスポット群の実体。

### 時間計測(`time`, 環境ノイズを避け同一fixtureで前後比較。各3回、非クラッシュ実行のみ集計)

| シナリオ | fixture | before(avg) | after(avg) | 削減率 |
|---|---|---:|---:|---:|
| no-hash / PROJECT_DIR==REPO_ROOT(3→1走査) | cmd_3804報告(dm-signal, 4files, commitなし) | 8.56s (9.42, 7.70) | 4.06s (3.70, 4.23, 4.24) | **-52.6%** |
| hash-path / PROJECT_DIR==REPO_ROOT(PRE13のみ元々1走査。回帰なし) | infra報告(commit hashあり) | 9.23s (8.87, 10.55, 8.26) | 7.49s (9.29, 6.89, 6.28) | -18.9%(WSL2環境ノイズの範囲。構造的差分なし) |
| no-hash / PROJECT_DIR≠REPO_ROOT(4→2走査) | cmd_3786報告(dm-signal, IS_DM_SIGNAL=1) | 5.31s (4.33, 4.95, 6.64) | 3.94s (3.14, 5.70, 2.98) | -25.8% |

備考: 環境はninja_monitor常駐+他忍者稼働中のWSL2共有環境のため、同一コード・同一入力でも実行時間の分散が
大きい(4.3s〜10.5s)。「before」は`git stash`で原本を一時復元し同一fixtureで直接計測した。

## 統合設計

冒頭のBatch git dataセクションで、numstat出力の3列目(path)がname-only相当であることを利用し、
1回のnumstat走査結果をPRE3/PRE13/PRE19の3チェックで共有する構成へ統合。

- `_PRE_PROJECT_NUMSTAT`: `${PROJECT_DIR:-$REPO_ROOT}`のnumstat(no-hash時のみ1回)。SG-PRE3のfile一覧(3列目抽出)
  とSG-PRE19のDM-Signal合計が共用(IS_DM_SIGNAL=1の時PROJECT_DIR==DM_SIGNAL_PATHが保証されるため安全に共用可)。
- `_PRE_REPO_NUMSTAT`: REPO_ROOTのnumstat。SG-PRE13は hash有無に関わらず全履歴grep走査が必要(元の挙動を維持)
  なため独立にガード。PROJECT_DIR==REPO_ROOT(非DM-Signal報告)の場合は`_PRE_PROJECT_NUMSTAT`をそのまま再利用し
  git呼出を追加0回にする。PROJECT_DIR≠REPO_ROOTの場合のみ別途1回スキャンする。

フラグ差異(`--no-merges --fixed-strings`の有無)による出力差の有無を統合前に実データで検証:

```
$ git log --grep="cmd_3804" --format="" --numstat
$ git log --no-merges --fixed-strings --grep="cmd_3804" --format="" --numstat
$ diff <(...) <(...) | wc -l
0
```
(cmd_3804/cmd_3786/cmd_training_speed_yaml_auto_archive_...の3つのPARENT_CMD値で検証、全てdiff 0行。
PARENT_CMDは英数字+アンダースコアのみで正規表現メタ文字を含まず、git logは`--numstat`時にmerge commitの
diffをデフォルトで出力しないため、`--no-merges --fixed-strings`追加は挙動に影響しない。)

numstat 3列目からのname-only導出も実データで検証:

```
$ git log --grep="cmd_3804" --format="" --name-only | sort -u
$ git log --no-merges --fixed-strings --grep="cmd_3804" --format="" --numstat | awk -F'\t' 'NF>=3{print $3}' | sort -u
$ diff <(...) <(...) | wc -l
0
```

## 出力等価性検証(AC1: diff行数0)

同一report入力に対し、`git stash`で原本を再現した「修正前」と現行コードの「修正後」の標準出力をdiff。

| fixture | 分岐 | before行数 | after行数 | diff行数 |
|---|---|---:|---:|---:|
| cmd_3804報告 | no-hash, PROJECT_DIR==REPO_ROOT | 131 | 131 | **0** |
| infra報告(commit hashあり) | hash-path | 131 | 131 | **0** |
| cmd_3786報告 | no-hash, PROJECT_DIR≠REPO_ROOT (SG-PRE22手前でSIGPIPE) | 113(共通到達点まで) | 113 | **0** |

3種の分岐(hash有/no-hash×PROJECT_DIR==REPO_ROOT/no-hash×PROJECT_DIR≠REPO_ROOT)すべてでdiff行数0を確認。

## 既知の別事象(スコープ外・decision_candidateへ記録)

cmd_3786報告(IS_DM_SIGNAL=1)を入力にすると、SG-PRE22(semantic_search呼出)付近で`set -euo pipefail`下の
SIGPIPE(exit 141)が原本コード・修正後コードの両方で再現する(既存バグ、本cmdのgit履歴走査統合とは無関係)。
`_sem_result=$(... | head -5)`の`head`早期終了によるSIGPIPEが疑われる。修正前後で同一行数(113行)・同一箇所で
再現することを確認済みで、本cmdによる新規リグレッションではない。

## Verification (AC2)

対象gate関連batsテスト(`gate_gunshi_report_precheck.sh`を直接テストする8ファイル):

```bash
bats tests/unit/test_gate_gunshi_precheck_large_artifact.bats \
     tests/unit/test_gate_gunshi_precheck_sg_pre30.bats \
     tests/unit/test_gate_gunshi_precheck_sg_pre31.bats \
     tests/unit/test_gate_gunshi_precheck_sg_pre32.bats \
     tests/unit/test_gate_gunshi_precheck_sg_pre9c_scope.bats \
     tests/unit/test_gate_hot_path_no_sync_io.bats \
     tests/unit/test_sg_pre24_generated_penetration.bats \
     tests/unit/test_cmd_complete_gate_gunshi_verdict_precheck.bats
```

Result: **54/54 PASS, 0 SKIP, 0 FAIL**

`tests/unit/test_learning_ops_small_consolidated.bats`内のSG-PRE9関連3件も含め全PASS。同ファイル内で
`test_causal_backlinks.bats`/`test_lesson_harvest.bats`系4件が`rg`未インストール+データ陳腐化により
`not ok`だったが、`git stash`で原本コードに戻して同一テストを実行しても同一4件が同一理由でFAILすることを確認し、
本cmdの変更とは無関係な既存の環境起因失敗であると特定した(`scripts/test_select.sh scripts/gates/gate_gunshi_report_precheck.sh`
の選択結果は"no test mapping"で空だったため、命名規則から漏れているこれら関連テストを直接特定して実行した)。

Note: `bash scripts/test_select.sh scripts/gates/gate_gunshi_report_precheck.sh` は"no test mapping"を返す
(テストファイル命名が`test_gate_gunshi_precheck_*.bats`でありスクリプト名`gate_gunshi_report_precheck.sh`との
命名規則マッチングに乗らないため)。将来的な改善余地としてdecision_candidateに記録。
