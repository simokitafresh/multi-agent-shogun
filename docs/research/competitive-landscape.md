# 競合調査レポート — 6スタイル+我ら
<!-- last_updated: 2026-03-01 cmd_453 追加調査反映 -->
<!-- next_review: 定点観測は将軍判断。最低月1回 -->

## §1 調査対象一覧

| # | 名称 | 種別 | 出典 | 概要 |
|---|------|------|------|------|
| 1 | ACE | 学術FW | arxiv 2510.04618, ICLR 2026 | Generator→Reflector→Curatorで自己改善コンテキスト |
| 2 | Vercel CE | 企業思想 | vercel.com/blog | 受動100%>能動79%。AGENTS.md+Skills+filesystem |
| 3 | OpenClaw | OSS 210K+ | docs.openclaw.ai | Gateway, SOUL.md, 53 Skills, Lobster workflow |
| 4 | おしお殿 | fork元 | github.com/yohey-w/multi-agent-shogun | 991stars。3層+軍師(Gunshi)。4CLI対応。busy時nudge抑制 |
| 5 | Claude Teams | 公式 | code.claude.com/docs/en/agent-teams | lead/teammate 2層, worktree隔離 |
| 6 | OpenAI Agents | SDK+製品 | openai.github.io/openai-agents-python | Agents SDK + Codex Agent + ChatGPT Agent |

※ Cursor Agent / Windsurf は補足として§4で言及

## §2 アーキテクチャ比較

### §2.1 エージェント階層

| システム | 階層数 | 構造 |
|----------|--------|------|
| 我ら | 3層 | 殿→将軍→家老→忍者8名。鎖の原理(一本、分岐なし迂回なし) |
| おしお殿 | 3層+1 | 将軍→家老→足軽7名+軍師(Gunshi)。Bloom Levelルーティング |
| ACE | 3段 | Generator→Reflector→Curator（固定パイプライン、役割変更不可） |
| Claude Teams | 2層 | lead→teammate(3-5名推奨)。固定リーダー、昇格不可 |
| OpenClaw | 2層 | coordinator→specialist agents。Gateway経由ルーティング |
| OpenAI Agents | 2層 | orchestrator→specialist via handoff。LLM駆動のルーティング |
| Vercel | 1層 | 単一エージェント+ファイルシステム |

### §2.2 通信プロトコル

| システム | 方式 | 永続性 | 特徴 |
|----------|------|--------|------|
| 我ら | ファイルベースinbox + inotify wake-up | flock排他で永続 | 2層保証(ファイル永続+nudge信号) |
| おしお殿 | ファイルベースinbox + inotify + 3フェーズself-watch | flock排他で永続 | Phase1(通常)→2(nudge抑止)→3(最終escalationのみ) |
| ACE | パイプライン直列 | playbook永続 | delta蓄積は永続、通信はパイプライン内のみ |
| Claude Teams | SendMessage + 自動配信 | ファイルベース永続 | message/broadcast。lead compactionで途切れる |
| OpenClaw | WebSocket + inbox | セッション+メモリ永続 | Gateway経由、チャネル隔離 |
| OpenAI Agents | handoff(ツールコール) + 共有会話履歴 | Session wrapper任意 | LLMが`transfer_to_X()`を呼んで切替。stateless-by-design |
| Vercel | なし | ファイルシステム | 単一エージェントのため不要 |

### §2.3 状態管理

| システム | 方式 | 復帰手段 |
|----------|------|----------|
| 我ら | YAML永続 + tmux変数 + karo_snapshot陣形図 | SessionStart hook自動注入 + /clear Recovery |
| おしお殿 | YAML永続 + flag file(/tmp/shogun_idle_*) | /clear Recovery + auto-recovery inbox書込み |
| ACE | playbook(テキストファイル) | playbook再読込 |
| Claude Teams | タスクファイル(~/.claude/tasks/) | TaskList/TaskGet（leadが忘れる問題あり） |
| OpenClaw | セッション永続 + メモリ層 | Gateway再接続 |
| OpenAI Agents | stateless（Session wrapper任意） | Session API or caller管理。デフォルトは揮発 |
| Vercel | ファイルシステム | AGENTS.md再読込 |

