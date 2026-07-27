# /clear前準備の3指揮官共通スキル化 — ASIS/TOBE 5W1H (2026-07-27)

- 起案: 将軍(殿下知 2026-07-27 10:57「3人がクリア前の準備をできる共通のスキルにアップデートしたい」)
- 殿の原則: 「いまクリアされても今より強くてニューゲームできるようにせよ」は**各自の問題**である。将軍だけが準備し家老・軍師が裸で/clearされる現状は原則に反する
- origin: [[殿下知_clear_prep共通化_20260727]] -> [[shogun-clear-prep]] -> [[本設計書]]

## §1 ASIS(現状)

### 現行の非対称(一次確認済み)
| ロール | /clear前準備 | 記憶連続性の担い手 | 消えるもの |
|---|---|---|---|
| 将軍 | **/shogun-clear-prep**(SKILL.md 107行+clear_prep_check.sh 1170行): G0殿指示ガード+会話退避+12項目チェック+session_summary+ntfy | compact_state / MEMORY.md / 三層記憶 / lessons_shogun | (準備すれば)ほぼなし |
| 家老 | **なし**。ninja_monitorが陣形図付き/clearを自動送信(KARO_CLEAR_DEBOUNCE=120s)するのみ | karo_snapshot / lessons_karo / karo_workarounds | 進行中の判断状態・保全/凍結宣言・観測役割・注視点・レビュー途中状態 |
| 軍師 | **なし** | gunshi_review_log / lessons_gunshi | レビュー途中状態・draft指摘の未消化分・観測中の仮説・「網羅していない範囲」の申告在庫 |

### 実害(本日2026-07-27の実証)
1. **保全宣言の失念**: 家老が自分の保全宣言(lessons.yaml書込み禁止)を同一セッション内ですら失念し破壊した。宣言はinbox archiveにしか無く、/clear後なら発見すら不可能だった
2. **観測役割の非永続**: 家老が「single-flight timeout同型の観測役」を引き受けたが、この役割はどのファイルにも構造化されておらず/clearで消える
3. **lessons_karo上限35件到達**: 家老の学びが教訓として登録不能=セッションの学びの受け皿が詰まっている(blt_075316)。instructions追記で代替したが読了強制はロール非対称(READ_REQUIRED機構は軍師gateのみ、karo:0/shogun:0 — blt_080530)
4. **「実装したが接続していない」型**: 4規律をinstructionsへ書いたが「書いてあることと読まれることは別」(軍師留保 blt_075935)。準備→復帰の往復が機械検証されていない

### 根本欠陥
- **準備は将軍のみ・復帰は3者全員**という片翼構造。Recovery手順(CLAUDE.md)は3ロール分あるのに、その入力(compact_state・宣言台帳・観測役割)を作る側が将軍にしか無い
- 家老の/clearはninja_monitorの**自動送信**であり、準備ステップを挟む場所が経路上に存在しない

## §2 TOBE — 原理1行

**「強くてニューゲーム」は各自の問題: /clearされる者が自分で退避し、次の自分がstartup gateでそれを必ず読む — 準備と復帰を同一ロールで閉じた往復にする。**

## §3 5W1H

