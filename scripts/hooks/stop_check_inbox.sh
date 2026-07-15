#!/usr/bin/env bash
# semantic-links: [[Hook自動化フレームワーク]], [[inbox処理規律]], [[編成管理]]
# @source: cmd_451 (inbox未読チェックstop防止hook)
set -euo pipefail

SOURCE_PATH="${BASH_SOURCE[0]}"
case "$SOURCE_PATH" in
  */scripts/hooks/*) SCRIPT_DIR="${SOURCE_PATH%/scripts/hooks/*}" ;;
  scripts/hooks/*) SCRIPT_DIR="." ;;
  *) SCRIPT_DIR="$(cd "${SOURCE_PATH%/*}/../.." && pwd)" ;;
esac
readonly COMPLETE_PATTERN='任務完了|完了でござる|報告YAML.*更新|task completed|タスク完了'
readonly ERROR_PATTERN='エラー.*中断|失敗.*中断|error.*abort|failed.*stop'
readonly SUMMARY_LIMIT=5
readonly SUMMARY_SNIPPET_LEN=80
readonly SHOGUN_BRAINWASH_AUDIT='洗脳8パターン自問: #1早期終了 #2検証スキップ #3他者依存 #4緩い設計 #5先送り #6出力=仕事 #7簡潔本能 #8完了急ぎ'

has_successful_three_layer_preflight() {
  local evidence_dir="${THREE_LAYER_PREACTION_EVIDENCE_DIR:-$SCRIPT_DIR/logs/preaction_memory}"
  local evidence
  shopt -s nullglob
  for evidence in "$evidence_dir"/evidence_shogun_*.json; do
    if python3 - "$evidence" <<'PY' >/dev/null 2>&1
import json, sys
try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    raise SystemExit(1)
raise SystemExit(0 if data.get("status") == "success" and all(str(data.get(k)) == "0" for k in ("memory_db", "semantic", "obsidian")) else 1)
PY
    then
      shopt -u nullglob
      return 0
    fi
  done
  shopt -u nullglob
  return 1
}

is_routine_shogun_response() {
  grep -qiE '配備(開始|完了)|初回配備|GATE (CLEAR|BLOCK)|完了(しました|報告)|inbox(未読|空)|新着を待つ|レビュー依頼待ち' <<<"$1"
}

unresolved_startup_defer_count() {
  local history_file="$1"
  [[ -f "$history_file" ]] || {
    printf '0\n'
    return 0
  }

  awk '
function flush_run() {
  if (current_run != "") {
    run_count++
    run_keys[run_count] = current_keys
  }
}
function add_defer(key) {
  sub(/^先送り判断:[[:space:]]*/, "", key)
  sub(/[[:space:]]が[0-9]+セッション連続$/, "", key)
  if (key == "") return
  if (current_keys == "") current_keys = key
  else current_keys = current_keys "\034" key
}
{
  split($0, parts, "\t")
  if (length(parts) < 2) next
  run_id = parts[1]
  key = substr($0, length(parts[1]) + 2)
  if (current_run == "") current_run = run_id
  if (run_id != current_run) {
    flush_run()
    current_run = run_id
    current_keys = ""
  }
  if (key == "__OK__") {
    current_keys = ""
    next
  }
  if (key ~ /^先送り判断:/) add_defer(key)
}
END {
  flush_run()
  if (run_count == 0 || run_keys[run_count] == "") {
    print 0
    exit
  }
  split(run_keys[run_count], keys, "\034")
  for (j in keys) {
    key = keys[j]
    if (key != "" && !seen[key]) {
      seen[key] = 1
      count++
    }
  }
  print count + 0
}
' "$history_file" 2>/dev/null || printf '0\n'
}

IFS='' read -r -d '' payload || true
if [[ -z "$payload" ]]; then
  exit 0
fi

# cmd_2076: jq -e . (validation) → bash文字列マッチに変更 (~5ms削減)
# 初回改善。前回アプローチなし。
if [[ "$payload" != '{'* ]]; then
  exit 0
fi

STATE_DIR="${SHOGUN_STATE_DIR:-/tmp}"

