---
name: shogun-clear-prep
argument-hint: ""
quality_metric: "将軍系: /clear前準備cmdのcmd_save.shチェック通過率(q1-q4 BLOCKなしで保存できた割合)"
description: |
  【将軍専用】家老・忍者は使用禁止。将軍以外が呼んだ場合は即座に中断せよ。
  将軍専用の/clear前準備スキル。clear_prep_check.shで/clear指示ガード、
  会話退避、12項目チェック、session_summary自動追記を実行し、殿に報告+ntfy送信。
  TRIGGER: /shogun-clear-prep、将軍の/clear前、セッション終了前の状態確認
  DO NOT TRIGGER: 知識棚卸し（→shogun-teire / dream）、
  PD反映確認（→shogun-pd-sync）、家老・忍者の/clear（自前の手順あり）
allowed-tools:
  - Bash
---

<!-- script_refs_checked_at: 2026-07-03T11:15:00+09:00 -->

Script refs verified: 2026-06-26 a7ba82b4a. `clear_prep_check.sh` 直近変更はL804整数比較バグ修正+batch context auto-commit。引数なし実行で/clear前チェックを出力し、終了コードはissues>0で1/なしで0の契約を維持。/shogun-clear-prepの実行手順(Step 1-3)は変更なし。
Script refs verified: 2026-06-11. `clear_prep_check.sh` の契約は引数なし実行で/clear前チェックを出力する形式のまま。a7ba82b4aは知識埋込みチェック内の整数比較修正で、/shogun-clear-prepの実行手順・入力・完了報告契約変更なし。

# /shogun-clear-prep — 将軍の/clear前準備

/clearで消える情報がないか確認し、会話退避・セッション学びの埋込み状況・裁定反映状況をチェックする。

## 実行前ガード

このスキルは殿が直近で `/clear` または `/shogun-clear-prep` を明示した場合だけ続行する。
`bash scripts/clear_prep_check.sh` の冒頭 `[G0.殿/clear指示]` が直近5件の `lord_conversation` inboundを検査し、指示がなければWARNを出す。
WARN時は状態確認結果を殿に報告し、殿未指示のままStep 2以降へ進まない。

## 手順（3ステップ）

### Step 1: 状態チェック+報告

```bash
bash scripts/clear_prep_check.sh
```

`clear_prep_check.sh` が以下を順に実行する:
- `[G0.殿/clear指示]` 殿/clear指示ガード（直近5件の殿inbound確認）
- `[0.会話退避]` `queue/lord_conversation.jsonl` をarchiveへコピーしknowledge要約を生成
- `[1.PD未決]`
- `[2.cmd pending]`
- `[3.🚨要対応]`
- `[4.忍者]` 忍者状態+陣形図鮮度
- `[5.会話記録]` 会話記録の健全度（殿のinbound件数）
- `[6.未commit]` scripts/context/instructions配下はWARN
- `[7.成果物]` 成果物マッピング健全度（gate_artifact_map.sh連携）
- `[8.知識埋込み]` セッション学び埋込み状況（lesson登録数/semantic-index更新/insights未処理件数）
- `[9.強くてニューゲーム]` 「今クリアされても次の将軍はこのセッションの学びを持っているか？」
- `[10.裁定反映]` 裁定のprojects反映
- `[11.session_summary]` session_summary自動追記
- `[12.掲示板未対応]` 掲示板 action_required 未対応

出力を殿にそのまま報告する。`[G0.殿/clear指示]` がWARNなら、殿未指示のままStep 2以降へ進まない。
`[STATUS] ALERT` があれば、理由を殿に報告して確認を取る。

### Step 2: 自動記録の確認

`clear_prep_check.sh` は会話退避、記憶DB再構築、semantic_search照合、`session_summary` 追記を自動実行する。
手動で `queue/lord_conversation.jsonl` へ追記しない。

以下の出力を確認する:

1. `[0.会話退避] OK` または不在時のSKIP
2. `[8d.記憶整理Phase] memory DB再構築`
3. `[8e.記憶整理Phase] semantic_search照合`
4. `[11.session_summary] APPENDED` または `SKIP`

`ALERT` が出た場合は殿に確認を取る。

### Step 3: ntfy通知

```bash
bash scripts/ntfy.sh "【将軍】/clear準備完了。PD:{件数} cmd:{件数} 🚨:{件数}"
```

---

## 旧9項目からの対応

1. PD未決
2. cmd pending
3. 🚨要対応
4. 忍者状態+陣形図鮮度
5. 会話記録の健全度（殿のinbound件数）
6. 未commit変更（scripts/context/instructions配下はWARN）
7. 成果物マッピング健全度（gate_artifact_map.sh連携）
8. セッション学び埋込み状況（lesson登録数/semantic-index更新/insights未処理件数）
9. 強くてニューゲームリマインダ（「今クリアされても次の将軍はこのセッションの学びを持っているか？」）
10. 裁定のprojects反映
11. session_summary自動追記
12. 掲示板 action_required 未対応

---

## 原則

- **裁定はその場で記録** — /clear前にまとめてMCPに書くな。殿の裁定があった時点で即add_observations + pending_decision_write.sh resolve を実行する（shogun.md裁定同時記録ルール）。この原則が守られていれば/clear前に退避する情報はない
- **MEMORY.mdは/clear前に触らない** — 更新が必要なら別途/dreamで棚卸しする。/clear準備とは混ぜない
- **手動追記しない** — `session_summary` は `clear_prep_check.sh` がflock付きで自動追記する
- **復帰完了マーカーを手動維持しない** — `clear_prep_check.sh` は完了時に `SHOGUN_RECOVERY_MARKER`（未指定時 `logs/shogun_recovery_complete`。cmd_3674で/tmpから恒久パスへ移行）を削除し、次セッションがstartup recoveryを踏むまでRECOVERY INCOMPLETE警告を有効化する
- **所要時間: 30秒以内** — スクリプト実行+出力確認+ntfyだけ。ファイル読みやEdit不要

Script refs verified: 2026-06-04 cmd_karo_hotfix_shogun_clear_prep_skill_sync_20260604. `clear_prep_check.sh` 現行のG0/会話退避/記憶整理/session_summary/掲示板未対応チェックまで反映済み。
Script refs verified: 2026-06-10 14aa13952. `clear_prep_check.sh` は[8.知識埋込み]に(e)知見反映状況チェックを追加(cmd_3252)。セッション中のcontext更新件数とlesson_candidate件数を集計し、cmd完了ありで知識反映0件ならALERT(洗脳#7/#8防御)。チェック項目の拡張であり、/shogun-clear-prepの実行手順(Step 1-3)は変更なし。
