#!/usr/bin/env bash
# deploy_task/context_injection.sh — cluster G: semantic, memory, causal, skill,
# model/context injection, production invariants, and postcondition helpers.
# Function bodies are extracted verbatim from deploy_task.sh.

deploy_task_semantic_phase_mark() {
    local phase="$1" started_ms="$2" cache_state="${3:-na}" now_ms
    now_ms="$(date +%s%3N)"
    log "semantic_context_phase: phase=${phase} wall_ms=$((now_ms - started_ms)) cache=${cache_state}"
    printf '%s\n' "$now_ms"
}

deploy_task_semantic_context_generate() {
    local purpose="$1" index_path="$2" helper="$3" search_script="$4" skills_root="$5"
    local raw_file rc
    raw_file="$(mktemp /tmp/deploy-semantic-raw.XXXXXX)" || return 1
    # A regular temporary output avoids a semantic-search background telemetry
    # child retaining a pipeline FD and making the caller wait after timeout.
    # Either producer or parser failure rejects cache publication.
    if env SEMANTIC_DISABLE_LLM=1 \
        SEMANTIC_INDEX_PATH="$index_path" \
        timeout "${DEPLOY_TASK_SEMANTIC_SEARCH_TIMEOUT_SEC:-5}" \
        bash "$search_script" "$purpose" > "$raw_file"; then
        if python3 "$helper" from-search-output \
            --purpose "$purpose" --skills-root "$skills_root" < "$raw_file"; then
            rc=0
        else
            rc=$?
        fi
    else
        rc=$?
    fi
    rm -f "$raw_file"
    return "$rc"
}

inject_semantic_concepts() {
    local task_file="$1"
    [ -f "$task_file" ] || return 0

    local _sem_phase_ms
    _sem_phase_ms="$(date +%s%3N)"

    local index_path="${SEMANTIC_INDEX_PATH:-$SCRIPT_DIR/docs/semantic-index/index.md}"
    [ -f "$index_path" ] || return 0

    # Read the query identity once.  project belongs in the cache key: an
    # identical sentence deployed to a different project is not the same
    # semantic-context request even when today's global index happens to make
    # both results equal.
    local purpose target_path project
    purpose=$(awk '/^  purpose:/{sub(/^  purpose: /,""); p=$0; next} p && /^  [a-z]/{exit} p{p=p " " $0} END{print p}' "$task_file" 2>/dev/null)
    [ -z "$purpose" ] && return 0
    target_path=$(awk '/^  target_path:/{sub(/^  target_path: /,""); print; exit}' "$task_file" 2>/dev/null)
    target_path="${target_path:-none}"
    project=$(awk '/^  project:/{sub(/^  project: /,""); print; exit}' "$task_file" 2>/dev/null)
    project="${project:-none}"
    _sem_phase_ms="$(deploy_task_semantic_phase_mark task_query "$_sem_phase_ms")"

    # One Python process reads/parses the index and scans all recommended skill
    # contracts.  The cached value is query data only, never task bytes.  Thus
    # same-query deploys share the expensive read without leaking task fields.
    # NO_MATCH/helper failure exits nonzero, so wave_cache never publishes a
    # negative or partial snapshot and a later corrected source is retried.
    local semantic_helper="${DEPLOY_TASK_SEMANTIC_HELPER:-$SCRIPT_DIR/scripts/lib/deploy_task_semantic_context_fast.py}"
    local semantic_search_script="${DEPLOY_TASK_SEMANTIC_SEARCH_SCRIPT:-$SCRIPT_DIR/scripts/semantic_search.sh}"
    local semantic_skills_root="${DEPLOY_TASK_SKILLS_ROOT:-$SCRIPT_DIR/skills}"
    local semantic_sources semantic_json
    semantic_sources=$(printf '%s\n' \
        "$index_path" \
        "$SCRIPT_DIR/context/semantic-map.md" \
        "$semantic_search_script" \
        "$SCRIPT_DIR/scripts/semantic_index.py" \
        "$semantic_helper" \
        "${SEMANTIC_MEMORY_DB_PATH:-$SCRIPT_DIR/data/multi_agent_shogun_memory.db}" \
        "skill-tree:$semantic_skills_root")
    semantic_json=$(deploy_task_wave_cache semantic_context_v2 \
        "$purpose|$target_path|$project" "$semantic_sources" \
        deploy_task_semantic_context_generate \
            "$purpose" "$index_path" "$semantic_helper" \
            "$semantic_search_script" "$semantic_skills_root") || semantic_json=""
    _sem_phase_ms="$(deploy_task_semantic_phase_mark semantic_query_cache "$_sem_phase_ms" wave)"

    local matches="" recommended_skills="" record_type record_value
    if [ -n "$semantic_json" ]; then
        while IFS=$'\t' read -r record_type record_value; do
            case "$record_type" in
                C) matches+="${record_value}"$'\n' ;;
                S) recommended_skills+="${record_value}"$'\n' ;;
            esac
        done < <(printf '%s\n' "$semantic_json" | python3 -c '
import json, sys
value = json.load(sys.stdin)
if not isinstance(value, dict):
    raise SystemExit(2)
concepts = value.get("concept_lines")
skills = value.get("skills")
if not isinstance(concepts, list) or not concepts or not isinstance(skills, list):
    raise SystemExit(2)
for concept in concepts:
    if not isinstance(concept, str) or "\t" in concept or "\n" in concept:
        raise SystemExit(2)
    print("C\t" + concept)
for skill in skills:
    if not isinstance(skill, str) or "\t" in skill or "\n" in skill:
        raise SystemExit(2)
    print("S\t" + skill)
')
    fi
    matches="${matches%$'\n'}"
    recommended_skills="${recommended_skills%$'\n'}"
    _sem_phase_ms="$(deploy_task_semantic_phase_mark result_decode "$_sem_phase_ms")"
    if [ -z "$matches" ]; then
        log "inject_semantic_concepts: NO_MATCH purpose=${purpose//$'\n'/ } target_path=${target_path//$'\n'/ }"
        return 0
    fi

    # task YAMLに semantic_concepts フィールドとして注入
    local indent="  "
    local inject_block="${indent}semantic_concepts:"
    while IFS= read -r line; do
        inject_block="${inject_block}"$'\n'"${indent}- \"${line}\""
    done <<< "$matches"

    if [ -n "$recommended_skills" ]; then
        inject_block="${inject_block}"$'\n'"${indent}recommended_skills:"
        while IFS= read -r skill; do
            [ -z "$skill" ] && continue
            inject_block="${inject_block}"$'\n'"${indent}- \"${skill}\""
        done <<< "$recommended_skills"
    fi

    # 既存のsemantic_concepts/recommended_skillsを除去してから追加
    local tmp_file
    tmp_file=$(mktemp "${task_file}.XXXXXX")
    awk '
        /^  semantic_concepts:/ { skip=1; next }
        /^  recommended_skills:/ { skip=1; next }
        skip && /^  - "/ { next }
        skip && /^  [a-z]/ { skip=0 }
        skip && /^[^ ]/ { skip=0 }
        !skip { print }
    ' "$task_file" > "$tmp_file"

    # description の直前に挿入（description は最後のフィールド）
    if grep -q "^  description:" "$tmp_file"; then
        local insert_file
        insert_file=$(mktemp)
        printf '%s\n' "$inject_block" > "$insert_file"
        awk -v insert_file="$insert_file" '
            /^  description:/ && !inserted {
                while ((getline line < insert_file) > 0) print line
                close(insert_file)
                inserted=1
            }
            { print }
        ' "$tmp_file" > "${tmp_file}.inserted"
        mv "${tmp_file}.inserted" "$tmp_file"
        rm -f "$insert_file"
    else
        echo "$inject_block" >> "$tmp_file"
    fi

    _yaml_field_set_publish_atomic "$tmp_file" "$task_file" || return 1
    _sem_phase_ms="$(deploy_task_semantic_phase_mark yaml_publish "$_sem_phase_ms")"
    log "inject_semantic_concepts: $(echo "$matches" | wc -l) concepts injected"

    # 推薦ログにninja_name付きで記録 (cmd_3244: precision照合キー修正)
    if [ -n "$recommended_skills" ]; then
        local _rec_ninja_name _rec_log _rec_ts _rec_hash
        _rec_ninja_name=$(basename "$task_file" .yaml)
        _rec_log="${SKILL_RECOMMEND_LOG_FILE:-$SCRIPT_DIR/logs/skill_recommend_log.yaml}"
        _rec_ts="$(date '+%Y-%m-%dT%H:%M:%S%z')"
        _rec_hash="$(printf '%s' "$purpose" | sha256sum | cut -d' ' -f1)"
        if [ -f "$_rec_log" ]; then
            {
                flock -w 5 9 || true
                {
                    printf -- '- ts: "%s"\n' "$_rec_ts"
                    printf '  agent_id: "deploy_task"\n'
                    printf '  ninja_name: "%s"\n' "$_rec_ninja_name"
                    printf '  prompt_hash: "%s"\n' "$_rec_hash"
                    printf '  recommended_skills:\n'
                    while IFS= read -r _rec_skill; do
                        [ -z "$_rec_skill" ] && continue
                        printf '  - "%s"\n' "$_rec_skill"
                    done <<< "$recommended_skills"
                } >> "$_rec_log"
            } 9>"${_rec_log}.lock"
            log "inject_semantic_concepts: recorded ${_rec_ninja_name} recommendation to skill_recommend_log"
        fi
    fi

    # L7穴2: 家老が配備時に因果概念を毎回消費する(startup gateは/clear後のみで低頻度)
    echo "INFO: [SEMANTIC_CONTEXT] 配備cmd関連概念:" >&2
    printf '%s\n' "$matches" | sed 's/^/  /' >&2
    local _causal_script="${SCRIPT_DIR}/scripts/causal_backlinks.sh"
    if [ "${SEMANTIC_DISABLE_CAUSAL:-0}" != "1" ] && [ -f "$_causal_script" ]; then
        local _target_stem
        _target_stem=$(awk '/^  target_path:/{sub(/^  target_path: /,""); gsub(/.*\//,""); sub(/\.[^.]*$/,""); print; exit}' "$task_file" 2>/dev/null)
        if [ -n "$_target_stem" ]; then
            local _causal_out
            _causal_out=$(bash "$_causal_script" "$_target_stem" 2>/dev/null | head -3 || true)
            [ -n "$_causal_out" ] && { echo "INFO: [CAUSAL_CONTEXT] target因果辺:" >&2; printf '%s\n' "$_causal_out" | sed 's/^/  → /' >&2; }
        fi
    fi
    _sem_phase_ms="$(deploy_task_semantic_phase_mark causal_context "$_sem_phase_ms")"
    # The injection operation succeeds even when no causal backlinks are
    # available.  Do not leak the status of the optional empty-output branch
    # as the function result; callers and fixed-SHA parity tests require a
    # successful semantic-context injection to return zero.
    return 0
}

