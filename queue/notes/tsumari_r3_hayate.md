# 領域 (e) hook/CLI 摩擦 — tsumari 第3回

- 抽出窓: `2026-09-03T04:37:00+09:00` 〜配備時刻 `2026-09-03T11:03:05+09:00`
- 対象: `logs/hook_artifacts/*pre-push*`、`logs/hook_artifacts/` の pre-bash 文言、`.codex/hooks.json` と `.claude/settings*.json`、`logs/inbox_codex_delivery_verify/`、`logs/ninja_monitor.log`
- 対象外: 上記以外のログ、他領域のログ、本番ファイル・daemon・gateの変更

## AC1 抽出コマンドと生出力

### pre-push artifact

抽出コマンド:

```bash
find logs/hook_artifacts -maxdepth 1 -type f -name '*pre-push*' \
  -newermt '2026-09-03T04:37:00+09:00' ! -newermt '2026-09-03T11:03:05+09:00' \
  -printf '%f\n' | sort | wc -l
```

生出力:

```text
14
```

抽出コマンド:

```bash
while read -r f; do
  rg -n 'FAILURE_DIAGNOSTIC: not ok|GA-PUSH1' "logs/hook_artifacts/$f"
done < /tmp/hayate_pre_push_files.txt | sed -E 's/ in [0-9]+ms$//' | sort | uniq -c
```

生出力（同一artifact内の診断再掲を含む）:

```text
10 FAILURE_DIAGNOSTIC: not ok 3 C2a mismatch moves request to rc and notifies karo
10 FAILURE_DIAGNOSTIC: not ok 6 publisher notifications use an allowed wake type
 8 FAILURE_DIAGNOSTIC: not ok 29 NO_MATCH purpose: cmd_complete queues pending aliases and L7f absorbs similar aliases
 2 FAILURE_DIAGNOSTIC: not ok 14 capture replaces manifest.base with merge-base when source merged origin/main
 2 FAILURE_DIAGNOSTIC: not ok 15 capture keeps deploy base when source did not merge origin/main
 2 FAILURE_DIAGNOSTIC: not ok 8 SG-PRE21 causal_backlinks tmpdir leaves no residue after a normal run
 2 FAILURE_DIAGNOSTIC: not ok 7 active publishes parent-one commit and synchronizes clean root
 2 FAILURE_DIAGNOSTIC: not ok 2 mixed batch moves only the failed op to rc and leaves origin unchanged
 2 FAILURE_DIAGNOSTIC: not ok 1 insight writer emits an op and publisher applies one active ledger commit
 1 [pre-push] BLOCK(GA-PUSH1): pushしようとしているcommitと、作業ツリーの未commit変更が同一pathを差している。
```

集計コマンド:

```bash
awk 'BEGIN{files=0;ga=0;notok=0;rf=0;rr=0} /^timestamp:/{files++} /GA-PUSH1/{ga++} /FAILURE_DIAGNOSTIC: not ok/{notok++} /TEST_RECEIPT_FAIL/{rf++} /RECEIPT_REUSE_REJECT/{rr++} END{printf "files=%d GA-PUSH1_lines=%d not_ok_lines=%d receipt_fail_lines=%d reuse_reject_lines=%d\n",files,ga,notok,rf,rr}'
```

生出力:

```text
files=14 GA-PUSH1_lines=1 not_ok_lines=40 receipt_fail_lines=26 reuse_reject_lines=5
```

代表一次証拠:

- `logs/hook_artifacts/20260903T054555_pre-push_2569472.log:42-45`: `test_publisher.bats` の test 3 が line 81 の status assertion で失敗。
- `logs/hook_artifacts/20260903T062706_pre-push_3467154.log:79-82`: `test_publish_artifact.bats` の test 14 が line 370 の remote push で失敗。
- `logs/hook_artifacts/20260903T063449_pre-push_3588090.log:101-103`: `test_gate_gunshi_report_precheck_direct_hash.bats` の test 8 が `after_count != before_count` で失敗。
- `logs/hook_artifacts/20260903T071848_pre-push_120820.log:113-115`: semantic index test 29 が期待文字列 `PENDING_ALIAS_SCORE` 不在で失敗。
- `logs/hook_artifacts/20260903T072109_pre-push_159736.log:107-110`: publisher ledger test 2 が status assertion で失敗。
- `logs/hook_artifacts/20260903T072541_pre-push_215308.log:162-164`: publisher ledger test 1 が ledger file count assertion で失敗。
- `logs/hook_artifacts/20260903T091546_pre-push_1440067.log:21`: GA-PUSH1 が同一pathの未commit変更を理由にBLOCK。

### pre-bash BLOCK 文言

抽出コマンド:

```bash
find logs/hook_artifacts -maxdepth 1 -type f \
  -newermt '2026-09-03T04:37:00+09:00' ! -newermt '2026-09-03T11:03:05+09:00' -print0 \
  | xargs -0 rg -n -i 'pre-bash|karo-retest|yaml_dump|sed/grep' | wc -l
```

