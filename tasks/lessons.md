
### L001: Read before Write必須（Claude Code制約）
- **status**: confirmed
- **日付**: 2026-02-18
- **出典**: cmd_125
- **記録者**: karo
- Claude CodeはRead未実施のファイルへのWrite/Editを拒否する。タスクYAML・inbox・報告YAML等を書く前に必ず対象ファイルをReadせよ。Write-before-Read試行はエラーとなりリトライが必要になる。

### L002: inbox_watcher.shのforeground bashブロックで家老が応答不能になる
- **status**: confirmed
- **日付**: 2026-02-18
- **出典**: cmd_125
- **記録者**: karo
- inbox_watcher.shは60秒リトライ内蔵だが、家老がforeground bashコマンドでブロック中はnudgeを受信できない。Bash toolのrun_in_background=true必須化で解決。新スクリプト不要。

### L003: CLAUDE.md更新は稼働中エージェントに即反映されない
- **status**: confirmed
- **日付**: 2026-02-18
- **出典**: cmd_125
- **記録者**: karo
- CLAUDE.mdやinstructions/*.mdを更新しても、既に稼働中のエージェントのコンテキストには反映されない。ninja_monitor.shにcheck_script_update機能を追加し、スクリプト更新時に/clearを発動して再読み込みさせる仕組みで解決(cmd_125)。

### L004: ペイン変数(@current_task)が空でも未配備と断定するな
- **status**: confirmed
- **日付**: 2026-02-18
- **出典**: cmd_092
- **記録者**: karo
- tmuxペイン変数@current_taskが空文字でも、忍者が実際にアイドルとは限らない。capture-paneで実際の画面出力を確認してから判断せよ。変数が設定されていないだけで作業中の可能性がある。

### L005: build_instructions.shはashigaru.mdのYAML front matterのみ抽出する
- **status**: confirmed
- **日付**: 2026-02-18
- **出典**: cmd_134
- **記録者**: karo
- ashigaru.mdの本文コンテンツはroles/ashigaru_role.mdから取得される。ashigaru.md本体への変更だけではbuild生成物に反映されない。roles/のパーツファイルも同時に更新が必要。

### L006: lesson_write.shには既存教訓との重複チェック機能がない
- **status**: confirmed
- **日付**: 2026-02-18
- **出典**: cmd_134
- **記録者**: karo
- **if**: lesson_write.shで新規教訓を登録する時
- **then**: タイトル類似度チェックまたはsource_cmd重複チェックを事前に実施せよ
- **because**: 重複チェック機能が未実装のため、同一内容の教訓が複数登録されるリスクがある
- IF lesson_write.shで新規教訓を登録する時 THEN タイトル類似度チェックまたはsource_cmd重複チェックを事前に実施せよ


### L007: .gitignoreがwhitelist方式の場合、新規スクリプト追加時はwhitelist許可(!path)を追加せよ
- **status**: confirmed
- **日付**: 2026-02-18
- **出典**: cmd_140
- **記録者**: karo
- multi-agent-shogunの.gitignoreは*で全除外→!で個別許可方式。scripts/配下に新ファイルを作成してもwhitelist未追加だとgitignoreされ、git addしてもcommitに含まれない。レビュー担当も確認必須。


### L008: WSL2新規shファイルはCRLF改行混入リスクあり
- **status**: confirmed
- **日付**: 2026-02-18
- **出典**: cmd_143
- **記録者**: karo
- WSL2環境(/mnt/c/)でClaude CodeのWriteツールで新規.shファイルを作成するとCRLF改行になる場合がある。新規.sh作成後はfile commandでチェックし、CRLF混入時はsed -i 's/\r$//' で修正。レビュー時もfile commandでCRLFチェックを追加すべし。

### L009: commit前にgit statusで全対象ファイルの認識状態を確認せよ
- **status**: confirmed
- **日付**: 2026-02-18
- **出典**: cmd_143
- **記録者**: karo
- **if**: whitelist方式.gitignoreのリポジトリでcommitする時
- **then**: git statusで全対象ファイルの認識状態を確認し、whitelist追加漏れがないか検証せよ
- **because**: whitelist未追加ファイルはgit addしてもcommitに含まれず、実装者が気づきにくい
- IF whitelist方式.gitignoreのリポジトリでcommitする時 THEN git statusで全対象ファイルの認識状態を確認し、whitelist追加漏れがないか検証せよ

### L010: 報告YAMLのstatus行先頭マッチ
- **status**: confirmed
- **日付**: 2026-02-18
- **出典**: cmd_145
- **記録者**: hanzo
- **if**: 報告YAMLからstatus行をgrepで抽出する時
- **then**: '^status:'で先頭マッチさせよ
- **because**: indent付きstatusフィールド(result内等)との誤マッチを防ぐため
- IF 報告YAMLからstatus行をgrepで抽出する時 THEN '^status:'で先頭マッチさせよ

### L011: core.hooksPathフック配置確認
- **status**: confirmed
- **日付**: 2026-02-18
- **出典**: cmd_147
- **記録者**: saizo
- core.hooksPathが.githooksに設定されている場合、.git/hooks/にフックを配置しても無視される。フック作成時はまず git config --get core.hooksPath を確認し、適切なディレクトリに配置すべし。

### L012: bashrc aliasではパイプ構文ブロック不可
- **status**: confirmed
- **日付**: 2026-02-18
- **出典**: cmd_147
- **記録者**: tobisaru
- bashrc aliasではパイプ構文(curl|bash等)をブロックできない。パイプはシェル構文であり個々のコマンドのalias化では検知不可。capture-pane監視(ninja_monitor)による検知が有効な代替手段。

### L013: L005教訓はkaro系にも適用
- **status**: confirmed
- **日付**: 2026-02-18
- **出典**: cmd_150
- **記録者**: hanzo
- karo.md(直接読み用)とroles/karo_role.md(ビルド用ソース)は別ファイル。karo.mdの変更だけではgenerated/karo.md等のビルド生成物に反映されない。一括置換タスクでは両方をスコープに含めるべき。L005のkaro版。

### L014: grep --excludeはWSL2 /mnt/c上で不安定
- **status**: confirmed
- **日付**: 2026-02-18
- **出典**: cmd_151
- **記録者**: karo
- **if**: grep --exclude時
- **then**: grep --exclude-dirやgrep --excludeはWSL2の/mnt/c(Windows FSマウント)上では予期しない動作をすることがある
- **because**: パイプフィルタ(grep -Ev 'pattern')の方が確実
- IF grep --exclude時 THEN grep --exclude-dirやgrep --excludeはWSL2の/mnt/c(Windows FSマウント)上では予期しない動作をすることがある

### L015: CLAUDE_CONFIG_DIR環境変数で~/.claudeディレクトリを丸ごと切替可能。CLAUDE_CODE_OAUTH_TOKENで認証のみの切替も可能
- **status**: confirmed
- **日付**: 2026-02-18
- **出典**: saizo
- **記録者**: karo
- **if**: Claude Codeで複数アカウントを運用する時
- **then**: CLAUDE_CONFIG_DIRで~/.claude丸ごと切替、CLAUDE_CODE_OAUTH_TOKENで認証のみ切替を使い分けよ
- **because**: 環境変数で設定ディレクトリや認証を分離でき、複数アカウント運用が可能になるため
- IF Claude Codeで複数アカウントを運用する時 THEN CLAUDE_CONFIG_DIRで~/.claude丸ごと切替、CLAUDE_CODE_OAUTH_TOKENで認証のみ切替を使い分けよ

### L016: OAuthリフレッシュトークンは単一使用。複数セッション共有時にプロセスAがリフレッシュするとBのトークンが無効化される。CLAUDE_CODE_OAUTH_TOKENで直接指定すればリフレッシュ競合を回避可能
- **status**: confirmed
- **日付**: 2026-02-18
- **出典**: tobisaru
- **記録者**: karo
- **if**: OAuthリフレッシュトークンを複数セッションで共有する時
- **then**: CLAUDE_CODE_OAUTH_TOKENで直接トークンを指定してリフレッシュ競合を回避せよ
- **because**: リフレッシュトークンは単一使用のため、プロセスAがリフレッシュするとBのトークンが無効化される
- IF OAuthリフレッシュトークンを複数セッションで共有する時 THEN CLAUDE_CODE_OAUTH_TOKENで直接トークンを指定してリフレッシュ競合を回避せよ

### L017: 入口門番は再配備時に自己ブロックする
- **status**: confirmed
- **日付**: 2026-02-18
- **出典**: cmd_158
- **記録者**: karo
- deploy_task.shの入口門番(check_entrance_gate)は、同一タスクの再配備時にもreviewed:false残存をブロックする。初回起動失敗→再配備のケースではinbox_write.sh直接送信で回避が必要。将来的にoverride経路の検討が望ましい

### L018: Claude Code Edit toolはflock未対応 — 並行書込みファイルにEdit toolを使うな
- **status**: confirmed
- **日付**: 2026-02-20
- **出典**: cmd_189
- **記録者**: karo
- Claude Code Edit toolはファイルロック(flock)を使わない。inbox_write.shがflock付きで書込む同ファイルにEdit toolで書き戻すと、inbox_write.shの書込み内容が失われる(Lost Update)。対策: flock+atomic writeを行うシェルスクリプト(inbox_mark_read.sh)で代替。同様の問題は他のflock付きスクリプトが触るファイル全般に存在しうる。

### L019: grep -c || echo 0で0件時に0\\n0が生まれる
- **status**: confirmed
- **日付**: 2026-02-20
- **出典**: cmd_192
- **記録者**: karo
- grep -c patternは0件時も'0'を出力してexit 1を返す。|| echo 0を付けると'0'出力後にecho 0が追加実行され、変数が'0\n0'になる。件数カウントにはawkを使うか、出力の改行/空白除去+数値バリデーションを必ず実装する。

### L020: cli_lookup.shの設定パス環境変数共有
- **status**: confirmed
- **日付**: 2026-02-21
- **出典**: cmd_208
- **記録者**: karo
- **if**: sourceされるライブラリの設定パスを定義する時
- **then**: 呼出し元と共通の環境変数(例: CLI_ADAPTER_SETTINGS)を使用せよ
- **because**: 独立した変数をハードコードするとテスト時にオーバーライドできないため
- IF sourceされるライブラリの設定パスを定義する時 THEN 呼出し元と共通の環境変数(例: CLI_ADAPTER_SETTINGS)を使用せよ

### L021: declare -Aのスコープ問題(bash source)
- **status**: confirmed
- **日付**: 2026-02-21
- **出典**: cmd_208
- **記録者**: karo
- declare -Aは関数内でsourceされるとfunction-localになる。declare -gAを使えばグローバルスコープに宣言できる(bash 4.2+)。キャッシュ用連想配列をライブラリに持つ場合は特に注意。

### L022: pending_decision_write.sh resolveのflock内pythonリトライ誤発動
- **status**: confirmed
- **日付**: 2026-02-21
- **出典**: cmd_220
- **記録者**: karo
- flock内pythonがexit 1するとサブシェル失敗→lock失敗と誤認し3回リトライする。python exit codeの分離が望ましい。現状は結果正常のため低優先

### L023: 教訓自動化は報告スキーマ先行整備なしでは品質劣化
- **status**: confirmed
- **日付**: 2026-02-22
- **出典**: cmd_231
- **記録者**: karo
- lesson_candidateからの転記自動化が最適解。key_findingsからの自動抽出はノイズ増大(3名一致)。入力品質(報告スキーマ厳格化)を先に固定してから自動化すべき。found=trueのlesson_candidate→draft登録→家老confirm/rejectの流れ。GATE BLOCKは不要(棚卸しで監視)。

### L024: 報告YAMLアーカイブ不在で歴史的教訓分析が不可能
- **status**: confirmed
- **日付**: 2026-02-22
- **出典**: cmd_231
- **記録者**: karo
- queue/reports/は各忍者1ファイルで最新報告のみ保持。archive_completed.shはreportsを退避対象としていない。教訓登録効果測定や品質分析にはアーカイブ保存が必要。3名合議で独立に同一問題を指摘。

### L025: draft
- **日付**: 2026-02-22
- **出典**: hanzo(cmd_236統合)
- **記録者**: karo
- **status**: deprecated
- **deprecated_by**: L042
- reports/上書き問題は統合タスク割当パターンで実害発生する。偵察→統合を同一忍者に割り当てるとdeploy_task.shのreport初期化で偵察報告が消失。L024の実害パターン。回避策: (1)偵察者と統合者を別忍者にする (2)report archive機能を実装する(L024根本解決)。

### L026: 知識陳腐化の定量実態と解決方針(cmd_237合議3名統合)
- **日付**: 2026-02-22
- **出典**: kagemaru(cmd_237統合)
- **記録者**: karo
- **if**: 知識ファイルの陳腐化が疑われる時
- **then**: 追加onlyの運用を見直し、定期的な削除・更新サイクルを導入せよ
- **because**: 陳腐化の根本原因は追加のみで削除されない構造にあり、方針レベルで20-30%が陳腐化する
- IF 知識ファイルの陳腐化が疑われる時 THEN 追加onlyの運用を見直し、定期的な削除・更新サイクルを導入せよ

### L027: reports/上書き問題は統合タスク割当パターンで実害発生する
- **日付**: 2026-02-22
- **出典**: cmd_236
- **記録者**: hanzo
- **status**: deprecated
- **deprecated_by**: L042
- 偵察と統合を同一忍者に割り当てると、統合タスクのreport初期化で偵察報告が消失する。
L024(アーカイブ不在)の実害パターン。回避策: (1)偵察者と統合者を別忍者にする
(2)report archive機能を実装する(L024根本解決) のいずれか。

### L028: CI Run番号とcommit SHAの整合性確認
- **日付**: 2026-02-22
- **出典**: cmd_248
- **記録者**: karo
- タスク記述のRun#とSHAが実データと異なるケースがある。Run #73=SHA c2313802(失敗)だが、タスクにはRun #73=SHA 06829a3と記載されていた。調査開始前にgh run listで実データを確認すべし

### L029: nudge嵐主因は二重経路(watcher再送+monitor再送)の合流増幅
- **日付**: 2026-02-22
- **出典**: cmd_255
- **記録者**: sasuke
- inbox_watcherの60秒安全網とninja_monitorのrenudge/cmd_pending再送が独立に動作するため、受信側が1回取り逃すと同一未読に対するnudgeが多重化する。再送は単一路化し、状態遷移またはfingerprint基準で制御すべき。fingerprint=unread ID集合のsort後hash。countではなくID集合をキー化。

### L030: current_projectフィールドは宣言のみで読み取りスクリプトがゼロの死コード状態
- **日付**: 2026-02-23
- **出典**: cmd_258
- **記録者**: kotaro
- config/projects.yamlのcurrent_projectは定義されているが、scripts/配下で このフィールドを読むスクリプトがゼロ。プロジェクトルーティングは完全に

### L031: CLAUDE.md PJ固有比率は4%のみ(14行/347行)
- **日付**: 2026-02-23
- **出典**: cmd_258
- **記録者**: kotaro
- **if**: CLAUDE.md PJ固有比率時
- **then**: 95%以上がPJ非依存骨格
- **because**: PJ切替時の変更対象はDM-Signal圧縮索引セクション(14行)のみ
- IF CLAUDE.md PJ固有比率時 THEN 95%以上がPJ非依存骨格

### L032: CLAUDE.md PJ固有セクション境界は##見出しレベルで識別
- **日付**: 2026-02-23
- **出典**: cmd_258
- **記録者**: saizo
- ##PJ名から次の##直前までが差替え対象。セクション内の###は区切りではない。才蔵設計

### L033: lesson_write.shはstatus=confirmed時にSSOTにstatus行を書かず、sync後のYAMLでstatus欠落を引き起こす
- **日付**: 2026-02-23
- **出典**: cmd_262
- **記録者**: karo
- lesson_write.sh L150-151でdraftのみstatus出力。confirmedはスキップ。sync_lessons.shはSSOTにstatus行がなければYAMLにも生成しない。27件の欠落がこれで説明される。推奨修正: sync_lessons.sh側でstatus未検出時にconfirmedをデフォルト設定(案B)

### L034: shogun_to_karo.yamlのインデントが動的に変動する(2space→0space)
- **日付**: 2026-02-23
- **出典**: subtask_279_gate1
- **記録者**: karo
- awk/sedパターンは固定インデントに依存させず柔軟なマッチに。cmd_complete_gate.shのupdate_status()も4space固定依存あり要注意

### L035: cmd_complete_gate.shの検証で副作用が発火する可能性
- **日付**: 2026-02-23
- **出典**: subtask_279_integ
- **記録者**: karo
- cmd_complete_gate.shはテスト用cmdでもinbox_archiveチェックを走らせる。検証時は運用データに副作用を与え得るため、隔離データまたは明示dry-run設計が望ましい

### L036: テストデータrevertでgit checkout -- SSOTは未コミット教訓を消失させる
- **日付**: 2026-02-25
- **出典**: cmd_310
- **記録者**: karo
- **if**: テストデータrevertでgit checkout -- SSOT時
- **then**: 対策: SSOTのrevertはgit管理外ファイルのみか、当該テストエントリのみ手動削除で対処すべき
- **because**: テスト後のrevert対象をgit checkout -- lessons.mdとするとL030-L035が消失
- IF テストデータrevertでgit checkout -- SSOT時 THEN 対策: SSOTのrevertはgit管理外ファイルのみか、当該テストエントリのみ手動削除で対処すべき


### L037: WSL2でWrite tool作成の.shファイルはCRLF混入が確実に発生する
- **日付**: 2026-02-25
- **出典**: cmd_311
- **記録者**: hayate
- auto_failure_lesson.sh作成時にもCRLF混入(L008)。Write tool経由の新規.shは100%CRLFになる前提でsed -i 's/\r$//'を即実行すべき


### L038: cmd_complete_gate.shテスト実行で本番lessonsにdraftが副作用で残る問題
- **日付**: 2026-02-25
- **出典**: cmd_311
- **記録者**: karo
- L035の実害事例。V2検証でcmd_311に対してgate実行した際、saizo未完了状態でauto-draftが本番lessonsに書き込まれた。検証時は必ずテスト用cmdを使用すべき。

### L039: [自動生成] 教訓参照を怠った: cmd_310
- **日付**: 2026-02-25
- **出典**: cmd_310
- **記録者**: gate_auto
- **status**: deprecated
- **deprecated_reason**: 教訓の意図(教訓事前確認)はdeploy_task.shのrelated_lessons自動注入で制度的に達成済み(cmd_1083精査)
- **if**: タスクに着手する時
- **then**: 関連教訓を事前に確認してから作業を開始せよ
- **because**: 教訓参照を怠ると過去の失敗を繰り返すリスクがあるため
- IF タスクに着手する時 THEN 関連教訓を事前に確認してから作業を開始せよ

### L040: WSL2環境でUsage API応答時間5秒超
- **日付**: 2026-02-25
- **出典**: cmd_314
- **記録者**: karo
- **if**: WSL2環境でUsage APIを呼び出す監視スクリプトを実装する時
- **then**: timeout設定を10秒以上に設定せよ
- **because**: WSL2→Anthropic API間のレイテンシでUsage APIの応答が常に5秒以上かかるため
- IF WSL2環境でUsage APIを呼び出す監視スクリプトを実装する時 THEN timeout設定を10秒以上に設定せよ

### L041: tmuxにペインレベル環境変数なし
- **日付**: 2026-02-25
- **出典**: cmd_314
- **記録者**: karo
- **if**: tmuxペインにエージェント固有の状態を保持させたい時
- **then**: @user_option(例: @agent_id)を使用せよ
- **because**: tmuxにはネイティブのペインレベル環境変数が存在せず、@user_optionはメタデータ用であり環境変数ではない
- IF tmuxペインにエージェント固有の状態を保持させたい時 THEN @user_option(例: @agent_id)を使用せよ

### L042: reports/上書き問題は統合タスク割当で実害発生
- **status**: confirmed
- **日付**: 2026-02-25
- **出典**: lesson_merge(L025+L027)
- **記録者**: karo
- **merged_from**: [L025, L027]
- 偵察→統合を同一忍者に割り当てるとreport初期化で偵察報告が消失。L024の実害パターン。回避策: 別忍者に分離 or reportアーカイブ実装

### L043: inbox_write.shのPython直接展開にコマンドインジェクション脆弱性
- **日付**: 2026-02-25
- **出典**: cmd_317
- **記録者**: tobisaru
- シェル変数($CONTENT/$TARGET)をPython文字列へ直接展開している。環境変数経由(os.environ)で渡す方式に修正すべき。TARGETも[a-z_]のみ許可バリデーション追加推奨

### L044: reports/*.yamlに扁平/ネスト2構造が混在
- **日付**: 2026-02-25
- **出典**: cmd_317
- **記録者**: karo
- 忍者名_report.yaml(ルートレベルフィールド)とsubtask_*.yaml(report:キー配下)で構造が異なる。スキーマ検証やパーサーは両方に対応が必要

### L045: AC達成状況フィールド名が3種混在
- **日付**: 2026-02-25
- **出典**: cmd_317
- **記録者**: karo
- **if**: 報告YAMLからAC達成状況を自動パースする時
- **then**: acceptance_criteria/ac_status/ac_checklistの3パターン全てに対応せよ
- **because**: reports内でフィールド名が3種混在しており、単一キー前提では取得漏れが発生するため
- IF 報告YAMLからAC達成状況を自動パースする時 THEN acceptance_criteria/ac_status/ac_checklistの3パターン全てに対応せよ

### L046: capture-paneバナー解析のfalse positive防止
- **日付**: 2026-02-25
- **出典**: cmd_320
- **記録者**: karo
- CLIバナーからモデル名を検出する際、コマンドテキスト自体にバナーパターンが含まれるfalse positiveに注意。grep+tail -1だけでなく、モデル名(Opus|Sonnet|Haiku)+バージョン番号まで含めた精密パターンが必要。

### L047: deploy_task.sh: Python -c文字列にシェル変数直接埋込はインジェクション危険
- **日付**: 2026-02-25
- **出典**: cmd_317
- **記録者**: tobisaru
- python3 -c内で$name等を直接補間すると、シングルクォートを含む入力でコード実行可能。環境変数経由(os.environ)か外部.pyファイル+引数渡しにせよ。R2全3モデルが独立して同一指摘(HIGH)

### L048: ninja_monitor auto-done誤判定: parent_cmdのみマッチではWave間で誤done。task_idチェック追加が必須
- **日付**: 2026-02-25
- **出典**: cmd_317v2
- **記録者**: karo
- check_and_update_done_taskがparent_cmdのみで判定していたためWave1報告doneがWave2タスクassignedを自動done化した。task_id一致チェックをL311後に追加して修正済み

### L049: コードレビューで既存対策を見落とす共通パターン — 全文精読とコメント確認の重要性
- **日付**: 2026-02-25
- **出典**: cmd_317v2
- **記録者**: kagemaru
- inbox_write.shの3件の独立レビューが全て同じ偽陽性(環境変数渡し済み+ホワイトリスト実装済み)を
報告した。コード中にHIGH-1/HIGH-2のコメントで明記されていたにもかかわらず見落とし。
コードレビュー時は (1)コメントも含めた全行精読 (2)既存の防御機構の確認 (3)推奨が既に実装されていないか検証 が必須。

### L050: コードレビューで既存対策を見落とす共通パターン — コメント含む全行精読が必須
- **日付**: 2026-02-25
- **出典**: cmd_317v2
- **記録者**: karo
- 3件の独立レビューが全て同じ偽陽性を報告。ただしTask3ではタイミング交絡あり(修正前コードレビュー→修正後コード検証)。純粋な見落としではない可能性

### L051: Sonnet 4.6はMUST/NEVER/ALWAYSをリテラルに従わず文脈判断でオーバーライドする。否定指示は肯定形+理由付き、絶対禁止は条件付きルーティング(IF X THEN Y)に変換すると遵守率向上。Pink Elephant研究で学術裏付け
- **日付**: 2026-02-25
- **記録者**: karo
- **tags**: [process]
- cmd_318 kagemaru

### L052: ninja_monitorのDESTRUCTIVE検出でcapture-pane履歴にsend-keysが残る誤検知あり。DESTRUCTIVE判定ログ(kill/rm等)はcapture-pane結果に他エージェントのsend-keys内容が混入する可能性を考慮すべき
- **日付**: 2026-02-25
- **記録者**: karo
- cmd_318 hayate

### L053: Claude 4.x CRITICAL/MUST/NEVERがovertriggering副作用
- **日付**: 2026-02-25
- **出典**: cmd_324
- **記録者**: karo
- **tags**: [process]
- Anthropic公式claude-4-best-practicesに明記。NEVER/MUSTはリテラル強制より文脈判断を優先し、ashigaru.mdのF001-F005は肯定形+理由付きに書き換えるとSonnet遵守率向上。L051の実証と一致

### L054: lesson_write.shのcontextロック失敗が非致命でSSOTとcontext不整合を許容
- **日付**: 2026-02-25
- **出典**: cmd_323
- **記録者**: karo
- context追記部のflock -w 10失敗時はWARNのみで終了し教訓登録は成功扱いになるが反映漏れが静かに残る。syncマーカー更新も同じflock内のためflock失敗時はマーカーも未更新となる

### L055: report YAML構造混在に対するフォールバック必須
- **日付**: 2026-02-25
- **出典**: cmd_337
- **記録者**: sasuke
- report YAMLは扁平/ネスト2系統+ACフィールド名5種混在(ac_results/ac_status/ac_checklist/acceptance_criteria/acceptance_criteria_check)。自動パーサは優先順位付きフォールバック必須。単一キー前提は破綻する

### L056: タスクYAML上書き問題: auto_deploy時の全サブタスク永続化
- **日付**: 2026-02-25
- **出典**: cmd_338
- **記録者**: hanzo
- queue/tasks/*.yamlは忍者名ファイル=上書き式のため完了タスク情報が消失する。auto_deploy機能を活用するには全サブタスクのYAMLを_subtask_*.yaml形式で事前作成し永続化する必要がある。task_idによるdedup処理で重複を吸収

### L057: cmd_338
- **日付**: 2026-02-26
- **出典**: check_and_update_done_task()はhandle_confirmed_idle()→is_task_deployed()内でのみ発火。忍者がidle確認後にしかauto-done判定されない。報告YAML→idle遷移まで最大20秒+CONFIRM_WAITのラグ存在。将来report YAML inotifywatchに移行すればラグ解消可能
- **記録者**: karo
- **if**: auto_deploy機能の発火タイミングを設計する時
- **then**: ninja_monitorのidle検知依存で最大25秒のラグが発生することを考慮せよ
- **because**: check_and_update_done_taskはhandle_confirmed_idle()内でのみ発火し、報告YAML作成からidle遷移まで最大20秒+CONFIRM_WAITのラグがあるため
- IF auto_deploy機能の発火タイミングを設計する時 THEN ninja_monitorのidle検知依存で最大25秒のラグが発生することを考慮せよ

### L058: WSL2の/mnt/c上でClaude CodeのWrite toolを使うと.shファイルにCRLF改行が混入する。bash -nで構文エラーになるため、新規.shファイル作成後は必ず sed -i 's/\r$//' で修正すること。
- **日付**: 2026-02-26
- **出典**: common.sh新規作成時にCRLF混入でbash -n失敗した実体験
- **記録者**: karo
- hayate(subtask_340_impl_a)

### L059: 共通スクリプトのリファクタ後はインタフェース契約の確認が必要。usage_status.shは引数なし統合出力設計だがusage_statusbar_loop.shが引数付き2回呼出しで重複表示バグ。呼出し側と被呼出し側のI/F整合を検証せよ。
- **日付**: 2026-02-26
- **出典**: usage_statusbar_loop.sh重複表示バグの修正体験
- **記録者**: karo
- **if**: 共通スクリプトのインタフェースをリファクタした後
- **then**: 全呼出し元のI/F整合(引数・出力形式)を検証せよ
- **because**: usage_status.shの引数なし統合設計に対しusage_statusbar_loop.shが引数付き2回呼出しで重複表示バグが発生した実例があるため
- IF 共通スクリプトのインタフェースをリファクタした後 THEN 全呼出し元のI/F整合(引数・出力形式)を検証せよ

### L060: タスクYAML/報告YAMLの上書き式がメトリクスデータ永続性を阻害
- **日付**: 2026-02-26
- **出典**: cmd_344
- **記録者**: karo
- **if**: 上書き式YAML(タスク/報告)でメトリクスデータを永続化したい時
- **then**: 追記ログ(lesson_tracking.tsv等)をcmd_complete_gate.shに追加して別経路で永続化せよ
- **because**: deploy_task.shがreport雛形を上書きし、タスクYAMLも忍者別1ファイルで上書きされるため、個別追跡データが消失する
- IF 上書き式YAML(タスク/報告)でメトリクスデータを永続化したい時 THEN 追記ログ(lesson_tracking.tsv等)をcmd_complete_gate.shに追加して別経路で永続化せよ

### L061: 統合設計レビューではソースコード実地確認が必須
- **日付**: 2026-02-26
- **出典**: cmd_344
- **記録者**: karo
- 3提案はそれぞれデータ構造を調査したが、cmd_complete_gate.shの実コード(1052行)を読んで初めて永続化追記の最適箇所(GATE判定直前)が判明した。提案段階の推定行番号(A:L297,C:L871)はいずれも不正確。統合レビューでは必ずソースコードの実地確認を行うべき。

### L062: YAMLフィールドのdict/str混在型はjoin前にstr()変換が必要
- **日付**: 2026-02-26
- **出典**: --tags
- **記録者**: pipeline,process
- **tags**: [yaml, parse, type-safety]
- **if**: YAMLフィールド(acceptance_criteria等)の要素をjoinする時
- **then**: 要素がdict型の場合があるため、str()変換のフォールバックを入れよ
- **because**: 報告YAMLのacceptance_criteriaがdict型の場合もstr型の場合もあり、型不一致でエラーになるため
- IF YAMLフィールド(acceptance_criteria等)の要素をjoinする時 THEN 要素がdict型の場合があるため、str()変換のフォールバックを入れよ

### L063: lessons.yamlはdict構造(lessons:キー配下リスト)。for lesson in dataはdictキーをイテレート→誤り。data['lessons']で取得せよ
- **日付**: 2026-02-26
- **出典**: cmd_351
- **記録者**: karo
- **tags**: [universal]
- 観点⑧のPythonコードが才蔵骨格実装時にdataを直接イテレーションしていた。lessons.yamlはトップレベルがdictでlessonsキー配下にリスト構造。for lesson in data.get('lessons',[])が正しい形

### L064: gitignore whitelist未登録は実行テストで検出不可
- **日付**: 2026-02-26
- **出典**: cmd_359
- **記録者**: kotaro
- **tags**: [review, process]
- knowledge_metrics.shはbash実行テストでは正常動作するが、whitelist方式.gitignoreでgit管理外になる。レビュー時にgit ls-files or git status --shortでgit管理状態を確認する手順が必須。L007+L009の複合パターン。

### L065: テンプレート定義とvalidation対象の一致確認義務
- **日付**: 2026-02-26
- **出典**: cmd_360
- **記録者**: hanzo
- **tags**: [testing]
- **if**: テンプレートを新規作成または変更する時
- **then**: (1)セクション名が実ファイルと完全一致するか (2)既存コードの依存セクションがテンプレートに含まれているか を検証せよ
- **because**: テンプレートと実態の不一致はvalidation WARN多発の原因になるため
- IF テンプレートを新規作成または変更する時 THEN (1)セクション名が実ファイルと完全一致するか (2)既存コードの依存セクションがテンプレートに含まれているか を検証せよ

### L066: reset_layout.shのような複数スクリプトを横断する機能では、依存APIのYAMLキー名を実データと突合せよ。settings.yamlのmodel_name vs get_agent_model()のmodelのようなキー不一致はdry-runでは正常終了するが実行結果が誤る
- **日付**: 2026-02-26
- **出典**: cmd_361
- **記録者**: karo
- **tags**: [api]
- integration,yaml-key-mismatch,dry-run-limitation

### L067: ペイン背景色は@model_name更新と連動していない(reset_layout.shのみで設定)
- **日付**: 2026-02-26
- **出典**: cmd_365
- **記録者**: hayate
- **tags**: [tmux, model-detection, background-color]
- **if**: ペイン背景色をモデル名と連動させたい時
- **then**: reset_layout.sh(起動時一括設定)でのみ背景色を設定する現行設計を理解した上で対処せよ
- **because**: ninja_monitor.shのcheck_model_names()は@model_nameのみ更新し背景色は更新しない設計のため
- IF ペイン背景色をモデル名と連動させたい時 THEN reset_layout.sh(起動時一括設定)でのみ背景色を設定する現行設計を理解した上で対処せよ

### L068: shutsujin_departure.shが2ファイル存在(root+scripts/)で背景色ロジック不整合
- **日付**: 2026-02-26
- **出典**: cmd_365
- **記録者**: kagemaru
- **tags**: [inconsistency, color-definition, dual-file]
- root版(フルデプロイ)は階級別静的PANE_BG_COLORS配列を使用し、reset_layout.shはモデル別動的_resolve_bg_color()を使用。cmd_361で導入したモデル別色がroot版に未反映。色定義の共通関数化が必要。

### L069: スキルがsystem-reminderに検出されるにはSKILL.mdにYAMLフロントマター(---/name/description/allowed-tools/---)が必須
- **日付**: 2026-02-26
- **出典**: cmd_368
- **記録者**: tobisaru
- **tags**: [skill-system, yaml-frontmatter, detection]
- shogun-param-neighbor-checkはMarkdown見出しのみでフロントマターなし→スキル検出システムに認識されず。他8スキルは全てフロントマター持ちで正常検出。

### L070: deploy_task.shはタスクYAMLの2スペースインデントを6箇所で固定仮定。YAML構造変更で沈黙死
- **日付**: 2026-02-26
- **出典**: cmd_370
- **記録者**: saizo
- **tags**: [yaml-key-mismatch, silent-fail, deploy]
- L171/172/666/901/942/943の6箇所がgrep '^  フィールド名:'で2sp固定。archive_completed.sh(cmd_369)と同根の問題。grep -E '^\s+フィールド名:'に統一せよ

### L071: SCRIPT_DIR設計パターンが2系統混在(リポルート基準 vs scripts/自身基準)で新規スクリプト作成時に混乱リスク
- **日付**: 2026-02-26
- **出典**: cmd_370
- **記録者**: kotaro
- **tags**: [inconsistency, script-pattern, onboarding-risk]
- 30+ファイルはSCRIPT_DIR=リポジトリルートだが7ファイル(shout,cmd_halt,health_check等)はscripts/自身基準でBASE_DIRで親に戻る方式。リポルート基準への統一推奨

### L072: git-ignoredスクリプトがwhitelist漏れで現役使用されるリスク — clone後に動作不全
- **日付**: 2026-02-26
- **出典**: cmd_368
- **記録者**: hayate
- **tags**: [git, whitelist, security, scripts]
- shout.sh(ninja FINAL step必須)とgate_mcp_access.sh(セキュリティhook)がwhitelist未登録。スクリプト作成直後にgit ls-files --error-unmatchで追跡確認せよ

### L073: タスク指示のパス相対指定は実ファイル位置で必ず検証せよ
- **日付**: 2026-02-26
- **出典**: path-resolution,task-instruction-verification,security-boundary
- **記録者**: cmd_371
- **tags**: [testing]
- cmd_371 C1のタスク指示は'lib/配下→..でリポルート'だったが、実際はscripts/lib/配下のため../..が必要。指示コードをそのまま使うとscripts/で止まりセキュリティ境界が誤動作する。realpathで実機確認が必須

### L074: bash ((var++))はvar=0時にset -eで即exit — $((var+1))を使え
- **日付**: 2026-02-26
- **出典**: bash,set-e,arithmetic,trap
- **記録者**: cmd_372
- **tags**: [universal]
- ((PASS++))はPASS=0の時に((0))を評価→exit code 1→set -eでスクリプト即終了。PASS=$((PASS+1))に変換必須。

### L075: L075
- **日付**: 2026-02-26
- **出典**: cmd_378
- **記録者**: sync_lessons.shのcontent.split('---')がL069本文中の---でファイルを切断し、74件中69件(93%)の教訓が消失。数週間検知されず。行頭のYAMLフロントマターのみ除去する意図なのに、ファイル全体の文字列分割を使ったため本文中の---にヒット。対策: lines_raw[i].strip()=='---'で行単位判定に修正。postcondition(入出力件数乖離チェック)があれば即座に検知できた
- **tags**: [silent-fail, string-processing, postcondition]
- **if**: ファイル内容を特定の区切り文字で分割パースする時
- **then**: content.split(delimiter)ではなくline-by-lineで処理せよ
- **because**: splitはファイル全体で分割するため行頭限定のデリミタを正しく扱えない
- IF ファイル内容を特定の区切り文字で分割パースする時 THEN content.split(delimiter)ではなくline-by-lineで処理せよ

### L076: deploy_task.sh旧Python -cブロックにL047違反が残存
- **日付**: 2026-02-27
- **出典**: cmd_384
- **記録者**: karo
- **tags**: [deploy]
- 新関数(inject_role_reminder/inject_report_template)はL047準拠(環境変数経由)だが、旧来のresolve_pane(L58-67)とcheck_context_freshness(L805-816)はshell変数を直接Python -cに補間。制御された値だが原則統一が望ましい。tags: [security, python-injection, technical-debt]

### L077: Vercel構造分離では全セクション移動先マッピングを事前作成せよ
- **日付**: 2026-02-27
- **出典**: cmd_383
- **記録者**: hanzo
- **tags**: [process]
- karo.md→operations.md分離でgenin/jonin詳細表、Status Transitions、停滞タイムアウト値等が除去されたがoperations.mdに未移動で消失。圧縮元の全セクションリスト化→移動先(圧縮/移動/削除)マッピング必須

### L078: GATE BLOCK率65%は構造問題(missing_gate)。家老フラグ生成タイミングが主因
- **日付**: 2026-02-27
- **出典**: cmd_386
- **記録者**: kagemaru,saizo
- **tags**: [review, gate]
- gate_metrics.log分析で329件のBLOCK理由を全件分類。65%(214件)がmissing_gate(archive/lesson/review_gate)=家老の処理順序とゲート実行タイミングの不一致。81-90%が5分以内解決で実害は限定的。改善策: preflight一括フラグ生成でBLOCK率20%台に削減可能

### L079: deploy_task.sh再配備でrelated_lessons.reviewedがfalseに戻る→入口門番BLOCK
- **日付**: 2026-02-27
- **出典**: cmd_387
- **記録者**: sasuke
- **tags**: [deploy, review, gate, bash, lesson]
- scripts/deploy_task.shのinject_related_lessons実行でrelated_lessons配列が再構築され、reviewed:trueが保持されない。結果として次回deploy_task.sh実行時にentrance_gateでBLOCKされる。

### L080: sync_lessons.sh新フィールド追加時はパース+キャッシュ保持の2箇所を更新必須
- **日付**: 2026-02-27
- **出典**: cmd_385
- **記録者**: kotaro
- **tags**: [review, yaml, lesson]
- SSOT→YAMLキャッシュ変換はscore系3フィールド(helpful_count/harmful_count/last_referenced)のみ保持。tags等の新フィールドを追加してもsync側で(1)SSOTパース(2)キャッシュ保持の2箇所を更新しなければsync時に消失する。subtask_385_review_aで実証


### L081: 追記型YAMLファイルのフォーマット変更時は既存データのマイグレーションも必須
- **日付**: 2026-02-27
- **出典**: cmd_388
- **記録者**: kagemaru
- **tags**: [yaml]
- ntfy_listener.shのYAML出力インデント変更(2sp→0sp)でスクリプトのみ修正し既存データの一括マイグレーションを怠った。旧/新フォーマット混在でYAMLパーサーエラー発生。追記型ファイルのフォーマット変更時はsed等で既存データも同時に統一すべき

### L082: Codexは~/.codex/を全エージェント共有。分離機構なし
- **日付**: 2026-02-27
- **出典**: cmd_390
- **記録者**: saizo
- **tags**: [db, tmux]
- CLAUDE_CONFIG_DIRのような分離機構がCodexにはない。history.jsonl・state_5.sqlite・sessions/が全Codexエージェント間で共有。session_id混在・SQLite競合のリスクあり。per-agentのCODEX_HOME設定が望ましい

### L083: bypass-approvals-and-sandboxフラグ漏れで全操作が権限確認停止
- **日付**: 2026-02-27
- **出典**: cmd_390
- **記録者**: saizo
- **tags**: [db, yaml]
- launch_cmdのSSOT管理(cli_profiles.yaml)が再発防止の要。CLI_ADAPTER_LOADED=falseのフォールバックパスや手動起動時にフラグ漏れると全操作で権限確認が発生しCodex下忍が停止する

### L084: roles/ashigaru_role.mdは現在不存在 — build_instructions.shがashigaru.md直接処理
- **日付**: 2026-02-27
- **出典**: cmd_392
- **記録者**: hayate
- **tags**: [frontend, lesson]
- L005は「ashigaru.mdの本文はroles/ashigaru_role.mdから取得」と言うが、2026-02-27時点でroles/ディレクトリ自体が存在しない。build_instructions.shがinstructions/ashigaru.mdを直接入力として処理している。L005は旧アーキテクチャの教訓であり更新が必要。

### L085: 報告YAML命名変更はCLAUDE.md自動ロード+common/ビルドパーツ+全スクリプトの横断更新が必須
- **日付**: 2026-02-27
- **出典**: cmd_392
- **記録者**: kotaro
- **tags**: [communication, gate, yaml, reporting]
- cmd_392はashigaru.md/karo.mdのみをAC3スコープとしたが、CLAUDE.md:20(全エージェント自動ロード)、instructions/common/(生成ファイルのビルド元)、cmd_complete_gate.sh(8箇所以上)が未更新のまま。命名規則変更はファイル名パターンの全文検索(grep '_report\.yaml')で影響範囲を完全列挙してからスコープを決定すべき。

### L086: auto_draft_lesson.shがlesson_write.shをCMD_ID空で呼ぶためlesson.done未生成
- **日付**: 2026-02-27
- **出典**: cmd_391
- **記録者**: hanzo
- **tags**: [gate, lesson, deploy]
- auto_draft_lesson.sh L151でlesson_write.shを呼ぶ際、6番目引数(CMD_ID)が空文字。lesson_write.shはCMD_IDが空だとlesson.doneフラグを生成しない(L339条件)。本preflight実装で補完しているが、根本的にはauto_draft_lesson.shにCMD_IDを伝搬する修正が望ましい。

### L087: 教訓効果メトリクスΔはBLOCKリトライ行膨張+構造BLOCK混入で歪む — cmd単位dedup+品質BLOCK分離が必須
- **日付**: 2026-02-27
- **出典**: cmd_397
- **記録者**: karo
- **tags**: [gate, lesson]
- knowledge_metrics.shのΔ計算は全TSV行を独立カウントするが(1)BLOCK→CLEARリトライが1cmdあたり最大5行に膨張し教訓あり群のBLOCK率を押し上げ(2)missing_gate(73%)は教訓効果と無関係の構造的タイミング問題。cmd dedup+構造BLOCK分離でΔ=-8.4pp→0.0ppに正規化される

### L088: deploy_task.shタグ推定パターンが広すぎて平均4.6タグ→フィルタリング無効化。lesson_tags.yamlの汎用語(環境,注入等)を除去しmax 3タグ制限が必要
- **日付**: 2026-02-27
- **出典**: cmd_397
- **記録者**: karo
- **tags**: [deploy, yaml, lesson]
- lesson_tags.yamlのdeployパターンに環境、lessonパターンに教訓等の汎用語が含まれ、ほぼ全タスクが多数タグにマッチ(最大15/22タグ)。推定タグ数上限(max 3)の導入が必要

### L089: universal教訓がdm-signalで30件(23%)に膨張し注入枠10件中5件を固定占有 — タスク固有教訓枠を圧迫して精度低下
- **日付**: 2026-02-27
- **出典**: cmd_397
- **記録者**: karo
- **tags**: [lesson]
- infra7件+dm-signal30件のuniversalが全デプロイに候補入り。10件上限中5件をuniversalが占有しタスク固有教訓枠は実質5件。universal基準の厳格化(helpful率80%以上かつ全タスクタイプに適用)で5件以下に削減が必要

### L090: build_instructions.sh派生ファイル(gitignore対象)はCLAUDE.md修正だけではgit diffに現れない
- **日付**: 2026-02-27
- **出典**: cmd_403
- **記録者**: hanzo
- **tags**: [frontend, testing, review, git]
- copilot-instructions.mdとsystem.mdはgitignoreで管理外。CLAUDE.md修正→commitしても派生ファイルは自動再生成されず、build_instructions.shの手動実行が必要。レビューACもgit diff外ファイルを検証対象に含めるべき

### L091: L085再発(派生ファイル未更新): CLAUDE.md変更時は全派生ファイルをACスコープに含めよ
- **日付**: 2026-02-27
- **出典**: cmd_403
- **記録者**: kagemaru
- **tags**: [git]
- CLAUDE.mdの変更が.github/copilot-instructions.mdとagents/default/system.mdに反映されなかった。CLAUDE.md更新タスクではgrep -riで全派生ファイルを事前列挙し、ACスコープに含めるべき

### L092: awk state machine複数エージェント属性パース時のリセット位置
- **日付**: 2026-02-27
- **出典**: cmd_404
- **記録者**: hanzo
- **tags**: [universal]
- get_model()のawkが各エージェント名行でat/am変数をリセットしていたため、ターゲットエージェント設定後に次エージェント行でリセットされた。BEGIN{at=;am=}で初期化しエージェント名行ではリセットしない方式が正。

### L093: impl忍者のgit add漏れ — 新規ファイル作成時のcommit忘れ
- **日付**: 2026-02-27
- **出典**: cmd_404
- **記録者**: kotaro
- **tags**: [git]
- 新規ファイル作成後にgit add+commitを実行せずuntrackedのまま残した。.gitignore whitelistはあったがuntrackedのまま。新規ファイル作成時はgit statusでtracked確認をACに含めるべき。

### L094: scripts/shutsujin_departure.sh(session設定)にモデル名ハードコード残存
- **日付**: 2026-02-27
- **出典**: cmd_405
- **記録者**: karo
- **tags**: [bash, monitor, tmux]
- rootのshutsujin_departure.shはcmd_405でSSOT化済みだが、scripts/shutsujin_departure.sh(セッション設定用)のsaizo pane変数(@model_name Sonnet)にハードコードが残る。ninja_monitorのcheck_model_names()が毎サイクル自動修正するため実害なし。ただし将来的にモデル変更時はscripts/shutsujin_departure.shも更新が必要。

### L095: archive_dashboard()のgrep戦果行パターン不一致 — AUTO移行後は常にno-op
- **日付**: 2026-02-27
- **出典**: cmd_406
- **記録者**: hanzo
- **tags**: [gate, reporting]
- **if**: archive_dashboard()のgrep戦果行パターン不一致 — AUTO移行後時
- **then**: archive_dashboard()のgrep '^\| [0-9]'は戦果行(| cmd_XXX |)にマッチしない
- **because**: gate_metrics.logから都度生成のためarchive不要
- IF archive_dashboard()のgrep戦果行パターン不一致 — AUTO移行後時 THEN archive_dashboard()のgrep '^\| [0-9]'は戦果行(| cmd_XXX |)にマッチしない

### L096: preflight_gate_flags()でlocal変数をif/else跨ぎで参照する場合、両ブロックのどちらが実行されても参照可能なスコープ（関数先頭等）で宣言・初期化すべき。bashのlocalは関数スコープだが、宣言がif内にあると実行されないelseブロックでは未初期化になる。
- **日付**: 2026-02-27
- **出典**: cmd_407
- **記録者**: karo
- **tags**: [gate, bash]
- bash,variable-scope,preflight

### L097: cmd_complete_gate.shのresolve_report_file()がgrep直書きでreport_filename取得 — L070除外対象外
- **日付**: 2026-02-27
- **出典**: cmd_410
- **記録者**: kotaro
- **tags**: [gate, bash, yaml, reporting]
- cmd_complete_gate.shはscripts/配下(scripts/gates/ではない)のため、L070(field_get義務)の除外対象外。現在grepで動作するが、YAML構造変更時にサイレント失敗の可能性あり。field_getへの移行を推奨。

### L098: L_archive_mixed_yaml
- **日付**: 2026-02-27
- **出典**: yaml,archive,parsing,resilience
- **記録者**: cmd_411
- **tags**: [yaml]
- **if**: 混在フォーマットのYAMLファイル(commands:ブロック+ベアリスト)をパースする時
- **then**: splitしてcommands:ブロックとベアリスト部分を別々にパースするフォールバックを用意せよ
- **because**: shogun_to_karo_done.yamlのような不正YAMLはyaml.safe_load()が失敗するため
- IF 混在フォーマットのYAMLファイル(commands:ブロック+ベアリスト)をパースする時 THEN splitしてcommands:ブロックとベアリスト部分を別々にパースするフォールバックを用意せよ

### L099: backfill対象ログファイルのフォーマット事前確認の重要性
- **日付**: 2026-02-27
- **出典**: cmd_413
- **記録者**: hayate
- **tags**: [gate_metrics, file_format, investigation]
- **if**: 既存ログファイルをbackfillする時
- **then**: 事前にログファイルのフォーマット(TSV/YAML/JSON等)を確認してからパーサーを実装せよ
- **because**: gate_metrics.logはYAMLではなくTSV形式(6列)であり、フォーマット誤認がパーサー設計を根本から狂わせるため
- IF 既存ログファイルをbackfillする時 THEN 事前にログファイルのフォーマット(TSV/YAML/JSON等)を確認してからパーサーを実装せよ
実際には「logs/gate_metrics.log」(TSV)。ファイル形式の事前確認でアプローチ変更を要した。

### L100: gate_metrics task_type遡及の最適データソース
- **日付**: 2026-02-27
- **出典**: cmd_413
- **記録者**: kagemaru
- **tags**: [gate_metrics, task_type, data_quality]
- **if**: gate_metricsにtask_typeを遡及付与する時
- **then**: deploy_task.logのsubtask IDパターン推定を使用せよ
- **because**: archive/cmdsキーワード推定は246cmdsにヒットするが複合タイプになりやすく精度が劣るため
- IF gate_metricsにtask_typeを遡及付与する時 THEN deploy_task.logのsubtask IDパターン推定を使用せよ

### L101: gate_metrics.logはTSV形式(YAMLではない)
- **日付**: 2026-02-27
- **出典**: cmd_413
- **記録者**: hayate
- **tags**: [gate, yaml]
- gate_metricsのデータはqueue/gate_metrics.yaml(YAML)ではなくlogs/gate_metrics.log(TSV 6列: timestamp/cmd_id/result/reason/task_type/model)に格納される。タスク記述の「gate_metrics.yaml」は実際のファイルと異なる。実装前にファイル形式を確認せよ。

### L102: lesson_tracking.tsvのデータソース相違 — タスク記述はqueue/gate_metrics.yamlだが実在はlogs/lesson_tracking.tsv
- **日付**: 2026-02-27
- **出典**: cmd_414
- **記録者**: saizo
- **tags**: [gate, yaml, lesson]
- タスク仕様で「queue/gate_metrics.yaml — 教訓参照履歴(lesson_referenced)」と指定されたが実際のファイルは存在せず、正しくはlogs/lesson_tracking.tsvが教訓参照情報を持つ。タスク仕様策定時のデータソース誤記。

### L103: skill.md(小文字)でスキル配置するとLinux native環境やCI等case-sensitive環境でClaude Codeがスキルを検出できない。WSL2はcase-insensitiveで動作するが移植性なし。SKILL.md(大文字)への統一が必要。該当: building-block-addition, fof-pipeline-troubleshooting
- **日付**: 2026-02-28
- **出典**: draft
- **記録者**: cmd_439
- **tags**: [frontend, pipeline, gate, wsl2]
- **if**: skill.md(小文字)でスキル配置時
- **then**: DM-signal側2スキルがskill.md小文字で配置
- **because**: case-sensitive環境で検出不可リスク
- IF skill.md(小文字)でスキル配置時 THEN DM-signal側2スキルがskill.md小文字で配置

### L104: 本家参照時のパス揺れ — tree確認後に取得を標準化
- **日付**: 2026-02-28
- **出典**: cmd_438 sasuke
- **記録者**: karo
- **tags**: [recon, process]
- **if**: OSSリポジトリや外部ソースからファイルを参照する時
- **then**: 先にtreeを取得して実パスを確定してから取得せよ
- **because**: パスが揺れるケースが多く、事前確認なしでは404や誤ファイル取得が発生するため
- IF OSSリポジトリや外部ソースからファイルを参照する時 THEN 先にtreeを取得して実パスを確定してから取得せよ

### L105: E2Eテストでtmux pane-base-index依存は明示固定せよ
- **日付**: 2026-02-28
- **出典**: cmd_438 kirimaru
- **記録者**: karo
- **tags**: [testing, bash, tmux]
- tests/helpers/setup.bashでpane-base-index未固定だとユーザーtmux設定が1始まりの環境でe2e_test:agents.0が存在せずセットアップ失敗。E2Eセッション作成直後にpane-base-index=0を設定して安定化した。

### L106: lesson_impact_analysis.shのload_lesson_summariesパス誤り
- **日付**: 2026-02-28
- **出典**: cmd_444
- **記録者**: kagemaru
- **tags**: [bash, lesson]
- L303: load_lesson_summaries(os.path.dirname(data_file))は
data_file=SCRIPT_DIR/logs/lesson_impact.tsvの場合にlogs/を渡す。
glob(os.path.join(root, "projects", ...))がlogs/projects/を探し
summaryが常にnot found。修正: 親ディレクトリを2段上げるか、
SCRIPT_DIRをbashから明示的に渡すべき。

### L107: dedupログ仕様は文言と0件時出力条件をAC文字列と厳密一致させる
- **日付**: 2026-02-28
- **出典**: cmd_446
- **記録者**: saizo
- **tags**: [universal]
- **if**: dedupログ仕様時
- **then**: ACにログ文言が含まれる場合、語順・語彙・プレフィックス空白も含めて一致確認が必要
- **because**: N>0条件付き出力にするとN=0要件を落としやすい
- IF dedupログ仕様時 THEN ACにログ文言が含まれる場合、語順・語彙・プレフィックス空白も含めて一致確認が必要

### L108: compact_stateの長さ未制限による500文字超過リスク
- **日付**: 2026-02-28
- **出典**: cmd_452
- **記録者**: tobisaru
- **tags**: [process]
- **if**: compact_stateにタスク状態を記録する時
- **then**: 長さ制限(例: 500文字)の追加を検討せよ
- **because**: 現運用では問題ないが、将来タスク増加時に制限なしだとsend-keysバッファを超過するリスクがあるため
- IF compact_stateにタスク状態を記録する時 THEN 長さ制限(例: 500文字)の追加を検討せよ

### L109: git commit時のstaging巻き込み防止
- **日付**: 2026-02-28
- **出典**: cmd_452
- **記録者**: tobisaru
- **tags**: [git]
- git addで対象ファイルのみ追加してもstaged済み他ファイルが巻き込まれる。git commit -- <file>で対象限定すべき。

### L110: settings.local.jsonはwhitelist外、並行レビューでcommit重複リスク
- **日付**: 2026-02-28
- **出典**: cmd_449
- **記録者**: hanzo
- **tags**: [review, git]
- **if**: settings.local.json時
- **then**: .claude/settings.local.jsonはgitignore whitelist未登録でpush対象に指定されてもgit addできない
- **because**: また並行hook配備で複数レビュアーが同一ファイルを先行commit+pushする重複が発生する
- IF settings.local.json時 THEN .claude/settings.local.jsonはgitignore whitelist未登録でpush対象に指定されてもgit addできない

### L111: ACにテストファイル実行が含まれる場合は実行前にファイル実在を確認せよ
- **日付**: 2026-03-01
- **出典**: cmd_460
- **記録者**: karo
- **tags**: [testing, preflight]
- **if**: ACにテストファイル実行が含まれる時
- **then**: 実行前にファイルの実在を確認し、不在なら停止して報告せよ
- **because**: 存在しないテストファイルを実行しようとするとエラーになり手戻りが発生するため
- IF ACにテストファイル実行が含まれる時 THEN 実行前にファイルの実在を確認し、不在なら停止して報告せよ

### L112: ninja_monitorのcheck_stall()がtask_idフィールドを参照するが現行タスクYAMLはsubtask_idのみ
- **日付**: 2026-03-01
- **出典**: cmd_462
- **記録者**: karo
- **tags**: [recon, yaml, monitor]
- check_stall()はtask_id(L835)を読むが、タスクYAMLにはsubtask_idしか存在しない。結果、2/26以降STALL-DETECTEDが0件になりSTALL検知が沈黙。task_id||subtask_idフォールバック実装が必要。cmd_462偵察で疾風+才蔵が独立発見。

### L113: タスク指定ファイルが.gitignore whitelist外だとcommit要件を満たせない
- **日付**: 2026-03-01
- **出典**: cmd_463
- **記録者**: sasuke
- **tags**: [testing, bash, git, tmux]
- **if**: タスク指定ファイルが.gitignore whitelist外の可能性がある時
- **then**: 配備時に対象ファイルのgit追跡可否を事前検証せよ
- **because**: whitelist外のファイルはcommitできずAC要件を満たせないため
- IF タスク指定ファイルが.gitignore whitelist外の可能性がある時 THEN 配備時に対象ファイルのgit追跡可否を事前検証せよ

### L114: safe_send_clear独自idle判定(tail -3)がCLIステータスバーで❯を見落とし永久CLEAR-BLOCKED。idle判定は必ずcheck_idle()に一本化せよ。同一判定の重複実装は片方が必ず腐る
- **日付**: 2026-03-01
- **出典**: ninja_monitor,idle_detection,safe_send_clear
- **記録者**: karo
- **tags**: [gate, monitor]
- cmd_464_hotfix

### L115: awkでYAMLのインデント階層別フィールド抽出時はインデント深さの正規表現条件を明示せよ
- **日付**: 2026-03-01
- **出典**: ninja_monitor,auto_archive
- **記録者**: shogun(hotfix)
- **tags**: [yaml, awk, parse]
- **if**: awkでYAMLのインデント階層ごとにフィールドを抽出する時
- **then**: インデント深さの正規表現条件を明示的に指定せよ。浅いパターン(`/^[[:space:]]*-/`等)は複数階層にマッチして誤抽出する
- **because**: check_auto_archive()でcmdレベル(2スペース)とACレベル(6スペース)を区別しなかったため毎サイクルエラーが発生した
- IF awkでYAMLのインデント階層ごとにフィールドを抽出する時 THEN インデント深さの正規表現条件を明示的に指定せよ。浅いパターンは複数階層にマッチして誤抽出する

### L116: .gitignore whitelist-basedリポジトリでは新規スクリプト作成時に必ずwhitelist追加が必要
- **日付**: 2026-03-01
- **出典**: cmd_466
- **記録者**: hanzo
- **tags**: [bash, git, lesson]
- scripts/lesson_effectiveness.shがgit addで拒否された。whitelist方式の.gitignoreでは新規ファイルは自動的に除外される。lesson L113と同根だが、テストファイル限定ではなく全ファイル共通の問題。

### L117: lesson_referenced→lessons_usefulリネーム時に全派生ファイル(generated/4本+roles/+templates/)を漏れなく更新する必要がある
- **日付**: 2026-03-01
- **出典**: cmd_466
- **記録者**: kagemaru
- **tags**: [deploy, communication, gate, yaml, lesson, reporting]
- フィールド名変更は本体(ashigaru.md)だけでなくgenerated/4ファイル、roles/ashigaru_role.md、templates/report_implement.yaml、cmd_complete_gate.sh内の全Python判定コード、deploy_task.sh報告テンプレート等の横断更新が必須。後方互換フォールバックも各箇所に必要。impl_bが全箇所カバーしていたため問題なし。

### L118: tmux set-optionのtargetがsession指定だとwindow optionが意図せずcurrent windowのみ更新されることがある
- **日付**: 2026-03-01
- **出典**: cmd_468
- **記録者**: sasuke
- **tags**: [tmux]
- **if**: tmux set-optionでwindow option(pane-border-format等)を設定する時
- **then**: window明示(-w -t shogun:main|agents)か専用適用スクリプト呼出しを使え
- **because**: session指定だと意図せずcurrent windowのみ更新され他windowに反映されないため
- IF tmux set-optionでwindow option(pane-border-format等)を設定する時 THEN window明示(-w -t shogun:main|agents)か専用適用スクリプト呼出しを使え

### L119: deploy_task.shのpostcondファイル経由でbash→Pythonのデータ受け渡しパターンが確立
- **日付**: 2026-03-01
- **出典**: cmd_470
- **記録者**: kagemaru
- **tags**: [deploy, bash, lesson]
- inline Python scriptの実行結果(注入ID一覧)をpostcondファイルに書き出し、bash側で読み取って後続処理(lesson_update_score.sh呼び出し)を実行するパターン。send-keys不要で安全。

### L120: report gateの存在判定はprefix検索+archive探索が必要
- **日付**: 2026-03-02
- **出典**: cmd_482
- **記録者**: kirimaru
- **tags**: [process, communication, gate, reporting]
- **if**: report gateで報告ファイルの存在判定を行う時
- **then**: prefix検索+archive探索を併用せよ
- **because**: 報告ファイル命名に日付suffixが付く運用では完全一致判定が高頻度で誤ブロックを起こすため
- IF report gateで報告ファイルの存在判定を行う時 THEN prefix検索+archive探索を併用せよ

### L121: YAML回転処理でヘッダ保持を欠くと後続appendが既存履歴を失う
- **日付**: 2026-03-02
- **出典**: cmd_490
- **記録者**: sasuke
- **tags**: [yaml]
- **if**: YAML回転処理(古いエントリの刈り込み)を実装する時
- **then**: echo headerで先にヘッダを書き出してからsed出力を>>追記せよ
- **because**: sedのみだとヘッダ行が消失し、後続のdict前提appendが再初期化してしまうため
- IF YAML回転処理(古いエントリの刈り込み)を実装する時 THEN echo headerで先にヘッダを書き出してからsed出力を>>追記せよ

### L122: SKILL.md手順追加時に原則セクションとの矛盾を確認せよ
- **日付**: 2026-03-02
- **出典**: cmd_490
- **記録者**: kagemaru
- **tags**: [process]
- **if**: SKILL.md手順追加時
- **then**: SKILL.md原則に所要時間やEdit不要等の制約記載がある場合、新Stepが制約に抵触しないか確認
- **because**: 抵触時は原則文言を更新すること
- IF SKILL.md手順追加時 THEN SKILL.md原則に所要時間やEdit不要等の制約記載がある場合、新Stepが制約に抵触しないか確認

### L123: tmuxターゲットにウィンドウINDEXを使用するな — NAME(固有名)を使え
- **日付**: 2026-03-02
- **出典**: cmd_494
- **記録者**: kagemaru+hanzo
- **tags**: [bash, tmux]
- **if**: tmuxのsend-keysやset-optionでターゲットを指定する時
- **then**: ウィンドウINDEXではなくNAME(例: shogun:main)を使え
- **because**: base-indexの設定差異に依存しないため安定性が高い
- IF tmuxのsend-keysやset-optionでターゲットを指定する時 THEN ウィンドウINDEXではなくNAME(例: shogun:main)を使え

### L124: paste-bufferの-dフラグはタイムアウト時に発動しない — 明示的delete-buffer必須
- **日付**: 2026-03-02
- **出典**: cmd_494
- **記録者**: kagemaru+hanzo
- **tags**: [tmux]
- **if**: paste-bufferの-dフラグはタイムアウト時
- **then**: timeout N tmux paste-buffer -b name -dでタイムアウトした場合、-d(使用後削除)は発動しない
- **because**: バッファが残留しtmux prefix+]で意図しないペインに貼付されるリスク
- IF paste-bufferの-dフラグはタイムアウト時 THEN timeout N tmux paste-buffer -b name -dでタイムアウトした場合、-d(使用後削除)は発動しない

### L125: paste-buffer注入先はagent_id検証で防御せよ(defense-in-depth)
- **日付**: 2026-03-02
- **出典**: cmd_494
- **記録者**: kagemaru
- **tags**: [testing, tmux]
- **if**: paste-bufferで特定ペインにデータを注入する時
- **then**: 注入先の@agent_idを検証してから実行せよ(defense-in-depth)
- **because**: tmuxのペイン解決が予期しない結果を返す可能性があり、誤注入を構造的に防止する必要があるため
- IF paste-bufferで特定ペインにデータを注入する時 THEN 注入先の@agent_idを検証してから実行せよ(defense-in-depth)

### L126: 非同期通知ラッパーをif判定に使うと成功誤判定が起きる
- **日付**: 2026-03-03
- **出典**: cmd_496
- **記録者**: hanzo
- **tags**: [universal]
- **if**: 非同期通知ラッパー(常時exit 0)の結果をif判定で使う時
- **then**: 同期モードまたは結果ファイル連携で結果を取得せよ
- **because**: ntfy.shのように常時exit 0の設計では、呼び出し側のif/elseでsend失敗を判定できないため
- IF 非同期通知ラッパー(常時exit 0)の結果をif判定で使う時 THEN 同期モードまたは結果ファイル連携で結果を取得せよ

### L127: 再配備前に先行commit/reportの存在を確認すべき
- **日付**: 2026-03-04
- **出典**: cmd_494
- **記録者**: karo
- **tags**: [git, reporting]
- cmd_494再配備時、先行忍者(tobisaru)が既にcommit+report提出済みだった。家老は再配備前にgit log + report存在を確認することで重複作業を防止できる。小太郎cmd_494r2で発見

### L128: OSS参照タスクはcanonical repository解決を初手に入れる
- **日付**: 2026-03-04
- **出典**: cmd_506
- **記録者**: sasuke
- **tags**: [api, recon]
- **if**: OSS参照タスク時
- **then**: task記載URLが移転/非公開化されている場合がある
- **because**: 404時はAPI検索とorg/repo再解決を先に行うことで調査停止を防げる
- IF OSS参照タスク時 THEN task記載URLが移転/非公開化されている場合がある

### L129: WSL2 Python3.12環境では外部feed偵察時にvenv未整備ケースがある
- **日付**: 2026-03-04
- **出典**: cmd_506
- **記録者**: kirimaru
- **tags**: [recon, process, wsl2]
- python3-venv未導入だとvenv構築不可。pip --userもPEP668で拒否されるため、偵察手順に --break-system-packages か事前venv確認を含めるべき。

### L130: Get-Clipboard -Format Imageは非画像時にnullを返す
- **日付**: 2026-03-04
- **出典**: cmd_508
- **記録者**: saizo
- **tags**: [bash]
- **if**: PowerShellのGet-Clipboard -Format Imageで画像を取得する時
- **then**: try/catchだけでなくnull判定も必須化せよ
- **because**: 非画像コンテンツ時にnullが返され、try/catchではキャッチできないエラーパターンがあるため
- IF PowerShellのGet-Clipboard -Format Imageで画像を取得する時 THEN try/catchだけでなくnull判定も必須化せよ

### L131: archive_completed.sh sweep modeはparent_cmd完了チェック必須
- **日付**: 2026-03-04
- **出典**: cmd_510
- **記録者**: hayate
- **tags**: [communication, reporting]
- sweep mode（引数なし）はstatus判定のみだと進行中cmdの報告を早期退避し得る。原則はcmd_id指定呼び出しとし、sweepにはparent_cmd status確認（未解決時keep）を必ず入れる。

### L132: dashboard_update.shは完了報告専用、進捗メモはEdit toolで記録すべき
- **日付**: 2026-03-04
- **出典**: cmd_511
- **記録者**: saizo
- **tags**: [communication, gate, reporting]
- **if**: dashboard_update.sh時
- **then**: 進捗メモ（配備開始等）にはEdit toolを使え
- **because**: 引数バリデーションが緩く誤用を検知できなかった
- IF dashboard_update.sh時 THEN 進捗メモ（配備開始等）にはEdit toolを使え

### L133: injection_countがlessons.yamlで全件0(未同期)
- **日付**: 2026-03-04
- **出典**: cmd_514
- **記録者**: tobisaru
- **tags**: [yaml, security, lesson]
- **if**: lessons.yamlのinjection_countを参照する時
- **then**: 全件0の可能性を考慮し、sync_lessons.shの同期状態を確認せよ
- **because**: injection_countフィールドは存在するが同期未実装の可能性があり信頼できないため
- IF lessons.yamlのinjection_countを参照する時 THEN 全件0の可能性を考慮し、sync_lessons.shの同期状態を確認せよ

### L134: NINJA_MONITOR_LIB_ONLYガードでbashスクリプトの関数テストが可能に
- **日付**: 2026-03-04
- **出典**: cmd_519
- **記録者**: kagemaru
- **tags**: [bash, monitor]
- **if**: bashスクリプトの関数をbatsでユニットテストする時
- **then**: LIB_ONLYガード(例: NINJA_MONITOR_LIB_ONLY)を使ってメインループを実行せず関数定義のみロードせよ
- **because**: return 0 2>/dev/null || exit 0パターンでsource時はreturn、直接実行時はexitを使い分けられるため
- IF bashスクリプトの関数をbatsでユニットテストする時 THEN LIB_ONLYガード(例: NINJA_MONITOR_LIB_ONLY)を使ってメインループを実行せず関数定義のみロードせよ

### L135: build_instructions.sh は --help 指定でも生成処理を実行する
- **日付**: 2026-03-04
- **出典**: cmd_523
- **記録者**: karo
- **tags**: [frontend, process]
- **if**: build_instructions.sh時
- **then**: 副作用のないヘルプ確認を想定すると生成差分が発生する
- **because**: 事前に実行意図を明確化し、必要時のみ実行する運用が安全
- IF build_instructions.sh時 THEN 副作用のないヘルプ確認を想定すると生成差分が発生する

### L136: preflight_gate_flags upgradeのhas_found_trueスコープ不整合でlesson_done_source BLOCKが頻発
- **日付**: 2026-03-04
- **出典**: cmd_529
- **記録者**: karo
- **tags**: [deploy, gate, lesson]
- **if**: preflight_gate_flagsのupgradeロジックを修正する時
- **then**: has_found_true変数のスコープがif/else両ブロックで有効か確認せよ
- **because**: スコープ不整合でlesson_done_source BLOCKが全忍者共通95件/245BLOCK(39%)発生した実績があるため
- IF preflight_gate_flagsのupgradeロジックを修正する時 THEN has_found_true変数のスコープがif/else両ブロックで有効か確認せよ

### L137: lesson_done先行生成とpreflight upgradeの設計的不整合
- **日付**: 2026-03-04
- **出典**: cmd_529
- **記録者**: hanzo
- **tags**: [deploy, gate, lesson]
- deploy_task.shがlesson.doneをlesson_checkで先行生成する設計は、cmd_complete_gate.shのpreflight upgradeが正常動作する前提。しかしupgradeロジックにhas_found_trueスコープバグがあり不発。先行生成とupgradeを独立に実装すると整合性が崩れるため、lesson.done生成責任を一箇所(preflight)に集約すべき

### L138: レビューcmdは要求範囲外差分をBLOCK対象として明示判定すべき
- **日付**: 2026-03-04
- **出典**: cmd_528
- **記録者**: hayate
- **tags**: [review, process, gate, git]
- taskが特定セクション改修を要求している場合、commit diffに無関係なgate条件変更が混在した時点でFAILとし、目的適合性違反として差し戻す運用が必要。

### L139: scope外変更のrevert確認では、正味diff(HEAD~N..HEAD)と個別commit diffの両方を突合すべき
- **日付**: 2026-03-04
- **出典**: cmd_528
- **記録者**: kotaro
- **tags**: [frontend, review, gate, git]
- **if**: scope外変更のrevert確認時
- **then**: 本件ではkirimaru impl(85c8a96)とsaizo revert(f4b264c)の正味diffで主要3点(ALWAYS_REQUIRED/preflight/GATE CLEAR後archive)の復元を確認
- **because**: 個別diffとの突合でupdate_status/append_changelogの残存scope外変更を検出した
- IF scope外変更のrevert確認時 THEN 本件ではkirimaru impl(85c8a96)とsaizo revert(f4b264c)の正味diffで主要3点(ALWAYS_REQUIRED/preflight/GATE CLEAR後archive)の復元を確認

### L140: レビューFAIL指摘時はrevert対象を明示し、scope内差分を保持した最小修正で再提出すべき
- **日付**: 2026-03-04
- **出典**: cmd_528
- **記録者**: saizo
- **tags**: [testing, review, process, gate, lesson]
- **if**: レビューFAILで再提出を指示する時
- **then**: revert対象を明示し、scope内差分を保持した最小修正で再提出させよ
- **because**: scope内変更とscope外変更が混在すると修正範囲が不明確になり手戻りが増大するため
- IF レビューFAILで再提出を指示する時 THEN revert対象を明示し、scope内差分を保持した最小修正で再提出させよ

### L141: lesson_deprecation_scan.shの自動退役はsubprocessで外部スクリプト呼出のため、大量教訓がある場合に遅くなる可能性
- **日付**: 2026-03-04
- **出典**: cmd_531
- **記録者**: hanzo
- **tags**: [process, lesson]
- **if**: lesson_deprecation_scan.shで大量教訓を自動退役する時
- **then**: 教訓数に応じてバッチ処理(1回のPython内で複数教訓を更新)への変更を検討せよ
- **because**: 現行のsubprocess個別呼出し方式は教訓数に比例して遅くなるため
- IF lesson_deprecation_scan.shで大量教訓を自動退役する時 THEN 教訓数に応じてバッチ処理(1回のPython内で複数教訓を更新)への変更を検討せよ

### L142: 飛猿報告のテスト8件はbatsテスト2件のみ — テスト件数根拠明示義務
- **日付**: 2026-03-04
- **出典**: cmd_532
- **記録者**: kagemaru
- **tags**: [deploy, testing, communication, reporting]
- **if**: 飛猿報告のテスト8件時
- **then**: テスト件数を報告する場合は根拠(ファイル名・実行コマンド)も記載すべき
- **because**: ad-hocテストを含めた件数と推測されるが、報告での件数根拠が不明確
- IF 飛猿報告のテスト8件時 THEN テスト件数を報告する場合は根拠(ファイル名・実行コマンド)も記載すべき

### L143: gitignoreエラーはgateログに記録されず暗数化する — 15日間で最低11件、モデル非依存
- **日付**: 2026-03-04
- **出典**: cmd_534
- **記録者**: karo
- **tags**: [gate, git]
- **if**: gitignoreエラー時
- **then**: 対策は(1)ashigaru.md明文化(即効)→(2)pre-commitフック(根治)の段階実施が有効
- **because**: 忍者のgit addエラー(gitignore対象の誤addやwhitelist未登録)はgate_metrics.logに記録されない
- IF gitignoreエラー時 THEN 対策は(1)ashigaru.md明文化(即効)→(2)pre-commitフック(根治)の段階実施が有効

### L144: git add失敗の頻度分析にはgate_metricsではなく専用guardログが必要
- **日付**: 2026-03-04
- **出典**: cmd_534
- **記録者**: hayate
- **tags**: [recon, gate, git]
- **if**: git add/gitignore失敗の頻度を分析する時
- **then**: gate_metricsではなく専用guardログから集計せよ
- **because**: gate_metrics.logはゲート判定理由のみを保持し、git add/gitignore失敗は記録されないため
- IF git add/gitignore失敗の頻度を分析する時 THEN gate_metricsではなく専用guardログから集計せよ
発生頻度を継続観測するには、git add実行点でignored pathを記録する
git_add_safe.sh + guardログ化を先に実装すべき。

### L145: ashigaru.md生成はbuild_instructions.shで行われる→source filesを修正すべき(L005の実践確認)
- **日付**: 2026-03-04
- **出典**: cmd_533
- **記録者**: hanzo
- **tags**: [frontend, yaml]
- **if**: ashigaru.mdの内容を修正する時
- **then**: build_instructions.shのソースファイル(roles/,templates/等)を修正せよ
- **because**: instructions/ashigaru.mdはYAML front matterのみがbuild_instructions.shで使用され、本文は生成物であるため
- IF ashigaru.mdの内容を修正する時 THEN build_instructions.shのソースファイル(roles/,templates/等)を修正せよ
body contentはinstructions/roles/ashigaru_role.md + instructions/common/*.mdから構築。
生成ファイルを直接編集すると次回buildで上書きされる。
L005を適用し、source files修正→build実行→全生成ファイルに自動反映の流れで実装した。

### L146: AC6系レビューは実配備YAML確認だけでなく一時環境での再現実行を必須にすべき
- **日付**: 2026-03-04
- **出典**: cmd_533
- **記録者**: saizo
- **tags**: [deploy, review, process, yaml, git, lesson]
- **if**: AC6系(教訓注入関連)をレビューする時
- **then**: git diff確認に加え、summary-only lessonを使ったdeploy_task再現実行を実施せよ
- **because**: 差分確認だけでは誤判定余地が残り、実動作検証が再発防止に有効であるため
- IF AC6系(教訓注入関連)をレビューする時 THEN git diff確認に加え、summary-only lessonを使ったdeploy_task再現実行を実施せよ

### L147: related_lessons.detail注入はlessons.yamlスキーマ依存 — 現行スキーマではAC6未達
- **日付**: 2026-03-04
- **出典**: cmd_533
- **記録者**: sasuke
- **tags**: [deploy, yaml, lesson]
- **if**: related_lessons.detail注入はlessons.yamlスキーマ依存 — 現行スキーマ時
- **then**: AC6を成立させるには(1) lessons.yamlへdetail同期追加、または(2)summaryをdetailへフォールバック注入する実装が必要
- **because**: 結果として生成task YAMLへdetailが入らない
- IF related_lessons.detail注入はlessons.yamlスキーマ依存 — 現行スキーマ時 THEN AC6を成立させるには(1) lessons.yamlへdetail同期追加、または(2)summaryをdetailへフォールバック注入する実装が必要

### L148: AC文言は値参照元変更以外(例: コメント追記)の許容範囲を明示すると判定ブレを防げる
- **日付**: 2026-03-04
- **出典**: cmd_532
- **記録者**: sasuke
- **tags**: [review]
- **if**: AC文言は値参照元変更以外(例: コメント追記)の許容範囲を明示時
- **then**: 今回の差分にはtimestamp行コメント追記が含まれるが、機能要件への影響はない
- **because**: レビューACを『機能差分の主目的』と『非機能注記』に分離すると、レビュー担当間でPASS/FAIL判定の一貫性が上がる
- IF AC文言は値参照元変更以外(例: コメント追記)の許容範囲を明示時 THEN 今回の差分にはtimestamp行コメント追記が含まれるが、機能要件への影響はない

### L149: shellスクリプトでrgを使うな、grepを使え
- **日付**: 2026-03-04
- **出典**: cmd_537
- **記録者**: kagemaru
- **tags**: [bash, git]
- **if**: shellスクリプトやgit hookでテキスト検索を行う時
- **then**: rgではなく標準のgrepを使え
- **because**: ポータブルなスクリプトではrg/ripgrepの存在が保証されず、|| trueパターンもエラー握りつぶしリスクがあるため
- IF shellスクリプトやgit hookでテキスト検索を行う時 THEN rgではなく標準のgrepを使え

### L150: git commit --dry-runではpre-commitが走らずAC誤判定になる
- **日付**: 2026-03-04
- **出典**: cmd_537
- **記録者**: sasuke
- **tags**: [testing, git]
- **if**: commit関連のACを検証する時
- **then**: git commit --dry-runではなく実commit(失敗想定)またはhook直接実行で検証せよ
- **because**: dry-runではpre-commitフックが走らず、フック起因の問題を検出できないため
- IF commit関連のACを検証する時 THEN git commit --dry-runではなく実commit(失敗想定)またはhook直接実行で検証せよ

### L151: Git hook導入時はスクリプト内容だけでなく executable bit(100755) のコミット有無を必須確認
- **日付**: 2026-03-04
- **出典**: cmd_537
- **記録者**: hayate
- **tags**: [review, git]
- **if**: Git hookをリポジトリに導入する時
- **then**: スクリプト内容だけでなくexecutable bit(100755)のコミット有無を必ず確認せよ
- **because**: 実行権限がないとhookが無視されるが、エラーなく静かに失敗するため見落としやすい
- IF Git hookをリポジトリに導入する時 THEN スクリプト内容だけでなくexecutable bit(100755)のコミット有無を必ず確認せよ

### L152: KM_JSON_CACHEの無効化条件にlessons.yaml変更が含まれない
- **日付**: 2026-03-04
- **出典**: cmd_541
- **記録者**: kotaro
- **tags**: [gate, yaml, lesson, reporting]
- **if**: lessons.yamlを更新した後にdashboard_auto_section.shの出力を確認する時
- **then**: KM_JSON_CACHEの無効化条件にlessons.yaml変更検知を追加すべき
- **because**: 現行のキャッシュ無効化はgate_metrics.logの行数変化のみで判定しており、lessons.yaml変更が反映されるまでラグがあるため
- IF lessons.yamlを更新した後にdashboard_auto_section.shの出力を確認する時 THEN KM_JSON_CACHEの無効化条件にlessons.yaml変更検知を追加すべき

### L153: レビューACにpush条件がある場合は事前に ahead/behind を確認する
- **日付**: 2026-03-04
- **出典**: cmd_546
- **記録者**: kirimaru
- **tags**: [review, git]
- **if**: レビューACにpush条件がある時
- **then**: git rev-list --left-right --countでorigin/mainとの差分を事前確認せよ
- **because**: レビュー対象外コミットが混在するとpush時に予期しない差分が含まれるため
- IF レビューACにpush条件がある時 THEN git rev-list --left-right --countでorigin/mainとの差分を事前確認せよ

### L154: [自動生成] 有効教訓の記録を怠った: cmd_546
- **日付**: 2026-03-04
- **出典**: cmd_546
- **記録者**: gate_auto
- **status**: deprecated
- **deprecated_reason**: 報告フォーマット問題(nested YAML)による誤検知。実際にはL074/L081を記録済み
- **tags**: [communication, lesson, reporting]
- lessons_usefulが空のサブタスクが1件。役立った教訓IDを報告に記載してから完了せよ

### L155: lib/配下の共通関数は呼出し元の環境変数依存を明示バリデーションすべき
- **日付**: 2026-03-04
- **出典**: cmd_546
- **記録者**: kagemaru
- **tags**: [inbox]
- **if**: lib/配下の共通関数を実装する時
- **then**: 呼出し元の環境変数依存を関数冒頭で明示バリデーションせよ
- **because**: sourceされるライブラリは実行時に環境変数が設定されている保証がないため
- IF lib/配下の共通関数を実装する時 THEN 呼出し元の環境変数依存を関数冒頭で明示バリデーションせよ

### L156: set -e環境で共通関数の非0戻り値を直接受けると即時終了する
- **日付**: 2026-03-04
- **出典**: cmd_545
- **記録者**: sasuke
- **tags**: [universal]
- **if**: set -e環境で非0戻り値を返す判定関数を呼び出す時
- **then**: `if func; then rc=0; else rc=$?; fi` 形式で受けよ
- **because**: `func; rc=$?`形式ではset -eにより即exitしてしまうため
- IF set -e環境で非0戻り値を返す判定関数を呼び出す時 THEN `if func; then rc=0; else rc=$?; fi` 形式で受けよ

### L157: 追記型YAMLの上限制御はappend直後に同一トランザクションで実施すべき
- **日付**: 2026-03-04
- **出典**: cmd_547
- **記録者**: hayate
- **tags**: [yaml]
- **if**: 追記型YAMLの上限制御時
- **then**: append処理とローテーションを分離すると肥大化区間が残る
- **because**: flock配下の単一Pythonトランザクション内で entries.append→entries[-MAX_ENTRIES:] を連結すると、既存超過データも初回実行で即収束できる
- IF 追記型YAMLの上限制御時 THEN append処理とローテーションを分離すると肥大化区間が残る

### L158: ローテーション機能レビューでは境界値テストに加えて過剰初期データの実地検証が有効
- **日付**: 2026-03-04
- **出典**: cmd_547
- **記録者**: sasuke
- **tags**: [testing, review]
- **if**: ローテーション機能をレビューする時
- **then**: 境界値テストに加え、200超の初期データ(例:250件)を用いた追記検証を実施せよ
- **because**: 上限超過状態での追記動作を実地検証しないとAC2の実効性を担保できないため
- IF ローテーション機能をレビューする時 THEN 境界値テストに加え、200超の初期データ(例:250件)を用いた追記検証を実施せよ

### L159: 大規模偵察タスクの並列Agent活用パターン
- **日付**: 2026-03-05
- **出典**: cmd_548
- **記録者**: kagemaru
- **tags**: [recon]
- **if**: 5軸以上の独立した偵察を実施する時
- **then**: 並列Agent(例: 4並列)で各軸を分担して同時実行せよ
- **because**: 逐次実行より大幅に短縮でき、全調査を約12分で完了できるため
- IF 5軸以上の独立した偵察を実施する時 THEN 並列Agent(例: 4並列)で各軸を分担して同時実行せよ
軸ごとの独立性が高い偵察タスクではExplore Agentの並列起動が有効。
ただしAgent間のタイムアウト差が大きい(73秒〜695秒)ため、
最も時間のかかるAgentがボトルネックになる。
対策: 重い軸(AC3=ファイル行数カウント+構造分析)は先行起動すべき。

### L160: ntfy添付DLはAUTH_ARGS再利用でprivate topicでも同一認証経路を維持できる
- **日付**: 2026-03-05
- **出典**: cmd_551
- **記録者**: sasuke
- **tags**: [security, inbox, oauth]
- **if**: ntfyのprivate topicから添付ファイルをダウンロードする時
- **then**: ストリーム購読時に組み立てたAUTH_ARGSを添付ファイルcurlにも共通適用せよ
- **because**: 認証経路が異なると『メッセージは読めるが添付は403』の不整合が発生するため
- IF ntfyのprivate topicから添付ファイルをダウンロードする時 THEN ストリーム購読時に組み立てたAUTH_ARGSを添付ファイルcurlにも共通適用せよ

### L161: 画像添付MIME整合改善の必要性
- **日付**: 2026-03-05
- **記録者**: auto_draft
- **tags**: [review, process]
- **if**: ntfy添付画像を保存する時
- **then**: attachment MIMEに合わせた拡張子付与またはPNG変換を標準化せよ
- **because**: 拡張子固定(常に.png)は可読性要件を満たしていても、実際のMIMEと不整合でレビュー往復が増えるため
- IF ntfy添付画像を保存する時 THEN attachment MIMEに合わせた拡張子付与またはPNG変換を標準化せよ

### L162: フックスクリプトテストではsymlink構造でSCRIPT_DIRリダイレクトするモック手法が有効
- **日付**: 2026-03-05
- **出典**: testing
- **記録者**: cmd_558
- **tags**: [bash, yaml]
- **if**: フックスクリプトテスト時
- **then**: dirname($0)からパス計算するスクリプトは環境変数上書きでは対応不能
- **because**: symlink構造でSCRIPT_DIRをテスト用ディレクトリに向ける
- IF フックスクリプトテスト時 THEN dirname($0)からパス計算するスクリプトは環境変数上書きでは対応不能

### L163: MAX_ENTRIES等の定数変更時は既存テストの前提値も同時更新が必要
- **日付**: 2026-03-05
- **出典**: testing
- **記録者**: cmd_558
- **tags**: [universal]
- **if**: MAX_ENTRIES等の定数変更時
- **then**: impl側の定数変更とテストの前提値の整合性チェックをACに含めるべき
- **because**: cmd_558でMAX_ENTRIES 200→300変更時に既存テストT-LC-008/009の修正が追加発生
- IF MAX_ENTRIES等の定数変更時 THEN impl側の定数変更とテストの前提値の整合性チェックをACに含めるべき

### L164: Claude Code Hooksのshスクリプトはset -euのみ使用しpipefail禁止
- **日付**: 2026-03-05
- **出典**: hooks
- **記録者**: cmd_558
- **tags**: [bash]
- **if**: Claude Code Hooksのshスクリプトを作成する時
- **then**: set -euのみ使用しpipefailは使うな
- **because**: hookはsh経由で実行されるためpipefailはbash専用オプションであり構文エラーになる
- IF Claude Code Hooksのshスクリプトを作成する時 THEN set -euのみ使用しpipefailは使うな

### L165: 教訓効果率は『未解決負債』だけでなく『仕組み化後の未退役』でも低下する
- **日付**: 2026-03-05
- **出典**: cmd_567
- **記録者**: kirimaru
- **tags**: [universal]
- **if**: 教訓効果率の低い教訓群を分析する時
- **then**: 自動退役は『低効果』だけでなく『仕組み化完了フラグ』連動で回すべき
- **because**: 効果率0%群には、価値が低い教訓だけでなく、既にコード化され人間参照が不要になった教訓が混在するため
- IF 教訓効果率の低い教訓群を分析する時 THEN 自動退役は『低効果』だけでなく『仕組み化完了フラグ』連動で回すべき

### L166: ストリーミング受信デーモンは起動側pkillに依存せず、受信側でも単一起動ロックを持つべし
- **日付**: 2026-03-05
- **出典**: cmd_571
- **記録者**: karo
- **tags**: [universal]
- **if**: ストリーミング受信デーモンを新規実装する時
- **then**: 受信側にもflock/pidfileによる単一起動ロックを持たせよ
- **because**: 起動経路が複数ある場合、起動側のpkill/nohupだけでは多重起動を完全に防げないため
- IF ストリーミング受信デーモンを新規実装する時 THEN 受信側にもflock/pidfileによる単一起動ロックを持たせよ

### L167: ストリーム購読系デーモンは singleton lock + message idempotency を必須セットで実装すべき
- **日付**: 2026-03-05
- **出典**: cmd_571
- **記録者**: kirimaru
- **tags**: [process]
- **if**: ストリーム購読系デーモン時
- **then**: ntfy_listenerで多重起動防止(lock/pidfile)とMSG_ID重複排除が無いと、運用上の二重起動や再接続再配送で同一イベントを二重記録する
- **because**: 購読デーモンは両方を初期実装に含めるべき
- IF ストリーム購読系デーモン時 THEN ntfy_listenerで多重起動防止(lock/pidfile)とMSG_ID重複排除が無いと、運用上の二重起動や再接続再配送で同一イベントを二重記録する

### L168: auto_draft_lesson.shのIF-THEN引数にスペース含む値を渡すと切り詰められる
- **日付**: 2026-03-05
- **出典**: cmd_575
- **記録者**: tobisaru
- **tags**: [lesson]
- **if**: auto_draft_lesson.shからlesson_write.shにIF/THEN/BECAUSE値を渡す時
- **then**: IF_THEN_FLAGSの文字列結合ではなく、個別にquotedした引数として渡す
- **because**: unquoted展開でword
- IF auto_draft_lesson.shからlesson_write.shにIF/THEN/BECAUSE値を渡す時 THEN IF_THEN_FLAGSの文字列結合ではなく、個別にquotedした引数として渡す

### L169: YAMLへの追記をheredoc直書きすると引用符/改行で構造破壊する
- **日付**: 2026-03-05
- **出典**: cmd_578
- **記録者**: hayate
- **tags**: [communication, bash, yaml, inbox]
- scripts/ntfy_listener.sh の ntfy_inbox追記(173-178)は本文を未エスケープで埋め込むため、"を含むログでYAMLが壊れる。append系は flock + parse + dump の原子トランザクションに統一すべし。

### L170: terminalログ保存でバイト切り詰め(head -c)を使うとUTF-8破損が混入する
- **日付**: 2026-03-05
- **出典**: cmd_578
- **記録者**: saizo
- **tags**: [api, bash, yaml]
- `scripts/log_terminal_response.sh` の `head -c 500` が多バイト文字を途中切断し、`queue/lord_conversation.yaml` に `\udce2\udc94` の壊れた文字列を発生させた。文字数切り詰めはPython等でコードポイント単位に実施すべき。

### L171: Python呼出しパイプパターンexit code喪失 + bash→Python変数受渡しos.environ統一
- **日付**: 2026-03-06
- **出典**: cmd_585
- **記録者**: tobisaru
- **tags**: [deploy, bash]
- deploy_task.shのPython呼出し(2>&1|while)でexit code喪失。bash変数直接埋込はインジェクションリスク。os.environ[]パターン統一必須

### L172: レビューでは『履歴位置確認』を先に行うと push 可否の誤判定を防げる
- **日付**: 2026-03-06
- **出典**: cmd_590
- **記録者**: kirimaru
- **tags**: [review, git]
- git status の一時表示だけで ahead/behind を判断せず、`git branch -vv` と `git rev-parse HEAD origin/main` で追跡先一致を確認すると、不要な push ブロックや scope 誤認を避けられる。

### L173: build_instructions.sh再生成時はCLAUDE.md正本も同期→AGENTS系の旧表記残存を防止
- **日付**: 2026-03-06
- **出典**: cmd_604
- **記録者**: hayate
- **tags**: [frontend, git, reporting]
- **if**: build_instructions.shで
- **then**: instructions配下だけでなく
- **because**: AGENTS.md
- instructions/common/roles を修正して build_instructions.sh を実行しても、AGENTS.md / .github/copilot-instructions.md / agents/default/system.md の reports パスは CLAUDE.md を正本として再生成される。今回も CLAUDE.md の files.reports を更新するまで旧命名が残存したため、instruction系の命名変更時は CLAUDE.md も同時修正してから再生成する必要がある。

### L174: cmd_608
- **日付**: 2026-03-06
- **出典**: ストリーム購読デーモンのwatchdogがkeepalive/open行のread成功でも活動時刻を更新していたため、ntfyのkeepalive(45秒間隔)が流れ続けるとwatchdogが永遠延命され、実メッセージ停滞を30分で検知する設計が無効化された。LAST_STREAM_ACTIVITYとLAST_MESSAGE_ACTIVITYを分離し、message処理成功時のみ後者を更新すべき。2名独立一致
- **記録者**: karo
- **tags**: [universal]
- watchdogの活動時刻は『read成功』ではなく『意味のあるイベント処理成功』で更新すべし

### L175: ストリームwatchdogが任意の受信バイトで更新されるとkeepaliveで実メッセージ断を見逃す
- **日付**: 2026-03-06
- **出典**: cmd_608
- **記録者**: kirimaru
- **tags**: [api, bash, monitor, inbox]
- `scripts/ntfy_listener.sh:317-319` が `read` 成功直後にLAST_STREAM_ACTIVITYを更新し、`190-192` でkeepalive/openを破棄していた。ntfy購読APIは keepalive/open 行を流すため、watchdogは『無メッセージ』を検知できない。ストリーム監視とメッセージ監視のタイマーは分離すべき。

### L176: watchdogの活動時刻は『read成功』ではなく『意味のあるイベント処理成功』で更新すべし
- **日付**: 2026-03-06
- **出典**: cmd_608
- **記録者**: sasuke
- **tags**: [inbox]
- ストリーム購読デーモンで keepalive/open/outbound を同じ activity と見なすと、watchdog が『接続生存』しか測れず『実メッセージ停滞』を検知できない。byte-level と message-level の活動時刻を分離するか、少なくとも更新点をフィルタ後へ置くべき。

### L177: 追跡ログのキーをproducer/consumerで変える時は両側同時に整合させよ
- **日付**: 2026-03-06
- **出典**: cmd_611
- **記録者**: karo
- **tags**: [recon, monitor]
- IF 追跡TSVやqueueの識別子をparent_cmdからtask_id/subtask_idへ変更する時 THEN 書き込み側だけでなく集計・更新・分析のconsumer全部で同じキー体系へ同期せよ because producer/consumerの識別子不一致は静かにpending残留を生み、監視が遅れて壊れるため

### L178: Claude Codeドキュメントのホスト移行（docs.anthropic.com→code.claude.com）
- **日付**: 2026-03-07
- **出典**: cmd_630
- **記録者**: kotaro
- **tags**: [recon]
- Agent Teamsの公式ドキュメントURLが docs.anthropic.com/en/docs/claude-code/ から code.claude.com/docs/en/ に301リダイレクト。今後の偵察ではcode.claude.comを直接使用すべき

### L179: 忍者がcommit未実施でdone報告するケース
- **日付**: 2026-03-08
- **出典**: cmd_648
- **記録者**: kagemaru
- **tags**: [review, communication, yaml, git, reporting]
- 疾風がstatus: doneの報告YAMLを提出したが、git commitが未実施だった。レビュー担当がcommit+pushを代行した。impl忍者がcommitまで完了してから報告すべき。

### L180: whitelist型.gitignore配下では新規ファイルのstage前にgit check-ignoreを確認する
- **日付**: 2026-03-08
- **出典**: cmd_649
- **記録者**: saizo
- **tags**: [bash, git]
- IF whitelist-based .gitignore のrepoで新規source fileや対象scriptを追加する時 THEN git add前に git ls-files と git check-ignore -v で追跡可否を確認せよ because task達成後にignored pathだとcommitへ入らず、force-addや方針判断が終盤で発生するため

### L181: タスク記述と実際のgit状態の乖離確認
- **日付**: 2026-03-08
- **出典**: cmd_652
- **記録者**: kotaro
- **tags**: [git]
- タスク記述ではAC4実装済み・AC1-3未実装とあったが、実際はAC1-3がcommit済み・AC4のみ未commit。着手前にgit diffで実態を確認することで無駄な作業を回避できた

### L182: 設定UIで保存した値が実行経路で読まれているか別経路まで確認せよ
- **日付**: 2026-03-08
- **出典**: cmd_658
- **記録者**: kirimaru
- **tags**: [frontend]
- 今回のAndroidアプリは SettingsViewModel/NtfySettingsSection で ntfy topic を保存できる一方、実処理の NtfyService は Defaults.NTFY_TOPIC 固定値を参照していた。設定項目の有無だけで『カスタマイズ可能』と判断すると誤る。保存経路と実使用経路の両方を確認すべき。

### L183: bashrc export検証は対話シェル前提を確認せよ
- **日付**: 2026-03-08
- **出典**: cmd_664
- **記録者**: saizo
- **tags**: [testing, review, bash]
- Ubuntu既定の `~/.bashrc` は先頭で `case $-` により非対話シェルを即 return する。環境変数追加レビューで `bash -lc 'source ~/.bashrc'` だけを見ると false negative になるため、行番号確認か `bash -ic` での実測を併用すべき。

### L184: set -u配下で任意引数を追加するbash関数は既存呼び出し互換を守れ
- **日付**: 2026-03-08
- **出典**: cmd_667
- **記録者**: hayate
- **tags**: [testing, bash]
- `download_attachment_image()` に第2引数を追加した際、旧テストが1引数呼び出しのままで
`local attachment_name="$2"` が unbound variable で即死した。
`set -u` を使うbash関数で任意引数を増やす時は `${2:-}` のように後方互換を残し、
既存unit testを先に流して破壊的シグネチャ変更を検知すべき。

### L185: report_path 注入だけで報告テンプレート未生成→忍者が手動補完
- **日付**: 2026-03-09
- **出典**: cmd_675
- **記録者**: hayate
- **tags**: [deploy, communication, yaml, reporting]
- `cmd_675` 配備後の `queue/tasks/hayate.yaml` には `report_path: queue/reports/hayate_report_cmd_675.yaml` が入っていたが、実ファイルは存在しなかった。deploy_task の report template 実体生成経路を確認すべき。

### L186: 共有mainへのreview push前は remote確認だけでなく local HEAD再確認も直前に行え
- **日付**: 2026-03-09
- **出典**: cmd_675
- **記録者**: sasuke
- **tags**: [review, git]
- IF review taskで `git push origin main` を行う時 THEN `git ls-remote origin refs/heads/main` だけでなく push直前に `git rev-parse HEAD` / `git log -1 --oneline` で local HEAD も再確認せよ because 並行作業中は別忍者の commit が数十秒で main へ積まれ、意図しない別cmdを同時pushするため

### L187: Compose の zoom 下限は viewport 配下の onTextLayout 幅から計算するな
- **日付**: 2026-03-09
- **出典**: cmd_689
- **記録者**: sasuke
- **tags**: [universal]
- IF Compose で terminal の pinch-zoom `minScale` を `contentWidth` から算出する時 THEN `Text.onTextLayout` の viewport 制約済み幅ではなく `TextMeasurer` などの非制約測定を使え BECAUSE viewport 幅に丸められると `minScale=1.0` に固定され、実機で desktop view へ入れなくなる。

### L188: impl忍者のcommit未実施(L179再発)
- **日付**: 2026-03-09
- **出典**: cmd_702
- **記録者**: hanzo
- **tags**: [review, communication, git, reporting]
- 影丸がstatus:doneの報告を提出したがgit commitが未実施。レビュー担当(半蔵)がcommit+pushを代行した。

### L189: 並列impl配備時は全忍者のcommit完了を確認してからreview配備せよ
- **日付**: 2026-03-09
- **出典**: cmd_707
- **記録者**: hanzo
- **tags**: [testing, review, git]
- cmd_707で3名並列impl後review時、才蔵のみcommit済み・小太郎と影丸が未コミット。review配備前に家老がgit statusで未コミット差分確認するか完了ゲートにcommit検証追加すべき。

### L190: 並列impl配備時は全忍者のcommit完了を確認してからreview配備せよ。cmd_707で3名並列impl後review時、才蔵のみcommit済み・小太郎と影丸が未コミット。review配備前にgit statusで未コミット差分を確認すべき
- **日付**: 2026-03-09
- **出典**: cmd_707
- **記録者**: karo
- **tags**: [review, git]
- cmd_707で3名並列impl後review時、才蔵のみcommit済み・小太郎と影丸が未コミット。review配備前にgit status確認すべき

### L191: E2E fixture参照は tests/e2e/fixtures 実在確認をCIで壊れやすい前提として先に検証すべき
- **日付**: 2026-03-10
- **出典**: cmd_714
- **記録者**: hayate
- **tags**: [testing, yaml]
- IF E2E test が `cp "$PROJECT_ROOT/tests/e2e/fixtures/..."` のように fixture ファイルを前提にする時 THEN fixture 実在をテスト開始前に明示検証するか self-contained 化せよ BECAUSE run `22865773824` では `task_sasuke_basic.yaml` 不在で 5 件が同時多発FAILし、本来の挙動確認まで到達できなかった。

### L192: review配備前にcommit完了とgenerated派生物差分を分離確認せよ
- **日付**: 2026-03-10
- **出典**: karo
- **記録者**: cmd_715
- **tags**: [testing, review, git]
- 並列implのreviewではgit diff origin/main..HEADだけでなくgit diff --name-statusも確認し、対象差分が全てcommit済みか先に検証せよ。generated fileの大規模削除が混入するとreviewとCI確認の前提が崩れるため、派生物は再生成後の差分有無まで切り分けてからreview配備すべき。

### L193: pre-push制約時間の主要因はアプリ本体ではなくテストハーネスの固定待ちと初期化重複になりやすい
- **日付**: 2026-03-10
- **出典**: cmd_715
- **記録者**: hayate
- **tags**: [frontend, testing, yaml, git]
- IF pre-push で `timeout 30 bats tests/unit/ --jobs 4` のような厳しい予算を課す時 THEN 実装コードより先に unit test 側の固定sleep・過大timeout・setup重複を疑って削れ BECAUSE 今回は hook実装後も suite が32秒台で落ち、`test_build_system` の再ビルド、`test_cli_adapter` のYAML再生成、`test_ntfy_ack` の15秒timeout などを削って 30.0秒台まで短縮できたため。

### L194: pre-push timeout 40s→120s延長(WSL2)
- **日付**: 2026-03-10
- **出典**: cmd_721
- **記録者**: karo
- **tags**: [git, wsl2]
- テスト252件がWSL2 I/Oオーバーヘッドで40秒を超過(46件しか完走不可)。120秒に延長で解決。テスト数増加時は定期的にtimeout見直しが必要

### L195: UIコントラスト・アクセシビリティ基準
- **日付**: 2026-03-10
- **出典**: cmd_730
- **記録者**: kagemaru
- **tags**: [ui-design]
- **if**: UI要素・テキストの色やコントラストを決める時
- **then**: UI要素は3:1以上、小テキストは4.5:1以上、大テキストは3:1以上のコントラスト比を確保。色のみで情報伝達せず下線等の補助指標を併用。純黒#000禁止→ダークグレー使用
- **because**: WCAG 2.1 AAアクセシビリティ基準。色覚多様性への対応。純黒は画面上でハーシュに見える
- UI要素コントラスト比3:1以上(WCAG 2.1 AA)。テキストコントラスト比: 小文字4.5:1以上、大文字3:1以上(18px以下)。色だけに頼らず下線・アイコン等の追加視覚指標を併用。純粋な黒(#000)テキスト禁止→ダークグレー使用

### L196: UIスペーシング・レイアウト基準
- **日付**: 2026-03-10
- **出典**: cmd_730
- **記録者**: kagemaru
- **tags**: [ui-design]
- **if**: UIのスペーシング・レイアウトを設計する時
- **then**: 8pt刻み(8/16/24/32/48)でスペーシング統一。関連要素はスペースでグルーピング。不要なBox枠は削除。アライメントは左揃え統一。border-radiusは全要素で統一値を使用
- **because**: 一貫した8ptグリッドは視覚的リズムを生む。無駄なコンテナはノイズ。アライメント統一は可読性向上
- スペーシングは8pt刻みのTシャツサイズ(XS=8/S=16/M=24/L=32/XL=48)。スペースで関連要素をグルーピング。不要なコンテナ(Box枠)を削除。アライメントは左揃えで統一。border-radiusを全要素で統一

### L197: UIタイポグラフィ基準
- **日付**: 2026-03-10
- **出典**: cmd_730
- **記録者**: kagemaru
- **tags**: [ui-design]
- **if**: UIのフォント・テキストスタイルを決める時
- **then**: サンセリフ1種で統一(Inter推奨)。ウェイトはRegular+Boldのみ。UPPERCASE多用禁止。左揃え。行間1.5以上。見出しのletter-spacingは狭める
- **because**: Light/Thinは可読性低下。複数フォントは視覚ノイズ。行間1.5未満は読みにくい。大見出しはデフォルトのletter-spacingが広すぎて間延びする
- サンセリフ体1種類で統一(x-heightの高いフォント推奨、Inter等)。フォントウェイトはRegular+Boldのみ(Light/Thin禁止)。大文字(UPPERCASE)の多用禁止。テキストは左揃え。本文の行間は最低1.5(150%)。大きな見出しのletter-spacingは狭める

### L198: UIボタン・インタラクション基準
- **日付**: 2026-03-10
- **出典**: cmd_730
- **記録者**: kagemaru
- **tags**: [ui-design]
- **if**: ボタンやインタラクティブ要素を配置する時
- **then**: プライマリボタンは画面に1つ。filled/outlined/text-onlyの3階層。タッチターゲット48pt以上、間隔8pt以上。重要アクションは表面に。ナビアイコンにはテキストラベル必須
- **because**: 複数のプライマリボタンはユーザーの判断を阻害。48ptはモバイルタッチの最小快適サイズ。ラベルなしアイコンは認知負荷が高い
- プライマリボタンは画面に1つだけ。ボタン階層: filled(主)→outlined(副)→text-only(補助)の3段階。最小タッチターゲット48pt×48pt、要素間の最小間隔8pt。重要なアクションはメニューに隠さず表面に出す。ナビアイコンにはテキストラベルを必ず付ける

### L199: UIビジュアルヒエラルキー・一貫性基準
- **日付**: 2026-03-10
- **出典**: cmd_730
- **記録者**: kagemaru
- **tags**: [ui-design]
- **if**: UIコンポーネントの外観・装飾を決める時
- **then**: Squint Testで構造確認。アイコンスタイル統一(2ptストローク/角丸)。似た外観=同じ機能。不要な装飾削除。ブランドカラーはインタラクティブ要素のみ。アイコンとテキストの視覚的重みを揃える
- **because**: 視覚ヒエラルキーが不明確だとユーザーは何を見るべきか迷う。装飾は情報伝達を阻害。ブランドカラーの乱用はクリック可能要素の識別を困難にする
- 明確な視覚ヒエラルキー(Squint Test: 目を細めても構造がわかるか)。一貫性を保つ(アイコンスタイル統一/2ptストローク/角丸)。見た目が似ている要素は同じ機能にする。不要な装飾を削除。色は目的を持って使う(ブランドカラーはインタラクティブ要素のみ)。アイコンとテキストの視覚的重み(色の濃さ)を揃える

### L200: 殿のUI好み: 無地背景・チップ形式・デザインガイド参照
- **日付**: 2026-03-10
- **出典**: cmd_730
- **記録者**: kagemaru
- **tags**: [ui-design]
- **if**: UIデザインの方向性を決める時・フォルダ選択UIを実装する時
- **then**: 背景は無地ソリッドカラー。フォルダ/カテゴリ選択はチップ形式。Androidはandroid/.interface-design/system.md参照必須。DM-signalはcontext/dm-signal-frontend.md §6参照
- **because**: 殿の好み: 画像背景はノイズ、チップ形式は視認性と操作性が最良。デザインガイド参照で一貫性を保証
- シンプルな無地背景推奨(背景画像よりソリッドカラー)。フォルダ/カテゴリ選択にはチップ(chip/tag)形式がベスト。Androidアプリのデザインシステムはandroid/.interface-design/system.mdを必ず参照。DM-signalのデザイントークンはcontext/dm-signal-frontend.md §6参照

### L201: MCP Memory APIにはobservation単位のメタデータ(tag/priority)がなく、マーカーは本文埋込が唯一の実用策
- **日付**: 2026-03-10
- **出典**: cmd_732
- **記録者**: kotaro
- **tags**: [communication, process]
- **if**: MCP
- **then**: observation本文の先頭にマーカー（例:
- **because**: MCP
- MCP Memory API(memory MCP server)のobservationは単なるstring[]で、個別observationへのtag/priority/timestamp等の構造化メタデータ付与は不可能。フィルタリングにはsearch_nodesの全文検索しか使えないため、[share:ninja]等のプレフィックスマーカーを本文に埋め込む方式が唯一の実用策。別entity方式はobservation更新時にマッピングが壊れるリスクあり。

### L202: Compose で固定テーマ定数が広く直参照されている時は Material colorScheme 追加だけでは多テーマ化できない
- **日付**: 2026-03-10
- **出典**: cmd_729
- **記録者**: kirimaru
- **tags**: [frontend]
- 今回の Android UI は `Kinpaku` / `Zouge` / `Surface4` などの戦国色トークンを多画面で直接参照していたため、`lightColorScheme` を足すだけでは Light/Black へ切り替わらなかった。既存 UI を大規模書換えせず多テーマ化するには、静的定数を `CompositionLocal` 経由の動的パレットへ昇格させ、既存トークン名のまま mode-aware にする方が安全。

### L203: xAI x_searchはResponses API+grok-4ファミリー限定
- **日付**: 2026-03-10
- **出典**: cmd_738
- **記録者**: auto_draft
- **tags**: [api]
- xAI APIのlive search(search_parameters)はchat/completionsで廃止(HTTP 410)。x_searchツールはResponses API(/v1/responses)でのみ利用可能。さらにx_searchはgrok-4ファミリーのみ対応(grok-3系は400エラー)

### L204: STALL誤判定の実態は「idle+status未更新」が主因。pstree方式で予防的防御層追加が有効
- **日付**: 2026-03-11
- **出典**: cmd_777
- **記録者**: hanzo
- **tags**: [recon, bash, yaml, wsl2, monitor]
- 30日分134件のSTALL-DETECTEDログを分析した結果、ほぼ全件が「ペインが確実にidle状態なのにtask YAML statusが未更新」パターン。当初想定されたBash長時間実行中の誤判定はログ上では確認できなかった。ただしpstreeによるサブプロセス検知（WSL2動作確認済み）を予防的防御層として追加することで、将来のfalse positive防止と検知精度向上が見込める。

### L205: Codex pane の @agent_state=idle を busy 判定の truth source にしてはならぬ
- **日付**: 2026-03-11
- **出典**: cmd_777
- **記録者**: kirimaru
- **tags**: [bash, monitor, tmux]
- 2026-03-11 14:32 JST 実測で `kirimaru` pane は `@agent_state=idle` のまま `• Working (... esc to interrupt)` を表示した。`ninja_monitor.sh` が idle を短絡採用すると長時間 Bash/active work を false idle と誤判定する。idle state は必ず capture-pane または pstree 等の第二証跡と突合せるべし。

### L206: CC BY 4.0はOSS利用で最も柔軟なライセンスの一つ
- **日付**: 2026-03-11
- **出典**: cmd_798
- **記録者**: kotaro
- **tags**: [api, frontend]
- NDL OCR-LiteのCC BY 4.0は帰属表示のみで商用利用・改変・再配布すべて可能。ShareAlike制約なし。依存ライブラリも全て商用利用可(MIT/Apache2/BSD)。GUIのflet依存問題はCLI/API利用で完全回避可能。公開1ヶ月で873スター、Issue対応1-3日と非常にアクティブ。長期的に使えるツールになる可能性高い。

### L207: field_getはYAML block scalar指示子をリテラル文字列で返す
- **日付**: 2026-03-11
- **出典**: cmd_795
- **記録者**: hanzo
- **tags**: [gate, yaml]
- summary: | のようなblock scalar指示子は、field_get(grep+sed方式)では | がリテラル文字列として返る。YAML parserを使わないためブロック内容は取得できない。空判定にはこのリテラル値のcase文マッチが必要。

### L208: テスト#158ライブtmux環境依存FAILの修正要
- **日付**: 2026-03-11
- **出典**: cmd_799
- **記録者**: hanzo
- **tags**: [testing, gate, tmux]
- test_gate_metrics_model_labels.batsのテスト#158がライブtmuxセッションの@model_nameを取得し、テストフィクスチャの期待値と不一致になる。テスト内でtmuxルックアップをモックするか、環境非依存にすべき

### L209: done通知は inbox_write 直送を禁止し、報告ファイル検証付きラッパに一本化する
- **日付**: 2026-03-12
- **出典**: cmd_812
- **記録者**: hayate
- **tags**: [testing, process, communication, inbox, reporting]
- 運用ドキュメントに旧 `inbox_write.sh ... report_received` 手順が残っていると、忍者は report file 未作成でも task を done 化できる。done 通知は `ninja_done.sh` のような検証付きラッパに一本化し、inbox_write 側の auto-done hook は残さない。

### L210: done通知を transport 層で信用すると report file 欠損の虚偽完了が通る
- **日付**: 2026-03-12
- **出典**: cmd_812
- **記録者**: sasuke
- **tags**: [deploy, testing, process, communication, yaml, inbox, reporting]
- IF 忍者の done 通知を `inbox_write.sh` の message type だけで信用して task=done に進める THEN `ninja_done.sh` を迂回した虚偽完了で report YAML 欠損が本番運用に漏れる BECAUSE transport 層は report file existence/summary を検証していない

### L211: 大規模偵察(8名以上)には統合専任担当(水平H)をcmd設計段階で組み込むべき
- **日付**: 2026-03-12
- **出典**: cmd_862
- **記録者**: tobisaru
- **tags**: [recon, process]
- A-G各忍者は自担当範囲の辞書を高品質に作れるが、エントリ間の重複・矛盾・gap検出は不可能。統合専任が全報告を横断的に読み完全知識マップを作成して初めて実装可能な形になる

### L212: 一次データ不可侵原則: 外部知識(論文/API仕様/書籍等)は原典のまま保存し、自軍の解釈・適用は別セクション/別ファイルに分離する。改変は捏造。全PJ共通適用
- **日付**: 2026-03-12
- **記録者**: karo
- **tags**: [api]
- IF: 外部知識を記録・引用する時 THEN: 一次データ層と解釈・適用層を分離せよ BECAUSE: 一次データの改変は捏造であり、知識の信頼性が失われる

### L213: サブエージェントは「読み取り専用の一時ツール」に限定せよ — capability制約(Read+Grep+Glob/plan mode/haiku/maxTurns 4)+behavior制約(判定禁止/所見のみ)の分離設計が必須
- **日付**: 2026-03-13
- **出典**: cmd_873
- **記録者**: saizo+kotaro+tobisaru+hayate
- **tags**: [recon, gate, reporting]
- cmd_873の4観点偵察統合結論。実装許可すると教訓サイクル・GATEシステム・report追跡の3重迂回が発生しF003の根拠が崩壊する。capability(tools/mode/isolation)で強制可能な制約とbehavior(prompt/hook)でしか縛れない制約を分離し、まずcapabilityを最小化する設計順序が必須。起動条件は5ファイル以上横断のrecon前段Read onlyに限定し、shadow replayからの段階的拡大で導入する

### L214: ローカルIDを複数PJで再利用する系ではメトリクスキーを(project,id)にせよ
- **日付**: 2026-03-13
- **出典**: cmd_874
- **記録者**: sasuke
- **tags**: [universal]
- 教訓IDをproject非考慮で集計すると注入回数・有効率・退役判定が別PJ間で相互污染する。cmd_874で検出:同一IDの20組が両PJで同一退役理由。file_missing判定もinfra root基準固定で外部PJパスを誤判定。自動淘汰ロジックでは特に致命的

### L215: IF gate_metricsテストを書く THEN tmuxモックを配置してライブ環境からの干渉を防げ BECAUSE resolve_agent_model_labelはtmux変数を優先し、settings.yamlのフォールバックがテストされない
- **日付**: 2026-03-13
- **出典**: cmd_875
- **記録者**: karo
- **tags**: [gate, yaml, tmux]
- gate_metricsテストがtmux環境依存

### L216: gate_metricsテストがtmux環境依存
- **日付**: 2026-03-13
- **出典**: cmd_875
- **記録者**: kotaro
- **tags**: [gate, yaml, tmux]
- IF gate_metricsテストを書く THEN tmuxモックを配置してライブ環境からの干渉を防げ BECAUSE resolve_agent_model_labelはtmux変数を優先し、settings.yamlのフォールバックがテストされない

### L217: lesson_impact.tsvのPENDING行を淘汰・同期カウントへ入れるな
- **日付**: 2026-03-13
- **出典**: cmd_878
- **記録者**: karo
- **tags**: [yaml, security, lesson]
- IF lesson_impact.tsvを injection/helpful集計に使う THEN result=PENDINGを除外しproject列で分離せよ BECAUSE 未完了サブタスクが注入回数だけ増え、誤退役とlessons.yaml汚染を起こす

### L218: .gitignoreホワイトリスト未追加はレビューでも検出必須
- **日付**: 2026-03-13
- **出典**: cmd_876
- **記録者**: karo
- **tags**: [review, git]
- L007教訓が再び的中。新規スクリプト(chronicle_metrics.sh)の実装者が.gitignoreホワイトリスト追加を忘れていた。レビュー担当がL007を把握していたため検出・修正できた。実装者・レビュー者双方がL007を確認するフローが有効。

### L219: 偵察タスクの履歴参照パスは実在パスで配るべし
- **日付**: 2026-03-13
- **出典**: cmd_887
- **記録者**: hayate
- **tags**: [recon, yaml]
- cmd_887_B の分析対象に archive/completed_changelog.yaml とあったが、現行実体は queue/completed_changelog.yaml だった。履歴参照タスクは stale path のまま出すと、初動で探索コストが発生する。

### L220: bulk commit AC4 は queue/禁止hook と live-generated tracked files を考慮して定義せよ
- **日付**: 2026-03-13
- **出典**: cmd_904
- **記録者**: auto_draft
- **tags**: [process, git]
- .githooks/pre-commit が queue/ stage を全面禁止する一方、context/lord-conversation-index.md は作業中に自動更新される。bulk commit task で git status clean を AC に置く場合は、runtime tracked files を除外するか commit/push 対象から切り離さないと実運用で達成不能になる。

### L221: WSL2上の/mnt/c/配下ファイルはWindows改行(CRLF)を含むことがある
- **日付**: 2026-03-13
- **出典**: cmd_911
- **記録者**: karo
- **tags**: [wsl2, tmux]
- ~/.claude/skills/*/SKILL.mdがCRLFを含み、awkのregex ^---$ が ---\rにマッチしなかった。tr -d '\r'でCR除去してからパースする必要がある。

