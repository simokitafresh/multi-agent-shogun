---
name: gate-sync
argument-hint: "[cmd_id] [gate_result:CLEAR|BLOCK]"
user-invocable: false
description: |
  【軍師専用】gate CLEAR/BLOCK通知受信時にreview_logのgate_result更新+accuracy即時計算を実行。
  inbox受信→review_log該当エントリ更新→accuracy計算の3ステップを自動化。
  TRIGGER: /gate-sync、gate結果同期、review_log更新、accuracy計算
  DO NOT TRIGGER: レビュー完了処理（→/review-bundle）、idle分析（→/idle-persist）
quality_metric: "当該スキル同期後の軍師review精度（logs/gunshi_review_log.yamlでgate_prediction==gate_resultとなった割合）"
allowed-tools:
  - Bash
  - Read
---

<!-- script_refs_checked_at: 2026-07-15T13:46:00+09:00 -->
<!-- 2026-07-15検分: gunshi_gate_reflux.sh ab302df7bは同一cmd_idのdraft/report全件を単一flock区間でatomic置換し、gate_resultとgate_synced_atを同時更新。異なる既確定resultはtimestampごと保持する。 -->
<!-- cmd_karo_hotfix_skill_refs_after_infra_202607151211: yaml_field_set.sh 6dd44d13fはlist item内の後置id探索を追加した内部対応。既存CLI・flock・readback契約は維持。 -->

<!-- script_refs_checked_at: 2026-07-15T03:25:00+09:00 -->
<!-- cmd_3948検分: yaml_field_set.sh直近差分は重複parse削減。field-set引数・atomic更新契約不変。 -->
<!-- 検分: bulletin_write.sh 96e5f606eとyaml_field_set.sh 386cb6bbeをgit showで確認。通知先inbox root固定とlock_path SSOT化によるrace防止の内部強化。`yaml_field_set.sh <file> <block_id> <field> <value>`、`bulletin_write.sh <posted_by> <content> [requires_confirmation] [action_type]`、更新→accuracy→必要時投稿の順序は不変。 -->

Script refs verified: 2026-07-13 将軍検分. `yaml_field_set.sh` checked_at以降の変更(692b6c8d8)をgit showで確認。post-write検証のyaml.safe_load scalar比較統一+複数行値の安全エスケープ=内部改善。`<file> <block_id> <field> <value>`契約不変。手順書き換え不要。
<!-- 検分: yaml_field_set.sh 692b6c8d8(cmd_karo_hotfix_yaml_field_set_multiline_verify: post-write検証をawk生テキスト比較からyaml.safe_load後のscalar比較へ統一。複数行/引用符混在値の書込みを1物理行のquoted scalarへ安全にエスケープし、書込み自体は成功しているのに旧検証が偽FAILする問題を解消)。`bash scripts/lib/yaml_field_set.sh <file> <block_id> <field> <value>`の呼び出し契約・Usageは不変。本SKILL.mdのStep1呼び出し(`<file> "<cmd_id>" gate_result/gate_synced_at "<value>"`)への影響なし -->

<!-- script_refs_checked_at: 2026-07-13T07:55:00+09:00 -->
<!-- 検証(shogun 2026-07-11): yaml_field_set.sh(1fba56549 atomic公開+parse検証=内部変更)/deploy_task.sh(8be3eaf72 assumptions保全=内部変更)/cmd_complete_gate.sh(0a41c0110 perf=内部変更)。呼出しインターフェース不変、手順書換え不要 -->
<!-- 検分: bulletin_write.sh 61ad778f4。位置引数契約は不変だが、通知失敗時は3回retry後にfailure logへ記録してexit 1するfail-closed契約へ変更。投稿成功を終了コードで確認し、失敗時は処理完了扱いにしない -->

