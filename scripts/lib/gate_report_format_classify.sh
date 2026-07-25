#!/bin/bash
# gate_report_format_classify.sh — gate_report_format.shの終了コードを機械的に分類する共有正本
#
# 目的: gate_report_format.shの呼出元(inbox_write.sh / ninja_done.sh /
# cmd_complete_gate.sh / dashboard_update.sh)がそれぞれ独自の文字列prefix判定
# (grep -q "^FAIL") や「非ゼロ終了=品質FAIL」判定を重複実装すると、同型の誤帰属バグ
# (インフラ由来のsingle-flightロックタイムアウトを忍者の品質FAILとして扱ってしまう)
# が呼出元ごとに独立発生する。判定ロジックを本ファイル1箇所へ集約し、各呼出元は
# 終了コードを渡すだけで済むようにする。
#
# cmd_karo_hotfix_singleflight_fail_misattribution_20260725 (AC1):
# gate_report_format.shは終了コードで種別を返す(文字列prefixに依存しない):
#   0 = PASS
#   2 = INFRA_TIMEOUT (single-flightロック競合。忍者の品質問題ではない)
#   その他(1等) = QUALITY_FAIL (report YAML自体の品質問題)
#
# Usage:
#   source scripts/lib/gate_report_format_classify.sh
#   status=$(gate_report_format_classify "$exit_code")
#   # status: PASS | INFRA_TIMEOUT | QUALITY_FAIL
#
# Provenance (cmd_karo_hotfix_singleflight_fail_misattribution_20260725):
#   このfunction定義自体はd1499a6a7(cmd_complete_gate.sh側の遅延source化と共に
#   git追跡下へ移行)で導入。呼出側の実装はgate_report_format.sh側=118dc5ff8、
#   inbox_write.sh/ninja_done.sh/dashboard_update.sh側=df3421336に既出。

gate_report_format_classify() {
    local exit_code="${1:-1}"
    case "$exit_code" in
        0) echo "PASS" ;;
        2) echo "INFRA_TIMEOUT" ;;
        *) echo "QUALITY_FAIL" ;;
    esac
}
