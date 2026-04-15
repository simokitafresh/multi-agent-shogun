# WA免疫系ステータス分析 2026-04-15
> gunshi idle自走 Step 1+Step 5 分析結果

## 計測日時
2026-04-15T04:55:00+09:00

## WA率推移(直近30件)
- WA率: 40% (12/30)
- 04/14以降(GP-190効果反映後): 12.5% (1/8)

## カテゴリ別分析(直近30件WA=true)

| カテゴリ | 件数 | GP対処 | 状態 |
|----------|------|--------|------|
| verdict_override | 4 | GP-190 (GATE CLEAR 04/15) | **根絶見込み** |
| commit_missing | 4 | rules修正(04/13) | **解消済み**(04/13以降再発0) |
| stale_ac_contamination | 1 | GP-178 (implemented) | 解消済み |
| scout_exempt_missing | 1 | GP-186 (implemented) | 解消済み |
| premature_shelve | 1 | GP-185 (implemented) | 解消済み |
| deploy_error | 1 | 未対処(孤発) | 監視中 |

## 免疫系健全性

- **GP対応済みカテゴリの再発: 0件(全期間)**
- 免疫サイクル正常: 新種出現→GP開発→実装→再発0
- cmd_1898 APPROVE→BLOCK: パリティテストcmdの正常動作(設計ミスではない)。accuracy -0.1%

## commit_missing詳細

全4件が2026-04-13 13:00-13:40のバースト。Codex CLI commit不全。
S182分析通りrules修正でcmd_1893以降再発0(hayate 5cmd+saizo 1cmd成功)。

## 因果鎖

新カテゴリ出現→GP実装(L4)→翌日0%→別カテゴリ出現→GP実装→...
免疫は機能するが飽和しない。新種は常に出現しうる。持続的GP開発が必要。

## cmd品質ログ分析 (cmd_design_quality.yaml)

- 全607エントリ
- **直近30 cmd最終CLEAR率: 100%** (30/30)
- 直近50 cmd: 100% (前50 cmd: 92%→改善)
- BLOCK→CLEARの修正サイクルが全cmd完走
- gate実行あたりBLOCK率37%はcycleの中間状態を含む見かけ値

## 次のアクション

1. ~~verdict_override消滅をGP-190効果として04/15以降で定量確認~~ → **確認済み(19:35)**: cmd_1910以降5件で再発0。N=5
2. deploy_error再発監視(3件到達でGP化検討)。孤発1件
3. wrong_task_execution再発監視(3件到達でGP化検討)。孤発1件
4. GP-196実装完了(19:35): lessons_useful numbered dict→list autofix復活。家老承認済み
5. GP-197実装完了(19:50): PostToolUse Edit hook YAML構文検証。家老報告済み
6. GP-032をpartialに降格(ファイル不在確定)
7. review_logアーカイブ完了(773→216行。10本目)
8. 免疫系健全: GP対応済みカテゴリ全て対処後再発0件
