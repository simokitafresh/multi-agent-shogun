<!-- gist-master: 884767b5f209cd6b3d89c22e2c22434d readme_ja_reference_20260827.md -->
# README_ja 新リファレンス(将軍執筆・2026-08-27 23:30)

- 目的: 殿指示 2026-08-27 23:26『主な特徴も今は全然違う。将軍自身がリファレンスとして README_ja の新しいリファレンスを忍者とは別に作成し gist に共有』。cmd_4410(忍者が README/README_ja を現物突合で書き直す)の**参照原本**であり、忍者はこの文書と現物が食い違えば現物を正とし、差分を報告する。
- 前提: 本文の数値は 2026-08-27 23:26 の一次計測(`ls | wc -l`, `git log`, `config/settings.yaml`, gate_metrics)。日付付きで書き、更新時は行を差し替えず追記する(歴史修正禁止)。
- origin: `[[殿指示_README覚醒_他PCクローン整合_20260827_2312]] -> [[cmd_4409_可搬性根治]] -> [[cmd_4410_README現物突合]] -> [[readme_ja_reference_20260827]]`

---

## 1. これは何か(2026-08 時点の一文)

**multi-agent-shogun は、1 人の人間(殿)が tmux 上の 9 体の CLI エージェント(将軍 1・家老 1・軍師 1・忍者 6)に、YAML ファイルとファイル監視だけで指揮を出し、結果を二値で検証し、失敗を教訓・ゲート・テストへ還流させて自動成長させる「戦国式」マルチエージェント基盤**である。API ではなく各社 CLI(Claude Code / Codex CLI)をそのまま並べ、CLI ごとに固有の hook・gate を持つ multi-CLI 構成。2026-02-09 の初 commit から 16,555 commit(2026-08-27)。

旧 README(2026-02〜03 の記述)との最大の違い:

| 旧 README が書いていたこと | 現在(2026-08-27) |
|---|---|
| 将軍→家老→足軽 8 名、Claude 単一 | 将軍→家老→**軍師**→忍者 6 名。**家老・忍者は Codex(gpt-5.6-sol/luna)、将軍・軍師は Claude(Opus 4.6 1M)**の混成。`config/settings.yaml` が編成の唯一の正で `/shogun-cli-switch` で切替 |
| send-keys で指示を流す | **mailbox(`queue/inbox/*.yaml`)+inotify watcher の nudge**。エージェントは send-keys を呼ばない。確認プロンプト検知・配達検証・未読 N 分の再 nudge まで機械化 |
| 手動で結果を見る | **cmd_save 品質ゲート(82 check)→deploy_task(task worktree 隔離)→報告 YAML(二値 binary_checks)→軍師 SG7 レビュー→家老 GATE(cmd_complete_gate)→CI(bats 242 ファイル、shard 実行)**の全段が自動 |
| 教訓は人が書く | **三層学習ループ**: lesson_candidate→lesson→gate/fixture。reflux(insight 自動配備)が idle 忍者へ気づきを流す |
| メモリは Memory MCP のみ | **三層記憶**(記憶DB SQLite・セマンティック索引・Obsidian 因果ネットワーク)+起動時 preflight+[MEM:] 引用契約 |
| /mnt/c(Windows ドライブ)で運用 | **ext4(/home)へ移設済(2026-08-27 22:00)**。git status 60-120s→84ms、配備 199-397s→23s |
| Quick Start は C:\tools 前提 | 任意パスに clone(または ZIP 展開)→`first_setup.sh`→初回認証→`shutsujin_departure.sh`(cmd_4410 で書き直し) |

## 2. 陣形(2026-08-27、`config/settings.yaml` 正本)

