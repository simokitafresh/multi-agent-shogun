# 知識効果メトリクス統合設計書
<!-- cmd: cmd_344 | author: saizo (integrate) | date: 2026-02-26 -->
<!-- sources: hayate(proposal_a), kagemaru(proposal_b), hanzo(proposal_c) -->

> 殿向け概要: 教訓注入→参照→成果の循環がどれだけ機能しているかを定量化するスクリプト設計。
> 判断ゼロ・決定論的・モデル非依存。入力=既存ログ+YAML、出力=7指標+補助データ。

## §1 3提案の収斂点・分岐点

### 収斂点（全員一致 — 設計の前提として採用）

| # | 収斂点 | A | B | C | 採用 |
|---|--------|---|---|---|------|
| S1 | タスクYAML/報告YAMLの上書き式がデータ永続性の致命的ギャップ | ✅ | ✅ | ✅ | 前提 |
| S2 | データ永続化(追記ログ)を先行実装すべき | ✅ | ✅ | ✅ | 前提 |
| S3 | gate_metrics.logが最も信頼性の高いデータソース(288行, cmd_158～) | ✅ | ✅ | ✅ | 前提 |
| S4 | 一発CLEAR率が最終CLEAR率より意味がある(生存バイアス回避) | ✅ | — | ✅ | 採用 |
| S5 | GATE CLEARの循環性(教訓確認=ゲート条件の一部→トートロジー) | ✅ | ✅ | ✅ | 前提 |
| S6 | 因果推論は不可能、Δは相関のみ | ✅ | ✅ | ✅ | 前提 |
| S7 | helpful_count=0+confirmed+7日超が未参照の実用的定義 | ✅ | — | ✅ | 採用 |

### 分岐点（統合判断）

| # | 分岐点 | A案 | B案 | C案 | **統合判断** | 根拠 |
|---|--------|-----|-----|-----|-------------|------|
| D1 | 永続化形式 | TSV(lesson_tracking.log) | TSV(lesson_injection.log) | CSV(2ファイル) | **TSV単一ファイル** | gate_metrics.logと同パターン。2ファイル分離は過剰 |
| D2 | 注入有無の判定 | project+lessons.yaml近似 | deploy_task.logパース | project+lessons.yaml近似 | **project+lessons.yaml近似**(デフォルト) | D3確認: project+lessonsあれば自動注入≒100%。logパースは検証用 |
| D3 | スクリプト構造 | Python inline | bash+Pythonヘルパー分離 | Python inline | **Python inline** | deploy_task.shと同パターン。ヘルパー分離はファイル数増加 |
| D4 | 交絡対策 | 測定限界明記 | task_type層別 | 移動窓Δ | **限界明記+PJ別+初回CLEAR** | 限界明記(A)が最も誠実。PJ別(B応用)で部分緩和。移動窓はN不足リスク |
| D5 | 成功率定義 | 最終+初回両方 | 最終のみ | 初回のみ | **両方出力、初回をΔ主指標** | 最終≈100%(生存バイアス)。初回が実質的差分。殿が両方見て判断 |
| D6 | 永続化の書込み箇所 | cmd_complete_gate.sh | deploy_task.sh | 両方 | **cmd_complete_gate.sh** | GATE判定時点で注入+参照の両データが揃う。1箇所で完結 |

## §2 データ永続化仕様

### lesson_tracking.tsv（新設）

**目的**: タスクYAML/報告YAMLの上書きで消失する教訓注入・参照データを永続化。

| 項目 | 仕様 |
|------|------|
| ファイル | `logs/lesson_tracking.tsv` |
| 形式 | TSV (タブ区切り, append-only) |
| 書込み | `cmd_complete_gate.sh` のGATE CLEAR/BLOCK判定直前 |
| 粒度 | 1行 = 1忍者 × 1cmd（同一cmdで複数忍者→複数行） |

**フィールド定義**:

```
timestamp	cmd_id	ninja	gate_result	injected_ids	referenced_ids
```

