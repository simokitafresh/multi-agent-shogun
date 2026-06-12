# WA Pattern Analysis 2026-06-12
<!-- generated: 2026-06-12T09:25:00+09:00 by gunshi idle analysis -->

## 計測結果

- 直近10件中WA=2件(20%)、clean=8件(80%)
- WA 2件は全てhanzo担当、category=uncategorized

## WA詳細

### cmd_3301 (hanzo)
- 事象: AC3 green evidence不在→hayate hotfixのecdac9e0証跡を家老がmerge
- 根因: worktree .env不在→DATABASE_URL未設定→SessionLocal=None→pytest 10件fail→忍者がgreen証跡を自力生成不可
- 対処: cmd_karo_hotfix_cmd3301_test_sessionlocal(hayate)でSessionLocal隔離修正→full pytest green→元報告にmerge
- 状態: **根治済み**。worktree環境由来の問題はSessionLocal隔離で解消

### cmd_3306 (hanzo)
- 事象: task acknowledged後10分以上進まない→家老が既実行済み証跡を報告YAMLへ補完
- 根因: hanzo stall(GPT忍者の処理遅延/停止)
- 対処: 家老がreport_field_set.shで補完し軍師レビューへ回す
- 状態: **一過性**。ninja_monitorがSTALL検知を常時カバー

## パターン分析

| 観点 | 結果 |
|------|------|
| LG014(同一category 3件以上→インフラバグ) | 2件で閾値未満。インフラバグの疑いなし |
| hanzo固有問題 | hanzo全12件中WA=2件(17%)。他忍者WA=0件 |
| category不備 | 2件ともuncategorized。適切なcategoryは env_setup / stall |
| 構造的再発リスク | cmd_3301=根治済み、cmd_3306=ninja_monitor監視下 |

## 結論

- 直近WA率20%は前期(post-LG006: 0%)から悪化だが、2件とも構造的再発リスク低
- cmd_3301は環境由来問題の根治完了。cmd_3306はGPT忍者stall(監視済み)
- 追加インフラ修正不要。次回WA発生時にcategory付与を家老に提案

## 因果リンク
- -> [[cmd_3301]] pytest fail→SessionLocal隔離根治
- -> [[cmd_3306]] hanzo stall→家老補完
- -> [[LG014]] 道具のバグ仮説(閾値未満で不発動)
