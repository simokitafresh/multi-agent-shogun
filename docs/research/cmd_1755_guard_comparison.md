# cmd_1755 偵察B: guard.sh vs pre-bash-combined.sh 機能比較

> 調査日: 2026-04-06
> 調査元: yohey-w/multi-agent-shogun PR#113 (`scripts/hooks/guard.sh`)
> 比較先: `.claude/hooks/pre-bash-combined.sh` (我が軍)

## §1 概要

| 項目 | 大元 (guard.sh) | 我が軍 (pre-bash-combined.sh) |
|------|----------------|------------------------------|
| 配置 | `scripts/hooks/guard.sh` | `.claude/hooks/pre-bash-combined.sh` |
| Hook種別 | PreToolUse (exit 0=allow, exit 2=block) | PreToolUse (JSON hookSpecificOutput, exit 0=allow, exit 1=block) |
| 言語 | bash + grep/jq | bash + python3 (Guard 4のみ) |
| チェック数 | 6 hooks | 6 guards |
| テスト | `scripts/hooks/test_hooks.sh` (187行) | なし |
| 出力形式 | stderr + exit 2 | JSON permissionDecision deny |

## §2 機能比較表

### 破壊的操作ガード (D001-D009)

| ルールID | チェック内容 | 大元 | 我が軍 | 備考 |
|----------|------------|------|--------|------|
| D001 | `rm -rf /`, `/mnt/*`, `/home/*`, `~` | Hook 2 (grep) | Guard 4 (python3 check_rm) | 大元=正規表現マッチ、我が軍=shlex+realpath解決 |
| D002 | `rm -rf` プロジェクト外パス | **なし** | Guard 4 (outside_project) | **我が軍独自**。python3でrealpath解決し判定 |
| D003 | `git push --force/-f` | Hook 2 (grep) | Guard 4 (check_git) | 両方 --force-with-lease は許可 |
| D004 | `git reset --hard` | Hook 2 (grep) | Guard 4 (check_git) | 同等 |
| D004 | `git checkout -- .` | Hook 2 (grep `-- .`) | Guard 4 (check_git) | 同等 |
| D004 | `git restore .` | Hook 2 (grep) | Guard 4 (check_git) | 同等 |
| D004 | `git clean -f` | Hook 2 (grep) | Guard 4 (check_git) | 我が軍は `--force` フラグも検出 |
| D005 | `sudo`, `su` | **なし** | Guard 4 (cmd0チェック) | **我が軍独自** |
| D005 | `chmod -R`, `chown -R` on system paths | Hook 2 (grep, 限定パスリスト) | Guard 4 (python3 is_system_path) | 大元=/etc,/usr等13パス。我が軍=/etc,/usr等10パス+/home,/mnt/c,/mnt/d |
| D006 | `kill` (単体) | **なし** | Guard 4 (cmd0チェック) | **我が軍独自** |
| D006 | `killall`, `pkill` | Hook 2 (grep) | Guard 4 (cmd0チェック) | 同等 |
| D006 | `tmux kill-server/kill-session` | Hook 2 (grep) | Guard 4 (cmd0+tokens[1]チェック) | 同等 |
| D007 | `mkfs`, `fdisk` | Hook 2 (grep) | Guard 4 (cmd0チェック) | 同等 |
| D007 | `dd if=` | Hook 2 (grep) | Guard 4 (tokensチェック) | 同等 |
| D007 | `mount`, `umount` | **なし** | Guard 4 (cmd0チェック) | **我が軍独自** |
| D008 | `curl|bash`, `wget|sh` pipe-to-shell | Hook 2 (grep) | Guard 4 (python3 check_pipe_to_shell) | 我が軍の方が正規表現が精密 |
| D009 | `chrome --headless` without `--user-data-dir` | **なし** | Guard 4 (tokensチェック) | **我が軍独自** |

### 非破壊的ガード

| チェック内容 | 大元 | 我が軍 | 備考 |
|------------|------|--------|------|
| Co-Authored-By禁止 | Hook 1 | **なし (逆ルール)** | 我が軍はCo-Authored-By**必須**。大元は**禁止**。**相反ルール** |
| `--no-verify` ブロック | **なし** | Guard 1 | **我が軍独自**。git commit --no-verify を禁止 |
| yaml.dump/safe_dump on運用YAML | **なし** | Guard 2 | **我が軍独自**。queue/tasks/inbox/reports等のデータ消失防止 |
| report YAML直接書込み禁止 | **なし** | Guard 3 | **我が軍独自**。report_field_set.sh経由を強制 |
| main/masterブランチ保護 | Hook 3 | **なし** | **大元独自**。commit/pushをブロック |
| push前lint/typecheckチェック | Hook 4 | **なし** | **大元独自**。package.jsonからスクリプト検出し実行 |
| GH_TOKEN設定時ghブロック | Hook 5 | **なし** | **大元独自**。GH_TOKEN環境変数チェック |
| code-review-expert実行強制 | Hook 6 | **なし** | **大元独自**。.code-review-done marker file方式 |
| bats全量実行ブロック | **なし** | Guard 5 | **我が軍独自**。tests/unit/全量実行を禁止(12分超見込み) |
| capture-pane最小30行 | **なし** | Guard 6 | **我が軍独自**。末尾数行での状態誤判断防止 |

