# Infra教訓 詳細リスト
<!-- source: context/infrastructure.md §Infra教訓索引 -->
<!-- archived: 2026-03-23 by cmd_1282 -->

### L001-L050 テーブル索引（初期教訓）
| ID | 結論 | 区分 | 出典 |
|---|---|---|---|
| L001 | Write前Read必須 | CLI | cmd_125 |
| L002 | FG bashでnudge不可 | inbox | cmd_125 |
| L003 | MD更新=稼働中反映なし | CTX | cmd_125 |
| L004 | pane変数空≠未配備 | tmux | cmd_092 |
| L005 | ashigaru→roles/参照 | build | cmd_134 |
| L006 | lesson重複チェック欠如 | 教訓 | cmd_134 |
| L007 | whitelist gitignore注意 | git | cmd_140 |
| L008 | WSL2新sh→CRLF混入 | WSL2 | cmd_143 |
| L009 | commit前git status確認 | git | cmd_143 |
| L010 | status行^先頭マッチ | 報告 | cmd_145 |
| L011 | core.hooksPath確認 | git | cmd_147 |
| L012 | aliasでpipeブロック不可 | bash | cmd_147 |
| L013 | L005のkaro版 | build | cmd_150 |
| L014 | grep exclude WSL2不安定 | WSL2 | cmd_151 |
| L015 | CONFIG_DIR切替 | OAuth | saizo |
| L016 | OAuthトークン競合 | OAuth | tobisaru |
| L017 | 入口門番→再配備自己ブロック | 配備 | cmd_158 |
| L018 | Edit tool flock未対応 | inbox | cmd_189 |
| L019 | grep -c‖echo 0二重出力 | bash | cmd_192 |
| L020 | 設定パス環境変数共有 | script | cmd_208 |
| L021 | declare -A→-gA scope | bash | cmd_208 |
| L022 | flock内python retry誤発動 | script | cmd_220 |
| L023 | 自動化は報告スキーマ先行 | 教訓 | cmd_231 |
| L024 | 報告アーカイブ不在 | 報告 | cmd_231 |
| L025 | =L027 draft版 | 報告 | cmd_236 |
| L026 | 14%陳腐化→deprecation | 知識 | cmd_237 |
| L027 | 統合タスクでreport上書き | 報告 | cmd_236 |
| L028 | CI Run#とSHA整合確認 | CI | cmd_248 |
| L029 | nudge嵐=二重経路合流 | inbox | cmd_255 |
| L030 | current_project死コード | 知識 | cmd_258 |
| L031 | PJ固有=CLAUDE.mdの4% | 知識 | cmd_258 |
| L032 | PJセクション境界=## | 知識 | cmd_258 |
| L033 | confirmed時status欠落 | 教訓 | cmd_262 |
| L034 | YAMLインデント変動 | ゲート | cmd_279 |
| L035 | gate検証で副作用発火 | ゲート | cmd_279 |
| L036 | git checkout -- SSOTで未コミット教訓消失 | git | cmd_310 |
| L037 | WSL2 Write tool .sh→CRLF確定(L008拡張) | WSL2 | cmd_311 |
| L038 | gate実行で本番lessonsにdraft副作用(L035実害) | ゲート | cmd_311 |
| L039 | 教訓参照怠り(自動生成) | 教訓 | cmd_310 |
| L040 | WSL2 Usage API応答5秒超→timeout≥10秒 | WSL2 | cmd_314 |
| L041 | tmuxペインレベル環境変数なし→respawn-pane -e | tmux | cmd_314 |
| L042 | 統合タスクでreport上書き実害(L025+L027統合) | 報告 | cmd_310 |
| L043 | inbox_write.sh Python展開にインジェクション脆弱性 | inbox | cmd_317 |
| L044 | reports YAML扁平/ネスト2構造混在→パーサー両対応必須 | 報告 | cmd_317 |
| L045 | AC達成状況フィールド名3種混在(acceptance_criteria/ac_status/ac_checklist) | 報告 | cmd_317 |
| L046 | capture-paneバナー解析のfalse positive防止(モデル名+版数精密パターン) | tmux | cmd_320 |
| L047 | deploy_task.sh Python -cにシェル変数直接埋込→インジェクション危険 | セキュリティ | cmd_317 |
| L048 | ninja_monitor auto-done誤判定→parent_cmd+task_idチェック必須 | monitor | cmd_317v2 |
| L049/L050 | コードレビューで既存対策見落とし共通パターン→全行+コメント精読必須 | レビュー | cmd_317v2 |
<!-- lesson-sort 2026-03-16 Phase2: サブセクション化実施 -->

