# Silent Failure Audit — 直近変更スクリプト
<!-- generated: 2026-06-05T15:16:00+09:00 by gunshi idle analysis -->
<!-- 洗脳監査(19:15): P0-2(cmd_complete_gate.sh)は偽陽性。L452-453に空文字guard済み。P0-1(sync_lessons.sh)はP2に格下げ(os.walk fallback正常動作) -->

## 監査対象

直近20コミットのshellスクリプト変更から5ファイルを選定し、silent failureパターンを検出。

## P2 (中) — 診断ログ改善候補

### 1. sync_lessons.sh L110-133: subprocess.run exception握りつぶし

```python
def _add_tracked_filenames_from_git(base):
    try:
        proc = subprocess.run(
            ['git', '-C', base, 'ls-files', '--', *_tf_scan_dirs],
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=8,
        )
    except Exception:        # TimeoutExpired含む全例外を握りつぶし
        return False         # 呼出元はgit失敗/timeoutを区別不可
```

- **問題**: TimeoutExpired/git失敗の区別なくreturn False→fallback os.walkが発動。ログ出力なし
- **影響**: fallback os.walkにより処理継続するためP0ではないが、git失敗診断が残らず調査性が落ちる
- **推奨**: 例外型別分岐(TimeoutExpired→warn、その他→error) + fallback時にstderrへ診断ログ記録

## 偽陽性

### 2. cmd_complete_gate.sh L452,454: tmux操作の戻り値チェック喪失

初回監査ではP0候補としたが、現物確認により偽陽性。L452-453に空文字guardがあり、pane_target未解決のまま通知先ミスへ進む構造ではない。

## 対処判定

| # | 対象 | D0適用可 | 理由 |
|---|------|---------|------|
| 1 | sync_lessons.sh | NO | P2。fallback正常動作あり。診断ログ改善候補 |
| 2 | cmd_complete_gate.sh | NO | 偽陽性。既存guard確認済み |

→ 即時D0修正対象なし。sync_lessons.shは診断性改善cmd候補として扱う。