### §2.4 コンテキスト管理

| システム | 戦略 | 特徴 |
|----------|------|------|
| 我ら | 6層知識 + Vercel式2層圧縮 | 受動(100%) > 能動。リンク先なき圧縮禁止 |
| おしお殿 | 4層(MCP/PJファイル/YAML/セッション) | slim_yaml.sh(完了データ退避)。Vercel式圧縮規律なし |
| ACE | 単一playbook + delta蓄積 | 自動圧縮(semantic dedup)、トークン予算制約 |
| Claude Teams | CLAUDE.md + タスク記述 | leadの会話履歴はteammateに引き継がれない |
| OpenClaw | SOUL.md + 53 Skills + Memory | 3層(passive/active/ephemeral) |
| OpenAI Agents | ツール定義 + RAG + 共有会話履歴 | handoff間で会話履歴共有。input_filterで境界変換可能 |
| Vercel | AGENTS.md + Skills | 受動100%>能動79%。ツール80%削減 |

## §3 機能軸比較マトリクス（固定7軸・10点満点）

| 軸 | 我ら | おしお殿 | ACE | Claude Teams | OpenClaw | OpenAI | Vercel | 判定根拠 |
|-----|------|---------|-----|-------------|----------|--------|--------|----------|
| マルチエージェント協調 | 9 | 8 | 6 | 7 | 8 | 7 | 3 | おしお殿: 3層+軍師+Bloom routing。我らと同方向だが軍師で+1 |
| 知識管理・永続性 | 9 | 6 | 7 | 4 | 7 | 5 | 7 | おしお殿: 4層。lessons.yaml層とVercel式圧縮規律がない |
| Hooks・自動化 | 9 | 8 | 5 | 6 | 7 | 6 | 4 | おしお殿: Stop hook+3フェーズself-watch。CI/CDあり |
| エラー回復・耐障害性 | 9 | 8 | 5 | 3 | 6 | 5 | 4 | おしお殿: watcher_supervisor+3段escalation+auto-recovery inbox |
| 安全性・ガードレール | 10 | 10 | 3 | 6 | 5 | 8 | 3 | おしお殿: 同一D001-D008+settings.json deny。同等 |
| 計測・メトリクス | 8 | 6 | 9 | 2 | 3 | 8 | 3 | おしお殿: selfwatch metrics+ratelimit。GATE CLEAR相当なし |
| セットアップ容易性 | 3 | 4 | 5 | 8 | 6 | 7 | 8 | おしお殿: macOS互換+CI/CD。我らよりやや整備 |

合計: 我ら57 / おしお殿50 / ACE40 / Teams36 / OpenClaw42 / OpenAI46 / Vercel32

## §4 各競合の詳細プロファイル

### §4.1 ACE (Agentic Context Engineering)

- 出自: SambaNova/Stanford/UC Berkeley共同。ICLR 2026採択
- 構造: Generator(実行トレース) → Reflector(教訓抽出、最大5エポック) → Curator(決定論的マージ、非LLM)
- delta形式: `[section_slug-00000] helpful=X harmful=Y :: advice`
- 重複排除: semantic embedding(類似度閾値設定可能)
- ベンチ: AppWorld +10.6%(DeepSeek-V3)、Finance +8.6%
- 効率: offline適応レイテンシ82.3%削減、トークンコスト83.6%削減
- 強み: 学術的計測精度、教訓自動蓄積・pruning、unsupervised学習、並列batch対応
- 弱み: Reflector品質依存、固定3役割、コールドスタート問題、人間審査なし
- 我らとの関係: Generator≒忍者、Reflector≒家老、Curator≒lesson_write.sh。我らは人間審査(家老品質ゲート)あり

### §4.2 Vercel Context Engineering

