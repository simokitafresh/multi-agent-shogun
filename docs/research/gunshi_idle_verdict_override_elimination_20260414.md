# verdict_override構造的排除 — なぜなぜ7回

殿指示「今回の気づきから家老をレベルアップさせるアイデアは？なぜなぜ7回」

## 結論

verdict_override 8件中5件(62.5%)がcommit check起因。
**根因: cmdの「commit禁止」制約がdeploy_task.shのbc template生成に伝達されない。**
構造化フィールド `no_commit: true` をcmd_save.shに追加し、deploy_task.shがcommit checkをwaiveすれば、家老の手動override負担が62.5%削減される。

## なぜなぜ7回

1. **なぜ家老がverdict_overrideする？** → gate BLOCK(verdict=PASS + bc commit:no = 不整合)だが成果物正常
2. **なぜverdict↔bc不整合？** → cmd制約(commit禁止/研究出力/gitignore)で忍者がcommit:noにする
3. **なぜcommit:noになる？** → deploy_task.shが全cmdに一律commit check注入。制約無視
4. **なぜ全cmdに一律？** → bc template生成にcmd制約参照の分岐がない
5. **なぜ参照しない？** → cmd制約は自然言語(「★commit禁止」)。構造化されていない
6. **なぜ構造化されていない？** → cmd_save.shのquality_gate(q1-q9)にcommit有無のメタ情報がない
7. **根因: cmd設計時にcommit有無が構造化されていない → deploy_task.shが検出不能 → 一律注入 → 毎回override = 負の複利**

## verdict_override 8件の根因分類

| パターン | 件数 | 対策状況 |
|---------|------|---------|
| A) commit check一律注入 | 5(62.5%) | **本提案で解決** |
| B) AC設計問題(推奨/必須混在, 進行中月) | 2(25%) | GP-173, GP-184で対処済み |
| C) データ時差(GS作成日vs本番更新日) | 1(12.5%) | GP-184で対処済み |

### A) commit check起因 5件の内訳

| cmd | 状況 | 根因 |
|-----|------|------|
| cmd_root_dashboard_auto | gitignore対象ファイル | 既にauto-no分岐あり(L1167)が条件漏れ |
| cmd_1821 | 研究cmd output | GP-183で対処済み |
| cmd_1884 | scope外未commitファイル | 共有WT構造問題 |
| cmd_1897 | commit禁止cmd | **未対処** |
| cmd_karo_gp110 | commit禁止補正 | **未対処** |

## 解決策: `no_commit` フィールド

### 層1: cmd_save.sh — 構造化フィールド追加

cmd本文に「commit禁止」「登録のみ」「INSERT Only」等のキーワードがあれば `no_commit: true` を自動付与。

```bash
# cmd_save.sh Check N: commit禁止キーワード検出
if echo "$CMD_BLOCK_NC" | grep -qiE 'commit.*禁止|commit一切禁止|登録.?のみ|INSERT.?only|commit不要'; then
    echo "INFO: commit禁止キーワード検出 → no_commit: true 自動付与"
    # shogun_to_karo.yamlにno_commit: trueを追記
fi
```

### 層2: deploy_task.sh — commit check waive

```bash
# deploy_task.sh L1157付近: no_commit検出時にcommit checkをwaive
local _no_commit
_no_commit=$(FIELD_GET_NO_LOG=1 field_get "$STK" "$CMD_ID" "no_commit" 2>/dev/null)
if [ "$_no_commit" = "true" ]; then
    _commit_bc='  commit:
  - check: "N/A(cmd制約: commit禁止)"
    result: "yes"  # commit禁止cmdのため自動waive'
    log "binary_checks: commit check auto-waived (no_commit=true)"
fi
```

### 効果予測

| 指標 | Before | After |
|------|--------|-------|
| verdict_override/全WA | 8/75(10.7%) | 3/75(4.0%) |
| commit起因override | 5件 | 0件 |
| 家老手動override時間 | 5回×2-3分=10-15分 | 0分 |
| 10回繰返し | 50-75分の無駄 | 0分 |

### 防御レベル

- 層1(cmd_save.sh): Level 3(事前強制auto-gen) — キーワード検出→自動付与
- 層2(deploy_task.sh): Level 4(フロー内埋込) — 配備時にcommit checkをwaive

### 既存分岐との整合

deploy_task.sh L1157-1207に既にある分岐:
- scout/recon → commit check skip ✅
- gitignore対象 → auto no ✅
- scout_exempt + target_path未設定 → auto no ✅
- **no_commit=true → auto waive** ← 新規追加

同じパターンの拡張。新しい概念導入なし。

## 実装優先度

- 自力実行可能: **NO**(cmd_save.sh + deploy_task.sh = インフラ共有スクリプト。cmd化必要)
- 家老への提案: GP-190として送信
- 防御レベル: Level 3+4
- 複利の問い: 10回繰返したら→10回×0分=0分(現状10回×10分=100分)。**正の複利**

作成: 2026-04-14T09:15:00+09:00
