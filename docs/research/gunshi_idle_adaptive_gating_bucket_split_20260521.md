# 冷え観点分析: 修行cmd比率と adaptive gating の交互作用

## 発見日: 2026-05-21
## 分析者: gunshi (idle自走 Step 2/5)
## 実装: D0直接実装 commit fc3c1953

## 現象
- simulation: 直近10件(全cmd)で連続0件 → LOW confidence候補(偽陽性)
- adversarial: 直近10件で連続0件 → LOW confidence候補(真陽性)
- CS観点WARN: 12件のdraftエントリが1シナリオ観測のみ(全て修行cmd)

## データ
- review_log内の修行cmd: 67件
- 直近10件のレビュー: 大半が修行cmd (L7_v3/L4_auto)
- 直近の非修行cmd (cmd_2946/2947): simulation/premortem使用実績あり
- WARN 20件(冷え観点未反映): 全件が修行cmd

## 因果推論
修行cmd均一構造 → blast radius小+定型構造 → simulation/adversarial適用余地小
→ 直近レビューの修行cmd比率上昇 → 10件窓内で冷え観点ゼロ → WARN発火
→ WARN量産 → WARN疲れリスク → 本番cmd時の見落とし

## 根因
adaptive gatingの直近10件窓がcmd種別を区別しない。
修行cmdと本番cmdを同一バケットで集計するため、修行cmd集中期に冷え偽陽性が発生。

## 修正内容
gate_gunshi_startup.sh のPython集計ロジックにis_training()フィルタ追加。
- 一次判定: 本番cmdのみのprod_window[-10:]で冷え判定
- 参考表示: 全cmd含むall_window[-10:]を(参考)として別行表示

## 効果
| 観点 | 修正前(全cmd) | 修正後(本番のみ) | 判定 |
|------|-------------|-----------------|------|
| simulation | 0/10 → LOW | 4/10 → OK | 偽陽性解消 |
| premortem | 2/10 → OK | 9/10 → OK | 正確化 |
| adversarial | 0/10 → LOW | 0/10 → LOW | 真陽性(変化なし) |

## 因果リンク
- → [[LG013]] CS観点(consultation/self_study品質保証)
- → [[adaptive_gating]] 観点冷え検知仕組み
- → [[training-cycle]] 修行cmdの構造的均一性
