# DM-Signal 横断リファレンスマップ (cmd_487)

> 統合: hanzo (subtask_487_recon_b)
> 入力: kagemaru AC1+AC2 (`cmd_487_api-frontend-crossmap.md`) + hanzo AC3 (Docs参照整合)
> ソース: `cmd_477_dm-signal-knowledge-audit.md`, `cmd_478_dm-signal-backend-catalog.md`, `cmd_479_dm-signal-frontend-catalog.md`
> 作成日: 2026-03-02

---

## §1 API↔Frontend 横断マップ (kagemaru AC1)

### 集計

| カテゴリ | エンドポイント数 |
|---------|--------------|
| FE接続済み | 51 |
| FE未使用(Backend Only) | 19カテゴリ(debug含むと35+) |
| **Backend全体** | **84-88** |

### API影響度ランキング (変更時の影響ページ数)

| Rank | Endpoint | 影響ページ数 | 説明 |
|------|----------|------------|------|
| 1 | `GET /api/signals` | 12+ | SignalsContext経由で全Viewerページ |
| 2 | `GET /api/portfolios/get` | 4 | AdminAuthContext経由で全Adminページ |
| 3 | `GET /api/performance/{id}` | 3 | Signal, Dashboard, Compare |
| 4 | `GET /api/benchmark/{ticker}` | 3 | Signal, Dashboard, Compare |
| 5 | `GET /api/history/{id}` | 2 | Signal, Dashboard |

→ 詳細テーブル: `docs/research/cmd_487_api-frontend-crossmap.md` §AC1

### FE未使用エンドポイント (主要)

| ID | Endpoint | 理由 |
|----|----------|------|
| U1 | `POST /api/portfolios/save-legacy` | 新save APIに移行済み |
| U2 | `POST /admin/run-etl` | api-client.tsに定義あるがFEページ未呼出 |
| U3-U19 | debug系/管理系17個 | FE未接続 or 代替API移行 |

---

## §2 Frontendページ → Backend依存 逆引き (kagemaru AC2)

### ページ構成

| 区分 | ページ数 | API呼出パターン |
|------|---------|---------------|
| Viewer/Public | 15 | SignalsContext(共通) + 個別API |
| Admin | 4 | AdminAuthContext(共通) + CRUD API群 |
| **合計** | **19** | |

### 共通Context注入

| Context | API Call | 影響範囲 |
|---------|----------|---------|
| SignalsProvider | `GET /api/signals` | 全Viewerページ(TTL 1h) |
| ViewerPermissionsProvider | `GET /api/viewer-permissions` | 権限チェック付きページ |
| AdminAuthProvider | `GET /api/portfolios/get` + login | 全Adminページ |

→ 詳細テーブル: `docs/research/cmd_487_api-frontend-crossmap.md` §AC2

---

## §3 Docs参照整合チェック (hanzo AC3)

### 検証サマリー

| 区分 | 件数 | 説明 |
|------|-----|------|
| 検証対象パス | 110 | cmd_477 docs catalog Dependencies列の全ユニークパス |
| 実在確認 | 65 | パス通り存在 |
| 移動済み(cross-dir) | 20 | docs/rule↔docs/skills間の相互参照誤り等 |
| アーカイブ済み | 3 | docs/archives/配下に移動済み |
| 完全消失 | 21 | gitにもファイルシステムにも痕跡なし |
| プレースホルダ | 1 | xxx.md (テンプレート例示) |

### 移動済みパス参照 (20件)

参照されたパスは存在するが、異なるディレクトリに配置されている。ドキュメント内リンクの更新が必要。