| 役割 | pane | CLI / model | 何をするか |
|---|---|---|---|
| 殿 | 端末 | 人間 | 指示・裁定。将軍と対話し、dashboard/artifact を自分で見る |
| 将軍 shogun | window 1 | Claude Code (Opus 4.6, 1M) | 殿の指示を cmd(YAML)に起票、品質ゲートを通し家老へ委任。30 分 loop で一次確認・つまり解消・artifact 更新。コード深掘り調査は禁止(F008)=偵察 cmd で委任 |
| 家老 karo | agents.1 | Codex (gpt-5.6-sol medium) | cmd を task に分解し忍者へ配備。報告を受け GATE を回し、converge/push(1 commit ずつ)。karo_hotfix/ci_fix は将軍 cmd なしで自立配備 |
| 軍師 gunshi | agents.2 | Claude Code (Opus 4.6, 1M) | cmd draft と報告 YAML の一次レビュー(SG7 プロトコル)。LGTM→家老 ACCEPT、FAIL→差戻し。idle 時は分析を永続化 |
| 忍者 ×6 hayate/kagemaru/hanzo/saizo/kotaro/tobisaru | agents.3-8 | Codex (gpt-5.6-luna high) | task YAML の AC を最高品質で遂行。task worktree で隔離作業→`ninja_scope_commit.sh`→報告 YAML。記憶の連続性なし(毎回 /clear) |

鎖=殿→将軍→家老→忍者の一本道。分岐なし・迂回なし。**鎖は命令の道であると同時に学びの還流路**(忍者の lesson_candidate が家老を経て教訓・gate・fixture へ入る)。

## 3. 三層学習ループ(殿定義 2026-03-19/20)

全作業に「①実行→②二値計測→③知見還流→次サイクル強化」を回す。スコープの三層:

| 層 | スコープ | 実装 |
|---|---|---|
| 個 | ロール内 | AC ごとの binary_checks(yes/no)、brainwash_check(洗脳 8 パターン)、deepdive 追体験(起動時 Phase 単位 replay と receipt) |
| 対 | 忍者+家老、家老+軍師 | 報告 YAML→軍師 SG7→家老 GATE の往復、karo_workarounds の計測、rework 率 |
| 全 | 鎖全体 | reflux(insights.yaml の pending を idle 忍者へ自動配備)、教訓淘汰(RETIRE)、gate_metrics/defense_overhead の日次 before/after、CI GREEN 維持 |

**/clear=強くてニューゲーム**: CTX 0% に戻っても、知識基盤(CLAUDE.md・instructions・lessons・記憶DB・runbook)が残るので次は前より強い状態で再開する(ラルフループ)。**自動消火禁止**: 問題を隠す変更をせず根源へ。**削るな、速くしろ**(2026-07-21): gate/hook は削除せず、品質 2 原則を保ったまま超速化する。

## 4. 三層記憶(殿厳命 2026-06-10『使用しないのはバグ』)

| 層 | 実体 | 入口 |
|---|---|---|
| 記憶DB | SQLite `data/multi_agent_shogun_memory.db`(events/FTS5、殿との対話・裁定・knowledge・session_save) | `bash scripts/memory_db_query.sh --search "<語>"`、書込み `scripts/memory_db_knowledge_write.sh` |
| セマンティック索引 | `context/semantic-map.md` + `docs/semantic-index/index.md`(概念・alias・discussion) | `bash scripts/semantic_search.sh "<query>"` |
| Obsidian 因果ネットワーク | `[[リンク]]` と `origin: "[[発端]] -> [[原因]] -> [[結果]]"`(教訓・報告・cmd に必須) | `.cache/causal_index.tsv`、`/three-layer-penetrate` |

契約: 全ての作業前に三層を検索(hook が preflight を自動注入)、殿への応答に `[MEM: …]` 引用タグ必須(欠落は stop hook が BLOCK)。新知識は三層へ貫通(記憶DB 書込み+alias+[[リンク]])。復帰点は記憶DB の `session_save_YYYYMMDD_HHMM`。

## 5. 主な特徴(2026-08-27 現在・現物ベース)

