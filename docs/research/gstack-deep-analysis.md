# gstack深掘り偵察 統合レポート

<!-- cmd_931 統合 | 6報告統合: sasuke(A), kirimaru(B), kagemaru(C), saizo(E), kotaro(F), tobisaru(G) -->
<!-- 前回分析: docs/research/gstack-analysis.md §2 の12テクニックは除外済み -->
<!-- 統合者: tobisaru | 2026-03-14 -->

## §1 統合サマリ

6名が異なる観点でgstack全体を精読。前回分析の12テクニック（Suppressions/停止条件二分法/推薦先行+WHY/モードコミットメント/反復STOP/Priority Hierarchy/Engineering Preferences/名前をつけろ/並列実行明示/Temporal Interrogation/Dream State Mapping/Two-pass Review）を除外した結果、**64件の新規発見**を抽出。報告間重複は統合済み。

| 報告者 | 観点 | 生発見数 | 統合後 |
|--------|------|---------|--------|
| sasuke | /plan-ceo-review + /plan-eng-review | 10 | 10（うち3件は他報告と統合） |
| kirimaru | /review + /ship | 14 | 14（うち2件は他報告と統合） |
| kagemaru | /browse全ソース | 15 | 15（うち5件は他報告と統合） |
| saizo | プロンプト心理学+状態管理 | 10 | 10（うち5件は他報告と統合） |
| kotaro | 品質保証+差分 | 30+ | 7独自（残りは上記と統合）+差分20+10 |
| tobisaru | エラーハンドリング+設計哲学 | 27 | 12独自（残りは上記と統合） |

適用ROI最高の知見: **Deferred Work Discipline**（全cmd影響・低コスト）、**wrapError AI行動指示変換**（全gate影響）、**Named Invariants**（全instruction影響）。

---

## §2 全発見一覧

### G1: レビュー前準備（3件）

| ID | 発見 | 内容 | 出典 | コスト | 適用先 |
|----|------|------|------|--------|--------|
| G1-1 | 事前システム監査 | レビュー開始前に`git log`/`git diff --stat`/`git stash list`/TODO grep/最近変更ファイル一覧を実行し、CLAUDE.md+TODOS.md+architecture docsを読む。戦況把握を独立工程化 | sasuke: plan-ceo-review:56-70 | 中 | 偵察/レビュー開始手順 |
| G1-2 | 再発領域増幅レビュー | git logから過去のrevert/refactorを検出し、同一領域を厳格度1段上げてレビュー | sasuke: plan-ceo-review:72-73, plan-eng-review:151-152 | 中 | task配備時に差戻し履歴チェック |
| G1-3 | Taste Calibration | レビュー前に良い実装例2-3件+悪い例1-2件を抽出し、以後のstyle referenceにする | sasuke: plan-ceo-review:75-77 | 低 | 大型設計レビュー |

### G2: レビュー観点拡張（6件）

| ID | 発見 | 内容 | 出典 | コスト | 適用先 |
|----|------|------|------|--------|--------|
| G2-1 | Shadow Paths 4分岐 | 全データフローをhappy/nil/empty/upstream errorの4経路で追跡。validate/transform/persist/outputの各ノードにshadow pathをぶら下げる | sasuke: plan-ceo-review:29-31,209-219 | 中 | 偵察findings |
| G2-2 | Interaction Edge Matrix + Hostile QA | UI/非同期/一覧/BGジョブごとにdouble-click/navigate-away/stale state/duplicate runなどのedge case表。さらにhostile QA engineer視点の破壊テスト | sasuke: plan-ceo-review:32,221-239,282-285 | 低 | recon edge_cases |
| G2-3 | Error & Rescue Registry | method→failure→exception と exception→rescued/action/user seesの二段表。RESCUED=N, TEST=N, USER SEES=Silentの組合せ=CRITICAL GAP | sasuke+kotaro: plan-ceo-review:183-188,374-382 | 高 | 高リスク偵察 |
| G2-4 | レビュー観点の章分離 | security/observability/deployment/long-term trajectoryをarchitectureに埋め込まず独立章に昇格。「Observability is scope, not afterthought」 | sasuke: plan-ceo-review:33,191-203,305-348 | 中 | 家老レビューcmd設計 |
| G2-5 | 追加レビュー観点4種 | Race Conditions & Concurrency / Crypto & Entropy / Time Window Safety / Type Coercion at Boundaries。Two-passの具体カテゴリ詳細 | kirimaru: review/checklist.md:41-89 | 中 | 偵察・レビュー観点ライブラリ |
| G2-6 | CEO vs Eng多段階レビュー | 3フェーズ順序: CEO(What正しい問題か?)→Eng(Howアーキテクチャ)→Review(Break壊せるか?)。前フェーズ出力が次の入力 | kotaro: 品質保証分析 | 低 | cmd分解設計 |

