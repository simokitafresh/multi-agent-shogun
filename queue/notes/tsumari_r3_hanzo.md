# つまり 第3回偵察 — 領域 (f) X運用 lane / doc lane

- 領域: (f) X運用 lane と doc lane
- 抽出窓: `2026-09-03T04:37:00+09:00` 〜 配備時刻 `2026-09-03T11:44:24+09:00`（task issued_at）
- parent_cmd: `cmd_karo_recon2_4470_f_xlane_doclane_202609031100`
- 担当: hanzo
- 分類軸: 偽陽性 / 過剰 BLOCK / 構造バグ / 循環拘束 / 遅い script・test / Claude↔Codex 仕組み差 / サンクコスト過剰複雑化 / 影響範囲・依存未解明の浅い対応
- 対象外: 他領域の log、ソースコードの診断文字列、実装変更、本番 file・daemon・gate の変更

## AC1: 一次 log source の所在・抽出コマンド・件数

### `queue/gates/cmd_4467*/`

抽出コマンド:

```bash
find queue/gates/cmd_4467 -type f | awk 'END{print "cmd_4467_files=" NR+0}'
```

生出力:

```text
cmd_4467_files=42
```

```bash
rg --no-ignore -n -i 'SCOPE DRIFT|context_freshness|state=|tests_fail=|tests_missing=|nodes_without_tests|WAIT:UNPUSHED|source publication|WARN|FAIL|DOC_LANE|not found' queue/gates/cmd_4467 | awk 'END{print NR+0}'
```

生出力:

```text
22
```

主要行:

- `cmd_complete_gate.trigger.log:146-148`: `SCOPE DRIFT: 2/5 file(s) outside target_path`、対象は `scripts/x_ops/x_post_gate.sh` と `tests/unit/test_x_post_gate.bats`。
- `semantic_causal_audit.result:1-8`: `state=FAIL`、`tests_fail=2`、`tests_missing=11`、`nodes_without_tests=86`。
- `context_freshness_doc_lane.warning:1-4`: `result: warning`、`source commits 1件` の `ALERT`。
- `cmd_complete_gate.trigger.log:175-181`: `WAIT: UNPUSHED`、`AUTO_PUSH_WAIT ... source_publication_failed`、`GATE WAIT: report_commit_main_ancestry`。

### `queue/gates/cmd_karo_hotfix_x_post_gate*/`

抽出コマンド:

```bash
find queue/gates/cmd_karo_hotfix_x_post_gate_blocklist_fail_close_202609031003 -type f | awk 'END{print "x_post_gate_files=" NR+0}'
```

生出力:

```text
x_post_gate_files=41
```

```bash
rg --no-ignore -n -i 'state=|result:|ALERT|WARNING|ERRORS=|fail-close|showcase|signals|API|entry not found|scope|blocklist' queue/gates/cmd_karo_hotfix_x_post_gate_blocklist_fail_close_202609031003 | awk 'END{print NR+0}'
```

生出力:

```text
58
```

主要行:

- `single_review_manifest.json:8-10`: 公開 `showcase API` に holding が非公開で、認証付き `signals API` を正本にして fail-close 化した因果。
- `single_review_manifest.json:20-27`: `blocklist` を signals API へ切替、API 不達・空を `exit 1` とした実測記録。
- `single_review_manifest.json:35`: `[[cmd_4467_gate欠陥]] -> [[signals_API_blocklist]] -> [[LGTM]]`。
- `context_freshness.warning` 相当の source は `result: clear`、`semantic_causal_audit.log` は `state=PASS` で、修正後の同 hotfix は収束済み。

### `logs/publish_direct_commit*.log`

```bash
find logs -maxdepth 1 -type f -name 'publish_direct_commit*.log' -print | awk 'END{print NR+0}'
```

生出力:

```text
0
```

該当 source は存在しない。

### `logs/hook_artifacts` の U1b ff-only 失敗 `rc=8`

```bash
rg --no-ignore -n -i 'U1b|ff-only|rc=8' logs/hook_artifacts | awk 'END{print NR+0}'
```

生出力:

```text
0
```

該当する hook artifact 行は存在しない。U1b の記録は今回の指定 source ではなく、別領域の記録を代用しない。

### bulletin `entry not found`

実行ログだけを対象にした抽出:

```bash
rg --no-ignore -n -i 'entry not found' queue/bulletin_board.yaml logs \
  --glob '*.log' --glob '*.yaml' --glob '*.jsonl' \
  --glob '*bulletin_confirm*' --glob '*bulletin_action*' | awk 'END{print NR+0}'
```

生出力:

```text
0
```

`logs/wave-final-checkpoints/*/tree/scripts/bulletin_confirm.sh` と `bulletin_action.sh` には診断文字列の定義が各1行あるが、実行ログではないため件数から除外した。

### `logs/gate_context_freshness*.log` の `DOC_LANE_ALERT`

