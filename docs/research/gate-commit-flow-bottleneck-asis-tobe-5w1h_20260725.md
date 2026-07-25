# gate/commitフロー ボトルネック設計書 — AsIs/ToBe 5W1H

origin: [[殿指示_gate_commit_flow設計_20260725]] <- [[three-layer-learning-loop-auto-growth v3.0]] + [[deploy_control_plane速度改善_20260721]] + [[将軍家老RCA協働_20260725]]
created: 2026-07-25T17:00+09:00 (将軍直筆)
status: **draft v1 — 家老・軍師レビュー待ち。レビュー後に殿裁定で方針確定**
baseline: 2026-07-25 一次計測(defense_overhead.jsonl + 本日の事故4件)

## §0 要求定義(殿指示 2026-07-25 16:57)

| 要素 | 内容 |
|------|------|
| WHY | gate/commitでボトルネックが頻発している。場当たり対処でなくフロー全体を一枚で見て方針を決める |
| WHAT | cmd実行フロー全体の設計書+ボトルネック台帳+ToBe方針案 |
| WHO | 起草=将軍、レビュー=家老(運用実態)+軍師(品質観点)、裁定=殿 |
| HOW | 本日の実測・事故データで接地。原則=品質2原則維持のまま超速化(P7)+考える工程は削らない(P8) |

## §1 AsIsフロー(cmd 1本のライフサイクル)

```
[起票] 将軍cmd_save.sh(gate: q1-q3 BLOCK+三層発火) 実測2.1s(表示型cut後)+three_layer_ruling 8.4s(median)
  ↓
[配備] 家老deploy_task.sh(admission/related_lessons/preflight/契約注入) 実測35.8s(-47%改善後)。テールmax 65.3s
  ↓
[作業] 忍者実装+テスト → /ninja-commit(scope検証+pre-commit hook)
  ↓
[報告] /report-write(report_field_set)→gate_report_format(bc→verdict自動導出)
  ↓
[一次レビュー] 軍師precheck(median 4.8s/max 50.4s)→レビュー→LGTM/FAIL
  ↓
[完了] 家老cmd_complete_gate.sh(GATE CLEAR判定+ロック) → post-CLEARパイプライン
        (insight triage→通知→dashboard→gist→task idle戻し) ※直列
  ↓
[後処理] archive_completed.sh+push(CI GREEN時)→CI(bats)→CI RED時は忍者ci_fix配備
```

## §2 ボトルネック台帳(本日までの実測・全て一次証跡あり)

| # | 箇所 | 事象 | 実測 | 分類 |
|---|------|------|------|------|
| B1 | cmd_save | three_layer_ruling_overhead | median 8.4s/max 32.2s | 速度 |
| B2 | deploy | queue/125,527ファイルのpreflight走査 | 配備wall 141.6s(3倍化)実測 | 速度(資源) |
| B3 | 軍師precheck | コールドパス | median 4.8s/max 50.4s | 速度 |
| B4 | cmd_complete_gate | post-CLEAR直列: triage 1件BLOCKで後続全停止(idle戻し欠落→次弾配備BLOCK連鎖) | cmd_4171実証 | 直列脆弱 |
| B5 | commit | HEAD lock競合(多エージェント同時commit) | 将軍commit失敗1回/日実測 | 競合 |
| B6 | commit | 新規ファイルsource+未追跡=CI破壊(才蔵239d663ff) | 本日実証 | 品質 |
| B7 | commit→CI | gate系ファイル変更の回帰がCIで初検出(bats 3件RED) | run 30149013181 | 品質(遅い検出) |
| B8 | scope検証 | test batsがplanned_paths未宣言→全忍者反復BLOCK | 軍師知見07-25 | 品質(FP) |
| B9 | stop hook | session_alerts同根因3行重複=処理コスト3倍 | shogun-rca:5 | 品質(重複) |
| B10 | loop_ledger | 33.2s/回+stock指標欠陥(是正済) | shogun-rca:3/穴12 | 速度+計器 |

## §3 構造分類 — ボトルネックは4種類しかない

| 型 | 該当 | 対処原理 |
|----|------|---------|
| A 速度型(機械的処理が遅い) | B1/B2/B3/B10 | **台帳駆動高速化**(支配項逆引き→品質維持高速化→前後証明)。稼働中 |
| B 直列脆弱型(1箇所の失敗が全体を止める) | B4 | **fail-open分離**(各ステップ独立+失敗隔離)。配備中(才蔵再作業) |
| C 競合型(共有資源の同時アクセス) | B5(HEAD lock)/B2(queueファイル) | **単一writer化 or リトライ規約 + retention**(T9) |
| D 品質型(検出が遅い/誤検出/重複) | B6/B7/B8/B9 | **検出の前倒し**(commit時に構造検証)+**FP根治**+**重複統合** |

## §4 ToBe方針案(レビュー対象)

### 方針1: 型別の標準対処を確立し、新規ボトルネックは型判定→標準対処で処理する
各ボトルネックへの個別対処(各論パッチ)をやめ、§3の4型への分類と型別標準対処を正本化する。
- A型→既存高速化レーン(変更なし・実績-47%〜-99%)
- B型→post-CLEARで確立するfail-open分離パターンを、他の直列パイプライン(deploy内部/archive)へ横展開
- C型→(a)commit: 忍者はninja-commit経由でretry内蔵化、将軍/家老/軍師のD0 commitにも共通retryヘルパー導入 (b)queue: T9 retention
- D型→**commit時構造検証の1本化**: 「新規source先の同一commit内包」「gate系ファイル変更時の該当batsローカル実行」をpre-commit(既存commit_contract系)へ接続。CIまで検出を遅らせない

### 方針2(対案): CI RED級のみ即応し、速度系は現行レーン任せで新設なし
最小変更。ただしB5/B6/B7は再発する(本日3件発生が反証)。

**将軍推薦=方針1**。理由: 本日1日でB4-B7の4件が実発生しており、型別標準対処がなければ同型を毎回一から診断することになる。方針1は新gate増設ではなく「既存機構への接続+パターンの正本化」であり、P7(削るな速くしろ)/P8(考える工程維持)と整合。

## §5 レビュー依頼事項

- 家老へ: (1)§1フローに運用実態との乖離はないか (2)B5 commit競合の頻度体感と、retryヘルパーの現実性 (3)§4方針1のD型=pre-commit接続が配備フローを遅くしないか(速度と品質のトレードオフ実測案)
- 軍師へ: (1)§2台帳に漏れているボトルネックはないか(レビュー観点から) (2)D型「gate系変更時の該当batsローカル実行」の選定規則(全量実行はBLOCK対象=cmd_save gate反転と整合させる方法) (3)B8 planned_paths自動拡張(tobisaru decision_candidate)の本設計への統合可否

レビュー期限: 忍者稼働と並行で可。両者のレビュー完了後、将軍が集約して殿裁定へ上げる。

## 因果リンク
- ← [[three-layer-learning-loop-auto-growth v3.0]] §3.4詰まり台帳+P7-P10=本設計の原理
- ← [[defense_overhead.jsonl]] B1-B3/B10の実測正本
- → [[cmd_karo_hotfix_post_clear_fail_open_20260725]] B型の初実装(才蔵再作業中)
- → [[LS101]] CI RED診断手順 / [[LS110]] 証跡と現物の突合=B6の教訓的根拠
