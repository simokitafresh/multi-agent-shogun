# 事後チャンピオン選出ツール設計書
<!-- gunshi 2026-04-11 殿指示: 現行方式の極限を目指せ -->

## 結論

`outputs/scripts/champion_selector.py` — GS CSV/.npyから3目的チャンピオンを直列選出。
195万パターン×3メトリクス → **25秒、peak RSS ~1GB**。cmd_1844(hanzo)と21/21完全一致。

## なぜなぜ7回（計測ベース）

| # | なぜ | 計測事実 |
|---|------|---------|
| 1 | なぜ素朴vectorizedではダメ？ | cumprodがNaN伝播。真チャンピオン(kasoku_diff CAGR=1.078)がNaN化して消える |
| 2 | なぜNaN-safe+float64が必要？ | NaN→0置換+有効月数年率化で正解一致。float64でMaxDD順位安定 |
| 3 | なぜチャンク処理？ | 一括RSS 5.7GB → チャンク100K列でRSS 1.1GB。OOM構造的排除 |
| 4 | なぜ方向テーブル？ | MaxDDだけlower-is-better。cmd_1840で方向バグ実証済み |
| 5 | なぜNHFでNaN月除外？ | NaN→0でequity横ばい=偽new high。valid_mask AND new_highで除外必須 |
| 6 | なぜ.npy優先？ | CSV 1.8GB→.npy 541MB。mmapで即開始。CSVパース不要 |
| 7 | 到達: 5要素(NaN-safe/float64/チャンク/方向テーブル/NaN月NHF除外)をツールに埋込み。25秒/1GB |

## 4要素の自動化×強制

| 要素 | 問題 | 埋込み方法 |
|------|------|-----------|
| NaN-safe CAGR | cumprod NaN伝播でチャンピオン消失 | prod方式+有効月数年率化 |
| NaN月NHF除外 | NaN→0で偽new high発生 | `(new_high & valid).sum() / n_valid` |
| METRIC_DIRECTION | MaxDD方向間違い(cmd_1840実証) | ツール内定数テーブル。未知メトリクス→KeyError |
| float64 MaxDD | float32で近接順位入替 | チャンク内でastype(float64) |
| チャンク処理 | 一括RSs 5.7GB→OOMリスク | 100K列単位。peak 1.1GB |

## ベンチマーク実測値

| 忍法 | パターン数 | 時間 | source |
|------|-----------|------|--------|
| bunshin | 6,175 | 0.06s | npy |
| yotsume | 37,050 | 0.32s | npy |
| oikaze | 222,300 | 1.86s | npy |
| kawarimi | 222,300 | 1.85s | npy |
| nukimi | 481,650 | 4.22s | npy |
| kasoku_diff | 944,775 | 8.47s | npy |
| kasoku_ratio | 944,775 | 8.41s | npy |
| **合計** | **1,859,025** | **25.2s** | — |

Peak RSS: ~1,055MB (kasoku_diffチャンク処理時)

## cmd_1844との突合（21/21完全一致）

全7忍法×3目的=21チャンピオンがcmd_1844(hanzo手動計算)と完全一致。
pattern_id・値ともに一致を確認。

## 使い方

```bash
cd /mnt/c/Python_app/DM-signal

# 全7本
python3 outputs/scripts/champion_selector.py \
  --csv-dir outputs/grid_search/okugi_shin_ninpo_20body \
  --cmd-id cmd_1822

# 特定忍法
python3 outputs/scripts/champion_selector.py \
  --csv-dir outputs/grid_search/okugi_shin_ninpo_20body \
  --cmd-id cmd_1822 \
  --ninjutsu bunshin,kasoku_diff

# JSON出力
python3 outputs/scripts/champion_selector.py \
  --csv-dir outputs/grid_search/okugi_shin_ninpo_20body \
  --cmd-id cmd_1822 --json
```

## 経緯

1. cmd_1843: wf_runner.py並列実行でOOM Kill → エージェント死亡
2. 殿裁定: 並列不要、直列が正解。cmd_1843クローズ
3. 殿指示: 現行方式(直列事後計算)の極限を目指せ。なぜなぜ7回
4. 穴発見: OOMリスクゼロ(嘘)/30秒(想像)/adhoc(未確認) → 計測で全て修正
5. 5つの穴を仕組みに埋込み → 25秒/1GB/21/21一致のツール完成
