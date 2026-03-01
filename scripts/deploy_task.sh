#!/bin/bash
# deploy_task.sh — タスク配備ヘルパー（忍者状態自動検知付き）
# Usage: bash scripts/deploy_task.sh <ninja_name> [message] [type] [from]
# Example: bash scripts/deploy_task.sh hanzo "タスクYAMLを読んで作業開始せよ" task_assigned karo
#
# 機能:
#   1. 対象忍者のCTX%とidle状態を自動検知
#   2. CTX:0%(clear済み) → プロンプト準備を確認してから起動
#   3. CTX>0%(通常) → そのままinbox_writeで通知
#   4. 動作ログを記録
#
# cmd_102: 殿の哲学「人が従う」ではなく「仕組みが強制する」

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$SCRIPT_DIR/logs/deploy_task.log"

# cli_lookup.sh — CLI Profile SSOT参照（CLI種別判定・パターン取得）
source "$SCRIPT_DIR/scripts/lib/cli_lookup.sh"
source "$SCRIPT_DIR/scripts/lib/field_get.sh"
source "$SCRIPT_DIR/scripts/lib/yaml_field_set.sh"

NINJA_NAME="${1:-}"
DEFAULT_MESSAGE="タスクYAMLを読んで作業開始せよ。"
MESSAGE="${2:-$DEFAULT_MESSAGE}"
TYPE="${3:-task_assigned}"
FROM="${4:-karo}"

if [ -z "$NINJA_NAME" ]; then
    echo "Usage: deploy_task.sh <ninja_name> [message] [type] [from]" >&2
    echo "例1: deploy_task.sh sasuke" >&2
    echo "例2: deploy_task.sh sasuke \"タスクYAMLを読んで作業開始せよ\" task_assigned karo" >&2
    echo "受け取った引数: $*" >&2
    exit 1
fi

if [[ "$NINJA_NAME" == cmd_* ]]; then
    echo "ERROR: 第1引数はninja_name（例: hanzo, sasuke）。cmd_idではない。" >&2
    echo "Usage: deploy_task.sh <ninja_name> [message] [type] [from]" >&2
    echo "例1: deploy_task.sh sasuke" >&2
    echo "例2: deploy_task.sh sasuke \"タスクYAMLを読んで作業開始せよ\" task_assigned karo" >&2
    echo "受け取った引数: $*" >&2
    exit 1
fi

mkdir -p "$SCRIPT_DIR/logs"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEPLOY] $1" >> "$LOG"
    echo "[DEPLOY] $1" >&2
}

# ─── ペインターゲット解決 ───
resolve_pane() {
    local name="$1"
    # ninja_states.yamlから取得（ninja_monitorが定期更新）
    local pane
    pane=$(python3 -c "
import yaml, sys
try:
    with open('$SCRIPT_DIR/logs/ninja_states.yaml') as f:
        data = yaml.safe_load(f)
    ninja = data.get('ninjas', {}).get('$name', {})
    print(ninja.get('pane', ''))
except:
    pass
" 2>/dev/null)

    if [ -n "$pane" ]; then
        echo "$pane"
        return 0
    fi

    # フォールバック: 既知のペインマッピング
    case "$name" in
        karo)     echo "shogun:agents.1" ;;
        sasuke)   echo "shogun:agents.2" ;;
        kirimaru) echo "shogun:agents.3" ;;
        hayate)   echo "shogun:agents.4" ;;
        kagemaru) echo "shogun:agents.5" ;;
        hanzo)    echo "shogun:agents.6" ;;
        saizo)    echo "shogun:agents.7" ;;
        kotaro)   echo "shogun:agents.8" ;;
        tobisaru) echo "shogun:agents.9" ;;
        *) echo "" ;;
    esac
}

# ─── CTX%取得（cli_profiles.yaml経由でCLI種別に応じたパターンを取得） ───
get_ctx_pct() {
    local pane_target="$1"
    local ctx_num

    # Source 1: tmux pane variable
    ctx_num=$(tmux show-options -p -t "$pane_target" -v @context_pct 2>/dev/null | grep -oE '[0-9]+' | tail -1)
    if [ -n "$ctx_num" ] 2>/dev/null; then
        echo "$ctx_num"
        return 0
    fi

    # Source 2: capture-pane + cli_profiles.yamlのパターン
    local output
    output=$(tmux capture-pane -t "$pane_target" -p -S -5 2>/dev/null)

    local ctx_pattern ctx_mode
    ctx_pattern=$(cli_profile_get "$NINJA_NAME" "ctx_pattern")
    ctx_mode=$(cli_profile_get "$NINJA_NAME" "ctx_mode")

    if [ -n "$ctx_pattern" ]; then
        ctx_num=$(echo "$output" | grep -oE "$ctx_pattern" | tail -1 | grep -oE '[0-9]+')
        if [ -n "$ctx_num" ]; then
            if [ "$ctx_mode" = "remaining" ]; then
                echo $((100 - ctx_num))
            else
                echo "$ctx_num"
            fi
            return 0
        fi
    fi

    echo "0"
}

# ─── idle検知（cli_profiles.yaml経由でBUSY/IDLEパターンを取得） ───
check_idle() {
    local pane_target="$1"

    # Source 1: @agent_state変数
    local state
    state=$(tmux show-options -p -t "$pane_target" -v @agent_state 2>/dev/null)
    if [ "$state" = "idle" ]; then
        return 0
    elif [ -n "$state" ] && [ "$state" != "idle" ]; then
        return 1
    fi

    # Source 2: capture-pane フォールバック
    local output
    output=$(tmux capture-pane -t "$pane_target" -p -S -5 2>/dev/null)

    # cli_profiles.yaml経由でBUSY/IDLEパターンを取得
    local busy_raw idle_pattern
    busy_raw=$(cli_profile_get "$NINJA_NAME" "busy_patterns")
    idle_pattern=$(cli_profile_get "$NINJA_NAME" "idle_pattern")

    # BUSYパターン（cli_lookupはリストをパイプ区切りで返す → grep -E の alternation として使用）
    if [ -n "$busy_raw" ] && echo "$output" | grep -qE "$busy_raw"; then
        return 1
    fi

    # IDLEパターン: プロンプト表示
    if [ -n "$idle_pattern" ] && echo "$output" | tail -3 | grep -qF "$idle_pattern"; then
        return 0
    fi

    return 1  # デフォルト: BUSY（安全側）
}


# ─── task_id自動注入（cmd_465: STALL検知キー統一） ───
# subtask_idの値をtask_idとして注入。ninja_monitor check_stall()がtask_idを参照するため必須。
inject_task_id() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "inject_task_id: task file not found: $task_file"
        return 1
    fi

    local subtask_id
    subtask_id=$(field_get "$task_file" "subtask_id" "")
    if [ -z "$subtask_id" ]; then
        log "inject_task_id: no subtask_id found, skipping"
        return 0
    fi

    local existing_task_id
    existing_task_id=$(field_get "$task_file" "task_id" "")
    if [ -n "$existing_task_id" ] && [ "$existing_task_id" != "idle" ]; then
        log "inject_task_id: task_id already set ($existing_task_id), skipping"
        return 0
    fi

    yaml_field_set "$task_file" "task" "task_id" "$subtask_id"
    log "inject_task_id: set task_id=$subtask_id"
}