| フィールド | 型 | 説明 | 例 |
|-----------|-----|------|-----|
| timestamp | ISO8601 | 記録時刻 | `2026-02-26T03:00:00` |
| cmd_id | string | 親cmd ID | `cmd_344` |
| ninja | string | 忍者名 | `hayate` |
| gate_result | CLEAR\|BLOCK | 最終ゲート結果 | `CLEAR` |
| injected_ids | comma-separated | task.related_lessons[].id | `L001,L018,L033` |
| referenced_ids | comma-separated | report.lesson_referenced[] | `L001,L033` |

**例**:
```tsv
2026-02-26T03:00:00	cmd_344	hayate	CLEAR	L001,L018,L033	L001,L033
2026-02-26T03:00:00	cmd_344	hanzo	BLOCK	L012,L045
2026-02-26T03:05:00	cmd_345	saizo	CLEAR	L008,L009	L008
```

### 追記箇所: cmd_complete_gate.sh

GATE判定（L771〜L882）の直前、全チェック完了後・判定結果出力前に追記。
この時点でタスクYAML(related_lessons)と報告YAML(lesson_referenced)の両方がまだ上書きされていない。

```bash
# ─── lesson_tracking永続化（GATE判定直前） ───
TRACKING_LOG="$LOG_DIR/lesson_tracking.tsv"
GATE_RESULT="CLEAR"
[ "$ALL_CLEAR" != true ] && GATE_RESULT="BLOCK"
for task_file in "$TASKS_DIR"/*.yaml; do
    [ -f "$task_file" ] || continue
    grep -q "parent_cmd: ${CMD_ID}" "$task_file" 2>/dev/null || continue
    ninja_name=$(basename "$task_file" .yaml)
    report_file="$SCRIPT_DIR/queue/reports/${ninja_name}_report.yaml"
    python3 -c "
import yaml, sys
try:
    with open('$task_file') as f:
        td = yaml.safe_load(f)
    task = td.get('task', {}) if td else {}
    rl = task.get('related_lessons', [])
    injected = ','.join(l['id'] for l in rl if isinstance(l, dict) and 'id' in l) if rl else ''
    referenced = ''
    try:
        with open('$report_file') as f:
            rd = yaml.safe_load(f)
        lr = rd.get('lesson_referenced', []) if rd else []
        if lr and isinstance(lr, list):
            ids = []
            for item in lr:
                if isinstance(item, str): ids.append(item)
                elif isinstance(item, dict) and 'id' in item: ids.append(item['id'])
            referenced = ','.join(ids)
    except: pass
    if injected or referenced:
        from datetime import datetime
        ts = datetime.now().strftime('%Y-%m-%dT%H:%M:%S')
        print(f'{ts}\t${CMD_ID}\t$ninja_name\t${GATE_RESULT}\t{injected}\t{referenced}')
except: pass
" >> "$TRACKING_LOG" 2>/dev/null || true
done
```

**制約**: 判断ゼロ。injected/referencedが両方空の場合は行を出力しない（教訓無関係のcmd）。

## §3 7指標の最終設計

### 指標一覧

| # | 指標名 | 定義 | 主データソース | 精度 |
|---|--------|------|---------------|------|
| M1 | 注入率 | 教訓注入ありcmd / 全cmd | archive cmds + projects/ | 高（近似） |
| M2 | 参照率 | 参照教訓数 / 注入教訓数 | lesson_tracking.tsv（蓄積後） | 低→高 |
| M3 | 教訓あり一発CLEAR率 | 注入ありcmdの初回CLEAR / 注入ありcmd数 | gate_metrics.log + archive cmds | 高 |
| M4 | 教訓なし一発CLEAR率 | 注入なしcmdの初回CLEAR / 注入なしcmd数 | gate_metrics.log + archive cmds | 高 |
| M5 | Δ | M3 - M4 | M3, M4の導出 | M3/M4依存 |
| M6 | 成長率 | 新規教訓数 / 完了cmd数（期間） | lessons.yaml + gate_metrics.log | 高 |
| M7 | 未参照教訓リスト | helpful_count=0, confirmed, 7日超 | lessons.yaml | 中 |

### M1: 注入率