| 参照パス | 実際のパス | パターン |
|---------|-----------|---------|
| `docs/rule/api-reference.md` | `docs/skills/api-reference.md` | rule→skills移動 |
| `docs/rule/best-practices.md` | `docs/skills/best-practices.md` | rule→skills移動 |
| `docs/rule/building-block-addition-guide.md` | `docs/skills/building-block-addition-guide.md` | rule→skills移動 |
| `docs/rule/building-block-pattern.md` | `docs/skills/building-block-pattern.md` | rule→skills移動 |
| `docs/rule/database-schema.md` | `docs/skills/database-schema.md` | rule→skills移動 |
| `docs/rule/environment-switching.md` | `docs/skills/environment-switching.md` | rule→skills移動 |
| `docs/rule/fof-pipeline-troubleshooting.md` | `docs/skills/fof-pipeline-troubleshooting.md` | rule→skills移動 |
| `docs/rule/password-expiry-management.md` | `docs/skills/password-expiry-management.md` | rule→skills移動 |
| `docs/rule/tier-visibility-control.md` | `docs/skills/tier-visibility-control.md` | rule→skills移動 |
| `docs/skills/api-usage-guide.md` | `docs/rule/api-usage-guide.md` | skills→rule移動 |
| `docs/skills/business_rules.md` | `docs/rule/business_rules.md` | skills→rule移動 |
| `docs/skills/calculation-theory.md` | `docs/rule/calculation-theory.md` | skills→rule移動 |
| `docs/skills/check-rule.md` | `docs/rule/check-rule.md` | skills→rule移動 |
| `docs/skills/requirements-spec.md` | `docs/rule/requirements-spec.md` | skills→rule移動 |
| `docs/business_rules.md` | `docs/rule/business_rules.md` | 旧パス |
| `docs/design.md` | `docs/rule/design.md` | 旧パス |
| `scripts/verify_rebalance.py` | `backend/scripts/verify_rebalance.py` | scripts→backend/scripts移動 |
| `scripts/verify_rebalance_comprehensive.py` | `backend/scripts/verify_rebalance_comprehensive.py` | 同上 |
| `scripts/verify_truth.py` | `backend/scripts/verify_truth.py` | 同上 |
| `Visibility-Settings.md` | `docs/spec/Visibility-Settings.md` | ベア名→spec配下 |

### アーカイブ済みパス (3件)

| 参照パス | アーカイブ先 |
|---------|------------|
| `073-layer-separation-architecture.md` | `docs/archives/future/073-layer-separation-architecture.md` |
| `docs/11th-step.md` | `docs/archives/steps/11th-step.md` |
| `password.md` | `docs/archives/misc/password.md` |

### 完全消失パス (21件) — 陳腐化ドキュメントの根拠

| 消失パス | 参照元ドキュメント | 備考 |
|---------|-----------------|------|
| `backend/scripts/compare_precomputed.py` | `docs/architecture/Performance.md` | 旧パフォーマンス比較スクリプト |
| `backend/scripts/test_trade_perf.py` | `docs/architecture/Performance.md` | 旧テストスクリプト |
| `docs/implementation-task-list.md` | `docs/rule/api-usage-guide.md` | 旧タスクリスト |
| `docs/rule/kalman-design.md` | (docs/skills内相互参照) | Kalman設計書(未作成 or 削除) |
| `docs/skills/kalman-design.md` | `docs/skills/portfolio-analysis-*.md` | 同上 |
| `scripts/analysis/check_fof_structure.py` | `docs/rule/local-verification-guide.md` | 大掃除で削除 |
| `scripts/analysis/check_local_db.py` | `docs/rule/local-verification-guide.md` | 大掃除で削除 |
| `scripts/analysis/create_dc_shijin.py` | `docs/rule/ninpou-fof-creation-runbook.md`, `docs/rule/shijin-pf-creation-runbook.md` | 大掃除で削除 |
| `scripts/analysis/create_prod_shijin.py` | `docs/rule/shijin-pf-creation-runbook.md` | 大掃除で削除 |
| `scripts/analysis/grid_search/_extract_cagr_top.py` | `docs/rule/shijin-pf-creation-runbook.md` | 大掃除で削除 |
| `scripts/analysis/grid_search/_extract_calmar_top.py` | `docs/rule/shijin-pf-creation-runbook.md` | 大掃除で削除 |
| `scripts/analysis/grid_search/family_grid_search.py` | `docs/rule/shijin-pf-creation-runbook.md` | 大掃除で削除 |
| `scripts/analysis/new_feature_test.py` | `docs/rule/local-verification-guide.md` | 大掃除で削除 |
| `scripts/analysis/rename_prod_create_cagr_shijin.py` | `docs/rule/shijin-pf-creation-runbook.md` | 大掃除で削除 |
| `scripts/analysis/verify_v0_v2_consistency.py` | `docs/rule/local-verification-guide.md` | 大掃除で削除 |
| `scripts/check_return_consistency.py` | `docs/rule/return-consistency-verification.md` | 大掃除で削除 |
| `scripts/check_return_detail.py` | `docs/rule/return-consistency-verification.md` | 大掃除で削除 |
| `scripts/check_trades_vs_monthly.py` | `docs/rule/return-consistency-verification.md` | 大掃除で削除 |
| `scripts/setup_local_db.py` | `docs/rule/local-postgresql-guide.md` | 大掃除で削除 |
| `scripts/verify_025_endbalance.py` | `docs/rule/check-rule.md` | 大掃除で削除 |
| `scripts/verify_return_vs_price.py` | `docs/rule/return-consistency-verification.md` | 大掃除で削除 |