# ─── 三層記憶先行知識注入(殿厳命2026-06-10: 使用しないのはバグ。L0-L7貫通) ───
# Level5: 配備時に記憶DBから先行知識(過去の裁定/類似cmd)を自動検索しtask YAMLに注入
inject_memory_db_context() {
    local task_file="$1"
    [ -f "$task_file" ] || return 0

    local query_script="$SCRIPT_DIR/scripts/memory_db_query.sh"
    [ -f "$query_script" ] || { log "inject_memory_db_context: query script not found"; return 0; }
    local db_path="${SHOGUN_MEMORY_DB:-$SCRIPT_DIR/data/multi_agent_shogun_memory.db}"

    # purposeからキーワード抽出
    local purpose
    purpose=$(awk '/^  purpose:/{gsub(/^  purpose: *"?/,""); gsub(/"$/,""); print; exit}' "$task_file" 2>/dev/null)
    [ -n "$purpose" ] || return 0

    # 2-3語のキーワードを抽出してFTS5検索
    local keywords result=""
    keywords=$(echo "$purpose" | tr '　/ ()（）' '\n' | grep -E '.{3,}' | head -3 | tr '\n' ' ')
    [ -n "$keywords" ] || return 0

    # cmd_3758: キーワード毎に別プロセスで叩いていたのをUNION ALLで1クエリ/1プロセスに統合(per-keyword LIMIT 2は維持)
    local kw kw_esc combined_sql=""
    for kw in $keywords; do
        kw_esc="${kw//\'/\'\'}"
        if [ -n "$combined_sql" ]; then
            combined_sql="${combined_sql}"$'\nUNION ALL\n'
        fi
        combined_sql="${combined_sql}SELECT ts || ' | ' || substr(summary,1,100) FROM events WHERE summary LIKE '%${kw_esc}%' AND event_type IN ('conversation','knowledge','ruling') ORDER BY ts DESC LIMIT 2"
    done
    if declare -F deploy_task_wave_cache >/dev/null 2>&1; then
        result=$(deploy_task_wave_cache memory "$keywords|$combined_sql" "$db_path" \
            timeout "${DEPLOY_TASK_MEMORY_CONTEXT_TIMEOUT_SEC:-3}" bash "$query_script" "$combined_sql" 2>/dev/null) || result=""
    else
        # Keep this function usable by isolated callers/tests that source only it.
        # The normal deploy path always defines deploy_task_wave_cache above.
        result=$(bash "$query_script" "$combined_sql" 2>/dev/null) || result=""
    fi
    [ -n "$result" ] || { log "inject_memory_db_context: no hits for: $keywords"; return 0; }

    # task YAMLに memory_db_context フィールドとして注入
    local indent="  "
    local inject_block="${indent}memory_db_context:"
    local line seen_lines=$'\n'
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            case "$seen_lines" in
                *$'\n'"$line"$'\n'*) continue ;;
            esac
            seen_lines="${seen_lines}${line}"$'\n'
            line="${line//$'\r'/}"
            line="${line//\'/\'\'}"
            inject_block="${inject_block}"$'\n'"${indent}- '${line}'"
        fi
    done <<< "$(echo "$result" | head -5)"

    # 既存のmemory_db_contextを除去してから追加
    local tmp_file
    tmp_file=$(mktemp)
    awk '
        /^  memory_db_context:/ { skip=1; next }
        skip && /^  [^ ]/ { skip=0 }
        skip { next }
        { print }
    ' "$task_file" > "$tmp_file"
    # task: ブロックの末尾(次のトップレベルキーの前)に挿入
    awk -v block="$inject_block" '
        printed == 0 && /^[^ ]/ && prev ~ /^  / { print block; printed=1 }
        { prev=$0; print }
        END { if (printed==0) print block }
    ' "$tmp_file" > "${task_file}.tmp" && mv "${task_file}.tmp" "$task_file"
    rm -f "$tmp_file"
    log "inject_memory_db_context: $(echo "$result" | grep -c '.' || echo 0) entries injected"
}

