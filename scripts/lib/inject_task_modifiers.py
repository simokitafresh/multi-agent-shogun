#!/usr/bin/env python3
# semantic-links: [[タスク修飾子注入]]
"""inject_task_modifiers.py — Consolidated task YAML injection operations.

cmd_1393: Merged 7 separate Python subprocesses into 1 for performance.
Replaces: inject_engineering_preferences, inject_reports_to_read,
          inject_context_files, inject_credential_files,
          inject_context_update, inject_report_template,
          inject_execution_controls

Usage:
    TASK_FILE_ENV=<path> SCRIPT_DIR_ENV=<path> \
        python3 scripts/lib/inject_task_modifiers.py
"""
import glob
import os
import re
import sys
import tempfile

import yaml


DB_OPERATION_RE = re.compile(
    r'(^|[^A-Za-z0-9_])'
    r'(migrate|ALTER\s+TABLE|schema|database|init_database|SQLite|DROP|TRUNCATE|DELETE\s+FROM)'
    r'([^A-Za-z0-9_]|$)',
    re.IGNORECASE,
)

BACKUP_STOP_FOR = 'バックアップなしのDB変更'
BACKUP_INSTRUCTION_MARKER = '【DB変更前バックアップ必須】'
BACKUP_INSTRUCTION = (
    '【DB変更前バックアップ必須】DB操作cmd。変更前に対象DB/テーブルのバックアップを取得し、'
    '取得コマンド・保存先・復元手順をprogressまたは報告YAMLに記録せよ。'
)

LSA16_STOP_FOR = '本番パリティ未確認'
LSA16_INSTRUCTION_MARKER = '【LS-A16 本番パリティ必須】'
LSA16_INSTRUCTION = (
    '【LS-A16 本番パリティ必須】DM-Signal本番DB/recalculate系cmd。'
    'DB変更後は同一cmd内でDB/API/FEの3レイヤー貫通確認を実行し、'
    'precompute等の巻き添えrollbackがあり得る処理はsavepoint(begin_nested)で範囲限定せよ。'
)
LSA16_RE = re.compile(
    r'(fullrecalculate|recalculate-sync|recalculate_fast|本番DB|DB変更|'
    r'holding_signal|monthly_returns|precompute|pipeline_config)',
    re.IGNORECASE,
)


def load_yaml_safe(path):
    try:
        with open(path, encoding='utf-8') as f:
            return yaml.safe_load(f) or {}
    except Exception:
        return {}


def normalize_acceptance_criteria(value):
    """Return the canonical list form without discarding mapping-form AC bodies.

    karo-direct source YAMLs legitimately use ``AC1: {description: ...}``.
    Treating that mapping with ``list(value)`` keeps only the keys and silently
    destroys the acceptance criteria before later modifiers append their ACs.
    """
    if value in (None, ''):
        return []
    if isinstance(value, list):
        return list(value)
    if isinstance(value, dict):
        normalized = []
        for ac_id, body in value.items():
            if isinstance(body, dict):
                item = dict(body)
                item.setdefault('id', str(ac_id))
                if 'description' not in item and 'criteria' in item:
                    item['description'] = item['criteria']
            else:
                item = {'id': str(ac_id), 'description': str(body or '')}
            normalized.append(item)
        return normalized
    return [{'id': 'AC1', 'description': str(value)}]


def has_assigned_acs_scope(task):
    """True if task carries an explicit assigned_acs contract (split deployment).

    assigned_acs is authoritative for split subtasks (deploy_task.sh
    inject_parent_contract). Appending generic safety ACs to
    acceptance_criteria after assigned_acs is set makes the AC id set
    exceed the parent cmd's own AC namespace, which falsely BLOCKs
    parent contract validation (cmd_3873).
    """
    value = task.get('assigned_acs')
    if isinstance(value, list):
        return bool(value)
    if isinstance(value, str):
        return bool(value.strip())
    return False


def parent_cmd_entry(task, script_dir):
    parent_cmd = str(task.get('parent_cmd', '') or '').strip()
    if not parent_cmd or not script_dir:
        return {}
    stk = os.path.join(script_dir, 'queue', 'shogun_to_karo.yaml')
    if not os.path.exists(stk):
        return {}
    stk_data = load_yaml_safe(stk)
    cmd_data = stk_data.get('commands', {})
    if not isinstance(cmd_data, dict):
        return {}
    entry = cmd_data.get(parent_cmd, {})
    return entry if isinstance(entry, dict) else {}


def is_dm_signal_scope(task, parent_entry):
    """True only when project/target_path (structural fields) name DM-Signal.

    Free-text fields (description/purpose/command/title) can legitimately
    reference "DM-Signal" while describing or fixing an unrelated infra task
    (e.g. this very module's own task discusses a DM-Signal reproduction
    fixture). Matching those fields false-positives non-DM-Signal tasks into
    DM-Signal-only safety AC injection (cmd_karo_hotfix_split_ac_modifier_scope
    _202607131307: an infra/deploy_task.sh task got LSA16+target_date ACs
    solely because its own description mentioned cmd_3873). project/
    target_path are the authoritative scope boundary; only those are checked.
    """
    def _matches(entry):
        if not isinstance(entry, dict):
            return False
        project = str(entry.get('project', '') or '').strip().lower()
        target_path = str(entry.get('target_path', '') or '').lower()
        return project == 'dm-signal' or 'dm-signal' in target_path
    return _matches(task) or _matches(parent_entry)


