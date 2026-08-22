#!/usr/bin/env bash
# deploy_task/modifiers.sh — cluster H: lesson/workaround, target, role/model, and execution modifiers.
# Function bodies are extracted verbatim from deploy_task.sh.

# ─── 教訓自動注入（task YAMLにrelated_lessonsを挿入） ───
# cmd_349: タグマッチによる選択的教訓注入
inject_related_lessons() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "inject_lessons: task file not found: $task_file"
        return 0
    fi

    deploy_task_postcondition_prepare "$task_file"

    local py_output
    py_output=$(mktemp)
    if ! run_python_logged "$py_output" env TASK_FILE_ENV="$task_file" SCRIPT_DIR_ENV="$SCRIPT_DIR" POSTCOND_FILE_ENV="$DEPLOY_TASK_POSTCOND_FILE" python3 - <<'PY'; then
import csv
import datetime
import fnmatch
import os
import random
import re
import subprocess
import sys
import tempfile

import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)

task_file = os.environ['TASK_FILE_ENV']
script_dir = os.environ['SCRIPT_DIR_ENV']
postcond_file = os.environ['POSTCOND_FILE_ENV']

DEDUP_THRESHOLD = 0.25
USEFUL_RATE_THRESHOLD = 0.40  # effectiveness_score below this → exclude from injection candidates
USEFUL_RATE_DECAY = 0.3       # legacy constant retained for tests/docs that compare deploy_task constants
TARGET_PATH_MATCH_BOOST = int(os.environ.get('TARGET_PATH_MATCH_BOOST', '50'))
NO_WHEN_PENALTY = int(os.environ.get('NO_WHEN_PENALTY', '10'))  # when未設定教訓のスコア降格値(useful_rate改善。3→10: 219件when未設定のキーワード衝突注入をほぼ排除)
MIN_KEYWORD_SCORE_BY_TASK_TYPE = {
    'default': int(os.environ.get('MIN_KEYWORD_SCORE', '2')),
    'impl': int(os.environ.get('MIN_KEYWORD_SCORE_IMPL', '6')),
    'exact': int(os.environ.get('MIN_KEYWORD_SCORE_EXACT', '4')),
    'focused': int(os.environ.get('MIN_KEYWORD_SCORE_FOCUSED', os.environ.get('MIN_KEYWORD_SCORE_EXACT', '4'))),
}
# 是正1: Bootstrapギャップ解消 — feedback=0件の教訓はこの閾値を要求(通常閾値より高く設定)
MIN_KEYWORD_SCORE_ZERO_FEEDBACK = int(os.environ.get('MIN_KEYWORD_SCORE_ZERO_FEEDBACK', '5'))
# 是正2: cross-project注入の精度向上 — project不一致教訓はこの閾値を要求(通常閾値より高く設定)
MIN_KEYWORD_SCORE_CROSS_PROJECT = int(os.environ.get('MIN_KEYWORD_SCORE_CROSS_PROJECT', '5'))
IMPACT_COLUMNS = [
    'timestamp', 'cmd_id', 'ninja', 'lesson_id', 'action', 'result',
    'referenced', 'project', 'task_type', 'bloom_level', 'score',
    'traversal_depth',
]

def _is_empty_row(row):
    """Return True if all fields in *row* are blank (or only whitespace/CR)."""
    return all(not cell.strip().strip('\r') for cell in row)

def ensure_impact_header(impact_path):
    """Upgrade existing lesson_impact.tsv headers without losing old rows."""
    if not os.path.exists(impact_path) or os.path.getsize(impact_path) == 0:
        os.makedirs(os.path.dirname(impact_path), exist_ok=True)
        with open(impact_path, 'w', encoding='utf-8', newline='') as f:
            f.write('\t'.join(IMPACT_COLUMNS) + '\n')
        return
    with open(impact_path, 'r', encoding='utf-8', newline='') as f:
        rows = list(csv.reader(f, delimiter='\t'))
    if not rows:
        return
    # Strip CR from header fields for reliable comparison
    header = [c.strip().strip('\r') for c in rows[0]]
    if header == IMPACT_COLUMNS:
        return

    new_header = list(header)
    for col in IMPACT_COLUMNS:
        if col not in new_header:
            new_header.append(col)

    upgraded_rows = [new_header]
    for row in rows[1:]:
        # Skip empty rows (all fields blank)
        if _is_empty_row(row):
            continue
        upgraded = [cell.strip('\r') for cell in row]
        while len(upgraded) < len(new_header):
            upgraded.append('')
        upgraded_rows.append(upgraded)

    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(impact_path), prefix='lesson_impact.', suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w', encoding='utf-8', newline='') as f:
            writer = csv.writer(f, delimiter='\t', lineterminator='\n')
            writer.writerows(upgraded_rows)
        os.replace(tmp_path, impact_path)
    except Exception:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
        raise

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
        l_text = f'{lesson.get("title","")} {lesson.get("summary","")} {lesson.get("content","")}'
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

USEFUL_RATE_MIN_SAMPLES = int(os.environ.get('USEFUL_RATE_MIN_SAMPLES', '1'))  # 3→1: 除外感度向上(除外=降格であり完全削除ではない)

def compute_useful_rates(script_dir):
    """lesson_impact.tsvのfeedback行からlesson別effectiveness_scoreを算出。
    score = USEFUL / (USEFUL + NOT_USEFUL)。feedback以外や未確定値は分母に入れない。
    MIN_SAMPLES未満の教訓は除外対象外（サンプル不足でのペナルティ防止）。"""
    impact_path = os.path.join(script_dir, 'logs', 'lesson_impact.tsv')
    if not os.path.exists(impact_path):
        return {}, {}, {}
    feedback_counts = {}  # lesson_id -> [useful_count, total_feedback_count]
    try:
        with open(impact_path, 'r', encoding='utf-8', newline='') as f:
            reader = csv.DictReader(f, delimiter='\t')
            for row in reader:
                lid = (row.get('lesson_id') or '').strip()
                action = (row.get('action') or '').strip().lower()
                if not lid or action != 'feedback':
                    continue
                result = (row.get('result') or '').strip().upper()
                if result not in ('USEFUL', 'NOT_USEFUL'):
                    continue
                if lid not in feedback_counts:
                    feedback_counts[lid] = [0, 0]
                feedback_counts[lid][1] += 1
                if result == 'USEFUL':
                    feedback_counts[lid][0] += 1
    except Exception:
        return {}, {}, {}
    # MIN_SAMPLES以上のfeedbackがある教訓のみscoreを返す
    useful_rates = {
        lid: vals[0] / vals[1] if vals[1] > 0 else 0.0
        for lid, vals in feedback_counts.items()
        if vals[1] >= USEFUL_RATE_MIN_SAMPLES
    }
    feedback_totals = {lid: vals[1] for lid, vals in feedback_counts.items()}
    useful_counts = {lid: vals[0] for lid, vals in feedback_counts.items()}
    return useful_rates, feedback_totals, useful_counts

ZERO_USEFUL_DEPRECATE_MIN_SAMPLES = int(os.environ.get('ZERO_USEFUL_DEPRECATE_MIN_SAMPLES', '3'))
ENABLE_ZERO_USEFUL_AUTO_DEPRECATE = os.environ.get('ENABLE_ZERO_USEFUL_AUTO_DEPRECATE', '1') == '1'

def _deprecate_lessons_in_file(yaml_path, lesson_ids):
    """Add deprecated: true to matching lesson blocks without round-tripping YAML."""
    if not lesson_ids or not yaml_path or not os.path.exists(yaml_path):
        return 0
    target_ids = set(str(lid) for lid in lesson_ids if lid)
    try:
        with open(yaml_path, encoding='utf-8') as f:
            lines = f.read().splitlines()
    except Exception:
        return 0

    out = []
    current_id = None
    current_indent = None
    has_deprecated = False
    pending_insert = False
    changed = 0

    def flush_pending():
        nonlocal pending_insert, changed
        if pending_insert and current_id in target_ids and not has_deprecated:
            out.append(' ' * (current_indent + 2) + 'deprecated: true')
            out.append(' ' * (current_indent + 2) + 'deprecation_reason: auto_useful_rate_zero')
            changed += 1
        pending_insert = False

    id_re = re.compile(r'^(\s*)-\s+id:\s*[\'"]?([^\'"#\s]+)')
    # cmd_3254: flow-style YAML対応 — `- {id: L723, ...}` パターン
    flow_id_re = re.compile(r'^(\s*)-\s+\{.*?id:\s*[\'"]?([^\'"#\s,}]+)')
    item_re = re.compile(r'^(\s*)-\s+')
    deprecated_re = re.compile(r'^\s+deprecated:\s*true\s*(?:#.*)?$', re.IGNORECASE)
    status_deprecated_re = re.compile(r'^\s+status:\s*[\'"]?deprecated[\'"]?\s*(?:#.*)?$', re.IGNORECASE)

    for line in lines:
        # cmd_3254: flow-style行を先にチェック（一行完結のため即時処理）
        flow_m = flow_id_re.match(line)
        if flow_m:
            fid = flow_m.group(2).strip()
            if fid in target_ids and 'deprecated: true' not in line and 'deprecated:true' not in line:
                # flow-style: 閉じ`}`の直前に`, deprecated: true`を挿入
                line = re.sub(r'\}(\s*)$', r', deprecated: true, deprecation_reason: auto_useful_rate_zero}\1', line)
                changed += 1
            out.append(line)
            continue

        item_m = item_re.match(line)
        if item_m and current_id is not None and len(item_m.group(1)) <= current_indent:
            flush_pending()
            current_id = None
            current_indent = None
            has_deprecated = False

        id_m = id_re.match(line)
        if id_m:
            current_id = id_m.group(2).strip()
            current_indent = len(id_m.group(1))
            has_deprecated = False
            pending_insert = current_id in target_ids
            out.append(line)
            continue

        if current_id in target_ids and (deprecated_re.match(line) or status_deprecated_re.match(line)):
            has_deprecated = True

        out.append(line)

    if current_id is not None:
        flush_pending()

    if changed <= 0:
        return 0

    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(yaml_path), prefix='.lessons_deprecated.', suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w', encoding='utf-8') as f:
            f.write('\n'.join(out) + '\n')
        os.replace(tmp_path, yaml_path)
    except Exception:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
        return 0
    return changed

def apply_zero_useful_deprecation(
    lessons, lessons_path, feedback_totals, useful_counts,
    project_id=None, script_dir=None,
):
    """Retire zero-useful lessons through the canonical SSOT writer.

    ``lessons_path`` remains part of the call contract for cache identity and
    fixtures, but this function never writes the generated YAML cache. The
    canonical writer updates tasks/lessons.md and regenerates the cache.
    """
    if not ENABLE_ZERO_USEFUL_AUTO_DEPRECATE:
        return 0
    if not lessons:
        return 0
    zero_lids = {
        lid for lid, total in feedback_totals.items()
        if total >= ZERO_USEFUL_DEPRECATE_MIN_SAMPLES and useful_counts.get(lid, 0) == 0
    }
    if not zero_lids:
        return 0
    changed_ids = []
    for lesson in lessons:
        lid = str(lesson.get('id', '') or '')
        if not lid or lid not in zero_lids:
            continue
        if lesson.get('deprecated', False) or str(lesson.get('status', '')).lower() == 'deprecated':
            continue
        changed_ids.append(lid)
    if project_id and script_dir:
        writer = os.path.join(script_dir, 'scripts', 'lesson_write.sh')
        if not os.path.isfile(writer):
            raise RuntimeError(f'canonical lesson writer not found: {writer}')
        for lesson_id in sorted(changed_ids):
            subprocess.run(
                ['bash', writer, project_id, '--retire', lesson_id],
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )

    # The cache snapshot was loaded before the writer ran. Keep the in-memory
    # view consistent so retired lessons are not re-injected in this deploy.
    changed = 0
    for lesson in lessons:
        if str(lesson.get('id', '') or '') in changed_ids:
            lesson['deprecated'] = True
            lesson['deprecation_reason'] = 'auto_useful_rate_zero'
            lesson['retired'] = True
            changed += 1
    if changed:
        print(f'[INJECT] auto-retired zero-useful lessons via canonical SSOT writer: {changed_ids}', file=sys.stderr)
    return changed

def build_lesson_detail(lesson):
    if_then = lesson.get('if_then')
    if isinstance(if_then, dict):
        cond = str(if_then.get('if', '') or '').strip()
        action = str(if_then.get('then', '') or '').strip()
        reason = str(if_then.get('because', '') or '').strip()
        if cond and action and reason:
            return f'IF: {cond} → THEN: {action} (BECAUSE: {reason})'
        if cond and action:
            return f'IF: {cond} → THEN: {action}'
        if action and reason:
            return f'THEN: {action} (BECAUSE: {reason})'
        if cond and reason:
            return f'IF: {cond} (BECAUSE: {reason})'
        if cond:
            return f'IF: {cond}'
        if action:
            return f'THEN: {action}'
        if reason:
            return f'BECAUSE: {reason}'
    return str(lesson.get('detail', '') or lesson.get('content', '') or lesson.get('summary', '') or '')

