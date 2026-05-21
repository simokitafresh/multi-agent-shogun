# ドキュメントインデックス + DB/パリティ/APIルール抜粋
<!-- cmd_286 | 2026-02-23 | ops.mdから移動 -->
<!-- 結論: docs/skills/(25件)+docs/rule/(25件)全一覧+DB接続・パリティ・API使用法ルール -->

## docs/skills/ (25件)

| ファイル | 目的 | 優先度 | マーカー |
|---------|------|--------|---------|
| _INDEX.md | skills全体の目次と更新導線の集約 | high | — |
| api-reference.md | バックエンドAPIの包括リファレンス。認証・エンドポイント・環境設定 | high | API |
| building-block-addition-guide.md | 新規BB追加の実装チェックリスト(BE→registry→FE型→ドキュメント) | high | — |
| building-block-pattern.md | FoFパイプライン設計原則。Selection/Terminal分離、13ブロック構成 | high | — |
| database-schema.md | 本番DBスキーマ・信頼度・整合性ルール。29テーブル、SSOT=monthly_returns | high | DB, PARITY |
| environment-switching.md | ローカル/本番環境切替と検証手順。DATABASE_URL・認証変数・Render設定 | high | DB, API |
| fof-pipeline-troubleshooting.md | FoFパイプライン不具合の症状別トラブルシュート集 | high | — |
| portfolio-analysis-idea-loop.md | 分析→アイデア→検証のPF改善ループ。Sortino超え/Return最大化2トラック | high | API |
| portfolio-analysis-verification.md | PF構造確認・比較・検証の総合リファレンス。3視点独立評価 | high | API, PARITY, DB |
| structural-suspect-ban.md | GSにおける構造的SUSPECT自動Ban機能の設計 | high | — |
| Agent Skills.md | Agent Skills標準の概念・作成方法の入門 | medium | — |
| best-practices.md | Skills/CLAUDE.md/AGENTS.mdの役割分離と文書作法の標準化 | medium | — |
| passive-context-index-standard.md | AGENTS.md中心の受動コンテキスト設計標準 | medium | — |
| password-expiry-management.md | Tier課金連動のパスワード有効期限管理パターン | medium | — |
| tier-visibility-control.md | Tier別可視性制御(L1-L4)実装パターン | medium | — |
| knowledge-01〜06.md | 戦略背景知識(トレンド/MR/リセッション/FoF設計/補完戦略/予備) | low | — |
| document-naming-convention.md | docs配下の命名規則とステータス運用 | low | — |
| performance-audit.md | HARを使う定期パフォーマンス監査手順 | low | — |
| performance-measurement.md | 計測・レポート・改善反映の定量評価ワークフロー | low | — |
| skills-creation-guide.md | skills文書の新規作成/更新/削除手順 | low | — |

## docs/rule/ (25件)

| ファイル | 目的 | 優先度 | マーカー |
|---------|------|--------|---------|
| _INDEX.md | rule配下の全体地図と優先読了順 | high | — |
| trade-rule.md | signal/holding/rebalance/return計算の絶対ルール(RULE01-11)。**最重要SSOT** | high | — |
| calculation-theory.md | リターン計算理論の正規定義(Level0-3データソース階層) | high | — |
| business_rules.md | 業務ルール包括定義(データ/計算/UI/FoF/可視性) | high | — |
| check-rule.md | Truth-Based検証ルール標準化。Stock API=Truth(D)、bp閾値判定 | high | PARITY |
| database-info.md | DB構造・テーブル役割・データフロー明文化 | high | DB |
| DTB3-guide.md | DTB3リスクフリーリターン計算仕様。FRED年率→日次→21D月次変換 | high | — |
| gs-parity-verification-guide.md | GSエンジンと本番計算の一致検証手順。simulate_strategy_vectorized突合 | high | PARITY |
| api-usage-guide.md | Stock Data Platform API利用規約・制約・エンドポイント仕様 | high | API |
| rebalance-verification.md | rebalance_trigger準拠とsignal/holding整合の検証 | high | PARITY |
| requirements-spec.md | 機能要件・技術構成・データモデル・API要件の基準定義 | high | — |
| return-consistency-verification.md | RULE11(Return同一性)の検証と不一致調査手順 | high | PARITY |
| local-postgresql-guide.md | ローカルPostgreSQL環境の構築・クローン・運用手順 | medium | DB |
| local-verification-guide.md | 本番API依存を減らしたローカル検証フロー | medium | — |
| ninpou-fof-creation-runbook.md | 忍法FoF(L3)作成・登録・検証の標準手順 | medium | — |
| portfolio-naming-convention.md | PF命名規則統一(日次/月次プレフィックス、四神/L2忍法パターン) | medium | — |
| renderyaml_guide.md | Renderデプロイ時の接続設定ベストプラクティス | medium | — |
| rule.md | ドキュメント作成時の必須参照・テンプレート・禁止事項 | medium | — |
| security-status.md | セキュリティ実装現状(認証・可視性・レート制限) | medium | — |
| shijin-pf-creation-runbook.md | 四神PF作成のGS→抽出→変換→登録→再計算手順 | medium | — |
| timing-and-bottleneck-analysis.md | Layer別計測とボトルネック分析手順 | medium | — |
| design.md | デザインシステム(ダークテーマ)規定 | low | — |
| design-light.md | ライトモードのデザイン原則と配色仕様 | low | — |
| design-list.md | 現行デザイン実装の統一状況と基準値 | low | — |
| design-list-light.md | ライトモードの実装チェックリスト | low | — |

## 重要ルール抜粋（DB接続・パリティ検証・API使用法）

### DB接続ルール

| ルール | 詳細 | 参照 |
|--------|------|------|
| 書込先 | PostgreSQL(DATABASE_URL)のみ。dm_signal.db書込禁止 | — |
| 価格truth | experiments.db(daily_prices) | — |
| PF設定truth | dm_signal.db(portfolios) | — |
| ローカルDB | Docker+pg_dump/restore | `local-postgresql-guide.md` |
| 読取先 | DATABASE_URL直接。Render HTTP API経由禁止(L064) | — |

### パリティ検証ルール

| 検証手法 | 内容 | 参照 |
|----------|------|------|
| SSOT整合 | monthly_returns基準(annual=Π(1+monthly)-1) | `database-schema.md` |
| Truth判定 | Stock API=Truth(D)、A/C/D比較、bp閾値 | `check-rule.md` |
| GS-本番 | simulate_strategy_vectorized vs monthly_return_open突合 | `gs-parity-verification-guide.md` |
| rebalance別 | 月次/隔月/四半期/FoF別に検証観点+FAIL条件 | `rebalance-verification.md` |
| RULE11 | 株価計算値・DB値・UI表示の差分診断 | `return-consistency-verification.md` |
| 3視点独立 | return/downside/UD比で交差点候補判定 | `portfolio-analysis-verification.md` |

### API使用法ルール

| ルール | 詳細 | 参照 |
|--------|------|------|
| 本番API | `dm-signal-backend.onrender.com` + Basic認証 | `api-reference.md` |
| 認証 | 環境変数(ADMIN_USER/ADMIN_PASS)経由。ハードコード禁止 | — |
| Stock Data | rate limit、auto_fetch差分、ページング | `api-usage-guide.md` |
| 環境切替 | DATABASE_URL・Render設定 | `environment-switching.md` |
