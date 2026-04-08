# gstack (garrytan/gstack) 全分析

<!-- source: 殿直接指示による調査 2026-03-13 -->
<!-- repo: https://github.com/garrytan/gstack (MIT, Garry Tan / YC CEO) -->
<!-- version: 0.0.2 (2026-03-12) -->

> Claude Code用6スキルツールキット。1エージェントを6つの認知モードに切替える。
> 我が軍への適用価値: プロンプトエンジニアリングテクニック群。

## §1 概要

6 slash commands = 6認知モード。個人開発者(Garry Tan)のワークフロー最適化ツール。

| Skill | Mode | 核心の問い |
|-------|------|-----------|
| `/plan-ceo-review` | 創業者/CEO | 正しい問題を解いているか？10-star productは？ |
| `/plan-eng-review` | エンジニアリングマネージャー | 構築可能か？アーキテクチャは？ |
| `/review` | パラノイアなスタッフエンジニア | CIを通過してprodで爆発するバグは？ |
| `/ship` | リリースエンジニア | ただ出せ。確認するな |
| `/browse` | QAエンジニア | エージェントに目を与える。ブラウザ自動操作 |
| `/retro` | エンジニアリングマネージャー | 今週何が起きたか？データで |

## §2 プロンプトテクニック一覧（我が軍適用候補）

### §2.1 Suppressions（偽陽性抑制リスト）

review/checklist.mdから。LLMレビューの最大の弱点「false positive洪水」を制御。

**全9項目**:
1. `present?`が`length > 20`と冗長でも可読性があれば指摘するな
2. 「この閾値/定数の理由をコメントせよ」→ 閾値はチューニングで常に変わる、コメントは腐る
3. 「アサーションをもっと厳密に」→ 動作をカバーしていれば十分
4. 一貫性だけの変更提案（他の定数と同じguardで囲めとか）
5. 「正規表現がエッジケースXを扱えない」→ 入力が制約されXは実際に発生しない場合
6. 「テストが複数ガードを同時にテストしている」→ それで良い
7. Eval閾値の変更 → 経験的チューニングなので常に変わる
8. 無害なno-op（配列に絶対いない要素への.reject等）
9. **レビュー対象のdiffで既に対処済みの問題** → diffを全部読んでからコメントせよ

**適用先**: 偵察cmdの品質4要件に「報告不要な発見リスト」として追加。家老の報告レビューにも適用可能。

### §2.2 停止条件の二分法

/shipの核心。LLMの過剰確認を構造的に排除。

```
Only stop for:
  - mainブランチ（即中止）
  - 自動解決不能なmerge conflict
  - テスト失敗
  - Pre-landing reviewでCRITICAL発見 & ユーザーがfix選択
  - MINOR/MAJORバージョンバンプ判断

Never stop for:
  - uncommitted changes（常に含める）
  - バージョンバンプ選択（MICRO/PATCHは自動）
  - CHANGELOG内容（自動生成）
  - コミットメッセージ承認（自動）
  - 複数ファイル変更（bisectable commitsに自動分割）
```

冒頭宣言: `"This is a non-interactive, fully automated workflow. Do NOT ask for confirmation at any step. The user said /ship which means DO IT."`

**適用先**: タスクYAMLに`stop_for`/`never_stop_for`フィールド追加。忍者の不要確認を構造的排除。

### §2.3 「判断を述べよ、メニューを出すな」

```
"Be opinionated. I'm paying for your judgment, not a menu."
"Lead with your recommendation. State it as a directive: 'Do B. Here's why:' — not 'Option B might be worth considering.'"
```

AskUserQuestion制御の全ルール:
- 1 issue = 1 question（バッチ禁止）
- 推薦を先に述べよ。命令形で
- WHYを1-2文で、Engineering Preferencesにマッピング
- 2-3選択肢を提示（「何もしない」を含む）
- 自明な修正は質問せずに実行して先に進め（Escape Hatch）
- Open-ended質問は4カテゴリのみ許可（開発者意図/アーキテクチャ方向/12ヶ月目標/ユーザー体験の曖昧さ）

