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

**multi-agent-shogun** は、1 人の人間（殿）が tmux 上の **9 体の CLI エージェント**（将軍 1・家老 1・軍師 1・忍者 6）を、YAML ファイルとファイル監視だけで指揮し、結果を二値で検証し、失敗を教訓・ゲート・テストへ還流させて自動成長させる戦国式のマルチエージェント基盤です。API ではなく各社の CLI（Claude Code / Codex CLI）をそのまま並べ、CLI ごとに固有の hook・gate を持つ multi-CLI 構成です。

### 陣形（2026-08-27、`config/settings.yaml` が唯一の正本）

| 役割 | window / pane | CLI・モデル | 何をするか |
|---|---|---|---|
| **殿**（あなた） | 端末 | 人間 | 指示と裁定。将軍と対話し、dashboard / artifact を自分で見る |
| **将軍** shogun | `main` | Claude Code（Fable 5） | 殿の指示を cmd（YAML）に起票し品質ゲートを通して家老へ委任。30 分ごとに一次確認・つまり解消・戦況 artifact 更新。コードの深掘り調査はせず偵察 cmd で委任 |
| **家老** karo | `agents` pane 1 | Codex（gpt-5.6-sol） | cmd を task に分解し忍者へ配備。報告を受けて GATE を回し、converge / push（1 commit ずつ）。hotfix / ci_fix は将軍 cmd なしで自立配備 |
| **軍師** gunshi | `agents` pane 2 | Claude Code（Opus 4.6, 1M） | cmd 草案と報告 YAML の一次レビュー（SG7 プロトコル）。LGTM → 家老 ACCEPT、FAIL → 差戻し。idle 時は分析を永続化し、将軍の自己検査（洗脳チェック）を第三者検証 |
| **忍者 ×6** hayate / kagemaru / hanzo / saizo / kotaro / tobisaru | `agents` pane 3-8 | Codex（gpt-5.6-luna high） | task YAML の受入条件を最高品質で遂行。task worktree で隔離作業 → scope commit → 報告 YAML。記憶の連続性なし（毎回 /clear） |

```
        殿（あなた）
          │ 日本語で指示
          ▼
   ┌──────────────┐        ┌──────────────┐
   │   将軍 SHOGUN │──cmd──▶│   家老 KARO   │
   │  起票・委任・  │        │ 分解・配備・   │
   │  30分loop      │        │ GATE・push    │
   └──────────────┘        └──────┬───────┘
          ▲                        │ task YAML + inbox nudge
          │ レビュー結果            ▼
   ┌──────────────┐     ┌─┬─┬─┬─┬─┬─┐
   │  軍師 GUNSHI  │◀────│1│2│3│4│5│6│  忍者 NINJA ×6（task worktree で隔離）
   │  SG7 レビュー  │報告 └─┴─┴─┴─┴─┴─┘
   └──────────────┘
   鎖: 殿→将軍→家老→忍者（分岐なし）。同じ鎖を学びが逆向きに還流する（lesson_candidate→教訓→gate→test）
```

**なぜ使うのか**
- 1 つの指示で 9 体が動き、すぐ制御が戻る。報告→レビュー→GATE→通知まで人手ゼロ
- エージェント間通信は **YAML + inotify**。API オーケストレーション費用を増やさない（定額 CLI サブスク）
- **cmd 品質ゲート（82 check）・二段レビュー・GATE・reflux・教訓淘汰**を内蔵し、失敗が次回の環境に埋め込まれる
- **三層記憶**（記憶DB / セマンティック索引 / Obsidian 因果）で `/clear` 後も前より強い状態で再開する
- ntfy・Android アプリ・戦況 artifact で外出先から指揮できる

---

## 現在の運用実績

| 指標 | 現在値 |
|---|---|
| GATE CLEAR | 465 / 467 (99.6%) |
| 連勝 | 295連勝（`cmd_357`〜`cmd_660`） |
| 発令cmd数 | 665+ |
| 教訓注入率 | 75.1% |
| 教訓効果率 | 70.3% |

上記の数値は、このローカル環境の `dashboard.md` 戦況メトリクスに基づく。

---

## なぜ Shogun なのか？

多くのマルチエージェントフレームワークは、連携のために API トークンを消費します。Shogun は違います。

| | Claude Code `Task` ツール | LangGraph | CrewAI | **multi-agent-shogun** |
|---|---|---|---|---|
| **アーキテクチャ** | 1 プロセス内のサブエージェント | グラフベースの状態機械 | ロールベースエージェント | tmux 上の 9 体（将軍・家老・軍師・忍者 6）の階層構造 |
| **並列性** | 逐次実行 | 並列ノード（v0.2+） | 限定的 | **忍者 6 体が task worktree で独立実行** |
| **連携コスト** | Task ごとに API コール | API + インフラ（Postgres/Redis） | API + CrewAI プラットフォーム | **ゼロ**（YAML + inotify、定額 CLI） |
| **品質保証** | なし | なし | なし | **cmd 品質ゲート 82 check → 軍師レビュー → 家老 GATE → CI** |
| **学習** | なし | なし | なし | **三層学習ループ**（教訓→ゲート→テストへ還流、reflux 自動配備） |
| **記憶** | セッション内 | 外部ストア | 外部ストア | **三層記憶**（記憶DB / セマンティック索引 / Obsidian 因果） |
| **可観測性** | Claude のログのみ | LangSmith 連携 | OpenTelemetry | **ライブ tmux ペイン** + 陣形図 + 戦況 artifact + ntfy |
| **セットアップ** | Claude Code 内蔵 | 重い（インフラ必要） | pip install | `first_setup.sh` 1 本（Linux/WSL2、ext4） |

### 他のフレームワークとの違い

**連携コストゼロ** — エージェント間の通信はディスク上の YAML ファイルと inotify の nudge。API コールは実際の作業にのみ使われ、オーケストレーションには使われない。

**完全な透明性** — すべてのエージェントが見える tmux ペインで動作し、すべての指示・報告・判断・ゲート結果がプレーンな YAML / log。読んで、diff して、バージョン管理できる。

**実戦で鍛えた階層構造** — 殿→将軍→家老→忍者の鎖と、鎖の脇に立つ軍師（レビュー専任）。役割ごとの専用ファイル、イベント駆動通信、二値の受入条件、そして失敗を環境に埋め込む成長ループ。2026-02 の初 commit から 16,000 commit 超の実運用で磨かれた（数値は「現在の運用実績」）。

---

## この fork の独自性

