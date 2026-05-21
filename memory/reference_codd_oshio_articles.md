# CoDD おしお記事 参照メモ

<!-- last_updated: 2026-05-15 cmd_2760 -->

## codd-skeleton-complete (2026-04)

Source: `https://zenn.dev/shio_shoppaize/articles/codd-skeleton-complete`

| 観点 | 知見 | 将軍システムへの反映 |
|------|------|----------------------|
| 問題設定 | SDD/Markdown設計書の弱点は「作った後に腐る」こと。静的docsは要求変更に追随しない | docs作成完了ではなく、更新伝播できる状態を完了条件に含める |
| 依存グラフ | docs frontmatterの`codd.node_id` / `depends_on`から`codd scan`で依存グラフを作る | context/docs/researchの設計書は依存先を明示し、scan対象にできる形を優先 |
| 影響分析 | 上流要求やコード変更に対し`codd impact`でGreen/Amber/Grayの影響範囲を出す | 変更対象の列挙を手作業で完結させず、影響範囲の機械確認を標準化する |
| 伝播 | `codd propagate --update`で下流docsを自動更新する | after設計書作成後は、必要に応じて下流docs更新まで確認する |
| extract | `codd extract`で既存コードから設計docsを逆生成し、CoDD自身もCoDDで管理している | brownfieldでは先に現物からdocsを起こし、想像の設計書を書かない |
| 未解決 | 1000ファイル級brownfield、増分extract、UI設計層、Mermaid可視化などは今後の課題 | 大規模legacyでの一括適用は過信せず、対象範囲と限界を報告する |

## shogun-2026-04-landscape (2026-05-11)

Source: `https://zenn.dev/shio_shoppaize/articles/shogun-2026-04-landscape`

| 観点 | 知見 | 将軍システムへの反映 |
|------|------|----------------------|
| 業界地図 | IDE化(Claude Code/Codex/Cursor等)とSDD化(spec-kit/Kiro/BMAD/Augment等)が同時進行。CoDDは整合性駆動側、multi-agent-shogunはMulti-CLI Orchestrator側 | CoDDを単独ツールでなく、将軍システムの実行層と相互強化する方法論層として扱う |
| 立ち位置 | multi-agent-shogun + CoDDは「Multi-CLI統合」と「整合性駆動」の交点 | context更新時はCoDDのCLI機能だけでなく、shogun運用への接続を併記する |
| dogfooding | shogunでCoDDを作り、CoDDが進化するとshogunの設計判断も良くなる | CoDD更新時はsemantic indexとスキルも同時更新し、次セッションの判断入力へ戻す |
| Harness Engineering | Prompt/Contextだけでなく、Hooks/Skills/Orchestration/Coherence Driven flowまで含めて品質を強制する | CoDD知見は「読むべき記事」ではなく、gate・skill・task YAMLへ還流する対象 |

## codd-v2-17-milestone (2026-05-13)

Source: `https://zenn.dev/shio_shoppaize/articles/codd-v2-17-milestone`

| 観点 | 知見 | 将軍システムへの反映 |
|------|------|----------------------|
| 北極星 | 人間は要件定義と触った後の感想だけを言い、AIが設計書・実装・テストの整合性を維持する | 改善依頼は実装指示だけでなく、観測した事象(PHENOMENON)として記録できる形を優先 |
| `codd elicit` | 要件の穴をAIが質問し、lexicon/coverage軸として補う | cmd設計時の曖昧なACは`elicit`対象。人間の注意でなく質問生成と承認で埋める |
| `codd fix [PHENOMENON]` | 自然言語の事象から関連設計書を選び、設計書 -> 実装 -> テストを更新し、DAG検査まで回す | CI REDだけでなく、UX/仕様違和感の修正にもCoDDを使える |
| `codd dag verify` | 設計書・コード・テストをDAGで検査し、家系図の欠落を検出する | docs更新の完了条件にDAG/伝播/semantic index反映を含める |
| v2.17実績 | v1.34以前のgreenfield難を5日でv2.17.1まで改善。次の挑戦はbrownfield | v2.x情報ではv1.xの制限を過去履歴として扱い、現CLIを必ず実測する |

---

## 因果リンク

- → [[technique_judgment_framework]] CoDD設計書→判断フレームワークの道具
