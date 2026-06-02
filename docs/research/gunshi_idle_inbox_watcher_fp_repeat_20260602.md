# inbox_watcher FP-CHANGE連続nudgeバグ
<!-- generated: 2026-06-02T23:58:00+09:00 by gunshi idle analysis -->

## 現象

karoに同一「1 unread」で47秒間に3回nudge送信(23:48:43/23:49:48/23:50:29)。

## ログ証拠

```
[23:48:43] [FP-CHANGE] Unread set changed for karo (1 unread), sending nudge
[23:49:48] [FP-CHANGE] Unread set changed for karo (1 unread), sending nudge
[23:50:29] [FP-CHANGE] Unread set changed for karo (1 unread), sending nudge
[23:51:25] [FP-RESET] No unread, cleared fingerprint for karo
```

## 根因

inbox_mark_read.sh等のYAML書込みでkaro.yamlのmtimeが変化→MODIFYイベント発火→inbox_watcher.shがfingerprintを再計算→未読セットは同じ(msg_id同一)だがファイル内容の微差(timestamp等)でfingerprintハッシュが変わる→FP-CHANGEと判定→再nudge。

## 既存防御

- GP-139: `first_unread_age`で独立安全弁 → BUSY時のdefer。しかしnudge送信自体は抑制できない
- BUSY gating(L558-595): active+busy時はdefer。しかし`FP-CHANGE`パスはBUSY gatingの前に`send`判定が出る

## 影響

- 家老CTX消費: 同一nudge3回でコンテキスト無駄消費
- inbox処理重複: 家老が同じinboxを3回読む可能性
- 殿が「同じinboxが何度も届いている」と指摘(2026-06-02)

## 修正案

### 案A: nudge送信後のcooldown(推奨)

FP-CHANGE判定後、nudge送信成功→`LAST_NUDGE_TIME`記録→次のMODIFYでFP-CHANGE判定時に`LAST_NUDGE_TIME`から30秒以内ならスキップ。

```bash
# 疑似コード
LAST_NUDGE_FILE="${STATE_DIR}/last_nudge_${AGENT_ID}"
if [ -f "$LAST_NUDGE_FILE" ]; then
    last_nudge=$(stat -c %Y "$LAST_NUDGE_FILE")
    now=$(date +%s)
    if [ $((now - last_nudge)) -lt 30 ]; then
        echo "[NUDGE-COOLDOWN] Skipping (${now-last_nudge}s < 30s)"
        return
    fi
fi
# ... nudge送信 ...
touch "$LAST_NUDGE_FILE"
```

### 案B: fingerprint計算を未読msg_idセットのハッシュに限定

現在のfingerprint計算がファイル内容全体に依存しているなら、未読msg_idのソート済みリストのハッシュに限定。read: true/falseの切替やtimestampの微差でFPが変わらなくなる。

### 推奨: 案A+B併用

案A(cooldown)で即効性確保 + 案B(FP精密化)で根本対策。

## 因果リンク

- → [[LG016]] WSL2 NTFS flock/mtime問題の同根
- → [[feedback_idempotent_write_mtime]] 冪等書込みmtime副作用
- → [[inbox_watcher.sh]] FP-CHANGE判定ロジック
