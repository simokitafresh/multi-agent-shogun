#!/usr/bin/env python3
"""inject_task_modifiers.py — Consolidated task YAML injection operations.

cmd_1393: Merged 7 separate Python subprocesses into 1 for performance.
Replaces: inject_engineering_preferences, inject_reports_to_read,
          inject_context_files, inject_credential_files,
          inject_context_update, inject_report_template,
          inject_execution_controls

Usage:
    TASK_FILE_ENV=<path> SCRIPT_DIR_ENV=<path> python3 scripts/lib/inject_task_modifiers.py
"""
import glob
import os
import sys
import tempfile

import yaml


def load_yaml_safe(path):
    try:
        with open(path, encoding='utf-8') as f:
            return yaml.safe_load(f) or {}
    except Exception:
        return {}


def atomic_write(data, task_file):
    tmp_fd, tmp_path = tempfile.mkstemp(
        dir=os.path.dirname(task_file), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w', encoding='utf-8') as f:
            yaml.dump(data, f, default_flow_style=False,
                      allow_unicode=True, indent=2)
        os.replace(tmp_path, task_file)
    except Exception:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise


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
                if t.get('task_id') == blocked_task_id:
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

    target_path = task.get('target_path', '')
    if not target_path or not os.path.isdir(target_path):
        warn = task.get('credential_warning', '')
        if not warn:
            task['credential_warning'] = (
                '⚠ 認証が必要なタスクだがtarget_pathが未設定。'
                '認証情報(.env等)の場所を家老に確認せよ。見つからなければ即報告。')
            print('[INJECT_CRED] WARN: auth task but no target_path',
                  file=sys.stderr)
            return True
        return False

    env_files = glob.glob(os.path.join(target_path, '.env.*'))
    env_base = os.path.join(target_path, '.env')
    if os.path.exists(env_base):
        env_files.append(env_base)

    all_env = [f for f in env_files if not f.endswith('.example')]

    if not all_env:
        warn = task.get('credential_warning', '')
        if not warn:
            task['credential_warning'] = (
                f'⚠ 認証が必要なタスクだが{target_path}に.envファイルが見つからない。'
                '認証情報の準備が必要。家老に即報告せよ。')
            print(f'[INJECT_CRED] WARN: auth task but no .env in '
                  f'{target_path}', file=sys.stderr)
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
    if not parent_cmd:
        return False

    def find_cmd_source(parent_cmd, script_dir):
        stk = os.path.join(script_dir, 'queue', 'shogun_to_karo.yaml')
        if os.path.exists(stk):
            obj = load_yaml_safe(stk)
            commands = obj.get('commands', [])
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
            if isinstance(commands, list):
                for cmd in commands:
                    if (isinstance(cmd, dict) and
                            str(cmd.get('id', '')).strip() == parent_cmd):
                        return cmd, cpath

        return None, ''

    cmd_entry, source_path = find_cmd_source(parent_cmd, script_dir)
    if cmd_entry is None:
        return False

    context_update = normalize_list(cmd_entry.get('context_update', []))
    if not context_update:
        return False

    existing = normalize_list(task.get('context_update', []))
    if existing == context_update:
        return False

    task['context_update'] = context_update
    rel_source = (os.path.relpath(source_path, script_dir)
                  if source_path else source_path)
    print(f'[INJECT_CONTEXT_UPDATE] Injected {len(context_update)} entries '
          f'from {rel_source}', file=sys.stderr)
    return True


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
    ]

    changed = False

    if 'stop_for' not in task or task.get('stop_for') is None:
        task['stop_for'] = []
        changed = True

    if 'never_stop_for' not in task or task.get('never_stop_for') is None:
        task['never_stop_for'] = NEVER_STOP_DEFAULTS
        changed = True

    ac_list = task.get('acceptance_criteria', [])
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


# ─── main ───
def main():
    task_file = os.environ.get('TASK_FILE_ENV', '')
    script_dir = os.environ.get('SCRIPT_DIR_ENV', '')

    if not task_file or not os.path.isfile(task_file):
        print('[TASK_MOD] Task file not found', file=sys.stderr)
        sys.exit(1)

    data = load_yaml_safe(task_file)
    if not data or 'task' not in data:
        sys.exit(0)

    task = data['task']
    changed = False

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
    ]

    for name, op in operations:
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
