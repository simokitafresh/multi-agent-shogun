# Saxo Trade Engine — システムトレード基盤設計
<!-- created: 2026-05-24 -->
<!-- last_updated: 2026-07-12 cmd_training_L4_r1_hanzo -->
<!-- status: 設計段階 -->

## §1 目的

DM-Signal専用ではなく**汎用システムトレード基盤**。任意のシグナルソースからSaxo口座で完全自動売買。殿の承認不要（チャンスを逃すため）。結果はntfy通知で殿に可視化。

## §2 殿の口座情報

- Saxo Bank口座: **あり**（既存顧客）
- リージョン: **未確認**（API基盤URLが異なる。要確認）
- LIVE環境アクセス: 直接顧客のため申請可能

## §3 Saxo OpenAPI 概要

SaxoTraderGOと同一API基盤。REST API。OAuth2認証。

| 操作 | エンドポイント | HTTPメソッド |
|------|--------------|-------------|
| ポジション取得 | `/port/v1/netpositions/me` | GET |
| 口座残高 | `/port/v1/balances/me` | GET |
| 注文送信 | `/trade/v2/orders` | POST |
| 注文変更 | `/trade/v2/orders` | PATCH |
| 注文取消 | `/trade/v2/orders/{OrderId}` | DELETE |
| 注文状況 | `/port/v1/orders/me` | GET |
| 商品検索 | `/ref/v1/instruments/details` | GET |
| ヒストリカル | `/chart/v1/charts` | GET |
| リアルタイム価格 | Streaming API (WebSocket) | Subscribe |

APIベースURL（リージョン依存）:
- SIM: `https://gateway.saxobank.com/sim/openapi/`
- LIVE: `https://gateway.saxobank.com/openapi/` （デンマーク）
- 他リージョン: 要確認

## §4 アーキテクチャ

```
任意のシグナルソース
  │ DM-Signal holding_signal / 別システム / CSV
  ▼
Trade Execution Engine (Python)
  ├─ シグナル受信 (API or ファイル)
  ├─ 現在ポジション取得 (Saxo GET)
  ├─ 差分計算 → 売買リスト生成
  ├─ 注文送信 (Saxo POST)
  ├─ 約定確認 + パリティ検証
  ├─ ログ全記録 (PostgreSQL)
  └─ ntfy結果通知
```

実行入力は `signal` ではなく、リバランス月外の維持を含む `holding_signal` を使う（定義は [[dm-signal-core]]）。SIM→LIVE移行では、全期間の `holding_signal` と売買重量を同一入力で突合し、既存のパリティ基準に従う（[[dm-signal-ops]]）。

## §5 認証

OAuth2フロー。LIVE環境はrefresh_tokenで長期維持可能。
- `.env`にrefresh_token保持
- トークン自動更新ロジック（DM-Signal Render認証と同構造）
- 24hトークンはSIM専用

## §6 安全装置

| 安全装置 | 内容 |
|---------|------|
| SIM全フロー検証 | LIVE投入前にSIM環境で全パス検証 |
| API異常停止 | HTTP 4xx/5xx → 注文停止 + ntfy通知 |
| 全取引ログDB | 全APIリクエスト/レスポンスをDB記録 |
| ntfy結果通知 | 実行結果を毎回通知（殿は見たい時だけ見る） |
| 差分上限（検討中） | 1回のリバランスで総資産X%超 → 停止+通知 |

## §7 次のステップ

1. 殿のSaxo口座リージョン確認 → APIベースURL確定
2. Developer Portal登録 → SIMアカウント+OAuth2 App作成
3. SIM環境でポジション取得テスト（Python requests）
4. DM-Signal holding_signal → 差分計算 → 注文送信の一気通貫実装
5. SIM検証完了 → LIVE ReadOnly → LIVE本番

## §8 参照

- 全ページ統合ドキュメント旧参照名: docs / research / saxo_openapi_excel_user_guide.md は2026-06-06時点でgit管理ファイルにもワークツリーにも存在しない。`docs/semantic-index/index.md` には同等の旧参照が残っているため、Saxo原典再配置またはsemantic index修正が別途必要。
- セマンティクスインデックス: `saxo_openapi_excel`
- Excel関数一覧: OpenAPIGet/Post/Put/Patch/Delete/Subscribe + ユーティリティ8種
- サポート: openapisupport@saxobank.com

## §9 設計原則（殿裁定 2026-05-24）

- **完全自動**: 殿の承認ゼロ。チャンスを逃す承認フローは排除
- **汎用基盤**: DM-Signal専用にしない。別システム・別戦略にも対応
- **拡張可能**: DM-Signal拡張や新システム作成の土台

## §10 鮮度確認（cmd_3095）

- 2026-05-29確認: 直近の非auto commitは `600b2edc`（2026-05-26, causal links追加）。本文内容は同commitの追加内容と一致し、追加更新は鮮度メタデータのみ。
- 2026-06-06確認: git log --since=2026-05-30 -- docs / research / saxo_openapi_excel_user_guide.md context/saxo-trade-engine.md は該当なし。Saxo本文の新規source commitはないが、参照先ドキュメント不在を§8へ明記した。
- 2026-06-20確認（GA-100）: `git log --since=2026-06-06 -- context/saxo-trade-engine.md` は2026-06-06のGA-007更新のみ。`gate_context_freshness`の直接原因はlast_updated=2026-06-06後のinfra root fallback source commit検知で、Saxo固有本文の新規根拠commitではない。外部Saxo API仕様は未調査のため本文仕様は維持し、鮮度メタデータのみ更新。
- GA-099/L825接続: GA-099と同じく「context更新がcmd完了時に強制されず、後段gateで発見される」カテゴリ。saxo固有ではなくinfra context全般の横展開問題。防御層案は、context_freshness hotfix配備時にtarget contextの`last_updated`更新または維持判断行の追加を報告gateで必須化すること。

## 因果リンク

- → [[dmsignal_operations]] DM-Signal holding_signalがシグナルソースの第一候補
- → [[investment_knowledge_base]] 投資知識辞書(トレード手法・リスク管理)
- → [[production_parity]] SIM→LIVE移行時のパリティ検証
- → [[infrastructure]] ntfy通知・認証(.env refresh_token)はinfra共有基盤
