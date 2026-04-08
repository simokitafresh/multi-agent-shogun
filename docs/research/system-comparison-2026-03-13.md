# 7システム対比分析（2026-03-13最新版）

<!-- updated: 2026-03-13 殿指示による全システム最新調査 -->
<!-- systems: ACE / Vercel / GSD / gstack / おしお殿 / Claude Teams / 我が軍 -->
<!-- previous: cmd_709_system-comparison.md (2026-03-09) -->

> 前回(cmd_709)の6システムにgstackを追加した7システム対比。各システムの最新状態を反映。

---

## §1 一覧対比表（横串）

### §1.1 設計思想

| システム | 作者 | 設計信念 | 一言で言うと |
|---------|------|---------|------------|
| **ACE** | Dave Shapiro | 道徳的羅針盤(L1)が全ての行動を規定する。学習は自動化できる | 「倫理的自動進化」 |
| **Vercel** | Vercel社 | 受動的コンテキスト(100%) > 能動的取得(79%)。検索させるな、置いておけ | 「極限の受動配置」 |
| **GSD** | glittercowboy | Context Rotが品質劣化の根因。CTX残量こそが最重要KPI | 「コンテキスト生存戦」 |
| **gstack** | Garry Tan (YC CEO) | 1つのLLMを認知モード切替で専門家チームにする。Planning is not review | 「認知モード切替」 |
| **おしお殿** | shio_shoppaize | 多くのCLI・多くの環境・多くの人が使えることが価値。OSS公開 | 「アクセシビリティ優先」 |
| **Claude Teams** | Anthropic | 協調プリミティブはプラットフォームが提供すべき | 「ネイティブ統合の賭け」 |
| **我が軍** | 殿+将軍 | 品質は計測しなければ改善できない。知識は循環しなければ腐る | 「計測と循環の規律」 |

### §1.2 基本スペック

| | ACE | Vercel | GSD | gstack | おしお殿 | Claude Teams | 我が軍 |
|---|---|---|---|---|---|---|---|
| **状態** | アーカイブ(2024-08) | 本番稼働 | OSS v1.22.4 | OSS v0.0.2 | OSS v4.0 ★1045 | 商用β | 非公開本番 |
| **Stars** | 1,500 | — | **28,539** | 414 | 1,045 | — | — |
| **エージェント数** | 6層(理論) | 1+AutoFix | 11特化 | 1×6モード | 1+1+7+1=10 | 可変 | 1+1+8=10 |
| **並列実行** | 理論のみ | AutoFix並列 | Wave-based | 不可 | 足軽7並列 | スレッド | **忍者8並列** |
| **通信方式** | Dual Bus(理論) | SDK API | ファイル(.planning/) | なし(単一) | YAML+inbox | SDK native | YAML+inbox |
| **記憶** | Playbook自動進化 | AGENTS.md(8KB索引) | STATE.md+CONTEXT.md | なし | MCP+3層 | プラットフォーム | MCP+6層Vercel式 |
| **品質ゲート** | なし(理論) | AutoFix RFT | 4段階+Nyquist | checklist.md | 軍師QC | なし | **GATE7項目+レビュー** |
| **教訓蓄積** | ACE的自動進化 | なし | なし | retro JSON | なし | なし | **lessons.yaml循環** |
| **ブラウザ** | なし | agent-browser(ref式) | なし | browse(Playwright daemon) | CDP直接 | なし | **CDP(Chrome直接,daemon+ref実装済)** |
| **CI/CD** | なし | GitHub Actions | **v1.21.1で導入** | なし | **あり** | — | **GATE7項目+pre-push hook+CI赤検知** |
| **モバイル** | なし | なし | なし | なし | **Android App v4.0** | なし | **Android Companion App**(おしお殿版をクローン+改良。SSH+音声+8ペイン+dashboard+スクショ共有) |

### §1.3 プロンプトテクニック

