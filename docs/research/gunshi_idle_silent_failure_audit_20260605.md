# Silent Failure Audit — 直近変更スクリプト
<!-- generated: 2026-06-05T15:16:00+09:00 by gunshi idle analysis -->
<!-- 洗脳監査(19:15): P0-2(cmd_complete_gate.sh)は偽陽性。L452-453に空文字guard済み。P0-1(sync_lessons.sh)はP2に格下げ(os.walk fallback正常動作) -->

## 監査対象

直近20コミットのshellスクリプト変更から5ファイルを選定し、silent failureパターンを検出。

## P0 (重大) — 直ちに対処が必要

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
- **影響**: target_files自動抽出がサイレント失敗→lessons.yamlのtarget_files未設定→教訓参照精度低下
- **推奨**: 例外型別分岐(TimeoutExpired→warn、その他→error) + fallback時にstderrへ診断ログ記録

### 2. cmd_complete_gate.sh L452,454: tmux操作の戻り値チェック喪失

```bash
pane_target=$(agent_pane_target "$agent" 2>/dev/null || true)
```

- **問題**: agent_pane_targetのtmuxエラーを2>/dev/null+||trueで完全消音。GATE処理中にtmux操作失敗がサイレント通過
- **影響**: GATE処理がpane_target未解決のまま進行→cmd_complete通知の送信先ミスの可能性
- **推奨**: ||trueを除去し、pane_target空文字チェックを追加

## 対処判定

| # | 対象 | D0適用可 | 理由 |
|---|------|---------|------|
| 1 | sync_lessons.sh | NO | Python embedded script、例外分岐追加は20行超 |
| 2 | cmd_complete_gate.sh | YES | 1行修正(||true除去+空文字guard) |

→ P0-2はD0候補だが、cmd_complete_gate.shは高リスクファイル(7125行)のため家老経由cmd推奨。