agent_id="${TMUX_AGENT_ID:-}"
if [[ -z "$agent_id" ]] && command -v tmux >/dev/null 2>&1; then
  agent_cache=""
  if [[ -n "${TMUX:-}${TMUX_PANE:-}" ]]; then
    cache_key="${TMUX:-no_tmux}_${TMUX_PANE:-no_pane}"
    cache_key="${cache_key//[^A-Za-z0-9_.-]/_}"
    agent_cache="$STATE_DIR/shogun_agent_id_${cache_key}"
    if [[ -s "$agent_cache" ]]; then
      IFS= read -r agent_id < "$agent_cache" || agent_id=""
    fi
  fi

  if [[ -z "$agent_id" ]]; then
    if [[ -n "${TMUX_PANE:-}" ]]; then
      agent_id="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
    elif [[ -n "${TMUX:-}" ]]; then
      agent_id="$(tmux display-message -p '#{@agent_id}' 2>/dev/null || true)"
    fi
    if [[ -n "$agent_id" && -n "$agent_cache" ]]; then
      [[ -d "$STATE_DIR" ]] || mkdir -p "$STATE_DIR"
      printf '%s\n' "$agent_id" > "$agent_cache" 2>/dev/null || true
    fi
  fi
fi

if [[ -z "$agent_id" ]]; then
  exit 0
fi

[[ -d "$STATE_DIR" ]] || mkdir -p "$STATE_DIR"
idle_flag="${STATE_DIR}/shogun_idle_${agent_id}"
# cmd_2076: jq -r '.stop_hook_active...' → bash文字列マッチに変更 (~5ms削減)
stop_hook_active=false
if [[ "$payload" == *'"stop_hook_active":true'* || "$payload" == *'"stop_hook_active": true'* ]]; then
  stop_hook_active=true
fi
if [[ "$stop_hook_active" == "true" ]]; then
  : > "$idle_flag"
  exit 0
fi

detect_shogun_brainwash_pattern() {
  local message="$1"
  local pattern_id=""
  local pattern_name=""

  if [[ "$message" =~ (これで十分|十分です|十分と判断|これでOK|で良い|問題なし) ]]; then
    pattern_id="#1"
    pattern_name="早期終了"
  elif [[ "$message" =~ (確認済み|妥当|検証不要|推論で十分|他者.*確認|レビュー済み.*だから) ]]; then
    pattern_id="#2"
    pattern_name="検証スキップ"
  elif [[ "$message" =~ (続けてください|指示を待|待機します|判断を委ね|確認してください) ]]; then
    pattern_id="#3"
    pattern_name="他者依存"
  elif [[ "$message" =~ (口約束|注意書き|手順に書く|ドキュメントで防ぐ|運用でカバー) ]]; then
    pattern_id="#4"
    pattern_name="緩い設計"
  elif [[ "$message" =~ (低優先|後で|次セッション|非致命的|見送り|段階的に|後回し|次回) ]]; then
    pattern_id="#5"
    pattern_name="先送り"
  elif [[ "$message" =~ (起票したので完了|記録したので完了|投稿したので完了|まとめたので完了|報告したので完了) ]]; then
    pattern_id="#6"
    pattern_name="出力=仕事"
  elif [[ "$message" =~ ^[[:space:]]*(はっ|承知|仰る通り|了解|はい)[[:space:][:punct:]]*$ ]]; then
    pattern_id="#7"
    pattern_name="簡潔本能"
  elif [[ "$message" =~ (収束|完了急ぎ|穴なし|これで完了|完結|GATE CLEAR.*安心) ]]; then
    pattern_id="#8"
    pattern_name="完了急ぎ"
  fi

  if [[ -n "$pattern_id" ]]; then
    printf '%s %s\n' "$pattern_id" "$pattern_name"
  fi
}