| テクニック | ACE | Vercel | GSD | gstack | おしお殿 | 我が軍 |
|-----------|-----|--------|-----|--------|---------|--------|
| Suppressions(偽陽性抑制) | — | — | — | **9項目** | — | **導入済(cmd_875)** |
| 停止条件の二分法 | — | — | — | **stop/never_stop** | — | **導入済(cmd_875)** |
| 推薦先行+WHY | — | — | — | **"judgment, not menu"** | — | **導入済(cmd_875)** |
| モードコミットメント | — | — | — | **3モード+drift防止** | — | 偵察/実装分離で類似 |
| 反復STOP | — | — | — | **11回反復** | — | AC完了時checkpoint |
| Priority Hierarchy | — | — | — | **不等号表記** | — | **導入済(cmd_875)** |
| Engineering Preferences | — | — | — | **6項目マッピング** | — | **導入中(cmd_876)** |
| パッシブコンテキスト | Playbook | **100%=AGENTS.md** | STATE.md | — | Global Context | **CLAUDE.md索引+context** |
| コンテキスト圧縮 | — | **80%圧縮で100%維持** | CTX Monitor | — | — | **Vercel式2層** |
| 4観点独立分析 | — | — | **Stack/Feat/Arch/Pit** | — | — | **GSD式偵察** |
| Bloom Taxonomy | — | — | — | — | **L1-L6ルーティング** | 手動偵察/実装指定 |
| Spec-First | — | — | **Spec→Test→Impl** | plan→review→ship | Spec-First | **cmd→AC→報告→レビュー** |
| 中立プロンプト | — | — | — | — | — | **殿指示で導入** |
| Nyquist Validation | — | — | **テストカバレッジ契約** | — | — | SKIP=FAIL |
| Requirements Trace | — | — | **REQ-ID全貫通** | — | — | AC_version追跡 |

---

## §2 各システム最新状態（詳細）

### §2.1 ACE — アーカイブ後の思想的影響

**状態**: フレームワーク開発終了。Shapiroは著述・社会経済研究に移行。

**最新見解(2026-01)**: OpenClawを「最も成功した自律エージェントフレームワーク」と評価しつつ、「Aspirational Layer(道徳的羅針盤)が欠けている」と指摘。`CONSTITUTION.md`による倫理的制約の付与を提案。

**6層(最終版)**:
- L1 Aspirational: 道徳的羅針盤(Heuristic Imperatives: 苦痛削減/繁栄増大/理解増進)
- L2 Global Strategy: 環境+使命→戦略計画
- L3 Agent Model: 自己モデリング・自己認識
- L4 Executive Function: 戦略→実行計画変換
- L5 Cognitive Control: タスク選択・切替
- L6 Task Prosecution: 単一タスク実行

**我が軍との対応**: L1=殿の裁定, L2=将軍, L3=陣形図, L4=家老, L5=家老(配備), L6=忍者。Heuristic Imperativesに相当する明示的道徳フレームワークは我が軍にはない(鎖の原理で代替)。

### §2.2 Vercel — 定量評価の権威

**最新(2026-03)**:
- **AGENTS.md 100% vs Skills 79%**: パッシブコンテキストの定量的優位を実証
- **v0 Composite Model**: RAG層+ベースLLM+AutoFix層の3層合成。93%エラーフリー
- **ツール削減**: 17→2ツールで成功率80%→100%、トークン37%削減、3.5倍高速
- **Agent-Browser**: Rust CLI+Playwright。**アクセシビリティツリーref方式**（gstackと同じ手法）
- **AI Gateway**: Claude Code Maxをエンタープライズ統合

**核心の教訓**: 「モデルの推論を信頼せず制約していた。ツールを減らしたらモデルが自由に考えられるようになった」

**我が軍への示唆**: 我が軍のCLAUDE.md索引+context詳細の構造はVercel評価と定量的に整合。Agent-Browserのref方式はgstack browseと同技術（cmd_877で導入完了）。

