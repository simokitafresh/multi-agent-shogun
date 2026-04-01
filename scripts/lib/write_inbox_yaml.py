#!/usr/bin/env python3
"""Atomic YAML writer for inbox files.
yaml.dump禁止(CLAUDE.md) — 手動YAML構築でデータ消失を防止。
inbox_write.sh内の2箇所(軍師inbox書込み/メインinbox書込み)で使用。
"""
import os
import tempfile


def _serialize_value(v):
    """YAML値の安全なシリアライズ。yaml.dumpの代替。"""
    if isinstance(v, bool):
        return str(v).lower()
    s = str(v)
    if '\n' in s:
        return '|-\n' + '\n'.join('    ' + ln for ln in s.split('\n'))
    sq = chr(39)
    return sq + s.replace(sq, sq + sq) + sq


def write_inbox(inbox_path, data):
    """Atomic write of inbox YAML data to file.

    Args:
        inbox_path: Path to the inbox YAML file
        data: dict with 'messages' key containing list of message dicts
    """
    tmp_fd, tmp_path = tempfile.mkstemp(
        dir=os.path.dirname(inbox_path), suffix='.tmp'
    )
    try:
        with os.fdopen(tmp_fd, 'w', encoding='utf-8') as f:
            if not data.get('messages'):
                f.write('messages: []\n')
            else:
                f.write('messages:\n')
                for m in data['messages']:
                    keys = ['content', 'from', 'id', 'read', 'timestamp', 'type']
                    extra = sorted(k for k in m if k not in keys)
                    first = True
                    for k in keys + extra:
                        if k not in m:
                            continue
                        p = '- ' if first else '  '
                        first = False
                        f.write(f'{p}{k}: {_serialize_value(m[k])}\n')
        os.replace(tmp_path, inbox_path)
    except:
        os.unlink(tmp_path)
        raise
