#!/usr/bin/env bash
# gate_queue_yaml_reader_migration.sh
# cmd_karo_hotfix_queue_yaml_atomicity_202607110113 follow-up-2 (家老GATE BLOCK 02:09).
#
# yaml_field_set()/yaml_field_set_batch()/report_field_set.sh(fast path)/
# inbox_write.sh/pending_decision_write.sh はいずれも同一ディレクトリmktemp+mvで
# at-riskなqueue YAMLを公開する。この方式のrename(2)はWSL2 drvfs越しでは
# 瞬間的に対象パスを消失させうる(measured: bounded race harnessで GNU mv /
# Python os.replace / libc rename直呼び を各30ラウンド比較した結果、書込み単位
# あたりのbad率はmv 2.73%・os.replace 2.82%・rename_ctypes 2.36%で方式間に有意差
# なし。userspaceのrenameプリミティブ選択では0件化不可能と実証済み)。
#
# 唯一の0件化手段は「at-riskファイルを読む全readerがscripts/lib/yaml_safe_read.py
# のsafe_load_retry()を経由する」こと。本ゲートは、at-riskパターンに触れる
# bare yaml.safe_load()/yaml.load()呼出し(safe_load_retry不使用)を静的に検出し、
# 1件でもあればBLOCKする。「共通entry pointの存在」ではなく「全実consumerの
# 移行」を強制するための恒久ゲート。
#
# at-riskパターンはgate_queue_yaml_parse.shのpatterns変数と同一集合を保つ
# (queue/tasks/*.yaml, queue/reports/*.yaml, queue/inbox/*.yaml,
#  queue/shogun_to_karo.yaml, queue/insights.yaml, queue/pending_decisions.yaml)。
# 更新時は両ファイルを揃えて直すこと。

set -euo pipefail

# 注意: rg(ripgrep)はこのCLIの対話シェルにのみ関数として存在し、`bash foo.sh`の
# ような非対話サブシェル(git hook等の実行経路)ではPATHに無くcommand-not-foundで
# 静的に空扱いになりうる(2026-07-11 kotaro実測: bash -c 'command -v rg' はrc=1)。
# gate_no_hardcoded_ninja_list.shが同型のrg依存で気づかれずno-opしている恐れは
# decision_candidateへ回し、本ゲートはPOSIX grep(常にPATH解決される)のみで書く。

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# at-riskパターン(ファイル内のどこかにこの文字列があればat-risk対象を扱っていると判定)
AT_RISK_RE='queue/tasks/|queue/reports/|queue/inbox/|shogun_to_karo\.yaml|SHOGUN_TO_KARO|queue/insights\.yaml|INSIGHTS_FILE|pending_decisions\.yaml'

# 検査対象ディレクトリ(本番運用スクリプト。tests/はconsumerではないため対象外)
SCAN_DIRS=("$ROOT_DIR/scripts" "$ROOT_DIR/.claude/hooks")

violations=""
scanned_calls=0
migrated_calls=0

while IFS= read -r match; do
    [ -z "$match" ] && continue
    file="${match%%:*}"
    rest="${match#*:}"
    lineno="${rest%%:*}"
    line="${rest#*:}"

    stripped="${line#"${line%%[![:space:]]*}"}"
    [[ "$stripped" == "#"* ]] && continue

    # 自己除外: safe_load_retry()の実装自体は正規のbare yaml.safe_load
    [[ "$file" == *"scripts/lib/yaml_safe_read.py" ]] && continue
    # 自己除外: 本ゲート/コメント内の説明文で誤検知しない
    [[ "$file" == *"gate_queue_yaml_reader_migration.sh" ]] && continue

    scanned_calls=$((scanned_calls + 1))

    # 既にsafe_load_retry経由(同一行でラップ呼出し、またはこの行自体がsafe_load_retry定義側)
    if [[ "$line" == *safe_load_retry* ]]; then
        migrated_calls=$((migrated_calls + 1))
        continue
    fi

    # 対象ファイルがat-riskパターンに一切触れていなければ対象外(汎用YAMLユーティリティ等)
    if ! grep -Eq "$AT_RISK_RE" "$file" 2>/dev/null; then
        continue
    fi

    # 同一ファイル内でsafe_load_retryを一切import/使用していない場合のみ違反とする
    # (ファイル内の他の読み口で既に移行済みなら、当該行だけの個別事情を人手確認する
    #  余地を残すため、importの有無をシグナルにする)
    if grep -Eq 'from yaml_safe_read import safe_load_retry|yaml_safe_read\.safe_load_retry' "$file" 2>/dev/null; then
        # このファイルはsafe_load_retryを使う経路を持つが、この行はbareのまま
        violations="${violations}${file}:${lineno}: ${stripped}  [同ファイル内にsafe_load_retry経路ありだがこの呼出しは未移行]
"
    else
        violations="${violations}${file}:${lineno}: ${stripped}
"
    fi
done < <(grep -rnE 'yaml\.safe_load\(|yaml\.load\(|yaml\.safe_load_all\(' \
    --include='*.sh' --include='*.py' \
    "${SCAN_DIRS[@]}" 2>/dev/null || true)

unmigrated_count=0
if [ -n "$violations" ]; then
    unmigrated_count=$(printf '%s' "$violations" | grep -c ':' || true)
fi

if [ -n "$violations" ]; then
    {
        echo "BLOCK: at-riskなqueue YAMLへの未移行reader(bare yaml.safe_load/load)を検出。"
        echo "対象: yaml_field_set/yaml_field_set_batch/report_field_set/inbox_write/pending_decision_write"
        echo "が同一ディレクトリmktemp+mvで公開するファイル(queue/tasks,queue/reports,queue/inbox,"
        echo "shogun_to_karo.yaml,queue/insights.yaml,queue/pending_decisions.yaml)。"
        echo "drvfs越しrenameは瞬間的にFileNotFoundErrorを生じうる(userspaceのプリミティブ選択では"
        echo "回避不可能。実測済み)。scripts/lib/yaml_safe_read.pyのsafe_load_retry()を経由せよ。"
        echo ""
        echo "scanned_bare_calls=${scanned_calls} migrated=${migrated_calls} unmigrated=${unmigrated_count}"
        echo ""
        printf '%s' "$violations"
    } >&2
    exit 1
fi

echo "OK: at-riskなqueue YAML readerは全てsafe_load_retry経由(unmigrated=0, scanned_bare_calls=${scanned_calls}, migrated=${migrated_calls})"
