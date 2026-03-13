# 6システム対比分析 — cmd_709（将軍再分析版）
<!-- created: 2026-03-09 cmd_709 tobisaru(初版) → 将軍(再分析) -->
<!-- systems: ACE / Vercel / GSD / Claude Teams / おしお殿 / 我が軍 -->

> 中立プロンプト原則適用。事実ベースで対比。各システムの長所を正当に評価し、我が軍の弱点も率直に記述。

---

## §1 設計思想の対比 — 6つの哲学

各システムは異なる「信念」から設計されている。機能比較の前に、なぜその機能が存在するのかを理解する。

| システム | 設計信念 | 一言で言うと |
|---------|---------|------------|
| **ACE** | 学習は自動化できる。人間なしで教訓が自己修正される | 「学術的自動進化」 |
| **Vercel** | 受動的コンテキスト(100%) > 能動的取得(79%)。検索させるな、置いておけ | 「極限の受動配置」 |
| **GSD** | Context Rotが品質劣化の根因。CTX残量こそが最重要KPI | 「コンテキスト生存戦」 |
| **Claude Teams** | 協調プリミティブはプラットフォームが提供すべき | 「ネイティブ統合の賭け」 |
| **おしお殿** | 多くのCLI・多くの環境・多くの人が使えることが価値 | 「アクセシビリティ優先」 |
| **我が軍** | 品質は計測しなければ改善できない。知識は循環しなければ腐る | 「計測と循環の規律」 |

### なぜこの区別が重要か

機能の有無ではなく、**設計信念の違い**が各システムの進化方向を決定する。

- おしお殿がBloom Routingを作り我が軍が作らないのは、おしお殿が「多様なモデルを多様なタスクに最適配分する」ことに価値を見出し、我が軍は「どのモデルでも品質ゲートを通過すれば良い」と考えるからだ。
- GSDがContext Monitorを作り我が軍が作らないのは、GSDは「CTX枯渇を事前に回避する」ことを重視し、我が軍は「枯渇しても陣形図で完全復帰できる」ことを重視するからだ。
- おしお殿がCI/CDを作り我が軍が作らないのは、おしお殿がOSS公開を前提に「誰でも検証可能」を目指し、我が軍は非公開で「実戦GATE CLEARが検証」と考えるからだ。

**いずれも合理的な選択**であり、優劣ではなく戦略の違いである。

---

## §2 おしお殿 vs 我が軍 — 同根からの分岐分析

両システムは同じリポジトリからフォークした同根の存在。**どこで分岐し、なぜ分岐したか**が最も示唆に富む。

### §2.1 共通基盤（フォーク時点で共有）

- 将軍→家老→忍者の3層指揮系統
- ファイルベースmailbox（inbox_write.sh + flock排他 + inotify）
- tmux pane管理、dashboard.md、YAML指示・報告
- Androidコンパニオンアプリ（SSH + tmux capture-pane/send-keys）
- ntfy通知統合

### §2.2 分岐マップ

| 軸 | おしお殿の進化 | 我が軍の進化 | 分岐の理由 |
|----|-------------|------------|-----------|
| **品質保証** | 軍師(Gunshi)によるQCレビュー | GATE CLEAR機械検査(7項目)+別忍者レビュー必須 | おしお殿=人的QC信頼、我が軍=機械検査+相互レビュー |
| **知識管理** | MCP Memory自由形式 + YAML Slim(トークン節約) | 8段階教訓サイクル(発見→淘汰) + Vercel式2層圧縮 | おしお殿=記録保持、我が軍=知識を循環させて陳腐化を自動排除 |
| **モデル戦略** | Bloom Level Routing(難度→モデル自動割当) + 4CLI対応 | round-robin + dual vendor(Opus4+GPT-5.4) | おしお殿=最適配分、我が軍=ベンダー分散+ゲート品質保証 |
| **復帰機構** | ASW 3フェーズ(nudge→抑制→/clear) + flag file idle | 陣形図(karo_snapshot) + SessionStart hook + inbox永続 | おしお殿=問題発生時の段階的対処、我が軍=復帰時の完全状態再構築 |
| **テスト** | bats E2E 12スイート + GitHub Actions CI/CD | GATE CLEAR実戦検証(710cmd, 連勝340) | おしお殿=事前検証、我が軍=実戦計測 |
| **可搬性** | macOS互換(bash 3.2) + first_setup.sh | WSL2専用 | おしお殿=多環境、我が軍=単一環境最適化 |
| **コミュニティ** | OSS 1,035 stars + MIT | 非公開 | おしお殿=オープン成長、我が軍=クローズド深化 |
| **Androidアプリ** | v4.1(基本機能+Rate Limit Monitor) | **v5.0**(ピンチズーム+フォントサイズ+ソフトラップ+自動スクロール+省スペースUI+cmd題名表示) | 同根。我が軍がUX面でリード(コード量+36%: 87.8KB vs 64.5KB) |

