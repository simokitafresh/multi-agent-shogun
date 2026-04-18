# cmd_2036 CoDD Batch

対象:
- `scripts/lesson_write.sh`
- `scripts/sync_lessons.sh`
- `scripts/inbox_write.sh`

## 計測条件

- 実施日: 2026-04-18
- 実施者: hayate
- 計測方法: 一時 fixture 上で 10-20 回反復し、平均実行時間(ms)を算出
- 目的: 起動直後の無駄な subprocess / YAML 参照 / ファイル走査を削減

## 変更要約

### `scripts/lesson_write.sh`

- named option 解析を単一 pass 化
- `config/projects.yaml` の `path/context_file` 解決をプロセス内キャッシュ化
- lesson ID 採番と exact duplicate 検出を単一走査へ統合
- tags / reflux keyword 整形を shell/awk に寄せて subprocess を削減

結果:
- `133ms -> 113ms` (`-15.0%`, same fixture average)

### `scripts/sync_lessons.sh`

- project path 解決を Python 起動前の bash/awk に置換
- divergence 通知でしか使わない `subprocess` import を遅延化

結果:
- `80ms -> 55ms` (`-31.3%`, same fixture average)

### `scripts/inbox_write.sh`

- `lock_path` を `/mnt/c|/mnt/d` のみ `/tmp` hash lock、その他は隣接 `.lock` に分岐
- 既存 fast path は維持しつつ、余分な lock-path 初期化コストを削減

結果:
- `29ms -> 26ms` (`-10.3%`, `/tmp` fixture average)

## 検証

- `bats tests/unit/test_lesson_write.bats`
- `bats tests/unit/test_sync_lessons.bats`
- `bats tests/unit/test_inbox_write.bats`
- `bats tests/unit/test_report_template_gate_compat.bats`
