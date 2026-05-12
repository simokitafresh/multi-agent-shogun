# 放置項目陳腐化調査 — 軍師視点

<!-- created: 2026-05-10 | auditor: gunshi | trigger: 殿指示(blt_20260510_130722) -->

## DM-Signal

| # | 項目 | 状態 | 根拠 |
|---|------|------|------|
| 1 | Visibility Tier実装 | **有効(活発)** | cmd_2596(05-07) MECEマトリクス作成、cmd_2597 UI監査実施。活発に進行中 |
| 2 | FE速度改善残Phase | **部分陳腐化** | Phase 1完了(cmd_2267/2283, 04-25/26)。Phase 2-3(prefetch/defer/admin batch)は04-26以降cmd未発見。設計書(fe-speed-improvement-design.md)は有効だが未着手Phase残存 |
| 3 | ALM再構築 | **部分陳腐化** | 04-25浄化(39体/138,007レコード全削除)済み。チェックリストStep 2b-2d無効化。再登録時はobjective修正(cagr→MRU/calmar/UWP)必須。Step 2bからやり直し |
| 4 | Aveシリーズ | **有効(研究済み)** | cmd_2437-2439実装済み。Ave奥義-常勝 Calmar 4.459達成。gist提供済み。殿判断待ち |
| 5 | Phase4 A2ベクトル化 | **未確認(文書不在)** | dm-signal-research.md/dm-signal-ops.mdに記述なし。設計書・cmd記録見当たらず。殿に存在確認が必要 |
| 6 | ETL cron移行 | **完了** | cmd_2236(04-22)廃止完了。dm-signal-ops.md §37にL0-L3 sync体制正式化済み。MEMORY.mdの「廃止予定」記載が古い→更新必要 |

## infra

| # | 項目 | 状態 | 根拠 |
|---|------|------|------|
| 7 | context/infrastructure.md | **有効** | last_updated 04-30。scripts/config との乖離なし |
| 8 | 古い設計書(cmd_286/314-317/454) | **陳腐化** | 2月下旬〜3月上旬の偵察結果。後続実装で前提変更済み。ただし歴史的参照価値は残存 |
| 9 | 仙人構想 | **有効(温め中)** | MEMORY.mdに「温め中」記載。memory/project_sennin_ralph_loop.mdはauto-memory側に存在 |

## google-classroom

| # | 項目 | 状態 | 根拠 |
|---|------|------|------|
| 10 | context/google-classroom.md | **部分陳腐化** | last_updated 04-09。repo は04-21にPDF抽出/auto-login追加あり→context未反映 |

## database

| # | 項目 | 状態 | 根拠 |
|---|------|------|------|
| 11 | context/database.md | **有効(活動停止)** | last_updated 04-09。repo自体が03-12以降更新なし。陳腐化ではなくPJ活動停止 |

## 要対応サマリ

1. **MEMORY.md ETL cron記載更新**: 「廃止予定」→「廃止完了(cmd_2236, 04-22)」
2. **FE速度Phase 2-3の方針確認**: 殿に残Phase実施の意思確認が必要
3. **ALM チェックリスト更新**: Step 2b-2d無効化の反映+objective修正(cagr→MRU/calmar/UWP)
4. **Phase4 A2ベクトル化の存在確認**: 殿に確認が必要(設計書・cmd記録が見当たらない)
5. **context/google-classroom.md更新**: 04-21のPDF抽出/auto-login反映
6. **古い設計書(cmd_286等)**: 歴史保持で問題なし。削除不要
