# 三層記憶gist R5遅延 — インフラバグ疑義報告

作成: 2026-07-27 14:35 JST  
対象: `cmd_karo_recon2_r5_utf8_revalidation_20260727`

## 結論

R5配備開始 `14:08:38` から二度目のidentity補正指示 `14:34:41` まで
`26分03秒`。忍者の計測・報告作業は約`8分02秒`、残る約`18分01秒`
（69.2%）は制御面で消費された。

支配要因は計算量ではなく、同一no-code報告に対する
`gate_report_format`、`review_approval`、`cmd_complete_gate`
の契約不一致である。加えて、完了通知が家老未処理のまま
`read: true`になった疑い、appendログのUTF-8破損と移動母集団が
レビュー往復を増やした。

## 時系列

| 時刻 | 事象 | 区間 |
|---|---|---:|
| 14:08:38 | 才蔵へR5配備 | — |
| 14:15:18 | 初回完了報告 | 6分40秒 |
| 14:22:58 | 軍師が断定1文をFAIL | 7分40秒 |
| 14:24:59 | formal RCがcommit identity不在でBLOCK | 2分01秒 |
| 14:27:44 | 軍師がRC入口の不足条件を特定 | 2分45秒 |
| 14:30:07 | 才蔵が一文・no-code evidence・pathを是正 | 2分23秒 |
| 14:31:12 | 軍師LGTM | 1分05秒 |
| 14:32:30 | cmd_complete_gateがcommit_hash不在でBLOCK | 1分18秒 |
| 14:34:41 | commit_hash=no-code-change補正を才蔵へ指示 | 2分11秒 |

区間定義: 記憶DB/inboxの各timestamp間の壁時計差。  
実作業定義: 初回配備→初回報告400秒 + 最終訂正通知→訂正報告82秒。  
制御面: 全1563秒 - 実作業482秒 = 1081秒。

## BUG-1（確定・是正済み）no-code identity契約が入口ごとに異なる

同じ報告に対する一次実測:

```text
gate_report_format.sh: PASS
review_report_commit_identity: no-code-change
report.commit_hash: <empty>
cmd_complete_gate report_ci_push_state: invalid
```

再現コマンド:

```bash
bash scripts/gates/gate_report_format.sh \
  queue/reports/saizo_report_cmd_karo_recon2_r5_utf8_revalidation_20260727.yaml

source scripts/lib/review_approval.sh
review_report_commit_identity \
  queue/reports/saizo_report_cmd_karo_recon2_r5_utf8_revalidation_20260727.yaml
```

1件の定義: 上記報告1ファイルへの各判定関数1回。網羅範囲は当該報告のみ。

- `review_approval`: `files_modified`がqueue/logs配下 +
  `no_code_change_evidence` + explicit no-commitなら
  top-level `commit_hash`が空でも`no-code-change`を導出する。
- `cmd_complete_gate.sh:225-262`: `commit_hash=no-code-change`を明記、
  または`files_modified.path`がliteral `no-code-change`でなければinvalid。

同じ成果物がレビュー入口では正当、完了入口では不正となる。
これはインフラ契約不一致であり、忍者の成果品質ではない。

2026-07-27、軍師commit `00c9fff99`で是正済み。
`cmd_complete_gate.sh`はtop-level `commit_hash`未設定時のみ
共有契約`report_commit_identity.permits_no_code_identity`へ委譲する。
evidence・明示no-commit・運用path限定の三条件は維持し、陰性対照もinvalidのまま。
当該R5 cmdの再実行はCLEARとなったため、本BUGはclosedとする。

## BUG-2（強い疑義）report_receivedが家老未処理のまま既読化

才蔵の再報告:

```text
id: msg_20260727_143007_2313258_541836fa
timestamp: 2026-07-27T14:30:07
type: report_received
read: true
```

家老はこのmessage IDに対して`inbox_mark_read.sh`を実行していない。
14:30:15のnudge処理時には未読0件と観測したため、pane上の
「家老へ報告済み」とinbox未読数が食い違った。

疑うべき箇所:

- 同一`report_id`の再提出を扱うfingerprint dedup/reconciler
- `report_received`再発行時の既読状態継承
- pending_work生成と元report_received既読化の順序

