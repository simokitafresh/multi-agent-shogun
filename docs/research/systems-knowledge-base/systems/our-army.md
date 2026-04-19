# 我が軍 (multi-agent-shogun current fork)

> tmux 上で将軍・家老・軍師・忍者を役割分担させ、YAML を一次データとして運用するマルチエージェント基盤。指揮系統、学習ループ、ゲート、自動復帰を一体で回す。

## Basic Info

| 項目 | 内容 |
|------|------|
| System | multi-agent-shogun current fork |
| Origin Repo | `https://github.com/simokitafresh/multi-agent-shogun.git` |
| Upstream Repo | `https://github.com/yohey-w/multi-agent-shogun.git` |
| Status | 本番運用中 |
| System Config | `AGENTS.md` / `CLAUDE.md` system configuration `version: "3.0"` |
| Active Roles | Lord(人間) → shogun → karo → gunshi → ninja×6 |
| CLI Split | Claude + Codex (`projects/infra.yaml` `cli_agents`) |
| Communication | YAML mailbox + `scripts/inbox_write.sh` + watcher nudge |
| Current Command Archive | `context/cmd-chronicle.md` に `cmd_` 行 725 件 (2026-04-19確認) |
| Knowledge Layout | `AGENTS.md` / `instructions*` / `projects/*.yaml` / `context/*.md` / `queue/*.yaml` / MCP Memory(将軍限定) |

## Design Philosophy

- **指揮系統優先**: Lord → shogun → karo → gunshi/ninja の階層を固定し、判断と実行を分離する
- **一次データ優先**: `queue/` や `projects/*.yaml` を正本とし、`dashboard.md` は二次データとして扱う
- **学習ループ常設**: 全作業で binary check を回し、FAIL 時停止・原因報告・教訓還流まで含める
- **自動化×強制**: 口約束ではなく、hook・gate・状態遷移・テンプレートで正しい挙動を環境へ埋め込む
- **受動的知識配置**: `AGENTS.md` と `context/*.md` を圧縮索引として置き、必要時のみ詳細へ降りる
- **非ポーリング運用**: mailbox 更新を watcher が検知し、`inboxN` ナッジで作業再開する

## Architecture

### Role Structure

| 役割 | 責務 |
|------|------|
| shogun | WHAT と二値基準を定義し、cmd を発令する |
| karo | 配備、レビュー、教訓還流、全軍の采配を担う |
| gunshi | 一次レビュー、分析、検証設計を担う |
| ninja | task YAML の任務だけを遂行し、報告 YAML で家老へ返す |

### Communication / State

| 観点 | 実装 |
|------|------|
| 配備 | `queue/tasks/{agent}.yaml` |
| 通知 | `scripts/inbox_write.sh` → `queue/inbox/{agent}.yaml` → watcher → `inboxN` |
| 状態遷移 | `idle → assigned → acknowledged → in_progress → done/failed` |
| 報告 | `queue/reports/*` + `inbox_write.sh` |
| 状況要約 | `dashboard.md` |

### Knowledge / Quality

| 観点 | 実装 |
|------|------|
| 知識層 | `AGENTS.md` 圧縮索引 + `context/*.md` 詳細 + `projects/*.yaml` 核心知識 |
| 教訓層 | `projects/*/lessons.yaml` と `projects/infra/lessons_{role}.yaml` |
| レビュー | 家老 + 軍師の品質管理ユニット |
| 品質保証 | GATE 7項目 + review + pre-push/CI監視 |
| 復帰 | tmux pane ID + task YAML + inbox 読み直しによる lightweight recovery |
| コンテキスト管理 | ninja monitor による自動 `/new` `/clear` と 90% auto-compact |

## Key Features

| 機能名 | 説明 | 導入/根拠 |
|--------|------|-----------|
| YAML mailbox | 永続 inbox と watcher nudge によるイベント駆動通信 | `AGENTS.md`, `projects/infra.yaml` |
| `acknowledged` 状態 | 配備直後と実作業開始を分離し、ゴースト配備を防ぐ | cmd_181 |
| pane recovery | tmux ペイン消失を検知し再配備する | cmd_183 |
| lesson injection | task 配備時に関連教訓を注入し、完了時に lesson candidate を回収する | cmd_348-351, cmd_531 |
| Read tracking hook | 未読ファイルへの Write/Edit をブロックする | cmd_1044 |
| task/report write guard | `queue/tasks/*.yaml` と `queue/reports/*.yaml` の直接編集を禁止する | cmd_1065, cmd_1067 |
| 軍師品質管理ユニット | 忍者報告の一次レビューを軍師が担当する | cmd_1162, cmd_1174, cmd_1181 |
| CoDD L3 診断 | Diagnose MANDATORY, Session State, before/after 計測, affected tests を運用へ組み込む | cmd_1939-1942 |
| Karpathy自問 | `assumption_check` と `simplicity_check` を報告/レビューに埋め込む | cmd_2019 |
| Android Companion App | SSH + 音声 + 8ペイン + dashboard + スクショ共有の運用面を持つ | `docs/research/system-comparison-2026-03-13.md` |

## Changelog since 2026-03-13