# ─── 因果リンク注入（task YAMLにcmdのoriginリンクを挿入） ───
# Level5: 忍者が関連する過去の失敗/裁定因果を自動で知る。意志依存ゼロ。
inject_causal_links() {
    local task_file="$1"
    [ -f "$task_file" ] || return 0

    local stk="$SCRIPT_DIR/queue/shogun_to_karo.yaml"
    [ -f "$stk" ] || return 0

    # parent_cmdを取得
    local parent_cmd
    parent_cmd=$(awk '/^  parent_cmd:/{sub(/^  parent_cmd:[[:space:]]*/,""); gsub(/'"'"'|"/,""); print; exit}' "$task_file" 2>/dev/null)
    [ -z "$parent_cmd" ] && return 0

    # shogun_to_karo.yamlからoriginフィールドを抽出
    local origin
    origin=$(awk -v cmd="$parent_cmd" '
        /^  [^ ]/ {
            if (in_cmd) { exit }
            s = $0; sub(/^  /, "", s); sub(/:.*/, "", s)
            if (s == cmd) { in_cmd = 1; next }
        }
        in_cmd && /^    origin:/ {
            val = $0; sub(/^    origin:[[:space:]]*/, "", val)
            fc = substr(val, 1, 1); lc = substr(val, length(val), 1)
            if (length(val) >= 2 && ((fc == "\"" && lc == "\"") || (fc == "\x27" && lc == "\x27")))
                val = substr(val, 2, length(val) - 2)
            print val
            exit
        }
    ' "$stk" 2>/dev/null)
    [ -z "$origin" ] && return 0

    # [[...]]形式のリンクを抽出
    local links
    links=$(printf '%s\n' "$origin" | grep -oE '\[\[[^]]+\]\]' | sort -u)
    [ -z "$links" ] && return 0

    # task YAMLにrelated_causal_linksフィールドとして注入
    local indent="  "
    local inject_block="${indent}related_causal_links:"
    while IFS= read -r link; do
        [ -z "$link" ] && continue
        inject_block="${inject_block}"$'\n'"${indent}- \"${link}\""
    done <<< "$links"

    # 既存のrelated_causal_linksを除去してから追加
    local tmp_file
    tmp_file=$(mktemp "${task_file}.XXXXXX")
    awk '
        /^  related_causal_links:/ { skip=1; next }
        skip && /^  - / { next }
        skip && /^  [a-zA-Z_][a-zA-Z0-9_]*:/ { skip=0 }
        skip && /^[^ ]/ { skip=0 }
        !skip { print }
    ' "$task_file" > "$tmp_file"

    # description の直前に挿入（description は最後のフィールド）
    if grep -q "^  description:" "$tmp_file"; then
        local insert_file
        insert_file=$(mktemp)
        printf '%s\n' "$inject_block" > "$insert_file"
        awk -v insert_file="$insert_file" '
            /^  description:/ && !inserted {
                while ((getline line < insert_file) > 0) print line
                close(insert_file)
                inserted=1
            }
            { print }
        ' "$tmp_file" > "${tmp_file}.inserted"
        mv "${tmp_file}.inserted" "$tmp_file"
        rm -f "$insert_file"
    else
        printf '%s\n' "$inject_block" >> "$tmp_file"
    fi

    _yaml_field_set_publish_atomic "$tmp_file" "$task_file" || return 1
    log "inject_causal_links: $(printf '%s\n' "$links" | wc -l) links injected from ${parent_cmd}.origin"
}

# ─── 標準スキル注入（全task YAMLに常時使用スキルを明示） ───
# Level5: 忍者が報告/commit時に必要なスキルを自動で知る。意志依存ゼロ。
inject_standard_skills() {
    local task_file="$1"
    [ -f "$task_file" ] || return 0

    local inject_block
    inject_block="  standard_skills:"$'\n'
    inject_block="${inject_block}  - \"report-write\""$'\n'
    inject_block="${inject_block}  - \"verdict-check\""$'\n'
    inject_block="${inject_block}  - \"ninja-commit\""

    local tmp_file
    tmp_file=$(mktemp "${task_file}.XXXXXX")
    awk '
        /^  standard_skills:/ { skip=1; next }
        skip && /^  - / { next }
        skip && /^  [a-zA-Z_][a-zA-Z0-9_]*:/ { skip=0 }
        skip && /^[^ ]/ { skip=0 }
        !skip { print }
    ' "$task_file" > "$tmp_file"

    if grep -q "^  description:" "$tmp_file"; then
        local insert_file
        insert_file=$(mktemp)
        printf '%s\n' "$inject_block" > "$insert_file"
        awk -v insert_file="$insert_file" '
            /^  description:/ && !inserted {
                while ((getline line < insert_file) > 0) print line
                close(insert_file)
                inserted=1
            }
            { print }
        ' "$tmp_file" > "${tmp_file}.inserted"
        mv "${tmp_file}.inserted" "$tmp_file"
        rm -f "$insert_file"
    else
        printf '%s\n' "$inject_block" >> "$tmp_file"
    fi

    _yaml_field_set_publish_atomic "$tmp_file" "$task_file" || return 1
    log "inject_standard_skills: standard skills injected"
}

# ─── push_allowed自動付与（cmd_3820: ACにpush要求があるcmdでG2ガードBLOCK→家老WAが発生） ───
# Level5: ACに'push'があるcmdは配備時にpush_allowed:trueを自動付与し、忍者の権限不足による
# git push BLOCK(.claude/hooks/pre-bash-combined.sh check_main_branch_protection)と
# karo_workarounds category=push_deploy_permission_gap(cmd_3820)の再発を防ぐ。
# §42v2(2026-07-10殿裁定: 自走push+deploy)に伝播していなかった権限設定を接続する。
inject_push_allowed() {
    local task_file="$1"
    [ -f "$task_file" ] || return 0

    # 既にpush_allowedが設定済み（preinject/手動設定）なら上書きしない
    grep -q '^[[:space:]]*push_allowed:' "$task_file" && return 0

    local ac_text
    ac_text="$(awk '
        /^  acceptance_criteria:/ { f=1; next }
        f && /^  [a-zA-Z_][a-zA-Z0-9_]*:/ { f=0 }
        f { print }
    ' "$task_file")"

    # \bpush\b はC.UTF-8ロケールで日本語(カナ/漢字)に直接隣接するとASCII境界を検出できない
    # (例:「pushして」「push完了」がNOMATCH)。ASCII文字以外を境界とみなす自前境界で代替する。
    # 否定形(push禁止/pushはしない/pushせず/pushしない/push不可/pushは行わない/no push/do not push/
    # must not push/push未)は「pushを要求していない」ので付与対象から除く。
    # 2026-08-18 02:55 実測: cmd_4349/4351/4352のAC『(pushはしない)』『push禁止』が語句一致で
    # push_allowed:true に反転し、cmd_complete_gateのpre-GATE autopushがGitHub不安定中(殿裁定
    # 00:45 deploy凍結)にorigin/main→Render自動deployまで進んだ。DOC_LANE_ROUTING偽陽性(73449dd3)と同型。
    local push_positive
    push_positive="$(printf '%s\n' "$ac_text" \
        | sed -E 's/(^|[^A-Za-z])(no|do not|must not|never|without)[[:space:]]+push($|[^A-Za-z])/\1__NEGPUSH__\3/Ig' \
        | sed -E 's/(^|[^A-Za-z])push(は|を|も)?(禁止|不可|しない|せず|しません|未実施|未|は行わない|を行わない|するな)/\1__NEGPUSH__/g' \
        | grep -ciE '(^|[^A-Za-z])push($|[^A-Za-z])' || true)"
    if [ "${push_positive:-0}" -gt 0 ]; then
        yaml_field_set "$task_file" "task" "push_allowed" "true" \
            && log "inject_push_allowed: AC内に'push'検出。push_allowed=trueを自動付与(cmd_3820 G2ガード解消)"
    fi
}

inject_model_injection_profile() {
    local task_file="$1"
    local ninja_name="$2"
    [ -f "$task_file" ] || return 0

    local model_label family intensity tmp_file inject_block indent="  "
    model_label="$(cli_model_display "$ninja_name" 2>/dev/null || true)"
    [ -n "$model_label" ] || model_label="$(FIELD_GET_NO_LOG=1 _cli_lookup_settings_get "$ninja_name" model_name unknown 2>/dev/null || true)"
    [ -n "$model_label" ] || model_label="unknown"
    family="$(model_injection_profile_family "$model_label")"
    intensity="$(model_injection_profile_intensity "$model_label")"

    inject_block="${indent}model_injection_profile:"
    inject_block="${inject_block}"$'\n'"${indent}  model_label: \"${model_label}\""
    inject_block="${inject_block}"$'\n'"${indent}  family: \"${family}\""
    inject_block="${inject_block}"$'\n'"${indent}  injection_intensity: \"${intensity}\""
    inject_block="${inject_block}"$'\n'"${indent}  protocol: \"T5弱LLM構造化プロトコル\""
    inject_block="${inject_block}"$'\n'"${indent}  report_contract:"
    inject_block="${inject_block}"$'\n'"${indent}  - \"binary_checks全resultをyes/noで記入\""
    inject_block="${inject_block}"$'\n'"${indent}  - \"lessons_useful全reasonを具体記入\""
    inject_block="${inject_block}"$'\n'"${indent}  - \"files_modifiedはrepo相対path形式\""
    inject_block="${inject_block}"$'\n'"${indent}  - \"D7適用表を証跡化: 新behavior=新/拡張test、bugfix=再現regression、behavior不変refactor=既存coverage維持、docs/data-only=実行test免除根拠。既存contract再利用、配置二値基準、モック4類型、contract消滅時のみ削除\""
    inject_block="${inject_block}"$'\n'"${indent}  - \"任務帰属検証契約: 反復・報告直前とも bash scripts/run_tests.sh task queue/tasks/${ninja_name}.yaml を実行し、task/reportの所有pathから選ばれたテストだけをbinary_checksへ帰属させる。選択対象はFAIL0・SKIP0を必須とし、scope外FAILを当該任務のFAILへ混入させない。run_tests.sh unit全量は個別taskで要求せず、fixed-SHAまたはwave最終checkpointで共有1回だけ実行する\""
    if [ "$intensity" = "max" ]; then
        inject_block="${inject_block}"$'\n'"${indent}  extra_scaffold:"
        inject_block="${inject_block}"$'\n'"${indent}  - \"ACごとに実テスト証跡をresult.detailsへ記録\""
        inject_block="${inject_block}"$'\n'"${indent}  - \"報告前にplaceholder残存確認とgate_report_formatを実行\""
        inject_block="${inject_block}"$'\n'"${indent}  - \"hook_failures.detailsはcount>0なら文字列でなくmapping形式で記入: cause/independent_verification/bypass_record/post_verification/post_verification_result/post_verification_headの6キー必須。post_verification_headは事後検証を実測した7-40文字hexのcommit hash(LG083)\""
    fi

    tmp_file=$(mktemp "${task_file}.XXXXXX")
    awk '
        /^  model_injection_profile:/ { skip=1; next }
        skip && /^  [a-zA-Z_][a-zA-Z0-9_]*:/ { skip=0 }
        skip && /^[^ ]/ { skip=0 }
        !skip { print }
    ' "$task_file" > "$tmp_file"

    insert_task_block_before_description "$tmp_file" "$inject_block"
    _yaml_field_set_publish_atomic "$tmp_file" "$task_file" || return 1
    log "inject_model_injection_profile: ninja=${ninja_name} model=${model_label} intensity=${intensity}"
}

insert_task_block_before_description() {
    local tmp_file="$1"
    local inject_block="$2"

    if grep -q "^  description:" "$tmp_file"; then
        local insert_file
        insert_file=$(mktemp)
        printf '%s\n' "$inject_block" > "$insert_file"
        awk -v insert_file="$insert_file" '
            /^  description:/ && !inserted {
                while ((getline line < insert_file) > 0) print line
                close(insert_file)
                inserted=1
            }
            { print }
        ' "$tmp_file" > "${tmp_file}.inserted"
        mv "${tmp_file}.inserted" "$tmp_file"
        rm -f "$insert_file"
    else
        printf '%s\n' "$inject_block" >> "$tmp_file"
    fi
}

task_targets_are_documentation_only() {
    local task_file="$1"
    python3 - "$task_file" <<'PY'
import sys
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)

try:
    data = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
except Exception:
    raise SystemExit(1)
task = data.get("task") or data
raw = [task.get("target_path"), task.get("planned_paths")]
paths = []
for value in raw:
    if isinstance(value, str):
        paths.append(value)
    elif isinstance(value, list):
        paths.extend(value)
paths = [str(path or "").strip() for path in paths if str(path or "").strip()]
suffixes = (".md", ".mdx", ".rst", ".adoc")
raise SystemExit(0 if any(path.lower().endswith(suffixes) for path in paths) else 1)
PY
}