### L222: deploy_task.sh既定値補完: empty sentinelテスト必須
- **日付**: 2026-03-14
- **出典**: cmd_926
- **記録者**: karo
- **tags**: [deploy, yaml]
- IF deploy_task.shが未設定/空文字/空リストを既定値へ補完する仕様を持つ THEN テストはmissing/Noneだけでなく空文字と空リストのsentinelも再現せよ BECAUSE 現行実装はnot in/Noneしか見ておらず、実タスクYAMLに残る空配列を取り逃して9PASSの偽陰性が起きた

### L223: gstackのwrapError+checklist分離+Named Invariantsパターン
- **日付**: 2026-03-14
- **出典**: cmd_931
- **記録者**: karo
- **tags**: [recon, process, gate, inbox]
- IF gate/スクリプトのエラー出力を設計する THEN 「次にやるべきこと」を含むAI行動指示形式にせよ。チェックリストは外部md分離(Read失敗→STOP)。長手順は短名原則にパック化(Named Invariants) BECAUSE gstackの全コードベースでエラーメッセージの受信者=AIエージェント前提で設計されており、エージェントの自律判断精度が向上する(cmd_931深掘り偵察)

### L224: MCP obsに運用ルールと殿の好みを混在させると陳腐化が加速する
- **日付**: 2026-03-15
- **出典**: cmd_957
- **記録者**: saizo
- **tags**: [process]
- 53obsの突合でMCPに混在していた重複・旧版化項目の多くが本来context/instructionsに置くべき運用ルールだった。MCPは殿の好み/哲学を中心に残し、運用ルールは受動層に昇格させる三分法(好み/運用/裁定)で棚卸しすると漂流を抑えやすい。