1. **mailbox 通信** `scripts/inbox_write.sh <to> "<msg>" <type> <from> <action>`: flock 付き YAML 永続化+`inbox_watcher.sh`(inotify)が `inboxN` の短い nudge を送る。type により自動既読(info 系)/起床(task_assigned 等)を分離。確認プロンプト検知で nudge 抑止、Codex 配達検証、未読 N 分で再 nudge。
2. **cmd 起票ゲート** `scripts/cmd_skeleton.sh`→`cmd_save.sh --preflight`→`cmd_save.sh`→`cmd_delegate.sh`: 82 の check 関数(q1-q12 品質問答、AC の二値性・パス実在・テスト契約・DB restore 契約・environment_change)で BLOCK/WARN。BLOCK は「次の cmd で BLOCK されないよう環境へ埋め込む」成長ループの入口。
3. **配備と隔離** `scripts/deploy_task.sh`: task YAML 生成・関連教訓 push 注入・semantic_concepts 注入・**task worktree**(`/home/simokitafresh/shogun-task-worktrees`、ext4 永続)で忍者を隔離。配備 wall 23s(ext4)。
4. **報告契約** 報告 YAML は `gate_report_format.sh` が整形・verdict 導出(binary_checks 全 yes→PASS)。偵察 cmd は finding 必須/commit 免除。lesson_candidate・decision_candidate・skill_candidate・origin を構造化。
5. **二段レビュー→GATE** 軍師 SG7 precheck/LGTM→家老 ACCEPT→`cmd_complete_gate.sh`(15,030 行、17 unit へ分割設計済)が commit 祖先・blob parity・CI readiness・context freshness を検査→CLEAR→archive→忍者 idle。gate_metrics.log に e2e/deploy/work/finalize 秒を記録。
6. **監視デーモン** `ninja_monitor.sh`: 陣形図(karo_snapshot)生成、STALL/ghost/UNACTIONED 検知、CTX 監視と自動 /clear・respawn、reflux 自動配備、Codex model/effort 実態≠settings の WARN。daemon_watchdog が watcher/monitor を自動再起動。
7. **multi-CLI** Claude Code(`.claude/hooks` 23 本、pinned 2.1.87=`~/bin/claude`)と Codex(`.codex/hooks.json`、exit 2=BLOCK)を CLI ごとに別実装で同じ成果基準へ。`/shogun-cli-switch` で CLI/model/version を idle pane だけ respawn して切替。Codex は device-auth でアカウント切替。
8. **スキル 41 本** `skills/*/SKILL.md` を正本に両 CLI で共用(cmd-complete/dashboard-update/db-check/codd/codd-refactor/dream/lesson-sort/shogun-teire/karo-direct/recon-dual/report-write/review-bundle/gate-sync/ninja-commit/verdict-check/x-research/weekly・monthly-report-writer/note-writer/sengoku-writer/pf-registration/three-layer-penetrate ほか)。description に TRIGGER/DO NOT TRIGGER 必須。
9. **CoDD**(Coherence-Driven Development、おしお殿作): spec→設計書→generate→validate→measure。bash script のリファクタは `/codd-refactor` で計測→設計→実装→再計測。
10. **テスト** bats 242 ファイル(`tests/unit`)、`run_tests.sh task|file|affected` の選択実行が原則(unit 全量 2454s vs 選択数秒)。CI は GitHub Actions で shard 実行+receipt、SKIP=FAIL、timing ledger で shard 割当。孤児テスト検知(Gate 10.07)と `orphan_test_reap.sh`。default-delete test policy(contract test だけ残す)。
11. **速度計測器が常設** `logs/defense_overhead.jsonl`(hook/gate wall)、`gate_metrics.log`、pre_push ledger、deploy receipt、publish phase 計装。らせん最適(計測器の名指し→直す→一段深く計測→計測器は本番に残す)。
12. **三層記憶+deepdive 追体験** 起動時に `gate_*_startup.sh` が Memory 健全度・未読・PD・deepdive receipt を一括チェック。`deepdive_replay.sh` で Phase 単位に追体験(結論だけ読むと同じ間違いに戻るため全文が残る)。
13. **殿インターフェース** `dashboard.md`(殿が自分で見る)、戦況 artifact(claude.ai/code/artifact、将軍が 30 分 loop で再公開)、ntfy(スマホ通知、`scripts/ntfy.sh`)、Android アプリ v6.4(SSH で tmux 操作+音声入力)、gist 共有(`gist_share.sh`、新規作成は GIST_ALLOW_CREATE=1 必須=歴史修正防止)。
14. **安全弁** Tier1 絶対禁止(D001-D009: rm -rf / push --force / reset --hard / kill / chrome --headless 無プロファイル 等)、Tier2 停止報告、YAML dump 禁止 hook、DB 直接接続 BLOCK(`/db-check`)、指揮官の git commit 直書き禁止(`ninja_scope_commit.sh -m -- <paths>`)、歴史修正禁止(created_at/ts は SSOT)。
15. **外部プロジェクト管理** `config/projects.yaml`+`projects/{id}.yaml`(git-ignored、PI/UUID/DB ルール)+`context/{project}.md`(索引層)+`docs/research/*.md`(詳細層、Vercel スタイル)。現 focus=dm-signal(Deterioration Monitor 本番稼働)。
16. **9p→ext4 移設(2026-08-27)** `scripts/migrate_to_ext4_{relocate,cutover,rollback}.sh` と runbook(`docs/research/9p_root_fix_runbook_20260827.md`)。効果は §6。