```
定義: 教訓注入ありcmd / 全完了cmd
データ: gate_metrics.logのユニークCLEAR cmd → archive cmdsのproject → projects/{pj}/lessons.yaml存在
計算:
  total = count(unique cmd_ids with at least one CLEAR in gate_metrics)
  with_lessons = count(cmd where project exists AND lessons.yaml has >=1 confirmed lesson)
  M1 = with_lessons / total
エッジケース:
  - テストcmd(cmd_test*, cmd_999): 除外
  - cancelled cmd: gate_metricsに記録なし→自動除外
  - 複数CLEAR: deduplicate(最初のCLEARのみ)
  - lessons.yaml空(confirmed 0件): 注入なし扱い
精度: 高。deploy_task.shはproject+lessons存在で自動注入(フォールバック含め≒100%)
```

### M2: 参照率

```
定義: 参照された教訓数 / 注入された教訓数（cmd単位平均）
データ:
  [現在] 計測不可 — タスクYAML/報告YAML上書きで消失
  [蓄積後] lesson_tracking.tsvのinjected_ids/referenced_idsから算出
  [暫定近似] lessons.yamlのhelpful_count>0割合 = 累積参照率
計算(蓄積後):
  per_cmd_rate = len(referenced_ids) / len(injected_ids)  # cmd×ninja単位
  M2 = mean(per_cmd_rate for all rows where injected_ids non-empty)
計算(暫定):
  confirmed = count(lessons where status=confirmed)
  ever_referenced = count(lessons where helpful_count>0 or last_referenced is not null)
  M2_approx = ever_referenced / confirmed
エッジケース:
  - injected_ids空: 分母0 → 除外
  - L055: lesson_referenced構造混在(str/dict) → 両方パース
  - 忍者が過剰申告の可能性 → 検証不可、信頼ベース
```

### M3: 教訓あり一発CLEAR率

```
定義: 教訓注入ありcmdのうち、初回ゲートでCLEARした割合
データ: gate_metrics.log(初回イベント) + archive cmds(project判定)
計算:
  with_lessons = set(cmd where project+lessons.yaml exists)
  first_clear = set(cmd where gate_events[cmd][0].result == 'CLEAR')
  M3 = len(with_lessons & first_clear) / len(with_lessons)
エッジケース:
  - 初回=gate_metrics.logの当該cmdの最初の行
  - テストcmd除外
  - cmdがgate未到達(cancelled): 自動除外
  - cmd_158以前: gate_metrics.log未記録→対象外
根拠(Cの知見):
  最終CLEAR率≈100%(BLOCK→修正→CLEAR)で無意味。
  初回CLEARは「教訓を事前に読んで手戻りなく完了できたか」の代理指標。
  循環性(S5)を部分回避。
```

### M4: 教訓なし一発CLEAR率

```
定義: M3の補集合。教訓注入なしcmdの初回CLEAR率。
データ: M3と同一データソースの逆条件。
計算:
  without_lessons = all_cmds - with_lessons
  M4 = len(without_lessons & first_clear) / len(without_lessons)
注意:
  - cmd_158以前は教訓システム未導入→全て「なし」。時間バイアス大。
  - 対策: --since オプションで期間制限（デフォルト: 教訓注入開始以降）
  - without_lessonsのN<10なら「N/A」と出力（統計的無意味）
```

### M5: Δ（効果差分）

```
定義: M3 - M4
計算: delta = M3 - M4
出力: Δ値 + N値(with/without) + 解釈ガイド
解釈ガイド(自動出力):
  Δ > 0: 教訓ありcmdの方が一発CLEAR率が高い（相関のみ、因果は不明）
  Δ ≈ 0: 差なし
  Δ < 0: 教訓なしcmdの方が高い（交絡の可能性大: タスク難易度差、時間トレンド等）
  N_without < 10: サンプル不足により統計的に信頼できない
```

### M6: 成長率

```
定義: 新規教訓数 / 完了cmd数（期間あたり）
データ: lessons.yamlのdateフィールド + gate_metrics.logのCLEAR timestamp
計算:
  # 全期間
  new_lessons = count(all confirmed lessons)
  completed_cmds = count(unique CLEAR cmd_ids)
  M6 = new_lessons / completed_cmds

  # 日別ローリング(7日窓)は--detailオプションで出力
エッジケース:
  - deprecated教訓: カウントから除外
  - merge統合された教訓: 統合後のIDでカウント(dateは元の登録日)
  - dateフィールドなし: 除外
```