**適用先**: 偵察テンプレートの報告形式を「推薦先行+WHY」に変更。

### §2.4 モードコミットメント

3モードから選択後、最後まで維持する仕組み:

| モード | メタファー | 核心の問い |
|--------|-----------|-----------|
| SCOPE EXPANSION | `building a cathedral` | `10x more ambitious for 2x the effort?` |
| HOLD SCOPE | `a rigorous reviewer` | このスコープを完璧にせよ |
| SCOPE REDUCTION | `a surgeon` | `minimum viable version` |

**Drift防止**: `"Do not silently drift toward a different mode. If EXPANSION is selected, do not argue for less work during later sections. If REDUCTION is selected, do not sneak scope back in."`

**適用先**: 偵察cmd vs 実装cmdの境界をタスクYAMLで明示。偵察中に実装を始める問題を封じる。

### §2.5 反復STOP

全10セクション末尾に同一のSTOP指示を11回繰り返し:
```
STOP. AskUserQuestion once per issue. Do NOT batch. Recommend + WHY.
If no issues or fix is obvious, state what you'll do and move on — don't waste a question.
Do NOT proceed until user responds.
```

LLMは長いプロンプトの中盤の指示を忘れる。力技だが確実な対策。

**適用先**: タスクYAMLのACが多い場合、各AC完了後にCHECKPOINTを挟む。

### §2.6 Priority Hierarchy（不等号表記）

```
Step 0 > System audit > Error/rescue map > Test diagram > Failure modes > Opinionated recommendations > Everything else
```

CTX圧迫時に何を捨てるかを事前定義。不等号が視覚的に明瞭。

**適用先**: タスクYAMLのACに`priority: AC1 > AC2 > AC3`を追加。

### §2.7 Engineering Preferences事前注入

6項目の判断基準をプロンプトに埋め込み、全推薦をこの基準にマッピング:
```
* DRY is important—flag repetition aggressively.
* Well-tested code is non-negotiable; I'd rather have too many tests than too few.
* I want code that's "engineered enough" — not under/over-engineered.
* I err on the side of handling more edge cases, not fewer.
* Bias toward explicit over clever.
* Minimal diff: fewest new abstractions and files touched.
```

**適用先**: `projects/{id}.yaml`にPJ固有のEngineering Preferencesセクション追加。

### §2.8 「名前をつけろ」パターン

```
"Don't say 'handle errors.' Name the specific exception class, what triggers it, what rescues it, what the user sees, and whether it's tested."
"rescue StandardError is ALWAYS a smell."
```

LLMの抽象的回答を封じ、具体性を強制。

**適用先**: 偵察品質4要件の強化。「問題がある」→「{ファイル}のL{行}の{関数}が{条件}で{例外}を投げる」を要求。

### §2.9 並列実行の明示指示

```
"Run ALL of these git commands in parallel (they are independent)"
```

書かないとLLMは逐次実行する。明示が必要。

**適用先**: タスクYAMLに`parallel_ok: [AC1, AC2]`で並列可能ACを明示。

### §2.10 Temporal Interrogation

実装時間軸でのpre-mortem:
```
HOUR 1 (foundations):     What does the implementer need to know?
HOUR 2-3 (core logic):   What ambiguities will they hit?
HOUR 4-5 (integration):  What will surprise them?
HOUR 6+ (polish/tests):  What will they wish they'd planned for?
```

**適用先**: 大型偵察cmdの報告テンプレートに「実装時の伏兵予測」セクション追加。

### §2.11 Dream State Mapping

```
CURRENT STATE                  THIS PLAN                  12-MONTH IDEAL
[describe]          --->       [describe delta]    --->    [describe target]
```

プランが12ヶ月後の理想に近づくか乖離するかを可視化。局所最適の防止。

### §2.12 Two-pass Review

