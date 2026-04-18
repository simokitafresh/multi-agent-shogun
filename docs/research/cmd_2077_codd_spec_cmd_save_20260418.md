# CoDD Spec: cmd_save.sh 正規CoDD再改善 (cmd_2077)

## Meta
- date: 2026-04-18
- author: tobisaru
- parent_cmd: cmd_2077
- target: `scripts/cmd_save.sh` (2202行)
- predecessor: `docs/research/codd_spec_cmd_save_20260416.md` (前回spec省略版: 1.83s → 1.06s warm)

---

## Before 計測 (warm path median 5回, /mnt/c/tools/multi-agent-shogun)

| パス | 測定値 (5回) | median |
|------|-------------|--------|
| warm (cmd_2077, 全チェック実行) | 1026,833,894,913,921ms | **913ms** |

> L496教訓確認: 実運用ディレクトリ(/mnt/c/)はWSL2 NTFSのため/tmp比で2-4倍遅い。
> 前回台帳値321ms(warm)は条件差あり。本計測を正としてbefore基準とする。

---

## ボトルネック分析

### プロファイリング手法

1. `PS4='TRACE:$(date +%s%3N):${LINENO}: ' bash -x scripts/cmd_save.sh 2077` でトレース取得
2. `early exit` テスト: スクリプトの特定行でexit 0を挿入し区間時間を測定
3. 独立計測: 各ボトルネック候補をシェルから直接実行

### Top 3 ボトルネック

| 順位 | 箇所 | 行番号 | 計測コスト | 根本原因 |
|------|------|--------|-----------|---------|
| 1 | `git diff-files` (Check 5) | L831 | **300-500ms** | WSL2 NTFS上でgit diff-filesが全tracked filesをstat()比較。NTFSのstat()は高コスト |
| 2 | `check_param_space_against_results` python3 | L1566 | **71ms** | python3プロセス起動(~20ms) + `glob.glob("outputs/analysis/**/*.yaml")` (infra project: ~50ms) |
| 3 | `load_cmd_block_cache` の`$(trim_inline_yaml_scalar)` subshells | L114, L122 | **25-30ms** | ループ内で21回 `$(trim_inline_yaml_scalar)` subshellを生成。関数内容は純bash演算なので不要 |

### 計測詳細

```
Before median: 913ms
│
├─ git diff-files のみ独立計測: 181-592ms (median ~400ms)
│   git status --porcelain=v2 --no-optional-locks 代替: 23ms
│   → 節約: ~370ms
│
├─ check_param_space_against_results 独立計測: 71ms
│   python3起動 + glob.glob(PROJECT_DIR/outputs/analysis/) → 0件でexit
│   → bash早期return追加で: ~2ms
│   → 節約: ~69ms
│
└─ load_cmd_block_cache trim subshells:
    trim_inline_yaml_scalar = ltrim + rtrim + quote-strip (pure bash)
    $(trim_inline_yaml_scalar) 21回 × ~1ms/subshell fork = ~25ms
    → inline化で: ~3ms
    → 節約: ~22ms
```

---

## 改善設計

### Fix #1: `git diff-files` → `git status --porcelain=v2 --no-optional-locks`

**Before:**
```bash
UNCOMMITTED=$(git -C "$PROJECT_DIR" diff-files --name-only -- scripts/ CLAUDE.md instructions/ config/ 2>/dev/null || true)
```

**After:**
```bash
UNCOMMITTED=$(git -C "$PROJECT_DIR" status --porcelain=v2 --no-optional-locks \
    -- scripts/ CLAUDE.md instructions/ config/ 2>/dev/null \
    | awk '!/^[?!#]/{sub(/.*[[:space:]]/,""); print}' || true)
```