Script refs verified: 2026-07-08 cmd_karo_hotfix_skill_refs_202607081021. `yaml_field_set.sh` checked_at以降の変更(d1b841e/f8137de/2fb50f6)をgit showで確認。3件とも`gunshi_review_log.yaml`が`- cmd_id: xxx`形式のYAMLリストである点への対応強化: d1b841eはbegin_target 3箇所に`- cmd_id:`パターンを追加(review_logのgate_result更新自体ができないインフラバグの修正)、f8137deはis_boundary正規表現を`/- id:/`→`/- (id|cmd_id):/`へ拡張(次エントリを境界と誤認せず対象ブロック内に混入させない修正)、2fb50f6はflush_blockのblock_len=1条件にi>1を追加(1行だけのcmd_idブロックでfieldが正しい位置に入らない不具合の修正)。本SKILL.mdのStep1が実行する`bash scripts/lib/yaml_field_set.sh logs/gunshi_review_log.yaml "<cmd_id>" gate_result/gate_synced_at "<value>"`はこの`- cmd_id:`形式を直接対象にしており、3件はいずれもこの呼び出しの正しさ・安全性を修正・強化するもの。呼び出し引数の形式(`<file> <cmd_id> <field> <value>`)自体は変更なく、gate-sync手順の書き換えは不要。ただし従来はこのバグにより対象外エントリを誤って汚染する/更新が反映されないリスクがあった点は認識しておくべき（現在は解消済み）。

Script refs verified: 2026-07-02 cmd_karo_hotfix_skill_script_refs_202607021234. 対象scriptの2026-07-02T01:12以降差分をgit log/showで確認。直近変更は速度改善・内部検査強化・テンプレート修復・files_modified path guardで、各SKILL本文の呼び出し契約は維持。

# /gate-sync — gate結果同期スキル

gate CLEAR/BLOCK通知をreview_logに同期し、軍師のgate予測精度を即時計算。

## 引数

`/gate-sync <cmd_id> <gate_result: CLEAR|BLOCK>`

## 実行フロー

### Step 1: review_log更新
```bash
# gunshi_gate_reflux.shで全エントリ(draft+report)のgate_result+gate_synced_atを一括更新する
# yaml_field_set.shはfirst-matchのみ更新のため、同一cmd_idに2エントリある場合にreportが未同期になる
bash scripts/gunshi_gate_reflux.sh "<cmd_id>" "<gate_result>"
```

### Step 2: accuracy計算
```bash
# review_logの全エントリでgate_prediction vs gate_resultを突合
python3 -c "
import yaml
with open('logs/gunshi_review_log.yaml') as f:
    data = yaml.safe_load(f)
entries = [e for e in data.get('reviews', []) if e.get('gate_prediction') and e.get('gate_result')]
correct = sum(1 for e in entries if e['gate_prediction'] == e['gate_result'])
total = len(entries)
print(f'Accuracy: {correct}/{total} ({correct*100//total if total else 0}%)')
# 直近10件
recent = entries[-10:]
rc = sum(1 for e in recent if e['gate_prediction'] == e['gate_result'])
print(f'Recent 10: {rc}/{len(recent)} ({rc*100//len(recent) if recent else 0}%)')
"
```

### Step 3: 掲示板投稿（精度低下時のみ）
直近10件のaccuracyが70%未満の場合:
```bash
BULLETIN_NOTIFY=shogun bash scripts/bulletin_write.sh gunshi "gate予測精度低下: <accuracy>%。要因分析必要" false action_required
```
`bulletin_write.sh` の現在仕様:
- 推奨形式は `bash scripts/bulletin_write.sh <posted_by> <content> [requires_confirmation] [action_type]`。
- `requires_confirmation` は `true|false` または確認必須エージェントのCSV。`BULLETIN_NOTIFY` もCSV指定可能。
- `action_type` は `info` または `action_required`。将軍に対応を求める通知は `action_required` を指定する。
- 同一 `posted_by` + 同一 `content` は重複投稿せずDEDUPする。
- 投稿後のinbox通知は掲示板本文全文を含む。`inbox_write` 失敗やwatcher未起動はWARN表示される。
- 投稿成功後に `yaml_auto_archive.sh` を自動呼出し。bulletin_board.yaml が閾値超過時に古いエントリをアーカイブする（cmd_2856）。
- Script refs verified: 2026-05-22 cmd_2952. `bulletin_write.sh` は明示 `posted_by` 形式を推奨し、旧形式(content先頭)も互換維持する。`requires_confirmation` と `BULLETIN_NOTIFY` は `true|false` またはエージェントCSVを正規化し、不正agent名はERRORで停止する。`action_type` は `info|action_required` のみ許可し、将軍対応依頼は `action_required` を使う。