try:
    with open(task_file) as f:
        data = yaml.load(f, Loader=yaml.SafeLoader)

    if not data or 'task' not in data:
        print('[INJECT] No task section in YAML, skipping', file=sys.stderr)
        sys.exit(0)

    task = data['task']
    project = task.get('project', '')
    task_type = str(task.get('task_type') or task.get('type') or task.get('scope_mode') or 'unknown').lower().strip()
    MIN_KEYWORD_SCORE = MIN_KEYWORD_SCORE_BY_TASK_TYPE.get(task_type, MIN_KEYWORD_SCORE_BY_TASK_TYPE['default'])
    parent_cmd = str(task.get('parent_cmd', '') or '').strip()

    # L4 direct-training ACs are injected as a dict schema before this
    # function runs.  Rewriting the task for related lessons can normalize it
    # into a list and silently break that training contract; template context
    # therefore wins over optional lesson injection.
    if parent_cmd.startswith('cmd_training_L4_') and task_type == 'normal':
        print('[INJECT] L4 training template: preserving acceptance_criteria schema; related lesson rewrite skipped', file=sys.stderr)
        sys.exit(0)

    def extract_keywords(text, min_len=4):
        words = re.split(r'[^a-zA-Z0-9_\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FFF]+', str(text or ''))
        seen = set()
        keywords = []
        for word in words:
            word = word.lower().strip()
            if len(word) < min_len or word in seen:
                continue
            seen.add(word)
            keywords.append(word)
        return keywords

    command_text = str(task.get('command', '') or '')
    stk_path = os.path.join(script_dir, 'queue', 'shogun_to_karo.yaml')
    if not command_text and parent_cmd and os.path.exists(stk_path):
        try:
            with open(stk_path, encoding='utf-8') as stk_f:
                stk_data = yaml.load(stk_f, Loader=yaml.SafeLoader) or {}
            cmd_entry = (stk_data.get('commands') or {}).get(parent_cmd, {})
            command_text = str(cmd_entry.get('command', '') or '')
        except Exception as e:
            print(f'[INJECT] WARN: shogun_to_karo.yaml read failed for command keywords: {e}', file=sys.stderr)
    useful_rates, feedback_totals, useful_counts = compute_useful_rates(script_dir)

    # ═══ 偵察固有教訓リスト (cmd_1340) ═══
    # recon/scout/research タスクには以下の教訓のみ注入(全スキップ→固定リスト注入に変更)
    # 選定基準: recon/偵察/scope/search タグ持ちから偵察品質に直結する教訓を選定
    # 新規偵察教訓の追加手順:
    #   1. lessons.yamlに教訓を登録(lesson_write.sh経由)
    #   2. このRECON_LESSON_IDSセットにIDを追加
    #   3. リスト外の教訓は偵察タスクではスキップされる(CTX浪費防止)
    RECON_LESSON_IDS = {'L219', 'L211', 'L213', 'L104', 'L129', 'L128'}
    # L159 is useful only for large, independently splittable reconnaissance.
    # Keeping it in the blanket recon allowlist injected it into every small
    # recon task, where recent feedback was 0/3 useful.  Admit it only when the
    # task text states the lesson's actual trigger.
    _l159_trigger_terms = ('5軸', '5つ以上', '大規模偵察', '並列agent', '独立した偵察')
    _l159_trigger_text = ' '.join(str(task.get(key, '') or '') for key in ('title', 'description', 'purpose', 'command'))
    if any(term.casefold() in _l159_trigger_text.casefold() for term in _l159_trigger_terms):
        RECON_LESSON_IDS.add('L159')

    recon_mode = task_type in ('recon', 'scout', 'research')

    if not project:
        # GP-028: 3段フォールバック (task→cmd→current_project)
        fallback_source = None
        if parent_cmd:
            if os.path.exists(stk_path):
                try:
                    with open(stk_path) as stk_f:
                        stk_data = yaml.load(stk_f, Loader=yaml.SafeLoader)
                    cmd_entry = (stk_data or {}).get('commands', {}).get(parent_cmd, {})
                    fallback_project = str(cmd_entry.get('project', '') or '').strip()
                    if fallback_project:
                        project = fallback_project
                        fallback_source = f'shogun_to_karo.yaml ({parent_cmd})'
                except Exception as e:
                    print(f'[INJECT] WARN: shogun_to_karo.yaml read failed: {e}', file=sys.stderr)
        if not project:
            proj_yaml_path = os.path.join(script_dir, 'config', 'projects.yaml')
            if os.path.exists(proj_yaml_path):
                try:
                    with open(proj_yaml_path) as pf:
                        proj_data = yaml.load(pf, Loader=yaml.SafeLoader)
                    cp = str((proj_data or {}).get('current_project', '') or '').strip()
                    if cp:
                        project = cp
                        fallback_source = 'current_project'
                except Exception as e:
                    print(f'[INJECT] WARN: projects.yaml read failed: {e}', file=sys.stderr)
        if not project:
            print('[INJECT] No project field, all fallbacks exhausted, skipping lesson injection', file=sys.stderr)
            sys.exit(0)
        print(f'[INJECT] WARN: project field missing, fallback to {fallback_source} (project={project})', file=sys.stderr)

    # GP-080: 教訓キャッシュ (/tmp/deploy_lesson_cache_{project}_{mtime}.json)
    # YAML解析は遅い(WSL2+大ファイル)。mtimeが同じなら/tmpのJSONキャッシュを使う
    import fcntl
    import hashlib
    import json

    def load_lessons_cached(yaml_path):
        """YAMLをJSONキャッシュ経由でロード。mtime不変ならキャッシュヒット"""
        if not os.path.exists(yaml_path):
            return []
        try:
            with open(yaml_path, 'rb') as source:
                source_bytes = source.read()
        except OSError:
            return []
        source_fp = hashlib.sha256(source_bytes).hexdigest()
        cache_key = hashlib.sha256((yaml_path + '\0' + source_fp).encode()).hexdigest()[:24]
        _cache_dir = os.environ.get('DEPLOY_LESSON_CACHE_DIR', '/tmp')
        os.makedirs(_cache_dir, exist_ok=True)
        cache_path = f'{_cache_dir}/deploy_lesson_cache_{cache_key}.json'
        lock_path = cache_path + '.lock'
        # キャッシュヒット
        if os.path.exists(cache_path):
            try:
                with open(cache_path) as cf:
                    return json.load(cf)
            except Exception:
                pass
        # 同一waveの同時missは1 workerだけが解析し、他workerはsnapshotを読む。
        try:
            with open(lock_path, 'w') as lock_f:
                fcntl.flock(lock_f, fcntl.LOCK_EX)
                if os.path.exists(cache_path):
                    with open(cache_path) as cf:
                        return json.load(cf)
                data = yaml.load(source_bytes.decode('utf-8'), Loader=yaml.SafeLoader)
                lessons = data.get('lessons', []) if data else []
                fd, tmp_path = tempfile.mkstemp(dir=_cache_dir, prefix='.lesson_snapshot.', suffix='.json')
                with os.fdopen(fd, 'w') as cf:
                    json.dump(lessons, cf)
                os.replace(tmp_path, cache_path)
                return lessons
        except Exception:
            return []

    # Active lessons (index) for injection. Archive is for detail lookup only (GP-219).
    index_path = os.path.join(script_dir, 'projects', project, 'lessons.yaml')
    archive_path = os.path.join(script_dir, 'projects', project, 'lessons_archive.yaml')
    lessons_path = index_path if os.path.exists(index_path) else archive_path
    lessons = load_lessons_cached(lessons_path)
    if not lessons and not os.path.exists(lessons_path):
        print(f'[INJECT] WARN: lessons not found for project={project}', file=sys.stderr)
    apply_zero_useful_deprecation(
        lessons, lessons_path, feedback_totals, useful_counts,
        project_id=project, script_dir=script_dir,
    )
    # cmd_2270: プロジェクトソーストラッキング (project-source boostに使用)
    for _l in lessons:
        _l['_source_project'] = project

    # ═══ Platform教訓の追加読み込み ═══
    projects_yaml_path = os.path.join(script_dir, 'config', 'projects.yaml')
    platform_count = 0
    cross_project_count = 0
    cross_project_projects = 0
    pdata = {}
    platform_project_ids = set()
    if os.path.exists(projects_yaml_path):
        try:
            with open(projects_yaml_path) as pf:
                pdata = yaml.load(pf, Loader=yaml.SafeLoader)
            for pj in (pdata or {}).get('projects', []):
                if pj.get('type') == 'platform':
                    platform_project_ids.add(str(pj.get('id', '') or '').strip())
                if pj.get('type') == 'platform' and pj.get('id') != project:
                    plat_index = os.path.join(script_dir, 'projects', pj['id'], 'lessons.yaml')
                    plat_archive = os.path.join(script_dir, 'projects', pj['id'], 'lessons_archive.yaml')
                    plat_path = plat_index if os.path.exists(plat_index) else plat_archive
                    plat_lessons = load_lessons_cached(plat_path)
                    apply_zero_useful_deprecation(
                        plat_lessons, plat_path, feedback_totals, useful_counts,
                        project_id=pj['id'], script_dir=script_dir,
                    )
                    # cmd_2270: platformソースをトラッキング
                    for _l in plat_lessons:
                        _l['_source_project'] = pj['id']
                    platform_count += len(plat_lessons)
                    lessons.extend(plat_lessons)
        except Exception as pe:
            print(f'[INJECT] WARN: platform lessons load failed: {pe}', file=sys.stderr)

    def _lesson_project_allowed(lesson):
        source_project = str(lesson.get('_source_project', '') or '').strip()
        lesson_project = str(lesson.get('project', '') or '').strip()
        if source_project in platform_project_ids:
            return True
        if source_project != project:
            return False
        return not lesson_project or lesson_project == project

    _pre_project_filter = len(lessons)
    lessons = [lesson for lesson in lessons if _lesson_project_allowed(lesson)]
    _project_filtered = _pre_project_filter - len(lessons)
    if _project_filtered:
        print(f'[INJECT] project filter: removed {_project_filtered} lessons outside project={project} (platform allowed)', file=sys.stderr)

    # Deduplicate lessons by ID deterministically.  The task project's SSOT
    # wins over platform copies; within one source the first canonical entry
    # wins.  Loading order can therefore never silently replace project facts.
    _id_to_lesson = {}
    _no_id = []
    for _l in lessons:
        _lid = _l.get('id', '')
        if _lid:
            current = _id_to_lesson.get(_lid)
            if current is None:
                _id_to_lesson[_lid] = _l
            elif current.get('_source_project') != project and _l.get('_source_project') == project:
                _id_to_lesson[_lid] = _l
        else:
            _no_id.append(_l)
    _pre_dedup = len(lessons)
    lessons = list(_id_to_lesson.values()) + _no_id
    if len(lessons) < _pre_dedup:
        print(f'[INJECT] lesson_id dedup: {_pre_dedup} → {len(lessons)} (removed {_pre_dedup - len(lessons)} duplicate IDs)', file=sys.stderr)

    if not lessons:
        # Insert empty related_lessons via text manipulation (avoid yaml.dump on full file)
        with open(task_file, encoding='utf-8') as f:
            raw = f.read()
        import re
        raw = re.sub(r'\n  related_lessons:.*?(?=\n  [a-z]|\Z)', '', raw, flags=re.DOTALL)
        # Append before end of task block
        task_end = re.search(r'\n[a-z]', raw[raw.index('task:'):])
        if task_end:
            pos = raw.index('task:') + task_end.start()
            raw = raw[:pos] + '\n  related_lessons: []' + raw[pos:]
        else:
            raw = raw.rstrip() + '\n  related_lessons: []\n'
        tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
        try:
            with os.fdopen(tmp_fd, 'w', encoding='utf-8') as f:
                f.write(raw)
            os.replace(tmp_path, task_file)
        except:
            os.unlink(tmp_path)
            raise
        print(f'[INJECT] No lessons for project={project} (including platform)', file=sys.stderr)
        sys.exit(0)

    # Build task text for keyword extraction
    # GP-223: purpose/target_path/context_files追加でキーワード関連度向上
    # cmd_2276: commandも統合し、target_path非依存でタスク意図を教訓注入に反映
    title = task.get('title', '')
    description = task.get('description', '')
    purpose = str(task.get('purpose') or '')
    target_path = str(task.get('target_path') or '')
    has_target_path = bool(target_path.strip())
    _cf = task.get('context_files')
    context_files = ' '.join(str(f) for f in _cf if f) if isinstance(_cf, list) else str(_cf or '')
    ac_list = task.get('acceptance_criteria', [])
    if isinstance(ac_list, list):
        ac_text = ' '.join(str(a.get('description', '')) if isinstance(a, dict) else str(a) for a in ac_list)
    else:
        ac_text = str(ac_list or '')
    task_text = f'{title} {description} {purpose} {command_text} {target_path} {context_files} {ac_text}'
    # Training task templates own their AC schema.  Lesson selection may add
    # context but must not gain extra relevance from procedural when/how text
    # and replace that schema through the training injection path.
    _training_identity = str(task.get('parent_cmd') or task.get('task_id') or '')
    use_condition_semantics = not _training_identity.startswith('cmd_training_')

    # Extract keywords: split by non-word chars, then ASCII↔CJK boundary split, dedup
    # GP-225: ASCII↔CJK境界分割で"CDP計測"→["CDP","計測"]に分離+アクロニム(>=2,全大文字)はmin_len免除
    _CJK = r'\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FFF'
    _boundary = re.compile(rf'(?<=[a-zA-Z0-9_])(?=[{_CJK}])|(?<=[{_CJK}])(?=[a-zA-Z0-9_])')
    words = re.split(rf'[^a-zA-Z0-9_{_CJK}]+', task_text)
    expanded = [part for w in words for part in _boundary.split(w) if part]
    keywords = list(set(w.lower() for w in expanded if len(w) > 3 or (len(w) >= 2 and w.isupper() and w.isascii())))

    # cmd_3231: target_pathなし時はキーワードスコアリング閾値を引き上げ、低関連教訓の注入を抑止
    NO_TARGET_PATH_MIN_SCORE = int(os.environ.get('NO_TARGET_PATH_MIN_SCORE', '8'))
    if not has_target_path:
        MIN_KEYWORD_SCORE = max(MIN_KEYWORD_SCORE, NO_TARGET_PATH_MIN_SCORE)
        print(f'[INJECT] no target_path: MIN_KEYWORD_SCORE raised to {MIN_KEYWORD_SCORE}', file=sys.stderr)

    SEMANTIC_LESSON_BOOST = int(os.environ.get('SEMANTIC_LESSON_BOOST', '20'))

    def _split_semantic_cell(value):
        return [
            item.strip().strip('`')
            for item in str(value or '').split(',')
            if item.strip() and item.strip() != 'なし'
        ]

    def _semantic_concept_lesson_boosts(query_text):
        """Boost lessons linked from matched semantic concepts in docs/semantic-index."""
        index_md = os.path.join(script_dir, 'docs', 'semantic-index', 'index.md')
        if not os.path.exists(index_md):
            return {}, []
        try:
            raw_index = open(index_md, encoding='utf-8').read()
        except Exception:
            return {}, []

        query_fold = str(query_text or '').casefold()
        boosts = {}
        matched_concepts = []
        for section in re.split(r'(?m)^##\s+', raw_index)[1:]:
            lines = section.splitlines()
            if not lines:
                continue
            heading = lines[0].strip()
            if ' — ' in heading:
                concept_id, heading_label = heading.split(' — ', 1)
            else:
                concept_id, heading_label = heading, ''
            attrs = {'id': concept_id.strip(), 'label': heading_label.strip()}
            for line in lines[1:]:
                stripped = line.strip()
                if not stripped.startswith('|') or not stripped.endswith('|'):
                    continue
                parts = stripped.split('|')
                if len(parts) < 4:
                    continue
                left = parts[1].strip()
                right = '|'.join(parts[2:-1]).strip()
                if left in {'id', 'label', 'aliases', 'related_lessons'}:
                    attrs[left] = right

            lesson_ids = _split_semantic_cell(attrs.get('related_lessons', ''))
            if not lesson_ids:
                continue
            terms = [attrs.get('label', ''), *_split_semantic_cell(attrs.get('aliases', ''))]
            matched_terms = [
                term for term in terms
                if term and (term.casefold() in query_fold or query_fold in term.casefold())
            ]
            if not matched_terms:
                continue
            cid = attrs.get('id') or concept_id.strip()
            matched_concepts.append(cid)
            for lid in lesson_ids:
                boosts[lid] = max(boosts.get(lid, 0), SEMANTIC_LESSON_BOOST)

            if len(matched_concepts) >= 5:
                break
        return boosts, matched_concepts

    def _resolve_memory_db_read_path(db_path):
        """cmd_3758: event_concepts全表スキャンをext4キャッシュ経由に迂回する。
        WSL2の/mnt/cは9pマウントで、464MB DBへのGROUP BY/JOINランダムI/Oが
        1クエリ40-60s級になる(scripts/memory_db_query.shのwarmキャッシュでは<1s)。
        memory_db_query.shのprepare_memory_db_for_read(L77-125)と同じ判定を
        Python側から再現し、同一キャッシュを共有する。取得失敗時はdb_pathをそのまま返す
        (テスト用フィクスチャDB等、キャッシュ層が使えない環境でも既存動作を維持)。"""
        if os.environ.get('SHOGUN_MEMORY_DB_QUERY_DISABLE_CACHE', '0') == '1':
            return db_path
        if os.environ.get('SHOGUN_DISABLE_MEMORY_DB_CACHE', '0') == '1':
            return db_path
        lib_dir = os.path.join(script_dir, 'scripts')
        try:
            if lib_dir not in sys.path:
                sys.path.insert(0, lib_dir)
            import memory_db_live_insert as _mdbi
            cache_path = _mdbi.memory_db_cache_path(db_path)
        except Exception:
            return db_path

        def _mtime(path):
            try:
                return os.path.getmtime(path)
            except OSError:
                return None

        cache_mtime = _mtime(cache_path)
        _build_cmd = [
            sys.executable, '-c',
            'import sys; sys.path.insert(0, sys.argv[1]); '
            'import memory_db_live_insert as m; m.create_memory_db_ext4_cache(sys.argv[2])',
            lib_dir, db_path,
        ]
        if cache_mtime is None or os.path.getsize(cache_path) == 0:
            # キャッシュ未生成: 初回のみ同期構築(タイムアウト保護)。以降の呼出は常にwarmキャッシュを使う
            try:
                import subprocess
                subprocess.run(
                    _build_cmd,
                    timeout=int(os.environ.get('SHOGUN_MEMORY_DB_CACHE_INIT_TIMEOUT', '30')),
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False,
                )
            except Exception:
                return db_path
            return cache_path if os.path.exists(cache_path) and os.path.getsize(cache_path) > 0 else db_path

        src_mtime = _mtime(db_path)
        wal_mtime = _mtime(f'{db_path}-wal')
        shm_mtime = _mtime(f'{db_path}-shm')
        if any(m is not None and m > cache_mtime for m in (src_mtime, wal_mtime, shm_mtime)):
            try:
                import subprocess
                subprocess.Popen(
                    _build_cmd,
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True,
                )
            except Exception:
                pass
        return cache_path

    def _memory_db_concept_lesson_boosts(query_text, seed_concepts=None):
        """Boost lesson IDs found in memory events connected to matched event_concepts."""
        import sqlite3

        db_path = os.environ.get(
            'MEMORY_DB_PATH',
            os.path.join(script_dir, 'data', 'multi_agent_shogun_memory.db'),
        )
        if not os.path.exists(db_path):
            return {}, [], 0

        query_fold = str(query_text or '').casefold()
        if not query_fold.strip():
            return {}, [], 0

        db_read_path = _resolve_memory_db_read_path(db_path)
        try:
            conn = sqlite3.connect(f'file:{db_read_path}?mode=ro', uri=True, timeout=2.0)
        except Exception:
            return {}, [], 0

        matched_concepts = []
        seed_concepts = [str(c).strip() for c in (seed_concepts or []) if str(c).strip()]
        try:
            rows = conn.execute(
                """
                SELECT concept_name
                FROM event_concepts
                GROUP BY concept_name
                ORDER BY MAX(relevance_score) DESC, COUNT(*) DESC
                LIMIT 1000
                """
            ).fetchall()
            available_concepts = {str(c or '').strip() for (c,) in rows}
            for concept in seed_concepts:
                if concept in available_concepts and concept not in matched_concepts:
                    matched_concepts.append(concept)
            for (concept_name,) in rows:
                concept = str(concept_name or '').strip()
                if not concept:
                    continue
                concept_fold = concept.casefold()
                if concept_fold in query_fold or query_fold in concept_fold:
                    matched_concepts.append(concept)
                if len(matched_concepts) >= 10:
                    break

            if not matched_concepts:
                return {}, [], 0

            placeholders = ','.join('?' for _ in matched_concepts)
            event_rows = conn.execute(
                f"""
                SELECT e.summary, e.detail, e.concepts, e.cmd_id
                FROM event_concepts AS c
                JOIN events AS e ON e.id = c.event_id
                WHERE c.concept_name IN ({placeholders})
                ORDER BY COALESCE(e.ts, '') DESC
                LIMIT 300
                """,
                matched_concepts,
            ).fetchall()
        except Exception:
            return {}, [], 0
        finally:
            conn.close()

        boost = int(os.environ.get('MEMORY_DB_LESSON_BOOST', str(SEMANTIC_LESSON_BOOST)))
        boosts = {}
        lesson_re = re.compile(r'(?<![A-Za-z0-9_])L\d{2,4}(?![A-Za-z0-9_])')
        for row in event_rows:
            event_text = ' '.join(str(v or '') for v in row)
            for lid in lesson_re.findall(event_text):
                boosts[lid] = max(boosts.get(lid, 0), boost)
        return boosts, matched_concepts, len(event_rows)

    semantic_lesson_boosts, semantic_matched_concepts = _semantic_concept_lesson_boosts(task_text)
    memory_db_lesson_boosts, memory_db_matched_concepts, memory_db_event_count = _memory_db_concept_lesson_boosts(
        task_text,
        semantic_matched_concepts,
    )
    if memory_db_matched_concepts or memory_db_lesson_boosts or memory_db_event_count:
        print(
            '[INJECT] memory_db_boost: '
            f'concepts={len(memory_db_matched_concepts)} '
            f'lessons={len(memory_db_lesson_boosts)} '
            f'events={memory_db_event_count}',
            file=sys.stderr,
        )
    lesson_boosts = dict(semantic_lesson_boosts)
    for _lid, _boost in memory_db_lesson_boosts.items():
        lesson_boosts[_lid] = max(lesson_boosts.get(_lid, 0), _boost)

    # cmd_2606: target_path由来のサブドメインで教訓を絞る。
    # subdomain未設定の既存教訓は後方互換のため全サブドメインにマッチさせる。
    SUBDOMAIN_ALIASES = {
        'frontend': 'fe',
        'front': 'fe',
        'ui': 'fe',
        'fe': 'fe',
        'backend': 'be',
        'back': 'be',
        'api': 'be',
        'be': 'be',
        'grid_search': 'gs',
        'grid-search': 'gs',
        'gridsearch': 'gs',
        'gs': 'gs',
        'infra': 'infra',
        'platform': 'infra',
    }

    def _as_str_list(value):
        if isinstance(value, list):
            return [str(v) for v in value if v]
        if isinstance(value, str) and value:
            return [value]
        return []

    def _normalize_subdomains(value):
        if value is None or value == '':
            return set()
        if isinstance(value, str):
            raw_items = re.split(r'[, ]+', value)
        elif isinstance(value, list):
            raw_items = value
        else:
            raw_items = [value]
        normalized = set()
        for item in raw_items:
            key = str(item).lower().strip()
            if not key:
                continue
            normalized.add(SUBDOMAIN_ALIASES.get(key, key))
        return normalized

    def _infer_subdomains_from_paths(paths):
        inferred = set()
        for raw_path in paths:
            path = str(raw_path).replace('\\', '/').lower().strip()
            if not path:
                continue
            basename = os.path.basename(path)
            if '/frontend/' in path or path.startswith('frontend/'):
                inferred.add('fe')
            if '/backend/' in path or path.startswith('backend/') or '/app/api/' in path:
                inferred.add('be')
            if (
                '/grid_search/' in path
                or '/outputs/grid_search/' in path
                or 'grid_search' in path
                or basename.startswith('run_077')
                or basename.startswith('gs_')
            ):
                inferred.add('gs')
            if (
                path.startswith(('scripts/', 'queue/', 'context/', 'instructions/', 'projects/', 'config/', 'tests/'))
                and not inferred
            ):
                inferred.add('infra')
        return inferred

    task_subdomains = _infer_subdomains_from_paths(_as_str_list(task.get('target_path', '')))

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
                    tdata = yaml.load(tf, Loader=yaml.SafeLoader)
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

    # (3) タグ推定が空かつtarget_pathあり → pathディレクトリベースでタグ推定
    # cmd_3413: task_tags空+target_pathあり時の全教訓フォールバック(L5017-5018)を削減するため
    # target_pathのディレクトリ構造からプロジェクト文脈タグを推定する
    if not task_tags and has_target_path:
        _path_lower = target_path.lower().replace('\\', '/')
        _path_tag_rules_dir = [
            (r'(?:^|/)scripts/', 'infra'),
            (r'(?:^|/)context/', 'infra'),
            (r'(?:^|/)config/', 'infra'),
            (r'(?:^|/)queue/', 'infra'),
            (r'(?:^|/)instructions/', 'infra'),
            (r'(?:^|/)docs/', 'infra'),
            (r'(?:^|/)backend/', 'api'),
            (r'(?:^|/)frontend/', 'frontend'),
            (r'(?:^|/)tests?/', 'testing'),
        ]
        for _ppat, _ptag in _path_tag_rules_dir:
            if re.search(_ppat, _path_lower):
                task_tags = [_ptag]
                tag_inferred = True
                print(f'[INJECT] path-dir tag inferred: {target_path!r} -> tags={task_tags}', file=sys.stderr)
                break

    # Keep only active lessons: status=confirmed or undefined (default=confirmed)
    confirmed_lessons = []
    filtered_draft = 0
    filtered_deprecated = 0
    filtered_retired = 0
    for lesson in lessons:
        # Applicability metadata is an executable contract.  Missing tags or
        # malformed when/scope/target_files must fail closed, not be coerced
        # into a broad keyword candidate.
        _tags_value = lesson.get('tags')
        _when_value = lesson.get('when')
        _scope_value = lesson.get('scope')
        _targets_value = lesson.get('target_files')
        _metadata_types_valid = (
            isinstance(_tags_value, (list, str))
            and isinstance(_when_value, (str, type(None)))
            and isinstance(_scope_value, (str, type(None)))
            and isinstance(_targets_value, (list, str, type(None)))
        )
        if not _metadata_types_valid or not _tags_value:
            continue
        # Skip retired lessons (cmd_1297: 退役制度)
        if lesson.get('retired', False):
            filtered_retired += 1
            continue
        l_status = str(lesson.get('status', 'confirmed')).lower()
        if l_status == 'deprecated':
            filtered_deprecated += 1
            continue
        if lesson.get('deprecated', False):
            filtered_deprecated += 1
            continue
        if str(lesson.get('superseded_by', '') or '').strip():
            filtered_deprecated += 1
            continue
        if l_status != 'confirmed':
            filtered_draft += 1
            continue
        confirmed_lessons.append(lesson)

    if task_subdomains:
        _pre_subdomain_count = len(confirmed_lessons)
        _subdomain_filtered = []
        for lesson in confirmed_lessons:
            lesson_subdomains = _normalize_subdomains(lesson.get('subdomain'))
            if not lesson_subdomains or (lesson_subdomains & task_subdomains):
                _subdomain_filtered.append(lesson)
        confirmed_lessons = _subdomain_filtered
        _removed_subdomain_count = _pre_subdomain_count - len(confirmed_lessons)
        if _removed_subdomain_count > 0:
            print(
                f'[INJECT] subdomain filter: removed {_removed_subdomain_count} lessons '
                f'(task_subdomains={sorted(task_subdomains)})',
                file=sys.stderr,
            )

    # ═══ 偵察モード: 固定リストの教訓のみ通過 (cmd_1340) ═══
    if recon_mode:
        recon_filtered = [l for l in confirmed_lessons if l.get('id', '') in RECON_LESSON_IDS]
        recon_skipped_count = len(confirmed_lessons) - len(recon_filtered)
        confirmed_lessons = recon_filtered
        print(f'[INJECT] recon_mode: {len(confirmed_lessons)} recon-specific lessons selected (skipped {recon_skipped_count} non-recon)', file=sys.stderr)

    # ═══ target_filesマッチング: ファイルレベルフィルタ (cmd_1563) ═══
    # 教訓にtarget_files指定がある場合、タスクのtarget_pathまたはfiles_modifiedとマッチ時のみ注入
    task_target_path = task.get('target_path', '')
    task_files_modified = task.get('files_modified', [])
    if isinstance(task_target_path, str):
        _ttp_list = [task_target_path] if task_target_path else []
    elif isinstance(task_target_path, list):
        _ttp_list = [str(p) for p in task_target_path if p]
    else:
        _ttp_list = []
    if isinstance(task_files_modified, str):
        task_files_modified = [task_files_modified] if task_files_modified else []
    elif isinstance(task_files_modified, list):
        task_files_modified = [str(p) for p in task_files_modified if p]
    else:
        task_files_modified = []
    _all_task_files = _ttp_list + task_files_modified

    def _target_files_match(lesson_target_files, task_files):
        """教訓のtarget_filesパターンがタスクファイルのいずれかにマッチするか判定"""
        for pattern in lesson_target_files:
            pattern = str(pattern).strip()
            if not pattern:
                continue
            for tf in task_files:
                if fnmatch.fnmatch(tf, pattern) or fnmatch.fnmatch(os.path.basename(tf), pattern):
                    return True
                if fnmatch.fnmatch(os.path.basename(tf), os.path.basename(pattern)):
                    return True
        return False

    def _lesson_matches_task_target_path(lesson):
        """target_path/files_modifiedに一致するtarget_files教訓を順位付けで強く優先する。"""
        lesson_target_files = lesson.get('target_files', [])
        if isinstance(lesson_target_files, str):
            lesson_target_files = [lesson_target_files]
        if not any(str(p).strip() for p in lesson_target_files):
            return False
        return _target_files_match(lesson_target_files, _all_task_files)

    def _lesson_has_only_report_artifact_target_match(lesson):
        """報告YAML artifact全般への一致を、対象コードの関連性として扱わない。"""
        lesson_target_files = lesson.get('target_files', [])
        if isinstance(lesson_target_files, str):
            lesson_target_files = [lesson_target_files]
        patterns = [str(p).strip() for p in lesson_target_files if str(p).strip()]
        if not patterns:
            return False
        task_files = [str(p).strip() for p in _all_task_files if str(p).strip()]
        if not task_files or not all(p.startswith('queue/reports/') for p in task_files):
            return False
        non_report_patterns = [p for p in patterns if not p.startswith('queue/reports/')]
        return bool(non_report_patterns)

    def _path_relevance_terms(task_files):
        terms = set()
        for path in task_files:
            path = str(path or '').lower()
            if not path:
                continue
            terms.update(extract_keywords(path, min_len=3))
            base = os.path.basename(path)
            stem, _ = os.path.splitext(base)
            terms.update(t for t in re.split(r'[^a-z0-9]+', stem.lower()) if len(t) >= 3)
        return terms

    task_file_terms = _path_relevance_terms(_all_task_files)

    def _universal_without_target_files_is_relevant(lesson, l_tags):
        """target_filesなしuniversalが全cmdへ漏れるのを防ぐため、target_pathとの語彙関連を要求する。"""
        lesson_target_files = lesson.get('target_files', [])
        if isinstance(lesson_target_files, str):
            lesson_target_files = [lesson_target_files]
        if any(str(p).strip() for p in lesson_target_files):
            return _target_files_match(lesson_target_files, _all_task_files)
        non_universal_tags = {t for t in l_tags if t != 'universal'}
        if task_tags and (set(task_tags) & non_universal_tags):
            return True
        if not task_file_terms:
            return True
        lesson_text = ' '.join(str(lesson.get(k, '') or '') for k in ('id', 'title', 'summary', 'content', 'source')).lower()
        lesson_text += ' ' + ' '.join(non_universal_tags)
        lesson_terms = set(extract_keywords(lesson_text, min_len=3))
        return bool(task_file_terms & lesson_terms)

    _GENERIC_WHEN = {
        '', '未設定', '同種の作業・判断・検証を行う時',
        '同種の作業を行う時', '関連作業を行う時',
    }

    def _condition_terms(value):
        """Extract bounded applicability terms; boilerplate is not evidence."""
        text = str(value or '').strip()
        if text in _GENERIC_WHEN:
            return set()
        return set(extract_keywords(text, min_len=4))

    task_condition_terms = set(extract_keywords(task_text, min_len=4))
    task_scope_terms = set(extract_keywords(
        ' '.join(str(task.get(k, '') or '') for k in ('scope', 'scope_mode', 'task_type', 'type')),
        min_len=3,
    ))

    def _lesson_has_applicability_evidence(lesson):
        """Require a concrete when/scope/target_files fact, never project or boost alone."""
        if _lesson_matches_task_target_path(lesson):
            return True
        when_terms = _condition_terms(lesson.get('when'))
        if when_terms and (when_terms & task_condition_terms):
            return True
        lesson_scope_terms = _condition_terms(lesson.get('scope'))
        return bool(lesson_scope_terms and (lesson_scope_terms & task_scope_terms))

    def _lesson_tags_compatible(l_tags):
        """Task kind/domain and lesson tags must agree; universal is not a wildcard."""
        concrete = {t for t in l_tags if t != 'universal'}
        if concrete and task_tags and (concrete & set(task_tags)):
            return True
        type_aliases = {
            'recon': {'recon', 'research', 'scout'},
            'scout': {'recon', 'research', 'scout'},
            'research': {'recon', 'research', 'analysis'},
            'impl': {'impl', 'implementation', 'code'},
            'exact': {'exact', 'impl', 'implementation', 'code'},
            'focused': {'focused', 'impl', 'implementation', 'code'},
            'hotfix': {'hotfix', 'impl', 'implementation', 'code'},
        }
        return bool(concrete & type_aliases.get(task_type, {task_type}))

    # target_filesフィルタ: 明示target_filesはタグより強い制約として扱う。
    # narrow lessonがタグ一致だけで別ファイルtaskへ漏れると useful率を悪化させる。
    _tf_excluded_ids = set()  # target_files不一致で除外候補のID
    if _all_task_files:
        for _l in confirmed_lessons:
            if _l.get('_cross_project_opt_in'):
                continue
            # cmd_karo_hotfix_boost_bypass_production_path_20260725 AC1:
            # boost付きでもtarget_files不一致なら除外対象にする(boostは関連度加点であり
            # 明示target_files制約のバイパス根拠ではない)
            _ltf = _l.get('target_files', [])
            if not _ltf:
                continue
            if isinstance(_ltf, str):
                _ltf = [_ltf]
            if _lesson_has_only_report_artifact_target_match(_l):
                _tf_excluded_ids.add(_l.get('id', ''))
                continue
            if not _target_files_match(_ltf, _all_task_files):
                _tf_excluded_ids.add(_l.get('id', ''))
        if _tf_excluded_ids:
            print(f'[INJECT] target_files filter: {len(_tf_excluded_ids)} lessons marked for exclusion (task files: {[os.path.basename(f) for f in _all_task_files[:3]]})', file=sys.stderr)
    else:
        # GP-218: タスクファイルなし→target_files設定ありの教訓は除外(マッチ不可能)
        for _l in confirmed_lessons:
            if _l.get('_cross_project_opt_in'):
                continue
            _ltf = _l.get('target_files', [])
            if isinstance(_ltf, str):
                _ltf = [_ltf]
            if _ltf and any(str(p).strip() for p in _ltf):
                # cmd_karo_hotfix_boost_bypass_production_path_20260725 AC1:
                # boost付きもマッチ不可能な以上は除外する
                _tf_excluded_ids.add(_l.get('id', ''))
        if _tf_excluded_ids:
            print(f'[INJECT] target_files filter (no task files): {len(_tf_excluded_ids)} lessons with target_files excluded', file=sys.stderr)

    # ═══ タグマッチ: 教訓をフィルタ ═══
    # universal教訓は別管理（常に注入）
    universal_lessons = []
    tag_candidates = []

    for lesson in confirmed_lessons:
        l_tags = lesson.get('tags', [])
        if isinstance(l_tags, str):
            l_tags = [l_tags]
        l_tags = [str(t).lower().strip() for t in l_tags if t]

        # Relevance boosts and project membership only rank already-applicable
        # lessons.  They can never manufacture task applicability.
        if not _lesson_has_applicability_evidence(lesson):
            continue

        # universal教訓は広すぎるため、target_files未設定ならtarget_pathとの関連性を確認する。
        if 'universal' in l_tags:
            if _universal_without_target_files_is_relevant(lesson, l_tags) and (
                _lesson_tags_compatible(l_tags) or _condition_terms(lesson.get('when'))
            ):
                universal_lessons.append(lesson)
            else:
                _tf_excluded_ids.add(lesson.get('id', ''))
            continue

        # タグなし旧形式は適用種別を証明できないため、target_files一致時だけ許可する。
        if not l_tags:
            if _lesson_matches_task_target_path(lesson):
                tag_candidates.append(lesson)
            continue

        # task_tagsが決定済みの場合、タグ重複チェック
        if task_tags:
            if _lesson_tags_compatible(l_tags):
                tag_candidates.append(lesson)
        # cmd_3271: target_pathなし+tag推定失敗 → タグ付き教訓は除外（NOT_USEFUL量産防止）
        # target_pathあり時は安全側フォールバック維持（既存動作）
        elif has_target_path:
            tag_candidates.append(lesson)
        # else: target_pathもtask_tagsもなし → この教訓をskip

    # (5) タスクにtagsがなくキーワード推定もできない → 全教訓fallback
    # cmd_3271: target_pathなし時は全量fallback禁止（has_target_pathがある場合のみ実行）
    if not task_tags and has_target_path:
        tag_candidates = [l for l in confirmed_lessons if l not in universal_lessons]
        print(f'[INJECT] WARN: full-lesson fallback triggered (path-dir inference failed, target_path={target_path!r}, candidates={len(tag_candidates)})', file=sys.stderr)
    elif not task_tags:
        print(f'[INJECT] no target_path + no task_tags: skipping full-lesson fallback ({len(confirmed_lessons)} lessons withheld)', file=sys.stderr)

    # target_filesフィルタ適用: target_files不一致はタグ一致でも除外する。
    if _tf_excluded_ids:
        _pre_tf_count = len(tag_candidates)
        tag_candidates = [l for l in tag_candidates if l.get('id','') not in _tf_excluded_ids]
        _tf_actually_removed = _pre_tf_count - len(tag_candidates)
        if _tf_actually_removed > 0:
            print(f'[INJECT] target_files post-filter: removed {_tf_actually_removed}', file=sys.stderr)

    # cmd_karo_gp196: AC1 — MAX_INJECT=10 総合注入上限（universalは内数）
    # cmd_2270: 3→10に拡大。キーワード関連度スコアリングで上位10件に絞る
    # cmd_3405: 10→3に縮小。useful_rate=16.7%(<30%)の根因=過剰注入修正
    # tag fallback/useful_rate処理より前に定義し、条件分岐での未定義参照を防ぐ
    MAX_INJECT = int(os.environ.get('MAX_INJECT_OVERRIDE', '3'))

    # ═══ スコアリング: タグマッチ候補内でキーワードスコア順位付け ═══
    scored = []
    keyword_score_filtered = 0
    for lesson in tag_candidates:
        lid = lesson.get('id', '')
        l_title = str(lesson.get('title', ''))
        l_summary = str(lesson.get('summary', ''))
        l_content = str(lesson.get('content', ''))
        l_source = str(lesson.get('source', ''))
        l_when = str(lesson.get('when', '') or '').strip()
        l_how = str(lesson.get('how', '') or '').strip()

        title_text = l_title.lower()
        # AC文の語は要約だけでなく、教訓が適用される条件(when)と
        # 実行手順(how)にも現れる。ここを除外すると表層語の一致だけで
        # 注入され、意味的に適合する教訓が低スコアで落ちる。
        condition_text = f'{l_when} {l_how}' if use_condition_semantics else ''
        other_text = f'{l_summary} {l_content} {l_source} {condition_text}'.lower()

        keyword_score = 0
        for kw in keywords:
            # cmd_2270: 頻度重み付きスコアリング (engram-style: presence→frequency count)
            # タイトル内出現回数×3 + その他テキスト内出現回数×1
            keyword_score += title_text.count(kw) * 3 + other_text.count(kw) * 1

        score = keyword_score

        # D0: when未設定教訓のスコア降格 — when条件なしはキーワードのみで注入され
        # NOT_USEFUL率が高い(199/828=24%がwhen未設定, useful_rate 19%)
        if (not l_when or l_when == '未設定') and not _condition_terms(lesson.get('scope')) \
                and not _lesson_matches_task_target_path(lesson):
            score -= NO_WHEN_PENALTY

        # cmd_3254: boostはkeyword_score>0の教訓にのみ適用
        # 根因: keyword_score=0でもboost(20)+project(2)=22でMIN_KEYWORD_SCOREを突破し
        # 全NOT_USEFUL教訓の28%(16/58)を占めていた(useful_rate 3.4%の主因)
        semantic_boost = lesson_boosts.get(lid, 0)
        if semantic_boost and keyword_score > 0:
            score += semantic_boost

        cross_project_score = lesson.get('_cross_project_score', 0) or 0
        # 是正2: cross-project注入の精度向上 — project不一致教訓はraw keyword_scoreで高閾値フィルタ
        # 根因: platform教訓(infra等)がdm-signal cmdにkeyword_score低値で素通りしNOT_USEFUL量産(L1290-L1292事例)
        if (lesson.get('_source_project') and lesson.get('_source_project') != project
                and keyword_score < MIN_KEYWORD_SCORE_CROSS_PROJECT):
            keyword_score_filtered += 1
            continue
        if cross_project_score and score < cross_project_score:
            score = cross_project_score

        # cmd_3466: target_path boost is a ranking boost, not a relevance bypass.
        # keyword_score=0 + target_files basename match was injecting low-useful lessons
        # whose only relation was "this file changed before".
        if keyword_score > 0 and _lesson_matches_task_target_path(lesson):
            score += TARGET_PATH_MATCH_BOOST

        if score <= 0:
            continue

        # 是正1: Bootstrapギャップ解消 — feedback=0件の新規教訓はより高い閾値を要求
        # 根因: 初回注入時feedback=0の教訓はuseful_rateフィルタを素通りしNOT_USEFUL量産(L1291-L1292等)
        _effective_min_score = MIN_KEYWORD_SCORE
        if feedback_totals.get(lid, 0) == 0:
            _effective_min_score = max(_effective_min_score, MIN_KEYWORD_SCORE_ZERO_FEEDBACK)
        if score < _effective_min_score:
            keyword_score_filtered += 1
            continue

        # cmd_2270: プロジェクト一致ボーナス — 同プロジェクト教訓を優先注入
        if lesson.get('_source_project') == project:
            score += 2
        scored.append((score, lid, l_summary or l_title))

    if keyword_score_filtered:
        print(f'[INJECT] keyword score filter: removed {keyword_score_filtered} lessons below MIN_KEYWORD_SCORE={MIN_KEYWORD_SCORE}', file=sys.stderr)
    if semantic_lesson_boosts:
        boosted_ids = sorted(set(semantic_lesson_boosts) & {lid for _, lid, _ in scored})
        print(
            f'[INJECT] semantic lesson boost: concepts={semantic_matched_concepts} '
            f'candidate_lessons={sorted(semantic_lesson_boosts)} boosted={boosted_ids} boost={SEMANTIC_LESSON_BOOST}',
            file=sys.stderr,
        )
    if memory_db_lesson_boosts:
        boosted_ids = sorted(set(memory_db_lesson_boosts) & {lid for _, lid, _ in scored})
        print(
            f'[INJECT] memory_db lesson boost: concepts={memory_db_matched_concepts} '
            f'events={memory_db_event_count} candidate_lessons={sorted(memory_db_lesson_boosts)} '
            f'boosted={boosted_ids} boost={os.environ.get("MEMORY_DB_LESSON_BOOST", str(SEMANTIC_LESSON_BOOST))}',
            file=sys.stderr,
        )

    # 忍者成長速度改善: タグマッチしたがキーワード0点の教訓をhelpful_count順でフォールバック注入
    # GP-221: target_filesなし教訓のフォールバック注入廃止。タスク無関係教訓のNOT_USEFUL量産防止
    # cmd_3231: target_pathなし時はfallback注入も無効化（helpful_count順=関連性無視→NOT_USEFUL量産の根因）
    if not scored and task_tags and tag_candidates:
        if not has_target_path:
            print(f'[INJECT] no target_path: skipping tag fallback (would inject {min(len(tag_candidates), MAX_INJECT)} lessons by helpful_count)', file=sys.stderr)
        else:
            _relevant_fallback = [
                l for l in tag_candidates
                if _lesson_matches_task_target_path(l)
            ]
            _tag_fallback = [(l.get('helpful_count',0) or 0, l.get('id',''), str(l.get('summary', l.get('title','')))[:80]) for l in _relevant_fallback]
            _tag_fallback.sort(key=lambda x: -x[0])
            scored = [(1, lid, summ) for hc, lid, summ in _tag_fallback[:MAX_INJECT]]
            if scored:
                print(f'[INJECT] tag fallback: keyword score=0, using {len(scored)} target_path-matched lessons by helpful_count', file=sys.stderr)

    # cmd_1564+karo_idle_fix: useful_rate feedback基盤
    # cmd_2700: mature feedback effectiveness_scoreが低い教訓は注入候補から除外
    # フィードバックデータ(record_lesson_feedback.sh)から実有用率を算出
    effectiveness_excluded = []

    def needs_initial_feedback(lid):
        return feedback_totals.get(lid, 0) < USEFUL_RATE_MIN_SAMPLES

    # universal教訓にもuseful_rateフィルタを適用
    # 有用率が閾値未満のuniversal教訓はtag_candidatesに降格（スコアリング対象に移動）
    if useful_rates and universal_lessons:
        demoted = []
        kept = []
        for lesson in universal_lessons:
            lid = lesson.get('id', '')
            rate = useful_rates.get(lid)
            if rate is not None and rate < USEFUL_RATE_THRESHOLD:
                demoted.append(lesson)
                effectiveness_excluded.append({'id': lid, 'summary': lesson.get('summary', '') or lesson.get('title', '')})
            else:
                kept.append(lesson)
        if demoted:
            demoted_ids = [l.get('id', '?') for l in demoted]
            print(f'[INJECT] universal effectiveness exclusion: {len(demoted)} lessons below {USEFUL_RATE_THRESHOLD*100:.0f}% effectiveness_score: {demoted_ids}', file=sys.stderr)
            universal_lessons = kept

    if useful_rates:
        new_scored = []
        excluded_ids = []
        for score, lid, summary in scored:
            rate = useful_rates.get(lid)
            if rate is not None and rate < USEFUL_RATE_THRESHOLD:
                excluded_ids.append(lid)
                effectiveness_excluded.append({'id': lid, 'summary': summary})
            else:
                new_scored.append((score, lid, summary))
        scored = new_scored
        if excluded_ids:
            print(f'[INJECT] effectiveness exclusion: {len(excluded_ids)} lessons below {USEFUL_RATE_THRESHOLD*100:.0f}% threshold: {excluded_ids}', file=sys.stderr)

    # Sort by score descending, take top 7 (AC5: task-specific max 7)
    scored.sort(key=lambda x: -x[0])

    # Greedy dedup: 類似教訓の枠消費防止
    lessons_by_id = {l.get('id',''): l for l in confirmed_lessons}
    pre_dedup_count = len(scored)
    scored = greedy_dedup(scored, lessons_by_id)

    # cmd_1457: keyword_score(関連度)をprimary sort、helpful_countをtiebreaker
    # 根因: helpful_count最終決定でL074(hc=1086)/L063(hc=1013)等が常に枠占拠(マシュー効果)
    scored_with_helpful = []
    for score, lid, summary in scored:
        lesson = lessons_by_id.get(lid, {})
        helpful = lesson.get('helpful_count', 0) or 0
        scored_with_helpful.append((helpful, score, lid, summary))
    scored_with_helpful.sort(key=lambda x: (-x[1], -x[0]))
    scored = [(s, lid, summ) for _, s, lid, summ in scored_with_helpful]

    # AC4: スコア0時のフォールバック = 注入なし（無関連教訓のCTX浪費防止）

    # cmd_1457: universal教訓の準備（max 1、helpful_count上位）— task-specificに最低2枠確保(忍者成長速度改善1: 2→1)
    MAX_UNIVERSAL = 1
    universal_total_count = len(universal_lessons)
    universal_lessons.sort(key=lambda l: -(l.get('helpful_count', 0) or 0))
    universal_lessons = universal_lessons[:MAX_UNIVERSAL]

    # cmd_1457: universal/task-specific枠分離（universalがtask-specificの枠を奪えない構造）
    # universal: 先頭に配置、最大MAX_UNIVERSAL(2)枠
    # task-specific: 残り枠（最低 MAX_INJECT - MAX_UNIVERSAL = 1枠確保）
    related = []
    withheld = list(effectiveness_excluded)
    universal_added = 0
    seen_ids_final = set()
    lesson_scores = {}
    for _score, _lid, _summary in scored:
        lesson_scores[_lid] = _score

    # Phase 1: Universal枠（最大MAX_UNIVERSAL）
    for ul in universal_lessons:
        ul_id = ul.get('id', '')
        if ul_id in seen_ids_final:
            continue
        if universal_added >= MAX_UNIVERSAL:
            break
        lesson = lessons_by_id.get(ul_id, {})
        detail = build_lesson_detail(lesson)[:200]
        entry = {'id': ul_id, 'summary': ul.get('summary', '') or ul.get('title', '')}
        if detail:
            entry['detail'] = detail
        related.append(entry)
        seen_ids_final.add(ul_id)
        universal_added += 1

    # Phase 2: Task-specific枠（残り全て — universalが不足すれば繰上げ）
    task_specific_slots = MAX_INJECT - len(related)
    task_specific_added = 0
    for _, lid, summary in scored:
        if task_specific_added >= task_specific_slots:
            break
        if lid in seen_ids_final:
            continue
        lesson = lessons_by_id.get(lid, {})
        detail = build_lesson_detail(lesson)[:200]
        entry = {'id': lid, 'summary': summary}
        if detail:
            entry['detail'] = detail
        related.append(entry)
        seen_ids_final.add(lid)
        task_specific_added += 1

    # Withheld: 枠外の教訓
    for ul in universal_lessons:
        ul_id = ul.get('id', '')
        if ul_id not in seen_ids_final:
            if needs_initial_feedback(ul_id):
                continue
            withheld.append({'id': ul_id, 'summary': ul.get('summary', '') or ul.get('title', '')})
    for _, lid, summary in scored:
        if lid not in seen_ids_final:
            if needs_initial_feedback(lid):
                continue
            withheld.append({'id': lid, 'summary': summary})

    task['related_lessons'] = related

    # (A) description冒頭に教訓要約を挿入（忍者が即座に目にする）
    desc_modified = False
    if related:
        desc = task.get('description', '')
        marker = '【注入教訓】'
        if marker not in str(desc):
            lines = [marker + ' 必ず確認してから作業開始せよ']
            for r in related:
                lines.append(f"  - {r['id']}: {r['summary'][:80]}")
            lines.append('─' * 40)
            prefix = '\n'.join(lines) + '\n\n'
            task['description'] = prefix + str(desc or '')
            desc_modified = True

    # GP-240: description埋込IDとrelated_lessons IDの不一致検出
    desc_ids = set(r['id'] for r in related) if related else set()
    rl_ids = set(r['id'] for r in task.get('related_lessons', []) if isinstance(r, dict))
    if desc_ids != rl_ids:
        print(f'[INJECT] WARN: description/related_lessons ID mismatch. desc={sorted(desc_ids)} rl={sorted(rl_ids)}', file=sys.stderr)

    # --- Safe targeted write (avoid full yaml.dump — cmd_1407 AC2) ---
    with open(task_file, 'r', encoding='utf-8') as f:
        raw = f.read()

    # yaml.dump禁止(CLAUDE.md): 手動YAML構築でデータ消失を防止
    def _sv(v, multiline_indent=2):
        if v is None: return 'null'
        if isinstance(v, bool): return str(v).lower()
        if isinstance(v, (int, float)): return str(v)
        s = str(v)
        if '\n' in s:
            return '|-\n' + '\n'.join(' ' * multiline_indent + ln for ln in s.split('\n'))
        sq = chr(39)
        return sq + s.replace(sq, sq + sq) + sq
    def _yaml_lines(key, val, ind=0):
        p = ' ' * ind
        if not isinstance(val, (dict, list)):
            s = _sv(val, ind + 2)
            if '\n' in s:
                parts = s.split('\n')
                return [p + key + ': ' + parts[0]] + [p + x for x in parts[1:]]
            return [p + key + ': ' + s]
        if not val:
            return [p + key + ': ' + ('[]' if isinstance(val, list) else '{}')]
        r = [p + key + ':']
        if isinstance(val, dict):
            for k, v in val.items():
                r.extend(_yaml_lines(k, v, ind + 2))
        else:
            for item in val:
                r.extend(_list_item(item, ind))
        return r
    def _list_item(item, ind):
        p = ' ' * ind
        if not isinstance(item, (dict, list)):
            s = _sv(item, ind + 2)
            if '\n' in s:
                parts = s.split('\n')
                return [p + '- ' + parts[0]] + [p + '  ' + x for x in parts[1:]]
            return [p + '- ' + s]
        if isinstance(item, dict) and item:
            lines = []
            first = True
            for k, v in item.items():
                tag = '- ' if first else '  '
                first = False
                if isinstance(v, (dict, list)) and v:
                    lines.append(p + tag + k + ':')
                    if isinstance(v, list):
                        for sub in v:
                            lines.extend(_list_item(sub, ind + 2))
                    else:
                        for dk, dv in v.items():
                            lines.extend(_yaml_lines(dk, dv, ind + 4))
                else:
                    sv = _sv(v, ind + 4) if not isinstance(v, (dict, list)) else ('[]' if isinstance(v, list) else '{}')
                    if '\n' in sv:
                        parts = sv.split('\n')
                        lines.append(p + tag + k + ': ' + parts[0])
                        lines.extend(parts[1:])
                    else:
                        lines.append(p + tag + k + ': ' + sv)
            return lines
        return [p + '- ' + ('[]' if isinstance(item, list) else '{}')]
    def _safe_section_replace(text, section_name, new_value):
        """Replace a 2-space-indented section under task: without full yaml.dump"""
        frag = '\n'.join(_yaml_lines(section_name, new_value))
        indented = '\n'.join('  ' + line for line in frag.split('\n'))
        # 行ベースのブロック置換（正規表現はマルチライン値で誤マッチする）
        _lines = text.split('\n')
        _result = []
        _skip = False
        _inserted = False
        for _l in _lines:
            _s = _l.lstrip(' ')
            _i = len(_l) - len(_s)
            if _skip:
                if _s == '' or _i > 2 or (_i == 2 and _s.startswith('- ')):
                    continue
                _skip = False
            if _i == 2 and _s.startswith(section_name + ':'):
                _skip = True
                _result.append(indented)
                _inserted = True
                continue
            _result.append(_l)
        text = '\n'.join(_result)
        if not _inserted:
            task_idx = text.index('task:')
            rest = text[task_idx + 5:]
            top_m = re.search(r'^\S', rest, re.MULTILINE)
            if top_m:
                pos = task_idx + 5 + top_m.start()
                text = text[:pos] + indented + '\n' + text[pos:]
            else:
                text = text.rstrip('\n') + '\n' + indented + '\n'
        return text

    raw = _safe_section_replace(raw, 'related_lessons', related)
    if desc_modified:
        raw = _safe_section_replace(raw, 'description', task['description'])

    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w', encoding='utf-8') as f:
            f.write(raw)
        os.replace(tmp_path, task_file)
    except:
        os.unlink(tmp_path)
        raise

    # Postcondition data (cmd_378)
    try:
        with open(postcond_file, 'w') as _pf:
            _pf.write(f'available={len(tag_candidates) + universal_total_count}\n')
            _pf.write(f'injected={len(related)}\n')
            _pf.write(f'task_id={task.get("task_id", "unknown")}\n')
            _pf.write(f'project={project}\n')
            _pf.write(f'injected_ids={" ".join(r["id"] for r in related)}\n')
    except Exception:
        pass

    ids = [r['id'] for r in related]
    tag_info = f'task_tags={task_tags} inferred={tag_inferred}'
    scored_count = len(scored)
    tag_candidate_count = len(tag_candidates)
    print(f'[INJECT] Injected {len(related)} lessons (universal={universal_added}/{universal_total_count}, task_specific={len(related)-universal_added}, platform={platform_count}): {ids}', file=sys.stderr)
    print(f'[INJECT]   project={project} {tag_info} scored={scored_count}/{tag_candidate_count} cross_project={cross_project_count}/{cross_project_projects} top_scores={[(s,i) for s,i,_ in scored[:5]]}', file=sys.stderr)
    print(f'[INJECT]   filtered: draft={filtered_draft} deprecated={filtered_deprecated} retired={filtered_retired}', file=sys.stderr)
    dedup_removed = pre_dedup_count - len(scored)
    print(f'[INJECT]   dedup: {dedup_removed} duplicates removed (threshold={DEDUP_THRESHOLD})', file=sys.stderr)

    # ═══ 教訓因果追跡ログ記録 ═══
    impact_log = os.path.join(script_dir, 'logs', 'lesson_impact.tsv')
    cmd_id = task.get('task_id') or task.get('parent_cmd') or 'unknown'
    # cmd_3269: ninja_nameをタスクファイル名から取得（assigned_to未設定時のunknown防止）
    _task_basename = os.path.splitext(os.path.basename(task_file))[0]
    ninja_name = _task_basename if _task_basename and _task_basename != 'unknown' else task.get('assigned_to', 'unknown')
    task_type = task.get('task_type') or task.get('type', 'unknown')
    bloom = task.get('bloom_level', 'unknown')
    impact_header = '\t'.join(IMPACT_COLUMNS) + '\n'

    try:
        os.makedirs(os.path.dirname(impact_log), exist_ok=True)
        ensure_impact_header(impact_log)
        # cmd_3269: cmd_id+lesson_id重複チェック（二重記録防止）
        existing_keys = set()
        if os.path.exists(impact_log):
            try:
                with open(impact_log, 'r', encoding='utf-8', newline='') as ef:
                    reader = csv.DictReader(ef, delimiter='\t')
                    for row in reader:
                        _ek_cmd = (row.get('cmd_id') or '').strip()
                        _ek_lid = (row.get('lesson_id') or '').strip()
                        if _ek_cmd and _ek_lid:
                            existing_keys.add((_ek_cmd, _ek_lid))
            except Exception:
                pass
        write_header = not os.path.exists(impact_log) or os.path.getsize(impact_log) == 0
        skipped_dup = 0
        with open(impact_log, 'a', encoding='utf-8') as lf:
            if write_header:
                lf.write(impact_header)
            ts = datetime.datetime.now().isoformat(timespec='seconds')
            for r in related:
                if (cmd_id, r["id"]) in existing_keys:
                    skipped_dup += 1
                    continue
                score_value = lesson_scores.get(r["id"], 0)
                lf.write(f'{ts}\t{cmd_id}\t{ninja_name}\t{r["id"]}\tinjected\tpending\tpending\t{project}\t{task_type}\t{bloom}\t{score_value}\t0\n')
            for w in withheld:
                if (cmd_id, w["id"]) in existing_keys:
                    skipped_dup += 1
                    continue
                score_value = lesson_scores.get(w["id"], 0)
                lf.write(f'{ts}\t{cmd_id}\t{ninja_name}\t{w["id"]}\twithheld\tpending\tno\t{project}\t{task_type}\t{bloom}\t{score_value}\t0\n')
        written = len(related) + len(withheld) - skipped_dup
        print(f'[INJECT] Impact log: {written} written ({skipped_dup} duplicates skipped) to lesson_impact.tsv', file=sys.stderr)
    except Exception as ie:
        print(f'[INJECT] WARN: impact log write failed: {ie}', file=sys.stderr)