### 実装品質比較

| 観点 | 大元 (guard.sh) | 我が軍 (pre-bash-combined.sh) |
|------|----------------|------------------------------|
| コマンドパース | grep正規表現のみ | shlex.split + realpath (python3) |
| パス解決 | 文字列マッチのみ | `os.path.realpath` で正規化後に判定 |
| セグメント分割 | なし (コマンド全体をgrep) | `re.split(r"&&|\|\||;|\|")` でセグメント単位チェック |
| バイパス対策 | `has_git_subcmd()` — function alias, variable alias, full path, command/env wrapper検出 | なし (直接コマンド名のみ) |
| GIT_TARGET_DIR | `resolve_git_dir()` — cd先の外部リポを検出 | なし (CWD前提) |
| 早期リターン | payload全体の文字列チェックなし | 危険キーワード不在→即exit 0 (高速化) |
| テスト | test_hooks.sh (187行, 40+テストケース) | なし |

## §3 大元にあって我が軍にないチェック（取込推奨判定）

| # | チェック | 取込推奨 | 理由 |
|---|---------|---------|------|
| 1 | Co-Authored-By禁止 | **不要 (相反)** | 我が軍はCo-Authored-By**必須**ルール。大元とは逆方向の運用 |
| 2 | mainブランチ保護 | **検討** | 我が軍は全エージェントがmainで直接commit/pushする運用（infra repo）。外部PJ(DM-Signal等)では有用。ただし適用範囲の制御が必要 |
| 3 | push前lint/typecheck | **検討** | DM-Signal等のNode.jsプロジェクトでは有用。ただし我が軍のinfra repoにはpackage.jsonなし |
| 4 | GH_TOKEN警告 | **不要** | 我が軍の環境では問題未発生。geolonia org固有の課題 |
| 5 | code-review-expert実行強制 | **不要** | 我が軍は軍師+家老レビューフロー。marker file方式は不使用 |
| 6 | git subcommandバイパス検知 (has_git_subcmd) | **検討** | function alias/variable alias等のバイパス検出は堅牢性向上に寄与。ただし我が軍のpython3チェッカーはshlex.splitでトークン化するため、直接コマンドのバイパスリスクは低い |
| 7 | GIT_TARGET_DIR (cd先外部リポ判定) | **検討** | cd先でgit操作する場合にCWDのブランチで誤判定するリスクを防止。現状我が軍にmainブランチ保護がないため依存関係あり |
| 8 | テストスクリプト (test_hooks.sh) | **推奨** | guard hookの回帰テストがない。変更時の安全性向上 |

## §4 我が軍にあって大元にないチェック

| # | チェック | 意義 |
|---|---------|------|
| 1 | D002: rm -rf プロジェクト外パス検出 | プロジェクト外の誤削除防止。realpath解決で精密 |
| 2 | D005: sudo/su直接ブロック | 権限昇格の根本防止 |
| 3 | D006: kill単体ブロック | プロセス終了の広域防止 |
| 4 | D007: mount/umount | マウント操作の安全策 |
| 5 | D009: chrome --headless保護 | 殿のChrome sessionsデータ保護 |
| 6 | --no-verify ブロック | hookバイパス防止 |
| 7 | yaml.dump運用YAML保護 | データ消失防止 (cmd_1399事故教訓) |
| 8 | report YAML直接書込み禁止 | report_field_set.sh強制 |
| 9 | bats全量実行ブロック | 無駄な長時間テスト防止 |
| 10 | capture-pane最小30行 | 状態誤判断防止 |
| 11 | python3パース (shlex+realpath) | 文字列grepより精密なコマンド解析 |
| 12 | セグメント分割チェック | `&&`, `||`, `;`, `|` でチェーンされたコマンドを個別検査 |

## §5 総合所見

**我が軍のpre-bash-combined.shは破壊的操作ガードにおいて大元を上回る**:
- D002/D005(sudo)/D006(kill)/D007(mount)/D009は我が軍独自
- python3によるshlex+realpathパースは、grepベースより精密なコマンド解析を提供
- セグメント分割により、チェーンコマンド内の危険操作も検出

**大元は非破壊的ガード(mainブランチ保護・lint/typecheck・レビュー強制)が充実**:
- 我が軍にはCLAUDE.mdルールとしては存在するが、hook自動強制はなし
- バイパス検知(has_git_subcmd)は堅牢性の観点で参考になる

**取込優先度**:
1. テストスクリプト — hook変更時の回帰テスト確保(最優先)
2. mainブランチ保護 — 外部PJ操作時の安全策(適用範囲制御要)
3. バイパス検知 — 現行python3パーサーとの統合検討
4. push前lint/typecheck — DM-Signal等Node.jsPJで有用