# ─── DM-Signal PF削除/復元運用ガードレール注入 ───
# Level5: cmd_3786で露呈した前提知識不備をタスクYAMLへ自動注入し、
# PF一括削除/restore-all/rollback系で同じ試行錯誤を再発させない。
inject_dm_signal_pf_operation_guardrails() {
    local task_file="$1"
    [ -f "$task_file" ] || return 0
    task_targets_are_documentation_only "$task_file" && {
        log "inject_dm_signal_pf_operation_guardrails: documentation-only target, skip"
        return 0
    }

    local project task_type title purpose command_text parent_cmd haystack
    project=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "project" "" 2>/dev/null || true)
    [ "$project" = "dm-signal" ] || return 0

    task_type=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "task_type" "" 2>/dev/null || true)
    title=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "title" "" 2>/dev/null || true)
    purpose=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "purpose" "" 2>/dev/null || true)
    command_text=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "command" "" 2>/dev/null || true)
    parent_cmd=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "parent_cmd" "" 2>/dev/null || true)

    if [ -n "$parent_cmd" ] && [ -f "$SCRIPT_DIR/queue/shogun_to_karo.yaml" ]; then
        command_text="${command_text}
$(awk -v cmd="$parent_cmd" '
    /^  [a-zA-Z0-9_-]+:/ {
        cur=$0
        sub(/^[[:space:]]*/, "", cur)
        sub(/:.*$/, "", cur)
    }
    cur == cmd && /^(    title:|    type:|    purpose:|    command:|    acceptance_criteria:|        )/ { print }
' "$SCRIPT_DIR/queue/shogun_to_karo.yaml" 2>/dev/null || true)"
    fi

    haystack="${task_type}
${title}
${purpose}
${command_text}"

    printf '%s\n' "$haystack" | grep -Eqi 'restore-all|restore|復元|rollback|ロールバック|portfolio_archive|archive.*portfolio|PF.*(削除|復元|rollback|ロールバック)|portfolio.*(delete|restore)|一括削除|cmd_3785|cmd_3786' || return 0

    local tmp_file inject_block indent="  "
    tmp_file=$(mktemp "${task_file}.XXXXXX")
    awk '
        /^  dm_signal_pf_operation_guardrails:/ { skip=1; next }
        skip && /^  [a-zA-Z_][a-zA-Z0-9_]*:/ { skip=0 }
        skip && /^[^ ]/ { skip=0 }
        !skip { print }
    ' "$task_file" > "$tmp_file"

    inject_block="${indent}dm_signal_pf_operation_guardrails:"
    inject_block="${inject_block}"$'\n'"${indent}- \"PF一括削除は登録順だけで判断しない。DELETE APIの400参照保護は安全停止。live DB/config依存を再計測し、削除できたPFから反復削除する。\""
    inject_block="${inject_block}"$'\n'"${indent}- \"restore-allは POST /api/admin/portfolios/restore-all。名前衝突がある時は新PF削除を先行する。PF一覧APIは /api/portfolios/get であり /api/portfolios は404。\""
    inject_block="${inject_block}"$'\n'"${indent}- \"restore-all後はHTTP応答やDB recalculation_statusがstaleでも、/admin/recalculate-status running=false、active数、holding_signal/monthly_returns生成数、API/FEを一次確認して判定する。\""
    inject_block="${inject_block}"$'\n'"${indent}- \"WSL実行ではLinux python3を使う。Windows venv pythonをWSLから起動しない。CSV成果物はLFへ正規化し git diff --check を通す。\""
    inject_block="${inject_block}"$'\n'"${indent}- \"開始前後に active_total、新PFlive数、archive restored/unrestored数、holding_signal数、monthly_returns数、API件数、FE HTTP status を数値で記録する。\""
    inject_block="${inject_block}"$'\n'"${indent}- \"restore-locked実行前にsignal_change_log等の診断履歴をpost-snapshot artifactへ保存する。artifactにはrun_id/source/input provenance、row_count、hashを含め、restore後に同じ値を照合する。\""

    insert_task_block_before_description "$tmp_file" "$inject_block"
    _yaml_field_set_publish_atomic "$tmp_file" "$task_file" || return 1
    log "inject_dm_signal_pf_operation_guardrails: injected"
}

# L877 Level5: 巨大golden-baselineを扱うDM-Signal taskへ、GitHub上限を
# 越える前にmanifest/archive二層契約を事前供給する。
inject_dm_signal_golden_baseline_contract() {
    local task_file="$1"
    [ -f "$task_file" ] || return 0

    local project purpose command_text title haystack tmp_file inject_block indent="  "
    project=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "project" "" 2>/dev/null || true)
    [ "$project" = "dm-signal" ] || return 0
    purpose=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "purpose" "" 2>/dev/null || true)
    command_text=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "command" "" 2>/dev/null || true)
    title=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "title" "" 2>/dev/null || true)
    haystack="$title $purpose $command_text"
    printf '%s\n' "$haystack" | grep -Eqi 'golden[-_ ]?baseline|golden[-_ ]?data' || return 0

    inject_block="${indent}golden_baseline_contract:"
    inject_block="${inject_block}"$'\n'"${indent}- \"100MB超のrow payload本体はgit管理せず、gitignore済みoutputs/analysis/cmd_* archiveへ保存する。\""
    inject_block="${inject_block}"$'\n'"${indent}- \"git管理する小manifestにはcanonical hash、row_count、schema/version、archive相対pathを含める。\""
    inject_block="${inject_block}"$'\n'"${indent}- \"テストでmanifestとarchiveのcanonical hash、row_count、schema/version一致を二値検証する。\""

    tmp_file=$(mktemp "${task_file}.XXXXXX")
    cp "$task_file" "$tmp_file"
    insert_task_block_before_description "$tmp_file" "$inject_block"
    _yaml_field_set_publish_atomic "$tmp_file" "$task_file" || return 1
    log "inject_dm_signal_golden_baseline_contract: L877 Level5 contract injected"
}

# ─── DM-Signal 5PF canary rotation contract ───
# Level5: every DM-Signal verification/performance task receives the same
# reversible one-commit → Live → fixed-five-PF --get → layer-total tracking
# contract.  Scope is structural (project/target_path) plus an explicit
# verification/performance term; prose-only references from infra tasks must
# never opt them into production validation obligations.
inject_dm_signal_canary_rotation_contract() {
    local task_file="$1"
    [ -f "$task_file" ] || return 0
    task_targets_are_documentation_only "$task_file" && {
        log "inject_dm_signal_canary_rotation_contract: documentation-only target, skip"
        return 0
    }

    local project target_path task_type title purpose command_text parent_cmd parent_text scope_text
    project=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "project" "" 2>/dev/null || true)
    target_path=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "target_path" "" 2>/dev/null || true)
    task_type=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "task_type" "" 2>/dev/null || true)
    title=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "title" "" 2>/dev/null || true)
    purpose=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "purpose" "" 2>/dev/null || true)
    command_text=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "command" "" 2>/dev/null || true)
    parent_cmd=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "parent_cmd" "" 2>/dev/null || true)

    # A resolved task may carry only parent_cmd/purpose while the command text
    # remains in the command SSOT.  Read the parent entry without mutating it.
    parent_text=$(python3 - "$SCRIPT_DIR/queue/shogun_to_karo.yaml" "$parent_cmd" <<'PY' 2>/dev/null || true
import sys
import yaml

path, cmd = sys.argv[1:]
if not cmd or not cmd.startswith('cmd_'):
    raise SystemExit(0)
try:
    data = yaml.safe_load(open(path, encoding='utf-8')) or {}
except Exception:
    raise SystemExit(0)
entry = (data.get('commands') or {}).get(cmd, {})
if isinstance(entry, dict):
    for key in ('title', 'purpose', 'command', 'description'):
        value = entry.get(key)
        if value is not None:
            print(value)
PY
)

    # project/target_path define ownership; the terms define this narrower
    # verification/performance lane.  This prevents an unrelated DM-Signal
    # feature task from inheriting canary/full-recalc obligations.
    if ! printf '%s\n%s\n' "$project" "$target_path" | grep -Eqi '(^|[^a-z0-9])dm-signal([^a-z0-9]|$)'; then
        return 0
    fi
    scope_text="${task_type}