## 6. 速度(2026-08-27 実測、`docs/research/ext4_speed_rebaseline_20260827.md`)

| 指標 | 9p(/mnt/c) | ext4(/home) |
|---|---|---|
| git status | 60-120s | 84ms |
| cmd publish | 3770ms | 227ms |
| scope_commit git_commit / scope_sync | 9487 / 5846ms | 173 / 73ms |
| deploy_task 配備 | 199-397s | 23s |
| cmd e2e(deploy→GATE CLEAR) | 中央値 40 分 | 31 分(残る支配項=報告整形→レビュー→ACCEPT の人手往復) |
| 1 日の GATE CLEAR | 28 件/13h | 5 件/67 分(母数小) |

## 7. Quick Start の骨子(cmd_4410 が現物突合で本文化。本節は要件)

1. 前提: WSL2/Ubuntu(または Linux)、git、tmux、node/npm(nvm)、python3、jq、gh、`inotify-tools`、bats(テスト実行時)。Windows ドライブ(/mnt/c)には置かない(9p が律速、§6)。
2. 取得: `git clone https://github.com/simokitafresh/multi-agent-shogun.git ~/multi-agent-shogun`(任意パス)。**ZIP 展開でも可**(GitHub に入れない環境)。ZIP は `.git` が無いので、展開後に `git init && git remote add origin …`(cmd_4410 AC3 で実手順を確定)。
3. `bash first_setup.sh`: 依存の冪等インストール、`config/settings.yaml` の対話設定(ntfy topic、gist、CLI 選択)。殿固有値は README に書かない。
4. 初回認証(初回のみ): Claude Code=`~/bin/claude`(pinned 2.1.87)で OAuth ログイン+Bypass Permissions 承認→`/exit`。Codex=`codex login --device-auth`(スマホ完結、要「デバイスコード認証」有効化)。確認=`claude --version` / `codex --version` と最初の起動バナー。別ユーザー(家族含む)は自分のアカウントで入る。
5. `./shutsujin_departure.sh`: tmux セッション `shogun`(window 1=将軍、window 2=agents 8 pane)と watcher/monitor を起動。`Ctrl+A → 0/1` で切替。
6. 最初の 1 コマンド: 将軍 pane に日本語で指示(例「readme を読んで現状を報告せよ」)。将軍が cmd を起票し家老へ委任、忍者の報告→GATE CLEAR→ntfy 通知。

## 8. ファイル構成(現行・主要のみ)