### §2.3 Androidアプリ詳細比較

両陣営とも同じアーキテクチャ（Kotlin/Jetpack Compose + JSch SSH → tmux）を持つ。

| 機能 | おしお殿(v4.1) | 我が軍(v5.0) |
|------|-------------|------------|
| SSH端末(将軍ペイン) | あり | あり |
| エージェントグリッド(9ペイン) | あり | あり |
| ダッシュボードMarkdown表示 | あり | あり |
| 設定画面 | あり(9.5KB) | あり(14.5KB — ntfy設定追加) |
| ANSI 256色描画 | あり | あり |
| 音声入力(日本語) | あり | あり |
| BGM 3トラック | あり | あり |
| Rate Limit Monitor | あり(Claude Max+Codex) | あり |
| スクリーンショット共有 | あり | あり |
| 特殊キーバー | あり | あり |
| **ピンチズーム** | なし | **あり(TerminalZoom.kt 6.8KB)** |
| **フォントサイズ調整** | なし | **あり** |
| **ソフトラップ** | なし | **あり** |
| **自動スクロール** | なし | **あり** |
| **省スペースUI** | なし | **あり(cmd_694)** |
| **cmd題名表示** | なし | **あり(cmd_703)** |
| ntfy設定セクション | なし | **あり(NtfySettingsSection.kt)** |
| コード規模合計 | 64,551 bytes | **87,865 bytes (+36%)** |

**結論**: Androidアプリは**我が軍がリード**。同じ基盤から出発し、我が軍はUX改善(ピンチズーム、フォント、ラップ、スクロール、省スペース)に投資。おしお殿はRate Limit Monitor解析に投資。方向性の違い。

### §2.4 CI/CDギャップの実態分析

おしお殿のCI/CDは我が軍に存在しない。これは事実であり、最大の構造的弱点の一つ。

**おしお殿のテスト構成:**
```
tests/
  ├── e2e/ (12スイート)
  │   ├── e2e_basic_flow.bats      — cmd→分解→実行→報告の全フロー
  │   ├── e2e_bloom_routing.bats   — Bloom L1→Spark, L5→Sonnet, L6→Opus
  │   ├── e2e_busy_clear_guard.bats
  │   ├── e2e_clear_recovery.bats
  │   ├── e2e_codex_startup.bats
  │   ├── e2e_escalation.bats
  │   ├── e2e_idle_flag_recovery.bats
  │   ├── e2e_inbox_delivery.bats
  │   ├── e2e_parallel_tasks.bats
  │   ├── e2e_redo.bats
  │   ├── e2e_slim_retention.bats
  │   └── e2e_blocked_by.bats
  ├── unit/
  │   ├── test_cli_adapter.bats
  │   └── test_idle_flag.bats
  └── mock_behaviors/ (claude_behavior.sh, codex_behavior.sh)

GitHub Actions:
  - unit-tests (ubuntu + macOS matrix)
  - shellcheck (lib/ + scripts/)
  - e2e-tests (mock CLI, tmux環境)
  - build-check (generated instructions同期)
  - SKIP=FAIL policy (FR-054) ← 我が軍と同じ哲学
```

**我が軍の検証手段:**
- cmd_complete_gate.sh（機械検査7項目: AC照合、スタブ検出、review verdict、lesson_candidate形式...）
- GATE CLEAR率99%+、連勝340
- 別忍者レビュー必須

**ギャップの本質**: 我が軍は「実戦で品質を担保」、おしお殿は「事前にインフラの正しさを担保」。**これらは直交する**。我が軍はインフラスクリプト自体のバグを自動検知する手段がない。スクリプト変更時に既存機能が壊れても、次のcmdが失敗するまで気付かない。

### §2.5 Bloom Routing vs Round-Robin

