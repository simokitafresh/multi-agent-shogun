# 経費証票入手経路 完全監査マトリクス
<!-- cmd: cmd_916 | author: cmd_916_A(saizo)+cmd_916_B(kotaro) | date: 2026-03-13 -->

## §1 分類凡例

| ラベル | 意味 | 対応方針 |
|--------|------|----------|
| a | メール/手動対応のみ | Gmail経由(tax_receipt_collector.py)または手動 |
| b | ポータルDL主体 | CDP自動化候補 |
| c | ポータルDL + メール両方 | Gmail経由 or CDP、最適経路を選択 |
| e | 既に自動化済み | receipt_manager.py + note_pipeline.py稼働中 |

## §2 完全マトリクス（19パターン）

### a — メール/手動対応（3件）

| # | 判定キー | 発行元 | Sheet経路 | 証票入手方法 | 備考 |
|---|----------|--------|-----------|-------------|------|
| 1 | SUNABACO | SUNABACO | Gmail | 自動返信メール。公式billing/receiptドキュメントなし | 低信頼。個別問い合わせ必要な場合あり |
| 2 | SRL*ANALYTICS | Portfolio Visualizer | Gmail | 公式billing docs確認不可。メール/手動対応 | 低信頼 |
| 3 | キャンプファイヤー | CAMPFIRE | Gmail | CAMPFIRE原則領収書不発行。完了メール or 起案者発行電子領収書 | システム利用料のみMyPage/問い合わせ |

### e — 既に自動化済み（2件）

| # | 判定キー | 発行元 | 自動化状態 | 備考 |
|---|----------|--------|-----------|------|
| 4 | note PF手数料 | note株式会社 | 手動DL → receipt_manager.pyで自動リネーム/アップロード | PD-003: スクレイピング禁止のためCDP自動取得見送り |
| 5 | note 振込手数料 | note株式会社 | 同上 | 同上 |

### b — ポータルDL主体（7件）

| # | 判定キー | 発行元 | DLページURL/導線 | 一括DL | 認証方式 | CDP難易度 | 判定理由 |
|---|----------|--------|-----------------|--------|----------|-----------|----------|
| 6 | ノート | note株式会社 | `note.com` > 設定 > 購入・チップ履歴 > `...` > 領収書 > 印刷/PDF保存 | 不可（1件ずつ） | Email+Password | **高** | 利用規約でスクレイピング禁止(L010)。CDP自動化は規約違反リスク。Gmail経由が安全 |
| 7 | RENDER | Render | `dashboard.render.com/billing` > Invoice history > PDF DL | 不可（1件ずつ） | Google SSO / Email+Password。2FA強制可能 | **中** | 2FA設定次第。Google SSOならOAuth redirect必要。PDFは直接DL可 |
| 8 | X CORP | X Corp. (Premium) | `x.com/settings/subscription/manage` > Change Payment Method > **Stripe画面**で領収書 | 不可 | Email+Password / Google / Apple。2FA利用可 | **高** | Stripe外部リダイレクト。X社のanti-automation対策。DOM変更頻度高 |
| 9 | TWITTER ADS | X Corp. (広告) | `ads.x.com` > Billing > Billing history tab > invoice DL | 不可（期間別） | X account同一認証 | **高** | X社anti-automation。広告アカウント別認証。invoice修正不可(過去分) |
| 10 | COGNITION LABS | Cognition Labs (Devin) | Settings > Plans / Usage & Limits > billing cycle end時に請求 | 不明 | OAuth2 (Cognition account)。Enterprise: Okta SSO | **中** | OAuth2フロー。比較的新プラットフォームでDOM安定性未知 |
| 11 | DYNALISTINC | Dynalist | `dynalist.io` > account > invoices page > view/print | 可（一覧表示） | Email+Password / Google login | **低** | シンプルなログイン+invoiceページ。DOM構造安定 |
| 12 | いいオフィス | いいオフィス | **いいアプリ(モバイルアプリ)** MyPage > 支払い履歴 > メール送信 | 不可 | アプリ内認証(Email+Password) | **高** | モバイルアプリ専用UI。WebポータルでのDL導線不明。CDP対象外 |

### c — ポータルDL + メール両方（7件）