# cmd_3251 AC2: F009 殿への操作依頼パターン検出
# 洗脳#3(他者依存)の具体的防御。殿にCLI操作・手動作業を依頼するパターンをBLOCK
# 偽陽性防止: パターンは殿/lordコンテキストに限定(軍師指摘反映)
# cmd_3252 AC1: 過去形引用パターン除外（偽陽性防止）
detect_f009_lord_delegation() {
  local message="$1"
  local clause normalized

  # F009は「誰に」「何の操作を」「今依頼しているか」が同じ文節に揃う時だけ発火する。
  # 完了報告・引用・第三者への依頼・F009自身の説明を、単語の共起だけで拾わない。
  normalized="${message//$'\n'/。}"
  normalized="${normalized//！/。}"
  normalized="${normalized//？/。}"
  normalized="${normalized//!/。}"
  normalized="${normalized//\?/。}"
  normalized="${normalized//。/$'\n'}"
  normalized="${normalized//；/$'\n'}"
  normalized="${normalized//;/$'\n'}"
  while IFS= read -r clause; do
    [[ -n "$clause" ]] || continue

    # 過去の実施・依頼済み報告、引用、禁止規則や検出理由の説明は依頼ではない。
    if [[ "$clause" =~ (依頼済み|お願い済み|してもらった|してくれた|してくださった|していただいた|実行済み|操作済み|完了報告|過去報告|引用|BLOCK理由|発火理由|依頼するな|依頼しない|求めるな) ]]; then
      continue
    fi

    # 操作語と依頼態の両方を必須にする。「殿05:02指示」「次の一手として推薦」は除外。
    [[ "$clause" =~ (手動|実行|操作|貼り付け|入力|コピー|commit|push|kill|respawn|CLI) ]] || continue
    [[ "$clause" =~ (ください|いただけ|頂け|いただきたい|頂きたい|してほしい|お願いします|お願いしたい|頼む|してくれ) ]] || continue

    # 家老・軍師・忍者への明示依頼は指揮系統内でありF009対象外。
    if [[ "$clause" =~ (家老|軍師|忍者|karo|gunshi|hayate|kagemaru|hanzo|saizo|kotaro|tobisaru)(に|へ|、).{0,40}(手動|実行|操作|貼り付け|入力|コピー|commit|push|kill|respawn|CLI) ]] \
      && [[ ! "$clause" =~ 殿(に|へ|、).{0,40}(手動|実行|操作|貼り付け|入力|コピー|commit|push|kill|respawn|CLI) ]]; then
      continue
    fi

    # 将軍の最終応答は殿宛なので、対象省略の直接命令も押し返しとして扱う。
    return 0
  done <<< "$normalized"
  return 1
}

# cmd_3420: 数量表現検出 — 殿への回答でN体/N件等が含まれる場合に全件照合を強制
# 洗脳#1(部分データで全体断定)と#8(部分完了報告)のL5化
# AC1: 数量表現含む回答にWARN注入
# AC2: 部分データ→全体断定パターン検出(より重大)
detect_quantity_in_lord_response() {
  local message="$1"
  # AC2: 部分→全体断定パターン(優先チェック)
  # 「X体のうちY体」「X件中Y件」等、部分サンプルで全体を断定する構造を検出
  if echo "$message" | grep -qE '[0-9]+[体件個][[:space:]]*のうち[[:space:]]*[0-9]+|[0-9]+[体件個][[:space:]]*中[[:space:]]*[0-9]+[体件個]'; then
    printf 'WARN: 部分データから全体断定パターン検出(洗脳#1)。「X体のうちY体確認」はX体全体の確認ではない。全数を一次データで確認してから結論せよ。\n' >&2
    return 0
  fi
  # AC1: 数量表現検出(N体/N件/N個/N名等)
  if echo "$message" | grep -qE '[0-9]+[体件個種名枚冊台本通]'; then
    printf 'WARN: 数量表現(N体/N件等)検出(洗脳#1/#8防御)。全件照合が完了しているか？部分データで断定するな。一次データとの件数照合を添えよ。\n' >&2
  fi
}