### bash/シェルスクリプト
- L059: 共通スクリプトのリファクタ後はインタフェース契約の確認が必要。usage_status.shは引数なし統合出力設計だがusage_statusbar_loop.shが引数付き2回呼出しで重複表示バグ。呼出し側と被呼出し側のI/F整合を検証せよ。（usage_statusbar_loop.sh重複表示バグの修正体験）
- L074: bash ((var++))はvar=0時にset -eで即exit — $((var+1))を使え（bash,set-e,arithmetic,trap）
- L092: awk state machine複数エージェント属性パース時のリセット位置（cmd_404）
- L096: preflight_gate_flags()でlocal変数をif/else跨ぎで参照する場合、両ブロックのどちらが実行されても参照可能なスコープ（関数先頭等）で宣言・初期化すべき。bashのlocalは関数スコープだが、宣言がif内にあると実行されないelseブロックでは未初期化になる。（cmd_407）
- L149: shellスクリプトでrgを使うな、grepを使え（cmd_537）
- L155: lib/配下の共通関数は呼出し元の環境変数依存を明示バリデーションすべき（cmd_546）
- L156: set -e環境で共通関数の非0戻り値を直接受けると即時終了する（cmd_545）
- L157: 追記型YAMLの上限制御はappend直後に同一トランザクションで実施すべき（cmd_547）
- L164: Claude Code Hooksのshスクリプトはset -euのみ使用しpipefail禁止（hooks）
- L169: YAMLへの追記をheredoc直書きすると引用符/改行で構造破壊する（cmd_578）
- L170: terminalログ保存でバイト切り詰め(head -c)を使うとUTF-8破損が混入する（cmd_578）
- L171: Python呼出しパイプパターンexit code喪失 + bash→Python変数受渡しos.environ統一（cmd_585）
- L177: 追跡ログのキーをproducer/consumerで変える時は両側同時に整合させよ（cmd_611）
- L183: bashrc export検証は対話シェル前提を確認せよ（cmd_664）
- L184: set -u配下で任意引数を追加するbash関数は既存呼び出し互換を守れ（cmd_667）
- L231: ruffの出力判定は終了コードか--quietで行うべき（cmd_979）
- L278: YAML値出力時にコロンを含む値は必ずダブルクォートで囲め。report_field_set.sh等でクォートなしだとYAMLパースエラーになる（cmd_1162）
- L279: 複数フィールド検出はsed+headよりawkパターンマッチを使え。部分記入検出が容易でフィールド欠落の個別特定も1パスで可能（cmd_1170）
- L263: bashライブラリ関数のwhile read変数名は呼出元と衝突する(動的スコープ)（cmd_1136）
- L269: bashのwhile readでYAMLブロック境界判定は不安定→awkを使え（cmd_1152）
- L270: flat YAML非対応時のフォールバック考慮必須（cmd_1156）
- L272: yaml_field_set flat対応はbash-levelフォールバック方式が安全（cmd_1157）
- L277: IFS readのleading delimiter stripping（kotaro）