| # | 判定キー | 発行元 | DLページURL/導線 | 一括DL | 認証方式 | CDP難易度 | 判定理由 |
|---|----------|--------|-----------------|--------|----------|-----------|----------|
| 13 | ANTHROPIC | Anthropic PBC | `console.anthropic.com/settings/billing` > Invoice history > Download | 不可（1件ずつ） | Google / Apple / Magic link（パスワードなし）。2FA非標準 | **中** | OAuth redirect必要。Magic linkはメール認証のためCDP単体では完結しない。billing emailへ自動送信あり→**Gmail経由推奨** |
| 14 | GITHUB | GitHub, Inc. | Settings > Billing & Licensing > Payment history > Receipt/Invoice DL | 不可（1件ずつ） | Email+Password + **2FA(TOTP/WebAuthn)ほぼ必須** | **高** | 2FAがほぼ必須。WebAuthn対応だとCDPでは困難。**Gmail経由推奨** |
| 15 | SEEKINGALPH | Seeking Alpha | Account Settings > Subscriptions > Invoices > Email Invoice | 不可（Email送信型） | Email+Password | **低** | 標準ログイン。Invoicesタブから直接Email送信可。CDPでもGmailでも容易 |
| 16 | BUFFER | Buffer, Inc. | Dashboard > avatar > Billing > Invoices & Receipts > Download invoice/receipt | 不可（1件ずつ） | Email+Password / Social login | **低** | 標準ログイン。シンプルなUI。自動メールにもinvoiceリンク付き。CDPでもGmailでも容易 |
| 17 | PYTHONANYWHERE | PythonAnywhere | `pythonanywhere.com/account` > invoices list | 可（一覧表示） | Email+Password | **低** | シンプルなログイン+account page。DOM安定。billing emailもあり |
| 18 | SUPABASE | Supabase, Inc. | `supabase.com/dashboard/org/_/billing` > Invoices > receipt DL | 不可（1件ずつ） | GitHub OAuth / Email+Password。2FA利用可 | **中** | GitHub OAuth依存の場合2FA連鎖。Email+Password直接なら中程度。invoiceはemail送付あり→**Gmail経由推奨** |
| 19 | TRADINGVIEW | TradingView, Inc. | Profile Settings > Billing history > Get invoice icon | 不可（1件ずつ。1注文複数商品=アイコン1つ） | Email+Password / Google / Apple / Social | **低** | 標準ログイン。直接invoice DL。billing emailもあり |

## §3 自動化優先度（件数×頻度×難易度）

### 推奨: Gmail経由優先（tax_receipt_collector.py拡充）

既存の`tax_receipt_collector.py`がGmail検索→PDF保存パイプラインを持つ。
以下のサービスはGmail経由が最適経路（CDP不要）:

| 優先度 | サービス | 分類 | 理由 | 既存SERVICES定義 |
|--------|----------|------|------|-----------------|
| **S** | Anthropic | c | Magic link認証でCDP困難。billing email自動送信あり | あり |
| **S** | GitHub | c | 2FA必須でCDP困難。receipt emailあり | あり |
| **S** | Supabase | c | GitHub OAuth連鎖でCDP困難。invoice email送付あり | あり |
| **A** | Buffer | c | 自動emailにinvoiceリンク付き。CDPも容易だがGmail十分 | あり |
| **A** | TradingView | c | billing emailあり。CDPも容易だがGmail十分 | あり |
| **A** | Seeking Alpha | c | Email Invoice送信機能あり | なし(要追加) |
| **A** | Render | b | invoiceメール通知あり（公式docs確認） | あり |
| **B** | PythonAnywhere | c | billing emailあり。Gmail収集可能 | あり |
| **B** | X Premium | b | 領収書メールがある場合Gmail経由。なければStripe経由要確認 | あり(X_Twitter) |
| **B** | Twitter Ads | b | billing通知メールがある場合Gmail経由 | あり(X_Ads) |
| **B** | Cognition Labs | b | 請求メールがある場合Gmail経由 | あり |

### CDP候補（Gmail非対応 or ポータル限定）

| 優先度 | サービス | 分類 | CDP難易度 | 備考 |
|--------|----------|------|-----------|------|
| **C** | Dynalist | b | 低 | invoiceページが一覧表示でCDP容易。ただし少額・低頻度 |
| **D** | いいオフィス | b | 高 | モバイルアプリ専用。CDPでは対応不可。手動 or アプリ内メール送信 |
| 対象外 | note(購入) | b | 高 | 利用規約スクレイピング禁止(L010) |

