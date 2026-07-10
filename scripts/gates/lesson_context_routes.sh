#!/usr/bin/env bash
# semantic-links: [[教訓ライフサイクル管理]] [[GA-216_GA-217_lesson_context_reflux]]
# ============================================================
# lesson_context_routes.sh
# lesson subdomain → context file ルーティングのSSOT。
#
# scripts/lesson_write.sh（書込み時に実際にsyncするファイルを決定）と
# scripts/gates/gate_lesson_health.sh（未合流チェックがどのファイルの
# last_synced_lesson markerを見るべきか決定）の両方がこの関数を使う。
#
# 背景(GA-216/GA-217, cmd_karo_hotfix_ga216_lesson_context_reflux_202607101555):
#   このルーティング表は元々lesson_write.sh内にのみ inline定義されていた。
#   gate_lesson_health.shはconfig/projects.yamlの単一context_fileしか見ておらず、
#   subdomain(fe/be/gs)でdm-signal-frontend.md/dm-signal-ops.mdへ実際には
#   正しくsync済みの教訓を「未合流」と誤検知し続けていた
#   (L858-L863: 実体はfrontend.md/ops.mdへ合流済みだったが、dm-signal.mdの
#   markerだけを見るgateが繰り返しALERTを出していた)。
#   同じ関数を共有することで、書込み側とチェック側の「どこへsyncしたか」の
#   認識を構造的に一致させ、二重実装によるドリフトを防ぐ。
#   tests/unit/test_lesson_context_routes.bats がこの一致を回帰検証する。
#
# Usage:
#   source scripts/gates/lesson_context_routes.sh
#   PROJECT_META_CONTEXT_FILE="context/${proj_id}.md" \
#       resolve_lesson_context_route "$proj_id" "$subdomain"
#   echo "$CONTEXT_ROUTE_FILE" "$CONTEXT_ROUTE_ANCHOR"
#
# 呼び出し前提: 呼び出し側がデフォルトのプロジェクトcontext_fileを
# PROJECT_META_CONTEXT_FILE 環境変数/シェル変数へ設定しておくこと。
# 該当するroute caseがなければ CONTEXT_ROUTE_FILE はそのデフォルト値のまま。
# ============================================================

resolve_lesson_context_route() {
    local proj_id="$1"
    local subdomain="${2:-}"
    local first_subdomain="${subdomain%%,*}"

    CONTEXT_ROUTE_FILE="$PROJECT_META_CONTEXT_FILE"
    CONTEXT_ROUTE_ANCHOR=""

    case "$proj_id:$first_subdomain" in
        dm-signal:fe)
            CONTEXT_ROUTE_FILE="context/dm-signal-frontend.md"
            CONTEXT_ROUTE_ANCHOR='^## 12\. Frontend関連教訓'
            ;;
        dm-signal:be)
            CONTEXT_ROUTE_FILE="context/dm-signal-ops.md"
            CONTEXT_ROUTE_ANCHOR='^## §6-7 '
            ;;
        dm-signal:gs)
            CONTEXT_ROUTE_FILE="context/dm-signal-ops.md"
            CONTEXT_ROUTE_ANCHOR='^## §33 '
            ;;
        dm-signal:infra|infra:infra)
            CONTEXT_ROUTE_FILE="context/infrastructure.md"
            CONTEXT_ROUTE_ANCHOR='^## Infra教訓索引'
            ;;
        infra:*)
            CONTEXT_ROUTE_FILE="context/infrastructure.md"
            CONTEXT_ROUTE_ANCHOR='^## Infra教訓索引'
            ;;
    esac
}

# 既知のルーティングキー(subdomain値)の一覧。
# gate_lesson_health.shがproject毎にどのsubdomainを走査すればよいかを知るために使う。
# 新しいproj_id:subdomainケースをresolve_lesson_context_routeへ追加したら、
# ここにも同じsubdomain文字列を追加すること(test_lesson_context_routes.batsが
# case文中のsubdomainキーとの一致を検証する)。
LESSON_CONTEXT_ROUTE_KNOWN_SUBDOMAINS=(fe be gs infra)
