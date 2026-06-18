#!/usr/bin/env bash
# semantic_causal_traverse.sh — 因果グラフBFSトラバーサル
# cmd_3439: Phase 3 パルス伝達装置
#
# Usage:
#   bash scripts/semantic_causal_traverse.sh --cmd-id CMD_ID [--depth N] [--format json|text]
#   bash scripts/semantic_causal_traverse.sh --concepts "c1,c2" [--depth N] [--format json|text]
#
# Options:
#   --cmd-id CMD_ID       CMD_IDから起点conceptを自動推論
#   --concepts "c1,c2"    起点concept_idリスト（カンマ区切り）
#   --depth N             BFS深さ（デフォルト: 3）
#   --format json|text    出力形式（デフォルト: text）
#   --index PATH          セマンティックインデックスパス（デフォルト: docs/semantic-index/index.md）
#
# Exit 0: 正常完了
# Exit 1: エラー（インデックス不在等）

set -euo pipefail

_self="${BASH_SOURCE[0]}"
[[ "$_self" != /* ]] && _self="$PWD/$_self"
SCRIPT_DIR="${_self%/scripts/semantic_causal_traverse.sh}"

# デフォルト値
CMD_ID=""
CONCEPTS=""
DEPTH=3
FORMAT="text"
INDEX_PATH="$SCRIPT_DIR/docs/semantic-index/index.md"

# 引数パース
while [[ $# -gt 0 ]]; do
    case "$1" in
        --cmd-id)   CMD_ID="$2"; shift 2 ;;
        --concepts) CONCEPTS="$2"; shift 2 ;;
        --depth)    DEPTH="$2"; shift 2 ;;
        --format)   FORMAT="$2"; shift 2 ;;
        --index)    INDEX_PATH="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [ ! -f "$INDEX_PATH" ]; then
    echo "ERROR: semantic index not found: $INDEX_PATH" >&2
    exit 1
fi

if [ -z "$CMD_ID" ] && [ -z "$CONCEPTS" ]; then
    echo "ERROR: --cmd-id or --concepts required" >&2
    exit 1
fi

# Python3でBFSトラバース実行
python3 - "$INDEX_PATH" "$CMD_ID" "$CONCEPTS" "$DEPTH" "$FORMAT" <<'PY_EOF'
import sys
import re
import json
from collections import deque

index_path = sys.argv[1]
cmd_id = sys.argv[2]
concepts_arg = sys.argv[3]
max_depth = int(sys.argv[4])
output_format = sys.argv[5]

# ─── インデックス解析 ───
def parse_related_concepts_cell(value):
    related = []
    for raw in str(value or "").split(","):
        item = raw.strip().strip("`")
        if not item:
            continue
        relation_type = "related"
        concept_id = item
        m = re.match(r"^([A-Za-z0-9_-]+)\s*\((.*?)\)$", item)
        if m:
            concept_id = m.group(1).strip()
            for attr in m.group(2).split(";"):
                k, sep, v = attr.partition("=")
                if sep and k.strip() == "relation_type" and v.strip():
                    relation_type = v.strip()
        related.append({"id": concept_id, "relation_type": relation_type})
    return related

def parse_index(path):
    text = open(path, encoding="utf-8").read()
    sections = re.split(r"(?m)^##\s+", text)
    concepts = []
    for raw in sections[1:]:
        lines = raw.splitlines()
        if not lines:
            continue
        heading = lines[0].strip()
        if " — " in heading:
            cid, clabel = heading.split(" — ", 1)
        else:
            cid, clabel = heading, ""
        attrs = {}
        resources = []
        for line in lines[1:]:
            s = line.strip()
            if not s.startswith("|") or not s.endswith("|"):
                continue
            parts = s.split("|")
            if len(parts) < 4:
                continue
            left = parts[1].strip()
            right = "|".join(parts[2:-1]).strip()
            if left in {"属性", "------", "種別"} or right in {"値", "----------"}:
                continue
            if left in {"id", "label", "aliases", "related_concepts"}:
                attrs[left] = right
            elif right:
                resources.append((left, right))
        concepts.append({
            "id": attrs.get("id") or cid.strip(),
            "label": attrs.get("label") or clabel,
            "aliases": [x.strip() for x in attrs.get("aliases", "").split(",") if x.strip()],
            "related_concepts": parse_related_concepts_cell(attrs.get("related_concepts", "")),
            "resources": resources,
        })
    return concepts

concepts = parse_index(index_path)

# ─── グラフ構築 ───
# ノードマップ: concept_id -> concept_dict
node_map = {c["id"]: c for c in concepts}

# エッジ構築（related_concepts: 無向、混同注意は除外）
graph = {}  # concept_id -> [(neighbor_id, edge_type)]
for c in concepts:
    cid = c["id"]
    if cid not in graph:
        graph[cid] = []
    for rc in c["related_concepts"]:
        neighbor = rc["id"]
        etype = rc.get("relation_type", "related")
        if etype == "混同注意":
            continue  # 混同注意は伝播対象外
        graph[cid].append((neighbor, etype))
        # 無向エッジ: 逆方向も追加
        if neighbor not in graph:
            graph[neighbor] = []
        graph[neighbor].append((cid, etype))

# ─── 起点concept決定 ───
start_concepts = []

if concepts_arg:
    for c in concepts_arg.split(","):
        c = c.strip()
        if c:
            start_concepts.append(c)

if cmd_id:
    # CMD_IDが含まれる概念ブロックを特定
    # "| cmd | `cmd_XXX`" または "| causal | `cmd_XXX`" で検索
    cmd_pattern = re.compile(r"`" + re.escape(cmd_id) + r"`")
    for c in concepts:
        for (rtype, rval) in c["resources"]:
            if rtype in ("cmd", "causal") and cmd_pattern.search(rval):
                if c["id"] not in start_concepts:
                    start_concepts.append(c["id"])
                break

if not start_concepts:
    if output_format == "json":
        print(json.dumps({"cmd_id": cmd_id, "start_concepts": [], "affected_nodes": [], "depth": max_depth}))
    else:
        print(f"[causal_traverse] 起点concept未発見 (cmd_id={cmd_id})")
    sys.exit(0)

# ─── BFSトラバース ───
visited = {}  # concept_id -> {depth, via, edge_type}
queue = deque()

for sc in start_concepts:
    if sc not in visited:
        visited[sc] = {"depth": 0, "via": None, "edge_type": "start"}
        queue.append((sc, 0))

affected = []
while queue:
    node, depth = queue.popleft()
    if depth >= max_depth:
        continue
    for (neighbor, etype) in graph.get(node, []):
        if neighbor not in visited:
            visited[neighbor] = {"depth": depth + 1, "via": node, "edge_type": etype}
            queue.append((neighbor, depth + 1))
            neighbor_info = node_map.get(neighbor)
            # 影響ノードの検証スクリプト候補を抽出（FM注意: 不在時はtest_scripts=[]でfallback）
            test_scripts = []
            if neighbor_info:
                for (rtype, rval) in neighbor_info.get("resources", []):
                    if rtype == "file":
                        # バッククォートで囲まれたパスを抽出
                        fp_m = re.search(r"`([^`]+)`", rval)
                        fp = fp_m.group(1) if fp_m else rval
                        if "tests/" in fp or fp.endswith(".bats") or fp.endswith("_test.sh"):
                            test_scripts.append(fp)
            affected.append({
                "concept_id": neighbor,
                "label": neighbor_info["label"] if neighbor_info else "",
                "declared": neighbor in node_map,
                "depth": depth + 1,
                "via": node,
                "edge_type": etype,
                "test_scripts": test_scripts,  # [] = 検証スクリプト不在(skip/warn対象)
            })

# ─── 出力 ───
if output_format == "json":
    no_test = sum(1 for n in affected if not n["test_scripts"])
    result = {
        "cmd_id": cmd_id,
        "start_concepts": start_concepts,
        "affected_nodes": affected,
        "depth": max_depth,
        "total": len(affected),
        "no_test_scripts_count": no_test,  # 検証スクリプト不在ノード数
    }
    print(json.dumps(result, ensure_ascii=False))
else:
    if not affected:
        print(f"[causal_traverse] 影響ノードなし (start={','.join(start_concepts)}, depth={max_depth})")
        sys.exit(0)
    print(f"[causal_traverse] 起点: {','.join(start_concepts)} | 深さ{max_depth} | 影響: {len(affected)}ノード")
    for node in affected:
        declared_marker = "" if node["declared"] else " [浮遊]"
        label = f" ({node['label']})" if node["label"] else ""
        print(f"  D{node['depth']} {node['concept_id']}{label}{declared_marker} ← {node['via']} [{node['edge_type']}]")

PY_EOF