### 対応不要（a分類 — Gmail or 手動）

| サービス | 対応方針 |
|----------|----------|
| SUNABACO | 自動返信メール → tax_receipt_collector.py(定義済み) |
| SRL*ANALYTICS | メール or 手動。tax_receipt_collector.py(定義済み) |
| CAMPFIRE | 完了メール → Gmail収集。or 手動 |

## §4 年度パイプラインスコープ推奨

### Phase 1: Gmail経由強化（低コスト・高カバレッジ）

**スコープ**: tax_receipt_collector.pyのSERVICES定義に不足サービスを追加

| 追加候補 | query_from | query_extra |
|----------|------------|-------------|
| Seeking Alpha | `seekingalpha.com` | `(invoice OR receipt OR subscription)` |
| CAMPFIRE | `campfire.jp, camp-fire.jp` | `(支援 OR 支払い OR 完了)` |
| Dynalist | `dynalist.io` | `(invoice OR receipt OR Pro)` |
| いいオフィス | `e-office.space, iioffice.net` | `(領収 OR 支払い OR 利用)` |

既存定義済み(10件): X_Twitter, X_Ads, GitHub, PythonAnywhere, Render, Buffer, TradingView, Anthropic, Cognition_AI, Supabase

**合計カバレッジ**: 19件中16件がGmail経由で収集可能（a+c+bのメール通知あり分）

### Phase 2: CDP拡張（オプション・低優先度）

- Dynalist invoice一括取得（CDP難易度: 低、ただし少額・低頻度で ROI低）
- Render invoice PDF直接DL（2FA未設定前提。Gmail代替あり）

### Phase 3: 手動残存（3件）

| サービス | 理由 | 作業量 |
|----------|------|--------|
| note(購入) | 利用規約禁止 | 月数件。手動DL→receipt_manager.py |
| note PF手数料/振込手数料 | 同上。既にe分類 | 既存フロー継続 |
| いいオフィス | モバイルアプリ専用 | アプリ内メール送信→Gmail収集を試行 |

## §5 実装直結情報

### 変更対象ファイル

| ファイル | 変更内容 |
|----------|----------|
| `auto-ops/tax_receipt_collector.py` L60-96 SERVICES | Seeking Alpha, CAMPFIRE, Dynalist, いいオフィスの4定義追加 |
| `auto-ops/workflows/receipt_manager.py` L37-42 SUBFOLDER_MAP | 新サービス用のsubfolder mapping追加 |

### 新規ファイル候補

- なし（Phase 1はtax_receipt_collector.py拡充のみで完結）

### 既存コードとの共通化

| 既存コード | 共通化可能箇所 |
|-----------|---------------|
| `tax_receipt_collector.py` run_gws() | gws Gmail検索の共通ヘルパー。既に再利用パターン確立済み |
| `workflows/receipt_manager.py` | リネーム+Drive upload。全サービス共通で利用可能 |
| `cdp/cdp_helper.py` | CDP transport。Phase 2のCDP拡張時に利用 |
| `workflows/note_pipeline.py` | CDPログイン+PDF取得パターン。新CDP pipeline作成時のテンプレート |
| `workflows/mf_csv_pipeline.py` | CDP+認証フロー。TOTP対応パターンの参考 |

### エッジケース・副作用

| リスク | 影響 | 対策 |
|--------|------|------|
| Gmail検索のfalse positive | 無関係メールを証票として収集 | query_extraを具体的に。L019: 複数候補はfail-close |
| サービス側のメールフォーマット変更 | 金額抽出失敗 | AMOUNT_RE(L39-45)の正規表現更新 |
| Gmail API rate limit | 大量検索時の429エラー | run_gws()に既にretry+exponential backoff実装済み |
| Stripe領収書(X Premium等) | Stripe側のDOM変更でURL変化 | Gmail経由で回避。Stripe直接DLはPhase 2以降 |
| 認証失敗時の挙動 | CDPセッション残存 | preflight_cdp_flow()でクリーンアップ済み。Gmail経由なら不問 |
| レート制限 | gws連続実行時のGoogle API quota | GWS_TIMEOUT=30s + retry。バッチ間にsleep推奨 |
