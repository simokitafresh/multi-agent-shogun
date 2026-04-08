# cmd_314: Usage API実証結果

> 調査日: 2026-02-25 | 実施: saizo | parent: cmd_314 (偵察A)

## §1 API仕様実証

### Usage API (`GET /api/oauth/usage`)

| フィールド | 型 | 説明 |
|-----------|-----|------|
| `five_hour.utilization` | float | 5時間枠の使用率(%) |
| `five_hour.resets_at` | string (ISO8601) | 5時間枠のリセット時刻 |
| `seven_day.utilization` | float | 7日間枠の使用率(%) |
| `seven_day.resets_at` | string (ISO8601) | 7日間枠のリセット時刻 |
| `seven_day_oauth_apps` | null or object | OAuthアプリ専用枠（Max20xではnull） |
| `seven_day_opus` | null or object | Opus専用枠（Max20xではnull） |
| `seven_day_sonnet.utilization` | float | Sonnet専用7日間枠の使用率(%) |
| `seven_day_sonnet.resets_at` | string (ISO8601) | Sonnet専用枠のリセット時刻 |
| `seven_day_cowork` | null or object | Cowork枠（Max20xではnull） |
| `iguana_necktie` | null | 不明フィールド（常にnull） |
| `extra_usage.is_enabled` | bool | 追加課金の有効/無効 |
| `extra_usage.monthly_limit` | null or number | 月次追加上限 |
| `extra_usage.used_credits` | null or number | 使用済み追加クレジット |
| `extra_usage.utilization` | null or float | 追加枠の使用率(%) |

認証: `Authorization: Bearer {accessToken}` + `anthropic-beta: oauth-2025-04-20`

### Profile API (`GET /api/oauth/profile`)

| フィールド | 型 | 説明 |
|-----------|-----|------|
| `account.uuid` | string | アカウントUUID |
| `account.full_name` | string | 表示名 |
| `account.display_name` | string | 表示名 |
| `account.email` | string | メールアドレス |
| `account.has_claude_max` | bool | Maxプラン加入状態 |
| `account.has_claude_pro` | bool | Proプラン加入状態 |
| `account.created_at` | string (ISO8601) | アカウント作成日時 |
| `organization.uuid` | string | 組織UUID |
| `organization.name` | string | 組織名 |
| `organization.organization_type` | string | "claude_max" |
| `organization.billing_type` | string | "stripe_subscription" |
| `organization.rate_limit_tier` | string | "default_claude_max_20x" |
| `organization.has_extra_usage_enabled` | bool | 追加課金有効フラグ |
| `organization.subscription_status` | string | "active" |
| `organization.subscription_created_at` | string (ISO8601) | サブスク開始日時 |
| `application.uuid` | string | アプリUUID |
| `application.name` | string | "Claude Code" |
| `application.slug` | string | "claude-code" |

## §2 ポーリング耐性検証

5回×1分間隔のポーリング結果:

| # | 時刻 | HTTP | 応答時間 | 5h利用率 | 7d利用率 |
|---|------|------|---------|---------|---------|
| 1 | 12:31:15 | 200 | 5.41s | 39% | 54% |
| 2 | 12:32:20 | 200 | 5.31s | 39% | 54% |
| 3 | 12:33:26 | 200 | 5.42s | 39% | 54% |
| 4 | 12:34:31 | 200 | 5.30s | 39% | 54% |
| 5 | 12:35:37 | 200 | 5.29s | 40% | 54% |

**結論**:
- 全5回200 OK。レート制限なし
- 応答時間: 5.29-5.42秒（安定）— WSL2→Anthropic API間のレイテンシ
- Read-only確認: utilization値は外部操作がなければ変動なし（Poll 5の39→40%は将軍CLI側の自然消費）
- **1分間隔ポーリングは安全**。APIドキュメント上もレート制限記載なし

## §3 2アカウント同時監視スクリプト設計案