${title}
${purpose}
${command_text}
${parent_text}"
    if ! printf '%s\n' "$scope_text" | grep -Eqi '検証|verify|validation|parity|canary|高速化|speed|performance|perf|bottleneck|hot[ -]?path|cache|ledger|計測|cost'; then
        return 0
    fi

    local indent="  " tmp_file inject_block
    tmp_file=$(mktemp "${task_file}.XXXXXX") || return 1
    awk '
        /^  dm_signal_canary_rotation_contract:/ { skip=1; next }
        skip && /^  [a-zA-Z_][a-zA-Z0-9_]*:/ { skip=0 }
        skip && /^[^ ]/ { skip=0 }
        !skip { print }
    ' "$task_file" > "$tmp_file" || { rm -f "$tmp_file"; return 1; }

    inject_block="${indent}dm_signal_canary_rotation_contract:"
    inject_block="${inject_block}"$'\n'"${indent}  scope: \"DM-Signal verification/performance tasks only\""
    inject_block="${inject_block}"$'\n'"${indent}  revision:"
    inject_block="${inject_block}"$'\n'"${indent}    max_commits: 1"
    inject_block="${inject_block}"$'\n'"${indent}    allowed_changes:"
    inject_block="${inject_block}"$'\n'"${indent}      - \"cache reuse\""
    inject_block="${inject_block}"$'\n'"${indent}      - \"duplicate computation removal\""
    inject_block="${inject_block}"$'\n'"${indent}    new_mechanism: false"
    inject_block="${inject_block}"$'\n'"${indent}  deploy_live: required"
    inject_block="${inject_block}"$'\n'"${indent}  canary:"
    inject_block="${inject_block}"$'\n'"${indent}    pf_count: 5"
    inject_block="${inject_block}"$'\n'"${indent}    query: \"--get\""
    inject_block="${inject_block}"$'\n'"${indent}    duration_minutes: 3"
    inject_block="${inject_block}"$'\n'"${indent}    binary_checks:"
    inject_block="${inject_block}"$'\n'"${indent}      error_count: 0"
    inject_block="${inject_block}"$'\n'"${indent}      new_cash_delta: 0"
    inject_block="${inject_block}"$'\n'"${indent}      valid_start: normal"
    inject_block="${inject_block}"$'\n'"${indent}    layer_timings: [L2, L3, L5, other, TOTAL]"
    inject_block="${inject_block}"$'\n'"${indent}  feedback:"
    inject_block="${inject_block}"$'\n'"${indent}    numeric_one_line_report: true"
    inject_block="${inject_block}"$'\n'"${indent}    next_target: \"maximum bottleneck across L2/L3/L5/other/TOTAL\""
    inject_block="${inject_block}"$'\n'"${indent}  full:"
    inject_block="${inject_block}"$'\n'"${indent}    checkpoint: \"T7 final checkpoint only\""
    inject_block="${inject_block}"$'\n'"${indent}    max_runs: 1"

    insert_task_block_before_description "$tmp_file" "$inject_block"
    _yaml_field_set_publish_atomic "$tmp_file" "$task_file" || {
        rm -f "$tmp_file"
        return 1
    }
    rm -f "$tmp_file"
    log "inject_dm_signal_canary_rotation_contract: injected (project=${project:-none}, task_type=${task_type:-none})"
}

# ─── context hints注入（purpose/project/task_typeから必読contextをLevel5化） ───
# R2残件: 重要contextをタスクYAMLに強制注入し、忍者の能動検索依存をなくす。
inject_context_hints() {
    local task_file="$1"
    [ -f "$task_file" ] || return 0

    local project task_type title purpose command_text planned_paths haystack
    project=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "project" "" 2>/dev/null || true)
    task_type=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "task_type" "" 2>/dev/null || true)
    title=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "title" "" 2>/dev/null || true)
    purpose=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "purpose" "" 2>/dev/null || true)
    command_text=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "command" "" 2>/dev/null || true)
    planned_paths=$(python3 - "$task_file" <<'PY' 2>/dev/null || true
import sys, yaml
task = (yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}).get("task", {})
value = task.get("planned_paths", [])
if isinstance(value, str):
    print(value)
elif isinstance(value, list):
    print("\n".join(str(item) for item in value))
PY
)

    haystack="${project}
${task_type}
${title}
${purpose}
${command_text}
${planned_paths}"

    local -a hints=()
    local codd_scope=false
    local is_dm_signal=false
    [ "$project" = "dm-signal" ] && is_dm_signal=true

    if [ "$is_dm_signal" = true ] || grep -Eqi 'robustness|ロバスト|PBO|MaxDD|robustness-verification-catalog|検証カタログ' <<< "$haystack"; then
        hints+=("context/robustness-verification-catalog.md")
    fi
    if [ "$is_dm_signal" = true ] || grep -Eqi 'GS|grid[ -]?search|グリッド|高速化|fullrecalculate|gs-speedup-knowledge' <<< "$haystack"; then
        hints+=("context/gs-speedup-knowledge.md")
    fi
    if [ "$is_dm_signal" = true ] || grep -Eqi 'terminology|用語|dm-signal-terminology|disambiguation|解釈|Flair|ALM|FOF|PF' <<< "$haystack"; then
        hints+=("$(get_project_path 'dm-signal' 2>/dev/null || echo '')/context/dm-signal-terminology.md")
    fi
    if [ "$project" = "infra" ] || [ "$task_type" = "training" ] || grep -Eqi 'training-cycle|修行|L[1-4]|訓練|idle' <<< "$haystack"; then
        hints+=("context/training-cycle.md")
    fi
    # GA-293 / L288: the pre-commit hook correctly requires CoDD source and
    # its freshness index in one commit.  Supply that contract at deployment
    # time whenever the task scope names a CoDD source path, so the first
    # commit does not have to discover it through a Level4 BLOCK.
    if printf '%s\n' "$planned_paths" | grep -Eqi '(^|/)(scripts/codd|skills/codd/|skills/codd-refactor/)'; then
        codd_scope=true
        hints+=("context/codd.md")
    fi

    [ ${#hints[@]} -gt 0 ] || return 0

    local tmp_file inject_block indent="  "
    tmp_file=$(mktemp "${task_file}.XXXXXX")
    awk '
        {
            if (match($0, /[^ ]/)) indent = RSTART - 1; else indent = 999
            if (skip) {
                if (indent <= 2 && $0 ~ /^  [a-zA-Z_][a-zA-Z0-9_]*:/) { skip = 0 }
                else { next }
            }
            if (indent == 2 && $0 ~ /^  context_hints:/) { skip = 1; next }
            print
        }
    ' "$task_file" > "$tmp_file"

    inject_block="${indent}context_hints:"
    local hint
    for hint in "${hints[@]}"; do
        inject_block="${inject_block}"$'\n'"${indent}- \"${hint}\""
    done

    insert_task_block_before_description "$tmp_file" "$inject_block"

    if [ "$codd_scope" = true ]; then
        local codd_scope_json
        codd_scope_json=$(python3 - "$tmp_file" <<'PY'
import json
import sys
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)

task = (yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}).get("task", {})
paths = task.get("planned_paths") or []
if isinstance(paths, str):
    paths = [paths]
paths = list(dict.fromkeys([*[str(path) for path in paths], "context/codd.md"]))
contract = task.get("commit_contract")
if isinstance(contract, dict):
    contract = dict(contract)
    contract_paths = contract.get("planned_paths") or []
    if isinstance(contract_paths, str):
        contract_paths = [contract_paths]
    contract["planned_paths"] = list(
        dict.fromkeys([*[str(path) for path in contract_paths], "context/codd.md"])
    )
print(json.dumps({"planned_paths": paths, "commit_contract": contract}, ensure_ascii=False))
PY
) || return 1
        local codd_planned_json codd_contract_json
        codd_planned_json=$(python3 -c 'import json,sys; print(json.dumps(json.loads(sys.argv[1])["planned_paths"], ensure_ascii=False))' "$codd_scope_json") || return 1
        yaml_field_set "$tmp_file" "task" "planned_paths" "$codd_planned_json" || return 1
        codd_contract_json=$(python3 -c 'import json,sys; value=json.loads(sys.argv[1])["commit_contract"]; print(json.dumps(value, ensure_ascii=False) if isinstance(value, dict) else "")' "$codd_scope_json") || return 1
        if [ -n "$codd_contract_json" ]; then
            yaml_field_set "$tmp_file" "task" "commit_contract" "$codd_contract_json" || return 1
        fi
    fi

    _yaml_field_set_publish_atomic "$tmp_file" "$task_file" || return 1
    log "inject_context_hints: ${#hints[@]} hints injected"
}

# ─── reflux shared-queue commit contract (Level5) ───
# A reflux worker commits one bounded insight record while self-retro may
# update occurrence metadata in the same shared YAML immediately afterwards.
# Give the worker and the report gate the same immutable contract up front:
# the canonical helper, the exact scope, the producer identity, and the only
# fields a post-commit producer mutation may change.  A worker edit to any
# other field remains a real uncommitted change and must BLOCK.
inject_reflux_commit_contract() {
    local task_file="$1"
    [ -f "$task_file" ] || return 0

    local project task_type purpose command_text planned_paths haystack
    project=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "project" "" 2>/dev/null || true)
    task_type=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "task_type" "" 2>/dev/null || true)
    purpose=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "purpose" "" 2>/dev/null || true)
    command_text=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "command" "" 2>/dev/null || true)
    planned_paths=$(python3 - "$task_file" <<'PY' 2>/dev/null || true
import sys, yaml
task = (yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}).get("task", {})
value = task.get("planned_paths", [])
if isinstance(value, str):
    print(value)