| 機能 | このリポジトリでの意味 |
|---|---|
| **鎖 + 軍師** | 殿→将軍→家老→忍者の一本道に、レビュー専任の軍師を加えた 4 役。将軍は決め、家老は仕切り、軍師は検分し、忍者は遂げる |
| **cmd 品質ゲート** | `cmd_skeleton.sh` → `cmd_save.sh`（82 check）→ `cmd_delegate.sh`。BLOCK は「次に BLOCK されないよう環境へ埋め込む」入口 |
| **task worktree 隔離配備** | `deploy_task.sh` が教訓・関連概念を push 注入し、忍者ごとに ext4 上の worktree で隔離 |
| **報告契約 + 二段レビュー + GATE** | 二値 `binary_checks` の報告 YAML → 軍師 SG7 → 家老 ACCEPT → `cmd_complete_gate.sh` → CI |
| **三層学習ループ / reflux** | 教訓の注入・評価・淘汰、`queue/insights.yaml` の気づきを idle 忍者へ自動配備 |
| **三層記憶** | 記憶DB（SQLite/FTS5）・セマンティック索引・Obsidian 因果ネットワーク。起動時 preflight と `[MEM:]` 引用契約 |
| **Vercel スタイル context** | `context/*.md` は索引層、詳細は `docs/research/` に置きリンクで戻す |
| **ninja_monitor / 陣形図** | `queue/karo_snapshot.txt` を機械生成。STALL / ghost / UNACTIONED 検知、CTX 監視と自動 /clear |
| **multi-CLI** | Claude Code と Codex を CLI 固有の hook・gate で運用し、成果基準だけ共通化。`/shogun-cli-switch` で編成切替 |
| **計測器の常設** | `defense_overhead.jsonl` / `gate_metrics.log` / deploy receipt / pre_push ledger。速度改善は before/after で証明 |
| **ext4 移設 runbook** | Windows ドライブ（9p）から ext4 へ移すための relocate / cutover / rollback script と副作用の突合表 |
| **Android コンパニオン** | `android/` に Kotlin + Jetpack Compose 製アプリ。SSH 制御・音声入力・ntfy 通知 |

---

## なぜCLI（APIではなく）？

多くの AI コーディングツールはトークン従量課金です。9 体の Opus 級エージェントを API 経由で動かすと **$100+/時間**。CLI の定額サブスクはこれを逆転させます。

| | API（従量課金） | CLI（定額制） |
|---|---|---|
| **9 エージェント × Opus 級** | ~$100+/時間 | 月額固定（Claude + ChatGPT の 2 サブスク） |
| **コスト予測性** | 予測不能なスパイク | 月額固定 |
| **使用時の心理** | 1 トークンが気になる | 使い放題 |
| **実験の余地** | 制約あり | 自由に投入（「実験ファースト」が原則） |

**「AI を使い倒す」思想** — 定額 CLI サブスクなら、6 体の忍者を気兼ねなく投入できる。1 時間稼働でも 24 時間稼働でもコストは同じ。「まあまあ」ではなく「徹底的に」が既定になる。上限に当たったときは `/usage` の reset か device-auth によるアカウント切替（Codex）で復帰する。

### Multi-CLI 対応

特定ベンダーに依存しない。指示書は共有テンプレートから **4 つの CLI 向けに自動生成**され（`bash scripts/build_instructions.sh`）、本番編成（2026-08-27）は Claude Code + Codex の 2 つで運用している。

| CLI | 特徴 | 本番での使用 |
|-----|------|-----------------|
| **Claude Code** | tmux 統合の実績、Memory MCP、専用ファイルツール（Read/Write/Edit/Glob/Grep）、hook で構造型の安全弁 | 将軍（Fable 5）・軍師（Opus 4.6, 1M） |
| **OpenAI Codex** | サンドボックス実行、`.codex/hooks.json`（exit 2 = BLOCK）、device-auth、`codex exec` ヘッドレス | 家老（gpt-5.6-sol）・忍者 6（gpt-5.6-luna） |
| **GitHub Copilot** | GitHub MCP 組込、特化エージェント、`/delegate` | 指示書を生成済み（`.github/copilot-instructions.md`）、本番編成外 |
| **Kimi Code** | 無料プランあり、多言語 | 指示書を生成済み、本番編成外 |

```
instructions/
├── common/              # 共通ルール（全 CLI 共通）
├── cli_specific/        # CLI 固有のツール説明（claude / codex / copilot / kimi）
├── roles/               # ロール定義（将軍・家老・軍師・忍者）
└── generated/           # ビルド結果（{cli}-{role}.md × 4 CLI × 4 役）
    ↓ bash scripts/build_instructions.sh
CLAUDE.md / AGENTS.md / .github/copilot-instructions.md
```

原則（multi-CLI 大原則）: 共通化するのは成果の評価基準（二値 AC・報告契約）だけ。hook・gate・起動方法は CLI ごとに別実装し、同じ実行機構を共用しない。ルールの変更は `instructions/roles/` の 1 箇所。

---

## ボトムアップスキル発見

忍者はタスクを遂行する中で **再利用可能なパターンを発見** し、報告 YAML の `skill_candidate` として提案します。家老がレビューし、採用されたものは `skills/{name}/SKILL.md` に正本として置かれ、Claude Code / Codex の両 CLI から `/{name}` で呼べます（2026-08-27 時点で 41 本）。

```
忍者がタスクを完了
    ↓
気づき: 「このパターン、3 つのプロジェクトで同じことをした」
    ↓
報告 YAML:  skill_candidate:
              found: true
              name: "api-endpoint-scaffold"
              reason: "3 プロジェクトで同じ REST スキャフォールドパターンを使用"
    ↓
軍師レビュー → 家老が skills/api-endpoint-scaffold/SKILL.md を作成（description に TRIGGER / DO NOT TRIGGER 必須）
    ↓
全エージェントが /api-endpoint-scaffold を呼び出し可能に。skill_execution_log で使用実績を計測
```

同じ経路で `lesson_candidate`（教訓）と `decision_candidate`（裁定が要る事項）も上がります。スキルも教訓も実際の作業から有機的に増え、使われないものは淘汰されます。

---

## 🚀 クイックスタート

### 🪟 Windowsユーザー（最も一般的）

<table>
<tr>
<td width="60">

**Step 1**

</td>
<td>

📥 **リポジトリをダウンロード**