```
CLAUDE.md / AGENTS.md      恒久ルール(Claude/Codex 同期・非一本化)
instructions/               役割別ルール(shogun/karo/gunshi/ashigaru)+generated/
config/settings.yaml        編成の正本(CLI/model/launch_cmd)、projects.yaml、cli_profiles.yaml
queue/                      shogun_to_karo.yaml(cmd)/tasks/{ninja}.yaml/reports/inbox/insights.yaml/bulletin_board.yaml/karo_snapshot.txt
scripts/ (243) + scripts/gates/ (58) + scripts/lib/   起票・配備・監視・ゲート・計測
skills/ (41)                両 CLI 共用スキル
tests/unit/ (242 bats)      契約テスト
context/                    索引層(project/infra/growth-loop/semantic-map)   docs/research/ (1063) 詳細層
memory/                     deepdive_*.md(追体験原本)、dialogue_*.md(研究日誌)
data/multi_agent_shogun_memory.db   記憶DB     logs/   gate_metrics/defense_overhead/deploy_task
docs/dashboard/             戦況 artifact の HTML 正本     android/   Android アプリ
```

## 9. 忍者(cmd_4410)への注記

- 本書は**参照原本**。現物(first_setup.sh/shutsujin_departure.sh/settings.yaml/scripts)と食い違う箇所は現物を正とし、差分を報告 YAML の finding に残す。
- 数値は本書の日付のもの。README には「2026-08-27 時点」と日付を付けて書く。
- 殿固有値(ntfy topic・gist URL・アカウント)は書かない。cmd_4409 完了後はユーザー固有パスも 0 件が前提。

## 10. OSS 化に向けた危険点と改修点

前提(殿の方針 2026-08-27 23:29): 個人使用が原則だが OSS にも対応する。今の multi-agent-shogun はそのまま、OSS 用に新リポジトリを将来作る。

方針: **現リポジトリは殿の運用正本のまま触らず、OSS 版は「エクスポート」で作る**(履歴ごと公開しない=過去 16,555 commit の中の個人情報を追跡できない。歴史修正禁止の原則とも整合)。以下は将軍の一次確認(2026-08-27 23:29)に基づく棚卸し。

### 10.1 危険点(公開してはいけないもの・一次確認値)

| # | 危険 | 現物 | OSS 版での扱い |
|---|---|---|---|
| 1 | 殿との全対話・裁定・個人事情 | `queue/lord_conversation.jsonl`(408K、git 追跡外だが実体あり)、`data/multi_agent_shogun_memory.db`(1.23GB、記憶DB)、`memory/`、`logs/`(1.0GB) | **含めない**。OSS 版は空の DB を初期化する `first_setup` に |
| 2 | クリニック・家族・メール等の個人情報 | git 追跡ファイルのうち `clinic/karasuyama/dm-signal` を含むもの 35 件(context/dm-signal*.md、skills/db-check・weekly/monthly-report-writer、docs/research 多数)、CLAUDE.md の `gws デフォルト=simokitafresh@gmail.com`、settings.yaml の `ntfy_topic: shogun-simokitafresh` | **除外または汎用化**。PJ 固有 context/skills は OSS 版から外す(PJ は `config/projects.yaml` で外付け) |
| 3 | 外部プロジェクトの秘密 | `projects/`(git-ignored: PI/UUID/DB ルール)、DM-signal の Render サービス ID・DB 接続(`context/auto-ops.md`、`context/dm-signal-ops.md`) | 含めない。`.gitignore` は OSS 版で再設計 |
| 4 | 認証情報・トークンの経路 | `~/.codex/auth.json`(全 Codex 共有)、gh auth、ntfy topic(推測されると通知を覗ける)、gist 一覧(`gist-index.md` に非公開 gist の ID) | README には「各自のアカウントで」とだけ書く。gist index は公開しない |
| 5 | 破壊的権限で動く前提 | 全 CLI が `--dangerously-skip-permissions` / `--dangerously-bypass-approvals-and-sandbox` / `--dangerously-bypass-hook-trust` で起動(settings.yaml/cli_profiles.yaml) | README 冒頭に**明示的な警告**(専用マシン/VM 推奨、Tier1 禁止リスト D001-D009 は hook で強制していることを説明) |
| 6 | tmux send-keys と自動 nudge | 他人のセッションに文字列が流れうる(T74 事故: 検証が本番 tmux を汚染) | 隔離条件(session 名・AGENTS_WINDOW_TARGET)を既定で安全側に。OSS 版では単一 session 固定 |
| 7 | ユーザー固有パス・ユーザー名 | `/home/simokitafresh` 36 ファイル(cmd_4409 で除去中)、GitHub `simokitafresh/*` の URL(config/projects.yaml、README バッジ) | cmd_4409 完了が前提。URL は OSS 版のリポジトリへ |
| 8 | Windows 固有・drvfs 前提 | `install.bat`、`/mnt/c` 前提の記述、`reset_layout`/`mntc_remount` 系 | 「Linux/WSL2 の ext4 上で動かす」を唯一の前提に(§6 の実測が根拠) |
| 9 | 日本語固定・戦国用語 | CLAUDE.md『Always respond in japanese』、役名(将軍/家老/軍師/忍者)、殿裁定の引用が instructions に多数 | 用語集(§2)を README に置く。言語は `config/settings.yaml: language` で切替可能にする |
| 10 | ライセンスと帰属 | MIT(LICENSE 実在)。fork 元 `yohey-w`、CoDD=おしお殿、Autoresearch 派生 | クレジット節を維持。第三者コード(CoDD 等)のライセンス確認 |

