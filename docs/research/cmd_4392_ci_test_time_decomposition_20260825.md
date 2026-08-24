# cmd_4392 テスト・CI回転時間の全体分解 — 統合正本(AC3)

- 作成: 2026-08-25T03:03+09:00 将軍(doc lane)
- 発端: 殿指示2026-08-24 23:38『テストやスクリプトはどうなんだ』
- 一次成果物: 疾風=`hayate_report_cmd_4392`(CI分解) / 才蔵=`logs/cmd_4392_local-test-timing.json`(ローカル分解・retry確定版)

## §1 CI側(成功run 5件・30 jobs・260 steps全数分解)

| 区分 | 秒 | 比率 |
|---|---:|---:|
| **テスト実行** | 4,122 | **90.7%** |
| setup | 420 | 9.2% |
| その他 | 4 | 0.1% |

支配step=「Run unit and root-level tests」**2,885秒**。setup側の最適化余地はほぼ無い。

## §2 ローカル側(bats 239ファイル独立計測・重複0欠落0)

- 合計 **12,801秒**(直列相当)・PASS 221 / FAIL 18(環境依存含む・要個別検分)
- 上位: test_cmd_complete_gate 912秒 / test_cmd_save_block_aggregation 412秒 / test_inbox_write 373秒 / test_gate_gunshi_report_precheck_cache 369秒(exit 1) / 同precheck 368秒 / test_cmd_skeleton 331秒(exit 1)
- **top8で全体の26%のみ=ロングテール分布**。個別ファイル短縮の複利は薄い(7月修行のab_not_improvedと整合)

## §3 短縮候補(効果見込み順・次弾入力)

| P | 候補 | 根拠 |
|---|---|---|
| **P0** | **CIテストのshard並列化**(ジョブ分割でwall-clockを1/Nへ) | ロングテール分布=並列化が最も効く形。テスト実行90.7%支配 |
| P1 | CIの選択実行(affected)化(pushの変更範囲に応じたsubset) | ローカルでは選択実行が既に原則(run_tests.sh task/file/affected)。CIはfull固定 |
| P2 | 上位ファイル個別短縮(test_cmd_complete_gate 912秒等のfixture共有) | 効果は上限26%・7月A/Bで不成立実績あり=優先度低 |
| 検分 | ローカルFAIL 18ファイルの原因分類(環境依存か実FAILか) | FAIL=計測の信頼境界 |

## §4 境界
- 本正本は分解と序列のみ。shard/選択実行の実装は次弾cmd。
- ローカル合計12,801秒は独立直列計測値であり、通常の選択実行(数秒〜数百秒)とは別物。
