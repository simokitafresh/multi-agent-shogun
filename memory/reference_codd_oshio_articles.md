# CoDD おしお記事 参照メモ

<!-- last_updated: 2026-05-02 cmd_2485 -->

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
