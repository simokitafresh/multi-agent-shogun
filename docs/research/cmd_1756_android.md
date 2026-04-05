# cmd_1756_android: Androidアプリ差分比較

> 大元: yohey-w/multi-agent-shogun v4.3.0→v4.4.1 (c87ca64)
> 我が軍: simokitafresh/multi-agent-shogun v6.2 (versionCode=13)
> 調査日: 2026-04-06

## §1 大元タグ状況

| タグ | 日付 | 備考 |
|------|------|------|
| v4.3.0 | 2026-03-27 | `--effort max` 導入 |
| v4.4.0 | 2026-03-27 | karo daily log, .gitignore更新 (Android変更なし) |
| v4.4.1 | 2026-03-28 | **Android修正リリース**: ratelimit表示修正+SSH改善+key picker |

**v4.5.0は存在しない。** タスク記載のv4.5.0は未発行。最新=v4.4.1。

## §2 変更ファイル一覧 (android/ のみ)

| ファイル | 追加行 | 削除行 | 内容 |
|---------|--------|--------|------|
| ssh/SshManager.kt | +30 | -5 | SSH key bytes loading, stderr capture |
| ui/AgentsScreen.kt | +31 | -2 | Raw/UI toggle, parse failure fallback |
| ui/SettingsScreen.kt | +108 | -42 | SSH key file picker |
| viewmodel/AgentsViewModel.kt | +3 | -2 | 2>&1 redirect, error message改善 |

## §3 機能差分表

### 3.1 SSH Key File Picker + Bytes Loading (P1:高)

**大元の変更**:
- `SettingsScreen.kt`: `ActivityResultContracts.OpenDocument()` でファイルピッカーUI追加
- `SettingsScreen.kt`: `copySshKeyToAppStorage()` — 選択した鍵をアプリ内部ストレージにコピー
- `SshManager.kt`: `loadPrivateKeyIdentity()` — ファイルからバイト配列で鍵を読み、`jsch.addIdentity(name, keyBytes, null, passphraseBytes)` で登録
- Android 11+ のScoped Storage対応。パスベースの `addIdentity(path)` ではアクセス不可のケースがある

**我が軍の状態**: 未取込。パスベースの `jsch.addIdentity(lastKeyPath)` のまま

**取込推奨度**: **高** — Android 11+でSSH接続が失敗するケースの根本修正。UX大幅改善(ファイルピッカー)

### 3.2 stderr capture in SSH exec (P1:高)

**大元の変更**:
- `SshManager.kt`: `execCommandInternal()` に `channel.errStream` 読み取り追加
- stderrが空でなければ `AppLogger.log("SSH", "exec STDERR ...")` でログ出力
- ratelimit_check.sh等のスクリプトエラーがAndroid側でデバッグ可能に

**我が軍の状態**: 未取込。stderrは読み捨て

**取込推奨度**: **高** — デバッグ能力の大幅向上。変更量小(+15行程度)

### 3.3 Raw/UI Toggle in Ratelimit Dialog (P2:中)

**大元の変更**:
- `AgentsScreen.kt`: ダイアログタイトル行に Raw/UI トグルボタン追加
- `showRawText` state で生テキスト表示を切替可能
- パース失敗時の `hasAnyData` チェック + フォールバック表示

**我が軍の状態**: **部分的に取込済み**
- parse failure fallback: `allNull` チェックで同等機能を実装済み（かつ大元より包括的 — sonnet7d/opus7d/todayTokens/sessions/messages も検査）
- Raw/UI手動トグル: 未取込

**取込推奨度**: **中** — parse failure fallbackは既に我が軍の方が優秀。Raw/UIトグルは便利だが必須ではない

### 3.4 2>&1 Redirect + Error Message (P2:中)

**大元の変更**:
- `AgentsViewModel.kt`: `ratelimit_check.sh 2>&1` でstderr統合
- エラーメッセージに実行コマンドを含む: `"SSH取得失敗: ${it.message}\ncmd: $cmd"`

**我が軍の状態**: **別アプローチで進化済み**
- `usage_status.sh` を使用（大元の `ratelimit_check.sh` とは別スクリプト）
- Claude/OpenAI プロバイダ切替機能あり（大元にはない独自機能）
- ただし `2>&1` redirect は付加していない

**取込推奨度**: **中** — `usage_status.sh` 呼び出しに `2>&1` を追加する価値はあり

### 3.5 lastKeyPath.trim() (P3:低)

**大元の変更**: `lastKeyPath = privateKeyPath.trim()` — 空白文字のトリミング

**我が軍の状態**: 未取込

**取込推奨度**: **低** — 3.1のbytes loading取込時に自然に含まれる

## §4 取込推奨リスト（優先順位順）

| 順位 | 機能 | 変更対象ファイル | 推定行数 | 理由 |
|------|------|-----------------|---------|------|
| 1 | SSH key file picker + bytes loading | SshManager.kt, SettingsScreen.kt | +140/-50 | Android 11+ Scoped Storage対応。鍵読込の根本修正 |
| 2 | stderr capture | SshManager.kt | +15/-0 | デバッグ能力向上。低コスト高効果 |
| 3 | Raw/UI toggle | AgentsScreen.kt | +20/-0 | 手動デバッグ切替。既存parse fallbackとは補完関係 |
| 4 | 2>&1 redirect | AgentsViewModel.kt | +2/-1 | `usage_status.sh` 呼出にstderr統合追加 |

## §5 我が軍の独自進化（大元にない機能）

大元v4.4.1にはなく我が軍v6.2にある機能:
- Claude/OpenAI プロバイダタブ切替 (`RateLimitProviderTab`)
- `usage_status.sh` 経由のratelimit取得（大元は `ratelimit_check.sh`）
- より包括的なparse failure fallback (`allNull` — 7フィールド検査 vs 大元の3フィールド)
- `backgroundStyle` / `fontSizePref` / `softWrapEnabled` 設定
- `themeMode` 設定
- `BuildConfig` import (バージョン表示)
- v6.2 (versionCode=13) vs 大元v4.4.1

## §6 注意事項

- 順位1（SSH key picker + bytes loading）は SettingsScreen.kt の変更量が大きい(+108/-42)。imports追加+`copySshKeyToAppStorage()`関数追加+SSH鍵パスUI改修の3点セット
- SshManager.kt の `loadPrivateKeyIdentity()` は順位1と順位2を同時に取り込む場合、同一ファイルで衝突しないよう注意
- 大元の `ratelimit_check.sh` は我が軍では `usage_status.sh` に進化済み。スクリプト名の違いに注意
