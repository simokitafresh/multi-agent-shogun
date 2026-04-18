# inbox_write.sh CoDD Spec (cmd_2080)

- cmd: cmd_2080
- 実施者: saizo
- CoDD Phase到達: Phase 5(before/after計測+spec+実装+検証)
- 作成: 2026-04-18

## 対象

- `scripts/inbox_write.sh`
- lines: 1231

## before計測

- 条件A: isolated write path
  - fixture: `INBOX_WRITE_ROOT_OVERRIDE=<tmp>`
  - command: `bash scripts/inbox_write.sh karo "bench" wake_up saizo bench`
  - 5run: `62, 42, 30, 29, 32 ms`
  - median: `32ms`
- 条件B: live `/mnt/c` write path
  - fixture: `INBOX_WRITE_TEST=1`, target=`testbench_inbox_write`
  - command: `bash scripts/inbox_write.sh testbench_inbox_write "bench" wake_up saizo bench`
  - 5run: `55, 40, 48, 51, 44 ms`
  - median: `48ms`

## ボトルネック

### B1: empty/small inbox append前に `grep` 2本

現状の `inbox_append_message_locked` 系は、empty inbox でも毎回以下を実行していた。

1. `grep -c '^- ' "$inbox_file"`
2. `grep -qx 'messages: \[\]' "$inbox_file"`

局所ベンチ:

- empty inbox 100回:
  - current: `416ms`
  - `read` 先頭1行判定のみ: `5ms`
- non-empty inbox 100回:
  - current: `413ms`
  - `read` + `grep -c` 1本: `147ms`

結論: `messages: []` 判定は bash builtin の `read` で十分。small inbox append では `grep` は1本で足りる。

### B2: `/mnt/c` lockfile名生成で `cksum` 1回

`lock_path()` は `/mnt/c/*|/mnt/d/*` で毎回 `cksum` をforkしていた。

局所ベンチ:

- current `cksum` 100回: `333ms`
- pure bash sanitize 100回: `6ms`

結論: `/mnt/c` 実運用経路では lockfile 名生成だけで `~3.3ms/call` を消費していた。

## 実装

### R1: empty inbox判定を builtin 化

追加:

```bash
inbox_is_empty_file() {
    local inbox_file="$1"
    [[ -f "$inbox_file" ]] || return 0

    local first_line=""
    IFS= read -r first_line < "$inbox_file" || first_line=""
    [[ "$first_line" == "messages: []" ]]
}
```

変更:

- empty inbox なら即 `messages:\n%s` で書く
- small inbox append (`<50`) は `grep -c` 1本だけで判定し、そのまま `>>` append
- `grep -qx 'messages: []'` を排除

### R2: `/mnt/c` lock path を pure bash 化

変更前:

```bash
read -r _cksum _ < <(printf '%s' "$1" | cksum)
printf '/tmp/shogun_lock_%s.lock' "$_cksum"
```

変更後:

```bash
local sanitized="${1//[^[:alnum:]._-]/_}"
if ((${#sanitized} > 180)); then
    sanitized="${sanitized:0:120}_${sanitized: -40}_${#1}"
fi
printf '/tmp/shogun_lock_%s.lock' "$sanitized"
```

意図:

- forkなしで lockfile 名を生成
- 長すぎるパスだけ truncate して `/tmp` の filename 長制限を回避

## after計測

- 条件A: isolated write path
  - 5run: `20, 26, 31, 25, 24 ms`
  - median: `25ms`
- 条件B: live `/mnt/c` write path
  - 5run: `35, 38, 40, 32, 27 ms`
  - median: `35ms`

## 結果

- isolated write path: `32ms → 25ms` (`-21.9%`)
- live `/mnt/c` write path: `48ms → 35ms` (`-27.1%`)

既存の write semantics は不変。改善対象は empty/small inbox append の固定費と `/mnt/c` lock path 生成のみ。

## 検証

- `bash -n scripts/inbox_write.sh`
- `bats tests/unit/test_inbox_write.bats` (`22/22 PASS`)