| 日付 | cmd/変更 | 内容 | 影響 |
|------|----------|------|------|
| 2026-03-13 | cmd_875-878 | gstack Tier1-2取込、CDP daemon 化、教訓同期修復 | プロンプト技法とブラウザ基盤を強化 |
| 2026-03-18〜20 | cmd_1039-1120 | 三段階 `/clear`、Read追跡、task/report YAML guard、自動トリム | 作業中断事故と運用破損を削減 |
| 2026-03-30 | cmd_1532-1543 | report gate の主要 BLOCK 原因を構造的に修正 | 初回 CLEAR 率を引き上げた |
| 2026-04-16 | cmd_1939-1942 | CoDD L3 診断推論、教訓閾値更新、before/after 計測、related tests 化 | 改善 cmd の診断と検証を強化 |
| 2026-04-17 | cmd_2019 | Karpathy 由来の自問をレビュー/報告に追加 | 過剰設計と仮定暴走の抑制 |
| 2026-04-19 | cmd_2099 | AI開発知識辞書に我が軍エントリ、索引、採用ログを追加 | 知識辞書の自己記述が完成 |

## Notable Techniques

| テクニック名 | 説明 | このシステム固有か |
|-------------|------|-----------------|
| 鎖の原理 | shogun が決め、karo が仕切り、ninja が遂げる責務分離 | 固有 |
| YAML mailbox | メッセージ永続化と短い wake-up signal を分離する | 固有 |
| lessons.yaml 循環 | task 配備時注入 → 実行 → lesson candidate 回収 → 正式還流 | 固有 |
| Vercel式2層知識 | 圧縮索引と詳細文書を分ける retrieval-oriented 文書構造 | 採用済み設計 |
| GATE 7項目 + review | ゲートと人レビューを並列ではなく層として運用する | 固有 |
| binary checks | AC ごとに yes/no の自己検証を強制する | 固有 |
| auto-compact recovery | CTX 管理を外部インフラへ委譲し、復帰を定型化する | 固有 |
| CI RED 自走修正 | 家老が CI RED を検知し、idle 忍者へ即配備する | 固有運用 |

## Ecosystem

| カテゴリ | 内容 |
|---------|------|
| Repositories | origin=`simokitafresh/multi-agent-shogun`, upstream=`yohey-w/multi-agent-shogun` |
| Projects | `infra` を platform として常時ロードし、個別 PJ は `projects/{id}.yaml` で切替える |
| CLI | 現行設定は Claude + Codex の併用 |
| Browser / Device | CDP 系スクリプト、Android Companion App |
| Notifications | `scripts/ntfy.sh` による `shogun-simokitafresh` topic 通知 |
| Current Focus | `dm-signal` が current project として設定されている |

## Pitfalls

| 落とし穴 | 何が問題か | どこで表面化するか |
|---------|-----------|------------------|
| 陣形図(karo_snapshot)と実態の乖離 | karo_snapshot.txtは定期生成だが、STALLした忍者やペイン消失はcapture-paneで実態確認しないと見落とす。陣形図を事実として信じると誤判断を招く | 長時間タスク実行中、ペイン消失後のリカバリ、家老の状況判断 |
| task/report YAMLへのyaml.dump直接書き込み | yaml.dump/yaml.safe_dumpで運用YAMLを上書きすると複雑なマルチライン文字列のround-tripに失敗してエントリが消失する(cmd_1399事故) | Python経由での運用YAML書き込み、一括更新スクリプト作成時 |
| inbox_watcher遅延によるnudge不達 | WSL2上ではinotifywaitがstatポーリングになるため、inbox_write直後にnudgeが届かず忍者がidle待機を続けるケースがある。nudgeだけを信頼してinbox自体を確認しない設計は危険 | inbox_write直後の反応確認、WSL2 /mnt/c上ファイル変更検知 |

## Cross-References

| 軸 | 対象 | 関係 |
|----|------|------|
| 補完 | [oshio](oshio.md) | our-armyの実運用フローに対し、oshioのCoDD整合性保証・Bloom Taxonomyルーティング・OSS設計思想が設計の洗練を補完する |
| 競合 | [ace](ace.md) | our-armyはYAML鎖型通信と実運用ゲートを中心に置く一方、ACEは抽象的な自然言語バスと6層認知モデルを前提とする |
| 前提 | [逆瀬川 (Harness Engineering)](../sources/gyakusegawa.md) | our-armyのハーネス設計思想はHarness Engineeringの7原則と同方向性であり、Skill/Hook/AGENTS.md設計の知識が前提基盤となる |

## Sources

| 種別 | パス/URL |
|------|----------|
| System Rules | `AGENTS.md` |
| Synced Rules | `CLAUDE.md` |
| Core Project Knowledge | `projects/infra.yaml` |
| Infra Context | `context/infrastructure.md` |
| Command History | `context/cmd-chronicle.md` |
| Comparative Record | `docs/research/system-comparison-2026-03-13.md` |
| Repository Remote | `git remote -v` (`simokitafresh/multi-agent-shogun`, `yohey-w/multi-agent-shogun`) |

## Verification

| 項目 | 内容 |
|------|------|
| verified_at | 2026-04-19T09:18:08+09:00 |
| method | ローカル一次資料読取 (`AGENTS.md`, `CLAUDE.md`, `projects/infra.yaml`, `context/infrastructure.md`, `context/cmd-chronicle.md`) + `git remote -v` + 件数確認 |
| source | `AGENTS.md`, `CLAUDE.md`, `projects/infra.yaml`, `context/infrastructure.md`, `context/cmd-chronicle.md` |
| notes | `context/cmd-chronicle.md` の `cmd_` 行数は 725、知識辞書の既存件数は `systems=7`, `sources=1` を確認 |