elif isinstance(value, list):
    print("\n".join(str(item) for item in value))
PY
)
    haystack="${project}\n${task_type}\n${purpose}\n${command_text}\n${planned_paths}"
    if ! grep -Eqi 'reflux[_ -]?insight|insight.*還流|還流.*insight' <<< "$haystack" \
        || ! grep -qxF 'queue/insights.yaml' <<< "$planned_paths"; then
        return 0
    fi

    local repo_root helper_path
    repo_root=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || printf '%s\n' "$SCRIPT_DIR")
    helper_path=$(realpath "$repo_root/scripts/ninja_scope_commit.sh" 2>/dev/null || printf '%s\n' "$repo_root/scripts/ninja_scope_commit.sh")
    # Generic yaml_field_set treats unknown JSON-valued fields as scalars.
    # Publish this mapping as a real YAML block so the task/report contract
    # cannot silently degrade into a quoted string.
    local tmp_file inject_block
    tmp_file=$(mktemp "${task_file}.XXXXXX") || return 1
    awk '
        {
            if (match($0, /[^ ]/)) indent = RSTART - 1; else indent = 999
            if (skip) {
                if (indent <= 2 && $0 ~ /^  [a-zA-Z_][a-zA-Z0-9_]*:/) { skip = 0 }
                else { next }
            }
            if (indent == 2 && $0 ~ /^  reflux_commit_contract:/) { skip = 1; next }
            print
        }
    ' "$task_file" > "$tmp_file" || return 1
    inject_block=$(cat <<EOF
  reflux_commit_contract:
    helper_path: "${helper_path}"
    repo_root: "${repo_root}"
    scope:
      - "queue/insights.yaml"
    producer:
      field: "source"
      value: "self_retro"
    stable_id_field: "id"
    post_commit_allowed_fields:
      - "occurrence_count"
      - "last_seen"
    uncommitted_worker_policy: "block"
EOF
)
    insert_task_block_before_description "$tmp_file" "$inject_block" || return 1
    _yaml_field_set_publish_atomic "$tmp_file" "$task_file" || return 1
    log "inject_reflux_commit_contract: helper=${helper_path} scope=queue/insights.yaml producer=self_retro"
}

