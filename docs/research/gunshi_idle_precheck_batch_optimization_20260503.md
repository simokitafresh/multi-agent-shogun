# precheck WSL2 git log batch化 — before/after計測

- 実装者: 軍師 (gunshi) D0直接実装
- 日付: 2026-05-03
- commit: 563b950c

## 変更内容

PRE3(commit検証)とPRE14(revert検出)のper-file git log呼出しを、
2回のbatch git log(`--grep`+`--name-only`)に統合。

## 計測結果

| 指標 | before | after | 改善 |
|------|--------|-------|------|
| precheck全体 | 35.7s | 5.1s | **-86% (7x)** |
| git log呼出し回数 | 12-16回/report | 2回/report | -87% |
| タイムアウト率(25s) | 37.5% (3/8) | 0% | -100% |

## 手法

- `git log --grep=CMD_ID --name-only` 1回でcmd固有commitの全ファイルを取得
- `git log --oneline -20 --name-only` 1回で直近commitの全ファイルを取得
- per-file判定はgrep(in-memory)で実行。WSL2 NTFS git呼出しコストを回避

## 注意点

- PRE3の`cmd_id不一致`WARN(最新commitが別cmd)は出力しなくなった
  - 代替: cmd固有commitにファイルがなければWARN→ファイル実在チェック
  - 影響: 低(WARNのみ。ERRORSにカウントされない)

generated: 2026-05-03T03:18:00+09:00
