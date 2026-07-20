# ninja_monitor auto_clear不動作→CTX未クリア→rate limit加速→スループット低下 対策設計書

## 発見日・発見者
2026-07-20 殿指摘

## 現象
1. ninja_monitor.sh L8437構文エラー(if欠落)→即死→auto_clear全停止(47分間)
2. idle忍者(hayate CTX35%/saizo/kotaro)がclearされない→CTX蓄積
3. CTX蓄積→APIトークン消費加速→rate limit到達が早まる→スループット低下

## 因果連鎖
```
commit 6845c0041(retro_pane_transport)がif欠落
  → ninja_monitor起動時にbash全体パース→L8437で構文エラー→即死
  → AUTO-RESTART機構がスクリプト変更を検知するまで監視なし
  → idle忍者のauto_clearが停止→CTX蓄積
  → 高CTXでAPI呼出し→トークン消費増→rate limit加速
  → 次の作業開始が遅延→スループット低下
```

## 根因分析(5 Why)
1. なぜauto_clearが止まった? → ninja_monitorが構文エラーで死亡
2. なぜ構文エラーが入った? → tobisaruのcommitにif欠落(レビューで未検出)
3. なぜレビューで未検出? → 構文エラーはbashの遅延パースで2092テスト全PASSでも検出不能
4. なぜbash -nチェックがcommit前にない? → pre-commitにninja_monitor.sh専用の構文チェックなし
5. なぜ復旧に47分かかった? → AUTO-RESTARTのファイル変更検知間隔+singleton lockの旧PIDブロック

## 対策(3層)

### 対策A: bash -n構文チェックのpre-commit追加(Level4 BLOCK)
- scripts/ninja_monitor.shを変更するcommitの前に`bash -n scripts/ninja_monitor.sh`を自動実行
- rc≠0ならcommit BLOCK
- 実装: run_precommit_checks.shにninja_monitor.sh変更検知→bash -n追加
- 効果: 構文エラーがcommit前にBLOCK→ninja_monitor死亡を根絶

### 対策B: AUTO-RESTART検知間隔の短縮
- 現在: スクリプトのmtime変化を毎サイクル(20秒)で検知→変更後最大20秒で再起動
- 改善: heartbeat監視を追加し、ログ無出力が60秒超なら強制再起動
- 効果: 構文エラー→即死→60秒以内に復旧(現在の47分→1分以下)

### 対策C: graceful takeover(kagemaru実装中)
- 新世代がheartbeat/世代判定で旧世代をkillなしで引継ぎ
- singleton lockのPIDファイルをheartbeat年齢で無効化
- 効果: D006制約下でも自動復旧

## 優先順位
1. **対策A**(即時・最大効果): 構文エラー混入を根絶。try回数0で問題消滅
2. **対策C**(実装中): kagemaru cmd_karo_hotfix_ninja_monitor_graceful_takeover
3. **対策B**(補助): Aで防げなかったケースのfallback

## 効果予測
- 修正前: 構文エラー→47分停止→3忍者idle滞留→CTX蓄積→rate limit加速
- 修正後(A): 構文エラーcommit不可→停止0秒→auto_clear正常→CTX最小→rate limit遅延→スループット最大

## 因果リンク
origin: [[ninja_monitor構文エラー即死]] -> [[auto_clear停止47分]] -> [[CTX蓄積→rate limit加速→スループット低下]]