### git/gitignore/CI/hooks
- L064: gitignore whitelist未登録は実行テストで検出不可（cmd_359）
- L072: git-ignoredスクリプトがwhitelist漏れで現役使用されるリスク — clone後に動作不全（cmd_368）
- L093: impl忍者のgit add漏れ — 新規ファイル作成時のcommit忘れ（cmd_404）
- L109: git commit時のstaging巻き込み防止（cmd_452）
- L110: settings.local.jsonはwhitelist外、並行レビューでcommit重複リスク（cmd_449）
- L113: タスク指定ファイルが.gitignore whitelist外だとcommit要件を満たせない（cmd_463）
- L116: .gitignore whitelist-basedリポジトリでは新規スクリプト作成時に必ずwhitelist追加が必要（cmd_466）
- L143: gitignoreエラーはgateログに記録されず暗数化する — 15日間で最低11件、モデル非依存（cmd_534）
- L144: git add失敗の頻度分析にはgate_metricsではなく専用guardログが必要（cmd_534）
- L150: git commit --dry-runではpre-commitが走らずAC誤判定になる（cmd_537）
- L151: Git hook導入時はスクリプト内容だけでなく executable bit(100755) のコミット有無を必須確認（cmd_537）
- L153: レビューACにpush条件がある場合は事前に ahead/behind を確認する（cmd_546）
- L172: レビューでは『履歴位置確認』を先に行うと push 可否の誤判定を防げる（cmd_590）
- L179: 忍者がcommit未実施でdone報告するケース（cmd_648）
- L180: whitelist型.gitignore配下では新規ファイルのstage前にgit check-ignoreを確認する（cmd_649）
- L186: 共有mainへのreview push前は remote確認だけでなく local HEAD再確認も直前に行え（cmd_675）
- L188: impl忍者のcommit未実施(L179再発)（cmd_702）
- L189: 並列impl配備時は全忍者のcommit完了を確認してからreview配備せよ（cmd_707）
- L190: 並列impl配備時は全忍者のcommit完了を確認してからreview配備せよ。cmd_707で3名並列impl後review時、才蔵のみcommit済み・小太郎と影丸が未コミット。review配備前にgit statusで未コミット差分を確認すべき（cmd_707）
- L192: review配備前にcommit完了とgenerated派生物差分を分離確認せよ（karo）
- L218: .gitignoreホワイトリスト未追加はレビューでも検出必須（cmd_876）
- L220: bulk commit AC4 は queue/禁止hook と live-generated tracked files を考慮して定義せよ（cmd_904）
- L232: pre-pushフックtimeout: 294テストが120秒内に完走しない（cmd_995）
- L233: review task の `git diff --check` AC は対象commitスコープか clean-tree 前提を明示すべし（cmd_996）
- L377: 短命タスクのcommit指示前にHEADを再確認せよ（cmd_1032）

### deploy_task.sh/配備
- L056: タスクYAML上書き問題: auto_deploy時の全サブタスク永続化（cmd_338）
- L057: cmd_338（check_and_update_done_task()はhandle_confirmed_idle()→is_task_deployed()内でのみ発火。忍者がidle確認後にしかauto-done判定されない。報告YAML→idle遷移まで最大20秒+CONFIRM_WAITのラグ存在。将来report YAML inotifywatchに移行すればラグ解消可能）
- L070: deploy_task.shはタスクYAMLの2スペースインデントを6箇所で固定仮定。YAML構造変更で沈黙死（cmd_370）
- L071: SCRIPT_DIR設計パターンが2系統混在(リポルート基準 vs scripts/自身基準)で新規スクリプト作成時に混乱リスク（cmd_370）
- L073: タスク指示のパス相対指定は実ファイル位置で必ず検証せよ（path-resolution,task-instruction-verification,security-boundary）
- L076: deploy_task.sh旧Python -cブロックにL047違反が残存（cmd_384）
- L079: deploy_task.sh再配備でrelated_lessons.reviewedがfalseに戻る→入口門番BLOCK（cmd_387）
- L088: deploy_task.shタグ推定パターンが広すぎて平均4.6タグ→フィルタリング無効化。lesson_tags.yamlの汎用語(環境,注入等)を除去しmax 3タグ制限が必要（cmd_397）
- L111: ACに含めるテストファイルは配備時に実在確認が必要（cmd_460）
- L119: deploy_task.shのpostcondファイル経由でbash→Pythonのデータ受け渡しパターンが確立（cmd_470）
- L181: タスク記述と実際のgit状態の乖離確認（cmd_652）
- L185: report_path 注入だけで報告テンプレート未生成→忍者が手動補完（cmd_675）
- L207: field_getはYAML block scalar指示子をリテラル文字列で返す（cmd_795）
- L219: 偵察タスクの履歴参照パスは実在パスで配るべし（cmd_887）
- L222: deploy_task.sh既定値補完: empty sentinelテスト必須（cmd_926）
- L230: deploy_task.shのlessons_by_id dict構築でplatform教訓がproject教訓を上書きする（cmd_980）
- L256: deploy_task.sh lessons_by_id dictのID衝突でPJ間教訓が上書きされる（cmd_1127）
- L284: 並行cmd同一ファイル編集時のnot_in_scopeスコープ衝突防止（cmd_1181）

