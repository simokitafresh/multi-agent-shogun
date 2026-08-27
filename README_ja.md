<div align="center">

# multi-agent-shogun

**AIコーディング軍団統率システム — Multi-CLI対応**

*戦国軍制で9体のAIエージェントを並列運用 — **Claude Code / OpenAI Codex** をYAML・tmux・イベント駆動メールボックスで統率*

**Talk Coding — Vibe Codingではなく、ターミナル・スマホ・Androidコンパニオンから指揮する**

[![GitHub Stars](https://img.shields.io/github/stars/simokitafresh/multi-agent-shogun?style=social)](https://github.com/simokitafresh/multi-agent-shogun)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Formation](https://img.shields.io/badge/formation-config%2Fsettings.yaml-ff6600?style=flat-square)](https://github.com/simokitafresh/multi-agent-shogun)
[![GATE CLEAR](https://img.shields.io/badge/GATE%20CLEAR-465%2F467%20(99.6%25)-2d7d46?style=flat-square)](https://github.com/simokitafresh/multi-agent-shogun)
[![Shell](https://img.shields.io/badge/Shell%2FBash-100%25-green)]()

[English](README.md) | [日本語](README_ja.md)

</div>

<!-- <p align="center">
  <img src="assets/screenshots/tmux_shogun_9panes.png" alt="multi-agent-shogun: 9ペインが並列稼働" width="800">
</p> -->

<p align="center"><i>家老1体が config/settings.yaml の現行混成編成を統率 — 実際の稼働画面、モックデータなし</i></p>

---

## これは何？

**multi-agent-shogun** は、実運用向けのマルチエージェント開発基盤です。現行の生きた編成は以下です。

- 将軍 + 家老: **Claude Code / Opus**
- エージェントのCLI・モデル・起動パス: **config/settings.yaml / config/cli_profiles.yaml** を正本とする
- 影丸・半蔵・小太郎・飛猿: **Claude Code / Opus**

**なぜ使うのか？**
- 1つの命令で**10体のエージェント**を起動し、すぐ制御が戻る
- ワーカー間連携は **YAML + tmux**。APIオーケストレーション費用を増やさない
- **GATEシステム**、**教訓サイクル**、**PDシステム**、**cmd年代記** を内蔵
- **ntfy**、**Tailscale/Termux/mosh**、**Androidコンパニオン**で外出先から指揮可能
- 待ち時間なし - タスクがバックグラウンドで実行中も次の命令を出せる
- AIがセッションを跨いであなたの好みを記憶（将軍のMemory MCP）
- ダッシュボードと `queue/karo_snapshot.txt` でリアルタイム進捗確認

```
      あなた（上様）
           │
           ▼ 命令を出す
    ┌─────────────┐
    │   SHOGUN    │  ← 命令を受け取り、即座に委譲
    └──────┬──────┘
           │ YAMLファイル + tmux
    ┌──────▼──────┐
    │    KARO     │  ← タスクをワーカーに分配
    └──────┬──────┘
           │
  ┌─┬─┬─┬─┴─┬─┬─┬─┐
  │1│2│3│4│5│6│7│8│  ← 8体のワーカーが並列実行
  └─┴─┴─┴─┴─┴─┴─┴─┘
       NINJA
```

---

## 現在の運用実績

| 指標 | 値（2026-08-27 実測） |
|---|---|
| 発令 cmd 数 | 4,410 |
| GATE CLEAR | 本日 49 件（gate_metrics.log） |
| git 履歴 | 16,555 commit（2026-02-09 初 commit〜） |
| `git status` | 84ms（ext4。移設前の 9p では 60〜120 秒） |
| 配備 1 件（deploy_task） | 23 秒（移設前 199〜397 秒） |
| cmd e2e（配備→GATE CLEAR）中央値 | 31 分（うち人手レビュー往復が 4〜16 分） |

上記は `logs/gate_metrics.log` / `logs/deploy_task.log` / `docs/research/ext4_speed_rebaseline_20260827.md` に基づく。

---

## なぜ Shogun なのか？

多くのマルチエージェントフレームワークは、連携のためにAPIトークンを消費します。Shogunは違います。

| | Claude Code `Task` ツール | LangGraph | CrewAI | **multi-agent-shogun** |
|---|---|---|---|---|
| **アーキテクチャ** | 1プロセス内のサブエージェント | グラフベースの状態機械 | ロールベースエージェント | tmux経由の階層構造 |
| **並列性** | 逐次実行（1つずつ） | 並列ノード（v0.2+） | 限定的 | **8体の独立エージェント** |
| **連携コスト** | TaskごとにAPIコール | API + インフラ（Postgres/Redis） | API + CrewAIプラットフォーム | **ゼロ**（YAML + tmux） |
| **可観測性** | Claudeのログのみ | LangSmith連携 | OpenTelemetry | **ライブtmuxペイン** + ダッシュボード |
| **スキル発見** | なし | なし | なし | **ボトムアップ自動提案** |
| **セットアップ** | Claude Code内蔵 | 重い（インフラ必要） | pip install | シェルスクリプト |

### 他のフレームワークとの違い

**連携コストゼロ** — エージェント間の通信はディスク上のYAMLファイル。APIコールは実際の作業にのみ使われ、オーケストレーションには使われません。8体のエージェントを動かしても、支払うのは8体分の作業コストだけです。

**完全な透明性** — すべてのエージェントが見えるtmuxペインで動作。すべての指示・報告・判断がプレーンなYAMLファイルで、読んで、diffして、バージョン管理できます。ブラックボックスなし。

**実戦で鍛えた階層構造** — 将軍→家老→忍者の指揮系統が設計レベルで衝突を防止：明確な責任分担、エージェントごとの専用ファイル、イベント駆動通信、ポーリングなし。

---

## この fork の独自性

| 機能 | このrepoでの意味 |
|---|---|
| **知識7層** | system rules、役割別指示、project core、project lessons、live YAML、Vercelスタイルcontext、Memory MCP を分離管理 |
| **Vercelスタイル context** | `context/*.md` は索引層、深い調査は `docs/research/` に逃がしてリンクで戻す |
| **教訓サイクル** | 教訓をタスクへ注入し、参照し、GATE後に評価し、効かないものは自動退役する |
| **GATEシステム** | `cmd_complete_gate.sh`、`gate_cmd_state.sh`、`gate_lesson_health.sh` が false done や stale state を止める |
| **karo_snapshot** | `queue/karo_snapshot.txt` で compact 復帰後も陣形図を即再構築できる |
| **PDシステム** | `queue/pending_decisions.yaml` で未裁定事項を管理する |
| **cmd年代記** | `context/cmd-chronicle.md` が直近cmdの履歴を低コストで保持する |
| **Androidコンパニオン** | `android/` に Kotlin + Jetpack Compose 製アプリを同梱。SSH制御と ntfy 通知を1台に集約 |

---

## なぜCLI（APIではなく）？

多くのAIコーディングツールはトークン従量課金。8体のOpus級エージェントをAPI経由で動かすと**$100+/時間**。CLI定額サブスクはこれを逆転させる：

| | API（従量課金） | CLI（定額制） |
|---|---|---|
| **8エージェント × Opus** | ~$100+/時間 | ~$200/月 |
| **コスト予測性** | 予測不能なスパイク | 月額固定 |
| **使用時の心理** | 1トークンが気になる | 使い放題 |
| **実験の余地** | 制約あり | 自由に投入 |

**「AIを使い倒す」思想** — 定額CLIサブスクなら、8体の忍者を気兼ねなく投入できる。1時間稼働でも24時間稼働でもコストは同じ。「まあまあ」と「徹底的に」の二択で悩む必要がない — エージェントを増やせばいい。

### Multi-CLI対応

将軍システムは特定ベンダーに依存しない。4つのCLIツールに対応し、それぞれの強みを活かす：

| CLI | 特徴 | デフォルトモデル |
|-----|------|-----------------|
| **Claude Code** | tmux統合の実績、Memory MCP、専用ファイルツール（Read/Write/Edit/Glob/Grep） | Claude Opus 4.6 |
| **OpenAI Codex** | サンドボックス実行、JSONL構造化出力、`codex exec` ヘッドレスモード | gpt-5.5 |
| **GitHub Copilot** | GitHub MCP組込、4種の特化エージェント（Explore/Task/Plan/Code-review）、`/delegate` | Provider-managed |
| **Kimi Code** | 無料プランあり、多言語サポート | Kimi k2 |

統一ビルドシステムが共有テンプレートからCLI固有の指示書を自動生成：

```
instructions/
├── common/              # 共通ルール（全CLI共通）
├── cli_specific/        # CLI固有のツール説明
│   ├── claude_tools.md  # Claude Code ツール・機能
│   └── copilot_tools.md # GitHub Copilot CLI ツール・機能
└── roles/               # ロール定義（将軍、家老、忍者）
    ↓ ビルド
CLAUDE.md / AGENTS.md / copilot-instructions.md  ← CLI別に生成
```

ルールの変更は1箇所。全CLIに反映。同期ズレなし。

---

## ボトムアップスキル発見

他のフレームワークにはない機能です。

忍者がタスクを実行する中で、**再利用可能なパターンを自動的に発見**し、スキル候補として提案します。家老が提案を `dashboard.md` に集約し、殿（あなた）が正式なスキルに昇格させるか判断します。

```
忍者がタスクを完了
    ↓
気づき: 「このパターン、3つのプロジェクトで同じことをした」
    ↓
YAMLで報告:  skill_candidate:
                 found: true
                 name: "api-endpoint-scaffold"
                 reason: "3プロジェクトで同じRESTスキャフォールドパターンを使用"
    ↓
dashboard.md に掲載 → 殿が承認 → .claude/commands/ にスキル作成
    ↓
全エージェントが /api-endpoint-scaffold を呼び出し可能に
```

スキルは実際の作業から有機的に成長します — 既製のテンプレートライブラリからではなく。スキルセットは**あなた自身**のワークフローの反映になります。

---

## 🚀 クイックスタート

> 2026-08-27 時点の現物（`first_setup.sh` / `shutsujin_departure.sh` / `config/settings.yaml`）から書き起こした手順。対応環境は **WSL2(Ubuntu) または Native Linux**。リポジトリは必ず **ext4 上（`~/` 配下など）** に置く。Windows ドライブ（`/mnt/c/...`）は 9p ファイルシステム経由で `git status` が 60〜120 秒かかり、実用にならない（実測は「速度」節）。

### Step 1: 前提ツール

| ツール | 用途 | 確認 |
|---|---|---|
| git, tmux, jq, curl, flock, timeout, setsid, crontab | 基盤 | `first_setup.sh` が確認し、不足分は apt で補完を試みる |
| node/npm（nvm 推奨）, python3 | Claude Code / Codex CLI、ゲート群 | 同上 |
| gh（GitHub CLI）, inotify-tools, bats | CI 確認、inbox 監視、テスト | 同上 |

### Step 2: 取得（git clone または ZIP）

```bash
# A. git（通常）
git clone https://github.com/<owner>/multi-agent-shogun.git ~/multi-agent-shogun

# B. ZIP（GitHub に入れない環境）
#   GitHub の「Code → Download ZIP」を ext4 上に展開し、展開先で:
git init && git add -A && git commit -m "import" && git remote add origin https://github.com/<owner>/multi-agent-shogun.git
```

ZIP には `.git` が無い。ゲート群は git を前提にするため、B では上の 1 行で最小のリポジトリを作る。

### Step 3: 初回セットアップ

```bash
cd ~/multi-agent-shogun
bash first_setup.sh        # 依存・venv・Codex CLI・config・ディレクトリ・Memory MCP を冪等に確認/補完
source ~/.bashrc           # PATH 反映
```

- 対話は「ネイティブ版をインストールしますか? [Y/n]」の 1 問のみ。
- `config/settings.yaml` は **無い場合だけ** 最小設定を生成し、既存は保持する。ntfy トピック・使用 CLI・モデルは `config/settings.yaml` を直接編集する（対話入力は無い）。
- 所要時間はネットワークとインストール量に依存する。

### Step 4: 初回認証（初回のみ・各自のアカウントで）

```bash
# Claude Code（pinned 版 ~/bin/claude を使う）
~/bin/claude --dangerously-skip-permissions
#   → ブラウザで OAuth ログイン → "Bypass Permissions" は「Yes, I accept」を選択 → /exit
claude auth status            # loggedIn=True を確認

# Codex CLI（スマホ完結の device-auth。アカウント側で「デバイスコード認証」を有効化しておく）
codex login --device-auth
codex login status            # "Logged in using ChatGPT" を確認
```

家族など別の利用者は、それぞれ自分の Anthropic / ChatGPT アカウントで入る。認証情報は `~/.claude` と `~/.codex/auth.json` に置かれ、リポジトリには入らない。

### Step 5: 出陣

```bash
./shutsujin_departure.sh
```

tmux セッション `shogun` に window **`main`**（将軍）と **`agents`**（家老・軍師・忍者 6 = 8 pane）を作り、inbox watcher・ninja_monitor・ntfy などのデーモンを起動する。window 番号は tmux の `base-index` 設定で 0/1 または 1/2 になるため、切替は **名前** で行う。CLI の起動確認は最大 30 秒。

```bash
tmux attach -t shogun
# Ctrl+A → w でウィンドウ一覧、または Ctrl+A → :select-window -t main / agents
```

### Step 6: 最初の 1 コマンド

将軍 pane に日本語で指示する（例: `readme を読んで現状を報告せよ`）。将軍が cmd を起票し家老へ委任、忍者が task worktree で作業して報告 YAML を提出、軍師レビュー→家老 GATE→CLEAR→ntfy 通知、の順に進む。

### 📱 Android アプリ（任意）

SSH 経由で tmux を操作し音声入力できるコンパニオンアプリが `android/` にある。接続先は `whoami` / `pwd` の値をアプリの設定に入れる。詳細は `android/README_ja.md`。

---

## 📖 基本的な使い方

### Step 1: 将軍に接続

`shutsujin_departure.sh` 実行後、全エージェントが自動的に指示書を読み込み、作業準備完了となります。

新しいターミナルを開いて将軍に接続：

```bash
tmux attach-session -t shogun
```

### Step 2: 最初の命令を出す

将軍は既に初期化済み！そのまま命令を出せます：

```
JavaScriptフレームワーク上位5つを調査して比較表を作成せよ
```

将軍は：
1. タスクをYAMLファイルに書き込む
2. 家老（管理者）に通知
3. 即座にあなたに制御を返す（待つ必要なし！）

その間、家老はタスクを忍者ワーカーに分配し、並列実行します。

### Step 3: 進捗を確認

エディタで `dashboard.md` を開いてリアルタイム状況を確認：

```markdown
## 🔗 鎖・三層学習ループ・三層記憶

### 鎖（指揮の一本道）

殿 → 将軍 → 家老 → 忍者。分岐なし、迂回なし。将軍は決め、家老は仕切り、忍者は遂げ、軍師はレビューする。**鎖は命令の道であると同時に学びの還流路**で、忍者の `lesson_candidate` が家老を経て教訓→ゲート→テスト fixture に入る。鎖を迂回すると指示が消え、同時に学びも消える（正本: `CLAUDE.md` 先頭、`instructions/*.md`）。

### 三層学習ループ

全ての作業に「①実行 → ②二値計測 → ③知見還流 → 次サイクル強化」を回す。スコープが三層ある。

| 層 | スコープ | 実装 |
|---|---|---|
| 個 | ロール内 | AC ごとの `binary_checks`（yes/no）、洗脳 8 パターン自己検査、起動時の deepdive 追体験（Phase 単位 replay と receipt） |
| 対 | 忍者+家老 / 家老+軍師 | 報告 YAML → 軍師 SG7 レビュー → 家老 GATE の往復、rework 率の計測 |
| 全 | 鎖全体 | reflux（`queue/insights.yaml` の気づきを idle 忍者へ自動配備）、教訓の淘汰、`gate_metrics` の日次 before/after、CI GREEN 維持 |

`/clear` は「強くてニューゲーム」。会話のコンテキストが 0 に戻っても、知識基盤（`CLAUDE.md`・`instructions/`・教訓・記憶DB・runbook）が残るので、次は前より強い状態で再開する。原則は「削るな、速くしろ」— ゲートを減らすのではなく、品質を保ったまま速くする（正本: `context/growth-loop.md`、`docs/research/three-layer-learning-loop-auto-growth-asis-tobe-5w1h_20260707.md`）。

### 三層記憶

| 層 | 実体 | 入口 |
|---|---|---|
| 記憶DB | SQLite `data/multi_agent_shogun_memory.db`（対話・裁定・knowledge・復帰点 `session_save_*`、FTS5） | `bash scripts/memory_db_query.sh --search "<語>"` / 書込み `scripts/memory_db_knowledge_write.sh` |
| セマンティック索引 | `context/semantic-map.md` + `docs/semantic-index/index.md`（概念・alias・discussion） | `bash scripts/semantic_search.sh "<query>"` |
| Obsidian 因果ネットワーク | `[[リンク]]` と `origin: "[[発端]] -> [[原因]] -> [[結果]]"`（教訓・報告・cmd に必須） | `.cache/causal_index.tsv`、`/three-layer-penetrate` |

契約: 作業の前に三層を検索する（hook が preflight を自動注入）。殿への応答には `[MEM: …]` の引用タグを付ける（欠落は stop hook が止める）。新しい知識は三層すべてへ貫通させる（正本: `context/memory-db-schema.md`、`docs/research/semantic_index_design.md`）。

---

## 進行中## 進行中
| ワーカー | タスク | 状態 |
|----------|--------|------|
| Sasuke | React調査 | 実行中 |
| Kirimaru | Vue調査 | 実行中 |
| Hayate | Angular調査 | 完了 |
```

### 詳細なフロー

```
あなた: 「トップ5のMCPサーバを調査して比較表を作成せよ」
```

将軍がタスクを `queue/shogun_to_karo.yaml` に書き込み、家老を起動。あなたには即座に制御が戻ります。

家老がタスクをサブタスクに分解：

| ワーカー | 割当内容 |
|----------|----------|
| Sasuke | Notion MCP調査 |
| Kirimaru | GitHub MCP調査 |
| Hayate | Playwright MCP調査 |
| Kagemaru | Memory MCP調査 |
| Hanzo | Sequential Thinking MCP調査 |

5体の忍者が同時に調査開始。リアルタイムで作業を見ることができます。

結果は完了次第 `dashboard.md` に表示されます。

---

## ✨ 主な特徴

2026-08-27 時点の現物ベース。旧版（2026-02〜03）にあった「send-keys で指示」「Claude 単一」「手動で結果確認」は全て置き換わっている。

1. **mailbox 通信** — `scripts/inbox_write.sh <to> "<msg>" <type> <from> <action>`。flock 付き YAML に永続化し、`inbox_watcher.sh`（inotify）が `inboxN` の短い nudge だけを送る。エージェントは tmux send-keys を呼ばない。確認プロンプト検知で nudge 抑止、Codex 配達検証、未読が続けば再 nudge。
2. **cmd 起票ゲート** — `cmd_skeleton.sh` → `cmd_save.sh --preflight` → `cmd_save.sh` → `cmd_delegate.sh`。82 の check 関数（品質問答 q1-q12、AC の二値性、パス実在、テスト契約、environment_change）で BLOCK/WARN。BLOCK は「次の cmd で BLOCK されないよう環境へ埋め込む」成長ループの入口。
3. **配備と隔離** — `deploy_task.sh` が task YAML を生成し、関連教訓と関連概念を push 注入、忍者を **task worktree**（ext4 上、再起動でも消えない）で隔離する。配備 23 秒。
4. **報告契約** — `gate_report_format.sh` が報告 YAML を整形し verdict を導出（`binary_checks` 全 yes → PASS）。偵察 cmd は finding 必須・commit 免除。`lesson_candidate` / `decision_candidate` / `origin` を構造化。
5. **二段レビュー → GATE** — 軍師 SG7 precheck/LGTM → 家老 ACCEPT → `cmd_complete_gate.sh`（commit 祖先・blob parity・CI readiness・context freshness）→ CLEAR → archive → 忍者 idle。`gate_metrics.log` に e2e/deploy/work/finalize 秒を記録。
6. **監視デーモン** — `ninja_monitor.sh`: 陣形図生成、STALL/ghost/UNACTIONED 検知、CTX 監視と自動 /clear・respawn、reflux 自動配備、Codex の model/effort が設定と違えば WARN。`daemon_watchdog` が watcher/monitor を自動再起動。
7. **multi-CLI** — Claude Code（`.claude/hooks/` 23 本、pinned 2.1.87 = `~/bin/claude`）と Codex（`.codex/hooks.json`、exit 2 = BLOCK）を CLI ごとに別実装で同じ成果基準へ。`/shogun-cli-switch` で CLI/model を idle pane だけ respawn して切替。編成の唯一の正は `config/settings.yaml`。
8. **スキル 41 本** — `skills/*/SKILL.md` を正本に両 CLI で共用。description に TRIGGER / DO NOT TRIGGER 必須。
9. **CoDD** — Coherence-Driven Development（おしお氏作）。spec → 設計書 → generate → validate → measure。bash script のリファクタは `/codd-refactor` で計測→設計→実装→再計測。
10. **テスト** — bats 242 ファイル。`run_tests.sh task|file|affected` の選択実行が原則（全量 2,454 秒 vs 選択数秒）。CI は shard 実行+受領書、SKIP=FAIL、timing ledger で shard 割当。孤児テスト検知と回収。contract test だけ残す default-delete ポリシー。
11. **計測器の常設** — `logs/defense_overhead.jsonl`（全 hook の wall）、`gate_metrics.log`、pre_push ledger、deploy receipt、publish phase 計装。「計測器を名指す → 直す → 一段深く計測する → 計測器は本番に残す」のらせん。
12. **三層記憶 + deepdive 追体験** — 起動時に `gate_*_startup.sh` が Memory 健全度・未読・未決裁定・deepdive receipt を一括チェック。結論だけ読むと同じ間違いに戻るため、過程の全文を Phase 単位で追体験する。
13. **殿インターフェース** — `dashboard.md`（殿が自分で見る）、戦況 artifact（将軍が 30 分ごとに再公開）、ntfy（スマホ通知）、Android アプリ、gist 共有（新規作成は明示フラグ必須 = 歴史修正防止）。
14. **安全弁** — Tier1 絶対禁止（`rm -rf` 系、`push --force`、`reset --hard`、`kill`、プロファイル無しの headless Chrome ほか）、Tier2 停止報告、YAML dump 禁止 hook、DB 直接接続 BLOCK、指揮官の `git commit` 直書き禁止（`ninja_scope_commit.sh`）、歴史修正禁止。
15. **外部プロジェクト管理** — `config/projects.yaml` + `projects/{id}.yaml`（git-ignored の核心知識）+ `context/{project}.md`（索引層）+ `docs/research/*.md`（詳細層）。
16. **ext4 移設 runbook** — `scripts/migrate_to_ext4_{relocate,cutover,rollback}.sh` と `docs/research/9p_root_fix_runbook_20260827.md`。Windows ドライブから ext4 へ安全に移す手順と、移設後の副作用の突合表。

### 速度（2026-08-27 実測、`docs/research/ext4_speed_rebaseline_20260827.md`）

| 指標 | 9p(/mnt/c) | ext4(/home) |
|---|---|---|
| git status | 60〜120 秒 | 84ms |
| cmd publish | 3,770ms | 227ms |
| scope_commit git_commit / scope_sync | 9,487 / 5,846ms | 173 / 73ms |
| 配備 1 件 | 199〜397 秒 | 23 秒 |
| hook 1 回の中央値（全 hook） | 183ms | 90ms |

---

## 🗣️ SayTask — タスク管理が嫌いな人のためのタスク管理

### SayTaskとは？

**タスク管理が嫌いな人のためのタスク管理。スマホに話しかけるだけ。**

**Talk Coding — Vibe Codingではない。** タスクを話すだけで、AIが整理する。入力なし、アプリを開かない、摩擦ゼロ。

- **ターゲット**: Todoistをインストールしたけど3日で開かなくなった人
- あなたの敵は他のアプリじゃない。何もしないこと。競合は他の生産性ツールではなく、無行動
- UIゼロ。入力ゼロ。アプリを開く動作ゼロ。ただ話すだけ

> *「あなたの敵は他のアプリじゃない。何もしないことだ。」*

### 仕組み

1. [ntfyアプリ](https://ntfy.sh)をインストール（無料、アカウント不要）
2. スマホに話しかける: *「歯医者 明日」*、*「請求書 金曜まで」*
3. AIが自動整理 → 朝に通知: *「今日の予定です」*

```
 🗣️ 「牛乳買う、歯医者 明日、請求書 金曜まで」
       │
       ▼
 ┌──────────────────┐
 │  ntfy → 将軍     │  AIが自動分類、日付解析、優先度設定
 └────────┬─────────┘
          │
          ▼
 ┌──────────────────┐
 │   tasks.yaml     │  構造化ストレージ（ローカル、端末外に出ない）
 └────────┬─────────┘
          │
          ▼
 📱 朝の通知:
    「今日: 🐸 請求書期限 · 🦷 歯医者3時 · 🛒 牛乳買う」
```

### 変更前／変更後

| 変更前（v1） | 変更後（v2） |
|:-----------:|:----------:|
| ![タスク一覧 v1](images/screenshots/ntfy_tasklist_v1_before.jpg) | ![タスク一覧 v2](images/screenshots/ntfy_tasklist_v2_aligned.jpg) |
| 生のタスクダンプ | きれいに整理された日次サマリ |

> *注: スクリーンショットに表示されているトピック名は例です。自分専用のトピック名を使用してください。*

### ユースケース

- 🛏️ **ベッドの中**: *「明日レポート提出しないと」* — 忘れる前にキャプチャ、ノート探さなくていい
- 🚗 **運転中**: *「クライアントAの見積もり忘れないで」* — ハンズフリー、前を見たまま
- 💻 **仕事中**: *「あ、牛乳買わないと」* — 即座にダンプしてフローに戻る
- 🌅 **起床時**: 今日のタスクが既に通知で待っている — アプリを開かない、受信トレイ確認不要
- 🐸 **Eat the Frog**: AIが毎朝一番大変なタスクを選ぶ — 無視してもいいし、最初に倒してもいい

### FAQ

**Q: 他のタスクアプリと何が違う？**
A: アプリを開かない。ただ話すだけ。摩擦ゼロ。多くのタスクアプリは、人々が開かなくなるから失敗する。SayTaskはそのステップ自体を取り除いた。

**Q: Shogunシステム全体なしでSayTaskだけ使える？**
A: SayTaskはShogunの機能の一部。Shogunはスタンドアロンのマルチエージェント開発プラットフォームとしても機能する — 1つのシステムで両方の機能が手に入る。

**Q: 🐸 Frogって何？**
A: 毎朝、AIがあなたの一番大変なタスクを選ぶ — 避けたいやつ。最初に倒す（「Eat the Frog」方式）か無視するか。あなた次第。

**Q: 無料？**
A: すべて無料でオープンソース。ntfyも無料。アカウント不要、サーバ不要、サブスクリプション不要。

**Q: データはどこに保存される？**
A: ローカルのYAMLファイル。クラウドには何も送信されない。タスクは端末の外に出ない。

**Q: 「仕事のあれ」みたいに曖昧なことを言ったら？**
A: AIがベストを尽くして分類・スケジュールする。後で修正もできる — でもポイントは、忘れる前に思考をキャプチャすること。

### SayTask vs cmdパイプライン

将軍システムには2つの補完的なタスクシステムがある：

| 機能 | SayTask（音声レイヤー） | cmdパイプライン（AI実行） |
|---|:-:|:-:|
| 音声入力 → タスク作成 | ✅ | — |
| 朝の通知ダイジェスト | ✅ | — |
| Eat the Frog 🐸 選定 | ✅ | — |
| ストリーク追跡 | ✅ | ✅ |
| AI実行タスク（複数ステップ） | — | ✅ |
| 8エージェント並列実行 | — | ✅ |

SayTaskは個人の生産性を担当（キャプチャ → スケジュール → リマインド）。cmdパイプラインは複雑な作業を担当（リサーチ、コード、複数ステップのタスク）。両者はストリーク追跡を共有し、どちらのタスクを完了してもデイリーストリークにカウントされる。

---

## 🧠 モデル設定

| エージェント | モデル | 思考モード | 理由 |
|-------------|--------|----------|------|
| 将軍 | Opus | **有効（high）** | 殿との戦略議論・リサーチ・方針設計に深い推論が必要 |
| 家老 | Opus | 有効 | タスク分配には慎重な判断が必要 |
| Sasuke, Kirimaru, Hayate, Saizo | Codex | 有効 | 実装速度とローカル実行に強い |
| Kagemaru, Hanzo, Kotaro, Tobisaru | Opus | 有効 | 高曖昧度の調査・レビュー向け |

将軍は殿（人間）の参謀として、タスク中継だけでなく戦略議論・リサーチ分析・方針設計を行う。これらはBloom's Taxonomy の Level 4-6（分析・評価・創造）に該当し、Thinking有効が必須。中継のみに特化したい場合は `--shogun-no-thinking` オプションで無効化可能。

### 現行編成

| 部隊 | 現在のCLI / モデル | 備考 |
|------|--------------------|------|
| 将軍・家老 | Claude Code / Opus | 戦略・統制系 |
| Sasuke, Kirimaru, Hayate, Saizo | Codex / gpt-5.5 | Codex隊 |
| Kagemaru, Hanzo, Kotaro, Tobisaru | Claude Code / Opus | Opus隊 |

現行ローテーションは 2026-02-27 から継続中。配備は CLI 特性とタスク適性で決まる。

### Bloom's Taxonomy によるタスク分類

タスクはBloom's Taxonomy（ブルームの分類法）に基づいて分類し、最適なモデルに割り当てます：

| レベル | カテゴリ | 内容 | モデル |
|--------|----------|------|--------|
| L1 | 記憶 | 事実の想起、コピー、一覧化 | Codex |
| L2 | 理解 | 説明、要約、言い換え | Codex |
| L3 | 応用 | 手順の実行、既知パターンの実装 | Codex |
| L4 | 分析 | 比較、調査、構造の分解 | Opus |
| L5 | 評価 | 判断、批評、推奨 | Opus |
| L6 | 創造 | 設計、構築、新しいソリューションの統合 | Opus |

家老が各サブタスクにBloomレベルを付与し、適切なエージェント profile にルーティングします。定型的な repo 作業は Codex、曖昧性の高い推論やレビューは Opus を優先します。

### タスク依存関係（blockedBy）

タスクは `blockedBy` を使って他タスクへの依存を宣言できます：

```yaml
# queue/tasks/kirimaru.yaml
task:
  task_id: subtask_010b
  blockedBy: ["subtask_010a"]  # sasukeのタスク完了を待つ
  description: "subtask_010aで構築したAPIクライアントを統合"
```

ブロック元のタスクが完了すると、家老が自動的に依存タスクのブロックを解除し、空いている忍者に割り当てます。これにより待機時間が削減され、依存タスクの効率的なパイプライン処理が可能になります。

---

## 🧭 核心思想（Philosophy）

> **「脳死で依頼をこなすな。最速×最高のアウトプットを常に念頭に置け。」**

将軍システムは5つの核心原則に基づいて設計されている：

| 原則 | 説明 |
|------|------|
| **自律陣形設計** | テンプレートではなく、タスクの複雑さに応じて陣形を設計 |
| **並列化** | サブエージェントを活用し、単一障害点を作らない |
| **リサーチファースト** | 判断の前にエビデンスを探す |
| **継続的学習** | モデルの知識カットオフだけに頼らない |
| **三角測量** | 複数視点からのリサーチと統合的オーソライズ |

詳細: **[docs/philosophy.md](docs/philosophy.md)**

---

## 🎯 設計思想

### なぜ階層構造（将軍→家老→忍者）なのか

1. **即座の応答**: 将軍は即座に委譲し、あなたに制御を返す
2. **並列実行**: 家老が複数の忍者に同時分配
3. **単一責任**: 各役割が明確に分離され、混乱しない
4. **スケーラビリティ**: 忍者を増やしても構造が崩れない
5. **障害分離**: 1体の忍者が失敗しても他に影響しない
6. **人間への報告一元化**: 将軍だけが人間とやり取りするため、情報が整理される

### なぜメールボックスシステムなのか

1. **状態の永続化**: YAMLファイルで構造化通信し、エージェント再起動にも耐える
2. **ポーリング不要**: `inotifywait`はイベント駆動（カーネルレベル）なので、アイドル時のAPIコストゼロ
3. **割り込み防止**: エージェント同士やあなたの入力への割り込みを防止
4. **デバッグ容易**: 人間がinbox YAMLファイルを直接読んでメッセージフローを把握できる
5. **競合回避**: `flock`（排他ロック）で同時書き込みを防止 — 複数エージェントが同時送信してもレースコンディションなし
6. **配信保証**: ファイル書き込み成功 = メッセージ配信保証。到達確認不要、偽陰性なし、send-keys失敗による1.5時間ハングもなし
7. **nudge-only配信**: `send-keys`は短い起床通知のみ送信（timeout 5s）、メッセージ全文は送らない。エージェントが自分でinboxファイルをRead。旧方式（メッセージ全文をsend-keys送信）で発生した文字化け・1.5時間ハング等の配信障害を根絶。

### エージェント識別（@agent_id）

各ペインに `@agent_id` というtmuxユーザーオプションを設定（例: `karo`, `sasuke`）。`pane_index` はペイン再配置でズレるが、`@agent_id` は `shutsujin_departure.sh` が起動時に固定設定するため変わらない。

エージェントの自己識別:
```bash
tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}'
```
`-t "$TMUX_PANE"` が必須。省略するとアクティブペイン（操作中のペイン）の値が返り、誤認識の原因になる。

モデル名は `@model_name`、現在のタスクの要約は `@current_task` として保存され、いずれも `pane-border-format` で常時表示されます。Claude Codeがペインタイトルを上書きしても、これらのユーザーオプションは消えません。

### なぜ dashboard.md は家老のみが更新するのか

1. **単一更新者**: 競合を防ぐため、更新責任者を1人に限定
2. **情報集約**: 家老は全忍者の報告を受ける立場なので全体像を把握
3. **一貫性**: すべての更新が1つの品質ゲートを通過
4. **割り込み防止**: 将軍が更新すると、殿の入力中に割り込む恐れあり

---

## 🛠️ スキル

共有スキルは `skills/` に含まれます。ユーザー固有スキルは `.claude/skills/` または `~/.codex/skills/` に置け、`first_setup.sh` は既存ディレクトリを上書きしません。

スキルは `/スキル名` で呼び出し可能。将軍に「/スキル名 を実行」と伝えるだけ。

### スキルの思想

**1. 共有スキルとユーザー固有スキルを分離**

ユーザー固有の `.claude/commands/` 配下のスキルはリポジトリにコミットしない設計。理由：
- 各ユーザの業務・ワークフローは異なる
- 汎用的なスキルを押し付けるのではなく、ユーザが自分に必要なスキルを育てていく

**2. スキル取得の手順**

```
忍者が作業中にパターンを発見
    ↓
dashboard.md の「スキル化候補」に上がる
    ↓
殿（あなた）が内容を確認
    ↓
承認すれば家老に指示してスキルを作成
```

スキルはユーザ主導で増やすもの。自動で増えると管理不能になるため、「これは便利」と判断したものだけを残す。

---

## 🔌 MCPセットアップガイド

MCP（Model Context Protocol）サーバはClaudeの機能を拡張します。セットアップ方法：

### MCPとは？

MCPサーバはClaudeに外部ツールへのアクセスを提供します：
- **Notion MCP** → Notionページの読み書き
- **GitHub MCP** → PR作成、Issue管理
- **Memory MCP** → セッション間で記憶を保持

### MCPサーバのインストール

以下のコマンドでMCPサーバを追加：

```bash
# 1. Notion - Notionワークスペースに接続
claude mcp add notion -e NOTION_TOKEN=your_token_here -- npx -y @notionhq/notion-mcp-server

# 2. Playwright - ブラウザ自動化
claude mcp add playwright -- npx @playwright/mcp@latest
# 注意: 先に `npx playwright install chromium` を実行してください

# 3. GitHub - リポジトリ操作
claude mcp add github -e GITHUB_PERSONAL_ACCESS_TOKEN=your_pat_here -- npx -y @modelcontextprotocol/server-github

# 4. Sequential Thinking - 複雑な問題を段階的に思考
claude mcp add sequential-thinking -- npx -y @modelcontextprotocol/server-sequential-thinking

# 5. Memory - セッション間の長期記憶（推奨！）
# ✅ first_setup.sh で自動設定済み
# 手動で再設定する場合:
claude mcp add memory -e MEMORY_FILE_PATH="$PWD/memory/shogun_memory.jsonl" -- npx -y @modelcontextprotocol/server-memory
```

### インストール確認

```bash
claude mcp list
```

全サーバが「Connected」ステータスで表示されるはずです。

---

## 🌍 実用例

### 例1: 調査タスク

```
あなた: 「AIコーディングアシスタント上位5つを調査して比較せよ」

実行される処理:
1. 将軍が家老に委譲
2. 家老が割り当て:
   - Sasuke: GitHub Copilotを調査
   - Kirimaru: Cursorを調査
   - Hayate: Claude Codeを調査
   - Kagemaru: Codeiumを調査
   - Hanzo: Amazon CodeWhispererを調査
3. 5体の忍者が同時に調査
4. 結果がdashboard.mdに集約
```

### 例2: PoC準備

```
あなた: 「このNotionページのプロジェクトでPoC準備: [URL]」

実行される処理:
1. 家老がMCP経由でNotionコンテンツを取得
2. Kirimaru: 確認すべき項目をリスト化
3. Hayate: 技術的な実現可能性を調査
4. Kagemaru: PoC計画書を作成
5. 全結果がdashboard.mdに集約、会議の準備完了
```

---

## ⚙️ 設定

### 言語設定

```yaml
# config/settings.yaml
language: ja   # 日本語のみ
language: en   # 日本語 + 英訳併記
```

### スクリーンショット連携

```yaml
# config/settings.yaml
screenshot:
  path: "/mnt/c/Users/あなたの名前/Pictures/Screenshots"
```

将軍に「最新のスクショを見ろ」と伝えるだけで、スクリーンキャプチャを読み取って分析します。（Windowsでは `Win+Shift+S`）

### ntfy（スマホ通知）

```yaml
# config/settings.yaml
ntfy_topic: "shogun-yourname"
```

スマホの [ntfyアプリ](https://ntfy.sh) で同じトピックをサブスクライブしてください。リスナーは `shutsujin_departure.sh` で自動起動します。

---

## 🛠️ 上級者向け

<details>
<summary><b>スクリプトアーキテクチャ</b>（クリックで展開）</summary>

```
┌─────────────────────────────────────────────────────────────────────┐
│                      初回セットアップ（1回だけ実行）                   │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  install.bat (Windows)                                              │
│      │                                                              │
│      ├── WSL2のチェック/インストール案内                              │
│      └── Ubuntuのチェック/インストール案内                            │
│                                                                     │
│  first_setup.sh (Ubuntu/WSLで手動実行)                               │
│      │                                                              │
│      ├── tmuxのチェック/インストール                                  │
│      ├── Node.js v20+のチェック/インストール (nvm経由)                │
│      ├── Claude Code CLIのチェック/インストール（ネイティブ版）       │
│      │       ※ npm版検出時はネイティブ版への移行を提案                │
│      └── Memory MCPサーバー設定                                      │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│                      毎日の起動（毎日実行）                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  shutsujin_departure.sh                                             │
│      │                                                              │
│      ├──▶ tmuxセッションを作成                                       │
│      │         • "shogun"セッション（1ペイン）                        │
│      │         • "shogun"セッション（9ペイン、3x3グリッド）        │
│      │                                                              │
│      ├──▶ キューファイルとダッシュボードをリセット                     │
│      │                                                              │
│      └──▶ 現行の混成CLI編成を起動                                    │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

</details>

<details>
<summary><b>shutsujin_departure.sh オプション</b>（クリックで展開）</summary>

```bash
# デフォルト: フル起動（tmuxセッション + 混成CLI起動）
./shutsujin_departure.sh

# セッションセットアップのみ（CLI起動なし）
./shutsujin_departure.sh -s
./shutsujin_departure.sh --setup-only

# タスクキューをクリア（指令履歴は保持）
./shutsujin_departure.sh -c
./shutsujin_departure.sh --clean

# 決戦の陣: 全忍者をOpusで起動（最大能力・高コスト）
./shutsujin_departure.sh -k
./shutsujin_departure.sh --kessen

# サイレントモード: 戦国エコーを無効化（echoのAPIトークン節約）
./shutsujin_departure.sh -S
./shutsujin_departure.sh --silent

# フル起動 + Windows Terminalタブを開く
./shutsujin_departure.sh -t
./shutsujin_departure.sh --terminal

# 将軍中継専用モード: 将軍のThinkingを無効化（コスト節約）
./shutsujin_departure.sh --shogun-no-thinking

# ヘルプを表示
./shutsujin_departure.sh -h
./shutsujin_departure.sh --help
```

</details>

<details>
<summary><b>よく使うワークフロー</b>（クリックで展開）</summary>

**通常の毎日の使用：**
```bash
./shutsujin_departure.sh          # 全て起動
tmux attach-session -t shogun     # 接続してコマンドを出す
```

**デバッグモード（手動制御）：**
```bash
./shutsujin_departure.sh -s       # セッションのみ作成

# 特定のエージェントでClaude Codeを手動起動
tmux send-keys -t shogun:0 'claude --dangerously-skip-permissions' Enter
tmux send-keys -t shogun:2.1 'claude --dangerously-skip-permissions' Enter
```

**クラッシュ後の再起動：**
```bash
# 既存セッションを終了
tmux kill-session -t shogun
tmux kill-session -t shogun

# 新しく起動
./shutsujin_departure.sh
```

</details>

<details>
<summary><b>便利なエイリアス</b>（クリックで展開）</summary>

`first_setup.sh` を実行すると、以下のエイリアスが `~/.bashrc` に自動追加されます：

```bash
alias csst='cd ~/multi-agent-shogun && ./shutsujin_departure.sh'
alias css='tmux attach-session -t shogun'      # 将軍ウィンドウの起動
alias csm='tmux attach-session -t shogun'  # 家老・忍者ウィンドウの起動
```

※ エイリアスを反映するには `source ~/.bashrc` を実行するか、PowerShellで `wsl --shutdown` してからターミナルを開き直してください。

</details>

---

## 📁 ファイル構成

<details>
<summary><b>クリックでファイル構成を展開</b></summary>

```
multi-agent-shogun/
│
│  ┌─────────────────── セットアップスクリプト ───────────────────┐
├── install.bat               # Windows: 初回セットアップ
├── first_setup.sh            # Ubuntu/Mac: 初回セットアップ
├── shutsujin_departure.sh    # 毎日の起動（指示書自動読み込み）
│  └────────────────────────────────────────────────────────────┘
│
├── instructions/             # エージェント指示書
│   ├── shogun.md             # 将軍の指示書
│   ├── karo.md               # 家老の指示書
│   ├── ashigaru.md           # 忍者の指示書
│   └── cli_specific/         # CLI固有のツール説明
│       ├── claude_tools.md   # Claude Code ツール・機能
│       └── copilot_tools.md  # GitHub Copilot CLI ツール・機能
│
├── scripts/                  # ユーティリティスクリプト
│   ├── inbox_write.sh        # エージェントinboxへのメッセージ書き込み
│   ├── inbox_watcher.sh      # inotifywaitでinbox変更を監視
│   ├── ntfy.sh               # スマホにプッシュ通知を送信
│   └── ntfy_listener.sh      # スマホからのメッセージをストリーミング受信
│
├── config/
│   ├── settings.yaml         # 言語、ntfy、その他の設定
│   └── projects.yaml         # プロジェクト一覧
│
├── projects/                 # プロジェクト詳細（git対象外、機密情報含む）
│   └── <project_id>.yaml    # 各プロジェクトの全情報（クライアント、タスク、Notion連携等）
│
├── queue/                    # 通信ファイル
│   ├── shogun_to_karo.yaml   # 将軍から家老へのコマンド
│   ├── ntfy_inbox.yaml       # スマホからの受信メッセージ（ntfy）
│   ├── inbox/                # エージェント別inboxファイル
│   │   ├── shogun.yaml       # 将軍へのメッセージ
│   │   ├── karo.yaml         # 家老へのメッセージ
│   │   └── {ninja_name}.yaml  # 各忍者へのメッセージ (sasuke, kirimaru, hayate, kagemaru, hanzo, saizo, kotaro, tobisaru)
│   ├── tasks/                # 各ワーカーのタスクファイル
│   └── reports/              # ワーカーレポート
│
├── saytask/                  # 行動心理学に基づくモチベーション管理
│   └── streaks.yaml          # ストリーク追跡と日次進捗
│
├── templates/                # レポート・コンテキストテンプレート
│   ├── integ_base.md         # 統合: ベーステンプレート
│   ├── integ_fact.md         # 統合: ファクトファインディング
│   ├── integ_proposal.md     # 統合: 提案書
│   ├── integ_code.md         # 統合: コードレビュー
│   ├── integ_analysis.md     # 統合: 分析
│   └── context_template.md   # 汎用7セクション プロジェクトコンテキスト
│
├── memory/                   # Memory MCP保存場所
├── dashboard.md              # リアルタイム状況一覧
└── CLAUDE.md                 # システム指示書（自動読み込み）
```

</details>

---

## 📂 プロジェクト管理

このシステムは自身の開発だけでなく、**全てのホワイトカラー業務**を管理・実行する。プロジェクトのフォルダはこのリポジトリの外にあってもよい。

### 仕組み

```
config/projects.yaml          # プロジェクト一覧（ID・名前・パス・ステータスのみ）
projects/<project_id>.yaml    # 各プロジェクトの詳細情報
```

- **`config/projects.yaml`**: どのプロジェクトがあるかの一覧（サマリのみ）
- **`projects/<id>.yaml`**: そのプロジェクトの全詳細（クライアント情報、契約、タスク、関連ファイル、Notionページ等）
- **プロジェクトの実ファイル**（ソースコード、設計書等）は `path` で指定した外部フォルダに配置
- **`projects/` はGit追跡対象外**（クライアントの機密情報を含むため）

### 例

```yaml
# config/projects.yaml
projects:
  - id: my_client
    name: "クライアントXコンサルティング"
    path: "/mnt/c/Consulting/client_x"
    status: active

# projects/my_client.yaml
id: my_client
client:
  name: "クライアントX"
  company: "X株式会社"
contract:
  fee: "月額"
current_tasks:
  - id: task_001
    name: "システムアーキテクチャレビュー"
    status: in_progress
```

この分離設計により、将軍システムは複数の外部プロジェクトを横断的に統率しつつ、プロジェクトの詳細情報はバージョン管理の対象外に保つことができる。

---

## 🔧 トラブルシューティング

<details>
<summary><b>npm版のClaude Code CLIを使っている？</b></summary>

npm版（`npm install -g @anthropic-ai/claude-code`）は公式で非推奨（deprecated）になりました。`first_setup.sh` を再実行すると、npm版を検出してネイティブ版への移行を提案します。

```bash
# first_setup.sh を再実行
./first_setup.sh

# npm版が検出されると以下のメッセージが表示される:
# ⚠️ npm版 Claude Code CLI が検出されました（公式非推奨）
# ネイティブ版をインストールしますか? [Y/n]:

# Y を選択後、npm版をアンインストール:
npm uninstall -g @anthropic-ai/claude-code
```

</details>

<details>
<summary><b>MCPツールが動作しない？</b></summary>

MCPツールは「遅延ロード」方式で、最初にロードが必要です：

```
# 間違い - ツールがロードされていない
mcp__memory__read_graph()  ← エラー！

# 正しい - 先にロード
ToolSearch("select:mcp__memory__read_graph")
mcp__memory__read_graph()  ← 動作！
```

</details>

<details>
<summary><b>エージェントが権限を求めてくる？</b></summary>

`--dangerously-skip-permissions` 付きで起動していることを確認：

```bash
claude --dangerously-skip-permissions --system-prompt "..."
```

</details>

<details>
<summary><b>ワーカーが停止している？</b></summary>

ワーカーのペインを確認：
```bash
tmux attach-session -t shogun
# Ctrl+B の後に数字でペインを切り替え
```

</details>

<details>
<summary><b>将軍やエージェントが落ちた？（Claude Codeプロセスがkillされた）</b></summary>

**`css` 等のtmuxセッション起動エイリアスを使って再起動してはいけません。** これらのエイリアスはtmuxセッションを作成するため、既存のtmuxペイン内で実行するとセッションがネスト（入れ子）になり、入力が壊れてペインが使用不能になります。

**正しい再起動方法：**

```bash
# 方法1: ペイン内でclaudeを直接実行
claude --model opus --dangerously-skip-permissions

# 方法2: 家老がrespawn-paneで強制再起動（ネストも解消される）
tmux respawn-pane -t shogun:2.1 -k 'claude --model opus --dangerously-skip-permissions'
```

**誤ってtmuxをネストしてしまった場合：**
1. `Ctrl+B` の後 `d` でデタッチ（内側のセッションから離脱）
2. その後 `claude` を直接実行（`css` は使わない）
3. デタッチが効かない場合は、別のペインから `tmux respawn-pane -k` で強制リセット

</details>

---

## 📚 tmux クイックリファレンス

| コマンド | 説明 |
|----------|------|
| `tmux attach -t shogun` | 将軍に接続 |
| `tmux attach -t shogun` | ワーカーに接続 |
| `Ctrl+B` の後 `0-8` | ペイン間を切り替え |
| `Ctrl+B` の後 `d` | デタッチ（実行継続） |
| `tmux kill-session -t shogun` | 将軍セッションを停止 |
| `tmux kill-session -t shogun` | ワーカーセッションを停止 |

### 🖱️ マウス操作

`first_setup.sh` が `~/.tmux.conf` に `set -g mouse on` を自動設定するため、マウスによる直感的な操作が可能です：

| 操作 | 説明 |
|------|------|
| マウスホイール | ペイン内のスクロール（出力履歴の確認） |
| ペインをクリック | ペイン間のフォーカス切替 |
| ペイン境界をドラッグ | ペインのリサイズ |

キーボード操作に不慣れな場合でも、マウスだけでペインの切替・スクロール・リサイズが行えます。

---

## 現在のハイライト

- **設定駆動の混成編成** — `config/settings.yaml` と `config/cli_profiles.yaml` に基づく配備。READMEにモデルを固定記載しない
- **GATE-first 運用** — `cmd_complete_gate.sh`、`gate_cmd_state.sh`、`gate_lesson_health.sh` が false completion、stale delegation、低価値教訓を防ぐ
- **知識運用** — 知識7層、`queue/karo_snapshot.txt`、`queue/pending_decisions.yaml`、`context/cmd-chronicle.md` により復帰と監査を低コスト化
- **モバイル面** — ntfy、Androidコンパニオン、Termux/mosh でデスクを離れても軍を動かせる

---

## コントリビューション

Issue、Pull Requestを歓迎します。

- **バグ報告**: 再現手順を添えてIssueを作成してください
- **機能アイデア**: まずDiscussionで提案してください
- **スキル**: 共有スキルは `skills/`、個人スキルはリポジトリ外に分離します

## 🙏 クレジット

[Claude-Code-Communication](https://github.com/Akira-Papa/Claude-Code-Communication) by Akira-Papa をベースに開発。

---

## 📄 ライセンス

MIT License - 詳細は [LICENSE](LICENSE) を参照。

---

<div align="center">

**コマンド1つ。エージェント9体。連携コストゼロ。**

⭐ 役に立ったらスターをお願いします — 他の人にも見つけてもらえます。

</div>