```bash
find logs -maxdepth 1 -type f -name 'gate_context_freshness*.log' -print | awk 'END{print NR+0}'
```

生出力:

```text
0
```

専用 log は存在しない。freshness の一次証跡は指定された `queue/gates/cmd_4467/context_freshness_doc_lane.warning:1-4` のみを使用した。

### `Published-By` trailer 無し commit

分母と欠落数を sentinel で明確に分離した抽出:

```bash
git log --since='2026-09-03T04:37:00' origin/main --format='%h%x09%s%x09%b%x1e' |
  awk -v RS='\036' 'length($0)>1 && $0 !~ /Published-By:/{n++} END{print n+0}'
git log --since='2026-09-03T04:37:00' origin/main --format='%h%x1e' |
  awk -v RS='\036' 'length($0)>1{n++} END{print n+0}'
```

生出力:

```text
49
199
```

欠落 commit 一覧（`%h` と subject）:

```text
6886cba25  docs(research): X運用設計書 v0.6 §10 X API/xAI API 対比+P1 手順
3d3796125  cmd_karo_recon2_4470_b_gate_202609031100: record gate log reconnaissance
b6fb92889  cmd_karo_recon2_4470_e_hook_cli_202609031100_normal: add hook CLI friction tsumari
ea2ebfb18  recon: tsumari_r3_tobisaru — 領域(d) reflux/insights/semantic_index 8分類抽出
a10e59e58  recon(cmd_karo_recon2_4470_c_monitor_202609031100): 領域(c) monitor/watchdog/inbox_watcher 一次log抽出→8分類つまり事例3件
44727f354  docs(research): X運用設計書 v0.5 §9 Grok 質問状への回答(コピペ用)
46d4ba0db  cmd_reflux_insight_202609031044_hanzo_exact: resolve ledger worktree-source finding as decision candidate
ecc579dbb  publisher: task=cmd_reflux_insight_202609031014_kotaro_exact merge 3215e923b
3215e923b  cmd_reflux_insight_202609031014_kotaro_exact: reflux insight resolve
b7014627f  runtime: integrate origin/main 95b2accb (push_lane auto)
60c20e901  cmd_4467: gate FAIL履歴の自動追記をcommit
84720014e  publisher: task=cmd_reflux_insight_202609030920_hayate_exact merge
c12d3be7d  publisher: task=cmd_reflux_insight_202609030912_kotaro_exact merge
003421635  cmd_reflux_insight_202609030920_hayate: resolve duplicate insight
a5cedb60c  cmd_reflux_insight_202609030912_kotaro: resolve insight
c2f49e973  merge: root reflux commit into origin/main
c63c397fa  cmd_reflux_insight_202609030812_kotaro_exact: annotate resolve
b74a45200  merge: root reflux commit dbc3c3c15 into origin/main
c47a3e7a0  scope外debris吸収: semantic_alias_absorb_pending.sh
dbc3c3c15  reflux insight: resolve README_ja.md semantic index未登録
4532dd6b1  cmd_reflux_insight_202609030754_saizo_exact: resolve README semantic insight
d3250159d  cmd_reflux_insight_202609030740_hanzo_exact: resolve duplicate skill-script follow-up insight
8f47589a0  runtime: integrate origin/main a6f54a6a9
aaea7851e  cmd_reflux_insight_202609030646_tobisaru_exact: annotate resolve
b1209392c  cmd_reflux_insight_202609030627_kotaro_exact: annotate resolve
54dc07402  cmd_reflux_insight_202609030614_hayate_exact: resolve fingerprint guard insight
2fe8ec713  cmd_reflux_insight_202609030545_tobisaru_exact: resolve publisher missing-artifact insight
3862932ed  publisher: capture lock-run rc explicitly
5251e76c1  publisher: once-mode returns the request rc
12fe9aa70  publisher: keep RC exit status for once-mode contract
609cbb673  insights: auto-commit (reflux dirty-guard防止)
2ba9896dd  cmd_reflux_insight_202609030513_hayate_exact: resolve AUTO-VOID report lifecycle insight
2cdb47364  queue: cmd_4464/4465 起票・4461 void
3094847db  insights: auto-commit (reflux dirty-guard防止)
cda20bbc5  insights: checkpoint hook-regenerated insights.yaml
a5fbb088f  cdp: commit cmd_4401 publish timing note
bc59797a9  runtime: karo checkpoint of root ledger dirty
abfffaad4  docs(research): tsumari 第2回 T2-27 U6 ledger route 沈黙フォールバック追記
9dc5bd8ac  insights: land INS-20260903-045419797-9e86
954936bcd  insight_write: restore -x guard on ledger_writer route
d90f86e71  gate/insight: replace -x guards with -f
9fd435f1e  gate_skill_script_refs: invoke insight_write.sh via bash
43a065d8f  docs(research): single publisher 設計書 v3.13 U7 完了
02b64428a  insights: auto-commit (reflux dirty-guard防止)
5f35e8995  insights: auto-commit (reflux dirty-guard防止)
561df5eb9  insights: auto-commit (reflux dirty-guard防止)
f153e6a2a  docs(context): infrastructure PUBLISHER_SINGLE flag file helper
73945c7dc  runtime: local postclear field-aware checkpoint
7a2621b49  runtime: local postclear field-aware checkpoint
```