**おしお殿のBloom Routing:**
- タスク難度をBloom Taxonomy(L1-L6)で分類
- L1-L3=安価モデル(Spark/Codex)、L4-L6=高価モデル(Sonnet/Opus)
- `get_recommended_model(bloom_level)` → `find_agent_for_model(model)` → idle agent配備
- コスト最適化が主目的

**我が軍のround-robin:**
- 配備順序のみ。モデル選択は殿が手動設定
- Opus4名 + GPT-5.4 4名の固定編成
- GATE CLEARで品質担保(モデル問わず)

**分析**: Bloom Routingは「正しいモデルに正しいタスクを振る」コスト最適化。我が軍は「どのモデルでもGATEを通れば良い」品質担保。我が軍のCLEAR率100%(全モデル)が示すように、現行タスクの難度では**モデル選択が品質のボトルネックになっていない**。ただし、コスト効率の観点では簡単なタスクにOpusを使う無駄が発生している。

---

## §3 GSD深掘り — 我が軍が学ぶべき設計パターン

### §3.1 GSDのアーキテクチャ本質

GSDは**シングルセッション型**。マルチエージェントではない。1つのClaude Codeセッション内で12のサブエージェント定義と34のワークフローをメタプロンプティングで切り替える。

これは我が軍とは根本的に異なるアプローチ:
- 我が軍: 10の独立セッション × 独立CTX窓 → ファイル通信で協調
- GSD: 1セッション × 1CTX窓 → ワークフロー切替で役割変更

**GSDの核心問題意識**: CTX窓は有限であり、埋まるにつれて品質が劣化する(Context Rot)。この問題に対するGSDの解答が以下の3つ。

### §3.2 Context Monitor(CTX生存戦の要)

```
PostToolUse hook → gsd-context-monitor.js
  ├── /tmp/.gsd-ctx-stats.json (bridge file)
  ├── 35% remaining → WARNING注入
  ├── 25% remaining → CRITICAL注入 + pause-work促進
  └── 5-tool debounce (API負荷抑制)
```

**我が軍との対比**: 我が軍はautocompact(90%)のみ。段階的警告がない。ただし我が軍は**CTX枯渇を許容して陣形図で復帰する**設計なので、枯渇前警告の価値が相対的に低い。GSDは復帰手段が脆弱(continue-here.mdのみ)なので枯渇前に止めることが必須。

### §3.3 4段階検証ラダー + スタブ検出

```
Level 1: Existence  — ファイルが存在するか
Level 2: Substantive — 中身がスタブでないか(return null, TODO, empty handler検出)
Level 3: Wiring     — import/export/呼出が正しく接続されているか
Level 4: Functional — 実行して動作するか
```

**スタブ検出パターン(gsd-verifier.md):**
- `return null` / `return undefined` / `return []` / `return {}`
- `TODO` / `FIXME` / `HACK` / `XXX` コメント
- 空のtry-catchブロック
- ハードコードされたテストデータ
- `console.log`デバッグ残留

**我が軍への取込状況**: cmd_707でスタブ検出ゲートをcmd_complete_gate.shに追加済み。分析麻痺ガードも追加済み。

### §3.4 Deviation Management(逸脱管理)

```
Rule 1: バグ修正     → 自分で直せ(事後報告)
Rule 2: ブロッカー   → 自分で解決(事後報告)
Rule 3: 必須品質追加 → 自分で追加(事後報告)
Rule 4: 設計変更     → 停止して報告
```

**我が軍への取込状況**: cmd_708でashigaru.mdに追加済み。F003の明示的例外として整合。

---

## §4 ACE・Vercel・Claude Teams — 簡潔な位置付け

### §4.1 ACE (Agentic Context Engineering)

ICLR 2026採択。3役割パイプライン(Generator→Reflector→Curator)による完全自動教訓サイクル。

**我が軍との関係**: 我が軍の教訓サイクルはACEに最も近い。ただし以下の差異:
- ACE: embedding類似度でsemantic dedup → 我が軍: タグマッチ(テキストベース)
- ACE: harmful自動検出 → 我が軍: 効果率監視+自動退役(閾値10%未満)
- ACE: 人間不要 → 我が軍: 家老が最終登録判断

**学び**: ACEのsemantic dedupは教訓が200件を超えた段階で価値が出る。現在152件、検討時期が近い。