| Pass 1 (CRITICAL, blocks /ship) | Pass 2 (INFORMATIONAL, in PR body) |
|-----|-----|
| SQL & Data Safety | Conditional Side Effects |
| Race Conditions & Concurrency | Magic Numbers & String Coupling |
| LLM Output Trust Boundary | Dead Code & Consistency |
| | Test Gaps, Crypto, Time Window, Type Coercion, View/Frontend |

判定基準: **データ破壊・セキュリティ侵害 = CRITICAL、コード品質・保守性 = INFORMATIONAL**

**適用先**: 家老の報告レビューをPass 1(AC達成=blocking) → Pass 2(品質・教訓=info)に分離。

## §3 /browse 技術分析

### アーキテクチャ

```
Claude Code (Bash tool)
  → browse CLI (Bunコンパイル済みバイナリ ~58MB)
    → HTTP POST localhost:9400 (Bearer token認証)
      → Bun.serve HTTP server
        → Playwright API
          → headless Chromium
```

- 初回: ~3秒（Chromium起動）
- 以降: ~100-200ms（HTTP POST）
- 30分アイドルで自動停止
- Chromiumクラッシュ → サーバー即死 → 次回CLI呼出で自動再起動
- MCP不使用。plain text stdout。トークンコスト0

### snapshot + ref方式（核心イノベーション）

1. `page.locator('body').ariaSnapshot()` → アクセシビリティツリーYAML取得
2. 2パス: 第1パスで`role:name`出現数カウント → 第2パスで`@e1`,`@e2`...のref割当
3. 同一role+name複数 → `nth()`で曖昧さ解消
4. **DOM非改変。スクリプト注入なし。CSP問題なし**
5. ページ遷移で自動refクリア（stale ref構造的防止）
6. `-i`フラグでインタラクティブ要素のみ（17 ARIAロール: button,link,textbox,checkbox,radio等）
7. トークン効率: ~200-400 tokens (snapshot) vs ~3000-5000 (full DOM)

### 我々のCDP方式との比較

| 観点 | gstack browse | 我々のCDP方式 |
|------|--------------|-------------|
| ブラウザ制御 | Playwright API (高レベル) | Chrome DevTools Protocol (低レベル) |
| ブラウザ | Playwright管理headless Chromium | 既存Chrome (port 9222) |
| 通信経路 | CLI → HTTP → Bun → Playwright | WSL2 bash → PowerShell → CDP WebSocket |
| 要素選択 | アクセシビリティツリー + @ref | CSS selector / XPath / DOM直接 |
| 起動速度 | 初回3秒、以降100-200ms | 毎回PowerShell起動+CDP接続 |
| 我々の優位 | — | **GUIブラウザ直接制御（ユーザーが見ているものを操作）** |
| gstackの優位 | **ref方式でLLMのセレクタ推測排除** | — |

### CDP改善案（gstack知見の転用）

1. **persistent daemon化**: CDPコマンドをWSL2側HTTPサーバーでラップ → PowerShell4重クォート問題の根本解決
2. **ref-based要素選択**: `Accessibility.getFullAXTree`で@ref体系構築
3. **chain（バッチ実行）**: 複数CDP操作を1回のHTTP POSTで実行

## §4 TODO.md — ロードマップ（未実装構想）

### Phase 2: Enhanced Browser（次マイルストーン）
- Annotated screenshots（要素に番号ラベル+ref対応）
- Snapshot diffing（before/afterアクセシビリティツリー比較）
- Dialog handling, File upload, Cursor-interactive elements, Element state checks

### Phase 3: QA Testing Agent（最大の構想）
browseの上に**自律QAエージェント**を構築:
- 6フェーズ: Initialize → Authenticate → Orient → Explore → Document → Wrap up
- 7カテゴリ問題分類: visual/functional/UX/content/performance/console/accessibility
- 動画記録(Playwright WebMキャプチャ) + アノテーション付きスクショ

### Phase 4: Skill + Browser Integration
- `/ship` + `/browse`: デプロイ後自動検証（staging閲覧→JSエラーチェック→snapshot diff→PRにスクショ）
- `/review` + `/browse`: ビジュアルdiffレビュー