# ─── 本番不変量注入（task YAMLにproduction_invariantsを挿入） ───
# Level5: 忍者が本番ルールを意志依存ゼロで知る。PI違反=本番事故。
inject_production_invariants() {
    local task_file="$1"
    [ -f "$task_file" ] || return 0

    # タスクのproject取得
    local project
    project=$(awk '/^  project:/{print $2; exit}' "$task_file" 2>/dev/null)
    [ -n "$project" ] || return 0

    local pj_yaml="$SCRIPT_DIR/projects/${project}.yaml"
    [ -f "$pj_yaml" ] || return 0

    # PIエントリ抽出(上位5件)
    local pi_lines
    pi_lines=$(awk '
        /production_invariants:/ { found=1; next }
        found && /entries:/ { in_entries=1; next }
        in_entries && /- \{id: PI-/ {
            sub(/.*id: /, ""); sub(/,.*fact: /, ": ");
            sub(/"\}.*/, ""); sub(/"/, "");
            print; count++
            if (count >= 5) exit
        }
        found && /^[a-z]/ && !/entries:/ { exit }
    ' "$pj_yaml" 2>/dev/null)
    [ -n "$pi_lines" ] || return 0

    # 既存のproduction_invariantsを除去してから追加
    local tmp_file inject_block indent="  "
    inject_block="${indent}production_invariants:"
    while IFS= read -r line; do
        inject_block="${inject_block}"$'\n'"${indent}- \"${line}\""
    done <<< "$pi_lines"

    tmp_file=$(mktemp "${task_file}.XXXXXX")
    awk '
        /^  production_invariants:/ { skip=1; next }
        skip && /^  - "/ { next }
        skip && /^  [a-z]/ { skip=0 }
        skip && /^[^ ]/ { skip=0 }
        !skip { print }
    ' "$task_file" > "$tmp_file"

    insert_task_block_before_description "$tmp_file" "$inject_block"

    _yaml_field_set_publish_atomic "$tmp_file" "$task_file" || return 1
    log "inject_production_invariants: project=$project $(echo "$pi_lines" | wc -l) PIs injected"
}

# ─── チェックリスト隣接Step制約自動注入（cmd_2644 Level5化） ───
# AC/command内のchecklist-*.md + Step番号を検出し、
# 前後Stepの制約条件（🛑/前提条件/⚠/🔴）をタスクYAMLへ強制注入。
# cmd_1397事故(再計算禁止ステップ未転写)の構造的再発防止。
# Pythonがtask_fileに直接書き込む（inject_related_lessonsと同パターン）。
inject_checklist_constraints() {
    local task_file="$1"
    [ -f "$task_file" ] || return 0

    local py_output
    py_output=$(mktemp)
    if ! run_python_logged "$py_output" env TASK_FILE_ENV="$task_file" SCRIPT_DIR_ENV="$SCRIPT_DIR" python3 - <<'INJECT_CL_PY'; then
import os, re, sys, tempfile

task_file = os.environ['TASK_FILE_ENV']
script_dir = os.environ['SCRIPT_DIR_ENV']

try:
    import yaml
    with open(task_file, encoding='utf-8') as f:
        data = yaml.safe_load(f)
except Exception:
    sys.exit(0)

task = data.get('task', data) if isinstance(data, dict) else {}

texts = []
ac = task.get('acceptance_criteria', {})
if isinstance(ac, dict):
    texts.append(str(ac.get('description', '')))
elif isinstance(ac, list):
    texts.extend(str(x) for x in ac)
for key in ('command', 'purpose'):
    v = task.get(key)
    if v:
        texts.append(str(v))

full_text = ' '.join(texts)

pattern = re.compile(r'(checklist-[\w-]+\.md)\s+(?:Step\s+)?(\d+)', re.IGNORECASE)
refs = {}
for m in pattern.finditer(full_text):
    fname = m.group(1)
    step = int(m.group(2))
    if fname not in refs:
        refs[fname] = set()
    refs[fname].add(step)

if not refs:
    sys.exit(0)


def find_step_positions(lines):
    positions = {}
    for i, line in enumerate(lines):
        m = re.match(r'^## (?:Step )?(\d+)[.: ]', line)
        if m:
            positions[int(m.group(1))] = i
    return positions


CONSTRAINT_KEYWORDS = ['🛑', '必ずここで止まれ', '前提条件', '⚠', '🔴', '禁止', '入るな', '確認後']


def is_constraint(line):
    return any(kw in line for kw in CONSTRAINT_KEYWORDS)


def clean_markdown(line):
    line = re.sub(r'^\s*>?\s*\**\s*', '', line)
    line = re.sub(r'\**\s*$', '', line)
    line = line.replace('"', "'")
    return line.strip()


def extract_adjacent_constraints(lines, step_positions, step_num):
    constraints = []
    prev = step_num - 1
    if prev in step_positions and step_num in step_positions:
        s, e = step_positions[prev], step_positions[step_num]
        for line in lines[s:e]:
            if is_constraint(line):
                clean = clean_markdown(line)
                if clean and len(clean) > 5:
                    constraints.append(f'[Step{prev}末尾] {clean}')
    nxt = step_num + 1
    if nxt in step_positions:
        s = step_positions[nxt]
        e = step_positions.get(nxt + 1, len(lines))
        e = min(s + 20, e)
        for line in lines[s:e]:
            if is_constraint(line):
                clean = clean_markdown(line)
                if clean and len(clean) > 5:
                    constraints.append(f'[Step{nxt}前提] {clean}')
    return constraints


all_constraints = []
for fname, steps in refs.items():
    cl_path = os.path.join(script_dir, 'context', fname)
    if not os.path.exists(cl_path):
        print(f'[INJECT_CL] WARN: {fname} not found', file=sys.stderr)
        continue
    with open(cl_path, encoding='utf-8') as f:
        lines = f.read().split('\n')
    step_positions = find_step_positions(lines)
    if not step_positions:
        continue
    for step_num in sorted(steps):
        if step_num not in step_positions:
            print(f'[INJECT_CL] WARN: Step {step_num} not found in {fname}', file=sys.stderr)
            continue
        c = extract_adjacent_constraints(lines, step_positions, step_num)
        all_constraints.extend(c)

if not all_constraints:
    sys.exit(0)

with open(task_file, encoding='utf-8') as f:
    raw = f.read()

raw_lines = raw.split('\n')
new_lines = []
skip = False
for line in raw_lines:
    if line.startswith('  checklist_constraints:'):
        skip = True
        continue
    if skip:
        if re.match(r'  - "', line):
            continue
        else:
            skip = False
    if not skip:
        new_lines.append(line)

inject_lines = ['  checklist_constraints:']
for c in all_constraints:
    inject_lines.append(f'  - "{c}"')
inject_text = '\n'.join(inject_lines)

result_text = '\n'.join(new_lines)
if '\n  description:' in result_text:
    result_text = result_text.replace('\n  description:', '\n' + inject_text + '\n  description:', 1)
elif result_text.startswith('  description:'):
    result_text = inject_text + '\n' + result_text
else:
    result_text = result_text.rstrip('\n') + '\n' + inject_text + '\n'

tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
try:
    with os.fdopen(tmp_fd, 'w', encoding='utf-8') as f:
        f.write(result_text)
    os.replace(tmp_path, task_file)
except Exception:
    if os.path.exists(tmp_path):
        os.unlink(tmp_path)
    raise

print(f'[INJECT_CL] Injected {len(all_constraints)} checklist constraints', file=sys.stderr)
INJECT_CL_PY
        log "inject_checklist_constraints: python error (non-fatal)"
    fi
    rm -f "$py_output"
}

# ─── 成長ループ防御階層注入（cmd_2649 Level5化） ───
# gate/hook関連cmdの忍者タスクYAMLにgrowth-loop.md §11を強制注入。
# 忍者がgate BLOCK後に「同じBLOCKが二度と起きない仕組み」を考える材料を提供。
# 事前コンテキスト提供（Level5）: 間違える余地がない環境を作る。
inject_growth_loop_defense() {
    local task_file="$1"
    [ -f "$task_file" ] || return 0

    local py_output
    py_output=$(mktemp)
    if ! run_python_logged "$py_output" env TASK_FILE_ENV="$task_file" SCRIPT_DIR_ENV="$SCRIPT_DIR" python3 - <<'INJECT_GLD_PY'; then
import os, re, sys, tempfile

task_file = os.environ['TASK_FILE_ENV']
script_dir = os.environ['SCRIPT_DIR_ENV']

try:
    import yaml
    with open(task_file, encoding='utf-8') as f:
        data = yaml.safe_load(f)
except Exception:
    sys.exit(0)

task = data.get('task', data) if isinstance(data, dict) else {}

# テキスト収集: purpose + acceptance_criteria + description
texts = []
for key in ('purpose', 'description', 'command'):
    v = task.get(key)
    if v:
        texts.append(str(v))
ac = task.get('acceptance_criteria', {})
if isinstance(ac, dict):
    texts.append(str(ac.get('description', '')))
elif isinstance(ac, list):
    texts.extend(str(x) for x in ac)

full_text = ' '.join(texts)

# FP防止: 外部PJ(dm-signal等)のPythonコードのhook/gateはinfra gate/hookではない
EXTERNAL_PROJECTS = {'dm-signal', 'google-classroom', 'clinic-expense-tracker', 'dividend-tracker'}
task_project = task.get('project', '')
if task_project in EXTERNAL_PROJECTS:
    sys.exit(0)

# gate/hook関連キーワード検出
GATE_KEYWORDS = [
    'gate', 'hook', 'BLOCK', 'growth.loop', 'growth-loop',
    '防御階層', 'Level5', 'gate_fire', 'gate_report', '成長ループ',
    'defense', 'defense_level', 'フロー内',
]
if not any(kw.lower() in full_text.lower() for kw in GATE_KEYWORDS):
    sys.exit(0)

# growth-loop.md §11 を読み込む
growth_loop_path = os.path.join(script_dir, 'context', 'growth-loop.md')
if not os.path.exists(growth_loop_path):
    print('[INJECT_GLD] WARN: growth-loop.md not found', file=sys.stderr)
    sys.exit(0)

with open(growth_loop_path, encoding='utf-8') as f:
    lines = f.readlines()

# §11 セクションを抽出
section_start = None
section_end = None
for i, line in enumerate(lines):
    if re.match(r'^## §11', line):
        section_start = i
    elif section_start is not None and re.match(r'^## ', line):
        section_end = i
        break
if section_start is None:
    print('[INJECT_GLD] WARN: §11 not found in growth-loop.md', file=sys.stderr)
    sys.exit(0)
if section_end is None:
    section_end = len(lines)

section_lines = lines[section_start:section_end]

# キーラインを抽出
key_lines = []
for line in section_lines:
    stripped = line.rstrip()
    # ゲートの成功（太字除去）
    if 'ゲートの成功' in stripped:
        cleaned = re.sub(r'\*\*', '', stripped).strip()
        if cleaned:
            key_lines.append(cleaned)
    # Level行（テーブル行）: | 1 | 名称 | 仕組み | ...
    elif re.match(r'^\| \d ', stripped):
        parts = [p.strip() for p in stripped.split('|') if p.strip()]
        if len(parts) >= 3:
            key_lines.append(f'Level{parts[0]}({parts[1]}): {parts[2]}')
    # BLOCKされたら行
    elif 'BLOCKされたら' in stripped and '環境に埋め込め' in stripped:
        cleaned = re.sub(r'^[-\*\s]+', '', stripped).strip()
        if cleaned:
            key_lines.append(cleaned)
    # Level5を目指せ行
    elif 'Level 5を目指せ' in stripped:
        cleaned = re.sub(r'^[-\*\s]+', '', stripped).strip()
        if cleaned:
            key_lines.append(cleaned)

if not key_lines:
    print('[INJECT_GLD] WARN: no key lines extracted from §11', file=sys.stderr)
    sys.exit(0)

# 既存の growth_loop_defense をYAML node境界で除去する。
# quote/styleに依存した行regexは正規化後のsingle-quote listを孤立させるため禁止。
with open(task_file, encoding='utf-8') as f:
    raw = f.read()

raw_lines = raw.split('\n')
new_lines = raw_lines
try:
    root_node = yaml.compose(raw)
    task_node = root_node
    if isinstance(root_node, yaml.MappingNode):
        for key_node, value_node in root_node.value:
            if key_node.value == 'task':
                task_node = value_node
                break
    if isinstance(task_node, yaml.MappingNode):
        for key_node, value_node in task_node.value:
            if key_node.value == 'growth_loop_defense':
                start = key_node.start_mark.line
                end = value_node.end_mark.line
                new_lines = raw_lines[:start] + raw_lines[end:]
                break
except yaml.YAMLError:
    sys.exit(1)

inject_lines = ['  growth_loop_defense:']
for kl in key_lines:
    kl_safe = kl.replace('"', "'")
    inject_lines.append(f'  - "{kl_safe}"')
inject_text = '\n'.join(inject_lines)

result_text = '\n'.join(new_lines)
if '\n  description:' in result_text:
    result_text = result_text.replace('\n  description:', '\n' + inject_text + '\n  description:', 1)
elif result_text.startswith('  description:'):
    result_text = inject_text + '\n' + result_text
else:
    result_text = result_text.rstrip('\n') + '\n' + inject_text + '\n'

tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
try:
    with os.fdopen(tmp_fd, 'w', encoding='utf-8') as f:
        f.write(result_text)
    os.replace(tmp_path, task_file)
except Exception:
    if os.path.exists(tmp_path):
        os.unlink(tmp_path)
    raise

print(f'[INJECT_GLD] Injected {len(key_lines)} defense levels', file=sys.stderr)
INJECT_GLD_PY
        log "inject_growth_loop_defense: python error (non-fatal)"
    fi
    rm -f "$py_output"
}

# ─── 実験ファースト原則（殿厳命2026-07-20、全task Level5） ───
inject_experiment_first_principle() {
    local task_file="$1"
    [ -f "$task_file" ] || return 0
    PYTHONPATH="$SCRIPT_DIR" TASK_FILE_ENV="$task_file" python3 - <<'INJECT_EFP_PY'
import os
import tempfile
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)
from scripts.lib.yaml_atomic import atomic_yaml_write

task_file = os.environ['TASK_FILE_ENV']
with open(task_file, encoding='utf-8') as f:
    data = yaml.safe_load(f) or {}
task = data.get('task', data)
task['experiment_first_principle'] = [
    '殿の原文: 『LLMは人間ではない。考えることは向いてない。膨大な量の実験を超速で回し続ける総当たりが構造的に有効だ』',
    '適用形: 仮説を頭で絞らず、小さな独立実験へ分けて並列に全て試せ。想像で結論せず、各実験の一次結果を確認してから採否を決めよ。',
]
atomic_yaml_write(task_file, data)
INJECT_EFP_PY
}

inject_readonly_refs() {
    local task_file="$1"
    local parent_cmd command_text readonly_yaml

    parent_cmd=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "parent_cmd" "" 2>/dev/null || true)
    [ -n "$parent_cmd" ] || return 0

    command_text=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "command" "" 2>/dev/null || true)
    if [ -z "$command_text" ] && [ -f "$SCRIPT_DIR/queue/shogun_to_karo.yaml" ]; then
        command_text=$(
            PARENT_CMD_ENV="$parent_cmd" STK_ENV="$SCRIPT_DIR/queue/shogun_to_karo.yaml" python3 - <<'PY' 2>/dev/null || true
import os
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)