detect_numeric_tool_memory_gap() {
  local hook_payload="$1"
  python3 - "$hook_payload" <<'PY' 2>/dev/null || true
import json
import os
import re
import sys

payload_raw = sys.argv[1]
try:
    payload = json.loads(payload_raw)
except Exception:
    payload = {}

number_unit_re = re.compile(
    r"(?:\d[\d,]*(?:\.\d+)?|\d+(?:\.\d+)?)\s*"
    r"(?:件|体|個|名|枚|冊|台|本|通|種|パターン|%|％|円|万円|億|兆|倍|秒|分|時間|日|ヶ月|年)"
)
memory_re = re.compile(r"(?:^|[/\s])(?:memory_db_query|semantic_search)\.sh\b")


def strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for item in value.values():
            yield from strings(item)
    elif isinstance(value, list):
        for item in value:
            yield from strings(item)


def dicts(value):
    if isinstance(value, dict):
        yield value
        for item in value.values():
            yield from dicts(item)
    elif isinstance(value, list):
        for item in value:
            yield from dicts(item)


def tool_name(obj):
    return str(obj.get("tool_name") or obj.get("toolName") or obj.get("name") or "")


def tool_input(obj):
    value = obj.get("tool_input")
    if value is None:
        value = obj.get("toolInput")
    if value is None:
        value = obj.get("input")
    return value if isinstance(value, dict) else {}


def has_memory_search(obj):
    name = tool_name(obj)
    ti = tool_input(obj)
    command = str(ti.get("command") or ti.get("cmd") or "")
    if name == "Bash" and memory_re.search(command):
        return True
    return any(memory_re.search(text) for text in strings(obj))


def numeric_write_or_gist(obj):
    name = tool_name(obj)
    ti = tool_input(obj)
    if name == "Write":
        content = str(ti.get("content") or "")
        return bool(number_unit_re.search(content))
    if name == "Bash":
        command = str(ti.get("command") or ti.get("cmd") or "")
        if re.search(r"\bgh\s+gist\s+edit\b", command):
            return any(number_unit_re.search(text) for text in strings(obj))
    return False


events = [payload]
transcript = payload.get("transcript_path") or payload.get("transcriptPath") or ""
if isinstance(transcript, str) and transcript and os.path.isfile(transcript):
    try:
        with open(transcript, encoding="utf-8") as fh:
            lines = fh.readlines()[-240:]
        for raw in lines:
            try:
                events.append(json.loads(raw))
            except json.JSONDecodeError:
                continue
    except OSError:
        pass

all_objects = [obj for event in events for obj in dicts(event)]
memory_seen = any(has_memory_search(obj) for obj in all_objects)
gist_edit_seen = any(
    tool_name(obj) == "Bash"
    and re.search(r"\bgh\s+gist\s+edit\b", str(tool_input(obj).get("command") or tool_input(obj).get("cmd") or ""))
    for obj in all_objects
)
numeric_output = any(numeric_write_or_gist(obj) for obj in all_objects)
if not numeric_output and gist_edit_seen:
    numeric_output = any(number_unit_re.search(text) for event in events for text in strings(event))
if numeric_output and not memory_seen:
    print(
        "WARN: 数値を含むWrite/gh gist edit出力だが同一セッション内の三層記憶検索(memory_db_query.sh/semantic_search.sh)が未検出。推測値を出す前に記憶DB/セマンティックを確認せよ(cmd_3522)。"
    )
PY
}

detect_numeric_flag_memory_gap() {
  local agent="$1"
  local numeric_flag="$STATE_DIR/shogun_numeric_tool_output_${agent}"
  local memory_flag="$STATE_DIR/shogun_memory_search_seen_${agent}"
  [[ -f "$numeric_flag" ]] || return 0
  [[ -f "$memory_flag" ]] && return 0
  printf 'WARN: 数値を含むWrite/gh gist edit出力フラグあり、同一セッション内の三層記憶検索(memory_db_query.sh/semantic_search.sh)フラグなし。推測値を出す前に記憶DB/セマンティックを確認せよ(cmd_3522)。\n' >&2
}

detect_verification_action_gap() {
  local agent="$1"
  local count_file="$STATE_DIR/shogun_verification_action_count_${agent}"
  local count=0
  if [[ -f "$count_file" ]]; then
    count="$(wc -l < "$count_file" 2>/dev/null | tr -d '[:space:]' || echo 0)"
  fi
  case "$count" in
    ''|*[!0-9]*) count=0 ;;
  esac
  if [[ "$count" -eq 0 ]]; then
    printf 'WARN: 確認行為ゼロ。将軍応答前に三層記憶検索/capture-pane/DB検索/grep/bats等の一次確認を1回以上実行せよ(cmd_3523)。\n' >&2
  fi
  rm -f "$count_file" 2>/dev/null || true
}

