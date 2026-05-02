---
name: shogun-clear-prep
argument-hint: ""
description: |
  【将軍専用】家老・忍者は使用禁止。将軍以外が呼んだ場合は即座に中断せよ。
  将軍専用の/clear前準備スキル。clear_prep_check.shで7項目チェックし、
  殿に報告+会話要約記録+ntfy送信。
  TRIGGER: /shogun-clear-prep、将軍の/clear前、セッション終了前の状態確認
  DO NOT TRIGGER: 知識棚卸し（→shogun-teire / dream）、
  PD反映確認（→shogun-pd-sync）、家老・忍者の/clear（自前の手順あり）
allowed-tools:
  - Bash
---

# /shogun-clear-prep — 将軍の/clear前準備

/clearで消える情報がないか7項目チェックし、殿に報告する。

## 手順（3ステップ）

### Step 1: 状態チェック+報告

```bash
bash scripts/clear_prep_check.sh
```

7項目を確認:
1. PD未決
2. cmd pending
3. 🚨要対応
4. 忍者状態+陣形図鮮度
5. 会話記録の健全度（殿のinbound件数）
6. 未commit変更（scripts/context/instructions配下はWARN）
7. 成果物マッピング健全度（gate_artifact_map.sh連携）

出力を殿にそのまま報告する。ALERT項目があれば殿に確認を取る。

### Step 2: 会話要約の記録

`queue/lord_conversation.jsonl` に会話要約を追記:

```bash
printf '{"ts":"%s","source":"terminal","direction":"session_summary","summary":"%s","agent":"shogun"}\n' \
  "$(date -Iseconds)" "{このセッションで殿と話した内容の1-3行要約}" \
  >> queue/lord_conversation.jsonl
```

書く内容: 殿の指示・裁定・未解決の話題。将軍の判断ではなく殿の言葉を残す。

### Step 3: ntfy通知

```bash
bash scripts/ntfy.sh "【将軍】/clear準備完了。PD:{件数} cmd:{件数} 🚨:{件数}"
```

---

## 原則

- **裁定はその場で記録** — /clear前にまとめてMCPに書くな。殿の裁定があった時点で即add_observations + pending_decision_write.sh resolve を実行する（shogun.md裁定同時記録ルール）。この原則が守られていれば/clear前に退避する情報はない
- **MEMORY.mdは/clear前に触らない** — 更新が必要なら別途/dreamで棚卸しする。/clear準備とは混ぜない
- **所要時間: 30秒以内** — スクリプト実行+ntfyだけ。ファイル読みやEdit不要