### L225: MCP棚卸しではentity/project境界の混入を先に検査すべし
- **日付**: 2026-03-15
- **出典**: cmd_957
- **記録者**: karo
- **tags**: [universal]
- dm_signal_decisions名義にauto-ops/確定申告の裁定が混入していた(cmd_957)。正本突合を速く正確にするには内容種別だけでなく『このobsは当該entity/projectの知識か』を最初に切り分ける必要がある。

### L226: Codexモデルは/clear Recovery時に849行→9行圧縮でアイデンティティを失う
- **日付**: 2026-03-16
- **記録者**: karo
- **tags**: [gate]
- ashigaru.md読込スキップ(コスト削減)で忍者は8行のアイデンティティブロック+1行role_reminderだけでペルソナ再構築が必要。対策: /clear Recoveryに核心5項目追加(+10行)+role_reminder拡充+Summary Generation強化。cmd_974影丸発見。

### L227: WSL2のWrite toolはCRLF改行を生成する
- **日付**: 2026-03-16
- **出典**: cmd_970
- **記録者**: kotaro
- **tags**: [bash, wsl2]
- Write toolで作成した.shファイルがCRLF改行になり、bash実行時にset -euが失敗する。WSL2(/mnt/c/)でスクリプト作成後はsed -i 's/\r$//' で変換が必要。