except Exception as e:
    print(f'[INJECT] ERROR: {e}', file=sys.stderr)
    sys.exit(1)
PY
        return 1
    fi
}

# ─── WA頻発パターン教訓注入（cmd_3582: workaround TOP3 → related_lessons） ───
inject_workaround_pattern_lessons() {
    local task_file="$1"
    local ninja_name="$2"
    if [ ! -f "$task_file" ]; then
        log "inject_workaround_pattern_lessons: task file not found: $task_file"
        return 0
    fi

    local workarounds_file="$SCRIPT_DIR/logs/karo_workarounds.yaml"
    if [ ! -f "$workarounds_file" ]; then
        log "inject_workaround_pattern_lessons: karo_workarounds.yaml not found, skipping"
        return 0
    fi

    local py_output
    py_output=$(mktemp)
    local ninja_jp_name
    ninja_jp_name="$(get_japanese_name "$ninja_name" 2>/dev/null || echo "$ninja_name")"
    if ! run_python_logged "$py_output" env TASK_FILE_ENV="$task_file" WORKAROUNDS_FILE_ENV="$workarounds_file" NINJA_NAME_ENV="$ninja_name" NINJA_JP_ENV="$ninja_jp_name" SCRIPT_DIR_ENV="$SCRIPT_DIR" python3 - <<'PY'; then
import os, re, sys, tempfile, yaml

task_file = os.environ['TASK_FILE_ENV']
workarounds_file = os.environ['WORKAROUNDS_FILE_ENV']
ninja_name = os.environ['NINJA_NAME_ENV']
script_dir = os.environ['SCRIPT_DIR_ENV']
ninja_jp_name = os.environ.get('NINJA_JP_ENV', ninja_name)

CATEGORY_LESSON_IDS = {
    'commit_missing': ['L278', 'L342'],
    'report_yaml_format': ['L311'],
    'report_missing': ['L278'],
    'yaml_dump': ['L295'],
    'yaml_dump_policy': ['L295'],
    'scope_contamination': ['L589'],
    'scope_leak': ['L589'],
}

def match_ninja(entry):
    field = str(entry.get('ninja', '') or '')
    if field and field.lower() == ninja_name.lower():
        return True
    return bool(ninja_jp_name) and any(ninja_jp_name in str(entry.get(k, '') or '') for k in ('root_cause', 'detail', 'issue', 'workaround_detail'))

def is_workaround(entry):
    wa = entry.get('workaround')
    if wa is True:
        return True
    if wa is False:
        return False
    return str(entry.get('karo_workaround', '') or '').lower() == 'yes'

def parse_workarounds():
    text = open(workarounds_file, encoding='utf-8').read()
    try:
        loaded = yaml.load(text, Loader=yaml.SafeLoader)
        if isinstance(loaded, dict):
            items = loaded.get('workarounds') or []
        elif isinstance(loaded, list):
            items = loaded
        else:
            items = []
        return [item for item in items if isinstance(item, dict)]
    except yaml.YAMLError:
        pass
    entries = []
    body = re.sub(r'^workarounds:\s*\n', '', text)
    for block in re.split(r'\n(?=- )', body):
        block = block.strip()
        if not block:
            continue
        try:
            parsed = yaml.load(block, Loader=yaml.SafeLoader)
        except yaml.YAMLError:
            continue
        if isinstance(parsed, list) and parsed and isinstance(parsed[0], dict):
            entries.append(parsed[0])
        elif isinstance(parsed, dict):
            entries.append(parsed)
    return entries

def recent_top_categories(limit=3, window=30):
    matched = [e for e in parse_workarounds() if match_ninja(e) and is_workaround(e)][-window:]
    counts, first_pos = {}, {}
    for idx, entry in enumerate(matched):
        cat = str(entry.get('category') or 'uncategorized').strip() or 'uncategorized'
        counts[cat] = counts.get(cat, 0) + 1
        first_pos.setdefault(cat, idx)
    return sorted(counts.items(), key=lambda kv: (-kv[1], first_pos[kv[0]], kv[0]))[:limit]

def load_lessons():
    lessons = {}
    for rel in ('projects/infra/lessons.yaml', 'projects/infra/lessons_archive.yaml'):
        path = os.path.join(script_dir, rel)
        if not os.path.exists(path):
            continue
        try:
            data = yaml.load(open(path, encoding='utf-8'), Loader=yaml.SafeLoader) or {}
        except Exception:
            continue
        for lesson in data.get('lessons') or []:
            if isinstance(lesson, dict):
                lid = str(lesson.get('id') or '').strip()
                if lid and lid not in lessons:
                    lessons[lid] = lesson
    return lessons

def lesson_entry(lesson, category, count):
    summary = str(lesson.get('summary') or lesson.get('title') or '')[:200]
    detail = str(lesson.get('detail') or lesson.get('content') or lesson.get('how') or summary)[:200]
    entry = {'id': str(lesson.get('id')), 'summary': summary, 'wa_category': category, 'wa_count': count}
    if detail:
        entry['detail'] = detail
    return entry

def sv(value, indent=2):
    if value is None:
        return 'null'
    if isinstance(value, bool):
        return str(value).lower()
    if isinstance(value, (int, float)):
        return str(value)
    text = str(value)
    if '\n' in text:
        return '|-\n' + '\n'.join(' ' * indent + line for line in text.split('\n'))
    sq = chr(39)
    return sq + text.replace(sq, sq + sq) + sq

def yaml_lines(key, value, indent=0):
    p = ' ' * indent
    if not isinstance(value, (dict, list)):
        return [p + key + ': ' + sv(value, indent + 2)]
    if not value:
        return [p + key + ': ' + ('[]' if isinstance(value, list) else '{}')]
    rows = [p + key + ':']
    if isinstance(value, dict):
        for k, v in value.items():
            rows.extend(yaml_lines(k, v, indent + 2))
    else:
        for item in value:
            rows.extend(list_item(item, indent))
    return rows

def list_item(item, indent):
    p = ' ' * indent
    if not isinstance(item, dict):
        return [p + '- ' + sv(item, indent + 2)]
    rows, first = [], True
    for k, v in item.items():
        tag = '- ' if first else '  '
        first = False
        if isinstance(v, (dict, list)) and v:
            rows.append(p + tag + k + ':')
            if isinstance(v, list):
                for sub in v:
                    rows.extend(list_item(sub, indent + 2))
            else:
                for dk, dv in v.items():
                    rows.extend(yaml_lines(dk, dv, indent + 4))
        else:
            rows.append(p + tag + k + ': ' + (sv(v, indent + 4) if not isinstance(v, (dict, list)) else ('[]' if isinstance(v, list) else '{}')))
    return rows

def safe_section_replace(text, section_name, value):
    fragment = '\n'.join(yaml_lines(section_name, value))
    indented = '\n'.join('  ' + line for line in fragment.split('\n'))
    out, skip, inserted = [], False, False
    for line in text.split('\n'):
        stripped = line.lstrip(' ')
        indent = len(line) - len(stripped)
        if skip:
            if stripped == '' or indent > 2 or (indent == 2 and stripped.startswith('- ')):
                continue
            skip = False
        if indent == 2 and stripped.startswith(section_name + ':'):
            out.append(indented)
            skip, inserted = True, True
            continue
        out.append(line)
    text = '\n'.join(out)
    if not inserted:
        pos = text.index('task:') + 5
        text = text[:pos] + '\n' + indented + text[pos:]
    return text

def sync_description(description, related):
    marker = '【注入教訓】'
    lines = [marker + ' 必ず確認してから作業開始せよ']
    for item in related:
        if isinstance(item, dict) and item.get('id'):
            lines.append(f"  - {item.get('id')}: {str(item.get('summary') or '')[:80]}")
    lines.append('─' * 40)
    block = '\n'.join(lines)
    desc = str(description or '')
    if marker in desc:
        # Replacement strings interpret backslash escapes (for example lesson
        # text ``\bpush\b`` becomes literal 0x08 backspaces).  A callable
        # replacement preserves lesson prose byte-for-byte and keeps the task
        # YAML printable.
        return re.sub(
            r'【注入教訓】.*?─{10,}',
            lambda _match: block,
            desc,
            count=1,
            flags=re.DOTALL,
        )
    return block + '\n\n' + desc

try:
    data = yaml.load(open(task_file, encoding='utf-8'), Loader=yaml.SafeLoader) or {}
    task = data.get('task') or {}
    if not task:
        print('[WA_LESSON] No task section, skipping', file=sys.stderr)
        sys.exit(0)

    top = recent_top_categories()
    if not top:
        print(f'[WA_LESSON] {ninja_name}: no workaround categories, skipping', file=sys.stderr)
        sys.exit(0)

    lesson_map = load_lessons()
    related = task.get('related_lessons') or []
    if not isinstance(related, list):
        related = []
    seen = {str(item.get('id')) for item in related if isinstance(item, dict)}
    added = []
    for category, count in top:
        for lid in CATEGORY_LESSON_IDS.get(category, []):
            if lid in seen or lid not in lesson_map:
                continue
            related.append(lesson_entry(lesson_map[lid], category, count))
            seen.add(lid)
            added.append(lid)

    if not added:
        print(f'[WA_LESSON] {ninja_name}: no mapped lessons for top categories {top}', file=sys.stderr)
        sys.exit(0)

    task['description'] = sync_description(task.get('description', ''), related)
    raw = open(task_file, encoding='utf-8').read()
    raw = safe_section_replace(raw, 'related_lessons', related)
    raw = safe_section_replace(raw, 'description', task['description'])
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as f:
            f.write(raw)
        os.replace(tmp, task_file)
    except Exception:
        os.unlink(tmp)
        raise
    print(f'[WA_LESSON] {ninja_name}: injected {added} from top categories {top}', file=sys.stderr)
except Exception as exc:
    print(f'[WA_LESSON] ERROR: {exc}', file=sys.stderr)
    sys.exit(1)
PY
        return 1
    fi
    rm -f "$py_output"
}

