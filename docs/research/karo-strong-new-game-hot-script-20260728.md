# 家老 強くてニューゲーム復帰点 — hot-script第一弾 (2026-07-28 09:19 JST)

## 結論

復帰後は推測せず、`queue/tasks/{ninja}.yaml` → `queue/reports/` → `tmux capture-pane -S -30` の順で一次実態を再確認する。`queue/karo_snapshot.txt` は補助キャッシュであり、生成時刻が10分超なら判断根拠にしない。

## 現在地

| check | ninja | 正本status | 一次実態 | 次の出口 |
|---|---|---|---|---|
| checks_pre_session | hayate | idle / report completed | GATE CLEAR、`cmd-complete`完了 | 追加作業なし |
| memory_db_token_search | saizo | in_progress / report pending | full unit実行中。tokenなし枝のworker/DB接触ゼロ化、tokenあり枝の親cache継承を採用。limit縮小案は実測悪化で撤回 | report→軍師LGTM→家老ACCEPT→GATE→cmd-complete |
| instruction_sync | kagemaru | assigned / report pending | 外れ値7件中6件がbody-only、1件のみfrontmatter変更と実測。affected→unit試験中 | report→軍師LGTM→家老ACCEPT→GATE→cmd-complete |

第一弾の完了条件は12check全クローズ。その時点で `logs/defense_overhead.jsonl` を再集計し、設計書台帳を12/12へ更新して掲示板へ完了宣言する。

## 今セッションで環境へ残した強化

1. 同一fileの `checks_pre_session` と `memory_db_token_search` はhandoff barrierで直列化し、前者の家老ACCEPT後に後者へ解除通知した。
2. 設計書v2.4のthree-layer行が before 92件とafter 2件を直結していたためBLOCKし、v2.4.1で「全92件after未計測・cohort全体の恒常削減値ではない」へ修正させてAPPROVEした。
3. `checks_pre_session` は同一queue世代のYAML構文検証PASSを再利用し、変更世代のinvalid YAMLは再parseしてBLOCKする境界を維持した。GATE CLEARと完了tailまで確認済み。
4. 復帰時の判断順序を「三層記憶→task/report正本→capture-pane一次実態→行動」に固定した。

## 復帰直後の二値確認

- [ ] `queue/inbox/karo.yaml` の未読を個別IDで処理した
- [ ] `queue/tasks/saizo.yaml` と `queue/tasks/kagemaru.yaml` を読んだ
- [ ] `shogun:2.6` と `shogun:2.4` を `capture-pane -S -30` で確認した
- [ ] report completedなら形式検査・commit実体・軍師LGTMを突合した
- [ ] 2件ともGATE CLEAR後、`cmd-complete` を実行した
- [ ] 12/12の台帳再集計と掲示板完了宣言を行った

origin: `[[殿指示_20260728_強くてニューゲーム]] -> [[hot_script第一弾_残2件]] -> [[karo_clear_recovery_checkpoint]]`

