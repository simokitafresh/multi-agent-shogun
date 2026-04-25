# Autoresearch Ecosystem Analysis — 将軍システム対比

Created: 2026-04-25
Source: https://github.com/alvinreal/awesome-autoresearch
Purpose: Karpathy autoresearch派生エコシステム全体を将軍システムの視点で分析し、取り込むべき知見を特定

## §1 エコシステム概観

Karpathyのautoresearch（フィードバックループ駆動の自動改善）から派生した70+プロジェクトのキュレーション。
2024-2025年に爆発的に拡散し、6カテゴリに分化。

| カテゴリ | 件数 | 成熟度 | 概要 |
|---------|------|--------|------|
| 汎用後継 | 20+ | 高 | keep-or-revert評価ループの様々な実装 |
| 研究エージェント | 15+ | 高 | 文献→実験→論文の完全自動化パイプライン |
| プラットフォーム移植 | 8+ | 中 | macOS/Windows/WebGPU/Jetson対応 |
| ドメイン特化 | 6+ | 中 | 系図/音声AI/取引/カーネル最適化 |
| 評価ベンチマーク | 5 | 高 | MLAgentBench/mle-bench/AgentBench |
| 実践事例 | 5+ | — | Shopify Liquid/野球バイオメカニクス等 |

## §2 共通アーキテクチャパターン

### 2.1 Keep-or-Revert評価（全プロジェクト共通の不変パターン）
- 変更→計測→改善ならkeep/悪化ならrevert
- 将軍システム対応: **gate BLOCK/PASS + binary_checks + cmd_complete_gate**
- 差異: 将軍システムは「revert」ではなく「BLOCK→修正→再実行」。revertより強い（修正が学習を伴う）

### 2.2 永続メモリ（CORAL/engram/greyhaven-autocontext）
- セッション横断の知識保持
- CORAL: 共有永続メモリ + SOTA（arXiv:2604.01658）
- engram: 頻度重み付きクロスセッション知識検索
- autocontext: 評価→永続化→段階的検証→安価ランタイム蒸留
- 将軍システム対応: **lessons + deepdive + MCP Memory + ラルフループ**
- 差異: 将軍システムは「自動蒸留」がない（lessonsは手動抽出→自動適用）。autocontextの「安価ランタイム蒸留」は混成編成（Opus→Sonnet/GPT切替）と類似

### 2.3 メタレベル最適化（GEPA/HGM/ADAS/SICA）
- エージェント自身のアーキテクチャ/プロンプトを自動進化
- GEPA (ICLR 2026 Oral): 自然言語反射でプロンプト進化。RLを上回る
- HGM: SWE-benchパフォーマンスのメタ最適化
- ADAS (ICLR 2025): メタエージェントがアーキテクチャをコードで発明
- SICA (ICLR 2025 Workshop): スキャフォールドレベル自己改善
- 将軍システム対応: **cmd_save.shの自己改善（今日のFP率修正）+ 成長ループ3層**
- 差異: 将軍システムのメタ改善は人間駆動（殿の指摘→deepdive→gate改善）。自動メタ改善はまだない

### 2.4 マルチエージェント調整（ClawTeam/CORAL/hyperspaceai/Orchestra）
- ClawTeam: 並列GPU研究方向の分散
- CORAL: 多エージェント進化
- hyperspaceai: P2Pゴシップ + CRDTリーダーボード
- Orchestra: 二重ループ（内部最適化+外部合成）
- 将軍システム対応: **鎖の原理 + inbox + dashboard + 掲示板 + 三層学習ループ**
- 差異: 将軍システムは垂直統制（鎖）。水平知識共有（忍者間ゴシップ）がない

### 2.5 ドメイン横断汎化（zkarimi22/autoresearch-anything/GEPA）
- 同一ループを任意メトリクスに適用
- autoresearch-anything: プロンプト/API性能/LP/テスト/SQL/設定
- 将軍システム対応: **cmdパターンの汎用性（偵察/実装/最適化/検証の4モード）**
- 差異: 将軍システムはソフトウェア工学に特化。金融研究（DM-Signal）にも適用しているが、ドメイン横断の汎用フレームワーク化はしていない

## §3 将軍システムが既に実装済みの機能

| エコシステムの概念 | 将軍システム実装 | 成熟度 |
|-------------------|-----------------|--------|
| Keep-or-revert | gate BLOCK/PASS + binary_checks | ★★★★★ |
| 永続メモリ | lessons + deepdive + MCP + ラルフループ | ★★★★★ |
| クロスセッション学習 | /clear→知識基盤残存→強くてニューゲーム | ★★★★★ |
| マルチエージェント調整 | 鎖 + inbox + dashboard + 掲示板 | ★★★★☆ |
| メタレベル最適化 | cmd_save.sh自己改善 + 成長ループ | ★★★☆☆ |
| 実行トレース解析 | logs/cmd_design_quality.yaml + FP率分析 | ★★★★☆ |
| 段階的検証 | AC binary_checks + cmd_complete_gate + 軍師レビュー | ★★★★★ |
| ドメイン特化適応 | DM-Signal金融研究 + infra | ★★★★☆ |

