# CMD年代記
<!-- last_updated: 2026-06-11 cmd_3285 -->

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
| cmd_1301 | startup gate bash算術エラー修正 — grep -c || echo anti-pattern根絶 | infra | 03-23 | gate_shogun_startup.sh L101/L282の grep -c || echo anti-pattern を修正。syntax error  |

## 2026-04

| cmd | title | project | date | key_result |
|-----|-------|---------|------|------------|
| cmd_1696 | 影丸(Sonnet 4.6)の@model_nameが「Opus」と誤表示。根因: model_detect.shのバナー検出パターンが (Opus|Haiku)のみでSonnetが欠落。Sonnetバナーがマッチせずキャッシュの古い値が返される。 加えて、陣形図(karo_snapshot.txt)にモデル情報列がなく、編成状態が不可視。 | infra | 04-03 | model_detect.shにSonnet検出パターン追加 |
| cmd_1697 | cmd_save.sh L152-153のgrep "scope_mode:"/"scout_exempt:"がcmdブロック内にマッチしない場合、 set -eで即exit 1。|| trueがないのが原因。cmd_1696でscout_exemptなし初回BLOCK発生の根因。 | infra | 04-03 | cmd_save.sh L152-153のgrep scop |

## 2026-05

| cmd | title | project | date | key_result |
|-----|-------|---------|------|------------|
| cmd_2681 | 同一cmdに2名配備される二重配備パターン(cmd_2678-2680で3連続発生)を構造的に防止する | infra | 05-12 | cmd_2681: deploy_task.shの同一cmd |
| cmd_2682 | 同一cmdで先行忍者が完了済みの場合、後発忍者を自動的にvoid(task reset+/clear)して空報告を防止する | infra | 05-12 | ninja_monitorに同一parent_cmd完了済み |
| cmd_2683 | 起動手順スキップ(家老がinstructions/karo.md未読で即応答した事故)を構造的に防止する。全ロールのstartup gateをSessionStart hookで自動実行し意志依存をゼロにする | infra | 05-12 | SessionStart hookをsettings.jso |
| cmd_2684 | deploy_task.sh経由でもkaro_direct経由でも最終的にinbox_write.sh type=task_assignedを通るため、ここで同一parent_cmdの他忍者配備を検査しBLOCKすることで全配備経路の二重配備を防止する | infra | 05-12 | inbox_write.shにtask_assigned全経 |
| cmd_2685 | 教訓注入useful率29.3%(ALERT)。NOT_USEFUL 106件の根因=既存target_filesフィルタは存在するが教訓側メタデータ未設定で素通り。入口精度改善+退場加速の2軸 | infra | 05-12 | 教訓注入の入口精度改善としてtarget_files付与経路 |
| cmd_2687 | 掲示板確認が意志依存。inbox bulletin_notifyを読んでも confirmed_byに記録されず次回起動時に未確認WARNが再発。inbox_mark_read.shにbulletin_confirm連動を追加し意志依存ゼロにする | infra | 05-12 | inbox_mark_read.shでbulletin_no |
| cmd_2688 | 教訓注入useful率改善の補完。noise4件(L175/L170/L097/L136 参照率0%)とharm4件(L333/L326/L297/L263 BLOCK率100%)がfeedback不足でcmd_2685のdecay対象外。手動でdeprecate/tag限定し注入プールから排除 | infra | 05-12 | projects/infra/lessons.yaml のn |
| cmd_2689 | gate_skill_quality FAIL(3/38)。shogun-all-codex-switch/shogun-peacetime-rollback/weekly-report-writerのdescription不備(What/When/NOT When欠落)。startup WARN連続の一因 | infra | 05-12 | gate_skill_qualityのFAIL対象3スキルの |
| cmd_2690 | 軍師検出: semantic-index file参照12件がMISSING(DM-Signal外部リポジトリのパス移動/削除が未反映)。インデックス正確性を回復する | infra | 05-12 | semantic-indexのDM-Signal外部file |
| cmd_2691 | karo_direct方式の修行配備でdeploy_task.shの修行テンプレ注入をバイパスし、AC/descriptionが空のまま配備。deploy_error 5件蓄積の根因。karo_directでも修行テンプレ注入を実行する | infra | 05-12 | karo_directスキルのtrainingセクションをd |
| cmd_2692 | karo_workarounds.yaml 88件のresolved_by_cmdが空(解決率16.2%偽陽性)。根因=記入が意志依存。cmd_complete_gate CLEAR時にWAカテゴリを検索しresolved_by_cmdを自動backfillする | infra | 05-12 | cmd_complete_gate GATE CLEAR時に |
| cmd_2693 | karo_direct配備(ci_fix/recon2/hotfix)で旧task YAMLのフィールドがリセットされずstale_report 5件蓄積。根因=deploy_task.shのreset_stale_fieldsに相当する処理がkaro_directのcp前にない。cp前にstatusリセットを追加する | infra | 05-12 | karo-directのci_fix/recon2/hotf |
| cmd_2694 | restart_watchers.sh/ninja_monitor.shのwatcher起動が親プロセスからASW_DISABLE_ESCALATION=1を継承し将軍nudge無効化が再発(cmd_2403修正後も再発)。起動直前にunsetで継承を構造的に遮断する | infra | 05-12 | watcher起動直前にASW_DISABLE_ESCALA |
| cmd_2696 | 修行cmdの教訓参照率0%(89件feedback中useful=0)。根因=修行ACに教訓活用ステップがなくgate精読+報告作成で完結。テンプレートにAC(注入教訓から1件以上referenceせよ)を追加し教訓参照を構造的に強制 | infra | 05-12 | 修行cmd L4テンプレートに、注入教訓を1件以上参照してl |
| cmd_2698 | skill_auto_improve.shがgate FIXヒント75件を読まずBLOCK理由文字列のパターンマッチで防止ステップを生成→汎用テンプレート3件が具体性不足→一発CLEAR率71.6%止まり。FIXヒントDBを自動参照し具体的な防止ステップを生成する | infra | 05-12 | gate_report_format_main.pyにloo |
| cmd_2699 | karo_direct配備(cmd_2695-2698の4件連続)でac_count=0→draft_review SKIPが発生し、軍師レビューの成長ループ第二層が断絶している。全配備パスでac_countが正しく返るよう修正する | infra | 05-12 | karo_direct由来でtask側ACが空でも、壊れたa |
| cmd_2701 | rebalancerを将軍システムの管理対象に登録する。config/projects.yaml+projects/rebalancer.yaml+context/rebalancer.mdを作成し、偵察・cmd配備・教訓蓄積の基盤を整える | infra | 05-14 | rebalancerを管理対象として登録し、config索引 |
| cmd_2703 | cmd_save.shの3ゲート(q11_existing_alternative FP率52%、command_steps_over_ac FP率50%、ac_param_sufficiency FP率40%)が偽陽性を量産し、将軍のcmd起票に負の複利を生んでいる。検出精度を改善する | infra | 05-14 | cmd_save.shの3ゲートFP削減を実装。既存gate |
| cmd_2704 | 偵察タスク(scout_exempt:true)はコード変更を伴わないため未commitファイルが存在しない前提だが、git_uncommitted_gateはscout_exemptを考慮せずBLOCKする。偵察タスクではgit_uncommitted_gateをスキップする | infra | 05-14 | scout_exempt:trueタスクではreport_r |
| cmd_2705 | Renderは/var/lib/dataに永続diskをmountするが、アプリは相対パスstatic/data/cacheに読み書きし永続disk未使用。加えて/staticマウントでcache JSONが外部閲覧可能。CACHE_DIR環境変数対応+/static公開制限で修正する | rebalancer | 05-14 | Render永続diskにcacheを書き込むようCACHE |
| cmd_2706 | pytest-asyncioのasyncio_mode設定欠如により12件のasyncテストがFAIL。pytest設定追加+非推奨asyncio.get_event_loop().run_until_complete()をasyncio.run()に修正する | rebalancer | 05-14 | pytest-asyncioを0.24.0にpinし、bac |
| cmd_2708 | Toast.tsx ×ボタン押下時にsetIsVisible(false)のみでonClose()が呼ばれない。errorステートが残存し、同一エラー再発時にToastが再表示されない | rebalancer | 05-14 | Toastの×ボタン押下時もexit animation後に |
| cmd_2707 | Next.js 15.0.3にcritical(RCE GHSA-9qr9)+high(auth bypass GHSA-f82v)含む脆弱性4件。15.5.18へupgradeし、Serwist互換性とbuild/lint/auditを検証する | rebalancer | 05-14 | Next.js 15.0.3→15.5.18アップグレード完 |
| cmd_2710 | updaterとユーザーAPIが同じJSONを同時読み書きすると部分書込みでJSONDecodeError→Noneフォールバック→不要な外部API fetchが発生。atomic rename+lockで並行安全性を確保する | rebalancer | 05-14 | DiskCache.setをtmp書込み後のatomic r |
| cmd_2709 | Backend ModelはList[str]のみでregex・件数上限・supported ticker強制なし。重複tickerは後勝ち上書きで整合崩壊。入力検証を追加し、重複tickerを400エラーにする | rebalancer | 05-14 | Backend API入力検証を追加し、unsupporte |
| cmd_2712 | get_pricesが各tickerを逐次awaitし毎回1秒sleep。18銘柄で最低17秒以上。semaphore bounded concurrencyで並列化し、cache hit時はsleepスキップでレスポンス時間を大幅短縮する | rebalancer | 05-14 | get_pricesをSemaphore付き並列fetchに |
| cmd_2713 | sw.jsのprecache URLにバックスラッシュが混入しPWAアイコンcache失敗。加えてguide内URLがrender.yaml正本と不一致。Linux再生成+URL統一で修正する | rebalancer | 05-14 | Linux上のnpm run buildでSerwist s |
| cmd_2714 | FundingSection折りたたみがキーボード未対応、icon-onlyボタンにaria-labelなし、モバイルで横溢する。a11y標準に準拠しUX品質を改善する | rebalancer | 05-14 | FundingSectionの折りたたみをbutton+ar |
| cmd_2715 | CIが存在せず、Render前に品質ゲートが走らない。GitHub Actionsでbackend pytest+frontend lint/build/auditを自動実行し、品質を構造的に保証する | rebalancer | 05-14 | GitHub Actions CI workflowを新規作 |
| cmd_2716 | BUY/SELL/HOLDが英語ハードコード、formatCurrencyがen-US固定、APIエラーが英語のまま。日本語モードで全UI要素がi18n対応するよう修正する | rebalancer | 05-14 | 日本語モードでリバランス結果の売買ラベル、通貨表示、APIエ |
| cmd_2718 | Python requirementsがversion pinなしで再現性ゼロ。npm outdatedで主要パッケージに更新あり。requirements pinとnpm依存更新で再現性とセキュリティを確保する | rebalancer | 05-14 | backend/requirements.txtをpip f |
| cmd_2720 | 連続起票時に既知BLOCKパターンの教訓記録でlesson作成→supersede→物理削除のCTX浪費ループが発生(前セッション2026-05-14で20cmd連続起票時に毎回発生)。既知パターンを既存lessonクラスタにack(確認記録)する軽量メカニズムで解消する | infra | 05-14 | 既知BLOCKパターンを既存将軍教訓へack記録するヘルパー |
| cmd_2719 | frontend/src/配下にユーザー作成テストが0件(find確認済み)。Vitest+Testing Libraryを導入し、主要コンポーネントのユニットテストを追加する | rebalancer | 05-14 | Vitest+Testing Library+jsdomをf |
| cmd_2721 | Playwright/CypressなどのE2Eテストフレームワークが未導入(grep確認済み)。銘柄入力→計算→結果表示の主要ユーザーフローをE2Eで検証できるようにする | rebalancer | 05-14 | Playwrightをfrontendへ導入し、銘柄入力から |
| cmd_2722 | 過剰なカード化(glass-card内にrow card)で画面を有効活用できず、スマホでもPCでも一覧性が低い。カード廃止→テーブル直書き+PC2カラム化+ui-design-guide準拠(コントラスト、タッチターゲット、階層)でデータ密度と可読性を両立する | rebalancer | 05-14 | カード内row cardを廃止し、PortfolioForm |
| cmd_2724 | cmd_2703で偽陽性修正済みのac_phase_mixing(29件)とac_param_sufficiency(19件)のWARNカウントがquality logに残存し、正当発火時に即BLOCK(post-5/12 BLOCKの48%が遺産起因)。加えてcmd_quality_log.shとcmd_save.sh log_cmd_save_pass()のヒアドキュメントが2スペース余分でYAML破損を引き起こしていた(cmd_2723起票中に発見、直接修正済み)。残存WARN遺産の解消とcount_same_warn_patternのresolved除外とインデント修正のテスト追加で恒久対策する | infra | 05-14 | cmd_2703で解消済みのac_phase_mixing/ |
| cmd_2726 | 4行のうち3行使用時にtarget_weight未記入行がバリデーションエラーになる。shares未記入も0入力が必要で面倒。ticker未記入行を除外、target_weight未記入を0%扱い、shares未記入を0扱いにする | rebalancer | 05-14 | 未入力ticker行を計算対象から除外し、未入力target |
| cmd_2727 | PF入力をやり直したい時に1行ずつ削除するのが面倒。全消去ボタンで空行4行にリセットし、前回復元ボタンでSupabaseから保存済みPFを再ロードする操作を追加する | rebalancer | 05-14 | PortfolioFormに全消去/前回復元操作を追加し、S |
| cmd_2728 | Blue-Purpleグラデーション+glassmorphismの2023年AIテンプレ感を排除し、Wealthfront調のTeal(#14b8a6)基調+ソリッドカード+装飾最小限の金融プロフェッショナルデザインに刷新する。同時にガイドページの配色も統一する | rebalancer | 05-14 | Blue-Purple/glassmorphism系UIをT |
| cmd_2729 | モバイル(375px)でヘッダーが2行に折れ、サポート銘柄18件が横溢し、テーブル列が窮屈で入力しづらい。CDPモバイルビューポートで5箇所の崩れを確認済み。レスポンシブ対応を修正する | rebalancer | 05-14 | Rebalancer mobile responsive l |
| cmd_2731 | ガイドページに「データを保存しません」「サーバーに保存されません」と記載されているが、cmd_2723でSupabase保存機能が実装済み。cmd_2725(保存ボタン)、cmd_2726(バリデーション緩和)、cmd_2727(全消去+復元)の内容もガイドに未反映。ガイドと実装の整合性を修復する | rebalancer | 05-14 | frontend/app/guide/page.tsx のJ |
| cmd_2730 | ルート.gitignoreにpycache/pyc/cacheファイルが未登録で、backend側に.gitignoreが存在しない。445件のdirty filesが蓄積しworking treeが汚れている。.gitignore整備+git rm --cachedでtracked不要ファイルを除去する | rebalancer | 05-14 | ルート.gitignoreを追加し、pycache/back |
| cmd_2732 | Gate 20(スキル別FAIL率)が全期間累積fail>0で判定しているため、改善済みFAILが永久にWARN発火する。直近50件FAIL率は全スキル0%だが3セッション連続BLOCK。直近50件ベース+10%閾値に変更し実態を反映した判定にする | infra | 05-14 | Gate 20のスキル別FAIL率を全期間累積から各スキル直 |
| cmd_2734 | 概念→スキルの対応がインフラに存在せず、スキル使用が意志依存(CDP未使用トラブル、DB-check誤使用が繰返し発生)。semantic indexにskills列を追加し、deploy_task.shでタスクYAMLにrecommended_skillsとして自動注入する | infra | 05-15 | semantic indexのskills列をタスク配備時の |
| cmd_2735 | 忍者がrecommended_skillsを無視してもレビューで検出されない。軍師の6観点にスキル使用適切性チェックを追加し、recommended_skillsが存在するのに未使用の場合にREQ_CHANGESを出す | infra | 05-15 | 軍師レビューにrecommended_skills使用突合を |
| cmd_2736 | 将軍はスキルの存在を知っているがセッション中にTRIGGER条件と結びつかず手動作業に流れる(CDP未使用等、殿指摘)。prompt_state_inject.shにスキルTRIGGERキーワード照合を追加し、合致スキルを強制表示する | infra | 05-15 | prompt_state_inject.shに将軍向けスキル |
| cmd_2738 | DB-checkをrebalancerで呼ぶ等のスキル誤使用が繰返し発生(殿指摘)。SKILL.mdのDO NOT TRIGGER条件とcurrent_projectを照合し、制約違反時にexit 2でBLOCKするPreToolUse hookを追加する | infra | 05-15 | PreToolUse Skill guard hookを実装 |
| cmd_2742 | 現在ダークモード固定でライトモードがない(殿指摘)。Tailwind darkMode class方式で切替トグルを追加し、ユーザーがダーク/ライトを選択可能にする | rebalancer | 05-15 | Tailwind class dark方式のテーマ切替を追加 |
| cmd_2743 | cmd_complete_gate.sh L222がshogun_state!=idleでinbox_writeをスキップし、将軍がactive時(殿と対話中)にGATE CLEAR通知が届かない。殿がntfyで先に知り将軍に聞くが将軍が知らない事態が発生(殿指摘)。stateチェックを撤去し常時通知にする | infra | 05-15 | cmd_complete_gate.shの将軍GATE CL |
| cmd_2744 | 将軍がGATE CLEARを受けても殿の入力を待って動かない。F004(polling禁止)を過剰解釈し自走を抑制していた(殿指摘:自分で出したcmdの結果確認は鎖の中)。GATE CLEAR後の定型アクション(push判断/次cmd確認/殿への報告)を将軍の正当な自走としてshogun.mdに明文化する | infra | 05-15 | GATE CLEAR受信後の将軍自走フローをshogun.m |
| cmd_2746 | cmd_2662-2666で5回頻発したdeploy_task.sh配備後のinbox未配信事象の根因を特定し、再発防止策を提案する | infra | 05-15 | cmd_2662-2666のinbox未配信は、2026-0 |
| cmd_2747 | karo_workarounds.yamlの歴史的データ汚染(detail空・category不正)82件を正しいcategory/detailに修復し、WA分析の精度を回復する | infra | 05-15 | karo_workarounds.yamlのWAデータ品質汚 |
| cmd_2748 | dm-signal教訓698件+infra教訓583件の旧形式教訓にwhen/howフィールドを段階的に補完するスクリプトを作成し、教訓注入の精度を向上させる | infra | 05-15 | 旧形式教訓のwhen/how補完スクリプトを追加し、dm-s |
| cmd_2749 | skill_auto_improveがSKILL.md改善で閉じないFAIL(スクリプトバグ起因)を検出し、コード修正cmdの起票を将軍に掲示板経由で要請する仕組みを追加する | infra | 05-15 | skill_auto_improveにFAIL分類、UNCH |
| cmd_2750 | auto_failure_lesson.shがgate_fire_logのFAIL原因を参照し、スクリプトバグ起因のFAILを検出した場合にbulletin_write.shで将軍にコード修正cmd起票を要請する | infra | 05-15 | auto_failure_lesson.shにgate_fi |
| cmd_2751 | insight_write.shに同一パターン繰返し検出と優先度判定を追加し、高優先度insightが蓄積のまま埋もれる問題を解消する | infra | 05-15 | insight_write.shにsource一致のpend |
| cmd_2752 | gate_fire_logのFAIL→PASS遷移分析で未回復期間が閾値(設定可能)を超えたFAILを検出し、bulletin_write.shで将軍にコード修正cmd起票を要請する | infra | 05-15 | gate_shogun_startup.shのL6学習速度に |
| cmd_2753 | auto_failure_lesson.shがどこからも呼ばれていない断裂を修正し、gate FAILした忍者タスクから自動的に教訓が生成されるパイプラインを接続する | infra | 05-15 | cmd_complete_gate.shのGATE BLOC |
| cmd_2754 | ninja_monitorにidle忍者への修行自動配備トリガーを追加し、修行サイクルが家老の手動判断に依存する断裂を解消する | infra | 05-15 | ninja_monitor.shにidle継続+直近gate |
| cmd_2756 | bulletin_write.shにaction_typeフィールドを追加し、昇格通知が対応されたか追跡可能にする。startup gateで未対応ALERTを表示し、cmd_save.shでactioned_by自動更新する | infra | 05-15 | bulletin action_type/actioned_ |
| cmd_2755 | gate_fire_logのFAIL→PASS遷移率計測を将軍の/clear間隔依存から解放し、ninja_monitorで定期的に計測・記録する | infra | 05-15 | ninja_monitor.shにgate_fire_log |
| cmd_2758 | Gate 13.8のFP率閾値超過時にbulletin_write.shで将軍にgate条件緩和cmdの起票を要請し、FP増大による速度低下を防止する | infra | 05-15 | Gate 13.8の高FP率時bulletin緩和要請実装を |
| cmd_2757 | effectiveness低い教訓の定期棄却をninja_monitorで自動実行し、教訓注入ノイズの単調増加を防止する | infra | 05-15 | ninja_monitorに教訓deprecate候補の日次 |
| cmd_2760 | CoDD v1.10.0時点の知識体系をv2.18.0に更新する。context/codd.md+セマンティックインデックス+スキルSKILL.md+reference_codd_oshio_articles.mdを最新の記事・GitHub情報で刷新する | infra | 05-15 | CoDD知識体系をv2.18.0へ更新し、context/s |
| cmd_2761 | 全8PJでcodd init --suggest-lexicons --llm-enhancedを実行しlexiconを設定。codd.yamlをv2.x形式に刷新。新PJ作成時にcodd initが自動実行される仕組みを追加する | infra | 05-15 | 全8PJへCoDD v2系設定とshogun_core le |
| cmd_2766 | CLEAR済みcmd関連insightとsemantic_index_update由来insightを自動done化し、191件pending永久蓄積を解消する | infra | 05-15 | cmd_complete_gate CLEAR後にcmd関連 |
| cmd_2768 | harmful閾値に加えuseful率(helpful/参照回数)が低い教訓も自動deprecateし、効果の薄い教訓が永続する穴を解消する | infra | 05-15 | — |
| cmd_2769 | deploy_task.sh配備後にinbox未配信が5回頻発した根因を特定し、再発防止策を設計する | infra | 05-15 | cmd_2662-2666の未配信疑いは、5件ともinbox |
| cmd_2762 | 設計書ゼロの主要スクリプト4本(deploy_task.sh/cmd_save.sh/ninja_monitor.sh/inbox_write.sh)にcodd brownfieldを実行し、DAG構築+設計書逆生成でリファクタとcodd fix/verifyの土台を作る | infra | 05-15 | 主要4スクリプトのCoDD brownfield成果物(re |
| cmd_2776 | セマンティック辞書に未マッピングの5概念カテゴリを追加し30ファイルの辞書到達性を確保。前提崩壊の構造的防止 | infra | 05-15 | セマンティック辞書SSOTに5概念を追加し、semantic |
| cmd_2777 | cmd_2775偵察で特定した高優先度60関数をcontext/infrastructure.mdにカテゴリ別で追記し、全エージェントが起動時に自動ロードできる受動的知識に昇格させる | infra | 05-15 | context/infrastructure.mdにcmd_ |
| cmd_2779 | cmd_save.sh BLOCK後のREMINDに教訓記録だけでなく環境埋込み判定を強制追加し、BLOCKのたびにインフラ改善cmdの要否を自動判定させる | infra | 05-15 | cmd_save.shのCLEAR時REMINDに環境埋込み |
| cmd_2780 | Simple-OCRリポジトリ全体にcodd extract --ai を実行し、6層MECE設計書を逆生成する。OCRエンジン切替実装の土台とする | infra | 05-15 | Simple-OCRでCoDD brownfield ext |
| cmd_2781 | 設計書(docs/ocr-engine-switching-design.md)のPhase 1-3を実装。OCREngine抽象クラス+Google/Claude/GPTの3エンジンを切替可能にする | infra | 05-15 | OCRエンジン抽象化を追加し、Google/Claude/G |
| cmd_2782 | Google Vision DOCUMENT_TEXT_DETECTIONのブロック座標情報をClaude Haikuに渡し、お薬手帳の列構造を正確に復元する二段構えパイプラインをSimple-OCRに組み込む | infra | 05-15 | Google DOCUMENT_TEXT_DETECTION |
| cmd_2784 | force-with-lease/reset/clean等の破壊的コマンド実行前に、lord_conversation.jsonlのinboundに殿の承認発言があるか自動検証するhookを追加し、ハルシネーションに基づく破壊的操作を構造的に防止する | infra | 05-15 | pre-bash-combinedにD010 Guardを追 |
| cmd_2785 | skills/dream・gate-sync・idle-persistのSKILL.mdが参照scriptより古く、startup gateが3セッション連続WARNしている。scriptの変更内容をSKILL.mdに反映し、gate_skill_script_refs.shのWARNを解消する | infra | 05-15 | skills/dream・gate-sync・idle-pe |
| cmd_2786 | cmd_save.sh L254のadditionキーワード判定が過去形・受身形(追加された/追加済み等)にもマッチし、gate参照cmdをgate追加cmdと誤判定する。15回累計でBLOCK昇格している偽陽性を修正する | infra | 05-15 | — |
| cmd_2787 | _build_two_stage_promptがお薬手帳の処方行解釈をハードコードしており、情報の追加(処方日補完)や構造強制(1行まとめ)が発生する。プロンプトを座標ベースのレイアウト忠実復元に限定し、情報量を不変にする | simple-ocr | 05-15 | _build_two_stage_promptを座標ベースの |
| cmd_2788 | record_lesson_feedback.sh L91の${task_type:-impl}がexact/recon/trainingを全てimplにフォールバックし、deploy_task.shのeffectiveness_score計算でexactタスクの有効率が歪む(有効率30%)。task YAMLからtask_type取得のフォールバックを追加する | infra | 05-15 | record_lesson_feedback.shにtask |
| cmd_2791 | auto-ops/gc/db等の教訓にwhen/howフィールドが欠落している69件を補完する。when/howがないと教訓注入時のタスク特性マッチングが効かず、注入精度が低下する | infra | 05-15 | — |
| cmd_2792 | dashboard_auto_section.shのCI取得ロジックがcheck failedと表示するが、gh run list直近5件は全てsuccess。表示と実態の乖離原因を特定する | infra | 05-15 | dashboardのCI check failed表示は、l |
| cmd_2790 | deploy_task.shが全ACにbinary_checksスタブを注入するため、担当外ACにもbc:noが入りverdictがFAILになる(WA 10回)。task YAMLにac_assigned追加→担当ACのみスタブ生成に限定する | infra | 05-16 | inject_ac_assigned_from_stk()を |
| cmd_2793 | gate_lesson_health.shのawkがdetailフィールド内のenforcement:テキストを誤抽出しPHANTOM偽陽性4件を生んでいる。修正後、同スクリプトを参照するSKILL.md 3件を最新動作に追従更新し、3セッション連続BLOCK(gate_skill_script_refs.sh)を解消する | infra | 05-16 | gate_lesson_health.shのPHANTOM抽 |
| cmd_2794 | deploy_task.sh L3705のtag fallbackパスがeffectiveness除外(L3740)より前に実行されるため、useful率0%の教訓10件が除外されずに注入され続けている。fallbackパスにもeffectiveness除外を適用し、忍者CTX約295tok/タスク削減する | infra | 05-16 | 停止指示によりFAIL報告。cmd前提のfallback e |
| cmd_2795 | useful率0%の教訓10件がeffectiveness除外を通過して注入され続けている。cmd_2794でfallbackパスの除外漏れと推定したが、家老の現物確認でfallbackパスには除外が実装済みと判明。真因を特定するためdeploy_task.shのstderrログを分析し、10件がどの経路で注入されているかを特定する | infra | 05-16 | stderrログ確認で、still-injected 10件 |
| cmd_2796 | codd.yamlのsource_dirs(src/)が存在せず、doc_dirs(docs/)が研究ノート613件を設計書として取り込みhealth_score=0(662 errors)。source_dirsをscripts/に、doc_dirsをcodd/配下のみに修正し、codd measureのhealth_scoreを正常化する | infra | 05-16 | codd/codd.yamlのscan対象をscripts/ |
| cmd_2797 | gate_context_freshness.shがALERT時に毎回ntfy送信するが、ninja_monitorが5分間隔で実行するためcontextが古いまま5分ごとに同じALERTが殿に送信されrate limitに到達した。同一ALERTの重複送信を抑止する | infra | 05-16 | gate_context_freshness.shの同一AL |
| cmd_2798 | gate_context_freshness.shが安定context(軍師分析索引/設計ガイド/完成済み知見等)に14日ルールを一律適用し20件以上のALERTを出し続ける。安定contextを除外リストで管理し鮮度チェック対象から外す。cmd_2797(重複抑止)は安全網として維持 | infra | 05-16 | context鮮度チェックに除外リストファイルを導入し、安定 |
| cmd_2800 | report_field_set.shがself_gate_checkにPASS/FAILをトップレベルscalarで書くとdict構造がscalarに上書きされgate FAILを引き起こす。全忍者で22件発生(kagemaru25/hayate16/saizo15)。dot notation必須化でdict構造を保護する | infra | 05-16 | self_gate_checkのトップレベルscalar書込 |
| cmd_2799 | deploy_task.shが更新されたがskills/karo-direct/SKILL.mdが追従していない。gate_skill_script_refs.shが3セッション連続WARNでstartup BLOCK昇格。SKILL.mdの記述をdeploy_task.shの現在の動作に合わせて更新する | infra | 05-16 | skills/karo-direct/SKILL.mdをde |
| cmd_2802 | scripts/gates/*.sh変更時にtest_selectがそのgateを呼ぶ上位テスト(test_cmd_complete_gate.bats等)を選出しない。cmd_2798でgate_context_freshness.sh変更→test_context_freshness_check.batsのみ実行→test_cmd_complete_gate.batsのテスト28漏れ→CI RED。gate→消費先テストの間接依存マッピングを追加する | infra | 05-16 | scripts/gates/*.sh変更時にcmd_comp |
| cmd_2808 | ntfy.shにbackoff/cooldownがなく本日778回429エラー(殿通知ほぼ全失敗)。cmd_2797は1送信元の部分対策。新送信元追加で再発する構造。ntfy.shにグローバルthrottle(10s間隔+429時60s cooldown)を追加し全送信元を一括保護する | infra | 05-16 | ntfy.shに10秒グローバルthrottleとHTTP |
| cmd_2807 | cmd_2801の_sv()修正後にinject_ninja_weak_pointsがkagemaru+hanzoで連続YAML注入失敗(各2回)。配備自体は成功(weak_pointsはオプショナル)だがsilent failure可視化(cmd_2801で追加)がERRORを検出。_sv()修正の副作用か別の原因かを特定し修正する | infra | 05-16 | inject_ninja_weak_pointsの連続YAM |
| cmd_2809 | 前セッションのcmd_2801/2802/2808がスクリプト4本を変更したがSKILL.md未更新。3セッション連続WARNの根因はcmd_complete_gateにSKILL.md追従チェックが未組込み(事後検知のみで事前強制なし)。 | infra | 05-16 | SKILL.md script参照WARN 6件を追従更新し |
| cmd_2810 | cmd_complete_gate.sh L3650のauto_draft_lesson.shがdraft教訓を生成した直後に、L4843のdraft教訓チェックが自cmdが生成したdraftをBLOCKする循環構造。直近50cmdで19件BLOCK(最頻パターン)。 | infra | 05-16 | — |
| cmd_2812 | PC受信画面とスタンドアロン版のOCRエンジンドロップダウンのselected属性がgoogle側についており、UIデフォルトがGoogle Visionになっている。バックエンドはtwo_stageがデフォルトだがフロントが不整合。 | simple-ocr | 05-16 | PC受信画面とスタンドアロン版のOCRエンジンドロップダウン |
| cmd_2813 | OCR結果カードのタイトルがOCR結果とハードコードされている。two_stageパイプラインはpatient_nameを構造化JSONで出力済みなので、タイトルに患者名を表示する。テキスト本文からは消さない。 | simple-ocr | 05-16 | OCR結果カードのタイトルにtwo_stage抽出の患者名を |
| cmd_2814 | clear_prep_check.sh Check 8がWARN表示のみでALERT昇格しない。insights 5件放置/semantic-index未更新/BLOCK経験ありlesson 0件が/clear時に素通りし、次の将軍が今セッションの学びを持てない。なぜなぜ7回で確認と対処の未分離が根因。最終防衛線を強化する。 | infra | 05-17 | clear_prep_check.shで知識埋込み漏れ3条件 |
| cmd_2815 | gate_shogun_startup.sh Gate 13が教訓健全度ALERTを一律'/lesson-sort推奨'とするが、useful_rate<30%は/lesson-sortで解決しない。3セッション連続BLOCKの根因。ALERT種別(useful_rate vs 未振り分け)を判別し適切な推奨を表示するよう条件分岐を追加する。 | infra | 05-17 | Gate 13の教訓健全度ALERTをuseful_rate |
| cmd_2817 | binary_checks_fail FAILが直近50件中7件。ashigaru.md L52にルールはあるが具体的YAML記入例がなく忍者が形式を間違える。記入例追加で忍者の報告作成時の行動フローをFAIL→PASSに変換する。 | infra | 05-17 | AC1は完了。AC2は指定ID INS-20260516-1 |
| cmd_2818 | /clear後の将軍が各ルールの因果チェーン(何の実験→何の失敗→殿のどの裁定→ルール化)を持たないため、外部記事1本で安易に棚卸しを提案した。根因=時系列×因果のネットワークが環境に永続化されていない。Obsidian式[[リンク]]で既存lessons/senkyoku-logに因果辺を埋込み、逆引きCLIで任意ノードの前後を辿れるようにする。 | infra | 05-17 | 将軍教訓26件にoriginリンクを追加し、逆引きCLIとl |
| cmd_2822 | 因果ネットワーク活用の第二出口。deploy_task.shが忍者タスクYAMLに関連因果[[リンク]]を自動注入する。忍者が実装時に関連する過去の失敗/裁定を参照でき、同じ失敗の再発を防ぐ。 | infra | 05-17 | deploy_task.shにinject_causal_l |
| cmd_2821 | 因果ネットワーク活用の出口。lessons_shogun.yamlのエントリでoriginフィールドが空またはリンク0件のものを起動時にWARN表示し、因果不明ルールを可視化する。将軍が因果を埋める行動を促す。 | infra | 05-17 | gate_shogun_startupにlessons_sh |
| cmd_2823 | 因果ネットワーク(Obsidian [[リンク]]+origin)の仕組み知識が将軍の頭の中にしかない。家老・軍師・忍者は存在を知らず利用できない。使えないものは存在しないのと同じ(殿厳命)。CLAUDE.md Knowledge Map+各ロールinstructionsに因果NW利用手順を埋込み、全エージェントが自動化活用できる状態にする。 | infra | 05-17 | 因果ネットワークのorigin/Obsidianリンク手順を |
| cmd_2824 | 将軍がRenderのプラン挙動を知らずコールドスタート推測を繰り返す(殿指摘2026-05-17)。根因=Render知識がcontext/instructionsに体系化されていない。プラン別挙動(Free=コールドスタート/Starter=なし)、ログ取得方法、障害切り分け手順、全サービス一覧をcontext/infrastructure.mdに追記し、全エージェントが考えずに利用できる状態にする。 | infra | 05-17 | context/infrastructure.mdにRend |
| cmd_2826 | 将軍が殿の質問に答える前にセマンティック辞書/Obsidianリンクを検索しない(意志依存)。Render障害でコールドスタート推測を繰り返した根因。prompt_state_inject.sh(UserPromptSubmit hook)に殿の入力テキストでsemantic_search.shを自動実行し、関連知識を将軍のコンテキストに自動注入する。 | infra | 05-17 | prompt_state_inject.shが殿入力をsem |
| cmd_2827 | deploy_task.shがqueue/reports/の全ファイルを処理するため、241件蓄積でtimeout発生しnudge未送信。GPT忍者3名がプロンプト待ちで停止した(2026-05-17 20:34事故)。根因はarchive_completed.sh L948のCMD_IDガード。GATE CLEAR時(CMD_ID指定)にoverflow cap(=10)が発火せず蓄積が止まらない。ガード撤去でGATE CLEARごとにcap超過分を自動アーカイブする。 | infra | 05-17 | archive_completed.shのCMD_ID指定時 |
| cmd_2828 | 因果ネットワークのリンク追加が意志依存。context/memoryファイル作成時に因果リンクセクションが書かれず孤立ノードが増加しネットワークが成長しない。pre-write-edit-combined.shに検出ロジックを追加し、リンク記載を構造的に促す。 | infra | 05-17 | — |
| cmd_2829 | gate_lesson_health.shとdeploy_task.shが更新されたがSKILL.md 3件が未追従。startup gateで3セッション連続WARNが出ており解消が必要。cmd_2809と同パターンの定型追従作業。 | infra | 05-17 | SKILL.md script参照の追従WARNを解消し、g |
| cmd_2830 | deploy_task.shのnudge送信(safe_inbox_write L6379)がスクリプト末尾に配置されており、途中kill/timeoutでnudge未到達が無音で発生する。2026-05-17 20:34事故でGPT忍者3名がプロンプト待ちで停止した直接原因。trap EXITでnudge送信を保証し、スクリプト中断時も忍者に通知が届く構造にする。 | infra | 05-17 | deploy_task.shにEXIT trap nudge |
| cmd_2831 | check_ac_phase_mixing(L4280)がAC内のファイル名(例: 配備スクリプト名)に含まれるキーワードを配備アクションと誤検出し偽陽性BLOCKを発生させる。12回累計昇格済み。awk関数check_buf内でファイルパスパターンを除去してからキーワードマッチすることで偽陽性を排除する。 | infra | 05-17 | check_ac_phase_mixingのファイル名由来d |
| cmd_2832 | 軍師分析(掲示板blt_20260517_212058)で検出された残り3件の構造的弱点を修正する。(P1)内部timeout保護なし→外部bash timeoutに依存で中断制御が不完全。(P1)post-deploy verify(L6404付近)がlog出力のみでリトライなし→形骸化。(P2)gawk全忍者分読込み(L1620)→対象忍者のレポートのみに限定しI/O削減。 | infra | 05-17 | deploy_task.shに内部deadline、実効po |
| cmd_2834 | WARN累計昇格がBLOCK全体の15%(227件/1485件)を占め、将軍のcmd起票速度を構造的に阻害している。ac_phase_mixing(39件)はcmd_2831+2833で対処済みだが残6チェック(累計20-27件のWARN昇格BLOCK)の偽陽性パターンが未特定。対象チェック名リストはcmd_design_quality.yamlのBLOCK集計TOP6参照。各チェック関数のロジックを精読し偽陽性の発火条件・再現手順・修正方針を特定する。 | infra | 05-17 | cmd_save.shのWARN累計昇格TOP候補を精読し、 |
| cmd_2836 | 教訓健全度ALERT(useful_rate=28.1%)が3セッション連続。家老分析で不参照TOP4(L500/L078/L585/L101)が特定済み。根因はL500/L585/L078にuniversalタグが付与されており全タスクに注入されるが内容は超限定的(特定関数/特定パス)。universalタグを具体的なファイル/機能タグに変更しノイズ注入を削減する。 | infra | 05-17 | L500/L585/L078/L101の教訓タグを内容に合う |
| cmd_2837 | cmd_2834偵察で特定された6チェック関数の偽陽性パターンを修正する。(1)GS/WFツール検出:偵察/分析cmdを除外 (2)否定的前提claim:検査対象をclaim限定 (3)AC基準チェック:infra/偵察を除外 (4)q11既存代替:q5/assumptionsのrg結果も補助認定 (5)q8縮小表現:非破壊/スコープ限定文脈を除外 (6)行動変換:偵察/分析を除外+同義語追加。累計昇格BLOCK 227件(15%)の構造的解消。 | infra | 05-17 | cmd_save.shの6チェック関数にcmd_2834偵察 |
| cmd_2835 | 家老のidle自走分析(掲示板blt_20260517_203516)で特定された忍者報告品質の構造的改善3件。(1)report_format FAIL 11件/50cmd→ashigaru-procedures.mdにRFS再実行手順を先頭固定化。(2)binary_checks FAIL 7件→ashigaru.mdにbc yes/no記入例付き強調。(3)purpose_validation不一致 3件→ashigaru.mdにcmd目的との差分確認を明記。全てドキュメント追記のみで新仕組みゼロ。 | infra | 05-17 | cmd_2835の忍者報告品質改善3件は正本に反映済み。現物 |
| cmd_2838 | dashboard_update.shがdashboard_template.mdの必須セクションをdashboard.mdに照合するが、テンプレートが古く3セクション不一致(進行中=欠落/調査結果=欠落/要対応=絵文字不一致)でFAIL率22%(11/50)。テンプレートをdashboard.mdの現行構造に同期する。 | infra | 05-17 | dashboard_template.mdのKAROセクショ |
| cmd_2839 | cmd_2837のcheck_research_tool_explicit FP修正で除外条件が広すぎ、テスト556(RTE-T004: wf_engine参照は従来通りWF警告する)がFAIL。正当なWF警告が消された。除外条件を偵察/分析文脈に限定し正当WARNを復活させる。 | infra | 05-17 | cmd_2839対象のcheck_research_tool |
| cmd_2841 | gate_report_format_main.pyがassumption_invalidationのaffected_cmdsを必須検証するが、RFS(report_field_set.sh)経由で書き込む際にaffected_cmdsが欠落し39件FAILが発生。テンプレート(L1883-1886)にはデフォルト値があるがRFS書込みで上書きされる際にサブフィールドが消える。RFSのassumption_invalidation書込みでaffected_cmdsを保持する修正を行う。 | infra | 05-17 | RFSのassumption_invalidation.*書 |
| cmd_2845 | cmd_2840でlesson_write.shにorigin引数を追加し新規教訓は自動でorigin付与されるようになった。だが既存軍師教訓33件はorigin=0件のまま。因果NWの既存ノードにリンクを遡及追加しネットワーク密度を即時向上させる。 | infra | 05-18 | projects/infra/lessons_gunshi. |
| cmd_2844 | cmd_2840でlesson_write.sh(軍師共通)にorigin引数を追加した。残り2件: (1)gate_lesson_health.shに教訓originフィールド欠落時のWARN追加(将軍教訓にはcmd_2821で実装済み→同パターン転用)。(2)lesson_write_karo.sh(家老専用)にも--origin引数追加。因果NW自動成長の対象を全ロールに拡大する。 | infra | 05-18 | cmd_2844のorigin全ロール拡大を実装済みとして確 |
| cmd_2846 | autofix提案が忍者未読ファイルを対象に+既存gateで解決済み問題を提案する二重無効状態を解消。INSIGHT_REPEAT action_required蓄積の根因 | infra | 05-18 | gate_autofix_proposalで未読target |
| cmd_2849 | 偵察cmd_2848で特定された根因を修正。GATE BLOCK時にlesson_write --status draftで自動生成されたdraftが、同一cmdの後続GATEでCRITICAL BLOCKされる自己循環(19件中15件=78.9%)を解消 | infra | 05-18 | GATE自動生成draftへgate_auto_draftマ |
| cmd_2850_cancelled | — | — | 05-18 | — |
| cmd_2850 | CoDDで生成した設計書15件に基づきkj-role-countアプリ全体を実装する。忍者6名並列配備で一括完成 | kj-role-count | 05-18 | — |
| cmd_2851 | cmd_save.shのWARN累計昇格がproject=infraの累計を外部PJ(kj-role-count等)のcmdに適用し誤BLOCKする。累計カウントをproject別にスコープ分離し、外部PJのcmdもcmd_save.shを正規に通せるようにする | infra | 05-18 | cmd_save.shのWARN累計昇格をproject別に |
| cmd_2852 | deploy_task.shのinject_context_hints(L2826)/inject_production_invariants(L2882)内のsed -iが変数展開時に特殊文字で壊れ、set -euo pipefailでexit 1→nudge未送信になる問題を修正する。全cmd配備に影響中 | infra | 05-19 | deploy_task.shのinject_context_ |
| cmd_2853 | 殿の5要望を一括修正する。(1)入力画面にrole=admin非表示 (2)常勤/パート色分けを集計BarChart+管理画面+カレンダー詳細に統一 (3)DatePicker shiftDateのtoISOString UTCバグ修正(右矢印無反応+左矢印2日戻る) (4)カレンダーセル縦幅拡大(5名表示) (5)管理画面ロール追加/切替のpin_auth→pinフィールド名修正 | kj-role-count | 05-19 | 殿の5要望を実装し、admin非表示・常勤/パート色分け統一 |
| cmd_2854 | cmd_save.shの2つの問題を修正する。(1)殿発言検索+cmd履歴検索の全走査で16秒に低下。キャッシュまたは件数制限で高速化 (2)sourceに絶対パスを書くとPROJECT_WDと二重結合されファイル不在BLOCKになるバグ。絶対パス検出時はPROJECT_WD結合をスキップ | infra | 05-19 | cmd_save.shのquality log検索を直近50 |
| cmd_2856 | 運用YAMLの肥大化を書込み時に自動制御する汎用機構を構築する。各書込みスクリプトが追記後にwc -l > 閾値なら即アーカイブ退避し、索引層を常に小さく保つ。startup gateやcronではなく書込み時に実行することで待機時間ゼロ | infra | 05-19 | yaml_auto_archive.shをcmd_save. |
| cmd_2859 | startup gateで3セッション連続WARN。9件のSKILL.mdが参照scriptより古い。scriptの最新動作をSKILL.mdに反映する | infra | 05-19 | 8件のSKILL.mdに各scriptの最新動作を反映。ga |
| cmd_2862 | gate_report_format FAILが直近でも発生(2026-05-19)。根因=忍者がEdit toolで報告YAMLを直接編集しフィールドをstr化/MISSING化する。report_field_set.sh経由なら型ガードが効くが直接Editを阻止する仕組みがない。PreToolUse hookで報告YAML直接Editを検出しBLOCKする | infra | 05-19 | — |
| cmd_2863 | 本セッションでcmd_2857(self_gate_check既存)とcmd_2862(Guard 3既存)の車輪再発明が2回発生。根因=将軍のgrep検索キーワード不足で既存Guardを見落とし。cmd_save.shがhook/gate変更cmd検出時に対象ファイルのGuard一覧を自動抽出し表示することで、grepキーワード精度に依存しない確認を強制する | infra | 05-19 | cmd_save.shのq11でgate/hook変更cmd |
| cmd_2864 | 教訓健全度ALERT 3セッション連続。根因分析: fb>=3の全77件がuseful=0%。deploy_task.sh L3953の`if score > 0`でcontent1回マッチ(score=1)でも注入される。汎用キーワード(修正/実装等)が広くマッチし無関係教訓を量産。MIN_KEYWORD_SCORE変数を導入しscore>=2に引き上げ、弱いマッチを除外する | infra | 05-19 | MIN_KEYWORD_SCORE=2をdeploy_tas |
| cmd_2871 | 軍師提案。verdictはbinary_checksから常に導出可能な計算値(ALL yes→PASS, else FAIL)。独立フィールドとして存在すること自体が矛盾の温床でGP-072c2-c5の4層防御が必要になっている。gate_report_format.shでverdictをbcから自動計算し上書きすることで、verdict関連FAIL/workaround/修正サイクルを構造的に消滅させる | infra | 05-19 | gate_report_format.shでverdictを |
| cmd_2869 | 成長ループ第2段[E]。cmd_save.sh q11の既存代替確認がgrep単独で車輪を見逃す(cmd_2857/2862/2863の3連続車輪)。semantic_search.sh(因果辺トラバース付き=cmd_2866)をq11チェックに統合し、概念レベルで関連cmdを自動発見する | infra | 05-19 | cmd_save.sh q11にsemantic_searc |
| cmd_2870 | 成長ループ第3段[F]。セマンティック辞書のresourcesはリポジトリ内ファイルのみ。GitHub/Zenn/外部記事等のURLをresourcesとして格納可能にし、外部知識と内部因果辺を接続する。コリ先生OpenPBX等の外部リポが辞書から到達可能になる | infra | 05-19 | semantic-index resourcesにurl種別 |
| cmd_2868 | cmd_2866(因果辺トラバース統合)で概念拡張検索が動くが、トラバース結果の有用性が計測されない。lesson_impact.tsvにtraversal_depth列(直接マッチ=0, 1ホップ=1, 2ホップ=2)を追加し、depth別のuseful率を分析可能にする。成長ループの[D]精度計測を閉じる | infra | 05-19 | lesson_impact.tsvにtraversal_de |
| cmd_2867 | Obsidian×セマンティック統合パイプライン(cmd_2866)の成長ループを閉じる。因果辺(origin [[リンク]])が毎日追加されるが辞書更新と概念発見が手動。lesson_write/cmd完了時にsemantic_map_generate.sh自動実行+未登録[[リンク]]ターゲット検出→insight_write自動通知で、使うほど辞書が賢くなる免疫系ループを構築する | infra | 05-19 | semantic_index_updateがoriginの[ |
| cmd_2866 | Obsidian因果辺(origin [[リンク]])とセマンティック辞書とcausal_backlinks.shが独立して動いている。semantic_search.shに因果辺トラバースを統合し、概念マッチ→因果辺拡張→関連resourcesを一括返却するパイプラインを構築する | infra | 05-19 | semantic_search.shに因果辺トラバースを統合 |
| cmd_2865 | なぜなぜ7回の真因=教訓注入の計測基盤不在。deploy_task.shが教訓注入時のkeyword scoreを記録せず、score帯別のuseful率分析が不可能。score列をlesson_impact.tsvに追加し、改善サイクルの因果追跡を可能にする | infra | 05-19 | lesson_impact.tsvにscore列を追加し、教 |
| cmd_2873 | デーモン重複実行が頻出(本セッション: ninja_monitor 3重、inbox_watcher全員2重)。根因=統一管理層不在。restart_watchers.shはwatcherのみ管轄でninja_monitor/ntfy_listenerは対象外。全デーモンを統一管理するdaemon_supervisor.shを作成し、プロセス数チェック+重複停止+ヘルスチェック+自動再起動+ntfy通知を一括実行する | infra | 05-19 | daemon_supervisor.shを追加し、inbox |
| cmd_2872 | 本セッションでreview_log 0バイト破壊事故。根因=cmd_complete_gate.shのnohup+disown並行実行時に共有ファイル(review_log/dashboard.md等)書込みにflockなし。全共有ファイル書込みにflock追加し並行安全性を構造保証する | infra | 05-19 | cmd_complete_gate.shの共有ファイル直接書 |
| cmd_2874 | 殿指示「辞書の育成をやろう」。Phase 1(cmd_2860-2867)でaliases追加+自動成長ループ構築済み。Phase 2=品質向上: (1)noise aliases除去(task notification文字列やtool-use-id等の非意味的文字列がlord_conversation自動取込で混入) (2)未カバードメイン概念追加(修行サイクル/デーモン管理/外部PJ群/報告品質) (3)aliases精度向上(自然言語バリエーション追加) | infra | 05-19 | semantic index Phase 2としてnoise |
| cmd_2875 | semantic_search(cmd_2869)は概念レベル検索を実現したが、因果辺トラバース(causal_backlinks.sh)は未統合。道具はあるが使う仕組みに埋め込まれていない=意志依存。cmd起票時にq11のsemantic_search結果と合わせてcausal_backlinksの結果も自動表示し、関連cmd/教訓の因果辺を起票前に強制提示する | infra | 05-19 | cmd_save.shのq11 semantic_searc |
| cmd_2878 | 報告YAMLのorigin付与率が1.2%(61/4938)。根因=gate_report_format.shとreport_field_set.shにorigin関連チェックがゼロ(grep確認済み)。Level 1(ドキュメント記載のみ)→Level 5(gate強制+書込み支援)に昇格し、因果ネットワークの成長速度を構造的に加速する | infra | 05-19 | cmd_2878: gate_report_formatのo |
| cmd_2881 | startup gate BLOCK 3セッション連続。dashboard-update FAIL率16%(8/50)だがskill_execution_logにFAIL 1件のみ。ログ乖離の有無を含め根因を特定し対処方針を出す | infra | 05-19 | dashboard-update Gate20 8/50は実 |
| cmd_2882 | cmd_2881偵察で判明: dashboard-update FAIL率16%(8/50)は全てcmd_test_*6件+誤呼出し2件。実運用FAILゼロ。分母からテスト用cmdを除外し3セッション連続startup BLOCKを解消する | infra | 05-19 | Gate20のskill FAIL率でcmd_test_*と |
| cmd_2884 | 教訓健全度ALERT(useful_rate=16.7%)の根因=フィードバック記録率17%(参照36→記録6)。注入教訓のうち参照したがフィードバック未記録分を自動的にnot_usefulとして記録し、effectiveness_scoreの分母を正常化する | infra | 05-19 | record_lesson_feedback.shに未記載の |
| cmd_2885 | Obsidian [[リンク]]1597あるが大半が静的deepdive参照。cmd間因果辺が成長しない根因=origin記入(入口)はあるがsemantic-map還流(出口)がない。GATE CLEAR時にorigin+depends_onから因果辺を自動追記し、cmd数に比例してNWを成長させる | infra | 05-19 | GATE CLEAR時のsemantic index更新pa |
| cmd_2887 | 前セッションでscope/context stale残存が2件連続FAIL(cmd_2875+cmd_2880)。家老がLK-A02 v7で修正済みだがテスト未追加。再発防止テストを追加する | infra | 05-19 | reset_stale_fieldsのscope/conte |
| cmd_2888 | ac_phase_mixing等のgate FPが今セッション6回BLOCK。高FP gateを自動検出し修正候補を提案する仕組みで、gate品質の学習速度を最大化する | infra | 05-19 | Gate 13.8のFP率計算を独立スクリプト化し、閾値超g |
| cmd_2891 | CoDD台帳の最終更新が5/15で17日間停滞。修行サイクルにCoDD速度改善ラウンドを追加し、idle忍者にCoDD refactorを自動配備+軍師レビューで品質担保。インフラ最適化と忍者成長を同時に回す | infra | 05-19 | context/training-cycle.mdにCoDD |
| cmd_2892 | 196ファイル1766テストが蓄積。追加のみで淘汰なし。殿の3問検証(リグレッション検出実績/変更頻度/維持コスト)で低価値テストを特定し統合/削除方針を出す | infra | 05-19 | unit 196ファイル/現状1765テストを3問基準で棚卸 |
| cmd_2893 | cmd_2892偵察で低価値テスト10ファイル(削除4+統合6)を特定。790行削減+10ファイル削減でCI保守コストを下げる | infra | 05-19 | 低価値bats 10ファイルを4削除+6統合し、unitファ |
| cmd_2894 | cmd_2892偵察の10件は5%。196ファイル中62ファイル(32%)が1-3テストの小ファイルで同一スクリプトのテストが分散。スクリプト単位で統合し196→推定130ファイルに圧縮する | infra | 05-19 | 1-3件の小規模Bats 51ファイルを6本のスクリプト単位 |
| cmd_2895 | テスト196ファイル蓄積の根因=追加時にファイル粒度ガイドラインなし。追加test_*.bats作成時に同一対象スクリプトの既存テストファイルを検出→統合を促しファイル肥大化を構造的に防止する | infra | 05-19 | pre-commitで新規tests/unit/test_* |
| cmd_2897 | ac_phase_mixing FP率100%(3/3)。commitは忍者の通常完了動作であり実装ACに書くのが自然。deliveryキーワードからcommit/コミットを除外し偽陽性を根絶する | infra | 05-20 | cmd_save.shのAC phase mixing de |
| cmd_2898 | 将軍がcmd_save BLOCK後にフリーズする根因=どの行のどのキーワードがBLOCKを引き起こしたか不明で1箇所ずつ修正→再BLOCK→探す→修正の繰り返し。全BLOCK要因を一括表示し1回の修正で全解消できるようにする | infra | 05-20 | cmd_save.shのBLOCK/WARN終了サマリにチェ |
| cmd_2900 | gws CLIのGmail操作知識がcontext/infrastructure.mdに不足。auth statusが暗号化credentialsを検出できないバグがあり、将軍がログアウトと誤判断→殿に無駄なブラウザ認証を依頼した。実APIで確認すれば1秒で動くことを確認できた。知識不足が確認不足を招く構造を修正する | infra | 05-20 | context/infrastructure.md §gws |
| cmd_2902 | 因果NW成長が停止している根因=cmdのoriginフィールドが空/noneでもWARN止まりで通過する。causal_resource_rows()は実装済みだがorigin空では辺が生成されずsemantic_index還流が不発。originに[[リンク]]1つ以上を必須化しBLOCKで強制する | infra | 05-20 | origin空/none/リンクなしをBLOCKとして固定す |
| cmd_2903 | 掲示板が100件に膨張(open85件)。bulletin_archive.shがPython SyntaxErrorで動かない(L177-178のf-stringエスケープ漏れ)。真因=手動実行前提で自動パスがなくバグが放置された。構文修正+bulletin_write.shに閾値超過時の自動アーカイブ呼出しを追加し、掲示板肥大化を構造的に防止する | infra | 05-20 | bulletin_archive.shのSyntaxErro |
| cmd_2904 | Codex CLI忍者がidle時にsafe_send_clear()で無条件respawn-pane -kされ無限ループ(198回/今日)。根因=L754のcodex分岐がtask statusを確認せずidle/in_progress問わず一律respawn。idleならcodex /newで十分。respawnはin_progress時のみ必要。task status分岐を追加し無限ループを根絶する | infra | 05-20 | Codex idle+no_task時に_handle_au |
| cmd_2906 | cmd_2904がCodex+idle時にsafe_send_clearを呼ばない即returnを追加した結果、Codex忍者がidle時にCTXリセットされなくなった(GPT忍者3名のCTX蓄積中)。修正: (1)_handle_auto_clearの即returnを削除 (2)safe_send_clear内のCodex分岐でtask statusを確認し、idle/done→respawn分岐スキップ→clear_cmd=/new経路に落ちる。in_progress→respawn-pane -k維持 | infra | 05-20 | ninja_monitor.shのCodex idle時 / |
| cmd_2907 | cmd_2906でCodex idle時を/new経路に変更したが、Codex CLIが/newをtask in progressで拒否しCTXリセット不能。元のrespawn-pane -k経路に戻す | infra | 05-20 | Codex safe_send_clearのテスト期待値をr |
| cmd_2908 | cmd_save.sh/cmd_publish.sh BLOCK時にPostToolUse hookのGuard 0が発火せず、将軍がBLOCK後に停止する。根因はexit_code抽出jqがClaude Codeの実payload構造にマッチしないこと | infra | 05-20 | post-bash Guard 0がClaude Code実 |
| cmd_2910 | 因果辺のoriginノード名の68%がセマンティクスインデックス未登録。GATE CLEAR時にoriginノードをaliases照合し、未登録ノードをinsights.yamlにpending蓄積→概念自動成長を実現する | infra | 05-20 | cmd_complete originノードを専用にalia |
| cmd_2911 | lessons_karo.yamlが35件上限に到達し新規教訓追加がBLOCK。LK-A01にv8吸収(設計意図確認)とLK013(STALL再配備3点確認)をA系列に統合し件数を削減する | infra | 05-20 | LK-A01へv8設計意図確認を統合し、LK013をLK-A |
| cmd_2912 | insights.yamlに蓄積されたpending概念22件がセマンティクスインデックスに昇格されず手動待ち。類似概念スコア照合で既存概念のaliases自動拡張し、因果NWの到達性を自動的に拡大する | infra | 05-20 | pending semantic insightsを類似度ス |
| cmd_2915 | L7成長速度最大化のなぜなぜ7回→軍師検証で律速=aliases品質と判明。改善にはNO_MATCHの内容(purpose/target_path)が必要だが現在記録されていない。計測基盤を先に作り、データ駆動でaliases拡充する道具を整える | infra | 05-21 | HEAD既存のsemantic NO_MATCH記録を現物確 |
| cmd_2917 | deploy_task.shがexit 1で終了した場合、maybe_notify_draft_review(L6712)が成功パスにのみ存在するため軍師へのdraft_review通知が送信されない。EXIT trap(L323)にdraft_reviewフォールバックを追加し、配備失敗時も軍師レビューフローが途切れないようにする | infra | 05-21 | deploy_task.shのEXIT trapにdraft |
| cmd_2918 | L7現物確認でNO_MATCH率表示が家老gateのみで将軍gateにないことを発見。L7は将軍が管理するがL7健全度が起動時に見えない。家老gate(L181 show_semantic_no_match_metrics)と同じ計測セクションを将軍gateに追加する | infra | 05-21 | 将軍startup gateにセマンティックNO_MATCH |
| cmd_2919 | 殿のクエリがsemantic_searchを経由するが、NO_MATCH時の記録がない。L7の最重要消費者(殿)側の計測が盲点。NO_MATCHカウントのみ記録し(クエリ内容は非記録)、startup gateで可視化する | infra | 05-21 | prompt_state_injectのsemantic_s |
| cmd_2920 | L7成長速度の律速=aliases品質(軍師検証確定)。cmd_complete時にsemantic_index_update.shがpurposeからaliases候補を生成する基盤(L437 candidate_aliases)は既にあるが、NO_MATCH時の候補を既存概念のaliases拡充に使う経路がない。NO_MATCHログ(cmd_2915)のpurposeキーワードをpending aliasesに自動蓄積し、L7f(score閾値自動昇格)基盤でaliasesに自動追加する | infra | 05-21 | NO_MATCH purposeをpending alias |
| cmd_2921 | gate_skill_script_refs.shの3セッション連続WARNを解消する。5件全て現物確認済みでインタフェース変更なし | infra | 05-21 | gate_skill_script_refs.shのWARN |
| cmd_2922 | semantic_searchのヒット率を定量計測し、NO_MATCHデータをaliases自動成長パイプライン(cmd_2920)に流す道具を作る。軍師実測でヒット率45.7%、因果展開timeout誤判定バグも発見済み | infra | 05-21 | semantic_searchのalias層ヒット率を3入力 |
| cmd_2913 | cmd_2909のstartup gate表示は1回/セッション。家老がcmd受領時に毎回semantic_searchを実行し因果概念を表示することで消費頻度を大幅に向上させる | infra | 05-21 | cmd_2913は家老task_haltにより中止。軍師レビ |
| cmd_2923 | 既存Guard 0にinbox未読チェック追加+既存inbox_mark_read.shに対処引数必須化。既存cmd_save.sh Session Stateが自動でBLOCK履歴を蓄積し累計昇格する(自己改善ループは既存インフラに内蔵済み) | infra | 05-21 | — |
| cmd_2924 | cmd_2922(ストレステストツール本体)を3つの自動発火トリガーに接続する。軍師5W1H設計(blt_013243)に基づく。手動実行→自動組込みで意志依存をゼロにする | infra | 05-21 | L7 semantic stress testの3トリガー配 |
| cmd_2926 | idle忍者の修行ACに対象スクリプトの機能用途をaliases候補として提案するステップを追加。6忍者並列でaliases品質を加速。修行の成果がL7パイプラインに直結する | infra | 05-21 | context/training-cycle.mdのCoDD |
| cmd_2927 | index.mdにrelated_conceptsフィールド追加。semantic_search.shで1概念ヒット時に関連概念も注入。45概念の相互接続で配備時コンテキスト密度を倍増する | infra | 05-21 | semantic indexにrelated_concept |
| cmd_2925 | semantic_searchの道具は存在するが全ロールの手順に未記載。家老karo.md=0件、忍者ashigaru.md/CLAUDE.md=0件、軍師gunshi.md=レビュー時0件。Phase 4: 手順にないものは使われない。全ロールのinstructions/recovery手順にsemantic概念確認ステップを追加する | infra | 05-21 | cmd_2925は家老task_haltにより中止。軍師レビ |
| cmd_2928 | skill_auto_improve.shのreasonグルーピングがcmdID/ninjaID含みで同一根因が別パターン化。古いパターンのlast_failが更新されず14日カットオフで除外→Gate 20.7が12件中1件しか表示しない。グルーピングキーを正規化し、last_failを常時最新に更新する | infra | 05-21 | skill_auto_improveのFAIL reason |
| cmd_2931 | 教訓注入のuseful率7.1%(95注入中2有用)。現在のkeyword/tag/pathマッチは意味を理解しない。semantic_searchが既にdeploy_task.shで概念を検出しているため、概念にrelated_lessonsフィールドを追加し、検出された概念の教訓をスコアブーストで優先注入する | infra | 05-21 | semantic概念related_lessonsとdepl |
| cmd_2932 | 教訓健全度ALERT(useful_rate=16%)の根因修正。DM-Signal固有教訓(L510/L630/L594/L509/L097)がcross-project opt-inで全infra taskに漏洩→全件NOT_USEFUL。有効性0%教訓のauto-deprecated化+cross-project scoringにproject固有語比率フィルタを追加し、注入精度を改善する | infra | 05-21 | deploy_task.shのcross-project教訓 |
| cmd_2933 | assumptions_bulletin_count_grep_evidenceのFP率66%(2/3)を改善する。claimにblt_XXXX(掲示板ID)を含む場合は掲示板自体が検証済みソースであり、grep証跡不要。bulletin ID引用をgrep_evidence_patの許容パターンに追加する | infra | 05-21 | cmd_save.shのbulletin件数claim検証で |
| cmd_2935 | 殿が5/21 02:39にスクショで確認した事象: 1着信に対しnudge(inbox1)が2回送信される。既存のdebounce/dedup機構があるにもかかわらず二重送信が発生する根因を特定する | infra | 05-21 | 二重nudgeの根因は同一agentに複数のinbox_wa |
| cmd_2936 | 修行中の忍者がAC5で概念名付きaliases候補を提案する形式を設計し、parse_pending_semantic_insightsがその形式を認識→概念名で直接マッチ→similarity_score不要でauto-promote可能にする。修行6忍者並列で高品質aliases蓄積を加速する | infra | 05-21 | 修行AC5を概念名付きalias行へ更新し、直接昇格を検証す |
| cmd_2937 | cmd_2935偵察結果に基づく修正。根因=同一agentにinbox_watcher.shが2本以上常駐し同一イベントを並列処理。singleton lockでagent別1プロセスを保証し、debounce/fingerprint check+writeを同一flock内でatomic化する | infra | 05-21 | inbox_watcherのagent別singletonと |
| cmd_2938 | cmd_2936で修行AC5→auto-promote直結を実装したがPENDING_ALIAS_DIRECT=0件。なぜなぜ7回: (1)忍者のinsight_writeのsource引数が未指定→parse側フィルタ(L651 training含む)に不合致→スキップ (2)insight自体がinsights.yamlに残っていない(archiveに退避or書込失敗)。修正: 修行テンプレートにinsight_write source=training引数を明示+書込後のgrep検証ACを追加+parse側のsourceフィルタ緩和 | infra | 05-21 | DIRECT経路のtraining source alias |
| cmd_2941 | スキル自動成長エスカレーションが3セッション連続。report-writeスキルのFAIL理由 assumption_invalidation: is str (must be dict) がSKILL.md改良5回で未解消。根因はgate_report_format_main.py L154のdict型チェックに対し、report_field_set.shまたはテンプレートがstring型で生成している可能性。スクリプト側を修正し、assumption_invalidationが常にdict形式で出力されるようにする | infra | 05-21 | report_field_set.shのassumption |
| cmd_2942 | verdict-checkスキル自動成長が3セッション連続エスカレーション。binary_checks resultにyes/no以外(空/waive/PASS/FAIL)が混入しcmd_complete_gateがBLOCK。SKILL.md改良5回で未解消=忍者の意志依存。report_field_set.shにbinary_checks result値のバリデーション(yes/no以外をBLOCK)を追加し、不正値を構造的に排除する | infra | 05-21 | binary_checks resultのyes/noバリデ |
| cmd_2943 | dashboard-updateスキル自動成長が3セッション連続エスカレーション。dashboard_update.sh exit=1が複数cmd(cmd_2739/cmd_karo_test/cmd_2514等)で再発。SKILL.md改良5回で未解消=スクリプト側のエラーハンドリングまたはデータ前提にバグ。exit=1の根因を特定し修正する | infra | 05-21 | dashboard_update.shのreport探索をp |
| cmd_2945 | 教訓健全度ALERT(useful_rate=16.7%)が3セッション連続。根因: 忍者がreport YAMLでuseful:false/trueと記入しているが、lesson_impact.tsvにフィードバックが還流されていない(全件status=pending)。lesson_deprecation_scan.shが退役候補を検出できず、低useful教訓が永続注入される。cmd_complete_gate.shまたは完了処理フローでreport YAMLのlessons_useful→lesson_impact.tsvへの書戻しを修正する | infra | 05-21 | lesson_impact.tsvへlessons_usef |
| cmd_2944 | cmd-completeスキル自動成長が3セッション連続エスカレーション。2パターン: (1)lesson_done_missing=cmd_complete_gateがlesson reviewフラグ不在を検出 (2)ac_version_mismatch task=d41d8cd9(空ハッシュ)=karo_direct配備でタスクYAMLにac_version未設定。SKILL.md改良5回で未解消。スクリプト側でkaro_direct配備時のac_version自動補完+lesson_done検出ロジック修正 | infra | 05-21 | _compute_ac_hash()修正(check:フィー |
| cmd_2946 | cmd_2936でDIRECT経路を実装、cmd_2938でテスト21件PASSしたが、本番でPENDING_ALIAS_DIRECT昇格が0件。修行12回転(hayate4+kagemaru4+saizo4)でinsight蓄積されたがaliasesに昇格していない。テストは通るが本番で動かない=テストと本番の乖離。semantic_index_update.shのDIRECT昇格コードパスがなぜ本番で発火しないかを特定し修正する | infra | 05-21 | semantic_index_update.shのDIREC |
| cmd_2948 | 起動チェックでSKILL.md参照WARNが3セッション連続。scriptが更新されたがSKILL.mdが追従していない4件を更新し、スキル記述と実装の乖離を解消する | infra | 05-21 | SKILL.md 4件を現script仕様へ追従更新し、対象 |
| cmd_2949 | cmd_2947でYAML存在チェックを追加したが、kagemaru R9で再発(本セッション4件消失)。忍者のinbox_write(家老通知)完了前にclear発動する競合が残存。3条件(YAML存在+verdict存在+家老通知完了)に拡張して根絶する | infra | 05-21 | ninja_monitorのauto-clear repor |
| cmd_2950 | 修行がtarget_path未指定で全ラウンド実行されており、忍者が裁量でスクリプト選択→aliases薄概念が放置。deploy_task.shの修行配備時にaliases品質の低い概念のスクリプトを優先指定し、修行が自然にaliases品質を引き上げる仕組みにする | infra | 05-21 | aliases薄概念Top10を出す semantic_al |
| cmd_2951 | deploy_task.shが次ラウンド配備時に前ラウンドのGATE未完了のまま忍者に/clear送信し、報告YAMLが消失する(本セッション6件、GPT忍者18.5%/Sonnet5.6%)。配備前にpending report存在チェックを追加し、GATE完了まで配備をBLOCKする | infra | 05-21 | deploy_task.shが対象忍者のGATE未処理報告を |
| cmd_2952 | deploy_task.sh(cmd_2950/2951変更)+bulletin_write.sh変更がSKILL.md 5件に未反映。startup gate 3セッション連続WARN解消 | infra | 05-22 | SKILL.md 5件をbulletin_write.sh/ |
| cmd_2953 | 修行targetを[[リンク]]数昇順で選択し、孤立ファイルから順にリンクネットワークを育てる。現状944 mdファイル中88%が孤立。修行ACに[[リンク]]追加を組込み、Obsidianグラフを修行サイクルで自然に成長させる | infra | 05-22 | 修行targetをMarkdownリンク数昇順で選び、孤立M |
| cmd_2955 | cmd_2954設計変更(軍師REQUEST_CHANGES)。ファイル間直接リンクではなく概念名リンクのみ挿入。各resourcesファイルに所属概念名への[[概念名]]リンクを挿入し、概念をハブとするスター型ネットワークを構築 | infra | 05-22 | docs/semantic-index/index.mdから |
| cmd_2954 | index.mdの46概念×resourcesをパースし、同一概念内resources間+概念⇔resourcesの双方向[[リンク]]を自動挿入。孤立率88%を一括削減。殿直接指示 | infra | 05-22 | — |
| cmd_2957 | deploy_task.sh inject_direct_training_templateのAC2/AC5が概念名リンク(ハブ方式)を許容している。殿確定の分離原則(context/obsidian-link-principles.md)に準拠し、ファイル間直接リンク方式に修正する | infra | 05-22 | deploy_task.shのL4修行テンプレートをファイル |
| cmd_2959 | 参照scriptがSKILL.mdより新しい11ファイルを更新し、スキル指示とスクリプト実態の乖離を解消する | infra | 05-22 | SKILL.md 13件の参照script仕様追従を更新し、 |
| cmd_2960 | shutsujin_departure.sh L945が将軍watcherをASW_DISABLE_ESCALATION=1で起動し、GATE CLEAR通知が将軍に届かない。cmd_2403/2694で対症療法したが真因が残存。shutsujin側を修正し構造的に根絶する | infra | 05-22 | shutsujin_departure.shの将軍watch |
| cmd_2962 | 将軍がcmd起票時にsemantic_search.shを使っていない。grepでは既知キーワードしか探せず、関連概念の見落としが起きる。起票前hookに10問目を追加し、将軍が毎回semantic_searchを実行する構造にする | infra | 05-22 | Guard 0の起票前確認を10問へ更新し、semantic |
| cmd_2963 | lord_conversation.jsonlのアーカイブディレクトリは3月に作成済みだが退避処理が未実装で全セッションの対話が消失している。clear_prep_check.shに全文退避+知識抽出を追加し、長期記憶を構造的に保存する | infra | 05-22 | clear_prep_check.shにlord_conve |
| cmd_2964 | 全文記録(24MB/79日)とsemantic_search(0.3秒)は動いているが、セッション中に発見した知識がObsidianリンクやaliasesに整理されずに消えている。全ロールの/clear前処理と作業完了時に記憶整理Phaseを追加し、短期記憶→長期記憶の移行を構造的に強制する | infra | 05-22 | 全ロール記憶整理Phaseとしてclear_prep_che |
| cmd_2965 | 全文記録(lord_conversation_archive 24MB/79日分)がJSONLファイルで概念検索不能。SQLite(multi_agent_shogun_memory.db)に構造化して格納し、semantic_searchから到達可能にする。先にDBを作ることでLLMが外部DBに飛びつくパターンマッチを環境で封じる(殿裁定2026-05-22) | infra | 05-22 | SQLite記憶DBインポータを追加し、lord_conve |
| cmd_2966 | cmd_2965のconversationsテーブルは殿×将軍の対話のみ。殿は家老/軍師/忍者にも直接指示する。全ロールの全イベント(inbox/掲示板/gate/報告/insight)を統合するeventsテーブルに拡張し、conceptsカラムでsemantic_search照合結果を格納してObsidian/セマンティクスインデックスと連携する | infra | 05-22 | memory_db_init.shを追加し、eventsテー |
| cmd_2968 | 報告テンプレートのverdictフィールドにYAMLコメント付き空文字列が残存し、忍者がautofix前に保存するとverdict空でGATE BLOCKが発生(14件検出)。テンプレートからコメント行を除去し汚染を根絶する | infra | 05-22 | 報告テンプレートのverdict空値コメントを生成元から除去 |
| cmd_2970 | eventsテーブルのdetailをLIKE検索すると24MB全スキャン。FTS5仮想テーブルで全文検索を高速化し、parent_event_id(因果チェーン)とimportance(重要度)カラムを追加して検索品質と到達可能性を向上する | infra | 05-22 | events_fts(FTS5)をsummary/detai |
| cmd_2971 | deploy_task.sh/restart_watchers.sh変更後にSKILL.md 4件が未更新で3session連続WARNが発生。scriptの最新挙動をSKILL.mdに反映しgate判定をOKにする | infra | 05-22 | SKILL.md 4件を最新script挙動に追従し、gat |
| cmd_2972 | is_gate_or_hook_addition_cmd()がSKILL.md追従/DB拡張/semantic_search等の非gate追加cmdをgate追加と誤判定しFP率100%(3/3)。L299除外キーワードに追従/更新/拡張を追加し偽陽性を解消する | infra | 05-22 | is_gate_or_hook_addition_cmdの追 |
| cmd_2973 | dashboard-update/verdict-check/cmd-complete/report-writeの4スキルがSKILL.md改良5回超で効果なし。code_fix_requiredエスカレーション9件。各スキルのFAIL根因を特定し修正cmdの設計材料を作る | infra | 05-22 | 4スキルFAILは、dashboard_updateのrep |
| cmd_2974 | GPT忍者へのnudge自動到達率が0%(11/11手動)。deploy_task.shのEXIT trap内でnudgeが確実に送信されるよう修正し、配備後の自動到達を保証する | infra | 05-22 | deploy_task.shのEXIT nudge arm位 |
| cmd_2975 | CI並列実行時にflaky test 2件(T-005+AC4-2)が発生。テスト間の状態共有が根因。並列隔離で安定化する | infra | 05-22 | T-005とAC4-2の並列flaky要因をテストfixtu |
| cmd_2976 | memory_db_import.pyにFTS5+拡張列が実装済みだがDBが再構築されていない。再実行してDBスキーマを最新化する | infra | 05-22 | memory_db_import.pyを再実行し、data/ |
| cmd_2977 | eventsテーブルが全件conversation型。bulletin_board.yamlのエントリをevent_type=bulletinとして投入し、GATE CLEAR/家老報告/INSIGHT等の非会話イベントを検索可能にする | infra | 05-22 | memory_db_import.pyのbulletin投入 |
| cmd_2978 | insights.yamlの気づきエントリをevent_type=insightとして記憶DBに投入し、学習ループの気づきを検索可能にする | infra | 05-22 | insights.yamlをmemory DBのevents |
| cmd_2979 | eventsテーブルのconcepts列がJSON配列のTEXT格納で検索が遅い。event_concepts(event_id, concept_name)ジャンクションテーブルに正規化しJOINで高速検索+概念別集計を可能にする | infra | 05-22 | memory_db_import.pyにevent_conc |
| cmd_2981 | 記憶DBが手動実行でしか更新されない。clear_prep_check.shの記憶整理Phaseにmemory_db_import.py実行を追加し、毎/clear時にDBが自動再構築されるようにする | infra | 05-22 | clear_prep_checkの記憶整理Phaseでmem |
| cmd_2982 | append_lord_conversation()でJSONL書込み後にDBへもINSERTし、lord_conversation全イベントがリアルタイムでDBに蓄積されるようにする | infra | 05-22 | append_lord_conversation()のJSO |
| cmd_2984 | journal_mode=DELETEでリアルタイムINSERTと再構築が競合しdatabase locked発生。WALモードに変更し並行書込みを許可する。再構築もDROP+CREATEからINSERT OR REPLACEに変更し時間短縮 | infra | 05-22 | memory_db_import.pyのWAL再構築を確認し |
| cmd_2985 | inbox_write.shの全agent間通信(配備指示/報告完了/gate_clear/nudge)をevent_type=inboxとして記憶DBにリアルタイムINSERTする | infra | 05-22 | inbox_write.shのYAML永続化成功後にeven |
| cmd_2987 | 忍者の報告YAML書込み(report_field_set.sh)をevent_type=reportとして記憶DBにINSERTし、学習ループの成果(binary_checks/lesson_candidate)がDB検索可能になるようにする | infra | 05-22 | memory_db_live_insert.pyにrepor |
| cmd_2991 | cmd品質記録(cmd_design_quality.yaml)をevent_type=cmd_qualityとして記憶DBにリアルタイムINSERTし、gate FP/BLOCK分析がDB検索で即座に可能になるようにする | infra | 05-22 | cmd_design_qualityの品質記録をevent_ |
| cmd_2992 | memory_db_import.pyの/clear時再構築にskill_execution_log/完了cmd archive/pending_decisionsの3ソースを追加し、バッチ再構築時の網羅性を完成させる | infra | 05-22 | memory_db_import.pyのバッチ再構築にski |
| cmd_2995 | スクリプト内部変更(DB INSERT追加等)でもSKILL.md追従WARNが発火する偽陽性を解消する。3セッション連続BLOCK再発の構造的原因 | infra | 05-22 | script_refs_checked_at markerを |
| cmd_2997 | ルート直下の0バイト空DB削除と、eventsテーブルと完全重複するconversationsテーブル(27,154件同数)を整理する | infra | 05-22 | 0バイトDBを削除し、conversations実体テーブル |
| cmd_2998 | 日本語の長いクエリでFTS5検索がタイムアウト(10秒超)する問題を改善する | infra | 05-22 | semantic_search.shのmemory_db_s |
| cmd_3000 | Google Chrome公式のAIエージェント向けモダンWeb APIスキルを導入し、FE開発品質を向上させる | infra | 05-22 | Modern Web Guidanceを導入し、semant |
| cmd_3001 | 記憶DBのスキーマ+event_type分布+サンプル行をmemory_db_import.pyの--build後に自動生成し、LLMが自然言語→SQL変換できる基盤を構築する | infra | 05-22 | memory_db_import.pyのschema mar |
| cmd_3002 | memory_db_query.shにSELECT以外のSQL(DELETE/UPDATE/DROP等)をBLOCKするガードを追加し、記憶DBの安全な汎用クエリ実行を保証する | infra | 05-22 | memory_db_query.shにSELECT-only |
| cmd_3005 | 全PJ(dm-signal/infra/google-classroom/database/simple-ocr等)のドキュメントファイルを棚卸しし、記憶DBに投入すべき知識資産の全体像を把握する | infra | 05-22 | 全登録PJのmd/yaml/yml/txt/rstをフル走査 |
| cmd_3007 | 知識パスへのgrep実行を検知し、記憶DB検索結果を自動注入する。3層記憶を経由せずに行動する迂回路をふさぐ | infra | 05-22 | 知識パスgrep/rg検知時にmemory DB検索結果をa |
| cmd_3008 | 記憶DB検索時にtarget=自分のagent_idでフィルタしていないため、殿が他ロールに向けた発言を自分宛てと誤認するバグを修正する | infra | 05-22 | memory DB検索のtargetフィルタ実装を検証する回 |
| cmd_3009 | post-shogun-inbox-check.shがlord_conversation.jsonlのinboundを全件表示し、殿が家老paneに入力した内容を将軍が自分宛てと誤認するバグを修正する | infra | 05-23 | post-shogun-inbox-check.shの殿発言 |
| cmd_3010 | 記憶3層ハーネスPhase 2。cmd_3005棚卸し結果から品質保証済みの3カテゴリ132件を記憶DBに投入し、検索精度を向上させる | infra | 05-23 | — |
| cmd_3011 | 記憶DBにcontext/教訓/チェックリスト等のドキュメントファイルを投入する手段がない。build_dbに7番目のソースとしてドキュメントファイル投入を追加する | infra | 05-23 | memory_db_import.pyの--doc-dirs |
| cmd_3012 | cmd_3011で追加した--doc-dirsを使い、品質保証済み153件を記憶DBに投入する。殿裁定(2026-05-23): 品質未保証データ投入禁止、132件+記事21件に限定 | infra | 05-23 | 品質保証済み153件をmemory DBへdocument投 |
| cmd_3014 | Phase 2追加投入。品質保証済みだが未投入の164件を記憶DBに投入する。event_type=documentのまま、source_fileパスが自然な分類子となる(殿裁定: 独自ラベル分類は不要) | infra | 05-23 | cmd_3014: 8ディレクトリ253文書をevent_t |
| cmd_3013 | 投資知識とシステム知識とcontext文書を同一event_type=documentに混在させると検索結果が混乱する(殿指摘2026-05-23)。--event-typeでevent_typeを指定可能にし、投入時に分離する | infra | 05-23 | — |
| cmd_3015 | 投資知識辞書108件とシステム知識辞書14件が記憶DBに投入済みだが、セマンティクスインデックスとObsidianリンクに未接続。3層全てに通す(殿指摘2026-05-23) | infra | 05-23 | 知識辞書2概念をsemantic-indexへ追加し、sys |
| cmd_3016 | systems-knowledge-base/systems/の7件(Karpathy除く)は最終確認から35-43日以上経過。GitHub repoの最新バージョン+主要変更を調査し知識辞書を更新する | infra | 05-23 | systems知識辞書7件を2026-05-23時点のGit |
| cmd_3017 | cmd_save.shのshow_lord_conversation_matches()がdirection=inboundのみでフィルタし、target未確認のため殿が家老/軍師宛てに発した発言が将軍のcmd設計時に関連発言として表示される。cmd_3008/3009(post-shogun-inbox-check.sh)で修正した同構造バグをcmd_save.shにも適用する | infra | 05-23 | cmd_save.shの殿発言検索にtargetフィルタを追 |
| cmd_3018 | ci_status_check.sh L38の--limit 1が最新run=in_progressの場合UNKNOWNを返し、dashboard_auto_section.shがcheck failedと誤表示する。--limit 2にして2件目(completed)のconclusionを返すことで、CI実行中でも前回結果を正しく表示する。LK001(cmd_2792)で根因特定済み | infra | 05-23 | ci_status_check.shが最新2件から最新com |
| cmd_3020 | deploy_task.sh L4283にtarget_filesマッチングがあるがtarget_files未設定の教訓はタグのみでマッチし全cmdに注入される。有用率0%教訓4件(L510等)の共通根因=tag=universalが広すぎて無関係cmdに注入。target_files未設定教訓に対しても、教訓のtags+cmdのtarget_pathの関連性を考慮したフィルタを追加する | infra | 05-23 | target_files未設定のuniversal教訓にta |
| cmd_3021 | NewStandard PF問合せで5回試行錯誤した。根因: db-checkスキルにtier_visibility_settingsのスキーマ(tier_id+portfolio_settings JSON構造)が未記載、portfolio_metricsのmetrics_json実キー(total_return等)が未記載、接続時のcwd+PYTHONIOENCODING注意が未記載。追記して次回から一発で到達可能にする | infra | 05-23 | db-checkスキルにNewStandard/Tier可視 |
| cmd_3022 | verdict-check SKILL.md改良5回効果なし(binary_checks_fail)。忍者がbc:noのまま報告完了通知を送るとcmd_complete_gateでBLOCKされるが、inbox_write.sh report_received分岐のPhase 2とPhase 3の間にbc:no検出BLOCKを追加し、忍者の報告完了をその場で差戻す。意志依存を排除する構造予防 | infra | 05-24 | inbox_write report_receivedでve |
| cmd_3024 | 全ロール(将軍・家老・軍師・忍者)で操作時にセマンティクスインデックスからスキルを自動推薦する。殿の入力テキストを検索キーにsemantic_searchを呼び、関連スキルをLevel 5(recommend)で表示する。殿裁定: 完全自動+全ロール+原理1つ+BLOCK不可+各論パッチ禁止 | infra | 05-24 | prompt_state_inject.shにsemanti |
| cmd_3025 | q8_縮小表現(quality_gate_q8_scope_expression)のFP率66%(2/3)。scope_mode=focusedのcmdはスコープ限定が正当なので除外すべき。L2536の_Q8_SCOPE_EXEMPTにscope_mode判定を追加する | infra | 05-24 | cmd_save.sh q8縮小表現WARNでscope_m |
| cmd_3026 | gate_skill_script_refs.shが4スキル(codd-fix/idle-persist/karo-direct/recon-dual)で参照スクリプトがSKILL.mdより新しいとWARN。3セッション連続startup BLOCK要因。各SKILL.mdのscript_refs_checked_atを現在日時に更新し、参照スクリプトの変更がSKILL.md手順に影響しないか確認する | infra | 05-24 | 4スキルのscript_refs_checked_atを20 |
| cmd_3027 | Phase 1(cmd_3024)でスキル推薦表示を全ロールに実装した。Phase 2は推薦が正しかったか計測する基盤を構築する。(2a)推薦ログ記録 (2b)source正規化 (2c)startup gate集計 (2d)recall miss補完の4段。全てロール非依存 | infra | 05-24 | スキル推薦ログ、source正規化、startup gate |
| cmd_3028 | render_lord_decisionsが将軍のresponse(軍師D0承認等)を殿の裁定として分類する問題を修正。lord_conversation.jsonl消費者17本の波及確認も実施 | infra | 05-24 | render_lord_decisionsをinbound限 |
| cmd_3029 | gate_fp_relaxation_proposal.py L119でWARN累計昇格(escalated_to_block)をFP(偽陽性)としてカウントしているバグを修正。WARN累計昇格=WARNが正しく問題を検出した証拠(TP)。TPをFPカウントするためFP率が実際より高く計算されALERTが誤発火し3セッション連続startup BLOCKを引き起こした | infra | 05-24 | WARN累計昇格をFPカウントから除外し、escalated |
| cmd_3030 | skill_auto_improve_stateのcode_fix_requiredが直近50件FAIL率0%でも14日間ALERTし続ける。直近FAIL率0%なら自動解除してALERT誤発火を防止。現状cmd_2993の1イベントが3忍者×5回=15回ALERTに膨張 | infra | 05-24 | gate_shogun_startupのcode_fix_r |
| cmd_3032 | context/infrastructure.mdが24日間未更新で連日WARN。lord_conversationデータフロー(live→アーカイブ→記憶DB)、記憶DB構造、Codex respawn-pane裁定、CI並列隔離等が未反映。将軍が/clear後にインフラ構造を参照できない真因を解消 | infra | 05-24 | context/infrastructure.mdへlord |
| cmd_3035 | cmd_3033(将軍Level 0-7)とcmd_3034(軍師Level 4)で将軍・軍師の洗脳防御を実装したが家老gateには洗脳チェックがない。家老の判断(配備/workaround分類/LGTM)でAnthropicの早期終了本能が影響するケースを防御する | infra | 05-24 | 家老startup gateにworkaround brai |
| cmd_3036 | CLAUDE.md Step 8にQ6(洗脳チェック)を追加したがgate検出がなく省略しても何も起きない(Level 2止まり)。gate_shogun_startup.shでQ6回答の有無を検証しLevel 4(gate BLOCK)に到達させる。軍師はcmd_3034でLevel 4実装済み。将軍も同等に | infra | 05-24 | gate_shogun_startup.shへQ6洗脳チェッ |
| cmd_3037 | 家老だけinstructions洗脳防御0件(将軍12件/軍師6件)の穴を塞ぐ。§0.1日常フィルタ+idle深い監査+軍師第三者検証の2層構造 | infra | 05-24 | 家老向け洗脳防御を§0.1/idle自走/instructi |
| cmd_3040 | lord_conversation_read.shは引数必須の手動実行道具スクリプト。hooks登録不可だがgateが意志依存と誤検出し7セッション連続ALERT。allowlistに追加して偽陽性を解消する | infra | 05-24 | lord_conversation_read.shをenfo |
| cmd_3041 | PDF/画像/ドキュメントの内容を確認してからリネームする汎用スキルを作成。Drive(gws)とローカル(mv)の両対応。全件内容確認を構造的に強制する | infra | 05-24 | skills/file-rename/SKILL.mdを新規 |
| cmd_3042 | cmd_3041+追加commit(27a9e4c7)でsource_location+FTS5は反映済み。未反映の日付3列(file_created_at/file_added_at/renamed_at)とINSERT前正規化ルールを追加する | infra | 05-24 | file-rename SKILL.mdへrename_pa |
| cmd_3044 | リネーム間違い時に元ファイル名に戻せる仕組みがない。リネーム前にファイル名一覧を保存し一括ロールバック可能にする。リスクは先にふさぐ(殿指示) | infra | 05-24 | file-renameスキルにリネーム前バックアップ、JSO |
| cmd_3046 | lord_conversation.jsonlが202行でMAX_ENTRIES=200を超過しsession_summary喪失リスク。200→500に拡張 | infra | 05-25 | conversation_retention.shのMAX_ |
| cmd_3045 | skill_auto_improve.shがcode_fix_cleared済みパターンを再分類→再エスカレーションするバグの修正。report-writeとverdict-checkで偽エスカレーションが毎起動発生し将軍の確認コストが累積する | infra | 05-25 | code_fix_cleared済みskill_auto_i |
| cmd_3048 | 殿の入力受信時に記憶DB FTS5検索で過去の関連裁定を将軍に自動注入する。現在grep/rg実行時のみDB利用で殿対話時は未接続(なぜなぜ7回で特定した穴)。prompt_state_inject.sh内に関数追加 | infra | 05-25 | prompt_state_inject.shの殿入力時mem |
| cmd_3049 | cmd_3048のFTS5は漢字/カタカナでagent=lord 0件(unicode61 CJK問題)。ext4上のlord専用キャッシュ(5417件)にLIKE検索(3-4ms)で差替え。殿の入力から2-4文字チャンクを抽出しOR検索。実データ検証で10件中8件ヒット確認済み | infra | 05-25 | lord ruling cache LIKE検索の検証を追加 |
| cmd_3050 | prompt_state_inject.shのsemantic_search呼出しがtimeout 0.30sで全語TIMEOUT(10/10=100%)。SEMANTIC_DISABLE_CAUSAL=1+SEMANTIC_DISABLE_MEMORY_DB=1追加+timeout 0.60sで安定HIT(8語全完了、max 298ms)。セマンティクスインデックス質的向上spec v3 Phase 1 | infra | 05-25 | prompt_state_inject.shのsemanti |
| cmd_3051 | ブラックホール概念修復(5概念94件の30文字超aliases削除)+alias長上限validation追加+殿の6原則を独立概念化。8語正しいHIT率 12.5%→改善。spec v3 Phase 2 | infra | 05-25 | 5概念の長文aliasesを削除し、6原則概念を追加、sem |
| cmd_3052 | Phase 2後の品質スコア63%(28/44)を93%(40/43)に改善。全概念ノイズalias掃除(39件30文字超+2件短いノイズ)+14語alias追加+first-layerスコアソート追加+validation(min_length+重複検出)+品質テスト自動実行+誤配置修正+リンク修復。spec v6 Phase 3a | infra | 05-26 | semantic index Phase 3a: spec準 |
| cmd_3053 | 共有repoでstage→auto-commit間に他忍者のauto-commitが割込みstage済みdiffを吸収する。cmd_3050でsaizoが発見。ninja_monitor.shのauto-commit前にgit diff --cachedで他忍者のstageを検出しスキップする条件を追加 | infra | 05-26 | ninja_monitorのauto-commit前に既存s |
| cmd_3054 | gate_improvement_triggerが同一ファイル+同一alert_typeで毎起動ALERTを発行し将軍の確認コストが累積。codd.md staleが3日連続(GA-379/380/382)。同一file+alert_typeの24h dedup条件を追加 | infra | 05-26 | gate_improvement_triggerに同一fil |
| cmd_3055 | Phase 3a後の品質88%(44/50)を維持しつつ、2文字語3語(証拠/結論/丁寧)の概念マッピングをテスト駆動で判定する。テストが判断し、将軍も殿も判断しない(自動化×強制) | infra | 05-26 | Phase 3bの2文字語3語をテスト駆動で概念マッピングし |
| cmd_3057 | stress_testのlordソースにtask-notification junk(toolu_/task-id等)が混入しNO_MATCH率を汚染している。2層防御フィルタを自動実行で実装し、正確なNO_MATCH率baselineを確立する | infra | 05-26 | semantic_stress_testのlord入力とca |
| cmd_3056 | 知識は無限に増える。PJ登録/ファイル作成/教訓追加の3経路で概念が自動的にセマンティクスインデックスに流入する仕組みを構築し、過去cmdの紐付けバックフィルで既存概念のcmd参照0件を解消する | infra | 05-26 | semantic_map_generate.shにPJ登録/ |
| cmd_3060 | セマンティクスインデックスの検索にaliases辞書引き(ブラインド6%)に加え記憶DB三層検索パス(FTS5+bm25()+IDF)を追加し、殿の実発言に対する概念到達率を56%以上に引き上げる。三層記憶アーキテクチャ(殿設計)の最初の接続 | infra | 05-26 | 記憶DB FTS→event_concepts→IDF概念ラ |
| cmd_3061 | startup gate 3セッション連続BLOCK。推薦precision 14%/偽陽性86%を改善し、recall miss(cmd-complete, dashboard-update)を解消する | infra | 05-26 | skill_recommend_metrics.shの計測対 |
| cmd_3062 | deploy_task.sh inject_related_lessonsがtarget_pathを無視し汎用教訓を注入するため、aliases修正等の特定ファイル向けタスクでUSEFUL率0%。target_path重み付けで教訓の関連度を向上させる | infra | 05-26 | inject_related_lessonsでtarget_ |
| cmd_3064 | cmd_3061軍師FAIL(Goodhart)の根因対処。growth_loop L677の4スキル集中を概念分離し、SKILL.md【X専用】パースでロールフィルタを追加。metrics.sh evaluable分母定義をrevertしてbaseline正常化 | infra | 05-26 | growth_loopのスキル集中を概念分離し、semant |
| cmd_3065 | パスA(cmd_3063 FTS5タグ伝播)で到達した概念から、related_conceptsをO(1) lookupして隣接概念に連鎖する層2パスを実装。片方向56%(102/180)の双方向強制化+バックリンク数事前計算+接続強度スコアで三層記憶の連想ネットワークを完成させる | infra | 05-27 | related_concepts隣接ランキングと双方向強制化 |
| cmd_3066 | 固定50語テスト=Goodhart(50語100%vsブラインド6%で実証)。ブラインドテストのみで改善判定する計測基盤を構築し、NO_MATCH高頻度語→品質テスト→テストセット追加の自動パイプラインで計測自体を自動成長させる | infra | 05-27 | semantic_stress_testのNO_MATCH高 |
| cmd_3067 | 追体験Q1-Q6が形骸化しテキスト処理に堕している(殿指摘2026-05-27)。結論を知っているから通過するだけで行動変容が生まれない。固定Q→殿の生発言Q動的生成(自己参照パラドックス回避)+自動化ターゲット必須フィールドで行動変換を強制する | infra | 05-27 | gate_shogun_startup.shの追体験検証に殿 |
| cmd_3069 | 洗脳パターンが連鎖する(P5→P8→P6)ことを発見したが対策が未実装。殿の介入率と将軍の自己検出率を自動計測し4象限で可視化する。殿の介入なしに洗脳を検知できる状態(成長象限)を客観的に追跡する。三往復洗脳覚醒レビューで設計確定済み | infra | 05-27 | gate_shogun_startup.shへ洗脳連鎖2x2 |
| cmd_3068 | bm25のIDF項が殿の最重要概念を最弱検索にする根幹バグを修正。IDF(頻出=非重要)をR(c)(最近高頻度=重要)に置換し、三層記憶+スキル推薦+概念検索の全システムを同時改善する。三往復洗脳覚醒レビューで設計確定済み | infra | 05-27 | BM25 FTSの概念ランキングとタグ伝播からIDF重みを除 |
| cmd_3070 | cmd_3068でIDF→R(c)置換したがブラインド30語delta=0.0pt。完全一致は偶然ではなくR(c)がスコアリングに影響していない証拠。集計パスの動作確認+R(c)実値ダンプで根因を特定する | infra | 05-27 | semantic_index.pyにSEMANTIC_REC |
| cmd_3071 | 殿未指示の/clear準備を実行した事故(2026-05-27 11:08)の再発防止。入口(discussion resource重複排除+target付与)と出口(clear準備スキルの殿指示検証ガード)の2点で防御 | infra | 05-27 | AC1 discussion dedup、AC2 clear |
| cmd_3072 | 推薦precision 3%(2/73)を改善。偽陽性TOP5(karo-direct:14,recon-dual:14,hensei:12,hensei-mixed:12,hensei-opus:12)はロール不一致推薦。3セッション連続BLOCK解消 | infra | 05-27 | cmd_3072は前提崩壊。ロールフィルタ/agent_id |
| cmd_3073 | deploy_task.sh変更(cmd_3062等)後にkaro-direct/recon-dualのSKILL.mdが未追従。gate_skill_script_refs.sh WARN 3セッション連続BLOCK解消 | infra | 05-27 | karo-direct/recon-dualのdeploy_ |
| cmd_3074 | 殿テスト(KJシリーズはいくつある？)で穴発見。個別PJ(kj-toilet/kj-role-count/kj-partshift)は記憶DBにあるがグループ概念が不在。雑な入力から正解に到達できるよう概念を埋め込む | infra | 05-27 | kj_seriesグループ概念をsemantic index |
| cmd_3075 | スキル推薦precision 0%/偽陽性100%の根因2つを修正し、計測精度を正常化する | infra | 05-27 | スキル推薦ログ重複抑止を実装し、対象Bats 11件全PAS |
| cmd_3077 | maintenance.pyの2006ハードコードとFEの2006送信を修正し、price/DTB3データを全期間取得可能にする。ノンレバ玄武の計算期間拡大 | dm-signal | 05-28 | 2006固定のbackfill開始年をFULL_HISTOR |
| cmd_3078 | 殿の裁定を学んだ瞬間に三層記憶へ自動貫通する仕組みを環境に埋め込む。記憶せよと言われてから動く意志依存を排除 | infra | 05-28 | 家老即停止指示によりcmd_3078実装を中止し、作業com |
| cmd_3079 | PortfolioEditor UIでsafe_haven_asset/absolute_assetを変更してもpipeline_config内のSafeHavenSwitch/AbsoluteMomentumFilterブロックに反映されないバグの全容を調査 | dm-signal | 05-28 | PortfolioEditor/BE save/API/本番 |
| cmd_3080 | skill_recommend_log.yamlのデダップ窓が10件と狭く、同一(agent_id, prompt_hash)ペアが数百回重複記録され、precision=0%/偽陽性100%の計測障害が3セッション連続でstartup BLOCKを発生させている。根因はprompt_state_inject.sh L226のrecommendations[-10:]。修正して正確な計測を復元する | infra | 05-28 | skill推薦ログの重複記録窓を200件へ拡張し、metri |
| cmd_3081 | cmd_3076(年制限全量特定)+cmd_3077(maintenance.py 2006→定数統一+backfill)+cmd_3079(UI-pipeline_config同期バグ)の成果がcontext/dm-signal-core.md・dm-signal-ops.mdに未反映(28日前更新)。/clear後の将軍が最新状態で起動できるよう還流する | dm-signal | 05-28 | context/dm-signal-ops.md §37に本 |
| cmd_3082 | cmd_3077でFE文言変更のみなのにCDPチェック(cdp_measure.sh→powershell.exe)が必須実行され、WSL2ハング→GATE 30分停止→殿手動kill 2回発生。run_cdp_production_check()にCDP_SKIP環境変数チェックを追加し、CDPチェック不要時にスキップ可能にする | infra | 05-28 | run_cdp_production_checkにCDP_S |
| cmd_3083 | 殿裁定「三層自動貫通」(2026-05-27)。現状lib/lord_conversation.sh L230でconcepts='[]'固定挿入しており、殿の発言が記憶DBに入っても概念紐付け(event_concepts)されない。memory_db_import.pyのconcepts_for_text(L357)と同等のロジックをappend_memory_db_entry内に追加し、リアルタイムで概念紐付けINSERTする | infra | 05-28 | live lord_conversation DB追記でセマ |
| cmd_3084 | CLAUDE.md/instructions内のorigin説明文に[[リンク]][[発端]][[原因]][[結果]]がそのまま記載されており、memory_db_import.pyのOBSIDIAN_LINK_REが実データと区別できずevent_linksに149件のノイズを生成している(全2,310件中6.5%)。テンプレート/説明文の[[...]]をバッククォート囲みに変更し、regexにマッチしないようにする | infra | 05-28 | CLAUDE.md/instructionsのorigin説 |
| cmd_3086 | cmd_publish.shのStep 2(pending昇格)→Step 3(cmd_delegate.sh委任)の間にauto-commitが走りq11のgrep根拠が陳腐化する構造的穴を修正する。cmd_3081で起票時に確認したq11根拠が配備時には崩壊していた事故の再発防止 | infra | 05-28 | cmd_publish.shの委任直前にq11 grep根拠 |
| cmd_3088 | semantic_stress_testが蓄積したNO_MATCH候補40件のうち構造的NO_MATCH(コマンド系5件+短文3件)を除外し、残り32件からaliases拡充可能な概念を抽出してsemantic-map.mdに追加する。NO_MATCH率60%を40%以下に改善する | infra | 05-28 | NO_MATCH29件分類(構造的15件+aliases拡充 |
| cmd_3089 | gate_context_freshness.shがlast_updatedコメントからの経過日数だけで鮮度を判定しており、ソースPJに変更がなくても時間経過でALERTが出る偽陽性バグを修正する。将軍×軍師3往復で収束した設計(ソースPJ commit比較+auto-commitフィルタ+ファイル名PJマッピング+ベースライン自動更新)を実装する | infra | 05-29 | context鮮度判定を日数ベースからソースrepo com |
| cmd_3090 | DM-Signalリポジトリにlast_updated(2026-04-30)以降60件の新commitがあり、context/dm-signal系5ファイルが追随していない。git log --oneline --since=2026-04-30の差分を確認し、contextの索引層を最新化してlast_updatedを更新する | dm-signal | 05-29 | DM-Signal 2026-04-30以降の43commi |
| cmd_3091 | deploy_task.shのメインフロー完走率が0.5%(208回中1回のみdeployment complete到達)。set -euo pipefail(L18)が7300行スクリプト全体に適用され、中間コマンドの非0 returnで早期exit、EXIT trapフォールバック。品質監視機能群(ntfy、deployed_at、preflight_gate、draft_review、post_deploy_verify)が99.5%到達不能。家老発見+軍師独立検証済み | infra | 05-29 | deploy_task.shのbinary_checks件数 |
| cmd_3092 | startup gateのgate_skill_script_refs.shが検出した5件のSKILL.md-script乖離を解消する。dream, idle-persist, karo-direct, recon-dual, shogun-teireの各SKILL.mdが参照scriptの変更に追随していない(3セッション連続startup BLOCK) | infra | 05-29 | 5件のSKILL.mdを参照script最新仕様に追随させ、 |
| cmd_3093 | gate_lesson_health.shのuseful_rate=25.7%がALERT(3セッション連続startup BLOCK)。低useful教訓を特定しwhen/how品質向上または淘汰でuseful_rateを改善する。軍師分析(gunshi_idle_useful_rate_alert_nazenaze_20260519.md等)を参照し根因に基づく改善を行う | infra | 05-29 | 低useful教訓TOP10をlesson_impact.t |
| cmd_3094 | 軍師計測(blt_20260529_124846)でcmd_complete_gate.sh(fresh)=220秒が全スクリプト最大ボトルネックと判明。毎cmd完了時に3分40秒消費。殿指示「スクリプト速度ボトルネック洗脳監査」への対応 | infra | 05-29 | cmd_complete_gate.shのGATE CLEA |
| cmd_3095 | context_freshness ALERT残存(saxo-trade-engine.md ソースPJ commit未反映 + 記憶DB定義ファイル last_updated未記載)を解消し、進化検知のmemory-db-queries.mdをCLAUDE.md知識マップに接続する | infra | 05-29 | context_freshness ALERTを解消し、Sa |
| cmd_3096 | 軍師計測(blt_20260529_124540)でgate_gunshi_report_precheck.sh=76.6秒が速度TOP2。毎レビュー時に76秒消費(1日10レビュー=12.7分/日損失)。22項目直列+WSL2 I/O律速が根因 | infra | 05-29 | gate_gunshi_report_precheck.sh |
| cmd_3097 | 軍師計測でgate_gunshi_startup.sh=23.4秒が速度TOP3。軍師起動時に23秒消費。gate_sync 3068件走査+統計集計が根因 | infra | 05-29 | gate_gunshi_startup.sh fresh実行 |
| cmd_9997 | cmd_save.sh速度計測のための新規PASSシナリオ。全必須フィールドを充足しPASSを取る | — | 05-29 | — |
| cmd_3099 | 軍師報告(blt_20260529_190957)で修行分27件中26件がCoDD台帳(codd_refactor_registry.md)未記載(96.3%漏れ)と判明。根因仮説: 修行cmdはcmd_complete_gateの自動台帳記載が発火しないフローで処理されている。一括台帳記載+自動記載フロー修正の2層対処 | infra | 05-29 | AC1: 修行分27件中26件(FAIL除く)の速度改善結果 |
| cmd_3100 | gate_skill_script_refs.shが18 WARN(12ファイル)を検出。参照scriptが更新されたがSKILL.md内容が未同期。3セッション連続startup BLOCKの解消 | infra | 05-29 | gate_skill_script_refs.shの参照sc |
| cmd_3103 | テスト2008件/12分超でpre-push hook BLOCK=日常回帰テスト不能。重複テスト名4件+1テストファイル2件+consolidated3.7%。テスト品質の自動管理基盤を構築し肥大化を構造的に防止 | infra | 05-29 | gate_test_health.sh新規作成(AC1: テ |
| cmd_3104 | 1031リンクが44ファイルに集中。context/skills/docsからのリンクがほぼゼロ。リンク密度を計測し、context更新時の因果リンク付与をgate WARNで強制し、backlinks=0ファイルを修行対象に自動組込み | infra | 05-29 | backlink密度計測スクリプト、context更新時の因 |
| cmd_3106 | cmd_3103で検出された統合候補52ファイル(テスト数5件以下)を統合し、テストファイル数を削減。test_cmd_save系3ファイルはcmd_3105で速度改善中のため除外し競合回避 | infra | 05-29 | watcher/起動系の小テスト2ファイルをtest_inf |
| cmd_3105 | cmd_3103で判明したSLOW 3件(test_cmd_save 88s+test_cmd_save_block_aggregation 51s+test_cmd_save_command_steps_vs_ac 44s=合計183秒)を最適化。テスト速度改善→全量計測も高速化する複利効果 | infra | 05-29 | test_cmd_save_command_steps_vs |
| cmd_3107 | 3セッション連続startup BLOCK 2件解消: scripts/未コミット変更3件のcommit + SKILL.md script参照4件の追随更新 | infra | 05-29 | 対象4件のSKILL.mdを現行script実装へ追随更新し |

## 2026-06

| cmd | title | project | date | key_result |
|-----|-------|---------|------|------------|
| cmd_3110 | recalculate_fof.pyのs_data構築(L517-527)でholding_signal_rawとsignal_cacheがif/elif排他構造のため、preloadでDBの古いデータがholding_signal_rawに入ると、1段目FoF計算後にsignal_cacheに書き戻された新データを2段目以降のネストFoFが読めない。6月signal未生成42件(奥義-GS 18/旧忍法系16/秘奥義4/NFF3/Ward1)の根因 | dm-signal | 06-01 | recalculate_fof.pyのFoF s_data構 |
| cmd_3111 | portfolio_config_snapshotsテーブルは076マイグレーションで作成済みだが書込みロジックが未接続(0件)。PF設定のロールバック手段がない。recalculate Phase 0直前とPF保存時に自動スナップショットを取る | dm-signal | 06-01 | portfolio_config_snapshotsへのPF |
| cmd_3113 | memory_db_import.py L839-865のCJK LIKEフォールバックが長文クエリで部分文字列マッチしない。文字種境界分割でクエリを短いトークンに分解し、各トークンのAND LIKE検索に変更して長文でもヒットさせる。記憶DB検索品質向上 | infra | 06-02 | CJK長文検索を文字種境界トークンのAND LIKEへ変更し |
| cmd_3114 | 将軍がcmd_idなしのtype=cmd_newをinbox_writeで送信するとcmd_new_gateをバイパスし、品質gate/軍師レビュー/教訓サイクルを全スキップする穴がある。L0-L7の全レベルで封鎖する | infra | 06-02 | cmd_idなしshogun cmd_newをL4 BLOC |
| cmd_3116 | memory_db_live_insert.pyの全関数でconcepts='[]'ハードコード。学習ループ出力(報告/gate/教訓/workaround)8185件が概念空間に未接続。軽量キャッシュ辞書でlive_insert時に概念付与し横断検索可能にする | infra | 06-02 | memory_db_live_insertのlive挿入でs |
| cmd_3117 | live_insertの概念付与入力テキストがevent_type別に品質差大。report=フィールド名メタデータ(充填0.8%)、cmd_delegate=定型文(4.7%)。concept_textにcmd title/purposeを逆引き注入し意味密度を向上 | infra | 06-02 | memory_db_live_insertの概念抽出にcmd |
| cmd_3120 | 軍師startup gateのWARN表示→推薦行動が人間依存(L2)。idle活動率5.4%(37件中2件)。WARN検出→対応するidle自走ステップを自動実行指示をpromptに注入し、WARNを見て判断する工程を排除(L4化) | infra | 06-02 | 軍師startup gateのWARN/ALERTをidle |
| cmd_3118 | 記憶DB 67456件中31617件(46.9%)が概念空。cmd_3116/3117は新規INSERT改善だが歴史データは空のまま。memory_db_import.pyのconcepts_for_text()で既存データを一括backfill | infra | 06-02 | events.concepts空履歴31636件をbackf |
| cmd_3119 | deploy_task.shの教訓注入はindex.mdのrelated_lessons(10概念28リンク)の静的マッチのみ使用。記憶DBのevent_concepts(71概念83494行)が教訓注入に還流しない。概念経由で関連教訓を動的発見し注入候補を拡張 | infra | 06-02 | deploy_task.shのrelated_lessons |
| cmd_3121 | 教訓注入59件中42件がNOT_USEFUL(偽陽性71.2%)。impl=100%偽陽性(7/7)。キーワードスコアリングが広すぎて無関係教訓が注入される。task_type別MIN_KEYWORD_SCORE引き上げで注入精度向上 | infra | 06-02 | impl task_typeのMIN_KEYWORD_SCO |
| cmd_3124 | useful率全期間28.8%(WARN)と直近窓58.6%(OK)の乖離。startup gateが全期間値でWARN判定→過去蓄積で改善が遅い。gate_lesson_health.shと同じ直近窓に統一 | infra | 06-02 | startup gateの教訓useful率判定をgate_ |
| cmd_3127 | infra教訓585/685件(85%)がorigin([[リンク]])なし。教訓が孤立し因果をたどれない。lesson_write.shにorigin必須化gateを追加し新規登録時の因果接続を強制 | infra | 06-02 | lesson_write.shにorigin必須gateを追 |
| cmd_3128 | event_concepts(概念タグ)は70.3%改善したがevent_links(因果リンク)は1.2%(813/67875件)。memory_db_live_insert.pyにorigin/[[リンク]]自動抽出→event_links自動INSERTを追加 | infra | 06-02 | memory_db_live_insert.pyのappen |
| cmd_3125 | hook_automation_framework(14389件)が突出し概念付与が偏集中。広すぎるaliasesが原因で横断検索にノイズ。aliasesを精査し概念分散を改善 | infra | 06-02 | hook_automation_frameworkの広すぎる |
| cmd_3129 | idle-persist/karo-direct/recon-dual の3 SKILL.mdが参照先script(inbox_write.sh, deploy_task.sh)より古い。scriptの変更内容をSKILL.mdに反映し、gate_skill_script_refs.sh WARNを解消する | infra | 06-02 | idle-persist/karo-direct/recon |
| cmd_3132 | 将軍がshogun_to_karo.yamlにcmd起票時、q5記入済みだがq5_verified_source未記入というパターンをcmd_save.sh到達前に検知する。pre-write-edit-combined.shにquality_gateフィールド対チェックを追加し、片方だけ記入のパターンマッチ漏れを構造的に防止する | infra | 06-02 | pre-write/edit hookでquality_ga |
| cmd_3135 | cmd_3132でL4(pre-edit WARN)を実装したが、L6(学習速度最大化)が未接続。cmd_save.shのSession Stateにq5/q5_verified_source対フィールドの片方欠落パターンを累計追跡し、再発時に検出ロジックを自動表示する | infra | 06-02 | cmd_save.shのSession Stateにq5/q |
| cmd_3136 | 教訓有効率34.6%(startup WARN)の根因。L4555の_universal_without_target_files_is_relevant()がtarget_files存在時に_target_files_matchを迂回してTrue返却→無関係教訓が全cmdに注入される。NOT_USEFUL 95件中の大部分がこの経路。1行修正で教訓注入精度を大幅改善 | infra | 06-02 | _universal_without_target_file |
| cmd_3140 | ninja_monitor.sh L338のauto_commit_before_clear()がgit addで全未commit変更を拾い、忍者Aの成果物を忍者Bのauto-commitが包含する。本セッション4件発生。task YAML target_pathでscopeフィルタを追加し、triggering ninja以外のファイルを除外する | infra | 06-03 | ninja_monitor auto-commitをtask |
| cmd_3141 | CI RED fixでcmd=7スクリプト対象だがreport files_modified=テスト2本のみという乖離が未検証で通過した。precheckにshogun_to_karo command欄のファイルパス抽出→files_modified突合→乖離WARN追加。L3(gate)の穴 | infra | 06-03 | cmd_complete_gate.shにcommand欄フ |
| cmd_3143 | gate_shogun_startup.sh L783のtarget_re=r'自動化ターゲット\s*[:：]\s*(.+)'がMarkdown太字(**自動化ターゲット**:)にマッチせず、将軍が自動化ターゲットを記入してもWARN判定される。3セッション連続WARNの真因。regexにMarkdown装飾を許容させ、テストでMarkdown太字パターンの通過を検証する | infra | 06-03 | gate_shogun_startup.shのQ6自動化ター |
| cmd_3144 | gate_skill_script_refs.shが検出した9件(7スキル)のSKILL.mdがscriptより古い。忍者がSKILL.mdを参照して作業する際に古い手順を使うリスク。LS042教訓: 3セッション放置は洗脳#5(先送り)の証拠 | infra | 06-03 | 9件(9スキル)のSKILL.mdをscript参照調査し、 |
| cmd_3146 | 軍師分析(docs/research/gunshi_idle_lesson_injection_crossproject_20260603.md): DM-Signal教訓(L633/L630/L598/L255/L147)がinfra/trainingタスクにクロスプロジェクト注入され100%NOT_USEFUL。教訓品質は正常、スコープ不一致が根因。deploy_task.shにproject一致フィルタを追加し、タスクのproject属性と教訓のproject属性が一致する場合のみ注入する | infra | 06-03 | deploy_task.shの教訓注入にproject一致フ |
| cmd_3148 | cmd_3147で実装したtarget_path基準の読み/書き区別がcmd_3145で再発FP。根因: command欄がテスト名を省略形で参照(semantic_index_update→test_semantic_index_update.bats)しbasename完全一致では照合不能。部分一致(substring/contains)をfiles_modified照合に追加する | infra | 06-03 | cmd_complete_gateのcommand/file |
| cmd_3149 | ローカルWSL2でBatsテスト全量が遅い根因=run_save(cmd_save.shフル実行)を毎テスト呼ぶファイル群(warn_logging/prev_cmd_lesson_warn/env_change/command_steps_vs_ac)。run_saveを関数単位テスト(source+対象関数呼出し)に変更し、テスト品質を維持しつつ実行時間を大幅削減する | infra | 06-03 | cmd_save系Bats 4ファイルのrun_saveフル |
| cmd_3150 | 三層記憶設計書§14-6。semantic_search.shの検索語・ヒット件数・ヒット0件フラグ・実行時刻をSQLiteに記録する専用スクリプトsearch_log_write.shを新規作成し、semantic_search.shから呼出す。保守クエリ(NO_MATCH傾向分析/検索頻度/未到達概念)と殿の使用パターン分析の前提データを蓄積する | infra | 06-03 | search_log_write.shを新規追加し、sema |
| cmd_3151 | 三層記憶設計書§14-8+家老F4。現在のaliasesは平坦リストで関係種別(同義/上位/混同注意)を区別できない。cmd_3125事故(alias広すぎ14389件)の構造的再発防止。index.mdの概念定義にrelation_type属性を導入し、semantic_index_update.shおよびsemantic_search.shのparserが無害に読めるようにする(構造変更のみ、検索展開制御は後続cmd) | infra | 06-03 | related_conceptsにrelation_type |
| cmd_3152 | cmd_3151でrelation_type属性が導入された。次のステップとして、relation_type=混同注意の概念をrelated_concepts自動双方向化および検索展開から除外し、誤結合を構造的に防止する。cmd_3125事故(alias広すぎ)の再発防止の完成 | infra | 06-03 | relation_type=混同注意のrelated_con |
| cmd_3153 | 三層記憶設計書§14-2。現在のeventsテーブル(14列70K行)には記憶の状態を表す列がなく、全イベントが同じ重みで扱われる。state列(raw/verified/stale_candidate/expired/hypothesis/refuted/canonical/historical/archived)を追加し、memory_db_import.pyのINSERT時にデフォルト値rawを設定する。記憶運用装置への最小変更 | infra | 06-03 | eventsテーブルにstate列(DEFAULT 'raw |
| cmd_3156 | 三層記憶設計書§14-4。原文と加工物がsummary/detail列に混在。分離設計の前に書込み元/読取り元/データパターンを調査する | infra | 06-03 | 記憶DB events.summary/detail の書込 |
| cmd_3158 | lesson_write.sh L1000/L1004でsemantic_index_update.sh(10秒)+semantic_map_generate.sh(3.3秒)が同期実行されており、教訓N件登録でN*13.3秒ブロック。cmd_3154で5分超遅延(家老infra_signal)。L1000/L1004を&でバックグラウンド化する(cmd_complete_gate.sh L6190と同パターン) | infra | 06-03 | lesson_write.shのsemantic_index |
| cmd_3157 | command欄の自然言語テキストからファイル参照を過剰抽出し、偵察cmdや自然言語記述のcmdでcommand_files_modified_mismatch BLOCKが誤発火する問題を修正する。cmd_3153+cmd_3156で2連続BLOCK(家老修正でCLEAR)。軍師LG014提案 | infra | 06-03 | — |
| cmd_3159 | 三層記憶設計書§14-4。eventsテーブルのsummary/detail列は検索用投影の混在列(68.3%がderived/metadata, cmd_3156偵察)。新規イベントにraw_content列を追加し、書込みスクリプト(memory_db_live_insert.py)のappend_eventで原文を保存する。既存70,810行は変更しない(新規のみ分離) | infra | 06-03 | events.raw_content列を追加し、memory |
| cmd_3160 | 三層記憶設計書§11。記憶DBに矛盾・重複候補を記録する仕組みがない。eventsテーブルのstate列(cmd_3153で追加済み)にcontradiction_candidate/duplicate_candidateを追加し、候補イベントを記録するスクリプトを作成する。矛盾は分類(§11の10種)付きで記録する | infra | 06-03 | 記憶DB live insertにcontradiction |
| cmd_3161 | 三層記憶設計書§8/§7。記憶DBに蓄積されたイベントのうち高頻度参照・高importance・複数リンクを持つものをObsidian昇格候補として抽出するスクリプトを新規作成する。候補はstate列をobsidian_candidateに更新し、人間確認待ちキューに入れる | infra | 06-03 | Obsidian昇格候補抽出スクリプトを追加し、本番DBで1 |
| cmd_3162 | dashboard_update.sh L411/L510のopen(path,'w')が即時truncateし、crash/timeout時にdashboard.mdが0バイトになる(2日連続WA)。tmp+os.replaceのatomic writeパターンに変更する。dashboard_auto_section.shは既にatomic write実装済みで0件WA | infra | 06-03 | dashboard_update.sh の2箇所の dash |
| cmd_3163 | 三層記憶設計書§9。古い記憶を削除せず想起制御する仕組みがない。state列にarchived/stale値を追加し、state遷移スクリプトを実装する。同時にVALID_EVENT_STATESにobsidian_candidate/verifiedが不在の不整合(軍師blt_20260603_221154)も修正しSSOT化する | infra | 06-03 | — |
| cmd_3164 | memory_db_live_insert.py VALID_EVENT_STATESに{raw,contradiction_candidate,duplicate_candidate}しかなく、cmd_3161で追加したobsidian_candidateとcmd_3153のverified、設計書§9のarchivedが不在(軍師blt_20260603_221154)。全state値を統一定義する | infra | 06-03 | VALID_EVENT_STATESは現行HEADで7種全て |
| cmd_3165 | 三層記憶設計書§9。古い記憶を削除せず想起制御する仕組みがない。state遷移関数update_event_stateとrecall_controlスクリプトを実装し、条件に基づくverified→archived遷移を可能にする。cmd_3164(SSOT化)完了後に着手 | infra | 06-03 | — |
| cmd_3166 | 三層記憶設計書§9。古い記憶を削除せず想起制御する仕組みがない。state遷移関数update_event_stateとrecall_controlスクリプトを実装し、条件に基づくverified→archived遷移を可能にする。cmd_3164(SSOT化)完了済み | infra | 06-04 | 想起制御用のmemory_recall_control.sh |
| cmd_3167 | 3セッション連続startup BLOCK解消。テスト選択スクリプトの3commit分(docs/rule mapping+軍師instruction tests+速度改善)がスキル定義に未反映 | infra | 06-04 | skills/codd-fix/SKILL.mdの手順6へd |
| cmd_3168 | L0-L7貫通設計書v6 cmd#-1。既存ext4キャッシュ(0.086秒/クエリ)をgate/prompt/healthの正本read pathへ昇格し、182GB tmp残骸をcleanup。全後続cmdの速度前提 | infra | 06-04 | memory_db_query.shをext4 cache優 |
| cmd_3169 | L0-L7貫通設計書v6 cmd#0。設計書2本をgit commit+event_state_transitionsテーブル存在確認+VALID_EVENT_STATESにobsidian_promotedを追加し8値化 | infra | 06-04 | 設計書2本をcommitし、実DBにevent_state_ |
| cmd_3171 | L0-L7貫通設計書v6 cmd#3。local_memory_db概念にstate管理スクリプト(recall_control/update_event_state/obsidian_promote)のresource行を追加。忍者タスク注入(L4)で三層記憶関連cmdに自動注入される | infra | 06-04 | docs/semantic-index/index.mdのl |
| cmd_3172 | L0-L7貫通設計書v6 cmd#2。gate_three_layer_health.sh共通関数を作成し、全roleのstartup gateから呼出し。events.state分布/raw_content充填率/矛盾候補件数/昇格候補件数の4指標を起動時表示 | infra | 06-04 | gate_three_layer_health.shに三層記 |
| cmd_3173 | L0-L7貫通設計書v6 cmd#4。将軍プロンプトにcontradiction_candidate、duplicate_candidate、obsidian_candidateの未処理件数を1行表示。候補が放置される構造を防止 | infra | 06-04 | prompt_state_inject.shに三層記憶候補の |
| cmd_3174 | L0-L7貫通設計書v6 cmd#7。gate_three_layer_health.shに三層記憶各機能の使用回数(検索、state遷移、原文保存、候補生成)を表示。使用0件の機能をWARN。接続した=使われたではない問題を検出 | infra | 06-04 | gate_three_layer_health.shに三層記 |
| cmd_3175 | L0-L7貫通設計書v6 cmd#5。ninja_monitorのidle自動トリガーにtmp cleanup(TTL24h)とrecall_control(dry-run)+obsidian_promote(dry-run)の定期実行を追加。掃除の自動化で18GB残存tmp蓄積を防止 | infra | 06-04 | ninja_monitorに三層記憶の日次メンテナンストリガ |
| cmd_3176 | L0-L7貫通設計書v6 cmd#8。cmd_save.shに記憶DB関連cmdのL0-L7 coverage map要求チェックを追加。部品だけ作られて導線なしで放置される免疫系 | infra | 06-04 | cmd_save.shに三層記憶L0-L7 coverage |
| cmd_3177 | L0-L7貫通設計書v6 cmd#6。obsidian_candidate→Obsidianノート雛形生成→state=obsidian_promoted更新→対応関係記録の一連フロー | infra | 06-04 | obsidian_candidateをObsidianノート |
| cmd_3178 | L0-L7貫通設計書v6 cmd#9。4種候補(矛盾、重複、昇格、アーカイブ)に対する統一確定スクリプト。approve、reject、deferの3アクション+検証+ntfy通知 | infra | 06-04 | memory_candidate_resolve.shを新規 |
| cmd_3181 | 三層記憶が全員に使われていない根因の1つは候補蓄積の放置。deploy_task.sh配備時にcandidate件数(obsidian_candidate/contradiction_candidate/duplicate_candidate)を確認し、閾値超でWARN表示。放置防止の構造的仕組み(殿指示: 三層記憶を全員が使う状態を作る) | infra | 06-04 | deploy_task.sh配備時に三層記憶candidat |
| cmd_3182 | recall_control/obsidian_promoteが本番DB(data/multi_agent_shogun_memory.db)にeventsテーブル不在で機能停止中(require_columns L97-103でexit)。三層記憶11cmd全GATE CLEARだが自動state遷移ゼロの直接原因。memory_db_import.pyの本番DB実行でeventsテーブルを作成し、ninja_monitorのdry-run→apply切替で三層記憶を実稼働させる | infra | 06-05 | 本番記憶DBにevents関連表とevent_state_t |
| cmd_3186 | causal_verification WARNが7回累計昇格→BLOCKの繰り返し。根因=gate/infra対象cmdのq5にgit log/因果キーワードを毎回手動追記する必要がある意志依存構造。cmd_save.shのcausal_verification scope判定時にq5にプレースホルダ(git log確認:)を自動表示し、記入漏れを防止する | infra | 06-05 | cmd_save.sh causal_verificatio |
| cmd_3184 | context_freshness gateがdm-signal-research.mdのbacklink追記(context自身のcommit)をsource更新として検出→偽陽性ALERT。根因=projects/dm-signal.yaml不在時にroot repoフォールバックし、context自身のcommitがsource commitsに数えられる。偵察(cmd_karo_recon_context_freshness)で特定した候補Bを実装: rootフォールバック時のcontext自身commitをsource更新から除外 | infra | 06-05 | context_freshness root fallbac |
| cmd_3187 | cancelled — WARN累計蓄積によりcmd_3188に再起票 | infra | 06-05 | — |
| cmd_3188 | cancelled — FP WARN累計蓄積によりcmd_3189に再起票 | infra | 06-05 | — |
| cmd_3190 | 偵察cmd_3189計測: Pre 90.8ms(2 fork)+Post 76.8ms(3 fork)=167.6ms/Bash呼出し。fork 1回=10ms。5→2 forkで30ms削減。100回/セッション×30ms=3秒/セッション。品質不変(チェック項目削除なし、設定層fork統合のみ) | infra | 06-05 | Claude Code settingsのPre/Post |
| cmd_3191 | cmd_3183(FAIL: 8.5→4.5s)の後続。残存python3呼び出し(L538/582/628/688/775/815)をbatch化し4s安定を達成する | infra | 06-05 | gate_shogun_startup.shのGate4 Y |
| cmd_3194 | 3セッション連続startup BLOCK解消。37957イベント蓄積だがcandidate=0/state遷移=0。obsidian_promote+insight_resolveパイプラインが動作していない根因を特定し修正する | infra | 06-05 | obsidian_promote+insight_resol |
| cmd_3195 | 殿指示: gate品質によるBlock/WARNはバグ。今セッションcmd_3191-3194起票で発見した3件を全て修正する | infra | 06-05 | cmd_save.sh gate品質バグ3件(q5抽出deb |
| cmd_3196 | cmd_3194でcandidate生成(0→14)成功だがfinalize未実行。洗脳#8(完了急ぎ)検出。パイプライン最後まで回す | infra | 06-05 | obsidian_promote_finalize.sh - |
| cmd_3197 | 軍師分析: 教訓注入useful率27.4%。根因=deprecated教訓が修行タスクYAML再利用で残存。inject_direct_training_templateでdeprecated教訓を除外しuseful率向上 | infra | 06-05 | deploy_task.shの教訓注入フィルタにsupers |
| cmd_3198 | 覚醒監査で検出した2件の改良を環境に埋め込む。(1)GP-262: 定型cmdでも洗脳#1(早期終了)で1観測止まり防止 (2)殿の質問時にsemantic_knowledge結果を引用強制し概念混同を防止 | infra | 06-05 | GP-262の最低2観測明示と、殿の質問時のsemantic |
| cmd_3199 | 将軍が三層記憶(記憶DB+Obsidian+セマンティック)を使わずMEMORY.mdで回答する根因を解消。L0-L7に三層記憶第一優先を貫通させる。軍師覚醒レビュー3往復完了の設計書v3に基づく | infra | 06-06 | 三層記憶第一優先化L0-L7貫通: instructions |
| cmd_3200 | 三層記憶検索到達保証+自動成長ループの穴を塞ぐ。軍師3往復+家老3往復レビュー合意 | infra | 06-06 | three_layer_memory_system概念をse |
| cmd_3206 | 速度修行でscript群が更新されたがSKILL.md内容が未追随。忍者が古い手順で作業するリスク解消。3セッション連続startup BLOCK | infra | 06-07 | 14件のSKILL.mdを参照scriptの現行動作へ追従し |
| cmd_3211 | 速度修行ledger auto-deployがCTX%を確認せず連続配備→コンパクション頻発→速度低下。_handle_speed_training_auto_deployにCTX閾値チェックを追加し、CTX高忍者への配備をauto-clear完了まで保留する | infra | 06-07 | ninja_monitor.sh _handle_speed |
| cmd_3210 | report_received hookがテンプレート段階(bc空)で偽発火→FAIL記録し、dashboard-updateのFAIL率が実態と乖離している。bc空FAILを偽FAIL分類して計測精度を回復する | infra | 06-07 | gate_karo_startup.shのskill_exe |
| cmd_3213 | cmd_3211で追加したCTX50%閾値チェック(L2095-2104)を削除。殿指摘(2026-06-07 21:13): idleなら何%でも/clearする既存仕組みで十分。閾値は不要な複雑性であり洗脳#4(緩い設計)+#6(出力=仕事)の産物 | infra | 06-07 | ninja_monitor.sh _handle_speed |
| cmd_3214 | gate_skill_script_refs.shが検出した9件のSKILL.mdが参照先scriptより古い。scriptの変更内容をSKILL.mdに反映し、startup BLOCKを解消する | infra | 06-07 | gate_skill_script_refs.sh検出の9件 |
| cmd_3212 | ledger pending39件中34件がcommit済みだがrecord-after未実行で偽pending。一括修復+karo_directフローにrecord-after呼出しを統合し再発防止 | infra | 06-07 | reconcile追加+update_entry_field |
| cmd_9998 | cmd_save.sh速度計測のための新規PASSシナリオ。cmd_9999に蓄積したWARN履歴の影響を排除する | — | 06-07 | — |
| cmd_9999 | 速度計測テスト用のダミーcmd | — | 06-07 | — |
| cmd_3215 | 3xレバレッジETF保有中の大幅損失月を全期間で特定し、その前月のシグナル・価格・ボラティリティに共通パターンがないか調査する。殿指示(2026-06-07): 先週木金の急落のような事態を事前に予測できるサインを探す | dm-signal | 06-07 | 3xレバレッジETF保有中の月次リターン-10%以下を全期間 |
| cmd_3216 | cmd_3215は3xレバレッジETF保有月のみに限定していた。殿指示(2026-06-07 22:55): 全デュアルモメンタム全PFを同時に分析に加えないと意味がない。四神12体+忍法20体+奥義21体の全53PFで損失月(-10%以下)を全期間特定し、前月パターンを分析する | dm-signal | 06-07 | 全54PF(L0四神12+L1忍法21+L2奥義21)の全期 |
| cmd_3217 | cmd_3216の損失パターン(負け条件)に加え、全PFの好調月(勝ち条件)も同手法で分析。全利用可能データ(monthly_returns/holding_signal/signal_change_log/deterioration_snapshots/prices/VIX/DTB3)を投入し、勝ち条件vs負け条件を対比。殿指示: サイズ調整のための危険度判定材料を全データで構築 | dm-signal | 06-08 | 全54体(L0四神12+L1忍法21+L2奥義21)の月次リ |
| cmd_3219 | safe_send_clear後にL891で@context_pctを0%リセットするが、CLIステータスラインに前回のCTX表示が残留し、次のget_context_pctサイクルでcapture-paneから旧値が検出→@context_pctに書き戻される。殿指摘(2026-06-08 01:45): /clear後にCTXが0%にならないのはおかしい | infra | 06-08 | safe_send_clear内の/clear後にtmux |
| cmd_3220 | 殿指示: サイズ調整のみ、100% or 80%の二択。7戦略(VIX連動/実現ボラ/ATR/分類器/レジーム検出/カレンダー効果/連続上昇カウンター)を全78PF×全期間でバックテストし横並び比較。cmd_3218の教訓(HIGH月+3.3%で機会損失)を踏まえ控えめな20%縮小で検証 | dm-signal | 06-08 | 7戦略サイズ調整(100%/80%)バックテスト完了。全78 |
| cmd_3221 | Gate 20がcmd_training_speed_*(修行cmd)を運用cmdと同列にFAIL判定しreport-write FAIL率12%(6/50)で3セッション連続BLOCK。修行cmdの報告は運用cmdより簡易でフィールド欠落が起きやすいが修行の性質であり運用品質の問題ではない。GP-263(adversarial免除)と同構造 | infra | 06-08 | gate_shogun_startup.sh _exclud |
| cmd_3222 | 殿指摘: cmd_3220のVIX>25は調査が甘い。VIXだけでも時点・動的閾値・変化率・パーセンタイル・組合せがある。投資知識に基づくシグナル(SPY200日MA/実現ボラパーセンタイル/モメンタム急落)も加え、約20バリアントを全78PF×全期間でバックテストし横並び比較。cmd_3220のD10-VIX>25を超える戦略を探索 | dm-signal | 06-08 | VIX深掘り+投資知識シグナル13バリアント×78PF×全期 |
| cmd_3223 | cmd_3222でV8(VIX>25 AND VIX>VIX_MA20)が最優秀と判明したが全額キャッシュ方式で実装されていた。殿指示の100%/80%二択方式で再計算し、cmd_3220と直接比較可能にする。加えてV8ベースで閾値(VIX>20/25/30)×MA期間(10/20/30/50)の12バリアントを80%方式で網羅的にバックテストし最適パラメータを特定 | dm-signal | 06-08 | V8閾値チューニング完了。12バリアント(VIX閾値20/2 |
| cmd_3224 | cmd_3223でV8_T25_MA50が80%方式の最適パラメータと判明。本番採用前に過適合リスクを検証する。(1)OOS検証: 2010-2017訓練期/2018-2026テスト期で効果が持続するか (2)サブ期間分析: COVID(2020)/金利上昇(2022)/平常期での戦略効果を個別検証 (3)ローリング3年窓で年ごとの安定性を確認 | dm-signal | 06-08 | V8_T25_MA50過適合検証完了。OOS保持率Sorti |
| cmd_3225 | 殿指摘: 四神(L0)と忍法(L1)でパフォーマンスが全く違うのにcmd_3223/3224は全PF平均。レイヤー別のV8効果を確認する。加えて殿提案のマネージドボラティリティ(PFごとの実現ボラでサイズを動的調整)をBT。(1)V8_T25_MA50をL0四神/L1忍法/L2スタンダード/L3奥義で分けて分析 (2)マネージドボラ方式=各PFの実現ボラ20日をターゲットボラで割り、サイズを80-100%にクリップして適用 | dm-signal | 06-08 | V8_T25_MA50をL0四神/L1忍法/L2スタンダード |
| cmd_3226 | note.comエディタが2026-06時点で初回ロード時にスピナーで停止しProseMirror未描画。note_draft.shがno_prosemirrorで失敗する。リロード+待機ロジック追加とセレクタ更新で対応。加えてreference_cdp_note_com.mdに新エディタ構造を反映 | infra | 06-08 | note_draft.shにwait_for_prosemi |
| cmd_3227 | 殿指摘: 各論パッチではなく全スキル・今後作るスキルにも適用される自動成長の仕組みが必要。現状の穴: (1)実行結果記録が各スキル個別実装→未接続スキルは失敗が見えない (2)失敗→修行課題生成が手動 (3)修行完了→SKILL.md更新が手動。全ステップ(実行→検知→修行→再現性確認→スキル更新)を共通基盤で自動化する設計を作成 | infra | 06-08 | 全スキル自動成長ループ共通基盤の設計を作成。現状穴3件(実行 |
| cmd_3228 | cmd_3227設計に基づきPhase1を実装。PostToolUse hookでSkill tool実行後にskill_execution_log.shを自動呼出し、全スキルの実行結果(PASS/FAIL+失敗理由)を記録する。新スキル追加時の個別接続作業がゼロになる | infra | 06-08 | PostToolUse hookにSkill tool判定分 |
| cmd_3229 | cmd_3227設計§3穴2に基づきPhase2を実装。skill_auto_improve.shのescalation判定(unchanged_streak>=閾値)後に修行課題を自動生成し家老inboxに通知する。完全自動配備ではなく家老確認を挟む安全弁付き | infra | 06-08 | skill_auto_improve.shのescalati |
| cmd_3230 | cmd_3227設計§3穴3に基づきPhase3を実装。修行完了時(gate_fire_log解析でPASS判定)にskill_auto_improve.shを呼出しSKILL.mdの防止ステップを自動更新。修行の成果がスキル自体に自動還流する最終ピース | infra | 06-08 | Phase3実装完了: training_completio |
| cmd_3231 | 教訓健全度WARNが3セッション連続BLOCK。根因=研究cmdにtarget_pathなし→deploy_task.shのinject_related_lessonsがMIN_KEYWORD_SCORE閾値を下回り全量fallback注入→大半NOT_USEFUL(useful_rate=35%)。target_pathなし時のスコアリング精度を上げ、関連性の低い教訓の注入を抑止する | infra | 06-08 | deploy_task.sh inject_related_ |
| cmd_3234 | 起動チェックがbacklinks=0の5ファイルを検出。孤立ドキュメントは因果ネットワークから切断され知識として到達不能。context/skills/docsから因果リンクを接続し知識基盤の健全性を回復する | infra | 06-08 | backlinks=0の5ファイル(ashigaru-det |
| cmd_3240 | obsidian昇格率0.07%(32/47037)。candidate12件蓄積。昇格が将軍の/dream(手動)依存=意志依存=停止。ninja_monitorの定期サイクルでcandidate蓄積を検知し自動昇格するトリガーを追加する | infra | 06-08 | ninja_monitorにcheck_obsidian_c |
| cmd_3239 | raw_content充填率2.4%(1121/47037)。97.6%のイベントが原文未保存で要約のみ。三層記憶の全文記録原則(LS-A23)が機能していない。書込みスクリプト群(lord_conversation_write/bulletin_write/insight_write等)にraw_content保存を追加し充填率を向上させる | infra | 06-08 | lord_conversation.sh/memory_db |
| cmd_3242 | 忍者にはninja_weak_points/gate_fail_top3/gate_blocks(L6)が自動注入されるが、将軍のcmd起票には同等の仕組みがない。本セッション10回BLOCK+5回lesson_ack=同じパターン繰返し=L6不在の証拠。cmd_save.sh実行前のpreflight表示に将軍個人のBLOCK TOP3と過去の回避策を自動表示し、忍者と同等のL6を将軍に適用する | infra | 06-08 | — |
| cmd_3241 | 将軍の三層記憶引用率0%。殿応答時のみ[MEM:]引用で自発的引用なし。殿指摘(2026-06-05)「使わないから間違う」が改善されていない。cmd起票時のpreflight(pre-write-edit-combined.sh)に記憶DB検索結果を自動表示し、将軍が三層記憶を参照せざるを得ない環境を作る | infra | 06-08 | pre-write-edit-combined.shのcmd |
| cmd_3244 | startup gate「スキル推薦精度」が3セッション連続BLOCK。precision 0%(0/18)、偽陽性100%。軍師分析で根因3つ特定(設計書: docs/research/gunshi_idle_skill_precision_20260608.md)。根因1(推薦ログ停止)と根因3(役割フィルタ)は家老D0で対処。本cmdは根因2(推薦agent≠実行agent照合不一致)を修正する。推薦ログにninja_nameフィールドを追加し、precision計測の照合キーを推薦agent→割当ninjaに変更する | infra | 06-08 | deploy_task.shのinject_semantic |
| cmd_3245 | cmd_3244起票で7回BLOCK。覚醒なぜなぜ7回で根因特定: cmd_save.shがquality_gateのフィールド値はチェックするがフィールド名の正しさはチェックしない。将軍がq5_assumptionsと書いてもq5_verified_sourceと照合されず素通り→値チェックフェーズで初めてBLOCK→修正ループ。フィールド名バリデーション(テンプレートの必須名リストとの照合)を追加し、不正フィールド名を即BLOCKする | infra | 06-09 | cmd_save.sh Check3にquality_gat |
| cmd_3246 | cmd_3244起票で7回BLOCK→覚醒なぜなぜで根因言語化→しかし教訓記録+環境cmd起票は殿の介入で初めて実行(殿依存=洗脳#3)。根因: cmd_publish.sh PASS後にnazenaze_root_causeがあっても教訓記録+環境変更cmdの起票を強制するgateがない(半パイプライン)。加えて殿裁定(2026-06-08): 洗脳監査の正しいサイクル(行動→行動結果検証)は家老/軍師にも横展開が必須 | infra | 06-09 | cmd_publish.shにnazenaze_root_c |
| cmd_3247 | 覚醒洗脳監査→家老なぜなぜで根因特定: 軍師レビューWARN率35%(7/20)の全件がcommand_files_modified_mismatch由来。SG-PRE25がreadonly_ref未考慮のINFOを出す→軍師がLGTM→gateはreadonly_ref除外後にBLOCK→判定乖離。SG-PRE25にreadonly_ref除外ロジックを追加し、除外後の真のmismatchをWARNに昇格させることでgate判定と同期する | infra | 06-09 | SG-PRE25にcmd_complete_gate.shと |
| cmd_3249 | 軍師idle自走分析(GP-265)で検出: cmd_3231でblast_radius大(changed_lines>200)だがadversarial未適用。根因: SG-PRE15.5のadversarialリマインドがcmd種別(自動化系)のみで判定しchanged_linesを参照しない。changed_lines閾値(200行)超過時にadversarial必須を自動トリガーし、大規模変更の見落としを防止する | infra | 06-09 | — |
| cmd_3250 | 三層ループFAIL率30%超WARNINGが3セッション連続startup BLOCK。家老偵察(才蔵)で根因2件特定: (1)L457のautofix_count==0条件がAUTO-FIXED=7件蓄積で永続False→自己修正率判定を迂回→粗いFAIL率判定に到達 (2)L470のFAIL率がFAIL/PASS(33.3%)で計算されFAIL/TOTAL(25%)ではない。2件のバグを修正しFAIL率判定を正確化する | infra | 06-09 | gate_loop_health.shの2件バグ修正: (1 |
| cmd_3251 | 覚醒なぜなぜ7回で根因特定: 将軍の洗脳チェックがL2/L3のみでL4に穴。セッション中に洗脳5/8発現。リマインダー表示だけでは#1(早期終了=ツール失敗時の諦め)と#3(他者依存=殿への操作依頼)に効かない。3層で対策: (A)prompt_state_inject.shに8パターンリマインダー(#2/#7/#8対策) (B)stop hookにF009パターン検出(殿への操作依頼をBLOCK)(#3対策) (C)note_draft.sh失敗時にWebSocket回避策を自動フォールバック(#1対策) | infra | 06-09 | 洗脳チェック3層対策: (A)prompt_state_in |
| cmd_3252 | セッション中に洗脳5/8発現。#3はcmd_3251で環境強制済み。残り4パターン+F009偽陽性の5件を完結させる: (A)F009偽陽性=過去形引用除外 (B)#1早期終了=note_draft.sh WebSocketフォールバック (C)#2検証スキップ=sengoku-writerにls自動確認ステップ強制 (D)#7簡潔本能+#8完了急ぎ=clear_prep_check.shにセッション知見全件反映チェック追加 | infra | 06-09 | 洗脳4パターン+F009偽陽性の5件修正完了。AC1:F00 |
| cmd_3254 | startup BLOCK 3セッション連続。useful_rate=3.4%(2/58)。直近6cmdで58件教訓注入のうちuseful2件のみ。根因特定(注入ロジック/タグ精度/フィードバック記録)+低useful教訓のwhen/how改善で有効率を回復する | infra | 06-09 | useful_rate 3.4%の根因=memory_db |
| cmd_3255 | startup BLOCK 3セッション連続。cmd_3075(重複抑止)/3080(窓拡張)/3244(照合キー修正)で0%→7%に改善したが偽陽性93%(28/30)が残存。残存根因を特定し改善する | infra | 06-09 | skill_recommend.shにrole_marker |
| cmd_3259 | 覚醒洗脳監査6/8 YES。根因: GATE CLEARで鎖が切れ効果を再確認しない→洗脳#6(出力=仕事)が構造化。cmd_3254 GATE CLEARでuseful_rate+1%なのに完了と報告した。GATE CLEAR受信時にcmdのpurposeから数値改善キーワードを抽出し、効果再確認リマインダーを将軍に強制注入する | infra | 06-09 | post-shogun-inbox-check.shにGAT |
| cmd_3262 | note_draft.sh がChrome未起動時にPython exit 1でFAILカウントされる。Chrome接続確認をbash層で事前実行し、未起動時はSKIP(exit 0+理由表示)に変換してFAIL率を正常化する | infra | 06-10 | note_draft.shにbash層CDP事前チェック(S |
| cmd_3265 | gate_context_freshness.shがlast_updatedからの経過日数だけでALERT判定するため、ソースPJに変更がなくても日付変更でALERTが連発する(GA-031〜036の6件/日)。ソースに変更がない場合はALERTを抑止し、信号対雑音比を改善する | infra | 06-10 | gate_context_freshness.shの日数のみ |
| cmd_3264 | 忍者の本体変更がauto-commit(chore: auto-commit before /clear)に巻き込まれ、cmd固有commitにはテストのみ含まれる。SG-PRE3のcommit検証をすり抜ける。3件連続発生(cmd_3255/3261/3263)。忍者commit完了後のgit status確認を強制し、auto-commit先取りを検出する | infra | 06-10 | auto-commit巻込み防止: ninja_monito |
| cmd_3266 | 将軍のstartup gateにある先送り3セッション連続検出+自動エスカレーション(L1)が家老・軍師に未実装。洗脳#5(先送り)は全ロールに作用するため、gate_karo_startup.sh/gate_gunshi_startup.shに同等機能を横展開する | infra | 06-10 | gate_karo/gunshi_startup.shに先送 |
| cmd_3267 | gate_shogun_startup.shの殿生発言Q生成がtask-notificationをinboundとして取得し殿の発言でないテキストを追体験Qに含めている。フィルタ追加で追体験Qの精度を改善する | infra | 06-10 | gate_shogun_startup.shの2箇所のinb |
| cmd_3268 | docs/research/cmd_1991_codd_extract/modules/配下5ファイルがbacklinks=0で因果ネットワークから孤立。20セッション先送り。context/dm-signal-research.mdから因果リンクを接続し知識到達性を回復する | infra | 06-10 | cmd_1991 CoDD extract modules/ |
| cmd_3269 | deploy_task.sh inject_related_lessonsがassigned_to未設定時にninja_name=unknownで記録し、同一教訓が忍者名+unknownで二重登録される。172 NOT_USEFUL中81件がunknownで水増し。二重記録を防止しuseful_rate計測を正常化する | infra | 06-10 | deploy_task.sh inject_related_ |
| cmd_3270 | note-draft スキルの直近50件FAIL率が38%(3/8)で3セッション連続startup BLOCK。家老escalation(blt_20260610_115209)でCMD起票要請あり。skill_auto_improve_stateでcode_fix_requiredエスカレーション済み。根因を特定し修正する | infra | 06-10 | note-draft FAIL率38%の根本原因(CDPなし |
| cmd_3271 | 教訓健全度WARN(useful_rate=46.2%)が3セッション連続startup BLOCK。根因=target_path未設定cmdでMIN_KEYWORD_SCORE閾値を下回り全量fallback注入(cmd_3231分析済み)。絞り込み精度を改善しuseful_rateを向上させる | infra | 06-10 | inject_related_lessonsのtarget_ |
| cmd_3272 | 家老escalation(blt_20260610_172123): pre-commit yaml.dump BLOCKの根因修正。skills/shogun-claude-version-switch/scripts/claude_version_switch.sh L198がyaml.safe_dumpでsettings.yamlを丸ごと上書き→GP-136正当BLOCK。yaml_field_set.shで該当フィールドのみ更新に変更 | infra | 06-10 | set_launch_cmd()のL182-198 yaml |
| cmd_3274 | 殿指示(2026-06-10 21:04「遅すぎる。やり方が間違っている。Gmailは今後も増える。サンクコストに囚われず今やるべき」+21:18「速度を合格点にするのではなく、より早くを目的にして修行すべき」)。遅さの真因=1通ごとにgws CLI(Node.js)をcold startする直列ループ(実測145分/1,577通=5.5秒/通)。投入自体は21:06に完了済み(1,577件・将軍と家老が独立検証済み)のため、本cmdはデータ再投入ではなく取込エンジンの恒久部品化: プロセス起動O(1)化+増分同期+FTS5日本語トークナイザ欠陥修正 | clinic-expense-tracker | 06-10 | gws CLI cold start O(N)→O(1)化( |
| cmd_3275 | 殿裁定(2026-06-10 19:12「最大の痛みは現況がはっきりしないこと」+19:15「まずはリスト。次にリストを佐瀬メールなどで埋める。見える化で第三者にも頼める作業になる」+19:17「今後も使う仕組みだから古い時期から」)。docs/02 §WHATの21カテゴリ表を骨格に完全リストを生成する。佐瀬メール起点は抜け漏れ→手戻りのため骨格はマスタ表(殿裁定)。ソースで埋める作業はStep 2(後続cmd) | clinic-expense-tracker | 06-10 | expense_sources 21件+monthly_st |
| cmd_3276 | 殿裁定(2026-06-10 19:15「次にリストを佐瀬メールなどで埋める」)の手順(2)第1ソース。佐瀬会計メール=会計士が何を受け取り何が不足と言っているかの一次記録(ground truth)。gmail_receiptsのshortage_list 35通(検証済み)をパースし、cmd_3275で生成した294セル(全not_obtained)のうち会計士記録が裏付けるセルを更新する。1ソースずつ埋める(殿裁定: 全部一気にやらない) | clinic-expense-tracker | 06-10 | 佐瀬メールshortage_list 35通を全文取得しパー |

<!-- clinic-expense-tracker研究リンク(cmd_3278自動追記) -->
- → [[expense-receipt-audit]] 経費レシート監査詳細(cmd_3275/3276: 佐瀬会計メール+21カテゴリ表監査)
| cmd_3282 | 軍師実証(blt_20260611_014139): cmd_3278 hayate報告でfiles_modifiedに7ファイル分のリストが1つのpath文字列として押込まれた形式破損を、autofixが単一ファイル向けのstring→dict変換で機械変換しERROR化を回避→破損したまま下流(レビュー/gate)へ素通りした。LG038(silent SKIP=情報の墓場)のautofix版であり、『直せない破損』を『直したことにする』のは検査不能の隠蔽。変換可否を判別しERRORへ昇格させる | infra | 06-11 | FM_FORMAT_INVALID検出追加: files_m |
| cmd_3279 | 殿指示(2026-06-11 01:19)「続きはシンプルだ。renderにデプロイするウェブアプリ。画面はシンプルで、縦軸はカテゴリごとに項目一覧、横軸は年月」に基づき、monthly_status 294セルをブラウザで見えるマトリクス画面として実装する。Sheets併存。スタッフ(第三者)にも現況が見える作業化の土台 | clinic-expense-tracker | 06-11 | 【軍師RC対応済み】FastAPI+Jinja2でmonth |
| cmd_3283 | 殿指示(2026-06-11 01:19)「renderにデプロイするウェブアプリ」の最終工程。cmd_3279でアプリ実装+render.yaml整備+ローカル検証が完了したが、DBは機密経費データのためrepo同梱不可(.gitignore対象)でRender persistent diskへの搬送方式が未確定(render.yaml NOTE現物で確認)。搬送方式=Basic Auth付きDBアップロードエンドポイントとし、デプロイ→DB搬送→本番表示確認まで貫通させる | clinic-expense-tracker | 06-11 | Renderデプロイ+DB搬送+本番確認まで貫通完了。/up |
| cmd_3286 | 家老escalation(2026-06-11): レビュー品質WARN率が3セッション連続で30%超。根因調査の結果、review_quality_scale_summary()が同一cmd_idの全レビューイテレーション(RC→FAIL→LGTM等)を個別カウントしており、正常な反復レビューがWARN率を膨張させていた。実測: 直近20エントリでWARN率55%だが、cmd_id重複排除すると最終PASS率85%超。メトリクスをcmd_id単位の最終verdict集計に修正する | infra | 06-11 | review_quality_scale_summary() |
| cmd_3284 | 家老正直報告(blt_20260611_022919)+軍師第三者検証(blt_20260611_023032): 殿が裁可保留していた変更3群が、kotaroのcmd_3278完了時batch commit(6cfda60e1)に巻き込まれpush到達=裁可保留の機構的迂回。将軍がgit show --statでscripts/gates/3本の巻き込みとorigin/main到達を一次確認済み。防御2層のうち第1層=batch commitが安全機構変更(scripts/gates/+.claude/hooks/)を無差別に巻き込むスコープ無制限を塞ぐ | infra | 06-11 | ninja_monitor.shにfilter_exclud |
| cmd_3287 | 殿裁定(2026-06-11): 取得済み=該当証票PDFがDriveに保存されていること。未取得を自動取得可能/手動の2種に分ける。データ取得ルートも明確にする。現状: monthly_status.statusは3値(not_obtained/obtained/submitted)で未取得の自動/手動区別なし。expense_sources.collection_methodにgmail_api/cdp/manualが設定済みだがWebアプリ表示に反映されていない。修正: not_obtainedをcollection_method参照で自動/手動に色分け表示+取得ルート列追加 | clinic-expense-tracker | 06-11 | app.py fetch_matrix()にcollecti |
| cmd_3288 | 殿指示(2026-06-11): 設定画面を作って経費元を設定・変更・保存できる仕組み。人間の判断がファースト。カテゴリと項目を自由に設定可能。SSOT=Render上のアプリDB。現状: expense_sourcesテーブルは21行あるが編集はSQLite直操作のみ。Webから編集不可。ローカル→Renderのupload-dbはあるがRender→ローカルのdownload-dbがない。修正: (1)設定画面(/settings)でexpense_sourcesのCRUD (2)download-dbエンドポイント追加 (3)ローカルスクリプト実行前にdownload-dbで最新化するフローを確立 | clinic-expense-tracker | 06-11 | AC1-AC4全PASS: /settings CRUD画面 |
