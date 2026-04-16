# gate_karo_startup.sh リファクタリング CoDD Spec (事後作成)

## cmd: cmd_1958 (CoDD改善#6)
## 実施者: tobisaru

## 問題（ボトルネック関数+計測値）

gate_karo_startup.sh の実行時間 464ms。
ボトルネック3箇所: python3 x 4回起動 + tmux list-panes x 6回 + WA gate 直列実行。

## 定量プロファイル(実測 before)

| 処理 | 時間 | 根因 |
|------|------|------|
| python3 x 4回 (phase guide x 2 + session summary + bulletin) | ~120ms | インタプリタ起動 x 4(各~30ms) |
| tmux list-panes x 6回 | ~30ms | tmuxサーバー問い合わせ x 6(各~5ms) |
| gate_workaround_rate.sh + gate_ninja_workaround_rate.sh (直列) | ~120ms | 2つのゲートを逐次実行 |
| その他 | ~194ms | - |
| **合計** | **464ms** (3回計測: 397/572/424ms) | python3起動+tmux重複+直列WA |

### python3 1回あたりのコスト
- インタプリタ起動: ~25-30ms
- 実処理: ~2-5ms
- **計: ~30ms/回**

## リファクタリング対象

### R1: python3 4回起動 → 1回に統合

**現状**:
- python3 起動 #1: phase guide (deepdive_why_chain)
- python3 起動 #2: phase guide (deepdive_causal_tracing or deepdive_karo_verification)
- python3 起動 #3: session summary 生成
- python3 起動 #4: bulletin board 解析

**改善**:
- 4つの python3 呼び出しを1つの統合スクリプトにまとめ、1回の起動で全処理を実行

- 期待効果: ~90ms削減(python3起動3回分)
- 実績: 統合により ~90ms削減

### R2: tmux list-panes 6回 → 1回キャッシュ

**現状**:
- ループ内で忍者ペインごとに tmux list-panes を呼び出し
- 6忍者分で6回の tmux サーバー問い合わせ

**改善**:
- ループ外で1回だけ tmux list-panes を実行し、結果を変数にキャッシュ
- ループ内ではキャッシュした結果を参照

- 期待効果: ~25ms削減(tmux問い合わせ5回分)
- 実績: 6回 → 1回で ~25ms削減

### R3: WA gate 直列実行 → バックグラウンド並列起動

**現状**:
- gate_workaround_rate.sh を実行完了後に gate_ninja_workaround_rate.sh を実行(直列)

**改善**:
- 両方を `&` でバックグラウンド起動し `wait` で同期
- 実行時間 = max(gate_wa, gate_ninja_wa) に短縮

- 期待効果: ~60ms削減(2つの直列 → 並列で約半分)
- 実績: 並列化により ~60ms削減

## 制約

- テスト全PASS必須(全12テスト)
- API互換（出力形式変更なし）: ゲート出力(9項目チェック結果)のフォーマット・判定基準は不変
- 凍結ロジック: 9項目の個別チェックロジック(deepdive必読催促, 陣形図鮮度, 忍者CTX実態, inbox未読, PD未解決, workaround傾向, 忍者別WA率, idle自走, 配備漏れ)

## 結果

- before: 464ms (3回計測: 397/572/424ms)
- after: 225ms (3回計測: 200/271/205ms)
- 改善率: 51%削減(2.1x高速化, 目標300ms達成)
- テスト: 12/12 PASS
- 対象ファイル: `scripts/gates/gate_karo_startup.sh`