## 制約
- review_logのEdit直接編集禁止（`gunshi_gate_reflux.sh`経由）
- accuracy計算はreview_logのgate_prediction+gate_result両方存在するエントリのみ
- gate_sync.shが一括処理する場合と競合しない（両者とも`lock_path.sh`由来の同一flockで排他）
- Script refs verified: 2026-07-15 ab302df7b. review_logのgate同期はfirst-matchの`yaml_field_set.sh`ではなく、全matching entryを更新する`gunshi_gate_reflux.sh`を正本とする。
- Script refs verified: 2026-05-22 cmd_2959. `yaml_field_set.sh` WSL2最適化済み(lock_path純bash化、Windows path用/tmp lock、検証込み)。

Script refs verified: 2026-06-09 cmd_karo_skill_update_batch1. `yaml_field_set.sh` 直近変更(3de0d29c)は_yaml_field_set_apply_rootのskip_children条件修正(YAMLリスト要素`- id:`等の子要素認識漏れ修正)。内部バグフィックスのみ、インターフェース変更なし。本スキルはroot操作を使わないため直接影響なし。flock+readback検証の契約は維持。
Script refs verified: 2026-06-07 cmd_3206. `yaml_field_set.sh` はlock path純bash化で高速化されたが、flock+root fallback+readback検証の契約は維持。`bulletin_write.sh` の明示posted_by形式と通知先CSV仕様も変更なし。SKILL.md記載のreview_log更新と掲示板通知手順は現行と一致。

Script refs verified: 2026-06-20 48204a464. `bulletin_write.sh` 直近変更は操作的オントロジー/targetフィルタ/スキル強制の内部反映で、`bash scripts/bulletin_write.sh <posted_by> <content> [requires_confirmation] [action_type]` の掲示板投稿契約は変更なし。

Script refs verified: 2026-06-26 cmd_karo_hotfix_skill_refs_20260626082009. `bulletin_write.sh` の現物未commit差分は `compute_notify_targets` 追加と `notify_targets` 記録追加。投稿者を通知先から除外する既存挙動、`BULLETIN_NOTIFY` CSV、`requires_confirmation`、`action_type=info|action_required`、`bash scripts/bulletin_write.sh <posted_by> <content> [requires_confirmation] [action_type]` の呼び出し契約は変更なし。本スキルの掲示板投稿手順変更は不要。

Script refs verified: 2026-06-28 75aac6a10. `yaml_field_set.sh` 直近変更は既存ブロックへ新規fieldを挿入する際、ブロック末尾の最終行より前に差し込む内部バグ修正。flock+root fallback+readback検証の契約は維持。

Script refs verified: 2026-07-02 a2e4e93cc. `bulletin_write.sh` 直近変更は引数順序ミス検出ガード追加(contentがagent名ならERROR)。本SKILL.mdの呼び出し例は正しい`<posted_by> <content>`順のため投稿契約に変更なし。

<!-- script_refs_checked_at: 2026-07-13T07:55:00+09:00 -->
<!-- 検証(shogun 2026-07-11): yaml_field_set.sh(1fba56549 atomic公開+parse検証=内部変更)/deploy_task.sh(8be3eaf72 assumptions保全=内部変更)/cmd_complete_gate.sh(0a41c0110 perf=内部変更)。呼出しインターフェース不変、手順書換え不要 -->

<!-- script参照互換確認 2026-07-12: 参照先(yaml_field_set.sh/deploy_task.sh/ninja_monitor.sh)の直近変更はatomic mv/validate/fail-closed等の内部堅牢化のみでCLI引数・呼出手順の変更なし。本書の手順は現行スクリプトと互換(将軍git log現物確認) -->