生出力:

```text
0
```

`run_tests` 文言の別集計:

```bash
find logs/hook_artifacts -maxdepth 1 -type f \
  -newermt '2026-09-03T04:37:00+09:00' ! -newermt '2026-09-03T11:03:05+09:00' -print0 \
  | xargs -0 rg -n 'run_tests' | wc -l
```

```text
78
```

### Codex と Claude の hook 差

抽出コマンド:

```bash
for f in .codex/hooks.json .claude/settings.json .claude/settings.local.json; do
  jq -r '.hooks // {} | to_entries[] | "\\(.key):\\(.value|length)"' "$f"
  jq -r '[.hooks // {} | .. | objects | .command? // empty] | length' "$f"
done
```

生出力:

```text
.codex/hooks.json: PreToolUse:1 SessionStart:1 UserPromptSubmit:1 PostToolUse:1 ; hook_commands=8
.claude/settings.json: SessionStart:1 PreToolUse:1 PostToolUse:1 Stop:1 SessionEnd:1 UserPromptSubmit:1 ; hook_commands=12
.claude/settings.local.json: PreToolUse:2 PostToolUse:0 PreCompact:1 Stop:0 SessionStart:1 ; hook_commands=4
```

差分の観測事実:

- Codex固有: `codex_inbox_priority_guard.sh`、`codex_skill_execution_guard.sh`、`codex_session_start.sh`、`codex_user_prompt_submit.sh`、`pre-bash-combined.sh`、`post-bash-combined.sh`。
- Claude固有: `pretool-dispatch.sh`、`posttool-dispatch.sh`、Stop/SessionEnd、`log_terminal_input.sh`、`log_terminal_response.sh`、`pre_compact_save.sh`。

### Codex delivery verify

抽出コマンド:

```bash
find logs/inbox_codex_delivery_verify -maxdepth 1 -type f \
  -newermt '2026-09-03T04:37:00+09:00' ! -newermt '2026-09-03T11:03:05+09:00' -print0 \
  | xargs -0 awk '/ASYNC_VERIFY (START|SKIP|FAILURE)/{print $0}' | awk '{print $2}' | sort | uniq -c
```

生出力:

```text
73 START
56 SKIP
17 FAILURE
```

failure target集計:

```text
5 hanzo
5 hayate
2 kagemaru
5 saizo
```

failureの共通生出力:

```text
[inbox_write] codex watcher dedup rearmed 5/5 for hayate (...)
[inbox_write] WARN: codex delivery remained unverified for hayate after 5 retries
[2026-09-03T05:14:39] ASYNC_VERIFY FAILURE target=hayate ... status=1
```

出典: `logs/inbox_codex_delivery_verify/msg_20260903_051429_2022740_36854416.log:1-8`。同一形式の17件を確認。

### ninja_monitor Codex固有行

抽出コマンド:

```bash
awk '$0 ~ /^\\[2026-09-03 / {ts=substr($0,2,19); if (ts >= "2026-09-03 04:37:00" && ts <= "2026-09-03 11:03:05") print}' logs/ninja_monitor.log > /tmp/hayate_monitor_window.txt
rg -c '^\\[.*\\] CODEX-RESPAWN:' /tmp/hayate_monitor_window.txt
rg -c '^\\[.*\\] CTX-RESET:.*CODEX-RESPAWN' /tmp/hayate_monitor_window.txt
rg -c '^\\[.*\\] WARN: CODEX-MODEL-CAPTURE-MISMATCH' /tmp/hayate_monitor_window.txt
rg -c '^\\[.*\\] RESPAWN-PANE:' /tmp/hayate_monitor_window.txt
rg -c 'Working spinner' /tmp/hayate_monitor_window.txt
```

生出力:

```text
CODEX-RESPAWN=45
CTX-RESET after CODEX-RESPAWN=45
CODEX-MODEL-CAPTURE-MISMATCH=45
RESPAWN-PANE=6
Working spinner=0
```

代表一次証拠:

- `logs/ninja_monitor.log:241-243`: hayate の `CODEX-RESPAWN`、CTX reset、`actual_capture=unavailable`。
- `logs/ninja_monitor.log:16413-16415`: 配備直前にも hayate で同じ3行が再発。

## AC2 事例表

分類軸は、task指定の8分類（偽陽性 / 過剰 BLOCK / 構造バグ / 循環拘束 / 遅い script・test / Claude↔Codex 仕組み差 / サンクコスト過剰複雑化 / 影響範囲・依存未解明の浅い対応）で固定した。根因が同じ反復は1事例に集約し、発生数を記載した。