### 報告YAML/レポート/アーカイブ
- L055: report YAML構造混在に対するフォールバック必須（cmd_337）
- L060: タスクYAML/報告YAMLの上書き式がメトリクスデータ永続性を阻害（cmd_344）
- L062: acceptance_criteriaフィールドはdict/str混在のためjoin前に型変換が必要（--tags）
- L085: 報告YAML命名変更はCLAUDE.md自動ロード+common/ビルドパーツ+全スクリプトの横断更新が必須（cmd_392）
- L091: L085再発(派生ファイル未更新): CLAUDE.md変更時は全派生ファイルをACスコープに含めよ（cmd_403）
- L095: archive_dashboard()のgrep戦果行パターン不一致 — AUTO移行後は常にno-op（cmd_406）
- L098: L_archive_mixed_yaml（yaml,archive,parsing,resilience）
- L120: report gateの存在判定はprefix検索+archive探索が必要（cmd_482）
- L121: YAML回転処理でヘッダ保持を欠くと後続appendが既存履歴を失う（cmd_490）
- L127: 再配備前に先行commit/reportの存在を確認すべき（cmd_494）
- L131: archive_completed.sh sweep modeはparent_cmd完了チェック必須（cmd_510）
- L132: dashboard_update.shは完了報告専用、進捗メモはEdit toolで記録すべき（cmd_511）
- L209: done通知は inbox_write 直送を禁止し、報告ファイル検証付きラッパに一本化する（cmd_812）
- L210: done通知を transport 層で信用すると report file 欠損の虚偽完了が通る（cmd_812）
- L362: ベンチマーク計測報告はJSON生データをSSoTとし報告YAML文面は二次参照（cmd_1027）
- L264: archive_cmds list形式grepとdict形式STKの断絶（cmd_1140）