### G3: レビュー出力規律（5件）

| ID | 発見 | 内容 | 出典 | コスト | 適用先 |
|----|------|------|------|--------|--------|
| G3-1 | Checklist外部ファイル分離 | チェックリストをSKILL.mdから外部mdに分離。Read失敗→STOP強制。更新がスキル本体と独立。11カテゴリ・2パス | kirimaru+kotaro: review/checklist.md, review/SKILL.md:31-35 | 低 | 品質4要件を外部md化 |
| G3-2 | Read-only Default | reviewは読取専用がデフォルト。critical issueに対しユーザーが"Fix it now"を選んだ時だけ編集許可 | kirimaru: review/SKILL.md:64-78 | 低 | 忍者review原則強化 |
| G3-3 | A/B/C Triage | critical issueごとにA fix / B acknowledge / C false positiveの3択。PASS/FAILの二値と「例外承認」の区別が明確 | kirimaru: review/SKILL.md:64-69 | 低 | 家老WAIVE判断 |
| G3-4 | 1 issue = 2 lines | 問題文+fix案を分離した超簡潔出力契約。「Be terse」 | kirimaru: review/checklist.md:11-27 | 低 | 偵察報告evidence |
| G3-5 | FP/FN対策（Suppressions外） | FP: 「Full diff読んでからコメント」「Only flag real problems」。FN: git logで再発エリア検出→重点レビュー | kirimaru+kotaro: review/SKILL.md:39-48 | 低 | 家老レビューにFP skip追加 |

### G4: スコープ・延期管理（4件）

| ID | 発見 | 内容 | 出典 | コスト | 適用先 |
|----|------|------|------|--------|--------|
| G4-1 | Deferred Work Discipline | NOT in scope / What already exists / TODO context schema / Unresolved decisionsを必須出力化。先送り理由を構造的に保存 | sasuke+saizo+kotaro: plan-ceo-review:35,365-400, plan-eng-review:107-126 | 低 | 偵察報告末尾 |
| G4-2 | BIG/SMALL CHANGE圧縮モード | BIG CHANGEとSMALL CHANGEを分け、後者のみ「各章1件厳選・最後に一括」の例外。圧縮時の質問粒度を明示的に切替 | sasuke: plan-eng-review:43-48,91-103 | 低 | review/recon cmd |
| G4-3 | Completion Summary | 大型偵察・実装の末尾に統合サマリテーブルを義務化 | kotaro: 品質保証分析 | 低 | 大型偵察報告 |
| G4-4 | Stale Diagram Audit | 変更ファイル内のASCII図を同一commitで更新義務。touched files内のstale diagramsを監査 | sasuke+kotaro: plan-eng-review:30-33,128-129, plan-ceo-review:49-50 | 低 | 図を含むファイル変更時 |

### G5: プロンプト心理（4件）