| ID | 時刻・発生数 | 事象 | 主分類 | 副分類 | 真因（一次ログで確認できる範囲） | 根治済/未根治 | 次の一手 | log引用 |
|---|---|---|---|---|---|---|---|---|
| T3-hayate-01 | 05:45:55〜07:21:09、5 artifacts | publisherのC2a mismatch test 3 と wake type test 6 が各5回失敗 | 構造バグ | publisher status/notification contract | `test_publisher.bats:81` と `:122` の status assertion failure | 未根治 | 同じfixtureを独立再実行し、実statusとpublisher分岐を行単位で採取 | `logs/hook_artifacts/20260903T054555_pre-push_2569472.log:42-45` |
| T3-hayate-02 | 06:27:06、1 artifact | publish_artifactのmerge-base/deploy-base capture test 14/15 が失敗 | 影響範囲・依存未解明の浅い対応 | remote HEAD fixture依存 | test 14 は remote push command failure、同artifactに `remote HEAD refers to nonexistent ref` | 未根治 | fixture remote HEADを明示生成して両分岐を再実行し、失敗箇所を分離 | `logs/hook_artifacts/20260903T062706_pre-push_3467154.log:79-82` |
| T3-hayate-03 | 06:34:49、1 artifact | SG-PRE21 normal runでtmpdir残数が変化 | 構造バグ | cleanup residue | `after_count` と `before_count` の不一致 | 未根治 | 同一testを単独実行し、残存pathの一覧と作成元を採取 | `logs/hook_artifacts/20260903T063449_pre-push_3588090.log:101-103` |
| T3-hayate-04 | 07:02:23、1 artifact | active publisherのparent-one test 7 が失敗 | 構造バグ | publisher active path | test line 130 の `[ "$status" -eq 0 ]` assertion failure | 未根治 | active pathを単独再実行し、statusを発生分岐と対応付ける | `logs/hook_artifacts/20260903T070223_pre-push_4030240.log:49-52` |
| T3-hayate-05 | 07:18:48〜07:23:25、4 artifacts | semantic indexのNO_MATCH test 29が期待alias scoreを出力しない | 構造バグ | pending alias resolution | `PENDING_ALIAS_SCORE: 意味検索改善 -> semantic_dictionary_design` の期待値不在 | 未根治 | semantic index updateを単独実行し、入力alias・出力候補・score生成点を記録 | `logs/hook_artifacts/20260903T071848_pre-push_120820.log:113-115` |
| T3-hayate-06 | 07:21:09、1 artifact | ledger mixed batch test 2 が失敗 | 構造バグ | rc/origin isolation | test line 61 の status assertion failure | 未根治 | mixed batchを単独再実行し、failed opのrc化とorigin不変を別々に計測 | `logs/hook_artifacts/20260903T072109_pre-push_159736.log:107-110` |
| T3-hayate-07 | 07:25:41、1 artifact | ledger active insight test 1 が期待ledger file count 1を満たさない | 構造バグ | active ledger publication | `find .../ledger_inbox/insights ... | wc -l` の `-eq 1` assertion failure | 未根治 | insight write→publisherを単独実行し、ledger投入前後のfile countを採取 | `logs/hook_artifacts/20260903T072541_pre-push_215308.log:162-164` |
| T3-hayate-08 | 09:15:46、1 artifact | push対象commitと作業ツリー未commit変更の同一pathをpre-pushがBLOCK | 過剰 BLOCK | shared worktree overlap | `GA-PUSH1` が同一path重複を理由にexit 1 | 未根治 | shared index/worktreeの重複検知を独立fixtureで再現し、正規の解消経路とpass後証跡を採取 | `logs/hook_artifacts/20260903T091546_pre-push_1440067.log:21` |
| T3-hayate-09 | 05:14:39〜11:01:21、delivery FAILURE 17件・monitor mismatch 45件 | Codex watcherが5回再送後もdelivery未検証、monitorがcapture unavailableを記録。Working spinnerは0件 | Claude↔Codex 仕組み差 | Codex delivery/capture観測 | deliveryは`dedup rearmed 5/5`後`status=1`、monitorは`actual_capture=unavailable` | 未根治 | Codex watcherの確認対象とpane capture取得経路を同一時刻の一次ログで連結し、成功時のcapture証跡を追加 | `logs/inbox_codex_delivery_verify/msg_20260903_051429_2022740_36854416.log:1-8`; `logs/ninja_monitor.log:241-243` |

## 集計

### 主分類別

| 主分類 | 事例数 |
|---|---:|
| 偽陽性 | 0 |
| 過剰 BLOCK | 1 |
| 構造バグ | 6 |
| 循環拘束 | 0 |
| 遅い script・test | 0 |
| Claude↔Codex 仕組み差 | 1 |
| サンクコスト過剰複雑化 | 0 |
| 影響範囲・依存未解明の浅い対応 | 1 |
| 合計 | 9 |

根治済 `0` / 未根治 `9`。全9事例に一次ログ引用があり、false_positive `0` 行。未根治条件が残るためAC3の判定はBLOCKとする。

## AC3

- gate/hook未解消: `GA-PUSH1` 1件、Codex delivery FAILURE 17件、Codex capture mismatch 45件。PASSへ進めずBLOCK。
- 推測語カウント: `0`。
