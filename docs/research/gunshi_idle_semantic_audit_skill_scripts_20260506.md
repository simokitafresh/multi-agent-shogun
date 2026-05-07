# セマンティック監査: スキル関連スクリプト4本 (2026-05-06)

## 対象
- `scripts/skill_gate_feedback.sh` (262行)
- `scripts/skill_execution_log.sh` (124行)
- `scripts/skill_metrics.sh` (107行)
- `scripts/cmd_absorb.sh` (267行)

## トリガー
`git diff --name-only 8c94bab5^..HEAD -- scripts/` で直近変更4本を検出。

## 監査結果サマリ

| スクリプト | silent_failure | state_transition | race_condition | implicit_assumption |
|-----------|---------------|-----------------|----------------|---------------------|
| skill_gate_feedback.sh | 検出なし | P2(状態値多値チェック不足) | P2(TOCTOU: read→write) | P1(引数バリデーション) |
| skill_execution_log.sh | 検出なし | P2(resultホワイトリスト不足) | P2(flock timeout無音) | P2(パースエラー処理) |
| skill_metrics.sh | 検出なし | P2(OTHERステータス無音無視) | P3(glob読取専用) | P1(usedフィールドnull値) |
| cmd_absorb.sh | ★偽陽性確認済 | P1(dual-lock不整合) | P1(複数ファイル非atomic) | P1(ハードコードパス) |

## P0検出→偽陽性確認

### cmd_absorb.sh subshell exit伝播問題
- **エージェント報告**: subshell内のexit 1が親に伝播しない → update_cmd_yaml失敗後に後続実行
- **現物検証**: `set -euo pipefail`(行8)が有効。bashで`( exit 1 ) 200>/dev/null`は`set -e`で親を停止させる
- **実証**: `bash -c 'set -euo pipefail; (exit 1) 200>/dev/null; echo "should not reach"'` → 到達せず
- **結論**: **偽陽性**。`set -e`がsubshellの非ゼロexitを正しく伝播

## P1問題(真)

### 1. cmd_absorb.sh dual-lock不整合 (state_transition + race_condition)
- 行206-209: `update_cmd_yaml` → `abort_deployed_ninjas` → `append_changelog` → `notify_karo` が順序実行
- CMD_FILEとCHANGELOG_FILEは独立flock。update成功→changelog前にクラッシュ時に不整合
- **実運用リスク**: 低。cmd_absorbの呼出頻度は低く（月数回）、クラッシュ自体が稀
- **対策案**: 即時対応不要。将来的に単一トランザクション化

### 2. skill_metrics.sh usedフィールドnull値 (implicit_assumption)
- 行88: `str(entry.get("used", True)).strip().lower() == "false"`
- YAML `used: null` → `str(None)="None"` → `"none" != "false"` → フィルタされずFAILカウント
- **実データ確認**: 7エントリ全てにnullなし。将来リスクのみ
- **対策案**: `if entry.get("used") is False or str(entry.get("used","")).lower() == "false":` に修正

### 3. skill_gate_feedback.sh 引数バリデーション (implicit_assumption)
- 行46-262: Python埋め込みが`sys.argv[1:9]`で固定8引数を期待。不足時エラーメッセージなし
- **実運用リスク**: 低。呼出元はhookで引数固定

## 結論
- P0: 0件（偽陽性1件確認済み）
- P1: 3件（即時対応不要、将来リスクとして記録）
- P2: 多数（ログ改善、バリデーション強化等）
- **cmd起票推奨**: なし（実害発生前。skill_metrics.shのnull値修正はD0候補だが優先度低）
