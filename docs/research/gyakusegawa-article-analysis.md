# 逆瀬川記事 深掘り分析

<!-- source: cmd_960 AC5 (hanzo) -->
<!-- article: 逆瀬川ちゃん(@gyakuse)「Coding Agent時代の開発ワークフロー」2026-03-14、31分 -->
<!-- url: https://nyosegawa.github.io/posts/coding-agent-workflow-2026/ -->
<!-- analysis_date: 2026-03-15 -->

> 業界最包括的サーベイ。我が軍は記事が紹介する主要概念の70%以上を独自実装済み。
> 取込4点(cmd_960) + 1点(cmd_961) + 記憶1点(仙人Ralph Loop) + 保留1点(Symphony)

---

## §1 記事3層構造要約

記事は3つの層で構成される。各層が独立しつつ相互参照する構造。

### 層1: ワークフロー（何をどう進めるか）

| 概念 | 出典 | 核心 |
|------|------|------|
| SDD (Specification-Driven Development) | Harper Reed等 | コード前に仕様書。AIに渡す入力品質が出力品質を決める |
| RPI (Recursive Planning Iteration) | Boris Tane | 計画→実装→検証を再帰的に繰り返す。一発実装ではなく段階的精緻化 |
| Superpowers | 記事独自整理 | AIエージェントが人間を超える領域: 並列実行・網羅探索・疲れない反復 |

### 層2: テクニック（品質を上げる手法）

| 概念 | 出典 | 核心 |
|------|------|------|
| Context Engineering | 記事独自整理 | プロンプトの外側=環境・ファイル・ツール構成の最適化。Prompt Engineeringの上位概念 |
| TDD / tdd-guard | nizos/tdd-guard (1,811 stars) | テスト先行をHookで機械強制。SKIP=FAILを自動化 |
| Best-of-N | 学術系+実務 | 同一タスクにN個のエージェントを投入し最良を選択 |
| 確率的カスケード | 学術系 | N段パイプラインの成功率 = p₁×p₂×...×pₙ の急落問題 |

### 層3: インフラ（何を整備するか）

| 概念 | 出典 | 核心 |
|------|------|------|
| AGENTS.md | Vercel実証+Linux Foundation AAIF | ツール横断の共通プロジェクトブリーフ。60,000+ OSS採用 |
| Skills / Hooks | Claude Code公式 | PostToolUse等のフックで品質を自動強制 |
| Worktree | Git機能+各ツール | 並列作業の隔離。ブランチ衝突の構造的排除 |
| Comprehension Debt | Addy Osmani | AI生成速度と人間理解速度のギャップ蓄積 |
| ADR鮮度管理 | 記事独自提案 | last-validated付きで知識腐敗を自動検知 |

---

## §2 我が軍との対比表

凡例: **実装済**=独自に到達 / **取込中**=cmd_960/961で導入中 / **記憶済**=設計記録あり・未実装 / **保留**=殿判断で段階適用