## AC2: 事例表

同一根因の反復は1事例へ集約した。各行に一次証拠を付け、根治済みでも再発条件が残るものは未根治とした。

| ID | 時刻・発生数 | 事象 | 主分類 | 副分類 | 真因（log記載範囲） | 根治済/未根治 | 次の一手 | 一次証拠 |
|---|---|---|---|---|---|---|---|---|
| T3-hanzo-01 | 09:52〜10:38、1件 | x_post_gate Rule 1 が公開 showcase API の holding 集合だけを見ており、非公開 PF holding を blocklist に含めず、空でも PASS する欠陥 | 構造バグ | 影響範囲未解明 | review manifest が `showcase APIにholding非公開`、`signals API(認証付)正本化+fail-close` と記録 | 根治済み（hotfixの監査 state=PASS、LGTM） | P1投稿前に Basic holding=PASS / 非Basic holding=FAIL を本番APIで毎回計測 | `queue/gates/cmd_karo_hotfix_x_post_gate_blocklist_fail_close_202609031003/single_review_manifest.json:8-10,20-27,35` |
| T3-hanzo-02 | 09:44、1回 | cmd_4467 の report が `SCOPE DRIFT: 2/5` を警告し、target_path外の x_post_gate script/test が含まれた | 影響範囲・依存未解明の浅い対応 | 過剰 BLOCK境界 | gateが対象外2 pathを検出した事実だけを記録し、修正・再検証の証跡はこの source にない | 未根治 | target_pathと files_modified の照合を commit 前に fail-close 化し、同じ2 pathの再発件数を再計測 | `queue/gates/cmd_4467/cmd_complete_gate.trigger.log:145-148` |
| T3-hanzo-03 | 09:52、1回 | semantic causal audit が FAIL、affected 102、fail 2、missing 11、no_test 86 | 影響範囲・依存未解明の浅い対応 | 検証欠落 | audit result が `reason=test_failure` と未検証ノード数を記録 | 未根治 | fail 2・missing 11・no_test 86 の各対象を列挙し、対象別の検証を追加して再実行 | `queue/gates/cmd_4467/semantic_causal_audit.result:1-8` |
| T3-hanzo-04 | 09:48、1回 | doc lane の context freshness が source commit 1件を検出し warning | 影響範囲・依存未解明の浅い対応 | doc lane鮮度 | warning が `context/infrastructure.md` の source commit と更新要否確認を要求 | 未根治 | source commit と context反映の対応を同一窓で確認し、専用 freshness log を生成するか出力先を固定 | `queue/gates/cmd_4467/context_freshness_doc_lane.warning:1-4` |
| T3-hanzo-05 | 09:44、1回 | report commit が origin/main ancestry に無く、publisher待ちの `GATE WAIT: report_commit_main_ancestry` へ遷移 | 循環拘束 | publication依存 | gateが `UNPUSHED`、`source_publication_failed`、publisher待機を順に記録 | 未根治 | publisher request・remote ancestry・gate再実行を1 transactionの証跡へ結合し、同一待機の再発数を計測 | `queue/gates/cmd_4467/cmd_complete_gate.trigger.log:175-184` |
| T3-hanzo-06 | 04:37〜11:44、49/199 commit | origin/main の期間内199 commit中49 commitに Published-By trailer が無い | 構造バグ | Claude↔Codex 仕組み差 | git log の本文に Published-By が無いcommit集合を機械抽出。publisher由来と wrapper/runtime 由来が混在する | 未根治 | 49 commitを producer別に分解し、公開経路ごとの trailer 必須化と例外を固定して再計測 | `git log --since=2026-09-03T04:37:00 origin/main ...` の上記出力、代表 `6886cba25` |

## AC2 集計

### 主分類別

| 主分類 | 事例数 |
|---|---:|
| 偽陽性 | 0 |
| 過剰 BLOCK | 0 |
| 構造バグ | 2 |
| 循環拘束 | 1 |
| 遅い script・test | 0 |
| Claude↔Codex 仕組み差 | 0（T3-hanzo-06は副分類） |
| サンクコスト過剰複雑化 | 0 |
| 影響範囲・依存未解明の浅い対応 | 3 |
| **合計** | **6** |

根治済み `1` / 未根治 `5`。事例表6行すべてに file:line または git log 抽出証拠を付けた。log source の不在はAC1へ0件として記録した。

## AC3 判定

gate/hook の未解消条件が5件（T3-hanzo-02〜06）残るため、PASSではなくBLOCKとして報告する。禁止推測語の検索結果は0件。