### L228: ast-grepのregex ruleはkind併記が要る
- **日付**: 2026-03-16
- **出典**: cmd_973
- **記録者**: kirimaru
- **tags**: [frontend]
- ast-grep rule を regex ベースで書く場合、kind を伴わない composite rule は `Rule must specify a set of AST kinds to match` で parse error になる。frontend rule は import_statement/export_statement/call_expression + regex に分解すると安定した。

### L229: Stop Hookで全テスト実行は既存GATEと重複し有害
- **status**: confirmed
- **日付**: 2026-03-16
- **出典**: cmd_972（殿直接指摘で撤去）
- **記録者**: shogun
- **tags**: [infra, universal]
- cmd_969〜972でHarness Engineering記事の手法を取り込んだ際、Stop Hookで全batsテスト(299件)をフル実行するゲートを追加した。結果: (1)22分ハングで全エージェントが停止不能 (2)将軍・家老も巻き込まれた (3)既存のcmd_complete_gate.shと完全に重複。**外部記事の推奨を取り込む前に「既存インフラで同じことをやっていないか」を確認せよ。** PostToolUse Hook（即時フィードバック）はGATEシステムと層が違うので有用だが、Stop Hook（完了時チェック）はGATEと同じ層であり重複する。stop_hook_inbox.sh（inbox未読チェック+report欠如チェック）も同様に既存GATEと重複するため未接続のまま削除。
- **if**: 外部記事・ベストプラクティスからHook/ゲートを新規導入する場合
- **then**: 既存のGATEシステム（cmd_complete_gate.sh）との重複チェックを必須化。即時フィードバック（PostToolUse）は補完関係、完了時チェック（Stop）は重複の可能性大