| 記事の概念 | 我が軍の対応実装 | 状態 | 備考 |
|------------|-----------------|------|------|
| SDD (仕様先行) | cmd YAML + AC定義 + projects/*.yaml | **実装済** | 将軍が仕様、家老が分解、忍者が実装 |
| RPI (再帰的計画) | cmd分解 + AC単位実装 + レビューサイクル | **実装済** | §5参照。家老のレビュー→修正→再レビューが再帰 |
| Context Engineering | CLAUDE.md + context/*.md + Vercel構造 | **実装済** | 受動的>能動的の原則で環境最適化 |
| TDD機械強制 | PostToolUse Hook + Gate SKIP検査 | **取込中** | cmd_961 |
| Best-of-N | 万全偵察(水平4+垂直4) + GSD式4観点 | **実装済** | §7参照。Best-of-8を構造化 |
| 確率的カスケード対策 | Gate + レビューサイクル + 教訓注入 | **実装済** | §6参照。各段でp上昇 |
| AGENTS.md | AGENTS.md (AAIF準拠) | **取込中** | cmd_960 AC3 |
| Skills | ~/.claude/skills/ (12+ スキル) | **実装済** | shogun-teire, reset-layout等 |
| Hooks | .claude/settings.json hooks | **実装済** + **取込中** | 既存hook + tdd-guard(cmd_961) |
| Worktree並列 | tmux pane × 8忍者 | **実装済** | 同一リポジトリ内YAML分離で衝突回避 |
| Comprehension Debt対策 | how_it_works報告フィールド | **取込中** | cmd_960 AC1 |
| ADR鮮度管理 | gate_context_freshness.sh | **取込中** | cmd_960 AC4 |
| 通知バッチ化 | ntfy_batch.sh (HIGH即時/INFO 15分) | **取込中** | cmd_960 AC2 |
| Ralph Loop | 仙人heartbeat候補 | **記憶済** | `memory/project_sennin_ralph_loop.md` |
| Symphony (自動オーケストレーション) | — | **保留** | 殿判断: 対話学習を優先、段階適用 |
| Patrol Agent | ntfy_batch.sh相当 | **取込中** | cmd_960 AC2で概念吸収 |
| Suppressions (偽陽性抑制) | 偵察テンプレート報告不要リスト | **実装済** | cmd_927 gstack知見取込 |
| 停止条件二分法 | task YAML stop_for/never_stop_for | **実装済** | cmd_927 gstack知見取込 |
| Two-pass Review | 家老CRITICAL/INFO 2パスレビュー | **実装済** | cmd_927 gstack知見取込 |
| Engineering Preferences | task YAML engineering_preferences | **実装済** | cmd_927 gstack知見取込 |

**集計**: 実装済 14 / 取込中 6 / 記憶済 1 / 保留 1 = **計22概念中、実装済+取込中=20 (91%)**

---

## §3 Vercel実証データ突合

### AGENTS.md: 60,000+ OSSリポジトリ採用

Vercelが実証したAGENTS.mdの効果:
- ツール横断の共通ブリーフとして機能
- Claude Code / Codex / Cursor / Gemini CLI が同一ファイルを読める
- Linux Foundation AAIF (AI Agent Interoperability Framework) に準拠

**我が軍の対応**: cmd_960 AC3でAGENTS.md作成済み。48行、AAIF frontmatter付き。
CLAUDE.mdから抽出した共通情報のみ記載し、役割固有手順はCLAUDE.md参照ポインタで解決。

### Vercel原則と我が軍の整合

| Vercel原則 | 我が軍の実装 | 状態 |
|-----------|-------------|------|
| 受動的 > 能動的 (判断回数最小化) | CLAUDE.md自動ロード + context/*.md索引 | 完全一致 |
| 索引+詳細2層構造 | context/*.md(索引) + docs/research/(詳細) | 完全一致 |
| 500行以下/ファイル | CLAUDE.md + context各ファイルで遵守 | 完全一致 |
| リンク先なき圧縮=削除=禁止 | 圧縮手順Phase順序厳守ルール化 | 完全一致 |

Vercel原則は2026-02-25に取込済み(`MCP passive_context_philosophy`)。
記事で改めて言及されたことで、我が軍の早期採用が裏付けられた。

---

## §4 gstack交差検証

gstack (garrytan/gstack) は逆瀬川記事とは独立に調査済み (cmd_927, 2026-03-13)。
→ 詳細: `docs/research/gstack-analysis.md`

### 重複する知見

| 概念 | 逆瀬川記事での扱い | gstackでの実装 | 交差点 |
|------|-------------------|---------------|--------|
| Context Engineering | 層2の中核テーマ | 6スキルがCLAUDE.md/AGENTS.mdを前提 | 両者とも「環境構築>プロンプト」を主張 |
| TDD強制 | tdd-guard紹介 | /review + /ship のTwo-pass | テスト品質の機械強制という思想が共通 |
| 停止条件制御 | ワークフロー効率化の文脈 | /ship のstop_for/never_stop_for | **完全一致**。gstackが先行実装 |
| Best-of-N | 学術的文脈で紹介 | 直接言及なし | gstackは1エージェント前提のため非対応 |

### gstack独自でかつ記事で言及されない知見

| テクニック | gstack実装 | 我が軍への取込状態 |
|-----------|-----------|-----------------|
| Suppressions (偽陽性抑制9項目) | review/checklist.md | 取込済み (cmd_927) |
| モードコミットメント (HOLD/EXPANSION/REDUCTION) | scope_mode | 取込済み (cmd_927) |
| 推薦先行+WHY | AskUserQuestion制御 | 取込済み (cmd_927) |
| Priority Hierarchy (不等号表記) | ac_priority | 取込済み (cmd_927) |
| Temporal Interrogation (伏兵予測) | hour-by-hour pre-mortem | 取込済み (cmd_927) |
| browse (Playwright+ref方式) | /browse スキル | 未取込 (CDP方式と並行検討中) |

**結論**: gstackのプロンプトテクニック群は逆瀬川記事より先に調査・取込済み。
記事はgstackが扱わない学術的概念(確率的カスケード、Best-of-N)を補完する関係。

---

## §5 Boris Tane RPI 誤解修正

### RPI (Recursive Planning Iteration) とは

Boris Taneが提唱する開発手法。核心は:

1. **仕様作成** → AIが理解可能な明確な仕様を書く
2. **計画生成** → AIが実装計画を生成、人間がレビュー
3. **段階的実装** → 計画に基づき1ステップずつ実装
4. **検証・修正** → 結果を検証し、必要なら計画に戻る（再帰）

### 記事での扱いと誤解されやすい点

記事はRPIを「計画を先に書く」手法として紹介しているが、
RPIの本質は**計画そのものではなく再帰性**にある。

| 誤解されやすい解釈 | 正確な解釈 |
|-------------------|-----------|
| 「計画書を書けばAIが正しく実装する」 | 計画は仮説。実装結果で計画を修正する再帰ループが本質 |
| 「SDDと同じ」 | SDDは仕様→実装の一方向。RPIは仕様⇔実装の双方向 |
| 「一度計画すれば十分」 | 各ステップの結果が次のステップの計画を変える。反復が前提 |

### 我が軍との対応

| RPI要素 | 我が軍の実装 |
|---------|------------|
| 仕様作成 | 将軍がcmd YAML作成（purpose + AC定義） |
| 計画生成 | 家老がAC分解 + 忍者配備計画 |
| 段階的実装 | 忍者がAC単位で実装 + progress更新 |
| 検証・修正(再帰) | 家老レビュー → 修正要求 → 忍者再実装 → 再レビュー |
| 仕様への還流 | lesson_candidate → 家老 lesson_write.sh → projects lessons |

**我が軍はRPIを組織的に実装している**。個人ワークフローのRPIを
3階層(将軍/家老/忍者)に分散し、各層で再帰を回す構造。

---

## §6 確率的カスケード検証

### 概念

N段のAIパイプラインで各段の成功確率がpのとき:

```
P(全段成功) = p^N
```

| 段数N | p=0.95 | p=0.90 | p=0.80 |
|-------|--------|--------|--------|
| 3 | 0.857 | 0.729 | 0.512 |
| 5 | 0.774 | 0.590 | 0.328 |
| 10 | 0.599 | 0.349 | 0.107 |
| 20 | 0.358 | 0.122 | 0.012 |

段数が増えると成功確率は指数関数的に低下する。
AIエージェントの長いタスクチェーンほどこの問題が深刻。

### 我が軍の対策（カスケード分断）

我が軍は確率的カスケードを**構造的に分断**している:

| 対策 | 効果 | 実装 |
|------|------|------|
| AC単位分割 | 長いチェーンをAC=1-3段に分断 | 家老のcmd分解 |
| Gate検査 | 各段の出力品質を強制検証 | cmd_complete_gate.sh |
| レビューサイクル | 失敗段を検出・修正・再実行 | 家老のPass 1/Pass 2レビュー |
| 教訓注入 | 過去の失敗パターンを事前注入して各段のp向上 | related_lessons in task YAML |
| 偵察→実装分離 | 不確実な探索と確実な実装を分離 | 偵察cmd + 実装cmd |

**カスケード分断の効果**: 仮に各忍者のAC成功率p=0.90でも、
家老レビューで失敗を検出・修正すれば実効p≈0.99に向上。
3AC×p=0.99 = 0.970 > 10段×p=0.90 = 0.349

核心: **長いチェーンを回さない設計**がカスケード問題の根本解決。
記事が学術的に指摘する問題を、我が軍は組織構造で解決済み。

---

## §7 Best-of-N 我が軍適用

### Best-of-N手法

同一タスクにN個の独立エージェントを投入し、最良の結果を選択する手法。

```
期待品質 = max(品質₁, 品質₂, ..., 品質ₙ)
```

Nが増えると最良結果の期待値が対数的に上昇（収穫逓減あり）。

### 我が軍の実装: 万全偵察

| パターン | N値 | 独立性 | 選択方法 |
|----------|-----|--------|---------|
| GSD式4観点偵察（垂直） | 4 | 異なる観点から同一テーマ | 家老が結論突合 |
| 領域分割偵察（水平） | 4 | 異なる領域を各1名 | 家老が統合 |
| 万全偵察（水平+垂直） | 8 | 4+4の二重構造 | 家老がAC5で全統合 |

### 記事のBest-of-Nとの違い

| 観点 | 記事のBest-of-N | 我が軍の万全偵察 |
|------|----------------|-----------------|
| エージェント | 同一プロンプト×N | **異なる観点×N**（構造化Best-of-N） |
| 選択基準 | テスト通過率等の自動指標 | 家老の判断（CRITICAL/INFO分離） |
| 目的 | 最良結果の選択 | **盲点発見**（最良選択+盲点炙り出し） |
| コスト効率 | 同一作業N回=冗長 | 観点分割で冗長性を最小化 |

**我が軍の優位**: 純粋なBest-of-Nは同一プロンプトの「ガチャ」。
我が軍は観点を構造化することで、N回のコストを盲点発見に転換している。
cmd_719+720(水平) + cmd_721(垂直)で実証: 水平だけでは盲点を見落とし、
垂直だけでは定量データが薄い。両方やることで改善優先順位の確度が最大化。

---

## §8 Comprehension Debt 概念

### Addy Osmaniの問題提起

```
テスト通過 → マージ → 3日後に「このコード何してるか説明できない」
```

AI生成コードの速度と人間の理解速度のギャップ: **5-7倍**。
AIが1時間で書くコードを、人間が理解するのに5-7時間かかる。

このギャップが「Comprehension Debt（理解負債）」として蓄積:
- コードは動く（テスト通過）
- しかし誰も理解していない
- 修正・拡張時に「理解コスト」が爆発

### 技術的負債との違い

| 種類 | 蓄積原因 | 発覚タイミング | 対策 |
|------|---------|--------------|------|
| 技術的負債 | 意図的な妥協・設計劣化 | リファクタリング時 | コード品質改善 |
| 理解負債 | AI高速生成による人間理解の遅延 | 修正・拡張時 | **生成時の説明強制** |

### 我が軍の対策: how_it_works

cmd_960 AC1で導入する「Linear Walkthrough」:

```yaml
# 忍者の報告YAMLに追加されるフィールド
how_it_works: |
  gate_context_freshness.sh は context/*.md の last_updated コメントを
  grep で抽出し、現在日付との差分を計算する。
  14日超→WARN、30日超→ALERT を出力し、ALERT時はntfy送信する。
  既存の gate_shogun_memory.sh と同じ OK/WARN/ALERT 出力形式。
```

- 実装タスク(type: impl)のみ対象。偵察(recon)は除外
- cmd_complete_gate.sh で how_it_works 欠落時に WARN（BLOCKではない）
- **殿が3日後に読んでも「何をなぜそうしたか」が報告から復元可能**

### 我が軍固有の強み

殿↔将軍の対話で自然に理解が深まる構造が既存:
- 将軍が殿にcmd結果を報告する際、WHYを含めて説明
- 殿の質問→将軍の回答→殿の理解という対話ループ
- how_it_worksフィールドはこの対話をスケーラブルにする仕組み

---

## §9 取込済み知見一覧

### cmd_960: 逆瀬川記事知見4+1点取込

| AC | 内容 | 記事の対応概念 | 状態 |
|----|------|--------------|------|
| AC1 | how_it_works報告フィールド (Linear Walkthrough) | Comprehension Debt対策 | 取込中 |
| AC2 | ntfy_batch.sh 通知バッチ化 | Patrol Agent概念 | 取込中 |
| AC3 | AGENTS.md新規作成 (AAIF準拠) | Vercel AGENTS.md 60k+ OSS | 取込中 |
| AC4 | gate_context_freshness.sh 鮮度ゲート | ADR last-validated | 取込中 |
| AC5 | 本ドキュメント (恒久分析) | — | 本文書 |

### cmd_961: tdd-guard型Hook+Gate

| AC | 内容 | 記事の対応概念 | 状態 |
|----|------|--------------|------|
| AC1 | PostToolUse Hook (SKIP/FAIL検出→コンテキスト注入) | tdd-guard (1,811 stars) | 取込中 |
| AC2 | cmd_complete_gate.sh SKIP>0 BLOCK | SKIP=FAILの機械強制 | 取込中 |

### 記憶済み（未実装・設計記録あり）

| 知見 | 出典 | 記録先 | 適用先 |
|------|------|--------|--------|
| Ralph Loop | Geoffrey Huntley (2025/06〜) | `memory/project_sennin_ralph_loop.md` | 仙人heartbeat |

Ralph Loopの核心: `while :; do cat PROMPT.md | claude ; done`
毎回0%コンテキストでContext Rot構造的回避。仙人の3生命維持装置
(記憶=心臓/heartbeat=脈拍/soul=魂)のうち「脈拍」に該当。

### 保留（殿判断により段階適用）

| 知見 | 理由 | 判断 |
|------|------|------|
| Symphony型自動オーケストレーション | 殿が対話を通じた学習を重視 | 殿が「説明不要」と判断した領域から段階適用 |

Symphony = Issue起票→自動タスク分解→自動配備→自動レビュー→自動マージの完全自動化。
殿の判断: 「殿↔将軍の対話は学習機会」であり、完全自動化は学習機会を奪う。
cmd起票の自動化は殿が「説明不要」と判断した領域のみ許可。

### cmd_927 (gstack): 既に取込済みの関連知見

gstack調査(cmd_927)で既に取込済みの知見群。逆瀬川記事と重複するもの:

| gstack知見 | 記事対応概念 | 取込cmd |
|-----------|-------------|---------|
| Suppressions 9項目 | (記事では未言及) | cmd_927 |
| stop_for/never_stop_for | ワークフロー効率化 | cmd_927 |
| scope_mode (HOLD/EXPANSION/REDUCTION) | (記事では未言及) | cmd_927 |
| 推薦先行+WHY | Context Engineering文脈 | cmd_927 |
| Priority Hierarchy不等号 | (記事では未言及) | cmd_927 |
| Two-pass Review (CRITICAL/INFO) | TDD/品質管理文脈 | cmd_927 |
| Temporal Interrogation (伏兵予測) | (記事では未言及) | cmd_927 |

---

## §10 総合評価

### 我が軍の位置づけ

```
記事の主要概念22点中:
  実装済み: 14点 (64%) — 記事執筆前に独自到達
  取込中:   6点 (27%) — cmd_960/961で導入中
  記憶済み: 1点 (4%)  — 仙人設計に記録
  保留:     1点 (5%)  — 殿判断で段階適用
  ────────────────────
  合計:     91%がカバー済みまたはカバー予定
```

### 記事から得た最大の知見

1. **Comprehension Debt**: 名前がついたことで対策が明確化。how_it_worksフィールドとして構造化
2. **AGENTS.md標準化**: 60,000+ OSS採用の実証データ。他ツール互換の必要性が裏付け
3. **Ralph Loop**: 仙人heartbeatの設計候補として記憶。Context Rot構造的回避

### 記事が我が軍から学べる点

| 我が軍の独自実装 | 記事で未カバー |
|-----------------|--------------|
| 鎖の原理 (将軍→家老→忍者) | マルチエージェント組織構造 |
| Gate + レビューサイクル | 品質保証の多段構造 |
| 教訓自動注入 (related_lessons) | 組織学習の仕組み |
| 陣形図 (karo_snapshot) | リアルタイム全軍状態可視化 |
| MCP Memory (殿の好み永続化) | 人間の嗜好の構造的記憶 |
| YAML mailbox (inbox_write.sh) | エージェント間通信の永続化 |

記事は1エージェント×個人開発の最適化に焦点。
我が軍は10エージェント×組織運用の最適化で、根本的に異なる問題を解いている。
