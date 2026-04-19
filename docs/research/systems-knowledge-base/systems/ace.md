# ACE Framework

> David Shapiro (daveshap)作。6層階層アーキテクチャで自律的認知エンティティを構築する概念フレームワーク。OSIネットワークモデル着想。Northbound/Southboundバスで層間通信。arXiv論文化済み。2024年8月アーカイブ（read-only）。

## Basic Info

| 項目 | 内容 |
|------|------|
| Author | David Shapiro (daveshap)、共著: Wangfan Li / Manuel Delaflor / Carlos Toxtli |
| Status | Archived (read-only, 2024-08-13以降) |
| Stars | 1,500+(2026-04-19時点) |
| Forks | 218 |
| Watchers | 91 |
| Version | — (リリースタグなし) |
| Last Commit | 2024-02-06 (c6693ee2) |
| Last Push | 2024-03-17 |
| Repo | https://github.com/daveshap/ACE_Framework |
| License | MIT |
| Primary Language | Python (73.9%) |

## Design Philosophy

**「内部認知を優先し、倫理的整合性を最上位に置く自律エージェント設計」**

David Shapiroの核心：AIが欠いているのは能力ではなく「それらを結びつけ高度な認知を生み出すソフトウェアアーキテクチャ」。

- **Cognition-first**: 環境への反応ループではなく、内部での想像・反省・戦略思考を優先。外部環境とのインタラクションは二次的。
- **Top-down ethical control**: 下位層の懸念（効率・自己保存）が道徳原則を歪めないよう、Aspirational Layerが最上位で倫理を保持。人間の前頭前皮質が本能を抑制する構造に対応。
- **OSI inspired**: OSIネットワークモデルの7層構造を参考に、自律エージェントの認知を6層に分割。各層が明確な役割を持ち、隣接層とのみ通信する。
- **100% local / model agnostic**: クラウド依存なし。特定LLMプロバイダーへのベンダーロックイン回避を設計原則とする。
- **Human interpretable**: 全層間メッセージを自然言語でエンコードし、人間の監視・透明性を確保。

### 5つの基本原則

| 原則 | 内容 |
|------|------|
| Be Scrappy | ボランティア駆動開発の中での実験と迅速なイテレーションを奨励 |
| Avoid Vendor Lock-in | モデル不可知性を維持し、複数プロバイダへの開放性を保持 |
| Task-Constrained Approach | 測定・テスト可能な能力を中心にフレームワークを設計 |
| Avoid Overcomplication | 包括的解決を最初から目指さず、段階的マイルストーンを追求 |
| Establish New Principles | 自律ソフトウェア設計の新しいアーキテクチャパラダイムを認識・確立 |

### 道徳フレームワーク階層

| 優先度 | 構成 | 内容 |
|--------|------|------|
| 1位 (最高) | Greater Purpose / Heuristic Imperatives | 繁栄の増大・苦痛の低減・理解の促進を普遍的に目指す北極星 |
| 2位 | Human Rights Framework | 人権規範を組込んだ倫理原則 |
| 3位 | Agent Mission | 個別エージェントの目的・タスク |

## Architecture

### 6層スタック

```
Layer 1: Aspirational Layer       — 倫理基盤(heuristic imperatives, human rights)
Layer 2: Global Strategy Layer    — 環境コンテキスト統合・高レベル戦略精緻化
Layer 3: Agent Model Layer        — 自己能力・限界の自己理解・メタ認知
Layer 4: Executive Function Layer — 詳細プロジェクト計画・リソース配分
Layer 5: Cognitive Control Layer  — 動的タスク選択・切替
Layer 6: Task Prosecution Layer   — デジタル/物理アクション実行
```

### 通信バス

| バス | 方向 | 役割 |
|------|------|------|
| Northbound Bus | 下位 → 上位 | 内部状態・センサーデータ・テレメトリを上位層へ報告 |
| Southbound Bus | 上位 → 下位 | 指令・指示を上位層から下位層へ伝達 |

- **単方向2バス**: 各バスは一方向のみ。双方向通信は両バスの組み合わせで実現。
- **自然言語エンコード**: 全メッセージが人間可読形式。LLMが各層の処理エンジン。
- **透明性確保**: メッセージの解釈可能性が設計上の必須要件。

### 想定デプロイメントモデル

| カテゴリ | 内容 |
|---------|------|
| Personal Assistant | 個人向けコンパニオン・補助エージェント |
| Game NPC | 自律的行動を持つゲームキャラクター |
| Corporate Employee | 企業内自律エージェント |
| Embodied Robot | 物理ロボットへの実装 |

### 実装形態

- **Python主体 (73.9%)**: コアフレームワークとサンプル実装
- **GitHub Discussions + Discord**: コミュニティエンゲージメント
- **`ACE_Framework.md`**: フレームワーク本体ドキュメント(メインリポジトリ)
- **`ACE_L1_Aspiration`**: Aspirational Layer独立リポジトリ (github.com/daveshap/ACE_L1_Aspiration)
- **arXiv論文**: 2310.06775 (2023-10-03投稿, 2023-11-01改訂)

## Key Features