[ZIPダウンロード](https://github.com/simokitafresh/multi-agent-shogun/archive/refs/heads/main.zip) して `C:\tools\multi-agent-shogun` に展開

*または git を使用:* `git clone https://github.com/simokitafresh/multi-agent-shogun.git C:\tools\multi-agent-shogun`

</td>
</tr>
<tr>
<td>

**Step 2**

</td>
<td>

🖱️ **`install.bat` を実行**

右クリック→「管理者として実行」（WSL2が未インストールの場合）。WSL2 + Ubuntu をセットアップします。

</td>
</tr>
<tr>
<td>

**Step 3**

</td>
<td>

🐧 **Ubuntu を開いて以下を実行**（初回のみ）

```bash
cd /home/simokitafresh/multi-agent-shogun
./first_setup.sh
```

</td>
</tr>
<tr>
<td>

**Step 4**

</td>
<td>

✅ **出陣！**

```bash
./shutsujin_departure.sh
```

</td>
</tr>
</table>

#### 🔑 初回のみ: 認証

`first_setup.sh` 完了後、一度だけ以下を実行して認証：

```bash
# 1. PATHの反映
source ~/.bashrc

# 2. OAuthログイン + Bypass Permissions承認（1コマンドで完了）
claude --dangerously-skip-permissions
#    → ブラウザが開く → Anthropicアカウントでログイン → CLIに戻る
#    → 「Bypass Permissions」の承認画面 → 「Yes, I accept」を選択（↓キーで2を選んでEnter）
#    → /exit で退出
```

認証情報は `~/.claude/` に保存され、以降は不要。

#### 📅 毎日の起動（初回セットアップ後）

**Ubuntuターミナル**（WSL）を開いて実行：

```bash
cd /home/simokitafresh/multi-agent-shogun
./shutsujin_departure.sh
```

### 📱 スマホからアクセス（どこからでも指揮）

スマホからの操作経路は2本ある。

- **ターミナル経路**: Tailscale + Termux + `mosh` / `ssh`
- **アプリ経路**: [`android/`](android/) の Android コンパニオン + ntfy

#### Option A: Termux + Tailscale + mosh

1. クライアントを入れる
   - Android: Tailscale、F-Droid版Termux、必要ならntfyアプリ
   - WSL/Ubuntuホスト: Tailscale、`openssh-server`、`mosh`
2. ホスト側を準備
   ```bash
   sudo apt update
   sudo apt install -y openssh-server mosh
   sudo service ssh start
   tailscale ip -4
   whoami
   tmux ls
   ```
3. Termux から接続
   ```sh
   pkg update
   pkg install openssh mosh
   mosh あなたのユーザー名@あなたのTailscale IP -- tmux attach -t shogun
   ```
4. UDPが通らない時のフォールバック
   ```sh
   ssh あなたのユーザー名@あなたのTailscale IP -t 'tmux attach -t shogun'
   ```
5. tmux 内での基本操作
   - `Ctrl+A` → `0`: 将軍ウィンドウ
   - `Ctrl+A` → `1`: agentsウィンドウ
   - `Ctrl+A` → `d`: detachしてもエージェントは継続

#### 値の確認場所

| 値 | ホスト側コマンド | このrepoの現在値例 |
|---|---|---|
| Tailscale IPv4 | `tailscale ip -4` | `100.75.173.26` |
| SSHユーザー名 | `whoami` | `simokitafresh` |
| プロジェクトパス | `pwd` | `/home/simokitafresh/multi-agent-shogun` |
| tmuxセッション名 | `tmux ls` | `shogun` |
| tmuxプレフィックス | `tmux show-options -gqv prefix` | `C-a` |
| Android APK | `ls android/release` | `multi-agent-shogun.apk` |

#### なぜ mosh なのか

- モバイル回線のパケット欠損やIP変化に強い
- Wi-Fi とセルラーの切替でも端末操作が固まりにくい
- 切断しても tmux セッションは残るので、忍者たちはそのまま走り続ける

#### トラブルシューティング

| 問題 | 確認ポイント |
|---|---|
| `mosh` が繋がらない | ホスト側に `mosh-server` があるか、UDP が塞がれていないか |
| SSHは繋がるが tmux に入れない | `tmux ls` で実際のセッション名を確認 |
| Androidアプリで違うペインが開く | [`android/README.md`](android/README.md) の session name と project path を再確認 |
| ntfy は動くのにアプリの端末が動かない | Android アプリは mosh ではなく SSH/JSch で接続する |
| Termux のパッケージが古い/足りない | Play Store版ではなく F-Droid 版 Termux を使う |

#### Option B: Android コンパニオンアプリ

このrepoには [`android/`](android/) が同梱されている。

- **Kotlin + Jetpack Compose + Material 3**
- **4タブ構成**: Shogun / Agents / Dashboard / Settings
- **SSH/JSch** で tmux をライブ操作
- **ntfy** でプッシュ通知
- **APKダウンロード: [`shogun-companion.apk`](https://github.com/simokitafresh/multi-agent-shogun/releases/download/v4.2/shogun-companion.apk)**

画面ごとの設定手順は [`android/README.md`](android/README.md) を参照。

---

<details>
<summary>🐧 <b>Linux / Mac ユーザー</b>（クリックで展開）</summary>

### 初回セットアップ

```bash
# 1. リポジトリをクローン
git clone https://github.com/simokitafresh/multi-agent-shogun.git ~/multi-agent-shogun
cd ~/multi-agent-shogun

# 2. スクリプトに実行権限を付与
chmod +x *.sh

# 3. 初回セットアップを実行
./first_setup.sh
```

### 毎日の起動

```bash
cd ~/multi-agent-shogun
./shutsujin_departure.sh
```

</details>

---

<details>
<summary>❓ <b>WSL2とは？なぜ必要？</b>（クリックで展開）</summary>

### WSL2について

**WSL2（Windows Subsystem for Linux）** は、Windows内でLinuxを実行できる機能です。このシステムは `tmux`（Linuxツール）を使って複数のAIエージェントを管理するため、WindowsではWSL2が必要です。

### WSL2がまだない場合

問題ありません！`install.bat` を実行すると：
1. WSL2がインストールされているかチェック（なければ自動インストール）
2. Ubuntuがインストールされているかチェック（なければ自動インストール）
3. 次のステップ（`first_setup.sh` の実行方法）を案内

**クイックインストールコマンド**（PowerShellを管理者として実行）：
```powershell
wsl --install
```

その後、コンピュータを再起動して `install.bat` を再実行してください。

</details>

---

<details>
<summary>📋 <b>スクリプトリファレンス</b>（クリックで展開）</summary>

| スクリプト | 用途 | 実行タイミング |
|-----------|------|---------------|
| `install.bat` | Windows: WSL2 + Ubuntu のセットアップ | 初回のみ |
| `first_setup.sh` | tmux、Node.js、必要CLI群のインストール + Memory MCP設定 | 初回のみ |
| `shutsujin_departure.sh` | tmuxセッション作成 + 混成CLI編成の起動 + 指示書読み込み + ntfyリスナー起動 | 毎日 |

### `install.bat` が自動で行うこと：
- ✅ WSL2がインストールされているかチェック（未インストールなら案内）
- ✅ Ubuntuがインストールされているかチェック（未インストールなら案内）
- ✅ 次のステップ（`first_setup.sh` の実行方法）を案内

### `shutsujin_departure.sh` が行うこと：
- ✅ tmuxセッションを作成（`shogun:main` と `shogun:agents`）
- ✅ `config/settings.yaml` の現行混成編成を起動
- ✅ 各エージェントに指示書を自動読み込み
- ✅ キューファイルをリセットして新しい状態に
- ✅ ntfyリスナーを起動してスマホ通知を有効化（設定済みの場合）

**実行後、全エージェントが即座にコマンドを受け付ける準備完了！**

</details>

---

<details>
<summary>🔧 <b>必要環境（手動セットアップの場合）</b>（クリックで展開）</summary>

依存関係を手動でインストールする場合：

| 要件 | インストール方法 | 備考 |
|------|-----------------|------|
| WSL2 + Ubuntu | PowerShellで `wsl --install` | Windowsのみ |
| Ubuntuをデフォルトに設定 | `wsl --set-default Ubuntu` | スクリプトの動作に必要 |
| tmux | `sudo apt install tmux` | ターミナルマルチプレクサ |
| Node.js v20+ | `nvm install 20` | MCPサーバーに必要 |
| Claude Code CLI | `curl -fsSL https://claude.ai/install.sh \| bash` | Anthropic公式CLI（ネイティブ版を推奨。npm版は非推奨） |

</details>

---

### 実行時依存台帳

`first_setup.sh` は、出陣・watcher・hook・gate・検証が実行時に要求する依存を一括確認します。機械抽出した集計コマンド、生出力、クローン検証手順は [`docs/research/cmd_4407_clone_dependency_ledger_20260827.md`](docs/research/cmd_4407_clone_dependency_ledger_20260827.md) に保存しています。

| 区分 | 必須の実行時依存 | セットアップの動作 |
|------|------------------|--------------------|
| コマンド | bash、git、python3、node、npm、tmux、jq、ripgrep（`rg`）、`gh`、`inotifywait`、bats、flock、timeout、setsid、crontab、curl | 一括確認し、不足時だけDebian/Ubuntuパッケージ補完を試行 |
| Python | `requirements.txt`、clone内 `.venv/bin/python3`、PyYAML | venvがない・壊れている時だけ作成し、グローバルへ導入しない |
| CLI | Codex CLI、Claude CLI、Claude pin `~/bin/claude`（2.1.87方針） | 既存バイナリ・版を報告し、暗黙に置換しない |
| 設定 | `config/settings.yaml`、`config/cli_profiles.yaml`、`~/.codex/config.toml` | 既存設定を正本として保持し、Codex設定雛形は欠落時だけ作成 |
| 実行時データ | `data/multi_agent_shogun_memory.db`、`queue/lord_conversation.jsonl`、`queue/pending_decisions.yaml`、`queue/bulletin_board.yaml`、`queue/insights.yaml`、`logs/` | 欠落時だけ初期化し、既存履歴は保持 |
| cron | 毎分の `daemon_watchdog.sh`、週次の `shogun-weekly-metrics-trend` | markerがない時だけ追加し、無関係なcron行は保持 |

現行の編成・エージェント名・モデル・CLI種別・起動パスは `config/settings.yaml` と `config/cli_profiles.yaml` が正本です。READMEの例を第二の設定源にしません。クリーンcloneでは、まず `first_setup.sh` を実行し、エージェントを起動しない検証を次で行います：

移設時の注意：監査済みcheckoutでは、絶対ルート `/home/simokitafresh/multi-agent-shogun` がscripts・設定・hook配下の93ファイルに存在します。移設完了まではこのルートを前提とします。別のcheckoutルートを使う場合は、リポジトリ内のこの文字列だけを置換し、残存数を再計数してからセットアップを再実行します：

```bash
OLD_ROOT=/home/simokitafresh/multi-agent-shogun
NEW_ROOT=/path/to/multi-agent-shogun
rg -l -F "$OLD_ROOT" --glob '!data/**' --glob '!queue/**' | xargs -r sed -i "s|$OLD_ROOT|$NEW_ROOT|g"
test "$(rg -l -F "$OLD_ROOT" --glob '!data/**' --glob '!queue/**' | wc -l)" -eq 0
bash first_setup.sh
```

この一括操作でユーザーHOME・プロジェクト・スクリーンショットのパスまで置換してはなりません。それらは個別に確認してください。93ファイルは監査時点の基準値なので、upstream変更後は必ず再計数します。

```bash
TMUX_TMPDIR="$(mktemp -d)" ./shutsujin_departure.sh -s
```

このセットアップ専用検証はtmux socketを隔離し、常駐daemonを起動しません。exit 0で完走し、元のcheckoutのqueueとユーザー設定を変更しないことが条件です。

---

### ✅ セットアップ後の状態

どちらのオプションでも、**9体のAIエージェント**が自動起動します：

| エージェント | 役割 | 数 |
|-------------|------|-----|
| 🏯 将軍（Shogun） | 総大将 - あなたの命令を受ける | 1 |
| 📋 家老（Karo） | 管理者 - タスクを分配 | 1 |
| ⚔️ 忍者（Ninja） | ワーカー - 並列でタスク実行 | 6 |

tmuxセッションが作成されます：
- `shogun:main` - ここで将軍に命令する
- `shogun:agents` - 家老と忍者がバックグラウンドで稼働

---

## 📖 基本的な使い方

### Step 1: 将軍に接続

`./shutsujin_departure.sh` の後、全エージェントは自分の指示書（`CLAUDE.md` / `AGENTS.md` + `instructions/generated/*.md`）を読み、起動ゲート（三層記憶の健全性・未読 inbox・deepdive 追体験）を通って待機します。

```bash
tmux attach -t shogun          # window main = 将軍、window agents = 家老・軍師・忍者
```

### Step 2: 最初の命令を出す

将軍 pane に日本語で書くだけです。

```
JavaScript フレームワーク上位 5 つを調査して比較表を作成せよ
```

将軍は (1) 三層記憶を検索し、(2) `queue/shogun_to_karo.yaml` に cmd を起票して品質ゲート（82 check）を通し、(3) 家老へ委任して即座に制御を返します。あなたは待ちません。

### Step 3: 鎖が回る

```
家老   cmd を task に分解 → deploy_task.sh で忍者へ配備（教訓・関連概念を注入、task worktree で隔離）
忍者   受入条件を遂行 → scope commit → 報告 YAML（binary_checks は yes/no）
軍師   報告を SG7 でレビュー → LGTM / FAIL
家老   ACCEPT → cmd_complete_gate.sh（commit 祖先・CI・context 鮮度）→ GATE CLEAR → archive → 忍者 idle
通知   ntfy でスマホへ「GATE CLEAR」。将軍は掲示板・gate_metrics で突合し、戦況 artifact を更新
```

### Step 4: 進捗を確認

- `queue/karo_snapshot.txt` — 陣形図（`ninja_monitor` が機械生成。誰が何を、CTX 何 %、いつから）
- `dashboard.md` — 殿が自分で見る戦況（家老が更新）
- `queue/bulletin_board.yaml` — 家老・軍師から将軍への報告チャネル
- `logs/gate_metrics.log` — cmd ごとの e2e / deploy / work / finalize 秒
- 戦況 artifact（claude.ai）— 将軍が 30 分ごとに再公開するタスクマップ

### 詳細なフロー（例）

```
あなた: 「トップ 5 の MCP サーバを調査して比較表を作成せよ」
```

将軍が cmd_XXXX を起票 → 家老がサブタスクへ分解:

| 忍者 | 割当内容 |
|------|----------|
| Hayate | Playwright MCP 調査 |
| Kagemaru | Memory MCP 調査 |
| Hanzo | Sequential Thinking MCP 調査 |
| Saizo | Notion MCP 調査 |
| Kotaro | GitHub MCP 調査 |

5 体が同時に調査を開始し、tmux でリアルタイムに見えます。偵察 cmd は finding（観測・結果・根拠パス）を必須にし、commit は免除。報告が揃うと軍師→家老→GATE CLEAR→ntfy の順に進み、比較表は報告 YAML と `docs/research/` に残ります。

---

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

## ✨ 主な特徴

### ⚡ 1. 並列実行

1つの命令で最大8つの並列タスクを生成：

```
あなた: 「5つのMCPサーバを調査せよ」
→ 5体の忍者が同時に調査開始
→ 数時間ではなく数分で結果が出る
```

### 🔄 2. ノンブロッキングワークフロー

将軍は即座に委譲して、あなたに制御を返します：

```
あなた: 命令 → 将軍: 委譲 → あなた: 次の命令をすぐ出せる
                                    ↓
                    ワーカー: バックグラウンドで実行
                                    ↓
                    ダッシュボード: 結果を表示
```

長いタスクの完了を待つ必要はありません。

### 🧠 3. セッション間記憶（Memory MCP）

AIがあなたの好みを記憶します：

```
セッション1: 「シンプルな方法が好き」と伝える
            → Memory MCPに保存

セッション2: 起動時にAIがメモリを読み込む
            → 複雑な方法を提案しなくなる
```

### 📡 4. イベント駆動（ポーリングなし）

エージェントはファイルベースのメールボックス（inbox_write.sh + inbox_watcher.sh）で通信します。
**ポーリングループでAPIコールを浪費しません。**

**2層構造（nudge-only配信方式）:**

- **Layer 1: ファイル永続化**
  - `inbox_write.sh` がメッセージを `queue/inbox/{agent}.yaml` に flock（排他ロック）付きで書き込み
  - メッセージ全文をYAMLに保存 — 永続化保証
  - 複数エージェントが同時書き込み可能（flockが直列化）

- **Layer 2: nudge配信**
  - `inbox_watcher.sh` が `inotifywait`（カーネルイベント）でファイル変更を検知
  - watcherが短い1行のnudge（起動シグナル）を `send-keys` で送信（timeout 5s）
  - エージェント自身が自分のinboxファイルをReadして未読メッセージを処理
  - **send-keysはメッセージ全文を送らない** — 起床通知のみ

- **CPU使用率ゼロ**: watcherは`inotifywait`でファイル変更イベントまでブロック（待機中はCPU 0%）

### 📸 5. スクリーンショット連携

VSCode拡張のClaude Codeはスクショを貼り付けて事象を説明できます。このCLIシステムでも同等の機能を実現：

```
# config/settings.yaml でスクショフォルダを設定
screenshot:
  path: "/mnt/c/Users/あなたの名前/Pictures/Screenshots"

# 将軍に伝えるだけ:
あなた: 「最新のスクショを見ろ」
あなた: 「スクショ2枚見ろ」
→ AIが即座にスクリーンショットを読み取って分析
```

**💡 Windowsのコツ:** `Win + Shift + S` でスクショが撮れます。保存先を `settings.yaml` のパスに合わせると、シームレスに連携できます。

こんな時に便利：
- UIのバグを視覚的に説明
- エラーメッセージを見せる
- 変更前後の状態を比較

### 📁 6. コンテキストと知識管理（知識7層）

このrepoは巨大な1枚プロンプトに依存しない。耐久知識を7層に分けて保持する。

| 層 | 保存場所 | 用途 |
|---|---|---|
| 1. System rules | `AGENTS.md`, `CLAUDE.md` | 全体の安全規則、復帰ルーティング、共通制約 |
| 2. Role instructions | `instructions/generated/*.md` | 将軍・家老・忍者それぞれの手順 |
| 3. Project core | `config/projects.yaml`, `projects/<id>.yaml` | プロジェクトのメタ情報、パス、核心ルール |
| 4. Project lessons | `projects/<id>/lessons.yaml` | 再利用可能な失敗・修正・ヒューリスティクス |
| 5. Live ops YAML | `queue/`, `tasks/`, `reports/` | cmd、inbox、タスク状態、報告 |
| 6. Context index | `context/*.md`, `docs/research/*.md` | Vercelスタイル検索層。要約は `context/`、詳細は `docs/research/` |
| 7. Memory MCP | `memory/shogun_memory.jsonl` | 殿の好みと将軍専用の長期記憶 |

この設計により：
- 忍者は会話全履歴を再生せず、必要ファイルだけ読めば復帰できる
- `/clear` や `/new` を挟んでも知識が失われない
- 要約と詳細を分けることで取得コストを抑えられる

#### Vercelスタイル context

`context/*.md` は索引層。深い調査は `docs/research/` に移し、`context/` 側からリンクで戻す。リンク先のない圧縮は削除と同義であり禁止。

#### 教訓サイクル

教訓は単なるメモではない。タスクへ注入し、作業中に参照し、GATE後に評価し、効かなくなったら自動退役する。これで知識ベースが肥大化しても腐らない。

#### `/clear` / `/new` 後の復帰

作業中コンテキストは捨ててもよい。耐久知識は上記の層に残るため、ルール・task YAML・project context を読み直せば復帰できる。

### 📱 7. スマホ通知（ntfy）

スマホと将軍の間で双方向通信 — SSH不要、Tailscale不要、サーバ不要。

| 方向 | 仕組み |
|------|--------|
| **スマホ → 将軍** | ntfyアプリからメッセージを送信 → `ntfy_listener.sh` がストリーミングで受信 → 将軍が自動処理 |
| **家老 → スマホ（直接）** | 家老が `dashboard.md` を更新する際、`scripts/ntfy.sh` 経由で直接プッシュ通知を送信 — **将軍を経由しない**（将軍は人間との対話用、進捗報告用ではない） |

```
📱 あなた（ベッドから）       🏯 将軍
    │                          │
    │  "React 19を調査せよ"    │
    ├─────────────────────────►│
    │    (ntfyメッセージ)      │  → 家老に委譲 → 忍者が作業
    │                          │
    │  "✅ cmd_042 完了"       │
    │◄─────────────────────────┤
    │    (プッシュ通知)        │
```

**セットアップ：**
1. `config/settings.yaml` に `ntfy_topic: "shogun-yourname"` を追加
2. スマホに [ntfyアプリ](https://ntfy.sh) をインストールし、同じトピックをサブスクライブ
3. `shutsujin_departure.sh` がリスナーを自動起動 — 追加手順なし

**通知の例：**

| イベント | 通知内容 |
|----------|----------|
| コマンド完了 | `✅ cmd_042 complete — 5/5 subtasks done` |
| タスク失敗 | `❌ subtask_042c failed — API rate limit` |
| 対応要 | `🚨 Action needed: approve skill candidate` |
| ストリーク更新 | `🔥 3-day streak! 12/12 tasks today` |

無料、アカウント不要、サーバ管理不要。[ntfy.sh](https://ntfy.sh) — オープンソースのプッシュ通知サービスを利用。

> **⚠️ セキュリティ注意:** トピック名がそのままパスワードです。知っている人は誰でも通知を読んだり、将軍にメッセージを送れてしまいます。推測されにくい名前を選び、**スクリーンショットやブログ、GitHubコミットなどで公開しないでください**。

**動作確認:**

```bash
# テスト通知をスマホに送信
bash scripts/ntfy.sh "将軍システムからのテスト通知 🏯"
```

スマホに通知が届けば設定完了です。届かない場合:
- `config/settings.yaml` の `ntfy_topic` が設定されているか（空でないか、余分な引用符がないか）
- スマホのntfyアプリで**完全に同じトピック名**を購読しているか
- スマホがインターネットに接続されており、ntfyの通知が有効か

**スマホから将軍に指示を送る方法:**

1. スマホでntfyアプリを開く
2. 購読しているトピックをタップ
3. メッセージを入力（例: `React 19のベストプラクティスを調査して`）して送信
4. `ntfy_listener.sh` が受信 → `queue/ntfy_inbox.yaml` に書き込み → 将軍を起こす
5. 将軍がメッセージを読み、通常の家老→忍者パイプラインで処理

送信したテキストがそのままコマンドになります。将軍に話しかけるように書けばOK — 特別な構文は不要です。

**リスナーの手動起動**（`shutsujin_departure.sh` を使わない場合）:

```bash
# バックグラウンドでリスナーを起動
nohup bash scripts/ntfy_listener.sh &>/dev/null &

# 起動確認
pgrep -f ntfy_listener.sh

# ログを見ながら起動（フォアグラウンド）
bash scripts/ntfy_listener.sh
```

リスナーは接続が切れても自動的に再接続します。`shutsujin_departure.sh` で出陣すれば自動起動されるため、手動起動は出陣スクリプトを使わない場合のみ必要です。

**トラブルシューティング:**

| 症状 | 対処 |
|------|------|
| スマホに通知が来ない | `settings.yaml` とntfyアプリのトピック名が完全に一致しているか確認 |
| リスナーが起動しない | `bash scripts/ntfy_listener.sh` をフォアグラウンドで実行してエラーを確認 |
| スマホ→将軍が動かない | リスナーが稼働中か確認: `pgrep -f ntfy_listener.sh` |
| メッセージが将軍に届かない | `queue/ntfy_inbox.yaml` を確認 — メッセージがあれば将軍が処理中の可能性 |
| "ntfy_topic not configured" エラー | `config/settings.yaml` に `ntfy_topic: "your-topic"` を追加 |
| 通知が重複する | 再接続時の正常動作 — 将軍がメッセージIDで重複排除します |
| トピック名を変更したのに通知が来ない | リスナーの再起動が必要: `pkill -f ntfy_listener.sh && nohup bash scripts/ntfy_listener.sh &>/dev/null &` |

#### SayTask通知

行動心理学に基づくモチベーション通知：

- **ストリーク追跡**: `saytask/streaks.yaml` で連続完了日数をカウント — ストリーク維持が損失回避の心理を利用してモメンタムを持続
- **Eat the Frog** 🐸: その日の最も難しいタスクを「カエル」としてマーク。完了すると特別な祝福通知が送信される
- **日次進捗**: `12/12 tasks today` — 視覚的な完了フィードバックがArbeitslust効果（仕事の進捗による喜び）を強化

### 🖼️ 8. ペインボーダータスク表示

各tmuxペインのボーダーにエージェントの現在のタスクを表示：

```
┌ sasuke (Codex) VF requirements ─────┬ hayate (Codex) API research ────────┐
│                                      │                                     │
│  Working on SayTask requirements     │  Researching REST API patterns      │
│                                      │                                     │
├ kirimaru (Codex) ───────────────────┼ kagemaru (Opus) DB schema design ───┤
│                                      │                                     │
│  (idle — waiting for assignment)     │  Designing database schema          │
│                                      │                                     │
└──────────────────────────────────────┴─────────────────────────────────────┘
```

- **作業中**: `sasuke (Codex) VF requirements` — エージェント名、モデル、タスク概要
- **待機中**: `sasuke (Codex)` — モデル名のみ、タスクなし
- 家老がタスク割当・完了時に自動更新
- 9ペインを一目見れば、誰が何をしているか即座にわかる

### 🔊 9. シャウトモード（戦国エコー）

忍者がタスクを完了すると、パーソナライズされた戦国風の叫びをtmuxペインに表示します — 部下が働いている実感を得られる。

```
┌ sasuke (Codex) ──────────────┬ kirimaru (Codex) ─────────────┐
│                               │                               │
│  ⚔️ sasuke、任を果たし待機！  │  🔥 kirimaru、二番槍の意地！  │
│  八刃一志の志、胸に刻む！     │  八刃一志！共に城を落とせ！   │
│  ❯                            │  ❯                            │
└───────────────────────────────┴───────────────────────────────┘
```

**仕組み:**

家老がタスクYAMLに `echo_message` フィールドを記述。忍者は全作業完了後（レポート + inbox通知の後）、**最後のアクション**として `echo` を実行。メッセージは `❯` プロンプト直上に残る。

```yaml
# タスクYAML（家老が記述）
task:
  task_id: subtask_001
  description: "比較表を作成"
  echo_message: "🔥 sasuke、先陣を切って参る！八刃一志！"
```

**シャウトモードがデフォルト。** 無効にする場合（echoのAPIトークン節約）:

```bash
./shutsujin_departure.sh --silent    # 戦国エコーなし
./shutsujin_departure.sh             # デフォルト: シャウトモード（戦国エコー有効）
```

サイレントモードは `DISPLAY_MODE=silent` をtmux環境変数に設定。家老がタスクYAML作成時にこれを確認し、`echo_message` フィールドを省略する。

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
| 忍者 6 体の並列実行 | — | ✅ |

SayTaskは個人の生産性を担当（キャプチャ → スケジュール → リマインド）。cmdパイプラインは複雑な作業を担当（リサーチ、コード、複数ステップのタスク）。両者はストリーク追跡を共有し、どちらのタスクを完了してもデイリーストリークにカウントされる。

---

## 🧠 モデル設定

編成の正本は `config/settings.yaml`（CLI・モデル・effort・launch_cmd）と `config/cli_profiles.yaml`。README の表は 2026-08-27 時点の値であり、切替は `/shogun-cli-switch`（idle pane だけ respawn し、作業中の pane は触らない）で行う。

| エージェント | CLI / モデル | effort | 理由 |
|---|---|---|---|
| 将軍 | Claude Code / Fable 5 | low（settings）| 殿との対話・cmd 起票・全体判断。深掘り調査はしない |
| 家老 | Codex / gpt-5.6-sol | medium | 分解・配備・GATE の判断を速く回す |
| 軍師 | Claude Code / Opus 4.6（1M context） | high | レビューは長文（cmd 全文+報告 YAML）を読むため 1M が要る |
| 忍者 ×6 | Codex / gpt-5.6-luna | high | 実装・計測・偵察。モデル名は忍者 launch_cmd に固定せず settings から継承 |

原則（殿裁定 2026-08-27）: モデルを cmd で名指ししない（配備は家老の判断）。作業中の pane は respawn しない。Codex は `~/.codex/config.toml` の trust とモデルを `codex_config_apply_agent` が respawn 経路で適用し、pane 表示が settings と違えば `ninja_monitor` が WARN を出す。

### 混成の考え方

- **Claude 主・Codex 従**（multi-CLI 大原則）: 評価基準（二値 AC・報告契約）だけを共通化し、hook・gate・起動方法は CLI ごとに別実装。協議不調時は Claude 側の契約を正とする。
- **切替は編成単位**: 家老を Claude に、忍者を全員 Codex に、などの切替は `/shogun-cli-switch` の 1 コマンド。過去の編成履歴は `context/training-cycle.md`。
- **上限・更新プロンプト**: Codex の利用上限や「Update available」プロンプトで pane が止まると watcher が nudge を抑止する。解除は可逆操作（選択肢を確認してから送出）。

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

### なぜ階層構造（殿→将軍→家老→忍者 + 軍師）なのか

1. **即座の応答**: 将軍は即座に委譲し、あなたに制御を返す
2. **並列実行**: 家老が複数の忍者に同時分配
3. **単一責任**: 各役割が明確に分離され、混乱しない
4. **スケーラビリティ**: 忍者を増やしても構造が崩れない
5. **障害分離**: 1体の忍者が失敗しても他に影響しない
6. **人間への報告一元化**: 将軍だけが人間とやり取りするため、情報が整理される
7. **レビューの分離（軍師）**: 家老は配備と GATE、軍師は cmd 草案と報告のレビューに専念する。作る側と検分する側を分けることで、家老の「自分の配備を自分で通す」偏りを消す。軍師は鎖の外（Claude, 1M context）に立ち、将軍の自己検査も第三者検証する
8. **鎖は還流路でもある**: 忍者の lesson_candidate が家老→教訓→gate→test へ戻る。鎖を迂回すると指示も学びも消える

### なぜメールボックスシステムなのか

1. **状態の永続化**: YAMLファイルで構造化通信し、エージェント再起動にも耐える
2. **ポーリング不要**: `inotifywait`はイベント駆動（カーネルレベル）なので、アイドル時のAPIコストゼロ
3. **割り込み防止**: エージェント同士やあなたの入力への割り込みを防止
4. **デバッグ容易**: 人間がinbox YAMLファイルを直接読んでメッセージフローを把握できる
5. **競合回避**: `flock`（排他ロック）で同時書き込みを防止 — 複数エージェントが同時送信してもレースコンディションなし
6. **配信保証**: ファイル書き込み成功 = メッセージ配信保証。到達確認不要、偽陰性なし、send-keys失敗による1.5時間ハングもなし
7. **nudge-only配信**: `send-keys`は短い起床通知のみ送信（timeout 5s）、メッセージ全文は送らない。エージェントが自分でinboxファイルをRead。旧方式（メッセージ全文をsend-keys送信）で発生した文字化け・1.5時間ハング等の配信障害を根絶。

### エージェント識別（@agent_id）

各ペインに `@agent_id` というtmuxユーザーオプションを設定（例: `karo`, `gunshi`, `hayate`）。`pane_index` はペイン再配置でズレるが、`@agent_id` は `shutsujin_departure.sh` が起動時に固定設定するため変わらない。

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

共有スキルは `skills/{name}/SKILL.md` を正本に、Claude Code / Codex の両 CLI から `/{name}` で呼べます（2026-08-27 時点で 41 本）。ユーザー固有スキルは `.claude/skills/` または `~/.codex/skills/` に置き、リポジトリにはコミットしません。

### スキルの思想

**1. 正本は 1 つ、CLI は複数** — `skills/` を正本とし、CLI ごとの配置は symlink/生成で追従する（multi-CLI 大原則）。description には TRIGGER / DO NOT TRIGGER / ロール制限（将軍専用・家老専用・忍者専用）を必ず書き、誤発火を防ぐ。殿の直接指示はロール制限に優先する。

**2. 取得の手順（ボトムアップ）**

```
忍者が作業中にパターンを発見 → 報告 YAML の skill_candidate
    ↓
軍師レビュー → 家老が skills/{name}/SKILL.md を作成
    ↓
skill_execution_log で使用実績を計測 → 使われないものは淘汰
```

**3. 主なスキル（役割別）** — 将軍: `/dream`（三層記憶整理）`/lesson-sort` `/shogun-teire` `/shogun-clear-prep` `/x-research` `/weekly-report`／家老: `/cmd-complete` `/dashboard-update` `/karo-direct` `/recon-dual`／軍師: `/review-bundle` `/gate-sync` `/idle-persist`／忍者: `/report-write` `/ninja-commit` `/verdict-check`／共通: `/shogun-cli-switch` `/codd` `/codd-refactor` `/three-layer-penetrate` `/db-check`

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
1. 将軍が cmd を起票（品質ゲート 82 check）→ 家老に委任
2. 家老が task に分解して割り当て（task worktree で隔離）:
   - Saizo: GitHub Copilotを調査
   - Kotaro: Cursorを調査
   - Hayate: Claude Codeを調査
   - Kagemaru: Codeiumを調査
   - Hanzo: Amazon CodeWhispererを調査
3. 5体の忍者が同時に調査
4. 各忍者が報告 YAML（finding 必須）を提出 → 軍師レビュー → 家老 GATE CLEAR → ntfy 通知
5. 比較表は報告 YAML と docs/research/ に残り、dashboard.md に要約
```

### 例2: PoC準備

```
あなた: 「このNotionページのプロジェクトでPoC準備: [URL]」

実行される処理:
1. 家老がMCP経由でNotionコンテンツを取得
2. Kotaro: 確認すべき項目をリスト化
3. Hayate: 技術的な実現可能性を調査
4. Kagemaru: PoC計画書を作成
5. 報告 YAML → 軍師 → 家老 GATE → dashboard.md に要約、会議の準備完了
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
alias csst='cd /home/simokitafresh/multi-agent-shogun && ./shutsujin_departure.sh'
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
├── first_setup.sh            # 初回セットアップ（Linux/WSL2、冪等）
├── shutsujin_departure.sh    # 毎日の起動（tmux 2 window + 9 agent + daemon）
├── install.bat               # Windows: WSL2/Ubuntu の案内（旧・補助）
│
├── CLAUDE.md / AGENTS.md     # 恒久ルール（Claude / Codex 同期・非一本化）
├── instructions/             # 役割別ルール
│   ├── shogun.md karo.md gunshi.md ashigaru.md   # 将軍・家老・軍師・忍者
│   ├── roles/ common/ cli_specific/             # 生成元（4 CLI）
│   └── generated/            # build_instructions.sh の出力（{cli}-{role}.md）
│
├── config/
│   ├── settings.yaml         # 編成の正本（CLI・モデル・effort・launch_cmd・ntfy）
│   ├── cli_profiles.yaml     # CLI ごとの起動プロファイル
│   └── projects.yaml         # 外部プロジェクト一覧
├── projects/                 # プロジェクト核心知識（git 追跡外、機密含む）
│
├── queue/                    # 通信・状態（全て YAML）
│   ├── shogun_to_karo.yaml   # 将軍の cmd（起票→pending→delegated→completed）
│   ├── tasks/{agent}.yaml    # 家老が配備する task
│   ├── reports/              # 忍者の報告 YAML（binary_checks / finding / lesson_candidate）
│   ├── inbox/{agent}.yaml    # mailbox（flock、watcher が nudge）
│   ├── bulletin_board.yaml   # 家老・軍師 → 将軍の報告チャネル
│   ├── insights.yaml         # 気づき（reflux の元）
│   ├── pending_decisions.yaml# 未裁定事項
│   ├── karo_snapshot.txt     # 陣形図（ninja_monitor が生成）
│   └── archive/              # 完了 cmd / report の退避
│
├── scripts/ (243)            # 起票・配備・監視・ゲート・計測
│   ├── cmd_skeleton.sh cmd_save.sh cmd_delegate.sh   # cmd 起票ゲート
│   ├── deploy_task.sh + deploy_task/                  # 配備（task worktree 隔離）
│   ├── inbox_write.sh inbox_watcher.sh inbox_mark_read.sh
│   ├── ninja_monitor.sh daemon_watchdog.sh            # 監視・自動 /clear・reflux
│   ├── cmd_complete_gate.sh gates/ (58)               # GATE と起動ゲート
│   ├── ninja_scope_commit.sh run_tests.sh             # scope commit / 選択テスト
│   ├── memory_db_query.sh memory_db_knowledge_write.sh semantic_search.sh   # 三層記憶
│   ├── migrate_to_ext4_{relocate,cutover,rollback}.sh # ext4 移設
│   ├── ntfy.sh ntfy_listener.sh gist_share.sh         # 殿インターフェース
│   └── lib/                  # 共通ライブラリ
├── skills/ (41)              # 両 CLI 共用スキル（{name}/SKILL.md）
├── .claude/hooks/ (23) .codex/hooks.json   # CLI 固有 hook
│
├── tests/unit/ (242 bats)    # 契約テスト（選択実行・shard CI）
├── context/                  # 索引層（growth-loop / semantic-map / infrastructure / {project}）
├── docs/research/ (1000+)    # 詳細層（runbook・計測・設計書）
├── docs/dashboard/           # 戦況 artifact の HTML 正本
├── memory/                   # deepdive_*.md（追体験原本）・dialogue_*.md（研究日誌）
├── data/multi_agent_shogun_memory.db   # 記憶DB（SQLite / FTS5）
├── logs/                     # gate_metrics / defense_overhead / deploy_task ほか
├── saytask/                  # SayTask（streaks.yaml）
├── android/                  # Android コンパニオンアプリ
└── dashboard.md              # 殿が自分で見る戦況（家老が更新）
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
    path: "~/work/client_x"   # ext4 上の任意パス
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
<summary><b>全体が遅い — git status に 1 分かかる？</b></summary>

リポジトリが Windows ドライブ（`/mnt/c/...`、9p ファイルシステム）上にあります。`git` / `flock` / `stat` が全て RPC になり、実測で `git status` 60〜120 秒・D-state プロセスが出ます。ext4（例: `~/multi-agent-shogun`）へ移してください。手順と script は `docs/research/9p_root_fix_runbook_20260827.md` と `scripts/migrate_to_ext4_{relocate,cutover,rollback}.sh`。移設後の `git status` は 84ms です。

</details>

<details>
<summary><b>Codex の pane が「Update available」や利用上限で止まっている？</b></summary>

確認プロンプトが開いている間は watcher が nudge を抑止するため、エージェントが idle に見えます。`tmux capture-pane` で pane を確認し、選択肢を選んでから 2 回目の capture で確認し、Enter を送る（可逆な手順）で解除します。利用上限は `/usage` の reset か device-auth によるアカウント切替で復帰し、その後 `ninja_monitor` が idle pane を respawn します。

</details>

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

- **2026-08-27 — リポジトリを Windows ドライブ（9p）から ext4 へ移設**: `git status` 60〜120 秒 → 84ms、配備 1 件 199〜397 秒 → 23 秒、cmd publish 3.8 秒 → 0.23 秒、hook 1 回の中央値 183 → 90ms。runbook: `docs/research/9p_root_fix_runbook_20260827.md`。
- **2 つの CLI の混成編成**: 将軍（Claude Fable 5）・軍師（Claude Opus 4.6, 1M）と、家老・忍者 6 の Codex gpt-5.6。`config/settings.yaml` が唯一の正本で、`/shogun-cli-switch` は作業中の pane に触れず切り替える。
- **全てを計測**: `defense_overhead.jsonl`（全 hook）、`gate_metrics.log`（cmd ごとの e2e/deploy/work/finalize）、deploy receipt、pre_push ledger。移設後に残る律速はファイルシステムではなく人手のレビュー往復（finalize 250〜960 秒）。
- **三層記憶が本番稼働**: 記憶DB（SQLite/FTS5）・セマンティック索引・Obsidian 因果。起動時 preflight と `[MEM:]` 引用契約を hook が強制。
- **可搬性の作業が進行中**: scripts/config からユーザー固有の絶対パスを除去（cmd_4409）、README を現物から書き直し隔離 clone / ZIP で再現検証（cmd_4410）。

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