# ─── 報告YAML雛形生成（cmd_138: lesson_candidate欠落防止） ───
generate_report_template() {
    local ninja_name="$1"
    local task_id="$2"
    local parent_cmd="$3"
    local project="$4"
    local task_file="$SCRIPT_DIR/queue/tasks/${ninja_name}.yaml"
    local report_file=""

    # report_filenameフィールドを優先参照（cmd_412: 命名ミスマッチ根治）
    local report_filename=""
    report_filename=$(field_get "$task_file" "report_filename" "")

    if [ -n "$report_filename" ]; then
        report_file="$SCRIPT_DIR/queue/reports/${report_filename}"
    elif [[ -n "$parent_cmd" && "$parent_cmd" == cmd_* ]]; then
        report_file="$SCRIPT_DIR/queue/reports/${ninja_name}_report_${parent_cmd}.yaml"
    else
        # 後方互換: parent_cmdが未設定/不正なら旧形式にフォールバック
        report_file="$SCRIPT_DIR/queue/reports/${ninja_name}_report.yaml"
    fi

    mkdir -p "$SCRIPT_DIR/queue/reports"

    # 冪等性: 既存テンプレートがあればスキップ（L060: 上書き防止）
    if [ -f "$report_file" ]; then
        log "report_template: already exists, skipping (${report_file})"
        return 0
    fi

    cat > "$report_file" <<EOF
worker_id: ${ninja_name}
task_id: ${task_id}
parent_cmd: ${parent_cmd}
timestamp: ""
status: pending
result:
  summary: ""
  details: ""
purpose_validation:
  cmd_purpose: ""
  fit: true
  purpose_gap: ""
files_modified: []
lesson_candidate:
  found: false
  title: ""
  detail: ""
  project: ${project}
lessons_useful: []
skill_candidate:
  found: false
decision_candidate:
  found: false
EOF

    log "report_template: generated (${report_file})"
}

# ─── 教訓自動注入（task YAMLにrelated_lessonsを挿入） ───
# cmd_349: タグマッチによる選択的教訓注入
inject_related_lessons() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "inject_lessons: task file not found: $task_file"
        return 0
    fi

    python3 -c "
import yaml, sys, os, re, tempfile, random, datetime

task_file = '$task_file'
script_dir = '$SCRIPT_DIR'

DEDUP_THRESHOLD = 0.25

def tech_terms(text):
    '''技術用語のみ抽出（日本語テキスト対応）'''
    text = str(text)
    terms = set()
    terms.update(w.lower() for w in re.findall(r'[a-zA-Z_][a-zA-Z0-9_\\.]{2,}', text))
    terms.update(w.lower() for w in re.findall(r'L\\d{2,3}', text))
    terms.update(w.lower() for w in re.findall(r'\\.[a-z]{1,4}', text))
    return terms

def jaccard(set_a, set_b):
    if not set_a or not set_b:
        return 0.0
    return len(set_a & set_b) / len(set_a | set_b)

def greedy_dedup(scored_list, all_lessons, threshold=DEDUP_THRESHOLD):
    accepted = []
    accepted_terms = []
    deduped_count = 0
    for score, lid, summary in scored_list:
        lesson = all_lessons.get(lid, {})
        l_text = f'{lesson.get(\"title\",\"\")} {lesson.get(\"summary\",\"\")} {lesson.get(\"content\",\"\")}'
        terms = tech_terms(l_text)
        is_dup = False
        for acc_terms in accepted_terms:
            if jaccard(terms, acc_terms) >= threshold:
                is_dup = True
                break
        if is_dup:
            deduped_count += 1
            continue
        accepted.append((score, lid, summary))
        accepted_terms.append(terms)
    if deduped_count > 0:
        print(f'[INJECT] dedup: removed {deduped_count} similar lessons (threshold={threshold})', file=sys.stderr)
    return accepted