# ─── Engineering Preferences自動注入 ───
# cmd_1393: inject_task_modifiers.py に統合済み（stub）
inject_engineering_preferences() { log "inject_engineering_preferences: merged into inject_task_modifiers (no-op)"; }

# ─── Skill hint自動注入（cmd_2460: スキル発動タイミングの意志依存排除） ───
inject_skill_hint() {
    local task_file="$1"
    [ -f "$task_file" ] || return 0

    local project task_type title purpose parent_cmd command_text haystack hints
    project=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "project" "" 2>/dev/null || true)
    task_type=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "task_type" "" 2>/dev/null || true)
    title=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "title" "" 2>/dev/null || true)
    purpose=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "purpose" "" 2>/dev/null || true)
    parent_cmd=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "parent_cmd" "" 2>/dev/null || true)
    command_text=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "command" "" 2>/dev/null || true)

    if [ -n "$parent_cmd" ] && [ -f "$SCRIPT_DIR/queue/shogun_to_karo.yaml" ]; then
        command_text="${command_text}
$(awk -v cmd="$parent_cmd" '
    /^  [a-zA-Z0-9_-]+:/ {
        cur=$0
        sub(/^[[:space:]]*/, "", cur)
        sub(/:.*$/, "", cur)
    }
    cur == cmd && /^(    title:|    type:|    purpose:|    command:|        )/ { print }
' "$SCRIPT_DIR/queue/shogun_to_karo.yaml" 2>/dev/null || true)"
    fi

    haystack="${title}
${purpose}
${command_text}"
    hints=""

    if [ "$project" = "dm-signal" ] && printf '%s\n' "$haystack" | grep -Eqi '(^|[^A-Za-z])(DB|database|SQL|PostgreSQL|SQLite)([^A-Za-z]|$)|本番DB|holding_signal|monthly_returns|portfolio_rankings|PF検索|パリティ検証'; then
        hints="/db-check"
    fi

    if [ "$task_type" = "registration" ] || printf '%s\n' "$haystack" | grep -Eq '本番登録'; then
        if [ -n "$hints" ]; then
            hints="${hints}, /pf-registration"
        else
            hints="/pf-registration"
        fi
    fi

    [ -n "$hints" ] || return 0
    yaml_field_set "$task_file" "task" "skill_hint" "$hints" \
        && log "skill_hint: injected (${hints})"
}