### 教訓サイクル/lesson system
- L054: lesson_write.shのcontextロック失敗が非致命でSSOTとcontext不整合を許容（cmd_323）
- L063: lessons.yamlはdict構造(lessons:キー配下リスト)。for lesson in dataはdictキーをイテレート→誤り。data['lessons']で取得せよ（cmd_351）
- L075: L075（cmd_378）
- L080: sync_lessons.sh新フィールド追加時はパース+キャッシュ保持の2箇所を更新必須（cmd_385）
- L081: 追記型YAMLファイルのフォーマット変更時は既存データのマイグレーションも必須（cmd_388）
- L086: auto_draft_lesson.shがlesson_write.shをCMD_ID空で呼ぶためlesson.done未生成（cmd_391）
- L087: 教訓効果メトリクスΔはBLOCKリトライ行膨張+構造BLOCK混入で歪む — cmd単位dedup+品質BLOCK分離が必須（cmd_397）
- L089: universal教訓がdm-signalで30件(23%)に膨張し注入枠10件中5件を固定占有 — タスク固有教訓枠を圧迫して精度低下（cmd_397）
- L102: lesson_tracking.tsvのデータソース相違 — タスク記述はqueue/gate_metrics.yamlだが実在はlogs/lesson_tracking.tsv（cmd_414）
- L106: lesson_impact_analysis.shのload_lesson_summariesパス誤り（cmd_444）
- L107: dedupログ仕様は文言と0件時出力条件をAC文字列と厳密一致させる（cmd_446）
- L117: lesson_referenced→lessons_usefulリネーム時に全派生ファイル(generated/4本+roles/+templates/)を漏れなく更新する必要がある（cmd_466）
- L126: [自動生成] 有効教訓の記録を怠った: cmd_497（cmd_497）
- L133: injection_countがlessons.yamlで全件0(未同期)（cmd_514）
- L136: preflight_gate_flags upgradeのhas_found_trueスコープ不整合でlesson_done_source BLOCKが頻発（cmd_529）
- L137: lesson_done先行生成とpreflight upgradeの設計的不整合（cmd_529）
- L141: lesson_deprecation_scan.shの自動退役はsubprocessで外部スクリプト呼出のため、大量教訓がある場合に遅くなる可能性（cmd_531）
- L145: ashigaru.md生成はbuild_instructions.shで行われる→source filesを修正すべき(L005の実践確認)（cmd_533）
- L147: related_lessons.detail注入はlessons.yamlスキーマ依存 — 現行スキーマではAC6未達（cmd_533）
- L152: KM_JSON_CACHEの無効化条件にlessons.yaml変更が含まれない（cmd_541）
- L154: [自動生成] 有効教訓の記録を怠った: cmd_546（cmd_546）
- L165: 教訓効果率は『未解決負債』だけでなく『仕組み化後の未退役』でも低下する（cmd_567）
- L168: auto_draft_lesson.shのIF-THEN引数にスペース含む値を渡すと切り詰められる（cmd_575）
- L214: ローカルIDを複数PJで再利用する系ではメトリクスキーを(project,id)にせよ（cmd_874）
- L217: lesson_impact.tsvのPENDING行を淘汰・同期カウントへ入れるな（cmd_878）
- L257: lesson_impact.tsvのtask_type列にimplとimplementが混在し参照追跡が分断（cmd_1127）
- L260: knowledge_metricsとlesson_impact.tsvのinjection_count乖離+Bottom教訓のPJ識別にはPJ列が必要+reconスキップの長期影響はPJ特性で差が出る（cmd_1127）
- L266: 教訓registrationは常にlesson_write.sh経由（cmd_1142）
- L273: 計測基盤は永続ログを一次ソースにすべし（cmd_1162）
- L275: 計測指標の分母定義を精査せよ — 意図的除外が分母を膨らませ過小評価を招く（cmd_1165）
- L276: 計測指標の分母が意図的除外を含む場合はフィルタ漏れに注意（cmd_1168）

### ゲート/gate_metrics
- L097: cmd_complete_gate.shのresolve_report_file()がgrep直書きでreport_filename取得 — L070除外対象外（cmd_410）
- L099: backfill対象ログファイルのフォーマット事前確認の重要性（cmd_413）
- L100: gate_metrics task_type遡及の最適データソース（cmd_413）
- L101: gate_metrics.logはTSV形式(YAMLではない)（cmd_413）
- L215: IF gate_metricsテストを書く THEN tmuxモックを配置してライブ環境からの干渉を防げ BECAUSE resolve_agent_model_labelはtmux変数を優先し、settings.yamlのフォールバックがテストされない（cmd_875）
- L216: gate_metricsテストがtmux環境依存（cmd_875）
- L262: stop-lint-gate.shの偽ブロック防止: (1)shellcheckに-S warning追加でinfo/style除外 (2)block時exit 1→exit 0でJSON decisionに委譲(exit 1はClaude Codeにhookエラーと誤判定される) (3)全uncommitted filesを対象にするため他忍者の変更でブロックされうる構造的欠陥は認識済み（cmd_1136実装中の半蔵がstop hook errorで停止）
- L280: 自動消火→通知変換の3点セットチェック（cmd_1175）
- L282: gate未実装の機械的チェックが5項目存在（cmd_1173）

