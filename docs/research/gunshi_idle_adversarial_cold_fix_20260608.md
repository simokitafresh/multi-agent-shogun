# Adversarial観点冷え修正 — 根因分析と2件の即修正
<!-- generated: 2026-06-08T01:58:00+09:00 by gunshi idle analysis -->

## 問題

startup gate観点別集計でadversarial 3/10(本番)が最低値。直近10件中7件でadversarial未使用。

## 根因分析

### 原因1: 速度修行cmdのノイズ
- `cmd_training_speed_*`(速度修行)はコード変更なしの理解テスト
- adversarialリスクが本質的にゼロだが、CS gate(§5.6)がscripts対象として全件WARN
- 8件のノイズが重要WARNを埋没させる(負の複利)

### 原因2: target_path未設定cmdの素通り
- SG-PRE15.5はtask YAMLのtarget_pathでscripts判定
- cmd_3219(ninja_monitor.sh変更)ではtarget_path未設定→「非自動化系」と誤判定
- files_modifiedにscripts/があっても検出されない

## 修正

### GP-263: CS gateで速度修行cmd除外
- ファイル: `scripts/gates/gate_gunshi_cs_checklist.sh` L701
- 変更: `id ~ /^cmd_training_speed_/` をawk条件に追加してnext
- 効果: WARNノイズ8件削減

### GP-263b: SG-PRE15.5にfiles_modifiedフォールバック
- ファイル: `scripts/gates/gate_gunshi_report_precheck.sh` L386-396
- 変更: target_pathが非自動化系の場合にfiles_modifiedからscripts/パスを検出
- 効果: target_path未設定のscripts変更cmdでもadversarial推奨が表示される(Level 5)

## 検証

| 項目 | 結果 |
|------|------|
| GP-263 | CS gate実行: 速度修行cmd除外確認。残WARN=通常cmd+karo_hotfix |
| GP-263b | cmd_3219報告でprecheck実行: `★ files_modifiedに自動化系ファイル` 表示確認 |
| 冷え観点WARN | simulation遡及適用で冷えWARN解消確認 |

## 因果鎖

```
adversarial 3/10(最低)
  → 原因1: 速度修行ノイズ(8件) → GP-263除外
  → 原因2: target_path未設定素通り → GP-263b フォールバック
  → 構造的対策: Level 5(事前コンテキスト提供)で冷え再発を防止
```

## 遡及適用実施

| cmd | 観点 | 追記内容 |
|-----|------|---------|
| cmd_training_speed_reset_layout | simulation | tmuxペイン操作、並行衝突なし |
| cmd_3207 | adversarial | 3修正全てrollback可能、空文字対処済み |
| cmd_3219 (self_study) | adversarial | clear-historyバッファ消去、プロセス無影響 |
| cmd_3219 (self_study) | operational_simulation | CTX0%正常化確認済み。safe_send_clear防御 |
| idle_adversarial_cold_fix (self_study) | operational_simulation | GP-263/263b次/clearサイクルで自動適用 |

## Session 2 追加修正 (2026-06-08T13:15)

### GP-264: gate_gunshi_cs_checklist.sh L770 `-A1`→`-B1`バグ修正
- review_logのYAML構造: `cmd_id:`が`review_type:`の前行にある
- `-A1`(次行)では`cmd_id:`を取得不能→`_review_done`が常に空→全cmdが偽WARN
- `-B1`(前行)に修正。reportレビュー済みcmd_id正しく検出確認済み
- 効果: cmd_3224/cmd_3225の偽WARN(L6-洗脳#1)解消

### 洗脳#8遡及分析: confidence:HIGH 5連続
- 対象: cmd_3221〜3225(DM-Signal V8バックテスト研究系)
- 5件全てGATE CLEAR。深刻な見落としは検出されず
- ただしGP-262(1シナリオ観測7件)の放置は惰性の兆候。次サイクルで対処

## Session 3 追加分析 (2026-06-08T22:42)

### zero_streak=6/10の遡及適用

GP-263/263b修正後もzero_streak=6。cmd_3231-3235の直近6件でadversarial未使用。

| cmd | changed_lines | blast_radius | adversarial要否 | 遡及結果 |
|-----|--------------|-------------|----------------|---------|
| cmd_3231 draft | N/A | **大**(全cmdの教訓注入精度) | **要** | USEFUL教訓スコアが閾値以上か未検証。穴あり |
| cmd_3231 report | deploy_task.sh | 大 | 要 | 同上 |
| cmd_3233 | SKILL.md×8 | 限定 | 不要 | 正当 |
| cmd_3232 | semantic-index | 限定 | 不要 | 正当 |
| cmd_3234 | context×3 | 限定 | 不要 | 正当 |
| cmd_3235 | note下書き | 最小 | 不要 | 正当 |

**発見**: cmd_3231のblast radiusは大(deploy_task.shは全忍者影響)だがadversarialを未適用。
changed_lines < 200のためトリガーされなかったが、blast radius大で適用すべきだった。

### 改善案: blast_radius自動判定
ac_physical_verify.shまたはSG-PRE15.5にblast_radius推定を追加:
- deploy_task.sh / inbox_write.sh / ninja_monitor.sh → blast_radius=high
- CLAUDE.md / instructions/*.md → blast_radius=high
- gate_*.sh / hook_*.sh → blast_radius=medium
200行未満でもblast_radius=highならadversarial推奨を表示(Level 5)
