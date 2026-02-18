
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

