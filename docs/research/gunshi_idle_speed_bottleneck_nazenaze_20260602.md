# 速度ボトルネック計測+なぜなぜ7回: report_field_set memory_db遅延
<!-- generated: 2026-06-02T20:25:00+09:00 by gunshi -->

## 速度ボトルネック実測結果

| スクリプト | 実行時間 | 頻度 |
|-----------|---------|------|
| gate_gunshi_report_precheck | **33秒** | レビューごと |
| └ semantic_search (memory_db FTS) | **13秒** (39.4%) | precheck内 |
| └ causal_backlinks (rg全走査) | 5秒 | precheck内 |
| gate_gunshi_startup | 1.9秒 | 起動ごと |
| gate_skill_script_refs | 488ms | cmd完了ごと |
| gate_report_format | 166ms | 報告ごと |
| stop-lint-gate | 75ms | 毎応答 |
| hooks (pre/post) | 5-21ms | 毎ツール |
| inbox_write | 32ms | 通信ごと |

## なぜなぜ7回: report_field_set memory_db遅延

| # | なぜ | 答え |
|---|------|------|
| 1 | report_field_setが230ms | python3 async.py起動+subprocess→python3 live_insert.py(2重python3) |
| 2 | 2重python3なのはなぜ | async.pyがsubprocess.run()で本体を別プロセス実行 |
| 3 | キュー31件蓄積 | 忍者報告バーストで生産>消費 |
| 4 | drain_limit=10で足りない | report_field_setが**フィールドごと**に呼ばれる。1報告30-50回 |
| 5 | drainしても減らない | 他忍者が同時記入中。生産>消費が恒常化 |
| 6 | async.pyの設計意図は | YAML書込みをブロックしない。だがpython3起動コストは残る |
| 7 | **根因** | **1フィールドごとにpython3×2起動。1報告60-100プロセス生成** |

## 対策

- cmd_karo_hotfix_semantic_search_timeout CLEAR (bounded query化+LLM明示制御)
- cmd_3133 (ext4キャッシュ化) APPROVE→配備中
- 家老がasync.pyにcoalesce_queue()+source_file_is_ephemeral()を追加(本セッション)
- 軍師D0(direct import)は家老対策と協調のため保留→家老修正検証後に判断

## Codex Stop痕跡

config.tomlにstop:0:0のtrusted_hash→Codex CLIはStopイベントをサポートしている可能性。blockレスポンス→無限ループだが、warn/infoレスポンスなら安全かもしれない。要実験。

## 教訓

- 派生ファイル(lessons.yaml)を正本(lessons.md)と混同するな。gate_lesson_healthの計測対象を確認せよ(洗脳#2)
- 計測は掲示板だけでなくdocs/researchに永続化。/clear後も参照可能にする