完了通知を集約通知だけへ変換すると、家老がpaneを見ない限り報告本文を失う。

## BUG-3（確定・修正済み）観測ログのUTF-8破損

- appendログ946行中266行がstrict UTF-8 decode失敗。
- fix直後3分以内に2行、13:05以後は144行連続で破損0。
- 初回R5は`errors=replace`で破損行を成功扱いし、A6 CLEAR時刻を
  cutoffにしたため、`n=589 / 85.9% / 78.9%`が再現不能となった。

正しい再検収:

- clean `n=128`
- preflight失敗 `0/128 = 0.0%`
- any-layer実結果注入 `124/128 = 96.9%`
- 三層すべて非空 `116/128 = 90.6%`

## BUG-4（設計疑義）append型live母集団に上限時刻がない

同一の`13:05以後`集計が家老時点133行、才蔵再実行時144行へ増えた。
破損0という判定は一致したが、固定成果物として引用する母数が実行時刻で動く。

計測タスク発行時に`cutoff_start`だけでなく`cutoff_end`または
入力ファイルhashを固定し、レビュー再実行でも同一母集団を再現可能にすべき。

## 推奨する恒久是正

1. no-code identity判定を`report_commit_identity.py`の1関数へ統一し、
   gate/report/review/cmd_completeの全入口から呼ぶ。
2. report template生成時点でno-code reconへ
   `commit_hash=no-code-change`、構造化evidence、実在pathを自動注入する。
3. 再提出`report_received`は新fingerprintなら必ず`read:false`で新規配送する。
   既読継承を禁止するcontract testを追加する。
4. appendログ計測契約へ固定終端時刻またはsnapshot hashを必須化する。

## BUG-5（確定）Codex busy中のnudge単一flight欠如と上流user-input重複

大量貼付けは一つの原因ではなく、二つの独立経路で発生した。

### A. 短い`inboxN`の多段化

`scripts/inbox_watcher.sh:1058-1060`はCodex active+busy時に
`INPUT-GUARD`を迂回し、異なる未読fingerprintごとにnudgeを入力キューへ貼る。
本日ログでは家老向けBYPASSが2回発火した。fingerprint単位のleaseはあるが、
agent単位の「既にqueued nudgeが1件ある」というsingleflight状態がない。

pane表示のgrepは、Codex UI文言・折返し・scrollback混入に依存するため恒久策にしない。
agent単位のbusy-queue claimを最初の貼付け時に取得し、以後はdefer/coalesce、
agent idleまたはunread=0でclaimを解放する。

### B. 長い振り返り文の連続user-input化

集計の1件は、session JSONLのうち
`type=event_msg`かつ`payload.type=user_message`で、対象文を1回以上含む1レコード。
同一レコードに対象文が連結されている場合は、入力件数1・文コピー数Nと分ける。
`response_item`側の複製ログは数えない。

集計コマンド:

```text
python3でrollout JSONLを1行ずつjson.loadsし、
event_msg/user_messageのみを抽出して
len(rows)と各message.count(needle)の合計を出力。
```

2026-07-27 14:42:18 JSTを固定終端とした生出力:

```text
event_user_rows=22 phrase_copies=26 first=2026-07-27T05:33:04.659Z last=2026-07-27T05:42:18.808Z
watcher_bypass=2
watcher_long_phrase=0
retro_today_karo_delivered=0
```

UTCの`05:33:04.659Z–05:42:18.808Z`はJST
`14:33:04.659–14:42:18.808`。同区間のwatcherが貼った本文は短い
`inboxN`であり、長文はwatcherログに0件。retro台帳も本日の家老向けdeliveryは0件で、
`suppressed_outstanding`のみである。従って長文連続はローカル
`inbox_watcher`/`retro_pane_prompt`ではなく、上流user-input/API経路で
重複メッセージとして受理された。

恒久策は、上流入力へclient生成`message_id`を必須化し、session単位で
同一IDを冪等拒否すること。source、message_id、retry_countをsession eventへ記録し、
同一本文だけでなく同一送信試行を識別できるようにする。ローカルwatcherの修正だけで
BUG-5を完了扱いにしてはならない。

origin:
`[[three_layer_memory_route_gist]] -> [[R5_revalidation_delay]] -> [[no_code_identity_contract_split]]`