| ID | 発見 | 内容 | 出典 | コスト | 適用先 |
|----|------|------|------|--------|--------|
| G5-1 | Named Invariants | 長手順を覚えやすい短名の原則へ圧縮。"Zero silent failures" / "Every error has a name" / "Data flows have shadow paths"。Prime Directives 9箇条 | saizo+kotaro: plan-ceo-review:28-37 | 低 | 全instruction |
| G5-2 | Section Gate付き単一意思決定 | 各セクションで「1 issue = 1 AskUserQuestion」「解決まで次節へ進むな」を強制。推薦先行+WHYの一段深い実行制御 | saizo: plan-eng-review:62-103, plan-ceo-review:135-204 | 中 | 殿判断事項 |
| G5-3 | Incremental Evidence Capture | issueを見つけた瞬間にbefore/result screenshot+snapshot diffまで即記録。後でまとめ書きしない | saizo: qa/SKILL.md:146-172,269-277 | 低 | 偵察・レビュー報告 |
| G5-4 | LLM Prompt Eval Scope接続 | prompt/LLM変更時にCLAUDE.mdのfile patternを起点にeval suite・追加ケース・baseline比較を列挙。テスト範囲の起点を設定ファイルに寄せる | sasuke: plan-eng-review:75-80 | 中 | LLM関連PJ |

### G6: リリースワークフロー（8件）

| ID | 発見 | 内容 | 出典 | コスト | 適用先 |
|----|------|------|------|--------|--------|
| G6-1 | Merge origin/main before test | テスト前に必ずorigin/mainを取り込み、最新main上で検証 | kirimaru: ship/SKILL.md:46-57 | 中 | push前review task |
| G6-2 | Diff-based Conditional Eval | prompt-related diffの時だけeval mandatory。changed filesからgate/test自動注入 | kirimaru: ship/SKILL.md:60-140 | 高 | deploy_task拡張 |
| G6-3 | Re-review Loop | review中にblocking fix→commit→STOP→再度/ship。曖昧に続行せず修正task再配備→再review | kirimaru: ship/SKILL.md:144-170 | 低 | 家老レビュー |
| G6-4 | Version Auto-decide | diff sizeとchange typeで自動決定。MICRO/PATCHは自動、MINOR/MAJORだけ質問 | kirimaru+tobisaru: ship/SKILL.md:174-190 | 中 | 軽微→自動、節目→上位確認 |
| G6-5 | CHANGELOG Full-commit Reconstruction | branch上の全commit+全diffからrelease noteを再構成。断片加筆ではなく最終統合サマリ | kirimaru: ship/SKILL.md:193-212 | 中 | dashboard/chronicle更新 |
| G6-6 | Bisectable Commit Grouping | commitをbisectable chunksに分ける明確なgrouping rule。1 logical unit + dependent test同梱 | kirimaru+tobisaru: ship/SKILL.md:215-249 | 中 | impl task commit指示 |
| G6-7 | PR Body Mandatory Sections | Summary / Pre-Landing Review / Eval Results / Test Plan必須化。最終出力=PR URL | kirimaru: ship/SKILL.md:263-300 | 低 | report YAML分離 |
| G6-8 | Ship内蔵8ゲート+Eval 3段Tier | 8ゲート: branch check/merge/dual parallel test/eval conditional/pre-landing review/version auto-decide/bisectable commit/no force push。Eval: fast(Haiku$0.07)/standard(Sonnet$0.37)/full(Opus$1.27) | kotaro: 品質保証分析 | 中 | gate tier概念導入 |

### G7: エラー・フォールバック設計（11件）