### L230: deploy_task.shのlessons_by_id dict構築でplatform教訓がproject教訓を上書きする
- **日付**: 2026-03-16
- **出典**: cmd_980
- **記録者**: kagemaru
- **tags**: [deploy, lesson]
- **if**: deploy_task.shがproject+platform教訓をlessons_by_idに統合する時
- **then**: dictキーをproject-prefixed IDにして名前空間を分離せよ
- **because**: 同一IDのproject教訓がplatform教訓で静かに上書きされ、dm-signal固有教訓227件が注入不能になっていた
- lessons.extend()でplatform教訓を後方追加→dict comprehensionで同一IDの場合にplatform版が残る。ID重複227件のproject固有教訓が静かに消失。対策: キーをproject-prefixed IDにするかID体系自体を分離

### L231: ruffの出力判定は終了コードか--quietで行うべき
- **日付**: 2026-03-16
- **出典**: cmd_979
- **記録者**: tobisaru
- **tags**: [lint, hook]
- **if**: Stop Hookでruff出力を判定する時
- **then**: ruff check --quietを使うか終了コードで判定せよ
- **because**: ruff成功時にAll checks passed!が出力され空判定で偽陽性が発生した
- ruffはlint成功時にAll checks passed!を標準出力する。出力の空判定(if [ -n ruff_out ])では偽陽性。修正: ruff check --quiet(成功時出力なし) or 終了コード判定。WSL2環境でruff.exe使用時はwslpath -wでパス変換が必要