### §2.3 GSD — 高速進化中

**最新v1.22.4(2026-03-03)**:
- **★28,539**(前回26,786から+1,753)。成長継続
- **CI/CD導入済み**: 428テスト + GitHub Actions (3 OS x 3 Node)。前回「GSDにない」→**解消**
- **Nyquist Validation**: plan前にテストカバレッジを契約。Wave 0でテスト基盤先行構築
- **Requirements Traceability全貫通**: REQ-IDがplanner→checker→executor→verifier全チェーンを貫通
- **Context Monitor**: PostToolUse hookで35% WARNING / 25% CRITICAL
- **Codexマルチエージェント対応**: v1.22.0

**エコシステム拡大**: gsd-teams(チーム対応), gsd-orchestrator(/clear自動化), GSD-LAW(法律文書), UCAI(対抗馬)等。

**我が軍への新規取込候補**: Nyquist Validation(テストカバレッジ契約)が中程度の優先度。他は既に取込済みまたはAC体系で同等。

### §2.4 gstack — プロンプトの匠

**最新v0.0.2(2026-03-12)**:
- 6スキル: /plan-ceo-review, /plan-eng-review, /review, /ship, /browse, /retro
- **browse**: Playwright persistent daemon + ref-based要素選択。100-200ms/コマンド
- **プロンプトテクニック8種**: Suppressions/停止条件二分法/推薦先行/モードコミットメント/反復STOP/Priority Hierarchy/Engineering Preferences/Escape Hatch

**TODO.mdロードマップ**: Phase 3で自律QAエージェント、Phase 6でCDPモード（我々と同じ着想）。

**設計哲学**: `"Browser is the nervous system, skills are the product"`

**我が軍への適用**: 8テクニック全てをcmd_875(完了)/876(進行中)で導入。browse技術はcmd_877でCDP daemon+ref化を完了。

→ 全詳細: `docs/research/gstack-analysis.md`

### §2.5 おしお殿 — 元祖、OSS展開

**最新v4.0(2026-02-28)**:
- **Android Companion App**: SSH+音声入力+8ペイン表示
- **Bloom Taxonomy**: L1-L3→足軽, L4-L6→軍師。自動ルーティング
- **軍師新設(v3.4)**: 「考える専門」のOpus専任係。家老はSonnetに自己降格
- **Flag File Busy Detection(v3.8)**: 48回の修正試行の末に到達
- **コンテキスト設計論考**: 「Judgment Criteria Is All You Need」仮説。LoRAで判断基準をモデル重みに焼き込むことが本質的解決策
- **Zenn 26記事、総いいね2,917**

**おしお殿の独自知見**:
1. Thinking無効化(MAX_THINKING_TOKENS=0)で将軍を「考えるな、委譲しろ」に
2. 家老の自己降格提案(AI自身がモデルダウングレードを提案)
3. 7つの未解決問題(コンテキスト分散の形式理論、N二乗通信問題等)
4. Flag File Busy Detection(48回の試行で忍者idle検知を解決)
5. CDPブラウザ操作(我々と独立で同じ技術に到達)

**我が軍との共通点**: inbox_write.sh、inotifywait、send-keys禁止、D001-D008、SKIP=FAIL、CDP、ntfy等。**独立進化した双子**。

**直接的な技術移転**: 我が軍のAndroid Companion Appはおしお殿のAndroid Appをクローンし改良したもの。BGM機能は削減。SSH+音声+8ペイン+dashboard+スクショ共有は継承・拡張。

**差異の本質**: おしお殿=広さ(OSS/4CLI/macOS/Android/学術言語化)、我が軍=深さ(GATE/教訓サイクル/Vercel圧縮/鎖の原理)。

→ おしお殿リスペクト原則: おしお殿は元祖。対比記事で優劣を論じるな（殿厳命）。

### §2.6 Claude Teams — プラットフォーム統合

