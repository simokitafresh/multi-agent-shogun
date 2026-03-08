
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
- **status**: confirmed
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

### L062: acceptance_criteriaフィールドはdict/str混在のためjoin前に型変換が必要
- **日付**: 2026-02-26
- **出典**: --tags
- **記録者**: pipeline,process
- **tags**: [pipeline, process]
- **if**: acceptance_criteriaフィールドをパースする時
- **then**: dict/str混在を考慮し、join前に型変換(str化)のフォールバックを入れよ
- **because**: 報告YAMLのacceptance_criteriaがdict型の場合もstr型の場合もあり、型不一致でエラーになるため
- IF acceptance_criteriaフィールドをパースする時 THEN dict/str混在を考慮し、join前に型変換(str化)のフォールバックを入れよ

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

### L111: ACに含めるテストファイルは配備時に実在確認が必要
- **日付**: 2026-03-01
- **出典**: cmd_460
- **記録者**: karo
- **tags**: [testing, review, gate]
- **if**: ACにテストファイルパスを含むタスクを配備する時
- **then**: テストファイルの実在を事前検証してから配備せよ
- **because**: 存在しないテストファイルをACに含めると忍者が実行不能になり手戻りが発生するため
- IF ACにテストファイルパスを含むタスクを配備する時 THEN テストファイルの実在を事前検証してから配備せよ

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

### L115: check_auto_archive()のawkがacceptance_criteria idを誤抽出。YAMLパース時はcmd_*パターン限定が必須
- **日付**: 2026-03-01
- **出典**: ninja_monitor,auto_archive
- **記録者**: shogun(hotfix)
- **tags**: [monitor, yaml, awk]
- **if**: check_auto_archive()のawkがacceptance_criteria idを誤抽出。YAMLパース時
- **then**: check_auto_archive()のawkパターン `/^[[:space:]]*-[[:space:]]id:/` がcmdレベル(2スペース)とacceptance_criteriaレベル(6スペース)の両方にマッチ
- **because**: 最後に拾ったAC4がarchive_completed.shに渡されて毎サイクルエラー
- IF check_auto_archive()のawkがacceptance_criteria idを誤抽出。YAMLパース時 THEN check_auto_archive()のawkパターン `/^[[:space:]]*-[[:space:]]id:/` がcmdレベル(2スペース)とacceptance_criteriaレベル(6スペース)の両方にマッチ

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