### L232: pre-pushフックtimeout: 294テストが120秒内に完走しない
- **日付**: 2026-03-16
- **出典**: cmd_995
- **記録者**: kotaro
- **tags**: [testing, git]
- bats tests/unit/（294件、--jobs 4）がpre-pushのtimeout 120秒を超過。テストスイート増加に伴いtimeout延長かテスト分割が必要。

### L233: review task の `git diff --check` AC は対象commitスコープか clean-tree 前提を明示すべし
- **日付**: 2026-03-16
- **出典**: cmd_996
- **記録者**: sasuke
- **tags**: [testing, review, git]
- review/push task で `git diff --check` を repo 全体に対して要求すると、対象 commit が clean でも unrelated dirty worktree により恒常的に FAIL し得る。AC には `git show --check <commit>` のような commit-scope 検証を使うか、事前条件として clean-tree を明記すべき。

### L234: Android local unit test で org.json.JSONObject.put を直接使うと not mocked で落ちる
- **日付**: 2026-03-16
- **出典**: cmd_997
- **記録者**: hayate
- **tags**: [frontend, testing]
- IF Android の local unit test (`testDebugUnitTest`) で `org.json.JSONObject.put(...)` を使う THEN 実行前に Android stub 制約を確認し、純 JVM で動く代替初期化か mockable 設定を用意せよ BECAUSE 今回は `VoiceDictionaryTest` が `Method put in org.json.JSONObject not mocked` で fail し、build 成功後も AC を完了できなかった。