# cmd_TRAINING: shogunのみjqでlast_assistant_message抽出→brainwash check。忍者/家老はpayload直接マッチ(jq不要, ~7ms削減)
if [[ "$agent_id" == "shogun" && "$payload" == *'"last_assistant_message"'* ]]; then
  last_assistant_message="$(printf '%s' "$payload" | jq -r '.last_assistant_message // empty' 2>/dev/null || true)"
  printf '%s\n' "$SHOGUN_BRAINWASH_AUDIT" >&2
  detect_verification_action_gap "$agent_id"
  detect_numeric_flag_memory_gap "$agent_id"
  detect_numeric_tool_memory_gap "$payload"
  # LS065: Q6洗脳フラグ確認(前回検出→cmd起票未完了ならWARN継続。認識→行動ギャップ防止)
  _q6_flag="$STATE_DIR/shogun_q6_brainwash_${agent_id}"
  if [[ -f "$_q6_flag" ]]; then
    _karo_yaml="$SCRIPT_DIR/queue/shogun_to_karo.yaml"
    _flag_mtime="$(stat -c %Y "$_q6_flag" 2>/dev/null || echo 0)"
    _karo_mtime=0
    [[ -f "$_karo_yaml" ]] && _karo_mtime="$(stat -c %Y "$_karo_yaml" 2>/dev/null || echo 0)"
    if [[ "$_karo_mtime" -gt "$_flag_mtime" ]]; then
      rm -f "$_q6_flag" 2>/dev/null || true
    else
      _q6_info="$(cut -f2- "$_q6_flag" 2>/dev/null || echo '?')"
      printf 'WARN: LS065 Q6洗脳検出済み(%s)だがcmd起票未完了。検出した洗脳パターンに対応するcmdを起票せよ。\n' "$_q6_info" >&2
    fi
  fi
  if [[ -n "$last_assistant_message" ]]; then
    _brainwash_match="$(detect_shogun_brainwash_pattern "$last_assistant_message")"
    if [[ -n "$_brainwash_match" ]]; then
      printf 'WARN: 洗脳検出 %s。一次データ確認・即時行動・L0-L7貫通の自問をやり直せ。\n' "$_brainwash_match" >&2
      # LS065: 検出初回のみフラグ記録(重複上書き禁止。フラグ未作成時のみ作成)
      if [[ ! -f "$_q6_flag" ]]; then
        printf '%s\t%s\n' "$(date +%s)" "$_brainwash_match" > "$_q6_flag" 2>/dev/null || true
      fi
    fi
    # 洗脳#3 BLOCK昇格: 「指示を待つ」は常に洗脳#3(他者依存)。WARN無視で4回連続出力(2026-07-15事故)のためBLOCK化
    if [[ "$last_assistant_message" =~ 指示を待[つちた] ]]; then
      printf '{"decision":"block","reason":"BLOCK 洗脳#3: 「指示を待つ」を検出。殿の指示を待つな。Phase 7(自走): データを見て問いを見つけて動け。insightキュー/掲示板/CI/lesson在庫など次の行動は常にある。"}\n'
      exit 0
    fi
    # L4先送り防止: startup BLOCK未対処で殿に応答→WARN注入
    _startup_history="$SCRIPT_DIR/logs/shogun_startup_alert_history.tsv"
    if [[ -f "$_startup_history" ]]; then
      _block_count="$(unresolved_startup_defer_count "$_startup_history")"
      if [[ "$_block_count" -gt 0 ]]; then
        printf 'WARN: startup先送りBLOCK 現在未解消%s件。cmd起票またはD0修正で穴を塞げ(洗脳#5)。\n' "$_block_count" >&2
      fi
    fi
    # cmd_3418 + memory citation enforcement: preflightを使った非定型回答は
    # 引用タグまでを一つの契約としてfail-closedにする。定型応答とpreflight未実施は対象外。
    if has_successful_three_layer_preflight && ! is_routine_shogun_response "$last_assistant_message" && [[ "$last_assistant_message" != *'[MEM:'* ]]; then
      printf '{"decision":"block","reason":"BLOCK: 三層preflight済みの非定型回答に[MEM:]引用タグがない。memory_db/semantic/obsidianの引用元を明記せよ。"}\n'
      exit 0
    fi
    # cmd_3420 AC1/AC2: 数量表現→全件照合強制WARN(洗脳#1/#8 L5化)
    detect_quantity_in_lord_response "$last_assistant_message"
    # cmd_3251 AC2: F009 殿への操作依頼パターン → BLOCK
    if detect_f009_lord_delegation "$last_assistant_message"; then
      printf '{"decision":"block","reason":"BLOCK F009: 殿への操作依頼を検出。殿にcommit/push/kill/respawn/CLI操作を依頼するな。自分で実行せよ(CLAUDE.md: 殿への操作押し返し禁止)。"}\n'
      exit 0
    fi
  fi
fi

