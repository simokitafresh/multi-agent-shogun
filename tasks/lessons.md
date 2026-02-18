
### L001: Read before Write必須（Claude Code制約）
- **日付**: 2026-02-18
- **出典**: cmd_125
- **記録者**: karo
- Claude CodeはRead未実施のファイルへのWrite/Editを拒否する。タスクYAML・inbox・報告YAML等を書く前に必ず対象ファイルをReadせよ。Write-before-Read試行はエラーとなりリトライが必要になる。

### L002: inbox_watcher.shのforeground bashブロックで家老が応答不能になる
- **日付**: 2026-02-18
- **出典**: cmd_125
- **記録者**: karo
- inbox_watcher.shは60秒リトライ内蔵だが、家老がforeground bashコマンドでブロック中はnudgeを受信できない。Bash toolのrun_in_background=true必須化で解決。新スクリプト不要。

### L003: CLAUDE.md更新は稼働中エージェントに即反映されない
- **日付**: 2026-02-18
- **出典**: cmd_125
- **記録者**: karo
- CLAUDE.mdやinstructions/*.mdを更新しても、既に稼働中のエージェントのコンテキストには反映されない。ninja_monitor.shにcheck_script_update機能を追加し、スクリプト更新時に/clearを発動して再読み込みさせる仕組みで解決(cmd_125)。

### L004: ペイン変数(@current_task)が空でも未配備と断定するな
- **日付**: 2026-02-18
- **出典**: cmd_092
- **記録者**: karo
- tmuxペイン変数@current_taskが空文字でも、忍者が実際にアイドルとは限らない。capture-paneで実際の画面出力を確認してから判断せよ。変数が設定されていないだけで作業中の可能性がある。

### L005: build_instructions.shはashigaru.mdのYAML front matterのみ抽出する
- **日付**: 2026-02-18
- **出典**: cmd_134
- **記録者**: karo
- ashigaru.mdの本文コンテンツはroles/ashigaru_role.mdから取得される。ashigaru.md本体への変更だけではbuild生成物に反映されない。roles/のパーツファイルも同時に更新が必要。

### L006: lesson_write.shには既存教訓との重複チェック機能がない
- **日付**: 2026-02-18
- **出典**: cmd_134
- **記録者**: karo
- 同一内容の教訓を異なるcmdから登録すると二重エントリが作成される。タイトル類似度チェックまたはsource_cmd重複チェックの追加が望ましい。


### L007: .gitignoreがwhitelist方式の場合、新規スクリプト追加時はwhitelist許可(!path)を追加せよ
- **日付**: 2026-02-18
- **出典**: cmd_140
- **記録者**: karo
- multi-agent-shogunの.gitignoreは*で全除外→!で個別許可方式。scripts/配下に新ファイルを作成してもwhitelist未追加だとgitignoreされ、git addしてもcommitに含まれない。レビュー担当も確認必須。


### L008: WSL2新規shファイルはCRLF改行混入リスクあり
- **日付**: 2026-02-18
- **出典**: cmd_143
- **記録者**: karo
- WSL2環境(/mnt/c/)でClaude CodeのWriteツールで新規.shファイルを作成するとCRLF改行になる場合がある。新規.sh作成後はfile commandでチェックし、CRLF混入時はsed -i 's/\r$//' で修正。レビュー時もfile commandでCRLFチェックを追加すべし。

### L009: commit前にgit statusで全対象ファイルの認識状態を確認せよ
- **日付**: 2026-02-18
- **出典**: cmd_143
- **記録者**: karo
- whitelist方式.gitignoreでは新ファイルをwhitelist追加し忘れるとgit addしてもcommitに含まれない。実装者がwhitelist追加しても対象ファイル自体(settings.yaml等)の漏れは見落としやすい。レビュー時にgit status --shortで全commit対象が認識されていることを確認する手順が有効。

### L010: 報告YAMLのstatus行先頭マッチ
- **日付**: 2026-02-18
- **出典**: cmd_145
- **記録者**: hanzo
- 報告YAMLのstatus行は'^status:'で先頭マッチすべき。indent付きstatusフィールド(result内等)との誤マッチを防ぐ。grep -m1 '^status:'が安全。

### L011: core.hooksPathフック配置確認
- **日付**: 2026-02-18
- **出典**: cmd_147
- **記録者**: saizo
- core.hooksPathが.githooksに設定されている場合、.git/hooks/にフックを配置しても無視される。フック作成時はまず git config --get core.hooksPath を確認し、適切なディレクトリに配置すべし。

### L012: bashrc aliasではパイプ構文ブロック不可
- **日付**: 2026-02-18
- **出典**: cmd_147
- **記録者**: tobisaru
- bashrc aliasではパイプ構文(curl|bash等)をブロックできない。パイプはシェル構文であり個々のコマンドのalias化では検知不可。capture-pane監視(ninja_monitor)による検知が有効な代替手段。

### L013: L005教訓はkaro系にも適用
- **日付**: 2026-02-18
- **出典**: cmd_150
- **記録者**: hanzo
- karo.md(直接読み用)とroles/karo_role.md(ビルド用ソース)は別ファイル。karo.mdの変更だけではgenerated/karo.md等のビルド生成物に反映されない。一括置換タスクでは両方をスコープに含めるべき。L005のkaro版。

### L014: grep --excludeはWSL2 /mnt/c上で不安定
- **日付**: 2026-02-18
- **出典**: cmd_151
- **記録者**: karo
- grep --exclude-dirやgrep --excludeはWSL2の/mnt/c(Windows FSマウント)上では予期しない動作をすることがある。パイプフィルタ(grep -Ev 'pattern')の方が確実。model_switch_preflight.shで実証(cmd_151)

### L015: CLAUDE_CONFIG_DIR環境変数で~/.claudeディレクトリを丸ごと切替可能。CLAUDE_CODE_OAUTH_TOKENで認証のみの切替も可能
- **日付**: 2026-02-18
- **出典**: saizo
- **記録者**: karo
- infrastructure

### L016: OAuthリフレッシュトークンは単一使用。複数セッション共有時にプロセスAがリフレッシュするとBのトークンが無効化される。CLAUDE_CODE_OAUTH_TOKENで直接指定すればリフレッシュ競合を回避可能
- **日付**: 2026-02-18
- **出典**: tobisaru
- **記録者**: karo
- infrastructure

### L017: 入口門番は再配備時に自己ブロックする
- **日付**: 2026-02-18
- **出典**: cmd_158
- **記録者**: karo
- deploy_task.shの入口門番(check_entrance_gate)は、同一タスクの再配備時にもreviewed:false残存をブロックする。初回起動失敗→再配備のケースではinbox_write.sh直接送信で回避が必要。将来的にoverride経路の検討が望ましい