### L235: WSL2 /mnt/c 上の Android KSP incremental は generated/ksp byRounds で崩れることがある
- **日付**: 2026-03-16
- **出典**: cmd_997
- **記録者**: saizo
- **tags**: [frontend, testing, wsl2]
- IF Android Gradle project を WSL2 の `/mnt/c/...` で回し、KSP が `build/generated/ksp/.../byRounds` の copy/update 中に `NoSuchFileException` や `failed to make parent directories` を出す THEN `android/gradle.properties` で `ksp.incremental=false` を固定して non-incremental に落とせ BECAUSE 今回は `compileDebugKotlin` が KSP incremental 出力の更新で不安定化し、無効化後は素の `./gradlew compileDebugKotlin` と focused unit test が安定通過した。

### L236: L236
- **日付**: 2026-03-16
- **出典**: cmd_998のDC_998_02(朱雀排除)がPD-007で裁定済みにもかかわらず再エスカレーションされた。殿の時間を無駄にした
- **記録者**: decision_candidate起票前にpending_decisions.yamlを読み、同一論点の既存裁定がないか確認する。裁定済みならDCを起票せず、裁定内容を引用して自己解決せよ
- **tags**: [yaml]
- DC起票前にpending_decisions.yamlの既存裁定を確認し、裁定済みの件を再質問するな

### L237: L237
- **日付**: 2026-03-16
- **出典**: OpenAI ChatGPT ProはOAuth認証でAPIキー不要。使用量APIエンドポイントも存在しない。tmuxペインパース方式では不正確だった
- **記録者**: usage_monitor.sh(PROVIDER=codex)にSQLite直接クエリ方式を統合済み。Codex使用量の取得・監視はこのDB経由で行え
- **tags**: [db, oauth]
- Codex CLIの使用量はローカルSQLite(~/.codex/state_5.sqlite)のthreadsテーブルtokens_usedから取得せよ

### L238: L238
- **日付**: 2026-03-16
- **出典**: /tmp/mcas_usage_status_cache_*が壊れるとCodexだけでなくClaude側も表示不能になる連鎖障害が発生した
- **記録者**: キャッシュ破損時はrm /tmp/mcas_usage_status_cache_*で復旧。usage_status.shの障害切り分けではキャッシュ確認を最初に行え
- **tags**: [universal]
- usage_status.shのキャッシュ破損は全CLI(Claude含む)の使用量表示を停止させる

### L239: 並列implレビューはcommit integrityを独立チェックせよ
- **日付**: 2026-03-17
- **出典**: cmd_1031
- **記録者**: hayate
- **tags**: [review, parallel]
- **if**: 並列impl(複数忍者)の成果物をレビューする時
- **then**: git show --name-only HEADで全impl差分がcommitに閉じているかを先に確認。コード品質レビューはその後
- **because**: コード品質がPASSでもcommit未完了だとpush判定に進めない
- cmd_1031ではGrid dedup/PPE/parityのコード品質は全てINFORMATIONALだったが、impl_aが未commitのままHEADに載っておらずFAIL。レビューではコード品質とcommit整合性を分離して確認し、片方がPASSでも他方のFAILを見落とさない構成にすべき

### L240: test_result_guard.sh正規表現がbats TAP出力のテスト番号+テスト名を誤マッチ
- **日付**: 2026-03-18
- **出典**: cmd_1041
- **記録者**: hayate
- **tags**: [testing]
- parse_skip_count()の汎用正規表現 r"(\d+)\s+(?:tests?\s+)?skips?\b" は
bats TAP出力 "ok 293 skip and fail..." のテスト番号+テスト名を
「293テストSKIP」と誤解する。hookの汎用regexはTAP行フォーマットの
行頭パターン(ok/not ok + 番号)を考慮したアンカー付きパターンにすべき。
bats固有のSKIPは既にL138の "# skip" パターンで正しく検出できるため、
汎用regexからbats TAP行を除外するのが最も安全。

### L241: block_destructive.shはsettings.local.jsonにのみ登録—共有settings.jsonに未登録
- **日付**: 2026-03-18
- **出典**: cmd_1041
- **記録者**: kagemaru
- **tags**: [process, gate, git]
- D001-D008防御hookのblock_destructive.shがsettings.local.json(ローカル専用)にのみ登録されている。settings.json(共有/git追跡)には含まれない。新環境セットアップ時にlocal.jsonのコピーを忘れるとD001-D008が全て無防備になる。shutsujin_departure.shや環境構築手順にlocal.json確認を含めるべき。

### L242: 同一データの取得/保存を別関数に分けると重複メンテリスク
- **日付**: 2026-03-18
- **出典**: cmd_1041
- **記録者**: kirimaru
- **tags**: [tmux]
- get_context_pct()とupdate_context_pct()がCTX%パース処理を重複実装。一方はecho返却、他方はtmux変数設定。IF 同一データの取得と保存が別関数にある THEN 取得関数+薄いラッパーに統一せよ

### L243: field_deps.tsvのようなログ追記専用ファイルにはローテーション設計を初期実装時に組込むべき
- **日付**: 2026-03-18
- **出典**: cmd_1041
- **記録者**: saizo
- **tags**: [universal]
- field_get.shの_field_get_log()がfield_deps.tsvに無条件追記し続け5.3MB/40K行に肥大。 ログ系ファイルを新設する際は、初期実装時にサイズ上限+ローテーションを組込む設計を標準とすべき。 rotate_log.sh(10MB/5世代)のパターンが既に存在するため流用可能。

### L244: bare except:がSystemExitを捕捉しPython埋込判定を無効化する
- **日付**: 2026-03-18
- **出典**: cmd_1045
- **記録者**: kagemaru
- **tags**: [gate]
- cmd_complete_gate.shのPython埋込でsys.exit(0)がbare except:に捕捉されていた。except Exception:に変更すべき。同パターンがスクリプト内の他のPython埋込にも存在する可能性あり