**理由**:
- `git diff-files`: index↔workingtree比較のため全tracked filesをstat()。WSL2 NTFSで遅い
- `git status --porcelain=v2 --no-optional-locks`: git自身のFSMONITOR/mtime cacheを活用。検出結果は同等(M/A/D)
- `awk '!/^[?!#]/'`: untracked(?)/ignored(!)/branch info(#)を除去してファイル名のみ抽出

**教訓参照**: L492 - "git status --porcelain=v2 -z パイプ awk で代替"

### Fix #2: `check_param_space_against_results` bash早期リターン追加

**Before:**
```bash
check_param_space_against_results() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0
    ...
    CMD_SECTION="..." PROJECT_ROOT_FOR_CMD="..." python3 - <<'PY'
    ...
```

**After:** CMD_SECTIONが空、またはproject=infraの場合にpython3を呼ばずreturn 0
```bash
check_param_space_against_results() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0
    ...
    [[ -z "$CMD_SECTION" ]] && return 0  # 既存チェック
    # NEW: infra project はGS結果YAMLなし → python3不要
    [[ "$PROJECT_ID" == "infra" || -z "${PROJECT_ID:-}" ]] && return 0
    # NEW: results YAML候補が存在しなければpython3不要
    if ! find "$PROJECT_ROOT_FOR_CMD/outputs/analysis" -name "*.yaml" -maxdepth 3 2>/dev/null | grep -q .; then
        return 0
    fi
    CMD_SECTION="..." PROJECT_ROOT_FOR_CMD="..." python3 - <<'PY'
```

**理由**: cmd_2077 (project=infra) の場合python3は`sys.exit(0)`するだけだが20+ms消費。bash早期リターンで回避。

### Fix #3: `load_cmd_block_cache` の`$(trim_inline_yaml_scalar)` subshell除去

**Before:**
```bash
CMD_BLOCK_CACHE["$key"]="$(trim_inline_yaml_scalar "$value")"
```

**After:**
```bash
_tcv="$value"
_tcv="${_tcv#"${_tcv%%[![:space:]]*}"}"
_tcv="${_tcv%"${_tcv##*[![:space:]]}"}"
if [[ "$_tcv" == \"*\" && "$_tcv" == *\" && ${#_tcv} -ge 2 ]]; then
    _tcv="${_tcv:1:${#_tcv}-2}"
elif [[ "$_tcv" == \'*\' && "$_tcv" == *\' && ${#_tcv} -ge 2 ]]; then
    _tcv="${_tcv:1:${#_tcv}-2}"
    _tcv="${_tcv//\'\'/\'}"
fi
CMD_BLOCK_CACHE["$key"]="$_tcv"
```

**理由**: `trim_inline_yaml_scalar`は純粋なbash文字列演算。subshellを排除しインライン化することで、21回のforkコスト(~25ms)を削減。

---

## 期待改善

| 修正 | 期待節約 |
|------|---------|
| Fix #1 (git) | ~370ms |
| Fix #2 (python3 early return) | ~69ms |
| Fix #3 (trim subshells) | ~22ms |
| **合計** | **~461ms** |
| **期待After** | 913 - 461 ≈ **~450ms** (目標200ms) |

> 注: WSL2 NTFS環境の計測変動が大きい(±200ms)。実測後に評価。
> 目標200ms達成のため、Fix #1-3以外の追加改善が必要な場合はAC2/AC3でrevert判断を行う。

---

## テスト計画 (AC4)

```bash
# 既存batsテスト全PASS確認
bats tests/test_cmd_save_ac_paths.bats \
     tests/test_cmd_save_q7_branch.bats \
     tests/test_cmd_save_content_dup.bats \
     tests/unit/test_cmd_save*.bats 2>&1 | tail -20
```

テスト項目:
- Check 1: cmdブロック存在確認
- Check 1.5: 委任済みBLOCK
- Check 2: アーカイブ重複
- Check 3: quality_gate検査
- Check 5: uncommitted changes検出 (git status代替で同等動作確認)
- Check 12: コンテンツ重複
- Check 14: パラメータ空間縮小検出 (infra skipが正常)
- Check 20: assumptions検証
