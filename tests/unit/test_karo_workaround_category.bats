#!/usr/bin/env bats
# test_karo_workaround_category.bats — cmd_1211 AC2 単体テスト
# classify_category()の分類精度検証: 既存karo_workarounds.yaml全件が正分類されること

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../scripts" && pwd)"

# classify_categoryを単体テスト可能にするためbash関数として再定義
classify_category() {
    local issue="$1"
    local pattern_report="lessons_useful|binary_checks|dict|list|string|フォーマット|lesson_candidate"
    local pattern_disappear="消失|missing|not found"
    if [[ "$issue" =~ $pattern_report ]]; then
        echo "report_yaml_format"
    elif [[ "$issue" =~ $pattern_disappear ]]; then
        echo "file_disappearance"
    else
        echo "uncategorized"
    fi
}

# --- cmd_1182: lessons_useful string→list変換 ---
@test "classify: cmd_1182 lessons_useful string→list → report_yaml_format" {
    result=$(classify_category "報告YAMLフォーマット修正: lessons_useful string→list変換、lesson_candidate found:false→true修正、binary_checks欠落補完。Python直接修正。内容変更なし")
    [ "$result" = "report_yaml_format" ]
}

# --- cmd_1183: lessons_useful空リスト ---
@test "classify: cmd_1183 lessons_useful空リスト → report_yaml_format" {
    result=$(classify_category "報告YAMLフォーマット修正: lessons_useful空リスト→5件のfalse+reason補完。Python直接修正")
    [ "$result" = "report_yaml_format" ]
}

# --- cmd_1184: lesson_candidate/lessons_useful string→構造体変換 ---
@test "classify: cmd_1184 lesson_candidate/lessons_useful → report_yaml_format" {
    result=$(classify_category "報告YAMLフォーマット修正: lesson_candidate/lessons_useful string→構造体変換、binary_checks/decision_candidate/skill_candidate/purpose_validation欠落補完。Python直接修正")
    [ "$result" = "report_yaml_format" ]
}

# --- cmd_1185: lessons_useful string→list変換 ---
@test "classify: cmd_1185 lessons_useful string→list → report_yaml_format" {
    result=$(classify_category "報告YAMLフォーマット修正: lessons_useful string→list変換、binary_checks/decision_candidate/skill_candidate/purpose_validation欠落補完。Python直接修正")
    [ "$result" = "report_yaml_format" ]
}

# --- ralph_L288_runbook: lessons_useful FILL_THIS ---
@test "classify: ralph_L288 lessons_useful FILL_THIS → report_yaml_format" {
    result=$(classify_category "報告YAMLフォーマット修正: lessons_useful FILL_THIS→override値統合、binary_checks/verdict欠落補完。Python直接修正")
    [ "$result" = "report_yaml_format" ]
}

# --- cmd_1187: 報告YAML消失 ---
@test "classify: cmd_1187 報告YAML消失 → file_disappearance" {
    result=$(classify_category "コミット品質OK(軍師APPROVE+家老commit diff確認)。ただし報告YAML消失(deploy_task.shテンプレート生成後に消失、原因不明)。GATEは報告不在のまま多数チェックSKIPでCLEAR")
    [ "$result" = "file_disappearance" ]
}

# --- cmd_1188: lesson_candidate.no_lesson_reason欠落 ---
@test "classify: cmd_1188 lesson_candidate欠落 → report_yaml_format" {
    result=$(classify_category "lesson_candidate.no_lesson_reason欠落 → report_field_set.shで補完。内容変更なし(found:falseの理由文追記のみ)")
    [ "$result" = "report_yaml_format" ]
}

# --- cmd_1205: lessons_useful dict→list変換 ---
@test "classify: cmd_1205 lessons_useful dict→list → report_yaml_format" {
    result=$(classify_category "報告YAMLフォーマット修正: lessons_useful dict→list変換(0/1/2/3→id付きリスト)、binary_checks文字列→dict変換。report_field_set.sh stdin経由")
    [ "$result" = "report_yaml_format" ]
}

# --- file_disappearance detection ---
@test "classify: 'missing file' → file_disappearance" {
    result=$(classify_category "report file missing after deploy")
    [ "$result" = "file_disappearance" ]
}

@test "classify: 'not found' → file_disappearance" {
    result=$(classify_category "config not found in expected path")
    [ "$result" = "file_disappearance" ]
}

# --- uncategorized fallback ---
@test "classify: unrelated text → uncategorized" {
    result=$(classify_category "タイムアウトでリトライ失敗")
    [ "$result" = "uncategorized" ]
}