parent_cmd = os.environ.get("PARENT_CMD_ENV", "")
stk = os.environ.get("STK_ENV", "")
try:
    with open(stk, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
except Exception:
    data = {}
commands = data.get("commands", data.get("cmds", data))
entry = None
if isinstance(commands, dict):
    entry = commands.get(parent_cmd)
elif isinstance(commands, list):
    entry = next((row for row in commands if isinstance(row, dict) and str(row.get("id", "")) == parent_cmd), None)
if isinstance(entry, dict):
    value = entry.get("command", "")
    if isinstance(value, (list, tuple)):
        value = "\n".join(str(v) for v in value)
    print(str(value or ""))
PY
        )
    fi
    [ -n "$command_text" ] || return 0

    if ! readonly_yaml=$(
        COMMAND_TEXT_ENV="$command_text" READONLY_ROOT_ENV="$SCRIPT_DIR" python3 - <<'PY'
import os
import re
import sys
from pathlib import Path

command = os.environ.get("COMMAND_TEXT_ENV", "")
root = Path(os.environ["READONLY_ROOT_ENV"])
pattern = re.compile(
    r"(?<![A-Za-z0-9_./-])"
    r"((?:/mnt/[A-Za-z0-9_.-]+/|(?:[A-Za-z0-9_.-]+/)*)[A-Za-z0-9_.-]+"
    r"\.(?:sh|py|md|yaml|yml|json|toml|js|ts|tsx|jsx|css|html|sql|csv|log))"
    r"(?![A-Za-z0-9_.-])"
)
read_markers = (
    "必読", "読む", "読んで", "読み", "確認", "参照", "調査", "精査", "review", "read", "inspect", "refer",
    "実行", "実行のみ", "変更対象外", "走らせ", "検証", "整理", "抽出", "算出", "run", "execute",
)
write_markers = (
    "修正", "更新", "変更", "編集", "実装", "追加", "削除", "作成", "反映",
    "modify", "update", "edit", "add", "remove", "delete", "create", "write", "implement",
)

def marker_pos(text, markers):
    positions = [text.find(marker) for marker in markers if text.find(marker) >= 0]
    return min(positions) if positions else -1

def write_marker_pos(text):
    positions = []
    for marker in write_markers:
        start = 0
        while True:
            pos = text.find(marker, start)
            if pos < 0:
                break
            # 「更新トリガー/頻度」の更新は調査対象を表す名詞であり、
            # 当該ファイルを更新する動詞ではない。これをwrite扱いすると
            # 設計・偵察cmdのreadonly_ref注入が漏れ、完了gateが偽BLOCKする。
            suffix = text[pos + len(marker):]
            if marker == "更新" and re.match(r"^(?:トリガー|頻度|対象|履歴|時刻|経路|条件|有無|内容|周期|契機|方式|箇所)", suffix):
                start = pos + len(marker)
                continue
            positions.append(pos)
            break
    return min(positions) if positions else -1

matches = list(pattern.finditer(command))
seen = set()
readonly = []
for idx, match in enumerate(matches):
    ref = match.group(1).strip().strip("`'\".,:;()[]{}")
    if not ref or ref in seen:
        continue
    sentence_end_candidates = [
        pos for pos in (
            command.find("\n", match.end()),
            command.find("。", match.end()),
            command.find("；", match.end()),
            command.find(";", match.end()),
        )
        if pos >= 0
    ]
    sentence_start_candidates = [
        pos for pos in (
            command.rfind("\n", 0, match.start()),
            command.rfind("。", 0, match.start()),
            command.rfind("；", 0, match.start()),
            command.rfind(";", 0, match.start()),
        )
        if pos >= 0
    ]
    sentence_start = max(sentence_start_candidates) + 1 if sentence_start_candidates else 0
    sentence_end = min(sentence_end_candidates) if sentence_end_candidates else len(command)
    next_file_start = matches[idx + 1].start() if idx + 1 < len(matches) else sentence_end
    local = command[match.end():next_file_start]
    sentence = command[sentence_start:sentence_end]
    sentence_tail = command[match.end():sentence_end]
    read_pos = marker_pos(local, read_markers)
    if read_pos < 0:
        read_pos = marker_pos(sentence, read_markers)
    write_pos = write_marker_pos(sentence_tail)
    next_ref_before_write = idx + 1 < len(matches) and matches[idx + 1].start() < sentence_end and (
        write_pos < 0 or matches[idx + 1].start() - match.end() < write_pos
    )
    is_readonly = read_pos >= 0 and (write_pos < 0 or next_ref_before_write or read_pos < write_pos)
    if is_readonly:
        seen.add(ref)
        readonly.append(ref)

canonical = []
missing = []
for ref in readonly:
    raw = Path(ref)
    candidates = [raw] if raw.is_absolute() else [root / raw]
    if not raw.is_absolute() and len(raw.parts) == 1:
        candidates.append(root / "scripts" / raw)
    resolved = next((path for path in candidates if path.exists()), None)
    if resolved is None:
        missing.append(ref)
        continue
    try:
        canonical.append(str(resolved.relative_to(root)).replace("\\", "/"))
    except ValueError:
        canonical.append(str(resolved))

if missing:
    print(
        "BLOCK: readonly_ref path does not exist or lacks canonical prefix: "
        + ",".join(missing),
        file=sys.stderr,
    )
    raise SystemExit(2)

for ref in canonical:
    escaped = ref.replace("'", "''")
    print(f"  - path: '{escaped}'")
    print("    reason: command欄の必読/参照専用ファイル")
PY
    ); then
        log "[INJECT_READONLY_REF] BLOCK: unresolved readonly command path"
        return 1
    fi

    [ -n "$readonly_yaml" ] || return 0

    TASK_FILE_ENV="$task_file" READONLY_YAML_ENV="$readonly_yaml" python3 - <<'PY'
import os
import tempfile
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)

task_file = os.environ["TASK_FILE_ENV"]
fragment = os.environ["READONLY_YAML_ENV"].rstrip("\n")

with open(task_file, encoding="utf-8") as f:
    raw = f.read()

yaml.safe_load("readonly_ref:\n" + fragment + "\n")

lines = raw.splitlines()
out = []
skip = False
for line in lines:
    stripped = line.lstrip(" ")
    indent = len(line) - len(stripped)
    if skip:
        # task直下のsequence itemは ``  - path: ...`` でindent=2。
        # indent>2だけを飛ばすと旧itemが残り、再注入のたび重複する。
        if stripped == "" or indent > 2 or (indent == 2 and stripped.startswith("-")):
            continue
        skip = False
    if indent == 2 and stripped.startswith("readonly_ref:"):
        skip = True
        continue
    out.append(line)

insert_at = len(out)
for idx in range(len(out) - 1, -1, -1):
    if out[idx].startswith("task:"):
        insert_at = idx + 1
        break
    if out[idx].startswith("  ") and not out[idx].startswith("    "):
        insert_at = idx + 1

out[insert_at:insert_at] = ["  readonly_ref:"] + fragment.splitlines()
result = "\n".join(out).rstrip("\n") + "\n"

fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix=".tmp")
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(result)
    yaml.safe_load(result)
    os.replace(tmp_path, task_file)
finally:
    if os.path.exists(tmp_path):
        os.unlink(tmp_path)
PY
    log "[INJECT_READONLY_REF] injected command readonly refs"
}

# One deploy generation owns one postcondition marker.  The old fixed
# queue/tasks/.postcond_lesson_inject path let parallel --yaml deployments
# overwrite and consume each other's task/project/lesson identity.
deploy_task_postcondition_prepare() {
    local task_file="$1"
    local task_dir task_key ninja_key cmd_key generation

    if [ "${DEPLOY_TASK_POSTCOND_TASK_FILE:-}" = "$task_file" ] \
        && [ -n "${DEPLOY_TASK_POSTCOND_FILE:-}" ]; then
        return 0
    fi

    deploy_task_postcondition_cleanup
    task_dir="${task_file%/*}"
    [ "$task_dir" != "$task_file" ] || task_dir="."
    task_key="${task_file##*/}"
    task_key="${task_key%.yaml}"
    ninja_key="${NINJA_NAME:-$task_key}"
    cmd_key="${CMD_ID:-unknown}"
    generation="${DEPLOY_TASK_STARTED_US:-${EPOCHREALTIME/./}}_${BASHPID}"
    task_key="${task_key//[^a-zA-Z0-9_.-]/_}"
    ninja_key="${ninja_key//[^a-zA-Z0-9_.-]/_}"
    cmd_key="${cmd_key//[^a-zA-Z0-9_.-]/_}"
    generation="${generation//[^a-zA-Z0-9_.-]/_}"
    # Keep the filename below common 255-byte limits even for descriptive cmd IDs.
    cmd_key="${cmd_key:0:80}"

    DEPLOY_TASK_POSTCOND_TASK_FILE="$task_file"
    DEPLOY_TASK_POSTCOND_FILE="${task_dir}/.postcond_lesson_inject.${task_key}.${ninja_key}.${cmd_key}.${generation}"
    export DEPLOY_TASK_POSTCOND_TASK_FILE DEPLOY_TASK_POSTCOND_FILE
}

deploy_task_postcondition_cleanup() {
    if [ -n "${DEPLOY_TASK_POSTCOND_FILE:-}" ]; then
        rm -f -- "$DEPLOY_TASK_POSTCOND_FILE"
    fi
    DEPLOY_TASK_POSTCOND_FILE=""
    DEPLOY_TASK_POSTCOND_TASK_FILE=""
    export DEPLOY_TASK_POSTCOND_FILE DEPLOY_TASK_POSTCOND_TASK_FILE
}