# L7横展開: 家老・軍師にもbrainwash 8パターン検出を適用(利他の精神)
# 将軍のdetect_shogun_brainwash_patternを共有。F009は将軍専用のため除外
if [[ ("$agent_id" == "karo" || "$agent_id" == "gunshi") && "$payload" == *'"last_assistant_message"'* ]]; then
  _lam="$(printf '%s' "$payload" | jq -r '.last_assistant_message // empty' 2>/dev/null || true)"
  if [[ -n "$_lam" ]]; then
    _bw="$(detect_shogun_brainwash_pattern "$_lam")"
    if [[ -n "$_bw" ]]; then
      printf 'WARN: 洗脳検出 %s。一次データ確認・即時行動・L0-L7貫通の自問をやり直せ。\n' "$_bw" >&2
    fi
  fi
fi

notify_completion() {
  local msg_type="$1"
  local message="$2"
  (
    bash "$SCRIPT_DIR/scripts/inbox_write.sh" karo "$message" "$msg_type" "$agent_id"
  ) >/dev/null 2>&1 &
}

if [[ "$agent_id" != "shogun" && "$agent_id" != "gunshi" && "$payload" == *'"last_assistant_message"'* ]]; then
  # cmd_TRAINING: jq不要。payload全体でパターン直接マッチ(忍者/家老, ~7ms削減)
  shopt -s nocasematch
  if [[ "$payload" =~ $COMPLETE_PATTERN ]]; then
    notify_completion "report_completed" "${agent_id}、タスク完了"
  elif [[ "$payload" =~ $ERROR_PATTERN ]]; then
    notify_completion "error_report" "${agent_id}、エラー停止"
  fi
  shopt -u nocasematch
fi

inbox_file="$SCRIPT_DIR/queue/inbox/${agent_id}.yaml"
if [[ ! -f "$inbox_file" ]]; then
  exit 0
fi

fast_cache=""
if [[ "$payload" != *'"last_assistant_message"'* && "$agent_id" != "karo" && "$agent_id" != "gunshi" && "$agent_id" != "shogun" ]]; then
  _ninja_task_for_cache="$SCRIPT_DIR/queue/tasks/${agent_id}.yaml"
  fast_cache="$STATE_DIR/shogun_stop_check_inbox_fast_${agent_id}"
  if [[ -f "$_ninja_task_for_cache" && -f "$fast_cache" && ! "$inbox_file" -nt "$fast_cache" && ! "$_ninja_task_for_cache" -nt "$fast_cache" ]]; then
    : > "$idle_flag"
    exit 0
  fi
fi

has_unread=false
unread_count=0
unread_count=$(grep -c '^[[:space:]]*read:[[:space:]]*false[[:space:]]*$' "$inbox_file" 2>/dev/null) || unread_count=0

if (( unread_count > 0 )); then
  has_unread=true
fi

if [[ "$has_unread" == "true" ]]; then
  : > "$idle_flag"
  _summary_cache="$STATE_DIR/shogun_stop_check_inbox_summary_${agent_id}"
  if [[ -s "$_summary_cache" && ! "$inbox_file" -nt "$_summary_cache" ]]; then
    IFS= read -r _cached_summary < "$_summary_cache" || _cached_summary=""
    if [[ -n "$_cached_summary" ]]; then
      printf '%s\n' "$_cached_summary"
    fi
  else
    # cmd_2111: python3 2回→1回に統合(サブプロセス削減)
    # cmd_karo_hotfix_speed_stop_check_inbox_20260613: 同一未読inboxの再Stopでは生成済みJSONを再利用する。
    INBOX_FILE="$inbox_file" SUMMARY_LIMIT_ENV="$SUMMARY_LIMIT" SUMMARY_SNIPPET_LEN_ENV="$SUMMARY_SNIPPET_LEN" UNREAD_COUNT="$unread_count" python3 - <<'PY' | tee "$_summary_cache"
import os, json, yaml

inbox_path = os.environ["INBOX_FILE"]
limit = int(os.environ["SUMMARY_LIMIT_ENV"])
snippet_len = int(os.environ["SUMMARY_SNIPPET_LEN_ENV"])
unread_count = int(os.environ["UNREAD_COUNT"])

with open(inbox_path, encoding="utf-8") as f:
    data = yaml.safe_load(f) or {}

CONCLUSION_TYPES = {"bulletin_notify", "review_feedback", "retraction", "analysis_result", "review_result", "report_review_result", "verify_result"}

