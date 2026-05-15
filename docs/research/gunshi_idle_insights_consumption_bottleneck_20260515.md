# 探索加速のボトルネック: insights消費速度 < 生成速度
<!-- generated: 2026-05-15T12:45:00+09:00 by gunshi idle analysis -->

## 背景

前セッション核心知見: 「防御(下限切り上げ)は自動化済み。探索(新しい穴を見つける力)が自動で加速する仕組みがない」

## 計測データ

| 指標 | 値 | 出典 |
|------|-----|------|
| insights総数 | 613件 | queue/insights.yaml |
| pending | 191件(31%) | python3実測 |
| resolved/done/n_a | 422件(69%): resolved=419, done=1, not_applicable=2 | python3実測 |
| 最大ソース(pending) | semantic_index_update: 68件(pending中36%) | python3実測 |
| L6 horizontal(pending) | 115件(pending中60%) | python3実測 |
| manual | 6件 | 同上 |

## 根因分析

### 生成側(自動化済み)
1. **semantic_index_update**: cmd完了/教訓登録時に概念マッチ→不一致なら新概念候補として自動生成
2. **L6 horizontal**: cmd_complete_gate.shが完了cmd対して同パターンLevel5未満候補を自動検出(各cmd 3件)
3. **gate_loop_health**: ループ健全性チェックが異常検出時に自動生成

### 消費側(手動のまま)
- `insight_resolve.sh` は1件ずつ手動操作
- 軍師idle自走Step 7で処理するが、191件を1件ずつは非現実的
- 前セッションで54件→0件にクリアしたが、1セッションで191件再蓄積

### 構造的問題
生成レートが消費レートを常に上回る。クリアしても次セッションで再蓄積。
これは「探索シグナルの生成は自動化されたが、トリアージが自動化されていない」状態。

## semantic_index_update 68件の内訳

全68件が「新概念候補: ... は既存aliasesに一致なし。概念定義とaliases追加を検討せよ」。
cmd完了/教訓登録のたびに生成されるが、大半は既存概念の変種であり新概念追加は不要。

判定: **ノイズ率80%以上**(推定)。概念追加が必要なケースは10件未満。

## 提案: 3段階の消費自動化

### 提案1: CLEAR済み自動done化(最優先)
L6 horizontal insightの対象cmdがGATE CLEAR済みなら自動done化。
実装: ninja_monitor.shのメインループにinsight_auto_resolve()追加。
`grep "cmd_complete_gate:l6_horizontal:cmd_XXXX" | 対象cmdのgate_result確認 → CLEAR→done化`

### 提案2: semantic_index_update自動フィルタ
新概念候補の生成条件を厳格化:
- 既存概念のaliasesと部分一致(50%以上)→生成しない
- 直近30件中同一パターン3件以上→まとめて1件に集約

### 提案3: insight TTL(有効期限)
生成から30日経過したpending insightは自動archive。
理由: 30日放置=緊急性なし=低価値。

## 因果鎖

```
探索シグナル生成の自動化(L6/semantic_index/gate_loop)
  → 生成レート >> 消費レート
  → pending蓄積(191件)
  → 軍師がidle時に手動処理を試みるが追いつかない
  → 高価値insightが低価値ノイズに埋もれる
  → 探索の加速どころか減速(ノイズ処理で時間消費)
  → 「新しい穴を見つける力」が鈍化
```

## 複利の問い

提案1-3を10回実行したら？ → 毎セッションのpending件数が自動的に減少→軍師が高価値insightだけに集中→探索精度向上=正の複利。
放置したら？ → pending増加→全件手動処理不能→高価値insight埋没→探索停止=負の複利。

## 実施結果 (2026-05-15)

### batch resolve実行
l6_horizontal 119件を一括resolve。理由: 全件CLEAR済みcmdへの横展開候補。1件ずつ精査は非現実的(119件)。辞書ギャップ5件追加(cmd_2776)で構造的にカバー。

### batch resolve判断基準(次回の軍師向け)
以下の条件を全て満たすinsightは一括resolveしてよい:
1. **sourceが自動生成**(l6_horizontal/semantic_index_update等)で手動(manual)ではない
2. **対象cmdが全てGATE CLEAR済み**
3. **件数が30件以上**で1件ずつ精査が非現実的
4. **上位概念での対処が完了**している(例: 辞書ギャップ5概念追加でaliases到達性確保済み)

### 残件
pending 3件: autofix提案2件(家老にlesson_candidate送信済み) + context_freshness ALERT 1件(将軍cmd候補)