## §4 将軍システムにない機能（取り込み候補）

### 4.1 自動メタ改善（GEPA/ADAS/SICA）
- 現状: 殿の指摘→deepdive→gate改善。人間駆動
- 取り込み案: gate FP率が閾値超→自動で修正cmdを起票する仕組み
- 優先度: 中（現状の人間駆動でも回っている。自動化は精度リスク）

### 4.2 水平知識共有（ClawTeam/hyperspaceai）
- 現状: 忍者間は独立。知識は鎖（将軍→家老→忍者）でのみ伝達
- 取り込み案: 忍者のlesson_candidateを掲示板に自動投稿 → 他忍者が参照可能
- 優先度: 低（忍者は/clearで記憶を失う。lesson_candidateは家老が回収するフローが既にある）

### 4.3 安価ランタイム蒸留（autocontext）
- 現状: 混成編成（Opus/Sonnet/GPT）は手動切替
- 取り込み案: タスク複雑度に応じて自動モデル選択
- 優先度: 中（/henseiスキルで手動切替は可能。自動化はタスク分類精度次第）
- 既存接点: 修行サイクルのモデル別FP率データが分類の材料になりうる

### 4.4 群知能による並列仮説探索（ClawTeam/mutable-state-inc）
- 現状: 忍者は1タスク=1忍者。同一問題の並列アプローチ（万全偵察）はあるが、仮説生成は将軍が行う
- 取り込み案: 研究フェーズで忍者が独立に仮説生成→実験→結果を統合
- 優先度: 低（鎖の原理に反する。将軍の判断品質が先）

### 4.5 P2P結果ゴシップ + CRDTリーダーボード（hyperspaceai）
- 現状: dashboard + 掲示板は一方向投稿。リーダーボードなし
- 取り込み案: 忍者の修行結果（L1-L4 FP率）を自動ランキング
- 優先度: 低（修行サイクルのcontext/training-cycle.mdに実績データはある。ランキング化は動機付け効果だが、忍者にはモチベーション概念がない）

