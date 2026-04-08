# cmd_316: Claude Code Max Plan レートリミットカウント方式分析

> 調査日: 2026-02-25 | 調査者: hanzo | タスク: subtask_316_recon_a

## §1 結論

**レートリミットは「APIコスト等価（ドル換算）」でカウントされている（確信度: 高）**

Anthropicは公式にカウント単位を明示していないが、以下の複数の独立した証拠から「各APIコールのトークン消費をAPI標準料金でドル換算し、プランごとの予算枠に対する消費率をutilization%として返している」と強く推定できる。

## §2 証拠

### 証拠1: Opus/Sonnet消費比 = API価格比（決定的）

| モデル | Input/MTok | Output/MTok | 消費比 |
|--------|-----------|-------------|--------|
| Sonnet 4.6 | $3 | $15 | 1x（基準） |
| Opus 4.6 | $15 | $75 | 5x |

ClaudeLogの記載: "Opus consumes ~5x more allocation than Sonnet"
→ **API価格比と完全一致**。トークン数ベースなら同一トークン数で同一消費のはず。コスト換算でなければこの5x比は説明できない。

### 証拠2: Extra Usageの課金単位

公式ヘルプセンター記載:
- "Extra usage is billed at standard API rates"
- "Once the request is processed, we calculate your token consumption"
- `extra_usage` APIフィールドに `used_credits`（ドル単位）が存在

→ レートリミットの内部計算がAPI料金ベースであることと整合。

### 証拠3: プランティア倍率

| プラン | 月額 | Proの何倍 | 料金倍率 |
|--------|------|-----------|----------|
| Pro | $20 | 1x | 基準 |
| Max 5x | $100 | 5x | 5x |
| Max 20x | $200 | 20x | 10x(※) |

※Max 20xは月額10xだが使用量は20x。これはAnthropicが量的割引を適用している可能性がある。

### 証拠4: Usage APIレスポンス構造

```json
{
  "five_hour": {
    "utilization": 78.0,
    "resets_at": "2025-11-13T04:00:00+00:00"
  },
  "seven_day": { "utilization": ..., "resets_at": ... },
  "seven_day_sonnet": { "utilization": ..., "resets_at": ... },
  "extra_usage": {
    "is_enabled": true/false,
    "monthly_limit": ...,
    "used_credits": ...,
    "utilization": ...
  }
}
```

- `utilization`は**パーセンテージ**で返される → 何らかの予算枠に対する比率
- `seven_day_sonnet`が別枠で存在 → Sonnet専用の週間予算枠がある
- `extra_usage.used_credits` → クレジット（ドル）単位の消費量
- `extra_usage.monthly_limit` → ユーザーが設定した月額上限（ドル）

### 証拠5: コミュニティの実測

- "A message in Claude's rate limit system is weighted by token consumption, not by the literal number of prompts"（TrueFoundry）
- "Long conversations cost more. A message in turn 50 includes the full conversation history"（複数情報源）
- Pro ~45 messages/5h, Max5x ~200 messages, Max20x 900+ messages で制限到達（Portkey）
  → メッセージ数の差はモデル・会話長で変動。固定メッセージ数制限ではない

### 証拠6: GitHub Issue #17252の証言

"20 lines of code consumed 14% of session usage limit"
→ コード行数やメッセージ数ではなく、そのリクエストが消費したトークン量（＝コスト）が14%に相当

## §3 カウントメカニズム（推定モデル）

```
1リクエストの消費コスト =
  (uncached_input_tokens × input_price/MTok)
  + (output_tokens × output_price/MTok)
  + (cache_creation_tokens × cache_write_price/MTok)
  ※ cache_read_tokensは消費ゼロ（公式: "only uncached input tokens count"）

utilization% = Σ(消費コスト) / 時間枠予算 × 100

時間枠:
  - five_hour: 5時間ローリングウィンドウ（最古メッセージから順に期限切れ）
  - seven_day: 7日間ウィンドウ（全モデル合算）
  - seven_day_sonnet: 7日間ウィンドウ（Sonnet専用枠）
```

### 重要な特性
- **ローリングウィンドウ**: 固定リセットではない。最古メッセージが5時間経過すると消費が徐々に回復
- **claude.ai + Claude Code共有**: Web/アプリでの使用もClaude Codeと同じ予算枠を消費
- **会話長さの影響**: 長い会話は毎ターンの入力トークンが増加 → 加速度的にコスト消費
- **キャッシュ読み取りは非課金**: prompt cachingが効いていればITPMレート制限にもカウントされない

## §4 確定情報 vs 推測の区分