| ID | 発見 | 内容 | 出典 | コスト | 適用先 |
|----|------|------|------|--------|--------|
| G7-1 | wrapError (AI行動指示変換) | Playwright生エラーを「次にやるべきこと」付きメッセージに変換。TimeoutError→「Run snapshot for fresh refs」。エラーの受信者=AIエージェント | kagemaru+tobisaru+kotaro: server.ts:165-183 | 中 | gate出力にaction提案 |
| G7-2 | CLI自動復旧3段階リトライ | (1)state読込→PID生存→/health (2)401→token更新, ECONNREFUSED→再起動(1回) (3)stale削除→spawn→100msポーリング(最大8秒) | kagemaru+tobisaru: cli.ts:119-198 | 中 | CDP/inbox_watcher復旧 |
| G7-3 | Token Mismatch Recovery | 401応答→state file再読込→tokenが変わっていたらリトライ。サーバー再起動時の競合状態ハンドル | tobisaru: cli.ts:159-166 | 低 | ntfy listener |
| G7-4 | Crash→Exit→Auto-restart哲学 | Chromium crash→process.exit(1)→CLI次回呼出で自動再起動。「自己修復するな。障害を隠すな。復旧は別レイヤーの責務」 | tobisaru: browser-manager.ts:7,47-52 | — | 設計原則参照 |
| G7-5 | Context Recreation 3段フォールバック | (1)完全復元(cookies/storage/URLs保存→再作成→復元) (2)個別失敗は無視 (3)全体失敗→クリーンスレート+明示メッセージ | kagemaru+saizo+tobisaru: browser-manager.ts:254-370 | 中 | /clear Recovery |
| G7-6 | SQLite Copy-on-Lock | SQLITE_BUSY→/tmpにDB+WAL+SHMコピー→readonlyで開く→close時自動削除 | saizo+tobisaru: cookie-import-browser.ts:226-272 | 中 | YAML flock代替読取 |
| G7-7 | Chain Error封じ込め | チェーン実行中の個別コマンドエラーをインライン報告。全体を中断しない。部分成功許容 | tobisaru: meta-commands.ts:170-182 | 低 | deploy_task複数注入 |
| G7-8 | Health Check = evaluate + race timeout | isConnected()だけでなくpage.evaluate('1')を2秒レースで実行。ゾンビ状態を検出 | tobisaru: browser-manager.ts:80-93 | 低 | ninja_monitor STALL検知 |
| G7-9 | Graceful Shutdown冪等性 | isShuttingDownガードで二重shutdown防止。シグナル多重到着を前提にした設計 | tobisaru: server.ts:226-241 | 低 | inbox_watcher trap |
| G7-10 | Buffer Flush非致命哲学 | ディスクflush失敗をcatchして無視。データはメモリに残存。永続化失敗≠機能停止 | tobisaru: server.ts:84-88 | — | 設計原則参照 |
| G7-11 | サーバー起動失敗時stderr読取 | 起動タイムアウトしたらstderrを読んでエラーメッセージに含める。「なぜ失敗したか」を伝える | tobisaru: cli.ts:106-117 | 低 | agent CLI起動失敗ntfy |

### G8: サーバー・インフラ設計（5件）

| ID | 発見 | 内容 | 出典 | コスト | 適用先 |
|----|------|------|------|--------|--------|
| G8-1 | State File方式ディスカバリ | 起動時にJSON(pid/port/token/startedAt)を/tmpに書込(0o600)。CLIは毎回読んで接続先決定。PID生存チェックで陳腐化検出 | kagemaru+saizo: server.ts:304-312, cli.ts:63-79 | 低 | CDP persistent daemon |
| G8-2 | Auth Token (randomUUID) | 毎回起動時にcrypto.randomUUID()生成→state fileに記録。CLI 401時にstate再読込→リトライ | kagemaru: server.ts:21 | 低 | CDP daemon認証 |
| G8-3 | CircularBuffer O(1)リングバッファ | 50,000エントリのリングバッファ。push=O(1)。totalAddedはclear後も保持(flush cursor用)。1秒ごとのasync disk flush+shutdown時final flush | kagemaru+saizo+tobisaru: buffers.ts:1-75 | 中 | CDP/monitorログ |
| G8-4 | Multi-instance (PORT計算) | CONDUCTOR_PORT - 45600 = BROWSE_PORT。サフィックスをstate/logに付加。複数セッション同時稼働 | kagemaru: server.ts:23-26 | 中 | CDP忍者別ポート割当 |
| G8-5 | Idle Timer自動シャットダウン | 30分アイドルで自動終了。1分間隔チェック | tobisaru: server.ts:94-106 | — | 我が軍はninja_monitorで実装済み |

### G9: ブラウザ固有（9件）

