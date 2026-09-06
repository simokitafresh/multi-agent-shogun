# 将軍 30 分 loop 手順 v3.1(2026-09-06 21:25 §8 に AC coverage/権限境界を追記。v3=19:55 殿指摘『loop 指示が肥大化していないか』→手順と状態を分離)
状態は記憶DB の復帰点(session_save_*)と設計書が正。本手順は不変の型のみ。loop prompt には「手順 v3 + 復帰点キー + 今 tick の焦点 3 行以内」だけを書く。

## 毎 tick(順序固定)
1. 復帰点(prompt 指定の session_save_*)を読む。inbox を inbox_read.sh で処理し既読化。
2. 一次確認: task yaml 6 名 / capture-pane / karo inbox 未読数・CTX / safe_shared_main_ff --dry-run mismatches / CI 両 repo(run ID) / gate_metrics 非 CLEAR。陣形図の in_progress を busy に代用しない。
3. ナッジ 3 判定→該当あれば家老へ順序付き 1 通(自動化は作らない。家老 未読 5 以上または CTX 75% 超なら次 tick へ): (a) done/await_clear/WAIT 30 分超=解放遅延→GATE と解放 (b) idle 30 分超=未配備→3 lane の次カード (c) failed 残置→close か再配備。60 分超の停滞は便停止として 1 通。
4. 設計書更新(状態変化があった時のみ): 部分更新禁止。冒頭〜末尾の全体整合(対象 ID×状態×観測時刻の矛盾 0)、状態集計は表の先頭記号を機械計数、1 行=一意 ID・履歴は経緯欄・「続」行なし・別 task 証跡を転記しない・CI は run ID 別記・反実仮想を書かない。1 時間放置禁止。更新後は家老に全本レビュー。
5. D0: 道具バグは将軍が先に直す(参照 bats を rg -l で全列挙→run_tests.sh file 全 PASS→publish。not ok は単独再実行で負荷由来か判定)。insights.yaml 直接編集禁止。
6. publish=$scratchpad/pubdocs.sh(隔離 clone、新規 file は先に list へ、root の stale copy を clone へ入れない)、gist_share は 1 Bash 1 本。DOC_LANE_ALERT は context_source_commit_set.sh(root に無い commit は git fetch 後に origin hash)。
7. todo map T242(anchor=直前更新時刻)→todo_map_render.py→artifact 4f5e79a2 再公開(変化時)。復帰点 session_save_YYYYMMDD_HHMM を記憶DB へ。CTX>70% なら復帰点を書いて /compact。
8. 禁則: 本番 DB/deploy 書込は殿の明示 OK のみ。DM-Signal main push=本番 deploy 相当=禁止(成果は非 main branch)。cmd 起票は LS110/LS-A13/LS-A22 の自己チェック(q1〜q12、q8 5W1H+複利、planned_paths、教訓 ack、cmd_delegate は INBOX_MESSAGE_ID で配備確認)。 **AC は忍者の権限内で閉じる(殿 09-06 21:23): 権限外の段(本番書込/DDL/deploy/共有 root 適用)は AC に入れず別 cmd か殿 OK 後の段に置く。可逆で本番に触れない操作(本番 DB readonly 取得=launcher+nonce、隔離 DB/worktree/非 main branch、隔離実験の反復)に『1 回だけ』等の人工制限を作らない。外部待ち状態を主経路にしない(家老がボトルネックになる)。**
9. tick の最後: 焦点 3 行を現状に合わせて改訂し ScheduleWakeup(25 分)。殿へは変化があった時だけ 1 報。
