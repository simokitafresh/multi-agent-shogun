# インフラバグ調査: universal教訓過剰注入 + commit hash検証不在

日付: 2026-04-30
軍師idle自走 — LG014「忍者ミス=インフラ真因を疑え」適用

## バグ1: universal教訓の過剰注入

### 症状
知識辞書cmd(dm-signal, 論文精読)にinfra系教訓(L503-L512)が注入。忍者全件useful:false。

### 根因
deploy_task.sh L2399-2402:
```python
if 'universal' in l_tags:
    universal_lessons.append(lesson)
    continue  # プロジェクトスコープチェックなし
```
Platform教訓(infra)は L2130-2140で無条件読み込み。universalタグ→全cmdに注入。

### 欠落フィルタ
- プロジェクトスコープ: universal教訓にも`target_projects`チェックが必要
- タスク型スコープ: infra最適化系教訓は`recon/impl`タスクにのみ適用すべき

### 影響
- 忍者CTX消費(10件のuseless教訓を読む時間)
- useful:false量産→lesson_impact.tsvのノイズ増加
- useful_rate低下→gate_lesson_health.shの閾値に影響(LG027再発リスク)

### 修正方向
(1) L503-L512のtags: [universal]→[infra, performance]に変更(最小修正)
(2) deploy_task.shにuniversal教訓のproject scopeチェック追加(構造的修正)

## バグ2: commit hash自動検証の不在

### 症状
hayate cmd_2427: commit hash=2bc6149bと報告→DM-Signalリポに不在。実際は047bd13d。

### 根因
- report_field_set.sh: commit hashを自動取得するロジックなし。忍者の手動記入に完全依存
- gate_gunshi_report_precheck.sh: commit存在検証なし(PRE3はproject dir未検出でSKIP)
- 外部リポジトリのcommit validation機構が皆無

### 修正方向
(1) PRE3のcommit検証をDM-Signalリポにも拡張(GP-238のfallbackと同様)
(2) 報告のresult.details/summaryからcommit hashを抽出→git show --quiet で実在検証
