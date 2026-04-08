# cmd_323 R4-Task3: scripts/archive_completed.sh コードレビュー (Blind C)

## 1. 全体構造の把握
- エントリポイント: `set -euo pipefail` と `trap cleanup EXIT` で開始し、引数を `KEEP_RESULTS`/`CMD_ID` に正規化。
- `archive_cmds()`:
  - `queue/shogun_to_karo.yaml` を行範囲分割で各cmdエントリ化。
  - `status` 判定で完了cmdを `queue/archive/shogun_to_karo_done.yaml` と `queue/archive/cmds/*.yaml` へ退避。
  - 未完了cmdのみを再構成して元キューへ戻す。
- `archive_dashboard()`:
  - `dashboard.md` の戦果テーブルから直近 `KEEP_RESULTS` 件を残し、古い行を `queue/archive/dashboard_archive.md` に追記。
- Main:
  - `archive_cmds` → `archive_dashboard` 実行後、`CMD_ID` 指定時に `queue/gates/{CMD_ID}/archive.done` を生成。

## 2. Findings (HIGH/MEDIUM/LOW)

| Severity | Category | Line | Description | Recommendation |
|---|---|---:|---|---|
| HIGH | security/path-traversal | 48-52, 192-193 | `CMD_ID` の検証が `cmd_*` のみで `/` や `..` を許容。`queue/gates/${CMD_ID}` 生成時に想定外パスへ到達可能。 | `CMD_ID` を厳格許可リスト（例: `^cmd_[0-9]+[a-z0-9_:-]*$`）で検証し、`/` と `..` を明示拒否。さらに `realpath` で `queue/gates` 配下を強制。 |
| HIGH | security/path-traversal | 104-107, 114-118 | キュー内 `id` から得た `cmd_id` をそのまま `queue/archive/cmds/${cmd_id}_...yaml` に使用。汚染データ時にアーカイブ先逸脱リスク。 | `cmd_id` の再検証を実装（許可リスト + `/` 禁止）。ファイル名化時に unsafe 文字を `_` へ正規化。 |
| MEDIUM | security/temp-file | 14, 63-64, 176 | `/tmp/*_$$.*` の固定名テンポラリを使用。ローカル競合/リンク差し替えに弱く、意図しないファイル操作の足掛かりになる。 | `mktemp` を使用し、`TMPDIR` と `umask 077` を適用。trap対象は実際に生成したパスを配列管理。 |
| MEDIUM | robustness/parsing | 97-101 | `status` 抽出が `^  status:` 固定。インデント揺れ時（L034系）に完了cmdを取りこぼす可能性。 | YAMLパーサ利用（推奨）か、top-level `status` をアンカー付きで堅牢抽出。入力フォーマット検証を追加。 |
| LOW | correctness/input-validation | 42-45 | ヘルプ文言は「正の整数」だが `KEEP_RESULTS` 検証は `0` を許容。仕様と実装が不一致。 | 正の整数を厳密化（`^[1-9][0-9]*$`）し、ヘルプと挙動を一致させる。 |

## 3. セキュリティ観点レビュー
- 主要リスクは **パストラバーサル**（`CMD_ID`/`cmd_id` の未サニタイズ）と **予測可能なテンポラリ名**。
- コマンド注入（`eval`/`python -c` 直埋め込み）は当該ファイル内では未検出。
- `flock` によるキュー/ダッシュボード更新の排他は実装済みで、競合耐性は一定確保されている。

## 4. 良い点
- `set -euo pipefail` と関数分割で失敗時挙動が明確。
- `QUEUE_FILE`/`DASHBOARD` 更新時に `flock` + `mv` を使い、更新競合と中間破損を抑制。
- cmd単位アーカイブ（`queue/archive/cmds/`）を併設し、追跡性を担保している。

## 5. サマリー
- HIGH: 2
- MEDIUM: 2
- LOW: 1
- Overall assessment: 運用保守性は高いが、ファイルパス入力の厳格化とテンポラリ安全化を優先しないと、将来の運用入力変化でセキュリティ事故へ繋がる。