### 10.2 改修点(OSS 版を作る前に現リポジトリ側で済ませるもの)

1. **cmd_4409**: ユーザー固有絶対パス 0 件(進行中)。
2. **cmd_4410**: README/README_ja を現物から書き直し、隔離 clone(git/ZIP)で再現(進行中)。
3. **設定の分離**: `config/settings.yaml` を「公開してよい既定(`settings.example.yaml`)」と「ローカル上書き(`settings.local.yaml`、git-ignored)」に分け、`first_setup.sh` が対話で local を生成する。ntfy topic・gist・email・外部 PJ パスは local 側のみ。
4. **PJ 固有物の外出し**: `context/dm-signal*.md`、`skills/{db-check,weekly-report-writer,monthly-report-writer,pf-registration,gs-bench-gate,x-research}`、`docs/research` の PJ 文書を「PJ パック」として `projects/<id>/` 配下(git-ignored)へ移せる構造に。CLAUDE.md の Current Project 節は生成物にする。
5. **教訓・deepdive の匿名化**: `projects/infra/lessons_*.yaml`、`memory/deepdive_*.md`、`instructions/*.md` の殿発言引用は OSS 版では「原則+日付」だけ残し固有名詞を落とす(殿の対話の全文は残さない)。
6. **危険権限の説明と選択肢**: `--dangerously-*` を使わない「安全モード」起動プロファイルを `cli_profiles.yaml` に 1 つ用意(hook が確認プロンプトを扱えるかは T78 の型で検証)。
7. **エクスポート script**: `scripts/oss_export.sh`(新規・OSS 版作成時のみ)で「含めるパスの allowlist→固有名詞 grep 0 件→空 DB 初期化→新リポジトリへ 1 commit」を機械化。allowlist 外は出さない(fail-closed)。grep 対象語: ユーザー名、メール、ntfy topic、gist ID、Render ID、クリニック名、家族に関する語。
8. **CI の秘密**: GitHub Actions の secrets 依存(gh token 等)を OSS 版では不要にし、fork でも GREEN になる workflow に。
9. **Android アプリ**: SSH 鍵と接続先を持つため、OSS 版では「任意コンポーネント」として分離(別 README)。
10. **記憶DB スキーマの初期化**: `context/memory-db-schema.md` から空 DB を作る初期化 script(現状は運用 DB をそのまま前提)。

### 10.3 OSS 版で「そのまま公開できる」核

鎖(§2)、三層学習ループ(§3)、三層記憶の仕組み(§4、DB は空)、mailbox/watcher、cmd 起票ゲート、deploy_task の worktree 隔離、報告契約、二段レビュー→GATE、ninja_monitor、multi-CLI の hook 分離、スキル機構、テスト方針(default-delete/選択実行/shard)、Tier1-3 安全弁、ext4 runbook。**個人・PJ 固有の"中身"を抜いても、仕組みは全て残る。**