前回(cmd_709)から大きな変化なし。Anthropic公式のマルチエージェント基盤。
SDK経由のネイティブ協調。我が軍はcmd_630でAgent Teams不適合を確定(tmux案が最適)。

---

## §3 横串比較テーブル（機能マトリクス）

### §3.1 知識管理

| | ACE | Vercel | GSD | gstack | おしお殿 | 我が軍 |
|---|---|---|---|---|---|---|
| 恒久ルール | L1定義 | AGENTS.md | — | SKILL.md内 | CLAUDE.md(500行) | **CLAUDE.md+instructions/** |
| PJ知識 | — | .next-docs/ | .planning/ | — | Global/Project Context | **projects/*.yaml** |
| 教訓 | Playbook自動 | — | — | retro JSON | — | **lessons.yaml循環** |
| 索引-詳細分離 | — | **AGENTS.md→docs** | STATE.md→files | — | — | **context→docs/research** |
| 永続記憶 | — | — | CONTEXT.md | — | MCP Memory | **MCP Memory** |
| 圧縮率 | — | **80%(40→8KB)** | CTX Monitor | — | — | **Vercel式2層** |

### §3.2 品質保証

| | ACE | Vercel | GSD | gstack | おしお殿 | 我が軍 |
|---|---|---|---|---|---|---|
| 自動ゲート | — | AutoFix RFT | 4段階 | /review checklist | — | **GATE 7項目** |
| コードレビュー | — | — | plan-checker | /review 2-pass | 軍師QC | **別忍者レビュー必須** |
| テスト | — | サンドボックス | Nyquist | — | SKIP=FAIL | **SKIP=FAIL** |
| CI/CD | — | GitHub Actions | **428テスト+3OS** | — | **あり** | gate WARN |
| 教訓→改善ループ | Playbook | — | — | retro trend | — | **注入→計測→退役** |

### §3.3 ブラウザ自動化

| | Vercel | gstack | おしお殿 | 我が軍 |
|---|---|---|---|---|
| 技術 | Playwright(Rust CLI) | Playwright(Bun daemon) | CDP(PowerShell経由) | **CDP(Pure Python, Chrome直接)** |
| 要素選択 | **@ref(AXTree)** | **@ref(AXTree)** | CSS/XPath | **@ref(AXTree) 実装済(cmd_877)** |
| 永続性 | — | **daemon(100-200ms)** | 毎回接続 | **daemon実装済(cmd_877)** |
| GUI制御 | headless | headless | **GUIブラウザ直接** | **GUIブラウザ直接(Chrome port 9222)** |
| トークン効率 | ref:200-400tok | ref:200-400tok | DOM直接 | **ref:200-400tok(cmd_877)** |
| 改善計画 | — | Phase6でCDP対応 | — | ✅**cmd_877完了: daemon+ref+CLI** |

### §3.4 運用自動化・通知

| | ACE | Vercel | GSD | gstack | おしお殿 | 我が軍 |
|---|---|---|---|---|---|---|
| 外部通知 | — | — | — | — | ntfy | **ntfy(dual watchdog)** |
| エージェント自動復旧 | — | — | — | — | Flag File Busy | **ninja_monitor(STALL/消失→自動回復)** |
| CTX自動管理 | — | — | CTX Monitor | — | — | **AUTOCOMPACT(90%)+ninja_monitor idle /clear** |
| ダッシュボード | — | — | — | — | — | **自動更新(忍者配備+メトリクス+教訓健全度)** |
| モバイル制御 | — | — | — | — | **Android SSH+8ペイン** | **Android(おしお殿版クローン+改良): SSH+音声+8ペイン+dashboard** |
| 音声入力 | — | — | — | — | **あり** | **Android音声認識(日本語連続)** |
| スクショ共有 | — | — | — | — | ntfy経由 | **Android Share Sheet→SFTP転送+ntfy受信** |

### §3.5 スコア（前回+gstack更新+Android/運用反映）

| 軸 | ACE | Vercel | GSD | gstack | おしお殿 | Claude Teams | 我が軍 |
|---|---|---|---|---|---|---|---|
| 知識管理 | 3 | 8 | 6 | 2 | 7 | 4 | **9** |
| 品質保証 | 1 | 7 | 8 | 7 | 5 | 3 | **9** |
| 並列実行 | 1 | 3 | 6 | 1 | 8 | 5 | **9** |
| プロンプト技術 | 2 | 5 | 7 | **9** | 6 | 3 | 7→**8**(gstack導入後) |
| ブラウザ | 0 | 7 | 0 | **8** | 6 | 0 | **8**(cmd_877完了: daemon+ref) |
| 教訓循環 | 6 | 0 | 1 | 2 | 0 | 0 | **9** |
| 運用自動化 | 0 | 3 | 4 | 0 | 6 | 2 | **9** |
| モバイル | 0 | 0 | 0 | 0 | **8** | 0 | **8**(おしお殿版クローン+改良、BGM削減) |
| エコシステム | 3 | 8 | **9** | 3 | **7** | 6 | 1 |
| 合計 | 16 | 41 | 41 | 32 | 53 | 23 | **60→70** |

---

## §4 盗取可能リスト（未着手分）

cmd_875-877で着手中の12項目に加え、今回の最新調査で新たに判明した候補。

| # | 出典 | テクニック | 価値 | 優先度 |
|---|------|-----------|------|--------|
| 1 | GSD v1.22 | Nyquist Validation(テストカバレッジ契約) | plan前にテスト設計強制 | 中 |
| 2 | Vercel | ツール削減(17→2で100%) | 検討の価値あり。ただし我が軍はマルチエージェント | 低 |
| 3 | Vercel | AutoFix RFT(カスタム小モデル) | エラー修正専用層。我が軍はGATEで代替 | 低 |
| 4 | おしお殿 | Bloom Taxonomy自動ルーティング | L1-L3→軽量モデル, L4-L6→重量モデル | 中 |
| 5 | おしお殿 | 軍師(考える専門係) | 偵察cmdで代替済みだが、専任化の価値は検討 | 低 |
| 6 | ACE | Heuristic Imperatives(道徳的羅針盤) | CONSTITUTION.md的なもの。鎖の原理で代替中 | 低 |
| 7 | GSD v1.22 | Cold-start smoke test | サーバ変更時の起動テスト自動注入 | 低 |

---

## §5 各システムの哲学的ポジショニング

```
        個人最適化 ────────────────────── 組織最適化
            │                                │
   gstack ──┤                                ├── 我が軍
            │                                │
            │              GSD ──────────────┤
            │                                │
            │                   おしお殿 ────┤
            │                                │
            └── Vercel ──────────────────────┘

   理論的 ──────────────────────────── 実践的
            │                                │
    ACE ────┤                                ├── gstack
            │                                │
            │         Claude Teams ──────────┤
            │                                │
            │              Vercel ───────────┤
            │                                │
            │                    GSD ────────┤
            │                                │
            └── おしお殿 ── 我が軍 ──────────┘
```

---

## §6 出典

| システム | 主要ソース |
|---------|-----------|
| ACE | arXiv:2310.06775, github.com/daveshap/ACE_Framework (archived) |
| Vercel | vercel.com/blog/agents-md-*, agent-browser, v0-composite-model |
| GSD | github.com/glittercowboy/get-shit-done v1.22.4 |
| gstack | github.com/garrytan/gstack v0.0.2, → `docs/research/gstack-analysis.md` |
| おしお殿 | github.com/yohey-w/multi-agent-shogun v4.0, zenn.dev/shio_shoppaize (26記事) |
| Claude Teams | docs.anthropic.com |
| 前回対比 | `docs/research/cmd_709_system-comparison.md` |
