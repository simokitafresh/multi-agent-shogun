# Adversarial観点 Zero-Streak根因分析

## 日時
2026-04-26T11:30:00+09:00 (gunshi idle自走)

## 事象
gate_gunshi_startup.sh Adaptive Gating: adversarial zero_streak=9/10 (直近10件で1件のみ)

## 根因分析

### 定量事実
- 全1225レビュー中 adversarial finding_categories記録: 1件
- adversarial_review必須トリガー: `changed_lines >= 200` (gate_gunshi_cs_checklist.sh L160-165)
- 直近のdraft: 計測cmd(2288), gate修正(2289)等の小規模変更が主
- changed_lines >= 200のdraftが直近10件に0件

### 因果鎖
小規模cmd連続期間→changed_lines < 200→adversarial gate未発火→finding_categories未記録→zero_streak増加

### プロトコルとgateの乖離
- instructions/gunshi.md §5.7: 「changed_lines >= 200 **または blast radius大** のcmd」が対象
- gate_gunshi_cs_checklist.sh: changed_linesのみ検出。blast radius判定なし
- 乖離: blast radius大(hook/gate/CLAUDE.md変更)の小規模cmdはgateをすり抜ける

### 具体例
- cmd_karo_perm_fix: settings.json+ninja_monitor.sh修正(+9行)。blast radius=全忍者の/clear後動作。changed_lines < 200のためadversarial未適用
- しかし破壊シナリオ(S-Tab timing/CLI version依存)は premortem で拾えている

## 結論

1. adversarial zero_streakは小規模cmd連続期間の構造的結果。盲点ではない
2. ただしprotocol「OR blast radius大」条件がgateに未反映
3. 対策候補: gate_gunshi_cs_checklist.shにblast_radius判定追加
   - target files に `scripts/hooks/|scripts/gates/|CLAUDE.md|instructions/|settings` を含む場合はadversarial必須
   - defense_level: L4 (フロー内埋込BLOCK)

## 判断
- 現状premortem観点でカバーできている(cmd_karo_perm_fixのFM1/FM2検出)
- adversarial固有の付加価値: rollback不能性/運用誤用/監視穴の明示的検出
- 改善の判断基準: (1)今よりマシか→YES(blast radius大cmdにadversarial強制) (2)新しい長期問題を生まないか→NO
- → GP提案として家老に報告
