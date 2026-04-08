# cmd_323 R4-Task3: archive_completed.sh コードレビュー (Blind-ID: A)

- reviewer: opus (hayate)
- date: 2026-02-25
- target: scripts/archive_completed.sh (197行)
- lessons_referenced: L047, L043, L034, L010, L009

## §1 全体構造

```
L1-10    ヘッダー・Usage
L11-16   set -euo pipefail + trap cleanup
L17-55   定数定義 + 引数パース・バリデーション
L57-143  archive_cmds() — shogun_to_karo.yaml完了cmdアーカイブ
L145-181 archive_dashboard() — ダッシュボード古い戦果アーカイブ
L183-198 Main — 両関数実行 + gate flag出力
```

処理フロー:
1. 引数パース（keep_results数値 + cmd_id形式チェック）
2. shogun_to_karo.yaml内の完了ステータスcmdを個別ファイル + 統合アーカイブに退避
3. dashboard.mdの古い戦果行をdashboard_archive.mdに退避
4. CMD_ID指定時はgate flagファイルをtouch

## §2 指摘事項

### HIGH (2件)

| # | Category | Line | Description | Recommendation |
|---|----------|------|-------------|----------------|
| H1 | Security | L105-107→L114 | `cmd_id`がファイル内容から抽出されサニタイズなしでファイルパス構築に使用。`sed 's/^- id: //'`の結果にスペースや特殊文字（`../`等）が残る可能性。パストラバーサルリスク | `cmd_id`抽出後に`[a-zA-Z0-9_]`のみ許可するバリデーション追加: `[[ "$cmd_id" =~ ^[a-zA-Z0-9_]+$ ]] \|\| continue` |
| H2 | Security | L14, L63-64 | `/tmp/stk_active_$$.yaml`等のPIDベース一時ファイルは予測可能。シンボリックリンク攻撃で任意ファイル上書きの理論的リスク | `mktemp`使用に変更: `tmp_active=$(mktemp /tmp/stk_active_XXXXXX.yaml)` + cleanup関数も対応更新 |

### MEDIUM (3件)

| # | Category | Line | Description | Recommendation |
|---|----------|------|-------------|----------------|
| M1 | Robustness | L100 | `grep '^  status: '` — 固定2-spaceインデント依存。**L034が直接該当**。YAML構造変更時にサイレント不一致 | 柔軟パターンに変更: `grep '^\s*status:\s' \| head -1` + sed調整 |
| M2 | Race condition | L167-171 vs L174-178 | DASH_ARCHIVEへの追記(L171)がflock外、DASHBOARD削除(L176)がflock内。並行実行時にアーカイブ重複+行番号ズレ | flock範囲を拡大し、DASH_ARCHIVE追記もflock内に含める |
| M3 | Clarity | L39 vs L104 | スクリプトレベル`CMD_ID`（大文字）とarchive_cmds()内local `cmd_id`（小文字）が同じセマンティクスで併存。混乱要因 | ローカル変数を`entry_cmd_id`等に改名して区別明確化 |

### LOW (3件)

| # | Category | Line | Description | Recommendation |
|---|----------|------|-------------|----------------|
| L1 | Fragility | L153 | `grep -n '^| [0-9]' "$DASHBOARD"` — テーブルデータ行が数字始まり前提。cmd_id等が先頭に来ると不一致 | パターン再検討（実際のテーブル形式を確認の上） |
| L2 | Data integrity | L134-135 | `cat>>ARCHIVE_CMD`成功後に`mv`が失敗すると、次回実行で同cmdが重複アーカイブ | mv失敗時のロールバック or 冪等性チェック（archive内に既存cmd_idがあればスキップ） |
| L3 | Cosmetic | L30 | `usage_error`が`$*`を生表示。セキュリティリスクはないが、長い引数でstderrが汚れる | 長さ制限 or 引用符囲みで表示 |

## §3 セキュリティ観点レビュー

### 良好な対策
- `set -euo pipefail` (L11): 未定義変数・パイプ失敗を即座に検出
- flock排他制御 (L132-136, L174-178): 並行書き込み保護
- 引数バリデーション (L42-52): 数値チェック + cmd_形式チェック
- trap cleanup (L16): 一時ファイルの確実な後始末

### 注意点
- **H1**: 内部YAML由来のcmd_idをサニタイズなしでファイルパスに使用（defence-in-depth不足）
- **H2**: PID予測可能な一時ファイル（mktemp推奨）
- **L047/L043適用**: Pythonは不使用だが、「外部データをサニタイズなしでシェル操作に使用」の教訓本質はH1に該当
- rm -fはL78, L139, L142のみ — 全てtmpファイル対象で安全

## §4 良い点

| # | Line | Description |
|---|------|-------------|
| G1 | L11 | `set -euo pipefail` — bash best practice完全準拠 |
| G2 | L14-16 | trap EXIT + PIDベースtmpファイル — 確実なリソース解放 |
| G3 | L114 | 個別cmd単位アーカイブファイル（`{cmd_id}_{status}_{date}.yaml`）— 監査証跡として優秀 |
| G4 | L132-136 | flock -w 10による排他制御 — 並行安全性確保 |
| G5 | L34-52 | 引数パースの柔軟性（位置入替対応）+ 形式バリデーション |

## §5 教訓照合

| Lesson | Applicable | Detail |
|--------|-----------|--------|
| L047 | 間接的 | Python不使用だが「外部データ→パス構築」のH1に教訓本質が適用 |
| L043 | 間接的 | 同上 |
| L034 | **直接該当** | L100の固定2-spaceインデントgrep → M1指摘 |
| L010 | 注意 | L100はentry内文脈で2-space前提だが、YAML構造変動時にM1と合流 |
| L009 | 非該当 | git操作なし |

## §6 総合評価

| Metric | Value |
|--------|-------|
| HIGH | 2 |
| MEDIUM | 3 |
| LOW | 3 |
| Good practices | 5 |
| Overall | 堅実な実装。セキュリティ面のdefense-in-depth（H1, H2）と柔軟性（M1）の強化が推奨。並行安全性は概ね良好だがM2の範囲拡大が望ましい |