- 出自: Vercel v0開発チーム。ブログ記事で思想公開
- 核心: 受動(AGENTS.md、100%pass) > 能動(Skills、79%pass)
- 原則: 「制約=受動(全出力)、能力=能動(特定出力)」
- ツール: 80%削減。bash+ファイルシステムに集約
- 強み: シンプルさ、受動/能動の使い分け、再現性
- 弱み: シングルエージェント、教訓蓄積なし、マルチPJ切替なし
- 我らとの関係: 受動ロード思想+2層圧縮を取り込み済み

### §4.3 OpenClaw

- 出自: OSS。GitHub 210K+ stars
- 構造: Gateway(WebSocket) → Agent Runtime(隔離)。ルーティング規則で振り分け
- SOUL.md: 人格・哲学定義。起動時に最初に読む
- Skills: 53個バンドル。環境検出で自動ロード
- Lobster: typed local-first macro engine。approval gates、resume tokens、nested pipelines
- Coordinator pattern: 安価モデルが分類→専門agent振り分け→結果集約
- 強み: コミュニティ(210K)、マルチプラットフォーム、Lobster再現性
- 弱み: 安全性(sandbox+allowlistのみ)、計測なし、教訓構造化なし
- 我らとの関係: SOUL.md≒instructions、Lobster≒cmdパイプライン(Lobsterの方がresume tokens等で洗練)

### §4.4 おしお殿 (yohey-w/multi-agent-shogun)

- 出自: 我らのfork元。991stars, 219forks, MIT License
- 編成: 将軍(Opus)+家老(Sonnet)+足軽7名+軍師(Opus) = 10名。tmux: shogun+multiagent 2セッション
- 軍師(Gunshi): 独立QCロール。Bloom Level L4-L6を担当。足軽成果物のQC+戦略分析。north_star_alignmentレポート必須
- Multi-CLI: Claude Code/OpenAI Codex/GitHub Copilot/Kimi K2の4種対応。lib/cli_adapter.shで抽象化。build_instructions.shで各CLI用指示書自動生成
- Bloom Levelルーティング: L1-L3=足軽、L4-L6=軍師。bloom_routing: auto/manual/off
- 通信: flock排他inbox + inotify + 3フェーズself-watch(Phase1通常→Phase2 nudge抑止→Phase3最終escalation)。inbox最大50メッセージ制限
- 障害検知: inbox_watcher.sh 3段escalation(0-2分nudge→2-4分Escape+nudge→4分~/clear) + watcher_supervisor.sh(5秒おき生存監視)
- 安全性: D001-D008(我らと同一) + settings.json deny list。WSL2保護も同一
- 知識管理: 4層(MCP Memory/PJファイル/YAML Queue/セッション)。lessons.yaml層なし
- 教訓蓄積: MCP Memory自由形式のみ。正式サイクル(lesson_candidate→審査→注入)なし。skill_candidateフィールドで再利用パターン報告あり
- 圧縮: slim_yaml.sh/slim_yaml.py(完了データ退避)。Vercel式索引/詳細分離なし。batch size制限(30/session)
- 計測: selfwatch metrics(unread_latency, bytes_read, estimated_tokens) + ratelimit_check.sh(5h/7日バケット) + SayTask streaks
- 自動復旧: /clear Recovery + enqueue_recovery_task_assigned()(auto-recovery inbox書込み)。陣形図(karo_snapshot)なし
- CI/CD: GitHub Actions(unit/e2e/shellcheck/build-check)。SKIP=FAILポリシー自動検証
- send-keys実態: busy時nudge=flag fileで完全抑制。idle時nudge=send-keys使用。CLIコマンド=send-keys使用。pty direct write=未実装
- 強み: 軍師QC、4CLI対応、3フェーズself-watch、macOS互換、CI/CD、flag fileによるbusy時nudgeゼロ
- 弱み: 教訓正式サイクルなし(MCP自由形式)、Vercel式圧縮規律なし、GATE CLEAR相当の品質計測なし、陣形図なし
- 分岐点: 我らは6層知識+Vercel式圧縮+教訓注入サイクル+GATE CLEAR計測+陣形図。おしお殿は軍師+4CLI+3フェーズself-watch+CI/CD