### 陳腐化ドキュメント一覧 (dead ref保有)

| # | ドキュメント | dead ref数 | 消失原因 | 重症度 |
|---|-----------|-----------|---------|-------|
| 1 | `docs/rule/shijin-pf-creation-runbook.md` | 6 | scripts大掃除 | HIGH — 手順の大半が実行不能 |
| 2 | `docs/rule/return-consistency-verification.md` | 4 | scripts大掃除 | HIGH — 検証手順全滅 |
| 3 | `docs/rule/local-verification-guide.md` | 4 | scripts大掃除 | HIGH — 検証手順全滅 |
| 4 | `docs/architecture/Performance.md` | 2 | スクリプト削除 | MEDIUM — 参照スクリプト消失 |
| 5 | `docs/rule/ninpou-fof-creation-runbook.md` | 1 | scripts大掃除 | MEDIUM — 一部手順が実行不能 |
| 6 | `docs/rule/local-postgresql-guide.md` | 1 | scripts大掃除 | MEDIUM — setup手順が実行不能 |
| 7 | `docs/rule/check-rule.md` | 1 | scripts大掃除 | LOW — 検証スクリプト1件消失 |
| 8 | `docs/rule/api-usage-guide.md` | 1 | 旧ドキュメント削除 | LOW — 参照リンク1件死亡 |
| 9 | `docs/skills/portfolio-analysis-idea-loop.md` | 1 | kalman-design未作成 | LOW — オプショナル参照 |
| 10 | `docs/skills/portfolio-analysis-verification.md` | 1 | kalman-design未作成 | LOW — オプショナル参照 |

---

## §4 横断分析: 知識基盤の健全性

### docs/rule + docs/skills + docs/architecture 総合

| 指標 | 値 |
|------|---|
| 全ドキュメント数 | 59 (rule:26 + skills:25 + architecture:8) |
| 全行数 | 27,096 |
| 鮮度(3ヶ月以内) | 100% (59/59 fresh) |
| 参照整合率 | 59.1% (65/110 正常パス) |
| 陳腐化ドキュメント数 | 10/59 (16.9%) |
| dead ref合計 | 21件(完全消失) + 20件(移動済み未更新) + 3件(アーカイブ済み) |

### 根本原因

1. **scripts大掃除**: `scripts/analysis/` と `scripts/` 直下のスクリプト群が一括削除されたが、参照元のdocs/rule/*.mdが未更新
2. **docs/rule↔docs/skills再編**: ファイル移動時に相互参照リンクが未更新(20件)
3. **Kalman関連**: `kalman-design.md` が計画されたが未作成のまま2ファイルから参照

### 推奨アクション

| 優先度 | アクション | 対象 |
|--------|----------|------|
| P1 | dead ref 6件のrunbook更新 or 廃止マーク | `shijin-pf-creation-runbook.md` |
| P1 | dead ref 4件の検証手順更新 or 廃止マーク | `return-consistency-verification.md`, `local-verification-guide.md` |
| P2 | cross-dir参照20件のリンク修正 | docs/rule↔docs/skills相互参照 |
| P2 | archive参照3件のリンク更新 | 各参照元ドキュメント |
| P3 | kalman-design.md作成 or 参照除去 | `portfolio-analysis-*.md` |
| P3 | knowledge-06.md空ファイル対処 | 内容記載 or 削除 |

---

## §5 参照先

| 成果物 | パス | 担当 |
|--------|-----|------|
| API↔FE横断マップ(詳細) | `docs/research/cmd_487_api-frontend-crossmap.md` | kagemaru |
| Docs知識監査(入力) | `docs/research/cmd_477_dm-signal-knowledge-audit.md` | sasuke+kirimaru |
| Backendカタログ(入力) | `docs/research/cmd_478_dm-signal-backend-catalog.md` | hayate+kagemaru |
| Frontendカタログ(入力) | `docs/research/cmd_479_dm-signal-frontend-catalog.md` | hanzo+saizo |
