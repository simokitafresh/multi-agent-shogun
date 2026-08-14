# 受け渡し地点STALL検知 統一設計書 AsIs/ToBe/5W1H v1.2 【📋設計済・裁可待ち】

> cmd_karo_stall_handoff_design_20260807。担当tobisaru。
> スコープは家老補足で3段階更新済み: (a)5地点→6組(msg_20260807_194433, 19:44) (b)6組→7組(msg_20260807_194631, 19:46・将軍→忍者を追加) (c)7組→**8組**(msg_20260807_194931, 19:49・殿→忍者→将軍を追加、殿裁定・CLAUDE.md:172に明記済み)。本書はその8組を対象とする。
> 対象8組: (1)将軍→家老 (2)将軍→忍者(**直接配備は迂回禁止=F002。本設計は鎖全体のend-to-end停滞「確認検知」のみ。直接通信路の新設ではない**) (3)将軍→軍師 (4)家老→忍者(既存STALL強化) (5)家老→軍師 (6)軍師→家老 (7)忍者→家老 (8)殿→忍者→将軍(**殿が忍者に直接指示した場合の例外経路。忍者→将軍の直接報告が許可される**)
> 対象外(既存対応済み・本設計の新規対象ではない): 家老→将軍/軍師→将軍(`detect_pending_action_required`)、殿→将軍(startup gate)
> 対象外(禁止ルート・確認検知も対象外): 忍者→将軍(#8の例外時を除く通常時)、忍者→忍者
>
> **★殿優先原則(家老補足19:46/19:49で明記指示)**: 殿の全ロールへの直接指示は本設計を含む全ルールに優先する(殿裁定2026-06-11、CLAUDE.md Skills章。忍者への例外はCLAUDE.md:172「例外: 殿が忍者に直接指示した場合、忍者は将軍に直接報告・対応してよい。殿の直接指示は全ルールに優先する(Rule 1.6)」で明文化済み)。殿が鎖を飛ばして忍者・軍師へ直接指示した場合、それは「STALL」でも「F002違反」でもない。本設計のWARN通知ロジックは「殿の直接指示による経路」を停滞・異常として誤検知してはならない。実装時は殿発の指示(通常のinbox/task/bulletin経由と異なる出所)を検知対象から除外する判定を組み込むこと

## §META — 5W1H

| 項 | 内容 |
|---|---|
| WHY | 鎖の各受け渡し地点で「送った側は送信ログが残るが、受け取った側が行動した証跡がタイムリーに確認されない」構造がある。既存STALL検知(`ninja_monitor.sh`)は家老→忍者の一部と将軍→家老のみをカバーし、家老↔軍師・忍者→家老の受信後アクション・将軍→軍師・将軍→忍者(end-to-end)・殿→忍者→将軍(例外経路)は未実装。放置は「指示が鎖の途中で静かに消える」事故(2026-07-26 status_update誤既読化事故と同型)を再発させうる |
| WHAT | 8組の送信ts取得方法・受信側の最初の行動ts取得方法・5分タイムアウト判定ロジック・WARN通知先を1設計書で統一設計する（各論パッチ禁止 — 殿指示） |
| WHO | 設計=tobisaru(本書)。実装判断・優先順位裁定=家老。実装=idle忍者(家老配備)。レビュー=軍師 |
| WHEN | 本書裁可後、家老が実装cmdを起票 |
| WHERE | `scripts/ninja_monitor.sh`(既存STALL検知の拡張)、必要に応じ`config/cli_profiles.yaml`(閾値の外出し)。#8は新規ログ基盤が要る(§ToBe参照) |
| HOW | 既存の`STALL_FIRST_SEEN`/`STALL_NOTIFIED`連想配列パターン(family key + epoch値 + dedupe)を再利用し、8組それぞれに送信ts取得関数・受信ts取得関数を用意する形で拡張する。新規の状態管理・対応表は増やさない(殿基本原則2026-03-11)。ただし#8のみ送信ts記録の仕組み自体が存在しないため例外的に新規プリミティブが必要 |

## §AsIs — 現状の検知有無(一次確認: `scripts/ninja_monitor.sh`, `scripts/cmd_delegate.sh`, `scripts/deploy_task.sh`, `scripts/inbox_write.sh`, `scripts/bulletin_write.sh`, `scripts/hooks/stop_check_inbox.sh`, `instructions/karo-procedures.md` §9-§11, `queue/lord_conversation.jsonl`, `CLAUDE.md:172` を実読)

### 対象8組の現状

| # | 組 | 送信イベント | 送信ts取得元 | 期待される受信側アクション | 受信ts取得元(理論上) | 既存検知 | ギャップ |
|---|---|---|---|---|---|---|---|
| 1 | 将軍→家老 | `cmd_delegate.sh`: status=delegated設定＋`inbox_write karo type=cmd_new` | `shogun_to_karo.yaml`の`delegated_at`フィールド | 家老が忍者へ配備(task YAML作成) or status変更 | `find_deployed_task_status()`で忍者task の`parent_cmd`一致確認 | **あり**: `check_undeployed_cmds()`(ninja_monitor.sh:6765)。`delegated_at`+**600秒(10分)**超過で`ntfy`+家老へ`inbox_write`nudge。dedupeは`UNDEPLOYED_CMD_NOTIFIED`連想配列 | 閾値が10分で本タスクの要求(5分)と不一致。他は概ね機能している |
| 2 | 将軍→忍者(end-to-end確認) | 直接通信路なし。将軍のcmd意図は必ず#1→#4を経由して忍者へ届く(F002: 直接配備迂回禁止) | #1の`delegated_at`(鎖全体の起点) | 忍者task YAMLの`deployed_at`出現(=#1+#4のリレーが完走したことの確認) | 忍者task YAMLの`deployed_at` | **なし**。#1・#4は個別に検知するが、「将軍の意図が最終的に忍者へ届いたか」を通しで見る合成ビューは存在しない | 未実装。ただし#1と#4が個別に機能していれば理論上カバーされるため、優先度は低い(合成ビューは診断補助であり、直接通信路の新設ではない点に注意) |
| 3 | 将軍→軍師 | `bulletin_write.sh shogun "..." `+`BULLETIN_NOTIFY=gunshi`(例: startup Q6洗脳チェック回答の第三者検証依頼、CLAUDE.md記載) | `queue/bulletin_board.yaml`該当entryの`posted_at` | 軍師が第三者検証→bulletin返信 or inbox返信 | 軍師による新規bulletin entry(`posted_by: gunshi`)の`posted_at`、またはinbox返信msgの`timestamp` | **なし**。ninja_monitor.shに将軍→軍師専用の検知は存在しない | 未実装。頻度が低い(将軍/clear時のQ6等、数時間〜数日に1回)ため、他組と同じ5分閾値が適切か要検討 |
| 4 | 家老→忍者 | `deploy_task.sh`: task YAML作成＋`inbox_write <ninja> type=task_assigned` | task YAMLの`deployed_at` | 忍者がstatus: assigned→acknowledged→in_progress | task YAMLの`acknowledged_at`/`status` | **部分あり**: `_handle_deploy_stall()`(ninja_monitor.sh:3791)がassigned/acknowledged/in_progress+idle継続を`cli_profile_get stall_debounce`(Codex=180秒)or`clear_debounce`(Claude=300秒/Codex=600秒)超過で検知→`/clear`+再送＋家老へ`deploy_stall`通知。2回連続STALLで`stall_escalate`。**ただし** `ACK_STALL_WARNED`という連想配列が宣言されているのみ(ninja_monitor.sh:1170)で**使用箇所が0件**＝acknowledged→in_progress遷移自体の未達を検知するロジックは未実装(死んだ宣言) | 「assigned+idle」は検知するが「acknowledged止まりでin_progressに進まない」個別ケースの検知ロジックが宣言だけで中身がない |
| 5 | 家老→軍師 | `inbox_write.sh gunshi "..." review_draft karo`(karo-procedures.md §9-10) | `queue/inbox/gunshi.yaml`該当msgの`timestamp` | 軍師がレビュー実施→`review_result`/`report_review_result`をkaroへ返信 | `logs/gunshi_review_log.yaml`の該当エントリ`timestamp`、または返信inbox msgの`timestamp` | **なし**。`ninja_monitor.sh`に`gunshi`関連のSTALL/timeout/elapsed/WARN文字列は0件(grep確認済み) | 未実装。並行配備方式(§9)のため軍師レビューが放置されても忍者作業は進むが、REQUEST_CHANGES/REJECTの取りこぼしに気づけない |
| 6 | 軍師→家老 | `inbox_write.sh karo "..." review_result`(または`report_review_result`) | `queue/inbox/karo.yaml`該当msgの`timestamp` | 家老がverdict処理: APPROVE=無処理(正)/REQUEST_CHANGES=補足cmd配備/REJECT=dashboard記録 | 補足task YAMLの`deployed_at`、またはdashboard更新時刻 | **なし**。`/gate-sync`スキルは`gate_result`(CLEAR/BLOCK)のreview_log同期のみで、verdict受領後の家老アクション遅延検知ではない | 未実装。**APPROVE時は「無処理が正しい」ため、これを誤ってSTALLとして検知しない設計が必須**(他の組と異なる特殊性) |
| 7 | 忍者→家老 | `inbox_write.sh karo "..." report_received <ninja> notify_karo` | `queue/inbox/karo.yaml`該当msgの`timestamp` | 家老が報告レビュー依頼(`report_review`→軍師)またはlesson_check+`cmd_complete_gate.sh`実行 | `queue/inbox/gunshi.yaml`の`report_review`送信ts、またはGATE実行ログ | **部分あり**: `REPORT-NOTIFY-MISSING-BLOCK`(ninja_monitor.sh:2407)は「報告YAMLは存在するが家老へのreport_received通知自体が送られていない」ケースのみ検知(送信漏れ)。**受信後**に家老がレビュー依頼/GATEを進めない停滞は検知対象外 | 送信側の漏れは見ているが、受信後アクション遅延は未実装 |
| 8 | 殿→忍者→将軍(例外経路) | 殿が忍者へ**会話で直接**指示(queue/task YAML等の構造化ログを経由しない)。CLAUDE.md:172で「殿の直接指示は全ルールに優先する」と明文化済み(本日追記) | **なし**。殿の忍者への直接発話は`queue/lord_conversation.jsonl`にも記録されない(同ファイルは`将軍↔殿`の会話専用。`agent`フィールドが`shogun`固定) | 忍者が将軍へ直接報告(通常は禁止されている忍者→将軍を例外的に許可) | 将軍のinbox/bulletin/lord_conversationいずれかへの新規記録(未確定) | **なし**。この経路自体が本日新設された例外ルールであり、既存コードに検知ロジックは存在しない | **送信ts取得元が構造的に存在しない**(会話はログ化されない)。他7組と異なり、STALL検知の前提となる「送信イベントの記録」自体が未整備。実装前に「殿の直接指示をどう記録するか」を先に決める必要がある |

### 対象外(参考: 既存対応済みルート)

| ルート | 検知方式 | 場所 |
|---|---|---|
| 家老→将軍/軍師→将軍 | `detect_pending_action_required()`。掲示板の自分宛open+notify_targets該当+「裁定/判断/対応/確認/BLOCK/URGENT」キーワード含みエントリをリアルタイムWARN | `scripts/hooks/stop_check_inbox.sh:435`。将軍のStop hookで**応答直前に毎回**実行される自己チェック型。ninja_monitor.shのような外部ポーリング型ではない |
| 殿→将軍 | startup gate各種チェック | `scripts/gates/gate_shogun_startup.sh` |

### 共通基盤(7組すべてが使う既存パーツ)

- タイムスタンプ形式: `YYYY-MM-DDTHH:MM:SS`(秒精度、TZ suffix無し、暗黙にJST)。`inbox_write.sh`のmsg、`bulletin_write.sh`のentry、task YAMLの`deployed_at`/`acknowledged_at`/`delegated_at`いずれも同一形式
- epoch変換: 全既存箇所で`date -d "$ts" +%s`パターンを使用(`check_undeployed_cmds`のL6793が代表例)
- dedupe(再通知抑制): `declare -A XXX_NOTIFIED`連想配列にkey=対象ID、value=epoch秒(または内容ハッシュ`notify_generation`)を保持し、解消時に`unset`する既存パターンが3種(`STALL_NOTIFIED`, `UNDEPLOYED_CMD_NOTIFIED`, `STALE_CMD_NOTIFIED`)で確立済み
- 通知手段: `bash scripts/inbox_write.sh <target> "<msg>" <type> ninja_monitor`(起床type必須。`low`/`info`等の自動既読typeは使うな — CLAUDE.md既存禁則)
- **殿発の直接指示の除外**: 上記いずれの送信ts取得元にも「殿が直接発した指示」は現れない(殿は鎖のYAML/inboxを介さず会話で直接指示することがある)。この場合はそもそも本設計の送信イベントが存在しないため誤検知の心配はないが、**殿の直接指示を受けたエージェントが鎖の通常経路(inbox/task/bulletin)を経由せず行動した結果、下流の受信側から見て「送信元不明の変化」が起きるケース**は各組の受信アクション判定で誤ってSTALL解除漏れ・誤警告としないよう、実装時に一次情報(capture-pane等)で確認する余地を残すこと

## §ToBe — 全8組統一STALL検知の設計

### 統一ロジック(疑似コード)

```
for each pair in [1..8]:
    for each open_handoff in pair.list_open_sends():
        send_ts_epoch = parse(open_handoff.send_ts)
        elapsed = now - send_ts_epoch
        if elapsed < pair.threshold_sec: continue
        if pair.receive_action_observed(open_handoff): 
            clear_dedupe(pair, open_handoff.id)
            continue
        if already_notified(pair, open_handoff.id, elapsed_generation): continue
        inbox_write(pair.notify_target, warn_msg, pair.notify_type, "ninja_monitor")
        mark_notified(pair, open_handoff.id, elapsed_generation)
```

既存の`_handle_deploy_stall`/`check_undeployed_cmds`/`check_stale_cmds`と同型。**新しい状態管理機構は作らず、この3関数のパターンをそのまま複製する**(殿基本原則: 既存インフラに乗せる軽量な仕組みを優先)。

### 組ごとの実装方針

| # | 組 | 送信ts取得 | 受信アクション判定 | 閾値(初期値) | 通知先 | 実装方針 |
|---|---|---|---|---|---|---|
| 1 | 将軍→家老 | `shogun_to_karo.yaml`の`delegated_at` | `find_deployed_task_status()`一致 | **要裁定**: 現行600秒(10分)を5分要件に合わせるか、10分のまま維持するかは家老が判断(未配備cmdは頻度が低く誤検知コストが低い一方、10分は殿の速度3原則「5-10分=即」の境界に近い) | 殿(ntfy)+家老(inbox) | 既存`check_undeployed_cmds()`の閾値定数を`config/cli_profiles.yaml`等へ外出しするだけ。ロジック変更不要 |
| 2 | 将軍→忍者(end-to-end確認) | #1と同じ(`delegated_at`) | #4(家老→忍者)側の`deployed_at`出現を合成参照 | #1・#4それぞれの閾値の合算(独立実装は不要) | 家老(inbox)。#1・#4が個別にWARNを出すため、本組は**新規の通知経路を作らない** | **実装不要 or 低優先度**。#1と#4を個別に直せば結果としてend-to-endも検知される。合成ダッシュボード表示(診断補助)は次点。**直接配備の新設は明確に禁止(F002)** |
| 3 | 将軍→軍師 | `queue/bulletin_board.yaml`の`posted_by: shogun`かつ`notify_targets`に`gunshi`含み`status: open`のentry`posted_at` | 軍師発言(`posted_by: gunshi`)の新規entry、または`confirmed_by`に`gunshi`追加 | **要裁定**: 頻度が低い(数時間〜数日に1回)ため5分は誤検知過多の可能性。既存`detect_pending_action_required`(軍師のStop hook自己チェック)がこの経路を部分的にカバーしている(軍師が自分の掲示板宛未対処を毎応答前にチェック)ため、**外部ポーリング型の追加実装が本当に必要か、家老が費用対効果を判断**すべき | 将軍(inbox) | 判断待ち。実装するなら`check_undeployed_cmds`型を流用 |
| 4 | 家老→忍者 | task YAMLの`deployed_at` | `acknowledged_at`があるのに`status`が`in_progress`へ進まず一定時間経過 | 5分(既存`clear_debounce`/`stall_debounce`と別軸で新設) | 家老(inbox) | **新規実装**: 宣言のみの`ACK_STALL_WARNED`を実体化。`_handle_deploy_stall`の直後に「status=acknowledged かつ acknowledged_at+300秒超過 かつ status未変化」を検知するチェックを追加し、家老へ「忍者が確認だけして作業に入っていない」WARN。既存の`/clear`+再送(DEPLOY-STALL)とは別物(すでにCLIは応答している状態なので/clearは不要、家老が内容確認を促すだけ) |
| 5 | 家老→軍師 | `queue/inbox/gunshi.yaml`の`review_draft`/`report_review`msg`timestamp`(`read:false`のもの) | 軍師からの`review_result`/`report_review_result`受信、または対応する`logs/gunshi_review_log.yaml`エントリ出現 | 5分 | 家老(inbox。並行配備方式のため忍者停止は不要) | **新規実装**: `check_undeployed_cmds`と同型の新関数`check_review_draft_stall()`。`queue/inbox/gunshi.yaml`をスキャンし`type in [review_draft, report_review]`かつ`read:false`のmsgを対象に経過時間判定 |
| 6 | 軍師→家老 | `queue/inbox/karo.yaml`の`review_result`/`report_review_result`msg`timestamp` | **verdict別分岐**: APPROVE→受信を確認した時点(`read:true`化)で即クリア(無処理が正)。REQUEST_CHANGES/REJECT→補足task YAMLの新規`deployed_at`出現、またはdashboard将軍宛セクションへの記録 | 5分(REQUEST_CHANGES/REJECTのみ対象) | 家老(inbox)。2回連続STALLで将軍へエスカレーション(`STALL_ESCALATE_THRESHOLD`と同パターン) | **新規実装**。msg本文からverdictを抽出できる場合のみ厳密判定、抽出不可なら`read:false`の放置のみを検知する簡易版から着手 |
| 7 | 忍者→家老 | `queue/inbox/karo.yaml`の`report_received`msg`timestamp` | `report_review`send(軍師宛)、または`cmd_complete_gate.sh`実行ログ出現 | 5分 | 家老(inbox) | **新規実装**。既存`REPORT-NOTIFY-MISSING-BLOCK`(送信漏れ検知)の姉妹関数として、受信後アクション遅延を検知する`check_report_action_stall()`を追加。両者は別関数のまま維持(検知対象が異なるため統合しない) |
| 8 | 殿→忍者→将軍(例外経路) | **前提: 未整備**。実装するなら、忍者が殿の直接指示を受けた時点で`queue/lord_conversation.jsonl`型の構造化ログ(例: `queue/lord_direct_instructions.jsonl`、`agent: <ninja_id>`)へ自己記録することを新ルール化する必要がある | 将軍への直接報告(inbox `type: direct_report`等の新設、またはbulletin) | 5分(ログ基盤整備後に適用) | 家老(遅延通知。鎖の可視性維持のため、例外経路でも家老には把握させる) | **実装不可(現状)**。他7組の「既存イベントに監視ロジックを足す」設計とは性質が異なり、**まず送信ログの記録ルール自体を新設する必要がある**。優先度は最も低い(発生頻度が最少・殿の直接指示は元々即応性が高い) |

### 5分タイムアウト判定ロジック(共通仕様)

```bash
elapsed_sec=$(( $(date +%s) - $(date -d "$send_ts" +%s) ))
if [ "$elapsed_sec" -ge 300 ]; then  # 5分=300秒
    # dedupe: 同一送信ts×同一対象への再通知を抑制(既存notify_generationパターン)
    generation=$(printf '%s' "$id" "$send_ts" | sha256sum | awk '{print $1}')
    if [ "${NOTIFIED[$id]:-}" != "$generation" ]; then
        inbox_write "$notify_target" "$warn_msg" "$notify_type" ninja_monitor
        NOTIFIED[$id]=$generation
    fi
else
    : # 5分未満は静観
fi
# 受信確認できたら NOTIFIED[$id] を unset して次回の再発火に備える
```

### WARN通知先の一般原則

1. **基本**: 受信が遅延している側の直属上位(家老中心の鎖なので大半は家老へ)
2. **家老自身が停滞源の組(#6軍師→家老, #7忍者→家老)**: 家老への通知だけでは自己検知にならないため、`STALL_ESCALATE_THRESHOLD`と同型で**2回連続検知時に将軍へエスカレーション**
3. **殿への通知(ntfy)**: 既存の#1(将軍→家老)のみ踏襲。他の組は鎖内(家老/将軍)で完結させ、殿への通知は増やさない(殿の時間を奪わない — CLAUDE.md既存原則)
4. **殿の直接指示による経路は対象外**: 上記§AsIs末尾「殿発の直接指示の除外」参照。自動WARNが殿の直接指示を停滞と誤認しないこと

## §未決事項(実装cmd起票前に家老が裁定)

1. #1(将軍→家老)の既存閾値600秒を、本設計の5分要件に合わせて短縮するか
2. #2(将軍→忍者end-to-end)は#1・#4の個別修正で足りるか、合成ビューを追加実装するか
3. #3(将軍→軍師)は頻度が低く、既存の`detect_pending_action_required`(自己チェック型)で十分か、外部ポーリング型を追加するか
4. #6(軍師→家老)のverdict別分岐をmsg本文パースで実装するか、簡易版(read:false放置のみ検知)から着手するか
5. #8(殿→忍者→将軍)は送信ログ基盤が未整備のため、本cmdの実装スコープに含めるか、送信ログ設計を別cmdへ切り出すか(発生頻度が低いため後回しでも実害は小さい)
