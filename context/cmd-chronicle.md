# CMD年代記
<!-- last_updated: 2026-04-21 -->

> 完了cmdの1行索引。詳細は queue/archive/cmds/{cmd_id}.yaml 参照。

## 2026-03

| cmd | title | project | date | key_result |
|-----|-------|---------|------|------------|
| — | → 3月前半(03-09, cmd_662-707)は `context/archive/cmd-chronicle-2026-03-early.md` 参照 | — | 03-09 | 43件 |
| cmd_940 | 偵察+整備 — Drive確定申告フォルダの整合性検証+チェックリスト恒久化 | | auto-ops | 03-14 | Drive「2026確定申告 個人事業」フォルダの完全性・整合性チェック完了。 3AC全て調査完了。ローカルCSVとDrive版の間に体系的な差異を検出。 |
| cmd_942 | 偵察 — 確定申告証票PDFの重複・有効性調査 | | auto-ops | 03-14 | — |
| cmd_944 | 修正 — マスターCSV更新（MFクレカ追加反映） | | auto-ops | 03-14 | — |
| cmd_945 | 修正 — PayPal公式レシートPDFでDrive既存PDFを差し替え | | auto-ops | 03-14 | — |
| cmd_946 | 実装 — マスターCSV列16「使用カード」追加 | | auto-ops | 03-14 | — |
| cmd_943 | 修正+整備 — 確定申告証票PDF浄化 | | auto-ops | 03-14 | — |
| cmd_949 | 修正 — CDP修復+note領収書DL試行 | | auto-ops | 03-15 | — |
| cmd_948 | 修正 — Anthropic領収書アップロード+[OK]格上げ | | auto-ops | 03-15 | — |
| cmd_947 | 修正 — note.com領収書DL（売上手数料2件+振込手数料11件） | | auto-ops | 03-15 | — |
| cmd_950 | 偵察 — 欠損領収書6商号Gmail調査+取得可能性判定 | | auto-ops | 03-15 | — |
| cmd_951 | 修正 — 全Driveフォルダ Invoice/Receipt混在是正 | | auto-ops | 03-15 | — |
| cmd_955 | 最適化 — monthly-returns fallback window query化（-88%改善） | | dm-signal | 03-15 | — |
| cmd_956 | 最適化 — monthly_trade N+1クエリ修正（170→3 queries） | | dm-signal | 03-15 | — |
| cmd_957 | 偵察 — MCP obs正本突合（Vercel原則適用） | | infra | 03-15 | — |
| cmd_959 | 偵察 — MCP判定割れobs万全偵察（8名独立判定） | | infra | 03-15 | — |
| cmd_960 | 強化 — 逆瀬川記事知見4点取込 | | infra | 03-15 | — |
| cmd_961 | 強化 — tdd-guard型Hook＋Gate（テストSKIP/FAIL機械強制） | | infra | 03-15 | — |
| cmd_962 | 万全偵察 — DM-signal UX快適性の現況再調査 | | dm-signal | 03-15 | — |
| cmd_964 | 修正 — FEキャッシュ整合性修復（ETag孤児/SWR不統一） | | dm-signal | 03-15 | — |
| cmd_963 | 修正 — BE N+1クエリ修正High3件 | | dm-signal | 03-15 | — |
| cmd_967 | 修正 — trade-rule.md §7.3aに§2.1 SSOT 3層への逆参照追加 | | dm-signal | 03-15 | trade-rule.md §7.3aの逆参照注記を強化。既 |
| cmd_968 | 強化 — 金融ML知識辞書 ID予約済み5エントリの辞書化 | | dm-signal | 03-15 | 金融ML知識辞書 ID予約済み5エントリの辞書化完了。 全フ |
| cmd_965 | 最適化 — Recharts/KaTeX dynamic import強化（バンドル27%削減） | | dm-signal | 03-15 | Recharts/KaTeX dynamic import強 |
| cmd_966 | 修正 — FEテスト5件FAIL修復（現行コードへの追随） | | dm-signal | 03-16 | — |
| cmd_958 | 修正 — MCP Vercel原則適用（構造改革） | | infra | 03-16 | — |
| cmd_969 | 強化 — DM-Signal Ruff導入 + PostToolUse Hook品質ループ構築 | | dm-signal | 03-16 | — |
| cmd_971 | 強化 — DM-Signal FE Biome PostToolUse Hook + Hurl API E2Eテスト | | dm-signal | 03-16 | DM-Signal FE Biome導入+PostToolU |
| cmd_974 | 偵察 — Codex忍者のアイデンティティ認識状況調査 | | infra | 03-16 | — |
| cmd_975 | 偵察 — DM-Signal PF健全性・現在ポジション・実績の定量調査 | | dm-signal | 03-16 | — |
| cmd_970 | 強化 — infra shellcheck PostToolUse Hook + リンター設定保全 | | infra | 03-16 | — |
| cmd_972 | 強化 — Stop Hook完了ゲート + エラーメッセージ修正 | | infra | 03-16 | — |
| cmd_973 | 強化 — AIアンチパターン検出 + ast-grepアーキテクチャ | | infra | 03-16 | — |
| cmd_976 | 偵察 — 殿の哲学から導くDM-Signal診断指標の再設計 | | dm-signal | 03-16 | — |
| cmd_978 | 衛生 — 全プロジェクト .gitignore整備 + 未プッシュ一覧 | | infra | 03-16 | — |
| cmd_980 | 偵察 — 教訓注入率低下の原因精査と改善提案 | | infra | 03-16 | — |
| cmd_979 | 強化 — lint違反放置禁止ルール + Stop Hook lint残留チェック | | infra | 03-16 | — |
| cmd_1010 | 四神12体+忍法15体 — 極値プロファイル・相関構造・忍法コンビネーション分析 | | dm-signal | 03-16 | AC7横断サマリー完了。4サブタスク(Sub-A〜D)の結果 |
| cmd_1241 | startup gateにGate 10(idle自走トリガー)を追加し、パイプライン空+全忍者idle時に将軍が自動的にidle時自己分析手順に入る仕組みを作る | infra | 03-22 | — |
| cmd_1242 | CI赤(run 23387382972)を修正し、全CIジョブを緑に戻す | infra | 03-22 | — |
| cmd_1244 | commit_missing(変更ありcommitなし)をcmd_complete_gate.shでBLOCK化し、忍者のcommit漏れを構造的に防止する | infra | 03-22 | — |
| cmd_1243 | L0-M_XLU holding_signal不一致の根本解決。^VIX/DTB3 cache汚染修正 | dm-signal | 03-22 | 64/65 PASS。PI-010追加 |
| cmd_1245 | シン青龍-鉄壁 2024-11パリティ最後の1件。65/65 PASS目標 | dm-signal | 03-22 | — |
| cmd_1246 | gate_report_format.shにverdict二値バリデーション追加。CONDITIONAL_PASS早期検出 | infra | 03-22 | PASS。テスト5件追加、退行なし |
| cmd_1247 | 偵察 — 33体本番DB登録の前提条件チェック(runbook突合+GAP検出) | dm-signal | 03-22 | — |
| cmd_1248 | gate_report_format.sh: lessons_useful/binary_checks形式バリデーション強化 | infra | 03-22 | — |
| cmd_1249 | cmd_1247偵察で発見されたFoF 21体のCRITICAL GAP 2件(component_portfolios旧v1構成+selection params全空)を解消し、v2正本CSVと一致させる | dm-signal | 03-22 | — |
| cmd_1252 | — | infra | 03-22 | — |
| cmd_1257 | シン四神・シン忍法登録ランブックをv2(33体)に更新し、本番登録cmdの前提条件を整える | dm-signal | 03-22 | — |
| cmd_1258 | dashboard CI状態の自動反映 + 陳腐化防止 | infra | 03-22 | — |
| cmd_1259 | dm-signal.yaml pipeline flow + registration陳腐化ステータス更新 | dm-signal | 03-22 | — |
| cmd_1260 | 軍師S6提案実装 — lessons_useful/binary_checksプリフィル + report構造強制 | infra | 03-22 | — |
| cmd_1261 | 軍師提案パイプライン構造化 — YAMLコメント→構造化フィールド+自動サーフェシング | infra | 03-22 | — |
| cmd_1262 | ninja_monitor.sh AUTO-DONE重複書込みバグ修正 — idle通知嵐の根絶 | infra | 03-22 | — |
| cmd_1264 | inbox_write.sh gate発火100%化 — サイレントスキップ→BLOCK | infra | 03-22 | — |
| cmd_1266 | 偵察 — FoF selection_pipeline動作乖離の根本原因調査 | dm-signal | 03-22 | — |
| cmd_1263 | ninja_monitorにcommit未完了チェック追加 — commit_missing構造的根絶 | infra | 03-23 | — |
| cmd_1268 | CI RED修正 — Unit Tests 9件失敗(ntfy_ack mock不備+auto_deploy_done不整合) | infra | 03-23 | — |
| cmd_1269 | FoFパリティ検証 バッチ1(7体) — cmd_1251スクリプト展開 | dm-signal | 03-23 | — |
| cmd_1270 | FoFパリティ検証 バッチ2(7体) — 第2陣並列実行 | dm-signal | 03-23 | — |
| cmd_1271 | FoFパリティ検証 バッチ3(7体) — 第3陣並列実行 | dm-signal | 03-23 | — |
| cmd_1272 | L1シン四神12体 登録スクリプト構築+dry-run検証 | dm-signal | 03-23 | — |
| cmd_1273 | 本番登録環境PI-006検証 — ランブックv2全Step実行可能性の事前確認 | dm-signal | 03-23 | — |
| cmd_1265 | report_field_set.sh強制hook — 忍者の直接Edit禁止で源流から構造不正防止 | infra | 03-23 | — |
| cmd_1275 | GS混乱候補スクリプト7本削除 — 忍法スクリプト誤用防止 | dm-signal | 03-23 | — |
| cmd_1277 | deploy_task.sh配備高速化 — preflight_gate_artifacts()からarchive_completed.sh呼出を除去し、配備時間を50秒→5秒に短縮する | infra | 03-23 | — |
| cmd_1279 | gate発火ログ計測基盤の構築 — gate_report_format.shの発火・結果をログに記録し、gate効果の定量的計測を可能にする | infra | 03-23 | — |
| cmd_1280 | lessons.yaml 3ファイルのVercel化 — 索引+アーカイブ分離で500行以下に圧縮し、読込エージェントのCTX浪費を構造的に解消する | infra | 03-23 | — |
| cmd_1282 | 運用ファイル3件のVercel化 — context/cmd-chronicle.md + context/infrastructure.md + logs/gunshi_review_log.yaml を500行以下に圧縮する | infra | 03-23 | — |
| cmd_1281 | 核心知識ファイル3件のVercel化 — projects/dm-signal.yaml + instructions/shogun.md + instructions/karo.md を500行以下に圧縮する | infra | 03-23 | dm-signal.yaml 307行+shogun.md 275行+karo.md 367行。二重配備(小太郎+疾風)発生もファイル破損なし |
| cmd_1283 | lesson_update_score.shのCACHE_FILE→lessons_archive.yaml切替 — Vercel化索引の再膨張防止 | infra | 03-23 | — |
| cmd_1284 | dashboard🚨要対応セクション清掃 + report_field_set.sh BLOCK昇格 | infra | 03-23 | — |
| cmd_1285 | 家老用スタートアップゲート作成 — deepdive必読の自動化×強制 | infra | 03-23 | — |
| cmd_1286 | GP-014 commit層自動防御 — report完了前のgit uncommittedチェックgate | infra | 03-23 | — |
| cmd_1290 | insightsキュー自動アーカイブ — doneエントリの残存防止 | infra | 03-23 | — |
| cmd_1291 | 報告YAMLアーカイブ時期修正 — 家老レビュー完了前のアーカイブ防止 | infra | 03-23 | — |
| cmd_1292 | ninja_monitor report存在チェック — report未作成での/clear防止 | infra | 03-23 | — |
| cmd_1293 | 忍者報告テンプレート導線修復 — format workaround源流根絶(GP-017) | infra | 03-23 | — |
| cmd_1294 | PreToolUse DENY実装 — Write/Editでの報告YAML直接作成を阻止(GP-003完遂) | infra | 03-23 | — |
| cmd_1301 | startup gate bash算術エラー修正 — grep -c || echo anti-pattern根絶 | infra | 03-23 | gate_shogun_startup.sh L101/L282の grep -c || echo anti-pattern を修正。syntax error  |
| cmd_1302 | cmd_complete_gate.sh archive実行タイミング修正 — GATE外完了の根絶 | infra | 03-23 | cmd_complete_gate.sh内のarchive_completed.sh呼出しをpreflight(L1581)からGATE CLEAR後(L381 |
| cmd_1303 | ninja_monitor uncommittedチェック scope修正 — 運用ファイル除外 | infra | 03-23 | git uncommittedチェックにgrep -v運用ファイル除外フィルタ追加。dashboard.md/logs/queue/inbox/.claude/ |
| cmd_1304 | 削除済みスクリプト参照27ファイルのクリーンアップ | infra | 03-23 | — |
| cmd_1305 | lesson_update_score.sh書込先修正 — Vercel化後のarchive参照切替 | infra | 03-23 | cmd_1283で既に対応済み。lesson_update_ |
| cmd_1306 | test_result_guard.sh偽陽性修正 — last_assistant_messageのSKIP誤検知除去 | infra | 03-23 | — |
| cmd_1307 | GP-021 ninja-adaptive failure injection — 忍者別過去失敗パターン自動注入 | infra | 03-23 | — |
| cmd_1308 | workaround率自動計測gate — cmd_complete_gate統合でpost-GP効果を自動追跡 | infra | 03-23 | — |
| cmd_1309 | queue/tasks/subtask_*.yaml 47件をarchive移動 — 旧アーキテクチャ残骸清掃 | infra | 03-23 | — |
| cmd_1310 | CI RED修正 — test_sync_lessons_injection_count_sync.bats L77 失敗 | infra | 03-23 | — |
| cmd_1311 | GP-003正規表現バグ修正 — report YAML hookが全忍者で未発火 | infra | 03-23 | — |
| cmd_1289 | GP-011 忍者別workaround率の自動計測・startup gate表示 | infra | 03-23 | — |
| cmd_1322 | GP-032 target_path存在検査WARN注入 | infra | 03-23 | inject_target_path_check関数をdeploy_task.shに追加。inject_credential_files直後に呼び出し。存在しな |
| cmd_1323 | STALL再配備時の旧報告テンプレート自動cleanup | infra | 03-23 | — |
| cmd_1324 | fix: lesson_impact.tsv タブ文字エスケープバグ修正+既存データ復旧 | infra | 03-23 | — |
| cmd_1326 | feat: cmd_complete_gate.sh GATE CLEAR後処理のpost-write verify横展開 | infra | 03-23 | — |
| cmd_1327 | fix: CI RED修復 — E2Eテスト2ファイルを現行編成に適合 | infra | 03-23 | — |
| cmd_1329 | fix: insights.yaml棚卸し — pending 25件の分類・重複削除・resolved更新 | infra | 03-23 | — |
| cmd_1328 | recon: GP-026実装設計 — report_yaml_missing BLOCK自動待機メカニズム | infra | 03-23 | report_yaml_missingの根本原因は2パターン: (1)gateが忍者未完了時に発火(61.5%), (2)CLEAR後archive移動→再ga |
| cmd_1330 | feat: GP-027実装 — commit漏れ検出WARN(gate check前) | infra | 03-23 | — |
| cmd_1331 | fix: CI Unit Test FAIL — test_text_utils.bats bash -lc を bash -c に修正 | infra | 03-23 | — |
| cmd_1334 | feat: GP-029実装 — insights自動起票品質改善(dedup+ID一意化) | infra | 03-23 | — |
| cmd_1332 | feat: GP-026実装(B案) — CLEAR済みcmd再check防止+全non-done WAIT | infra | 03-23 | — |
| cmd_1333 | feat: GP-028実装 — 教訓注入projectフィールドフォールバック | infra | 03-23 | — |
| cmd_1335 | feat: GP-023実装 — 軍師レビュー時cross-ninja WA率チェック | infra | 03-23 | — |
| cmd_1336 | CLEAR率65→85%向上、WA率53→27%半減。autofix→format check順序でrace condition根絶 | infra | 03-23 | — |
| cmd_1337 | ダッシュボード更新の意志依存を排除。イベント駆動で即時更新し将軍の判断速度を向上 | infra | 03-23 | — |
| cmd_1338 | GATE時にautofixを再実行しrace condition根絶。verdict/no_lesson_reason自動補完で61 FAIL根絶。CLEAR率65→85%。家老workaround構造的根絶 | infra | 03-23 | — |
| cmd_1339 | 将軍のcmd重複起票を構造的に防止。今日のcmd_1338重複事故(家老cmd_1336と同内容)のwhy chain分析から特定した自動化ターゲット | infra | 03-23 | — |
| cmd_1340 | 偵察教訓注入率0%(cmd_513全スキップ)を解消。偵察固有教訓が偵察タスクに伝わらず改善ループが断絶している。偵察は全cmdの前段であり品質の起点 | infra | 03-23 | recon/scout/researchの教訓全スキップを偵察固有7教訓(L219,L211,L213,L159,L104,L129,L128)のみ注入に変更。 |
| cmd_1341 | LLMには時系列の概念がない(殿指摘)。累積値は安心を与えるが因果を隠す。直近値は変化のシグナルを示す。recon注入率36%(実質0%)の誤認を構造的に防止 | infra | 03-23 | — |
| cmd_1342 | Step 2 Phase B — 既存追い風FoFパリティ検証（MomentumFilter） | dm-signal | 03-23 | 追い風FoF 3体(常勝/激攻/鉄壁)全期間パリティ検証完了。monthly_return(close/open)全月PASS。hs_cross_checkは各 |
| cmd_1343 | Step 2 Phase C — 既存抜き身FoFパリティ検証（SingleViewMomentumFilter） | dm-signal | 03-23 | — |
| cmd_1344 | Step 2 Phase D — 既存変わり身FoFパリティ検証（TrendReversalFilter） | dm-signal | 03-23 | — |
| cmd_1346 | Step 2 Phase E2 — 既存加速D FoFパリティ検証（MomentumAccelerationFilter diff） | dm-signal | 03-23 | — |
| cmd_1345 | Step 2 Phase E1 — 既存加速R FoFパリティ検証（MomentumAccelerationFilter ratio） | dm-signal | 03-23 | — |
| cmd_1347 | Step 2 Phase F — 既存FoFパリティ検証（MultiViewMomentumFilter 5体） | dm-signal | 03-23 | — |
| cmd_1350 | Step 1やり直し — numpy快速パスの本番パリティ検証 | dm-signal | 03-23 | — |
| cmd_1349 | Step 3 — シン四神v2 12体作成（shin_shijin_l1_gs.py）【中止】 | dm-signal | 03-23 | — |
| cmd_1348 | Step 2 Phase G — 既存ネステッドFoFパリティ検証（7体） | dm-signal | 03-23 | — |
| cmd_1351 | Step 1補強 — 本番standard PF全65体のnumpy快速パスパリティ検証 | dm-signal | 03-23 | — |
| cmd_1352 | 全standard PF numpy快速パス完全パリティ（hs+ret両方）+ L0-M_XLU原因特定 | dm-signal | 03-24 | — |
| cmd_1353 | numpy快速パス 53/53完全一致達成 — ^VIX grid汚染修正+hs順序一致 | dm-signal | 03-24 | — |
| cmd_1394 | — | infra | 03-25 | テスト4件全PASS。修正不要。awk実装はinvalid_lessons_useful_format/形式が不正を正しく出力しており、テスト期待値と整合済み。 |
| cmd_1392 | dashboard_auto_section.sh 高速化 — 22.5秒→5秒以下 | infra | 03-25 | model_analysis.sh --summaryをPython→bash/awkに置換。6.4s→0.8s(WSL2)。2秒以下達成 |
| cmd_1391 | CI RED修正 — simokitafresh/multi-agent-shogun 15テスト失敗 | infra | 03-25 | 担当テスト(ninja_monitor 9件)は他忍者(tobisaru+kotaro)のcommitで解決済み。追加作業不要 |
| cmd_1397 | シン四神v2(12体standard) + シン忍法v2(20体FoF)を本番DBに登録する。チェックリストStep 6 | dm-signal | 03-25 | シン四神v2 12体(standard)+シン忍法v2 20体(FoF)を本番DBに登録完了。全32体がAPI GET存在確認+フォルダー所属+pipeline |
| cmd_1398 | — | dm-signal | 03-26 | 全65 active standard PF ALL PASS (hs=完全一致, ret=完全一致)。シン四神v2 12体+既存53 PF全てパリティ検証完了 |
| cmd_1399 | — | dm-signal | 03-26 | シン忍法v2 20体パリティ検証完了。PASS=2体、FAIL=18体。18体のFAILは全てL485既知パターン（初月hs_cross不一致のみ）。構造的FA |
| cmd_1400 | — | infra | 03-26 | AgentsViewModel.kt L115の capture-pane -S パラメータを -50 から -500 に変更。assembleDebug BU |
| cmd_1401 | — | infra | 03-26 | RateLimitContentパース全null時rawTextフォールバック表示追加+execRateLimitCheck SSH空結果1回リトライ追加。ビル |
| cmd_1402 | — | infra | 03-26 | VoiceDictionarySection.ktをAnimatedVisibilityでアコーディオン化(デフォルト折りたたみ、タップ展開)。Constant |
| cmd_1403 | — | infra | 03-26 | Androidアプリからntfy通知機能を完全削除。3ファイル削除(NtfyService.kt/NotificationHelper.kt/NtfySetti |
| cmd_1414 | Auto-dreamを超える5 Phase Memory Consolidation。殿の原理(タイムスタンプ=因果推論/免疫系=進化)を実装。12システム調査の車輪(Zep二重タイムスタンプ/Audrey矛盾管理/Mnemosyne秒精度)を統合。Phase | infra | 03-27 | Dream-skill SKILL.md作成完了。設計書§2の全文を~/.claude/skills/dream/SKILL.mdに忠実配置。232行。diff |
| cmd_1077 | シン四神・シン忍法の本番DB登録手順書を作成し、忍者が即実行できる状態にする | dm-signal | 03-27 | — |
| cmd_1078 | シン玄武(DM7+)をXLU固定でPhase 3+Phase 4やり直し。DNA準拠の4体を再選定する | dm-signal | 03-27 | — |
| cmd_1079 | FE MAX_PORTFOLIOS を120→200に修正。BE(cmd_1076)との整合 | dm-signal | 03-27 | — |
| cmd_1084 | シン四神10体のpipeline_config欠落を修正し、full recalculateを再実行して正常なシグナル・月次リターンを生成する | dm-signal | 03-27 | — |
| cmd_1085 | LookbackPeriodスキーマのmonths上限を24→36に引き上げ、忍法FoFの長期lookbackを許容する | dm-signal | 03-27 | — |
| cmd_1101 | cmd_1096の診断結果に基づきFoF BBの不具合を修正し、シン忍法21体を再recalculateする | dm-signal | 03-27 | — |
| cmd_1133 | 家老の学習ループを構築する。karo.mdのレビュー・配備・GATE処理の各フェーズに品質チェックを組み込み、家老自身の判断を二値計測→還流する仕組みを作る | infra | 03-27 | — |
| cmd_1404 | — | infra | 03-27 | handleShareIntent内でURI→ByteArray読み取りをコルーチン外(同期)に移動。sendImageToNtfyの引数をUri→ByteAr |
| cmd_1405 | — | infra | 03-27 | E2Eテスト4件のタイムアウト失敗を修正。根本原因: get_unread_info()のPython出力で空normal_idsフィールドが連続タブを生成し、 |
| cmd_1406 | — | infra | 03-27 | gitignoreホワイトリスト整理完了。運用ファイル70件をgit rm --cachedで追跡解除、新規hooks4件+tests5件をgit add、co |
| cmd_1407 | — | infra | 03-27 | insight_write.sh環境変数サニタイズ(AC1)+deploy_task.sh安全書込み(AC2)+新規テスト14件全PASS(AC3)。既存36テ |
| cmd_1408 | — | infra | 03-27 | 防御的コーディング4件修正完了: (1)cmd_complete_gate.sh || true除去+エラー適切ログ (2)ntfy.sh ntfy_valid |
| cmd_1411 | — | dm-signal | 03-27 | AC3 PASS: R2(74.5%)>R1(63.8%) CAGR, R2(1.92)>R1(1.79) Sharpe。AC4: N=2-10全9パターン完了 |
| cmd_1412 | ネステッドFoFのR4(Half-Kelly)実装+外部レジーム(DTB3/VIX/SPY)分析。R1(63.8%)→R2(74.5%)→R4→R6_extの進化を検証し、最終ルールを決定する | dm-signal | 03-27 | R4 Half-Kelly実装完了。全出力ファイル生成済み。R4 CAGR=69.9% Sharpe=1.79 vs R2 CAGR=74.5% Sharpe= |
| cmd_1413 | R2(CAGR74.5%/Sharpe1.92/パラメータ0)を超えるか？最もシンプルな改善3手法(逆ボラ/絶対モメンタム/連続VIX)でテスト。R6_extルックアヘッドバイアス修正を含む。高度さではなくシンプルさで勝負 | dm-signal | 03-27 | R9(lag-1 VIX連続スケーリング)+R6_ext_lag1(離散lag-1)実装完了。全4出力ファイル生成済み。R9 CAGR=54.9% Sharpe |
| cmd_1436 | R1-R26の研究結論をビルディングブロック化する。Ward+二段EWの構造が構成PF非依存でワークすることを3段階（12体/21体/65体）で確認済み。内部グリッドサーチでK/LBを自動決定する汎用モジュールを実装し、R24/R25/R26の既知結果で検証する。 | dm-signal | 03-27 | PASS。building_block.py WardTwoStageEWクラス+共通関数3本。R24/R25/R26全検証8/8 PASS |
| cmd_1437 | WardTwoStageEWBlock実装。building_block.pyのWard+二段EWロジックをTerminalBlockとして本番パイプラインに移植 | dm-signal | 03-27 | PASS。ward_two_stage_ew.py実装。BlockType enum/registry/__init__.py登録。import+スキーマ検証全PASS |
| cmd_1443 | Ward二段EW weight pipeline修正。weightsが下流に伝わらないバグ5箇所修正+後方互換検証 | dm-signal | 03-27 | PASS。AC1(final_weights)+AC2(is_kalman_meta除去5箇所)+AC3(58FoF×9509行完全一致)。performance fix別途(9d845ad4) |
| cmd_1444 | 旧忍法15体を構成PFとする新Ward FoFを本番DB新規作成+既存123体完全不変証明 | dm-signal | 03-28 | PASS。旧忍法-Ward(0012f956)登録。k=5クラスタ二段EW(0.05/0.0667/0.10)。349s。既存123体差異0 |
| cmd_1446 | Ward FoF日次ETL(sync-fof)動作検証。cmd_1445修正がsync-fofコードパスもカバーしているか確認し、日次ETL後にWard FoFデータが消失しないことを証明する | dm-signal | 03-28 | sync-fofはfullrecalculateと同一コードパス(_recalculate_fof_history in recalculate_fof.py) |
| cmd_1451 | FoF MonthlyReturn生成(本番120.8s/15%)のボトルネック特定偵察。116 Optimization(Shared PriceCache)実装済みなのに120.8s — 何が遅いか | dm-signal | 03-28 | — |
| cmd_1447 | fullrecalculate内部の日次ループ（1日ずつ回す計算）がボトルネック。recalculate_fast.py / recalculate_fof.py のコードを分析し、日次ループしている処理を特定。月次単位にまとめられる処理と、どうしても日次が必要な処理を分類し、高速化の設計材料を作る | dm-signal | 03-28 | recalculate_fast.pyの日次ループを6箇所特定。Phase4のperf_calc(L1497-1621)が最大の月次化候補。累積リターンを毎日計 |
| cmd_1445 | fullrecalculate(portfolio_id=None)でWard FoFのsignals/monthly_returnsが生成されないバグを修正。日次ETL(sync-fof)でも同様の問題が起きる可能性あり | dm-signal | 03-28 | 根因はcommit 9d845ad4(cmd_1443)のis_custom_weight分離不足。d49a9174がis_kalman_metaガードを除去し |
| cmd_1448 | trade_perfの53K DBクエリを除去するOPT-1/2をcommit+push+本番検証。ローカル実証済み: trade_perf 4627s→242s(94.8%削減) | dm-signal | 03-28 | OPT-1/2 commit f3b66500 push成功。本番fullrecalculate 118s完了(旧3324s→96.4%削減)。trade_pe |
| cmd_1450 | FoF日次ループのmomentum_data月中縮小(OPT-A)。本番L3 db_write 144.5sのうち月中冗長データ95%を削除。cmd_1447小太郎偵察で実証済み | dm-signal | 03-28 | recalculate_fof.py momentum_data月中縮小(OPT-A)実装完了。リバランス日のみ完全版、月中は{skipped:True}に最小 |
| cmd_1454 | OPT-A/OPT-6/perf_calc除去の3コミットを本番push+fullrecalculate一括検証。118s(OPT-1/2後)からの追加削減を実測 | dm-signal | 03-28 | 3コミット(OPT-A/OPT-6/perf_calc除去) |
| cmd_1456 | L3 pipeline_exec 626s(Ward scipy)の相関行列キャッシュ実現可能性偵察。fullrecalculate最大残存ボトルネック | dm-signal | 03-28 | Ward FoF=1体(旧忍法-Ward)。pipeline |
| cmd_1449 | Phase 4 perf_calc(L1497-1622)がorphaned codeであることを実証し除去。cmd_1447偵察でprev_perf_cacheがDB/signals未出力と判明。除去でPhase | dm-signal | 03-28 | Phase 4 perf_calc(L1498-1622, |
| cmd_1457 | deploy_task.sh教訓注入のマシュー効果を修正。helpful_count優先ソートがkeyword_score(関連度)を上書きし、有用率13%。ソート優先順序を反転+universal/task-specific枠分離で注入精度を改善 | infra | 03-28 | inject_related_lessonsのソート優先順序 |
| cmd_1460 | — | dm-signal | 03-28 | — |
| cmd_1461 | — | dm-signal | 03-28 | — |
| cmd_1493 | — | infra | 03-29 | deploy_task.sh再配備時AC上書きスキップバグ修 |
| cmd_1494 | — | infra | 03-29 | 3ファイルのgate_fire_log書込み箇所にgate名 |
| cmd_1495 | — | dm-signal | 03-29 | Phase4.5/5 precompute失敗数をstats |
| cmd_1496 | gate_report_autofix.sh強化 — binary_checks str→list自動変換 + lessons_useful MISSING時デフォルト注入 | infra | 03-29 | Fix5 str→list変換+Fix6 MISSING/null→スケルトン生成。テスト12件PASS |
| cmd_1498 | ninja_monitorに家老idle検知追加 — パイプライン空+全忍者idle時にkaro自走サイクル起動 | infra | 03-29 | 家老idle検知→自走サイクル起動の自動化 |
| cmd_1499 | deploy_task.sh改善 — GP-051分割配備対応 + テンプレート欠損防止 | infra | 03-29 | 分割配備+テンプレート欠損防止 |
| cmd_1500 | cmd_save.sh改善 — AC内ファイルパス存在チェック + impl push AC検知 | infra | 03-29 | AC内パス存在チェック+push AC検知 |
| cmd_1502 | gate_cycle_health.sh heartbeatテスト追加 + insight_resolve.shヘルパー作成 | infra | 03-29 | heartbeatテスト+insight解決ヘルパー |
| cmd_1506 | 'L3 daily_loop=67.88s(全体の14%)。trade_perfに次ぐ第2ボトルネック。batch化の余地を特定する偵察' | dm-signal | 03-29 | _recalculate_fof_history(L114- |
| cmd_1505 | ローカルに2件未push(docs L508/509 + precompute integrity check)。加えてcmd_1504のCash修正後に一括push→Render | dm-signal | 03-30 | git push 3コミット→Render deploy l |
| cmd_1510 | 'cmd_1503偵察でwhileループがreturn_calculator.py L319-364(calculate_trade_period_return)と特定。月次リターン複利合成をNumPyプレフィックスプロダクトに置換しtrade_perf 142.78sを削減' | dm-signal | 03-30 | calculate_trade_period_returnの |
| cmd_1511 | 'cmd_1508偵察でSF LOW 17箇所中Group A(ログ追加のみ)5箇所を特定。Group C 12箇所は無害。残る修正対象5箇所にlogger追加' | dm-signal | 03-30 | Group A 5箇所にlogger.warning(exc |
| cmd_1512 | 'GP-116。commit_missing 7件の構造的原因=ashigaru.md Step4→Step5間にgit commit手順未定義。Step 4.6を追加しcommit漏れを構造的に予防' | infra | 03-30 | ashigaru.mdにStep 4.6(git add+c |
| cmd_1513 | 'Stop hookで毎ターン発火するlog_terminal_response.shが418ms。4回のpython3起動(各50-80ms)が主因。1回に統合して累積時間を70%以上削減する' | infra | 03-30 | log_terminal_response.shの5つのpy |
| cmd_1514 | '最も遅いゲート(9.4s)。find+ファイル毎のgrepループがWSL2の/mnt/c I/Oペナルティで遅い。grep -rnの1パス検索に変更しI/O回数を激減させる' | infra | 03-30 | gate_silent_fallback.shをgrep - |
| cmd_1515 | '2番目に遅いゲート(6.0s)。context mdからresearch参照を抽出し各参照のファイル存在確認。find+個別-fチェックのWSL2 I/Oペナルティが主因。既存ファイル一覧を先に取得してメモリ内照合に変更' | infra | 03-30 | gate_vercel_phase.shの個別ファイル存在チ |
| cmd_1516 | '起動ゲート(3.2s)の内部でGate 1(211ms), Gate 12(206ms), Gate 13(1873ms)を逐次実行→並列実行に変更。加えてgate_cycle_health.shのreportファイルループ(stat+grep逐次)をfindバッチに変更' | infra | 03-30 | Gate1/12/13並列化(background+tmpf |
| cmd_1517 | 'deploy_task.sh L1878が task_type="implement"を期待するがtask YAMLは"impl"。この不一致でreview_gate.doneが生成されず、archive_completed.shが報告をスキップ。CLEAR済み182件が滞留中' | infra | 03-30 | deploy_task.shのtask_type比較を'im |
| cmd_1518 | 'lesson_impact.tsv(29K行/2.5MB)にローテーション機構なし。3月だけで29K行に爆発。gate_lesson_health.shのawk全量reverse(259ms)をtail+tac(10ms)に最適化。古いデータはarchive TSVに退避' | infra | 03-30 | AC1: gate_lesson_health.sh awk |
| cmd_1526 | 'WSL2 /mnt/c(NTFS)上のflockが不安定。yaml_field_set.sh/inbox_write.sh/inbox_mark_read.shのlockファイルパスを/tmp/(ext4)に移動し排他制御を安定化' | infra | 03-30 | — |
| cmd_1527 | 'cmd_1144設計のL3未実装。忍者が報告完了→家老が手動でgunshi inboxに通知→軍師レビュー、の手動ステップを自動化。家老のレビュー配備負荷を削減' | infra | 03-30 | — |
| cmd_1528 | '軍師提案GP-113〜GP-126が17件(重複含む)pending。重複除去+要否判定→実行推奨リスト+却下理由を提出し、将軍のcmd起票材料とする' | infra | 03-30 | — |
| cmd_1529 | 'gate_fire初回CLEAR率69.0%=31%がBLOCKで家老rework発生。直近50cmdのBLOCK原因を分析し、忍者教育 or gate改善で初回CLEAR率80%以上を目指す' | infra | 03-30 | — |
| cmd_1530 | 'karo_workarounds.yaml workaround率60%(79/130)。最大category=report_yaml_format(41件)。根因パターン分析→構造的対策3件提案' | infra | 03-30 | — |
| cmd_1531 | '将軍がルール（既存裁定の文字面）で判断し殿に持っていく依存パターンを構造的に解消。原則で判断する力=自立を instructions/shogun.md に明文化' | infra | 03-30 | — |
| cmd_1533 | '報告テンプレート(report_field_set.sh)のコメントにTop5 BLOCK原因パターンの具体的FIX hintを追加。特にlesson_candidate(found:true/false両パターンの記入例)とbinary_checks(yes/no限定)を明示し、report_format BLOCK(32%・最多)を構造的に削減する' | infra | 03-30 | — |
| cmd_1532 | 'cmd_complete_gate.sh L3832のunknown_block_reasonフォールバックを修正。BLOCK_REASONSとMISSING_GATES両方空のelse分岐で各gate個別結果をblock_reasonに含めることで、直近50BLOCKの17.7%(11件)のRCA不能状態を解消する' | infra | 03-30 | — |
| cmd_1534 | 'deploy_task.shのninja_weak_points生成ロジックにgate_metrics.logのBLOCKパターン集計を追加。忍者別の頻出BLOCK原因をtask YAMLに注入し、忍者が自分の弱点を認識した上で作業開始できるようにする' | infra | 03-30 | — |
| cmd_1535 | autofix lessons_useful dict→list変換パターン網羅 | infra | 03-30 | WA率Top1のdict→list 16件を構造変換autofixで根絶。全15テストPASS |
| cmd_1536 | report YAML直接編集hookブロック(RFS使用強制) | infra | 03-30 | 既存hookがAC1-3カバー。偵察不足で重複cmd判明 |
| cmd_1537 | typeフィールドSTALE_FIELDS追加+残留清掃 | infra | 03-30 | _CLEAR_FIELDSにtype追加。修行001発見のtype残留バグ修正 |
| cmd_1538 | karo_workaround_log.shにcategory必須化+gate WARN | infra | 03-30 | uncategorized急増(1→16件)対策。WARN表示で分類品質向上 |
| cmd_1539 | GP-114 Production Branch Coverage Check実装 | infra | 03-30 | cmd_save.shにq7追加。条件分岐変更cmdで本番実データ突合漏れ防止 |
| cmd_1540 | GP-117 fullrecalculate baseline自動保存+差分比較 | infra | 03-30 | fullrecalculate.sh新規作成。変更の正当性を数値証明 |
| cmd_1541 | GP-115 post-deploy verification AC自動提案 | infra | 03-30 | cmd_save.shにWARN追加。デプロイ後検証AC構造的リマインド |
| cmd_1542 | GP-125b karo_workaround_log.shバリデーション強化 | infra | 03-30 | ninja_id検証+root_cause最小長チェック追加。WA計測データ品質向上 |
| cmd_1543 | 本セッション改善効果の計測検証 | infra | 03-30 | CLEAR率62.7%→84.6%(+21.9pt)。unknown_block_reason 9→0件(-100%) |
| cmd_1544 | 今セッション変更の結合テスト一括実行 | infra | 03-30 | 592テスト全PASS。deploy_task.sh並列修正3件の相互作用バグなし |
| cmd_1545 | GP-126c cmd_save.sh内容重複チェック実装 | infra | 03-30 | Check12追加(Jaccard類似度50%超でWARN)。テスト5件PASS |
| cmd_1546 | 本セッション全改善commitのpush+CI green確認 | infra | 03-30 | CI GREEN(全5ジョブPASS)。本セッション20+commitの一括検証 |
| cmd_1547 | context/infrastructure.md 本セッション改善の索引還流 | infra | 03-30 | cmd_1532-1543改善セクション追加。CLEAR率84.6%更新 |
| cmd_1548 | gate_metrics.logローテーション実装 | infra | 03-30 | 1000行超で自動アーカイブ実装。ログ無制限成長防止 |
| cmd_1549 | GP実装済みステータス更新 | infra | 03-30 | cmd_1528トリアージ結果+本セッション実装GP還流 |
| cmd_1550 | batsテスト構造マップ作成 | infra | 03-30 | 58bats/593テスト+未テスト131スクリプト分類。カバレッジ盲点可視化 |
| cmd_1560 | shogun_to_karo.yamlが1937行に肥大化。旧セッションcmd(cmd_1082-1524)をqueue/archive/cmds/に個別YAML退避し、本体をcmd_1525以降のみに軽量化 | infra | 03-30 | shogun_to_karo.yamlからcmd_1525よ |
| cmd_1561 | 'なぜ分析(殿指摘): shogun_to_karo.yamlが肥大化する根因=cmd完了時にstatusがdelegatedのまま更新されない→archive_completed.shが退避できない。cmd_complete_gate.sh | infra | 03-30 | GATE CLEAR時にSTK statusをdoneに更新 |
| cmd_training_structural_001 | 自身のtask YAMLを精査し、deploy_task.shの配備フローで設定されるフィールドと残留しうるフィールドを全列挙。構造的な問題があれば報告 | infra | 03-30 | STALE_FIELDS(21)とinject_task_m |
| cmd_training_structural_002 | inject_task_modifiers.pyの全フィールド注入ロジックを精査。存在チェック(not in task/is None)パターンを全列挙し、stale | infra | 03-30 | inject_task_modifiers.pyの全7関数を |
| cmd_training_structural_003 | archive_completed.shのsweep modeにおけるreport保護条件(status/archive.done/review_gate.done)を全列���し、レースコンディションが残っていないか検証 | infra | 03-30 | archive_completed.sh sweep mod |
| cmd_training_structural_004 | cmd_complete_gate.shのGATEチェック全項目を列挙し、GATE CLEAR後のアーカイブ・教訓同期フローの構造的問題がないか検証 | infra | 03-30 | cmd_complete_gate.sh(3937行)の全G |
| cmd_training_structural_005 | yaml_field_set.shの内部ロジック(AWK flush_block)を���査し、リスト型・ネスト型フィールドの処理制約を全列挙。flock | infra | 03-30 | flush_block(AWK)はスカラー値・空値・コロン含 |
| cmd_1525 | 教訓301件中272件(90.4%)がuseful:true 0回。注入はされているが活用されない構造問題。根因を特定し改善アクションを設計する | infra | 03-30 | 直近30cmd(1527-1561)の報告YAML202件を |
| cmd_1562 | 現在771テスト(root:80 + unit:673 + e2e:18)がCI毎回実行。殿指摘「必要性のないテストは負債」。3基準(リグレッション実績/変更頻度/コスト見合い)で全テストを仕分け、削除候補を特定する | infra | 03-30 | 全77テスト監査完了。削除候補(非本番フロー+変更頻度ゼロ) |
| cmd_1564 | cmd_1525偵察の改善提案3。活用率15%未満の教訓の注入スコアを半減させ、死蔵教訓が永久に枠を占拠する問題を解消する | infra | 03-30 | deploy_task.shの教訓注入スコアにuseful_ |
| cmd_1563 | cmd_1525偵察で判明した教訓注入useful:false 76.6%の根因（タグ粒度不足+ファイルレベルマッチング欠如）を解消し、教訓活用率を6.2%から大幅改善する | infra | 03-30 | AC1: infra lessons.yamlの全20件un |
| cmd_1565 | cmd_1562偵察で発見された重複テスト3組(gate_cycle_health/inbox_write/yaml_field_set)をtests/unit/に統合し、CI setup/teardownオーバーヘッドを削減する | infra | 03-30 | 重複テスト3組(gate_cycle_health/inbo |
| cmd_training_comprehensive_004 | model_switch_preflight.shを精査し改善点3つ特定→1つ実装→lesson_candidate付き完全報告。L4=L1-L3全スキル同時要求の総合演習 | infra | 03-30 | model_switch_preflight.shを精査し改 |
| cmd_training_comprehensive_003 | restart_watchers.shを精査し改善点3つ特定→1つ実装→lesson_candidate付き完全報告。L4=L1-L3全スキル同時要求の総合演習 | infra | 03-30 | restart_watchers.shを精査し改善点3つ特定 |
| cmd_training_comprehensive_002 | dashboard_auto_section.shを精査し改善点3つ特定→1つ実装→lesson_candidate付き完全報告。L4=L1-L3全スキル同時要求の総合演習 | infra | 03-30 | dashboard_auto_section.shを精査し改 |
| cmd_training_comprehensive_001 | reset_layout.shを精査し改善点3つ特定→1つ実装→lesson_candidate付き完全報告。L4=L1-L3全スキル同時要求の総合演習 | infra | 03-30 | reset_layout.sh Step 7サマリループを最 |
| cmd_training_comprehensive_006 | restart_watchers.shを精査し改善点3つ特定→1つ実装→lesson_candidate付き完全報告。L4=L1-L3全スキル同時要求の総合演習。003とは異なる観点で改善点を発見すること | infra | 03-30 | restart_watchers.shを精査し改善点3つ特定 |
| cmd_training_comprehensive_005 | dashboard_auto_section.shを精査し改善点3つ特定→1つ実装→lesson_candidate付き完全報告。L4=L1-L3全スキル同時要求の総合演習。002とは異なる観点で改善点を発見すること | infra | 03-30 | dashboard_auto_section.shを精査し改 |
| cmd_1566 | admin画面のFoF managementでWard PFの内部ウェイト(クラスタリング結果・各構成PFへのウェイト配分)が可視化されておらず、FoF構築時にブラックボックスになっている。現状のadmin画面表示内容と、可視化に必要なデータフローを特定する | dm-signal | 03-30 | FoF管理画面(admin/fof)は構成PF名・数・パイプ |
| cmd_1567 | シミュレーション(ローカルexperiments.db/fullrecalculate)のパフォーマンス結果と本番DB(Render PostgreSQL)のパフォーマンス結果が乖離している。乖離の原因を特定する | dm-signal | 03-30 | Ward FoF本番vsローカル乖離の根因=experime |
| cmd_1569 | WardFoFのpipeline_configが本番DBとローカル(fullrecalculate時)で同一か検証。configの差異がパフォーマンス乖離の原因となりうる | dm-signal | 03-30 | Ward FoF pipeline_config本番DB v |
| cmd_1568 | 'Ward PFのウェイトがmomentum_data["weights"]経由でexpand_portfolio_to_tickersに正しく伝達されているか検証。price_ratio_calculator.py:1067-1070のEWフォールバックが本番で意図せず発動している可能性がある(Silent Failure仮説)' | dm-signal | 03-30 | Ward PFのウェイト伝達パスにSilent Failur |
| cmd_1570 | 殿がWard FoFのパフォーマンスを「記憶よりショボい」と報告。Ward Two-Stage EW(k=5)の構造的制約、素材(旧忍法15体)の性能、k値の最適性を検証し、パフォーマンス低下の因果を特定する | dm-signal | 03-30 | Ward FoF(旧忍法-Ward)の12ヶ月パフォーマンス |
| cmd_1571 | 'cmd_1568偵察で発見。recalculate_fof.py:866で非リバランス日のenhanced_momentum_dataが{skipped:true}のみとなり、weightsキーが消失する。bimonthly/quarterly Ward/KalmanMeta FoFでexpand_portfolio_to_tickersのEWフォールバック(price_ratio_calculator.py:1067-1070)が意図せず発動する時限爆弾。現在の月次Wardは影響なしだが予防的に修正' | dm-signal | 03-30 | 非リバランス日のenhanced_momentum_data |
| cmd_1572 | cmd_1567偵察で発見。experiments.dbにWard FoF自体(0件)、四つ目3PF(常勝/激攻/鉄壁)、ティッカー4種が欠損。download_prod_data.pyの対象スコープを拡張し再DLでデータ完全性を確保する | dm-signal | 03-30 | download_prod_data.pyのdownload |
| cmd_1577 | cmd_1570は12ヶ月累積リターンのみ比較(Ward+54.93%,EW+54.69%,差+0.25%)。リスク調整後指標で比較すればWardの分散効果が見える可能性がある(R24-R26ではMaxDD優位率86-96%)。本番141ヶ月全期間でSharpe/MaxDD/Sortino/月次Volatilityを計算 | dm-signal | 03-30 | Ward FoFは1/N EWに対しリスク調整後指標で非優位 |
| cmd_1579 | 殿の新設計。現行Ward FoFは全15体保有(ウェイト調整のみ)で動的ローテーションがゼロ。Ward clusteringの役割をウェイト決定からselection scope定義に変更する。K個のクラスタに分割→各クラスタ内momentum top 1体を選出→K体EW保有→毎月リバランス。building_block.pyの既存Ward+EWロジックを改変し、旧忍法15体でバックテスト | dm-signal | 03-30 | Ward Cluster Selection(K=3,4,5 |
| cmd_1581 | cmd_1579は旧忍法15体。シン忍法v2(20体)は相関構造が異なり(cmd_1578:距離26%狭,separability11%悪化)、Wardクラスタが動的(ARI安定性45.5%)。異なる素材プールでWard Cluster Selectionの頑健性を検証。シンのトップ(96.5%)は旧の倍以上で超越条件を満たしやすい可能性 | dm-signal | 03-30 | シンWard Cluster Selection(K=3)は |
| cmd_1580 | cmd_1579のバックテスト結果が良くても過適合の可能性がある。Walk-Forward OOS(in-sample 60ヶ月→OOS 12ヶ月ローリング)で検証し、OOS期間でもselection ruleの予測力が維持されるか確認する。殿指示「やってみて過適合ではないか検証する」 | dm-signal | 03-30 | Walk-Forward OOS(IS=60m,OOS=12 |
| cmd_1584 | 殿はN=2-5が現実的と指定。cmd_1579はK=3,4,5をカバー。K=2(2クラスタ→各top1→2体EW)は最小保有数で管理最容易だが集中リスク最大。K=2の特性を独立検証し超越条件を満たすか判定する | dm-signal | 03-30 | 旧忍法15体K=2: CAGR=61.3%,Sharpe=1 |
| cmd_1582 | cmd_1579はmomentum(12ヶ月累積リターン)で各クラスタtop1を選出。しかしmomentumが最適な選択指標とは限らない。Sharpe/Calmar/Sortinoなど他のリスク調整指標で選出した場合の結果を比較し、R28の最適な選択指標を特定する | dm-signal | 03-30 | Ward Cluster Selection 4指標×K=3 |
| cmd_1583 | R28のWard Cluster Selectionはmomentum(過去リターン)で次月の保有PFを選出する。もし旧忍法のリターンに平均回帰(mean reversion)が働くなら、momentum strategyは逆効果になる。R28の理論的前提(momentum持続性)を統計的に検証する | dm-signal | 03-30 | 旧忍法15体のmomentum持続性を3観点で検証。AC1: |
| cmd_1585 | cmd_1581でシンWard ClSel K=3がCalmar4.60/UWP3mで超越条件B+C PASSという重大成果。しかしfull-sample結果のみで過適合未検証。cmd_1580(旧忍法OOS)と同じWalk-Forwardフレームワークでシン素材のOOS検証を実施し、超越条件が過適合でないことを確認する | dm-signal | 03-30 | ShinWardClSel WF-OOS(IS=60m,OO |
| cmd_1586 | cmd_1581でシンClSel K=3がmomentumでCAGR74.6%。cmd_1582は旧忍法で指標感度分析するが、超越条件PASSしたシン素材での指標感度がより重要。Sharpe/Calmar/Sortinoで選出した場合にCalmar4.60/UWP3mを超える組み合わせがあるか検証 | dm-signal | 03-30 | シンWard ClSel K=3,4,5 x 4指標(mom |
| cmd_1588 | シンClSel K=3のMaxDD -16.2%は全体統計。実運用では市場暴落時にどう振る舞うかが重要。下落期での月次リターンを個別分析し、ストレス時の耐性を評価する | dm-signal | 03-30 | シンClSel K=3のストレス耐性分析完了。市場下落月(E |
| cmd_1587 | シンClSel K=3は月次ローテーションだが、実際にどの程度入替が発生するか未知。毎月3体入替なら取引コスト大、同一PF連続選出が多ければ低コスト。本番採用判断に取引コスト/安定性の情報が必須 | dm-signal | 03-30 | Ward ClSel K=3(LB=36m,momentum |
| cmd_1589 | R28研究シリーズ(cmd_1579-1588)の全結果を1つの統合比較表+推奨にまとめる。殿が本番採用の意思決定を1ファイルで行えるようにする | dm-signal | 03-30 | R28研究シリーズ(cmd_1579-1588)全10報告統 |
| cmd_1591 | 殿指摘。R28の全分析はraw returnでありベータ未制御。momentum選出は高ベータPFを構造的に掴むバイアスがある。CAGR向上がアルファ(選別の巧さ)なのかベータ(市場露出)なのかを分離し、ClSelの真の付加価値を定量化する | dm-signal | 03-30 | ClSel K=3(momentum)のCAGR向上はほぼ全 |
| cmd_1590 | cmd_1586でSortino K=3がCalmar5.29/MaxDD-14.2%と全指標最良。cmd_1585ではmomentum K=3のCalmar劣化41.6%(MaxDD-16.2→-25.7)で過適合フラグ。SortinoのMaxDDが元々良好(-14.2%)ならOOS劣化幅が小さい可能性。Sortino選出のOOS信頼性を検証する | dm-signal | 03-30 | Sortino選出Ward ClSel WF-OOS(IS= |
| cmd_1592 | 殿指摘。超越条件はfull-sampleでのみ判定しておりOOS期間での判定が未実施。OOS同士で比較しなければ公正ではない。OOS期間で個体ベストを再計算し超越条件を判定する | dm-signal | 03-30 | OOS期間(2018-10~2026-03)個体ベスト再計算 |
| cmd_1593 | 殿指摘。IS=60ヶ月は保守的すぎる可能性。IS長を変えるとOOS結合期間・窓数・結論が変わるか検証する。IS=36(LB=36mちょうど)/48(LB36+momentum12)/60(現行)の3水準でOOS結果を比較し、IS長への結論の頑健性を確認する | dm-signal | 03-30 | シン忍法v2 20体のWard ClSel K=3(mome |
| cmd_1596 | cmd_1591でmomentumのα寄与4.2%と判明。しかし他3指標(Sortino/Sharpe/Calmar)のβ調整後パフォーマンスは未検証。4指標全てのβ調整後比較テーブルを作成し、真にα効率が高い選出指標を特定する。β露出に頼らない方式の有無を確認 | dm-signal | 03-30 | 4指標(momentum/Sharpe/Calmar/Sor |
| cmd_1595 | cmd_1591でmomentum選出のα寄与が4.2%と判明(95.8%はβ)。Sortino選出のβプロファイルが異なるか検証する。またcmd_1592がSortino OOS超越条件未完(FAIL)だったが、cmd_1590完了により補完可能。2つの残課題を1cmdで解決 | dm-signal | 03-30 | Sortino選出βプロファイルはmomentumと構造的に |
| cmd_1594 | 殿指摘。cmd_1583は3/6/12ヶ月の3点しか検証しておらず、過去データで有効とされた4-5ヶ月・10-11ヶ月の隙間期間が未検証。1-12ヶ月の全12水準でクロスセクショナル持続性(hit rate + t検定)を算出し、最適lookback期間を特定する。標準LB(3/6/12)が最適とは限らない | dm-signal | 03-30 | 旧忍法15体+シン忍法v2 20体のクロスセクショナルmom |
| cmd_1597 | cmd_1589統合レポートで3条件(超越PASS+OOS劣化<30%+Turnover)全PASSはシンClSel K=4 momentum唯一。しかしcmd_1591のβ分離はK=3のみでα4.2%。K=4でもβ主導なら、R28で本番採用に値する方式はゼロとなる。3条件唯一PASSの方式の真の付加価値を最終検証 | dm-signal | 03-30 | K=2-5全水準でβ調整後超越条件全FAIL(16判定全FA |
| cmd_1599 | cmd_1594でLB=2mが最適momentum持続性と判明(t=4.04)。しかし全ClSelバックテスト(cmd_1581等)はLB=12mで実行。LB短縮で(a)momentum予測力向上→CAGR改善(b)高β | dm-signal | 03-30 | LB=2mはLB=12m対比で全K(3,4,5)でCAGR/ |
| cmd_1600 | cmd_1599でLB=2mのfull-sample結果を取得後、OOSで過適合検証が必要。LB=12m(cmd_1585)ではCalmar劣化41.6%でOVERFIT。LB=2mは持続性が強い(t=4.04)ためOOS劣化が小さい可能性。LB変更がOOS安定性を改善するか検証 | dm-signal | 03-30 | LB=2m WF-OOS(IS=60m,OOS=12m,st |
| cmd_1601 | cmd_1600でLB=2m momentumのOOS劣化が-23.5%(改善方向)と判明。cmd_1595でSortinoがα最高効率(10%)と判明。最も有望な組み合わせ=Sortino×LB=2mは未検証。ただしSortinoは下方偏差計算に十分なデータが必要→LB=2mでSortino ratioが安定するか含め検証 | dm-signal | 03-30 | Sortino LB=2mはLB=12m対比で全K全指標劣後 |
| cmd_1604 | > | dm-signal | 03-30 | 20体全個体WF-OOS(8窓,90m)+buy&holdベ |
| cmd_1605 | > | dm-signal | 03-30 | 20体個体WF-OOS(IS=60m,OOS=12m,ste |
| cmd_1606 | > | dm-signal | 03-30 | シン忍法v2 LB×4指標 2DグリッドClSel WF-O |
| cmd_1608 | > | dm-signal | 03-30 | r29g_shin_clsel_2d_grid_extra. |
| cmd_1612 | R29研究成果のcontext索引更新（R29f-kyu/R29g-shin/R29g-kyu/R30-shin/cmd_1610の結論還流） | dm-signal | 03-31 | R29g-shin(cmd_1608)+R29g-kyu(c |
| cmd_1611 | 旧忍法15体の個体WF-OOSベンチマーク（R30-kyu: cmd_1604と同一手法で旧版比較データ作成） | dm-signal | 03-31 | 旧忍法15体個体WF-OOS(7窓84m)完了。全15体CA |
| cmd_1613 | ClSel本番化偵察: 研究スクリプト→本番パイプライン移行に必要な変更箇所の特定 | dm-signal | 03-31 | ClSel(Cluster Selection)ロジック偵察 |
| cmd_1610 | FoF管理画面にビルディングブロック可視化を実装（コンポーネントPF×ウェイト表示+Wardクラスタ表示） | dm-signal | 03-31 | — |
| cmd_1615 | — | infra | 03-31 | inbox_write.sh内のyaml.dump2箇所(L |
| cmd_1617 | > | infra | 03-31 | cmd_save.sh Check12のcheck_cont |
| cmd_1619 | > | infra | 03-31 | deploy_task.shのinject_ac_versi |
| cmd_1620 | 'gate_loop_health.shのWARNINGメッセージ「FAIL発生中だがAUTO-FIX未稼働。auto-fix対象拡大を検討せよ」が | infra | 03-31 | gate_loop_health.shのLoop Statu |
| cmd_1621 | スキル棚卸し: writer系名称統一+memory-teire廃止 | infra | 03-31 | MEMORY.md L109のスキル参照名をweekly-r |
| cmd_1622 | L3 FoF Per-FoF Signal query除去(signal_cache直接参照化) | dm-signal | 03-31 | — |
| cmd_1623 | ClSel研究: MP denoising + OPTICS密度ベースクラスタリング | dm-signal | 03-31 | building_block.pyにdenoise_corr |
| cmd_1624 | 知識辞書拡充: Gerber Statistic + Shrinkage Estimators | dm-signal | 03-31 | M14 Gerber Statistic (237行) + |
| cmd_1625 | 知識辞書拡充: OPTICS Clustering + 共分散前処理DM-Signal解釈 | dm-signal | 03-31 | — |
| cmd_1626 | 軍師review_log 3分離: stats/gp_tracker/log本体 | infra | 03-31 | — |
| cmd_1627 | 偵察: standard PF前処理適用ポイント特定(AbsoluteMomentum+加速BB実装精読) | dm-signal | 03-31 | 3ブロック(MomentumFilter/AbsoluteM |
| cmd_1628 | 研究: standard PF Gerber閾値フィルタ効果検証 | dm-signal | 03-31 | — |
| cmd_1629 | 研究: standard PF リターン平滑化(EMA)効果検証 | dm-signal | 03-31 | — |
| cmd_1630 | 研究: standard PF Ledoit-Wolf shrinkage効果検証 | dm-signal | 03-31 | — |
| cmd_1631 | 研究: standard PF Fractional Differentiation効果検証 | dm-signal | 03-31 | — |
| cmd_1632 | 研究: standard PF EMA平滑化 65PF拡張再実行 | dm-signal | 03-31 | ema_smoothing_study.pyを65PF対応に |
| cmd_1633 | 研究: standard PF L1 Trend Filter 65PF検証 | dm-signal | 03-31 | L1 Trend Filter 65PF study完了。c |
| cmd_1634 | 研究: standard PF Kalman Filter 65PF検証 | dm-signal | 03-31 | Kalman Filter study完了。65PF×4mo |
| cmd_1635 | 研究: standard PF Entropy Gate (Permutation Entropy) 65PF検証 | dm-signal | 03-31 | PE gate study完了。m=5, window=[1 |

## 2026-04

| cmd | title | project | date | key_result |
|-----|-------|---------|------|------------|
| cmd_1636 | 知識辞書: 平滑化・信号抽出系4手法(M17-M20/M33) | dm-signal | 04-01 | — |
| cmd_1637 | 知識辞書: エントロピー・ノイズ検出系4手法(M19/M21/M22/M23) | dm-signal | 04-01 | — |
| cmd_1638 | 知識辞書: 分解・フィルタ系4手法(M24/M25/M28/M30) | dm-signal | 04-01 | methods/に4ファイル(ssa.md,vmd.md,s |
| cmd_1639 | 知識辞書: リスク・PF関連4手法(M26/M27/M29/M34) | dm-signal | 04-01 | methods/にM17-M20の4ファイル(stochas |
| cmd_1640 | 知識辞書: 適応的・レジーム系4手法(M31/M32/M35/M36) | dm-signal | 04-01 | methods/に4ファイル(dynamic-momentu |
| cmd_1641 | 知識辞書: メタ知見sources/validation 5件(S02-S05/V04) | dm-signal | 04-01 | sources/4件(S02-S05: Valeyre ch |
| cmd_1642 | 知識辞書: モメンタム正典3件(TSMOM/CS-Mom/Dual Mom) | dm-signal | 04-01 | — |
| cmd_1643 | 知識辞書: モメンタムリスク+レジーム3件(Crash/LifeCycle/RegimeSw) | dm-signal | 04-01 | — |
| cmd_1644 | 知識辞書: PF構築正典A 3件(MVO/Ward/RiskParity) | dm-signal | 04-01 | — |
| cmd_1645 | 知識辞書: PF構築正典B 3件(BL/MaxDiv/Kelly) | dm-signal | 04-01 | — |
| cmd_1646 | 知識辞書: ボラティリティ・リスク基盤3件(GARCH/CVaR/EWMA) | dm-signal | 04-01 | — |
| cmd_1647 | 知識辞書: 統計・ML基盤3件(Bootstrap/FeatImp/SeqBoot) | dm-signal | 04-01 | — |
| cmd_1648 | 知識辞書: モメンタムリスク+レジーム3件(M40 Crash/M41 LifeCycle/M54 RegimeSw) — cmd_1643穴埋め | dm-signal | 04-01 | methods/に3ファイル(momentum-crashe |
| cmd_1649 | 知識辞書: 資産価格モデルA 3件(M55 CAPM/M56 FF3/M57 Carhart) | dm-signal | 04-01 | methods/に資産価格モデル3ファイル(capm.md, |
| cmd_1650 | 知識辞書: 資産価格モデルB+時系列基盤(M58 FF5/M59 APT/M60 ARIMA) | dm-signal | 04-01 | methods/に3ファイル(fama-french-5-f |
| cmd_1651 | 知識辞書: 診断的統計検定A 3件(V05 ADF/V06 KPSS/V07 Ljung-Box) | dm-signal | 04-01 | validation/に診断的統計検定3ファイル(adf-u |
| cmd_1652 | 知識辞書: 診断検定B+因果検定(V08 JB/M61 Granger/M62 Cointegration) | dm-signal | 04-01 | validation/jarque-bera.md, met |
| cmd_1653 | 知識辞書: 時系列+マイクロストラクチャー3件(M63 VAR/M64 Amihud/M65 VPIN) | dm-signal | 04-01 | methods/に3ファイル(var.md, amihud- |
| cmd_1655 | cmd_1654リグレッション修正 — FoFのuse_raw_signal伝播がsignalテーブル不在で破綻 | dm-signal | 04-01 | fullrecalculate完了(375s)。旧忍法15F |
| cmd_1654 | pending月の保有シグナル表示がstale — signal(新)からexpanded_tickers/holding_signal表示を構築 | dm-signal | 04-01 | pending月のexpanded_tickersがhold |
| cmd_1657 | CI RED修正 — Unit Tests (bats) FAIL (run 23832408726) | infra | 04-01 | — |
| cmd_1658 | ClSel研究: 共分散前処理4条件比較 (raw/MP/Gerber GS1/Ledoit-Wolf) × Ward K=3 | dm-signal | 04-01 | — |
| cmd_1659 | 研究日誌をリポジトリに配置 + context参照修正 | dm-signal | 04-01 | Gist aa7d9a9fの内容をdocs/research |
| cmd_1662 | deploy_task.shに配備前cmd_id衝突チェック追加(GP-132) | infra | 04-01 | 二重配備検出ロジックはdeploy_task.sh L297 |
| cmd_1663 | gate_report_format.shにverdict-BC矛盾検出追加(GP-132/LG005) | infra | 04-01 | GP-163: gate_report_format.shに |
| cmd_1661 | Hook最適化 — 毎ツールコールオーバーヘッド半減(修行兼務) | infra | 04-01 | hook処理時間93%削減。python3→bash+jq変 |
| cmd_1656 | deploy_task.sh AWK id:パターン修正 — 手書きYAML形式対応(explicit check抽出 + scout_gate) | infra | 04-01 | deploy_task.sh 2箇所修正完了: (1)AC1 |
| cmd_1667 | inbox_watcher BUSY判定タイムアウト追加 — idle_flag遅延によるnudgeフリーズ修正 | infra | 04-01 | inbox_watcher BUSY判定に@last_act |
| cmd_1666 | 研究: Standard PF FDA Smoothing 5PFリトマス紙検証 | dm-signal | 04-01 | fda_smoothing_study.py実装。5PF×1 |
| cmd_1670 | CI RED修正 — test_cmd_save_ac_paths.bats 3テストFAIL (CMD_BLOCK_NC未設定) | infra | 04-01 | test_cmd_save_ac_paths.batsのラッ |
| cmd_1671 | ninja_monitor.sh 2バグ修正 — pstree永久BUSY化 + pipeline空idle通知スキップ | infra | 04-02 | ninja_monitor.sh 2バグ修正完了。AC1: |
| cmd_1672 | deploy_task.sh direct mode追加 — 修行タスク配備パイプライン正常化(GP-138) | infra | 04-02 | deploy_task.shに--direct mode追加 |
| cmd_1673 | 編成切替スキル /hensei 構築 — 稼働中モデル混成切替+Opus全戻し | infra | 04-02 | get_agent_model()にclaude-sonne |
| cmd_1676 | gate_report_format.sh stale_reportチェック修正 — task_id/cmd_idサフィックス不一致(PD-005) | infra | 04-02 | gate_report_format.sh L367のsta |
| cmd_1678 | commit 353f59eでscripts/api_usage.shの出力形式が変更されたが、 tests/unit/test_api_usage.batsのテスト12-13のアサーションが旧形式のまま。 9時間以上CI REDが継続中。テストを現行スクリプト出力に合わせて修正する。 | infra | 04-03 | test_api_usage.batsテスト12-13を修正 |
| cmd_1680 | 月初にリバランスが確定しているにもかかわらず、Dashboard上で最大24時間「Pending」+生signal表示が続くバグを修正。 ユーザーから4/1 23:00と4/2 13:00でシグナルが異なるとの報告あり。 根因: holding_signalの確定が「当月の市場データ到着→signal行作成」に依存。 4月の保有は3月31日のパイプライン出力で既に決定済みだが、4月1日のsignal行がないとPendingになる。 | dm-signal | 04-03 | Phase 4.1月初signal行自動作成ロジックを実装。 |
| cmd_1681 | DM6(lookback=15D)は全前処理手法で劣化した(研究日誌Phase 8)。 殿の洞察: lookbackを中期に変更すればDNAが全く変わる別物として前処理が効く領域に入る。 DM3(126D)でEMA+112%/L1+383%の改善が出た中期域でDM6構成を検証する。 | dm-signal | 04-03 | DM6構成6仮想PF×4条件=24件のwalkforward |
| cmd_1682 | Phase 14でFDA 5PF実験を実施。DM3 +232%(K=32)と最大改善報告だがMatch率低下(49.5%)。 5PFは一般化に不十分(Phase 4でEMAも同じ指摘を殿から受けた)。 65PF全数に拡張してFDAのパフォーマンス特性の全体像を把握する。 OOS検証は後(殿指示)。まずパフォーマンスが良いものを探す。 | dm-signal | 04-03 | FDA smoothing study chunk2(PF |
| cmd_1683 | 研究日誌Phase 5で三層構造を認識。各レイヤーにmomentum計算があり前処理の余地がある。 第一層(L0)研究は7手法完了。第二層(L1: FoF)の前処理研究を開始する。 間接波及(L0前処理の伝播)と直接適用(L1前処理)の両方を定量化する。 | dm-signal | 04-03 | FoF第二層前処理研究スクリプトを追加し、6 FoF×3条件 |
| cmd_1684 | 殿指示: DM6.5のlookbackは1M~12Mまで全部やれ。4M/5M/10M/1M等に予想外のパフォーマンスがありうる。 DM6構成で1M~12Mの全12 lookbackを網羅的に探索し、パフォーマンス地図を描く。 | dm-signal | 04-03 | 9 lookback×2 rebalance×4条件=72 |
| cmd_1685 | cmd_1681事故: ACに「前処理4条件」とだけ書き具体値未記載→忍者が独自判断でKalman_autoを使用→条件不一致。 ACに「N条件」「Nパターン」等の数量指定があるのにcommand欄にしか具体値がない場合、 忍者がACだけで全パラメータを一意に特定できない。これを機械的に検出してWARNする。 | infra | 04-03 | cmd_save.sh Check 13(ACパラメータ充足 |
| cmd_1688 | cmd_1686がdelegated_at付与済みなのに家老が14分間配備を忘れた事故。 単一検出ポイントでは穴がある(cmd_delegate.sh=次cmd依存、gate=起動時のみ)。 二重防御: (1)cmd_delegate.shで委任時即検出 (2)ninja_monitorで常時監視。 | infra | 04-03 | cmd_delegate.shにStep 2.4(未配備cm |
| cmd_1686 | cmd_1682のFDA 65PF結果でK=32が最大改善(+258%)だがMatch率40-50%。 Match率が低い=シグナルが大きく変わる=本番投入リスク大。 K=4/8の低K領域でMatch率70%+を維持しつつ改善が出る設定を特定する。 | dm-signal | 04-03 | 65PF×16設定(K={4,8,16,32}×λ={0,1 |
| cmd_1687 | 第二層研究(cmd_1683)で間接波及が有効(朱雀+11%,玄武+3%,青龍+2%)。 最終出力PF(Ave-X/裏Ave-X)への伝播効果を定量化し、 EMA span=5(universal best, OOS ROBUST)の本番投入時のユーザー体験改善幅を確認する。 | dm-signal | 04-03 | Layer 3研究完了。Ave-X/裏Ave-X × 2条件 |
| cmd_1689 | Phase 3サーベイで発見した未実施手法。EMA/L1(入力平滑化)と直交するアプローチ。 統計的に異常なジャンプ(1日の大変動)のみを除去し、ノイズとシグナルを精密に分離する。 Winsorization(Phase 1で殿却下)の精密版: テール全体をキャップするのではなく、 統計的にジャンプと判定されたイベントだけ除去。crash情報は保持。 | dm-signal | 04-03 | — |
| cmd_1690 | Phase 3サーベイで発見した未実施手法。EMA/L1(時間軸平滑化)ともFDA(関数変換)とも直交。 SSAはSVDベースで価格系列を「トレ��ド+ノイズ+季節性」に分解し、トレンド成分のみ抽出。 非パラメトリック(分布仮定なし)。Deloitte研究でSharpe 1.88報告。 | dm-signal | 04-03 | — |
| cmd_1691 | 研究スクリプト13本が同一のsimulate_signals/calculate_metricsをコピペしている。 軍師分析: 共通エンジン化で全スクリプト同時高速化+保守コスト削減。 今後のJump Detection/SSA等の研究cmdは全てこのエンジンを使う。 道具を先に作り、研究の生産性を構造的に上げる。 | dm-signal | 04-03 | research_engine.py(14関数+simula |
| cmd_1692 | 今日5回の急がば回れ違反。全てcmdのACが前提としている事実をq5で確認していない。 q5=code_readingだけで通るのが根因。段階的では遅い。BLOCKにする。 | infra | 04-03 | cmd_save.shのq5=code_readingのみを |
| cmd_1693 | cmd_1688はcmd_delegate.sh(委任時検出)のみ実装。殿指摘「次のcmdを出さなければ検出されない」穴が残存。 ninja_monitor(常時監視)に未配備cmd検出を追加し、イベント非依存の検出層を構築する。 cmd_delegate.sh(委任時即検出) + ninja_monitor(常時10分監視)の二重防御を完成させる。 | infra | 04-03 | ninja_monitor.shにpending+deleg |
| cmd_1694 | 将軍がcmd_save.sh(保存確認)を実行せずにcmd_delegate.sh(委任)を実行する手順ミスが発生。 /clear後に手順を忘れる構造的問題。cmd_delegate.shの冒頭でcmd_save.shを自動実行し、 BLOCKなら委任中止、PASSなら続行。手順を覚える必要をなくす。 | infra | 04-03 | cmd_delegate.shに初回委任時のcmd_save |
| cmd_1696 | 影丸(Sonnet 4.6)の@model_nameが「Opus」と誤表示。根因: model_detect.shのバナー検出パターンが (Opus|Haiku)のみでSonnetが欠落。Sonnetバナーがマッチせずキャッシュの古い値が返される。 加えて、陣形図(karo_snapshot.txt)にモデル情報列がなく、編成状態が不可視。 | infra | 04-03 | model_detect.shにSonnet検出パターン追加 |
| cmd_1697 | cmd_save.sh L152-153のgrep "scope_mode:"/"scout_exempt:"がcmdブロック内にマッチしない場合、 set -eで即exit 1。|| trueがないのが原因。cmd_1696でscout_exemptなし初回BLOCK発生の根因。 | infra | 04-03 | cmd_save.sh L152-153のgrep scop |
| cmd_1698 | Phase 3サーベイで発見した未実施手法。EMA(入力平滑化)と直交するテール処理アプローチ。 統計的に異常なジャンプのみ除去し、ノイズとシグナルを精密に分離する。 research_engine.py(高速化済み: 65PF×1条件=4s)のpreprocessing_fn引数で実装。 | dm-signal | 04-03 | AC1-3全完了。research_engine.pyにma |
| cmd_1699 | Phase 3サーベイで発見した未実施手法。EMA/L1(時間軸平滑化)ともFDA(関数変換)とも直交。 SVDベースで価格系列を「トレンド+ノイズ」に分解しトレンド成分のみ抽出。非パラメトリック。 research_engine.py(高速化済み)のpreprocessing_fn引数で実装。 | dm-signal | 04-03 | SSA前処理をresearch_engine.pyのprep |
| cmd_1700 | 本番DB確認: FoF 59体、全てEqualWeight(selection block=0)。 cmd_1687ではAve-X/裏Ave-Xの2体のみ検証(+2.2pp/+1.3pp)。残り57体が未検証。 全59体でEMA span=5間接波及(L0前処理のL1/L2伝播)の効果を測定し、 前処理の恩恵がFoF全体でどう分布するかのパフォーマンス地図を描く。 | dm-signal | 04-03 | 全59 FoF × 2条件 = 118 walkforwar |
| cmd_1701 | cmd_1700で59 FoF中49体(83%)がEMA span=5間接波及で悪化。 殿の洞察: Standard PFは材料。尖っているほどFoF材料として価値が高い。 EMAは「ノイズ+独自性」を区別せず両方削る。尖り削減=FoF分散効果減少。 EMA前後のシグナル相関変化を定量化し、どのPFの尖りが削られたか特定する。 | dm-signal | 04-03 | 65 PF×2条件(baseline/EMA_span5)の |
| cmd_1703 | cmd_1702がHigh=「rolling CAGR > 全期間CAGR」の二値分類で実装した。 本番定義はHigh=rolling CAGR系列のMax値(generators/rolling_returns.py L89: best=portfolio_rolling.max())。 間違った前提で得た成果物は混乱の元。削除して正しい定義で再分析する。 | dm-signal | 04-04 | cmd_1702成果物3件を削除後、production定義 |
| cmd_1704 | cmd_1700で65PF一律EMA5→59 FoF 83%悪化。原因: Highが落ちるPFにも一律適用し尖りを削った。 cmd_1703のrolling return High特徴量で、EMA5でHighが落ちないPFを特定済み。 Highが落ちないPFだけにEMA5を選択適用し、FoF伝播を再測定する。 | dm-signal | 04-04 | 12M delta_high >= 0 で52/65 PFを |
| cmd_1705 | EMA span=5でStandard PF改善→FoF 83%悪化。棄却済み仮説2件: (1) シグナル同期化(Jaccard r=-0.199) (2) High(Max)落下(選択適用でも悪化)。 原因特定に至っていない。広く5指標を同時に算出してデータを揃え、原因を多角的に分析する。 | dm-signal | 04-04 | — |
| cmd_1706 | EMA5一律→FoF 83%悪化。原因分析より先に「より良いFoFが作れるか」を探る。 良いものが見つかれば、現行との差分をなぜなぜしてヒントが見つかる(殿指示)。 5パターンの前処理を59 FoFで試し、baselineに勝つパターンを探索する。 | dm-signal | 04-04 | 5条件×59FoF比較を完了。best patternはE( |
| cmd_1707 | 前処理研究完了。Standard PF品質改善はFoFに伝播しない。 次の研究: FoFがStandard PFを選ぶ「判断ロジック」自体の改善。 まず現行FoFのmomentum判定の実装を正確に把握し、改善余地を特定する。 | dm-signal | 04-04 | 59 active FoF auditを完了。現DB基準の相 |
| cmd_1708 | 前処理研究は区切り。FoFの天井突破には材料品質(前処理)ではなく判断ロジック(selection)の改善が必要。 既存のr29f_shin_clsel_2d_grid.py(LB×Metric 48セル WF-OOS)を再実行し、 現行シン忍法v2のselection blockパラメータが最適か検証する。 既存スクリプトをそのまま使う。新規開発なし。 | dm-signal | 04-04 | — |
| cmd_1709 | GS速度最適化を修行で回す前提条件。パリティ基盤なしに修行を回すな(軍師なぜなぜ結論)。 パリティ条件(殿定義): 全期間の本番DBでの保有ポジション(holding_signal)の完全一致。 ゴールデンデータ(殿提案): 本番DBから1回取得→固定ファイル。以降はこれと比較。 | dm-signal | 04-04 | 65 standard PF golden dump作成、g |
| cmd_1710 | 今日のセッションで4回、殿の言葉を定義確認せず即cmd起票した: (1) rolling return High→本番定義(Max)未確認 (2) シン忍法のスクリプト→run_077_*未特定 (3) 2Dグリッド→既存結果未確認 (4) パリティ条件→定義を軍師に丸投げ 真因: cmd起票前の「確認フェーズ」を強制する仕組みがない。 cmd_save.shにq7(殿用語定義確認)を追加し、環境に埋め込む。 | infra | 04-04 | cmd_save.sh に q7_definition_ve |
| cmd_karo_reflux_1707 | context還流 — cmd_1702-1707研究結果のdm-signal-research.md更新 | dm-signal | 04-04 | L544-L540の5件をcontext/dm-signal |
| cmd_karo_gs_profile | GS速度最適化Phase 1b。軍師設計書(gunshi-gs-speed-optimization-design.md §2)に基づく。 パリティ基盤(cmd_1709)完了。次はプロファイリングでhot pathを特定する。 | dm-signal | 04-04 | oikaze cProfileをPATTERN_LIMIT= |
| cmd_karo_gs_benchmark_v2 | GS速度最適化Phase 1c。軍師設計書+軍師助言(PATTERN_LIMIT=100, timeout 5分/本, 段階的実行)反映版。 | dm-signal | 04-04 | 8スクリプトをPATTERN_LIMIT=100で計測し、g |
| cmd_karo_gs_tool_growth | 軍師SG10なぜなぜ結果: cmdのACに'research_engine.pyに追加せよ'が明示されていない。 cmd_1698で半蔵が自発的に追加したが再現性なし(忍者の意志依存)。 cmd_save.shにresearch cmdで新規関数定義時にengine統合ACを要求するチェックを追加。 | infra | 04-04 | cmd_save.shに研究cmd向け道具成長WARNING |
| cmd_karo_gs_kawarimi_profile | kawarimi(81分)が全体の75%。高速化最優先。ランブック§7: kawaramiは未プロファイル。 oikazeの知見がそのまま適用できる保証はない。まずcProfile取得。 | dm-signal | 04-04 | 指定の cProfile コマンドを実行し、早期終了を含む |
| cmd_karo_gs_oikaze_optimize | oikazeプロファイルで特定済みの3最適化対象を実装。ランブック§7。 パリティ検証(gs_parity_check.py)必須。 | dm-signal | 04-04 | oikazeの月次momentum計算とcache再利用を最 |
| cmd_karo_gs_kawarimi_opt | kawarimi(81分)が最大ボトルネック。前回プロファイルは既存出力ガードで即終了。 既存出力をリネーム→cProfile取得→hot path特定→最適化実装→パリティ検証。 | dm-signal | 04-04 | kawarimiのGS hot-pathで補助データ生成を遅 |
| cmd_karo_gs_nukimi_opt | nukimi(3.5分)もMomentumFilter系。oikazeと同構造の可能性。oikaze知見を横展開。 | dm-signal | 04-04 | nukimi の single-view momentum |
| cmd_karo_gs_kasoku_diff_opt | GS高速化 — kasoku_diff最適化(oikaze知見横展開) | dm-signal | 04-04 | kasoku_diff の GS context build |
| cmd_karo_gs_kasoku_ratio_opt | GS高速化 — kasoku_ratio最適化(oikaze知見横展開) | dm-signal | 04-04 | kasoku_ratio の GS serial hot p |
| cmd_karo_gs_yotsume_opt | GS高速化 — yotsume最適化(oikaze知見横展開) | dm-signal | 04-04 | yotsume の multi-view hot path |
| cmd_karo_gs_bunshin_opt | GS高速化 — bunshin最適化 | dm-signal | 04-04 | bunshin の hot path を最適化し、gs_pa |
| cmd_karo_gs_shijin_opt | GS高速化 — shin_shijin最適化 | dm-signal | 04-04 | shin_shijin_l1_gs.py の monthly |
| cmd_karo_gs_kawarimi_opt2 | kawarimi 81分の99.9%はserial pathのTrendReversalFilterBlock.execute未最適化。 yotsume(21.6倍)で実証済みの3最適化を適用。ランブック§7に具体指示あり。 | dm-signal | 04-04 | TrendReversalFilterBlock に yot |
| cmd_karo_gs_shared_cache | 軍師cmd案A。oikaze/nukimi/yotsumeにあるshared_momentum_cache(rebalance間再利用)を kawarimi/kasoku_diff/kasoku_ratioに横展開。3スクリプトは異なるファイル。 | dm-signal | 04-04 | shared_momentum_cacheをkawarimi |
| cmd_karo_gs_dict_lookup | 軍師cmd案B。momentum_filter.pyとsingle_view_momentum_filter.pyの get_momentum_value_at_date(bisect)をdict lookupに置換。2ファイルは独立。 | dm-signal | 04-04 | MomentumFilterBlock と SingleVi |
| cmd_karo_gs_shijin_cache | 軍師提案。shin_shijin(14.6分)のsimulate_strategy_vectorized Phase 1結果を lookback configキーでキャッシュ。同一キーはキャッシュ→Phase 2のみ実行。 | dm-signal | 04-04 | shin_shijin_l1_gs.pyにlookback |
| cmd_karo_gs_shijin_batch | 軍師分析: shin_shijin Phase 2が384s(50%)。NumPy行列演算バッチ化で40x→合計4.1x。 | dm-signal | 04-04 | Phase 2の月次リターン計算をunique signal |
| cmd_karo_gs_skip_verify | 軍師提案。3スクリプトに--skip-verifyフラグ追加。 期待: kawarimi 3.3分→数十秒、kasoku_diff 46s→~10s、kasoku_ratio 50s→~20s。 | dm-signal | 04-04 | 3本の忍法GSランナーに --skip-verify を追加 |
| cmd_karo_gs_shijin_skip_parity | GS高速化 — shin_shijin --skip-parityフラグ追加(7.7分→4.3分見込み) | dm-signal | 04-04 | --skip-parity 実行時にAC1スキップを明示表示 |
| cmd_karo_gs_shijin_parallel | GS高速化 — shin_shijin ProcessPool並列化(206s→58s見込み) | dm-signal | 04-04 | shin_shijin_l1_gs.py を family |
| cmd_karo_gs_shijin_full_batch | GS高速化 — shin_shijin Phase 2完全バッチ化(3.2分→1.1分見込み) | dm-signal | 04-04 | shin_shijin_l1_gs.py の family |
| cmd_1711 | 忍法GS結果(run_077_* 35万パターン)が全忍法分揃っている。 この既存データを深掘りし、パラメータ空間の構造を可視化する。 画像(ヒートマップ)で殿に報告する。 | dm-signal | 04-04 | 7忍法GS CSVを集約し、champion 7x6メトリク |
| cmd_1712 | CI赤が1日以上放置。E2E test#11「inbox delivery: nudge reaches mock_cli」が32秒タイムアウト。 フレーキーで片付けているがCI赤放置はgate信頼性低下。根本修正する。 | infra | 04-04 | — |
| cmd_1713 | 殿指示で発見したFLAIR手法を知識辞書に登録する。 4パラメータで710MパラメータのChronos-T5-Largeを上回る時系列予測手法。 GPU不要、numpy+scipy 654行。ハイパーパラメータ0個。 我々のdual momentum/FoF研究に応用可能性あり。 | dm-signal | 04-04 | FLAIR知識辞書を2層構造で追加し、methods/m17 |
| cmd_karo_fix_1711 | 軍師FAIL指摘3点: (1)CSV選択誤り(1186_*→246_*に修正) (2)AC1パラメータ空間ヒートマップ42枚未生成 (3)kawarimi legacy名使用。正しいCSVで全AC再実行。 | dm-signal | 04-04 | cmd_1711を再修正し、正しいGS入力でtop10/ch |
| cmd_1714 | 前処理研究9手法の結論がdm-signal/解釈層に未還流。次cmdで忍者が同じ轍を踏むリスク。 軍師設計案P1(gunshi-interpretation-layer-design.md §4)に基づき作成。 | dm-signal | 04-04 | preprocessing-research-conclus |
| cmd_1715 | 殿の裁定(PI-021/PI-009/パリティ条件等)がdm-signal/解釈層に未明文化。 忍者がPI違反実装→本番破壊のリスク。軍師設計案P2に基づき作成。 | dm-signal | 04-04 | production-invariants.mdを作成し、P |
| cmd_1716 | FLAIRの周期検出能力をDM-Signal研究ツールとして使う(殿発案)。 65 PFの月次リターンに周期構造があるか→どのlookback帯に効くかの検証基盤。 | dm-signal | 04-04 | FLAIR 65PF分析を実装し、Pテーブル・12ヶ月Sha |
| cmd_karo_codex_deploy_fix | 本セッションでhayate(Codex)に8回STALL。根因: deploy後の到達確認なし+respawn起動待ちなし。 LK028(Codex STALL根因)の自動化ターゲット3点を実装。 | infra | 04-04 | Codex ninja deployment reliabi |
| cmd_1717 | 軍師ランドスケープ分析でnukimi/kasoku_diffがoverfit HIGH判定(CAGR drop 33-34%)。 忍法GSのchampionパラメータがOOSで崩壊するか定量検証する。 道具(33倍速GS+パリティ基盤)が揃っている。 | dm-signal | 04-04 | cmd_1717 OOS検証を実装・実行し、5忍法のIS/O |
| cmd_1718 | FLAIR部品のDM-Signal応用を5方向で同時検証。絞らず全部やる(殿指示)。 cmd_1716のLevel/Shape結果を入力に、各部品の有効性を定量評価する。 | dm-signal | 04-04 | FLAIR 5部品検証を65PFで実行し、cmd_1718 |
| cmd_1719 | 殿発案: PFの今月の信頼度を予測する。ゼロベースの新アプローチ。 FLAIRのforecast(horizon=1, n_samples=200)で来月リターンの確率予測→ 期待リターン/不確実性=信頼度スコア。momentum(後ろ向き)とは根本的に異なる前向き判定。 | dm-signal | 04-04 | cmd_1719 FLAIR信頼度研究を実装・実行し、65P |
| cmd_1720 | FLAIR部品のDM-Signal応用第2サイクル。4方向を同時検証。 cmd_1716/1718/1719と合わせてFLAIR全応用を網羅する。 | dm-signal | 04-04 | FLAIR第2サイクル4検証を65PFで実行。cmd_172 |
| cmd_1721 | FLAIR検証で有効判定された3部品(Shapeゲート/LOO残差/Box-Cox)+信頼度top3が 特定PFに依存した結果ではなく一般的な特性かを検証する(殿指示)。 | dm-signal | 04-04 | cmd_1721 FLAIR有効部品の汎用性検証を実装・実行 |
| cmd_1722 | 全研究の共通構造「lookback帯域がSNRを支配」の検証。 FLAIRのLevel(ノイズ除去トレンド)でmomentumを計算し、Raw momentumとの精度差を測定。 Level系列は12ヶ月周期解像度(15-19点/PF)のため、月次比較は不可。 年次解像度での比較+動的lookback切替の原理検証を行う。 | dm-signal | 04-04 | cmd_1722完了。cmd_1716 Level CSVを |
| cmd_1723 | 殿発案: 新しいビルディングブロック=新しい忍法。 Levy & Lopes (2021) Dynamic Momentum Learningをselection blockとして実装・検証。 固定lookbackの構造的上限を超える。全研究の到達点(lookback帯域=SNR支配)の解。 | dm-signal | 04-04 | Levy DMA/DMS研究を65PFへ適用し、5条件比較・ |
| cmd_1724 | FLAIR研究(cmd_1716-1721)の結果が解釈層に未反映。38行のまま。 9検証+信頼度スコア+汎用性検証の結論を還流する。 | dm-signal | 04-04 | flair-interpretation.mdに§5-§8を |
| cmd_1725 | cmd_1722で年次Level momentum > Raw momentum(delta+0.020, N=14, 統計的確証なし)。 月次解像度で検証する。SSA(Singular Spectrum Analysis)で月次トレンドを抽出し、 そのトレンド系列でmomentumを計算→翌月実リターンとの精度比較。 | dm-signal | 04-04 | SSA(window=12)月次Level momentum |
| cmd_1726 | 軍師発案: PFレベルではなく基礎資産レベル(最上流)でノイズ除去。 前処理研究Phase 8「ノイズの源泉に近いほど効果大」の究極形。 10銘柄の日次/月次価格にSSA+FLAIRを適用→トレンド抽出→ そのトレンド価格でstandard PFのmomentumを再計算→精度比較。 | dm-signal | 04-04 | SSA(252)で13資産のトレンド成分を抽出し、65標準P |
| cmd_1727 | Levy論文の孫引き+引用先調査で発見した6論文が知識辞書に未登録。 adaptive lookback momentum研究の知識基盤を厚くする。 | dm-signal | 04-04 | methods/ に 6 件のモメンタム知識辞書を追加し、i |
| cmd_karo_fix_kb | 将軍検証指摘: (1)production-invariants.mdがmulti-agent-shogunに誤配置→DM-Signal移動 (2)cmd_1727追加指示3件が未登録 | dm-signal | 04-04 | production-invariants.md を DM- |
| cmd_1728 | 軍師なぜなぜ合成(gunshi-nazenaze-synthesis.md)の設計検証。 信号改善の天井確定→選択改善に全振り。Ward(多様性)×confidence(品質)×momentum(方向)+動的K。 | dm-signal | 04-04 | cmd_1728 の4段検証を実装・実行し、random v |
| cmd_1729 | 殿指示: 最強のALMを見つける。 Levy DMAの根本問題=目的関数がBinary(方向予測正解率)。IPヒートマップで1Mが支配的だが、 忍法GS/momentum top5では18Mが圧勝。「当てやすい」≠「儲かる」。 目的関数をBinary→CAGRランキング精度に変え、「儲かるlookback」を動的選択するALMを設計・検証。 | dm-signal | 04-04 | — |
| cmd_1730 | ALM研究で本番メトリクスを特徴量に使う。独自計算は本番と乖離するため禁止(殿指示)。 本番metrics_calculator.pyのロジックを研究スクリプトからimportできる道具を構築する。 research_engine(前処理研究)と同じパターン。道具が先。 | dm-signal | 04-04 | metrics_research_engine.py作成完了 |
| cmd_1732 | gate — gate_fire_logからテスト実行FAILを除外しメトリクス汚染解消 | infra | 04-04 | gate_report_format が /tmp テストレ |
| cmd_1733 | gate — autofix拡張: verdict自動導出+status自動更新(GP-107消火4問PASS) | infra | 04-04 | gate_report_autofix_main.py に |
| cmd_1734 | gate — 報告テンプレートにninja_weak_points gate_warningをフィールド直上に注入し学習ループを回す | infra | 04-04 | deploy_task.sh の報告テンプレート生成に ga |
| cmd_1735 | 研究 — ALM: 34メトリクス目的関数×24 lookback(1M~24M全部)動的選択 | dm-signal | 04-04 | 24 lookback版ALM研究を完了。1M-24M全固定 |
| cmd_1736 | 研究 — ALM top_n=1-10 × 24 lookback × 5 rolling窓 × 34メトリクス目的関数 | dm-signal | 04-04 | cmd_1736完了。ALM full sweep 1940 |
| cmd_1737 | 研究 — ALM OOS検証 3段構え(Stage0:3軸同時 + Stage1:50組合せ + Stage2:PBO) | dm-signal | 04-04 | cmd_1737実装・実行完了。cache欠損を自己修復し、 |
| cmd_1738 | gate — cmd_save.shに前段cmdパラメータ空間突合チェック追加(BLOCK) | infra | 04-04 | cmd_save.sh に前段 results.yaml の |
| cmd_1739 | 研究 — ALM OOS検証 全50組合せPBO + Stage0/1 (パラメータ縮小なし) | dm-signal | 04-04 | cmd_1739を実装し、ALM OOS Stage0-2を |
| cmd_karo_1739_cscv | 研究 — ALM OOS Stage0/1をCSCV 70組合せに拡張 | dm-signal | 04-04 | cmd_1739 Stage0/1をCSCV 70分割へ拡張 |
| cmd_1743 | 研究 — 既存124PF有限時間4指標一括計測 + L0/L1層別分布 | dm-signal | 04-05 | research_engine.pyに有限時間4指標(cal |
| cmd_karo_fix_1743 | 修正 — cmd_1743層別分類の修正(L0=standard全65体/L1=FoF全59体) | dm-signal | 04-05 | classify_layer関数をportfolio_typ |
| cmd_1744 | 研究 — ALM L0材料×既存L1パターンでFoF構築+既存ベースライン比較 | dm-signal | 04-05 | cmd_1744完了。ALM L0 4系列CSV・L1パター |
| cmd_1746 | 強化 — shutsujin_departure.shに--dry-runオプション追加 | infra | 04-05 | shutsujin_departure.sh に --dry |
| cmd_1747 | 研究 — 6目的関数ALM L0材料×忍法7本。Max Run-up以外の尖りでも効くか検証 | dm-signal | 04-05 | cmd_1747完了。6目的関数×4ファミリーのALM be |
| cmd_karo_score_wide | 研究 — ALMスクリプトscore_wide高速化(score_fn→numpy一括) | dm-signal | 04-06 | cmd_1735/1736 を score_fn から sc |
| cmd_1748 | 研究 — ALM L1 OOS検証。6目的関数×忍法7種=42パターンWF-OOS | dm-signal | 04-06 | 41/42 ROBUST。tail_contribution×加速RのみOVERFIT |
| cmd_1749 | 偵察 — ALM本番組込み。BEパイプライン+Admin CDP+ALMフック候補 | dm-signal | 04-06 | L0フロー全容把握。Hook A(fof)+FE UI分析+CDPスクショ |
| cmd_1750 | 偵察 — ALM Phase 3.7/4/4.5改修設計。recalculate_fast.py精読 | dm-signal | 04-06 | 2パス方式推奨。事前計算+月次選出+fullrecalc設計確定 |
| cmd_1751 | 偵察 — ALM盲点6件。保存バリデーション+cron+FoF連携+CDP実地 | dm-signal | 04-06 | FoF透過的OK。daily cron=mode=PORTFOLIO。fullrecalc自動cronなし |
| cmd_1752 | ALM impl cmd発令前に残る4つの未検証事項を埋める。 cmd_1750設計書の実現可能性を実コードで最終確認する。 | dm-signal | 04-06 | cmd_1752書込み競合偵察を完了。Pass2→Phase |
| cmd_1753 | なぜなぜ7回転で発見した4盲点を現物確認。全て5-10分のコード精読で済む。 | dm-signal | 04-06 | MTDはMonthlyReturnテーブルに混入する（意図的 |
| cmd_1754 | ALM設計知識が10ファイルに散在。/clear後に全エージェントが即使えるよう 1統合設計書にまとめ、projects/dm-signal.yaml+context §35にポインタを置く。殿直接指示。 | dm-signal | 04-06 | cmd_1754を完了。ALM統合設計書を新規作成し、§1- |
| cmd_1755 | 大元リポ(yohey-w/multi-agent-shogun)の最新アップデートから 我が軍にない3点の有用性を現物比較で判定する。 なぜなぜ7回転で絞り込んだ3点。 | infra | 04-06 | PR#113 guard.sh(6 hooks)と我が軍pr |
| cmd_1756 | 大元リポ(yohey-w) commit c87ca64のratelimit表示改善+SSH key改善を 我が軍のAndroidアプリ(v5.7)+ratelimit_check.shと比較し、取り込み価値を判定する。 | infra | 04-06 | cmd_1756偵察を完了。upstream c87ca64 |
| cmd_1757 | cmd_1754で作成された統合設計書(docs/research/alm-integration-design.md)に なぜなぜ追加回転で発見した6件の修正事項を反映する。 誤った数字(30分)と誤った前提(2パス=manual限定)を正す。 | dm-signal | 04-06 | alm-integration-design.md に指定6 |
| cmd_1758 | 大元リポ(yohey-w)のPR#113+skill-creator v2.0から 我が軍に不足する7件を取り込む。cmd_1755偵察で特定済み。 | infra | 04-06 | guard強化3件完了。G1:test_hooks.sh(7 |
| cmd_1760 | ALM目的関数の鉄壁方向が手薄（LTJ_invのみ）。 calmar/sortino/UWP/MDDの4つを新規ALM目的として検証し、 L0性能+L1忍法7種性能+既存シン忍法比較まで一気に出す。 殿直接指示。 | dm-signal | 04-06 | cmd_1760 sortino_ratio ALM L0+ |
| cmd_1761 | ALM忍法19体とシン忍法20体の全メトリクスを38指標で統一計算し、 忍法別比較表の空欄を全て埋める。 cmd_1760のcalmar/sortino目的でMaxDD/MRU/TC/NHF等が欠落していた問題を解消。 | dm-signal | 04-06 | 分身+追い風の旧/シン/ALM3世代・11体38メトリクス算 |
| cmd_1762 | ALM(Adaptive Lookback Momentum)本番組込みの第一弾。 スキーマにAlmConfig追加 + recalculate_fast.pyのPhase 3.7で ALM PFの全候補lookbackのmomentum cache + vectorized signalsを事前計算する。 設計書: docs/research/cmd_1750_alm_design.md (AC1+AC3前半) | dm-signal | 04-06 | ALM本番組込み第一弾(cmd_1762)を完了。AC1/A |
| cmd_1737_v2 | ALM OOS検証v2: 全50組合せPBO | dm-signal | 04-06 | — |
| cmd_1740 | ファミリー別Max Run-up ALM+ローリング相関 | dm-signal | 04-06 | — |
| cmd_1763 | ALM忍法の3目的関数（現行: MRU/calmar/UWP）が最適か検証する。 L2（Ward FoF等）はシン忍法20体+ALM忍法を材料に使う。 L2材料プール全体の多様性を最大化する3目的関数の組合せを、 6目的関数の既存データからデータドリブンで選定する。 | dm-signal | 04-06 | AC1: cmd_1761_full_metrics.yam |
| cmd_1764 | cmd_1763(6目的C(6,3)=20通り)の不完全分析を完全版に拡張。 cmd_1760データ(calmar/MaxDD/sortino/UWP)を追加し10目的関数でC(10,3)=120通り。 L2材料プール(シン20体+ALM)の多様性を最大化する3目的関数をデータドリブンで確定。 | dm-signal | 04-06 | AC1-4完了。90体×11メトリクス行列/120通りランキ |
| cmd_1765 | L1 ALM WFエンジン骨格。CSV読込+WF fold生成+ベクトル化メトリクス計算。DM2(119,493パターン)先行 | dm-signal | 04-07 | AC1-3完了。L1 ALM WFエンジン骨格実装。CSV読 |
| cmd_1773 | URGENT — ALM四神12体を本番で非表示にする | dm-signal | 04-07 | global_visibility_settings(id= |
| cmd_1777 | 道具磨き — 月次リターン計算pure function化 + ALMパリティ完全達成 | dm-signal | 04-07 | 月次リターン pure function を新設し、既存 c |
| cmd_1780 | 起動ゲートstale GP検知修正 + 孤立context統合 + 未commit push | infra | 04-07 | Gate11 dashboard完了GP除外+GP-137 |
| cmd_1781 | ALM 67窓速度最適化 — compute_metrics_np全量呼出し廃止 | dm-signal | 04-07 | cmd_1781_impl は将軍指示で中止。作業到達点とし |
| cmd_1783 | ハーネス — cmd起票時WHY→WHAT因果強制 + 範囲縮小検知 | infra | 04-07 | cmd_save.shにq8_why_what BLOCK+ |
| cmd_1774 | ALM四神L0パリティ検証 — 研究スクリプト vs 本番DB(12体) + momentum_data修正 | dm-signal | 04-07 | ALM L0パリティ検証PASS。momentum_data |
| cmd_1784 | ALM 67窓速度 — Pool並列+batch最適化で7忍法31秒以内 | dm-signal | 04-07 | — |
| cmd_1787 | URGENT修正 — FoF 23体Cash化バグ修正 + fullrecalculate + 本番復旧 | dm-signal | 04-07 | 3ブロックの月次FoF momentum cache loo |
| cmd_1788 | ALM四神リネーム — DM番号→四神名に統一 | dm-signal | 04-07 | ALM四神12体の portfolios.name を DM |
| cmd_1790 | ALM L1 38メトリクス — Phase A commit + Phase B vectorized系7メトリクス | dm-signal | 04-07 | Phase A を commit 1ff11495 で固定し |
| cmd_1786 | URGENT偵察 — FoF Cash化バグ根因特定。4/7 fullrecalculateで23FoFがCash化 | dm-signal | 04-07 | Level3 FoF(23体)が常時Cashを出す根本原因を |
| cmd_1791 | ALM L1 38メトリクス Phase C — MINIMIZE更新+select_champions整合+7忍法67窓全量実行 | dm-signal | 04-07 | select_champions_multi_is は 6 |
| cmd_1789 | ALM L1 38メトリクス拡張Phase A — PrefixMomentCache+prefix系14メトリクス | dm-signal | 04-07 | PrefixMomentCacheに4配列を追加し、down |
| cmd_1792 | ALM四神フォルダ作成 — 12体をALM四神フォルダに移動 | dm-signal | 04-07 | 本番Admin APIで ALM四神 フォルダを新規作成し、 |
| cmd_1776 | ALM L0パリティ修正 — 研究スクリプトのmonthly_return計算を本番と完全一致させる | dm-signal | 04-07 | 研究側の monthly_return 期待値計算を本番Op |
| cmd_1782 | ALM 67窓 — 34メトリクス全量prefix/vectorized化 + 7忍法5分以内 | dm-signal | 04-07 | 34メトリクス window fast path 化により |
| cmd_1785 | 軍師設計依頼 — compute_metrics_npを38メトリクス対応に拡張する設計 | dm-signal | 04-07 | — |
| cmd_1793 | ALM L1 WF分析 — 7忍法selection_timelineから忍法別ALM適性+モードラベル付与 | dm-signal | 04-07 | cmd_1791で生成した7忍法selection_time |
| cmd_1794 | 知識鮮度回復 — ALMチェックリスト+context+dashboard+CLAUDE.md実物同期 | dm-signal | 04-08 | checklist-alm-registration.md( |
| cmd_karo_fix_precommit_comment | pre-commit hookコメント行偽陽性修正 | infra | 04-08 | git-pre-commit.sh L49にコメント行除外g |
| cmd_1795 | ALM忍法Step 3準備 — 12体universe+結合CSV+全7本ALM対応+bunshin動作検証 | dm-signal | 04-08 | AC1: alm_l0_12.yaml+alm_l0_12_ |
| cmd_1796 | ALM忍法Step 3実行 — 残り6忍法を6忍者並列実行 | dm-signal | 04-08 | 6忍法(oikaze/nukimi/kawarimi/kas |
| cmd_karo_fix_neverstop_hang | never_stop_forにプロセスhang独立検証を追加 | infra | 04-08 | NEVER_STOP_DEFAULTS に 4 項目目として |
| cmd_karo_fix_gate_split_loop | GATE構造バグ2件修正 — 分割配備ACスコープ+auto_draft循環防止 | infra | 04-08 | cmd_complete_gate.shのassigned_ |
| cmd_1797 | チェックリスト改訂 — Step 3をIS窓動的選出フローに書き換え+GS完了記録 | dm-signal | 04-08 | checklist-alm-registration.md |
| cmd_1798 | ALM忍法Step 3b — WFエンジンをALM GSデータで実行し21体候補のselection_timeline生成 | dm-signal | 04-08 | WFエンジンALM 7忍法実行は完了。CSV_FILESを6 |
| cmd_1799 | ALM忍法Step 3b再実行 — WFエンジン67窓(--multi-is)で7忍法全量実行 | dm-signal | 04-08 | 7忍法全量--multi-is(IS=6-72M, 67窓) |
| cmd_karo_ci_fix | CI赤修正 — テスト失敗3グループ修正(setup_file/q8_why_what/proposal出力) | infra | 04-08 | CI失敗テスト4件修正。全811件PASS達成 |
| cmd_1800 | infra — lord_conversation loggerに殿のinput(inbound)を記録する | infra | 04-08 | AC1: log_terminal_input.shのdir |
| cmd_1801 | infra — cmd_save.sh消火判定gate(q9)追加 — 消火cmdの入口で真因記入を強制 | infra | 04-08 | cmd_save.shに消火cmd向けq9_firefigh |
| cmd_1804 | fix — cmd_save.sh q9磨き上げ — キーワード追加+意志依存prevention WARN | infra | 04-09 | cmd_save.shのq9判定語彙にバグ/bug/不具合/ |
| cmd_1805 | fix — q9意志依存パターンを語幹マッチに強化（活用形抜け修正） | infra | 04-09 | q9意志依存パターンを語幹マッチに変更。活用形(気をつけて/ |
| cmd_1807 | fix — deploy_task.shに消火判定gate追加（家老自発cmd経路のq9カバー） | infra | 04-09 | deploy_task.shにcheck_firefight |
| cmd_karo_fix_wa_yaml_dump | fix — gate_wa_data_quality.sh --fixモードのyaml.dump除去 | infra | 04-09 | gate_wa_data_quality.sh --fixモ |
| cmd_karo_gp177_keyword_lib | enhance — 消火キーワードリストをscripts/lib/に共通化（GP-177） | infra | 04-09 | scripts/lib/firefighting_keywo |
| cmd_1808 | fix — /clear前チェックhookをSessionEndに移設+ntfy通知化 | infra | 04-09 | SessionEnd clear check hookを追加 |
| cmd_1809 | fix — Androidアプリ エージェントpane全画面表示の初期スクロール位置を最下部にする | infra | 04-09 | PaneFullScreen初回表示時のスクロール位置を最下 |
| cmd_1810 | enhance — Androidアプリ エージェントpane入力UI改善（展開ボタン+特殊コマンド常時表示） | infra | 04-09 | PaneFullScreen入力バー改善3点を実装。AC1: |
| cmd_1811 | enhance — Androidアプリ メモ画面にGistファイル一覧表示を追加 | infra | 04-09 | GistファイルAPI連携+メモ画面UI追加をassembl |
| cmd_1812 | enhance — GATE CLEAR時に将軍idle検知→inbox通知で将軍が自動で完了に気づく | infra | 04-09 | cmd_complete_gate.sh の通常・emerg |
| cmd_1814 | fix — 将軍画面のSpecialKeysRowも常時表示にする | infra | 04-09 | ShogunScreen.ktのSpecialKeysRow |
| cmd_1815 | recon — Androidアプリ入力欄キーボード問題の根本原因特定（おしお殿コード全比較+Android公式調査） | infra | 04-09 | Android EdgeToEdge+keyboard ha |
| cmd_1816 | fix — Android keyboard問題根本修正 — NavigationBar.imePadding削除+Column.imePadding追加 | infra | 04-09 | NavigationBarのimePadding()をSho |
| cmd_1817 | ゴールデンデータ全量アップデート — 全136PFのmonthly_returns+holding_signal取得(タイムスタンプ付き) | dm-signal | 04-09 | AC2完了: 全active PF 136体(standar |
| cmd_1819 | ALM忍法 殿定義6目的 67窓L1 WF全量実行 — METRIC_NAMES変更+7忍法再実行 | dm-signal | 04-09 | METRIC_NAMESをcagr/nhf/maximum_ |
| cmd_1821 | 奥義-シン忍法 — シン忍法20体を材料にL2忍法GS+67窓WF実行 | dm-signal | 04-09 | AC1-AC4の技術作業は完了。シン忍法20体の本番DB月次 |
| cmd_1823 | 研究道具カタログ永続化 + cmd_save.sh道具明示チェック追加 | infra | 04-09 | AC1: dm-signal-ops.md §18に研究道具 |
| cmd_1826 | 偵察 — l1_alm_wf_engine.py メモリプロファイリング（468MB CSV→13GB膨張の根因特定） | dm-signal | 04-10 | l1_alm_wf_engine.py メモリ消費分析完了。 |
| cmd_karo_premise_check | fix — inbox_write.sh pre-send captureに★前提問い追加 | infra | 04-10 | inbox_write.sh L785の★10回問いecho |
| cmd_1827 | fix — l1_alm_wf_engine.py メモリ削減（PrefixMomentCache fold毎構築+float32化） | dm-signal | 04-10 | cmd_1827_impl再完了。deepdive第3弾の5 |
| cmd_1829 | fix — nukimi simulate_batch L3キャッシュ最適化（BATCH_CHUNK分割） | dm-signal | 04-10 | run_077_nukimi.py に BATCH_CHUN |
| cmd_1831 | new — GS並列ランナー(gs_runner.py)構築 | dm-signal | 04-10 | gs_runner.py新規実装完了(147行)。--uni |
| cmd_1835 | recon — kawarimi batch vs sequential md5不一致の根因調査 | dm-signal | 04-10 | TrendReversalFilterBlock.execu |
| cmd_1834 | recon — CSV I/Oボトルネック調査(GS書出し91%占有) | dm-signal | 04-10 | CSV書出し実装箇所特定・計測完了。kasoku_ratio |
| cmd_1832 | perf — pipeline関連heavy import lazy化(全7忍法) | dm-signal | 04-10 | 7忍法 run_077_*.py のpipeline関連mo |
| cmd_1838 | fix — deploy_task.sh commit check gitignore自動除外 | infra | 04-10 | deploy_task.shにgit check-ignor |
| cmd_1836 | perf — GS CSV書出しnumpy savetxt置換(pandas 270s→4.6s) | dm-signal | 04-10 | 7忍法のrun_077_*.pyの月次CSV書出しをnump |
| cmd_1837 | fix — kawarimi PYTHONHASHSEED非決定性修正(L78 sorted()) | dm-signal | 04-10 | TrendReversalFilterBlock L78をs |
| cmd_1842 | fix — GS run_077_*.py CSV出力時に.npyキャッシュ同時生成（キャッシュ不在ゼロ化） | dm-signal | 04-10 | 7忍法run_077_*.pyのwrite_monthly_ |
| cmd_1841 | fix — l1_alm_wf_engine.py load_data() numpy直読み化（pd.read_csv OOM根絶） | dm-signal | 04-10 | l1_alm_wf_engine.pyのcache-miss |
| cmd_1840 | fix — 奥義-シン忍法 大CSVキャッシュ生成+WF完走+チャンピオン選出 | dm-signal | 04-10 | AC1 PASS: nukimi/kasoku_ratio |
| cmd_1844 | 奥義-シン忍法 GS事後チャンピオン選出 — 3目的(CAGR/NHF/MaxDD)×7忍法 | dm-signal | 04-10 | GS CSV 7本全量確認完了。全パターン(合計195805 |
| cmd_1845 | 奥義-シン忍法 6メトリクス比較表 — GS事後 vs ALM方式 vs シン忍法(材料) | dm-signal | 04-10 | AC1 PASS: シン忍法20体全UUID存在確認(20/ |
| cmd_1846 | 奥義-シン忍法 忍法×忍法 組み合わせ有効性分析 — selection_timeline全21チャンピオン | dm-signal | 04-11 | 21体パラメータ一覧(AC1)、21本selection_t |
| cmd_1848 | 奥義-シン忍法 過適合検証2 — 期間分割OOS | dm-signal | 04-11 | cmd_1848完了。IS/OOS分割(前半75M/後半75 |
| cmd_1847 | 奥義-シン忍法 過適合検証1 — 近傍パラメータ安定性 | dm-signal | 04-11 | AC1 PASS: 21チャンピオンpattern_idから |
| cmd_1850 | 奥義-シン忍法 CPCV全方位分析 — L0/L1/L2の3層PBO+IS-OOS相関+分散+MinBTL | dm-signal | 04-11 | AC1: L0(四神12体)/L2(奥義シン忍法20体×7忍 |
| cmd_1851 | fix — ninja_monitor.sh CLI死活判定+自動再起動（OOM死亡2h放置防止） | infra | 04-11 | ninja_monitor.shにCLI死活判定+自動再起動 |
| cmd_1852 | 奥義-シン忍法 β調整α分析 — L0/L1/L2の3層でSPY/TQQQ/TECLベンチマーク比較 | dm-signal | 04-11 | AC1: SPY 195ヶ月/TQQQ 194ヶ月/TECL |
| cmd_1854 | ゴールデンデータ更新 — 本番DB全PF monthly_returns再取得 | dm-signal | 04-11 | 本番DB全PF monthly_returnsを取得しゴール |
| cmd_1856 | 奥義-シン忍法 残り20体 本番DB一括登録（登録のみ） | dm-signal | 04-11 | 20体の奥義FoFレコードを本番DBに正常登録(hide=t |
| cmd_1857 | fix — insight§14自走トリガー廃止+report templateデフォルト値追加 | infra | 04-11 | cmd_1857: §14自走トリガー廃止(AC1)+dep |
| cmd_1858 | fix — gate_shogun_startup.sh ALERT精度改良3件（false ALERT削減+actionable化） | infra | 04-11 | AC2(Gate17 oneshot除外)+AC3(Gate |
| cmd_1859 | perf — Gate15 orphan検知 git logバッチ化（GP-170） | infra | 04-12 | Gate15 orphanループ内のgit log個別呼出し |
| cmd_1862 | fix — archive_completed.sh TOCTOU競合修正 shogun_to_karo.yaml読込flock内移動（GP-182） | infra | 04-12 | archive_cmds()のQUEUE_FILE読込(ma |
| cmd_1861 | fix — deploy_task.sh STALE_RESET全パス実行+実行済みフラグ確認（GP-180+GP-181） | infra | 04-12 | reset_stale_fields()をresolve_c |
| cmd_1863 | ALM WF再実行 — MaxDD方向バグ修正後の全量再計算(バグデータ削除+再生成) | dm-signal | 04-12 | AC1完了(127件削除/87件指定範囲+40件スコープ外を |
| cmd_1864 | FE Compare SummaryにCalmar RatioとUWP(Underwater Period)を追加 | dm-signal | 04-12 | Compare SummaryページにCalmar列(高→低 |
| cmd_1865 | ALM忍法CPCV検証 — 7忍法×4ファミリー選択バイアス定量評価 | dm-signal | 04-12 | 既存の --alm-dm 24セルに加え、constrain |
| cmd_1866 | ALM忍法 全方位検証(7手法) — WF-OOS劣化率+β調整+超越条件+IS感度+指標感度+構成体数+SPA | dm-signal | 04-12 | cmd_1866 ALM忍法全方位検証7手法完了。8手法中5 |
| cmd_1868 | ALM×シン — ALM四神BBのGS CSVからchampion_selector固定選出(2×2因子分析) | dm-signal | 04-12 | ALM四神BB 7忍法×3目的=21チャンピオン選出完了。c |
| cmd_1867 | シン×ALM — シン四神BBのGS CSVをWFエンジンで動的選出(2×2因子分析) | dm-signal | 04-12 | l1_alm_wf_engine.py --batch-cs |
| cmd_1869 | 2×2因子分析 同一期間統一再計算(2015-03~2026-01, 130ヶ月) | dm-signal | 04-12 | cmd_1869 2×2因子分析完了。7忍法×6メトリクス× |
| cmd_1870 | 2×2因子分析 β調整版 — 同一期間4セルのα/β分離+β調整後CAGR比較 | dm-signal | 04-12 | 4セル×7忍法=28データポイントのβ/α/β調整後CAGR |
| cmd_1871 | L2奥義8パターン生成 Step1 — universe CSV作成+GS実行+②WF | dm-signal | 04-12 | — |
| cmd_1872 | L2奥義8パターン生成 Step2 — ③〜⑧選出+L2 2×2因子分析(β調整) | dm-signal | 04-12 | — |
| cmd_1873 | fix — SessionEnd hookのALERT判定を修正（cmd_pending/ninja_activeはINFO化） | infra | 04-12 | clear_prep_check.shのcmd_pendin |
| cmd_1874 | gate — MCP書込み時の殿帰属キーワード照合hook追加（研究出力→殿定義混同防止） | infra | 04-12 | cmd_1874: pre-mcp-lord-attribu |
| cmd_1875 | gate — MCP書込み時の設計情報/好み仕分けhook（設計パラメータはprojects/*.yamlへ誘導） | infra | 04-12 | pre-mcp-lord-attribution-guard |
| cmd_1877 | L2奥義 49ブロック完全直列 — 1忍者1忍法OOM防止 | dm-signal | 04-13 | ③3-5 kawarimi GS完了。270900パターン処 |
| cmd_1879 | WF出力上書きバグ修正後の3忍法WF再実行 — 並列配備 | dm-signal | 04-13 | ④4-1 bunshin WF再実行を完了。5成果物生成と忍 |
| cmd_1878 | L2奥義 8パターン全比較 — チャンピオン21体確認+2×2因子分析+傾向分析 | dm-signal | 04-13 | AC1+AC2を完了。8パターン全てで21体を確認し、168 |
| cmd_1880 | L2奥義168体 β調整検証 — 市場リスク分離+α算出 | dm-signal | 04-13 | AC1-AC4完了。168体をSPY共通期間(88-161ヶ |
| cmd_1881 | DM-Signal push修復 — git履歴から大ファイル除去+push | dm-signal | 04-13 | AC1完了(8ファイル履歴除去済み)。AC2でG2ゲートブロ |
| cmd_1882 | UWP定義修正 — 比較表+β調整表再生成+スプレッドシート更新 | dm-signal | 04-13 | AC1-AC4完了。UWPを本番定義(最大DDのpeak→r |
| cmd_1883 | GS再実行 — filter-repo消失3忍法×2パターン復旧 | dm-signal | 04-13 | cmd_1883の欠損GS成果物6本を確認し、未存在だったk |
| cmd_1884 | GS出力CSV命名統一 — _grid_results_fast/_grid_monthly_fast形式に統一 | dm-signal | 04-13 | cmd_1884対象4dirのGS出力CSVを_grid_* |
| cmd_karo_gp183_184 | GP-183/184実装 — commit check研究cmd免除+進行中月除外AC文言 | infra | 04-13 | deploy_task.sh の binary_checks |
| cmd_1885 | 偵察+修正 — 三層学習ループFAIL率分析+gate強化 | infra | 04-13 | gate_fire_log.yaml の22件中9件FAIL |
| cmd_1887 | 修正 — gate_shogun_startup.sh 2件の誤検知修正（inboundアーカイブ+AC段階配備） | infra | 04-13 | gate_shogun_startup.sh 誤検知2件修正 |
| cmd_1889 | 整備 — context鮮度WARN解消（dm-signal 3件+infrastructure 1件） | infra | 04-13 | AC1/AC2達成。context/infrastructu |
| cmd_karo_shouka2_wid | 消火撤去第2弾 — worker_id/parent_cmdファイル名推定を撤去 | infra | 04-13 | gate_report_autofix_main.pyからw |
| cmd_1888 | 消火撤去 — lessons_useful MISSING autofixをBLOCK化（消火→免疫転換） | infra | 04-13 | gate_report_autofix_main.pyのle |
| cmd_1890 | 消火撤去 — binary_checks result文字列正規化(PASS/ok→yes)を撤去しBLOCKに転換 | infra | 04-13 | autofix から PASS/ok/FAIL/ng の r |
| cmd_1891 | GP-186 — infra系shallow cmdのscout_exempt自動判定（cmd_save.sh改修） | infra | 04-13 | cmd_save.sh の q5 判定に infra+q4_ |
| cmd_1892 | GP-189 — lesson_write.shにtitle Jaccard類似度WARN追加（教訓重複検出） | infra | 04-13 | lesson_write.sh に title Jaccar |
| cmd_karo_gp110_deploy_warn | GP-110 — deploy_task.shに配備前重複チェック(自走commit検知WARN) | infra | 04-13 | deploy_task.sh に target_path の |
| cmd_1893 | L2奥義168体 パターン間相関分析 — ①(登録済み)vs②〜⑧の月次リターン相関構造 | dm-signal | 04-13 | AC1-AC3完了。168体を共通87ヶ月で揃えた相関分析を |
| cmd_1894 | L3奥義EW全量β調整 — 79万組み合わせでL2αを超えるL3があるか | dm-signal | 04-14 | — |
| cmd_karo_gs_vectorized | GS高速化 — gs_vectorized_subset.py本実装(3最適化+チャンク+verify) | dm-signal | 04-14 | gs_vectorized_subset.py に3最適化+ |
| cmd_1896 | L3 EW β調整 — 84体C(84,2)=3486通りのβ/α分離+L2α比較 | dm-signal | 04-14 | 3486ペアのL3 2体EW β調整を完了。L3最良α=13 |
| cmd_1897 | 奥義ALMシン 21体 本番DB登録 — ⑤(ALM-BB×シン忍法×GS固定)をhide=trueで登録 | dm-signal | 04-14 | okugi_alm_shin champions.json |
| cmd_karo_gp192 | GP-192 — パリティcmdテンプレートにtarget_date標準文言追加 | infra | 04-14 | inject_task_modifiers.pyにinjec |
| cmd_karo_gp191 | GP-191 — dict.get(target_date)禁止 pre-commit hook | dm-signal | 04-14 | scripts/run_precommit_checks.s |
| cmd_1899 | fix — FoF選択ブロック日付ミスマッチ修正(TRF dict.get→bisect)+潜在バグ2箇所+fullrecalculate+パリティ | dm-signal | 04-14 | dict.get(target_date)→get_mome |
| cmd_karo_ci_fix_1900 | CI赤修正 — test_cmd_save_ac_paths.bats T-002/T-004/T-005 unbound WARN_COUNT + stderr capture | infra | 04-14 | test_cmd_save_ac_paths.bats修正。 |
| cmd_1900 | fix — パリティスクリプト target_date修正 + 奥義ALMシン21体全量パリティ再検証 | dm-signal | 04-14 | cmd_1898 parity script の targe |
| cmd_1902 | L3 β調整 6指標拡張 — cmd_1896既存3486ペアにα版NHF/MaxDD/MRU/Calmar/UWP追加 | dm-signal | 04-14 | cmd_1902完了。cmd_1896互換の3486ペアCS |
| cmd_karo_gp190 | GP-190 commit check waive — scout_exempt/研究cmdのbinary_checksからcommit check除外 | infra | 04-15 | GP-190: scout_exempt=trueのcomm |
| cmd_1898 | 奥義ALMシン 21体 パリティチェック — holding_signal+monthly_return突合 | dm-signal | 04-15 | cmd_1898 parity実測完了。21体のうち hol |
| cmd_1903 | 将軍のcmd起票品質を構造的に引き上げる。Phase 31-32で11過ちが全てgateを通過した根因=「無知の知」がcmd起票に強制されていない。q10で検証済み空間の明示を強制し、q7を昇格し、研究cmd手順を追加する | infra | 04-15 | AC1(q10 WARNING), AC2(q7 dm-si |
| cmd_1906 | WARNINGは意志依存で壊れる。trust:unverifiedが残存するcmdをBLOCKし、sourceのファイルパス実在を検査することで、将軍の前提自己申告の嘘を構造的に防ぐ | infra | 04-15 | AC1: Check 20のtrust:unverified |
| cmd_1907 | cmd_1902の6指標α版3486ペアCSVからα-Calmar Top30を抽出し、モード混成(激攻×鉄壁)・忍法組合せ・奥義レベル構成の出現頻度を定量化する。Phase 32の発見(激攻+鉄壁混成がα安定性の構造的源泉)を数字で裏付ける | dm-signal | 04-15 | cmd_1902のalpha-Calmar Top30を抽出 |
| cmd_1908 | L3 α-Calmar Top30 Pareto最適ペア特定(6指標)。→殿指摘「なぜペアなの？3体の研究したよな」で車輪再発明に気づく | dm-signal | 04-15 | Pareto最適9/30件特定。しかし2体分析の重複。次は3体C(84,3) |
| cmd_1904 | 将軍cmd品質フィードバックループ — 軍師RC傾向の起動時可視化+verdict自動記録 | infra | 04-15 | gate_shogun_startup.shにRC傾向表示+cmd_design_quality verdict自動更新 |
| cmd_1905 | cmd前提明示 — assumptionsフィールド新設+trust検査+軍師review連携(なぜなぜ7回到達点) | infra | 04-15 | assumptions+trust WARNING。AC≧3のcmdで前提明示を促す |
| cmd_1909 | GP-194実装 — 分割配備時binary_checksをac_assigned範囲に制限 | infra | 04-15 | 配備中(小太郎) |
| cmd_1910 | テスト統合整理Phase1 — deploy_task.sh 16→7ファイル統合(軍師設計書準拠) | infra | 04-15 | 配備中(半蔵) |
| cmd_1912 | 強化 — assumptions未記入BLOCK化: AC≧3のcmdにassumptions必須化 | infra | 04-15 | Check 20でAC>=3のassumptions欠落をB |
| cmd_1913 | 強化 — 未コミット変更WARNに陣形図照合追加(cmd_1912誤キャンセル事故防止) | infra | 04-15 | cmd_save.shの未コミット変更警告に直近完了忍者一覧 |
| cmd_1911 | fix — CI RED修正: テスト並列化(--jobs 4)で露出した14テストの分離不足修正 | infra | 04-15 | 4テストファイルのsetup/teardownでBATS_T |
| cmd_1914 | 整備 — CoDDリファクタリング台帳作成+既存実績登録+軍師連携 | infra | 04-15 | CoDDリファクタリング台帳を新設し、既存3実績登録・inf |
| cmd_1915 | 強化 — q11_not_already_done: cmdの必要性検証BLOCK(車輪の再発明の原理的防止) | infra | 04-15 | cmd_save.sh に q11_not_already_ |
| cmd_1917 | 偵察 — cmd_save.sh CoDDプロファイリング(Phase 1): 関数レベルボトルネック特定 | infra | 04-15 | cmd_save.sh を隔離cloneで実測し、全体中央値 |
| cmd_1919 | 強化 — inbox_writeにaction_required引数追加(全エージェントデッドロック防止) | infra | 04-15 | scripts/inbox_write.sh に任意5引数 |
| cmd_1920 | 強化 — 掲示板システム導入: 全エージェント共有ボード+チェックボックス確認追跡 | infra | 04-15 | 共有掲示板を導入し、書込み/確認スクリプトと shogun・ |
| cmd_1916 | 強化 — q11自動検索: cmdの対象スクリプトとdocs/research/を自動照合(意志依存ゼロ層) | infra | 04-15 | cmd_save.shにcommandフィールドのスクリプト名自動抽出+docs/research grep+INFO表示 |
| cmd_1918 | fix — q11自動検索バグ修正(cmd_1916実装の動作不良修正) | infra | 04-15 | cmd_save.sh L298-336のq11自動検索ロジック修正 |
| cmd_1921 | fix — 掲示板requires_confirmationバグ修正+Q4形骸化防止(前セッション出来事注入) | infra | 04-15 | 作業中(影丸) |
| cmd_1922 | 強化 — 因果探索原則を将軍必読ファイルに追加(CLAUDE.md+startup gate) | infra | 04-15 | CLAUDE.md Step 2.55+gate存在チェック追加。テスト済み |
| cmd_1923 | cmd_save.sh Check 21: ACの数値絶対値WARN検出 | infra | 04-15 | cmd_save.shにCheck 21を追加し、AC de |
| cmd_1924 | Androidアプリ知識のcontext登録 — 存在するものを探せない問題の根因修正 | infra | 04-15 | context/infrastructure.md に An |
| cmd_karo_feedback_gap | fix — lesson feedback記録欠損の根因調査+修正 | infra | 04-15 | AC1: cmd_complete_gate.sh L403 |
| cmd_1926 | cmd_1924取消 — 各論パッチrevert | infra | 04-15 | cmd_1924で追加されたAndroid知識をcontex |
| cmd_1925 | 殿の全入力に確認リマインド注入 — 確認せずに回答する真因修正 | infra | 04-15 | 通常モードの additionalContext に `re |
| cmd_1927 | cmd_1925取消 — 確認なし起票のrevert | infra | 04-15 | cmd_1925で加えられた確認リマインド注入を撤去し、追加 |
| cmd_1930 | deepdive_causal_tracing Phase 6追記 — 人殺しの思想 | infra | 04-15 | deepdive_causal_tracing に Phas |
| cmd_karo_revert_1928_1930 | fix — cmd_1928/1930のgate_shogun_startup.sh変更をrevert | infra | 04-15 | gate_shogun_startup.shからcmd_19 |
| cmd_karo_revert_1928_1930_v2 | fix — revert不完全修正(deepdive Phase 6 + gate L750-753) | infra | 04-15 | Gate 18(lord_conversation inbo |
| cmd_karo_ci_fix_ga056 | fix — CI RED修正(gate_karo_startup.bats + cmd_save.bats テスト失敗4件) | infra | 04-15 | CI失敗テスト(test_cmd_save.bats×5件 |
| cmd_1933 | cmd_save.sh Check 10の作成cmd偽陽性修正。ファイル不在時に親ディレクトリが存在すれば作成対象としてINFO表示に降格し、親ディレクトリも不在ならBLOCK維持。cmd_1931/1932で2回連続BLOCKされた実害あり | infra | 04-15 | Check 10で親ディレクトリが存在する未作成パスをINF |
| cmd_1931 | 将軍の追体験品質が構造的に低い根因修正。家老(lessons_karo.yaml 55件)と軍師(lessons_gunshi.yaml 26件)にはdeepdive前に通読する具体的失敗データがあるが、将軍にはない。教訓の格納形式が出力の深さを決める(軍師分析)。lessons_shogun.yamlを作成し起動手順に組み込む | infra | 04-16 | lessons_shogun.yaml 20件を新設し、将軍 |
| cmd_1932 | 掲示板システムの引数順バグ修正+ライフサイクル管理追加。4エントリ中3件でcontent/posted_byが逆転。根因=引数順<posted_by> <content>がinbox_write.sh(<target> <content> ... <from>)と不一致でエージェントが間違える | infra | 04-16 | 掲示板の引数順バグを修正し、明示クローズ機能追加と既存3件の |
| cmd_karo_ci_fix_acpaths | CI RED修正 — test_cmd_save_ac_paths.bats更新コミット | infra | 04-16 | AC path test期待値を更新し、追加で露出したbul |
| cmd_1934 | 研究 — 3体EW全量探索: C(21,3)=1330通り×4手法β調整α6指標 | dm-signal | 04-16 | cmd_1934 実装完了。⑤_* 21列の3体1330通り |
| cmd_1935 | 整備 — context/codd.md新設: CoDD v1.8.0知識一元化 | infra | 04-16 | context/codd.mdを新設し、CLAUDE.md/ |
| cmd_karo_gp195_197 | GP-195+197統合 — gate_diagnose_check.shをgate_report_format.shに統合 | infra | 04-16 | gate_report_format.sh の FAIL 経 |
| cmd_karo_gp196 | GP-196 — 教訓注入絞込み 10→3件+IF-THEN構造化 | infra | 04-16 | deploy_task.sh の related_lesso |
| cmd_1936 | 強化 — gist作成時にインデックスgistを自動更新するスクリプト | infra | 04-16 | gist一覧の自動更新スクリプトと52+件実データの分類テス |
| cmd_karo_gp198 | GP-198 — Session State: タスクレベル失敗履歴引継ぎ | infra | 04-16 | GP-198実装完了。gate_report_format. |
| cmd_1937 | 整備 — context/ui-design-guide.md新設: 全エージェント共通UIデザインガイド | infra | 04-16 | Created context/ui-design-guid |
| cmd_1938 | 整備 — context/ui-design-guide.md補強: ボタンデザイン9tips+16tips統合 | infra | 04-16 | context/ui-design-guide.md に 1 |
| cmd_1939 | 強化 — scripts/cmd_save.sh L3診断推論: BLOCK時Diagnose MANDATORY+Session State | infra | 04-16 | cmd_save.shにDiagnose MANDATORY |
| cmd_1942 | 強化 — 忍者ACテストをaffected_tests.sh(関連テストのみ)に変更 | infra | 04-16 | deploy_task.shのテストAC生成で、全量unit |
| cmd_1941 | 強化 — GP/改善にbefore/after退化計測を義務化 | infra | 04-16 | GP/改善cmd向けreport templateにbefo |
| cmd_1940 | 強化 — gate_lesson_health.sh閾値をuseful率に変更+低効果教訓自動除外 | infra | 04-16 | gate_lesson_health.shにuseful率計 |
| cmd_1943 | 改修 — Androidアプリ ボトムナビ「メモ」→「Gist Index」差替え | infra | 04-16 | ボトムナビの「メモ」を「Gist Index」に差し替え、旧 |
| cmd_1945 | 修正 — Androidアプリ ライトテーマ文字コントラスト強化（殿フィードバック: ルール違反） | infra | 04-16 | DarkSengokuPalette の textMuted |
| cmd_1946 | verdict_override構造対策 — waive_ac正式機構 + 研究cmd commit check自動waive | infra | 04-16 | deploy_task.shに研究cmd/waive_ac用 |
| cmd_1947 | 研究 — N体EW比較: 1体/2体/3体 × 4手法 × 6指標 横並び分析 | dm-signal | 04-16 | cmd_1947完了。⑤_* 21列の1体21通り・2体21 |
| cmd_1948 | 研究 — N体EW比較(①×①): 1体/2体/3体 × 4手法 × 6指標 | dm-signal | 04-16 | cmd_1947を実行し、⑤_*21列の1体21通り・2体2 |
| cmd_1949 | 研究 — N体EW比較(①2⑤1): クロス 2体+3体(①多め) × 4手法 × 6指標 | dm-signal | 04-16 | ①×⑤クロス2体441通りと①①⑤の3体4410通りをcmd |
| cmd_karo_1948_retry | 研究 — N体EW比較(①×①) 再配備: load_monthly_returns引数化済み | dm-signal | 04-16 | ①_* 21列の1/2/3体EWを4手法×6指標で再計算し、 |
| cmd_1950 | 研究 — N体EW比較(①1⑤2): クロス 3体(⑤多め) × 4手法 × 6指標 | dm-signal | 04-16 | ①1⑤2の3体4410通りをcmd_1934同手法で算出し、 |
| cmd_1951 | 偵察 — インフラスクリプト全量プロファイリング+CoDD改善リスト作成 | infra | 04-16 | 全220本を計測・分類しCoDD改善リスト作成 |
| cmd_karo_ci_fix_cmd_save | CI修正 — cmd_save.shテスト期待値修正(BLOCKメッセージ形式変更対応) | infra | 04-16 | cmd_save の現行出力に合わせて 5 件の失敗テスト期 |
| cmd_1957 | CoDD改善#5 — gate_artifact_map.sh高速化(2.2s→目標400ms) | infra | 04-16 | gate_artifact_map.sh高速化完了。967m |
| cmd_1954 | CoDD改善#2 — dashboard_auto_section.sh高速化(2.8s→目標500ms) | infra | 04-16 | dashboard_auto_section.sh を高速化 |
| cmd_1953 | CoDD改善#1 — shutsujin_departure.sh高速化(2.4s→目標500ms) | infra | 04-16 | scripts/shutsujin_departure.sh |
| cmd_1956 | CoDD改善#4 — report_merge.sh高速化(1.9s→目標300ms) | infra | 04-16 | report_merge.sh: 1ファイルあたり4-5回の |
| cmd_1955 | CoDD改善#3 — gate_cycle_health.sh高速化(2.6s→目標500ms) | infra | 04-16 | gate_cycle_health.sh を 793ms→2 |
| cmd_1958 | CoDD改善#6 — gate_karo_startup.sh高速化(1.1s→目標300ms) | infra | 04-16 | gate_karo_startup.sh高速化完了。befo |
| cmd_1960 | CoDD改善#8 — inbox_write.sh高速化(89ms→目標40ms) | infra | 04-16 | inbox_write.shを高速化。agent_confi |
| cmd_1961 | CoDD改善#9 — ntfy.sh高速化(130ms→目標50ms) | infra | 04-16 | ntfy.sh高速化: before 33ms→after |
| cmd_1959 | CoDD改善#7 — gate_recalculate_completeness.sh高速化(4.0s→目標500ms) | infra | 04-16 | gate_recalculate_completeness. |
| cmd_1963 | CoDD改善#11 — gate_loop_health.sh高速化(493ms→目標100ms) | infra | 04-16 | gate_loop_health.sh 287ms→93ms |
| cmd_1964 | CoDD改善#12 — gate_lesson_health.sh高速化(228ms→目標50ms) | infra | 04-16 | gate_lesson_health.sh を 666ms |
| cmd_1962 | CoDD改善#10 — lesson_effectiveness.sh高速化(5.5s→目標500ms) | infra | 04-16 | lesson_effectiveness.sh高速化: ba |
| cmd_1966 | CoDD改善#14 — report_field_set.sh高速化(40ms×73回→目標15ms) | infra | 04-16 | report_field_set.shを高速化し、scala |
| cmd_1965 | CoDD改善#13 — ninja_done.sh高速化(68ms×104回→目標30ms) | infra | 04-16 | ninja_done.sh を軽量化し、usage/help |
| cmd_1970 | CoDD改善#18 — gate_workaround_rate.sh高速化(135ms×14回→目標40ms) | infra | 04-16 | gate_workaround_rate.sh高速化: py |
| cmd_1972 | CoDD改善#20 — parity_check.sh高速化(5.5s timeout→目標500ms) | infra | 04-16 | parity_check.sh に --help fast- |
| cmd_1974 | CoDD改善#22 — post_recalculate_checks.sh高速化(5.5s timeout→目標500ms) | infra | 04-16 | post_recalculate_checks.shをCRL |
| cmd_1975 | CoDD改善#23 — test_hooks.sh高速化(4.0s timeout→目標500ms) | infra | 04-16 | test_hooks.shを共通evaluator直呼びへ変 |
| cmd_1976 | CoDD改善#24 — gate_vercel_phase.sh高速化(481ms×7回→目標100ms) | infra | 04-16 | gate_vercel_phase.sh高速化完了。norm |
| cmd_1969 | CoDD改善#17 — pre_compact_save.sh高速化(141ms×毎compaction→目標40ms) | infra | 04-16 | pre_compact_save.sh高速化完了。jq×2→ |
| cmd_1977 | CoDD改善#25 — cmd_save.sh高速化(4.0s→目標500ms) | infra | 04-16 | cmd_save.sh高速化結果を記録。warm media |
| cmd_1978 | CoDD改善#26 — stop-lint-gate.sh高速化(3.0s→目標500ms) | infra | 04-16 | Stop hookの changed-file 取得を Gi |
| cmd_1980 | CoDD改善#28 — gate_recalculate_completeness.sh再トライ(2.74s→目標500ms) | infra | 04-16 | gate_recalculate_completeness. |
| cmd_1984 | CoDD改善#32 — gate_karo_startup.sh再トライ(225ms→目標80ms, 起動ごと) | infra | 04-16 | gate_karo_startup.sh 3改善: pyth |
| cmd_1983 | CoDD改善#31 — deploy_task.sh再トライ(88ms→目標30ms, 配備ごと) | infra | 04-16 | deploy_task.sh generate_report |
| cmd_1981 | CoDD改善#29 — dashboard_auto_section.sh再トライ(340ms→目標100ms, ×21回) | infra | 04-16 | dashboard_auto_section.shの第2次高 |
| cmd_karo_ci_fix_1987 | CI RED修正 — test_stop_lint_gate.bats test 941 HASH_FILE未生成 | infra | 04-17 | bats --jobs 8並列実行でHASH_FILEが/t |
| cmd_karo_context_freshness_1993 | context鮮度更新 — dm-signal-research.md+infrastructure.md | infra | 04-17 | context鮮度更新2件を反映し、対象2ファイルのみをコミ |
| cmd_karo_1995_fix | cmd_1995補足 — compare_snapshots.py holding_signal空振り修正+列名統一 | dm-signal | 04-17 | compare_snapshots.pyのholding_s |
| cmd_1994 | Phase 4準備① — fullrecalculate cProfile計測(read-only) | dm-signal | 04-17 | recalculate_fast.py fullrecalc |
| cmd_karo_ci_fix_f821 | CI RED修正 — run_077_yotsume.py F821(未定義変数)解消 | dm-signal | 04-17 | run_077_yotsume.py F821/F841/B |
| cmd_karo_gp190_fix | GP-190バグ修正 — scout_exemptがcommit checkを消す問題解消 | infra | 04-17 | deploy_task.sh修正: scout_exempt |
| cmd_1998 | Phase 4偵察 — fullrecalculate cache miss/fallback/N+1実測 | dm-signal | 04-17 | Phase4 cache/miss偵察を完了。signal_ |
| cmd_1999 | インフラ改善 — cmd_delegate.sh gate先行送信化(レースコンディション防止) | infra | 04-17 | cmd_delegate の gate FAIL分岐を実装・ |
| cmd_karo_ci_fix_blt72 | CI RED修正 — test_bulletin_board.bats test 72修正 | infra | 04-17 | bulletin_confirm.sh の if rc: ガ |
| cmd_karo_gp210_fix | GP-210修正 — inbox_watcher STATE_DIRパス不一致解消 | infra | 04-17 | restart_watchers.shの3箇所からSHOGU |
| cmd_2000 | Phase 4偵察② — fullrecalculate SQLクエリログ分類+top10重クエリ特定 | dm-signal | 04-17 | SQLAlchemy queryロギングをcmd_1994ハ |
| cmd_2003 | Phase 4偵察④ — fullrecalculate DB呼出のループ構造現物確認 | dm-signal | 04-17 | expand_portfolio_to_tickersの直呼 |
| cmd_2002 | Gist Index分類改善 — gist_index_update.sh classify_gist()を10カテゴリに再設計 | infra | 04-17 | gist_index_update.shのCATEGORY_ |
| cmd_2005 | Phase 4偵察⑤ — B1 preload変更のFE/UI影響範囲確認+設計書追記 | dm-signal | 04-17 | preload条件は monthly_return 値を変え |
| cmd_karo_ci_fix_ga091 | CI RED修正(GA-091) — gist_index_updateテスト期待値を新カテゴリ体系に更新+CATEGORY_ORDER修正 | infra | 04-17 | gist_index_update.sh のカテゴリ体系を新 |
| cmd_karo_ci_fix_ga092 | CI RED修正(GA-092) — cmd_delegate inbox_write失敗時のexit code修正 | infra | 04-17 | cmd_delegate の inbox_write失敗仕様 |
| cmd_2007 | Phase 4事前確認 — preload動作3パターン記録(standardPF/FoF/nestedFoF) | dm-signal | 04-17 | 代表3体(standard/FoF/nestedFoF)を |
| cmd_2008 | Phase 4 golden data化 — cmd_2007スナップショットを全改善cmdのパリティ基準に固定 | dm-signal | 04-17 | golden baseline固定・設計書作成・compar |
| cmd_2009 | Phase 4設計書更新 — §3全改善項目にgolden dataパリティ基準を明記 | dm-signal | 04-17 | §3の5改善項目と§6.4 golden data節を設計書 |
| cmd_2010 | インフラ修正 — cmd初期statusをdraftに変更(gate未通過配備防止) | infra | 04-17 | — |
| cmd_2006 | Phase 4 B1 impl — monthly_returns preload条件変更(N+1解消) | dm-signal | 04-17 | monthly_returns の FoF partial- |
| cmd_1997 | Phase 4準備②補足 — compare_snapshots.py列名不一致修正 | dm-signal | 04-17 | compare tool修正はbranch履歴に存在しpus |
| cmd_2011 | Phase 4設計書更新 — B1実測反映+本番baseline計測位置づけ明記 | dm-signal | 04-17 | Phase4設計書更新完了 |
| cmd_2001 | Phase 4偵察③ — Render上cProfile計測(純Python時間取得) | dm-signal | 04-17 | Render cProfile結果を docs/resear |
| cmd_2012 | Phase 4偵察⑥ — DELETE FROM signals 2505s(77%)の真因特定 | dm-signal | 04-17 | signals cleanup経路を特定し、DELETE条件 |
| cmd_2013 | Phase 4偵察⑦ — fullrecalculate PF×date網羅性検証(UPSERT化可否判定) | dm-signal | 04-17 | full recalcのPF取得・date範囲・inacti |
| cmd_2016 | Phase 4偵察⑨ — スキーマドリフト修正方法確認(CASCADE本番未反映) | dm-signal | 04-17 | 本番DB FK制約 vs models.py宣言の差分を全件 |
| cmd_2014 | Phase 4 C1 spec作成 — cleanup UPSERT化の影響範囲設計+他テーブルDELETE時間確認 | dm-signal | 04-17 | C1 UPSERT specを新規作成し、signals D |
| cmd_2018 | Phase 4 A2 CoDD spec — _generate_trade_performance ベクトル化設計 | dm-signal | 04-17 | A2 vectorize specを新規作成し、5候補の変更 |
| cmd_2019 | Karpathy Simplicity導入 — 軍師review_log+忍者報告テンプレートに自問追加 | infra | 04-17 | gunshi_review_log headerとdeplo |
| cmd_2017 | Phase 4 C1 impl — signals cleanup DELETE→UPSERT化(fullrecalc 77%削減) | dm-signal | 04-17 | signals cleanup DELETEをskipしてP |
| cmd_2020 | Phase 4設計書v3.0更新 — C面追加+B1/C1実測反映+Render cProfile統合+次ステップ計画 | dm-signal | 04-17 | Phase 4設計書をv3.0三面作戦の完了状態へ同期し、C |
| cmd_2021 | Phase 4 C1後Render本番計測 — 新ベースライン確定+self time分析 | dm-signal | 04-17 | C1をmainへmerge(PR #12)してRender本 |
| cmd_2022 | Phase 4締め括り — 設計書v3.1最終更新+研究日誌Phase 34追記+成果サマリ | dm-signal | 04-17 | Phase 4設計書にcmd_2021の実測値(842.90 |
| cmd_2024 | L3選出(正確版) — 2体EWプール861通り+3体EWプール10150通りから3目的×Top1=6体 | dm-signal | 04-17 | 2体/3体EWプールからWF α 3目的のTop1候補6体を |
| cmd_2025 | L3秘奥義6体 本番登録 — フォルダー作成+FoF登録+hide+fullrecalculate+パリティ | dm-signal | 04-17 | 秘奥義6体の本番登録・folder hide・fullrec |
| cmd_2026 | ⑤奥義-ASS忍法 リネーム+フォルダー整理 — 21体のPF名変更+新フォルダー作成+移動 | dm-signal | 04-18 | 奥義ALMシン21体を奥義-ASS-{}形式へ改名し、新規フ |
| cmd_2027 | ①奥義-SSS忍法 リネーム+フォルダー整理 — 21体のPF名変更+新フォルダー作成+移動 | dm-signal | 04-18 | 奥義-シン忍法フォルダーとplain奥義21体を奥義-SSS |
| cmd_2028 | p̄バッチ実行 — 全active PFの劣化指標+p̄一括再計算 | dm-signal | 04-18 | 本番 deterioration-batch を実行し、秘奥 |
| cmd_2029 | 偵察 — 全184PFのp̄/Z統計量分布調査+q̄(好調指標)設計材料 | dm-signal | 04-18 | 184 active PFのp_bar+Z(6/12/24) |
| cmd_2030 | 研究 — ルックバック期間別IC分析(1M-12M) — 特徴量としてのモメンタム効果量 | dm-signal | 04-18 | 本番 monthly_return_open を用いて ac |
| cmd_2031 | 研究 — L3モメンタムローテーション全量バックテスト(LB 1-12M × Top 1-42 = 504通り) | dm-signal | 04-18 | L2奥義42体(ASS21+SSS21)の月次リターンを本番 |
| cmd_2032 | 偵察 — L3秘奥義6体パフォーマンス取得+cmd_2031モメンタムBestとの比較 | dm-signal | 04-18 | 秘奥義6体EWとcmd_2031主要4パターンの同条件比較を |
| cmd_2033 | CoDD改善バッチ6-A — insight_write.sh + gate_shogun_memory.sh + gate_skill_quality.sh | infra | 04-18 | 3本のCoDD改善を完了。insight_write 117 |
| cmd_2036 | CoDD改善バッチ7-B — lesson_write.sh + sync_lessons.sh + inbox_write.sh(再) | infra | 04-18 | lesson_write/sync_lessons/inbo |
| cmd_2035 | CoDD改善バッチ7-A — cmd_save.sh(再) + ninja_done.sh(再) + shutsujin_departure.sh(再) | infra | 04-18 | cmd_save.sh 1.06s→0.98s、ninja_ |
| cmd_2038 | CoDD改善バッチ8-B — gate_report_format.sh + yaml_field_set.sh + gate_pd_sync.sh | infra | 04-18 | gate_report_format/yaml_field_ |
| cmd_2037 | CoDD改善バッチ8-A — gate_karo_startup.sh(再) + gate_gunshi_cs_checklist.sh + gate_field_get.sh | infra | 04-18 | gate_karo_startup.sh・gate_guns |
| cmd_2039 | CoDD改善バッチ9-A — stop-lint-gate.sh(再) + gate_recalculate_completeness.sh(再) + git-pre-commit.sh | infra | 04-18 | stop-lint-gate を status v2+awk |
| cmd_2048 | CoDD改善バッチ13-B — mark_no_learning.sh + log_terminal_input.sh + statusline.sh | infra | 04-18 | infra小物3本を高速化し、mark_no_learnin |
| cmd_2046 | CoDD改善バッチ12-B — cmd_quality_log.sh + task_deploy.sh + log_terminal_response.sh | infra | 04-18 | cmd_quality_log.sh(26ms→~11ms, |
| cmd_2043 | CoDD改善バッチ11-A — lesson_harvest.sh(再) + post_recalculate_checks.sh(再) + model_switch_preflight.sh(再) | infra | 04-18 | lesson_harvest/post_recalculat |
| cmd_2045 | CoDD改善バッチ12-A — gate_report_autofix.sh + gate_dc_duplicate.sh + gate_cmd_state.sh | infra | 04-18 | gate_report_autofix/gate_dc_du |
| cmd_2049 | CoDD改善バッチ14-A — session_start_inject.sh + prompt_state_inject.sh + session_end_clear_check.sh | infra | 04-18 | session系hook 3本を高速化し、session_s |
| cmd_2047 | CoDD改善バッチ13-A — gate_diagnose_check.sh + gate_silent_fallback.sh + gate_mcp_access.sh | infra | 04-18 | gate_diagnose_check/silent_fal |
| cmd_2050 | CoDD改善バッチ14-B — bash_state_hook.sh + test_result_guard.sh + pre-write-report-deny.sh | infra | 04-18 | bash_state_hook.sh(36ms→~16ms, |
| cmd_2052 | CoDD改善バッチ15-B — gate_recalculate_completeness.sh(再々) + lesson_write.sh(再) + shutsujin_departure.sh(再々) | infra | 04-18 | 3本のスクリプトをCoDD再々/再改善完了。gate_rec |
| cmd_2044 | CoDD改善バッチ11-B — archive_completed.sh(再) + report_merge.sh(再) + parity_check.sh(再) | infra | 04-18 | archive_completed.sh(783ms→550 |
| cmd_2057 | CoDD spec補完(5/8) — gate_cmd_state.sh + bash_state_hook.sh + test_result_guard.sh | infra | 04-18 | CoDD spec 3本作成(gate_cmd_state/ |
| cmd_2056 | CoDD spec補完(4/8) — gate_mcp_access.sh + gate_report_autofix.sh + gate_dc_duplicate.sh | infra | 04-18 | gate_mcp_access/gate_report_au |
| cmd_2058 | CoDD spec補完(6/8) — pre-write-report-deny.sh + cmd_quality_log.sh + task_deploy.sh | infra | 04-18 | CoDD spec補完(6/8)完了。3本全specをdoc |
| cmd_2053 | CoDD spec補完+悪化revert — stop-lint-gate revert + spec省略21件の正規CoDDやり直し(1/8) | infra | 04-18 | cmd_2053 の CoDD 正規化を実施し、3本の sp |
| cmd_2054 | CoDD spec補完(2/8) — parity_check.sh + gate_recalculate_completeness.sh + lesson_write.sh | infra | 04-18 | cmd_2054 の対象3本について CoDD spec を |
| cmd_2055 | CoDD spec補完(3/8) — shutsujin_departure.sh + gate_diagnose_check.sh + gate_silent_fallback.sh | infra | 04-18 | CoDD spec補完3本完了。shutsujin_depa |
| cmd_2060 | CoDD spec補完(8/8) — inbox_mark_read.sh + 悪化防止gate追加 | infra | 04-18 | AC1: inbox_mark_read.sh CoDD s |
| cmd_2059 | CoDD spec補完(7/8) — log_terminal_response.sh + agent_config.sh + field_get.sh | infra | 04-18 | cmd_2059対象3本のCoDD spec補完は既に co |
| cmd_2062 | CoDD正規改善(忍者hook B) — pre-write-edit-combined.sh + post-write-edit-combined.sh + pre-write-read-tracker.sh | infra | 04-18 | write/edit/read系 hook 3本を正規CoD |
| cmd_2064 | CoDD正規改善(忍者通知) — report_field_set.sh(再) + inbox_write.sh(再) | infra | 04-18 | report_field_set.sh+inbox_writ |
| cmd_2063 | CoDD正規改善(忍者完了処理) — ninja_done.sh(再) + gate_report_format.sh(再) + post-search-completeness-guard.sh | infra | 04-18 | 3スクリプトCoDD正規改善完了。gate_report_f |
| cmd_2061 | CoDD正規改善(忍者hook A) — stop-lint-gate.sh + pre-bash-combined.sh + post-bash-combined.sh | infra | 04-18 | hook A 3本を正規 CoDD で再評価し、Before |
| cmd_2065 | stop-lint-gate.sh L3診断推論改善 — Session State付き正規CoDD(失敗履歴注入) | infra | 04-18 | stop-lint-gate.sh を L3診断推論 + S |
| cmd_2051 | CoDD改善バッチ15-A — cmd_save.sh(再々) + stop-lint-gate.sh(再々) + gate_karo_startup.sh(再々) | infra | 04-18 | cmd_2051 は部分完了。cmd_save.sh の w |
| cmd_2067 | 研究 — CoDD #5深堀り+本家リポジトリ分析 — 我が軍への応用拡張 | infra | 04-18 | CoDD #5記事と codd-dev 公開実装を深掘りし、 |
| cmd_2069 | CoDD拡張 P5 — context/codd.md索引同期(GP-198/200/201現状反映) | infra | 04-18 | context/codd.md の索引を 2026-04-1 |
| cmd_2070 | CoDD拡張 P2 — DIVERGENT v2: 仮説一致検知 | infra | 04-18 | DIVERGENT判定を prior_attempts[] |
| cmd_2072 | CoDD拡張 P4 — partial failure surfacing: verdict第三状態(PASS_NO_IMPROVEMENT)導入 | infra | 04-18 | gate_report_format_main.pyにPAS |
| cmd_karo_ci_fix_571 | CI RED修正 — test_gate_ninja_workaround_rate #571(再修正) | infra | 04-18 | テスト571（gate_ninja_workaround_r |
| cmd_karo_ci_fix_2066 | CI RED修正 — test_assumption_invalidation(3件) + test_cmd_save(1件) + test_pending_decision(1件) | infra | 04-18 | 6件のCIテスト失敗を修正。gate_report_form |
| cmd_karo_ci_fix_568 | CI RED修正 — test_gate_ninja_workaround_rate #568 | infra | 04-18 | gate_ninja_workaround_rate.shの |
| cmd_2075 | CoDD正規再改善 R1-C — revert retry Bash hooks 3本(combined+search-guard) | infra | 04-18 | pre-bash-combined(jq→awk, guar |
| cmd_karo_ci_fix_ssh_sl | CI RED修正: SSH/SLテスト(999-1006)CI環境FAIL | infra | 04-18 | unit-tests workflow の再実行でも SSH |
| cmd_2077 | CoDD正規再改善 R1-E — cmd_save.sh(spec省略→正規CoDD再改善) | infra | 04-18 | scripts/cmd_save.sh正規CoDD再改善。b |
| cmd_2090 | CoDD正規再改善 R2-C — gate_vercel_phase.sh(spec省略→正規CoDD再改善) | infra | 04-18 | gate_vercel_phase.sh を正規CoDDで再 |
| cmd_2078 | CoDD正規再改善 R1-F — deploy_task.sh(spec省略→正規CoDD再改善) | infra | 04-18 | deploy_task.sh CoDD正規再改善完了。hot |
| cmd_2081 | CoDD正規再改善 R1-I — dashboard_auto_section.sh(spec省略→正規CoDD再改善) | infra | 04-18 | dashboard_auto_section.sh 3fix |
| cmd_karo_sleep_fix | ninja_monitor.sh sleep -5エラー修正 — codex confirm_waitデフォルト値追加 | infra | 04-18 | ninja_monitor.sh L3060付近: code |
| cmd_2088 | CoDD正規再改善 R2-A — gate_cycle_health.sh(spec省略→正規CoDD再改善) | infra | 04-18 | gate_cycle_health.sh CoDD正規再改善 |
| cmd_karo_ci_fix_cli_lookup | CI赤修正 — cli_lookup.sh _cli_lookup_profile_getが空行でbreak | infra | 04-18 | cli_lookup が profile間の空行で code |
| cmd_2084 | CoDD正規再改善 R1-L — report_merge.sh(spec省略→正規CoDD再改善) | infra | 04-18 | report_merge.sh を mawk優先化し、rea |
| cmd_2085 | CoDD正規再改善 R1-M — archive_completed.sh(spec省略→正規CoDD再改善) | infra | 04-18 | archive_completed.sh CoDD正規再改善 |
| cmd_2086 | CoDD正規再改善 R1-N — lesson_harvest.sh(spec省略→正規CoDD再改善) | infra | 04-18 | lesson_harvest.sh CoDD正規再改善: T |
| cmd_karo_precommit_yaml_dump_fp | pre-commit yaml.dumpチェックのfalse positive修正 | infra | 04-18 | pre-commitのyaml.dump誤検知をpre_ba |
| cmd_2080 | CoDD正規再改善 R1-H — inbox_write.sh(spec省略→正規CoDD再改善) | infra | 04-18 | inbox_write.sh write path を再改善 |
| cmd_2092 | CoDD正規再改善 R2-E — gate_workaround_rate.sh(spec省略→正規CoDD再改善) | infra | 04-18 | gate_workaround_rate.sh CoDD正規 |
| cmd_2091 | CoDD正規再改善 R2-D — gate_loop_health.sh(spec省略→正規CoDD再改善) | infra | 04-18 | gate_loop_health.sh CoDD正規再改善: |
| cmd_2093 | insightノイズ除去 — 生成時自動done化 + cleanカテゴリALERT除外 | infra | 04-18 | insightノイズの上流生成を停止。auto-done/S |
| cmd_2094 | 偵察+実装 — 他システム知識辞書 一次知識層作成 (6システム並列調査) | infra | 04-19 | AC4完了。知識辞書一次層作成 |
| cmd_karo_ci_fix_ga116 | CI修正 — test_cmd_save.bats 8テスト失敗修正 | infra | 04-19 | CI修正完了。abort_if_block_immediat |
| cmd_2098 | 実装 — AI開発知識辞書 鮮度チェックgate (CoDDドキュメント適用Phase1) | infra | 04-19 | 知識辞書verified_at鮮度gateを追加し、将軍st |
| cmd_2100 | 実装 — AI開発知識辞書 落とし穴+相互参照の補完 (全エントリ) | infra | 04-19 | ace/vercel/gsd に Pitfalls/Cros |
| cmd_karo_ci_fix_ga117 | CI修正 — test_cmd_save.bats 5テスト失敗(BLOCK集約副作用) | infra | 04-19 | cmd_save.shの2箇所を修正: (1)q5 elif |
| cmd_2102 | 改善 — gate_shogun_startup.sh CoDD再改善 (サブプロセス削減で1.3秒→目標0.5秒) | infra | 04-19 | gate_shogun_startup.sh を 1.28s |
| cmd_2104 | 偵察 — Android SSH入力消失の原因調査 (両面調査) | infra | 04-19 | Android/SSH入力消失を5観点で切り分け、P1=Cl |
| cmd_2105 | 実装 — 変更連動テスト実行 (git diff→対応テストのみ実行) | infra | 04-19 | scripts/test_select.sh を新規作成。g |
| cmd_2103 | 改善 — テストCoDD高速化第一弾 TOP5ファイル (32秒→目標10秒) | infra | 04-19 | — |
| cmd_2109 | 改善 — テストCoDD高速化 test_gate_shogun_startup.bats (6.8秒→目標3秒) | infra | 04-19 | Gate 4.5 python3 fast-path追加 + |
| cmd_2107 | 改善 — テストCoDD高速化 test_deploy_task_ac_version.bats (32秒→目標10秒) | infra | 04-19 | AC4完了: test_deploy_task_ac_ver |
| cmd_2111 | 改善 — テストCoDD高速化 test_stop_check_inbox.bats (6.2秒→目標3秒) | infra | 04-19 | test_stop_check_inbox.bats 46. |
| cmd_2113 | 改善 — テストCoDD高速化 test_cli_adapter.bats (4.6秒→目標2秒) | infra | 04-19 | test_cli_adapter.bats の fixtur |
| cmd_2108 | 改善 — テストCoDD高速化 test_deploy_task_template_generation.bats (9.8秒→目標4秒) | infra | 04-19 | deploy_task template generatio |
| cmd_2116 | 改善 — テストCoDD高速化 test_build_system.bats (3.6秒→目標1.5秒) | infra | 04-19 | test_build_system.bats を37.6%高 |
| cmd_karo_pane_lookup_fix | pane_lookup.sh lazy init修正 — deploy_task.sh pane解決障害の真因修正 | infra | 04-19 | cmd_karo_pane_lookup_fix は com |
| cmd_2115 | 改善 — テストCoDD高速化 test_cmd_save.bats (4.2秒→目標2秒) | infra | 04-19 | test_cmd_save.bats の CMD_BLOCK |
| cmd_2112 | 改善 — テストCoDD高速化 test_deploy_task_lifecycle.bats (4.7秒→目標2秒) | infra | 04-19 | before 7.104s → after 4.134s ( |
| cmd_2122 | 強化(家老) — deploy_task.sh タスク明瞭性チェック追加 (配備前検証) | infra | 04-19 | HEAD上でcmd_2122要件が既に実装済みと確認。dep |
| cmd_2127 | 強化 — 軍師LGTM収束判定 (ambiguity_points 0件をLGTM条件に) | infra | 04-19 | instructions/gunshi.md のdraftレ |
| cmd_2128 | 強化 — 修行サイクルhold-outテスト設計 (gate過適合検出) | infra | 04-19 | context/training-cycle.md §27 |
| cmd_2124 | 強化(忍者) — gate_report_format binary_checks客観裏付け (git diff突合) | infra | 04-19 | gate_report_format_main.pyにbin |
| cmd_2123 | 強化(軍師) — karo_workaround_log.sh SG紐付けフィールド追加 (偽陰性計測) | infra | 04-19 | karo_workaround_log.shへ任意の第6引数 |
| cmd_2023 | L3選出 — 6パターン×3目的関数 WF-α Top1 候補リスト生成 | dm-signal | 04-19 | — |
| cmd_2130 | 強化 — 指示文書TDD (忍者task_clarity_scoreで指示品質を計測) | infra | 04-19 | deploy_task.shテンプレートにtask_clar |
| cmd_karo_ci_fix_lk084 | CI修正 — test_cmd_complete_gate_locking.bats bash -lc→bash -c (LK084) | infra | 04-19 | tests/unit/test_cmd_complete_g |
| cmd_2131 | 偵察(緊急) — FoF monthly_returns 0件の根因特定 | dm-signal | 04-19 | FoF monthly_returns 0件の主因は sig |
| cmd_2132 | 修正(緊急) — sync-standard FoF分離 + monthly_returns crash-safe化 | dm-signal | 04-19 | sync_standardの親FoF波及を止め、Monthl |
| cmd_2134 | 設計 — 3レジーム市場分析ページ CoDD設計書 | dm-signal | 04-19 | 3レジーム分析の spec と CoDD 設計文書 3 本を |
| cmd_2135 | 修正(緊急) — DM-Signal PR #15 コンフリクト解決+マージ+Renderデプロイ | dm-signal | 04-19 | PR #15 の2競合を解消し、FoF flush help |
| cmd_2137 | 設計 — 3レジーム市場分析 Frontend CoDD設計書 | dm-signal | 04-19 | Regime analysis frontend向けのspe |
| cmd_2138 | 実装 — 3レジーム市場分析 Frontend (チャート+テーブル+API連携) | dm-signal | 04-19 | MetricsページをRegime Analysis表示へ切 |
| cmd_2140 | 修正 — cmd_2138 frontend変更revert + 本番スクリーンショット撮影 | dm-signal | 04-19 | frontend 3ファイルを origin/main 一致 |
| cmd_2142 | CoDD最適化 — run_077_bunshin.py (GS分身忍法) | dm-signal | 04-20 | run_077_bunshin.py の serial ho |
| cmd_2143 | CoDD最適化 — run_077_kasoku_diff.py (GS加速diff忍法) | dm-signal | 04-20 | run_077_kasoku_diff.py に month |
| cmd_2146 | CoDD最適化 — run_077_nukimi.py (GS抜き身忍法) | dm-signal | 04-20 | run_077_nukimi.py CoDD再最適化完了。s |
| cmd_2144 | CoDD最適化 — run_077_kasoku_ratio.py (GS加速ratio忍法) | dm-signal | 04-20 | run_077_kasoku_ratio.py の simu |
| cmd_2149 | CoDD最適化 — champion_selector.py (チャンピオン選出) | dm-signal | 04-20 | champion_selector.py のCSV fall |
| cmd_2151 | CoDD最適化 — cmd_1947_l3_ew_combo_stability.py (2体EW安定性) | dm-signal | 04-20 | cmd_1947をcache-first fallback+ |
| cmd_2152 | CoDD最適化 — cmd_1934_l3_threebody_stability.py (3体EW安定性) | dm-signal | 04-20 | cmd_1934_l3_threebody_stabilit |
| cmd_karo_ci_fix_ga135 | CI修正 — TG-T002テスト失敗(SG10 AC_SECTIONインデント検出) | infra | 04-20 | check_research_tool_growth_ac |
| cmd_2157 | 強化 — cmd_save.sh assumptions全cmd必須化(CMD品質原理的解決) | infra | 04-20 | cmd_save.shのassumptions必須チェック閾 |
| cmd_2158 | 強化 — cmd_save.sh 1cmd毎ゲート強制(前回cmd未昇格ならBLOCK) | infra | 04-20 | cmd_save.sh に Check 1.6 を追加: P |
| cmd_2159 | 強化 — cmd_save.sh BLOCK/WARN学習ループ強制(diagnosis質検査+WARN累計昇格) | infra | 04-20 | diagnosis質検査(Check 3.5)とWARN累計 |
| cmd_2160 | 強化 — cmd_save.sh environment_change強制(BLOCK→環境埋込の免疫系完成) | infra | 04-20 | BLOCK後の再PASS時にenvironment_chan |
| cmd_2161 | 強化 — gate_report_format 忍者BLOCK学習ループ(同一パターンN回→テンプレート自動改善) | infra | 04-20 | gate_report_formatの反復BLOCK学習ルー |
| cmd_2162 | 修正 — deploy_task.sh target_path転写漏れ恒久修正 | infra | 04-20 | deploy_task.shのcmd解決経路へtarget_ |
| cmd_2163 | 強化 — LK007環境埋込: workaroundパターン3件累積で構造的解決cmd自動起票催促 | infra | 04-20 | gate_karo_startup.sh に同カテゴリwor |
| cmd_karo_ci_fix_ga137 | CI修正 — cmd_save系bats 16件FAIL(cmd_2157-2160新フィールド未対応) | infra | 04-20 | cmd_save系batsフィクスチャをassumption |
| cmd_2166 | 修正 — cmd_save.sh バンドル定義修正: 変更対象(target_path+command)のみスキャン | infra | 04-20 | collect_primary_cmd_targetsをta |
| cmd_2164 | 強化 — 忍者BLOCK学習ループ汎用化: 全BLOCKパターン自動学習→テンプレートprefill | infra | 04-20 | gate_report_format学習ループを汎化し、pr |
| cmd_2167 | 研究 — WF L0四神24体作成: shin_shijin_l1 GS 4CSV × WFエンジン → シン12体+ALM12体チャンピオン選出 | dm-signal | 04-20 | AC1-AC4完了。shin_shijin_l1 の 4 C |
| cmd_2169 | 修正 — cmd_save.sh ���ンドル除外リストにoutputs/とcontext/を追加(非変更パス誤検出) | infra | 04-20 | scripts/cmd_save.shのL213-220 a |
| cmd_2168 | 修正 — cmd_save.sh Check 18 GS誤検出修正: outputs/grid_searchパスをGS実行と判定しない | infra | 04-20 | cmd_save.shのGS検出を出力CSVパスでは反応しな |
| cmd_2170 | 研究 — WF L1準備: WF四神BB月次リターンCSV抽出 + universe YAML 2本作成 | dm-signal | 04-20 | WFシン12体/月次CSV、WF ALM12体/月次CSV、 |
| cmd_2171 | 修正 — cmd_save.sh バンドル検出: target_pathとcommandの重複パスを除外(dedup) | infra | 04-20 | collect_primary_cmd_targetsでta |
| cmd_2172 | 修正 — cmd_save.sh Check 18 WF誤検出修正: WFエンジンを使わないcmdでWF WARN発火しない | infra | 04-20 | WF検出前にWF四神とWF選別を説明ラベルとして無害化し、w |
| cmd_2175 | 研究 — WF L1 WF-AS忍法21体: WF ALM四神BBで忍法GS 7本実行 + WFα選出 | dm-signal | 04-20 | WF ALM四神BBで忍法GS 7本実行(全rc=0)・WF |
| cmd_2173 | 強化 — cmd_save.sh environment_change構造化+自動検証: 約束の履行をBLOCKで強制 | infra | 04-20 | environment_change が type=...; |
| cmd_2176 | L1でWFα選出が逆効果(2勝19敗)だった。WF四神BB(L0改善済み)はそのまま活かし、忍法チャンピオン選出だけ事後選出に戻す。WFα選出(cmd_2174)との比較で、どの選出方式が有効かを判定する材料を得る | dm-signal | 04-20 | cmd_2174 GS成果物へ champion_selec |
| cmd_2178 | L2奥義のBBを準備する。cmd_2176(SS事後21体)+cmd_2177(AS事後21体)のチャンピオンpattern_idをL1 GS月次CSVから抽出し、L2用BB月次リターンCSV+universe YAMLを作成する。cmd_2170(L0→L1準備)と同構造 | dm-signal | 04-20 | L2 WF universe準備完了。SS/AS月次CSV各 |
| cmd_2129 | 強化 — CTX消費率による忍者タスク負荷検出 (tool_uses質的解釈の代替) | infra | 04-20 | GATE CLEAR時にCTX%をgate_metrics. |
| cmd_2179 | L2奥義SS系統。cmd_2178で作成したSS 21体BBで忍法GS 7本→事後選出で21体(7忍法×3目的)を確定する。L0 WF四神+L1事後選出+L2事後選出の3層積み上げ | dm-signal | 04-20 | — |
| cmd_2180 | L2奥義AS系統。cmd_2178で作成したAS 21体BBで忍法GS 7本→事後選出で21体(7忍法×3目的)を確定する。cmd_2179のAS版 | dm-signal | 04-20 | — |
| cmd_2181 | 道具磨き — run_077_kasoku_diff.py CoDDメモリ削減(8.5GB→3-4GB) | dm-signal | 04-20 | AC4: 全batsテスト(unit 1158件+top-l |
| cmd_2182 | 道具磨き — run_077_kasoku_ratio.py CoDDメモリ+速度一括最適化(kasoku_diff横展開) | dm-signal | 04-20 | run_077_kasoku_ratio.py は既に ka |
| cmd_2184 | 道具磨き — run_077_oikaze.py CoDDメモリ+速度一括最適化(kasoku_diff横展開) | dm-signal | 04-20 | run_077_oikaze.py に kasoku_dif |
| cmd_2183 | 道具磨き — run_077_nukimi.py CoDDメモリ+速度一括最適化(kasoku_diff横展開) | dm-signal | 04-20 | run_077_nukimi.py に PatternSpe |
| cmd_2187 | 道具磨き — run_077_bunshin.py CoDDメモリ+速度一括最適化(kasoku_diff横展開) | dm-signal | 04-20 | run_077_bunshin.py に PatternSp |
| cmd_2185 | 道具磨き — run_077_kawarimi.py CoDDメモリ+速度一括最適化(kasoku_diff横展開) | dm-signal | 04-20 | run_077_kawarimi.py に kasoku_d |
| cmd_2186 | 道具磨き — run_077_yotsume.py CoDDメモリ+速度一括最適化(kasoku_diff横展開) | dm-signal | 04-20 | run_077_yotsume.py に kasoku_di |
| cmd_karo_ctx_reflux_2188 | context還流 — gs-speedup-knowledge.md にcmd_2181-2187成果反映 | dm-signal | 04-20 | context/gs-speedup-knowledge.m |
| cmd_karo_env_change_gate | karo_workaround_log.shにenvironment_change強制+grep検証を追加 | infra | 04-21 | karo_workaround_log.sh に --wa |
| cmd_karo_ci_fix_env_change | CI RED修正 — test_cmd_save_environment_change.bats 3件FAIL修正 | infra | 04-21 | environment_change系テスト4件の期待値を現 |
| cmd_karo_ci_fix_aggregation | CI RED修正 — test_cmd_save_block_aggregation.bats AC2期待値更新 | infra | 04-21 | cmd_save BLOCK集約テストの期待値を現行挙動へ更 |
| cmd_2189 | 研究 — WF L2 GS bunshin(SS系統): wf_l2_ss_21体でbunshin忍法GS実行 | dm-signal | 04-21 | wf_l2_ss_21ユニバースでbunshin GSをex |
| cmd_2190 | 研究 — WF L2 GS kasoku_diff(SS系統): wf_l2_ss_21体でkasoku_diff忍法GS実行 | dm-signal | 04-21 | wf_l2_ss_21ユニバースでkasoku_diff G |
| cmd_2191 | 研究 — WF L2 GS kasoku_ratio(SS系統): wf_l2_ss_21体でkasoku_ratio忍法GS実行 | dm-signal | 04-21 | wf_l2_ss_21ユニバースでkasoku_ratio |
| cmd_2192 | 研究 — WF L2 GS nukimi(SS系統): wf_l2_ss_21体でnukimi忍法GS実行 | dm-signal | 04-21 | wf_l2_ss_21ユニバースでnukimi GSをexi |
| cmd_2194 | 研究 — WF L2 GS oikaze(SS系統): wf_l2_ss_21体でoikaze忍法GS実行 | dm-signal | 04-21 | wf_l2_ss_21ユニバースでoikaze GSをexi |
| cmd_karo_auto_draft_review | deploy_task.shにdraftレビュー自動送信を追加 | infra | 04-21 | deploy_task.sh に draft review |
| cmd_2197 | 修正 — run_077_kawarimi.py verify部分のsequential/batch整合バグ修正 | dm-signal | 04-21 | AC1/AC2はPASS。AC3はcmd_2196基準CSV |
| cmd_2198 | 研究 — WF L2 SS系統 champion_selector統合: 7忍法GSからchampion事後選出 | dm-signal | 04-21 | wf_l2_ss の 7忍法 monthly/cache を |
| cmd_karo_ci_fix_draft_review | CI RED修正 — test deploy draft_review送信テスト修正 | infra | 04-21 | draft review CI失敗の根因を特定し、並列テスト |
| cmd_2199 | 研究 — WF L2 GS bunshin(AS系統): wf_l2_as_21体でbunshin忍法GS実行 | dm-signal | 04-21 | WF L2 AS bunshin GSを完了。exit 0 |
| cmd_2200 | 研究 — WF L2 GS kasoku_diff(AS系統): wf_l2_as_21体でkasoku_diff忍法GS実行 | dm-signal | 04-21 | WF L2 AS 21体universeでkasoku_di |
| cmd_2201 | 研究 — WF L2 GS kasoku_ratio(AS系統): wf_l2_as_21体でkasoku_ratio忍法GS実行 | dm-signal | 04-21 | WF L2 AS 21体universeでkasoku_ra |
| cmd_2203 | 研究 — WF L2 GS kawarimi(AS系統): wf_l2_as_21体でkawarimi忍法GS実行 | dm-signal | 04-21 | WF L2 AS 21体universeでkawarimi |
| cmd_2205 | 研究 — WF L2 GS yotsume(AS系統): wf_l2_as_21体でyotsume忍法GS実行 | dm-signal | 04-21 | WF L2 AS 21体universeでyotsume G |
| cmd_2207 | 研究 — WF L2 AS系統 champion_selector統合: 7忍法GSからchampion事後選出 | dm-signal | 04-21 | wf_l2_as 配下の7忍法 monthly CSV/ca |
| cmd_karo_auto_review_gate | inbox_write.shにreport_review自動送信+GATE自動実行を追加 | infra | 04-21 | report_received→report_review自 |
| cmd_karo_self_gate_template | deploy_task.shのreportテンプレートにself_gate_check 4項目を自動注入 | infra | 04-21 | deploy_task.shの報告テンプレートへself_g |
| cmd_karo_lk086_update | LK086+karo.md更新 — report_review自動化に伴う3アクション→2アクションへ | infra | 04-21 | LK086を2アクション運用へ更新し、AC2はinstruc |
| cmd_2209 | 修正 — cmd_save.shブロック抽出awkが非数字cmd_idで境界検出失敗 | infra | 04-21 | cmd_save.sh の cmd 境界判定を非数字 cmd |
| cmd_karo_gate_wait | cmd_complete_gate.sh GATE CLEARパスにwait追加 — background子プロセス完走保証 | infra | 04-21 | cmd_complete_gate の GATE CLEAR |
| cmd_2208 | 修正 — cmd_save.sh WARN記録にnotes欠落(FP率計測不能) | infra | 04-21 | cmd_2209で先行反映済みのWARN経路統一を現物確認し |
| cmd_karo_pipeline_verify | 検証 — 自動パイプライン全段動作確認(draftレビュー→report_review→GATE→bulletin) | infra | 04-21 | context/senkyoku-log.md に cmd_ |
| cmd_2211 | 偵察 — WF四神の本番fullrecalculate計算可能性調査 | dm-signal | 04-21 | 既存四神の保存実体を特定。シン四神pipeline_conf |