| ID | 発見 | 内容 | 出典 | コスト | 適用先 |
|----|------|------|------|--------|--------|
| G9-1 | Network Response後方マッチング | networkBufferを末尾から逆走査→URL一致+status未設定エントリにstatus/duration/size書込 | kagemaru: browser-manager.ts:421-451 | 中 | CDP Network処理 |
| G9-2 | Cursor-Interactive Scan -C | DOM全走査。cursor:pointer/onclick/tabindex>=0をARIAツリー外から検出。nth-child CSSパス生成。@c系ref | kagemaru: snapshot.ts:233-298 | 中 | CDP補完検出 |
| G9-3 | Cookie Import (Chromium暗号化復号) | Keychain→PBKDF2→AES-128-CBC。Chromium epoch変換。SQLite locked→ファイルコピー。Windows版はDPAPI別途必要 | kagemaru: cookie-import-browser.ts | 高 | auto-ops認証参考 |
| G9-4 | Cookie Picker Web UI | browseサーバー上認証なしWeb UI。2パネル。inflight制御。CORS同一ポート限定 | kagemaru: cookie-picker-routes.ts+cookie-picker-ui.ts | 高 | デバッグUI参考 |
| G9-5 | Sensitive Value Redaction | type→文字数のみ。cookie→値を****。Authorization等は****。password=[redacted] | kagemaru: write-commands.ts | 低 | CDP入力/Cookie設定 |
| G9-6 | Path Traversal防止 | ['/tmp',process.cwd()]チェック。resolved後startsWith+prefix collision防止。テスト済 | kagemaru+tobisaru: read-commands.ts:15-29 | 低 | CDPファイルI/O |
| G9-7 | Dialog Auto-Accept | alert/confirm/promptを自動受理。dialogバッファに記録。dismiss失敗は無視 | kagemaru+tobisaru: browser-manager.ts:382-403 | 低 | CDP dialogハンドラ |
| G9-8 | Ref-Baseline寿命分離 | refMapはnavigationで即invalidate、lastSnapshotはdiff baselineとして保持 | saizo: browser-manager.ts:33-42,346-379 | 中 | CDP ref管理 |
| G9-9 | Cross-session Baseline Artifacts | QAはbaseline.json、retroはprior JSON snapshotを前提に差分を主成果物化 | saizo: qa/SKILL.md:58-60,181-196 | 低 | CDP計測baseline |

### G10: 設計哲学（9件）

| ID | 発見 | 内容 | 出典 | コスト | 適用先 |
|----|------|------|------|--------|--------|
| G10-1 | スキル間依存関係マップ | /qa→/browse(バイナリ依存)。/ship→/review(checklist.md参照)。クロス依存が存在 | tobisaru: 全スキル横断 | — | context相互参照マッピング |
| G10-2 | 2段バイナリ発見 | (1)プロジェクトローカル→(2)グローバル(~/.claude/skills/)のフォールバック | tobisaru: 4つのSKILL.md | — | 参照のみ |
| G10-3 | CLAUDE.md極薄設計 | ビルドコマンド4行+構造ツリーのみ。全インテリジェンスはSKILL.mdに。「CLAUDE.md=ブートローダー、スキル=アプリケーション」 | tobisaru: CLAUDE.md | — | 肥大化防止原則の裏付け |
| G10-4 | Allowed-tools最小権限宣言 | 各スキルが使用ツールを明示宣言。/plan-*はRead+Grep+Glob+AskUserQuestionのみ | tobisaru: 全スキルfrontmatter | 低 | task YAML制約追加案 |
| G10-5 | Setupスマートリビルド | 4条件OR判定: バイナリ不在/source新しい/package.json更新/bun.lock更新。シンボリンクで全スキル同時更新 | tobisaru: setup script | 中 | skills登録自動化 |
| G10-6 | Dual SKILL.md | root SKILL.md=完全版、browse/SKILL.md=凝縮版。スキル単体 vs ツールキット一括の両立 | tobisaru: root vs subdirectory | — | 参照のみ |
| G10-7 | 共有データ構造は1つだけ | CircularBufferのみ共有。他は全てインライン。「共通化は最後の手段。重複は許容」 | tobisaru: buffers.ts | — | 設計原則参照 |
| G10-8 | 設定ファイルなし | .gstackrc等が一切なし。環境変数/CLIフラグ/ハードコードデフォルトのみ。convention over configuration | tobisaru: 全コードベース | — | 参照のみ（我が軍は規模上config必要） |
| G10-9 | Browse Server = マルチパーパスハブ | 同一ポートでCLIコマンド(認証あり)+Cookie Picker UI(認証なし、localhost限定) | tobisaru: server.ts | — | 1プロセス多用途設計 |