### M7: 未参照教訓リスト

```
定義: 確定教訓のうち、一度も有効参照されていないもの
データ: lessons.yamlのhelpful_count, last_referenced, status, date
計算:
  unreferenced = [l for l in lessons
    if l.status == 'confirmed'
    and l.helpful_count == 0
    and l.last_referenced is null
    and age(l.date) >= 7]  # 7日猶予
出力: IDリスト + 件数 + 全confirmed中の割合
エッジケース:
  - 新規教訓(7日未満): 猶予期間中→除外
  - 注入されていない教訓: project=infraの場合、非infraタスクには注入されない
    → 「未参照」≠「無用」。注記を併記
  - harmful_count: 現在全0(cmd_339実装直後)。蓄積後にM7の精度向上
```

## §4 交絡因子と解釈限界

### 交絡因子

| # | 交絡因子 | 深刻度 | 緩和策 | 出典 |
|---|---------|--------|--------|------|
| C1 | タスク難易度バイアス(recon≠implement) | HIGH | PJ別Δ + task_type推定(cmd目的文grep) | A,B,C |
| C2 | 時間トレンド(インフラ成熟) | HIGH | --since制限 + 同一期間比較 | A,B,C |
| C3 | 選択バイアス(PJ間差異) | MEDIUM | PJ内Δを主指標 | B |
| C4 | GATE CLEARの循環性 | HIGH | 一発CLEAR率で部分回避 | A,C |
| C5 | 忍者のコンプライアンス(形式的参照) | MEDIUM | 計測不可。信頼ベース | B |
| C6 | 生存バイアス(BLOCK→修正→CLEAR) | CRITICAL | 一発CLEAR率で回避 | C |

### 解釈限界（殿向け注意書き — スクリプト出力に自動併記）

```
=== 解釈上の注意 ===
1. 因果推論は不可能: Δは「相関」であり「教訓が成功を引き起こした」証明ではない。
2. GATE CLEARの循環性: 教訓確認自体がゲート通過条件の一部であるため、
   「教訓あり→CLEAR率高い」は部分的にトートロジー。
   一発CLEAR率を主指標としてこの問題を緩和している。
3. サンプル選択バイアス: 教訓あり/なしcmdの母集団は異質
   （プロジェクト、時期、タスク種別が異なる）。
4. N_without < 10 の場合: 統計的に信頼できない。参考値として扱うこと。
5. 測定可能な問い: 「教訓注入ありcmdは手戻り(BLOCK→修正)が少ないか?」
```

## §5 スクリプト骨格: knowledge_metrics.sh

### 概要

| 項目 | 仕様 |
|------|------|
| パス | `scripts/knowledge_metrics.sh` |
| 言語 | bash + inline Python3 |
| 入力 | `logs/gate_metrics.log`, `queue/archive/cmds/`, `queue/shogun_to_karo.yaml`, `projects/*/lessons.yaml`, `logs/lesson_tracking.tsv`(存在時) |
| 出力 | 7指標 + 補助データ (stdout) |
| オプション | `--json`: JSON出力, `--since YYYY-MM-DD`: 期間制限, `--project PJ_ID`: PJ限定 |
| 制約 | 判断ゼロ・決定論的・モデル非依存・同一入力→同一出力 |

### 擬似コード