### Phase 5: State & Sessions
- Auth vault（暗号化クレデンシャル、LLMにパスワード非表示）
- State persistence（cookie+localStorage JSON保存/復元）

### Phase 6: Advanced Browser
- **CDPモード**（既存Chrome/Electronアプリへの接続）← 我々と同じ着想が最終フェーズ
- iframe対応、ネットワークモック、ストリーミング

設計哲学: `"Browser is the nervous system — every skill should be able to see, interact with, and verify the web. Skills are the product; the browser enables them."`

## §5 我が軍との対比

| 観点 | gstack | 将軍システム |
|------|--------|------------|
| スケール | 1エージェント×6モード切替 | 10エージェント×役割固定+鎖の原理 |
| 並列処理 | 不可（1セッション） | **8忍者同時並列** |
| 状態管理 | なし（stateless） | **YAML+dashboard+陣形図で永続** |
| 品質管理 | スキルプロンプト強度依存 | **鎖+gate+レビューサイクル** |
| ブラウザ | Playwright+persistent daemon | CDP直接（GUI制御可） |
| 教訓蓄積 | retro JSON（個人メトリクス） | **lessons.yaml+MCP Memory（組織知識）** |
| プロンプト技術 | **洗練（Suppressions, 二分法, モードコミットメント）** | 基本的（禁則+AC定義中心） |

核心の差: gstack=**個人プロダクティビティ最適化**。将軍=**組織の知識蓄積と並列実行**。
設計思想は異なるが、プロンプトテクニック群は直接転用可能。

## §6 適用優先度表

### Tier 1: 即効（既存YAML/mdの修正のみ）

| # | テクニック | 適用先 | 変更内容 |
|---|-----------|-------|---------|
| 1 | Suppressions | 偵察テンプレート | 「報告不要な発見リスト」追加 |
| 2 | 停止条件の二分法 | タスクYAML | `stop_for`/`never_stop_for`フィールド |
| 3 | 推薦先行+WHY | 偵察テンプレート | `recommendation: (必須。推薦+WHY1文)` |
| 4 | Priority Hierarchy | タスクYAML AC | `priority: AC1 > AC2 > AC3` |
| 5 | Escape Hatch | ashigaru.md | 「自明な修正は実行→事後報告」ルール |
| 6 | 並列実行明示 | タスクYAML | `parallel_ok: [AC1, AC2]` |

### Tier 2: 中期（仕組みの追加）

| # | テクニック | 内容 |
|---|-----------|------|
| 7 | Two-pass Review | 家老レビューをCRITICAL/INFO 2パスに分離 |
| 8 | Gate分類 CRITICAL/INFO | gate系スクリプト出力のBLOCK/INFO二分化 |
| 9 | Engineering Preferences | `projects/{id}.yaml`にPJ固有判断基準 |
| 10 | retro定量分析 | chronicle.mdパース→メトリクスJSON→トレンド比較 |

### Tier 3: 長期

| # | テクニック | 内容 |
|---|-----------|------|
| 11 | CDP daemon化 | WSL2側HTTPサーバーでCDP操作ラップ |
| 12 | ref-based要素選択 | AXTree→@ref体系 |
| 13 | 自律QA（Phase 3相当） | 仙人構想への統合可能性 |

## §7 CLAUDE.md・setup分析

### CLAUDE.md（驚くほど薄い）

ビルドコマンド4行 + プロジェクト構造ツリーのみ。コーディング規約・テスト方針・コミット規約なし。
理由: gstack自体がツールコレクションでありアプリケーションコードではない。複雑なビジネスロジックなし。

我々のCLAUDE.mdとの対比: 我々は肥大化傾向。gstackの「スキルは自己完結」設計は参考になる。

### setupスクリプト

ビルド判定4条件(OR):
1. バイナリ不在
2. `browse/src/`に新しいファイルあり(`find -newer`)
3. `package.json`更新
4. `bun.lock`更新

シンボリックリンクで`~/.claude/skills/browse` → `gstack/browse`等を作成。Claude Codeのスキルディスカバリ機構に乗る設計。
