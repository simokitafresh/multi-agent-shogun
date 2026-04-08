# cmd_888: Self-Healing / Auto-Remediation パターン業界調査
> cmd_888_B (kagemaru) | 2026-03-13 | type: recon

## §1 業界事例（Web検索 — 5事例）

### 事例1: Kubernetes Operator Reconciliation Loop
- **仕組み**: Controller が desired state (Git/CRD) と actual state (cluster) を定期比較。差分検出時に自動修復。Fetch→Compare→Act→Report の4段サイクルが永続実行
- **成功要因**: 宣言的状態管理（desired state が単一ソース）、冪等性（同じ修復を何度実行しても安全）、controller-runtime の work queue が重複イベントを集約
- **失敗パターン**: cert-manager/Istio等が正当に変更したリソースを「ドリフト」と誤検知→修復→再変更→修復の無限ループ。exclusion list 未設定が原因
- **ループ暴走防止**: 比較ロジックによる冪等性（差分なし=no-op）、reconciliation interval（ArgoCD default 3分）、exclusion list で正当な外部変更を除外
- **偽陽性対処**: 動的ベースラインとcontextual analysis。「期待される変動」と「真の異常」を区別
- **部分失敗**: controller-runtime が work queue にリトライを積む。exponential backoff で部分失敗状態から回復を試行
- **人間介入**: auto-sync OFF時は手動 sync トリガー（UI/CLI）。ReconcileAt annotation で on-demand 制御
- **適用可能性**: ★★★ — 我々のgate→skill自動修復はまさにこのパターン。desired state=ルール定義、actual state=gate検出結果、reconcile=skill実行
- **出典**: [ArgoCD Reconciliation (Rafay)](https://rafay.co/ai-and-cloud-native-blog/understanding-argocd-reconciliation-how-it-works-why-it-matters-and-best-practices), [K8s Reconciliation Patterns (Kassaei)](https://hkassaei.com/posts/kubernetes-and-reconciliation-patterns/), [Flux CD Loop](https://oneuptime.com/blog/post/2026-03-05-flux-cd-reconciliation-loop/view)

### 事例2: Agentic AI Self-Healing Infrastructure (Algomox / Komodor)
- **仕組み**: 5層アーキテクチャ — Observability層(テレメトリ収集)→Cognitive Processing(ML異常検出)→Event Correlation(根本原因特定)→Knowledge Management(過去事例学習)→Execution Framework(修復実行)
- **成功要因**: アンサンブル手法で検出精度向上、段階的展開（低リスクから開始）、修復結果のフィードバックループで継続学習
- **失敗パターン**: ロールバック機構なしで修復が二次障害を引き起こすケース。修復が中途半端に終わる状態管理の欠如
- **ループ暴走防止**: adaptive execution（フィードバックに基づき行動変更）、state management（進行中の修復を追跡し重複実行を防止）
- **偽陽性対処**: 多層検出（unsupervised clustering + deep learning + 動的ベースライン）、confidence scoring で異常の確信度を数値化
- **部分失敗**: fault-tolerance機構、自動リトライ + alternative execution paths、escalation（自動修復の限界到達時に人間へ）
- **人間介入**: approval workflow（機密操作は承認必須）、escalation path、governance structure（新AI能力の承認プロセス）、監査ログ
- **適用可能性**: ★★☆ — Knowledge Management層（過去の修復結果学習）は我々の lessons.yaml と類似。ただしML異常検出は過剰
- **出典**: [Algomox Agentic AI](https://www.algomox.com/resources/blog/self_healing_infrastructure_with_agentic_ai/), [Komodor Klaudia](https://www.globenewswire.com/news-release/2025/11/05/3181574/0/en/Komodor-Introduces-Autonomous-Self-Healing-Capabilities-for-Cloud-Native-Infrastructure-and-Operations.html)

### 事例3: Incident.io Automated Runbook (3層構造)
- **仕組み**: Layer1 Trigger/Triage（チャネル作成・ページング・重要度設定）→ Layer2 Diagnostics（デプロイ履歴・メトリクスグラフ・関連アラート自動収集）→ Layer3 Remediation（承認ゲート付きアクション実行）
- **成功要因**: 非破壊的自動化から開始（読み取り専用→段階的に書き込み権限追加）、高頻度・予測可能なインシデントから着手、サービスオーナーシップメタデータとの連携
- **失敗パターン**: 全インシデント同時自動化の試み（失敗必至）、静的ドキュメントの陳腐化、承認ゲートなしの本番変更
- **ループ暴走防止**: conditional routing（異なるインシデント種別→異なるワークフロー）、graduated automation（段階的権限拡大）
- **偽陽性対処**: アクションプレビュー（クエリ差分・デプロイ変更を実行前に表示）、条件ルーティング
- **部分失敗**: 明示的な対処なし。承認ゲートで事前防止に注力
- **人間介入**: Kill query [Yes/No]、Pod追加 [Approve/Deny]、ロールバック（diff表示+原著者タグ）、ステータスページ更新承認
- **適用可能性**: ★★★ — 3層構造が我々のgate(検出)→提案→skill(修復)と直接対応。graduated automation（非破壊→破壊的の段階拡大）は最重要設計原則
- **出典**: [Incident.io Runbook Guide](https://incident.io/blog/automated-runbook-guide)

### 事例4: GitOps Reconciliation (Flux CD / ArgoCD)
- **仕組み**: Source Controller がGit/Helm/OCIから desired state を fetch → Kustomize/Helm Controller が live cluster と比較 → 差分を apply → health check で検証。Pull-based モデル（クラスタ側がGitをポーリング）
- **成功要因**: Git を Single Source of Truth として使用、Git webhook で即座に反応（ポーリング間隔に依存しない）、リソースレベルのドリフト検出
- **失敗パターン**: auto-sync ON + exclusion list 未設定 → Istio/cert-manager の正当な変更を巻き戻し → reconciliation loop で不安定化
- **ループ暴走防止**: 冪等性（差分なし=アクションなし）、reconciliation interval の調整（安定アプリ=長間隔、重要アプリ=短間隔）
- **偽陽性対処**: exclusion list を auto-sync 有効化 **前に** 構築（Pulumi Blog ベストプラクティス）
- **部分失敗**: health check で apply 後の状態検証。失敗時は次回 reconciliation で再試行
- **人間介入**: auto-sync OFF = 手動同期、webhook による明示的トリガー
- **適用可能性**: ★★★ — 「exclusion list を先に作れ」は我々の「修復対象を明示的にホワイトリスト化せよ」に直結
- **出典**: [Flux CD Concepts](https://fluxcd.io/flux/concepts/), [Pulumi GitOps Best Practices](https://www.pulumi.com/blog/gitops-best-practices-i-wish-i-had-known-before/)

### 事例5: Hoop.dev Access Guardrails (AI Runbook Security)
- **仕組み**: 静的承認ワークフローではなく continuous verification loop — 実行時にポリシーがコンテキスト（実行タイミング・対象環境・データ分類・行動パターン）をリアルタイム評価
- **成功要因**: 事前ブロック型（unsafe action を実行前に遮断）、自動PII/credential除去、ポリシー継承（automation stack 全体に適用）
- **失敗パターン**: （記事では明示なし。ガードレール自体が防止策）
- **ループ暴走防止**: （明示なし）
- **偽陽性対処**: （明示なし）
- **部分失敗**: （明示なし）
- **人間介入**: 承認ボトルネック排除と provable governance の両立。manual review を減らすが排除はしない
- **適用可能性**: ★★☆ — continuous verification loop（リアルタイムポリシー評価）は gate 検出と概念的に一致。ただし我々のgateはバッチ実行（セッション開始時）でリアルタイムではない
- **出典**: [Hoop.dev Guardrails](https://hoop.dev/blog/how-to-keep-ai-runbook-automation-and-ai-driven-remediation-secure-and-compliant-with-access-guardrails/)

## §2 横断的知見（5事例から抽出した設計原則）

### ループ暴走防止の3原則
1. **冪等性**: 差分なし=no-op。同じ修復を何度実行しても害がない設計（K8s operator, GitOps）
2. **Exclusion list / ホワイトリスト**: 修復対象を明示的に限定。auto-sync前にリストを構築（ArgoCD教訓）
3. **State tracking**: 進行中の修復を追跡し重複実行を防止（Algomox state management）

### 偽陽性対処の3原則
1. **多層検出**: 単一指標でなくアンサンブル手法。confidence score で確信度を数値化
2. **動的ベースライン**: 季節変動・利用パターンを考慮した正常範囲の動的更新
3. **アクションプレビュー**: 修復実行前に「何をするか」を表示し人間が判断可能に

### 部分失敗対処の2原則
1. **ロールバック機構**: 修復が二次障害を起こした場合の自動巻き戻し
2. **Exponential backoff + alternative path**: リトライ間隔を指数的に拡大、代替修復パスへフォールバック

### 人間介入ポイントの設計
1. **Graduated automation**: 非破壊的（診断のみ）→段階的に破壊的権限を付与（Incident.io最重要教訓）
2. **Approval gate**: 本番変更は承認必須。ただしボトルネックにしない（Hoop.dev: 承認排除≠自動化）
3. **Escalation path**: 自動修復の限界到達時に明示的に人間へエスカレーション

## §3 X検索結果（AI Agent自動修復の最新議論）

Context Pack保存先: `data/x-research/20260312_184817Z_self-healing-automation-agent-detect-rem.md`

### 主要クラスター
1. **Autonomous Loop Builders**: Claude Code /loop でログ監視→issue/PR生成→deployの閉ループ構築。guardrails必須でdrift注意
2. **CLAUDE.md Self-Improvement**: Boris Cherny(Claude Code作成者)のinternal workflowをmd化。correction→rule化でmistake rate低下
3. **Multi-Agent Orchestration**: subagents/parallel sessions/MCPで複雑タスク分担。TDD/verify loop強調

### 重要な警告事例
- **Agent Drift**: guardrailsなしで数イテレーション後にdrift（@PrimeLineAI）。exit condition（3回no-improvement→停止）やgit revert必須
- **Security Risks**: prompt injectionでprivate repo leak/data wipe事例（@intercept_dan）。root access回避+MCP policy enforcement推奨
- **Cost/Rate**: loop多用でtoken爆発リスク。間隔設計が重要（1m commit〜45m health check）

### データポイント
- GitHub commits 4%がClaude Code由来（2026-03時点）、年末20%+予測
- CLAUDE.md効果: correction→rule化で3ヶ月でproject熟練dev並み
- Loop間隔実例: 1m commit, 5m PR babysit, 15m log scan, 20m update, 30m deploy check, 45m health

## §4 我々への適用可能性マトリクス

| 業界パターン | 我々の対応物 | 適用度 | 注意点 |
|-------------|------------|--------|--------|
| K8s Reconciliation Loop | gate検出→skill修復 | ★★★ | 冪等性設計が鍵。修復が新問題を生まないこと |
| GitOps exclusion list | 修復対象ホワイトリスト | ★★★ | auto-remediation対象のgate→skillマッピングを先に定義 |
| Incident.io Graduated Automation | 段階的権限拡大 | ★★★ | Phase1=診断のみ、Phase2=非破壊修復、Phase3=破壊的修復 |
| Approval gate | 殿の承認 | ★★☆ | 高頻度gateには自動修復、低頻度/高リスクには承認必須 |
| Confidence scoring | gate WARN vs ALERT | ★★☆ | 既存のWARN/ALERTレベルがconfidence scoring相当 |
| Adaptive execution | lessons.yaml学習 | ★☆☆ | 現状は手動。自動化は過剰投資の可能性 |
