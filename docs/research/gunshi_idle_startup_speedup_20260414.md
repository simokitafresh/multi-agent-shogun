# 起動ゲート高速化 — なぜなぜ7回×2

軍師idle自走。殿指示「スクリプトのリファクタリングや最適化、高速化をせよ。なぜなぜ7回」。

## 結果

| スクリプト | Before | After | 倍率 | 変更内容 |
|-----------|--------|-------|------|---------|
| gate_gunshi_startup.sh | 7.0s | 0.4s | 17.5x | gunshi_gate_sync.sh glob→find (1740ファイル) |
| gate_shogun_startup.sh | 6.6s | 1.5s | 4.4x | Context著者MAP全履歴→遅延評価 |
| 合計 | 14.9s | 3.2s | 4.7x | |

871テスト全PASS。回帰なし。

## なぜなぜ7回 #1: gunshi_gate_sync.sh (6.7s→0.065s, 103x)

1. なぜ6.7秒？ → archive cmdファイル1740個のglob展開+basename loop(3.1s)
2. なぜ1740ファイルにloop？ → `for f in *_done_*.yaml` がbash globで個別stat
3. なぜ個別stat？ → bashのfor-globが各ファイルにstat()発行
4. なぜstatが遅い？ → WSL2 NTFS DrvFsは1stat≒2ms。1740×2ms=3.5s
5. なぜ全件走査？ → 「アーカイブ済み=CLEAR」推定で全cmd_id必要
6. なぜbasename+sed？ → ファイル名→cmd_id変換にfork+exec×1740回
7. **根因: `find -maxdepth 1 | sed`で1回のI/Oで完了。glob展開+per-file fork=WSL2で致命的**

修正: `for f in *.yaml → find | sed | sort -u` (3.1s→0.018s, 172x)

## なぜなぜ7回 #2: gate_shogun_startup.sh Context著者MAP (2.5s→0s)

1. なぜ2.5秒？ → `git log --format='%an' --name-only -- context/`が全履歴走査
2. なぜ全履歴？ → depth制限なし。1965行出力
3. なぜ1965行必要？ → 「各context/*.mdの最終変更者」取得のため
4. なぜ全42ファイル分？ → Gate15の孤立context検知用
5. なぜ全ファイルの著者を事前取得？ → 孤立は通常0-5件だが全件分を計算
6. なぜ遅延評価しない？ → 歴史的設計（一括取得＝最適化のつもり）
7. **根因: 42ファイル全著者の事前計算は過剰。孤立ファイル(0-5件)検出後にgit log -1すれば十分**

修正: declare -A → 関数`_get_context_author()`遅延呼出し

### 計測裏付け（代替案の棄却根拠）
- per-file `git log -1` × 42ファイル: **50.4秒**（論外）
- xargs -P4並列: **19.2秒**（論外）
- 全履歴一括(旧方式): **2.5秒**（改善余地あり）
- **遅延評価(孤立のみ)**: 0件=**0秒**, 2件≒**2.4秒**（最適解）

## 共通根因

**WSL2 NTFS上では個別ファイルstat/openが1-2ms/回。ファイル数×2ms=秒単位。**
一括I/O(find/ls/cat)→パイプ処理に変換すれば1回のシステムコールで完了。

## 学んだ原則

1. **計測が先**: `bash -x`+タイムスタンプで各行の実行時間を可視化
2. **glob展開=隠れたO(N)stat**: WSL2 NTFSでは`for f in *.yaml`がN×2ms
3. **遅延評価**: 全データ事前計算より、必要時に最小限取得が高速(孤立0件→0秒)
4. **`-x`のオーバーヘッド**: bashプロファイリング自体がI/O増→実測と乖離(4.6s vs 1.3s)

作成: 2026-04-14T03:50:00+09:00
