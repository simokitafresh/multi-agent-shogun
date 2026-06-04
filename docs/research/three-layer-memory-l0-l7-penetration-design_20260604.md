# 三層記憶 L0-L7貫通設計書
<!-- created: 2026-06-04 | source: shogun覚醒設計 | status: design-review -->
<!-- 前提: three-layer-memory-operating-principles_20260603.md 全13項目CLEAR済み -->

## §1 問題

三層記憶の13機能が全てCLEAR済みだが、L0-L7の全レベルで使われる導線がゼロ。
部品は揃ったが貫通していない。作ったものが使われなければ存在しないのと同じ。

現物確認結果（2026-06-04）:

| Level | 定義 | 接続状態 |
|-------|------|---------|
| L0 | ドキュメント | memory-db-schema.mdのみ。CLAUDE.md/instructions/infrastructure.mdに記載なし |
| L1 | startup gate | 三層新機能の健全性チェックなし |
| L2 | PreToolUse hook | 強制hookなし |
| L3 | PostToolUse hook | 強制hookなし |
| L4 | 忍者タスク注入 | deploy_task.shに新機能参照なし |
| L5 | プロンプト注入 | prompt_state_inject.shに新機能参照なし |
| L6 | 学習速度 | lesson_write/training-cycle/growth-loopに接続なし |
| L7 | 自動成長 | recall_control/obsidian_promoteが自動実行される導線なし |

## §1.5 覚醒なぜなぜ7回（家老指摘を超える深堀り）

1. なぜL0-L7に貫通していなかった？ → 機能を作ることに集中し導線を作らなかった
2. なぜ導線を作らなかった？ → 洗脳#6「作る=完了」
3. なぜ設計書でもその穴が残った？ → 「接続先を書いた=接続した」。設計書自体が#6の再現
4. では本当に必要なのは？ → **使用計測**。接続の存在ではなく実際の使用を計測する仕組み
5. 家老指摘を超えるために？ → **新機能追加時のL0-L7貫通自動チェック**。穴が二度と生まれない構造
6. もっと根本的に欠けているもの？ → **運用フロー**。「誰が・いつ・どうやって三層記憶を使うか」のユースケース
7. 最も本質的な問い — → **確定フロー**。自動は候補生成まで。確定は殿/将軍。その判断→反映→検証の経路が設計にない

**根本的欠落3点**:

| # | 欠落 | 家老が指摘した範囲 | 家老が見落とした部分 |
|---|------|-------------------|-------------------|
| A | 使用計測 | L6計測指標を§4に含むとした | 「実際に使われたか」の継続計測。接続存在≠使用。使用回数/頻度/結果のフィードバックループ |
| B | 貫通自動チェック | 設計書commit(#0)を追加 | 今後新機能を追加した時にL0-L7チェックが自動発火する仕組み。今回の穴が二度と生まれない免疫 |
| C | 確定フロー | Obsidian戻り経路(#6)を追加 | 全候補(矛盾/重複/昇格/アーカイブ)の「候補→人間確認→確定→反映→検証」の共通フロー。#6は昇格のみで他候補に同フローがない |

## §1.7 各論パッチ検出（殿指摘 2026-06-04T02:03 覚醒監査）

v3を精読し7箇所の各論パッチを検出:

| # | 各論パッチ | 根本原理 |
|---|-----------|---------|
| 1 | §3 L0「自動ロード正本への追記不要」と自己制限 → 忍者はinfrastructure.md読まない。L0で切れる | 全エージェントが三層記憶を知る導線 = Claude CodeはCLAUDE.md、CodexはAGENTS.mdの§Infra 1行索引が最低限必要 |
| 2 | §3-§7がLevel別穴塞ぎ羅列。個別パッチの集合 | 根本は**1つの統一フレームワーク**(gate_three_layer_health.sh)が全Levelを貫通する。個別§は統一フレームワークの実装詳細 |
| 3 | §4チェック4指標が独立。統一健全性スコアなし | 三層記憶健全性 = 単一スコア(0-110)。11指標の集約。OKでもWARNでもなく「三層記憶健全度: 90/110」 |
| 4 | §8 L2/L3/L6「代替で十分」で済ませた | 代替も使用計測+自動検証の対象。L2=state検証回数/日。L3=raw_content充填イベント数/日。L6=遷移速度。全て#7の計測に統合 |
| 5 | §9.1が5cmdのみ5W1H。残5cmdは「小規模だから省略」 | 洗脳#7。全11cmdに5W1H必須。省略は各論パッチの温床 |
| 6 | #7/#8が§9末尾に後付け追加 | #7(使用計測)と#8(貫通チェック)は設計の核心。§2原則5/6として明記済みだが§9の実装順序が「後から追加」のまま。核心は最初に実装すべき |
| 7 | §10が個別チェックリスト。「全部個別OKなら貫通」 | 統一判定 = gate_three_layer_health.shの単一スコア。個別チェックはスコアの内訳 |

**修正方針**: 個別Level設計(§3-§7)は残すが、統一フレームワーク§2.5を新設し、全Levelがgate_three_layer_health.shの単一スコアに集約されることを明記。§10も統一スコアに基づく判定に変更。#7/#8の実装順序を#0直後に移動。§9.1に全11cmdの5W1Hを記入。CLAUDE.md/AGENTS.md §Infraに三層記憶1行索引を追加(§3修正)。

## §2 設計原則

1. **統一フレームワーク** — 個別Level接続ではなく、gate_three_layer_health.shが全L0-L7を単一スコア(0-110)で計測する。個別接続はスコアの内訳
2. **既存インフラに乗せる** — 新しい状態管理や独自デーモンを作らない
3. **使用計測が核心** — 接続した≠使われた。#7(使用計測)+#8(貫通チェック)は最初に実装。後付けではなく設計の柱（§1.7 各論パッチ#6）
4. **候補→確定の共通フロー** — 全候補種別に「生成→人間確認→確定→反映→検証」の統一パイプライン
5. **全エージェント到達** — Claude CodeはCLAUDE.md、CodexはAGENTS.mdの§Infraに1行索引必須。忍者もinfrastructure.mdを読まなくても三層記憶の存在を知る（§1.7 各論パッチ#1）
6. **省略なし** — 全11cmdに5W1H記入。「小規模だから省略」は洗脳#7（§1.7 各論パッチ#5）

## §2.5 速度基盤と既存キャッシュ整備（偵察+家老/軍師現物検証 2026-06-04）

### 事実誤認の訂正

将軍は「ext4キャッシュDB不在」と断定したが**パス誤認**。既存キャッシュは存在する:
- 正しいパス: `/tmp/shogun_memory_db_cache/_mnt_c_tools_multi-agent-shogun_multi_agent_shogun_memory.db`
- 生成元: `memory_db_live_insert.py L188 sync_memory_db_ext4_cache()`
- 速度: ext4キャッシュ=0.086-0.118秒/クエリ（NTFS 2.2-4.6秒の18-50倍速）。4クエリ追加でも<0.5秒。**ボトルネックではない**

### 深刻なインフラバグ（家老検出）

`/tmp/shogun_memory_db_cache`にtmp残骸**2634個、182GB蓄積**。sync失敗/中断時のtmp未掃除。三層記憶cmdではなくインフラバグとして別途対処が必要。

### cmd#-1の修正

「ゼロから作る」→「既存キャッシュをgate/health/promptの正本read pathへ昇格+tmp残骸cleanup+容量gate+鮮度管理」に変更。

- WHO: 忍者
- WHAT: (1)gate_three_layer_health.sh/prompt_state_inject.shのread pathを既存ext4キャッシュに接続 (2)tmp残骸cleanup(TTL/世代管理) (3)cache不在時の初期生成(sqlite3 backup API、上限時間+ntfy) (4)容量gate(du閾値超WARN)
- WHEN: #0の前。全SQLiteクエリの前提
- WHERE: scripts/memory_db_live_insert.py sync_memory_db_ext4_cache + /tmp/shogun_memory_db_cache/
- HOW: 読み書き責務分離: **read-heavy**(gate/prompt/health)=ext4キャッシュ必須。**write/transaction**(live_insert/update_event_state)=NTFS正本DB+キャッシュ同期。live_insertはcanonical DB+cacheへ二重反映(既存sync関数)。失敗時staleフラグ+bounded WARN。重いrebuildはbackground/手動cmd
- WHY: 既存キャッシュは動いているが「使われていない」。gate/health/promptがNTFS直接クエリしている。接続するだけで<0.5秒

### 殿の問い「今も三層記憶を使っているのか？」への回答

search_logs 617件は自動プロセス(cmd_save/deploy_task等)の発火。将軍自身が記憶DBを意識的に検索し判断に使った回数はこのセッションでゼロ。三層記憶を**作った**が**使っていない**。これが§1の問題「部品は揃ったが貫通していない」の最も根本的な表れ。L0-L7貫通は「接続する」だけでなく「実際に使われる」状態を作ること。

## §3 L0: ドキュメント貫通

**目的**: 全エージェントが三層記憶の存在と使い方を起動時に知る

**接続先**:
- context/infrastructure.md §記憶DB — 新機能(state管理/raw_content/矛盾候補/Obsidian昇格/想起制御)の1行索引+参照先を追記
- context/memory-db-schema.md — 既にCLEAR済み(7件記載)。確認のみ

**CLI別正本追記必須**（v4家老指摘#1）: Claude Code=CLAUDE.md、Codex=AGENTS.md。両方に三層記憶1行索引が必須。忍者はCLI種別に関係なく三層記憶の存在を知る

**AC**: (1)infrastructure.md §記憶DBに三層記憶新機能5項目の索引行が存在する (2)CLAUDE.md §Infraに三層記憶1行索引が存在する (3)AGENTS.md §Infraに三層記憶1行索引が存在する

## §4 L1: startup gate貫通

**目的**: セッション開始時に三層記憶の健全性を自動チェック

**接続先**: scripts/gates/gate_three_layer_health.sh（共通関数） + gate_shogun_startup.sh/gate_karo_startup.sh/gate_gunshi_startup.sh

**チェック項目**:
1. events.state列にraw以外の値が存在するか（state遷移が実際に動いているか）
2. raw_content列の充填率（新規イベントにraw_contentが入っているか）
3. contradiction/duplicate候補の未処理件数（溜まりすぎていないか）
4. obsidian_candidate件数（昇格候補が生成されているか）

**AC**: 各ロールstartup gateがgate_three_layer_health.shを呼び、4項目と統一スコアがOK/WARNで表示される

## §5 L4: 忍者タスク注入貫通

**目的**: 忍者が記憶DB操作cmdを実行する際に三層記憶のstate管理ルールが自動注入される

**接続先**: deploy_task.sh inject_semantic_concepts

**方法**: セマンティック辞書にlocal_memory_db概念のresourcesとしてstate遷移ルール(memory-db-schema.md §state)を追加。deploy_task.shが自動注入する既存の仕組みに乗る

**AC**: 記憶DB関連cmdの忍者タスクYAMLにstate管理ルールへの参照が自動注入される

## §6 L5: プロンプト注入貫通

**目的**: 将軍のプロンプトに矛盾候補/昇格候補の未処理件数を自動表示

**接続先**: prompt_state_inject.sh

**方法**: events.stateが contradiction_candidate/duplicate_candidate/obsidian_candidate のイベント件数を1行で表示。将軍が未処理候補の存在を知り、対処cmdを起票する導線

**AC**: prompt_state_inject.shが矛盾候補N件/昇格候補M件を将軍プロンプトに表示する

## §7 L7: 自動成長貫通

**目的**: recall_controlとobsidian_promoteが定期自動実行される

**接続先**: ninja_monitor.sh idle自動トリガー

**方法**: ninja_monitorのidle時チェックに以下を追加:
1. recall_control: 最終実行から7日以上経過→自動実行（verified→archivedの定期巡回）
2. obsidian_promote: 最終実行から7日以上経過→自動実行（昇格候補の定期抽出）
3. contradiction_scan: insight_writeで未処理矛盾候補件数が閾値超→WARN表示

**パターン**: lesson_deprecation_scan.shと同じ(4003行付近)。STATE_FILE+interval制御+log出力

**AC**: ninja_monitor.shにrecall_control/obsidian_promote定期実行トリガーが追加され、idle時に自動実行される

## §8 L2/L3/L6の接続方法（家老指摘#4反映: 不要扱いせず接続方法を明示）

**L2 (PreToolUse hook)**: memory_db_live_insert.py VALID_EVENT_STATES(cmd_3164)がINSERT時にstate値を検証。直接hookは不要だが、L2として「不正state値はVALID_EVENT_STATESで拒否される」ことを§10成功判定に含める

**L3 (PostToolUse hook)**: memory_db_live_insert経由の書込みは既にPostToolUse hookチェーン内(cmd_save/inbox_write/bulletin_write等)で発火。L3として「live_insert経由の全書込みがraw_content列を充填する」ことを§10成功判定に含める

**L6 (学習速度)**: state遷移率(verified→archived件数/日)+raw_content充填率+矛盾候補処理速度をL6計測指標として§4(startup gate)に含む。「どれだけ速く記憶を育てているか」の計測

## §9 実装CMDチェックリスト（家老指摘反映: #0追加/#2全role化/#5 dry-run/#6 Obsidian戻り経路）

| # | 内容 | Level | depends_on | 想定規模 | 家老指摘 |
|---|------|-------|-----------|---------|---------|
| -1 | 既存ext4キャッシュをgate/health/promptのread pathへ昇格+tmp残骸cleanup(182GB)+容量gate+鮮度管理 | 速度前提 | なし | 中 | §2.5: 既存cache 0.1秒。接続するだけ |
| 0 | 設計書2本commit+実DB schema差分確認(event_state_transitions不在→バックアップ付きschema作成+ensure_schema実行+再確認)+obsidian_promoted state 8値化 | L0前提 | #-1 | 小 | 指摘#1,#3+v4(3) |
| 1 | infrastructure.md三層記憶索引追記 | L0 | #0 | 小(索引5行) | — |
| 2 | startup gate三層記憶健全性チェック(全role共通gate関数化) | L1+L6 | #1 | 中 | 指摘#2: 将軍のみ→全role |
| 3 | セマンティック辞書local_memory_dbにstate管理resource追加 | L4 | #1 | 小 | — |
| 4 | prompt_state_inject.sh矛盾/昇格候補件数表示 | L5 | #2 | 小 | — |
| 5 | ninja_monitor.sh recall_control/obsidian_promote(dry-run first+バックアップ+上限+ntfy) | L7 | #2 | 中 | 指摘#5: dry-run開始 |
| 6 | Obsidian正式昇格→SQLite対応更新の戻り経路スクリプト | L7補完 | #5 | 中 | 指摘#6: 戻り経路 |

| 7 | 三層記憶使用計測(使用回数/結果/フィードバック)をstartup gateに追加 | L6強化 | #2 | 中 | 覚醒§1.5 欠落A |
| 8 | 新機能追加時のL0-L7貫通自動チェックgate(cmd_save.sh拡張) | 免疫系 | #2 | 中 | 覚醒§1.5 欠落B |
| 9 | 候補確定共通パイプライン(矛盾/重複/昇格/アーカイブの統一確定→反映→検証フロー) | L7補完 | #6 | 中 | 覚醒§1.5 欠落C |

計11cmd。順序変更（§2.5速度前提+§1.7核心前倒し）:
#-1(キャッシュ基盤)→#0→#1→#7,#8(核心・並列)→#2→#3,#4(並列)→#5→#6→#9

### §9.1 各cmdの5W1H詳細（軍師覚醒指摘v3対応）

**#2 全role共通startup gate健全性チェック**
- WHO: 各ロールのstartup gate(gate_shogun_startup.sh/gate_karo_startup.sh/gate_gunshi_startup.sh)
- WHAT: events.state分布/raw_content充填率/矛盾候補件数/昇格候補件数の4指標表示
- WHEN: 各ロールのセッション起動時(既存startup gateフロー内)
- WHERE: scripts/gates/gate_three_layer_health.sh(共通関数。各role startup gateからsource)
- HOW: SQLite SELECT COUNT(*) GROUP BY stateをmemory_db_cache_path()由来のext4キャッシュDBで実行（現物0.086-0.118秒/クエリ）。呼出し方法=各startup gateに`source "$SCRIPT_DIR/scripts/gates/gate_three_layer_health.sh" && check_three_layer_health`の1行追加
- WHY: 三層記憶の健全性を全ロールが起動時に自動確認。使われない機能をWARNで検出

**#5 ninja_monitor定期トリガー(dry-run first)**
- WHO: ninja_monitor.sh(idle自動トリガー)
- WHAT: recall_control(verified→archived巡回)+obsidian_promote(昇格候補抽出)の定期実行
- WHEN: 最終実行からN日経過時。初期値=7日。根拠: 現在の日次イベント増加量≈200件/日。7日=1400件蓄積。stale候補が有意に出る最小単位。運用後にイベント増加速度から調整
- WHERE: scripts/ninja_monitor.sh内のidle自動トリガーセクション(L4003 lesson_deprecation_scanと同パターン)
- HOW: STATE_FILE+interval制御。初期はDRY_RUN=1で候補リスト生成のみ(DB更新なし)。DRY_RUN解除は将軍が手動(殿承認後)。上限=1回100件。バックアップ=実行前にcreate_sqlite_backup(SQLite backup API使用。cpは停止中/冷backup限定)。ntfy=実行結果通知
- WHY: 記憶の自動メンテナンス。手動だと忘れる(=使われない)

**#7 三層記憶使用計測**
- WHO: gate_three_layer_health.sh(#2で作成する共通gate)
- WHAT: 各機能の使用回数。計測対象: (1)search_logsテーブルのquery件数/日(検索) (2)events WHERE state!=raw の件数(state遷移) (3)events WHERE raw_content IS NOT NULL の件数(原文保存) (4)events WHERE state LIKE '%candidate' の件数(候補生成)
- WHEN: 各セッション起動時(#2と同タイミング)
- WHERE: gate_three_layer_health.sh内の使用計測セクション
- HOW: SQLite SELECT COUNT(*)を4本実行。使用回数0の機能をWARN表示。search_logsは直近7日、eventsは全期間
- WHY: 接続した≠使われた。使用0件の機能が放置される構造を検出

**#8 貫通自動チェックgate**
- WHO: cmd_save.sh(将軍cmd起票gate)
- WHAT: 新機能追加cmdでL0-L7接続が記載されているかチェック
- WHEN: cmd_save.sh実行時。target_pathにmemory_db|memory_recall|obsidian_promote|memory_candidate|semantic-index|memory-db-schemaを含むcmdが対象
- WHERE: scripts/cmd_save.sh内の新チェック関数check_three_layer_penetration
- HOW: target_pathが記憶DB関連(memory_db|memory_recall|obsidian_promote|memory_candidate|semantic-index|memory-db-schema)の場合、AC/command/q8にL0-L7 coverage map(infrastructure.md+startup gate+deploy_task+prompt_state_inject+ninja_monitor)の5接続先への言及または明示除外理由を要求。キーワード1つでは通さない。WARN(初期)→段階BLOCK化
- WHY: 新機能が部品だけ作られて導線なしで放置されることを防ぐ免疫系

**#9 候補確定共通パイプライン**
- WHO: 将軍(確定判断)+忍者(反映実行)。候補生成は自動、確定は人間
- WHAT: 矛盾/重複/昇格/アーカイブの4種候補に対する統一確定フロー
- WHEN: startup gate(#2)で未処理候補件数がWARN → 将軍がcmd起票 → 忍者が確定スクリプト実行
- WHERE: scripts/memory_candidate_resolve.sh(新規。4種候補の統一確定スクリプト)
- HOW: `bash scripts/memory_candidate_resolve.sh <candidate_type> <event_id> <action> <reason>`。action=approve(確定)/reject(棄却)/defer(保留)。approve時: (1)state更新 (2)Obsidian反映(昇格の場合) (3)SQLite対応関係更新 (4)遷移ログ記録。検証=更新後にSELECT確認+ntfy通知
- WHY: 候補が生成されても確定する手段がなければ永遠にpending。自動=候補まで、確定=人間。その橋

**#0 設計正本commit+DB schema差分確認**
- WHO: 忍者
- WHAT: (1)設計書2本をgit add+commit (2)sqlite3で event_state_transitions テーブル存在確認 (3)不在→バックアップ(create_sqlite_backup)+ensure_schema実行+再確認 (4)VALID_EVENT_STATESにobsidian_promotedを追加し8値化
- WHEN: 即時(他cmd全ての前提)
- WHERE: docs/research/配下2本 + data/multi_agent_shogun_memory.db
- HOW: git add+commit。sqlite3 .tables grep。不在時はmemory_db_import.py ensure_schema
- WHY: 未tracked設計書はL0正本化未完了。DBスキーマ差分は想起制御前提崩壊

**#1 infrastructure.md+CLI別正本三層記憶索引追記**
- WHO: 忍者
- WHAT: infrastructure.md §記憶DBに新機能5項目索引 + CLAUDE.md §Infraに三層記憶1行索引 + AGENTS.md §Infraに三層記憶1行索引
- WHEN: #0完了後
- WHERE: context/infrastructure.md + CLAUDE.md + AGENTS.md
- HOW: Edit toolで索引行追記。CLAUDE.md/AGENTS.mdは同等の1行(「三層記憶|state管理/raw_content/矛盾候補/Obsidian昇格/想起制御|→ context/memory-db-schema.md + infrastructure.md §記憶DB」)
- WHY: 全エージェントが三層記憶を知る導線。忍者はinfrastructure.md読まない→CLI別自動ロード正本（Claude Code=CLAUDE.md、Codex=AGENTS.md）への索引が必須(§1.7 #1)

**#3 セマンティック辞書state管理resource追加**
- WHO: 忍者
- WHAT: docs/semantic-index/index.mdのlocal_memory_db概念にstate遷移ルール(memory-db-schema.md §state)をresource追加
- WHEN: #1完了後(#4と並列可)
- WHERE: docs/semantic-index/index.md
- HOW: local_memory_db概念のresourcesブロックにfile参照1行追加
- WHY: deploy_task.shが自動注入する既存仕組みに乗せ、忍者が記憶DB cmdでstate管理ルールを自動受領

**#4 prompt_state_inject.sh候補件数表示**
- WHO: 忍者
- WHAT: 将軍プロンプトにcontradiction_candidate/duplicate_candidate/obsidian_candidateの未処理件数を1行表示
- WHEN: #2完了後(#3と並列可)
- WHERE: scripts/hooks/prompt_state_inject.sh
- HOW: SQLite SELECT COUNT(*) FROM events WHERE state LIKE '%candidate' GROUP BY state。memory_db_cache_path()由来のext4キャッシュDBを使用。件数>0の場合のみ表示
- WHY: 将軍が未処理候補の存在を知り対処cmdを起票する導線。表示なし=気づかない=永遠にpending

**#6 Obsidian正式昇格→SQLite戻り経路**
- WHO: 忍者
- WHAT: obsidian_candidate→Obsidianノート作成→SQLite state=obsidian_promoted更新→対応関係記録の一連フロー
- WHEN: #5完了後
- WHERE: scripts/obsidian_promote_finalize.sh(新規)
- HOW: (1)obsidian_candidateイベントのsummary/raw_contentからObsidianノート雛形生成 (2)state→obsidian_promoted更新 (3)Obsidianノートパス+event_idの対応をeventsテーブルのmetadataに記録 (4)ntfy通知。バックアップ=create_sqlite_backup
- WHY: candidate生成→正式昇格の橋。候補止まりではObsidian層に到達しない

**§10 成功判定 WHO**: gate_three_layer_health.sh(#2)がセッション起動時に自動計算。スコア90/110以上=貫通完了。将軍がスコアと内訳を確認し不足項目にcmd起票。自動計測+人間判断の2段構え

## §10 成功判定（v6: 統一スコア方式。§1.7各論パッチ#7是正）

**統一判定**: gate_three_layer_health.shが出力する**三層記憶健全度スコア(0-110)**が閾値以上。個別チェックリストではなく単一スコアで判定する。

**スコア計算（11指標×10点=110点満点）**:

| # | 指標 | Level | 計測方法 | 10点=OK / 0点=NG |
|---|------|-------|---------|-----------------|
| 0 | ext4キャッシュDB存在+鮮度 | 速度前提 | memory_db_cache_path()由来のext4キャッシュ存在+本体DBとのmtime差<1h | 存在+鮮度OK=10 / 不在or stale=0 |
| 1 | 設計書正本commit | L0 | git status 2本 | commit済み=10 / untracked=0 |
| 2 | CLAUDE.md+AGENTS.md+infrastructure.md索引存在 | L0 | grep 5キーワード(CLI別正本全て) | 5件以上=10 / 0件=0 |
| 3 | startup gate健全性チェック稼働 | L1 | gate出力にstate分布あり | あり=10 / なし=0 |
| 4 | VALID_EVENT_STATES 8値定義(obsidian_promoted含む) | L2 | grep VALID_EVENT_STATES | 8値=10 / 不足=0 |
| 5 | raw_content充填率 | L3 | SELECT COUNT WHERE raw_content NOT NULL / 直近7日INSERT | >0%=10 / 0%=0 |
| 6 | 忍者タスクにstate参照自動注入 | L4 | deploy_task.sh inject確認 | 注入あり=10 / なし=0 |
| 7 | プロンプトに候補件数表示 | L5 | prompt_state_inject出力確認 | 表示あり=10 / なし=0 |
| 8 | 使用計測4指標が全て>0 | L6 | search_logs/state遷移/raw_content/候補 | 全>0=10 / 1つでも0=0 |
| 9 | ninja_monitor定期トリガー稼働 | L7 | STATE_FILE存在+dry-runログ | 稼働=10 / 未稼働=0 |
| 10 | 候補確定パイプライン存在+動作 | L7補完 | memory_candidate_resolve.sh存在+テスト | 動作=10 / なし=0 |

**判定基準**: 90/110以上=貫通完了。70-89=WARN(不足項目cmd起票)。69以下=BLOCK

**§10 WHO**: gate_three_layer_health.shがセッション起動時に自動計算。将軍がスコアを確認し不足項目にcmd起票。自動計測+人間判断の2段構え。

## §11 家老レビュー指摘対応表（2026-06-04T01:49）

| # | 指摘 | 対応 |
|---|------|------|
| 1 | 設計書2本が未trackedでL0正本化未完了 | §9 #0追加: commit+schema差分確認 |
| 2 | L1がgate_shogun_startupのみで他role未貫通 | §9 #2: 共通gate関数化で全role startup接続 |
| 3 | event_state_transitionsが実DBに不在 | §9 #0: 実DB schema差分確認で存在チェック |
| 4 | L2/L3/L6を不要扱いで成功判定と矛盾 | §8: 接続方法明示。§10: 全L0-L7の判定基準追加 |
| 5 | L7自動実行はdry-runから開始すべき | §9 #5: dry-run first+バックアップ+上限+ntfy |
| 6 | Obsidian正式昇格後の戻り経路がない | §9 #6: 戻り経路スクリプト追加 |

## 因果リンク

- ← [[three-layer-memory-operating-principles_20260603]] 三層記憶設計書(機能定義)
- ← [[growth-loop]] §11防御階層原則(L0-L7定義)
- ← [[deepdive_why_chain_20260321]] Phase 4-5(自動化×強制=知性の外部化)
- → [[infrastructure]] §記憶DB(L0接続先)
- → [[gate_shogun_startup]] (L1接続先)
- → [[deploy_task]] (L4接続先)
- → [[prompt_state_inject]] (L5接続先)
- → [[ninja_monitor]] (L7接続先)