try:
    with open(task_file) as f:
        data = yaml.safe_load(f)

    if not data or 'task' not in data:
        print('[INJECT] No task section in YAML, skipping', file=sys.stderr)
        sys.exit(0)

    task = data['task']
    project = task.get('project', '')

    if not project:
        task['related_lessons'] = []
        tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
        try:
            with os.fdopen(tmp_fd, 'w') as f:
                yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
            os.replace(tmp_path, task_file)
        except:
            os.unlink(tmp_path)
            raise
        print('[INJECT] No project field, set related_lessons: []', file=sys.stderr)
        sys.exit(0)

    lessons_path = os.path.join(script_dir, 'projects', project, 'lessons.yaml')
    lessons = []
    if os.path.exists(lessons_path):
        with open(lessons_path) as f:
            lessons_data = yaml.safe_load(f)
        lessons = lessons_data.get('lessons', []) if lessons_data else []
    else:
        print(f'[INJECT] WARN: lessons.yaml not found for project={project}', file=sys.stderr)

    # ═══ Platform教訓の追加読み込み ═══
    projects_yaml_path = os.path.join(script_dir, 'config', 'projects.yaml')
    platform_count = 0
    if os.path.exists(projects_yaml_path):
        try:
            with open(projects_yaml_path) as pf:
                pdata = yaml.safe_load(pf)
            for pj in (pdata or {}).get('projects', []):
                if pj.get('type') == 'platform' and pj.get('id') != project:
                    plat_path = os.path.join(script_dir, 'projects', pj['id'], 'lessons.yaml')
                    if os.path.exists(plat_path):
                        with open(plat_path) as plf:
                            plat_data = yaml.safe_load(plf)
                        plat_lessons = plat_data.get('lessons', []) if plat_data else []
                        platform_count += len(plat_lessons)
                        lessons.extend(plat_lessons)
        except Exception as pe:
            print(f'[INJECT] WARN: platform lessons load failed: {pe}', file=sys.stderr)

    if not lessons:
        task['related_lessons'] = []
        tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
        try:
            with os.fdopen(tmp_fd, 'w') as f:
                yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
            os.replace(tmp_path, task_file)
        except:
            os.unlink(tmp_path)
            raise
        print(f'[INJECT] No lessons for project={project} (including platform)', file=sys.stderr)
        sys.exit(0)

    # Build task text for keyword extraction
    title = task.get('title', '')
    description = task.get('description', '')
    ac_list = task.get('acceptance_criteria', [])
    if isinstance(ac_list, list):
        ac_text = ' '.join(str(a.get('description', '')) if isinstance(a, dict) else str(a) for a in ac_list)
    else:
        ac_text = str(ac_list or '')
    task_text = f'{title} {description} {ac_text}'

    # Extract keywords: split by non-word chars, exclude <=3 chars, lowercase, dedup
    words = re.split(r'[^a-zA-Z0-9_\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FFF]+', task_text)
    keywords = list(set(w.lower() for w in words if len(w) > 3))

    # ═══ タグマッチ: タスクタグの決定 ═══
    # (1) タスクYAMLにtagsフィールドがあればそれを使用
    task_tags = task.get('tags', [])
    if isinstance(task_tags, str):
        task_tags = [task_tags]
    task_tags = [str(t).lower().strip() for t in task_tags if t]

    # (2) tagsがなければtitle+descriptionからキーワード推定 (AC2: config/lesson_tags.yaml辞書参照)
    tag_inferred = False
    if not task_tags:
        # (AC2-b) config/lesson_tags.yamlを読み込んでtag_rulesを動的構築
        tags_yaml_path = os.path.join(script_dir, 'config', 'lesson_tags.yaml')
        tag_rules = []
        if os.path.exists(tags_yaml_path):
            try:
                with open(tags_yaml_path, encoding='utf-8') as tf:
                    tdata = yaml.safe_load(tf)
                for rule in (tdata or {}).get('tag_rules', []):
                    tag = rule.get('tag', '')
                    patterns = rule.get('patterns', [])
                    if tag and patterns:
                        for pat in patterns:
                            tag_rules.append((pat, tag))
            except Exception:
                tag_rules = []

        # (AC2-c) 辞書ファイル不在時のフォールバック: 従来のハードコード値
        if not tag_rules:
            tag_rules = [
                (r'(?i)db|database|SQL|PostgreSQL', 'db'),
                (r'(?i)api|endpoint|request|response|Render', 'api'),
                (r'(?i)frontend|ui|css|react|component', 'frontend'),
                (r'(?i)deploy|本番|render|環境', 'deploy'),
                (r'(?i)pipeline|batch|cron|scheduler', 'pipeline'),
                (r'(?i)test|検証|parity|backtest', 'testing'),
                (r'(?i)review|査読|レビュー', 'review'),
                (r'(?i)recon|偵察|調査|分析', 'recon'),
                (r'(?i)process|手順|運用|workflow', 'process'),
                (r'(?i)通信|報告|inbox|notification', 'communication'),
                (r'(?i)gate|門番|block|clear', 'gate'),
            ]

        for pattern, tag in tag_rules:
            if re.search(pattern, task_text):
                task_tags.append(tag)
        if task_tags:
            tag_inferred = True
            # AC1: タグ推定数上限max 3 — マッチ回数スコア上位3個を採用
            if len(task_tags) > 3:
                tag_match_count = {}
                for pat, t in tag_rules:
                    if t in task_tags:
                        tag_match_count[t] = len(re.findall(pat, task_text))
                task_tags = sorted(set(task_tags), key=lambda t: -tag_match_count.get(t, 0))[:3]

    # Keep only active lessons: status=confirmed or undefined (default=confirmed)
    confirmed_lessons = []
    filtered_draft = 0
    filtered_deprecated = 0
    for lesson in lessons:
        l_status = str(lesson.get('status', 'confirmed')).lower()
        if l_status == 'deprecated':
            filtered_deprecated += 1
            continue
        if lesson.get('deprecated', False):
            filtered_deprecated += 1
            continue
        if l_status != 'confirmed':
            filtered_draft += 1
            continue
        confirmed_lessons.append(lesson)

    # ═══ タグマッチ: 教訓をフィルタ ═══
    # universal教訓は別管理（常に注入）
    universal_lessons = []
    tag_candidates = []

    for lesson in confirmed_lessons:
        l_tags = lesson.get('tags', [])
        if isinstance(l_tags, str):
            l_tags = [l_tags]
        l_tags = [str(t).lower().strip() for t in l_tags if t]

        # universal教訓は常に注入対象
        if 'universal' in l_tags:
            universal_lessons.append(lesson)
            continue

        # 教訓にtagsがない場合（旧フォーマット）→常にスコアリング候補に含める（後方互換）
        if not l_tags:
            tag_candidates.append(lesson)
            continue

        # task_tagsが決定済みの場合、タグ重複チェック
        if task_tags:
            overlap = set(task_tags) & set(l_tags)
            if overlap:
                tag_candidates.append(lesson)
        # task_tagsが空（推定もできなかった）→全教訓注入（安全側フォールバック）
        else:
            tag_candidates.append(lesson)

    # (5) タスクにtagsがなくキーワード推定もできない → 全教訓注入（現行動作=安全側フォールバック）
    if not task_tags:
        tag_candidates = [l for l in confirmed_lessons if l not in universal_lessons]

    # ═══ スコアリング: タグマッチ候補内でキーワードスコア順位付け ═══
    scored = []
    for lesson in tag_candidates:
        lid = lesson.get('id', '')
        l_title = str(lesson.get('title', ''))
        l_summary = str(lesson.get('summary', ''))
        l_content = str(lesson.get('content', ''))
        l_source = str(lesson.get('source', ''))

        title_text = l_title.lower()
        other_text = f'{l_summary} {l_content} {l_source}'.lower()

        score = 0
        for kw in keywords:
            if kw in title_text:
                score += 3
            elif kw in other_text:
                score += 1

        if score > 0:
            scored.append((score, lid, l_summary or l_title))

    # Sort by score descending, take top 7 (AC5: task-specific max 7)
    scored.sort(key=lambda x: -x[0])

    # Greedy dedup: 類似教訓の枠消費防止
    lessons_by_id = {l.get('id',''): l for l in confirmed_lessons}
    pre_dedup_count = len(scored)
    scored = greedy_dedup(scored, lessons_by_id)

    top = scored[:7]

    # AC4: スコア0時のフォールバック = 注入なし（無関連教訓のCTX浪費防止）

    HOLDOUT_RATE = 0.2
    related = []
    withheld = []
    for _, lid, summary in top:
        if random.random() < HOLDOUT_RATE:
            withheld.append({'id': lid, 'summary': summary})
        else:
            related.append({'id': lid, 'summary': summary, 'reviewed': False})

    # AC3: universal教訓の注入上限max 3 — helpful_count上位3件を選択
    universal_total_count = len(universal_lessons)
    universal_lessons.sort(key=lambda l: -(l.get('helpful_count', 0) or 0))
    universal_lessons = universal_lessons[:3]

    top_ids = set(r['id'] for r in related)
    universal_added = 0
    for ul in universal_lessons:
        ul_id = ul.get('id', '')
        if ul_id not in top_ids and len(related) < 10:
            related.append({
                'id': ul_id,
                'summary': ul.get('summary', '') or ul.get('title', ''),
                'reviewed': False
            })
            universal_added += 1

    task['related_lessons'] = related

    # (A) description冒頭に教訓要約を挿入（忍者が即座に目にする）
    if related:
        desc = task.get('description', '')
        marker = '【注入教訓】'
        if marker not in str(desc):
            lines = [marker + ' 必ず確認し reviewed: true に変更せよ']
            for r in related:
                lines.append(f\"  - {r['id']}: {r['summary'][:80]}\")
            lines.append('─' * 40)
            prefix = '\\n'.join(lines) + '\\n\\n'
            task['description'] = prefix + str(desc or '')

    # Atomic write
    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
        os.replace(tmp_path, task_file)
    except:
        os.unlink(tmp_path)
        raise

    # Postcondition data (cmd_378)
    _pc_path = os.path.join(os.path.dirname(task_file), '.postcond_lesson_inject')
    try:
        with open(_pc_path, 'w') as _pf:
            _pf.write(f'available={len(tag_candidates) + universal_total_count}\\n')
            _pf.write(f'injected={len(related)}\\n')
            _pf.write(f'task_id={task.get(\"task_id\", \"unknown\")}\\n')
            _pf.write(f'project={project}\\n')
            _pf.write(f'injected_ids={\" \".join(r[\"id\"] for r in related)}\\n')
    except Exception:
        pass

    ids = [r['id'] for r in related]
    tag_info = f'task_tags={task_tags} inferred={tag_inferred}'
    scored_count = len(scored)
    tag_candidate_count = len(tag_candidates)
    print(f'[INJECT] Injected {len(related)} lessons (universal={universal_added}/{universal_total_count}, task_specific={len(related)-universal_added}, platform={platform_count}): {ids}', file=sys.stderr)
    print(f'[INJECT]   project={project} {tag_info} scored={scored_count}/{tag_candidate_count} top_scores={[(s,i) for s,i,_ in scored[:5]]}', file=sys.stderr)
    print(f'[INJECT]   filtered: draft={filtered_draft} deprecated={filtered_deprecated}', file=sys.stderr)
    dedup_removed = pre_dedup_count - len(scored)
    print(f'[INJECT]   dedup: {dedup_removed} duplicates removed (threshold={DEDUP_THRESHOLD})', file=sys.stderr)

    # ═══ 教訓因果追跡ログ記録 ═══
    impact_log = os.path.join(script_dir, 'logs', 'lesson_impact.tsv')
    cmd_id = task.get('task_id') or task.get('parent_cmd') or 'unknown'
    ninja_name = task.get('assigned_to', 'unknown')
    task_type = task.get('task_type') or task.get('type', 'unknown')
    bloom = task.get('bloom_level', 'unknown')

    try:
        os.makedirs(os.path.dirname(impact_log), exist_ok=True)
        write_header = not os.path.exists(impact_log) or os.path.getsize(impact_log) == 0
        with open(impact_log, 'a', encoding='utf-8') as lf:
            if write_header:
                lf.write('timestamp\\tcmd_id\\tninja\\tlesson_id\\taction\\tresult\\treferenced\\tproject\\ttask_type\\tbloom_level\\n')
            ts = datetime.datetime.now().isoformat(timespec='seconds')
            for r in related:
                lf.write(f'{ts}\\t{cmd_id}\\t{ninja_name}\\t{r[\"id\"]}\\tinjected\\tpending\\tpending\\t{project}\\t{task_type}\\t{bloom}\\n')
            for w in withheld:
                lf.write(f'{ts}\\t{cmd_id}\\t{ninja_name}\\t{w[\"id\"]}\\twithheld\\tpending\\tno\\t{project}\\t{task_type}\\t{bloom}\\n')
        print(f'[INJECT] Impact log: {len(related)} injected + {len(withheld)} withheld written to lesson_impact.tsv', file=sys.stderr)
    except Exception as ie:
        print(f'[INJECT] WARN: impact log write failed: {ie}', file=sys.stderr)

except Exception as e:
    print(f'[INJECT] ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" 2>&1 | while IFS= read -r line; do log "$line"; done
}

# ─── 偵察報告自動注入（task YAMLにreports_to_readを挿入） ───
inject_reports_to_read() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "inject_reports: task file not found: $task_file"
        return 0
    fi

    python3 -c "
import yaml, sys, os, tempfile, glob

task_file = '$task_file'
script_dir = '$SCRIPT_DIR'

try:
    with open(task_file) as f:
        data = yaml.safe_load(f)

    if not data or 'task' not in data:
        print('[INJECT_REPORTS] No task section in YAML, skipping', file=sys.stderr)
        sys.exit(0)

    task = data['task']

    # 既にreports_to_readが設定済みなら上書きしない
    if task.get('reports_to_read'):
        print('[INJECT_REPORTS] reports_to_read already exists, skipping', file=sys.stderr)
        sys.exit(0)

    blocked_by = task.get('blocked_by', [])
    if not blocked_by:
        print('[INJECT_REPORTS] No blocked_by, skipping', file=sys.stderr)
        sys.exit(0)

    # blocked_byの各タスクIDから忍者名を解決
    tasks_dir = os.path.join(script_dir, 'queue', 'tasks')
    reports_dir = os.path.join(script_dir, 'queue', 'reports')
    report_paths = []

    for blocked_task_id in blocked_by:
        # queue/tasks/*.yamlを検索してtask_idが一致するものを見つける
        if not os.path.isdir(tasks_dir):
            continue
        for fname in os.listdir(tasks_dir):
            if not fname.endswith('.yaml'):
                continue
            fpath = os.path.join(tasks_dir, fname)
            try:
                with open(fpath) as f:
                    tdata = yaml.safe_load(f)
                if not tdata or 'task' not in tdata:
                    continue
                t = tdata['task']
                if t.get('task_id') == blocked_task_id:
                    assigned_to = t.get('assigned_to', '')
                    if assigned_to:
                        blocked_parent_cmd = t.get('parent_cmd', '')
                        new_report = ''

                        if isinstance(blocked_parent_cmd, str) and blocked_parent_cmd.startswith('cmd_'):
                            new_report = os.path.join(reports_dir, f'{assigned_to}_report_{blocked_parent_cmd}.yaml')

                        legacy_report = os.path.join(reports_dir, f'{assigned_to}_report.yaml')

                        if new_report and os.path.exists(new_report):
                            report_paths.append(f'queue/reports/{os.path.basename(new_report)}')
                        elif os.path.exists(legacy_report):
                            report_paths.append(f'queue/reports/{assigned_to}_report.yaml')
                        else:
                            # 後方互換: cmd指定報告がなければ最新のcmd付き報告を探索
                            alt = sorted(
                                glob.glob(os.path.join(reports_dir, f'{assigned_to}_report_cmd*.yaml')),
                                key=os.path.getmtime,
                                reverse=True
                            )
                            if alt:
                                report_paths.append(f\"queue/reports/{os.path.basename(alt[0])}\")
                            else:
                                print(f'[INJECT_REPORTS] WARN: report not found: {new_report or legacy_report}', file=sys.stderr)
                    break
            except Exception:
                continue

    if not report_paths:
        print('[INJECT_REPORTS] No report files found for blocked_by tasks', file=sys.stderr)
        sys.exit(0)

    # deduplicate while preserving order
    seen = set()
    unique_paths = []
    for p in report_paths:
        if p not in seen:
            seen.add(p)
            unique_paths.append(p)

    task['reports_to_read'] = unique_paths

    # description冒頭に参照報告を挿入
    desc = task.get('description', '')
    marker = '【参照報告】'
    if marker not in str(desc):
        lines = [marker + ' 以下の報告を読んでからレビューせよ']
        for rp in unique_paths:
            lines.append(f'  - {rp}')
        lines.append('─' * 40)
        prefix = '\\n'.join(lines) + '\\n\\n'
        task['description'] = prefix + str(desc or '')

    # Atomic write
    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
        os.replace(tmp_path, task_file)
    except:
        os.unlink(tmp_path)
        raise

    print(f'[INJECT_REPORTS] Injected {len(unique_paths)} reports: {unique_paths}', file=sys.stderr)

except Exception as e:
    print(f'[INJECT_REPORTS] ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" 2>&1 | while IFS= read -r line; do log "$line"; done
}

# ─── context_files自動注入（cmd_280: 分割context選択的読込） ───
inject_context_files() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "inject_context_files: task file not found: $task_file"
        return 0
    fi

    python3 -c "
import yaml, sys, os, tempfile

task_file = '$task_file'
script_dir = '$SCRIPT_DIR'
projects_yaml = os.path.join(script_dir, 'config', 'projects.yaml')

try:
    with open(task_file) as f:
        data = yaml.safe_load(f)

    if not data or 'task' not in data:
        sys.exit(0)

    task = data['task']

    # 既にcontext_filesが設定済みなら上書きしない（家老が手動指定した場合）
    if task.get('context_files'):
        print('[INJECT_CTX] context_files already exists, skipping', file=sys.stderr)
        sys.exit(0)

    project = task.get('project', '')
    if not project:
        sys.exit(0)

    if not os.path.exists(projects_yaml):
        sys.exit(0)

    with open(projects_yaml) as f:
        pdata = yaml.safe_load(f)

    # プロジェクトのcontext_files定義を探す
    ctx_files = None
    ctx_index = None
    for p in pdata.get('projects', []):
        if p.get('id') == project:
            ctx_files = p.get('context_files', [])
            ctx_index = p.get('context_file', '')
            break

    if not ctx_files:
        sys.exit(0)

    # 索引ファイルは常に含める
    result = []
    if ctx_index:
        result.append(ctx_index)

    # タスクのtask_typeやdescriptionからタグをマッチング
    task_type = str(task.get('task_type', '')).lower()
    description = str(task.get('description', '')).lower()
    title = str(task.get('title', '')).lower()
    task_text = f'{task_type} {description} {title}'

    for cf in ctx_files:
        tags = cf.get('tags', [])
        filepath = cf.get('file', '')
        if not filepath:
            continue
        # タグがタスクテキストに含まれるか、タグなしなら常に含める
        if not tags:
            result.append(filepath)
        elif any(tag.lower() in task_text for tag in tags):
            result.append(filepath)

    # フォールバック: タグマッチが索引のみの場合、全ファイルを含める
    if len(result) <= 1:
        result = [ctx_index] if ctx_index else []
        for cf in ctx_files:
            filepath = cf.get('file', '')
            if filepath:
                result.append(filepath)

    task['context_files'] = result

    # Atomic write
    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
        os.replace(tmp_path, task_file)
    except:
        os.unlink(tmp_path)
        raise

    print(f'[INJECT_CTX] Injected {len(result)} context files for project={project}', file=sys.stderr)

except Exception as e:
    print(f'[INJECT_CTX] ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" 2>&1 | while IFS= read -r line; do log "$line"; done
}

# ─── role_reminder自動注入（cmd_384: 忍者スコープ制限リマインダ） ───
inject_role_reminder() {
    local task_file="$1"
    local ninja_name="$2"
    if [ ! -f "$task_file" ]; then
        log "inject_role_reminder: task file not found: $task_file"
        return 0
    fi

    # L047: 環境変数経由でPythonに値を渡す（直接補間はインジェクション危険）
    TASK_FILE_ENV="$task_file" NINJA_NAME_ENV="$ninja_name" python3 -c "
import yaml, sys, os, tempfile

task_file = os.environ['TASK_FILE_ENV']
ninja_name = os.environ['NINJA_NAME_ENV']

try:
    with open(task_file) as f:
        data = yaml.safe_load(f)

    if not data or 'task' not in data:
        print('[ROLE_REMINDER] No task section, skipping', file=sys.stderr)
        sys.exit(0)

    task = data['task']

    # 既にrole_reminderが存在する場合は上書きしない
    if task.get('role_reminder'):
        print('[ROLE_REMINDER] Already exists, skipping', file=sys.stderr)
        sys.exit(0)

    task['role_reminder'] = f'忍者{ninja_name}。このタスクのみ実行せよ。スコープ外の改善・判断は禁止。発見はlesson_candidate/decision_candidateへ'

    # Atomic write
    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
        os.replace(tmp_path, task_file)
    except:
        os.unlink(tmp_path)
        raise

    print(f'[ROLE_REMINDER] Injected for {ninja_name}', file=sys.stderr)

except Exception as e:
    print(f'[ROLE_REMINDER] ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" 2>&1 | while IFS= read -r line; do log "$line"; done
}

# ─── report_template自動注入（cmd_384: タスク種別別レポート雛形） ───
inject_report_template() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "inject_report_template: task file not found: $task_file"
        return 0
    fi

    # L047: 環境変数経由でPythonに値を渡す
    TASK_FILE_ENV="$task_file" SCRIPT_DIR_ENV="$SCRIPT_DIR" python3 -c "
import yaml, sys, os, tempfile

task_file = os.environ['TASK_FILE_ENV']
script_dir = os.environ['SCRIPT_DIR_ENV']

try:
    with open(task_file) as f:
        data = yaml.safe_load(f)

    if not data or 'task' not in data:
        print('[REPORT_TPL] No task section, skipping', file=sys.stderr)
        sys.exit(0)

    task = data['task']

    # 既にreport_templateが存在する場合は上書きしない
    if task.get('report_template'):
        print('[REPORT_TPL] Already exists, skipping', file=sys.stderr)
        sys.exit(0)

    task_type = str(task.get('task_type', '')).lower()
    if not task_type:
        print('[REPORT_TPL] No task_type, skipping', file=sys.stderr)
        sys.exit(0)

    template_path = os.path.join(script_dir, 'templates', f'report_{task_type}.yaml')
    if not os.path.exists(template_path):
        print(f'[REPORT_TPL] WARN: template not found: {template_path}', file=sys.stderr)
        sys.exit(0)

    with open(template_path) as f:
        template_data = yaml.safe_load(f)

    if template_data:
        task['report_template'] = template_data

    # Atomic write
    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
        os.replace(tmp_path, task_file)
    except:
        os.unlink(tmp_path)
        raise

    print(f'[REPORT_TPL] Injected {task_type} template', file=sys.stderr)

except Exception as e:
    print(f'[REPORT_TPL] ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" 2>&1 | while IFS= read -r line; do log "$line"; done
}

# ─── report_filename自動注入（cmd_410: 命名ミスマッチ根治） ───
inject_report_filename() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "inject_report_filename: task file not found: $task_file"
        return 0
    fi

    # L047: 環境変数経由でPythonに値を渡す
    TASK_FILE_ENV="$task_file" NINJA_NAME_ENV="$NINJA_NAME" python3 -c "
import yaml, sys, os, tempfile

task_file = os.environ['TASK_FILE_ENV']
ninja_name = os.environ['NINJA_NAME_ENV']

try:
    with open(task_file) as f:
        data = yaml.safe_load(f)

    if not data or 'task' not in data:
        print('[REPORT_FN] No task section, skipping', file=sys.stderr)
        sys.exit(0)

    task = data['task']

    # 既にreport_filenameが存在する場合は上書きしない
    if task.get('report_filename'):
        print('[REPORT_FN] Already exists, skipping', file=sys.stderr)
        sys.exit(0)

    parent_cmd = str(task.get('parent_cmd', '') or '')
    if parent_cmd:
        report_filename = f'{ninja_name}_report_{parent_cmd}.yaml'
    else:
        report_filename = f'{ninja_name}_report.yaml'

    task['report_filename'] = report_filename

    # Atomic write
    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
        os.replace(tmp_path, task_file)
    except:
        os.unlink(tmp_path)
        raise

    print(f'[REPORT_FN] Injected report_filename={report_filename}', file=sys.stderr)

except Exception as e:
    print(f'[REPORT_FN] ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" 2>&1 | while IFS= read -r line; do log "$line"; done
}

# ─── bloom_level自動注入（cmd_434: タスク複雑度メタデータ） ───
inject_bloom_level() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "inject_bloom_level: task file not found: $task_file"
        return 0
    fi

    # L047: 環境変数経由でPythonに値を渡す
    TASK_FILE_ENV="$task_file" python3 -c "
import yaml, sys, os, tempfile

task_file = os.environ['TASK_FILE_ENV']

try:
    with open(task_file) as f:
        data = yaml.safe_load(f)

    if not data or 'task' not in data:
        print('[BLOOM_LVL] No task section, skipping', file=sys.stderr)
        sys.exit(0)

    task = data['task']

    # 既にbloom_levelが存在する場合は上書きしない
    if 'bloom_level' in task:
        print('[BLOOM_LVL] Already exists, skipping', file=sys.stderr)
        sys.exit(0)

    task['bloom_level'] = ''

    # Atomic write
    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
        os.replace(tmp_path, task_file)
    except:
        os.unlink(tmp_path)
        raise

    print('[BLOOM_LVL] Injected bloom_level (empty)', file=sys.stderr)

except Exception as e:
    print(f'[BLOOM_LVL] ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" 2>&1 | while IFS= read -r line; do log "$line"; done
}

# ─── preflight gate artifact生成（cmd_407: missing_gate BLOCK率削減） ───
# deploy_task.sh実行時にcmd_complete_gate.shが要求するgateフラグを事前生成。
# L078: 65%のBLOCKがmissing_gate(archive/lesson/review_gate)。配備時に生成で削減。
preflight_gate_artifacts() {
    local task_file="$1"
    local cmd_id
    cmd_id=$(field_get "$task_file" "parent_cmd" "")

    if [ -z "$cmd_id" ] || [[ "$cmd_id" != cmd_* ]]; then
        log "preflight_gate: SKIP (no valid parent_cmd)"
        return 0
    fi

    local gates_dir="$SCRIPT_DIR/queue/gates/${cmd_id}"
    mkdir -p "$gates_dir"
    log "preflight_gate: ${cmd_id} — artifact事前生成開始"

    # (1) archive.done — archive_completed.sh実行（過去の完了cmdのアーカイブ。配備時に安全）
    if [ ! -f "$gates_dir/archive.done" ]; then
        if bash "$SCRIPT_DIR/scripts/archive_completed.sh" "$cmd_id" >/dev/null 2>&1; then
            log "preflight_gate: archive.done generated"
        else
            log "preflight_gate: archive.done WARN (script failed, non-blocking)"
        fi
    else
        log "preflight_gate: archive.done already exists (skip)"
    fi

    # (2) lesson.done — 配備時点で報告YAMLは未存在→lesson_check.shで「候補なし」フラグ生成
    # 注: ninja完了後にlesson_candidate found:trueが出た場合、
    #   cmd_complete_gate.shのpreflight upgradeロジックがsource: lesson_writeに上書きする
    if [ ! -f "$gates_dir/lesson.done" ]; then
        if bash "$SCRIPT_DIR/scripts/lesson_check.sh" "$cmd_id" "deploy_preflight: 配備時点で候補なし" >/dev/null 2>&1; then
            log "preflight_gate: lesson.done generated (deploy_preflight)"
        else
            log "preflight_gate: lesson.done WARN (script failed, non-blocking)"
        fi
    else
        log "preflight_gate: lesson.done already exists (skip)"
    fi

    # (3) review_gate.done — implement時のみ。配備時点でreview未実施のためplaceholder生成
    local task_type
    task_type=$(field_get "$task_file" "task_type" "")
    if [ "$task_type" = "implement" ] && [ ! -f "$gates_dir/review_gate.done" ]; then
        cat > "$gates_dir/review_gate.done" <<EOF
timestamp: $(date '+%Y-%m-%dT%H:%M:%S')
source: deploy_preflight
note: 配備時placeholder。review_gate.shが完了時に上書き。
EOF
        log "preflight_gate: review_gate.done generated (deploy_preflight)"
    fi

    # (4) report_merge.done — recon時のみ。配備時点で報告未存在のためplaceholder生成
    if [ "$task_type" = "recon" ] && [ ! -f "$gates_dir/report_merge.done" ]; then
        cat > "$gates_dir/report_merge.done" <<EOF
timestamp: $(date '+%Y-%m-%dT%H:%M:%S')
source: deploy_preflight
note: 配備時placeholder。report_merge.shが完了時に上書き。
EOF
        log "preflight_gate: report_merge.done generated (deploy_preflight)"
    fi

    log "preflight_gate: ${cmd_id} — artifact事前生成完了"
}

# ─── deployed_at自動記録（cmd_387: 配備タイムスタンプ） ───
# 既にdeployed_atが存在する場合は上書きしない（再配備時の元タイムスタンプ保持）
record_deployed_at() {
    local task_file="$1"
    local timestamp="$2"
    if [ ! -f "$task_file" ]; then
        log "record_deployed_at: task file not found: $task_file"
        return 0
    fi

    TASK_FILE_ENV="$task_file" TIMESTAMP_ENV="$timestamp" python3 -c "
import yaml, sys, os, tempfile

task_file = os.environ['TASK_FILE_ENV']
timestamp = os.environ['TIMESTAMP_ENV']

try:
    with open(task_file) as f:
        data = yaml.safe_load(f)

    if not data or 'task' not in data:
        print('[DEPLOYED_AT] No task section, skipping', file=sys.stderr)
        sys.exit(0)

    task = data['task']

    # 既にdeployed_atが存在する場合は上書きしない
    if task.get('deployed_at'):
        print(f'[DEPLOYED_AT] Already exists ({task[\"deployed_at\"]}), skipping', file=sys.stderr)
        sys.exit(0)

    task['deployed_at'] = timestamp

    # Atomic write
    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
        os.replace(tmp_path, task_file)
    except:
        os.unlink(tmp_path)
        raise

    print(f'[DEPLOYED_AT] Recorded: {timestamp}', file=sys.stderr)

except Exception as e:
    print(f'[DEPLOYED_AT] ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" 2>&1 | while IFS= read -r line; do log "$line"; done
}

# ─── context鮮度チェック（穴2対策: cmd_239） ───
check_context_freshness() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        return 0
    fi

    local project
    project=$(field_get "$task_file" "project" "")
    if [ -z "$project" ]; then
        log "context_freshness: SKIP (no project field)"
        return 0
    fi

    local projects_yaml="$SCRIPT_DIR/config/projects.yaml"
    if [ ! -f "$projects_yaml" ]; then
        log "context_freshness: SKIP (projects.yaml not found)"
        return 0
    fi

    local context_file
    context_file=$(python3 -c "
import yaml, sys
try:
    with open('$projects_yaml') as f:
        data = yaml.safe_load(f)
    for p in data.get('projects', []):
        if p.get('id') == '$project':
            print(p.get('context_file', ''))
            break
except:
    pass
" 2>/dev/null)

    if [ -z "$context_file" ]; then
        log "context_freshness: SKIP (no context_file for project=$project)"
        return 0
    fi

    local full_path="$SCRIPT_DIR/$context_file"
    if [ ! -f "$full_path" ]; then
        log "context_freshness: WARNING (file not found: $context_file)"
        echo "⚠️ WARNING: $context_file not found" >&2
        return 0
    fi

    local last_updated
    last_updated=$(grep -o 'last_updated: [0-9-]*' "$full_path" 2>/dev/null | head -1 | cut -d' ' -f2)

    if [ -z "$last_updated" ]; then
        log "context_freshness: ⚠️ WARNING: $context_file has no last_updated metadata"
        echo "⚠️ WARNING: $context_file has no last_updated metadata (date unknown)" >&2
        return 0
    fi

    local days_old
    days_old=$(python3 -c "
from datetime import date
try:
    lu = date.fromisoformat('$last_updated')
    print((date.today() - lu).days)
except:
    print(-1)
" 2>/dev/null)

    if [ "$days_old" -ge 14 ] 2>/dev/null; then
        log "context_freshness: ⚠️ WARNING: $context_file last updated ${days_old} days ago"
        echo "⚠️ WARNING: $context_file last updated ${days_old} days ago" >&2
    else
        log "context_freshness: OK ($context_file updated ${days_old} days ago)"
    fi

    return 0
}

# ─── 入口門番: 前タスクの教訓未消化チェック ───
check_entrance_gate() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "entrance_gate: PASS (task file not found: $task_file)"
        return 0
    fi

    local result
    local exit_code=0
    result=$(python3 -c "
import yaml, sys

try:
    with open('$task_file') as f:
        data = yaml.safe_load(f)

    if not data or 'task' not in data:
        sys.exit(0)

    task = data['task']
    related = task.get('related_lessons', [])

    if not related:
        sys.exit(0)

    unreviewed = [r['id'] for r in related if isinstance(r, dict) and r.get('reviewed') is False]

    if unreviewed:
        print(', '.join(unreviewed))
        sys.exit(1)

    sys.exit(0)
except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(0)  # パース失敗時はブロックしない
" 2>/dev/null) || exit_code=$?

    if [ "$exit_code" -ne 0 ]; then
        log "BLOCK: ${NINJA_NAME}の前タスクにreviewed:false残存 [${result}]。教訓を消化してから再配備せよ"
        echo "BLOCK: ${NINJA_NAME}の前タスクにreviewed:false残存 [${result}]。教訓を消化してから再配備せよ" >&2
        exit 1
    fi

    log "entrance_gate: PASS (no unreviewed lessons)"
    return 0
}

# ─── 偵察ゲート: implタスクは偵察済みorscout_exempt必須 ───
check_scout_gate() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "scout_gate: PASS (task file not found)"
        return 0
    fi

    local result
    local exit_code=0
    result=$(python3 -c "
import yaml, sys, os, glob

task_file = '$task_file'
script_dir = '$SCRIPT_DIR'

try:
    with open(task_file) as f:
        data = yaml.safe_load(f)

    if not data or 'task' not in data:
        sys.exit(0)

    task = data['task']

    # 1. task_typeがimplement以外ならPASS（scout/recon/review等はゲート対象外）
    task_type = str(task.get('task_type', '')).lower()
    if task_type != 'implement':
        print(f'PASS: task_type={task_type} (not implement)', file=sys.stderr)
        sys.exit(0)

    parent_cmd = task.get('parent_cmd', '')
    if not parent_cmd:
        print('PASS: no parent_cmd', file=sys.stderr)
        sys.exit(0)

    # 2. shogun_to_karo.yaml + archive でscout_exemptを確認
    stk_paths = [
        os.path.join(script_dir, 'queue', 'shogun_to_karo.yaml'),
        os.path.join(script_dir, 'queue', 'archive', 'shogun_to_karo_done.yaml'),
    ]
    for stk_path in stk_paths:
        if not os.path.exists(stk_path):
            continue
        with open(stk_path) as f:
            stk = yaml.safe_load(f)
        for cmd in (stk or {}).get('commands', []):
            if cmd.get('id') == parent_cmd:
                if cmd.get('scout_exempt') is True:
                    reason = cmd.get('scout_exempt_reason', '(no reason)')
                    print(f'PASS: scout_exempt=true for {parent_cmd} ({reason})', file=sys.stderr)
                    sys.exit(0)
                break

    # 2.5. report_merge.doneチェック（偵察が統合済みならPASS）
    gate_dir = os.path.join(script_dir, 'queue', 'gates', parent_cmd)
    merge_done = os.path.join(gate_dir, 'report_merge.done')
    if os.path.exists(merge_done):
        print(f'PASS: report_merge.done exists for {parent_cmd}', file=sys.stderr)
        sys.exit(0)

    # 3. queue/tasks/*.yamlからscout/reconタスクのdone数をカウント
    tasks_dir = os.path.join(script_dir, 'queue', 'tasks')
    done_count = 0
    if os.path.isdir(tasks_dir):
        for fname in os.listdir(tasks_dir):
            if not fname.endswith('.yaml'):
                continue
            fpath = os.path.join(tasks_dir, fname)
            try:
                with open(fpath) as f:
                    tdata = yaml.safe_load(f)
                if not tdata or 'task' not in tdata:
                    continue
                t = tdata['task']
                if t.get('parent_cmd') != parent_cmd:
                    continue
                tid = str(t.get('task_id', '')).lower()
                if 'scout' in tid or 'recon' in tid:
                    t_status = str(t.get('status', '')).lower()
                    if t_status == 'done':
                        done_count += 1
            except Exception:
                continue

    if done_count >= 2:
        print(f'PASS: {done_count} scout/recon tasks done for {parent_cmd}', file=sys.stderr)
        sys.exit(0)

    # BLOCK
    print(f'BLOCK: {parent_cmd} — scout done={done_count}/2, scout_exempt=false')
    sys.exit(1)

except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(0)  # パース失敗時はブロックしない
" 2>&1) || exit_code=$?

    if [ "$exit_code" -ne 0 ]; then
        log "BLOCK(scout_gate): ${result}"
        echo "BLOCK(scout_gate): 偵察未完了。scout_reportsが2件未満かつscout_exemptなし。将軍にscout_exempt申請するか、先に偵察を配備せよ" >&2
        echo "詳細: ${result}" >&2
        exit 1
    fi

    # stderrの出力をログに記録
    log "scout_gate: ${result}"
    return 0
}

# ─── 教訓注入postcondition（cmd_378: 事後不変条件） ───
postcondition_lesson_inject() {
    local task_file="$1"
    local postcond_file
    postcond_file="$(dirname "$task_file")/.postcond_lesson_inject"

    if [ ! -f "$postcond_file" ]; then
        # inject early exit (no project/no lessons) → postcond data not written → OK
        return 0
    fi

    local available injected task_id
    available=$(grep '^available=' "$postcond_file" 2>/dev/null | head -1 | cut -d= -f2)
    injected=$(grep '^injected=' "$postcond_file" 2>/dev/null | head -1 | cut -d= -f2)
    task_id=$(grep '^task_id=' "$postcond_file" 2>/dev/null | head -1 | cut -d= -f2)
    rm -f "$postcond_file"

    available="${available:-0}"
    injected="${injected:-0}"
    task_id="${task_id:-unknown}"

    if [ "$available" -gt 0 ] 2>/dev/null && [ "$injected" -eq 0 ] 2>/dev/null; then
        log "[deploy] WARN: 教訓注入ゼロ (available=${available} injected=0 task=${task_id})"
    else
        log "[deploy] OK: 教訓注入 (available=${available} injected=${injected} task=${task_id})"
    fi

    return 0
}

# ═══════════════════════════════════════
# メイン処理
# ═══════════════════════════════════════

PANE_TARGET=$(resolve_pane "$NINJA_NAME")
if [ -z "$PANE_TARGET" ]; then
    log "ERROR: Unknown ninja: $NINJA_NAME"
    exit 1
fi

CTX_PCT=$(get_ctx_pct "$PANE_TARGET")
IS_IDLE=false
check_idle "$PANE_TARGET" && IS_IDLE=true

# タスクステータス確認
TASK_STATUS=$(field_get "$SCRIPT_DIR/queue/tasks/${NINJA_NAME}.yaml" "status" "unknown")

log "${NINJA_NAME}: CTX=${CTX_PCT}%, idle=${IS_IDLE}, task_status=${TASK_STATUS}, pane=${PANE_TARGET}"

# 入口門番: 前タスクの教訓未消化チェック（reviewed:false残存ならブロック）
TASK_FILE="$SCRIPT_DIR/queue/tasks/${NINJA_NAME}.yaml"
check_entrance_gate "$TASK_FILE"

# 偵察ゲート: implタスクは偵察済みorscout_exempt必須（BLOCKならexit 1）
check_scout_gate "$TASK_FILE"

# task_id自動注入（cmd_465: subtask_id→task_idエイリアス。STALL検知に必須）
inject_task_id "$TASK_FILE" || true

# 教訓自動注入（失敗してもデプロイは継続）
inject_related_lessons "$TASK_FILE" || true

# 教訓注入postcondition（失敗してもデプロイは継続）
postcondition_lesson_inject "$TASK_FILE" || true

# 教訓injection_countカウント加算（cmd_470: 注入回数トラッキング）
_pc_file="$SCRIPT_DIR/queue/tasks/.postcond_lesson_inject"
if [ -f "$_pc_file" ]; then
    _inj_project=$(grep '^project=' "$_pc_file" | cut -d= -f2)
    _inj_ids=$(grep '^injected_ids=' "$_pc_file" | cut -d= -f2)
    if [ -n "$_inj_ids" ] && [ -n "$_inj_project" ]; then
        for _lid in $_inj_ids; do
            bash "$SCRIPT_DIR/scripts/lesson_update_score.sh" "$_inj_project" "$_lid" inject 2>/dev/null || true
        done
        # platform教訓はinfra PJに属するため、project!=infraの場合はinfraも走査
        if [ "$_inj_project" != "infra" ]; then
            for _lid in $_inj_ids; do
                bash "$SCRIPT_DIR/scripts/lesson_update_score.sh" infra "$_lid" inject 2>/dev/null || true
            done
        fi
        log "injection_count: incremented for ${_inj_ids}"
    fi
fi

# 偵察報告自動注入（失敗してもデプロイは継続）
inject_reports_to_read "$TASK_FILE" || true

# context_files自動注入（失敗してもデプロイは継続）
inject_context_files "$TASK_FILE" || true

# role_reminder自動注入（cmd_384: 失敗してもデプロイは継続）
inject_role_reminder "$TASK_FILE" "$NINJA_NAME" || true

# report_template自動注入（cmd_384: 失敗してもデプロイは継続）
inject_report_template "$TASK_FILE" || true

# report_filename自動注入（cmd_410: 命名ミスマッチ根治）
inject_report_filename "$TASK_FILE" || true

# bloom_level自動注入（cmd_434: タスク複雑度メタデータ）
inject_bloom_level "$TASK_FILE" || true

# context鮮度チェック（失敗してもデプロイは継続）
check_context_freshness "$TASK_FILE" || true

# 状態に応じた処理
if [ "$CTX_PCT" -le 0 ] 2>/dev/null; then
    # CTX:0% — /clear済み、またはフレッシュセッション
    log "${NINJA_NAME}: CTX=0% detected (clear済み). Sending inbox_write (watcher handles timing)"
    bash "$SCRIPT_DIR/scripts/inbox_write.sh" "$NINJA_NAME" "$MESSAGE" "$TYPE" "$FROM"

elif [ "$IS_IDLE" = "true" ]; then
    # CTX>0% + idle — 通常idle、nudge可能
    log "${NINJA_NAME}: CTX=${CTX_PCT}%, idle. Sending inbox_write (normal nudge)"
    bash "$SCRIPT_DIR/scripts/inbox_write.sh" "$NINJA_NAME" "$MESSAGE" "$TYPE" "$FROM"

else
    # CTX>0% + busy — 稼働中、メッセージはキューに入る
    log "${NINJA_NAME}: CTX=${CTX_PCT}%, busy. Sending inbox_write (queued, watcher will nudge later)"
    bash "$SCRIPT_DIR/scripts/inbox_write.sh" "$NINJA_NAME" "$MESSAGE" "$TYPE" "$FROM"
fi

# 報告YAML雛形生成（配備完了ログの直前）
TASK_ID=$(field_get "$TASK_FILE" "task_id" "")
PARENT_CMD=$(field_get "$TASK_FILE" "parent_cmd" "")
PROJECT=$(field_get "$TASK_FILE" "project" "")
generate_report_template "$NINJA_NAME" "$TASK_ID" "$PARENT_CMD" "$PROJECT"

# deployed_at自動記録（cmd_387: 初回配備時のみ記録、再配備時は保持）
record_deployed_at "$TASK_FILE" "$(date '+%Y-%m-%dT%H:%M:%S')" || true

# preflight gate artifact生成（cmd_407: missing_gate BLOCK率削減）
preflight_gate_artifacts "$TASK_FILE" || true

log "${NINJA_NAME}: deployment complete (type=${TYPE})"
