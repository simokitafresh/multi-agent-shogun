# 教訓注入品質分析 — 2026-06-05

## 契機

gate_lesson_health.sh ALERT: useful率25-30%(直近4-5cmd)。注入教訓の70%が「とは無関係」と回答される。

## 定量分析

lesson_impact.tsv全体: 20/73件 useful (27.4%)

### 0%有効教訓 (total≧3)

| ID | useful/total | 内容 | 根因 |
|----|-------------|------|------|
| L630 | 0/4 | bulletin_write.shのSCRIPT_DIRパス | target_files=cmd_save.sh→全cmd_save.shタスクに注入。内容が極端に限定的 |
| L548 | 0/3 | yaml.dump残存偵察 | deprecated: true だが修行タスクに注入される。タスクYAML再利用時にフィルタ効かず |

### パターン分析

not usefulの理由は一貫して「とは無関係で、今回は〇〇のため未使用」。

**根因**: 教訓の注入はtarget_files + tags + project のマッチングで行われるが、粒度が粗い。
- cmd_save.sh対象タスクにcmd_save.sh関連教訓が全て注入される → 大半が無関係
- tags(infra, bash, yaml)が広すぎる → 多くのinfraタスクにマッチ

### 構造的問題

| 問題 | 影響 | 対処案 |
|------|------|--------|
| target_files粒度粗い | L630等が全cmd_save.shタスクに注入 | effectiveness_score閾値(40%)で自動除外 |
| deprecated教訓が修行タスクに残存 | L548等が除外されずに注入 | 修行タスク再配備時のdeprecatedフィルタ確認 |
| 全体useful率27% | 忍者CTX消費の73%が無駄 | 上記2件対処で改善を計測 |

## 改善アクション

1. **L630の自動除外確認**: effectiveness_score閾値(40%)を下回るため、次回注入時に除外されるか計測
2. **修行タスクYAMLからL548を除去**: 根因はタスクYAML再利用時のdeprecatedフィルタ不在
3. **計測**: 次の5cmdで改善したuseful率を確認

## 因果リンク

- → [[LG027]] referenced率≠useful率
- → [[effectiveness_score]] cmd_2700で実装済みの除外メカニズム
- → [[教訓注入ALERT]] gate_lesson_health.sh