### 4.6 自然言語反射によるプロンプト進化（GEPA）
- 現状: CLAUDE.md / instructions/*.md は人間が手動編集
- 取り込み案: gate BLOCK/WARNの傾向分析 → instructions自動修正提案
- 優先度: 高（GEPA的アプローチで「なぜこのBLOCKが出るか」→「instructionsのどこを変えれば出なくなるか」を自動提案）
- 既存接点: cmd_save.sh Session State（過去BLOCK履歴表示）が材料

### 4.7 研究ライフサイクル完全自動化（AI-Scientist/AI-Researcher/CORAL）
- 現状: 将軍がcmd起票→家老が配備→忍者が実行。研究テーマは殿が指定
- 取り込み案: 仙人構想（鎖の外で自走する11人目）と接続可能
- 優先度: 温め中（仙人v1-v5設計済み。実装はアーキテクチャ確定後）

## §5 注目プロジェクト詳細

### GEPA (gepa-ai/gepa) — ICLR 2026 Oral
- Genetic-Pareto: 自然言語の「反射」でプロンプトを進化
- RLベースライン（GRPO等）を上回る
- 将軍システムとの接点: deepdive追体験 = 人間版の反射。GEPAは機械版
- 取り込み価値: **高**。gate BLOCKパターンからinstructionsへの自動修正提案

### CORAL (Human-Agent-Society/CORAL) — arXiv:2604.01658
- 長実行エージェント + 共有永続メモリ + SOTA（10数学/アルゴリズムタスク）
- 将軍システムとの接点: ラルフループ + lessons永続化と同構造
- 差異: CORALは「共有」メモリ。将軍システムはロール別メモリ（将軍MCP/家老lessons/忍者なし）
- 取り込み価値: 中。共有メモリは鎖の原理と相反する可能性

### AI-Researcher (HKUDS/AI-Researcher) — NeurIPS 2025
- 仮説→実験→査読の完全自動化。novix.scienceで本番運用
- 将軍システムとの接点: 仙人構想の目標に近い
- 取り込み価値: **高**（仙人設計の参考）

### AIDE (WecoAI/aideml) — ツリーサーチMLエンジニアリング
- ツリーサーチで分岐→評価→最良パス選択
- 将軍システムとの接点: GS（グリッドサーチ）の全探索と類似
- 差異: AIDEは探索自体を自動化。将軍のGSは探索パラメータを将軍が設計

### autocontext (greyhaven-ai/autocontext)
- 評価→永続知識→段階的検証→安価ランタイム蒸留
- 将軍システムとの接点: 混成編成（Opus→Sonnet/GPT）
- 取り込み価値: 中（タスク複雑度→モデル自動選択の設計参考）

## §6 エコシステムの教訓（将軍システムへの示唆）

### 6.1 Keep-or-revertは不変パターン
70+プロジェクト全てがこのパターンを採用。将軍のgate BLOCK/PASSは正しい方向。
ただし「revert」ではなく「修正→再実行」は将軍システム独自の強み（学習を伴う）。

### 6.2 メタ改善が次の成長段階
GEPA/ADAS/HGMは「エージェント自身が自分のアーキテクチャを改善する」。
将軍システムは「人間（殿）がアーキテクチャを改善する」段階。
次のステップ: gate分析→instructions自動修正提案（GEPAアプローチ）

### 6.3 永続メモリの設計は成熟
CORAL/engram/autocontextの3系統が収束: 頻度重み付き + 関連度検索 + 蒸留。
将軍システムのlessons + MCP + deepdiveは同等かそれ以上（追体験という独自概念）。

### 6.4 群知能は鎖と相反する — 慎重に
ClawTeam/hyperspaceai的な水平共有は魅力的だが、鎖の原理（殿→将軍→家老→忍者）と矛盾する。
殿の設計意図: 制限の中で成長する（究極系原則）。水平共有は制限を緩める方向。

### 6.5 ドメイン横断は将軍システムの拡張余地
autoresearch-anythingが示す「任意メトリクスへの適用」は、
将軍システムのcmdパターンを他ドメイン（教育/運用/コンテンツ）に展開する道筋。

## §7 プロジェクト全量カタログ

### 汎用後継
| プロジェクト | 特徴 |
|-------------|------|
| kayba-ai/recursive-improve | 実行トレース→失敗パターン分析→修正 |
| vukrosic/auto-research | ファイルベース制御面 |
| uditgoenka/autoresearch | Claude Code skill化 |
| leo-lilinxiao/codex-autoresearch | Codex native + resume + 並列実験 |
| supratikpm/gemini-autoresearch | Gemini CLI + Google Search grounding + 1M context |
| davebcn87/pi-autoresearch | ダッシュボード + 信頼度追跡 |
| greyhaven-ai/autocontext | 評価→永続知識→段階的検証→蒸留 |
| jmilinovich/goal-md | GOAL.mdパターン（計測可能フィットネス関数を先に構築） |
| james-s-tayler/lazy-developer | Ralph Mode + 優先度付き最適化目標 |
| mutable-state-inc/autoresearch-at-home | 群スタイル仮説交換 + マルチGPU |
| zkarimi22/autoresearch-anything | 任意メトリクス汎化 |
| ShengranHu/ADAS | メタエージェントがアーキテクチャ発明 (ICLR 2025) |
| MaximeRobeyns/SICA | スキャフォールド自己改善 (ICLR 2025 Workshop) |
| metauto-ai/HGM | SWE-benchメタ最適化 |
| gepa-ai/gepa | 自然言語反射プロンプト進化 (ICLR 2026 Oral) |
| MrTsepa/autoevolve | GEPA + 自己対戦 + Elo/Bradley-Terry |
| HKUDS/ClawTeam | 並列GPU研究方向の群知能 |
| Orchestra-Research/AI-Research-SKILLs | 二重ループアーキテクチャ |
| WecoAI/aideml | ツリーサーチMLエンジニアリング |

### 研究エージェント
| プロジェクト | 特徴 |
|-------------|------|
| SakanaAI/AI-Scientist v1 | 初の包括的科学発見システム |
| SakanaAI/AI-Scientist-v2 | テンプレート不要のドメイン横断 |
| HKUDS/AI-Researcher | NeurIPS 2025。novix.science本番運用 |
| Human-Agent-Society/CORAL | 長実行エージェント + 共有永続メモリ + SOTA |
| openags/Auto-Research | 研究ライフサイクル全体のエージェント編成 |
| aiming-lab/AutoResearchClaw | トピック→文献→実験→分析→査読→論文 |
| OpenRaiser/NanoResearch | SLURM対応 + 自律実験 |
| hyperspaceai/agi | P2P + CRDTリーダーボード |
| SamuelSchmidgall/AgentLaboratory | アイデア→文献→実験→報告 |

### 評価ベンチマーク
| プロジェクト | 特徴 |
|-------------|------|
| snap-stanford/MLAgentBench | 13 MLタスク |
| openai/mle-bench | MLエンジニアリング |
| chchenhui/mlrbench | 201オープンエンドタスク |
| THUDM/AgentBench | 8環境 (ICLR 2024) |

### ドメイン特化
| プロジェクト | 特徴 |
|-------------|------|
| chrisworsey55/atlas-gic | 取引エージェント + ローリングSharpe |
| RightNow-AI/autokernel | GPUカーネル最適化 |
| ArchishmanSengupta/autovoiceevals | 音声AI強化 |
| mattprusak/autoresearch-genealogy | 系図研究 |

### 実践事例
| 事例 | 成果 |
|------|------|
| Shopify Liquid最適化 | 大幅速度改善 |
| Driveline野球バイオメカニクス | 球速予測の有意な改善 |
| Vesuvius Challenge巻物検出 | クロススクロール汎化改善 |