### §4.5 Claude Code Agent Teams (公式)

- 出自: Anthropic公式。experimental(`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`)
- 構造: lead(1) → teammate(3-5推奨)。SharedTaskList+SendMessage
- 通信: message(1:1) / broadcast(1:N、高コスト) / shutdown_request+response
- Hooks: TeammateIdle/TaskCompleted(exit 2で制御) + 標準hooks全対応
- Worktree: `isolation: worktree`でgit worktree自動作成
- 強み: セットアップ容易、worktree隔離、公式サポート
- 弱み: lead compactionで**全チーム認識喪失**、固定リーダー、ネスト不可、1セッション1チーム
- 我らとの関係: 仕組みは提供するが実装はユーザー任せ。我らは4hook実装済み

### §4.6 OpenAI Agents (SDK + Codex + ChatGPT Agent)

- 出自: OpenAI。Agents SDK(Swarm後継)、Codex Agent、ChatGPT Agent(Operator)
- SDK構造: 3抽象(Agents, Handoffs, Routines)。stateless-by-design(Chat Completions API)
- Handoff: LLMが`transfer_to_X()`ツールコール → SDK がactive_agent切替+会話履歴引継ぎ
- Session API: 永続化ラッパー(任意)。自動truncation+コールバック対応
- Guardrails: tripwire方式(input/output)。parallel(低レイテンシ) vs blocking(トークン節約)
- Tracing: 組込み(trace_id/group_id)。Datadog/Langfuse/Arize連携
- Codex: クラウドsandbox隔離、インターネット無効、GitHub連携、並列タスク実行
- ChatGPT Agent: Web自動化、watch mode(高リスクサイトは手動承認)、prompt injection検知
- Provider-agnostic: 100+ LLM対応（OpenAI以外も利用可能）
- 強み: tracing基盤充実、guardrails構造的、Codex sandbox隔離、handoff柔軟性、エコシステム
- 弱み: stateless設計(永続化はcaller責務)、教訓蓄積なし、知識管理は外部依存、handoffはLLM任せ(誤ルーティング可能)
- 我らとの関係: guardrails≒PreToolUse hook(我らの方がパイプ解析で精密)。tracing≒GATE CLEAR計測(方向は同じ、実装が異なる)。handoff≒inbox通信(我らはファイル永続、OpenAIは会話履歴内)

### §4.7 補足: Cursor Agent / Windsurf

- Cursor: 非同期subagent(並列)、Cloud Agent(VM隔離)、best-model-per-task
- Windsurf Wave 13: 並列Cascade 5+ agents、Git worktree隔離、dockable panes
- 共通弱点: IDE依存、知識永続化なし、教訓蓄積なし、計測なし
- 2026年2月に全プラットフォームがmulti-agent出荷（市場の標準化を意味）

## §5 盗むべきアイデア一覧