```bash
#!/bin/bash
# knowledge_metrics.sh — 知識効果メトリクス算出
# Usage: bash scripts/knowledge_metrics.sh [--json] [--since YYYY-MM-DD] [--project PJ_ID]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 引数パース
JSON_MODE=false
SINCE=""
PROJECT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --json) JSON_MODE=true; shift ;;
        --since) SINCE="$2"; shift 2 ;;
        --project) PROJECT="$2"; shift 2 ;;
        *) shift ;;
    esac
done

python3 -c "
import yaml, os, sys, json, re
from datetime import datetime, date
from collections import defaultdict

SCRIPT_DIR = '$SCRIPT_DIR'
SINCE = '$SINCE'
PROJECT_FILTER = '$PROJECT'
JSON_MODE = $( [ \"$JSON_MODE\" = true ] && echo True || echo False )

# ════════════════════════════════════════════
# Phase 1: データ読み込み
# ════════════════════════════════════════════

# 1a. gate_metrics.log → cmd別イベントリスト
gate_events = defaultdict(list)
gate_log = os.path.join(SCRIPT_DIR, 'logs/gate_metrics.log')
with open(gate_log) as f:
    for line in f:
        parts = line.strip().split('\t')
        if len(parts) < 3:
            continue
        ts, cmd_id, result = parts[0], parts[1], parts[2]
        reason = parts[3] if len(parts) > 3 else ''
        if 'test' in cmd_id.lower() or cmd_id == 'cmd_999':
            continue
        if SINCE and ts[:10] < SINCE:
            continue
        gate_events[cmd_id].append((ts, result, reason))

# 1b. archive cmds + shogun_to_karo → cmd定義(project)
cmd_project = {}
archive_dir = os.path.join(SCRIPT_DIR, 'queue/archive/cmds')
if os.path.isdir(archive_dir):
    for fname in os.listdir(archive_dir):
        if not fname.endswith('.yaml'):
            continue
        try:
            with open(os.path.join(archive_dir, fname)) as f:
                data = yaml.safe_load(f)
            cmds = data.get('commands', [data]) if isinstance(data, dict) else [data]
            for c in cmds:
                if isinstance(c, dict) and c.get('id', '').startswith('cmd_'):
                    cmd_project[c['id']] = c.get('project', '')
        except:
            pass

stk_path = os.path.join(SCRIPT_DIR, 'queue/shogun_to_karo.yaml')
try:
    with open(stk_path) as f:
        data = yaml.safe_load(f)
    for c in (data or {}).get('commands', []):
        cmd_project[c.get('id', '')] = c.get('project', '')
except:
    pass

# 1c. projects/*/lessons.yaml → 教訓マスタ
projects_dir = os.path.join(SCRIPT_DIR, 'projects')
project_has_lessons = {}  # pj_id → bool
all_lessons = {}          # lesson_id → lesson dict (with _project)
if os.path.isdir(projects_dir):
    for pdir in os.listdir(projects_dir):
        ppath = os.path.join(projects_dir, pdir)
        if not os.path.isdir(ppath):
            continue
        lpath = os.path.join(ppath, 'lessons.yaml')
        if not os.path.exists(lpath):
            project_has_lessons[pdir] = False
            continue
        try:
            with open(lpath) as f:
                ldata = yaml.safe_load(f)
            lessons = (ldata or {}).get('lessons', [])
            confirmed = [l for l in lessons
                         if str(l.get('status', 'confirmed')).lower() == 'confirmed']
            project_has_lessons[pdir] = len(confirmed) > 0
            for l in lessons:
                lid = l.get('id', '')
                if lid:
                    l['_project'] = pdir
                    all_lessons[lid] = l
        except:
            project_has_lessons[pdir] = False

# 1d. lesson_tracking.tsv（存在すれば）
tracking_data = []
tracking_path = os.path.join(SCRIPT_DIR, 'logs/lesson_tracking.tsv')
if os.path.exists(tracking_path):
    with open(tracking_path) as f:
        for line in f:
            parts = line.strip().split('\t')
            if len(parts) >= 6:
                tracking_data.append({
                    'ts': parts[0], 'cmd': parts[1], 'ninja': parts[2],
                    'result': parts[3],
                    'injected': [x for x in parts[4].split(',') if x],
                    'referenced': [x for x in parts[5].split(',') if x],
                })

# ════════════════════════════════════════════
# Phase 2: 指標算出
# ════════════════════════════════════════════

# 集合構築
all_cmds = set(gate_events.keys())
if PROJECT_FILTER:
    all_cmds = {c for c in all_cmds if cmd_project.get(c) == PROJECT_FILTER}

# 最終結果 / 初回結果
cmd_final = {}    # cmd → CLEAR or BLOCK
cmd_first = {}    # cmd → CLEAR or BLOCK
completed = set()
first_clear = set()

for cmd_id in all_cmds:
    events = gate_events[cmd_id]
    if not events:
        continue
    cmd_final[cmd_id] = events[-1][1]
    cmd_first[cmd_id] = events[0][1]
    if events[-1][1] == 'CLEAR':
        completed.add(cmd_id)
    if events[0][1] == 'CLEAR':
        first_clear.add(cmd_id)

# 教訓注入あり/なし分類
with_lessons = set()
without_lessons = set()
for cmd_id in completed:
    proj = cmd_project.get(cmd_id, '')
    if proj and project_has_lessons.get(proj, False):
        with_lessons.add(cmd_id)
    else:
        without_lessons.add(cmd_id)

total = len(completed)
n_with = len(with_lessons)
n_without = len(without_lessons)

# (M1) 注入率
M1 = n_with / total if total > 0 else 0

# (M2) 参照率
if tracking_data:
    ref_rates = []
    for row in tracking_data:
        if row['injected']:
            rate = len(row['referenced']) / len(row['injected'])
            ref_rates.append(rate)
    M2 = sum(ref_rates) / len(ref_rates) if ref_rates else 0
    M2_source = 'tracking'
    M2_n = len(ref_rates)
else:
    total_confirmed = sum(1 for l in all_lessons.values()
                          if str(l.get('status','confirmed')).lower() == 'confirmed')
    ever_ref = sum(1 for l in all_lessons.values()
                   if l.get('helpful_count', 0) > 0 or l.get('last_referenced'))
    M2 = ever_ref / total_confirmed if total_confirmed > 0 else 0
    M2_source = 'approx(helpful_count)'
    M2_n = total_confirmed

# (M3) 教訓あり一発CLEAR率
fc_with = len(first_clear & with_lessons)
M3 = fc_with / n_with if n_with > 0 else 0

# (M4) 教訓なし一発CLEAR率
fc_without = len(first_clear & without_lessons)
M4 = fc_without / n_without if n_without > 0 else 0

# (M5) Δ
M5 = M3 - M4
M5_reliable = n_without >= 10

# (M6) 成長率
total_confirmed_lessons = sum(1 for l in all_lessons.values()
    if str(l.get('status','confirmed')).lower() == 'confirmed')
deprecated_count = sum(1 for l in all_lessons.values()
    if str(l.get('status','')).lower() == 'deprecated')
M6 = total_confirmed_lessons / total if total > 0 else 0

# (M7) 未参照教訓リスト
today = date.today()
unreferenced = []
for lid, l in all_lessons.items():
    if str(l.get('status','confirmed')).lower() != 'confirmed':
        continue
    if l.get('helpful_count', 0) > 0 or l.get('last_referenced'):
        continue
    d = str(l.get('date', ''))[:10]
    try:
        ld = datetime.fromisoformat(d).date() if d else today
        age = (today - ld).days
    except:
        age = 0
    if age >= 7:
        unreferenced.append({
            'id': lid,
            'title': str(l.get('title', ''))[:60],
            'age_days': age,
            'project': l.get('_project', '?')
        })
unreferenced.sort(key=lambda x: x['id'])

# (bonus) 最終CLEAR率(参考値)
final_with = sum(1 for c in with_lessons if cmd_final.get(c) == 'CLEAR')
final_rate_with = final_with / n_with if n_with > 0 else 0
final_without = sum(1 for c in without_lessons if cmd_final.get(c) == 'CLEAR')
final_rate_without = final_without / n_without if n_without > 0 else 0

# ════════════════════════════════════════════
# Phase 3: 出力
# ════════════════════════════════════════════

result = {
    'period': {
        'from': min(e[0][0][:10] for e in gate_events.values()) if gate_events else 'N/A',
        'to': max(e[-1][0][:10] for e in gate_events.values()) if gate_events else 'N/A',
    },
    'total_cmds': total,
    'M1_injection_rate': round(M1, 3),
    'M1_n': {'with': n_with, 'without': n_without},
    'M2_reference_rate': round(M2, 3),
    'M2_source': M2_source,
    'M2_n': M2_n,
    'M3_first_clear_with': round(M3, 3),
    'M3_n': {'cleared': fc_with, 'total': n_with},
    'M4_first_clear_without': round(M4, 3),
    'M4_n': {'cleared': fc_without, 'total': n_without},
    'M5_delta': round(M5, 3),
    'M5_reliable': M5_reliable,
    'M6_growth_rate': round(M6, 3),
    'M6_n': {'lessons': total_confirmed_lessons, 'cmds': total},
    'M7_unreferenced': unreferenced,
    'M7_count': len(unreferenced),
    'M7_total_confirmed': sum(1 for l in all_lessons.values()
        if str(l.get('status','confirmed')).lower() == 'confirmed'),
    'bonus_final_clear_with': round(final_rate_with, 3),
    'bonus_final_clear_without': round(final_rate_without, 3),
}

if JSON_MODE:
    print(json.dumps(result, indent=2, ensure_ascii=False))
else:
    p = result['period']
    print(f'=== 知識効果メトリクス ({p[\"from\"]} ~ {p[\"to\"]}) ===')
    print(f'対象cmd数: {total} (CLEAR到達)')
    print()
    print(f'(M1) 注入率:          {M1:.1%} ({n_with}/{total})')
    print(f'(M2) 参照率({M2_source}): {M2:.1%} (N={M2_n})')
    print(f'(M3) 教訓あり一発CLEAR: {M3:.1%} ({fc_with}/{n_with})')
    print(f'(M4) 教訓なし一発CLEAR: {M4:.1%} ({fc_without}/{n_without})')
    delta_note = '' if M5_reliable else ' ⚠N_without<10'
    print(f'(M5) Δ(効果差分):     {M5:+.1%}{delta_note}')
    print(f'(M6) 成長率:          {M6:.2f} lessons/cmd')
    print(f'(M7) 未参照教訓:      {len(unreferenced)}/{result[\"M7_total_confirmed\"]}')
    print()
    if unreferenced:
        print('未参照教訓(7日超):')
        for u in unreferenced:
            print(f'  {u[\"id\"]} [{u[\"project\"]}] {u[\"title\"]} ({u[\"age_days\"]}日)')
        print()
    print(f'--- 参考: 最終CLEAR率 with={final_rate_with:.1%} without={final_rate_without:.1%} ---')
    print()
    print('=== 解釈上の注意 ===')
    print('1. Δは相関のみ。因果推論は不可能（RCT未実施）')
    print('2. GATE CLEARの循環性あり。一発CLEAR率で部分緩和')
    print('3. 教訓あり/なしの母集団は異質（PJ・時期・難易度が異なる）')
    if not M5_reliable:
        print(f'4. ⚠ N_without={n_without} < 10: サンプル不足。Δは参考値')
"
```