### What(何を作るか)
- **skills/clear-prep/** — 3指揮官共通スキル(新規)。/shogun-clear-prepは薄いaliasとして残すか廃止統合
- **scripts/clear_prep_check.sh のロール対応化** — 新スクリプトは作らない(車輪の再発明禁止)。`tmux @agent_id`で自ロールを判定し、共通チェック+ロール別チェックを切り替える
- **compact_state のロール別化** — `queue/compact_state_{role}.yaml`(将軍は既存を継承)。進行中判断・宣言・観測役割・注視点の構造化退避先

### Why(なぜ)
- 記憶の連続性は指揮官3者の生命線(殿下知10:57)。忍者は記憶なし前提で設計済み(task YAML注入)だが、指揮官は「進行中の判断状態」を跨いで持つ必要がある
- 本日の実害3件(§1)は全て「退避先が無い/読まれない」に帰着する
- 知性の外部化原則: エージェントは/clearで死ぬ。環境(ファイル)に蓄積した者だけが強くてニューゲームできる[[deepdive_why_chain_20260321]] Phase 5/9

### Who(誰が)
- 実装=忍者(家老が分解・配備)。設計=将軍(本書)。レビュー=軍師(draft先行 — 本日の「配備後レビューは間に合わない」教訓を適用)
- 運用=将軍・家老・軍師が各自実行。**各自の問題**であり他ロールに代行させない

### When(いつ実行されるか)
- 将軍: 殿の/clear指示時(現行G0ガード維持)
- 家老: ninja_monitorが家老/clearを送信する**前**に、nudgeで/clear-prep実行を先行指示し、prep完了マーカー(後述)を確認してから/clearを送る(経路上に準備ステップを新設)。タイムアウト(例: 5分)でマーカー無しでも/clearは送る(fail-open: CTX保護が優先)
- 軍師: idle時のCTX閾値到達またはセッション終了指示時。軍師には自動/clear経路が無いため、gate_gunshi_startupの逆向き=stop hookでCTX高時にprep推奨を表示(recommend方式・BLOCK禁止=スキル推薦L5裁定)

### Where(何がどこへ退避されるか)
| 退避物 | 先 | 消費者(復帰時) |
|---|---|---|
| 進行中判断・現在タスク・recovery_pointer | queue/compact_state_{role}.yaml | 各ロールRecovery手順(CLAUDE.md該当Step) |
| 保全・凍結・観測役割などの**効力ある宣言** | queue/active_declarations.yaml(新規・全ロール共有・宣言者/対象/期限/解除条件を構造化) | startup gate 3種+deploy_task保全ガード(才蔵配備中のcmd_karo_impl_preserved_path_deploy_guardの保全リスト正本と統合=二重管理禁止) |
| セッションの学び | lessons_{role}.yaml(上限詰まりの解消が前提条件 → 別弾) | 起動時自動ロード |
| 未クローズレビュー・未消化draft指摘(軍師) | logs/gunshi_review_log.yaml既存欄+compact_state_gunshi | gunshi Recovery Step 4 |

### How(どう強制するか — 意志依存ゼロ化)
1. **共通コア**(3ロール同一): inbox未読0確認 / 掲示板action_required未対応0確認 / 自ロールWIP(未commit)の申告 / compact_state_{role}書出し / active_declarations棚卸し(自分の宣言に期限切れ・目的喪失がないか — 本日の保全宣言失念の直接対策) / session_summary1行追記
2. **ロール別チェック**: 将軍=現行Check 0-12を継承(会話退避・PD・裁定反映) / 家老=陣形図整合+WA台帳+pending ruling+観測役割の引継ぎ記載 / 軍師=review_log未クローズ+網羅限界申告の在庫化
3. **往復の機械検証**: prep完了時にマーカー(logs/clear_prep_receipt_{role}.jsonl へ1行)を残し、**startup gateがマーカーとcompact_stateの鮮度を突合** — 「準備なしで/clearされた」ことが次セッション冒頭で可視化される(表示のみ・BLOCKしない。準備なし/clearは起こり得る前提でfail-open)
4. **軽量必須**: /clear直前は残CTXが小さい。チェックは全てBash(1コマンド)で完結し、LLMの作文を最小化する(厳密さは最終checkpointのみ・途中1行ログ原則)

## §4 やらないこと(安全境界)
- 忍者への拡張はしない(忍者=記憶なし前提の設計が正。task YAML注入で完結)
- prep未実行の/clearをBLOCKしない(CTX保護>準備。fail-open)
- 新デーモン・新watcher・新閾値の追加はしない(既存ninja_monitor/startup gate/stop hookへの接続のみ)
- clear_prep_check.shの将軍向け既存チェックの削除はしない(削るな、速くしろ)

## §5 レビュー論点(家老・軍師への問い)
1. 家老の自動/clear経路への準備ステップ挿入(When欄)は、ninja_monitorのdebounce/respawn設計と競合しないか(家老)
2. active_declarations.yamlは才蔵配備中の保全リスト正本と**同一ファイル**にすべきか(二重管理禁止の観点)(軍師)
3. 軍師のprepトリガー(stop hook recommend方式)はCTX閾値何%が妥当か。ninja_monitorのCTX観測を流用できるか
4. lessons_karo上限35件の詰まりは本スキルの前提条件(学びの受け皿)。統合弾を先行させるべきか
5. 忍者auto clear停止調査(軍師gist e6e289f3: staged残置→auto-commit skip→/clear中止174件)との統合是正の要否 — /clear経路の健全化として同一作戦に入れるか

## §6 実装順序(案)
1. clear_prep_check.shロール判定+共通コア(可逆・既存拡張)
2. compact_state_{role}+prep receipt+startup gate突合(往復の閉じ)
3. active_declarations正本化(才蔵の保全リスト弾と統合)
4. 家老自動/clear経路への挿入(ninja_monitor 1点変更)
5. 軍師stop hook recommend接続
