# 家老 強くてニューゲーム復帰点 — 2026-08-24

## 0. 正本宣言

- role: `karo`
- status: `ready_for_new_game`
- current_project: `dm-signal`
- finalized_at: `2026-08-24T14:50:56+09:00`
- origin: `[[殿指示_今クリアされても今より強くてニューゲーム_20260824]] -> [[CI_RED_32680992968根治]] -> [[旧completed未archive全終端]] -> [[strong_new_game_completion_contract]]`
- 本ファイルは保存時点の復帰正本。数値は未来値として流用せず、復帰後に一次再計測する。

## 1. 復帰直後の順序

1. AGENTS.mdの家老Recoveryを省略せず完走する。
2. 本ファイルのSHA256を`queue/compact_state/karo.yaml.target_sha256`と照合する。
3. `queue/karo_snapshot.txt`、`queue/pending_decisions.yaml`、`queue/inbox/karo.yaml`を再読する。
4. inboxは`read:false`のIDだけを処理し、`inbox_mark_read.sh karo <msg_id>`で個別既読化する。
5. active taskがあればtask YAML・report template・worktreeを正本として再開する。active 0なら新作業を捏造せずidleへ戻る。
6. Git/CI/insightsは本ファイルの値を信じ切らず、復帰時点の一次値を再計測する。

## 2. 今回強くなった点

- 三層記憶guard: 全tool・taskless role・Read/Skillを含む実行前照合へ統一。67/67 PASS。
- commit ledger: 共通HEAD/index mutationを`ninja-scope-commit` lockへ統一。index.lock実害10→0、267/267 PASS。
- deploy_task最終分割: wrapper 89行、lifecycle 102/102、stall 106/106 PASS。
- cmd_complete速度改善:
  - report validator `28.45s→0.18s`、99.4%短縮。
  - self-grade `11.716s→0.27s`、97.7%短縮。
  - report discovery `>30s→12.50s`、58.3%以上短縮。
  - durable writer wait `836ms→210ms`、74.9%短縮。
  - CI/push確認をGATE非ブロックのpost-CLEAR後追いへ移行。
- finalize隙間計装: report→review→LGTM→ACCEPT→GATEの恒久JSONL化。直近最大中央値は`ACCEPT→GATE開始 263.571s`。
- publication競合: 共有擬似ref`FETCH_HEAD`参照を0件化し、不変SHA`remote_tip`へ統一。273/273 PASS。
- CI契約: post-CLEAR queue後に通知する現行契約へtest #23を更新。対象45/45 PASS。
- 旧滞留の`cmd_4377`、`cmd_4378`、`cmd_4384`、`cmd_4385`、`cmd_4386`、daemon lock CI fix、kagemaru refluxをCLEAR/COMPLETEへ終端。
- DM-Signal feature branch先行7commitをremoteへ統合し、local ahead 7→0。primary dirty worktreeは変更していない。

## 3. 保存時点の陣形

- karo inbox unread: `0`
- active task count: `1`
- task states:
  - hayate: `cmd_reflux_insight_202608241436_hayate_exact / in_progress`
  - kagemaru: `idle`
  - hanzo: `idle`
  - saizo: `idle`
  - kotaro: `idle`
  - tobisaru: `idle`
- 現active taskの復帰指示: `queue/tasks/hayate.yaml`と`queue/reports/hayate_report_cmd_reflux_insight_202608241436_hayate.yaml`を正本として再開。家老はinbox未読を先に処理し、完了報告後にreview/GATEを行う。

## 4. Git / remote / CI

- multi-agent-shogun baseline local HEAD before checkpoint commit: `2beeceebd1063f3791d7d8506e0891417bb5645d`
- origin/main: `3ceb880ab1d194d08acb764556413c61688783c1`
- relation: ahead=`7` / behind=`4`（最終checkpoint公開時は隔離mergeで両履歴を統合する）
- tracked dirty: `1`（`queue/insights.yaml`共有runtime state。変更・巻戻し・一括commit禁止）
- protected/untracked・operational dirty: `queue/insights.yaml`とDM-Signal primary worktree既存dirty/untracked。checkpoint作業では変更しない。
- latest verified CI: run `32694169416`, head `3ceb880ab1d194d08acb764556413c61688783c1`, conclusion=`success`（Unit/E2E/Integration/Lint/Build/CoDD全success、SKIP0）
- DM-Signal feature branch: local ahead=0。primary worktreeの既存dirty/untrackedは保護し、checkpoint作業では変更していない。

## 5. GATE終端

- `cmd_4377`: CLEAR / cmd-complete COMPLETE
- `cmd_4378`: CLEAR / cmd-complete COMPLETE
- `cmd_4384`: CLEAR / cmd-complete COMPLETE
- `cmd_4385`: CLEAR / cmd-complete COMPLETE
- `cmd_4386`: CLEAR / cmd-complete COMPLETE
- `cmd_karo_ci_fix_32680992968_postclear_notification_contract`: CLEAR / cmd-complete COMPLETE
- `cmd_reflux_insight_202608232239_kagemaru`: CLEAR / cmd-complete COMPLETE

## 6. 在庫・未決裁定

- insights: total=`333`, pending=`79`, unique IDs=`333`, duplicates=`0`
- pending decisions: `PD-104, PD-107, PD-110, PD-114, PD-135, PD-137`
- shelved decisions: `PD-038`
- lesson retirement candidatesとscript size alertは掲示板で将軍がactioned。次のidle審査対象であり、active作業を偽装しない。

## 7. 禁則

- F001: 家老が通常実装を抱えない。CI修正は`karo-direct`で忍者へ配備する。
- F002: 通常の殿直報は禁止。将軍宛はbulletin、殿向けはdashboard経路。
- F003: Task agentを使わない。
- F004: polling loopを作らない。
- 運用YAMLへ`yaml.dump`/`safe_dump`を使わない。
- report YAMLは`report_field_set.sh`、共有YAMLは正規helperを使う。
- remote ancestryだけで完了判定せず、通常pathはblob、mutable pathはfield-aware不変量まで確認する。
- `queue/insights.yaml`の共有dirtyをclean/巻戻し/一括commitしない。

## 8. 強くてニューゲーム二値条件

- [x] role・禁則・現task・次行動を復帰正本へ記録。
- [x] startup gateの旧completed未archiveと未push在庫を処理。
- [x] 全旧cmdをCLEAR/COMPLETEへ終端。
- [x] CI RED原因をartifactで特定し、contract testを修正。
- [x] latest CI GREENを確認。
- [x] local/remote関係、tracked dirty、保護対象を一次計測。
- [x] inbox・task・insights・pending decisionsを一次計測。
- [x] checkpoint SHA256をcompact_stateへ反映。
- [x] 三層記憶へcheckpoint pointer/hashを貫通。