## §6 実装ロードマップ（decision_candidate）

| Phase | 内容 | コスト | 効果 |
|-------|------|--------|------|
| Phase 1 | lesson_tracking.tsv追記をcmd_complete_gate.shに追加 | 低(20行) | 将来データ蓄積即開始 |
| Phase 2 | knowledge_metrics.sh作成(§5の骨格を実装) | 中(1ファイル) | 既存データで即座にM1/M3/M4/M5/M6/M7出力 |
| Phase 3 | lesson_tracking.tsv蓄積後にM2を正確化 | なし(Phase2のコード内に条件分岐済み) | M2精度向上 |

**推奨**: Phase 1+2を同時実装（Aの推奨Cと同じ結論）。Phase 1は既存ロジック変更なし・追記のみで低リスク。

### decision_candidate

```yaml
title: "Phase 1(永続化)+Phase 2(スクリプト)の同時実装を承認するか"
options:
  - id: A
    label: "Phase 1+2同時実装（推奨）"
    pros: "即座に既存データ指標 + 今後のデータ蓄積。Phase 1は20行追記で低リスク"
    cons: "実装コスト中（ただしスクリプト骨格はこの設計書で完成済み）"
  - id: B
    label: "Phase 1のみ先行"
    pros: "最小変更。データ蓄積だけ開始"
    cons: "メトリクス出力は後日"
  - id: C
    label: "Phase 2のみ先行"
    pros: "既存データで即座にメトリクス確認"
    cons: "M2(参照率)はapprox止まり"
recommendation: "A — Phase 1は追記のみで低リスク、Phase 2の骨格はこの設計書で完成済み"
```
