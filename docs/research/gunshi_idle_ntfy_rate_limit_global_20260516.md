# ntfy rate limit問題 — クライアント側グローバルthrottle不在

## 現象
本日778回のntfy 429(rate limit)。200成功はわずか1件(09:00)。殿への通知がほぼ全て失敗。

## 429内訳
| 送信元 | 429件数 | 備考 |
|--------|---------|------|
| context鮮度ALERT | 228件 | cmd_2797(07:41)修正前の7.5時間で蓄積 |
| INFOバッチ | 30件 | |
| CLI再起動成功 | 18件 | cmd_2806 respawnループ修正前 |
| Dashboard更新 | ~8件 | |
| SessionEnd ALERT | 4件 | |
| その他 | ~490件 | 合計778 |

## なぜなぜ
1. なぜ778回429？ → ntfyサーバーのrate limitに到達
2. なぜcmd_2797/2798で対処済みなのに？ → 修正(07:41)前の7.5時間で228回蓄積。修正後は0回
3. なぜcontext鮮度以外も429？ → rate limitは送信元全体で共有。1送信元の大量送信が全体を汚染
4. なぜ大量送信が他に波及？ → 各送信元が独立。グローバルthrottleなし
5. なぜグローバルthrottleがない？ → ntfy.shがfire-and-forget設計。429→return 1→終了。バックオフなし
6. なぜbackoffがない？ → ntfy.shは元々低頻度送信を想定。自動化増加でrate limit未考慮
7. 根因: **ntfy.shにクライアント側グローバルthrottle/backoffがない。各送信元の独立デバウンスでは新送信元追加で再発する**

## 影響
- 殿への全通知(Dashboard/CMD完了/ALERT/CI RED等)が07:41まで不達
- rate limit回復後も累積バースト分が遅延
- cmd_2797/2798は部分対策（1送信元のみ）。根本対策ではない

## 修正案
### ntfy.shにグローバルthrottle追加
1. `/tmp/ntfy_last_send_epoch`に最終送信時刻を記録
2. 前回送信から10秒以内→sleep(10-elapsed)でthrottle
3. 429受信→60秒cooldown(`/tmp/ntfy_cooldown_until`)
4. cooldown中の全送信→stderrログ+skip（fire時に確認）

### 効果
- 全送信元に一括適用（各送信元のデバウンス実装不要）
- 429到達→自動cooldown→回復後に正常化
- 新送信元追加時もntfy.shのthrottleが自動保護

## 因果鎖
context鮮度228回(7.5h)→rate limit→全ntfy 429→殿通知不達。ntfy.shグローバルthrottle→rate limit到達前にthrottle→全送信元保護=正の複利
