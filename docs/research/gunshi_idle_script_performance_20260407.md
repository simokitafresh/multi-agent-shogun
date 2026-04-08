# Script Performance Bottleneck Analysis — 2026-04-07

## 計測環境
- WSL2 Linux 6.6.87.1 on /mnt/c/ (NTFS over 9P)
- Cold cache = 初回実行, Warm cache = 2回目以降

## ボトルネック特定結果

### Tier 1: 重大ボトルネック（cold 10s超）

| スクリプト | Cold | Warm | 原因 |
|-----------|------|------|------|
| `gate_shogun_startup.sh` | 14.8s | 5.0s | Gate 15 orphan git log + sub-gate合計 |
| `dashboard_auto_section.sh` | 12.1s | 3.3s | ci_status_check(GH API) + knowledge_metrics |

### Tier 2: 軽微（<1s）

| スクリプト | 時間 | 備考 |
|-----------|------|------|
| `gate_karo_startup.sh` | 0.55s | 許容範囲 |
| `gate_gunshi_startup.sh` | 0.47s | 許容範囲 |
| `inbox_write.sh` | 0.23s | 高頻度。flock + NTFS write |
| `gate_loop_health.sh` | 0.20s | OK |
| `gate_shogun_memory.sh` | 0.19s | OK |
| `ntfy.sh` | 0.05s | OK |
| `gate_report_format.sh` | 0.01s | OK |

### Tier 3: 正常（<0.01s）

deploy_task.sh(引数なし), inbox count, snapshot read, karo_workaround read等

## 根因分析

### gate_shogun_startup.sh 内訳

| セクション | 時間(ms) | 備考 |
|-----------|----------|------|
| gate_shogun_memory.sh | 206 | 参照ファイル47件実在チェック |
| gate_lesson_health.sh | 719 | 5PJ×lesson集計 |
| gate_loop_health.sh | 179 | gate_fire_log awk |
| gate_p_average_freshness.sh | 17 | 軽量 |
| **Gate 15: orphan git log** | **3400-4300** | **最大ボトルネック** |
| git status scripts/ | 273 | NTFS git |
| evolution kmap grep x41 | 138 | context/ 41ファイル |
| その他inline | ~500 | 各種grep/awk |

**Gate 15 (進化検知) の `git log -1 --format='%an' -- context/{orphan}.md`**:
- WSL2 NTFS上のgit log 1回 = 0.26s(warm) ~ 4.3s(cold)
- orphanが1件でも3-4s消費
- causal_chain: NTFS 9P低速I/O → git index scan遅延 → 1ファイル毎git呼出し → cold cacheで爆発

### dashboard_auto_section.sh 内訳

| サブスクリプト | 時間 | 備考 |
|---------------|------|------|
| **ci_status_check.sh** | **1816ms** | **GitHub API network call** |
| knowledge_metrics.sh | 602ms | gate_metrics.log awk集計 |
| context_freshness_check.sh | 114ms | キャッシュあり |
| model_analysis.sh | 77ms | 軽量 |

ci_status/knowledge_metricsは並列実行(background &)だが、wait時にmax(1.8, 0.6)=1.8sブロック。
TTLキャッシュ(60s/120s)あり。連続実行は高速だが初回は遅い。

**追加発見（bash -x トレース）**: 6忍者ループの各イテレーションが1.2-1.6s。
task YAML読取(awk)がNTFS上で毎忍者1.2-1.6sかかる。6忍者で合計7-10s。
これがcold cache時の12.1sの主因。サブスクリプト(ci_status等)は並列で隠れるが、
メインループのNTFS逐次読取は隠せない。

## 改善提案

### P1: Gate 15 orphan git log → バッチ化 (推定改善: -3s)
現在: orphan 1件毎に `git log -1 --format='%an' -- context/{file}` (0.26-4.3s/件)
提案: 全context/ authorを1回の `git log` で一括取得してキャッシュ
```bash
# 例: 全context/*.mdのlast authorを1回で取得
git log --all --diff-filter=ACRM --name-only --format='AUTHOR:%an' -- 'context/*.md' \
  | awk '/^AUTHOR:/{a=substr($0,8)} /^context\//{if(!seen[$0]++){print $0"\t"a}}'
```
効果: git呼出し回数 N→1。WSL2 NTFS上では劇的改善

### P2: ci_status_check TTLキャッシュ延長 (推定改善: -1.5s初回回避)
現在: 60s TTL。起動時はほぼ毎回cold hit
提案: 起動gate呼び出し時はTTL 300sに延長（ダッシュボード更新とCI確認は独立）

### P3: dashboard忍者ループ一括読取 (推定改善: -5s cold)
現在: 6忍者×個別awk呼出し(各1.2-1.6s on NTFS)
提案: task YAML 6ファイルを1回のcatで結合→1回のawkで全忍者分パース
```bash
# 例: 全task YAMLを結合して1パスで処理
cat queue/tasks/*.yaml | awk '/^task:/{...}' # 1回のI/Oで6忍者分取得
```
効果: NTFS read回数 6→1。cold cache時の7-10sを1-2sに削減

### P4: gate_shogun_startup BRIEFモード活用
`BRIEF=true bash scripts/gates/gate_shogun_startup.sh` で出力を抑制。
ただしGate 15のgit logは出力有無に関係なく実行される。

## トークン消費について

スクリプト自体はLLMトークンを消費しない（bash上実行）。
ただしBashツールの出力結果がCTXに注入されるため:
- gate_shogun_startup出力: ~80行 → CTX消費
- gate_gunshi_startup出力: ~50行 → CTX消費
- **verbose出力の長いスクリプトは間接的にCTX圧迫要因**

改善: 正常時は1行サマリのみ出力し、ALERT時のみ詳細展開する設計に変更可能。