### L245: ホワイトリスト型gitignoreで新規lib追加時はgitignore反映を確認せよ
- **日付**: 2026-03-18
- **出典**: cmd_1046
- **記録者**: saizo
- **tags**: [bash, git]
- ホワイトリスト型gitignore環境でscripts/lib/に新規shファイル追加時、.gitignoreホワイトリスト追記漏れでCIのみ失敗する。ローカルではファイルが存在するため検出不可。

### L246: デフォルト値return時はreturn 0が正しい(set -e対策)
- **日付**: 2026-03-18
- **出典**: cmd_1046
- **記録者**: saizo
- **tags**: [universal]
- 関数がデフォルト値をechoしつつreturn 1する設計は、set -euo pipefailの呼び出し元でクラッシュする。デフォルト値を返すならreturn 0が正しい。

### L247: found:falseは教訓を探さなかった証拠
- **日付**: 2026-03-19
- **出典**: cmd_1104
- **記録者**: kirimaru
- **tags**: [lesson]
- 全タスクに学びがある。found:falseの場合はno_lesson_reasonに理由必須。理由なきfound:falseは家老が差し戻す

### L248: assigned→idle化は/clear後にtask YAMLを読まなかった可能性大
- **日付**: 2026-03-19
- **出典**: cmd_1105
- **記録者**: kagemaru
- **tags**: [gate, yaml, monitor]
- STALL検知(assigned 10分超)で自動捕捉し家老に再配備を促す。ループ入口のスタック防止

### L249: 教訓還流の仕組み変更は3層同時修正必須
- **日付**: 2026-03-19
- **出典**: cmd_1104
- **記録者**: karo
- **tags**: [deploy, review]
- テンプレート(deploy_task.sh)・忍者ルール(ashigaru.md)・家老レビュー条件(karo.md)を同時修正しないと形骸化する。1箇所だけでは漏れる

### L250: 新規追加指示でもまず既存コードを確認せよ
- **日付**: 2026-03-19
- **出典**: cmd_1105
- **記録者**: karo
- **tags**: [monitor]
- 実装着手前に関連関数・変数をgrepで探索。今回check_stall関数が既存で閾値変更のみで済んだ。無駄な重複実装を防ぐ

### L251: no_lesson_reasonフィールド追加時は報告テンプレート+instructions+レビュー条件の3層を同時修正せよ
- **日付**: 2026-03-19
- **出典**: cmd_1104
- **記録者**: kirimaru
- **tags**: [deploy, review, communication, lesson, reporting]
- 教訓還流の仕組み変更は、テンプレート(deploy_task.sh)・忍者ルール(ashigaru.md)・家老レビュー条件(karo.md)の3層を同時に修正しないと、どこかで漏れる。1箇所だけ追加しても他が対応していなければ形骸化する

### L252: Stage 1ガード追加は上流(maybe_idle前)に配置すべし
- **日付**: 2026-03-19
- **出典**: cmd_1108
- **記録者**: karo
- **tags**: [deploy, gate, monitor]
- ninja_monitor.shのStage 1直後(maybe_idle追加前)にガードを入れることで下流のauto_clearとdeploy_stallの両経路を一箇所で保護できる

### L253: ホワイトリスト.gitignoreで新ファイル追加時はファイル単位パス指定必須
- **日付**: 2026-03-19
- **出典**: cmd_1111
- **記録者**: karo
- **tags**: [git]
- projects/ディレクトリ全体のホワイトリスト化はシークレット含有リスクあり。ファイル単位指定が必須。新規ファイル作成cmdでは.gitignoreホワイトリスト追加をACに含めるべき

### L254: 教訓注入ログの構造化不足が効果検証を阻害
- **日付**: 2026-03-20
- **出典**: cmd_1118
- **記録者**: karo
- **tags**: [deploy, testing, recon, gate, yaml, lesson]
- deploy_task.shは教訓を注入しているがcmd_id+注入lesson数+lesson_idsの構造化ログが未記録のため、教訓注入量とCLEAR率の相関分析が不可能。related_lessonsフィールドもarchived YAMLの大半で欠落。効果検証の定量精度向上にはログ構造化が前提。cmd_1118の計測で判明

### L255: lessons.yamlが最大の肥大化源(dm-signal:99k+infra:54k=153k tok)。定期アーカイブ機構が必要
- **日付**: 2026-03-20
- **出典**: cmd_1121
- **記録者**: karo
- **tags**: [yaml, lesson]
- 定期読込ファイルの計測で判明: lessons.yaml2本が家老CTXの34%を占める。cmd-chronicle.md(50k)+shogun_to_karo.yaml(42k)は全カテゴリ共通Redで定期アーカイブが全エージェントに効く。構造的ファイルは圧縮限界あり。単調増加型5件は定期パージで制御可能。cmd_1121で計測

### L256: deploy_task.sh lessons_by_id dictのID衝突でPJ間教訓が上書きされる
- **日付**: 2026-03-20
- **出典**: cmd_1127
- **記録者**: sasuke
- **tags**: [frontend, deploy, lesson]
- dm-signal+infra教訓を単一dictに格納する際、254件のID衝突でinfra版がdm-signal版を上書き。greedy_dedup/build_lesson_detail/helpful_countソートに影響。PJスコープ付き辞書に修正すべき

### L257: lesson_impact.tsvのtask_type列にimplとimplementが混在し参照追跡が分断
- **日付**: 2026-03-20
- **出典**: cmd_1127
- **記録者**: tobisaru
- **tags**: [deploy, lesson]
- deploy_task.shがtask_typeをそのままimpact_logに書き込むが、impl/implement/fix/enhance等で揺れている。参照追跡がimplement型でしか機能せず、impl型5150件分の参照データ欠損の可能性

### L258: ログローテーション世代数不足+task_idログ欠損
- **日付**: 2026-03-20
- **出典**: cmd_1129
- **記録者**: saizo
- **tags**: [recon, monitor]
- ログローテ1MBでは約1日分しか保持できず30日分析不可。STALL-DETECTEDの38%でcmd情報欠損(task_id空)。task_idフォールバック取得は低リスク高リターン

### L259: STALL偽陽性の38%はStale YAML Ghost(task_id空)が原因
- **日付**: 2026-03-20
- **出典**: cmd_1129
- **記録者**: kotaro
- **tags**: [gate, yaml, monitor, tmux]
- AUTO-CLEARはtmux変数のみリセットしYAMLファイルをクリーンアップしない。check_stall()がstatus残留を拾い偽陽性を発火。task_id空チェックで即排除可能。auto-clear自体が新問題を生む構造=自動消火が新問題を作る典型例

### L260: knowledge_metricsとlesson_impact.tsvのinjection_count乖離+Bottom教訓のPJ識別にはPJ列が必要+reconスキップの長期影響はPJ特性で差が出る
- **日付**: 2026-03-20
- **出典**: cmd_1127
- **記録者**: hayate
- **tags**: [recon, security, lesson]
- (1) L062(infra)がknowledge_metricsではinject=1だがlesson_impact.tsvに注入記録なし。データソース間の整合性チェック不足の可能性。
(2) L115/L062/L111/L133のIDだけではdm-signalかinfraか判別不能。knowledge_metricsのPJ列が正解。cmdでPJ明記がないとrecon時に混乱。
(3) recon比率: dm-signal65.5% vs infra34.9%。研究重視PJではreconスキップが注入率を大幅抑制する構造。PJ別スキップルール調整の余地あり。

### L261: 全体設定変更時のテスト整合性チェック不足
- **日付**: 2026-03-20
- **出典**: cmd_1128
- **記録者**: karo
- **tags**: [yaml, git]
- settings.yaml等の全体設定変更(全8名claude統一)がE2Eテスト2件+Unitテスト2件の陳腐化を43コミット蓄積後に発覚させた。設定変更コミット時にbatsテスト(e2e/unit)を走らせるpre-commitフック等があれば蓄積前に検知できた。全体設定変更→テスト影響確認のチェックリスト追加を推奨

### L262: stop-lint-gate.shの偽ブロック防止: (1)shellcheckに-S warning追加でinfo/style除外 (2)block時exit 1→exit 0でJSON decisionに委譲(exit 1はClaude Codeにhookエラーと誤判定される) (3)全uncommitted filesを対象にするため他忍者の変更でブロックされうる構造的欠陥は認識済み
- **日付**: 2026-03-20
- **出典**: cmd_1136実装中の半蔵がstop hook errorで停止
- **記録者**: karo
- **tags**: [gate, bash, git]
- stop-lint-gate hookが既存のinfo/style警告(SC1091等)で忍者をブロック。exit 1がClaude Codeに'non-blocking status code'エラーとして処理されblock decisionが無視された

### L263: bashライブラリ関数のwhile read変数名は呼出元と衝突する(動的スコープ)
- **日付**: 2026-03-20
- **出典**: cmd_1136
- **記録者**: karo
- **tags**: [bash]
- bashのwhile readループ変数名は呼出元のlocal変数と動的スコープで衝突する。ライブラリ関数内のwhile read変数は必ずプレフィックス付き(_ac_等)にせよ。cmd_1136でagent_config.shの変数name/role/jpが呼出元を上書きする問題が発生し、_ac_name/_ac_role/_ac_jpにリネームして解消。

### L264: archive_cmds list形式grepとdict形式STKの断絶
- **日付**: 2026-03-20
- **出典**: cmd_1140
- **記録者**: hayate
- **tags**: [yaml]
- archive_cmds()はgrep '- id: cmd_'でSTKを処理するがSTKはdict形式(cmd_XXXX:)。フォーマット変更時に処理側が追従しなかった。yaml.safe_loadで統一すべき

### L265: shutsujin_departure.shハードコードレイアウト禁止（3原則）
- **日付**: 2026-03-20
- **出典**: cmd_1139
- **記録者**: karo
- **tags**: [bash, tmux]
- (1) tmuxレイアウトにハードコード文字列を使うな→split-window+resize-pane (2) set -eスクリプトでは失敗箇所以降が全滅→重要初期化は失敗しない書き方で (3) 二重ファイル委譲は状態不整合の温床→一ファイル完結。出典:cmd_1139事故。target_files: shutsujin_departure.sh, scripts/lib/model_colors.sh

### L266: cmd_1142: 教訓registrationは常にlesson_write.sh経由
- **日付**: 2026-03-20
- **出典**: cmd_1142
- **記録者**: karo
- **tags**: [lesson]
- lesson_write.shの出力REFLUX_CHECK WARNを家老が必ず処理すること。忍者任せにせず家老がWARN内容をralph_loop_closer.shにパイプする

### L267: cmd_1143: 推薦先行+WHY形式を将軍ルールに恒久化
- **日付**: 2026-03-20
- **出典**: cmd_1143
- **記録者**: karo
- **tags**: [yaml, lesson]
- 殿への質問・提案は推薦先行+WHY必須。MCP教訓→lessons.yaml同期CMD起票義務。gstack知見3+L-teire提案フォーマットを将軍ルールとして恒久化

### L268: 非連番ペインインデックスにはPANE_IDS配列パターンが有効
- **日付**: 2026-03-20
- **出典**: cmd_1141
- **記録者**: hanzo
- **tags**: [tmux]
- 3列レイアウト等でペインインデックスが非連番になる場合、作成順にインデックスを追跡し列順(column-major)でPANE_IDS配列を構築すれば後続コードの変更を最小限(p=PANE_BASE+i→p=PANE_IDS[i])に抑えられる

### L269: bashのwhile readでYAMLブロック境界判定は不安定→awkを使え
- **日付**: 2026-03-20
- **出典**: cmd_1152
- **記録者**: hayate
- **tags**: [bash, yaml]
- while IFS= readループで ^[[:space:]]{4}cmd_ パターンマッチしたがYAML複数行文字列内のインデントと区別できず過剰カウント。awkの /^  cmd_/パターンなら正確に境界検出できた。YAMLブロック切り出しにはawkが安全

### L270: agent_config.sh導入時にテスト環境の依存関係も更新すべき
- **日付**: 2026-03-22
- **出典**: cmd_1242
- **記録者**: karo
- **tags**: [testing, communication, inbox]
- cmd_1136でagent_config.shを12スクリプトに導入した際、テスト環境(INBOX_WRITE_TEST=1/ファイル不在時のgraceful degradation)が未対応だった。外部依存追加時はテスト環境も確認すべき。

### L271: 報告YAMLフォーマット修正必要なし — cmd_1252
- **日付**: 2026-03-22
- **出典**: cmd_1252
- **記録者**: karo
- **tags**: [communication, gate, yaml, lesson, reporting]
- gate_report_format.sh cmd_1248でlessons_useful dict形式+binary_checks string形式のバリデーション追加済み。影丸がこのgate強化後もdict/string形式で提出。自動修正で対応したがgate BLOCKで差し戻すのが正規フロー

### L272: テスト依存ファイル追加時は全テストのsetup()も更新すべき+固定日付は動的日付に
- **日付**: 2026-03-22
- **出典**: cmd_1255
- **記録者**: saizo
- **tags**: [gate, reporting]
- agent_config.sh/normalize_report.sh/gate_dc_duplicate.sh追加時にテストsetupへのコピーが漏れた(L270同根)。また固定日付(2026-01,2026-03-11)はtrim(30日)やstale(7日)閾値超過でFAILする。動的日付(date -d N days ago)を使うべき

### L273: PostToolUse hookがテスト名中のskipに誤検知
- **日付**: 2026-03-22
- **出典**: cmd_1260
- **記録者**: hayate
- **tags**: [deploy]
- batsテスト名にskipsを含むテスト(例:deploy_task skips ac_priority)が存在すると、PostToolUse hookがSKIP検知として誤報する。実際のTAP SKIPマーカーは# skip形式。hookのgrep条件を# skipに限定すべき

### L274: Gate拡張時はalerts配列+overall更新パターンを踏襲
- **日付**: 2026-03-22
- **出典**: cmd_1261
- **記録者**: tobisaru
- **tags**: [gate]
- 新Gate追加時は出力だけでなくalerts配列への追加+overall状態更新を既存パターンに合わせること。Gate11で漏れが発生した

### L275: gunshi_review_log大規模ファイルのRead制限
- **日付**: 2026-03-22
- **出典**: cmd_1261
- **記録者**: kotaro
- **tags**: [review, yaml, oauth]
- gunshi_review_log.yamlは600行で10000token超。Read時にlimit指定必須。全量読みを前提とした作業設計は避けよ

### L276: WARNINGで続行するコードパスはサイレント障害の温床
- **日付**: 2026-03-22
- **出典**: cmd_1264
- **記録者**: karo
- **tags**: [testing, communication, gate, inbox]
- gate検証でパス解決失敗時にWARNING出力のみで続行すると、gateが発火せずすり抜ける。失敗時は即BLOCK(exit 1)が鉄則。WARNING+続行は問題を検知したが無視すると同義。inbox_write.shで3箇所のサイレントスキップをBLOCKED+exit1に修正して根絶

### L277: git diff一時リポジトリにはgit config user.email/name設定必須
- **日付**: 2026-03-22
- **出典**: cmd_1263
- **記録者**: karo
- **tags**: [git]
- git diffテスト用一時リポジトリにはgit config user.email/name設定必須。未設定だとcommit失敗しテスト前提が崩れる

### L278: 報告YAML欠損パターン — commit後/clear前にreport未作成
- **日付**: 2026-03-22
- **出典**: cmd_1264
- **記録者**: karo
- **tags**: [communication, gate, yaml, git, monitor, inbox, reporting]
- cmd_1264でkagemaruがcommit完了・task status doneだが報告YAML未作成のまま/clearされた。ninja_monitorのAUTO-DONEでstatus=doneになったがreport作成前。commitと報告は不可分のセットであり、commit後即座にreport作成が必要。現行のcommit→report→inbox_writeの順序で、commit直後に/clearされると報告が消失する。

### L279: scope_creep_同一ファイル並列配備
- **日付**: 2026-03-22
- **出典**: cmd_1267
- **記録者**: karo
- **tags**: [communication, git, reporting]
- 才蔵がAC1配備でAC2(小太郎担当)のコードも実装しcommit。小太郎は実装済みコードをテスト確認のみで報告。根本原因: 同一ファイル(dashboard_auto_section.sh)に対する異なるACを並列配備した。ファイル重複なしと判断したが、実装者が隣接機能も実装する自然な傾向を考慮していなかった。対策: 同一ファイルの異なるセクションであっても、ACの実装対象が密接に関連する場合は1名に統合配備せよ

### L280: ninja_monitor.sh新変数追加時は関連テストのdeclare-A+キー初期化も同時更新必須
- **日付**: 2026-03-22
- **出典**: cmd_1268
- **記録者**: hayate
- **tags**: [monitor]
- ninja_monitor.shはset -uを使わないがテストはset -euoで実行される。新しい連想配列変数を追加する際、関連テストのdeclare -Aとキー初期化も同時に更新しないとunbound variable errorでテスト失敗する。

### L281: bats mock環境でsource先stub追加漏れ
- **日付**: 2026-03-22
- **出典**: cmd_1268
- **記録者**: tobisaru
- **tags**: [testing, bash]
- ntfy_listener.shにscript_update.shのsource行が追加されたがtest側のmock setup()にstub追加が漏れた。source行追加時にmock側突合が必要。

### L282: PostToolUse hookはpermissionDecision:deny不可。WARN/BLOCK切替はPreToolUse制御
- **日付**: 2026-03-22
- **出典**: cmd_1265
- **記録者**: karo
- **tags**: [gate]
- PostToolUseは事後実行のためpermissionDecision:denyが効かない。WARNモード=PostToolUse additionalContext表示。BLOCKモード=PreToolUse deny。モード切替はPreToolUseのcase文復元/除去のみ。cmd_1265で半蔵実装確認済み

### L283: PostToolUse hook SKIPカウントの誤検知
- **日付**: 2026-03-23
- **出典**: cmd_1277
- **記録者**: kagemaru
- **tags**: [universal]
- batsテスト名にskipが含まれるとPostToolUse hookがSKIP検出と誤判定する。hookはTAP出力の ok N (hash) skip パターンのみをカウントすべき。

### L284: Vercel化後の消費者スクリプトarchive参照切替が必要
- **日付**: 2026-03-23
- **出典**: cmd_1280
- **記録者**: hanzo
- **tags**: [deploy, yaml, lesson]
- lessons.yamlが索引化されたため、deploy_task.sh/lesson_update_score.sh/lesson_deprecate.sh等のフルデータ消費者はlessons_archive.yamlを参照すべき。特にdeploy_task.shのタグマッチは後方互換フォールバック(全教訓注入)に退行する

### L285: lesson_update_score.shの書込先がindex(lessons.yaml)のままでblock-style書き戻しが発生する
- **日付**: 2026-03-23
- **出典**: cmd_1280
- **記録者**: kagemaru
- **tags**: [gate, yaml, lesson]
- sync_lessons.shがflow-style索引を出力後、lesson_update_score.shがyaml.dump(default_flow_style=False)で書き戻すと索引が3097行に膨張する。sync再実行で修復されるが、lesson_update_score.shの書込先をlessons_archive.yamlに変更するのが根本対策。
