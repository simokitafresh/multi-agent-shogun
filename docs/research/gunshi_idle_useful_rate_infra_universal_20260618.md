# 教訓useful_rate真因分析: infra教訓universal 97件
<!-- generated: 2026-06-18T23:20:00+09:00 by gunshi idle analysis -->

## 問題

gate_lesson_health.sh ALERT: useful_rate=2.0% (1/49, 直近30cmd)。
前セッションでdm-signal教訓のuniversalタグ155件を固有化完了(184→29件)したにもかかわらず改善なし。

## 根因分析

### 計測ラグ(部分的根因)

直近30cmdの計測窓にretag前のcmd(cmd_3418=2026-06-16)が残存。
完全反映には新しいcmd 30件の蓄積が必要。
retag後のフィードバック(2026-06-18T01:00以降): USEFUL=1, NOT_USEFUL=22 → 4.3%。改善は限定的。

### infra教訓のuniversalタグ(主根因)

| 項目 | 値 |
|------|-----|
| infra教訓総数 | 815件 |
| universalタグ | 97件 |
| タグなし | 0件 |

infra(type=platform)の教訓は`_lesson_project_allowed()`でTrue返却 → 全cmdに注入候補。
universalタグ97件がキーワードスコアリングで閾値を超えると全cmdに無差別注入される。

### 実証: NOT_USEFULトップの教訓はinfra側にuniversalタグで二重存在

L472がdm-signal(tags:['deploy'])とinfra(tags:['universal'])の両方に存在。
前セッションのretag対象=dm-signal教訓のみ。infra側のuniversal教訓は未対処。

retag後NOT_USEFUL教訓の実例:
| 教訓ID | infraタグ | 内容(80字) | 注入先cmd |
|--------|----------|------------|-----------|
| L472 | universal | instructions/shogun-procedures.mdはgitignoreで... | cmd_3441(infra) |
| L541 | infra,deploy,testing,yaml | environment_change=lesson登録のテストは... | cmd_3441(infra) |
| L123 | bash,tmux | tmuxのsend-keysターゲット指定... | cmd_3438(infra) |
| L630 | infra,bash,yaml | bulletin_write.shのSCRIPT_DIR... | cmd_3438(infra) |

## 対処方針

1. **infra教訓のuniversal 97件をretag**: dm-signalと同じ手順(lesson_write.sh --retag)で固有タグに変更
2. **ID重複解消**: dm-signalとinfra両方に同一IDの教訓がある場合、一方を削除またはIDリネーム
3. **計測窓の更新待ち**: retag効果は次回配備30cmd後に反映

## 因果リンク

- -> [[gunshi_idle_useful_rate_batch_retag_20260618]] dm-signal側retag(前セッション)
- -> [[LG027]] referenced率≠useful率
- -> [[cmd_3413]] target_pathタグ推定追加