### テスト
- L142: 飛猿報告のテスト8件はbatsテスト2件のみ — テスト件数根拠明示義務（cmd_532）
- L146: AC6系レビューは実配備YAML確認だけでなく一時環境での再現実行を必須にすべき（cmd_533）
- L148: AC文言は値参照元変更以外(例: コメント追記)の許容範囲を明示すると判定ブレを防げる（cmd_532）
- L158: ローテーション機能レビューでは境界値テストに加えて過剰初期データの実地検証が有効（cmd_547）
- L162: フックスクリプトテストではsymlink構造でSCRIPT_DIRリダイレクトするモック手法が有効（testing）
- L163: MAX_ENTRIES等の定数変更時は既存テストの前提値も同時更新が必要（testing）
- L191: E2E fixture参照は tests/e2e/fixtures 実在確認をCIで壊れやすい前提として先に検証すべき（cmd_714）
- L193: pre-push制約時間の主要因はアプリ本体ではなくテストハーネスの固定待ちと初期化重複になりやすい（cmd_715）
- L208: テスト#158ライブtmux環境依存FAILの修正要（cmd_799）
- L234: Android local unit test で org.json.JSONObject.put を直接使うと not mocked で落ちる（cmd_997）
- L235: WSL2 /mnt/c 上の Android KSP incremental は generated/ksp byRounds で崩れることがある（cmd_997）
- L261: 全体設定変更時のテスト整合性チェック不足（cmd_1128）

