# cmd_324 偵察A: LLMプロンプトにおける否定指示 vs 肯定指示 — 網羅的調査

- **cmd**: cmd_324
- **subtask**: subtask_324_recon_a
- **調査者**: saizo
- **日付**: 2026-02-25
- **目的**: PD-038（ashigaru.md F001-F005の否定→肯定形書き換え）裁定の判断材料

---

## §1 Pink Elephant問題の学術的裏付け

### §1.1 原著論文（認知心理学）

| # | 著者 | 年 | タイトル | 掲載先 | URL |
|---|------|---|---------|--------|-----|
| 1 | Wegner, D.M., Schneider, D.J., Carter, S.R., White, T.L. | 1987 | Paradoxical Effects of Thought Suppression | Journal of Personality and Social Psychology, 53, 5-13 | [PubMed](https://pubmed.ncbi.nlm.nih.gov/3612492/) |
| 2 | Wegner, D.M. | 1994 | Ironic Processes of Mental Control | Psychological Review, 101(1), 34-52 | [PubMed](https://pubmed.ncbi.nlm.nih.gov/8121959/) |

**White Bear実験（1987）**: 「白い熊を考えるな」→抑圧指示群は抑圧後のリバウンド効果で言及回数が自由思考群を上回った。否定指示の逆効果の最初の実証。

**Ironic Process Theory（1994）**: 思考制御の2プロセスモデル。(1)操作プロセス=望ましい状態へ注意誘導、(2)監視プロセス=失敗シグナルを常時検索。認知負荷が高まると監視プロセスが優位になり、抑制対象の概念が逆に強化される。

### §1.2 LLMへの適用（Pink Elephant Problem）

| # | 著者 | 年 | タイトル | 掲載先 | URL |
|---|------|---|---------|--------|-----|
| 3 | Castricato, L. et al. | 2024 | Suppressing Pink Elephants with Direct Principle Feedback | arXiv:2402.07896 | [arXiv](https://arxiv.org/abs/2402.07896) |
| 4 | (複数著者) | 2024 | Do Not Think About Pink Elephant! | arXiv:2404.15154 / CVPR 2024 ReGenAI WS | [arXiv](https://arxiv.org/abs/2404.15154) |

**Castricato et al. (2024)** — LLMにおける「Pink Elephant Problem」の命名論文。「Xについて話すな、Yについて話せ」という否定的指示をLLMが正しく従えない問題を定式化。Direct Principle Feedback (DPF)でLlama-2-13BをファインチューニングしGPT-4同等の性能を達成。**推論時プロンプトだけでは限界があり、訓練時介入が有効**と結論。

**CVPR 2024 (画像生成)** — Stable Diffusion/DALL-E3で「Pink Elephantを描くな」→逆にPink Elephantを強調。Attention機構が否定対象トークンに重みを付与するメカニズム。認知療法由来のプロンプト戦略で攻撃成功率を最大48.22%軽減。

### §1.3 認知心理学 vs LLM — メカニズムの相違

| 観点 | 認知心理学（Wegner） | LLM |
|------|----------------------|-----|
| 原因機序 | 監視プロセスが概念を継続的に活性化 | Attention機構が否定対象トークンに高い重みを付与 |
| 認知負荷依存性 | 高負荷で顕著（二重課題実験） | 常時発生（負荷概念なし） |
| 対処法 | 注意そらし（代替概念への誘導） | 肯定的再表現（「Xを避けよ」→「Yについて話せ」）/ 訓練時介入(DPF/RLHF) |
| 再現性 | メタ分析で確立（Wang et al., 2020） | 現象的に酷似するがメカニズムは別物。因果同一性は未証明 |

**結論**: LLMの否定処理失敗はIronic Process Theoryと現象レベルで酷似するが、メカニズムは異なる。Ironic Process Theoryは説明の比喩として有用だが、LLMへの直接適用は機構的に正確ではない。

---

## §2 LLMプロンプトにおける否定 vs 肯定の実証研究

### §2.1 論文リスト

| # | 著者 | 年 | タイトル | 掲載先 | URL |
|---|------|---|---------|--------|-----|
| 5 | Jang, J., Ye, S., Seo, M. (KAIST) | 2022 | Can Large Language Models Truly Understand Prompts? A Case Study with Negated Prompts | PMLR Vol.203:52-62 | [arXiv](https://arxiv.org/abs/2209.12711) |
| 6 | Zhang, Y. et al. (Stanford) | 2023 | Beyond Positive Scaling: How Negation Impacts Scaling Trends of Language Models (NeQA) | Findings of ACL 2023 | [arXiv](https://arxiv.org/abs/2305.17311) |
| 7 | Truong, T.H. et al. | 2023 | Language Models Are Not Naysayers | *SEM 2023, 101-114 | [ACL Anthology](https://aclanthology.org/2023.starsem-1.10/) |
| 8 | Vrabcova, T. et al. | 2025 | Negation: A Pink Elephant in the Large Language Models' Room? | arXiv:2503.22395 | [arXiv](https://arxiv.org/abs/2503.22395) |
| 9 | Cemri, M. et al. (UC Berkeley/CMU) | 2025 | Why Do Multi-Agent LLM Systems Fail? (MAST) | arXiv:2503.13657 | [arXiv](https://arxiv.org/abs/2503.13657) |
| 10 | 清華大学 KEG | 2024-25 | AGENTIF: Benchmarking Instruction Following of LLMs in Agentic Scenarios | (PDF) | [清華大学](https://keg.cs.tsinghua.edu.cn/persons/xubin/papers/AgentIF.pdf) |

### §2.2 主要知見

**逆スケーリング問題（Jang et al., 2022）**
- OPT/GPT-3系列(125M-175B)で9種タスクを否定プロンプトで比較
- **モデルが大きいほど否定プロンプトで性能が悪化**（逆スケーリング則）
- InstructGPT等の指示追従特化モデルも例外なし
- 結論: LLMは「否定」を理解していない。サイズ拡大で解決不可

**NeQA（Zhang et al., 2023, Stanford）**
- 否定QAタスクを構築、逆スケーリング/U字型/正スケーリングの3パターンを確認
- 否定理解にはモデルサイズの「創発的転換点（emergent transition point）」が存在
- Chain-of-thought等の強力なプロンプト手法で一部モデルが正スケーリングに移行可能

**否定ベンチマーク（Truong et al., 2023）**
- LLMの3つの系統的弱点: (1)否定の存在への無感覚、(2)否定の語彙意味論の把握失敗、(3)否定推論の頑健性欠如
- モデルサイズ増加だけでは否定理解は改善されない

**多言語ベンチマーク（Vrabcova et al., 2025）**
- 4言語(英/チェコ/独/ウクライナ)で新規データセット構築
- モデル規模拡大が否定処理を改善する場合もある（Jang 2022と異なる条件下）
- 否定の頑健性は言語依存（英語>独語>チェコ語）

**マルチエージェント失敗分析（MAST, 2025）**
- 7種フレームワーク/1600+トレースで分析
- **マルチエージェントシステムの失敗率: 41%-86.7%**
- 禁止事項系指示がエージェント間伝搬で薄まる
- プロンプト改善+トポロジー改善で最大+14%改善だが実運用水準には不足

**エージェント環境での指示遵守（AGENTIF）**
- 707件の手動アノテーション指示（1指示あたり平均11.9制約）
- **最高性能モデルでも完全遵守率30%未満**
- 否定的・排除的制約はLLMが特に苦手とする制約タイプ
- 制約数増加で遵守率が単調減少、否定形で顕著

### §2.3 否定形が失敗するメカニズム（研究横断的合意）

1. **Attention機構の限界**: Transformer系の表現空間では「概念の不在」の表現が構造上困難。否定語処理後も概念への注意は低下しない
2. **逆スケーリング**: 大モデルほど否定プロンプトで悪化（ただし創発的転換点の存在も示唆）
3. **マルチ制約累積崩壊**: 制約数増加→各制約の遵守率が単調低下。10制約でGPT-4oが15%
4. **マルチエージェント環境での増幅**: 禁止指示がエージェント間伝達で希薄化

### §2.4 肯定形が効果的な理由

- 「〜しろ」は出力空間を直接狭める（positive constraint）
- 「〜するな」は否定対象概念を活性化した上で回避を求める（処理コスト+エラーリスク増大）
- ATLAS論文(arXiv:2312.16171): 26原則中「肯定形指示」原則で平均10-57%の性能向上

### §2.5 否定形が有効な条件（例外）

- **安全拒否領域**: 「有害なことをするな」系はRLHF/CAIで強力に焼き込み済み→高い遵守率
- **理由付き否定**: 「なぜ禁止か」を添付で遵守率改善（Anthropic推奨パターン）
- **DPFファインチューン後**: 否定型指示遵守の専用訓練でGPT-4同等に到達可能

---

## §3 公式ドキュメントの推奨

### §3.1 Anthropic（Claude）

**URL**: [Claude 4 Best Practices](https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices)

公式引用:
> "Tell Claude what to do instead of what not to do"
> - Instead of: "Do not use markdown in your response"
> - Try: "Your response should be composed of smoothly flowing prose paragraphs."

理由付き否定の許容例:
> - Less effective: `NEVER use ellipses`
> - More effective: `Your response will be read aloud by a text-to-speech engine, so never use ellipses since the text-to-speech engine will not know how to pronounce them.`

**推奨強度**: Should — "golden rule"セクション直下のナンバー1推奨。完全否定禁止ではなく「コンテキスト付きなら否定語も許容」。

追加警告: Claude Opus 4.5/4.6では `CRITICAL: You MUST...` 等の強調語句がovertriggerを引き起こすと警告。

### §3.2 OpenAI

**URL**: [OpenAI Prompt Engineering Guide](https://platform.openai.com/docs/guides/prompt-engineering) / [旧Help Center](https://help.openai.com/en/articles/6654000-best-practices-for-prompt-engineering-with-the-openai-api)

旧ドキュメント（最も明示的）:
> "Rather than just saying what not to do, say what to do instead."
> - 悪い例: `DO NOT ASK USERNAME OR PASSWORD`
> - 良い例: `The agent will attempt to diagnose the problem and suggest a solution, whilst refraining from asking any questions related to PII.`

GPT-4.1 Prompting Guide（最新Cookbook）:
- 通常の誘導は肯定形主体
- 高stakesでは `DO NOT` を選択的に使用するハイブリッド方針

**推奨強度**: 旧=Should。現=明示的「avoid negation」節が削除、暗黙化。

### §3.3 Google / DeepMind

**URL**: [Gemini Prompting Strategies](https://ai.google.dev/gemini-api/docs/prompting-strategies) / [Vertex AI](https://docs.cloud.google.com/vertex-ai/generative-ai/docs/learn/prompts/prompt-design-strategies)

Gemini API:
> "Using examples to show the model a pattern to follow is more effective than using examples to show the model an anti pattern to avoid."
> - 悪い例: `"Don't end haikus with a question"`
> - 良い例: `"Always end haikus with an assertion"`

画像生成 (Vertex AI) — 最も強い禁止:
> Not recommended: Avoid instructive language or words like "no" or "don't".

**推奨強度**: テキスト=Should。画像生成=Must。

### §3.4 Microsoft Copilot

> "Focus on what Copilot should do, not what to avoid."

**推奨強度**: Should（Best practices筆頭項目）。

### §3.5 各社比較まとめ

| 発行元 | 方針 | 推奨強度 | 否定語の例外 |
|--------|------|----------|-------------|
| Anthropic | 肯定形推奨 + 理由付き否定は許容 | Should | コンテキスト付き "never" は許容 |
| OpenAI (旧) | 肯定形推奨を明示 | Should | 高stakes文脈では DO NOT |
| OpenAI (現) | 暗黙的に肯定形推奨 | May | ハイブリッド方針 |
| Google (テキスト) | 例示ベースで肯定形推奨 | Should | - |
| Google (画像生成) | 否定語禁止 | Must | - |
| Microsoft | 肯定形を筆頭に記載 | Should | - |

---

## §4 ashigaru.md F001-F005 書き換え提案

### §4.1 現状分析

F001-F005は `forbidden_actions` フィールド内に配置されており、構造的に全件が否定形（禁止行為の列挙）。

### §4.2 Before/After対照表

| ID | action | Before（現在: 否定形） | After（提案: 肯定形） |
|----|--------|------------------------|----------------------|
| F001 | direct_shogun_report | "Report directly to Shogun (bypass Karo)" | "Route all reports through Karo. Karo is the sole reporting channel." |
| F002 | direct_user_contact | "Contact human directly" | "Route all human-bound communication through Karo. Karo is the sole interface to the human." |
| F003 | unauthorized_work | "Perform work not assigned" | "Execute only tasks explicitly assigned by Karo via task YAML. Wait idle for the next assignment." |
| F004 | polling | "Polling loops" (reason: Wastes API credits) | "Wait for inbox nudge (inboxN) from inbox_watcher. Act only on event-driven signals." |
| F005 | skip_context_reading | "Start work without reading context" | "Before starting any task: read projects/{project}.yaml, projects/{project}/lessons.yaml, and context/{project}.md." |

### §4.3 構造的考慮

現在のYAML構造が `forbidden_actions:` というキー名であるため、肯定形descriptionと構造名が矛盾する。書き換え案:

**案A（description書き換えのみ）**: `forbidden_actions:` キーは維持し、descriptionを肯定形に変更。構造的矛盾は残るが変更コスト最小。

**案B（構造ごと変更）**: `forbidden_actions:` → `behavioral_rules:` に変更し、各エントリを肯定形ルールに変換。整合性は高いが変更範囲大（スクリプト・テスト影響要確認）。

**案C（ハイブリッド）**: `forbidden_actions:` キーは維持。descriptionに肯定形+理由を追加。Anthropic推奨の「理由付き否定」パターン。

```yaml
# 案Cの例
forbidden_actions:
  - id: F001
    action: direct_shogun_report
    description: "Report directly to Shogun (bypass Karo)"
    positive_rule: "Route all reports through Karo"
    reason: "Karo aggregates context and prevents Shogun interruption"
```

**推奨**: 案C（ハイブリッド）。否定形の明快さ（何が禁止か即座に分かる）を維持しつつ、肯定形ルール+理由を追加。Anthropicの「理由付き否定は許容」に合致。

### §4.4 Opus vs Sonnet の差異に関する考慮

| 観点 | Opus 4.6 | Sonnet 4.6 |
|------|----------|------------|
| 否定指示の遵守 | 高い（MUST/NEVER をリテラルに従う傾向） | 低い（文脈判断でオーバーライド, L051） |
| 肯定形の効果 | 元々高い遵守率のため差は小さい | 遵守率向上が期待される |
| overtrigger | 低い | MUST/NEVER/ALWAYS で発生しやすい |
| 推奨 | 現状維持でも可だが統一のため変更可 | 肯定形+理由付きが有効 |

### §4.5 モデル非依存の原則との整合性

肯定形書き換えはモデル非依存の原則と**整合する**:
- Anthropic/OpenAI/Google全社が肯定形を推奨（§3で実証）
- Sonnet系での効果が大きく、Opus系で副作用が少ない
- Codex（下忍用CLI）でも肯定形は有効（OpenAI推奨に合致）
- 「理由付き否定」パターンは全モデルで安全

---

## §5 OSSプロジェクト・プロダクション事例

### §5.1 肯定形を採用しているプロジェクト

| プロジェクト | 肯定形パターン | URL |
|-------------|---------------|-----|
| GitHub awesome-copilot | "Use [technology]", "Prefer [pattern]" の肯定形主体 | github.com/github/awesome-copilot |
| Microsoft Declarative Agent | "Ask one clarifying question at a time" 等の行動指示形 | learn.microsoft.com |

### §5.2 否定形→肯定形の変換効果事例

16x.engineer ブログ（"The Pink Elephant Problem"）より:

| 否定形 (非推奨) | 肯定形 (推奨) |
|----------------|--------------|
| `Don't use mock data` | `Only use real-world data` |
| `Avoid creating new files for fixes` | `Apply all fixes to existing files` |
| `Never output verbose comments` | `Write professional, concise code comments` |

---

## §6 総合評価と推奨

### §6.1 エビデンスの強さ

| 主張 | エビデンス強度 | 根拠 |
|------|---------------|------|
| LLMは否定指示の処理が構造的に苦手 | **強** | 6本以上の査読付き論文、逆スケーリング則の実証 |
| 肯定形指示は否定形より効果的 | **強** | 3社公式ドキュメント推奨 + 複数実証研究 |
| 理由付き否定は単純否定より有効 | **中** | Anthropic公式推奨 + 限定的実証 |
| マルチエージェント環境で否定指示の問題が増幅 | **中** | MAST論文(2025) + AGENTIF |
| Sonnet系でOpus系より否定指示の問題が顕著 | **中** | L051(内部観測) + Anthropic overtrigger警告 |

### §6.2 PD-038への推奨

**推奨: 案C（ハイブリッド）を段階的に導入**

1. **Phase 1**: F001-F005のdescriptionに `positive_rule` + `reason` フィールドを追加（既存の否定形は削除しない）
2. **Phase 2**: 忍者側の指示書(roles/ashigaru_role.md)で、forbidden_actionsセクションの表示形式を「肯定形ルール（理由付き）」に変更
3. **Phase 3**: 効果測定（禁則違反の発生頻度をcmd単位で計測）後、効果があればforbidden_actions自体の構造変更を検討

**理由**:
- 全面書き換えはOpusでの既存の高い遵守率を損なうリスク
- 段階導入でSonnetへの効果を計測可能
- Anthropicの「理由付き否定は許容」パターンに最も合致
- モデル非依存の原則を満たす

### §6.3 リスク

- **低リスク**: Opusで肯定形追加による副作用は学術的に考えにくい
- **中リスク**: `forbidden_actions` 構造名と肯定形descriptionの意味的矛盾（案Cで緩和）
- **注意**: roles/ashigaru_role.md と ashigaru.md の二重更新が必要（L005, L013）

---

## 参考文献（全リスト）

| # | 著者 | 年 | タイトル | URL |
|---|------|---|---------|-----|
| 1 | Wegner et al. | 1987 | Paradoxical Effects of Thought Suppression | [PubMed](https://pubmed.ncbi.nlm.nih.gov/3612492/) |
| 2 | Wegner | 1994 | Ironic Processes of Mental Control | [PubMed](https://pubmed.ncbi.nlm.nih.gov/8121959/) |
| 3 | Castricato et al. | 2024 | Suppressing Pink Elephants with Direct Principle Feedback | [arXiv](https://arxiv.org/abs/2402.07896) |
| 4 | (複数) | 2024 | Do Not Think About Pink Elephant! | [arXiv](https://arxiv.org/abs/2404.15154) |
| 5 | Jang, Ye, Seo | 2022 | Can LLMs Truly Understand Prompts? Negated Prompts | [arXiv](https://arxiv.org/abs/2209.12711) |
| 6 | Zhang et al. | 2023 | Beyond Positive Scaling (NeQA) | [arXiv](https://arxiv.org/abs/2305.17311) |
| 7 | Truong et al. | 2023 | Language Models Are Not Naysayers | [ACL](https://aclanthology.org/2023.starsem-1.10/) |
| 8 | Vrabcova et al. | 2025 | Negation: A Pink Elephant in the LLMs' Room? | [arXiv](https://arxiv.org/abs/2503.22395) |
| 9 | Cemri et al. | 2025 | Why Do Multi-Agent LLM Systems Fail? (MAST) | [arXiv](https://arxiv.org/abs/2503.13657) |
| 10 | 清華大学 KEG | 2024-25 | AGENTIF: Benchmarking Instruction Following | [PDF](https://keg.cs.tsinghua.edu.cn/persons/xubin/papers/AgentIF.pdf) |
| 11 | (ATLAS) | 2023 | Principled Instructions Are All You Need | [arXiv](https://arxiv.org/abs/2312.16171) |
| 12 | Anthropic | 2025 | Claude 4 Best Practices | [docs.anthropic.com](https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices) |
| 13 | OpenAI | 2024 | GPT-4.1 Prompting Guide | [cookbook.openai.com](https://cookbook.openai.com/examples/gpt4-1_prompting_guide) |
| 14 | Google | 2025 | Gemini Prompting Strategies | [ai.google.dev](https://ai.google.dev/gemini-api/docs/prompting-strategies) |
| 15 | 16x.engineer | 2024 | The Pink Elephant Problem | [eval.16x.engineer](https://eval.16x.engineer/blog/the-pink-elephant-negative-instructions-llms-effectiveness-analysis) |
