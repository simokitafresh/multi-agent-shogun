# karo_workarounds テストデータ汚染分析

## 発見日
2026-04-13

## 事実
- karo_workarounds.yamlにtest_001, test_002, test_003の3エントリが存在
- category: test_pd_verify, detail: "テスト1"/"テスト2"/"テスト3: PD起票確認"
- workaround: true → WA率計算に含まれる

## 定量影響
- 全WA=75件中3件がテストデータ → WA率4%膨張
- gate_gunshi_startup.shの「直近3件」チェックがtest_pd_verify 3件のみ表示 → 実WAパターンが不可視

## 因果鎖
テスト実行→karo_workaround_log.shにguard不在→本番ログ汚染→WA率膨張+分析パターン隠蔽→誤った改善判断=負の複利

## 推奨
1. 3件のテストエントリ除外/削除
2. karo_workaround_log.shにcmd_id prefix validation追加(test_*, dummy_* → BLOCK)
3. GP-190候補として追跡