| 機能名 | 説明 | 導入 |
|--------|------|------|
| 6層認知アーキテクチャ | Aspirational → Task Prosecutionの階層で認知を分割 | v1.0(概念設計) |
| Aspirational Layer | 倫理原則・ヒューリスティック命令を最上位に配置 | v1.0 |
| Northbound/Southbound Bus | 単方向2バスで層間通信。自然言語エンコード | v1.0 |
| Model Agnosticism | GPT-4/Llama/Claude等を透過的に切り替え可能 | v1.0 |
| Heuristic Imperatives | 繁栄・苦痛低減・理解促進の3命令を倫理基盤として組込み | v1.0 |
| Cognitive Control Layer | タスクキュー管理・動的タスク切替・優先度制御 | v1.0 |
| Agent Model Layer | 自己能力マッピング・メタ認知・自己参照 | v1.0 |
| Layer Integration (v2) | 2024-01-08: 層間通信のイベントベース化・モジュール構造リファクタリング | 2024-01 |

## Changelog since 2026-03-13

| 日付 | 変更 | 影響 |
|------|------|------|
| — | 変更なし | リポジトリは2024-08-13にアーカイブ済み。2026-03-13以降の更新は確認できない |

> **備考**: 最終commit 2024-02-06 (README更新)。2024-08-13にGitHub archive設定。概念アーキテクチャとしての参照価値が中心となっている。

## Notable Techniques

| テクニック名 | 説明 | このシステム固有か |
|-------------|------|-----------------|
| OSI-inspired 6層分割 | ネットワーク層モデルをエージェント認知に転用 | 固有(ACE発祥) |
| Northbound/Southbound Bus | 単方向2バス通信でエージェント内メッセージフローを明確化 | 固有(ACE発祥) |
| Aspirational Layer優先 | 道徳・倫理原則を最上位層に固定し下位層の意思決定を制約 | 固有(ACE発祥) |
| Heuristic Imperatives | 3命令(繁栄増大/苦痛低減/理解促進)を最高優先度の倫理基盤として定式化 | 固有(ACE発祥) |
| Natural Language Inter-layer | 層間メッセージをすべて自然言語でエンコード。LLMを各層のプロセッサとして利用 | 固有(ACE発祥) |
| Cognition-first設計 | 反応ループではなく内部認知(想像/反省/戦略)を優先するエージェント設計原則 | 固有(ACE発祥) |

## Ecosystem

| カテゴリ | 内容 |
|---------|------|
| コミュニティ | Stars 1.5k、Forks 218。GitHub Discussions + Discord(ボランティア駆動) |
| 論文 | arXiv 2310.06775「Conceptual Framework for Autonomous Cognitive Entities」(2023-10-03) |
| 独立レポジトリ | ACE_L1_Aspiration: Aspirational Layer独立実装(github.com/daveshap/ACE_L1_Aspiration) |
| 紹介記事 | Medium記事「Autonomous Agents Are Here: Introducing the ACE Framework」(2023-09-17) |
| アーカイブ状態 | 2024-08-13以降 read-only。後継プロジェクト等の明示なし |

## Pitfalls

| 落とし穴 | 何が問題か | どこで表面化するか |
|---------|-----------|------------------|
| archived前提の採用 | リポジトリは2024-08-13以降read-onlyで、上流の機能追加・脆弱性修正・運用改善を期待できない | 長期運用、依存更新、実装継続時 |
| 自然言語バスの曖昧さ | 層間通信を自然言語に寄せるため、人間可読性は高いが、厳密な状態同期や機械検証は別途設計が要る | 複雑なタスク引継ぎ、監査、再現性要求時 |
| 概念先行で運用層が薄い | 6層認知モデルは強いが、CI/CD、権限制御、レビュー、障害復旧などの実運用面はフレームワーク外で補う必要がある | 本番導入、チーム運用、複数エージェント配備時 |

## Cross-References

| 軸 | 対象 | 関係 |
|----|------|------|
| 補完 | [gstack](gstack.md) | ACEが示す抽象的な認知階層に対し、gstackはレビュー・QA・shipまでの実務ロール分離を提供する |
| 競合 | [vercel](vercel.md) | ACEは100% local / model agnosticを重視する一方、VercelはSandbox・Gateway・Hosted Agentを含むplatform-native運用を採る |
| 前提 | [oshio](oshio.md) | ACEの概念を実際の多エージェント運用へ落とすには、oshioのような通信・状態遷移・ハーネス層が別途必要になる |

## Sources

| カテゴリ | URL |
|---------|-----|
| Repository | https://github.com/daveshap/ACE_Framework |
| Framework Doc | https://github.com/daveshap/ACE_Framework/blob/main/ACE_Framework.md |
| README | https://github.com/daveshap/ACE_Framework/blob/main/README.md |
| arXiv論文 | https://arxiv.org/abs/2310.06775 |
| Medium記事 | https://medium.com/@dave-shap/autonomous-agents-are-here-introducing-the-ace-framework-a180af15d57c |
| ACE_L1_Aspiration | https://github.com/daveshap/ACE_L1_Aspiration |

## Verification

| 項目 | 内容 |
|------|------|
| verified_at | 2026-04-19T00:40:00+09:00 |
| method | WebFetch(GitHub repo/commits/ACE_Framework.md) + WebSearch + WebFetch(arXiv/Medium) |
| source | github.com/daveshap/ACE_Framework (commit履歴・archive状態確認), arxiv.org/abs/2310.06775 |
| confidence | HIGH — GitHub直接確認。Stars/archive状態・最終commit日を原典で検証 |
| 前回差分基準 | 2026-03-13以降の変更なし(archived 2024-08-13)。概念参照価値のみ |
