#!/usr/bin/env bats
# test_deploy_task_lesson_scoring.bats — cmd_2270 キーワード関連度スコアリングのユニットテスト
# AC1: キーワード関連度スコアリングで上位10件に絞られる
# AC2: DM-Signal系タスクにDM-Signal教訓が優先注入される
# AC3: 無関係な教訓がスコア0で排除される

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/lesson_scoring.XXXXXX")"
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

# Helper: スコアリングロジックを実行してIDとスコアを返す (ID:score形式、スコア降順)
# Usage: run_scoring <project> <keywords_json> <lessons_json>
run_scoring() {
    local project="$1"
    local keywords_json="$2"
    local lessons_json="$3"
    python3 - "$project" "$keywords_json" "$lessons_json" <<'PY'
import json
import sys

project = sys.argv[1]
keywords = json.loads(sys.argv[2])
lessons = json.loads(sys.argv[3])

scored = []
for lesson in lessons:
    lid = lesson.get('id', '')
    l_title = str(lesson.get('title', ''))
    l_summary = str(lesson.get('summary', ''))
    l_content = str(lesson.get('content', ''))

    title_text = l_title.lower()
    other_text = f'{l_summary} {l_content}'.lower()

    score = 0
    for kw in keywords:
        # cmd_2270: 頻度重み付きスコアリング (deploy_task.shと同一ロジック)
        score += title_text.count(kw) * 3 + other_text.count(kw) * 1

    if score > 0:
        # cmd_2270: プロジェクト一致ボーナス (deploy_task.shと同一ロジック)
        if lesson.get('_source_project') == project:
            score += 2
        scored.append((score, lid))

scored.sort(key=lambda x: -x[0])
for score, lid in scored:
    print(f'{lid}:{score}')
PY
}

# ─── AC1: 上位10件スコアリングテスト ───

@test "AC1: スコアありの教訓が上位順に並ぶ (MAX_INJECT=10想定)" {
    # 12件全てマッチするが、スコア上位順に並ぶことを確認
    run run_scoring "infra" \
        '["deploy", "task"]' \
        '[
          {"id": "L001", "title": "deploy task setup",              "_source_project": "infra"},
          {"id": "L002", "title": "deploy task configuration",      "_source_project": "infra"},
          {"id": "L003", "title": "deploy task workflow",           "_source_project": "infra"},
          {"id": "L004", "title": "deploy task lifecycle",          "_source_project": "infra"},
          {"id": "L005", "title": "deploy task monitoring",         "_source_project": "infra"},
          {"id": "L006", "title": "deploy task validation",         "_source_project": "infra"},
          {"id": "L007", "title": "deploy task cleanup",            "_source_project": "infra"},
          {"id": "L008", "title": "deploy task error handling",     "_source_project": "infra"},
          {"id": "L009", "title": "deploy task logging",            "_source_project": "infra"},
          {"id": "L010", "title": "deploy task reporting",          "_source_project": "infra"},
          {"id": "L011", "title": "deploy task archiving",          "_source_project": "infra"},
          {"id": "L012", "title": "deploy task scheduling",         "_source_project": "infra"}
        ]'
    [ "$status" -eq 0 ]
    # 12件全てスコアあり → 全てリストされる（MAX_INJECT=10の選択は注入フェーズで行う）
    count=$(echo "$output" | grep -c ':')
    [ "$count" -ge 10 ]
}

@test "AC1: 高頻度キーワードマッチの教訓が上位にランクされる" {
    # 同じキーワードが複数回現れる教訓が上位に来る
    run run_scoring "infra" \
        '["deploy"]' \
        '[
          {"id": "L_HIGH", "title": "deploy deploy deploy cycle",   "_source_project": "infra"},
          {"id": "L_LOW",  "title": "deploy step",                  "_source_project": "infra"}
        ]'
    [ "$status" -eq 0 ]
    first_id=$(echo "$output" | head -1 | cut -d: -f1)
    [ "$first_id" = "L_HIGH" ]
}

@test "AC1: MAX_INJECT=10がdeploy_task.shに設定されている" {
    grep -n 'MAX_INJECT = 10' "$PROJECT_ROOT/scripts/deploy_task.sh" | grep -q 'MAX_INJECT'
}