### G11: テスト設計（1件）

| ID | 発見 | 内容 | 出典 | コスト | 適用先 |
|----|------|------|------|--------|--------|
| G11-1 | BrowserManager直接呼出しテスト | HTTPサーバー経由せず関数直接呼出。afterAllでprocess.exit(500ms)ハング回避。fixture DB+モンキーパッチ。全コマンド+エラーパス+セキュリティ網羅。3ファイル203テスト15秒 | kagemaru+kotaro: commands.test.ts | — | CDPテスト設計参考 |

---

## §3 適用優先順位 TOP10

ROI = 効果の広さ × コストの低さ。全cmdに効く低コスト改善を最上位に配置。

| 順位 | ID | 発見 | 効果の広さ | コスト | ROI根拠 |
|------|-----|------|-----------|--------|---------|
| 1 | G4-1 | **Deferred Work Discipline** | 全cmd | 低 | NOT in scope / Unresolved decisions を偵察・実装報告に必須化。session跨ぎで「なぜ見送ったか」の消失を防止。テンプレート追記のみ |
| 2 | G7-1 | **wrapError (AI行動指示変換)** | 全gate/script | 中 | gate出力を「BLOCK/WARN/OK」から「BLOCK: 次にXXXせよ」形式に拡張。エージェントの自律判断精度向上 |
| 3 | G5-1 | **Named Invariants** | 全instruction | 低 | 長手順を短名原則にパック化。"Zero silent failures" "Shadow paths exist"。instruction忘却を構造的に抑制 |
| 4 | G3-1 | **Checklist外部ファイル分離** | 品質基盤 | 低 | 品質4要件チェックリストを外部md化。Read失敗→STOP強制。更新が本体と独立 |
| 5 | G3-3 | **A/B/C Triage** | 家老レビュー | 低 | Fix/Acknowledge/False Positiveの3択で「例外承認」と「FP判定」を明確に区別。判断の透明性向上 |
| 6 | G5-3 | **Incremental Evidence Capture** | 偵察・レビュー | 低 | 発見した瞬間に即記録。AC単位で逐次追記。記憶劣化・脚色を防止 |
| 7 | G8-1 | **State File方式ディスカバリ** | CDP daemon化 | 低 | JSON state file + PID生存チェック。CDP persistent daemon化の基盤技術。ninja_monitorからの監視も容易 |
| 8 | G3-2 | **Read-only Default** | 忍者discipline | 低 | review=読取専用がデフォルト。修正は別impl taskへ返す。既存運用に近いが明文化で強化 |
| 9 | G4-4 | **Stale Diagram Audit** | 図含むファイル | 低 | 変更ファイル内の図を「Still accurate?」で確認。図の腐敗=誤誘導を防止 |
| 10 | G2-1 | **Shadow Paths 4分岐** | 偵察品質 | 中 | happy/nil/empty/errorの4経路追跡をrecon findingsに追加。入力欠損・空配列系の落とし穴を構造的に検出 |

### 次点（11-15位）

| 順位 | ID | 発見 | コスト | 理由 |
|------|-----|------|--------|------|
| 11 | G1-1 | 事前システム監査 | 中 | 偵察前の戦況把握を定型化。重複調査を削減 |
| 12 | G6-3 | Re-review Loop | 低 | blocking fix→修正task再配備→再reviewの明示フロー |
| 13 | G4-3 | Completion Summary | 低 | 大型偵察報告末尾にサマリ義務化 |
| 14 | G7-8 | Health Check evaluate+race | 低 | ゾンビ状態検出でSTALL検知強化 |
| 15 | G10-4 | Allowed-tools最小権限 | 低 | task YAMLで忍者の行動範囲をスキルレベルで制約 |

---

## §4 逆差分（我が軍 vs gstack）

### 我が軍にありgstackにないもの（10項目）