def is_documentation_only_task(task):
    """Return True when every explicit target is a documentation file.

    Design documents often describe DB/recalculate/parity operations without
    performing them.  Those words are evidence to preserve in the document,
    not authorization to inject production-operation gates into the task.
    The structural target_path boundary therefore wins over prose matching.
    """
    raw_paths = task.get('target_path')
    if isinstance(raw_paths, str):
        paths = [raw_paths]
    elif isinstance(raw_paths, list):
        paths = [str(path or '') for path in raw_paths]
    else:
        return False

    paths = [path.strip() for path in paths if path.strip()]
    if not paths:
        return False
    documentation_suffixes = ('.md', '.mdx', '.rst', '.adoc')
    return all(path.lower().endswith(documentation_suffixes) for path in paths)


def atomic_write(data, task_file):
    tmp_fd, tmp_path = tempfile.mkstemp(
        dir=os.path.dirname(task_file), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w', encoding='utf-8') as f:
            yaml.dump(data, f, default_flow_style=False,
                      allow_unicode=True, indent=2, width=1000000)
        os.replace(tmp_path, task_file)
    except Exception:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise


def parse_selected_operations(raw_value):
    if not raw_value:
        return set()
    return {
        item.strip() for item in str(raw_value).split(',')
        if item.strip()
    }


# ─── engineering_preferences ───
def inject_engineering_preferences(task, script_dir):
    def is_empty(value):
        if value is None:
            return True
        if isinstance(value, str):
            return not value.strip()
        if isinstance(value, (list, dict)):
            return len(value) == 0
        return False

    def flatten_preferences(value):
        flattened = []
        if isinstance(value, str):
            text = value.strip()
            if text:
                flattened.append(text)
        elif isinstance(value, list):
            for item in value:
                flattened.extend(flatten_preferences(item))
        elif isinstance(value, dict):
            for nested in value.values():
                flattened.extend(flatten_preferences(nested))
        return flattened

    def dedupe_keep_order(values):
        seen = set()
        result = []
        for value in values:
            if value not in seen:
                seen.add(value)
                result.append(value)
        return result

    def extract_preferences_from_text(raw_text):
        lines = raw_text.splitlines()
        body = []
        capture = False
        for line in lines:
            stripped = line.strip()
            if not capture:
                if stripped == 'engineering_preferences:':
                    capture = True
                continue
            if stripped.startswith('#'):
                break
            if not stripped:
                body.append(line)
                continue
            if line.startswith((' ', '\t')):
                body.append(line)
                continue
            break
        if not body:
            return []
        try:
            section = yaml.safe_load(
                'engineering_preferences:\n' + '\n'.join(body) + '\n') or {}
        except Exception:
            return []
        return flatten_preferences(section.get('engineering_preferences'))

    existing = task.get('engineering_preferences')
    if not is_empty(existing):
        return False

    project = str(task.get('project', '') or '').strip()
    if not project:
        return False

    project_file = os.path.join(script_dir, 'projects', f'{project}.yaml')
    if not os.path.exists(project_file):
        task['engineering_preferences'] = []
        print(f'[INJECT_PREFS] WARN: project file not found for {project}',
              file=sys.stderr)
        return True

    with open(project_file, encoding='utf-8') as f:
        raw_text = f.read()

    preferences = []
    try:
        project_data = yaml.safe_load(raw_text)
    except Exception:
        project_data = None

    if isinstance(project_data, dict):
        preferences = flatten_preferences(
            project_data.get('engineering_preferences'))

    if not preferences:
        preferences = extract_preferences_from_text(raw_text)

    task['engineering_preferences'] = dedupe_keep_order(preferences)
    n = len(task['engineering_preferences'])
    print(f'[INJECT_PREFS] project={project} injected={n}', file=sys.stderr)
    return True


# ─── reports_to_read ───
def inject_reports_to_read(task, script_dir):
    if task.get('reports_to_read'):
        return False

    blocked_by = task.get('blocked_by', [])
    if not blocked_by:
        return False

    tasks_dir = os.path.join(script_dir, 'queue', 'tasks')
    reports_dir = os.path.join(script_dir, 'queue', 'reports')
    report_paths = []

    for blocked_task_id in blocked_by:
        if not os.path.isdir(tasks_dir):
            continue
        for fname in os.listdir(tasks_dir):
            if not fname.endswith('.yaml'):
                continue
            fpath = os.path.join(tasks_dir, fname)
            try:
                tdata = load_yaml_safe(fpath)
                if not tdata or 'task' not in tdata:
                    continue
                t = tdata['task']
                if (t.get('task_id') or t.get('_ac_task_id')) == blocked_task_id:
                    assigned_to = t.get('assigned_to', '')
                    if assigned_to:
                        blocked_parent_cmd = t.get('parent_cmd', '')
                        new_report = ''
                        if (isinstance(blocked_parent_cmd, str) and
                                blocked_parent_cmd.startswith('cmd_')):
                            new_report = os.path.join(
                                reports_dir,
                                f'{assigned_to}_report_{blocked_parent_cmd}.yaml')
                        legacy_report = os.path.join(
                            reports_dir, f'{assigned_to}_report.yaml')

                        if new_report and os.path.exists(new_report):
                            report_paths.append(
                                f'queue/reports/{os.path.basename(new_report)}')
                        elif os.path.exists(legacy_report):
                            report_paths.append(
                                f'queue/reports/{assigned_to}_report.yaml')
                        else:
                            alt = sorted(
                                glob.glob(os.path.join(
                                    reports_dir,
                                    f'{assigned_to}_report_cmd*.yaml')),
                                key=os.path.getmtime, reverse=True)
                            if alt:
                                report_paths.append(
                                    f'queue/reports/{os.path.basename(alt[0])}')
                    break
            except Exception:
                continue

    if not report_paths:
        return False

    seen = set()
    unique_paths = []
    for p in report_paths:
        if p not in seen:
            seen.add(p)
            unique_paths.append(p)

    task['reports_to_read'] = unique_paths

    desc = task.get('description', '')
    marker = '【参照報告】'
    if marker not in str(desc):
        lines = [marker + ' 以下の報告を読んでからレビューせよ']
        for rp in unique_paths:
            lines.append(f'  - {rp}')
        lines.append('─' * 40)
        prefix = '\n'.join(lines) + '\n\n'
        task['description'] = prefix + str(desc or '')

    print(f'[INJECT_REPORTS] Injected {len(unique_paths)} reports',
          file=sys.stderr)
    return True


# ─── context_files ───
def inject_context_files(task, script_dir):
    if task.get('context_files'):
        return False

    project = task.get('project', '')
    if not project:
        return False

    projects_yaml = os.path.join(script_dir, 'config', 'projects.yaml')
    if not os.path.exists(projects_yaml):
        return False

    pdata = load_yaml_safe(projects_yaml)

    ctx_files = None
    ctx_index = None
    for p in pdata.get('projects', []):
        if p.get('id') == project:
            ctx_files = p.get('context_files', [])
            ctx_index = p.get('context_file', '')
            break

    if not ctx_files:
        return False

    result = []
    if ctx_index:
        result.append(ctx_index)

    task_type = str(task.get('task_type', '')).lower()
    description = str(task.get('description', '')).lower()
    title = str(task.get('title', '')).lower()
    task_text = f'{task_type} {description} {title}'

    for cf in ctx_files:
        tags = cf.get('tags', [])
        filepath = cf.get('file', '')
        if not filepath:
            continue
        if not tags:
            result.append(filepath)
        elif any(tag.lower() in task_text for tag in tags):
            result.append(filepath)

    if len(result) <= 1:
        result = [ctx_index] if ctx_index else []
        for cf in ctx_files:
            filepath = cf.get('file', '')
            if filepath:
                result.append(filepath)

    task['context_files'] = result
    print(f'[INJECT_CTX] Injected {len(result)} context files for '
          f'project={project}', file=sys.stderr)
    return True


# ─── credential_files ───
def inject_credential_files(task, script_dir):
    auth_keywords = [
        'cdp', 'login', 'ログイン', '認証', 'credential', 'chrome', 'edge',
        'note.com', 'moneyforward', 'mf_', 'receipt', '領収書', 'selenium',
        'browser', 'preflight_cdp', '.env']

    task_text = ' '.join([
        str(task.get('command', '')),
        str(task.get('description', '')),
        str(task.get('context', '')),
        str(task.get('title', '')),
    ]).lower()

    if not any(kw.lower() in task_text for kw in auth_keywords):
        return False

    raw_target_paths = task.get('target_path', '')
    if isinstance(raw_target_paths, str):
        target_paths = [raw_target_paths]
    elif isinstance(raw_target_paths, list):
        target_paths = [
            str(path) for path in raw_target_paths
            if isinstance(path, (str, os.PathLike)) and str(path)
        ]
    else:
        target_paths = []

    target_paths = list(dict.fromkeys(target_paths))
    target_directories = [
        path for path in target_paths if os.path.isdir(path)
    ]
    if not target_directories:
        warn = task.get('credential_warning', '')
        if not warn:
            task['credential_warning'] = (
                '⚠ 認証が必要なタスクだがtarget_pathが未設定。'
                '認証情報(.env等)の場所を家老に確認せよ。見つからなければ即報告。')
            print('[INJECT_CRED] WARN: auth task but no target_path',
                  file=sys.stderr)
            return True
        return False

    env_files = []
    for target_directory in target_directories:
        env_files.extend(
            glob.glob(os.path.join(target_directory, '.env.*')))
        env_base = os.path.join(target_directory, '.env')
        if os.path.exists(env_base):
            env_files.append(env_base)

    all_env = sorted({
        path for path in env_files if not path.endswith('.example')
    })

    if not all_env:
        warn = task.get('credential_warning', '')
        if not warn:
            target_display = ', '.join(target_directories)
            task['credential_warning'] = (
                f'⚠ 認証が必要なタスクだが{target_display}に.envファイルが見つからない。'
                '認証情報の準備が必要。家老に即報告せよ。')
            print(f'[INJECT_CRED] WARN: auth task but no .env in '
                  f'{target_display}', file=sys.stderr)
            return True
        return False

    existing = task.get('context_files', []) or []
    existing_set = set(existing)
    added = []
    for ef in sorted(all_env):
        if ef not in existing_set:
            existing.append(ef)
            added.append(ef)

    if not added:
        return False

    task['context_files'] = existing
    print(f'[INJECT_CRED] Added {len(added)} credential files',
          file=sys.stderr)
    return True


# ─── context_update ───
def inject_context_update(task, script_dir):
    def normalize_list(value):
        if isinstance(value, list):
            return [str(v).strip() for v in value if str(v).strip()]
        if isinstance(value, str):
            text = value.strip()
            return [text] if text else []
        return []

    parent_cmd = str(task.get('parent_cmd', '') or '').strip()
    changed = False

    def find_cmd_source(parent_cmd, script_dir):
        stk = os.path.join(script_dir, 'queue', 'shogun_to_karo.yaml')
        if os.path.exists(stk):
            obj = load_yaml_safe(stk)
            commands = obj.get('commands', [])
            if isinstance(commands, dict):
                entry = commands.get(parent_cmd)
                if isinstance(entry, dict):
                    return entry, stk
            if isinstance(commands, list):
                for cmd in commands:
                    if (isinstance(cmd, dict) and
                            str(cmd.get('id', '')).strip() == parent_cmd):
                        return cmd, stk

        archive_dir = os.path.join(
            script_dir, 'queue', 'archive', 'cmds')
        candidates = glob.glob(
            os.path.join(archive_dir, f'{parent_cmd}_*.yaml'))
        for cpath in candidates:
            obj = load_yaml_safe(cpath)
            commands = obj.get('commands', [])
            if isinstance(commands, dict):
                entry = commands.get(parent_cmd)
                if isinstance(entry, dict):
                    return entry, cpath
            if isinstance(commands, list):
                for cmd in commands:
                    if (isinstance(cmd, dict) and
                            str(cmd.get('id', '')).strip() == parent_cmd):
                        return cmd, cpath

        return None, ''

    if parent_cmd:
        cmd_entry, source_path = find_cmd_source(parent_cmd, script_dir)
        if cmd_entry is not None:
            context_update = normalize_list(cmd_entry.get('context_update', []))
            if context_update:
                existing = normalize_list(task.get('context_update', []))
                if existing != context_update:
                    task['context_update'] = context_update
                    changed = True
                    rel_source = (os.path.relpath(source_path, script_dir)
                                  if source_path else source_path)
                    print(f'[INJECT_CONTEXT_UPDATE] Injected {len(context_update)} entries '
                          f'from {rel_source}', file=sys.stderr)

    # GA-457: an explicit cmd context_update is still authoritative, but a
    # source-boundary match must produce a durable candidate for tasks which
    # have no explicit update.  Keep this in the task YAML (the existing task
    # contract) instead of creating a parallel ledger or modifying context.
    candidates = inject_context_update_candidates(task, script_dir)
    if candidates is not None:
        existing_candidates = task.get('context_update_candidates')
        if existing_candidates != candidates:
            task['context_update_candidates'] = candidates
            changed = True
        if candidates:
            print(f'[INJECT_CONTEXT_UPDATE] Auto-generated {len(candidates)} '
                  'registry candidates', file=sys.stderr)
    return changed


def _task_source_paths(task, script_dir):
    """Return normalized source paths declared by a task.

    target_path is the normal deployment boundary; planned_paths and the
    other path-bearing fields are accepted so split/legacy task shapes use
    the same registry matcher.  Paths are data only: no filesystem access is
    needed to classify a source boundary.
    """
    values = []
    for key in ('target_path', 'planned_paths', 'source_paths',
                'files_to_modify', 'files_modified'):
        value = task.get(key)
        if isinstance(value, str):
            values.append(value)
        elif isinstance(value, list):
            values.extend(value)
    result = []
    seen = set()
    for value in values:
        if isinstance(value, dict):
            value = value.get('path', '')
        path = str(value or '').strip().replace('\\', '/')
        if not path:
            continue
        if os.path.isabs(path):
            try:
                path = os.path.relpath(path, script_dir).replace('\\', '/')
            except ValueError:
                path = path.lstrip('/')
        marker = '/DM-signal/'
        if marker in path:
            path = path.split(marker, 1)[1]
        path = path.removeprefix('./')
        if path not in seen:
            seen.add(path)
            result.append(path)
    return result


def _context_registry(script_dir):
    registry_path = os.path.join(
        script_dir, 'scripts', 'config', 'context_source_commits.tsv')
    if not os.path.isfile(registry_path):
        return []
    rows = []
    with open(registry_path, encoding='utf-8') as registry:
        for line_number, raw in enumerate(registry, 1):
            line = raw.rstrip('\n')
            if not line.strip() or line.lstrip().startswith('#'):
                continue
            fields = line.split('\t')
            if len(fields) != 4 or not all(field.strip() for field in fields):
                print(f'[INJECT_CONTEXT_UPDATE] WARN: malformed registry row '
                      f'{line_number}', file=sys.stderr)
                continue
            context_path, project, owner, triggers = [field.strip() for field in fields]
            rows.append({
                'path': context_path,
                'project': project,
                'owner': owner,
                'update_trigger': triggers,
            })
    return rows


def _source_matches_trigger(source_path, trigger):
    trigger = trigger.strip().replace('\\', '/')
    if not trigger:
        return False
    if trigger == 'root-fallback':
        return not source_path.startswith('context/')
    if trigger.startswith('cited:'):
        trigger = trigger[len('cited:'):]
    return (
        source_path == trigger
        or source_path.startswith(trigger.rstrip('/') + '/')
        or (trigger.endswith(('_', '-')) and source_path.startswith(trigger))
    )


_CONTEXT_FRONTIER_TASK_SOURCES = frozenset({
    'scripts/context_freshness_check.sh',
    'scripts/gates/gate_context_freshness.sh',
    'scripts/cmd_complete_gate.sh',
})


def _is_context_frontier_task(task, source_paths):
    """Return whether an infra task owns the cross-project freshness boundary.

    Context freshness scans both this repository and the external DM-Signal
    repository. A task that changes that scanner/gate therefore needs the
    complete DM-Signal registry frontier even when its own ``project`` and
    ``target_path`` are infra-local. Keep this opt-in structural: prose must
    not make an unrelated infra task inherit external context obligations.
    """
    project = str(task.get('project', '') or '').strip().lower()
    return project == 'infra' and any(
        source in _CONTEXT_FRONTIER_TASK_SOURCES for source in source_paths
    )


def inject_context_update_candidates(task, script_dir):
    """Build context-update candidates from the registered source boundary.

    ``[]`` is meaningful (a previously generated candidate set is stale),
    while ``None`` means the registry is unavailable and leaves the task
    untouched.  Explicit context_update paths are treated as already routed
    and are never duplicated as candidates.
    """
    registry = _context_registry(script_dir)
    if not registry:
        return None
    project = str(task.get('project', '') or '').strip()
    source_paths = _task_source_paths(task, script_dir)
    frontier_task = _is_context_frontier_task(task, source_paths)
    frontier_sources = [
        source for source in source_paths
        if source in _CONTEXT_FRONTIER_TASK_SOURCES
    ]
    explicit = set(normalize_context_paths(task.get('context_update', [])))
    candidates = []
    for row in registry:
        is_external_frontier = frontier_task and row['project'] == 'dm-signal'
        if project and row['project'] != project and not is_external_frontier:
            continue
        matched = [
            source for source in source_paths
            if source != row['path'] and any(
                _source_matches_trigger(source, trigger)
                for trigger in row['update_trigger'].split('|')
            )
        ]
        if is_external_frontier:
            # The freshness scanner is the source boundary for all external
            # DM-Signal contexts. Preserve scanner paths as provenance; do not
            # pretend the infra task changed backend/frontend source files.
            matched = frontier_sources
        if not matched or row['path'] in explicit:
            continue
        candidates.append({
            'path': row['path'],
            'owner': row['owner'],
            'update_trigger': row['update_trigger'],
            'source_paths': sorted(set(matched)),
        })
    return candidates


def normalize_context_paths(value):
    if isinstance(value, list):
        values = value
    elif isinstance(value, str):
        values = [value]
    else:
        values = []
    result = []
    for item in values:
        if isinstance(item, dict):
            item = item.get('path', item.get('context_path', ''))
        path = str(item or '').strip().removeprefix('./')
        if path:
            result.append(path)
    return result


# ─── report_template ───
def inject_report_template(task, script_dir):
    if task.get('report_template'):
        return False

    task_type = str(task.get('task_type', '')).lower()
    if not task_type:
        return False

    template_path = os.path.join(
        script_dir, 'templates', f'report_{task_type}.yaml')
    if not os.path.exists(template_path):
        return False

    template_data = load_yaml_safe(template_path)
    if template_data:
        task['report_template'] = template_data

    print(f'[REPORT_TPL] Injected {task_type} template', file=sys.stderr)
    return True


# ─── execution_controls ───
def inject_execution_controls(task):
    def ac_count(value):
        if isinstance(value, list):
            return len(value)
        if value is None:
            return 0
        if isinstance(value, str):
            return 1 if value.strip() else 0
        if isinstance(value, dict):
            return len(value.keys())
        return 0

    def extract_ac_ids(ac_list):
        if not isinstance(ac_list, list):
            return []
        ids = []
        for i, ac in enumerate(ac_list):
            if isinstance(ac, dict):
                ac_id = ac.get('id', '')
                if ac_id:
                    ids.append(str(ac_id))
                else:
                    ids.append(f'AC{i+1}')
            else:
                ids.append(f'AC{i+1}')
        return ids

    NEVER_STOP_DEFAULTS = [
        'CDPポート未応答 — preflight_cdp_flowが自動起動する。まず実行せよ',
        '既存インフラの自動対処機能があるエラー — まず実行→失敗なら報告',
        '自明な修正（typo等） — 実行→事後報告',
        '9p stall/hang疑い — まず独立検証（別ペイン/短いコマンド）で'
        '環境起因か切り分けよ',
    ]

    changed = False

    if 'stop_for' not in task or task.get('stop_for') is None:
        task['stop_for'] = []
        changed = True

    if 'never_stop_for' not in task or task.get('never_stop_for') is None:
        task['never_stop_for'] = NEVER_STOP_DEFAULTS
        changed = True

    ac_list = normalize_acceptance_criteria(
        task.get('acceptance_criteria', []))
    ac_ids = extract_ac_ids(ac_list)
    num_acs = ac_count(ac_list)

    if num_acs >= 3 and (
            'ac_priority' not in task or not task.get('ac_priority')):
        task['ac_priority'] = ' > '.join(ac_ids) if ac_ids else ''
        changed = True

    if num_acs >= 3 and (
            'ac_checkpoint' not in task or not task.get('ac_checkpoint')):
        task['ac_checkpoint'] = (
            '各AC完了後に checkpoint: 次ACの前提条件確認 '
            '→ scope drift検出 → progress更新')
        changed = True

    if 'parallel_ok' not in task or not task.get('parallel_ok'):
        if num_acs >= 2 and ac_ids:
            task['parallel_ok'] = ac_ids
        else:
            task['parallel_ok'] = []
        changed = True

    if changed:
        print('[EXEC_CTRL] Injected execution controls', file=sys.stderr)
    return changed


def inject_db_backup_controls(task, script_dir):
    if is_documentation_only_task(task):
        return False

    texts = [
        str(task.get('command', '') or ''),
        str(task.get('description', '') or ''),
    ]
    parent_entry = parent_cmd_entry(task, script_dir)
    if parent_entry:
        texts.extend([
            str(parent_entry.get('command', '') or ''),
            str(parent_entry.get('description', '') or ''),
        ])

    if not any(DB_OPERATION_RE.search(text) for text in texts):
        return False

    changed = False
    stop_for = task.get('stop_for')
    if not isinstance(stop_for, list):
        stop_for = [] if stop_for in (None, '') else [str(stop_for)]
    if BACKUP_STOP_FOR not in stop_for:
        task['stop_for'] = stop_for + [BACKUP_STOP_FOR]
        changed = True

    desc = str(task.get('description', '') or '')
    if BACKUP_INSTRUCTION_MARKER not in desc:
        task['description'] = BACKUP_INSTRUCTION + '\n  ────────────────────────────────────────\n' + desc
        changed = True

    if changed:
        print('[DB_BACKUP] Injected DB backup stop_for + instructions',
              file=sys.stderr)
    return changed


def inject_lsa16_production_parity_controls(task, script_dir):
    """LS-A16: DM-Signal本番DB/recalculate系cmdへ確認ACを事前注入する。"""
    if is_documentation_only_task(task):
        return False

    # LS-A16 constrains commands that mutate production state and therefore
    # require a post-write parity check.  Read-only reconnaissance often names
    # the production generator/table it is measuring (for example
    # ``monthly_returns``), but it neither authorizes nor performs a DB change.
    # Treating that noun as a mutation injected fullrecalculate/API/FE ACs into
    # recon2 experiments and changed their assigned scope after deployment.
    # Recon tasks must report observed parity through their own explicit ACs;
    # they must never acquire production-write obligations from keyword prose.
    task_type = str(task.get('task_type', '') or '').strip().lower()
    if task_type in {'recon', 'recon2', 'scout'}:
        return False

    parent_entry = parent_cmd_entry(task, script_dir)
    if not is_dm_signal_scope(task, parent_entry):
        return False

    fields = ['command', 'description', 'purpose']
    texts = [str(task.get(field, '') or '') for field in fields]
    if parent_entry:
        texts.extend(str(parent_entry.get(field, '') or '')
                     for field in ['command', 'description', 'purpose', 'title'])

    haystack = '\n'.join(texts)
    if not LSA16_RE.search(haystack):
        return False

    changed = False
    stop_for = task.get('stop_for')
    if not isinstance(stop_for, list):
        stop_for = [] if stop_for in (None, '') else [str(stop_for)]
    if LSA16_STOP_FOR not in stop_for:
        task['stop_for'] = stop_for + [LSA16_STOP_FOR]
        changed = True

    desc = str(task.get('description', '') or '')
    if LSA16_INSTRUCTION_MARKER not in desc:
        task['description'] = LSA16_INSTRUCTION + '\n  ────────────────────────────────────────\n' + desc
        changed = True

    # 分割task(assigned_acs指定あり)は親cmd AC契約が権威。安全ACを
    # acceptance_criteriaへ混入させず、stop_for/description注記のみ維持する
    # (cmd_3873: AC3-AC5混入でparent contract偽BLOCK)。
    if has_assigned_acs_scope(task):
        if changed:
            print('[LSA16_PARITY] Injected production parity stop_for only '
                  '(assigned_acs scope, AC injection skipped)', file=sys.stderr)
        return changed

    ac_list = normalize_acceptance_criteria(
        task.get('acceptance_criteria'))
    existing_text = '\n'.join(
        str(ac.get('description', '') if isinstance(ac, dict) else ac)
        for ac in ac_list
    )
    required_acs = [
        'DB/API/FEの3レイヤー貫通確認結果を一次情報で報告YAMLに記録する',
        'fullrecalculateまたは差分確認をDB変更直後に実行し、後回しにしない',
        'precompute等の巻き添えrollbackリスクがある変更ではsavepoint(begin_nested)または明示的な不要理由を記録する',
    ]
    new_acs = []
    for text in required_acs:
        if text not in existing_text:
            new_acs.append({'id': f'AC{len(ac_list) + len(new_acs) + 1}',
                            'description': text})
    if new_acs:
        task['acceptance_criteria'] = list(ac_list) + new_acs
        changed = True

    if changed:
        print('[LSA16_PARITY] Injected production parity stop_for + ACs',
              file=sys.stderr)
    return changed


# ─── recon task template hints ───
def inject_recon_task_template(task):
    task_type = str(task.get('task_type', '') or '').lower()
    if task_type not in ('recon', 'scout'):
        return False

    changed = False

    # GStack/GBrain takeaway #7 — 偵察は仮説を最低3本持ち、3連続不発でエスカレーション。
    if task.get('hypothesis_count') in (None, ''):
        task['hypothesis_count'] = 3
        changed = True

    if task.get('three_strike_rule') in (None, ''):
        task['three_strike_rule'] = (
            '仮説が3回連続で外れたら調査を止め、failed hypotheses と証拠を添えて家老へ報告'
        )
        changed = True

    marker = '【3-strike rule】'
    report_marker = '【report-write quick examples】'
    desc = str(task.get('description', '') or '')
    if marker not in desc:
        prefix = (
            f'{marker}\n'
            '  - 初期仮説は最低3本。hypothesis_count に現在の本数を維持せよ\n'
            '  - 3回連続で仮説が外れたら、追加探索で粘らずエスカレーションせよ\n'
            '  ────────────────────────────────────────\n\n'
        )
        task['description'] = prefix + desc
        changed = True
        desc = task['description']

    if report_marker not in desc:
        prefix = (
            f'{report_marker}\n'
            '  - 既存依存を参照のみで確認した場合:\n'
            '    echo \'- {path: scripts/existing.sh, reason: "既存依存として参照のみ。変更不要を確認", checked_not_modified: true}\' | bash scripts/report_field_set.sh <report> verified_existing_dependency -\n'
            '  - memory_references全体を書き直す場合:\n'
            '    echo \'- {id: MEM001, source: semantic_search, query: "検索語", summary: "要約", used: true, useful: true, reason: "判断に使用"}\' | bash scripts/report_field_set.sh <report> memory_references -\n'
            '  ────────────────────────────────────────\n\n'
        )
        task['description'] = prefix + desc
        changed = True

    if changed:
        print('[RECON_TEMPLATE] Injected 3-strike rule + hypothesis_count',
              file=sys.stderr)
    return changed


# ─── parity_target_date_ac ───
_PARITY_RE = re.compile(r'パリティ|parity', re.IGNORECASE)
_TARGET_DATE_AC = 'target_dateがproduction fullrecalculateと同一であること'


_GOLDEN_MARKER = '【ゴールデンデータ検証必須】'

_GOLDEN_INSTRUCTION = (
    '【ゴールデンデータ検証必須】BE変更impl。作業開始前にgolden snapshotを取得せよ。\n'
    '  手順: python backend/scripts/snapshot_recalc_results.py '
    '--output outputs/analysis/cmd_XXXX_parity/golden.json\n'
    '  修正後: fullrecalculate → golden.jsonとdiff。diff=0でパリティ証明。\n'
    '  ★修正の前後snapshotだけの比較は禁止(両方壊れていればdiff=0=偽パリティ)。\n'
    '  詳細→ docs/research/gunshi_fof_mr_nonlinear_rootcause_20260424.md §8'
)


def inject_golden_snapshot_for_be(task):
    """BE変更implタスクにゴールデンデータ取得指示を自動注入。

    条件: target_pathに'backend/'を含む AND task_typeがimpl
    既に注入済みならスキップ。
    """
    target_path = str(task.get('target_path', '') or '')
    task_type = str(task.get('task_type', '') or '')

    if 'backend' not in target_path:
        return False
    if task_type and task_type not in ('impl', 'fix'):
        return False

    desc = str(task.get('description', '') or '')
    if _GOLDEN_MARKER in desc:
        return False

    task['description'] = _GOLDEN_INSTRUCTION + '\n  ────────────────────────────────────────\n' + desc
    print('[GOLDEN] Injected golden snapshot instruction for BE impl task',
          file=sys.stderr)
    return True


def inject_parity_target_date_ac(task, script_dir):
    """パリティcmd検出 → target_date AC自動注入。

    タスクYAMLのtitle/command/description、または親cmdのtitle/commandに
    「パリティ」「parity」が含まれる場合に、acceptance_criteriaへ
    target_date確認ACを追記する。既にtarget_dateが含まれていれば何もしない。
    target_dateはDM-Signal production fullrecalculateの概念であり、project/
    target_path がDM-Signalを指す場合のみ対象とする(is_dm_signal_scope)。
    """
    if is_documentation_only_task(task):
        return False

    parent_entry = parent_cmd_entry(task, script_dir)
    if not is_dm_signal_scope(task, parent_entry):
        return False

    # 1. タスクYAML自体を確認
    task_texts = [
        str(task.get('title', '') or ''),
        str(task.get('command', '') or ''),
        str(task.get('description', '') or ''),
    ]
    is_parity = any(_PARITY_RE.search(t) for t in task_texts)

    # 2. タスク自体になければ親cmdを確認
    if not is_parity and parent_entry:
        for field in ['title', 'command', 'description']:
            if _PARITY_RE.search(str(parent_entry.get(field, '') or '')):
                is_parity = True
                break

    if not is_parity:
        return False

    # 2.5. scope_mode=NORMAL(変換/実装cmd)はパリティACの対象外 (LK002: AC4 stale contamination防止)
    #       パリティACが必要なのは scope_mode=PARITY/VERIFY/未設定のcmdのみ
    scope_mode = str(task.get('scope_mode', '') or '').strip().upper()
    if scope_mode == 'NORMAL':
        return False

    # 2.6. 分割task(assigned_acs指定あり)は親cmd AC契約が権威。target_date AC
    #       追加も親AC集合外となり parent contract を偽BLOCKする (cmd_3873)。
    if has_assigned_acs_scope(task):
        return False

    # 3. 既にtarget_dateACが存在すればスキップ
    ac_list = normalize_acceptance_criteria(
        task.get('acceptance_criteria'))
    for ac in ac_list:
        text = (str(ac.get('description', '') or '')
                if isinstance(ac, dict) else str(ac or ''))
        if 'target_date' in text.lower():
            return False

    # 4. 末尾に新ACを追加
    new_id = f'AC{len(ac_list) + 1}'
    task['acceptance_criteria'] = list(ac_list) + [
        {'id': new_id, 'description': _TARGET_DATE_AC}
    ]
    print(f'[PARITY_AC] Injected target_date AC ({new_id}) for parity cmd',
          file=sys.stderr)
    return True


# ─── main ───
def main():
    task_file = os.environ.get('TASK_FILE_ENV', '')
    script_dir = os.environ.get('SCRIPT_DIR_ENV', '')
    selected_operations = parse_selected_operations(
        os.environ.get('INJECT_TASK_MODIFIERS_ONLY', '')
    )

    if not task_file or not os.path.isfile(task_file):
        print('[TASK_MOD] Task file not found', file=sys.stderr)
        sys.exit(1)

    data = load_yaml_safe(task_file)
    if not data or 'task' not in data:
        sys.exit(0)

    task = data['task']
    changed = False

    original_acs = task.get('acceptance_criteria')
    normalized_acs = normalize_acceptance_criteria(original_acs)
    if original_acs not in (None, '') and normalized_acs != original_acs:
        task['acceptance_criteria'] = normalized_acs
        changed = True

    operations = [
        ('engineering_preferences',
         lambda: inject_engineering_preferences(task, script_dir)),
        ('reports_to_read',
         lambda: inject_reports_to_read(task, script_dir)),
        ('context_files',
         lambda: inject_context_files(task, script_dir)),
        ('credential_files',
         lambda: inject_credential_files(task, script_dir)),
        ('context_update',
         lambda: inject_context_update(task, script_dir)),
        ('report_template',
         lambda: inject_report_template(task, script_dir)),
        ('execution_controls',
         lambda: inject_execution_controls(task)),
        ('db_backup_controls',
         lambda: inject_db_backup_controls(task, script_dir)),
        ('lsa16_production_parity_controls',
         lambda: inject_lsa16_production_parity_controls(task, script_dir)),
        ('recon_task_template',
         lambda: inject_recon_task_template(task)),
        ('golden_snapshot_for_be',
         lambda: inject_golden_snapshot_for_be(task)),
        ('parity_target_date_ac',
         lambda: inject_parity_target_date_ac(task, script_dir)),
    ]

    for name, op in operations:
        if selected_operations and name not in selected_operations:
            continue
        try:
            if op():
                changed = True
        except Exception as e:
            print(f'[TASK_MOD] {name} ERROR: {e}', file=sys.stderr)

    if changed:
        atomic_write(data, task_file)
        print('[TASK_MOD] Written task modifications', file=sys.stderr)


if __name__ == '__main__':
    main()