### 確定（公式ドキュメント/API仕様）
- ✅ Usage APIエンドポイント: `GET /api/oauth/usage`（Bearer token + beta header）
- ✅ レスポンスフィールド: five_hour, seven_day, seven_day_sonnet, extra_usage
- ✅ utilization = パーセンテージ値
- ✅ extra_usage.used_credits = ドル単位
- ✅ 5時間ローリングウィンドウ + 7日間週間制限の2層構造
- ✅ claude.ai + Claude Code = 共有予算枠
- ✅ Extra usageは「standard API rates」で課金
- ✅ キャッシュ読み取りトークンはITPMレート制限に非カウント

### 強い推測（複数証拠から導出）
- 🟡 utilizationの分母 = ドル換算の予算枠
- 🟡 Opus ~5x消費 = API価格比と同一
- 🟡 プラン倍率 = 予算枠の倍率

### 不明（公式未開示）
- ❓ 各プラン・各時間枠の具体的なドル予算額
- ❓ キャッシュ作成トークンの扱い（課金対象か？）
- ❓ thinking tokensの扱い（output tokenと同じ料率か？）
- ❓ Max20xの20x倍率がMax5xの4倍か、独自計算か
- ❓ seven_day_sonnetの予算比率（全体枠との関係）

## §5 調査ソース

### 公式ドキュメント
- [Using Claude Code with Pro/Max](https://support.claude.com/en/articles/11145838-using-claude-code-with-your-pro-or-max-plan)
- [What is the Max plan?](https://support.claude.com/en/articles/11049741-what-is-the-max-plan)
- [Understanding usage and length limits](https://support.claude.com/en/articles/11647753-understanding-usage-and-length-limits)
- [Extra usage for paid plans](https://support.claude.com/en/articles/12429409-extra-usage-for-paid-claude-plans)
- [Manage costs effectively (Claude Code Docs)](https://code.claude.com/docs/en/costs)
- [Usage and Cost API](https://platform.claude.com/docs/en/api/usage-cost-api)
- [Rate limits (API Docs)](https://platform.claude.com/docs/en/api/rate-limits)

### OSSツール（APIレスポンス構造の検証源）
- [claude-code-pulse](https://github.com/hulryung/claude-code-pulse) — OAuth Usage APIモニタ
- [claude-pulse](https://github.com/NoobyGains/claude-pulse) — 同上、別実装
- [claude-usage](https://github.com/LightspeedDMS/claude-usage) — Python CLI、APIレスポンス例を公開
- [ccusage](https://github.com/ryoppippi/ccusage) — JSONL解析ツール（トークン数+コスト計算）
- [claude-code-limit-tracker](https://github.com/TylerGallenbeck/claude-code-limit-tracker) — ローカルJSONL解析

### コミュニティ・ニュース
- [Portkey: Everything We Know About Claude Code Limits](https://portkey.ai/blog/claude-code-limits/)
- [ClaudeLog: Claude Code Limits](https://claudelog.com/claude-code-limits/)
- [TrueFoundry: Claude Code Limits Guide](https://www.truefoundry.com/blog/claude-code-limits-explained)
- [Northflank: Rate limits, pricing, and alternatives](https://northflank.com/blog/claude-rate-limits-claude-code-pricing-cost)
- [TechCrunch: Anthropic unveils new rate limits](https://techcrunch.com/2025/07/28/anthropic-unveils-new-rate-limits-to-curb-claude-code-power-users/)
- [The Hidden Costs of Claude Code](https://www.aiengineering.report/p/the-hidden-costs-of-claude-code-token)

### GitHub Issues（実際のユーザー体験）
- [#17252: Excessive token consumption rate](https://github.com/anthropics/claude-code/issues/17252) — 20行のコードで14%消費
- [#22441: 70%なのにrate limit到達](https://github.com/anthropics/claude-code/issues/22441) — Web/CLI間の不整合
- [#16157: Max加入直後にlimit到達](https://github.com/anthropics/claude-code/issues/16157)
- [#25733: Max20xで低使用量なのにrate limit](https://github.com/anthropics/claude-code/issues/25733)

## §6 MCASへの実装示唆

1. **Usage APIの`utilization`をそのまま表示**すれば十分。内部計算の再現は不要
2. **extra_usage.used_credits**はドル額なので、そのまま表示可能
3. **七日間制限が2種**ある（全モデル + Sonnet専用）→ 両方モニタリングすべき
4. **キャッシュ効率**のモニタリングは別途JSONL解析が必要（Usage APIでは提供されない）
5. **アカウント切替の判断指標**: `five_hour.utilization` > 80% で切替推奨のアラートが合理的
