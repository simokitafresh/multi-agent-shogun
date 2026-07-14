# review two-phase test speed

## 改善候補

| 優先 | 対象 | 根拠 |
|---|---|---|
| 1 | `tests/unit/test_review_two_phase.bats` の一時領域 | 全30テストのsetupで追加`mktemp`し、teardownで再帰削除している。BATSが既にテスト単位の隔離領域を提供するため二重管理である。 |
| 2 | 同ファイルのfixtureコピー | `review_approval.sh`をsetup後に個別テストでも再コピーする箇所があり、fixture生成I/Oが重複する。 |
| 3 | 同ファイルの非同期待機 | 固定sleepと短周期pollを含む3テストがあり、完了通知へ置換できれば待機時間を削減できる。ただし競合再現契約を守る設計が必要である。 |

最高インパクト候補1を実装し、[[test_review_two_phase.bats]] の`setup`で[[review_approval.sh]]を検証する一時rootを`BATS_TEST_TMPDIR`へ統一した。テスト単位隔離を維持しつつ、追加の作成・再帰削除プロセスを除去する。