| # | 出典 | アイデア | 状態 | cmd | 備考 |
|---|------|---------|------|-----|------|
| 1 | Claude Teams | PreToolUse — D001-D008インフラ遮断 | 実装済 | cmd_449 | shlex解析+パイプ検出 |
| 2 | Claude Teams | PreCompact — compact前状態自動保存 | 実装済 | cmd_450 | agent/task/session_id保存 |
| 3 | Claude Teams | Stop — inbox未読強制チェック | 実装済 | cmd_451 | おしお殿と同方向 |
| 4 | Claude Teams | SessionStart — コンテキスト自動注入 | 実装済 | cmd_452 | karo_snapshot+compact_state |
| 5 | Claude Teams | PostToolUse — 自動lint/format | 検討中 | — | async。効果未検証 |
| 6 | Claude Teams | PostToolUseFailure — 失敗テレメトリ | 検討中 | — | async TSV記録 |
| 7 | Claude Teams | Notification → ntfy転送 | 検討中 | — | 既存ntfy.shと統合可能 |
| 8 | おしお殿 | busy時nudge抑制(flag file+Stop hook) | **実装済** | cmd_455 | 完全撤廃は不可。busy時ゼロが正しい目標 → `docs/research/cmd_454_sendkeys-elimination.md` |
| 19 | おしお殿 | 軍師(Gunshi)独立QCロール | 参考 | — | impl→QC→reviewの3段階品質保証 |
| 20 | おしお殿 | Bloom Levelルーティング(L1-L6) | 参考 | — | タスク難度に応じた自動モデル割当 |
| 21 | おしお殿 | Agent Self-Watch 3フェーズ | 参考 | — | Phase1→2→3で段階的nudge抑止 |
| 22 | おしお殿 | CI/CD(GitHub Actions) | 参考 | — | shellcheck+unit/e2e+SKIP=FAIL自動検証 |
| 23 | おしお殿 | Multi-CLI抽象化(4種CLI) | 参考 | — | cli_adapter.sh+build_instructions.shで差異吸収 |
| 9 | ACE | delta semantic dedup | 却下 | — | 家老審査で品質保証。自動dedup不要 |
| 10 | ACE | helpfulness/harmfulness counter | 参考 | — | cmd_444因果追跡と方向一致 |
| 11 | OpenClaw | Lobster resume tokens | 参考 | — | cmdパイプライン中断再開に応用可能 |
| 12 | OpenClaw | Coordinator pattern | 参考 | — | 家老round-robinが類似機能 |
| 13 | Vercel | ツール80%削減 | 採用済 | — | bash+FS中心。MCP最小限 |
| 14 | Vercel | 受動100%>能動79% | 採用済 | — | CLAUDE.md=受動、MCP=能動 |
| 15 | OpenAI | tripwire guardrails(parallel/blocking選択) | 参考 | — | 我らのPreToolUseは常時blocking。parallel modeは検討余地あり |
| 16 | OpenAI | 組込みtracing(trace_id+外部連携) | 参考 | — | GATE CLEAR TSVを外部可視化に拡張可能 |
| 17 | OpenAI | handoff input_filter | 参考 | — | agent間でデータ変換。我らのinbox通信には不要(同一形式) |
| 18 | OpenAI | Codex cloud sandbox | 参考 | — | 完全隔離実行環境。我らはWSL2内で十分 |

## §6 優位性・劣位性サマリ

### 優位(6競合全てに対して)

- 3層階層+鎖の原理: 他は最大2層。役割分離が最も深い
- 6層知識管理+Vercel式圧縮規律: 最多層。教訓注入率90.9%は唯一の構造的蓄積(ACE除く)
- 2重安全防御(deny + PreToolUse shlex): パイプ経由も検出。OpenAI tripwireより精密
- インフラ構造保証(hook 4本): CTX消失後も安全性・状態復元が維持
- 実運用計測(GATE CLEAR 99.3%、streak 95): ACE/OpenAI以外は計測基盤なし
- 教訓注入サイクル+人間審査: ACEは自動だが審査なし。OpenAIは蓄積自体なし

### 劣位(正直に)

- 外部可視性: OpenClaw 210K stars、おしお殿991stars。我ら非公開
- セットアップ: tmux+WSL2+8忍者が複雑。Teams/Codex/Vercelは一発。おしお殿はmacOS互換+CI/CDで上回る
- 学術ベンチ: ACEの定量的計測(82%削減等)に相当するものがない
- CI/CD: おしお殿はGitHub Actions整備済み。我らは手動テストのみ
- Multi-CLI: おしお殿は4CLI対応(Claude/Codex/Copilot/Kimi)。我らは2CLI(Claude/Codex)
- 独立QCロール: おしお殿の軍師(Gunshi)に相当するQC専門エージェントがない
- tracing外部連携: OpenAIのDatadog/Langfuse連携に相当する外部可視化がない
- Lobster洗練: resume tokens、approval gates。cmdパイプラインは素朴
- stateless柔軟性: OpenAI SDKの「永続化は任意」は異なる環境への移植性が高い