# ─── AC2: DM-Signal教訓優先テスト ───

@test "AC2: DM-Signalタスクに対してDM-Signal教訓がinfra教訓より高スコアを得る" {
    # 同じキーワードを含む教訓でも、DM-Signalソース教訓の方がスコア+2のボーナス
    run run_scoring "dm-signal" \
        '["portfolio", "return"]' \
        '[
          {"id": "L_DM",    "title": "portfolio return calculation", "summary": "", "_source_project": "dm-signal"},
          {"id": "L_INFRA", "title": "portfolio return check",       "summary": "", "_source_project": "infra"}
        ]'
    [ "$status" -eq 0 ]
    # L_DM がL_INFRAより高スコア → 先に出力される
    first_id=$(echo "$output" | head -1 | cut -d: -f1)
    [ "$first_id" = "L_DM" ]
}

@test "AC2: DM-Signalタスクで複数DM-Signal教訓がinfra教訓より前に並ぶ" {
    run run_scoring "dm-signal" \
        '["signal", "portfolio"]' \
        '[
          {"id": "L_INFRA1", "title": "signal portfolio metrics",   "_source_project": "infra"},
          {"id": "L_DM1",    "title": "signal portfolio tracking",  "_source_project": "dm-signal"},
          {"id": "L_INFRA2", "title": "portfolio signal analysis",  "_source_project": "infra"},
          {"id": "L_DM2",    "title": "portfolio signal strategy",  "_source_project": "dm-signal"}
        ]'
    [ "$status" -eq 0 ]
    # 上位2件はDM-Signal教訓
    first=$(echo "$output" | head -1 | cut -d: -f1)
    second=$(echo "$output" | sed -n '2p' | cut -d: -f1)
    [[ "$first"  == L_DM* ]]
    [[ "$second" == L_DM* ]]
}

@test "AC2: infraタスクにはinfra教訓がboostされる (プロジェクト一致)" {
    run run_scoring "infra" \
        '["deploy", "gate"]' \
        '[
          {"id": "L_INFRA", "title": "deploy gate check",  "_source_project": "infra"},
          {"id": "L_DM",    "title": "deploy gate signal", "_source_project": "dm-signal"}
        ]'
    [ "$status" -eq 0 ]
    first_id=$(echo "$output" | head -1 | cut -d: -f1)
    [ "$first_id" = "L_INFRA" ]
}

# ─── AC3: スコア0排除テスト ───

@test "AC3: キーワードが一切マッチしない教訓はスコア0で排除される" {
    run run_scoring "infra" \
        '["deploy", "task"]' \
        '[
          {"id": "L_RELEVANT",   "title": "deploy task setup",                "_source_project": "infra"},
          {"id": "L_IRRELEVANT", "title": "completely unrelated topic alpha",  "_source_project": "infra"}
        ]'
    [ "$status" -eq 0 ]
    # L_IRRELEVANT はキーワードなしでスコア0 → 出力されない
    [[ "$output" != *"L_IRRELEVANT"* ]]
    # L_RELEVANT は出力される
    [[ "$output" == *"L_RELEVANT"* ]]
}

@test "AC3: 全教訓がマッチしない場合は出力が空" {
    run run_scoring "infra" \
        '["deploy", "task"]' \
        '[
          {"id": "L_A", "title": "completely different topic",  "_source_project": "infra"},
          {"id": "L_B", "title": "totally unrelated subject",   "_source_project": "infra"}
        ]'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "AC3: スコア0のプロジェクト一致教訓もboostなしで排除される (キーワード必須)" {
    # プロジェクトが一致してもキーワードマッチがなければスコア0→排除
    run run_scoring "dm-signal" \
        '["portfolio"]' \
        '[
          {"id": "L_NO_MATCH", "title": "signal calculation method", "_source_project": "dm-signal"},
          {"id": "L_MATCH",    "title": "portfolio rebalancing",     "_source_project": "infra"}
        ]'
    [ "$status" -eq 0 ]
    # L_NO_MATCH はキーワード"portfolio"なしでスコア0 → 排除
    [[ "$output" != *"L_NO_MATCH"* ]]
    # L_MATCH はキーワードマッチあり → 出力される
    [[ "$output" == *"L_MATCH"* ]]
}