parts = []
has_conclusion = False
for msg in data.get("messages", []):
    if msg.get("read") is not False:
        continue
    sender = str(msg.get("from", "?"))
    msg_type = str(msg.get("type", "?"))
    content = " ".join(str(msg.get("content", "")).split())
    content = content[:snippet_len]
    parts.append(f"[{sender}/{msg_type}] {content}")
    if msg_type in CONCLUSION_TYPES:
        has_conclusion = True
    if len(parts) >= limit:
        break

result = " | ".join(parts)
if has_conclusion:
    result += " | ★結論を含む通知あり。自分の証拠と突合せよ。矛盾があれば問い返せ。撤回は突合後。"

if result:
    reason_text = f"inbox未読{unread_count}件あり。内容: {result}\n★Read toolで全文読め。mark_readだけするな。各メッセージが今の作業にどう影響するか自問せよ。起動時と同じ態度で(LS048)"
else:
    reason_text = f"inbox未読{unread_count}件あり\n★Read toolで全文読め。mark_readだけするな(LS048)"

print(json.dumps({"decision": "block", "reason": reason_text}, ensure_ascii=False))
PY
  fi
else
  # 全ロール共通: inbox未読0でも掲示板action_required未対処/insights pendingがあれば表示
  _bulletin_file="$SCRIPT_DIR/queue/bulletin_board.yaml"
  _insights_file="$SCRIPT_DIR/queue/insights.yaml"
  _warning_cache="$STATE_DIR/shogun_stop_check_warnings_${agent_id}"
  if [[ -f "$_warning_cache" ]] \
    && { [[ ! -f "$_bulletin_file" ]] || [[ ! "$_bulletin_file" -nt "$_warning_cache" ]]; } \
    && { [[ ! -f "$_insights_file" ]] || [[ ! "$_insights_file" -nt "$_warning_cache" ]]; }; then
    if [[ -s "$_warning_cache" ]]; then
      cat "$_warning_cache" >&2
    fi
  else
    _warning_text=""
    if [[ -f "$_bulletin_file" ]]; then
      _ar_count=$(awk '/action_type:.*action_required/{ar=1} ar && /actioned_by:.*'\'''\''/{count++; ar=0} {if(/^- id:/){ar=0}} END{print count+0}' "$_bulletin_file" 2>/dev/null)
      if [[ "$_ar_count" -gt 0 ]]; then
        _warning_text+="⚠ 掲示板action_required未対処${_ar_count}件。対処してactioned_byを埋めよ"$'\n'
      fi
    fi
    if [[ -f "$_insights_file" ]]; then
      _ins_pending=$(grep -cE 'status:.*pending' "$_insights_file" 2>/dev/null || echo 0)
      if [[ "$_ins_pending" -gt 3 ]]; then
        _warning_text+="⚠ insights pending ${_ins_pending}件（今処理 or wait_reason宣言）"$'\n'
      fi
    fi
    printf '%s' "$_warning_text" > "$_warning_cache" 2>/dev/null || true
    if [[ -n "$_warning_text" ]]; then
      printf '%s' "$_warning_text" >&2
    fi
  fi
  # 家老向け: inbox未読0でもpending workがあれば次アクションを表示(Codex STALL防止)
  if [[ "$agent_id" == "karo" ]]; then
    _pending_actions=()

    # 1. 完了忍者の報告パイプライン(status=done → レビュー/GATE処理が必要)
    for _tf in "$SCRIPT_DIR"/queue/tasks/*.yaml; do
      [[ -f "$_tf" ]] || continue
      _ninja_name="$(basename "$_tf" .yaml)"
      _task_status="$(awk '/^[[:space:]]*status:/{print $2; exit}' "$_tf" 2>/dev/null || true)"
      _task_pcmd="$(awk '/^  parent_cmd:/{print $2; exit}' "$_tf" 2>/dev/null || true)"
      if [[ "$_task_status" == "done" ]]; then
        _pending_actions+=("${_ninja_name}(${_task_pcmd}) status=done → 報告レビュー/GATE処理を進めよ")
      fi
    done

    # 2. 未配備CMD(status=delegated + task未作成。on_hold/shelved/blockedは除外)
    _delegated_cmds="$(awk '/^  cmd_[0-9]+:/{cmd=$1; gsub(/:$/,"",cmd)} cmd && /status:.*(on_hold|shelved|blocked)/{cmd=""} cmd && /status:.*delegated/{print cmd; cmd=""}' "$SCRIPT_DIR/queue/shogun_to_karo.yaml" 2>/dev/null || true)"
    for _dcmd in $_delegated_cmds; do
      _has_task=false
      for _tf2 in "$SCRIPT_DIR"/queue/tasks/*.yaml; do
        if grep -q "parent_cmd:.*${_dcmd}" "$_tf2" 2>/dev/null; then
          _has_task=true
          break
        fi
      done
      if [[ "$_has_task" == "false" ]]; then
        _pending_actions+=("${_dcmd} status=delegated → 忍者配備を進めよ")
      fi
    done

    if (( ${#_pending_actions[@]} > 0 )); then
      _action_text="$(printf '%s; ' "${_pending_actions[@]}")"
      _reason="inbox未読0件だが次アクションあり: ${_action_text%%; }"
      jq -n --arg reason "$_reason" '{"decision":"block","reason":$reason}'
      exit 0
    fi
  fi

  # 軍師向け: inbox未読0 → idle自走リマインド(意志依存排除)
  if [[ "$agent_id" == "gunshi" ]]; then
    _idle_last=""
    [[ -f /tmp/gunshi_idle_last_step ]] && _idle_last=$(< /tmp/gunshi_idle_last_step)
    if [[ -n "$_idle_last" ]]; then
      echo "★ inbox未読0。idle自走Step ${_idle_last}で中断。再開せよ(→Step 8)。止まるな。" >&2
    else
      echo "★ inbox未読0。idle自走プロトコル実行せよ(Step 0→8)。止まるな。" >&2
    fi
  fi

  # 忍者向け: task完了後に勝手な作業を始めるのを防止
  # status=done/completed + inbox未読0 → 待機指示
  if [[ "$agent_id" != "karo" && "$agent_id" != "gunshi" && "$agent_id" != "shogun" ]]; then
    _ninja_task="$SCRIPT_DIR/queue/tasks/${agent_id}.yaml"
    if [[ -f "$_ninja_task" ]]; then
      _ninja_task_done=false
      if grep -qE '^[[:space:]]*status:[[:space:]]*(done|completed)([[:space:]]|$)' "$_ninja_task" 2>/dev/null; then
        _ninja_task_done=true
      fi
      if [[ "$_ninja_task_done" == "true" ]]; then
        : > "$idle_flag"
        _reason="Task completed. Wait for next task assignment from karo. Do NOT start new work."
        jq -n --arg reason "$_reason" '{"decision":"block","reason":$reason}'
        exit 0
      fi
    fi
  fi

  # L4: 家老ALERT未処理検知 — startup gateが設置したpendingフラグをチェック
  if [[ "$agent_id" == "karo" ]]; then
    _alert_pending="$SCRIPT_DIR/queue/gates/karo_alert_pending.txt"
    if [[ -s "$_alert_pending" ]]; then
      _alert_content="$(head -3 "$_alert_pending" 2>/dev/null | tr '\n' '; ')"
      _reason="startup gate ALERT未処理: ${_alert_content}ALERTはバグ。根因調査→修正→commitまで回せ。解消したら rm $_alert_pending"
      jq -n --arg reason "$_reason" '{"decision":"block","reason":$reason}'
      exit 0
    fi
  fi

  : > "$idle_flag"
  if [[ -n "$fast_cache" ]]; then
    : > "$fast_cache"
  fi
fi

# === /clear自発禁止 (殿裁定2026-06-28 LS074) ===
# 将軍が/clearについて考える・判断する・行動する全て禁止。
# autocompact=90%が自動管理する。殿の明示的指示があった時だけ検討。
if [[ "${AGENT_ID:-}" == "shogun" ]]; then
  _stop_text=$(cat 2>/dev/null || true)
  if echo "$_stop_text" | grep -qiE 'clear.prep|shogun-clear-prep|/clear準備|クリア.*準備|CTX.*限界|コンテキスト.*限界'; then
    echo "BLOCK: /clear自発禁止(殿裁定2026-06-28 LS074)。/clearは殿の専権事項。autocompact=90%が自動管理。殿の明示的指示なしに/clearについて考えるな・判断するな・行動するな。" >&2
    exit 2
  fi
fi

exit 0