### 前提
- 入力: 2つのCLAUDE_CONFIG_DIR（各ディレクトリに`.credentials.json`）
- 出力: アカウント名, 5h%, 7d%, プラン を含む構造化データ

### 案A: tmuxステータスバー表示

```
┌─────────────────────────────────────────────────┐
│ [shogun:1] 将軍CLI                              │
│                                                 │
│ status-right: 🅰37%/54% 🅱12%/30%              │
└─────────────────────────────────────────────────┘
```

- 実装: bashスクリプト(cron 5分間隔) → tmux set-option status-right
- 長所: 常時視界内。追加ペイン不要
- 短所: 表示幅制限。詳細表示困難

### 案B: ntfy通知

```
bash scripts/ntfy.sh "【Usage】A:5h=37%,7d=54% / B:5h=12%,7d=30%"
```

- 実装: bashスクリプト(cron 5-15分間隔) → ntfy.sh
- 長所: スマホで確認可能。離席中も監視継続
- 短所: プッシュ過多リスク。閾値ベースが望ましい

### 案C: 専用ペイン（watchコマンド）

```
┌──────────────────────────────────────┐
│ Account A (Max20x)                   │
│   5h: ██████████░░░░ 37%  reset 06:00│
│   7d: ████████████░░ 54%  reset 03/02│
│ Account B (Max20x)                   │
│   5h: ███░░░░░░░░░░░ 12%  reset 08:00│
│   7d: ██████░░░░░░░░ 30%  reset 03/01│
│                                      │
│ Last update: 12:35 (5min interval)   │
└──────────────────────────────────────┘
```

- 実装: bashスクリプト + `watch -n 300` in tmux pane
- 長所: 最も情報量が多い。バー表示で直感的。リセット時刻も表示可能
- 短所: ペイン1枠消費

### 推奨: 案A + 案Bハイブリッド

**理由**:
1. 案Aで常時ステータスバーに最小限表示（5h%/7d%の数値のみ）
2. 案Bで閾値超過時のみntfy通知（例: 5h>80% or 7d>90%）
3. 案Cは情報過多。殿の運用は将軍ウィンドウが主戦場なのでペイン消費は避けたい
4. ステータスバー+閾値通知の組み合わせが最小コストで最大効果

**実装概要** (ハイブリッド案):
```bash
#!/bin/bash
# usage_monitor.sh — cron 5分間隔
CONFIGS=("$HOME/.claude" "/path/to/account_b/.claude")
LABELS=("A" "B")
OUTPUT=""
for i in 0 1; do
  TOKEN=$(python3 -c "import json; print(json.load(open('${CONFIGS[$i]}/.credentials.json'))['claudeAiOauth']['accessToken'])")
  RESP=$(curl -s -H "Authorization: Bearer $TOKEN" -H "anthropic-beta: oauth-2025-04-20" "https://api.anthropic.com/api/oauth/usage")
  FIVE=$(echo "$RESP" | python3 -c "import sys,json; print(int(json.load(sys.stdin)['five_hour']['utilization']))")
  SEVEN=$(echo "$RESP" | python3 -c "import sys,json; print(int(json.load(sys.stdin)['seven_day']['utilization']))")
  OUTPUT+="${LABELS[$i]}:${FIVE}/${SEVEN} "
  # 閾値通知
  if [ "$FIVE" -gt 80 ] || [ "$SEVEN" -gt 90 ]; then
    bash scripts/ntfy.sh "【Usage警告】${LABELS[$i]} 5h=${FIVE}% 7d=${SEVEN}%"
  fi
done
tmux set-option -g status-right "$OUTPUT"
```

### 追加考慮事項
- トークンリフレッシュ: accessTokenは有効期限あり(expiresAt)。期限切れ時はClaude CodeがCLI起動時に自動更新するが、監視スクリプトは自前でrefreshTokenを使う必要がある可能性あり → 要調査
- CLAUDE_CONFIG_DIR分離: 2アカウント目のcredentials.jsonパスは環境変数or引数で指定