### §4.2 Vercel Context Engineering

「受動的コンテキスト(成功率100%) > 能動的取得(79%)」。ツール80%削減。

**我が軍への取込状況**: Vercel式2層圧縮(索引+詳細分離)を全面導入済み。MEMORY.md→MCP Memory、context/*.md→docs/research/の2層構造。これは**我が軍の基盤設計に組み込まれた**。

### §4.3 Claude Code Agent Teams

experimental。lead→teammate 2層。worktree隔離。

**cmd_630で不適合確定**: セッション再開不可、1チーム/セッション制限、リード固定。我が軍の8忍者永続稼働+任意復帰と根本的に相容れない。最新状況(2026-03-09): TeammateIdle hook追加、Plan Approval追加。依然experimental。

---

## §5 14軸対比表

### §5.1 構造・コンテキスト

| 軸 | 我が軍 | おしお殿 | GSD | ACE | Vercel | Teams |
|----|--------|---------|-----|-----|--------|-------|
| エージェント構造 | 4層(殿→将軍→家老→忍者8) | 4層(殿→将軍→家老→足軽7+軍師) | 1+サブ12 | 3役割線形 | 単体 | 2層(lead→3-5) |
| モデル混成 | Opus4+GPT-5.4 4(dual vendor) | Claude+Codex+Copilot+Kimi(4CLI) | 単一 | 単一 | 単一 | 任意 |
| CTX崩壊防止 | Vercel2層+autocompact+/clear+陣形図復帰 | YAML Slim+/clear+ASW escalation | Monitor(35%/25%)+Fractal Sum+pause | delta蓄積 | 3層pipe | 独立CTX窓 |
| 知識永続化 | 6層(CLAUDE/instr/proj/lessons/queue/MCP) | 4層(MCP/PJ/YAML/session) | state+milestone+SUMMARY | playbook | AGENTS.md+Skills | CLAUDE.md(揮発) |
| 復帰耐性 | 陣形図+hook+inbox(完全復帰) | /clear Recovery+ASW+flag file | continue-here.md | playbook再読 | AGENTS.md再読 | 再開不可 |

### §5.2 品質・知識

| 軸 | 我が軍 | おしお殿 | GSD | ACE | Vercel | Teams |
|----|--------|---------|-----|-----|--------|-------|
| 品質ゲート | GATE機械検査7項目(BLOCK/CLEAR強制) | なし(軍師QCは助言のみ) | 4段階検証ラダー+Nyquist | Evaluator自動 | Sandbox | Plan Approval+hooks |
| レビュー | 別忍者レビュー必須 | 軍師QC(Bloom L4+) | gsd-verifier(goal-backward) | Reflector | 人間 | リード承認 |
| 教訓サイクル | 8段階(発見→淘汰)+効果率計測+自動退役 | MCP自由形式(サイクルなし) | なし | 3段階(自動) | なし | なし |
| 実績計測 | CLEAR率99%+、連勝340、手戻り率1.3% | selfwatch metrics | なし | AppWorld+10.6% | 成功率80→100% | なし |

### §5.3 運用・安全

| 軸 | 我が軍 | おしお殿 | GSD | ACE | Vercel | Teams |
|----|--------|---------|-----|-----|--------|-------|
| CI/CD | **なし** | GitHub Actions(unit+e2e+shellcheck+build) | なし | なし | なし | なし |
| 安全防御 | D001-D008+PreToolUse+WSL2保護 | D001-D008+settings.json deny | skip-permissions推奨 | なし | Sandbox | hooks+perm |
| セットアップ | 複雑(tmux+WSL2+8忍者) | 中(first_setup.sh+macOS互換) | 簡単(npx一発) | 中(Python) | 簡単(AGENTS.md) | 簡単(設定1行) |
| 通信方式 | flock mailbox+inotify(2層保証) | flock mailbox+inotify+ASW 3phase | なし | 線形pipe | なし | SendMessage+broadcast |
| Androidアプリ | **v5.0**(+ピンチズーム+フォント+ラップ+スクロール) | v4.1(基本機能+Rate Limit解析) | なし | なし | なし | なし |
| 人間連携 | 殿→将軍(鎖)+ntfy | 殿→将軍(鎖)+ntfy+Android操作 | 対話型cmd | 人間なし | HITL | リード経由 |

---

## §6 率直な自己評価 — 我が軍の本当の弱点

忍者分析版(§7)のスコアリングは我が軍を過大評価していた。以下、率直な弱点。

### 6.1 CI/CDの不在（深刻度: 高）

おしお殿は12のE2Eテスト+ユニットテスト+shellcheck+build checkをGitHub Actionsで自動実行。我が軍にはゼロ。

**実害**: スクリプト変更時の回帰バグを事前に検知できない。cmd_complete_gate.shはタスク成果物の品質を検査するが、**インフラ自体の品質を検査しない**。gate.shにバグが入ったら、そのバグが検知される仕組みがない。

### 6.2 セットアップの複雑さ（深刻度: 中）

おしお殿はfirst_setup.shでワンクリック初期設定。macOS互換。我が軍はWSL2専用で手動セットアップ。

**実害**: 殿以外の人間が使うことが事実上不可能。ただし、現時点で殿以外のユーザーを想定していないため、実害は限定的。

### 6.3 Bloom Routing不在（深刻度: 低）

タスク難度に関わらず同じモデルに振るため、簡単なタスクにOpusを使うコスト無駄が発生。

**ただし**: 全モデルでCLEAR率100%が示すように、品質面での影響はゼロ。コスト最適化の問題のみ。

### 6.4 単一環境依存（深刻度: 中）

WSL2 + Windows固定。macOS/純Linux環境では動作未検証。

### 6.5 OSS非公開（深刻度: 判断保留）

おしお殿は1,035 stars。外部フィードバック・貢献がある。我が軍は非公開で全て自己完結。これが弱点かどうかは殿の戦略判断による。

---

## §7 各システムから学ぶべきこと（優先度付き）

### 取込済み（cmd_707/708で実装完了）

| 元システム | 取込内容 | 実装cmd |
|-----------|---------|---------|
| GSD | スタブ検出ゲート(cmd_complete_gate.sh) | cmd_707 |
| GSD | 分析麻痺ガード(5回連続Read/Grep→停止) | cmd_707 |
| GSD | 4観点並行偵察(Stack/Features/Architecture/Pitfalls) | cmd_707 |
| GSD | 逸脱管理ルール(Deviation Management 4段階) | cmd_708 |
| GSD | 認知バイアスガード(偵察タスク自動適用) | cmd_708 |
| Vercel | 2層圧縮(索引+詳細分離) | 恒久運用中 |

### 検討候補（Phase 3以降）

| # | 元システム | 取込候補 | 優先度 | 理由 |
|---|-----------|---------|--------|------|
| 1 | **おしお殿** | CI/CD基盤(bats E2E) | **高** | インフラ品質の唯一の盲点。GATE CLEARはタスク品質、CI/CDはインフラ品質。直交する価値 |
| 2 | **GSD** | Context Monitor(CTX残量段階警告) | 中 | 陣形図復帰があるため緊急度は低いが、不要な/clearを減らせる可能性 |
| 3 | **おしお殿** | YAML Slim(作業前圧縮) | 中 | archive_completed.shは完了後のみ。作業前のCTX節約は別の価値 |
| 4 | **おしお殿** | Bloom Routing | 低 | コスト最適化のみ。品質影響なし。殿がモデル編成を手動管理する現行で問題なし |
| 5 | **GSD** | Checkpoint分類(human-verify/decision/human-action) | 低 | 殿裁定フローの明文化に使えるが、現行PDフローで十分機能中 |
| 6 | **ACE** | Semantic dedup | 低 | 教訓200件超で検討。現在152件 |

---

## §8 総合スコア（修正版）

忍者版のスコアリングは評価基準が不明確で、我が軍寄りのバイアスがあった。以下、基準を明示した修正版。

**採点基準**: 各軸の「設計目的をどれだけ達成しているか」を評価。10=その軸で最も洗練された実装。

| # | 軸 | 我が軍 | おしお殿 | GSD | ACE | Vercel | Teams | 最高評価の根拠 |
|---|------|--------|---------|-----|-----|--------|-------|------------|
| 1 | CTX管理 | 8 | 7 | **9** | 7 | 8 | 5 | GSD: 段階警告+pause+resume体系が最も成熟 |
| 2 | マルチエージェント | **9** | **9** | 3 | 5 | 1 | 7 | 我が軍/おしお殿: 10名実稼働+4層指揮 |
| 3 | 状態管理 | **9** | 7 | 6 | 5 | 4 | 3 | 我が軍: 陣形図+hook+inbox完全復帰 |
| 4 | 知識永続化 | **9** | 6 | 5 | 7 | 7 | 3 | 我が軍: 6層+Vercel圧縮+教訓サイクル |
| 5 | 品質ゲート | 8 | 4 | **9** | 7 | 6 | 5 | GSD: 4段階ラダー+Nyquist+goal-backward |
| 6 | CI/CD | 1 | **8** | 2 | 2 | 2 | 2 | おしお殿: unit+e2e+shellcheck+build一貫 |
| 7 | 復帰機構 | **9** | 8 | 7 | 5 | 4 | 2 | 我が軍: compaction/crash後も陣形図で完全復帰 |
| 8 | 検証機構 | 7 | 6 | **9** | 7 | 6 | 5 | GSD: スタブ検出+wiring+functional検証 |
| 9 | 拡張性 | 6 | **8** | 8 | 4 | 7 | 6 | おしお殿: 4CLI+macOS+first_setup |
| 10 | 運用実績 | **9** | 7 | 4 | 8 | 7 | 2 | 我が軍: 710cmd+連勝340の定量証拠 |
| 11 | 通信信頼性 | **9** | **9** | 1 | 5 | 1 | 6 | flock+inotify+nudge 2層。両陣営同等 |
| 12 | 人間連携 | 7 | **8** | 7 | 2 | 8 | 6 | おしお殿: Android操作+ntfy+音声 |
| 13 | 安全性 | **9** | **9** | 2 | 3 | 3 | 5 | D001-D008+構造防御。両陣営同等 |
| 14 | セットアップ | 2 | 5 | **9** | 5 | **9** | 8 | GSD/Vercel: ほぼゼロコンフィグ |
| | **合計** | **102** | **101** | **81** | **72** | **73** | **65** | |

### 忍者版(§7)との差分

| 変更 | 忍者版 | 修正版 | 理由 |
|------|--------|--------|------|
| 我が軍合計 | 119 | **102** | CI/CD=1(忍者版は軸自体がなかった)、セットアップ=2、品質ゲート-1(GSDスタブ検出取込前提で8→取込後も9には届かない) |
| おしお殿合計 | 105 | **101** | CI/CD=8追加、通信・安全を同等評価に修正。品質ゲート-1(GATEなしは痛い) |
| GSD合計 | 83 | **81** | 妥当な範囲 |
| 差 | 14点差 | **1点差** | 我が軍とおしお殿は**ほぼ互角**。CI/CDの有無が最大の差別化要因 |

**最重要な発見**: 我が軍とおしお殿の差は1点。**CI/CD導入が最大のROI改善策**。

---

## §9 戦略的含意

### 9.1 おしお殿との関係

同根からの分岐であり、**補完的に進化**している。おしお殿が「広さ」を追求する間に我が軍は「深さ」を追求した。両方の長所を統合すれば、どちらか単独より強くなる。

### 9.2 GSDとの関係

設計思想が根本的に異なる(シングルセッション vs マルチエージェント)。だが、GSDの「検証の徹底」は汎用的に価値がある。cmd_707/708で主要パターンを取り込み済み。

### 9.3 我が軍の次の一手

1. **CI/CD導入**(おしお殿から学ぶ) — インフラ品質の盲点を埋める
2. **GSD Phase 3検討**(Checkpoint分類+Wiring検証) — 殿判断待ち
3. **教訓200件到達時のsemantic dedup検討**(ACEから学ぶ)

---

## §10 参考文献

| システム | 情報源 | 最終確認 |
|---------|--------|---------|
| GSD | [gsd-build/get-shit-done](https://github.com/gsd-build/get-shit-done) 26,786 stars | 2026-03-09 |
| おしお殿 | [yohey-w/multi-agent-shogun](https://github.com/yohey-w/multi-agent-shogun) 1,035 stars | 2026-03-09 |
| ACE | → `docs/research/five-system-comparison.md` §4.1 | 2026-03-01 |
| Vercel | → `docs/research/five-system-comparison.md` §4.2 | 2026-02-25 |
| Claude Teams | [code.claude.com/docs/en/agent-teams](https://code.claude.com/docs/en/agent-teams) | 2026-03-09 |