| # | 能力 | 我が軍の実装 | gstackに不在の理由 |
|---|------|------------|-------------------|
| 1 | マルチエージェント並列 | 8忍者同時並列 | 1エージェント×6モード切替設計 |
| 2 | 永続状態管理 | YAML+dashboard+陣形図 | stateless設計（session間状態なし） |
| 3 | 教訓の組織蓄積 | lessons.yaml+MCP Memory | retro JSONは個人メトリクスのみ |
| 4 | Gate自動化インフラ | gate_*.sh+cmd_complete_gate | スキルプロンプト強度のみ依存 |
| 5 | Inbox通知システム | inbox_write.sh+inotifywait | 単一セッション、通知不要 |
| 6 | 破壊操作安全装置 | D001-D008 Tier 1-3 | 個人利用前提、安全装置なし |
| 7 | 偵察パターン（水平+垂直） | 万全偵察8名+GSD式4観点 | /plan-*は1エージェント |
| 8 | CTX管理自動化 | ninja_monitor idle→/clear | /browse idle timerのみ |
| 9 | GUI直接制御(CDP) | WSL2→PowerShell→Chrome CDP | Playwright headless（GUI不可） |
| 10 | PJ横断管理 | projects/*.yaml+config/projects.yaml | 単一リポジトリ特化 |

### gstackにあり我が軍にないもの（20項目）

| # | 能力 | gstack実装 | 適用可否 |
|---|------|-----------|---------|
| 1 | /qa (体系的QA) | 6フェーズ+Health Score+regression | 仙人構想で検討 |
| 2 | Cookie Import | macOS暗号化Cookie復号+Picker UI | auto-ops参考 |
| 3 | /retro (data-driven retro) | 14ステップ+team-aware+praise | chronicle→メトリクス転用可 |
| 4 | Conductor連携 | ワークスペース分離 | 不要（tmuxで実現済み） |
| 5 | Chain (バッチ実行) | 複数コマンド1 HTTP POST | CDP daemon化で実現 |
| 6 | Annotated Screenshots | overlay+refラベル | CDP拡張候補 |
| 7 | Element State Checks | visible/enabled/checked等7種 | CDP拡張候補 |
| 8 | Snapshot Diff | unified diff形式 | CDP baseline比較に転用 |
| 9 | Error & Rescue Map | failure mode表テンプレート | TOP10外だが高リスクcmdで有効 |
| 10 | Interaction Edge Matrix | edge case表テンプレート | G2-2で適用候補 |
| 11 | Prime Directives 9原則 | 短名原則パック | G5-1で適用候補 |
| 12 | NOT in scope | 必須出力 | G4-1で適用候補（TOP1） |
| 13 | Failure Modes Registry | failure mode登録 | 高リスク偵察で段階導入 |
| 14 | Stale Diagram Audit | 図の鮮度監査 | G4-4で適用候補 |
| 15 | Completion Summary | 統合サマリ義務 | G4-3で適用候補 |
| 16 | Security/Threat Model | 独立セキュリティ章 | G2-4で適用候補 |
| 17 | Observability Review | 独立監視レビュー | G2-4で適用候補 |
| 18 | Deployment Review | 独立配備レビュー | G2-4で適用候補 |
| 19 | Path Validation | safeDirs制約 | 我が軍はrealpathで対応済み |
| 20 | Dialog Auto-handling | 自動受理+バッファ記録 | CDP拡張候補 |

### 核心の差（更新）

前回分析の結論を維持・深化:

- **gstack = 個人プロダクティビティ最適化**。1エージェント×6モードで認知切替を最大化。プロンプトの洗練度は極めて高い。
- **将軍 = 組織の知識蓄積と並列実行**。10エージェント×永続状態で量的優位。ただしプロンプト技術はgstackに学ぶべき点が多い。

**今回の深掘りで判明した最大の知見**: gstackのプロンプト技術は§2の12テクニックだけでなく、レビュー/リリースワークフロー全体に体系的に組み込まれている。特に **Deferred Work Discipline**（先送り理由の構造的保存）と **wrapError**（エラー→AI行動指示変換）は、我が軍の全cmdに横断的に効く改善であり、+1点の複利として最もROIが高い。
