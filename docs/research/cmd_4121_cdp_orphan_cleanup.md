# CDP孤児プロセス掃除 — cmd_4121 二値計測

## 背景

- **発端**: cmd_4118 saizo が CDP Chrome 7プロセスを孤児として残存させた(pidfileなし)
- **原因**: `cleanup_all`/`cleanup_owner` はpidfile追跡分のみ掃除。pidfileなしプロセスは見逃す
- **結果**: `--user-data-dir`に`cdp-`を含むChrome孤児が自動掃除されずに蓄積

## 修正内容

`scripts/cdp_chrome_cleanup.sh` に `cleanup_orphan_profiles` 関数を追加。

- 対象: `cdp-` を含む `--user-data-dir` かつ `--remote-debugging-port` を持つ `chrome.exe`
- 除外: 殿のデフォルトChrome（`cdp-`を含まない）
- pidfile有無に関係なく掃除
- 既存 `cleanup_owner`(pidfile追跡)は維持

## 二値計測

| 状態 | 条件 | orphan_found | killed |
|------|------|-------------|--------|
| 修正前 | `cleanup_owner` のみ、pidfileなし孤児 | 検出不可 | 0 |
| 修正後 | `cleanup_orphan_profiles` 追加 | 2 | 2 |

### 計測フィクスチャ

```
PID   CommandLine
55001 chrome.exe --user-data-dir=C:\...\cdp-saizo-4118-mobile --remote-debugging-port=4118
55002 chrome.exe --user-data-dir=C:\...\cdp-hayate-9222-mobile --remote-debugging-port=9222
55003 chrome.exe --user-data-dir=C:\Users\simokitafresh --profile-directory=Default  ← 殿のChrome
```

- **修正後実行**: `Orphan profiles scan: found=2 killed=2`
- **55003 (殿のChrome)**: 掃除対象外(killed=0) ✓

### 実行コマンド

```bash
env CDP_PROCESS_TABLE_FILE="$PTABLE" CDP_STOP_LOG="$STOP_LOG" CDP_PID_DIR="$PID_DIR" \
  bash scripts/cdp_chrome_cleanup.sh --agent test-orphan
```

## 構文検証

```bash
bash -n scripts/cdp_chrome_cleanup.sh  # exit 0 確認済み
```

## 結論

CDP孤児=profileパターン自動掃除で意志非依存化。pidfileなし孤児プロセスが
`cleanup_orphan_profiles` により自動掃除されるようになった。
殿のデフォルトChrome（`cdp-`なし）は除外される安全境界も確認。
