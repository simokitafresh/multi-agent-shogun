# Useful率39.4% WARN根因分析 — L133/L736低有用教訓の注入メカニズム
<!-- generated: 2026-07-02T01:05:00+09:00 by gunshi idle analysis -->

## 背景
- startup gate WARN: 教訓注入有効率39.4% (13/33)
- 家老掲示板分析(blt_20260701_230035): L133=0/5, L736=1/5が低有用上位

## 分析結果

### L133 ID衝突問題
- **infra/lessons.yaml L133**: "injection_countがlessons.yamlで全件0(未同期)" tags=[yaml, security, lesson]
- **dm-signal/lessons.yaml L133**: "noteのMermaidは保守的構文" tags=[docs, note, mermaid]
- cmd_3629(project=infra)ではinfra側L133が注入。Mermaid教訓ではなかった
- infra L133のtags=[yaml]がYAML関連タスクに広くマッチ→score=26で注入→NOT_USEFUL
- target_files=[sync_lessons.sh]設定済みだが、フィルタ検証で不一致→除外されるはずが注入された（要追跡調査）

### L736 when/how未設定問題
- **infra L736**: "background子プロセスはflock FDを閉じて起動せよ" tags=[infra, db, bash]
- when/how=未設定 → NO_WHEN_PENALTY=-10適用後もscore=33
- target_files=[stop_check_inbox.sh, test_stop_check_inbox.bats, insight_write.sh]
- cmd_3629のtarget_path=insight_write.sh → target_filesマッチ → 注入は設計上正当
- しかしcmd_3629の修正内容(INSIGHT_REPEAT本文欠落)はflock FDとは無関係→NOT_USEFUL

### cmd_3629 fan-out効果
- 6忍者並列配備 → 同じ教訓が5-6忍者に同時注入
- 配備時はfeedback件数0 → useful_rateフィルタ非適用(MIN_SAMPLES未満)
- 全忍者NOT_USEFUL → 一度にfeedback 5件蓄積 → 次回以降useful_rateフィルタで自動除外

### useful_rateフィルタによる自然治癒
- L133: 0/5 = 0% < USEFUL_RATE_THRESHOLD(0.40) → 次回配備から除外
- L736: 1/5 = 20% < 0.40 → 同上
- 全体で71教訓がlow useful(rate < 0.40, samples >= 1)

## D0対処
- **L736 when/how追記**: commit aa1323bd8
  - when: flock内でbackground子プロセス(&)を起動する時
  - how: background起動前にFDを閉じる(200>&-)
  - 効果: NO_WHEN_PENALTYの適用がなくなりスコア計算が正確化。マッチ精度向上

## 残課題
- L133のtarget_filesフィルタが動作しなかった可能性の追跡調査(deploy_task.shデバッグログ追加検討)
- fan-out配備時のuseful_rateフィルタ遅延(初回配備時は常にMIN_SAMPLES未満)の構造的限界

## 因果鎖
cmd_3629 fan-out(6忍者並列) → L133/L736がMIN_SAMPLES未満でフィルタ非適用 → 5忍者同時NOT_USEFUL → useful率39.4%へ悪化 → L736 when/how追記(D0) + useful_rateフィルタ自然治癒