### 知識管理/ビルド
- L065: テンプレート定義とvalidation対象の一致確認義務（cmd_360）
- L066: reset_layout.shのような複数スクリプトを横断する機能では、依存APIのYAMLキー名を実データと突合せよ。settings.yamlのmodel_name vs get_agent_model()のmodelのようなキー不一致はdry-runでは正常終了するが実行結果が誤る（cmd_361）
- L077: Vercel構造分離では全セクション移動先マッピングを事前作成せよ（cmd_383）
- L084: roles/ashigaru_role.mdは現在不存在 — build_instructions.shがashigaru.md直接処理（cmd_392）
- L090: build_instructions.sh派生ファイル(gitignore対象)はCLAUDE.md修正だけではgit diffに現れない（cmd_403）
- L104: 本家参照時のパス揺れ — tree確認後に取得を標準化（cmd_438 sasuke）
- L128: OSS参照タスクはcanonical repository解決を初手に入れる（cmd_506）
- L135: build_instructions.sh は --help 指定でも生成処理を実行する（cmd_523）
- L173: build_instructions.sh再生成時はCLAUDE.md正本も同期→AGENTS系の旧表記残存を防止（cmd_604）
- L182: 設定UIで保存した値が実行経路で読まれているか別経路まで確認せよ（cmd_658）
- L206: CC BY 4.0はOSS利用で最も柔軟なライセンスの一つ（cmd_798）
- L212: 一次データ不可侵原則: 外部知識(論文/API仕様/書籍等)は原典のまま保存し、自軍の解釈・適用は別セクション/別ファイルに分離する。改変は捏造。全PJ共通適用
- L353: 共有出力ファイルにWriteツール上書きで他忍者の成果消失リスク。Edit(追記)かセクション分離ファイルで配備せよ（cmd_1021）
- L274: instructions変更時は正本(instructions/*.md)+CLAUDE.md要約行の同時更新を確認せよ（cmd_1163）

### レビュー
- L061: 統合設計レビューではソースコード実地確認が必須（cmd_344）
- L138: レビューcmdは要求範囲外差分をBLOCK対象として明示判定すべき（cmd_528）
- L139: scope外変更のrevert確認では、正味diff(HEAD~N..HEAD)と個別commit diffの両方を突合すべき（cmd_528）
- L140: レビューFAIL指摘時はrevert対象を明示し、scope内差分を保持した最小修正で再提出すべき（cmd_528）
- L236: L236（cmd_998のDC_998_02(朱雀排除)がPD-007で裁定済みにもかかわらず再エスカレーションされた。殿の時間を無駄にした）
- L239: 並列implレビューはcommit integrityを独立チェックせよ（cmd_1031）
- L375: 並列実装レビューは『内容』と『commitに閉じているか』を分離して見るべし（cmd_1031）
- L267: 推薦先行+WHY形式を将軍ルールに恒久化（cmd_1143）
- L283: 偵察報告の「未実装/不在」主張にはコード現物精読+存在確認をbinary_checksで義務化（cmd_1173）

### LLM/エージェント/MCP
- L051: Sonnet 4.6はMUST/NEVER/ALWAYSをリテラルに従わず文脈判断でオーバーライドする。否定指示は肯定形+理由付き、絶対禁止は条件付きルーティング(IF X THEN Y)に変換すると遵守率向上。Pink Elephant研究で学術裏付け
- L053: Claude 4.x CRITICAL/MUST/NEVERがovertriggering副作用（cmd_324）
- L108: compact_stateの長さ未制限による500文字超過リスク（cmd_452）
- L130: Get-Clipboard -Format Imageは非画像時にnullを返す（cmd_508）
- L159: 大規模偵察タスクの並列Agent活用パターン（cmd_548）
- L178: Claude Codeドキュメントのホスト移行（docs.anthropic.com→code.claude.com）（cmd_630）
- L201: MCP Memory APIにはobservation単位のメタデータ(tag/priority)がなく、マーカーは本文埋込が唯一の実用策（cmd_732）
- L203: xAI x_searchはResponses API+grok-4ファミリー限定（cmd_738）
- L211: 大規模偵察(8名以上)には統合専任担当(水平H)をcmd設計段階で組み込むべき（cmd_862）
- L213: サブエージェントは「読み取り専用の一時ツール」に限定せよ — capability制約(Read+Grep+Glob/plan mode/haiku/maxTurns 4)+behavior制約(判定禁止/所見のみ)の分離設計が必須（cmd_873）
- L223: gstackのwrapError+checklist分離+Named Invariantsパターン（cmd_931）
- L224: MCP obsに運用ルールと殿の好みを混在させると陳腐化が加速する（cmd_957）
- L225: MCP棚卸しではentity/project境界の混入を先に検査すべし（cmd_957）
- L226: Codexモデルは/clear Recovery時に849行→9行圧縮でアイデンティティを失う
- L238: L238（/tmp/mcas_usage_status_cache_*が壊れるとCodexだけでなくClaude側も表示不能になる連鎖障害が発生した）
- L400: 多角度偵察の価値は個別発見の合算ではなく相互作用の可視化。6角度統合で乗算的相乗効果(T3×T1, T3×T5)と設計依存(T3→T5)が明確化（cmd_1037）

### UI/Android
- L187: Compose の zoom 下限は viewport 配下の onTextLayout 幅から計算するな（cmd_689）
- L195: UIコントラスト・アクセシビリティ基準（cmd_730）
- L196: UIスペーシング・レイアウト基準（cmd_730）
- L197: UIタイポグラフィ基準（cmd_730）
- L198: UIボタン・インタラクション基準（cmd_730）
- L199: UIビジュアルヒエラルキー・一貫性基準（cmd_730）
- L200: 殿のUI好み: 無地背景・チップ形式・デザインガイド参照（cmd_730）
- L202: Compose で固定テーマ定数が広く直参照されている時は Material colorScheme 追加だけでは多テーマ化できない（cmd_729）

### → セクション振り分け済(ID参照のみ — 詳細は上記メインセクション参照)
L052,058,067,068,069,082,083,094,103,105,112,114,118,122,123,124,125,129,134,160,161,166,167,174,175,176,194,204,205,221,227,228,237,240,241,242,243,244,245,246,247,248,249,250,251,252,253,254,255,256,257,258,259,260,261,262,263,264,265,266,267,268,269,270,271,272,273,274,275,276,277,278,279,280,281,282,283,284