# ─── 偵察報告自動注入 ───
# cmd_1393: inject_task_modifiers.py に統合済み（stub）
inject_reports_to_read() { log "[INJECT_REPORTS] merged into inject_task_modifiers (no-op)"; }


# ─── context_files自動注入（cmd_280: 分割context選択的読込） ───
# ─── context_files自動注入 ───
# cmd_1393: inject_task_modifiers.py に統合済み（stub）
inject_context_files() { log "[INJECT_CTX] merged into inject_task_modifiers (no-op)"; }

# ─── credential_files自動注入（cmd_949: 認証タスクに.envを自動追加） ───
# ─── credential_files自動注入 ───
# cmd_1393: inject_task_modifiers.py に統合済み（stub）
inject_credential_files() { log "[INJECT_CRED] merged into inject_task_modifiers (no-op)"; }

# ─── target_path存在検査WARN注入（cmd_1322: 設定済みだが実在しないtarget_pathを警告） ───
# cmd_1393: Python→bash置換
inject_target_path_check() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "inject_target_path_check: task file not found: $task_file"
        return 0
    fi

    # target_pathをYAML型のまま取得。field_getは配列をcomma文字列へ潰すため使わない。
    local -a paths=()
    mapfile -t paths < <(python3 - "$task_file" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
value = (data.get("task") or {}).get("target_path")
if isinstance(value, str) and value.strip():
    print(value.strip())
elif isinstance(value, list):
    for item in value:
        if str(item).strip():
            print(str(item).strip())
PY
    )

    [ ${#paths[@]} -eq 0 ] && return 0

    # project pathを取得(別リポジトリのtarget_path解決用)
    local project_id project_path=""
    project_id=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "project" "" 2>/dev/null || true)
    if [ -n "$project_id" ] && [ -f "$SCRIPT_DIR/projects/${project_id}.yaml" ]; then
        project_path=$(grep -m1 '^\s*path:' "$SCRIPT_DIR/projects/${project_id}.yaml" 2>/dev/null | sed 's/.*path:[[:space:]]*//' | tr -d "'" | tr -d '"')
    fi

    # 存在しないパスと、作業ツリーにはあるがHEADにはないパスを分けて検出する。
    # L903: 旧pathのまま新規ファイルを作る重複実装を、配備時のLevel5コンテキスト注入で防ぐ。
    local -a missing=() untracked_in_head=() git_evidence=()
    for p in "${paths[@]}"; do
        local resolved="$p"
        if [[ "$p" != /* ]]; then
            resolved="$SCRIPT_DIR/$p"
            # SCRIPT_DIR基準で不在→project_path基準でも試行
            if [ ! -e "$resolved" ] && [ -n "$project_path" ]; then
                resolved="$project_path/$p"
            fi
        fi
        if [ ! -e "$resolved" ]; then
            missing+=("$p")
            git_evidence+=("${p}:worktree=no,head=no,last_commit=none")
            continue
        fi

        local repo_root="" repo_relative="" head_oid="" last_commit=""
        local git_probe_dir
        git_probe_dir="$(dirname "$resolved")"
        [ -d "$resolved" ] && git_probe_dir="$resolved"
        repo_root=$(git -C "$git_probe_dir" rev-parse --show-toplevel 2>/dev/null || true)
        if [ -n "$repo_root" ]; then
            repo_relative=$(realpath --relative-to="$repo_root" "$resolved" 2>/dev/null || true)
        fi
        if [ -z "$repo_root" ] || [ -z "$repo_relative" ] \
            || { [ "$repo_relative" != "." ] && ! git -C "$repo_root" cat-file -e "HEAD:${repo_relative}" 2>/dev/null; }; then
            untracked_in_head+=("$p")
            git_evidence+=("${p}:worktree=yes,head=no,last_commit=none")
            continue
        fi
        # Blob existence is the synchronous safety boundary. A history walk is
        # provenance only; concurrent 9P git-log traffic must not block delivery.
        head_oid=$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || true)
        if last_commit=$(deploy_task_history_cache_get "$repo_root" "$head_oid" "$repo_relative"); then
            git_evidence+=("${p}:worktree=yes,head=yes,last_commit=${last_commit}")
        else
            deploy_task_queue_history_lookup "$repo_root" "$head_oid" "$repo_relative"
            git_evidence+=("${p}:worktree=yes,head=yes,last_commit=pending@${head_oid:-unknown}")
        fi
    done

    local evidence_text
    evidence_text=$(IFS=';'; echo "${git_evidence[*]}")
    yaml_field_set "$task_file" "task" "target_path_git_preflight" "$evidence_text"

    if [ ${#untracked_in_head[@]} -gt 0 ]; then
        local untracked_str
        untracked_str=$(IFS=', '; echo "${untracked_in_head[*]}")
        yaml_field_set "$task_file" "task" "target_path_head_warning" \
            "⚠ target_pathがgit HEADに存在しない: ${untracked_str}。実装前に旧pathと同事象の直近commitを確認せよ"
        log "[INJECT_TARGET_PATH] WARN: target_path absent from git HEAD: ${untracked_str}"
    fi

    [ ${#missing[@]} -eq 0 ] && return 0

    # WARN注入
    local missing_str
    missing_str=$(IFS=', '; echo "${missing[*]}")
    local warn_msg="⚠ target_pathが存在しない: ${missing_str}"
    yaml_field_set "$task_file" "task" "target_path_warning" "$warn_msg"
    log "[INJECT_TARGET_PATH] WARN: target_path does not exist: ${missing_str}"

    # gate_fire_log.yamlに記録
    local gate_log="$SCRIPT_DIR/logs/gate_fire_log.yaml"
    local ts
    ts=$(date '+%Y-%m-%dT%H:%M:%S')
    echo "- ts: \"${ts}\", gate: inject_target_path_check, result: WARN, detail: \"${warn_msg}\"" >> "$gate_log" 2>/dev/null || true
    # DB INSERT: eventsテーブルへゲート記録（非ブロック）
    python3 "$SCRIPT_DIR/scripts/memory_db_live_insert_async.py" gate \
        --gate-name "deploy_task:inject_target_path_check" --result "WARN" \
        --cmd-id "" --ts "$ts" --detail "$warn_msg" \
        --source-file "$gate_log" >/dev/null 2>&1 &
    disown 2>/dev/null || true
}

# New tests are expensive permanent defenses.  Require one compact, reviewable
# necessity record before publication; existing-test edits and testless tasks
# remain outside this contract.
deploy_task_test_necessity_precheck() {
    local task_file="$1"
    local report_file="${2:-}"
    python3 - "$SCRIPT_DIR" "$task_file" "$report_file" "$DEPLOY_TASK_CODE_ROOT" <<'PY'
import os, re, subprocess, sys, yaml
from pathlib import PurePosixPath

repo, task_file, report_file, code_root = sys.argv[1:5]
sys.path.insert(0, code_root)
from scripts.lib.test_necessity_contract import validate_entries
data = yaml.safe_load(open(task_file, encoding="utf-8")) or {}
task = data.get("task", data)
project = str(task.get("project") or os.environ.get("DEPLOY_TASK_TEST_DEFAULT_PROJECT") or "").strip()
target_declared = task.get("target_path")

# Legacy/direct lifecycle fixtures intentionally omit project and target_path;
# optional injectors may still add derived context paths before this precheck.
# Do not invent a project repository for those runtime-only tasks.
if not project and (not target_declared or os.environ.get("DEPLOY_TASK_DIRECT_MODE") == "true"):
    raise SystemExit(0)

def resolve_project_repo(project_id):
    if project_id == "infra":
        candidate = repo
    else:
        projects_dir = os.environ.get("DEPLOY_TASK_PROJECTS_DIR") or os.path.join(repo, "projects")
        project_file = os.path.join(projects_dir, f"{project_id}.yaml")
        if not project_id or not os.path.isfile(project_file):
            raise SystemExit(f"BLOCK: cannot resolve test lifecycle repo for project={project_id or '<empty>'}")
        project_data = yaml.safe_load(open(project_file, encoding="utf-8")) or {}
        project_block = project_data.get("project") if isinstance(project_data.get("project"), dict) else project_data
        candidate = str(project_block.get("path") or "").strip()
        if not candidate:
            raise SystemExit(f"BLOCK: project path is empty for project={project_id}")
    resolved = subprocess.run(
        ["git", "-C", candidate, "rev-parse", "--show-toplevel"],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
    )
    if resolved.returncode != 0 or not resolved.stdout.strip():
        raise SystemExit(f"BLOCK: project working tree is unavailable for project={project_id}")
    return os.path.realpath(resolved.stdout.strip())

project_repo = resolve_project_repo(project)
paths = task.get("planned_paths") or []
if isinstance(paths, str):
    paths = [paths]
report = {}
if report_file and os.path.isfile(report_file):
    report = yaml.safe_load(open(report_file, encoding="utf-8")) or {}
    if "files_modified" in report or "transient_tests_deleted" in report:
        paths = [x.get("path") for x in report.get("files_modified") or [] if isinstance(x, dict) and x.get("path")]
        paths += [str(x) for x in report.get("transient_tests_deleted") or []]

# A task with no declared or reported paths has no new-test contract to
# validate. Keep minimal lifecycle/direct fixtures (which intentionally omit
# project metadata) on the existing deployment path instead of inventing a
# project repository solely for an empty check.
if not paths:
    raise SystemExit(0)

def is_test(path):
    path = str(path).strip()
    if not path:
        return False
    normalized = path.replace("\\", "/")
    parts = PurePosixPath(normalized).parts
    base = parts[-1] if parts else ""
    test_stem_extension = base.startswith("test_") and base.endswith((".py", ".sh"))
    return bool(
        "tests" in parts
        or test_stem_extension
        or base.endswith((".bats", ".spec.js", ".test.js"))
    )

new_tests = []
for path in paths:
    path = str(path).strip()
    if not is_test(path):
        continue
    normalized = path.replace("\\", "/")
    # Accept absolute paths that resolve inside the selected project, but
    # normalize them to repo-relative paths before the HEAD/new-test checks.
    # Absolute paths outside the project remain a hard boundary violation.
    if os.path.isabs(path):
        candidate = os.path.realpath(path)
    else:
        candidate = os.path.realpath(os.path.join(project_repo, normalized))
    if candidate == project_repo or not candidate.startswith(project_repo + os.sep):
        # Project外パスはinfra repo(REPO_ROOT)でフォールバック確認。
        # task project=dm-signalだがfiles_modifiedにinfra testがある場合の偽陽性根治。
        infra_repo = os.path.realpath(repo)
        infra_candidate = os.path.realpath(os.path.join(infra_repo, normalized))
        if infra_repo != project_repo and infra_candidate.startswith(infra_repo + os.sep):
            infra_relative = os.path.relpath(infra_candidate, infra_repo).replace(os.sep, "/")
            infra_exists = subprocess.run(
                ["git", "-C", infra_repo, "cat-file", "-e", f"HEAD:{infra_relative}"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            ).returncode == 0
            if infra_exists:
                continue  # infra既存テスト — new_testではない
        print(f"BLOCK: test path is outside project repo: {path}", file=sys.stderr)
        raise SystemExit(1)
    repo_relative = os.path.relpath(candidate, project_repo).replace(os.sep, "/")
    exists = subprocess.run(
        ["git", "-C", project_repo, "cat-file", "-e", f"HEAD:{repo_relative}"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    ).returncode == 0
    if not exists:
        # project HEADに不在でもinfra HEADに存在すれば既存テスト(cross-repo偽陽性根治)
        infra_repo = os.path.realpath(repo)
        if infra_repo != project_repo:
            infra_candidate = os.path.realpath(os.path.join(infra_repo, normalized))
            if infra_candidate.startswith(infra_repo + os.sep):
                infra_relative = os.path.relpath(infra_candidate, infra_repo).replace(os.sep, "/")
                if subprocess.run(
                    ["git", "-C", infra_repo, "cat-file", "-e", f"HEAD:{infra_relative}"],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                ).returncode == 0:
                    continue  # infra既存テスト — new_testではない
        new_tests.append(repo_relative)

if not new_tests:
    raise SystemExit(0)

# A new test is transient by default: it may be used to prove the change, but
# it is not silently promoted into the permanent suite.  Only a complete
# defense declaration opts it into persistent lifecycle.
persistent_set, errors = validate_entries(task.get("test_necessity"), new_tests)
if errors:
    print("BLOCK: new test necessity contract failed: " + "; ".join(errors), file=sys.stderr)
    print("BLOCK_TESTS=" + ",".join(new_tests), file=sys.stderr)
    raise SystemExit(1)
persistent = [p for p in new_tests if p in persistent_set]
transient = [p for p in new_tests if p not in persistent_set]
if report:
    deleted = set(map(str, report.get("transient_tests_deleted") or []))
    missing = [p for p in transient if p not in deleted]
    if missing:
        print("BLOCK: report omits transient deletion evidence: " + ",".join(missing), file=sys.stderr)
        raise SystemExit(1)
print("PASS: test_lifecycle actual_new_tests=" + ",".join(new_tests) + " persistent=" + ",".join(persistent) + " transient=" + ",".join(transient) + " contract_contamination=0")
PY
}

deploy_task_guard_target_path_collision() {
    local task_file="$1"
    local ninja_name="$2"
    [ -f "$task_file" ] || return 0

    PYTHONPATH="$SCRIPT_DIR" python3 - "$SCRIPT_DIR" "$task_file" "$ninja_name" <<'TARGET_COLLISION_PY'
import json
import os
import re
import subprocess
import sys
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)
from datetime import datetime, timezone
from scripts.lib.yaml_atomic import atomic_yaml_write

script_dir, task_file, current_ninja = sys.argv[1:4]
active_statuses = {'active', 'assigned', 'acknowledged', 'in_progress'}

def load_task(path):
    try:
        with open(path, encoding='utf-8') as f:
            doc = yaml.safe_load(f) or {}
    except Exception:
        return {}
    task = doc.get('task') if isinstance(doc.get('task'), dict) else doc
    return task if isinstance(task, dict) else {}

def paths_from(value):
    if isinstance(value, str):
        return [value.strip()] if value.strip() else []
    if isinstance(value, list):
        return [str(item).strip() for item in value if str(item).strip()]
    return []

def command_paths(value):
    text = '\n'.join(map(str, value)) if isinstance(value, list) else str(value or '')
    return re.findall(
        r'(?<![A-Za-z0-9_./-])((?:/mnt/[A-Za-z0-9_.-]+/|(?:[A-Za-z0-9_.-]+/)*)'
        r'[A-Za-z0-9_.-]+\.(?:sh|py|md|yaml|yml|json|toml|js|ts|tsx|jsx|css|html|sql|csv))'
        r'(?![A-Za-z0-9_.-])', text)

def readonly_paths(task):
    rows = task.get('readonly_ref') or []
    if isinstance(rows, dict):
        rows = [rows]
    return [str(row.get('path', '')).strip() for row in rows if isinstance(row, dict) and str(row.get('path', '')).strip()]

def normalize(path):
    path = path.replace('\\', '/').strip()
    if not path:
        return ''
    if not os.path.isabs(path):
        path = os.path.join(script_dir, path)
    return os.path.normpath(path)

def reserved_paths(task):
    # target_path is the primary scope, while planned_paths records every file
    # the task expects to touch. Command file references complete the contract,
    # except references explicitly classified readonly by the injector.
    explicit = paths_from(task.get('target_path')) + paths_from(task.get('planned_paths'))
    readonly = {normalize(path) for path in readonly_paths(task)}
    candidates = explicit + command_paths(task.get('command'))
    return [path for path in candidates if normalize(path) not in readonly]

def handoff_peers(task):
    value = task.get('overlap_handoff_from') or task.get('handoff_from') or []
    return set(paths_from(value))

def record(decision, peer='', overlap=None, false_positive=0):
    log_dir = os.path.join(script_dir, 'logs')
    os.makedirs(log_dir, exist_ok=True)
    row = {
        'timestamp': datetime.now(timezone.utc).isoformat(),
        'gate': 'deploy_target_overlap', 'worker': current_ninja,
        'peer': peer, 'decision': decision, 'overlap': overlap or [],
        'false_positive': false_positive,
    }
    with open(os.path.join(log_dir, 'target_overlap_gate_fire.jsonl'), 'a', encoding='utf-8') as f:
        f.write(json.dumps(row, ensure_ascii=False, sort_keys=True) + '\n')

def split_file_targets(paths):
    file_targets = set()
    dir_targets = set()
    for path in paths:
        norm = normalize(path)
        if not norm:
            continue
        if os.path.isdir(norm):
            dir_targets.add(norm)
        else:
            # A planned file need not exist yet.  Reserving it before creation
            # prevents two active tasks from concurrently creating/editing it.
            file_targets.add(norm)
    return file_targets, dir_targets

current_task = load_task(task_file)
current_files, current_dirs = split_file_targets(reserved_paths(current_task))
if not current_files and not current_dirs:
    record('PASS', false_positive=0)
    sys.exit(0)

task_dir = os.path.join(script_dir, 'queue', 'tasks')
collisions = []
dir_infos = []
settled_claims = []
for name in sorted(os.listdir(task_dir)) if os.path.isdir(task_dir) else []:
    if not name.endswith('.yaml') or name.startswith('.'):
        continue
    peer_ninja = name[:-5]
    if peer_ninja == current_ninja:
        continue
    peer_path = os.path.join(task_dir, name)
    peer_task = load_task(peer_path)
    status = str(peer_task.get('status') or '').strip()
    peer_files, peer_dirs = split_file_targets(reserved_paths(peer_task))
    if status not in active_statuses:
        parent_cmd = str(peer_task.get('parent_cmd') or '').strip()
        archive_marker = (
            os.path.join(script_dir, 'queue', 'gates', parent_cmd, 'archive.done')
            if parent_cmd and os.path.basename(parent_cmd) == parent_cmd
            else ''
        )
        # archive.done closes this task generation.  Any later dirty state on
        # the shared path belongs to a subsequent writer and must not revive
        # the archived worker's reservation.
        if archive_marker and os.path.isfile(archive_marker):
            continue
        # The task record says "finished", but unpushed edits say otherwise.
        # Keep the claim so the worktree lane below can compare declaration
        # against the actual tree (2026-07-26: hanzo held 5 uncommitted files
        # from terminal tasks while the same paths were deployed to tobisaru).
        settled_claims.append((peer_ninja, status, parent_cmd, peer_files))
        continue
    file_overlap = sorted(current_files & peer_files)
    dir_overlap = sorted(current_dirs & peer_dirs)
    if file_overlap:
        collisions.append((peer_ninja, status, str(peer_task.get('parent_cmd') or ''), file_overlap))
    if dir_overlap:
        dir_infos.append((peer_ninja, status, str(peer_task.get('parent_cmd') or ''), dir_overlap))

def worktree_dirty(candidates):
    """Paths that the tree says are still in flight, whatever the task says."""
    rels = []
    for path in sorted(candidates):
        rel = os.path.relpath(path, script_dir)
        if not rel.startswith('..'):
            rels.append(rel)
    if not rels:
        return set()
    try:
        # Pathspec-limited on purpose: a bare `git status` is 54s on this
        # DrvFs checkout, the limited form is 0.6s.
        proc = subprocess.run(
            ['git', '-C', script_dir, 'status', '--porcelain', '--', *rels],
            capture_output=True, text=True, timeout=60,
        )
    except (OSError, subprocess.SubprocessError):
        return set()
    if proc.returncode != 0:
        return set()
    dirty = set()
    for line in proc.stdout.splitlines():
        entry = line[3:].strip()
        if ' -> ' in entry:
            entry = entry.split(' -> ')[-1]
        dirty.add(normalize(entry.strip('"')))
    return dirty


settled_overlap = set()
for _peer, _status, _cmd, _peer_files in settled_claims:
    settled_overlap |= (current_files & _peer_files)
if settled_overlap:
    dirty_paths = worktree_dirty(settled_overlap)
    allowed_settled = handoff_peers(current_task)
    for peer_ninja, status, parent_cmd, peer_files in settled_claims:
        overlap = sorted((current_files & peer_files) & dirty_paths)
        if not overlap or peer_ninja in allowed_settled or parent_cmd in allowed_settled:
            continue
        collisions.append((peer_ninja, f'{status or "unknown"}/uncommitted', parent_cmd, overlap))

for peer_ninja, status, parent_cmd, overlap in dir_infos:
    print(
        f'INFO: target_path directory overlap with {peer_ninja} '
        f'(status={status}, parent_cmd={parent_cmd or "unknown"}): {", ".join(overlap)}',
        file=sys.stderr,
    )

if collisions:
    unresolved = []
    allowed = handoff_peers(current_task)
    for peer_ninja, status, parent_cmd, overlap in collisions:
        if peer_ninja in allowed or parent_cmd in allowed:
            barrier = current_task.setdefault('final_checkpoint_barrier', [])
            barrier.append({
                'peer': peer_ninja, 'parent_cmd': parent_cmd,
                'paths': overlap, 'release_statuses': ['done', 'failed', 'idle'],
            })
            record('HANDOFF_BARRIER', peer_ninja, overlap, 0)
            continue
        print(
            f'BLOCK: reserved path collision with {peer_ninja} '
            f'(status={status}, parent_cmd={parent_cmd or "unknown"}): {", ".join(overlap)}',
            file=sys.stderr,
        )
        record('BLOCK', peer_ninja, overlap, 0)
        unresolved.append(peer_ninja)
    if unresolved:
        sys.exit(1)
    atomic_yaml_write(task_file, {'task': current_task})
    sys.exit(0)
record('PASS', false_positive=0)
TARGET_COLLISION_PY
}

deploy_task_guard_preserved_path() {
    local task_file="$1"
    [ -f "$task_file" ] || return 0
    local preserved_file="$SCRIPT_DIR/queue/preserved_paths.yaml"
    [ -f "$preserved_file" ] || return 0

    PYTHONPATH="$SCRIPT_DIR" python3 - "$SCRIPT_DIR" "$task_file" "$preserved_file" <<'PRESERVED_PATH_PY'
import os
import sys
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)

script_dir, task_file, preserved_file = sys.argv[1:4]

def load_yaml(path):
    try:
        with open(path, encoding='utf-8') as f:
            return yaml.safe_load(f) or {}
    except Exception:
        return {}

def paths_from(value):
    if isinstance(value, str):
        return [value.strip()] if value.strip() else []
    if isinstance(value, list):
        return [str(item).strip() for item in value if str(item).strip()]
    return []

def normalize(path):
    path = path.replace('\\', '/').strip()
    if not path:
        return ''
    if not os.path.isabs(path):
        path = os.path.join(script_dir, path)
    return os.path.normpath(path)

doc = load_yaml(task_file)
task = doc.get('task') if isinstance(doc.get('task'), dict) else doc
task = task if isinstance(task, dict) else {}

# Both target_path (primary scope) and planned_paths (full touch set) are
# checked: the incident this guard closes (2026-07-27) was a task whose
# target_path itself was the preserved file.
target_paths = {normalize(p) for p in paths_from(task.get('target_path')) + paths_from(task.get('planned_paths'))}
if not target_paths:
    sys.exit(0)

preserved_doc = load_yaml(preserved_file)
entries = preserved_doc.get('preserved_paths') or []
if not isinstance(entries, list):
    sys.exit(0)

hit = None
for entry in entries:
    if not isinstance(entry, dict):
        continue
    # Guard checks current state, not "was a declaration ever made": a
    # released=true entry stays in the registry as an audit trail but must
    # not re-BLOCK (2026-07-27 shogun ruling released lessons.yaml; a
    # declaration-only/append-only log can't express "no longer preserved").
    if entry.get('released') is True:
        continue
    p = normalize(str(entry.get('path', '')))
    if p and p in target_paths:
        hit = entry
        break

if hit:
    print(
        f"BLOCK: preserved path collision: {hit.get('path')} "
        f"(reason={hit.get('reason', '')}, declared_by={hit.get('declared_by', '')}, "
        f"declared_at={hit.get('declared_at', '')}). "
        "解除の証跡を一次確認せよ。解除が殿の裁定事項なら裁定を待て。",
        file=sys.stderr,
    )
    sys.exit(1)
sys.exit(0)
PRESERVED_PATH_PY
}

deploy_task_guard_direct_yaml_prewrite_collision() {
    local yaml_file="$1"
    local ninja_name="$2"

    [ "$DIRECT_MODE" = true ] || return 0
    [ -n "$yaml_file" ] || return 0
    [ -f "$yaml_file" ] || return 0

    deploy_task_guard_target_path_collision "$yaml_file" "$ninja_name"
}

# ─── inject_task_modifiers: 7関数統合ラッパー（cmd_1393） ───
# inject_engineering_preferences, inject_reports_to_read, inject_context_files,
# inject_credential_files, inject_context_update, inject_report_template,
# inject_execution_controls を1つのPython呼び出しに統合
inject_task_modifiers() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "inject_task_modifiers: task file not found: $task_file"
        return 0
    fi
    local py_output
    py_output=$(mktemp)
    if ! run_python_logged "$py_output" env \
        TASK_FILE_ENV="$task_file" \
        SCRIPT_DIR_ENV="$SCRIPT_DIR" \
        python3 "$SCRIPT_DIR/scripts/lib/inject_task_modifiers.py"; then
        log "WARN: inject_task_modifiers failed (non-fatal)"
        return 1
    fi
}

# inject_context_update: cmd_1393で inject_task_modifiers.py に統合（stub）
inject_context_update() { log "inject_context_update: merged into inject_task_modifiers (no-op)"; }

# ─── 独立2系統偵察の相互汚染防止契約 ───
# Track Aの共有context還流がTrack Bの起動時contextへ混入したcmd_3878事故を、
# 注意喚起ではなくtask正本のfixed-base + embargo契約で遮断する。
inject_independent_recon_contract() {
    local task_file="$1"
    local ninja_name="$2"
    local title purpose command_text contract_text parent_cmd group track
    local base_commit target_path repo_path project existing_reminder

    [ -f "$task_file" ] || return 0
    title=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "title" "")
    purpose=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "purpose" "")
    command_text=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "command" "")
    contract_text="${title} ${purpose} ${command_text}"
    if ! grep -Eiq '独立2系統|相互参照禁止|independent[ _-]*(track|recon)|dual[ _-]*recon' <<< "$contract_text"; then
        return 0
    fi

    parent_cmd=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "parent_cmd" "")
    group=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "independence_group" "")
    if [ -z "$group" ]; then
        group=$(printf '%s' "$parent_cmd" | sed -E 's/_recon[0-9]+$//')
    fi
    track=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "independence_track" "")
    if [ -z "$track" ]; then
        if [[ "$parent_cmd" =~ _recon([0-9]+)$ ]]; then
            track="B${BASH_REMATCH[1]}"
        else
            track="A"
        fi
    fi

    base_commit=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "independence_base_commit" "")
    target_path=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "target_path" "")
    repo_path="$target_path"
    [ -f "$repo_path" ] && repo_path=${repo_path%/*}
    if [ -z "$repo_path" ] || ! git -C "$repo_path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        project=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "project" "")
        repo_path=$(get_project_path "$project" 2>/dev/null || true)
    fi
    if [ -z "$base_commit" ]; then
        base_commit=$(git -C "$repo_path" rev-parse HEAD 2>/dev/null || true)
    fi
    if [ -z "$base_commit" ] || ! git -C "$repo_path" cat-file -e "${base_commit}^{commit}" 2>/dev/null; then
        log "BLOCK: independent recon base commit is unavailable/invalid (ninja=${ninja_name}, repo=${repo_path:-missing}, base=${base_commit:-missing})"
        return 1
    fi

    yaml_field_set_batch "$task_file" "task" \
        "independence_group=${group}" \
        "independence_track=${track}" \
        "independence_base_commit=${base_commit}" \
        "independence_worktree_required=true" \
        "shared_context_embargo=karo_release_required"

    existing_reminder=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "role_reminder" "")
    if [ -z "$existing_reminder" ]; then
        yaml_field_set "$task_file" "task" "role_reminder" \
            "独立Track ${track}。固定base ${base_commit}から隔離worktreeを作り、自作probeのみ使用。兄弟Trackのtask/report/branch/worktree/commit・配備後の共有context参照禁止。共有context/semantic-map/記憶DBへの結論還流は家老releaseまで禁止"
    fi
    log "[INDEPENDENT_RECON] group=${group} track=${track} base=${base_commit:0:12} embargo=karo_release_required"
}

# ─── role_reminder自動注入（cmd_384: 忍者スコープ制限リマインダ） ───
# cmd_1393: Python→bash変換（field_get+yaml_field_set）
inject_role_reminder() {
    local task_file="$1"
    local ninja_name="$2"
    if [ ! -f "$task_file" ]; then
        log "inject_role_reminder: task file not found: $task_file"
        return 0
    fi

    local existing
    existing=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "role_reminder" "")
    if [ -n "$existing" ]; then
        log "[ROLE_REMINDER] Already exists, skipping"
        return 0
    fi

    yaml_field_set "$task_file" "task" "role_reminder" "忍者${ninja_name}。このタスクのみ実行せよ。スコープ外の改善・判断は禁止。発見はlesson_candidate/decision_candidateへ"
    log "[ROLE_REMINDER] Injected for ${ninja_name}"
}

# inject_report_template: cmd_1393で inject_task_modifiers.py に統合（stub）
inject_report_template() { log "inject_report_template: merged into inject_task_modifiers (no-op)"; }

# ─── report_filename自動注入（cmd_410: 命名ミスマッチ根治） ───
# cmd_1393: Python→bash変換（field_get+yaml_field_set）
inject_report_filename() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "inject_report_filename: task file not found: $task_file"
        return 0
    fi

    local existing parent_cmd report_filename
    eval "$(FIELD_GET_NO_LOG=1 field_get_multi "$task_file" \
        report_filename parent_cmd 2>/dev/null)" || true
    existing="${report_filename:-}"
    if [ -n "$existing" ]; then
        log "[REPORT_FN] Already exists, skipping"
        return 0
    fi

    if [ -n "$parent_cmd" ]; then
        report_filename="${NINJA_NAME}_report_${parent_cmd}.yaml"
    else
        report_filename="${NINJA_NAME}_report.yaml"
    fi

    yaml_field_set "$task_file" "task" "report_filename" "$report_filename"
    log "[REPORT_FN] Injected report_filename=${report_filename}"
}

# A speed-campaign round owns its report identity.  Generic direct YAML must
# still be normalized, but replacing this exact generator contract collapses
# R1/R2 onto the parent-cmd report and destroys the campaign history.
deploy_task_speed_campaign_report_is_explicit() {
    local task_file="$1"
    python3 - "$task_file" <<'PY'
import sys, yaml
try:
    task = (yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}).get("task", {})
except (OSError, yaml.YAMLError):
    raise SystemExit(1)
c = task.get("speed_campaign") or {}
campaign = str(c.get("campaign_id") or "")
round_index = c.get("round_index")
name = str(task.get("report_filename") or "")
path = str(task.get("report_path") or "")
expected = f"test_speed_report_{campaign}_r{round_index}.yaml"
ok = bool(campaign and isinstance(round_index, int) and round_index > 0
          and name == expected and path == f"queue/reports/{expected}")
raise SystemExit(0 if ok else 1)
PY
}

deploy_task_normalize_report_metadata() {
    local task_file="$1"
    if deploy_task_speed_campaign_report_is_explicit "$task_file"; then
        log "[REPORT_FN] Preserving explicit speed campaign round report"
    else
        yaml_field_set_batch "$task_file" "task" \
            "report_filename=" "report_path=" \
            || { log "FATAL: yaml_field_set_batch failed for report metadata"; return 1; }
    fi
    inject_report_filename "$task_file" || true
}

# ─── bloom_level自動注入（cmd_434: タスク複雑度メタデータ） ───
# cmd_1393: Python→bash変換（grep+yaml_field_set）
inject_bloom_level() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "inject_bloom_level: task file not found: $task_file"
        return 0
    fi

    # bloom_level:が既に存在する場合は上書きしない（空文字でも存在扱い）
    if grep -q '^\s*bloom_level:' "$task_file" 2>/dev/null; then
        log "[BLOOM_LVL] Already exists, skipping"
        return 0
    fi

    yaml_field_set "$task_file" "task" "bloom_level" ""
    log "[BLOOM_LVL] Injected bloom_level (empty)"
}

# inject_execution_controls: GS/忍法/DB系タスクにexecution_env制約を自動注入(L5)
# origin: cmd_3496 kagemaru PowerShell経由Windows python事故(2026-06-23)
# Guard 0f(L1将軍hook)+本関数(L5事前コンテキスト)で二層防御
inject_execution_controls() {
    local task_file="$1"
    [ -f "$task_file" ] || return 0

    # 既にexecution_envがtask YAMLにあればスキップ
    grep -q 'execution_env:' "$task_file" 2>/dev/null && {
        log "inject_execution_controls: execution_env already present, skip"
        return 0
    }

    local purpose command_text haystack command
    eval "$(FIELD_GET_NO_LOG=1 field_get_multi "$task_file" \
        purpose command 2>/dev/null)" || true
    command_text="${command:-}"
    haystack="${purpose} ${command_text}"

    # GS/忍法/DB操作を検出
    if printf '%s\n' "$haystack" | grep -Eqi 'grid.?search|GS実行|忍法|秘奥義|run_077|wf_runner|fullrecalculate|本番DB|migration'; then
        local indent="  "
        local inject_line="${indent}execution_env: \"Linux venv必須。RSS計測=/usr/bin/time -v。PowerShell/Windows python禁止(cmd_3496事故)\""
        # description行の前に挿入
        local tmp_file
        tmp_file=$(mktemp "${task_file}.XXXXXX")
        awk -v line="$inject_line" '
            /^  description:/ && !done { print line; done=1 }
            { print }
        ' "$task_file" > "$tmp_file"
        _yaml_field_set_publish_atomic "$tmp_file" "$task_file" || return 1
        log "inject_execution_controls: execution_env injected (GS/DB detected)"
    else
        log "inject_execution_controls: no GS/DB keywords, skip"
    fi
}

# ─── ninja_weak_points自動注入（cmd_1307: 忍者別過去失敗パターン注入） ───
# karo_workarounds.yamlから忍者名でフィルタし、category別件数をtask YAMLに注入
inject_ninja_weak_points() {
    local task_file="$1"
    local ninja_name="$2"
    if [ ! -f "$task_file" ]; then
        log "inject_ninja_weak_points: task file not found: $task_file"
        return 0
    fi

    local workarounds_file="$SCRIPT_DIR/logs/karo_workarounds.yaml"
    if [ ! -f "$workarounds_file" ]; then
        log "inject_ninja_weak_points: karo_workarounds.yaml not found, skipping"
        return 0
    fi

    local py_output
    py_output=$(mktemp)
    local ninja_jp_name
    ninja_jp_name="$(get_japanese_name "$ninja_name" 2>/dev/null || echo "$ninja_name")"
    if ! run_python_logged "$py_output" env TASK_FILE_ENV="$task_file" WORKAROUNDS_FILE_ENV="$workarounds_file" NINJA_NAME_ENV="$ninja_name" NINJA_JP_ENV="$ninja_jp_name" python3 - <<'PY'; then
import os
import re
import sys
import tempfile

import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)

task_file = os.environ['TASK_FILE_ENV']
workarounds_file = os.environ['WORKAROUNDS_FILE_ENV']
ninja_name = os.environ['NINJA_NAME_ENV']
ninja_jp_name = os.environ.get('NINJA_JP_ENV', ninja_name)

def match_ninja(entry, target_name):
    """エントリが対象忍者に属するか判定"""
    ninja_field = str(entry.get('ninja', '') or '')
    if ninja_field and ninja_field.lower() == target_name.lower():
        return True
    jp_name = ninja_jp_name if target_name.lower() == ninja_name.lower() else ''
    if not jp_name:
        return False
    for field in ('root_cause', 'detail', 'issue', 'workaround_detail'):
        val = str(entry.get(field, '') or '')
        if jp_name in val:
            return True
    return False

def is_workaround(entry):
    """workaround: true判定（新旧形式対応）"""
    wa = entry.get('workaround')
    if wa is True:
        return True
    if wa is False:
        return False
    kw = str(entry.get('karo_workaround', '') or '').lower()
    if kw == 'yes':
        return True
    return False

def parse_workarounds_robust(filepath):
    """karo_workarounds.yamlをロバストに解析（混在形式対応）"""
    with open(filepath) as f:
        content = f.read()

    # まずyaml.loadを試す
    try:
        wa_data = yaml.load(content, Loader=yaml.SafeLoader)
        if isinstance(wa_data, dict):
            return wa_data.get('workarounds', [])
        if isinstance(wa_data, list):
            return wa_data
    except yaml.YAMLError:
        pass

    # フォールバック: トップレベル '- ' エントリを個別にパース
    entries = []
    # workarounds:ヘッダを除去
    body = re.sub(r'^workarounds:\s*\n', '', content)
    # トップレベルのリストアイテムで分割（行頭が '- ' のもの）
    blocks = re.split(r'\n(?=- )', body)
    for block in blocks:
        block = block.strip()
        if not block:
            continue
        # ネストされた不正な '  - timestamp:' 行を除去
        cleaned_lines = []
        for line in block.split('\n'):
            # トップレベルエントリ内にネストされた別形式エントリを除外
            if re.match(r'^  - (timestamp|cmd|ninja|issue|fix|category|resolved_by_cmd):', line):
                continue
            cleaned_lines.append(line)
        cleaned = '\n'.join(cleaned_lines)
        try:
            parsed = yaml.load(cleaned, Loader=yaml.SafeLoader)
            if isinstance(parsed, list) and parsed:
                entries.append(parsed[0])
            elif isinstance(parsed, dict):
                entries.append(parsed)
        except yaml.YAMLError:
            continue
    return entries

try:
    entries = parse_workarounds_robust(workarounds_file)
    if not entries:
        print('[NINJA_WP] No entries parsed from karo_workarounds.yaml', file=sys.stderr)
        sys.exit(0)

    # 対象忍者のworkaround: trueエントリをフィルタ
    matched = [e for e in entries if isinstance(e, dict) and match_ninja(e, ninja_name) and is_workaround(e)]

    if not matched:
        print(f'[NINJA_WP] {ninja_name}: 0 workarounds, skipping injection', file=sys.stderr)
        sys.exit(0)

    # category別集計
    cat_counts = {}
    for e in matched:
        if 'category' in e and e['category']:
            cat = str(e['category']).strip()
        else:
            cat = 'uncategorized'
        cat_counts[cat] = cat_counts.get(cat, 0) + 1

    total = len(matched)
    top_cat = max(cat_counts, key=cat_counts.get)
    top_count = cat_counts[top_cat]

    # warning生成（top categoryに応じた具体的な注意事項）
    WARNING_MAP = {
        'report_yaml_format': '⚠ report_field_set.sh必ず使用。lessons_usefulはlist形式、dict(0:{},1:{})禁止。verdict二値(PASS/FAIL)厳守',
        'commit_missing': '⚠ コード変更後は必ずgit add+git commitを実行してから報告。commit漏れ厳禁',
        'report_missing': '⚠ 報告YAML作成を必ず完了してから完了報告。report未作成での完了報告禁止',
        'file_disappearance': '⚠ ファイル操作後は存在確認。特にreport YAMLが消失していないか検証',
    }
    warning = WARNING_MAP.get(top_cat, f'⚠ 過去{total}件のworkaround発生。品質に注意')

    # category内訳文字列
    breakdown = ', '.join(f'{cat}({cnt}件)' for cat, cnt in sorted(cat_counts.items(), key=lambda x: -x[1]))

    # task YAMLに注入
    with open(task_file) as f:
        data = yaml.load(f, Loader=yaml.SafeLoader)

    if not data or 'task' not in data:
        print('[NINJA_WP] No task section, skipping', file=sys.stderr)
        sys.exit(0)

    task = data['task']

    # 既に注入済みならスキップ（冪等性）
    if 'ninja_weak_points' in task:
        print('[NINJA_WP] Already injected, skipping', file=sys.stderr)
        sys.exit(0)

    task['ninja_weak_points'] = {
        'source': 'karo_workarounds.yaml',
        'total_workarounds': total,
        'top_pattern': f'{top_cat}({top_count}件)',
        'breakdown': breakdown,
        'warning': warning,
    }

    # --- GP-110: gate_fire_logからper-ninja FAILパターンTop3を追加 ---
    gate_log_path = os.path.join(os.path.dirname(workarounds_file), 'gate_fire_log.yaml')
    if os.path.exists(gate_log_path):
        fail_cats = {}
        GATE_FAIL_WARNING = {
            'lu_reason_empty': 'lessons_usefulの各教訓にreason(理由)を必ず記入。空文字禁止',
            'bc_result_empty': 'binary_checksの各check項目にresult("yes"/"no")を記入。空文字禁止',
            'verdict_invalid': 'verdictは"PASS"/"FAIL"の二値のみ。空文字/None禁止',
            'status_pending': '完了後にstatusを"completed"に更新。"pending"のまま報告禁止',
            'field_missing': '必須フィールド(binary_checks/files_modified/result.summary)を省略するな',
            'type_error': 'YAML型注意。dict({0:{},1:{}})禁止→list([{},{},{}])形式',
            'no_lesson_reason': 'lesson_candidate.found=false時はno_lesson_reasonに理由記入',
            'bc_result_invalid': 'binary_checksのresultは"yes"/"no"のみ。"PASS"/"FAIL"/"pending"等は不正値',
            'lu_structure_error': 'lessons_usefulの各要素にid/reason/usefulフィールド必須。null/空リスト/dict禁止。テンプレート構造を壊すな',
            'yaml_parse_error': 'YAML構文エラー。インデント・コロン後のスペース・引用符の閉じ忘れを確認せよ',
            'fill_this_remaining': 'FILL_THISが残存。全テンプレート値を実際の値に置換せよ',
        }
        try:
            with open(gate_log_path) as gf:
                for gline in gf:
                    gline = gline.strip()
                    if not gline.startswith('- ') or f'/{ninja_name}_report' not in gline:
                        continue
                    if '/tmp/' in gline:
                        continue
                    if 'result: FAIL' not in gline:
                        continue
                    rm = re.search(r'reasons:\s*"(.*)"$', gline)
                    if not rm:
                        continue
                    for reason in rm.group(1).split('; '):
                        if 'reason is empty' in reason:
                            fail_cats['lu_reason_empty'] = fail_cats.get('lu_reason_empty', 0) + 1
                        elif 'result: 空文字' in reason or 'result: ""' in reason:
                            fail_cats['bc_result_empty'] = fail_cats.get('bc_result_empty', 0) + 1
                        elif 'verdict' in reason:
                            fail_cats['verdict_invalid'] = fail_cats.get('verdict_invalid', 0) + 1
                        elif 'status' in reason and 'pending' in reason:
                            fail_cats['status_pending'] = fail_cats.get('status_pending', 0) + 1
                        elif 'MISSING' in reason:
                            fail_cats['field_missing'] = fail_cats.get('field_missing', 0) + 1
                        elif 'is dict' in reason or 'is str' in reason:
                            fail_cats['type_error'] = fail_cats.get('type_error', 0) + 1
                        elif 'no_lesson_reason' in reason:
                            fail_cats['no_lesson_reason'] = fail_cats.get('no_lesson_reason', 0) + 1
                        elif '不正' in reason:
                            fail_cats['bc_result_invalid'] = fail_cats.get('bc_result_invalid', 0) + 1
                        elif 'YAML parse error' in reason:
                            fail_cats['yaml_parse_error'] = fail_cats.get('yaml_parse_error', 0) + 1
                        elif 'FILL_THIS' in reason:
                            fail_cats['fill_this_remaining'] = fail_cats.get('fill_this_remaining', 0) + 1
                        elif ('missing' in reason and 'field' in reason) or \
                             'null (must be' in reason or \
                             'empty list' in reason or 'unexpected type' in reason or \
                             'empty dict' in reason or 'found=true but no' in reason:
                            fail_cats['lu_structure_error'] = fail_cats.get('lu_structure_error', 0) + 1
            if fail_cats:
                sorted_cats = sorted(fail_cats.items(), key=lambda x: -x[1])[:3]
                top3 = [{'pattern': p, 'count': c} for p, c in sorted_cats]
                gate_warnings = [GATE_FAIL_WARNING.get(p, p) for p, _ in sorted_cats]
                task['ninja_weak_points']['gate_fail_top3'] = top3
                task['ninja_weak_points']['gate_warning'] = '⚠ gate頻出FAIL: ' + '; '.join(gate_warnings)
                print(f'[NINJA_WP] {ninja_name}: gate FAIL top3 injected: {sorted_cats}', file=sys.stderr)
        except Exception as ge:
            print(f'[NINJA_WP] gate_fire_log parse warning: {ge}', file=sys.stderr)

    # --- cmd_1534: gate_metrics.logからBLOCKパターンを忍者別集計 ---
    gate_metrics_path = os.path.join(os.path.dirname(workarounds_file), 'gate_metrics.log')
    if os.path.exists(gate_metrics_path):
        BLOCK_HINT_MAP = {
            'empty_lessons_useful': 'lessons_usefulの各教訓にuseful(true/false)+reason(理由)を記入。空のまま提出禁止',
            'lesson_done_source': 'lesson_candidate登録後にlesson_done確認が必要。lesson_write.sh経由で正式登録',
            'lesson_candidate_missing': 'lesson_candidate.found欄を必ず記入(true/false)。省略禁止',
            'lesson_candidate_legacy_list': 'lesson_candidateはdict形式(found/title/detail)。リスト[]形式禁止',
            'lesson_done_missing': 'lesson登録完了の確認が不足。lesson_write.sh実行後にdone確認',
            'lesson_candidate_parse_error': 'lesson_candidateのYAML構文エラー。インデント・引用符を確認',
            'ac_version_mismatch': 'ac_version_readがtask YAMLのac_versionと不一致。最新タスクを再読込',
            'invalid_lessons_useful_format': 'lessons_usefulはリスト[{id,useful,reason}]形式。dict/null禁止',
            'lesson_candidate_no_reason_empty': 'lesson_candidate.found=false時はno_lesson_reasonに理由記入必須',
            'purpose_validation_fit_false': 'purpose_validation.fitがfalse。cmd目的と作業内容の乖離を確認',
            'empty_lesson_referenced': 'related_lessonsの参照教訓が空。タスクで指定された教訓を確認',
            'null_lessons_useful': 'lessons_usefulがnull。テンプレートのリスト構造を維持せよ',
            'fill_this_remaining': 'FILL_THISが残存。全テンプレート値を実際の値に置換せよ',
            'binary_checks_fail': 'binary_checksのresultが"yes"でない項目あり。全ACのチェック完了を確認',
            'unreviewed_lessons': '未レビューのlessonが残存。lesson確認を完了させよ',
            'lesson_candidate_found_missing': 'lesson_candidate.found欄がない。true/falseを明記',
            'report_format': 'report YAMLのフォーマットエラー。report_field_set.sh使用必須',
            'report_yaml_missing': 'report YAMLが存在しない。report_pathのファイルを作成・記入せよ',
        }
        NINJA_NAMES = set(os.environ.get('DEPLOY_NINJA_NAMES', 'kagemaru hanzo hayate tobisaru saizo kotaro').split())
        try:
            block_cats = {}
            with open(gate_metrics_path, encoding='utf-8') as gmf:
                for line in gmf:
                    cols = line.rstrip('\n').split('\t')
                    if len(cols) < 4 or cols[2] != 'BLOCK':
                        continue
                    reasons = cols[3].split('|')
                    for reason in reasons:
                        reason = reason.strip()
                        # Pattern 1: {ninja_name}:{category}... (e.g. kagemaru:empty_lessons_useful:...)
                        matched_ninja = False
                        for nn in NINJA_NAMES:
                            if reason.startswith(nn + ':'):
                                if nn == ninja_name:
                                    # Extract category: take the part after ninja_name:
                                    rest = reason[len(nn)+1:]
                                    # Category is the first segment before : or =
                                    cat = re.split(r'[:=]', rest)[0]
                                    if cat:
                                        block_cats[cat] = block_cats.get(cat, 0) + 1
                                matched_ninja = True
                                break
                        if matched_ninja:
                            continue
                        # Pattern 2: report_format:{ninja}_report... or report_yaml_missing:{ninja}_report...
                        if f':{ninja_name}_report' in reason or f'_{ninja_name}_report' in reason or f'/{ninja_name}_report' in reason:
                            cat = reason.split(':')[0] if ':' in reason else 'report_issue'
                            block_cats[cat] = block_cats.get(cat, 0) + 1
            if block_cats:
                sorted_blocks = sorted(block_cats.items(), key=lambda x: -x[1])
                gate_blocks = [
                    {'reason': cat, 'count': cnt, 'hint': BLOCK_HINT_MAP.get(cat, f'gate BLOCK: {cat}')}
                    for cat, cnt in sorted_blocks
                ]
                task['ninja_weak_points']['gate_blocks'] = gate_blocks
                print(f'[NINJA_WP] {ninja_name}: gate_metrics BLOCK {len(gate_blocks)} categories injected', file=sys.stderr)
            else:
                print(f'[NINJA_WP] {ninja_name}: no gate_metrics BLOCKs found', file=sys.stderr)
        except Exception as gme:
            print(f'[NINJA_WP] gate_metrics parse warning: {gme}', file=sys.stderr)

    # --- Safe targeted write (avoid full yaml.dump — cmd_1407 AC2) ---
    with open(task_file, 'r', encoding='utf-8') as f:
        raw = f.read()

    # yaml.dump禁止(CLAUDE.md): 手動YAML構築でデータ消失を防止
    def _sv(v, multiline_indent=2):
        if v is None: return 'null'
        if isinstance(v, bool): return str(v).lower()
        if isinstance(v, (int, float)): return str(v)
        s = str(v)
        if '\n' in s:
            return '|-\n' + '\n'.join(' ' * multiline_indent + ln for ln in s.split('\n'))
        sq = chr(39)
        return sq + s.replace(sq, sq + sq) + sq
    def _yaml_lines(key, val, ind=0):
        p = ' ' * ind
        if not isinstance(val, (dict, list)):
            s = _sv(val, ind + 2)
            if '\n' in s:
                parts = s.split('\n')
                return [p + key + ': ' + parts[0]] + [p + x for x in parts[1:]]
            return [p + key + ': ' + s]
        if not val:
            return [p + key + ': ' + ('[]' if isinstance(val, list) else '{}')]
        r = [p + key + ':']
        if isinstance(val, dict):
            for k, v in val.items():
                r.extend(_yaml_lines(k, v, ind + 2))
        else:
            for item in val:
                r.extend(_list_item(item, ind))
        return r
    def _list_item(item, ind):
        p = ' ' * ind
        if not isinstance(item, (dict, list)):
            s = _sv(item, ind + 2)
            if '\n' in s:
                parts = s.split('\n')
                return [p + '- ' + parts[0]] + [p + '  ' + x for x in parts[1:]]
            return [p + '- ' + s]
        if isinstance(item, dict) and item:
            lines = []
            first = True
            for k, v in item.items():
                tag = '- ' if first else '  '
                first = False
                if isinstance(v, (dict, list)) and v:
                    lines.append(p + tag + k + ':')
                    if isinstance(v, list):
                        for sub in v:
                            lines.extend(_list_item(sub, ind + 2))
                    else:
                        for dk, dv in v.items():
                            lines.extend(_yaml_lines(dk, dv, ind + 4))
                else:
                    sv = _sv(v, ind + 4) if not isinstance(v, (dict, list)) else ('[]' if isinstance(v, list) else '{}')
                    if '\n' in sv:
                        parts = sv.split('\n')
                        lines.append(p + tag + k + ': ' + parts[0])
                        lines.extend(parts[1:])
                    else:
                        lines.append(p + tag + k + ': ' + sv)
            return lines
        return [p + '- ' + ('[]' if isinstance(item, list) else '{}')]
    def _safe_section_replace(text, section_name, new_value):
        """Replace a 2-space-indented section under task: without full yaml.dump"""
        frag = '\n'.join(_yaml_lines(section_name, new_value))
        indented = '\n'.join('  ' + line for line in frag.split('\n'))
        # 行ベースのブロック置換（正規表現はマルチライン値で誤マッチする）
        _lines = text.split('\n')
        _result = []
        _skip = False
        _inserted = False
        for _l in _lines:
            _s = _l.lstrip(' ')
            _i = len(_l) - len(_s)
            if _skip:
                if _s == '' or _i > 2 or (_i == 2 and _s.startswith('- ')):
                    continue
                _skip = False
            if _i == 2 and _s.startswith(section_name + ':'):
                _skip = True
                _result.append(indented)
                _inserted = True
                continue
            _result.append(_l)
        text = '\n'.join(_result)
        if not _inserted:
            task_idx = text.index('task:')
            rest = text[task_idx + 5:]
            top_m = re.search(r'^\S', rest, re.MULTILINE)
            if top_m:
                pos = task_idx + 5 + top_m.start()
                text = text[:pos] + indented + '\n' + text[pos:]
            else:
                text = text.rstrip('\n') + '\n' + indented + '\n'
        return text

    raw = _safe_section_replace(raw, 'ninja_weak_points', task['ninja_weak_points'])

    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w', encoding='utf-8') as f:
            f.write(raw)
        os.replace(tmp_path, task_file)
    except Exception:
        os.unlink(tmp_path)
        raise

    print(f'[NINJA_WP] {ninja_name}: {total} workarounds injected (top: {top_cat}={top_count})', file=sys.stderr)

except Exception as e:
    print(f'[NINJA_WP] ERROR: {e}', file=sys.stderr)
    sys.exit(1)
PY
        return 1
    fi
    rm -f "$py_output"
}

# ─── GP-198: session_state → previous_failures 注入（再配備時失敗履歴引継ぎ） ───
inject_session_state_hints() {
    local task_file="$1"
    [ -z "${_DEPLOY_PREV_SESSION_STATE:-}" ] && return 0
    # Failure history belongs to a command attempt, not to the ninja slot.
    # A newly assigned command must not inherit an unrelated task's gate failure.
    local current_parent_cmd
    current_parent_cmd=$(awk '
        /^[[:space:]]+parent_cmd:[[:space:]]*/ {
            line=$0
            sub(/^[[:space:]]+parent_cmd:[[:space:]]*/, "", line)
            gsub(/^["'\'' ]+|["'\'' ]+$/, "", line)
            print line
            exit
        }
    ' "$task_file" 2>/dev/null || true)
    if [ -z "${_DEPLOY_PREV_PARENT_CMD:-}" ] || [ -z "$current_parent_cmd" ] || \
       [ "$_DEPLOY_PREV_PARENT_CMD" != "$current_parent_cmd" ]; then
        return 0
    fi
    local ss_tmp
    ss_tmp=$(mktemp)
    printf '%s' "$_DEPLOY_PREV_SESSION_STATE" > "$ss_tmp"
    python3 - "$task_file" "$ss_tmp" <<'SS_INJECT_PY' 2>/dev/null || true
import json, sys, re, os, tempfile

task_yaml = sys.argv[1]
ss_tmp = sys.argv[2]

try:
    with open(ss_tmp) as f:
        ss = json.load(f)
except Exception:
    sys.exit(0)

if not ss:
    sys.exit(0)

def _one_line(text, limit=180):
    text = re.sub(r'\s+', ' ', str(text or '')).strip()
    if len(text) > limit:
        text = text[:limit - 1].rstrip() + '…'
    return text

attempt = ss.get('attempt', 0)
last_reason = _one_line(ss.get('last_block_reason', ''))
tried = [_one_line(t) for t in list(ss.get('tried_approaches', [])) if _one_line(t)]
diagnose_reason = _one_line(ss.get('diagnose_reason', ''))
approach_summary = _one_line(ss.get('approach_summary', ''))
prior_attempts = ss.get('prior_attempts', [])

if not attempt and not last_reason:
    sys.exit(0)

with open(task_yaml, encoding='utf-8') as f:
    raw = f.read()

def _sq(s):
    return "'" + str(s).replace("'", "''") + "'"

pf_lines = ['previous_failures:',
            f'  attempt: {attempt}',
            f'  last_block_reason: {_sq(last_reason)}',
            '  tried_approaches:']
for t in tried:
    pf_lines.append(f'  - {_sq(t)}')
if diagnose_reason:
    pf_lines.append(f'  diagnose_reason: {_sq(diagnose_reason)}')
if approach_summary:
    pf_lines.append(f'  approach_summary: {_sq(approach_summary)}')
if isinstance(prior_attempts, list) and prior_attempts:
    pf_lines.append('  prior_attempts:')
    unique_attempts = []
    seen_reasons = set()
    for item in reversed(prior_attempts):
        if not isinstance(item, dict):
            continue
        reason_key = _one_line(item.get('block_reason', '')).casefold()
        if reason_key in seen_reasons:
            continue
        seen_reasons.add(reason_key)
        unique_attempts.append(item)
        if len(unique_attempts) == 3:
            break
    for item in reversed(unique_attempts):
        if not isinstance(item, dict):
            continue
        pf_lines.append(f"  - attempt: {int(item.get('attempt', 0) or 0)}")
        item_block_reason = _one_line(item.get('block_reason', ''))
        item_diagnose_reason = _one_line(item.get('diagnose_reason', ''))
        item_approach_summary = _one_line(item.get('approach_summary', ''))
        pf_lines.append(f"    block_reason: {_sq(item_block_reason)}")
        if item_diagnose_reason:
            pf_lines.append(f"    diagnose_reason: {_sq(item_diagnose_reason)}")
        if item_approach_summary:
            pf_lines.append(f"    approach_summary: {_sq(item_approach_summary)}")
pf_frag = '\n'.join(pf_lines)
pf_indented = '\n'.join('  ' + l for l in pf_frag.split('\n'))

# 行ベースのブロック置換（正規表現はマルチライン値で誤マッチする）
_lines = raw.split('\n')
_result = []
_skip = False
_inserted = False
for _l in _lines:
    _s = _l.lstrip(' ')
    _i = len(_l) - len(_s)
    if _skip:
        if _s == '' or _i > 2 or (_i == 2 and _s.startswith('- ')):
            continue
        _skip = False
    if _i == 2 and _s.startswith('previous_failures:'):
        _skip = True
        _result.append(pf_indented)
        _inserted = True
        continue
    _result.append(_l)
if not _inserted:
    _result.append(pf_indented)
raw = '\n'.join(_result)

fd, tmp = tempfile.mkstemp(dir=os.path.dirname(task_yaml), suffix='.pf_tmp')
os.close(fd)
with open(tmp, 'w', encoding='utf-8') as f:
    f.write(raw)
os.replace(tmp, task_yaml)
print(f'[SESSION_HINT] previous_failures injected: attempt={attempt} prior_attempts={len(prior_attempts) if isinstance(prior_attempts, list) else 0}', file=sys.stderr)
SS_INJECT_PY
    rm -f "$ss_tmp"
}

# ─── GP-201: CoDD改善cmd → failure history自動注入 ───
# CoDD改善cmdを配備する際に、同一スクリプトの過去revert/regressionエントリを
# codd_refactor_registry.mdから検索し、タスクYAMLに自動注入する。
# 忍者は同じ失敗アプローチを繰り返さずに済む（ステートレスリトライ→ステートフル蓄積）。
inject_codd_failure_history() {
    local task_file="$1"
    local cmd_id stk registry

    cmd_id=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "parent_cmd" "" 2>/dev/null || true)
    [ -z "$cmd_id" ] && return 0

    stk="$SCRIPT_DIR/queue/shogun_to_karo.yaml"
    [ -f "$stk" ] || return 0

    registry="$SCRIPT_DIR/docs/research/codd_refactor_registry.md"
    [ -f "$registry" ] || return 0

    python3 - "$task_file" "$stk" "$cmd_id" "$registry" <<'CODD_HIST_PY' 2>/dev/null || true
import sys, os, re, tempfile

task_file    = sys.argv[1]
stk_path     = sys.argv[2]
cmd_id       = sys.argv[3]
registry_path = sys.argv[4]

# 1. shogun_to_karo.yamlからcmd_idのtitle+commandを取得 (yaml.safe_loadで確実にパース)
try:
    import yaml as _yaml
    with open(stk_path, encoding='utf-8') as f:
        stk_data = _yaml.safe_load(f) or {}
except Exception as e:
    print(f'[CODD_HIST] ERROR reading stk: {e}', file=sys.stderr)
    sys.exit(0)

cmds = stk_data.get('commands', {})
cmd_entry = cmds.get(cmd_id, {})
if not cmd_entry:
    sys.exit(0)

cmd_title   = str(cmd_entry.get('title',   '') or '')
cmd_command = str(cmd_entry.get('command', '') or '')
cmd_text    = cmd_title + '\n' + cmd_command

# 2. CoDD改善cmdかを判定 (title/commandに"codd"または"/codd-refactor"を含む)
if not re.search(r'codd|/codd-refactor', cmd_text, re.IGNORECASE):
    sys.exit(0)

# 3. command/titleから .sh ファイル名を抽出
scripts = re.findall(r'[a-zA-Z0-9_./-]+\.sh', cmd_text)
scripts = list(dict.fromkeys(scripts))  # unique, preserve order

if not scripts:
    sys.exit(0)

def _one_line(text, limit=180):
    text = re.sub(r'\s+', ' ', str(text or '')).strip()
    if len(text) > limit:
        text = text[:limit - 1].rstrip() + '…'
    return text

# 4. registryからrevert/regressionエントリを検索
# 台帳形式: | date | ninja | script | phase | before→after | spec |
failures = []
try:
    with open(registry_path, encoding='utf-8') as f:
        for line in f:
            if '|' not in line:
                continue
            cols = [c.strip() for c in line.split('|')]
            if len(cols) < 7:
                continue
            script_col = cols[3]   # 対象スクリプト/領域
            phase_col  = cols[4]   # Phase到達
            result_col = cols[5]   # Before→After
            spec_col   = cols[6] if len(cols) > 6 else ''

            for sname in scripts:
                basename = os.path.basename(sname)
                if not basename:
                    continue
                if basename in script_col:
                    if re.search(r'revert|regression', result_col + phase_col, re.IGNORECASE):
                        diagnosis = _one_line(phase_col.strip('`').strip())
                        result = _one_line(result_col.strip('`').strip())
                        failures.append({
                            'script': script_col.strip('`').strip(),
                            'diagnosis': diagnosis,
                            'result': result,
                        })
                        break  # 同一行を重複追加しない
except Exception as e:
    print(f'[CODD_HIST] ERROR reading registry: {e}', file=sys.stderr)
    sys.exit(0)

if not failures:
    sys.exit(0)

# 5. タスクYAMLに codd_failure_history: ブロックを注入
with open(task_file, encoding='utf-8') as f:
    raw = f.read()

def _sq(s):
    return "'" + str(s).replace("'", "''") + "'"

note = 'このスクリプトは過去にCoDD改善でrevert/regressionあり。同じアプローチを繰り返すな'
frag_lines = [
    'codd_failure_history:',
    f'  count: {len(failures)}',
    f'  note: {_sq(note)}',
    '  attempts:',
]
for fa in failures:
    frag_lines.append(f'  - script: {_sq(fa["script"])}')
    frag_lines.append(f'    diagnosis: {_sq(fa["diagnosis"])}')
    frag_lines.append(f'    result: {_sq(fa["result"])}')

frag     = '\n'.join(frag_lines)
indented = '\n'.join('  ' + l for l in frag.split('\n'))

# 行ベースのブロック置換（正規表現はマルチライン値で誤マッチする）
_lines = raw.split('\n')
_result = []
_skip = False
_inserted = False
for _l in _lines:
    _s = _l.lstrip(' ')
    _i = len(_l) - len(_s)
    if _skip:
        if _s == '' or _i > 2 or (_i == 2 and _s.startswith('- ')):
            continue
        _skip = False
    if _i == 2 and _s.startswith('codd_failure_history:'):
        _skip = True
        _result.append(indented)
        _inserted = True
        continue
    _result.append(_l)
if not _inserted:
    _result.append(indented)
raw = '\n'.join(_result)

fd, tmp = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.cdd_tmp')
os.close(fd)
try:
    with open(tmp, 'w', encoding='utf-8') as f:
        f.write(raw)
    os.replace(tmp, task_file)
except Exception:
    try:
        os.unlink(tmp)
    except OSError:
        pass
    raise

print(f'[CODD_HIST] codd_failure_history injected: {len(failures)} revert/regression entries', file=sys.stderr)
CODD_HIST_PY
}
